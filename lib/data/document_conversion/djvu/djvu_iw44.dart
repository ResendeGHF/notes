// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// IW44 wavelet image decoder — pure Dart port.
//
// Ported from djvu-rs (crates/djvu-iw44, MIT,
// https://github.com/matyushkin/djvu-rs), a clean-room implementation of the
// IW44 progressive wavelet codec used by the DjVu BG44, FG44 and TH44 chunks.
// The ZP arithmetic coder is the existing Dart port in `djvu_zp.dart`.
//
// Behavioural notes:
//
// - Chunk framing, serial continuity, the slice loop, coefficient decoding,
//   the quantization schedule and both output conversions follow the reference
//   exactly; the decoded coefficients and output pixels are bit-identical.
// - Coefficient blocks are dense 32x32 `Int16List`s in zigzag-scan order. The
//   reference stores only the bucket prefix a block really uses, but an absent
//   bucket always reads as zero, so the decoded coefficients are identical.
// - The reference's SIMD kernels are ported as scalar loops. The vector paths
//   are pure performance, not semantics.
// - `Int16List` stores truncate exactly like Rust's `as i16`, so every place
//   the reference relies on wrapping is masked by the container type here.

import 'dart:typed_data';

import 'package:saber/data/document_conversion/djvu/djvu_bitmap.dart';
import 'package:saber/data/document_conversion/djvu/djvu_zp.dart';

/// Thrown when an IW44 stream is malformed, truncated, or out of order.
class Iw44Exception implements Exception {
  const Iw44Exception(this.message);

  /// Human-readable failure description.
  final String message;

  @override
  String toString() => 'Iw44Exception: $message';
}

/// Progressive IW44 decoder for one plane set (a BG44, FG44 or TH44 stream).
///
/// Feed every chunk of the stream to [decodeChunk] in document order. The ZP
/// coder state, the quantization schedule and the coefficient planes persist
/// across chunks — that is what makes the stream progressive: each chunk
/// refines the picture rather than restarting it. [toRgb] and [toGray8]
/// convert the coefficients decoded so far.
class Iw44Image {
  /// Creates a decoder with no chunks decoded yet.
  Iw44Image();

  var _width = 0;
  var _height = 0;
  var _isColor = false;
  var _chromaHalf = false;
  var _delay = 0;
  var _cslice = 0;
  var _nextSerial = 0;
  _PlaneDecoder? _y;
  _PlaneDecoder? _cb;
  _PlaneDecoder? _cr;

  /// Image width in pixels, from the first chunk header (0 before it).
  int get width => _width;

  /// Image height in pixels, from the first chunk header (0 before it).
  int get height => _height;

  /// Whether the stream carries chroma planes (the header's grayscale bit is
  /// clear).
  bool get isColor => _isColor;

  /// Whether chroma is stored at half resolution (`crcb_half`).
  bool get chromaHalf => _chromaHalf;

  /// Decodes one chunk in document order.
  ///
  /// Throws [Iw44Exception] on malformed input, short chunks, or a serial
  /// number that does not continue the sequence (0, 1, 2, …).
  void decodeChunk(Uint8List data) {
    if (data.length < 2) {
      throw const Iw44Exception('IW44 chunk is too short');
    }
    final serial = data[0];
    final slices = data[1];

    // Serial continuity, mirroring DjVuLibre's `cserial` counter and the
    // reference's `next_serial`: every chunk after the first must arrive with
    // the exact next serial. A mismatch — a dropped, duplicated or reordered
    // chunk — is rejected instead of being decoded into the wrong refinement
    // slot. The very first chunk is exempt so that a non-zero first serial
    // reports "missing first chunk" instead.
    if (_y != null && serial != _nextSerial) {
      throw const Iw44Exception(
        'IW44 chunk does not bear expected serial number',
      );
    }

    int payloadStart;
    if (serial == 0) {
      if (data.length < 9) {
        throw const Iw44Exception(
          'IW44 first chunk header too short (need ≥ 9 bytes)',
        );
      }
      final majver = data[2];
      final minor = data[3];
      final isGrayscale = (majver >> 7) != 0;
      final w = (data[4] << 8) | data[5];
      final h = (data[6] << 8) | data[7];
      final delayByte = data[8];
      final delay = minor >= 2 ? delayByte & 127 : 0;
      // A clear high bit is DjVuLibre's `crcb_half`. It never changes the
      // plane size (Cb/Cr are always allocated full size); it only changes how
      // a full-resolution picture is reconstructed: each scale-2 chroma value
      // is repeated over its 2x2 block.
      final chromaHalf = minor >= 2 && (delayByte & 0x80) == 0;

      if (w == 0 || h == 0) {
        throw const Iw44Exception('IW44 image has zero dimension');
      }
      if (w * h > 64 * 1024 * 1024) {
        throw const Iw44Exception('IW44 image dimensions too large');
      }

      _width = w;
      _height = h;
      _isColor = !isGrayscale;
      _delay = delay;
      _chromaHalf = _isColor && chromaHalf;
      _cslice = 0;
      _y = _PlaneDecoder(w, h);
      if (_isColor) {
        _cb = _PlaneDecoder(w, h);
        _cr = _PlaneDecoder(w, h);
      }
      payloadStart = 9;
    } else {
      if (_y == null) {
        throw const Iw44Exception(
          'IW44 subsequent chunk received before first chunk',
        );
      }
      payloadStart = 2;
    }

    // A refinement chunk's ZP payload may legitimately be shorter than the
    // ZP decoder's 2-byte minimum — even empty. Pad up to 2 bytes with 0xFF,
    // which is how reads past the end of a stream are treated anyway.
    final raw = Uint8List.sublistView(data, payloadStart);
    final Uint8List zpData;
    if (raw.length >= 2) {
      zpData = raw;
    } else {
      final padded = Uint8List(2);
      padded[0] = raw.isNotEmpty ? raw[0] : 0xff;
      padded[1] = 0xff;
      zpData = padded;
    }
    final zp = ZpDecoder(zpData);

    for (var i = 0; i < slices; i++) {
      _cslice++;
      _y!.decodeSlice(zp);
      if (_isColor && _cslice > _delay) {
        _cb!.decodeSlice(zp);
        _cr!.decodeSlice(zp);
      }
      // No early exit when the ZP byte buffer drains: the coder reads up to
      // 24 bits ahead, so the remaining slices still decode legitimate
      // refinement from buffered bits and arithmetic registers.
    }

    _nextSerial = serial + 1;
  }

  /// RGB output at the image's natural size, top-to-bottom rows.
  ///
  /// DjVu stores rows bottom-to-top, so the picture is flipped vertically
  /// here. For a grayscale stream every channel is `127 - Y`; for a colour
  /// stream the YCbCr formula from the DjVu specification is applied, with
  /// half-resolution chroma (when [chromaHalf]) repeated over 2x2 blocks.
  RgbaImage toRgb() {
    final yDec = _y;
    if (yDec == null) {
      throw const Iw44Exception('IW44 codec not yet initialized');
    }
    final w = _width;
    final h = _height;
    final yPlane = yDec.reconstruct(1);
    final out = RgbaImage(w, h);
    final pixels = out.data;
    final yData = yPlane.data;
    final yStride = yPlane.stride;

    if (!_isColor) {
      for (var row = 0; row < h; row++) {
        final outRow = h - 1 - row; // DjVu rows are bottom-to-top.
        final yOff = row * yStride;
        var o = outRow * w * 4;
        for (var col = 0; col < w; col++) {
          final gray = 127 - _normalize(yData[yOff + col]);
          pixels[o] = gray;
          pixels[o + 1] = gray;
          pixels[o + 2] = gray;
          o += 4;
        }
      }
      return out;
    }

    final half = _chromaHalf;
    final chromaSub = half ? 2 : 1;
    final cbPlane = _cb!.reconstruct(chromaSub);
    final crPlane = _cr!.reconstruct(chromaSub);
    final cbData = cbPlane.data;
    final crData = crPlane.data;
    final cStride = cbPlane.stride;
    for (var row = 0; row < h; row++) {
      final outRow = h - 1 - row;
      final yOff = row * yStride;
      final cOff = (half ? row >> 1 : row) * cStride;
      var o = outRow * w * 4;
      for (var col = 0; col < w; col++) {
        final y = _normalize(yData[yOff + col]);
        final ci = cOff + (half ? col >> 1 : col);
        final b = _normalize(cbData[ci]);
        final r = _normalize(crData[ci]);
        // DjVu YCbCr→RGB (LeCun 1998), the reference's portable formula.
        final t2 = r + (r >> 1);
        final t3 = y + 128 - (b >> 2);
        pixels[o] = _clamp8(y + 128 + t2);
        pixels[o + 1] = _clamp8(t3 - (t2 >> 1));
        pixels[o + 2] = _clamp8(t3 + (b << 1));
        o += 4;
      }
    }
    return out;
  }

  /// Luma-only 8-bit output at full resolution, top-to-bottom rows.
  ///
  /// For a grayscale stream this is `127 - Y`, identical to [toRgb]'s
  /// R channel (and to `toGray8` of that picture). For a colour stream this
  /// is the DjVu luma channel `clamp(Y + 128, 0, 255)` — the encoder's own
  /// luminance, not the Rec.601 luma of the reconstructed RGB.
  Gray8Image toGray8() {
    final yDec = _y;
    if (yDec == null) {
      throw const Iw44Exception('IW44 codec not yet initialized');
    }
    final w = _width;
    final h = _height;
    final yPlane = yDec.reconstruct(1);
    final out = Gray8Image(w, h);
    final pixels = out.data;
    final yData = yPlane.data;
    final yStride = yPlane.stride;
    final isColor = _isColor;
    for (var row = 0; row < h; row++) {
      final outRow = h - 1 - row; // DjVu rows are bottom-to-top.
      final yOff = row * yStride;
      final dst = outRow * w;
      for (var col = 0; col < w; col++) {
        final val = _normalize(yData[yOff + col]);
        pixels[dst + col] = isColor ? val + 128 : 127 - val;
      }
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------

/// `_bandBuckets[band]` = first and last bucket (inclusive) of the band.
const _bandBuckets = [
  (0, 0),
  (1, 1),
  (2, 2),
  (3, 3),
  (4, 7),
  (8, 11),
  (12, 15),
  (16, 31),
  (32, 47),
  (48, 63),
];

/// Initial quantization step for the 16 coefficients of band 0.
const _quantLoInit = [
  0x004000,
  0x008000,
  0x008000,
  0x010000,
  0x010000,
  0x010000,
  0x010000,
  0x010000,
  0x010000,
  0x010000,
  0x010000,
  0x010000,
  0x020000,
  0x020000,
  0x020000,
  0x020000,
];

/// Initial quantization step per band (entry 0 is unused / always zero).
const _quantHiInit = [
  0,
  0x020000,
  0x020000,
  0x040000,
  0x040000,
  0x040000,
  0x080000,
  0x040000,
  0x040000,
  0x080000,
];

// Coefficient state flags.
const _zero = 1;
const _active = 2;
const _new = 4;
const _unk = 8;

/// Inverse zigzag: `_zigzagInv[row * 32 + col]` is the zigzag index `i` with
/// `_zigzagRow(i) == row && _zigzagCol(i) == col`.
final Uint16List _zigzagInv = _buildZigzagInv();

/// Compact inverse zigzag for the scale-2 plane: `_zigzagInvSub2[row * 16 +
/// col]` is the index `i < 256` with `_zigzagRow(i) >> 1 == row` and
/// `_zigzagCol(i) >> 1 == col`.
final Uint8List _zigzagInvSub2 = _buildZigzagInvSub2();

int _zigzagRow(int i) =>
    ((i >> 1) & 1) * 16 +
    ((i >> 3) & 1) * 8 +
    ((i >> 5) & 1) * 4 +
    ((i >> 7) & 1) * 2 +
    ((i >> 9) & 1);

int _zigzagCol(int i) =>
    (i & 1) * 16 +
    ((i >> 2) & 1) * 8 +
    ((i >> 4) & 1) * 4 +
    ((i >> 6) & 1) * 2 +
    ((i >> 8) & 1);

Uint16List _buildZigzagInv() {
  final table = Uint16List(1024);
  for (var i = 0; i < 1024; i++) {
    table[_zigzagRow(i) * 32 + _zigzagCol(i)] = i;
  }
  return table;
}

Uint8List _buildZigzagInvSub2() {
  final table = Uint8List(256);
  for (var i = 0; i < 256; i++) {
    table[(_zigzagRow(i) >> 1) * 16 + (_zigzagCol(i) >> 1)] = i;
  }
  return table;
}

/// Map a raw wavelet coefficient to a signed pixel offset in `[-128, 127]`.
int _normalize(int val) {
  var v = (val + 32) >> 6;
  if (v < -128) v = -128;
  if (v > 127) v = 127;
  return v;
}

int _clamp8(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);

// ---------------------------------------------------------------------------
// Per-plane coefficient decoder
// ---------------------------------------------------------------------------

/// One 32x32 IW44 coefficient block in zigzag-scan order.
typedef _CoefBlock = Int16List;

/// State for a single Y/Cb/Cr plane wavelet decoder.
///
/// Holds the 32x32 coefficient blocks and the ZP context tables, both of which
/// persist across progressive slices and chunks.
class _PlaneDecoder {
  _PlaneDecoder(this.width, this.height)
    : blockCols = (width + 31) >> 5,
      blockRows = (height + 31) >> 5;

  final int width;
  final int height;
  final int blockCols;
  final int blockRows;

  late final List<_CoefBlock> blocks = List.generate(
    blockCols * blockRows,
    (_) => Int16List(1024),
  );

  late final quantLo = Int32List.fromList(_quantLoInit);
  late final quantHi = Int32List.fromList(_quantHiInit);

  /// Current band index (0..9, wraps around).
  var curband = 0;

  // ZP context bytes — persistent across slices and chunks.
  final ctxDecodeBucket = Uint8List(1);
  final ctxDecodeCoef = Uint8List(80);
  final ctxActivateCoef = Uint8List(16);
  final ctxIncreaseCoef = Uint8List(1);

  // Per-slice decode state (re-used for every block, not persisted).
  final coeffState = List.generate(16, (_) => Uint8List(16));
  final bucketState = Uint8List(16);
  var bbState = 0;

  /// Decode one slice (one band across all blocks) from `zp`.
  void decodeSlice(ZpDecoder zp) {
    if (!_isNullSlice()) {
      for (var blockIdx = 0; blockIdx < blocks.length; blockIdx++) {
        _preliminaryFlagComputation(blockIdx);
        if (_blockBandDecodingPass(zp) && _bucketDecodingPass(zp, blockIdx)) {
          _newlyActiveCoefficientDecodingPass(zp, blockIdx);
        }
        // Skip the inner loop when no ACTIVE coefficients exist.
        if ((bbState & _active) != 0) {
          _previouslyActiveCoefficientDecodingPass(zp, blockIdx);
        }
      }
    }
    _finishSlice();
  }

  /// Resets band 0's coefficient flags for the new slice and reports whether
  /// the whole slice can be skipped (no quantization step is active).
  bool _isNullSlice() {
    if (curband == 0) {
      var isNull = true;
      for (var i = 0; i < 16; i++) {
        final threshold = quantLo[i];
        coeffState[0][i] = _zero;
        if (threshold > 0 && threshold < 0x8000) {
          coeffState[0][i] = _unk;
          isNull = false;
        }
      }
      return isNull;
    }
    final threshold = quantHi[curband];
    return !(threshold > 0 && threshold < 0x8000);
  }

  /// Recompute the current band's UNK/ACTIVE flags from the coefficients.
  void _preliminaryFlagComputation(int blockIdx) {
    bbState = 0;
    final (from, to) = _bandBuckets[curband];
    final block = blocks[blockIdx];

    if (curband != 0) {
      for (var i = from; i <= to; i++) {
        final boff = i - from;
        final off = i << 4;
        final flags = coeffState[boff];
        var bstatetmp = 0;
        for (var k = 0; k < 16; k++) {
          final f = block[off + k] == 0 ? _unk : _active;
          flags[k] = f;
          bstatetmp |= f;
        }
        bucketState[boff] = bstatetmp;
        bbState |= bstatetmp;
      }
    } else {
      // Band 0 only updates entries whose previous state was not ZERO.
      final flags = coeffState[0];
      var bstatetmp = 0;
      for (var k = 0; k < 16; k++) {
        if (flags[k] != _zero) {
          flags[k] = block[k] == 0 ? _unk : _active;
        }
        bstatetmp |= flags[k];
      }
      bucketState[0] = bstatetmp;
      bbState |= bstatetmp;
    }
  }

  /// Decode whether the block's band carries newly significant buckets.
  bool _blockBandDecodingPass(ZpDecoder zp) {
    final (from, to) = _bandBuckets[curband];
    final bcount = to - from + 1;
    final shouldMarkNew =
        bcount < 16 ||
        (bbState & _active) != 0 ||
        ((bbState & _unk) != 0 && zp.decodeBitAt(ctxDecodeBucket, 0));
    if (shouldMarkNew) bbState |= _new;
    return (bbState & _new) != 0;
  }

  /// Decode the band's newly significant buckets. Returns whether any bucket
  /// became new.
  bool _bucketDecodingPass(ZpDecoder zp, int blockIdx) {
    final (from, to) = _bandBuckets[curband];
    final block = blocks[blockIdx];
    var anyNew = false;
    for (var i = from; i <= to; i++) {
      final boff = i - from;
      if ((bucketState[boff] & _unk) == 0) continue;
      var n = 0;
      if (curband != 0) {
        final t = 4 * i;
        for (var j = t; j < t + 4; j++) {
          if (block[j] != 0) n++;
        }
        if (n == 4) n = 3;
      }
      if ((bbState & _active) != 0) n |= 4;
      if (zp.decodeBitAt(ctxDecodeCoef, n + curband * 8)) {
        bucketState[boff] |= _new;
        anyNew = true;
      }
    }
    return anyNew;
  }

  /// Decode the newly significant coefficients of the band's NEW buckets.
  void _newlyActiveCoefficientDecodingPass(ZpDecoder zp, int blockIdx) {
    final (from, to) = _bandBuckets[curband];
    final block = blocks[blockIdx];
    var step = quantHi[curband];
    for (var i = from; i <= to; i++) {
      final boff = i - from;
      if ((bucketState[boff] & _new) == 0) continue;
      final shift = (bucketState[boff] & _active) != 0 ? 8 : 0;
      final flags = coeffState[boff];
      var np = 0;
      for (var j = 0; j < 16; j++) {
        if ((flags[j] & _unk) != 0) np++;
      }
      final base = i << 4;
      for (var j = 0; j < 16; j++) {
        if ((flags[j] & _unk) != 0) {
          final ip = np < 7 ? np : 7;
          if (zp.decodeBitAt(ctxActivateCoef, shift + ip)) {
            final sign = zp.decodePassthroughIw44() ? -1 : 1;
            np = 0;
            if (curband == 0) step = quantLo[j];
            final s = step;
            final val = sign * (s + (s >> 1) - (s >> 3));
            block[base + j] = val.toSigned(16);
          }
          if (np > 0) np--;
        }
      }
    }
  }

  /// Hot inner loop: refine the band's already-active coefficients.
  void _previouslyActiveCoefficientDecodingPass(ZpDecoder zp, int blockIdx) {
    final (from, to) = _bandBuckets[curband];
    final block = blocks[blockIdx];
    var step = quantHi[curband];
    for (var i = from; i <= to; i++) {
      final boff = i - from;
      final flags = coeffState[boff];
      final base = i << 4;
      for (var j = 0; j < 16; j++) {
        if ((flags[j] & _active) != 0) {
          if (curband == 0) step = quantLo[j];
          final coef = block[base + j];
          var absCoef = coef < 0 ? -coef : coef;
          final s = step;
          final bool des;
          if (absCoef <= 3 * s) {
            des = zp.decodeBitAt(ctxIncreaseCoef, 0);
            absCoef += s >> 2;
          } else {
            des = zp.decodePassthroughIw44();
          }
          if (des) {
            absCoef += s >> 1;
          } else {
            absCoef += -s + (s >> 1);
          }
          block[base + j] = coef < 0
              ? (-absCoef).toSigned(16)
              : absCoef.toSigned(16);
        }
      }
    }
  }

  /// Advance the quantization steps and the band counter after one slice.
  void _finishSlice() {
    quantHi[curband] >>= 1;
    if (curband == 0) {
      for (var i = 0; i < 16; i++) {
        quantLo[i] >>= 1;
      }
    }
    curband++;
    if (curband == 10) curband = 0;
  }

  /// Apply the inverse wavelet transform and return a flat `i16` plane.
  ///
  /// `subsample` 1 gives the full-resolution plane with stride
  /// `ceil(width / 32) * 32`; 2 gives the compact scale-2 plane with stride
  /// `ceil(width / 32) * 16` and logical size `(ceil(width / 2),
  /// ceil(height / 2))`, exactly like the reference's `reconstruct(2)`.
  _FlatPlane reconstruct(int subsample) {
    if (subsample == 2) {
      const side = 16;
      final compactStride = blockCols * side;
      final plane = Int16List(compactStride * blockRows * side);
      for (var r = 0; r < blockRows; r++) {
        for (var c = 0; c < blockCols; c++) {
          final block = blocks[r * blockCols + c];
          final baseRow = r * side;
          final baseCol = c * side;
          for (var row = 0; row < side; row++) {
            var dst = (baseRow + row) * compactStride + baseCol;
            final invBase = row * side;
            for (var col = 0; col < side; col++) {
              plane[dst++] = block[_zigzagInvSub2[invBase + col]];
            }
          }
        }
      }
      final flat = _FlatPlane(plane, compactStride);
      _inverseWaveletFrom(
        flat,
        (width + 1) >> 1,
        (height + 1) >> 1,
        1,
        8,
      );
      return flat;
    }

    final fullStride = blockCols * 32;
    final plane = Int16List(fullStride * blockRows * 32);
    for (var r = 0; r < blockRows; r++) {
      for (var c = 0; c < blockCols; c++) {
        final block = blocks[r * blockCols + c];
        final baseRow = r << 5;
        final baseCol = c << 5;
        for (var row = 0; row < 32; row++) {
          final dstBase = (baseRow + row) * fullStride + baseCol;
          final invBase = row << 5;
          for (var col = 0; col < 32; col++) {
            plane[dstBase + col] = block[_zigzagInv[invBase + col]];
          }
        }
      }
    }
    final flat = _FlatPlane(plane, fullStride);
    _inverseWaveletFrom(flat, width, height, 1, 16);
    return flat;
  }
}

// ---------------------------------------------------------------------------
// Inverse Dubuc-Deslauriers-Lemire (4,4) wavelet transform
// ---------------------------------------------------------------------------

/// A reconstructed plane: `i16` samples plus a row stride.
class _FlatPlane {
  _FlatPlane(this.data, this.stride);

  final Int16List data;
  final int stride;
}

/// Run the inverse wavelet from `startScale` down to `subsample`.
///
/// `width` and `height` are the logical plane dimensions; `stride` may be
/// larger (planes are allocated in whole 32x32 blocks). `startScale` is 16 for
/// the full-resolution plane and 8 for the compact scale-2 plane, whose
/// coefficients only reach that far.
void _inverseWaveletFrom(
  _FlatPlane plane,
  int width,
  int height,
  int subsample,
  int startScale,
) {
  final data = plane.data;
  final stride = plane.stride;
  var s = startScale;
  var sDegree = startScale.bitLength - 1;
  final st0 = Int32List(width);
  final st1 = Int32List(width);
  final st2 = Int32List(width);
  while (s >= subsample) {
    _columnPass(data, stride, width, height, s, sDegree, st0, st1, st2);
    _rowPass(data, stride, width, height, s, sDegree);
    s >>= 1;
    if (sDegree > 0) sDegree--;
  }
}

/// The transposed column pass for one resolution level.
void _columnPass(
  Int16List data,
  int stride,
  int width,
  int height,
  int s,
  int sd,
  Int32List st0,
  Int32List st1,
  Int32List st2,
) {
  final kmax = (height - 1) >> sd;
  final border = kmax >= 3 ? kmax - 3 : 0;
  final numCols = (width + s - 1) >> sd;

  for (var ci = 0; ci < numCols; ci++) {
    st0[ci] = 0;
    st1[ci] = 0;
  }
  if (kmax >= 1) {
    final off = (1 << sd) * stride;
    for (var ci = 0; ci < numCols; ci++) {
      st2[ci] = data[off + ci * s];
    }
  } else {
    for (var ci = 0; ci < numCols; ci++) {
      st2[ci] = 0;
    }
  }

  // Lifting (even samples).
  var k = 0;
  while (k + 3 <= kmax) {
    final kOff = (k << sd) * stride;
    final n3Off = ((k + 3) << sd) * stride;
    for (var ci = 0; ci < numCols; ci++) {
      final p3 = st0[ci];
      final p1 = st1[ci];
      final n1 = st2[ci];
      final n3 = data[n3Off + ci * s];
      final a = p1 + n1;
      final idx = kOff + ci * s;
      data[idx] = data[idx] - (((a << 3) + a - (p3 + n3) + 16) >> 5);
      st0[ci] = p1;
      st1[ci] = n1;
      st2[ci] = n3;
    }
    k += 2;
  }
  while (k <= kmax) {
    final kOff = (k << sd) * stride;
    for (var ci = 0; ci < numCols; ci++) {
      final p3 = st0[ci];
      final p1 = st1[ci];
      final n1 = st2[ci];
      final a = p1 + n1;
      final idx = kOff + ci * s;
      data[idx] = data[idx] - (((a << 3) + a - p3 + 16) >> 5);
      st0[ci] = p1;
      st1[ci] = n1;
      st2[ci] = 0;
    }
    k += 2;
  }

  // Prediction (odd samples).
  if (kmax >= 1) {
    const km1Off = 0;
    final kOff = (1 << sd) * stride;
    if (kmax >= 2) {
      final kp1Off = (2 << sd) * stride;
      for (var ci = 0; ci < numCols; ci++) {
        final p = data[km1Off + ci * s];
        final n = data[kp1Off + ci * s];
        final idx = kOff + ci * s;
        data[idx] = data[idx] + ((p + n + 1) >> 1);
        st0[ci] = p;
        st1[ci] = n;
      }
    } else {
      for (var ci = 0; ci < numCols; ci++) {
        final p = data[km1Off + ci * s];
        final idx = kOff + ci * s;
        data[idx] = data[idx] + p;
        st0[ci] = p;
        st1[ci] = 0;
      }
    }
    if (kmax >= 4) {
      final off = (4 << sd) * stride;
      for (var ci = 0; ci < numCols; ci++) {
        st2[ci] = data[off + ci * s];
      }
    }
    var k2 = 3;
    while (k2 <= border) {
      final kOff2 = (k2 << sd) * stride;
      final n3Off = ((k2 + 3) << sd) * stride;
      for (var ci = 0; ci < numCols; ci++) {
        final p3 = st0[ci];
        final p1 = st1[ci];
        final n1 = st2[ci];
        final n3 = data[n3Off + ci * s];
        final a = p1 + n1;
        final idx = kOff2 + ci * s;
        data[idx] = data[idx] + (((a << 3) + a - (p3 + n3) + 8) >> 4);
        st0[ci] = p1;
        st1[ci] = n1;
        st2[ci] = n3;
      }
      k2 += 2;
    }
    while (k2 <= kmax) {
      final kOff2 = (k2 << sd) * stride;
      if (k2 < kmax) {
        for (var ci = 0; ci < numCols; ci++) {
          final p = st1[ci];
          final n = st2[ci];
          final idx = kOff2 + ci * s;
          data[idx] = data[idx] + ((p + n + 1) >> 1);
          st1[ci] = n;
          st2[ci] = 0;
        }
      } else {
        for (var ci = 0; ci < numCols; ci++) {
          final p = st1[ci];
          final idx = kOff2 + ci * s;
          data[idx] = data[idx] + p;
          st1[ci] = st2[ci];
          st2[ci] = 0;
        }
      }
      k2 += 2;
    }
  }
}

/// The row pass for one resolution level.
void _rowPass(
  Int16List data,
  int stride,
  int width,
  int height,
  int s,
  int sd,
) {
  final kmax = (width - 1) >> sd;
  final border = kmax >= 3 ? kmax - 3 : 0;
  for (var row = 0; row < height; row += s) {
    final off = row * stride;

    // Lifting (even samples).
    var prev1 = 0;
    var next1 = 0;
    var next3 = kmax >= 1 ? data[off + (1 << sd)] : 0;
    var k = 0;
    while (k <= kmax) {
      final prev3 = prev1;
      prev1 = next1;
      next1 = next3;
      if (k + 3 <= kmax) {
        next3 = data[off + ((k + 3) << sd)];
      } else if (k == 2 || k == 4) {
        // DjVuLibre `filter_bh` keeps the previous a3 here.
        next3 = next1;
      } else {
        next3 = 0;
      }
      final a = prev1 + next1;
      final c = prev3 + next3;
      final idx = off + (k << sd);
      data[idx] = data[idx] - (((a << 3) + a - c + 16) >> 5);
      k += 2;
    }

    // Prediction (odd samples).
    if (kmax >= 1) {
      var k2 = 1;
      prev1 = data[off + ((k2 - 1) << sd)];
      if (k2 < kmax) {
        next1 = data[off + ((k2 + 1) << sd)];
        final idx = off + (k2 << sd);
        data[idx] = data[idx] + ((prev1 + next1 + 1) >> 1);
      } else {
        final idx = off + (k2 << sd);
        data[idx] = data[idx] + prev1;
      }
      next3 = kmax >= 4 ? data[off + ((k2 + 3) << sd)] : 0;
      k2 = 3;
      while (k2 <= border) {
        final prev3 = prev1;
        prev1 = next1;
        next1 = next3;
        next3 = data[off + ((k2 + 3) << sd)];
        final a = prev1 + next1;
        final idx = off + (k2 << sd);
        data[idx] = data[idx] + (((a << 3) + a - (prev3 + next3) + 8) >> 4);
        k2 += 2;
      }
      while (k2 <= kmax) {
        prev1 = next1;
        next1 = next3;
        next3 = 0;
        final idx = off + (k2 << sd);
        if (k2 < kmax) {
          data[idx] = data[idx] + ((prev1 + next1 + 1) >> 1);
        } else {
          data[idx] = data[idx] + prev1;
        }
        k2 += 2;
      }
    }
  }
}
