// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Streaming PDF writer for the DjVu → PDF converter.
//
// Ported from the reference writer in djvu-rs (`src/pdf/writer.rs`,
// `src/pdf/mask.rs`, `src/pdf/page.rs`, MIT,
// https://github.com/matyushkin/djvu-rs) with the same object layout and
// stream encodings:
//
// - the PDF is streamed to a [PdfByteSink] as objects are produced
//   ([DjvuPdfWriter]) and only the xref bookkeeping is retained, so a
//   conversion never buffers the whole document;
// - object ids can be pre-allocated ([DjvuPdfWriter.reserveId]) and bodies
//   written later in any order, which the converter needs for internal
//   `#page_N` link destinations and outline entries that reference page
//   objects;
// - 1-bit foreground masks are FlateDecode ImageMask stencils
//   (`/Decode [1 0]`, bit 1 = paint in the current fill colour), matching
//   the packed [DjvuBitmap] layout byte for byte;
// - colour rasters are FlateDecode or baseline JPEG (DCTDecode), whichever
//   body is smaller for detailed content — and always FlateDecode for
//   near-flat content, where JPEG's per-block overhead loses badly;
// - strings that are not pure ASCII become UTF-16BE hex strings
//   (`<FEFF...>`) so outline titles survive round-tripping.

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:saber/data/document_conversion/djvu/djvu_bitmap.dart';

/// JPEG quality used for colour rasters unless a caller overrides it.
const kDefaultJpegQuality = 80;

/// Raw raster size below which [makeRgbImageBody] and [makeGrayImageBody]
/// never try JPEG.
///
/// Below this the DCT tables and headers dominate, so the extra encode could
/// only cost time: a tiny raster's FlateDecode stream is small already.
const kRasterMinAdaptiveJpegBytes = 16 * 1024;

/// FlateDecode-output-to-raw ratio at or above which a raster counts as
/// detailed enough that JPEG may beat FlateDecode.
///
/// Near-flat rasters (blank pages, sparse text) deflate to a small fraction
/// of their raw size where JPEG can only lose — measured 0.2% FlateDecode vs
/// ~10× larger JPEG on sparse-text pages — while photographic and composited
/// rasters (IW44 backgrounds, dithered scans) stay well above this bound.
const kRasterJpegFlateRatio = 0.05;

/// A synchronous byte sink for [DjvuPdfWriter].
///
/// Matches `RandomAccessFile.writeFromSync`, so a conversion running in an
/// isolate can stream straight to a file. The sink receives byte chunks in
/// PDF order and must copy what it keeps; chunks are not retained by the
/// writer and may share storage with rebuilt buffers.
typedef PdfByteSink = void Function(List<int> bytes);

/// A streaming writer for the DjVu → PDF converter (PDF 1.4).
///
/// Object bodies are written to the sink as they are added and only their
/// `(id, byte offset)` bookkeeping is retained, so peak memory stays O(1
/// page) instead of O(document).
///
/// Object ids may be pre-allocated with [reserveId] and their bodies written
/// later in any order — the converter needs this to reference page objects
/// from annotations and the outline before the pages themselves are emitted.
/// The caller is responsible for writing a catalog object with [rootId]
/// (object 1 by convention) and for calling [finish] exactly once.
///
/// Example:
///
/// ```dart
/// final builder = BytesBuilder(copy: false);
/// final pdf = DjvuPdfWriter(builder.add);
/// final pagesId = pdf.reserveId();
/// final pageIds = [for (var i = 0; i < pageCount; i++) pdf.reserveId()];
/// // ... emit each page with pdf.writeObject(pageIds[i], ...) ...
/// pdf.writeObject(pagesId, utf8.encode('<< /Type /Pages /Kids [...] /Count $pageCount >>'));
/// pdf.writeObject(1, utf8.encode('<< /Type /Catalog /Pages $pagesId 0 R >>'));
/// pdf.finish();
/// ```
class DjvuPdfWriter {
  /// Creates the writer and emits the PDF header.
  DjvuPdfWriter(this._sink) {
    writeAll(_header);
  }

  static final _header = Uint8List.fromList([
    0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x34, 0x0a, // %PDF-1.4\n
    0x25, 0xe2, 0xe3, 0xcf, 0xd3, 0x0a, // binary comment line
  ]);

  final PdfByteSink _sink;

  /// Object ids in the order their bodies were written.
  final List<int> _offsetIds = [];

  /// Byte offset of the corresponding object body in [_offsetIds].
  final List<int> _offsetOffsets = [];

  final Set<int> _writtenIds = {};

  /// Bytes written so far (= the next object's offset).
  var _written = 0;

  var _nextId = 1;
  var _finished = false;

  /// Total bytes written so far.
  int get bytesWritten => _written;

  /// Reserves the next object id.
  ///
  /// The body does not have to follow immediately: any id reserved this way
  /// can be written at any later point with [writeObject] or
  /// [writeStreamObject].
  int reserveId() {
    if (_finished) throw StateError('writer already finished');
    return _nextId++;
  }

  /// Writes raw bytes to the sink. Empty writes are ignored.
  void writeAll(List<int> bytes) {
    if (bytes.isEmpty) return;
    _sink(bytes);
    _written += bytes.length;
  }

  /// Writes [text], which must be Latin-1 (all generated syntax is ASCII).
  void writeAscii(String text) {
    final length = text.length;
    if (length == 0) return;
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      final unit = text.codeUnitAt(i);
      assert(unit <= 0xff, 'writeAscii called with non-Latin-1 text');
      bytes[i] = unit;
    }
    writeAll(bytes);
  }

  /// Writes an object with a pre-allocated [id] (see [reserveId]).
  void writeObject(int id, List<int> body) {
    _startObject(id);
    writeAll(body);
    writeAscii('\nendobj\n');
  }

  /// Allocates an id and writes an object; returns the new id.
  int addObject(List<int> body) {
    final id = reserveId();
    writeObject(id, body);
    return id;
  }

  /// Writes a stream object with a pre-allocated [id].
  ///
  /// The body is `<< /Length N[dictExtra] >>\nstream\n[data]\nendstream`;
  /// [dictExtra] entries start with a space, e.g.
  /// `' /Type /XObject /Subtype /Image ...'`, and the filter entry goes
  /// first (matching the reference writer).
  void writeStreamObject(int id, String dictExtra, List<int> data) {
    _startObject(id);
    writeAscii('<< /Length ${data.length}$dictExtra >>\nstream\n');
    writeAll(data);
    writeAscii('\nendstream\nendobj\n');
  }

  /// Deflates [data] and writes it as a FlateDecode stream object.
  ///
  /// Returns the new object id.
  int addFlateStream(String dictExtra, List<int> data) {
    final id = reserveId();
    writeFlateStream(id, dictExtra, data);
    return id;
  }

  /// Writes a FlateDecode stream with a pre-allocated [id].
  void writeFlateStream(int id, String dictExtra, List<int> data) {
    writeStreamObject(id, ' /Filter /FlateDecode$dictExtra', _deflate(data));
  }

  /// Writes [jpeg] bytes unchanged as a DCTDecode stream object.
  ///
  /// Returns the new object id.
  int addDctStream(String dictExtra, List<int> jpeg) {
    final id = reserveId();
    writeDctStream(id, dictExtra, jpeg);
    return id;
  }

  /// Writes a DCTDecode stream with a pre-allocated [id].
  void writeDctStream(int id, String dictExtra, List<int> jpeg) {
    writeStreamObject(id, ' /Filter /DCTDecode$dictExtra', jpeg);
  }

  /// Writes the cross-reference table, trailer and `%%EOF`.
  ///
  /// [rootId] must be the object id of the document catalog; it defaults to
  /// the conventional object 1. Calling this more than once throws.
  void finish({int rootId = 1}) {
    if (_finished) throw StateError('finish() called twice');
    _finished = true;
    if (rootId < 1 || !_writtenIds.contains(rootId)) {
      throw StateError('root object $rootId was not written');
    }

    var maxId = 0;
    for (final id in _offsetIds) {
      if (id > maxId) maxId = id;
    }
    final offsets = List<int>.filled(maxId + 1, -1);
    for (var i = 0; i < _offsetIds.length; i++) {
      final id = _offsetIds[i];
      if (id <= maxId) offsets[id] = _offsetOffsets[i];
    }

    final xrefOffset = _written;
    final tail = StringBuffer('xref\n0 ${maxId + 1}\n0000000000 65535 f \n');
    for (var id = 1; id <= maxId; id++) {
      final offset = offsets[id];
      if (offset < 0) {
        tail.write('0000000000 65535 f \n');
      } else {
        tail.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
      }
    }
    tail.write(
      'trailer\n<< /Size ${maxId + 1} /Root $rootId 0 R >>\n'
      'startxref\n$xrefOffset\n%%EOF\n',
    );
    writeAscii(tail.toString());
  }

  /// Validates [id] and opens its object body, recording the byte offset.
  void _startObject(int id) {
    if (_finished) throw StateError('writer already finished');
    if (id < 1 || id >= _nextId) {
      throw ArgumentError.value(id, 'id', 'not reserved with reserveId()');
    }
    if (!_writtenIds.add(id)) {
      throw ArgumentError.value(id, 'id', 'object already written');
    }
    _offsetIds.add(id);
    _offsetOffsets.add(_written);
    writeAscii('$id 0 obj\n');
  }
}

/// Compresses [data] with zlib level 6 (the reference writer's setting).
List<int> _deflate(List<int> data) => ZLibCodec(level: 6).encode(data);

/// Builds a stream object body `<< /Length N[dictExtra] >>\nstream\n...\nendstream`.
Uint8List makePdfStream(String dictExtra, List<int> data) {
  final prefix = _latin1('<< /Length ${data.length}$dictExtra >>\nstream\n');
  final suffix = _latin1('\nendstream');
  final out = Uint8List(prefix.length + data.length + suffix.length);
  out.setRange(0, prefix.length, prefix);
  out.setRange(prefix.length, prefix.length + data.length, data);
  out.setRange(prefix.length + data.length, out.length, suffix);
  return out;
}

/// Builds a FlateDecode stream object body from [data].
Uint8List makeFlateStream(String dictExtra, List<int> data) =>
    makePdfStream(' /Filter /FlateDecode$dictExtra', _deflate(data));

/// Builds a DCTDecode stream object body from unchanged [jpeg] bytes.
Uint8List makeDctStream(String dictExtra, List<int> jpeg) =>
    makePdfStream(' /Filter /DCTDecode$dictExtra', jpeg);

/// Builds an ImageMask XObject body from a packed 1-bit [bitmap].
///
/// [DjvuBitmap] data is already packed 1-bit MSB first, which is the sample
/// layout PDF expects for an `/ImageMask` with `/Decode [1 0]`
/// (1 = black = marked). The mask is always FlateDecode of that raw raster.
Uint8List makeMaskBody(DjvuBitmap bitmap) {
  final dict =
      ' /Type /XObject /Subtype /Image'
      ' /Width ${bitmap.width} /Height ${bitmap.height}'
      ' /ImageMask true /BitsPerComponent 1 /Decode [1 0]';
  return makeFlateStream(dict, bitmap.data);
}

/// Builds a colour image XObject body from packed RGB bytes (3 per pixel).
///
/// With [jpegQuality] `null` the raster is always FlateDecode. Otherwise the
/// FlateDecode candidate is always computed, and when [adaptive] is set a
/// baseline JPEG (DCTDecode) candidate is tried for detailed rasters — see
/// [kRasterMinAdaptiveJpegBytes] and [kRasterJpegFlateRatio] — with the
/// smaller body winning. With `adaptive: false` the JPEG is always used
/// (falling back to FlateDecode when the encoder refuses the dimensions),
/// matching the reference writer's `jpeg_quality`/`adaptive_raster` options.
Uint8List makeRgbImageBody(
  Uint8List rgb,
  int width,
  int height, {
  int? jpegQuality = kDefaultJpegQuality,
  bool adaptive = true,
}) => makeRgbImageBodyWithExtra(rgb, width, height, '', jpegQuality: jpegQuality, adaptive: adaptive);

/// Like [makeRgbImageBody], with [dictExtra] appended after the base image
/// entries — used for masked foreground images (`/Mask n 0 R`, whose object id
/// is only known at emit time).
Uint8List makeRgbImageBodyWithExtra(
  Uint8List rgb,
  int width,
  int height,
  String dictExtra, {
  int? jpegQuality = kDefaultJpegQuality,
  bool adaptive = true,
}) {
  final dict =
      ' /Type /XObject /Subtype /Image'
      ' /Width $width /Height $height'
      ' /ColorSpace /DeviceRGB /BitsPerComponent 8$dictExtra';
  final flate = makeFlateStream(dict, rgb);
  if (jpegQuality == null) return flate;
  if (adaptive && !_shouldTryJpeg(rgb.length, flate.length)) return flate;
  final jpeg = encodeRgbJpeg(rgb, width, height, jpegQuality);
  if (jpeg == null) return flate;
  final dct = makeDctStream(dict, jpeg);
  if (!adaptive) return dct;
  return flate.length <= dct.length ? flate : dct;
}

/// Builds a grayscale image XObject body from unpacked 8-bit samples.
///
/// The FlateDecode candidate is a true `/DeviceGray` stream (a third of the
/// raw size of an RGB one). The JPEG candidate expands the samples to RGB,
/// because the bundled encoder only writes 3-component JPEG streams, so it is
/// declared `/DeviceRGB`; both are valid and the smaller body wins.
Uint8List makeGrayImageBody(
  Uint8List gray,
  int width,
  int height, {
  int? jpegQuality = kDefaultJpegQuality,
  bool adaptive = true,
}) {
  final grayDict =
      ' /Type /XObject /Subtype /Image'
      ' /Width $width /Height $height'
      ' /ColorSpace /DeviceGray /BitsPerComponent 8';
  final flate = makeFlateStream(grayDict, gray);
  if (jpegQuality == null) return flate;
  if (adaptive && !_shouldTryJpeg(gray.length, flate.length)) return flate;
  final jpeg = encodeRgbJpeg(
    _expandGrayToRgb(gray),
    width,
    height,
    jpegQuality,
  );
  if (jpeg == null) return flate;
  final dct = makeDctStream(
    ' /Type /XObject /Subtype /Image'
    ' /Width $width /Height $height'
    ' /ColorSpace /DeviceRGB /BitsPerComponent 8',
    jpeg,
  );
  if (!adaptive) return dct;
  return flate.length <= dct.length ? flate : dct;
}

/// Whether the adaptive policy should attempt a JPEG encode.
bool _shouldTryJpeg(int rawLength, int flateLength) =>
    rawLength >= kRasterMinAdaptiveJpegBytes &&
    flateLength >= (rawLength * kRasterJpegFlateRatio).ceil();

/// Encodes packed RGB bytes as a baseline JPEG with 4:2:0 chroma.
///
/// Returns `null` when the encoder cannot represent the dimensions (JPEG
/// limits them to 65535), in which case callers fall back to FlateDecode.
Uint8List? encodeRgbJpeg(Uint8List rgb, int width, int height, int quality) {
  if (width <= 0 || height <= 0 || width > 0xffff || height > 0xffff) {
    return null;
  }
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgb.buffer,
    bytesOffset: rgb.offsetInBytes,
    numChannels: 3,
  );
  return img.encodeJpg(
    image,
    quality: quality,
    chroma: img.JpegChroma.yuv420,
  );
}

/// Expands packed 8-bit grayscale samples to packed RGB.
Uint8List _expandGrayToRgb(Uint8List gray) {
  final out = Uint8List(gray.length * 3);
  for (var i = 0, j = 0; i < gray.length; i++, j += 3) {
    final value = gray[i];
    out[j] = value;
    out[j + 1] = value;
    out[j + 2] = value;
  }
  return out;
}

/// Formats a point value for a `cm`/`MediaBox` operand: the exact literal
/// `0` for zero (matching the historical full-page operator), else 4 decimals.
String fmtPt(double value) =>
    value == 0 ? '0' : value.toStringAsFixed(4);

/// Formats one `rg` colour component (0..255 → 0..1).
///
/// `0` and `255` format as the exact literals `0`/`1`, so an all-black layer
/// emits the historical `0 0 0 rg` operator byte for byte.
String fmtRgComponent(int value) {
  if (value == 0) return '0';
  if (value == 255) return '1';
  return (value / 255).toStringAsFixed(4);
}

/// Formats [text] as a complete PDF string token.
///
/// Pure-ASCII strings use literal syntax with parentheses, backslashes and
/// control characters escaped. Anything else is written as a UTF-16BE hex
/// string with a byte-order mark (`<FEFF...>`), which every PDF text string
/// context accepts, so bookmark titles with em dashes, accents or CJK text
/// survive instead of degrading to `?`.
String pdfStringLiteral(String text) {
  var ascii = true;
  for (final unit in text.codeUnits) {
    if (unit > 0x7f) {
      ascii = false;
      break;
    }
  }
  if (!ascii) {
    final hex = StringBuffer('<FEFF');
    for (final unit in text.codeUnits) {
      hex.write(unit.toRadixString(16).padLeft(4, '0').toUpperCase());
    }
    hex.write('>');
    return hex.toString();
  }
  final out = StringBuffer('(');
  for (final unit in text.codeUnits) {
    switch (unit) {
      case 0x28: // (
        out.write(r'\(');
      case 0x29: // )
        out.write(r'\)');
      case 0x5c: // \
        out.write(r'\\');
      case 0x0a: // \n
        out.write(r'\n');
      case 0x0d: // \r
        out.write(r'\r');
      case 0x09: // \t
        out.write(r'\t');
      case 0x08: // \b
        out.write(r'\b');
      case 0x0c: // \f
        out.write(r'\f');
      default:
        out.writeCharCode(unit);
    }
  }
  out.write(')');
  return out.toString();
}

/// Encodes an ASCII string as Latin-1 bytes (every syntax string
/// [DjvuPdfWriter] builds is ASCII).
Uint8List _latin1(String text) {
  final out = Uint8List(text.length);
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    assert(unit <= 0xff, 'non-Latin-1 text in PDF syntax');
    out[i] = unit;
  }
  return out;
}
