// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

/// Little-endian binary reader for Samsung Notes (.sdocx) structures.
///
/// Mirrors the `Reader` helper from the reverse-engineered Rust SDK
/// (twangodev/sdocx) and the Python research implementation
/// (bxff/samsung-notes-format `render.py`).
class SdocxReader {
  SdocxReader(this.data, [this.offset = 0]);

  final Uint8List data;
  int offset;

  int get remaining => data.length - offset;
  bool get isEof => remaining <= 0;
  int get position => offset;

  void seek(int pos) {
    if (pos < 0 || pos > data.length) {
      throw FormatException('SdocxReader: seek out of range: $pos');
    }
    offset = pos;
  }

  void skip(int n) {
    if (offset + n > data.length) {
      throw FormatException('SdocxReader: truncated skip ($n bytes)');
    }
    offset += n;
  }

  Uint8List readBytes(int n) {
    if (offset + n > data.length) {
      throw FormatException(
        'SdocxReader: truncated read (need $n, have $remaining)',
      );
    }
    final out = data.sublist(offset, offset + n);
    offset += n;
    return out;
  }

  int readU8() => readBytes(1)[0];

  int readU16() {
    final b = readBytes(2);
    return b[0] | (b[1] << 8);
  }

  int readI16() {
    final v = readU16();
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  int readU32() {
    final b = readBytes(4);
    return b[0] | (b[1] << 8) | (b[2] << 16) | (b[3] << 24);
  }

  int readI32() {
    final v = readU32();
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }

  int readU64() {
    final lo = readU32();
    final hi = readU32();
    // Dart ints are 64-bit; combine carefully for unsigned values.
    return (hi * 0x100000000) + (lo & 0xFFFFFFFF);
  }

  int readI64() {
    final b = readBytes(8);
    final bd = ByteData.sublistView(b);
    return bd.getInt64(0, Endian.little);
  }

  double readF32() {
    final b = readBytes(4);
    return ByteData.sublistView(b).getFloat32(0, Endian.little);
  }

  double readF64() {
    final b = readBytes(8);
    return ByteData.sublistView(b).getFloat64(0, Endian.little);
  }

  /// Length-prefixed UTF-16LE string with u16 length (code units).
  /// Returns empty string for length 0. Throws on truncation.
  String readUtf16U16() {
    final units = readU16();
    if (units == 0xFFFF) {
      // Null sentinel used by some Samsung strings.
      throw FormatException('SdocxReader: null string sentinel');
    }
    if (units == 0) return '';
    final bytes = readBytes(units * 2);
    // Decode UTF-16LE manually to avoid issues with lone surrogates.
    final codeUnits = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      codeUnits.add(bytes[i] | (bytes[i + 1] << 8));
    }
    try {
      return String.fromCharCodes(codeUnits);
    } catch (_) {
      // Fallback: replace invalid sequences.
      return utf8.decode(utf8.encode(String.fromCharCodes(codeUnits)),
          allowMalformed: true);
    }
  }

  String? tryReadUtf16U16() {
    if (remaining < 2) return null;
    final saved = offset;
    try {
      final units = readU16();
      if (units == 0xFFFF) return null;
      if (units == 0) return '';
      if (remaining < units * 2) {
        offset = saved;
        return null;
      }
      final bytes = readBytes(units * 2);
      final codeUnits = <int>[];
      for (var i = 0; i + 1 < bytes.length; i += 2) {
        codeUnits.add(bytes[i] | (bytes[i + 1] << 8));
      }
      return String.fromCharCodes(codeUnits);
    } catch (_) {
      offset = saved;
      return null;
    }
  }

  /// Length-prefixed UTF-8 string with u16 byte length.
  String readUtf8U16() {
    final len = readU16();
    if (len == 0) return '';
    final bytes = readBytes(len);
    // Stop at first NUL (Samsung UUIDs are NUL-terminated in some records).
    final nul = bytes.indexOf(0);
    final effective = nul >= 0 ? bytes.sublist(0, nul) : bytes;
    return utf8.decode(effective, allowMalformed: true);
  }
}

/// Length-prefixed bit mask: 1 byte count + that many bytes.
/// Mirrors Rust `Mask`.
class SdocxMask {
  SdocxMask(this.bytes);

  final Uint8List bytes;

  static SdocxMask read(SdocxReader r) {
    final count = r.readU8();
    final bytes = r.readBytes(count);
    return SdocxMask(bytes);
  }

  bool contains(int bit) {
    final idx = bit ~/ 8;
    if (idx >= bytes.length) return false;
    return (bytes[idx] & (1 << (bit % 8))) != 0;
  }

  int get lowU32 {
    var v = 0;
    for (var i = 0; i < bytes.length && i < 4; i++) {
      v |= bytes[i] << (i * 8);
    }
    return v;
  }

  bool get isEmpty => bytes.every((b) => b == 0);

  bool hasOtherBits(int knownLow) {
    if ((lowU32 & ~knownLow) != 0) return true;
    for (var i = 4; i < bytes.length; i++) {
      if (bytes[i] != 0) return true;
    }
    return false;
  }
}
