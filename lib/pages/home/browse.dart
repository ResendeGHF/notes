// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive_io.dart';
import 'package:collapsible/collapsible.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:saber/components/editor/folder_export_dialog.dart';
import 'package:saber/components/editor/note_properties_dialog.dart';
import 'package:saber/components/home/delete_note_button.dart';
import 'package:saber/components/home/export_note_button.dart';
import 'package:saber/components/home/masonry_files.dart';
import 'package:saber/components/home/move_folder_button.dart';
import 'package:saber/components/home/move_note_button.dart';
import 'package:saber/components/home/new_folder_dialog.dart';
import 'package:saber/components/home/new_note_button.dart';
import 'package:saber/components/home/no_files.dart';
import 'package:saber/components/home/path_components.dart';
import 'package:saber/components/home/rename_note_button.dart';
import 'package:saber/components/home/select_all_button.dart';
import 'package:saber/components/home/sort_button.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/editor_exporter.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/home_data_cache.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/data/tags_database.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/services/sba_encryption.dart';
import 'package:saber/services/vault_adapter.dart';

class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key, String? path}) : initialPath = path;

  final String? initialPath;

  @visibleForTesting
  static DirectoryChildren? overrideChildren;

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  DirectoryChildren? children;
  String? path;
  final ValueNotifier<List<String>> selectedFiles = ValueNotifier([]);
  List<String> _cachedNotesInCwd = [];
  Map<String, int> _folderFileCounts = const {};
  bool _isManagingFolders = false;
  bool _needsRefresh = false;

  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<String> _searchText = ValueNotifier('');
  final List<String> _allFilePaths = [];
  List<String> _filteredSearchFiles = [];
  final Map<String, Set<String>> _tagsByFile = {};
  bool _isSearching = false;
  bool _searchFailed = false;

  @override
  void initState() {
    super.initState();
    final raw = widget.initialPath;
    path = (raw != null && raw.isNotEmpty && !raw.startsWith('/'))
        ? '/$raw'
        : raw;
    fileWriteSubscription = FileManager.fileWriteStream.stream.listen(
      fileWriteListener,
    );
    selectedFiles.addListener(_onSelectionChanged);
    _searchController.addListener(_onSearchChanged);
    _loadWithCache();
  }

  @override
  void dispose() {
    _fileWriteDebounce?.cancel();
    selectedFiles.removeListener(_onSelectionChanged);
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchText.dispose();
    fileWriteSubscription?.cancel();
    super.dispose();
  }

  void _onSelectionChanged() {
    setState(() {});
    if (selectedFiles.value.isEmpty && _needsRefresh) {
      _needsRefresh = false;
      findChildrenOfPath(fromFileListener: true);
    }
  }

  void _onSearchChanged() {
    _searchText.value = _searchController.text;
    _filterFiles(_searchController.text);
  }

  Future<void> _filterFiles(String search) async {
    if (search.isEmpty) {
      _isSearching = false;
      _filteredSearchFiles = [];
      if (mounted) setState(() {});
      return;
    }

    _isSearching = true;

    if (_allFilePaths.isEmpty) {
      final list = await HomeDataCache.instance.getAllOrLoad();
      final tags = await HomeDataCache.instance.getAllTagsOrLoad();
      _allFilePaths.clear();
      _allFilePaths.addAll(list);
      _tagsByFile.clear();
      _tagsByFile.addAll(tags);
    }

    search = search.toLowerCase().trim();
    _filteredSearchFiles = _allFilePaths.where((file) {
      if (file.toLowerCase().contains(search)) return true;
      final normPath = TagDatabase.normalizePath(file);
      final tags = _tagsByFile[normPath] ?? const <String>{};
      return tags.any((tag) => tag.contains(search));
    }).toList();

    await SortNotes.sortNotes(
      _filteredSearchFiles,
      context: SortContext.browse,
      forced: true,
    );
    _searchFailed = _filteredSearchFiles.isEmpty;

    if (mounted) setState(() {});
  }

  StreamSubscription? fileWriteSubscription;
  Timer? _fileWriteDebounce;
  void fileWriteListener(FileOperation event) {

    final eventPath = event.filePath.startsWith('/')
        ? event.filePath
        : '/${event.filePath}';
    final currentPath = path ?? '/';

    _allFilePaths.clear();

    if (currentPath != '/' && !eventPath.startsWith(currentPath)) return;

    if (selectedFiles.value.isNotEmpty || _isManagingFolders) {
      _needsRefresh = true;
      return;
    }

    _fileWriteDebounce?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fileWriteDebounce?.cancel();
      _fileWriteDebounce = Timer(const Duration(milliseconds: 250), () {
        _fileWriteDebounce = null;
        if (mounted) {
          findChildrenOfPath(fromFileListener: true);
          if (_isSearching) {
            _filterFiles(_searchController.text);
          }
        }
      });
    });
  }

  void _loadWithCache() {
    final currentPath = path ?? '/';
    if (currentPath == '/') {
      final cache = HomeDataCache.instance;
      if (cache.browseRootCached != null) {
        children = cache.browseRootCached;
        _folderFileCounts = cache.browseRootFolderCountsCached ?? {};
        _cachedNotesInCwd = List<String>.from(
          cache.browseRootNotesCached ?? [],
        );
      }
    }
    findChildrenOfPath();
  }

  Future findChildrenOfPath({
    bool fromFileListener = false,
    bool fromSort = false,
  }) async {
    if (!mounted) return;

    if (fromFileListener) {
      if ((path ?? '/') == '/') HomeDataCache.instance.invalidate();
    }

    final currentPath = path ?? '/';
    if (currentPath == '/') {
      final data = await HomeDataCache.instance.getBrowseRootOrLoad();
      if (!mounted) return;

      Map<String, String> linkedDirs = {};
      Map<String, String> linkedFiles = {};
      try {
        final links = await FolderLinkManager.getLinks('/');
        for (final entry in links.entries) {
          if (entry.value.endsWith('.sbn') ||
              entry.value.endsWith('.sbn2') ||
              entry.value.endsWith('.pdf')) {
            linkedFiles[entry.key] = entry.value;
          } else {
            linkedDirs[entry.key] = entry.value;
          }
        }
      } catch (e) {

      }

      List<String> dirs = List.from(data.children.directories);
      List<String> dirPaths = dirs.map((d) => '/$d').toList();
      await SortNotes.sortNotes(
        dirPaths,
        context: SortContext.browse,
        forced: true,
      );
      dirs = dirPaths.map((p) => p.substring(1)).toList();

      if (linkedDirs.isNotEmpty) {
        Map<String, String> pathToName = {
          for (var e in linkedDirs.entries) e.value: e.key,
        };
        List<String> linkedPaths = linkedDirs.values.toList();
        await SortNotes.sortNotes(
          linkedPaths,
          context: SortContext.browse,
          forced: true,
        );
        Map<String, String> sortedLinkedDirs = {};
        for (var p in linkedPaths) {
          sortedLinkedDirs[pathToName[p]!] = p;
        }
        linkedDirs = sortedLinkedDirs;
      }

      Map<String, int> extraCounts = {};
      if (linkedDirs.isNotEmpty) {
        extraCounts = await FileManager.getFolderFileCountsBatch(
          linkedDirs.values.toList(),
        );
      }

      children = DirectoryChildren(
        dirs,
        data.children.files,
        linkedDirectories: linkedDirs,
        linkedFiles: linkedFiles,
      );
      _folderFileCounts = {...data.folderCounts, ...extraCounts};
      _cachedNotesInCwd = List<String>.from(data.notes);
      await SortNotes.sortNotes(
        _cachedNotesInCwd,
        context: SortContext.browse,
        forced: true,
      );
      if (mounted) {
        setState(() {
          if (!fromFileListener && !fromSort) selectedFiles.value = [];
        });
      }
      return;
    }

    final rawChildren =
        BrowsePage.overrideChildren ??
        await FileManager.getChildrenOfDirectory(path ?? '/');

    Map<String, String> linkedDirs = {};
    Map<String, String> linkedFiles = {};
    try {
      final links = await FolderLinkManager.getLinks(path ?? '/');
      for (final entry in links.entries) {
        if (entry.value.endsWith('.sbn') ||
            entry.value.endsWith('.sbn2') ||
            entry.value.endsWith('.pdf')) {
          linkedFiles[entry.key] = entry.value;
        } else {
          linkedDirs[entry.key] = entry.value;
        }
      }
    } catch (e) {

    }

    Map<String, int> folderCounts = const {};
    if (rawChildren != null) {
      var filteredDirs = rawChildren.directories
          .where((d) => !d.startsWith('.'))
          .toList();

      List<String> dirPaths = filteredDirs
          .map((d) => '${path ?? ''}/$d')
          .toList();
      await SortNotes.sortNotes(
        dirPaths,
        context: SortContext.browse,
        forced: true,
      );
      filteredDirs = dirPaths.map((p) => p.split('/').last).toList();

      if (linkedDirs.isNotEmpty) {
        Map<String, String> pathToName = {
          for (var e in linkedDirs.entries) e.value: e.key,
        };
        List<String> linkedPaths = linkedDirs.values.toList();
        await SortNotes.sortNotes(
          linkedPaths,
          context: SortContext.browse,
          forced: true,
        );
        Map<String, String> sortedLinkedDirs = {};
        for (var p in linkedPaths) {
          sortedLinkedDirs[pathToName[p]!] = p;
        }
        linkedDirs = sortedLinkedDirs;
      }

      children = DirectoryChildren(
        filteredDirs,
        rawChildren.files.where((f) {
          return !f.startsWith('.') &&
              !f.startsWith('TmPmP_') &&
              !f.contains('.sbn2.');
        }).toList(),
        linkedDirectories: linkedDirs,
        linkedFiles: linkedFiles,
      );

      final folderPaths = [
        for (final folderName in filteredDirs) '${path ?? ''}/$folderName',
        for (final linkPath in linkedDirs.values) linkPath,
      ];
      final countResults = await Future.wait([
        FileManager.getFolderFileCountsBatch(folderPaths),
        FileManager.getTotalFileCount(),
      ]);
      folderCounts = countResults[0] as Map<String, int>;

      _cachedNotesInCwd = [
        for (final filePath in children!.files) "${path ?? ""}/$filePath",
      ];
      await SortNotes.sortNotes(
        _cachedNotesInCwd,
        context: SortContext.browse,
        forced: true,
      );
    } else {
      children = null;
      _cachedNotesInCwd = [];
      _folderFileCounts = const {};
    }

    if (mounted)
      setState(() {
        if (!fromFileListener && !fromSort) selectedFiles.value = [];
        _folderFileCounts = folderCounts;
      });
  }

  void onDirectoryTap(String folder) {
    selectedFiles.value = [];
    final oldPath = path;
    if (folder == '..') {
      path = p.dirname(path ?? '/');
      if (path == '/') path = null;
    } else {
      path = p.join(path ?? '/', folder);
    }

    if (oldPath != path) {
      context.go(HomeRoutes.browseFilePath(path ?? '/'));
    }
  }

  void onPathComponentTap(String? newPath) {
    selectedFiles.value = [];
    if (newPath == null || newPath.isEmpty || newPath == '/') {
      newPath = null;
    }
    if (path != newPath) {
      path = newPath;
      context.go(HomeRoutes.browseFilePath(path ?? '/'));
    }
  }

  Future<void> createFolder(String folderName) async {
    final folderPath = '${path ?? ''}/$folderName';
    await FileManager.createFolder(folderPath);
    findChildrenOfPath();
  }

  Future<void> _renameFolder(String folderName) async {
    final controller = TextEditingController(text: folderName);
    final colorScheme = Theme.of(context).colorScheme;

    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.2),
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (context, anim1, anim2) {
        return Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 100, left: 24, right: 24),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 340,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.home.renameFolder.renameFolder,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: t.home.renameFolder.folderName,
                        filled: true,
                        fillColor: colorScheme.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                          child: Text(
                            t.common.cancel,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            t.common.done,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOut),
          child: SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(0, -0.05),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
                ),
            child: child,
          ),
        );
      },
    );

    if (confirmed == true &&
        controller.text.isNotEmpty &&
        controller.text != folderName) {
      final oldPath = '${path ?? ''}/$folderName';
      final newPath = '${path ?? ''}/${controller.text}';

      final folderColors = stows.folderColors.value;
      if (folderColors.containsKey(oldPath)) {
        final newColors = <String, int>{...folderColors};
        newColors[newPath] = folderColors[oldPath]!;
        newColors.remove(oldPath);
        stows.folderColors.value = Map<String, int>.from(newColors);
      }

      await FileManager.renameDirectory(oldPath, controller.text);
      findChildrenOfPath();
    }
  }

  Future<void> _moveFolder(String folderName) async {
    final destination = await showDialog<String>(
      context: context,
      builder: (context) =>
          MoveFolderDialog(folderName: folderName, currentPath: path ?? '/'),
    );

    if (destination != null) {
      final oldPath = '${path ?? ''}/$folderName';

      final folderColors = stows.folderColors.value;
      if (folderColors.containsKey(oldPath)) {
        final newPath = p.join(destination, folderName);
        final newColors = <String, int>{...folderColors};
        newColors[newPath] = folderColors[oldPath]!;
        newColors.remove(oldPath);
        stows.folderColors.value = Map<String, int>.from(newColors);
      }

      await FileManager.moveDirectory(oldPath, destination);
      findChildrenOfPath();
    }
  }

  Future<void> _showAddLinkDialog() async {
    final targetPath = await showDialog<String>(
      context: context,
      builder: (context) => AddLinkDialog(currentPath: path ?? '/'),
    );
    if (targetPath != null && targetPath.isNotEmpty) {
      await FolderLinkManager.addLink(path ?? '/', targetPath);
      findChildrenOfPath();
    }
  }

  Future<void> _deleteFolderLink(String linkKey) async {
    await FolderLinkManager.removeLink(path ?? '/', linkKey);
    findChildrenOfPath();
  }

  Future<void> _deleteFolder(String folderName) async {
    final folderPath = '${path ?? ''}/$folderName';

    final children = await FileManager.getChildrenOfDirectory(folderPath);
    final isEmpty = children?.isEmpty == true;

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AdaptiveAlertDialog(
        title: Text(t.editor.selectionBar.delete),
        content: Text(
          isEmpty
              ? 'Delete folder "$folderName"?'
              : 'Folder "$folderName" is not empty. Delete anyway?',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.common.cancel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.editor.selectionBar.delete),
          ),
        ],
      ),
    );

    if (confirmed == true) {

      final folderColors = stows.folderColors.value;
      if (folderColors.containsKey(folderPath)) {
        final newColors = <String, int>{...folderColors};
        newColors.remove(folderPath);
        stows.folderColors.value = Map<String, int>.from(newColors);
      }
      await FileManager.deleteDirectory(folderPath);
      findChildrenOfPath();
    }
  }

  Future<void> _changeFolderColor(String folderName) async {
    final folderPath = '${path ?? ''}/$folderName';

    const colors = [
      Colors.red,
      Colors.pink,
      Colors.purple,
      Colors.deepPurple,
      Colors.indigo,
      Colors.blue,
      Colors.lightBlue,
      Colors.cyan,
      Colors.teal,
      Colors.green,
      Colors.lightGreen,
      Colors.lime,
      Colors.yellow,
      Colors.amber,
      Colors.orange,
      Colors.deepOrange,
      Colors.brown,
      Colors.blueGrey,
      Colors.grey,
    ];

    final newColor = await showDialog<Color>(
      context: context,
      builder: (context) => AdaptiveAlertDialog(
        title: Text(t.home.folderColorTitle),
        content: SingleChildScrollView(
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [

              InkWell(
                onTap: () => Navigator.pop(context, Colors.transparent),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: const Icon(Icons.format_color_reset, size: 20),
                ),
              ),
              for (final color in colors)
                InkWell(
                  onTap: () => Navigator.pop(context, color),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black12, width: 0.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: Text(t.common.cancel),
          ),
        ],
      ),
    );

    if (newColor != null) {
      final folderColors = Map<String, int>.from(stows.folderColors.value);

      if (newColor == Colors.transparent) {
        folderColors.remove(folderPath);
      } else {
        folderColors[folderPath] = newColor.toARGB32();
      }

      stows.folderColors.value = folderColors;
    }
  }

  Future<void> _exportFolderArchive(
    String folderName, {
    bool isLink = false,
    String? targetPath,
  }) async {
    final opts = await showFolderExportDialog(context, folderName);
    if (opts == null || !mounted) return;

    final folderPath = isLink ? targetPath : '${path ?? ''}/$folderName';
    if (folderPath == null || folderPath.isEmpty) return;

    final notePaths = await FileManager.getNotePathsInFolder(
      folderPath,
      archiveRootName: folderName,
    );
    if (!mounted) return;

    if (notePaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.export.exportFolderEmpty)),
      );
      return;
    }

    final navigator = Navigator.of(context, rootNavigator: true);
    var progressDialogVisible = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Theme.of(dialogContext).brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                      const SizedBox(width: 16),
                      Text(t.export.preparingExport),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ).whenComplete(() => progressDialogVisible = false),
    );
    await Future<void>.delayed(Duration.zero);

    try {
      final archive = await Future(() async {
        final archiveFiles = <ArchiveFile>[];
        final ext = opts.format == FolderExportContentFormat.sba ? 'sba' : 'pdf';

        for (var i = 0; i < notePaths.length; i++) {
          if (i > 0 && i % 3 == 0) await Future<void>.delayed(Duration.zero);

          final entry = notePaths[i];
          EditorCoreInfo coreInfo;
          try {
            coreInfo = await EditorCoreInfo.loadFromFilePath(entry.notePath);
          } catch (_) {
            continue;
          }

          final archiveFileName = '${entry.archivePath}.$ext';

          if (opts.format == FolderExportContentFormat.sba) {
            var sba = await coreInfo.saveToSba(
              currentPageIndex: null,
              omitLinksForExport: true,
              includeExportMetadata: opts.sbaIncludeExportMetadata,
            );
            if (opts.sbaPassword != null) {
              sba = SbaEncryption.encrypt(
                Uint8List.fromList(sba),
                opts.sbaPassword!,
              );
            }
            archiveFiles.add(
              ArchiveFile(archiveFileName, sba.length, sba),
            );
          } else {
            final invert = getEffectiveNoteInvertInDarkModeForFile(
              coreInfo.filePath,
            );
            final pdf = await EditorExporter.generatePdf(
              coreInfo,
              context,
              invert: invert,
            );
            final bytes = await pdf.save();
            archiveFiles.add(
              ArchiveFile(archiveFileName, bytes.length, bytes),
            );
          }
        }

        final archive = Archive();
        for (final dir in _uniqueParentDirs(archiveFiles.map((f) => f.name))) {
          archive.add(ArchiveFile.directory('$dir/'));
        }
        for (final f in archiveFiles) {
          archive.addFile(f);
        }

        return FileManager.encodeFolderArchive(archive, opts.container);
      });

      if (progressDialogVisible && navigator.mounted) navigator.pop();
      if (!mounted) return;

      final safeName = p.basename(folderName).replaceAll(RegExp(r'[^\w\-.]'), '_');
      await FileManager.exportFile(
        '$safeName.${opts.container.extension}',
        archive,
        context: context,
      );
    } catch (e) {
      if (progressDialogVisible && navigator.mounted) navigator.pop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.export.exportFailed(error: e))),
      );
    }
  }

  Set<String> _uniqueParentDirs(Iterable<String> paths) {
    final dirs = <String>{};
    for (final path in paths) {
      final parts = path.split('/');
      for (var i = 1; i < parts.length; i++) {
        dirs.add(parts.sublist(0, i).join('/'));
      }
    }
    return dirs;
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
              valueListenable: stows.homeBrowseTreeView,
              builder: (context, treeView, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable: stows.homeListMode,
                  builder: (context, listMode, _) {

                    final screenWidth = MediaQuery.sizeOf(context).width;
                    final folderGridCount = (screenWidth / 180).floor().clamp(
                      2,
                      6,
                    );
                    final notesCrossAxisCount = listMode
                        ? 1
                        : (screenWidth ~/ 200).clamp(1, 10);

                    return RefreshIndicator(
                      onRefresh: () => Future.wait([
                        findChildrenOfPath(),
                        Future.delayed(const Duration(milliseconds: 500)),
                      ]),
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        cacheExtent: 1000,
                        slivers: [

                          SliverAppBar(
                            collapsedHeight: kToolbarHeight,
                            expandedHeight: kToolbarHeight,
                            pinned: true,
                            scrolledUnderElevation: 2,
                            leading: null,
                            title: ValueListenableBuilder<String>(
                              valueListenable: _searchText,
                              builder: (context, currentSearchText, _) =>
                                  TextField(
                                    controller: _searchController,
                                    decoration: InputDecoration(
                                      hintText: t.home.titles.browse,
                                      border: InputBorder.none,
                                      prefixIcon: const Icon(Icons.search),
                                      suffixIcon: currentSearchText.isNotEmpty
                                          ? IconButton(
                                              icon: const Icon(Icons.clear),
                                              onPressed: () {
                                                _searchController.clear();
                                                _filterFiles('');
                                              },
                                            )
                                          : null,
                                    ),
                                  ),
                            ),
                            actions: [
                              IconButton(
                                tooltip: t.home.tooltips.viewMode,
                                icon: Icon(
                                  listMode ? Icons.grid_view : Icons.view_list,
                                ),
                                onPressed: () {
                                  stows.homeListMode.value = !listMode;
                                },
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.create_new_folder_outlined,
                                ),
                                tooltip: 'New Folder',
                                onPressed: () => showDialog(
                                  context: context,
                                  builder: (context) => NewFolderDialog(
                                    createFolder: createFolder,
                                    doesFolderExist: (String folderName) {
                                      return children?.directories.contains(
                                            folderName,
                                          ) ??
                                          false;
                                    },
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_link),
                                tooltip: 'Create Shortcut Link',
                                onPressed: _showAddLinkDialog,
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
                                sortContext: SortContext.browse,
                                callback: () async {
                                  if (SortNotes.isNeeded) {
                                    if (_isSearching) {
                                      await SortNotes.sortNotes(
                                        _filteredSearchFiles,
                                        context: SortContext.browse,
                                        forced: true,
                                      );
                                    } else {
                                      await findChildrenOfPath(fromSort: true);
                                    }
                                    setState(() {});
                                  }
                                },
                              ),
                            ],
                          ),

                          if (_isSearching) ...[
                            if (_searchFailed)
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Text(t.home.noNotesFound),
                                  ),
                                ),
                              )
                            else
                              SliverSafeArea(
                                top: false,
                                minimum: EdgeInsets.only(
                                  left: 16,
                                  right: 16,
                                  bottom: isSelecting ? 16 : 100,
                                ),
                                sliver: MasonryFiles(
                                  key: ValueKey(Object.hashAll([
                                    path ?? '',
                                    notesCrossAxisCount,
                                    ..._filteredSearchFiles.take(50),
                                  ])),
                                  crossAxisCount: notesCrossAxisCount,
                                  files: _filteredSearchFiles,
                                  selectedFiles: selectedFiles,
                                ),
                              ),
                          ] else ...[

                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: PathComponents(
                                  path,
                                  onPathComponentTap: onPathComponentTap,
                                ),
                              ),
                            ),

                            if (children == null)
                              const SliverFillRemaining(
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else if (children!.isEmpty)
                              const SliverFillRemaining(child: NoFiles())
                            else ...[

                              if (children!.directories.isNotEmpty ||
                                  children!.linkedDirectories.isNotEmpty) ...[
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      16,
                                      20,
                                      8,
                                    ),
                                    child: Text(
                                      'Folders',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            color: colorScheme.onSurface,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: -0.5,
                                          ),
                                    ),
                                  ),
                                ),

                                if (listMode)
                                  SliverList.separated(
                                    itemCount:
                                        children!.directories.length +
                                        children!.linkedDirectories.length,
                                    itemBuilder: (context, index) {
                                      final isLink =
                                          index >= children!.directories.length;
                                      final folderName = isLink
                                          ? children!.linkedDirectories.keys
                                                .elementAt(
                                                  index -
                                                      children!
                                                          .directories
                                                          .length,
                                                )
                                          : children!.directories[index];
                                      final targetPath = isLink
                                          ? children!
                                                .linkedDirectories[folderName]
                                          : null;
                                      return _buildFolderListTile(
                                        context,
                                        folderName,
                                        colorScheme,
                                        isLink: isLink,
                                        targetPath: targetPath,
                                      );
                                    },
                                    separatorBuilder: (context, index) =>
                                        const Divider(height: 1, indent: 72),
                                  )
                                else
                                  SliverPadding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    sliver: SliverGrid(
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: folderGridCount,
                                            mainAxisSpacing: 16,
                                            crossAxisSpacing: 16,
                                            childAspectRatio:
                                                0.85,
                                          ),
                                      delegate: SliverChildBuilderDelegate(
                                        (context, index) {
                                          final isLink =
                                              index >=
                                              children!.directories.length;
                                          final folderName = isLink
                                              ? children!.linkedDirectories.keys
                                                    .elementAt(
                                                      index -
                                                          children!
                                                              .directories
                                                              .length,
                                                    )
                                              : children!.directories[index];
                                          final targetPath = isLink
                                              ? children!
                                                    .linkedDirectories[folderName]
                                              : null;
                                          return _buildFolderGridCard(
                                            context,
                                            folderName,
                                            colorScheme,
                                            isLink: isLink,
                                            targetPath: targetPath,
                                          );
                                        },
                                        childCount:
                                            children!.directories.length +
                                            children!.linkedDirectories.length,
                                      ),
                                    ),
                                  ),
                              ],

                              if (_cachedNotesInCwd.isNotEmpty ||
                                  children!.linkedFiles.isNotEmpty) ...[
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      24,
                                      20,
                                      8,
                                    ),
                                    child: Text(
                                      'Notes',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            color: colorScheme.onSurface,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: -0.5,
                                          ),
                                    ),
                                  ),
                                ),
                                SliverSafeArea(
                                  top: false,
                                  minimum: EdgeInsets.only(
                                    left: 16,
                                    right: 16,
                                    bottom: isSelecting
                                        ? 16
                                        : 100,
                                  ),
                                  sliver: MasonryFiles(

                                    key: ValueKey(Object.hashAll([
                                      path ?? '',
                                      notesCrossAxisCount,
                                      ..._cachedNotesInCwd.take(50),
                                    ])),
                                    crossAxisCount: notesCrossAxisCount,
                                    files: _cachedNotesInCwd,
                                    linkedFiles: children!.linkedFiles,
                                    selectedFiles: selectedFiles,
                                    onDeleteLink: _deleteFolderLink,
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ],
                      ),
                    );
                  },
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
                              filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
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
                              onDeleted: findChildrenOfPath,
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
                              allFiles: _isSearching
                                  ? _filteredSearchFiles
                                  : _cachedNotesInCwd,
                              selectAll: () {
                                selectedFiles.value = List.from(
                                  _isSearching
                                      ? _filteredSearchFiles
                                      : _cachedNotesInCwd,
                                );
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
            : NewNoteButton(cupertino: platform.isCupertino, path: path),
      ),
    );
  }

  int _getFolderFileCountFromCache(String folderPath) {
    var normalized = FileManager.toRelativePath(folderPath);
    if (!normalized.endsWith('/')) normalized += '/';
    return _folderFileCounts[normalized] ?? 0;
  }

  Widget _buildFolderGridCard(
    BuildContext context,
    String folderName,
    ColorScheme colors, {
    bool isLink = false,
    String? targetPath,
  }) {
    return ValueListenableBuilder(
      valueListenable: stows.folderColors,
      builder: (context, folderColors, child) {
        final folderPath = isLink ? targetPath! : '${path ?? ''}/$folderName';
        final colorValue = folderColors[folderPath];
        final accentColor = colorValue != null
            ? Color(colorValue)
            : colors.primary;

        final isDark = Theme.of(context).brightness == Brightness.dark;

        return GestureDetector(
          onLongPressStart: (details) => _showFolderContextMenu(
            context,
            details.globalPosition,
            folderName,
            isLink: isLink,
            targetPath: targetPath,
          ),
          child: InkWell(
            onTap: () async {
              if (isLink) {
                if (!(await FileManager.isDirectory(targetPath!))) {
                  await FolderLinkManager.showBrokenLinkDialog(context);
                  await _deleteFolderLink(folderName);
                  return;
                }
                onPathComponentTap(targetPath);
              } else {
                onDirectoryTap(folderName);
              }
            },
            borderRadius: BorderRadius.circular(24),
            child: LayoutBuilder(
              builder: (context, constraints) {

                final scale = (constraints.maxWidth / 180.0).clamp(0.5, 1.5);

                return Container(
                  padding: EdgeInsets.all(20 * scale),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E1E1E)
                        : const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.15),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: EdgeInsets.all(12 * scale),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(16 * scale),
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Icon(
                                  CupertinoIcons.folder_fill,
                                  color: accentColor,
                                  size: 32 * scale,
                                ),
                                if (isLink)
                                  Positioned(
                                    bottom: -4,
                                    left: -4,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.surface,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.shortcut,
                                        size: 12 * scale,
                                        color: accentColor,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 10 * scale,
                              vertical: 6 * scale,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(12 * scale),
                            ),
                            child: Text(
                              '${_getFolderFileCountFromCache(folderPath)}',
                              style: TextStyle(
                                fontSize: 13 * scale,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Padding(
                        padding: EdgeInsets.only(top: 8.0 * scale),
                        child: Text(
                          folderName,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14 * scale,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                            letterSpacing: -0.3 * scale,
                            height:
                                1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildFolderListTile(
    BuildContext context,
    String folderName,
    ColorScheme colors, {
    bool isManaging = false,
    bool isLink = false,
    String? targetPath,
  }) {
    return ValueListenableBuilder(
      valueListenable: stows.folderColors,
      builder: (context, folderColors, child) {
        final folderPath = isLink ? targetPath! : '${path ?? ''}/$folderName';
        final colorValue = folderColors[folderPath];
        final folderColor = colorValue != null
            ? Color(colorValue)
            : colors.primary;

        return GestureDetector(
          onLongPressStart: (details) => _showFolderContextMenu(
            context,
            details.globalPosition,
            folderName,
            isLink: isLink,
            targetPath: targetPath,
          ),
          child: ListTile(
            onTap: isManaging
                ? null
                : () async {
                    if (isLink) {
                      if (!(await FileManager.isDirectory(targetPath!))) {
                        await FolderLinkManager.showBrokenLinkDialog(context);
                        await _deleteFolderLink(folderName);
                        return;
                      }
                      onPathComponentTap(targetPath);
                    } else {
                      onDirectoryTap(folderName);
                    }
                  },
            leading: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(Icons.folder, color: folderColor, size: 32),
                if (isLink)
                  Positioned(
                    bottom: -2,
                    left: -2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.shortcut, size: 12, color: folderColor),
                    ),
                  ),
              ],
            ),
            title: Text(
              folderName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            trailing: isManaging ? const Icon(Icons.drag_handle) : null,
          ),
        );
      },
    );
  }

  void _showFolderContextMenu(
    BuildContext context,
    Offset tapPosition,
    String folderName, {
    bool isLink = false,
    String? targetPath,
  }) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    final colorScheme = Theme.of(context).colorScheme;
    final value = await showMenu<String>(
      context: context,
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: colorScheme.surfaceContainerHigh,
      position: RelativeRect.fromRect(
        tapPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        if (!isLink)
          PopupMenuItem(
            value: 'rename',
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.pencil,
                  size: 20,
                  color: colorScheme.onSurface,
                ),
                const SizedBox(width: 16),
                Text(
                  t.home.renameFolder.renameFolder,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        if (!isLink)
          PopupMenuItem(
            value: 'move',
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.folder_badge_minus,
                  size: 20,
                  color: colorScheme.onSurface,
                ),
                const SizedBox(width: 16),
                Text(
                  t.editor.selectionBar.move,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        if (!isLink)
          PopupMenuItem(
            value: 'color',
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.paintbrush,
                  size: 20,
                  color: colorScheme.onSurface,
                ),
                const SizedBox(width: 16),
                Text(
                  t.home.color,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        if (!isLink)
          PopupMenuItem(
            value: 'properties',
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.info_circle,
                  size: 20,
                  color: colorScheme.onSurface,
                ),
                const SizedBox(width: 16),
                const Text(
                  'Properties',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'export',
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.archivebox,
                size: 20,
                color: colorScheme.onSurface,
              ),
              const SizedBox(width: 16),
              const Text(
                'Export Archive',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        if (!isLink) const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              const Icon(
                CupertinoIcons.delete,
                size: 20,
                color: Colors.redAccent,
              ),
              const SizedBox(width: 16),
              Text(
                isLink ? 'Remove Link' : t.editor.selectionBar.delete,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (value == 'rename') _renameFolder(folderName);
    if (value == 'move') _moveFolder(folderName);
    if (value == 'export') {
      await _exportFolderArchive(
        folderName,
        isLink: isLink,
        targetPath: targetPath,
      );
    }
    if (value == 'delete') {
      if (isLink) {
        await _deleteFolderLink(folderName);
      } else {
        _deleteFolder(folderName);
      }
    }
    if (value == 'color') _changeFolderColor(folderName);
    if (value == 'properties') _showFolderProperties(folderName);
  }

  void _showFolderProperties(String folderName) async {
    final folderPath = '${path ?? ''}/$folderName';
    final props = await FileManager.getFolderProperties(folderPath);

    if (!mounted) return;

    String sizeStr = 'Unknown';
    String createdStr = 'Unknown';
    String modifiedStr = 'Unknown';

    if (props != null) {
      final size = props['total_size'] as int? ?? 0;
      if (size < 1024)
        sizeStr = '$size B';
      else if (size < 1048576)
        sizeStr = '${(size / 1024).toStringAsFixed(1)} KB';
      else if (size < 1073741824)
        sizeStr = '${(size / 1048576).toStringAsFixed(1)} MB';
      else
        sizeStr = '${(size / 1073741824).toStringAsFixed(1)} GB';

      final created = props['created_at'] as int?;
      final modified = props['last_modified'] as int?;

      if (created != null) {
        createdStr = DateTime.fromMillisecondsSinceEpoch(
          created,
        ).toString().split('.')[0];
      }
      if (modified != null) {
        modifiedStr = DateTime.fromMillisecondsSinceEpoch(
          modified,
        ).toString().split('.')[0];
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Folder Properties'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Name: $folderName',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text('Path: $folderPath'),
            const SizedBox(height: 8),
            Text('Size: $sizeStr'),
            const SizedBox(height: 8),
            Text('Created: $createdStr'),
            const SizedBox(height: 8),
            Text('Modified: $modifiedStr'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.common.done),
          ),
        ],
      ),
    );
  }
}

class SamsungLeftShoulderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    final w = size.width;
    final h = size.height;
    const radius = 16.0;

    const slantWidth = 12.0;

    path.moveTo(0, h);

    path.lineTo(0, radius);

    path.quadraticBezierTo(0, 0, radius, 0);

    path.lineTo(w - slantWidth, 0);

    path.cubicTo(
      w - (slantWidth * 0.5),
      0,
      w - (slantWidth * 0.5),
      h,
      w,
      h,
    );

    path.lineTo(0, h);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class AddLinkDialog extends StatefulWidget {
  final String currentPath;
  const AddLinkDialog({super.key, required this.currentPath});

  @override
  State<AddLinkDialog> createState() => _AddLinkDialogState();
}

class _AddLinkDialogState extends State<AddLinkDialog> {
  bool _isLoading = true;
  List<String> _allPaths = [];
  List<String> _filteredPaths = [];
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPaths();
    _searchController.addListener(() {
      setState(() {
        final q = _searchController.text.toLowerCase();
        _filteredPaths = _allPaths
            .where((p) => p.toLowerCase().contains(q))
            .toList();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPaths() async {
    final paths = <String>[];
    final dirs = ['/'];

    while (dirs.isNotEmpty) {
      final current = dirs.removeLast();
      final children = await FileManager.getChildrenOfDirectory(
        current,
        includeExtensions: true,
      );
      if (children == null) continue;

      for (final dir in children.directories) {
        if (dir.startsWith('.'))
          continue;

        final p = current == '/' ? '/$dir' : '$current/$dir';
        dirs.add(p);

        final c = widget.currentPath;
        final isAncestorOrSelf = p == c || c.startsWith('$p/');
        if (!isAncestorOrSelf) {
          paths.add(p);
        }
      }
      for (final file in children.files) {
        if (file.startsWith('.')) continue;
        final p = current == '/' ? '/$file' : '$current/$file';
        paths.add(p);
      }
    }

    if (mounted) {
      setState(() {
        _allPaths = paths;
        _filteredPaths = paths;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Create Shortcut Link'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search files and folders...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _filteredPaths.length,
                      itemBuilder: (context, index) {
                        final path = _filteredPaths[index];
                        final isFile =
                            path.endsWith('.sbn') ||
                            path.endsWith('.sbn2') ||
                            path.endsWith('.pdf');
                        return ListTile(
                          leading: Icon(
                            isFile ? Icons.insert_drive_file : Icons.folder,
                            color: colorScheme.primary,
                          ),
                          title: Text(
                            path.split('/').last,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.pop(context, path),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class SamsungRightTabClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    final w = size.width;
    final h = size.height;

    const radius = 16.0;
    const slantWidth = 12.0;

    path.moveTo(slantWidth, h);

    path.cubicTo(
      slantWidth * 0.5,
      h,
      slantWidth * 0.5,
      0,
      0,
      0,
    );

    path.lineTo(w - radius, 0);

    path.quadraticBezierTo(w, 0, w, radius);

    path.lineTo(w, h);

    path.lineTo(slantWidth, h);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
