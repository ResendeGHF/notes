// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:collection';
import 'dart:typed_data';

import 'package:saber/pages/editor/editor.dart';

class ThumbnailCache {
  ThumbnailCache._();
  static final ThumbnailCache instance = ThumbnailCache._();

  static const int _maxEntries = 80;
  static const int _maxBytes = 12 * 1024 * 1024;

  final LinkedHashMap<String, _CacheEntry> _cache = LinkedHashMap();
  int _totalBytes = 0;

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

  String _key(String path) {
    return path.endsWith(Editor.extension) ? path : '$path${Editor.extension}.p';
  }

  void _evictIfNeeded(int incomingSize) {
    while (_cache.isNotEmpty &&
        (_cache.length >= _maxEntries || _totalBytes + incomingSize > _maxBytes)) {
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
