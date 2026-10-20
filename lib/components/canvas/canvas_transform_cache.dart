// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart';

/// Remembers the last viewport transform per note so reopening (or
/// switching back to a tab) restores scroll/zoom instantly. Tiny LRU of
/// immutable matrices; cheap enough to cover many open tabs.
@visibleForTesting
class CanvasTransformCache {
  // Large enough that tab switching across many notes still hits.
  static const _maxCacheSize = 32;
  static final _cache = LinkedList<CanvasTransformCacheItem>();

  CanvasTransformCache._();

  static void add(
    String filePath,
    Matrix4 transform, {
    int? pageIndex,
    int? pageIndexEnd,
  }) {
    for (final entry in _cache) {
      if (entry.filePath != filePath) continue;
      entry.unlink();
      break;
    }
    _cache.add(
      CanvasTransformCacheItem(filePath, transform, pageIndex, pageIndexEnd),
    );

    if (_cache.length > _maxCacheSize) {
      _cache.first.unlink();
    }
  }

  static CanvasTransformCacheItem? get(String filePath) {
    try {
      return _cache.firstWhere((item) => item.filePath == filePath);
    } on StateError {
      return null;
    }
  }

  @visibleForTesting
  static void clear() {
    _cache.clear();
  }
}

@visibleForTesting
base class CanvasTransformCacheItem
    extends LinkedListEntry<CanvasTransformCacheItem> {
  final String filePath;
  final Matrix4 transform;

  /// Page indices visible when the transform was saved (inclusive), when
  /// known. Used to eager-parse the restored pages on the next open.
  final int? pageIndex;
  final int? pageIndexEnd;

  CanvasTransformCacheItem(
    this.filePath,
    this.transform, [
    this.pageIndex,
    this.pageIndexEnd,
  ]);
}
