// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// IFF container parsing (DjVu flavour): the `AT&T` FM/`FORM` chunk tree, the
// per-page `INFO` chunk, the DJVM `DIRM` directory and the `INCL` include
// mechanism.
//
// Ported from djvu-rs (`crates/djvu-iff`, `src/dirm.rs`, `src/info.rs`, MIT,
// https://github.com/matyushkin/djvu-rs), with the same tolerance rules:
// trailing fragments shorter than a chunk header inside a FORM are ignored,
// and a chunk claiming more bytes than its enclosing FORM is an error.

import 'dart:typed_data';

/// Thrown when a DjVu container is malformed.
class DjvuFormatException implements Exception {
  const DjvuFormatException(this.message);
  final String message;
  @override
  String toString() => 'DjvuFormatException: $message';
}

/// One IFF chunk: a 4-byte identifier plus a zero-copy view of its payload.
class IffChunk {
  IffChunk(this.id, this.data);

  /// Four ASCII bytes, e.g. `INFO`.
  final String id;

  /// Payload bytes (not including the 8-byte id/length header).
  final Uint8List data;

  /// The `FORM` secondary type when [id] is `FORM`, else null.
  String? formType;

  @override
  String toString() => '$id[${data.length}]';
}

/// A parsed top-level `FORM`.
class IffForm {
  IffForm(this.formType, this.chunks);

  /// The 4-byte secondary type (`DJVU`, `DJVM`, `DJVU`, `BM44`, …).
  final String formType;

  /// The FORM's direct children.
  final List<IffChunk> chunks;

  /// First direct child with [id], or null.
  IffChunk? find(String id) {
    for (final c in chunks) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// All direct children with [id], in order.
  List<IffChunk> findAll(String id) {
    final out = <IffChunk>[];
    for (final c in chunks) {
      if (c.id == id) out.add(c);
    }
    return out;
  }
}

/// Reads a big-endian u32 from [data] at [offset].
int _u32be(Uint8List data, int offset) =>
    (data[offset] << 24) |
    (data[offset + 1] << 16) |
    (data[offset + 2] << 8) |
    data[offset + 3];

String _fourcc(Uint8List data, int offset) =>
    String.fromCharCodes(data, offset, offset + 4);

/// Parses a complete DjVu file (`AT&T` magic followed by a root `FORM`).
///
/// Throws [DjvuFormatException] when the input is not a well-formed DjVu IFF
/// stream. Any bytes after the root FORM are ignored, matching the reference.
IffForm parseIffFile(Uint8List bytes) {
  if (bytes.length < 16) {
    throw const DjvuFormatException('input is too short to be a valid IFF file');
  }
  if (bytes[0] != 0x41 || bytes[1] != 0x54 || bytes[2] != 0x26 || bytes[3] != 0x54) {
    throw const DjvuFormatException('bad magic bytes: expected AT&T');
  }
  if (bytes[4] != 0x46 || bytes[5] != 0x4f || bytes[6] != 0x52 || bytes[7] != 0x4d) {
    throw const DjvuFormatException('root chunk is not FORM');
  }
  final formLen = _u32be(bytes, 8);
  final formEnd = 12 + formLen;
  if (formEnd > bytes.length || formLen < 4) {
    throw DjvuFormatException(
      'FORM claims $formLen bytes but only ${bytes.length - 12} are available',
    );
  }
  final formType = _fourcc(bytes, 12);
  final chunks = _parseChunks(bytes, 16, formEnd);
  return IffForm(formType, chunks);
}

/// Parses a sub-FORM body: the 4-byte secondary type followed by chunks.
///
/// Used for the components of a bundled `FORM:DJVM`, whose `FORM` framing was
/// already consumed by [parseIffFile].
IffForm parseIffSubForm(Uint8List body) {
  if (body.length < 4) {
    throw const DjvuFormatException('sub-form body is too short');
  }
  final formType = _fourcc(body, 0);
  final chunks = _parseChunks(body, 4, body.length);
  return IffForm(formType, chunks);
}

/// Parses the chunks in `[start, end)` of [bytes] into [IffChunk] views.
///
/// Nested `FORM` chunks are returned as a single [IffChunk] whose [IffChunk.data]
/// covers the secondary type and children, with [IffChunk.formType] set.
List<IffChunk> _parseChunks(Uint8List bytes, int start, int end) {
  final out = <IffChunk>[];
  var pos = start;
  while (pos + 8 <= end) {
    final id = _fourcc(bytes, pos);
    final len = _u32be(bytes, pos + 4);
    final payloadStart = pos + 8;
    final payloadEnd = payloadStart + len;
    if (payloadEnd > end) {
      throw DjvuFormatException(
        'chunk $id claims $len bytes but only ${end - payloadStart} are available',
      );
    }
    final data = Uint8List.sublistView(bytes, payloadStart, payloadEnd);
    if (id == 'FORM') {
      if (len < 4) {
        throw const DjvuFormatException('FORM chunk is too short');
      }
      final chunk = IffChunk(id, data)..formType = _fourcc(bytes, payloadStart);
      out.add(chunk);
    } else {
      out.add(IffChunk(id, data));
    }
    // Advance past the payload plus word-alignment padding.
    final total = 8 + len;
    pos += total + (total & 1);
  }
  return out;
}

/// Parses the children of a nested FORM given by absolute offsets.
List<IffChunk> parseFormChildren(Uint8List bytes, int payloadStart, int payloadEnd) =>
    _parseChunks(bytes, payloadStart + 4, payloadEnd);

// ---------------------------------------------------------------------------
// INFO
// ---------------------------------------------------------------------------

/// Page rotation flag in the INFO chunk.
enum DjvuRotation { none, ccw90, rot180, cw90 }

/// Metadata from a page's INFO chunk.
class DjvuPageInfo {
  const DjvuPageInfo({
    required this.width,
    required this.height,
    required this.dpi,
    required this.gamma,
    required this.rotation,
  });

  /// Page width in pixels.
  final int width;

  /// Page height in pixels.
  final int height;

  /// Resolution in dots per inch (defaults to 300 when absent).
  final int dpi;

  /// Display gamma (defaults to 2.2 when absent; always clamped to 0.3–5.0).
  final double gamma;

  /// Page rotation.
  final DjvuRotation rotation;
}

/// Parses an INFO chunk payload.
///
/// Layout: width/height (big-endian u16), minor/major version bytes, dpi
/// (little-endian u16), gamma byte, flags byte. Chunks down to 4 bytes parse
/// (real-world files carry short INFO chunks); a version ≥ 50 is rejected, as
/// in DjVuLibre and the reference implementation.
DjvuPageInfo parseDjvuPageInfo(Uint8List data) {
  if (data.length < 4) {
    throw const DjvuFormatException('INFO chunk is too short');
  }
  final width = (data[0] << 8) | data[1];
  final height = (data[2] << 8) | data[3];
  var version = 0;
  if (data.length >= 5) {
    version = data[4];
    if (data.length >= 6 && data[5] != 0xff) {
      version = (data[5] << 8) | data[4];
    }
  }
  if (version >= 50) {
    throw DjvuFormatException('unsupported DjVu format version $version');
  }
  var dpi = 300;
  if (data.length >= 8) {
    dpi = data[6] | (data[7] << 8);
  }
  var gamma = 2.2;
  if (data.length >= 9) {
    gamma = data[8] / 10.0;
    if (gamma < 0.3) gamma = 0.3;
    if (gamma > 5.0) gamma = 5.0;
  }
  var rotation = DjvuRotation.none;
  if (data.length >= 10) {
    rotation = switch (data[9] & 0x3) {
      1 => DjvuRotation.ccw90,
      2 => DjvuRotation.rot180,
      3 => DjvuRotation.cw90,
      _ => DjvuRotation.none,
    };
  }
  return DjvuPageInfo(
    width: width,
    height: height,
    dpi: dpi,
    gamma: gamma,
    rotation: rotation,
  );
}

// ---------------------------------------------------------------------------
// DIRM
// ---------------------------------------------------------------------------

/// Component classification from a DIRM per-component flags byte.
enum DirmKind {
  /// A renderable page (`FORM:DJVU`).
  page,

  /// A shared include component (`FORM:DJVI`), e.g. a symbol dictionary.
  shared,

  /// The document's shared annotation component.
  sharedAnnotation,

  /// A thumbnail (`FORM:THUM`).
  thumbnail,
}

/// One DIRM component descriptor.
class DirmComponent {
  const DirmComponent(this.kind, this.id, this.size);

  /// Component classification.
  final DirmKind kind;

  /// Directory entry id (resolver key / first metadata string).
  final String id;

  /// Component byte length from the DIRM size table (FORM header included),
  /// or 0 when the table is zeroed.
  final int size;
}

/// A parsed DIRM (directory) chunk payload.
class DirmPayload {
  DirmPayload(this.flags, this.nfiles, this.offsets, this.metadata);

  /// Version/flags byte; bit 7 set means "bundled" (offset table present).
  final int flags;

  /// Declared component count.
  final int nfiles;

  /// Absolute FORM-header offsets, one per component (empty when indirect).
  final List<int> offsets;

  /// Trailing BZZ-compressed metadata, captured verbatim.
  final Uint8List metadata;

  /// Whether this is a bundled document (offset table present).
  bool get isBundled => (flags & 0x80) != 0;

  /// Decodes per-component kind and id from the BZZ metadata.
  ///
  /// Lenient like the reference: a BZZ failure or short metadata yields
  /// [nfiles] synthetic page entries (`p0000`, `p0001`, …).
  List<DirmComponent> components(Uint8List Function(Uint8List) bzzDecode) {
    final n = nfiles;
    Uint8List meta;
    try {
      meta = bzzDecode(metadata);
    } catch (_) {
      meta = Uint8List(0);
    }
    final flagsStart = n * 3;
    if (flagsStart + n > meta.length) {
      return List.generate(
        n,
        (i) => DirmComponent(
          DirmKind.page,
          'p${i.toString().padLeft(4, '0')}',
          0,
        ),
      );
    }
    final out = <DirmComponent>[];
    var pos = flagsStart + n;
    for (var i = 0; i < n; i++) {
      final flag = meta[flagsStart + i];
      final kind = switch (flag & 0x3f) {
        1 => DirmKind.page,
        2 => DirmKind.thumbnail,
        3 => DirmKind.sharedAnnotation,
        _ => DirmKind.shared,
      };
      final id = _readNtString(meta, pos);
      pos = id.$2;
      if (flag & 0x80 != 0) {
        pos = _readNtString(meta, pos).$2;
      }
      if (flag & 0x40 != 0) {
        pos = _readNtString(meta, pos).$2;
      }
      final size = (meta[i * 3] << 16) | (meta[i * 3 + 1] << 8) | meta[i * 3 + 2];
      out.add(DirmComponent(kind, id.$1, size));
    }
    return out;
  }

  static (String, int) _readNtString(Uint8List data, int pos) {
    if (pos >= data.length) return ('', pos);
    var end = pos;
    while (end < data.length && data[end] != 0) {
      end++;
    }
    final s = String.fromCharCodes(data, pos, end);
    return (s, end + 1);
  }
}

/// Parses a DIRM chunk payload.
DirmPayload parseDirmPayload(Uint8List data) {
  if (data.length < 3) {
    throw const DjvuFormatException('DIRM chunk too short');
  }
  final flags = data[0];
  final nfiles = (data[1] << 8) | data[2];
  final bundled = (flags & 0x80) != 0;
  var pos = 3;
  var offsets = const <int>[];
  if (bundled) {
    final end = pos + nfiles * 4;
    if (end > data.length) {
      throw const DjvuFormatException('DIRM offset table truncated');
    }
    final list = List<int>.filled(nfiles, 0);
    for (var i = 0; i < nfiles; i++) {
      list[i] = _u32be(data, pos + i * 4);
    }
    offsets = list;
    pos = end;
  }
  return DirmPayload(
    flags,
    nfiles,
    offsets,
    Uint8List.sublistView(data, pos, data.length),
  );
}

/// The DIRM component name an INCL chunk payload refers to.
///
/// Writers pad the name with trailing NULs or whitespace; both are stripped.
/// Returns null when the name is not valid UTF-8 (it is always ASCII in
/// practice, so null simply means "treat as unresolvable").
String? inclTarget(Uint8List data) {
  var end = data.length;
  while (end > 0) {
    final b = data[end - 1];
    if (b != 0 && !(b == 0x20 || b == 0x09 || b == 0x0a || b == 0x0d)) break;
    end--;
  }
  if (end == 0) return null;
  try {
    return String.fromCharCodes(data, 0, end);
  } catch (_) {
    return null;
  }
}
