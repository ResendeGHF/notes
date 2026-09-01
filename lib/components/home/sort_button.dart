// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:saber/components/home/home_toolbar_chrome.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

enum SortContext { browse, recent, search }

class SortOverride {
  SortOverride({
    this.functionIdx = 1,
    this.increasing = false,
  });

  /// 0 alphabetical, 1 last modified, 2 size.
  int functionIdx;
  bool increasing;

  static const recentDefaultFunctionIdx = 1;
  static const recentDefaultIncreasing = false;

  void resetToRecentDefault() {
    functionIdx = recentDefaultFunctionIdx;
    increasing = recentDefaultIncreasing;
  }
}

class SortNotes {
  SortNotes._();

  static final List<Future<void> Function(List<String>, bool)> _sortFunctions =
      [_sortNotesAlpha, _sortNotesLastModified, _sortNotesSize];

  static bool _isNeeded = true;
  static bool get isNeeded => _isNeeded;

  static int _getSortFunctionIdx(SortContext context) {
    return switch (context) {
      SortContext.browse ||
      SortContext.search => stows.browseSortFunctionIdx.value,
      SortContext.recent => stows.recentSortFunctionIdx.value,
    };
  }

  static void _setSortFunctionIdx(SortContext context, int value) {
    switch (context) {
      case SortContext.browse || SortContext.search:
        stows.browseSortFunctionIdx.value = value;
        break;
      case SortContext.recent:
        stows.recentSortFunctionIdx.value = value;
        break;
    }
    _isNeeded = true;
  }

  static bool _getIsIncreasingOrder(SortContext context) {
    return switch (context) {
      SortContext.browse ||
      SortContext.search => stows.browseIsSortIncreasing.value,
      SortContext.recent => stows.recentIsSortIncreasing.value,
    };
  }

  static void _setIsIncreasingOrder(SortContext context, bool value) {
    switch (context) {
      case SortContext.browse || SortContext.search:
        stows.browseIsSortIncreasing.value = value;
        break;
      case SortContext.recent:
        stows.recentIsSortIncreasing.value = value;
        break;
    }
    _isNeeded = true;
  }

  static void _reverse(List<String> list) {
    final n = list.length;
    for (int i = 0; i < n / 2; i++) {
      final tmp = list[i];
      list[i] = list[n - i - 1];
      list[n - i - 1] = tmp;
    }
  }

  static Future<void> sortNotes(
    List<String> filePaths, {
    required SortContext context,
    bool forced = false,
    SortOverride? override,
  }) async {
    if (override != null || _isNeeded || forced) {
      final idx = override?.functionIdx ?? _getSortFunctionIdx(context);
      final increasing = override?.increasing ?? _getIsIncreasingOrder(context);
      await _sortFunctions[idx.clamp(0, _sortFunctions.length - 1)].call(
        filePaths,
        increasing,
      );
      if (override == null) _isNeeded = false;
    }
  }

  static void sortNoteIndex(List<NoteIndexEntry> notes, SortOverride override) {
    final idx = override.functionIdx.clamp(0, 2);
    final increasing = override.increasing;
    switch (idx) {
      case 0:
        notes.sort(
          (a, b) => a.path
              .split('/')
              .last
              .toLowerCase()
              .compareTo(b.path.split('/').last.toLowerCase()),
        );
      case 1:
        notes.sort((a, b) => a.modifiedMillis.compareTo(b.modifiedMillis));
      case 2:
        notes.sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
    }
    if (!increasing) {
      final n = notes.length;
      for (var i = 0; i < n / 2; i++) {
        final tmp = notes[i];
        notes[i] = notes[n - i - 1];
        notes[n - i - 1] = tmp;
      }
    }
  }

  static Future<void> _sortNotesAlpha(
    List<String> filePaths,
    bool isIncreasing,
  ) async {
    filePaths.sort(
      (a, b) => a
          .split('/')
          .last
          .toLowerCase()
          .compareTo(b.split('/').last.toLowerCase()),
    );
    if (!isIncreasing) _reverse(filePaths);
  }

  static Future<void> _sortNotesLastModified(
    List<String> filePaths,
    bool isIncreasing,
  ) async {
    final Map<String, DateTime> times = {};
    await Future.wait(
      filePaths.map((path) async {
        times[path] = await _getPathLastModified(path);
      }),
    );

    filePaths.sort((a, b) {
      final firstTime = times[a] ?? DateTime.fromMillisecondsSinceEpoch(0);
      final secondTime = times[b] ?? DateTime.fromMillisecondsSinceEpoch(0);
      return firstTime.compareTo(secondTime);
    });
    if (!isIncreasing) _reverse(filePaths);
  }

  static Future<void> _sortNotesSize(
    List<String> filePaths,
    bool isIncreasing,
  ) async {
    final Map<String, int> sizes = {};
    await Future.wait(
      filePaths.map((path) async {
        sizes[path] = await _getPathSize(path);
      }),
    );

    filePaths.sort((a, b) {
      final firstSize = sizes[a] ?? 0;
      final secondSize = sizes[b] ?? 0;
      return firstSize.compareTo(secondSize);
    });
    if (!isIncreasing) _reverse(filePaths);
  }

  static Future<DateTime> _getPathLastModified(String path) async {
    try {
      if (await FileManager.isDirectory(path)) {
        return await _getDirectoryLastModified(path);
      }
      final notePath = await _resolveNotePath(path);
      return await FileManager.lastModified(notePath);
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  static Future<int> _getPathSize(String path) async {
    try {
      if (await FileManager.isDirectory(path)) {
        return await _getDirectorySize(path);
      }
      final noteBasePath = _resolveNoteBasePath(path);
      // Use getNoteListRowStats to ensure the sorted size matches the UI exactly (including assets)
      final stats = await FileManager.getNoteListRowStats(noteBasePath);
      return stats?.sizeBytes ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static String _resolveNoteBasePath(String path) {
    if (path.endsWith(Editor.extension)) {
      return path.substring(0, path.length - Editor.extension.length);
    }
    if (path.endsWith(Editor.extensionOldJson)) {
      return path.substring(0, path.length - Editor.extensionOldJson.length);
    }
    return path;
  }

  static Future<String> _resolveNotePath(String path) async {
    if (path.endsWith(Editor.extension) ||
        path.endsWith(Editor.extensionOldJson)) {
      return path;
    }

    final oldJsonExists = await FileManager.doesFileExist(
      path + Editor.extensionOldJson,
    );
    return path + (oldJsonExists ? Editor.extensionOldJson : Editor.extension);
  }

  static Future<DateTime> _getDirectoryLastModified(String directory) async {
    final files = await _getDirectoryNoteFiles(directory);
    DateTime latest = DateTime.fromMillisecondsSinceEpoch(0);
    for (final file in files) {
      final modified = await FileManager.lastModified(file);
      if (modified.isAfter(latest)) latest = modified;
    }
    return latest;
  }

  static Future<int> _getDirectorySize(String directory) async {
    final props = await FileManager.getFolderProperties(directory);
    final size = props?['total_size'];
    return size is int ? size : 0;
  }

  static Future<List<String>> _getDirectoryNoteFiles(String directory) async {
    final prefix = directory.endsWith('/') ? directory : '$directory/';
    final allNotes = await FileManager.getAllFiles(includeExtensions: true);
    return allNotes
        .where(
          (path) =>
              path.startsWith(prefix) &&
              (path.endsWith(Editor.extension) ||
                  path.endsWith(Editor.extensionOldJson)),
        )
        .toList();
  }
}

class SortButton extends StatelessWidget {
  const SortButton({
    super.key,
    required this.callback,
    required this.sortContext,
    this.sortOverride,
  });

  final Future<void> Function() callback;
  final SortContext sortContext;
  /// When set (Recent Notes), sort is in-memory and does not persist.
  final SortOverride? sortOverride;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: t.home.sortNames.sort,
      icon: const Icon(Icons.sort),
      onPressed: () async {
        await showGeneralDialog(
          context: context,
          barrierDismissible: true,
          barrierLabel: 'Dismiss',
          barrierColor: Colors.black.withValues(alpha: 0.18),
          pageBuilder: (context, _, __) {
            return _SortButtonDialog(
              callback: callback,
              sortContext: sortContext,
              sortOverride: sortOverride,
            );
          },
        );
      },
    );
  }
}

class _SortButtonDialog extends StatefulWidget {
  const _SortButtonDialog({
    required this.callback,
    required this.sortContext,
    this.sortOverride,
  });

  final Future<void> Function() callback;
  final SortContext sortContext;
  final SortOverride? sortOverride;

  @override
  State<_SortButtonDialog> createState() => _SortButtonDialogState();
}

class _SortButtonDialogState extends State<_SortButtonDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, -0.05), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  int _functionIdx() {
    return widget.sortOverride?.functionIdx ??
        SortNotes._getSortFunctionIdx(widget.sortContext);
  }

  bool _isIncreasing() {
    return widget.sortOverride?.increasing ??
        SortNotes._getIsIncreasingOrder(widget.sortContext);
  }

  void _setFunctionIdx(int idx) {
    final override = widget.sortOverride;
    if (override != null) {
      override.functionIdx = idx;
    } else {
      SortNotes._setSortFunctionIdx(widget.sortContext, idx);
    }
  }

  void _toggleIncreasing() {
    final override = widget.sortOverride;
    if (override != null) {
      override.increasing = !override.increasing;
    } else {
      SortNotes._setIsIncreasingOrder(
        widget.sortContext,
        !SortNotes._getIsIncreasingOrder(widget.sortContext),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<String> sortNames = [
      t.home.sortNames.alphabetical,
      t.home.sortNames.lastModified,
      t.home.sortNames.sizeOnDisk,
    ];

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 60, right: 16),
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Material(
              color: Colors.transparent,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: SizedBox(
                  width: 272,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                        child: Text(
                          t.home.sortNames.sort,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                            letterSpacing: -0.35,
                          ),
                        ),
                      ),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.18,
                        ),
                      ),
                      for (int idx = 0; idx < sortNames.length; idx++)
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () async {
                              _setFunctionIdx(idx);
                              setState(() {});
                              await widget.callback();
                              if (mounted) Navigator.of(context).pop();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      sortNames[idx],
                                      style: theme.textTheme.bodyLarge
                                          ?.copyWith(
                                            fontSize: 15,
                                            color:
                                                _functionIdx() == idx
                                                ? colorScheme.onSurface
                                                : colorScheme.onSurfaceVariant,
                                            fontWeight:
                                                _functionIdx() == idx
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                          ),
                                    ),
                                  ),
                                  if (_functionIdx() == idx)
                                    Icon(
                                      Icons.check_rounded,
                                      size: 20,
                                      color: colorScheme.primary,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.18,
                        ),
                      ),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () async {
                            _toggleIncreasing();
                            setState(() {});
                            await widget.callback();
                            if (mounted) Navigator.of(context).pop();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    t.home.sortNames.increasing,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontSize: 15,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                Icon(
                                  _isIncreasing()
                                      ? Icons.arrow_upward_rounded
                                      : Icons.arrow_downward_rounded,
                                  size: 20,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
