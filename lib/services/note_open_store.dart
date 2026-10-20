// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:saber/data/editor/note_page_index.dart';

/// One inflated note body kept in the Dart heap.
///
/// The whole body is read, inflated and fingerprinted in a background isolate
/// ([Isolate.run]) when the note is opened, then stays resident. Page slices
/// are zero-copy views, so hydrating a page never crosses the platform channel
/// and never copies megabytes on the UI isolate. That matters during the first
/// seconds after open: a pan hydrates several dense pages, and each channel
/// round trip used to encode/copy the page bytes on the UI thread right in the
/// middle of the gesture.
class NoteBodySession {
  NoteBodySession._(this._body, this.sampleHash);

  final Uint8List _body;

  /// Cheap fingerprint of the decompressed body (matches
  /// [NotePageIndex.sampleHash], which the `.nix` sidecar was built with).
  final int sampleHash;

  int get length => _body.length;

  /// Zero-copy view of `[start, end)` into the resident body.
  Uint8List view(int start, int end) => Uint8List.sublistView(_body, start, end);

  /// The full resident body. Lazy page loading keeps this so every page slice
  /// is a view instead of an async copy.
  Uint8List get body => _body;

  Future<Uint8List> slice(int start, int end) async => view(start, end);

  /// The bytes are owned by the Dart heap (and possibly the reopen cache), so
  /// closing a session never has to free native memory.
  Future<void> close() async {}
}

/// Reads one note body in a background isolate.
///
/// Must stay a top-level function: [Isolate.run] sends the closure to a fresh
/// isolate, and only sendable state may cross. Returns
/// `[TransferableTypedData, sampleHash]` so the inflated bytes move back
/// without a copy.
List<Object?> _readBodyIsolate(String path) {
  final raw = File(path).readAsBytesSync();
  final body = _inflateNoteBody(raw);
  return <Object?>[
    TransferableTypedData.fromList(<Uint8List>[body]),
    NotePageIndex.sampleHash(body),
  ];
}

/// `.sbn2` bodies are zlib streams. Mirrors the previous Kotlin store: only
/// inflate when the stream looks like zlib, and fall back to the raw bytes on
/// any error (some imported notes are stored uncompressed).
Uint8List _inflateNoteBody(Uint8List raw) {
  if (raw.length < 2 || raw[0] != 0x78) return raw;
  try {
    final out = ZLibDecoder().convert(raw);
    if (out.isEmpty) return raw;
    return out is Uint8List ? out : Uint8List.fromList(out);
  } catch (_) {
    return raw;
  }
}

class _CachedBody {
  _CachedBody({
    required this.session,
    required this.fileLength,
    required this.fileModifiedMs,
  });

  final NoteBodySession session;

  /// Compressed file size/mtime used to detect edits between opens.
  final int fileLength;
  final int fileModifiedMs;

  int lastUse = 0;

  int get bytes => session.length;
}

/// In-memory note bodies.
///
/// Opening a note used to read + inflate the file natively and then copy every
/// page across a `MethodChannel`. Both are gone: the body is read and inflated
/// in a Dart isolate and kept resident, so reopening the same note (home →
/// note → back → note) skips the read entirely, and page slices are views.
abstract final class NoteOpenStore {
  /// Reopen cache. Bounded by entry count and total inflated bytes so a large
  /// note cannot pin tens of megabytes per opened file.
  static final Map<String, _CachedBody> _cache = <String, _CachedBody>{};
  static int _useCounter = 0;
  static const int _kMaxCachedEntries = 2;
  static const int _kMaxCachedBytes = 48 * 1024 * 1024;
  static const int _kMaxCacheableBodyBytes = 32 * 1024 * 1024;

  static Future<NoteBodySession?> open(String path) async {
    if (kIsWeb || path.isEmpty) return null;
    if (!Platform.isAndroid) return null;
    final stamp = _stamp(path);
    if (stamp == null) return null;
    final cached = _cache[path];
    if (cached != null &&
        cached.fileLength == stamp.size &&
        cached.fileModifiedMs == stamp.modifiedMs) {
      cached.lastUse = ++_useCounter;
      return cached.session;
    }
    try {
      final result = await Isolate.run(() => _readBodyIsolate(path));
      final data = result[0] as TransferableTypedData;
      final hash = result[1] as int;
      final body = data.materialize().asUint8List();
      final session = NoteBodySession._(body, hash);
      if (body.length <= _kMaxCacheableBodyBytes) {
        _cache[path] = _CachedBody(
          session: session,
          fileLength: stamp.size,
          fileModifiedMs: stamp.modifiedMs,
        )..lastUse = ++_useCounter;
        _trimCache();
      }
      return session;
    } catch (_) {
      return null;
    }
  }

  /// Drops [path]'s cached body (e.g. after a save rewrote the file).
  ///
  /// Normally unnecessary: [open] revalidates size/mtime against the file, so
  /// a rewritten note misses the cache on its own. Kept for callers that know
  /// a write happened in the same millisecond the stamp could not capture.
  static void invalidate(String path) {
    _cache.remove(path);
  }

  @visibleForTesting
  static void debugClearCache() {
    _cache.clear();
  }

  @visibleForTesting
  static int get debugCacheEntryCount => _cache.length;

  static ({int size, int modifiedMs})? _stamp(String path) {
    try {
      final stat = File(path).statSync();
      if (stat.type == FileSystemEntityType.notFound) return null;
      return (
        size: stat.size,
        modifiedMs: stat.modified.millisecondsSinceEpoch,
      );
    } catch (_) {
      return null;
    }
  }

  static void _trimCache() {
    if (_cache.length <= _kMaxCachedEntries) {
      var total = 0;
      for (final entry in _cache.values) {
        total += entry.bytes;
      }
      if (total <= _kMaxCachedBytes) return;
    }
    final entries = _cache.entries.toList()
      ..sort((a, b) => a.value.lastUse.compareTo(b.value.lastUse));
    var total = entries.fold<int>(0, (sum, e) => sum + e.value.bytes);
    for (final entry in entries) {
      if (_cache.length <= _kMaxCachedEntries && total <= _kMaxCachedBytes) {
        break;
      }
      _cache.remove(entry.key);
      total -= entry.value.bytes;
    }
  }
}
