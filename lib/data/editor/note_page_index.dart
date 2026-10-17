// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';

/// One page body inside a decompressed `.sbn2` buffer.
class NotePageSpan {
  const NotePageSpan({
    required this.start,
    required this.end,
    required this.width,
    required this.height,
    required this.id,
  });

  final int start;
  final int end;
  final double width;
  final double height;

  /// Null when the page was saved without an id.
  final int? id;

  int get length => end - start;
}

/// Byte ranges of every page in a note body. Built off the UI isolate (or
/// loaded from the `.nix` sidecar) so opening a note does not walk every
/// stroke on the platform thread.
class NotePageDirectory {
  const NotePageDirectory({
    required this.sampleHash,
    required this.spans,
  });

  /// Cheap fingerprint of the decompressed body. A full cryptographic hash
  /// would rescan tens of megabytes on the UI isolate just to trust the sidecar.
  final int sampleHash;
  final List<NotePageSpan> spans;

  int get pageCount => spans.length;

  bool structurallyValid(Uint8List body) {
    if (spans.isEmpty) return false;
    if (sampleHash != NotePageIndex.sampleHash(body)) return false;
    var cursor = spans.first.start;
    if (cursor < 0 || cursor >= body.length) return false;
    for (final span in spans) {
      if (span.start != cursor) return false;
      if (span.end <= span.start || span.end > body.length) return false;
      if (span.width <= 0 || span.height <= 0) return false;
      // Page bodies always start with the version key.
      if (body[span.start] != 1) return false;
      cursor = span.end;
    }
    return true;
  }
}

/// Sidecar `${note}.sbn2.nix` — page offsets for the decompressed body.
abstract final class NotePageIndex {
  static final _log = Logger('NotePageIndex');

  static const _magic = 0x314E4958; // 'XIN1' little-endian of ASCII NIX1
  static const _version = 1;

  static String sidecarPath(String noteBodyPath) => '$noteBodyPath.nix';

  /// Stride-64 mix plus the last byte. Stable across endianness.
  static int sampleHash(Uint8List body) {
    var h = body.length & 0x7fffffff;
    final n = body.length;
    var i = 0;
    while (i < n) {
      h = 0x1fffffff & (h * 131 + body[i]);
      i += 64;
    }
    if (n > 0) {
      h = 0x1fffffff & (h * 131 + body[n - 1]);
    }
    return h;
  }

  static Uint8List encode(NotePageDirectory directory) {
    final spans = directory.spans;
    final data = ByteData(16 + spans.length * 24);
    var o = 0;
    data.setUint32(o, _magic, Endian.little);
    o += 4;
    data.setUint16(o, _version, Endian.little);
    o += 2;
    data.setUint16(o, spans.length, Endian.little);
    o += 2;
    data.setUint32(o, directory.sampleHash, Endian.little);
    o += 4;
    data.setUint32(o, 0, Endian.little);
    o += 4;
    for (final span in spans) {
      data.setUint32(o, span.start, Endian.little);
      data.setUint32(o + 4, span.end, Endian.little);
      data.setInt32(o + 8, (span.width * 1000).round(), Endian.little);
      data.setInt32(o + 12, (span.height * 1000).round(), Endian.little);
      data.setInt32(o + 16, span.id ?? -1, Endian.little);
      data.setUint32(o + 20, 0, Endian.little);
      o += 24;
    }
    return data.buffer.asUint8List();
  }

  static NotePageDirectory? decode(Uint8List bytes) {
    if (bytes.length < 16) return null;
    final data = ByteData.sublistView(bytes);
    if (data.getUint32(0, Endian.little) != _magic) return null;
    if (data.getUint16(4, Endian.little) != _version) return null;
    final count = data.getUint16(6, Endian.little);
    if (bytes.length < 16 + count * 24) return null;
    final hash = data.getUint32(8, Endian.little);
    final spans = <NotePageSpan>[];
    var o = 16;
    for (var i = 0; i < count; i++) {
      final start = data.getUint32(o, Endian.little);
      final end = data.getUint32(o + 4, Endian.little);
      final width = data.getInt32(o + 8, Endian.little) / 1000.0;
      final height = data.getInt32(o + 12, Endian.little) / 1000.0;
      final idRaw = data.getInt32(o + 16, Endian.little);
      spans.add(
        NotePageSpan(
          start: start,
          end: end,
          width: width,
          height: height,
          id: idRaw >= 0 ? idRaw : null,
        ),
      );
      o += 24;
    }
    return NotePageDirectory(sampleHash: hash, spans: spans);
  }

  /// Sidecar trusted when [sampleHash] and [bodyLength] match, without
  /// pulling the note body into the Dart heap.
  static NotePageDirectory? tryLoadMatching(
    String noteBodyPath,
    int sampleHash,
    int bodyLength,
  ) {
    try {
      final file = File(sidecarPath(noteBodyPath));
      if (!file.existsSync()) return null;
      final decoded = decode(file.readAsBytesSync());
      if (decoded == null || decoded.sampleHash != sampleHash) return null;
      if (decoded.spans.isEmpty) return null;
      var cursor = decoded.spans.first.start;
      if (cursor < 0 || cursor >= bodyLength) return null;
      for (final span in decoded.spans) {
        if (span.start != cursor || span.end <= span.start || span.end > bodyLength) {
          return null;
        }
        if (span.width <= 0 || span.height <= 0) return null;
        cursor = span.end;
      }
      return decoded;
    } catch (e) {
      _log.fine('Page index ignored: $e');
      return null;
    }
  }

  /// Returns a directory only when the sidecar still describes [body].
  static NotePageDirectory? tryLoad(String noteBodyPath, Uint8List body) {
    try {
      final file = File(sidecarPath(noteBodyPath));
      if (!file.existsSync()) return null;
      final decoded = decode(file.readAsBytesSync());
      if (decoded == null || !decoded.structurallyValid(body)) return null;
      return decoded;
    } catch (e) {
      _log.fine('Page index ignored: $e');
      return null;
    }
  }

  static Future<void> store(
    String noteBodyPath,
    NotePageDirectory directory,
  ) async {
    final file = File(sidecarPath(noteBodyPath));
    final tmp = File('${file.path}.tmp');
    try {
      await tmp.writeAsBytes(encode(directory), flush: true);
      if (file.existsSync()) {
        await file.delete();
      }
      await tmp.rename(file.path);
    } catch (e) {
      _log.fine('Page index write skipped: $e');
      try {
        if (tmp.existsSync()) await tmp.delete();
      } catch (_) {}
    }
  }
}
