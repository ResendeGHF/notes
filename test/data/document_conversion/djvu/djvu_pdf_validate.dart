// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Minimal structural PDF reader for the DjVu → PDF converter tests.
//
// There is no general-purpose PDF parser available to unit tests (the `pdf`
// package only writes documents), so the converter's output is validated with
// this small reader instead. It parses exactly the subset the writer and
// converter emit: direct-object dictionaries and arrays, names, numbers,
// references, literal/hex strings and streams with a direct `/Length`. It
// checks the document structure (header, xref table, every offset pointing at
// its `N 0 obj`, stream lengths, trailer, `startxref`, `%%EOF`) and exposes
// decompressed streams so tests can assert on the actual content.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Thrown when [parsePdf] finds malformed PDF structure.
class PdfFormatException implements Exception {
  PdfFormatException(this.message, [this.offset]);

  final String message;
  final int? offset;

  @override
  String toString() =>
      'PdfFormatException: $message${offset == null ? '' : ' (at byte $offset)'}';
}

/// An indirect object reference `id 0 R`.
class PdfRef {
  const PdfRef(this.id);

  final int id;

  @override
  bool operator ==(Object other) => other is PdfRef && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => '$id 0 R';
}

/// One indirect object of a parsed PDF file.
class PdfObjectRecord {
  PdfObjectRecord({
    required this.id,
    required this.offset,
    required this.value,
    required this.stream,
    required this.endOffset,
  });

  final int id;

  /// Byte offset of `N 0 obj`.
  final int offset;

  /// Parsed body value: a `Map<String, Object?>` for dictionaries, a
  /// `List<Object?>` for arrays, or a scalar.
  final Object? value;

  /// Raw stream bytes, when the object is a stream.
  final Uint8List? stream;

  /// Byte offset just past the closing `endobj`.
  final int endOffset;

  /// The body as a dictionary (throws [PdfFormatException] otherwise).
  Map<String, Object?> get dict {
    final v = value;
    if (v is! Map<String, Object?>) {
      throw PdfFormatException('object $id is not a dictionary', offset);
    }
    return v;
  }

  /// Stream bytes, or a descriptive failure when the object is not a stream.
  Uint8List get streamBytes {
    final s = stream;
    if (s == null) throw PdfFormatException('object $id has no stream', offset);
    return s;
  }
}

/// A structurally validated PDF file.
class ParsedPdf {
  ParsedPdf({
    required this.bytes,
    required this.objects,
    required this.trailer,
    required this.xrefOffset,
    required this.xrefOffsets,
    required this.xrefGenerations,
    required this.xrefInUse,
  });

  final Uint8List bytes;

  /// Objects by id (only in-use entries).
  final Map<int, PdfObjectRecord> objects;

  final Map<String, Object?> trailer;

  /// The `startxref` value.
  final int xrefOffset;

  /// Byte offset per xref entry; `-1` for free entries.
  final List<int> xrefOffsets;

  final List<int> xrefGenerations;
  final List<bool> xrefInUse;

  /// The object count from the xref subsection header and `/Size`.
  int get objectCount => xrefInUse.length;

  /// Returns the object with [id], throwing a descriptive error if missing.
  PdfObjectRecord object(int id) {
    final record = objects[id];
    if (record == null) {
      throw PdfFormatException('no in-use object with id $id');
    }
    return record;
  }

  /// Decompresses a FlateDecode stream.
  Uint8List inflate(PdfObjectRecord record) {
    final filter = record.dict['Filter'];
    if (filter != 'FlateDecode') {
      throw PdfFormatException(
        'object ${record.id} is not FlateDecode (filter: $filter)',
        record.offset,
      );
    }
    return Uint8List.fromList(ZLibCodec().decode(record.streamBytes));
  }

  /// The decompressed text of a FlateDecode content stream (Latin-1).
  String contentText(PdfObjectRecord record) =>
      latin1.decode(inflate(record));
}

/// Parses and structurally validates [bytes].
///
/// Throws [PdfFormatException] on the first structural problem; the tests
/// rely on that to catch broken offsets, lengths and framing.
ParsedPdf parsePdf(Uint8List bytes) {
  if (!_startsWithAscii(bytes, 0, '%PDF-1.')) {
    throw PdfFormatException('missing %PDF-1.x header', 0);
  }

  // Locate the last startxref (the authoritative one).
  final startxrefIndex = _lastIndexOfAscii(bytes, 'startxref');
  if (startxrefIndex < 0) {
    throw PdfFormatException('missing startxref', bytes.length);
  }
  final tailLexer = _Lexer(bytes, startxrefIndex + 'startxref'.length);
  tailLexer.skipWhitespace();
  final xrefOffset = tailLexer.parseInteger();

  // Cross-reference table.
  final lexer = _Lexer(bytes, xrefOffset);
  lexer.expect('xref');
  lexer.skipWhitespace();
  final firstId = lexer.parseInteger();
  if (firstId != 0) {
    throw PdfFormatException('xref subsection must start at 0', lexer.pos);
  }
  lexer.skipWhitespace();
  final count = lexer.parseInteger();
  if (count < 1) {
    throw PdfFormatException('empty xref table', lexer.pos);
  }
  lexer.skipWhitespace();
  final offsets = List<int>.filled(count, -1);
  final generations = List<int>.filled(count, 0);
  final inUse = List<bool>.filled(count, false);
  for (var i = 0; i < count; i++) {
    final entryOffset = lexer.pos;
    // Exactly `NNNNNNNNNN GGGGG k \n` as produced by the writer.
    if (entryOffset + 20 > bytes.length) {
      throw PdfFormatException('truncated xref entry $i', entryOffset);
    }
    final offsetField = _parseFixedDigits(bytes, entryOffset, 10, 'xref offset');
    if (bytes[entryOffset + 10] != 0x20 ||
        bytes[entryOffset + 16] != 0x20 ||
        bytes[entryOffset + 18] != 0x20 ||
        bytes[entryOffset + 19] != 0x0a) {
      throw PdfFormatException(
        'malformed xref entry $i separator',
        entryOffset,
      );
    }
    final generation = _parseFixedDigits(
      bytes,
      entryOffset + 11,
      5,
      'xref generation',
    );
    final kind = bytes[entryOffset + 17];
    if (kind != 0x6e && kind != 0x66) {
      throw PdfFormatException('malformed xref entry $i kind', entryOffset);
    }
    offsets[i] = offsetField;
    generations[i] = generation;
    inUse[i] = kind == 0x6e;
    lexer.pos = entryOffset + 20;
  }
  if (inUse[0]) {
    throw PdfFormatException('object 0 must be free', xrefOffset);
  }

  // Trailer.
  lexer.skipWhitespace();
  lexer.expect('trailer');
  final trailer = lexer.parseDict();

  // startxref / %%EOF after the trailer.
  lexer.skipWhitespace();
  lexer.expect('startxref');
  lexer.skipWhitespace();
  final trailerXref = lexer.parseInteger();
  if (trailerXref != xrefOffset) {
    throw PdfFormatException(
      'startxref ($trailerXref) does not match xref offset ($xrefOffset)',
      lexer.pos,
    );
  }
  // `%%EOF` starts with '%', which the comment-aware whitespace skipper would
  // treat as a comment, so only plain whitespace is skipped here.
  lexer.skipPlainWhitespace();
  lexer.expect('%%EOF');
  lexer.skipPlainWhitespace();
  if (lexer.pos != bytes.length) {
    throw PdfFormatException('trailing bytes after %%EOF', lexer.pos);
  }

  // Every in-use entry must point at its own `N 0 obj`.
  final objects = <int, PdfObjectRecord>{};
  for (var id = 1; id < count; id++) {
    if (!inUse[id]) continue;
    final offset = offsets[id];
    if (offset < 0 || offset >= bytes.length) {
      throw PdfFormatException('xref offset for object $id out of range');
    }
    final objLexer = _Lexer(bytes, offset);
    final parsedId = objLexer.parseInteger();
    if (parsedId != id) {
      throw PdfFormatException(
        'xref entry $id points at object $parsedId',
        offset,
      );
    }
    objLexer.skipWhitespace();
    final generation = objLexer.parseInteger();
    if (generation != generations[id]) {
      throw PdfFormatException(
        'xref generation ${generations[id]} mismatches object $id',
        offset,
      );
    }
    objLexer.skipWhitespace();
    objLexer.expect('obj');
    objLexer.skipWhitespace();
    final value = objLexer.parseValue();
    objLexer.skipWhitespace();

    Uint8List? stream;
    if (objLexer.startsWithAscii('stream')) {
      if (value is! Map<String, Object?>) {
        throw PdfFormatException('object $id has a stream but no dict', offset);
      }
      final length = value['Length'];
      if (length is! int) {
        throw PdfFormatException(
          'object $id stream length is not a direct integer',
          offset,
        );
      }
      objLexer.pos += 'stream'.length;
      if (objLexer.startsWithAscii('\r\n')) {
        objLexer.pos += 2;
      } else if (objLexer.startsWithAscii('\n')) {
        objLexer.pos += 1;
      } else {
        throw PdfFormatException('missing EOL after stream', objLexer.pos);
      }
      final dataStart = objLexer.pos;
      if (dataStart + length > bytes.length) {
        throw PdfFormatException('stream of object $id overruns file');
      }
      stream = Uint8List.sublistView(bytes, dataStart, dataStart + length);
      objLexer.pos = dataStart + length;
      if (objLexer.startsWithAscii('\r\n')) {
        objLexer.pos += 2;
      } else if (objLexer.startsWithAscii('\n')) {
        objLexer.pos += 1;
      }
      objLexer.expect('endstream');
      objLexer.skipWhitespace();
    }

    objLexer.expect('endobj');
    objects[id] = PdfObjectRecord(
      id: id,
      offset: offset,
      value: value,
      stream: stream,
      endOffset: objLexer.pos,
    );
  }

  return ParsedPdf(
    bytes: bytes,
    objects: objects,
    trailer: trailer,
    xrefOffset: xrefOffset,
    xrefOffsets: offsets,
    xrefGenerations: generations,
    xrefInUse: inUse,
  );
}

bool _startsWithAscii(Uint8List bytes, int offset, String text) {
  if (offset + text.length > bytes.length) return false;
  for (var i = 0; i < text.length; i++) {
    if (bytes[offset + i] != text.codeUnitAt(i)) return false;
  }
  return true;
}

int _lastIndexOfAscii(Uint8List bytes, String text) {
  final first = text.codeUnitAt(0);
  for (var i = bytes.length - text.length; i >= 0; i--) {
    if (bytes[i] != first) continue;
    if (_startsWithAscii(bytes, i, text)) return i;
  }
  return -1;
}

int _parseFixedDigits(Uint8List bytes, int offset, int count, String what) {
  var value = 0;
  for (var i = 0; i < count; i++) {
    final b = bytes[offset + i];
    if (b < 0x30 || b > 0x39) {
      throw PdfFormatException('non-digit in $what', offset + i);
    }
    value = value * 10 + (b - 0x30);
  }
  return value;
}

bool _isPdfWhitespace(int b) =>
    b == 0x20 || b == 0x09 || b == 0x0a || b == 0x0d || b == 0x0c || b == 0x00;

bool _isPdfDelimiter(int b) =>
    b == 0x28 || // (
    b == 0x29 || // )
    b == 0x3c || // <
    b == 0x3e || // >
    b == 0x5b || // [
    b == 0x5d || // ]
    b == 0x7b || // {
    b == 0x7d || // }
    b == 0x2f || // /
    b == 0x25 || // %
    _isPdfWhitespace(b);

bool _isDigit(int b) => b >= 0x30 && b <= 0x39;

bool _isOctal(int b) => b >= 0x30 && b <= 0x37;

/// Recursive-descent PDF tokenizer for the writer's syntax subset.
class _Lexer {
  _Lexer(this.bytes, this.pos);

  final Uint8List bytes;
  int pos;

  bool get atEnd => pos >= bytes.length;

  bool startsWithAscii(String text) => _startsWithAscii(bytes, pos, text);

  void skipWhitespace() {
    while (!atEnd) {
      final b = bytes[pos];
      if (_isPdfWhitespace(b)) {
        pos++;
      } else if (b == 0x25) {
        while (!atEnd && bytes[pos] != 0x0a && bytes[pos] != 0x0d) pos++;
      } else {
        return;
      }
    }
  }

  /// Like [skipWhitespace] but treats `%` as data (needed for `%%EOF`).
  void skipPlainWhitespace() {
    while (!atEnd && _isPdfWhitespace(bytes[pos])) pos++;
  }

  void expect(String text) {
    if (!startsWithAscii(text)) {
      throw PdfFormatException('expected `$text`', pos);
    }
    pos += text.length;
  }

  int parseInteger() {
    skipWhitespace();
    final start = pos;
    if (!atEnd && (bytes[pos] == 0x2d || bytes[pos] == 0x2b)) pos++;
    while (!atEnd && _isDigit(bytes[pos])) pos++;
    if (pos == start || (pos == start + 1 && !_isDigit(bytes[start]))) {
      throw PdfFormatException('expected integer', start);
    }
    return int.parse(latin1.decode(Uint8List.sublistView(bytes, start, pos)));
  }

  Map<String, Object?> parseDict() {
    skipWhitespace();
    expect('<<');
    final map = <String, Object?>{};
    while (true) {
      skipWhitespace();
      if (atEnd) throw PdfFormatException('unterminated dictionary', pos);
      if (startsWithAscii('>>')) {
        pos += 2;
        return map;
      }
      if (bytes[pos] != 0x2f) {
        throw PdfFormatException('expected name in dictionary', pos);
      }
      final name = parseName();
      skipWhitespace();
      map[name] = parseValue();
    }
  }

  String parseName() {
    expect('/');
    final out = BytesBuilder();
    while (!atEnd && !_isPdfDelimiter(bytes[pos])) {
      var b = bytes[pos++];
      if (b == 0x23) {
        // #xx escape
        if (pos + 2 > bytes.length) {
          throw PdfFormatException('truncated # escape in name', pos);
        }
        final hex = latin1.decode(Uint8List.sublistView(bytes, pos, pos + 2));
        final value = int.tryParse(hex, radix: 16);
        if (value == null) {
          throw PdfFormatException('invalid # escape in name', pos);
        }
        b = value;
        pos += 2;
      }
      out.addByte(b);
    }
    return latin1.decode(out.takeBytes());
  }

  Object? parseValue() {
    skipWhitespace();
    if (atEnd) throw PdfFormatException('unexpected end of file', pos);
    final b = bytes[pos];
    if (b == 0x2f) return parseName();
    if (b == 0x28) return parseLiteralString();
    if (b == 0x3c) {
      if (startsWithAscii('<<')) return parseDict();
      return parseHexString();
    }
    if (b == 0x5b) return parseArray();
    if (_isDigit(b) || b == 0x2d || b == 0x2b || b == 0x2e) {
      return _parseNumberOrRef();
    }
    if (startsWithAscii('true')) {
      pos += 4;
      return true;
    }
    if (startsWithAscii('false')) {
      pos += 5;
      return false;
    }
    if (startsWithAscii('null')) {
      pos += 4;
      return null;
    }
    throw PdfFormatException('unexpected byte 0x${b.toRadixString(16)}', pos);
  }

  List<Object?> parseArray() {
    expect('[');
    final out = <Object?>[];
    while (true) {
      skipWhitespace();
      if (atEnd) throw PdfFormatException('unterminated array', pos);
      if (startsWithAscii(']')) {
        pos += 1;
        return out;
      }
      out.add(parseValue());
    }
  }

  Object? _parseNumberOrRef() {
    final n1 = _parseNumberToken();
    if (n1 is! int) return n1;
    final save = pos;
    skipWhitespace();
    if (!atEnd && _isDigit(bytes[pos])) {
      final n2 = _parseNumberToken();
      if (n2 is int) {
        skipWhitespace();
        if (!atEnd &&
            bytes[pos] == 0x52 && // R
            (pos + 1 >= bytes.length || _isPdfDelimiter(bytes[pos + 1]))) {
          pos += 1;
          return PdfRef(n1);
        }
      }
    }
    pos = save;
    return n1;
  }

  num _parseNumberToken() {
    final start = pos;
    if (!atEnd && (bytes[pos] == 0x2d || bytes[pos] == 0x2b)) pos++;
    var digits = 0;
    while (!atEnd && _isDigit(bytes[pos])) {
      pos++;
      digits++;
    }
    var isReal = false;
    if (!atEnd && bytes[pos] == 0x2e) {
      isReal = true;
      pos++;
      while (!atEnd && _isDigit(bytes[pos])) {
        pos++;
        digits++;
      }
    }
    if (digits == 0) {
      throw PdfFormatException('malformed number', start);
    }
    final text = latin1.decode(Uint8List.sublistView(bytes, start, pos));
    return isReal ? double.parse(text) : int.parse(text);
  }

  String parseLiteralString() {
    expect('(');
    final out = BytesBuilder();
    var depth = 1;
    while (true) {
      if (atEnd) throw PdfFormatException('unterminated string', pos);
      var b = bytes[pos++];
      if (b == 0x5c) {
        if (atEnd) throw PdfFormatException('unterminated escape', pos);
        b = bytes[pos++];
        if (b == 0x6e) {
          out.addByte(0x0a);
        } else if (b == 0x72) {
          out.addByte(0x0d);
        } else if (b == 0x74) {
          out.addByte(0x09);
        } else if (b == 0x62) {
          out.addByte(0x08);
        } else if (b == 0x66) {
          out.addByte(0x0c);
        } else if (b == 0x0a) {
          // Line continuation.
        } else if (b == 0x0d) {
          if (!atEnd && bytes[pos] == 0x0a) pos++;
        } else if (_isOctal(b)) {
          var v = b - 0x30;
          for (var i = 0; i < 2 && !atEnd && _isOctal(bytes[pos]); i++) {
            v = v * 8 + (bytes[pos++] - 0x30);
          }
          out.addByte(v & 0xff);
        } else {
          out.addByte(b);
        }
        continue;
      }
      if (b == 0x28) {
        depth++;
      } else if (b == 0x29) {
        depth--;
        if (depth == 0) break;
      }
      out.addByte(b);
    }
    return _decodePdfStringBytes(out.takeBytes());
  }

  String parseHexString() {
    expect('<');
    final digits = <int>[];
    while (true) {
      if (atEnd) throw PdfFormatException('unterminated hex string', pos);
      final b = bytes[pos++];
      if (b == 0x3e) break;
      if (_isPdfWhitespace(b)) continue;
      final value = _hexDigit(b);
      if (value == null) {
        throw PdfFormatException('invalid hex digit in string', pos - 1);
      }
      digits.add(value);
    }
    if (digits.length.isOdd) digits.add(0);
    final raw = Uint8List(digits.length ~/ 2);
    for (var i = 0; i < raw.length; i++) {
      raw[i] = (digits[i * 2] << 4) | digits[i * 2 + 1];
    }
    return _decodePdfStringBytes(raw);
  }

  int? _hexDigit(int b) {
    if (b >= 0x30 && b <= 0x39) return b - 0x30;
    if (b >= 0x41 && b <= 0x46) return b - 0x41 + 10;
    if (b >= 0x61 && b <= 0x66) return b - 0x61 + 10;
    return null;
  }
}

/// Decodes PDF string bytes: UTF-16BE when the string has a BOM (as the
/// writer emits for non-ASCII), Latin-1 otherwise.
String _decodePdfStringBytes(Uint8List raw) {
  if (raw.length >= 2 && raw[0] == 0xfe && raw[1] == 0xff) {
    final codeUnits = <int>[];
    for (var i = 2; i + 1 < raw.length; i += 2) {
      codeUnits.add((raw[i] << 8) | raw[i + 1]);
    }
    return String.fromCharCodes(codeUnits);
  }
  return latin1.decode(raw);
}
