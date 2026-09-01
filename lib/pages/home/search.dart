// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:collapsible/collapsible.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
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
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/home_data_cache.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/data/tags_database.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/services/vault_adapter.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final List<String> filePaths = [];
  List<String> filteredFiles = [];
  var failed = false;
  var _loading = true;

  final ValueNotifier<List<String>> selectedFiles = ValueNotifier([]);
  final TextEditingController searchController = TextEditingController();
  final ValueNotifier<String> searchText = ValueNotifier('');
  final log = Logger('SearchPage');
  final Map<String, Set<String>> _tagsByFile = {};

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
    searchController.addListener(_onSearchChanged);
    moveIncorrectlyImportedFiles();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadWithCache();
    });
  }

  @override
  void dispose() {
    selectedFiles.removeListener(_setState);
    searchController.removeListener(_onSearchChanged);
    searchController.dispose();
    searchText.dispose();
    fileWriteSubscription?.cancel();
    _fileWriteDebounce?.cancel();
    super.dispose();
  }

  StreamSubscription? fileWriteSubscription;
  Timer? _fileWriteDebounce;
  void fileWriteListener(FileOperation event) {
    if (selectedFiles.value.isNotEmpty) return;

    _fileWriteDebounce?.cancel();
    _fileWriteDebounce = Timer(const Duration(milliseconds: 320), () {
      _fileWriteDebounce = null;
      if (mounted) findAllNotes(fromFileListener: true);
    });
  }

  void _setState() => setState(() {});

  void _onSearchChanged() {
    searchText.value = searchController.text;
    filterFiles(searchController.text);
  }

  Future<void> filterFiles(String search) async {
    if (search.isEmpty) {
      filteredFiles = List.from(filePaths);
    } else {
      search = search.toLowerCase().trim();
      filteredFiles = filePaths.where((file) {
        if (file.toLowerCase().contains(search)) return true;
        final normPath = TagDatabase.normalizePath(file);
        final tags = _tagsByFile[normPath] ?? const <String>{};
        return tags.any((tag) => tag.contains(search));
      }).toList();
    }
    await SortNotes.sortNotes(
      filteredFiles,
      context: SortContext.search,
      forced: true,
    );
    if (mounted) setState(() {});
  }

  Future<void> _loadWithCache() async {
    final cache = HomeDataCache.instance;
    if (cache.allCached != null && cache.allTagsCached != null) {
      filePaths.clear();
      filePaths.addAll(cache.allCached!);
      failed = filePaths.isEmpty;
      _tagsByFile.clear();
      _tagsByFile.addAll(cache.allTagsCached!);
      await filterFiles(searchController.text);
      if (mounted) setState(() => _loading = false);
      return;
    }
    findAllNotes();
  }

  Future findAllNotes({bool fromFileListener = false}) async {
    if (!mounted) return;

    if (fromFileListener) {
      final location = GoRouterState.of(context).uri.toString();
      if (!location.startsWith(RoutePaths.prefixOfHome)) return;
      HomeDataCache.instance.invalidate();
    }

    if (!fromFileListener && mounted) setState(() => _loading = true);

    final list = await HomeDataCache.instance.getAllOrLoad();
    final tags = await HomeDataCache.instance.getAllTagsOrLoad();

    filePaths.clear();
    if (list.isEmpty) {
      failed = true;
      if (mounted) setState(() => _loading = false);
      return;
    }

    failed = false;
    filePaths.addAll(list);
    _tagsByFile.clear();
    _tagsByFile.addAll(tags);
    await filterFiles(searchController.text);

    if (mounted) setState(() => _loading = false);
  }

  Widget _buildSearchLoading(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: 20),
          Text(
            t.home.titles.search,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          child: _loading
              ? _buildSearchLoading(context)
              : LayoutBuilder(
                  key: const ValueKey('search-content'),
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
                            findAllNotes(),
                            Future.delayed(const Duration(milliseconds: 500)),
                          ]),
                          child: CustomScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            slivers: [
                              SliverAppBar(
                                primary: false,
                                pinned: true,
                                leading: null,
                                title: ValueListenableBuilder<String>(
                                  valueListenable: searchText,
                                  builder: (context, currentSearchText, _) =>
                                      TextField(
                                        controller: searchController,
                                        decoration: InputDecoration(
                                          hintText: t.home.titles.search,
                                          border: InputBorder.none,
                                          prefixIcon: const Icon(Icons.search),
                                          suffixIcon:
                                              currentSearchText.isNotEmpty
                                              ? IconButton(
                                                  icon: const Icon(Icons.clear),
                                                  onPressed: () {
                                                    searchController.clear();
                                                    filterFiles('');
                                                  },
                                                )
                                              : null,
                                        ),
                                        onChanged: (value) =>
                                            filterFiles(value),
                                      ),
                                ),
                                actions: [
                                  IconButton(
                                    tooltip: t.home.tooltips.viewMode,
                                    icon: ValueListenableBuilder<bool>(
                                      valueListenable: stows.homeListMode,
                                      builder: (context, listMode, _) {
                                        return Icon(
                                          listMode
                                              ? Icons.grid_view
                                              : Icons.view_list,
                                        );
                                      },
                                    ),
                                    onPressed: () {
                                      stows.homeListMode.value =
                                          !stows.homeListMode.value;
                                    },
                                  ),
                                  // Security: Lock Vault Button
                                  ValueListenableBuilder<bool>(
                                    valueListenable:
                                        stows.localEncryptionEnabled,
                                    builder: (context, encryptionOn, _) {
                                      return ValueListenableBuilder<bool>(
                                        valueListenable:
                                            VaultAdapter.unlockListenable,
                                        builder: (context, unlocked, _) {
                                          if (!encryptionOn || !unlocked) {
                                            return const SizedBox.shrink();
                                          }
                                          return IconButton(
                                            tooltip: 'Lock Vault',
                                            icon: const Icon(
                                              Icons.power_settings_new,
                                            ),
                                            onPressed: () {
                                              unawaited(
                                                VaultAdapter.lockAndGoToLogin(),
                                              );
                                            },
                                          );
                                        },
                                      );
                                    },
                                  ),
                                  SortButton(
                                    sortContext: SortContext.search,
                                    callback: () async {
                                      if (SortNotes.isNeeded) {
                                        await SortNotes.sortNotes(
                                          filteredFiles,
                                          context: SortContext.search,
                                          forced: true,
                                        );
                                        setState(() {});
                                      }
                                    },
                                  ),
                                ],
                              ),
                              if (failed) ...[
                                SliverSafeArea(
                                  sliver: SliverToBoxAdapter(
                                    child: Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Text(t.home.noNotesFound),
                                      ),
                                    ),
                                  ),
                                ),
                              ] else ...[
                                SliverSafeArea(
                                  minimum: EdgeInsets.only(
                                    bottom: isSelecting ? 16 : 100,
                                  ),
                                  sliver: MasonryFiles(
                                    key: const PageStorageKey(
                                      'search_notes_grid',
                                    ),
                                    crossAxisCount: crossAxisCount,
                                    files: filteredFiles,
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
        ),
        bottomNavigationBar: isSelecting
            ? SafeArea(
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
                        onDeleted: findAllNotes,
                      ),
                      ExportNoteButton(
                        selectedFiles: selectedFiles.value,
                        exportHostContext: context,
                        onExportStarted: () => selectedFiles.value = [],
                      ),
                      SelectAllButton(
                        selectedFiles: selectedFiles.value,
                        allFiles: filteredFiles,
                        selectAll: () {
                          selectedFiles.value = List.from(filteredFiles);
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
