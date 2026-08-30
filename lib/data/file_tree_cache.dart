// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:saber/data/file_manager/file_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shared cache for the navbar [FileTree].
///
/// Keeps last-known directory listings across remounts / [invalidate] so the
/// tree can paint immediately when returning from the editor, then refresh in
/// the background (same stale-while-revalidate pattern as [HomeDataCache]).
class FileTreeCache {
  FileTreeCache._();
  static final FileTreeCache instance = FileTreeCache._();

  final Map<String, DirectoryChildren> _live = {};
  final Map<String, DirectoryChildren> _stale = {};
  final Map<String, Future<DirectoryChildren?>> _inflight = {};

  final Map<String, Map<String, String>> _linksLive = {};
  final Map<String, Map<String, String>> _linksStale = {};
  final Map<String, Future<Map<String, String>>> _linksInflight = {};

  Map<String, bool>? _expandedPrefs;
  Future<Map<String, bool>>? _expandedPrefsFuture;

  static String normalizePath(String path) {
    var normalized = path.replaceAll('\\', '/');
    if (normalized.isEmpty) normalized = '/';
    if (!normalized.startsWith('/')) normalized = '/$normalized';
    if (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  /// Instant peek for UI paint (live, else stale).
  DirectoryChildren? peekChildren(String path) {
    final key = normalizePath(path);
    return _live[key] ?? _stale[key];
  }

  Map<String, String>? peekLinks(String path) {
    final key = normalizePath(path);
    return _linksLive[key] ?? _linksStale[key];
  }

  bool? peekExpanded(String path) {
    final prefs = _expandedPrefs;
    if (prefs == null) return null;
    return prefs['tree_expanded_${normalizePath(path)}'] ?? false;
  }

  void preload() {
    unawaited(getChildren('/'));
    unawaited(getLinks('/'));
    unawaited(loadExpandedPrefs());
  }

  /// Soft invalidate: keep stale snapshots for instant remount paint.
  void invalidate({String? path}) {
    if (path != null) {
      final key = normalizePath(path);
      final children = _live.remove(key);
      if (children != null) _stale[key] = children;
      _inflight.remove(key);
      final links = _linksLive.remove(key);
      if (links != null) _linksStale[key] = links;
      _linksInflight.remove(key);
      return;
    }
    for (final entry in _live.entries) {
      _stale[entry.key] = entry.value;
    }
    _live.clear();
    _inflight.clear();
    for (final entry in _linksLive.entries) {
      _linksStale[entry.key] = entry.value;
    }
    _linksLive.clear();
    _linksInflight.clear();
  }

  /// Invalidate the parent folder of [filePath] (and root when needed).
  void invalidateForFileEvent(String filePath) {
    final normalized = normalizePath(filePath);
    if (normalized == '/') {
      invalidate(path: '/');
      return;
    }
    final parts = normalized.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) {
      invalidate(path: '/');
      return;
    }
    // Parent of the file/folder that changed.
    if (parts.length == 1) {
      invalidate(path: '/');
    } else {
      final parent = '/${parts.sublist(0, parts.length - 1).join('/')}';
      invalidate(path: parent);
      // Root listing may also need a refresh when a top-level child appears.
      if (parts.length == 2) invalidate(path: '/');
    }
  }

  Future<DirectoryChildren?> getChildren(String path) {
    final key = normalizePath(path);
    final live = _live[key];
    if (live != null) return Future.value(live);

    return _inflight.putIfAbsent(key, () async {
      try {
        final children = await FileManager.getChildrenOfDirectory(key);
        if (children != null) {
          _live[key] = children;
          _stale[key] = children;
        }
        return children;
      } finally {
        _inflight.remove(key);
      }
    });
  }

  /// Force a fresh listing even if live cache is warm (background refresh).
  Future<DirectoryChildren?> refreshChildren(String path) async {
    final key = normalizePath(path);
    _inflight.remove(key);
    final previous = _live.remove(key);
    if (previous != null) _stale[key] = previous;
    return getChildren(key);
  }

  Future<Map<String, String>> getLinks(String path) {
    final key = normalizePath(path);
    final live = _linksLive[key];
    if (live != null) return Future.value(live);

    return _linksInflight.putIfAbsent(key, () async {
      try {
        final links = await FolderLinkManager.getLinks(key);
        _linksLive[key] = links;
        _linksStale[key] = links;
        return links;
      } finally {
        _linksInflight.remove(key);
      }
    });
  }

  Future<Map<String, String>> refreshLinks(String path) async {
    final key = normalizePath(path);
    _linksInflight.remove(key);
    final previous = _linksLive.remove(key);
    if (previous != null) _linksStale[key] = previous;
    return getLinks(key);
  }

  Future<Map<String, bool>> loadExpandedPrefs() {
    final cached = _expandedPrefs;
    if (cached != null) return Future.value(cached);
    return _expandedPrefsFuture ??= () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final out = <String, bool>{};
        for (final key in prefs.getKeys()) {
          if (!key.startsWith('tree_expanded_')) continue;
          out[key] = prefs.getBool(key) ?? false;
        }
        _expandedPrefs = out;
        return out;
      } catch (_) {
        _expandedPrefs = {};
        return _expandedPrefs!;
      } finally {
        _expandedPrefsFuture = null;
      }
    }();
  }

  Future<void> setExpanded(String path, bool expanded) async {
    final key = 'tree_expanded_${normalizePath(path)}';
    _expandedPrefs ??= {};
    if (expanded) {
      _expandedPrefs![key] = true;
    } else {
      _expandedPrefs!.remove(key);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (expanded) {
        await prefs.setBool(key, true);
      } else {
        await prefs.remove(key);
      }
    } catch (_) {}
  }
}
