// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

enum SortContext {
  browse,
  recent,
  search,
}

class SortNotes {
  SortNotes._();

  static final List<Future<void> Function(List<String>, bool)> _sortFunctions =
      [_sortNotesAlpha, _sortNotesLastModified, _sortNotesSize];

  static bool _isNeeded = true;
  static bool get isNeeded => _isNeeded;

  static int _getSortFunctionIdx(SortContext context) {
    return switch (context) {
      SortContext.browse || SortContext.search => stows.browseSortFunctionIdx.value,
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
      SortContext.browse || SortContext.search => stows.browseIsSortIncreasing.value,
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
  }) async {
    if (_isNeeded || forced) {
      final idx = _getSortFunctionIdx(context);
      final increasing = _getIsIncreasingOrder(context);
      await _sortFunctions[idx].call(filePaths, increasing);
      _isNeeded = false;
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
      final notePath = await _resolveNotePath(path);
      return await FileManager.getFileSize(notePath);
    } catch (_) {
      return 0;
    }
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
    final files = await _getDirectoryNoteFiles(directory);
    int total = 0;
    for (final file in files) {
      total += await FileManager.getFileSize(file);
    }
    return total;
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
  });

  final Future<void> Function() callback;
  final SortContext sortContext;

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
          barrierColor: Colors.black.withValues(alpha: 0.1),
          pageBuilder: (context, _, __) {
            return _SortButtonDialog(
              callback: callback,
              sortContext: sortContext,
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
  });

  final Future<void> Function() callback;
  final SortContext sortContext;

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

  @override
  Widget build(BuildContext context) {
    final List<String> sortNames = [
      t.home.sortNames.alphabetical,
      t.home.sortNames.lastModified,
      t.home.sortNames.sizeOnDisk,
    ];

    final colorScheme = Theme.of(context).colorScheme;

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
              child: Container(
                width: 250,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        t.home.sortNames.sort,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    for (int idx = 0; idx < sortNames.length; idx++)
                      InkWell(
                        onTap: () async {
                          SortNotes._setSortFunctionIdx(
                            widget.sortContext,
                            idx,
                          );
                          setState(() {});
                          await widget.callback();
                          if (mounted) Navigator.of(context).pop();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  sortNames[idx],
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: SortNotes._getSortFunctionIdx(
                                              widget.sortContext,
                                            ) ==
                                            idx
                                        ? colorScheme.onSurface
                                        : colorScheme.onSurfaceVariant,
                                    fontWeight: SortNotes._getSortFunctionIdx(
                                              widget.sortContext,
                                            ) ==
                                            idx
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (SortNotes._getSortFunctionIdx(
                                    widget.sortContext,
                                  ) ==
                                  idx)
                                Icon(
                                  Icons.check,
                                  size: 18,
                                  color: colorScheme.primary,
                                ),
                            ],
                          ),
                        ),
                      ),
                    const Divider(height: 1),
                    InkWell(
                      onTap: () async {
                        SortNotes._setIsIncreasingOrder(
                          widget.sortContext,
                          !SortNotes._getIsIncreasingOrder(widget.sortContext),
                        );
                        setState(() {});
                        await widget.callback();
                        if (mounted) Navigator.of(context).pop();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                t.home.sortNames.increasing,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ),
                            Icon(
                              SortNotes._getIsIncreasingOrder(widget.sortContext)
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward,
                              size: 18,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
