// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:collapsible/collapsible.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:saber/components/editor/note_properties_dialog.dart';
import 'package:saber/components/home/delete_note_button.dart';
import 'package:saber/components/home/export_note_button.dart';
import 'package:saber/components/home/home_selection_action_bar.dart';
import 'package:saber/components/home/home_toolbar_chrome.dart';
import 'package:saber/components/home/masonry_files.dart';
import 'package:saber/components/home/move_note_button.dart';
import 'package:saber/components/home/new_note_button.dart';
import 'package:saber/components/home/rename_note_button.dart';
import 'package:saber/components/home/select_all_button.dart';
import 'package:saber/components/home/sort_button.dart';
import 'package:saber/components/home/welcome.dart';
import 'package:saber/components/navbar/responsive_navbar.dart';
import 'package:saber/components/navbar/vertical_navbar.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/home_data_cache.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/recent_notes_index.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/services/vault_adapter.dart';

class RecentPage extends StatefulWidget {
  const RecentPage({super.key, this.isActive = true});

  /// Home keeps this page in an [IndexedStack]; sort resets when this goes false.
  final bool isActive;

  @override
  State<RecentPage> createState() => _RecentPageState();
}

class _RecentPageState extends State<RecentPage> {
  final RecentNotesIndex _index = RecentNotesIndex();
  List<String> filePaths = [];
  var failed = false;
  var _loaded = false;

  final ValueNotifier<List<String>> selectedFiles = ValueNotifier([]);

  final log = Logger('RecentPage');

  final List<FileOperation> _pendingOps = [];
  Timer? _flushOpsTimer;
  final Map<String, Timer> _verifyGone = {};

  /// Grid columns are locked to the window size, not the content width, so
  /// expanding/collapsing the vertical navbar only rescales cards in place.
  double? _gridColumnWindowWidth;
  int _gridCrossAxisCount = 2;

  void moveIncorrectlyImportedFiles() async {
    for (final filePath in stows.recentFiles.value) {
      if (filePath.startsWith('/')) continue;

      final String newFilePath;
      if (filePath.startsWith('null/')) {
        newFilePath = await FileManager.suffixFilePathToMakeItUnique(
          filePath.substring('null'.length),
        );
      } else {
        newFilePath = await FileManager.suffixFilePathToMakeItUnique(
          '/$filePath',
        );
      }

      log.warning(
        'Found incorrectly imported file at `$filePath`; moving to `$newFilePath`',
      );
      await FileManager.moveFile(filePath, newFilePath);
    }
  }

  @override
  void initState() {
    super.initState();
    fileWriteSubscription = FileManager.fileWriteStream.stream.listen(
      fileWriteListener,
    );
    selectedFiles.addListener(_setState);
    moveIncorrectlyImportedFiles();
    _loadInitial();
  }

  @override
  void didUpdateWidget(RecentPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) {
      final sort = _index.sort;
      final needsReset =
          sort.functionIdx != SortOverride.recentDefaultFunctionIdx ||
          sort.increasing != SortOverride.recentDefaultIncreasing;
      if (needsReset) {
        sort.resetToRecentDefault();
        _publish();
      }
    }
  }

  @override
  void dispose() {
    _flushOpsTimer?.cancel();
    for (final timer in _verifyGone.values) {
      timer.cancel();
    }
    _verifyGone.clear();
    selectedFiles.removeListener(_setState);
    fileWriteSubscription?.cancel();
    super.dispose();
  }

  StreamSubscription? fileWriteSubscription;

  void fileWriteListener(FileOperation event) {
    if (event.isThumbnail) return;
    _pendingOps.add(event);
    _flushOpsTimer ??= Timer(Duration.zero, _flushPendingOps);
  }

  void _flushPendingOps() {
    _flushOpsTimer = null;
    if (!mounted) return;
    final ops = List<FileOperation>.from(_pendingOps);
    _pendingOps.clear();
    if (ops.isEmpty) return;

    final result = _index.applyOperations(ops);
    for (final path in result.written) {
      _cancelVerifyGone(path);
      final entry = _index[path];
      if (entry != null) HomeDataCache.instance.upsertNoteIndex(entry);
    }
    for (final path in result.removed) {
      _cancelVerifyGone(path);
      HomeDataCache.instance.removeNoteIndex(path);
    }
    for (final path in result.unverifiedDeletes) {
      _scheduleVerifyGone(path);
    }

    if (result.written.isNotEmpty || result.removed.isNotEmpty) {
      _loaded = true;
      _publish();
    }
    for (final path in result.written) {
      unawaited(_refreshMeta(path));
    }
  }

  void _cancelVerifyGone(String path) {
    _verifyGone.remove(path)?.cancel();
  }

  void _scheduleVerifyGone(String path) {
    _cancelVerifyGone(path);
    _verifyGone[path] = Timer(const Duration(milliseconds: 280), () {
      _verifyGone.remove(path);
      unawaited(_confirmGone(path));
    });
  }

  Future<void> _confirmGone(String path) async {
    if (!mounted || !_index.contains(path)) return;
    if (await FileManager.doesNoteExist(path)) return;
    if (!mounted || !_index.contains(path)) return;
    _index.remove(path);
    HomeDataCache.instance.removeNoteIndex(path);
    _publish();
  }

  Future<void> _refreshMeta(String path) async {
    final peeked = await FileManager.peekNoteIndexEntry(path);
    if (!mounted || !_index.contains(path)) return;
    _index.applyPeekedMeta(peeked);
    final merged = _index[path];
    if (merged != null) HomeDataCache.instance.upsertNoteIndex(merged);
    _publish();
  }

  void _setState() => setState(() {});

  void _publish({bool notify = true}) {
    final nextPaths = _index.sortedPaths();
    final nextFailed = nextPaths.isEmpty && _loaded;
    if (listEquals(nextPaths, filePaths) && nextFailed == failed) {
      return;
    }
    failed = nextFailed;
    filePaths = nextPaths;
    if (notify) setState(() {});
  }

  void _loadInitial() {
    final cached = HomeDataCache.instance.allNotesCached;
    if (cached != null) {
      _index.mergeFromDisk(cached);
      _loaded = true;
      _publish(notify: false);
      if (mounted) setState(() {});
    }
    HomeDataCache.instance.getAllNotesOrLoad().then((list) {
      if (!mounted) return;
      if (list.isEmpty && _index.isNotEmpty) return;
      _index.mergeFromDisk(list);
      _loaded = true;
      _publish();
    });
  }

  Future<void> _reloadFromDisk() async {
    final list = await HomeDataCache.instance.reloadAllNotes();
    if (!mounted) return;
    if (list.isEmpty && _index.isNotEmpty) return;
    _index.mergeFromDisk(list);
    final diskPaths = {for (final e in list) e.path};
    final extras = [
      for (final path in _index.paths)
        if (!diskPaths.contains(path)) path,
    ];
    for (final path in extras) {
      if (await FileManager.doesNoteExist(path)) continue;
      if (!mounted) return;
      _index.remove(path);
      HomeDataCache.instance.removeNoteIndex(path);
    }
    _loaded = true;
    _publish();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final platform = theme.platform;

    final isSelecting = selectedFiles.value.isNotEmpty;
    final totalFileCount = _index.length;

    return PopScope(
      canPop: !isSelecting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        selectedFiles.value = [];
      },
      child: Scaffold(
        extendBody: true,
        appBar: AppBar(
          backgroundColor: colorScheme.surface,
          scrolledUnderElevation: 3,
          titleSpacing: 16,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                t.home.titles.home,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_loaded && totalFileCount > 0) ...[
                const SizedBox(width: 12),
                Badge(
                  label: Text('$totalFileCount'),
                  backgroundColor: colorScheme.secondaryContainer,
                  textColor: colorScheme.onSecondaryContainer,
                  largeSize: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ],
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: ValueListenableBuilder<bool>(
                valueListenable: stows.homeListMode,
                builder: (context, listMode, _) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: stows.localEncryptionEnabled,
                    builder: (context, encryptionOn, _) {
                      return ValueListenableBuilder<bool>(
                        valueListenable: VaultAdapter.unlockListenable,
                        builder: (context, vaultUnlocked, _) {
                          return _RecentNotesToolbarStrip(
                            listMode: listMode,
                            showVaultLock: encryptionOn && vaultUnlocked,
                            onToggleViewMode: () =>
                                stows.homeListMode.value = !listMode,
                            onLockVault: () {
                              unawaited(VaultAdapter.lockAndGoToLogin());
                            },
                            sortButton: SortButton(
                              sortContext: SortContext.recent,
                              sortOverride: _index.sort,
                              callback: () async {
                                _publish();
                              },
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return ValueListenableBuilder<bool>(
              valueListenable: stows.homeListMode,
              builder: (context, listMode, _) {
                final windowWidth = MediaQuery.sizeOf(context).width;
                if (_gridColumnWindowWidth != windowWidth) {
                  _gridColumnWindowWidth = windowWidth;
                  // Size columns for the widest content area (collapsed rail).
                  // Expanding the rail shrinks tiles but must not reflow rows.
                  final columnBasis = ResponsiveNavbar.isLargeScreen
                      ? windowWidth - VerticalNavbar.collapsedWidth
                      : windowWidth;
                  _gridCrossAxisCount = (columnBasis ~/ 200).clamp(1, 10);
                }
                final crossAxisCount = listMode ? 1 : _gridCrossAxisCount;

                // Lay out at the widest content width and Transform.scale into
                // the current slot so rail toggle only scales cards — scroll
                // offset (and what you see mid-list) stays put.
                final slotW = constraints.maxWidth;
                final slotH = constraints.maxHeight;
                final layoutW = ResponsiveNavbar.isLargeScreen
                    ? (windowWidth - VerticalNavbar.collapsedWidth)
                        .clamp(1.0, double.infinity)
                    : slotW;
                final scale = (slotW / layoutW).clamp(0.01, 1.0);
                final viewportH = slotH / scale;

                final scrollBody = RefreshIndicator(
                  onRefresh: () => Future.wait([
                    _reloadFromDisk(),
                    Future.delayed(const Duration(milliseconds: 500)),
                  ]),
                  child: CustomScrollView(
                    cacheExtent: 1400,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      if (failed) ...[
                        const SliverSafeArea(
                          top: false,
                          sliver: SliverToBoxAdapter(child: Welcome()),
                        ),
                      ] else ...[
                        SliverSafeArea(
                          top: false,
                          minimum: EdgeInsets.only(
                            bottom: isSelecting ? 16 : 100,
                          ),
                          sliver: MasonryFiles(
                            key: const ValueKey('recent_notes_grid'),
                            crossAxisCount: crossAxisCount,
                            files: filePaths,
                            selectedFiles: selectedFiles,
                            animateMutations: false,
                            addAutomaticKeepAlives: true,
                            showListMetadata: listMode,
                          ),
                        ),
                      ],
                    ],
                  ),
                );

                if (!ResponsiveNavbar.isLargeScreen) {
                  return scrollBody;
                }

                return SizedBox(
                  width: slotW,
                  height: slotH,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: layoutW,
                      maxWidth: layoutW,
                      minHeight: viewportH,
                      maxHeight: viewportH,
                      child: Transform.scale(
                        scale: scale,
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: layoutW,
                          height: viewportH,
                          child: scrollBody,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),

        bottomNavigationBar: isSelecting
            ? SafeArea(
                top: false,
                child: HomeSelectionActionBar(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Collapsible(
                        axis: CollapsibleAxis.horizontal,
                        collapsed: selectedFiles.value.length != 1,
                        child: RenameNoteButton(
                          existingPath: selectedFiles.value.isEmpty
                              ? ''
                              : selectedFiles.value.first,
                          unselectNotes: () => selectedFiles.value = [],
                        ),
                      ),
                      MoveNoteButton(
                        filesToMove: selectedFiles.value,
                        unselectNotes: () => selectedFiles.value = [],
                      ),
                      DeleteNoteButton(
                        selectedFiles: selectedFiles.value,
                        unselectNotes: () => selectedFiles.value = [],
                        onDeleted: _reloadFromDisk,
                      ),
                      ExportNoteButton(
                        selectedFiles: selectedFiles.value,
                        exportHostContext: context,
                        onExportStarted: () => selectedFiles.value = [],
                      ),
                      if (selectedFiles.value.length == 1)
                        IconButton(
                          tooltip: 'Properties',
                          icon: const Icon(Icons.info_outline),
                          onPressed: () {
                            showPropertiesForFile(
                              context,
                              selectedFiles.value.first,
                            );
                          },
                        ),
                      if (selectedFiles.value.length == 2)
                        IconButton(
                          tooltip: t.editor.splitView,
                          icon: const Icon(Icons.vertical_split_outlined),
                          onPressed: () {
                            final paths = List<String>.from(selectedFiles.value);
                            selectedFiles.value = [];
                            context.push(
                              RoutePaths.editSplit(paths[0], paths[1]),
                            );
                          },
                        ),
                      SelectAllButton(
                        selectedFiles: selectedFiles.value,
                        allFiles: filePaths,
                        selectAll: () {
                          selectedFiles.value = List.from(filePaths);
                        },
                        deselectAll: () => selectedFiles.value = [],
                      ),
                    ],
                  ),
                ),
              )
            : null,
        floatingActionButton: isSelecting
            ? null
            : NewNoteButton(cupertino: platform.isCupertino),
      ),
    );
  }
}

// Pill-style controls: [HomeGlassIconStrip] + rail-matched colors.
class _RecentNotesToolbarStrip extends StatelessWidget {
  const _RecentNotesToolbarStrip({
    required this.listMode,
    required this.showVaultLock,
    required this.onToggleViewMode,
    required this.onLockVault,
    required this.sortButton,
  });

  final bool listMode;
  final bool showVaultLock;
  final VoidCallback onToggleViewMode;
  final VoidCallback onLockVault;
  final Widget sortButton;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final actionStyle = homeToolbarCompactIconStyle(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: t.home.tooltips.viewMode,
          onPressed: onToggleViewMode,
          icon: Icon(listMode ? Icons.grid_view_rounded : Icons.view_list_rounded),
        ),
        if (showVaultLock) ...[
          const SizedBox(width: 4),
          IconButton(
            color: colorScheme.primary,
            tooltip: 'Lock Vault',
            onPressed: onLockVault,
            icon: const Icon(Icons.power_settings_new),
          ),
        ],
        const SizedBox(width: 4),
        sortButton,
      ],
    );
  }
}
