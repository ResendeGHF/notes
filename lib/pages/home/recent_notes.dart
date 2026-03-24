// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:ui';

import 'package:collapsible/collapsible.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:saber/components/editor/note_properties_dialog.dart';
import 'package:saber/components/home/delete_note_button.dart';
import 'package:saber/components/home/export_note_button.dart';
import 'package:saber/components/home/masonry_files.dart';
import 'package:saber/components/home/move_note_button.dart';
import 'package:saber/components/home/new_note_button.dart';
import 'package:saber/components/home/rename_note_button.dart';
import 'package:saber/components/home/select_all_button.dart';
import 'package:saber/components/home/sort_button.dart';
import 'package:saber/components/home/welcome.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/home_data_cache.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/services/vault_adapter.dart';

class RecentPage extends StatefulWidget {
  const RecentPage({super.key});

  @override
  State<RecentPage> createState() => _RecentPageState();
}

class _RecentPageState extends State<RecentPage> {
  List<String> filePaths =
      [];
  var failed = false;
  int? _totalFileCount;

  final ValueNotifier<List<String>> selectedFiles = ValueNotifier([]);

  final log = Logger('RecentPage');

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
    _loadWithCache();
  }

  @override
  void dispose() {
    _fileWriteDebounce?.cancel();
    selectedFiles.removeListener(_setState);
    fileWriteSubscription?.cancel();
    super.dispose();
  }

  StreamSubscription? fileWriteSubscription;
  Timer? _fileWriteDebounce;
  void fileWriteListener(FileOperation event) {

    if (selectedFiles.value.isNotEmpty) return;

    _fileWriteDebounce?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fileWriteDebounce?.cancel();
      _fileWriteDebounce = Timer(const Duration(milliseconds: 250), () {
        _fileWriteDebounce = null;
        if (mounted) findRecentlyAccessedNotes(fromFileListener: true);
      });
    });
  }

  void _setState() => setState(() {});

  void _loadWithCache() {
    final cache = HomeDataCache.instance;
    if (cache.recentCached != null) {
      filePaths = List<String>.from(cache.recentCached!);
      failed = filePaths.isEmpty;
      if (mounted) setState(() {});
    }
    cache.getRecentOrLoad().then((list) {
      if (!mounted) return;
      filePaths = List<String>.from(list);
      failed = filePaths.isEmpty;
      setState(() {});
    });
    FileManager.getTotalFileCount().then((count) {
      if (mounted) setState(() => _totalFileCount = count);
    });
  }

  Future findRecentlyAccessedNotes({bool fromFileListener = false}) async {
    if (!mounted) return;

    if (fromFileListener) {
      HomeDataCache.instance.invalidate();
    }

    final list = await HomeDataCache.instance.getRecentOrLoad();
    final totalFileCount = await FileManager.getTotalFileCount();

    if (list.isEmpty) {
      failed = true;
      filePaths = [];
    } else {
      failed = false;
      filePaths = List<String>.from(list);
    }

    if (mounted) {
      setState(() {
        _totalFileCount = totalFileCount;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final platform = Theme.of(context).platform;

    final isSelecting = selectedFiles.value.isNotEmpty;

    return PopScope(
      canPop: !isSelecting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        selectedFiles.value = [];
      },
      child: Scaffold(
        extendBody: true,

        body: LayoutBuilder(
          builder: (context, constraints) {
            return ValueListenableBuilder<bool>(
              valueListenable: stows.homeListMode,
              builder: (context, listMode, _) {
                final screenWidth = MediaQuery.sizeOf(context).width;
                final crossAxisCount = listMode
                    ? 1
                    : (screenWidth ~/ 200).clamp(1, 10);

                return RefreshIndicator(
                  onRefresh: () => Future.wait([
                    findRecentlyAccessedNotes(),
                    Future.delayed(const Duration(milliseconds: 500)),
                  ]),
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverAppBar(
                        collapsedHeight: kToolbarHeight,
                        expandedHeight: 140,
                        pinned: true,
                        scrolledUnderElevation: 1,
                        leading: null,
                        title: Text(
                          t.home.titles.home,
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.5,
                          ),
                        ),
                        actions: [
                          IconButton(
                            tooltip: t.home.tooltips.viewMode,
                            icon: Icon(
                              listMode ? Icons.grid_view : Icons.view_list,
                            ),
                            onPressed: () =>
                                stows.homeListMode.value = !listMode,
                          ),
                          // Security: Lock Vault Button
                          if (stows.localEncryptionEnabled.value &&
                              VaultAdapter.isUnlocked)
                            IconButton(
                              tooltip: 'Lock Vault',
                              icon: const Icon(Icons.power_settings_new),
                              onPressed: () async {
                                await VaultAdapter.instance.lock();
                                if (context.mounted) {
                                  context.go(RoutePaths.login);
                                }
                              },
                            ),
                          SortButton(
                            sortContext: SortContext.recent,
                            callback: () async {
                              HomeDataCache.instance.invalidate();
                              await findRecentlyAccessedNotes();
                            },
                          ),
                        ],
                      ),
                      if (_totalFileCount != null && _totalFileCount! > 0)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 20,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: colorScheme.outlineVariant.withValues(
                                    alpha: 0.3,
                                  ),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primaryContainer
                                          .withValues(alpha: 0.5),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.insert_drive_file_outlined,
                                      color: colorScheme.onPrimaryContainer,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '$_totalFileCount Files',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                            color: colorScheme.onSurface,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        ValueListenableBuilder<bool>(
                                          valueListenable:
                                              stows.localEncryptionEnabled,
                                          builder: (context, isEncrypted, _) {
                                            return Text(
                                              isEncrypted
                                                  ? 'Securely stored in your vault'
                                                  : 'Stored on disk',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (failed) ...[
                        const SliverSafeArea(
                          sliver: SliverToBoxAdapter(child: Welcome()),
                        ),
                      ] else ...[
                        SliverSafeArea(
                          minimum: EdgeInsets.only(

                            bottom: isSelecting ? 16 : 100,
                          ),
                          sliver: MasonryFiles(

                            key: ValueKey(
                              Object.hashAll([
                                crossAxisCount,
                                ...filePaths.take(50),
                              ]),
                            ),
                            crossAxisCount: crossAxisCount,
                            files: filePaths,
                            selectedFiles: selectedFiles,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        ),

        bottomNavigationBar: isSelecting
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutBack,
                    tween: Tween<double>(begin: 0.0, end: 1.0),
                    builder: (context, value, child) {
                      return Transform.translate(
                        offset: Offset(0, 50 * (1 - value)),
                        child: Opacity(
                          opacity: value.clamp(0.0, 1.0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(36),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                              child: Container(
                                decoration: BoxDecoration(

                                  color: Colors.black.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(36),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.25,
                                      ),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: child,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        iconTheme: IconThemeData(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
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
                              onDeleted: findRecentlyAccessedNotes,
                            ),
                            ExportNoteButton(
                              selectedFiles: selectedFiles.value,
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
                    ),
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
