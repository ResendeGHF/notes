// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/tags_database.dart';
import 'package:saber/components/home/sort_button.dart';

class HomeDataCache {
  HomeDataCache._();
  static final HomeDataCache instance = HomeDataCache._();

  List<String>? _recent;
  List<String>? _all;
  Map<String, Set<String>>? _allTags;
  DirectoryChildren? _browseRoot;
  Map<String, int>? _browseRootFolderCounts;
  int? _browseRootTotalCount;
  List<String>? _browseRootNotes;

  Future<void>? _recentFuture;
  Future<void>? _allFuture;
  Future<void>? _browseRootFuture;

  void preload() {
    getRecentOrLoad();
    getAllOrLoad();
    getBrowseRootOrLoad();
  }

  void invalidate() {
    _recent = null;
    _all = null;
    _allTags = null;
    _browseRoot = null;
    _browseRootFolderCounts = null;
    _browseRootTotalCount = null;
    _browseRootNotes = null;
    _recentFuture = null;
    _allFuture = null;
    _browseRootFuture = null;
  }

  List<String>? get recentCached => _recent;
  List<String>? get allCached => _all;
  Map<String, Set<String>>? get allTagsCached => _allTags;
  DirectoryChildren? get browseRootCached => _browseRoot;
  Map<String, int>? get browseRootFolderCountsCached => _browseRootFolderCounts;
  int? get browseRootTotalCountCached => _browseRootTotalCount;
  List<String>? get browseRootNotesCached => _browseRootNotes;

  Future<List<String>> getRecentOrLoad() async {
    if (_recent != null) return _recent!;
    _recentFuture ??= _loadRecent();
    await _recentFuture;
    return _recent ?? [];
  }

  Future<void> _loadRecent() async {
    final children = await FileManager.getRecentlyAccessed();
    if (children.isEmpty) {
      _recent = [];
      return;
    }
    final filtered = children.where((file) {
      final name = file.split('/').last;
      return !name.startsWith('.') &&
          !name.startsWith('TmPmP_') &&
          !name.contains('.sbn2.');
    }).toList();
    await SortNotes.sortNotes(filtered, context: SortContext.recent, forced: true);
    _recent = filtered;
  }

  Future<List<String>> getAllOrLoad() async {
    if (_all != null) return _all!;
    _allFuture ??= _loadAll();
    await _allFuture;
    return _all ?? [];
  }

  Future<void> _loadAll() async {
    final children = await FileManager.getAllFiles();
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
    await SortNotes.sortNotes(filtered, context: SortContext.search, forced: true);
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
    _browseRootFuture ??= _loadBrowseRoot();
    await _browseRootFuture;

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

  Future<void> _loadBrowseRoot() async {
    final rawChildren =
        await FileManager.getChildrenOfDirectory('/');
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

    _browseRoot = DirectoryChildren(filteredDirs, filteredFiles);
    final folderPaths = [
      for (final folderName in filteredDirs) '/$folderName',
    ];
    final countResults = await Future.wait([
      FileManager.getFolderFileCountsBatch(folderPaths),
      FileManager.getTotalFileCount(),
    ]);
    _browseRootFolderCounts = countResults[0] as Map<String, int>;
    _browseRootTotalCount = countResults[1] as int;
    _browseRootNotes = [
      for (final filePath in filteredFiles) '/$filePath',
    ];
    await SortNotes.sortNotes(_browseRootNotes!, context: SortContext.browse, forced: true);
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
