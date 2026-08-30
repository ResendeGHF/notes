// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:saber/pages/editor/editor.dart';

class ThumbnailCache {
  ThumbnailCache._();
  static final ThumbnailCache instance = ThumbnailCache._();

  /// Vault decrypts are expensive; keep more cards warm through fling.
  static const int _maxEntries = 220;
  static const int _maxBytes = 48 * 1024 * 1024;

  /// Cap concurrent `.p` vault reads so fling does not stampede decrypt workers.
  static const int _maxInflightLoads = 4;

  final LinkedHashMap<String, _CacheEntry> _cache = LinkedHashMap();
  int _totalBytes = 0;

  final Map<String, Future<Uint8List?>> _inflight = {};
  var _activeLoads = 0;
  final List<void Function()> _waitQueue = [];

  Uint8List? get(String path) {
    final key = _key(path);
    final entry = _cache[key];
    if (entry == null) return null;
    _cache.remove(key);
    _cache[key] = entry;
    return entry.bytes;
  }

  void put(String path, Uint8List bytes) {
    if (bytes.isEmpty) return;
    final key = _key(path);
    if (_cache.containsKey(key)) {
      _totalBytes -= _cache[key]!.bytes.length;
      _cache.remove(key);
    }
    _evictIfNeeded(bytes.length);
    _cache[key] = _CacheEntry(bytes);
    _totalBytes += bytes.length;
  }

  /// Coalesces and throttles [loader] so remounted cards share one decrypt.
  Future<Uint8List?> load(
    String path,
    Future<Uint8List?> Function() loader,
  ) {
    final key = _key(path);
    final cached = get(path);
    if (cached != null) return Future<Uint8List?>.value(cached);

    final existing = _inflight[key];
    if (existing != null) return existing;

    final future = _runThrottled(() async {
      final again = get(path);
      if (again != null) return again;
      final bytes = await loader();
      if (bytes != null && bytes.isNotEmpty) {
        put(path, bytes);
      }
      return bytes;
    });
    _inflight[key] = future;
    future.whenComplete(() {
      if (identical(_inflight[key], future)) {
        _inflight.remove(key);
      }
    });
    return future;
  }

  Future<T> _runThrottled<T>(Future<T> Function() work) async {
    if (_activeLoads >= _maxInflightLoads) {
      final gate = Completer<void>();
      _waitQueue.add(gate.complete);
      await gate.future;
    }
    _activeLoads++;
    try {
      return await work();
    } finally {
      _activeLoads--;
      if (_waitQueue.isNotEmpty) {
        _waitQueue.removeAt(0)();
      }
    }
  }

  String _key(String path) {
    return path.endsWith(Editor.extension) ? path : '$path${Editor.extension}.p';
  }

  void _evictIfNeeded(int incomingSize) {
    while (_cache.isNotEmpty &&
        (_cache.length >= _maxEntries ||
            _totalBytes + incomingSize > _maxBytes)) {
      final first = _cache.keys.first;
      final entry = _cache.remove(first)!;
      _totalBytes -= entry.bytes.length;
    }
  }

  void invalidate(String path) {
    final key = _key(path);
    final entry = _cache.remove(key);
    if (entry != null) _totalBytes -= entry.bytes.length;
  }

  void clear() {
    _cache.clear();
    _totalBytes = 0;
  }
}

class _CacheEntry {
  final Uint8List bytes;
  _CacheEntry(this.bytes);
}
