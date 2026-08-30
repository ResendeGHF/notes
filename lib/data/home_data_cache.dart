// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:saber/components/home/sort_button.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/file_tree_cache.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tags_database.dart';

class HomeDataCache {
  HomeDataCache._();
  static final HomeDataCache instance = HomeDataCache._();

  /// Recent Notes grid target: 10 rows × 7 cards on a typical tablet width.
  static const int maxRecentNotes = 70;

  List<String>? _recent;
  /// Last non-empty recent list kept across [invalidate] so Home can paint
  /// immediately while a reload runs (e.g. after leaving split editor).
  List<String>? _recentStale;
  List<String>? _all;
  /// Full library for Recent Notes: every note, cheap mtime/size, no 70 cap.
  /// Survives [invalidate] so editor saves never blank the Recent grid.
  List<NoteIndexEntry>? _allNotes;
  final Map<String, NoteIndexEntry> _allNotesByPath = {};
  Map<String, Set<String>>? _allTags;
  DirectoryChildren? _browseRoot;
  Map<String, int>? _browseRootFolderCounts;
  int? _browseRootTotalCount;
  List<String>? _browseRootNotes;

  Future<void>? _recentFuture;
  Future<void>? _allFuture;
  Future<void>? _allNotesFuture;
  Future<void>? _browseRootFuture;

  /// Bumped on [invalidate] so in-flight loads can discard stale results.
  int _recentEpoch = 0;
  int _allEpoch = 0;
  int _allNotesEpoch = 0;
  int _browseRootEpoch = 0;

  void preload() {
    getRecentOrLoad();
    getAllNotesOrLoad();
    getAllOrLoad();
    getBrowseRootOrLoad();
    FileTreeCache.instance.preload();
  }

  static String _normalizeNotePath(String path) {
    return FileManager.notePathWithoutExtension(path);
  }

  static List<String> _normalizeNotePaths(Iterable<String> paths) {
    final out = <String>[];
    final seen = <String>{};
    for (final raw in paths) {
      final path = _normalizeNotePath(raw);
      if (path.isEmpty || !seen.add(path)) continue;
      out.add(path);
    }
    return out;
  }

  void invalidate() {
    if (_recent != null && _recent!.isNotEmpty) {
      _recentStale = _normalizeNotePaths(_recent!);
    } else if ((_recentStale == null || _recentStale!.isEmpty) &&
        stows.recentFiles.value.isNotEmpty) {
      _recentStale = _normalizeNotePaths(stows.recentFiles.value);
    }
    _recent = null;
    _all = null;
    _allTags = null;
    // Keep [_allNotes] so Recent never flashes empty on editor save.
    _browseRoot = null;
    _browseRootFolderCounts = null;
    _browseRootTotalCount = null;
    _browseRootNotes = null;
    _recentEpoch++;
    _allEpoch++;
    _browseRootEpoch++;
    _recentFuture = null;
    _allFuture = null;
    _browseRootFuture = null;
    // Soft: keep FileTree stale snapshots so the navbar remounts instantly.
    FileTreeCache.instance.invalidate();
  }

  /// Prefer live cache, then stale-while-revalidate, for instant Home paint.
  List<String>? get recentCached {
    final cached =
        _recent ??
        (_recentStale != null && _recentStale!.isNotEmpty ? _recentStale : null);
    if (cached == null) return null;
    return _normalizeNotePaths(cached);
  }
  List<String>? get allCached => _all;
  List<NoteIndexEntry>? get allNotesCached =>
      _allNotes == null ? null : List<NoteIndexEntry>.from(_allNotes!);
  Map<String, Set<String>>? get allTagsCached => _allTags;
  DirectoryChildren? get browseRootCached => _browseRoot;
  Map<String, int>? get browseRootFolderCountsCached => _browseRootFolderCounts;
  int? get browseRootTotalCountCached => _browseRootTotalCount;
  List<String>? get browseRootNotesCached => _browseRootNotes;

  /// Seeds optimistic recent paths (e.g. notes just left in split view) so
  /// Home can show cards before background saves finish reloading the cache.
  final Set<String> _optimisticRecent = {};

  void rememberRecentPaths(Iterable<String?> paths) {
    final normalized = <String>[];
    final seen = <String>{};
    void addPath(String? raw) {
      if (raw == null || raw.isEmpty) return;
      final path = _normalizeNotePath(raw);
      if (path.isEmpty || !seen.add(path)) return;
      normalized.add(path);
    }

    for (final p in paths) {
      addPath(p);
    }
    if (normalized.isEmpty) return;

    for (final p in normalized) {
      _optimisticRecent.add(p);
    }

    final existing =
        _recent ?? _recentStale ?? List<String>.from(stows.recentFiles.value);
    for (final p in existing) {
      addPath(p);
    }
    final limited =
        normalized.take(HomeDataCache.maxRecentNotes).toList();
    // Publish as live cache so Home can paint the swap immediately.
    _recent = limited;
    _recentStale = limited;
    // Keep prefs warm for cold start / next launch without waiting on reload.
    // Growable: FileManager may removeAt() on this list during vault writes.
    stows.recentFiles.value = limited;
  }

  /// Drops notes from Recent immediately (empty auto-delete, manual delete).
  void forgetRecentPaths(Iterable<String?> paths) {
    final remove = <String>{};
    for (final raw in paths) {
      if (raw == null || raw.isEmpty) continue;
      final path = _normalizeNotePath(raw);
      if (path.isNotEmpty) remove.add(path);
    }
    if (remove.isEmpty) return;

    _optimisticRecent.removeAll(remove);

    List<String> filter(Iterable<String> src) => [
      for (final p in src)
        if (!remove.contains(_normalizeNotePath(p))) p,
    ];

    final current =
        _recent ?? _recentStale ?? List<String>.from(stows.recentFiles.value);
    final next = filter(current);
    _recent = next;
    _recentStale = next;
    stows.recentFiles.value = next;
    for (final p in remove) {
      _removeFromAllNotes(p);
    }
  }

  void upsertNoteIndex(NoteIndexEntry entry) {
    final path = _normalizeNotePath(entry.path);
    if (path.isEmpty) return;
    final stored = path == entry.path
        ? entry
        : NoteIndexEntry(
            path: path,
            modifiedMillis: entry.modifiedMillis,
            sizeBytes: entry.sizeBytes,
          );
    final existingIdx = _allNotes == null
        ? -1
        : _allNotes!.indexWhere((e) => e.path == path);
    _allNotesByPath[path] = stored;
    if (existingIdx >= 0) {
      _allNotes![existingIdx] = stored;
    } else {
      _allNotes ??= [];
      _allNotes!.add(stored);
    }
    if (_all != null && !_all!.contains(path)) {
      _all = [..._all!, path];
    }
  }

  void renameNoteIndex(String fromPath, String toPath) {
    final from = _normalizeNotePath(fromPath);
    final to = _normalizeNotePath(toPath);
    if (from.isEmpty || to.isEmpty || from == to) return;
    final prev = _allNotesByPath[from];
    _removeFromAllNotes(from);
    upsertNoteIndex(
      NoteIndexEntry(
        path: to,
        modifiedMillis:
            prev?.modifiedMillis ?? DateTime.now().millisecondsSinceEpoch,
        sizeBytes: prev?.sizeBytes ?? 0,
      ),
    );
  }

  void removeNoteIndex(String path) {
    final normalized = _normalizeNotePath(path);
    if (normalized.isEmpty) return;
    _removeFromAllNotes(normalized);
  }

  void _removeFromAllNotes(String path) {
    _allNotesByPath.remove(path);
    _allNotes?.removeWhere((e) => e.path == path);
    _all?.remove(path);
  }

  void _setAllNotes(List<NoteIndexEntry> notes) {
    _allNotes = notes;
    _allNotesByPath
      ..clear()
      ..addEntries(notes.map((e) => MapEntry(e.path, e)));
  }

  Future<List<NoteIndexEntry>> getAllNotesOrLoad() async {
    if (_allNotes != null) return List<NoteIndexEntry>.from(_allNotes!);
    while (_allNotes == null) {
      final epoch = _allNotesEpoch;
      _allNotesFuture ??= _loadAllNotes(epoch);
      final future = _allNotesFuture!;
      await future;
      if (_allNotes != null) return List<NoteIndexEntry>.from(_allNotes!);
      if (epoch != _allNotesEpoch) continue;
      break;
    }
    return List<NoteIndexEntry>.from(_allNotes ?? const []);
  }

  /// Replace the all-notes index without clearing first (no empty flash).
  Future<List<NoteIndexEntry>> reloadAllNotes() async {
    final epoch = ++_allNotesEpoch;
    _allNotesFuture = null;
    final notes = await FileManager.getAllNotesWithMeta();
    if (epoch != _allNotesEpoch) {
      return List<NoteIndexEntry>.from(_allNotes ?? notes);
    }
    _setAllNotes(notes);
    return List<NoteIndexEntry>.from(notes);
  }

  Future<void> _loadAllNotes(int epoch) async {
    final notes = await FileManager.getAllNotesWithMeta();
    if (epoch != _allNotesEpoch) return;
    _setAllNotes(notes);
  }

  Future<List<String>> getRecentOrLoad() async {
    if (_recent != null) return _recent!;
    while (_recent == null) {
      final epoch = _recentEpoch;
      _recentFuture ??= _loadRecent(epoch);
      final future = _recentFuture!;
      await future;
      if (_recent != null) return _recent!;
      if (epoch != _recentEpoch) {
        // Invalidated while loading — start a fresh load.
        continue;
      }
      break;
    }
    return _normalizeNotePaths(
      _recent ??
          _recentStale ??
          List<String>.from(stows.recentFiles.value),
    );
  }

  Future<void> _loadRecent(int epoch) async {
    final persistentRecent = _normalizeNotePaths(stows.recentFiles.value);

    // If the cache has fewer than the full recent window, force a cold start.
    // This cures defective caches and helps new / small libraries.
    final needsFullScan =
        persistentRecent.length < HomeDataCache.maxRecentNotes;

    final normalizedPaths = <String>{};

    void normalizeAndAdd(Iterable<String> paths) {
      for (final path in paths) {
        final normalized = _normalizeNotePath(path);
        if (normalized.isNotEmpty) normalizedPaths.add(normalized);
      }
    }

    if (needsFullScan) {
      final allFiles = await FileManager.getAllFiles();
      if (epoch != _recentEpoch) return;
      normalizeAndAdd(allFiles);
    } else {
      final systemRecent = await FileManager.getRecentlyAccessed();
      if (epoch != _recentEpoch) return;
      normalizeAndAdd(systemRecent);
      normalizeAndAdd(persistentRecent);
    }

    final filtered = normalizedPaths.where((file) {
      final name = file.split('/').last;
      return !name.startsWith('.') &&
          !name.startsWith('TmPmP_') &&
          !name.contains('.sbn2.') &&
          !name.endsWith('.sbn2') &&
          !name.endsWith('.sbn');
    }).toList();

    List<String> filesToSort;

    if (needsFullScan) {
      filesToSort = filtered;
    } else {
      filesToSort = [];
      // Only skip the existence check for notes we just seeded as pending
      // writes — not the whole recent prefs list (that kept auto-deleted
      // empty notes on Home after vault remove).
      for (final file in filtered) {
        if (epoch != _recentEpoch) return;
        final pending = _optimisticRecent.contains(file);
        final exists = pending
            ? true
            : await FileManager.doesFileExist('$file.sbn2') ||
                await FileManager.doesFileExist('$file.sbn');
        if (exists) {
          filesToSort.add(file);
          _optimisticRecent.remove(file);
        }
        if (filesToSort.length >= HomeDataCache.maxRecentNotes + 20) break;
      }
    }

    if (epoch != _recentEpoch) return;

    await SortNotes.sortNotes(
      filesToSort,
      context: SortContext.recent,
      forced: true,
    );
    if (epoch != _recentEpoch) return;

    final limitedRecent =
        filesToSort.take(HomeDataCache.maxRecentNotes).toList();

    // Transient empty results are common while split-editor saves rewrite
    // vault entries — keep a known-good list only while optimistic writes
    // are still pending. Otherwise empty means empty (auto-deleted notes).
    if (limitedRecent.isEmpty) {
      if (_optimisticRecent.isNotEmpty) {
        final fallback = _normalizeNotePaths(
          (_recentStale != null && _recentStale!.isNotEmpty)
              ? _recentStale!
              : persistentRecent,
        );
        if (fallback.isNotEmpty) {
          _recent = fallback;
          return;
        }
      }
      _recent = const [];
      _recentStale = const [];
      if (persistentRecent.isNotEmpty) {
        stows.recentFiles.value = const [];
      }
      return;
    }

    stows.recentFiles.value = limitedRecent;
    _recent = limitedRecent;
    _recentStale = limitedRecent;
  }

  Future<List<String>> getAllOrLoad() async {
    if (_all != null) return _all!;
    while (_all == null) {
      final epoch = _allEpoch;
      _allFuture ??= _loadAll(epoch);
      final future = _allFuture!;
      await future;
      if (_all != null) return _all!;
      if (epoch != _allEpoch) continue;
      break;
    }
    return _all ?? [];
  }

  Future<void> _loadAll(int epoch) async {
    final children = await FileManager.getAllFiles();
    if (epoch != _allEpoch) return;
    if (children.isEmpty) {
      _all = [];
      _allTags = {};
      return;
    }
    final filtered = children.where((file) {
      final name = file.split('/').last;
      return !name.startsWith('.') &&
          !name.startsWith('TmPmP_') &&
          !name.contains('.sbn2.');
    }).toList();
    await SortNotes.sortNotes(
      filtered,
      context: SortContext.search,
      forced: true,
    );
    if (epoch != _allEpoch) return;
    _all = filtered;
    _allTags = await TagDatabase.instance.getTagsForPaths(filtered);
  }

  Future<Map<String, Set<String>>> getAllTagsOrLoad() async {
    if (_allTags != null) return _allTags!;
    await getAllOrLoad();
    return _allTags ?? {};
  }

  Future<BrowseRootData> getBrowseRootOrLoad() async {
    if (_browseRoot != null) {
      return BrowseRootData(
        children: _browseRoot!,
        folderCounts: _browseRootFolderCounts ?? {},
        totalCount: _browseRootTotalCount ?? 0,
        notes: _browseRootNotes ?? [],
      );
    }
    while (_browseRoot == null) {
      final epoch = _browseRootEpoch;
      _browseRootFuture ??= _loadBrowseRoot(epoch);
      final future = _browseRootFuture!;
      await future;
      if (_browseRoot != null) break;
      if (epoch != _browseRootEpoch) continue;
      break;
    }

    if (_browseRoot == null) {
      return BrowseRootData(
        children: DirectoryChildren([], []),
        folderCounts: {},
        totalCount: 0,
        notes: [],
      );
    }
    return BrowseRootData(
      children: _browseRoot!,
      folderCounts: _browseRootFolderCounts ?? {},
      totalCount: _browseRootTotalCount ?? 0,
      notes: _browseRootNotes ?? [],
    );
  }

  Future<void> _loadBrowseRoot(int epoch) async {
    final rawChildren = await FileManager.getChildrenOfDirectory('/');
    if (epoch != _browseRootEpoch) return;
    if (rawChildren == null) {
      _browseRoot = DirectoryChildren([], []);
      _browseRootFolderCounts = {};
      _browseRootTotalCount = 0;
      _browseRootNotes = [];
      return;
    }
    var filteredDirs = rawChildren.directories
        .where((d) => !d.startsWith('.'))
        .toList();
    final filteredFiles = rawChildren.files.where((f) {
      return !f.startsWith('.') &&
          !f.startsWith('TmPmP_') &&
          !f.contains('.sbn2.');
    }).toList();

    try {
      final orderFile = '/.folder_order';
      final bytes = await FileManager.readFile(orderFile, suppressLogs: true);
      if (epoch != _browseRootEpoch) return;
      if (bytes != null) {
        final savedOrder = List<String>.from(jsonDecode(utf8.decode(bytes)));
        final sortedDirs = <String>[];
        final dirSet = filteredDirs.toSet();
        for (final name in savedOrder) {
          if (dirSet.contains(name)) {
            sortedDirs.add(name);
            dirSet.remove(name);
          }
        }
        sortedDirs.addAll(dirSet);
        filteredDirs = sortedDirs;
      }
    } catch (_) {}

    if (epoch != _browseRootEpoch) return;

    _browseRoot = DirectoryChildren(filteredDirs, filteredFiles);
    final folderPaths = [
      for (final folderName in filteredDirs) '/$folderName',
    ];
    final countResults = await Future.wait([
      FileManager.getFolderFileCountsBatch(folderPaths),
      FileManager.getTotalFileCount(),
    ]);
    if (epoch != _browseRootEpoch) return;
    _browseRootFolderCounts = countResults[0] as Map<String, int>;
    _browseRootTotalCount = countResults[1] as int;
    _browseRootNotes = [for (final filePath in filteredFiles) '/$filePath'];
    await SortNotes.sortNotes(
      _browseRootNotes!,
      context: SortContext.browse,
      forced: true,
    );
  }
}

class BrowseRootData {
  final DirectoryChildren children;
  final Map<String, int> folderCounts;
  final int totalCount;
  final List<String> notes;

  BrowseRootData({
    required this.children,
    required this.folderCounts,
    required this.totalCount,
    required this.notes,
  });
}
