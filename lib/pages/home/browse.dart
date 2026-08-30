// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io' show File;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:collapsible/collapsible.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:saber/components/editor/folder_export_dialog.dart';
import 'package:saber/components/editor/note_properties_dialog.dart';
import 'package:saber/components/home/browse_folder_list_row.dart';
import 'package:saber/components/home/delete_note_button.dart';
import 'package:saber/components/home/export_note_button.dart';
import 'package:saber/components/home/home_selection_action_bar.dart';
import 'package:saber/components/home/home_toolbar_chrome.dart';
import 'package:saber/components/home/masonry_files.dart';
import 'package:saber/components/home/move_folder_button.dart';
import 'package:saber/components/home/move_note_button.dart';
import 'package:saber/components/home/new_folder_dialog.dart';
import 'package:saber/components/home/new_note_button.dart';
import 'package:saber/components/home/no_files.dart';
import 'package:saber/components/home/path_components.dart';
import 'package:saber/components/home/rename_folder_button.dart';
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
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:saber/services/vault_adapter.dart';
import 'package:uuid/uuid.dart';

/// Add parent directory markers for [posixEntryPath] (e.g. `a/b/c.pdf` → `a/`, `a/b/`).
void _ensureZipParentDirs(
  ZipFileEncoder encoder,
  Set<String> added,
  String posixEntryPath,
) {
  final parts = posixEntryPath.split('/');
  if (parts.length <= 1) return;
  for (var i = 0; i < parts.length - 1; i++) {
    final dir = '${parts.take(i + 1).join('/')}/';
    if (added.add(dir)) {
      encoder.addArchiveFile(ArchiveFile.directory(dir));
    }
  }
}

/// Stream one on-disk file into [encoder] using ZIP *store* (no deflate buffer).
Future<void> _addStoredFileToZip(
  ZipFileEncoder encoder,
  String diskPath,
  String entryName,
) async {
  final file = File(diskPath);
  final stream = InputFileStream(diskPath);
  final archiveFile = ArchiveFile.stream(entryName, stream);
  archiveFile.lastModTime =
      (await file.lastModified()).millisecondsSinceEpoch ~/ 1000;
  archiveFile.mode = (await file.stat()).mode;
  archiveFile.compression = CompressionType.none;
  encoder.addArchiveFile(archiveFile);
  await stream.close();
}

Set<String> _uniqueParentDirsForFolderArchive(Iterable<String> paths) {
  final dirs = <String>{};
  for (final path in paths) {
    final parts = path.split('/');
    for (var i = 1; i < parts.length; i++) {
      dirs.add(parts.sublist(0, i).join('/'));
    }
  }
  return dirs;
}

/// Builds the folder archive (zip streams large PDFs from disk; tar.xz builds in memory).
Future<void> _runFolderExportBody({
  required ({
    FolderExportContentFormat format,
    FolderArchiveFormat container,
    String? sbaPassword,
    bool sbaIncludeExportMetadata,
  })
  opts,
  required List<({String notePath, String archivePath})> notePaths,
  required String safeName,
  required String? saveToPath,
  required BuildContext context,
  required BuildContext pdfContext,
  required void Function(double progress, String message) onProgress,
}) async {
  final n = math.max(notePaths.length, 1);
  final tempDir = await getTemporaryDirectory();

  void report(double t, String msg) => onProgress(t.clamp(0.0, 0.99), msg);

  double noteBase(int i) => 0.05 + 0.85 * (i / n);

  if (opts.container == FolderArchiveFormat.zip) {
    final zipPath = p.join(
      tempDir.path,
      'saber_folder_${const Uuid().v4()}.zip',
    );
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    final addedZipDirs = <String>{};
    try {
      final ext = opts.format == FolderExportContentFormat.sba ? 'sba' : 'pdf';

      for (var i = 0; i < notePaths.length; i++) {
        if (i > 0 && i % 3 == 0) await Future<void>.delayed(Duration.zero);
        if (!context.mounted) break;

        final entry = notePaths[i];
        report(noteBase(i), entry.archivePath);

        EditorCoreInfo coreInfo;
        try {
          coreInfo = await EditorCoreInfo.loadFromFilePath(entry.notePath);
        } catch (_) {
          continue;
        }

        if (!context.mounted) break;

        final archiveFileName = '${entry.archivePath}.$ext';
        _ensureZipParentDirs(encoder, addedZipDirs, archiveFileName);

        if (opts.format == FolderExportContentFormat.sba) {
          var sba = await coreInfo.saveToSba(
            currentPageIndex: null,
            omitLinksForExport: true,
            includeExportMetadata: opts.sbaIncludeExportMetadata,
          );
          if (opts.sbaPassword != null) {
            sba = await SbaEncryption.encryptForExport(
              Uint8List.fromList(sba),
              opts.sbaPassword!,
            );
          }
          final tmp = File(
            p.join(tempDir.path, 'saber_export_${const Uuid().v4()}.$ext'),
          );
          try {
            await tmp.writeAsBytes(sba, flush: true);
            await _addStoredFileToZip(encoder, tmp.path, archiveFileName);
          } finally {
            try {
              await tmp.delete();
            } catch (_) {}
          }
        } else {
          if (!pdfContext.mounted) break;
          final invert = getEffectiveNoteInvertInDarkModeForFile(
            coreInfo.filePath,
          );
          final data = await EditorExporter.generatePdfData(
            coreInfo,
            pdfContext,
            invert: invert,
            onProgress: (done, total) {
              final span = 0.85 / n;
              final tot = math.max(total, 1);
              report(
                noteBase(i) + span * (done / tot),
                '${entry.archivePath} $done/$total',
              );
            },
          );
          if (data.tempPdfPath != null) {
            final pdfPath = data.tempPdfPath!;
            try {
              await _addStoredFileToZip(encoder, pdfPath, archiveFileName);
            } finally {
              try {
                await File(pdfPath).delete();
              } catch (_) {}
            }
          } else {
            final tmp = File(
              p.join(tempDir.path, 'saber_export_${const Uuid().v4()}.pdf'),
            );
            try {
              await tmp.writeAsBytes(data.bytes!, flush: true);
              await _addStoredFileToZip(encoder, tmp.path, archiveFileName);
            } finally {
              try {
                await tmp.delete();
              } catch (_) {}
            }
          }
        }
      }

      await encoder.close();
    } catch (e) {
      try {
        await encoder.close();
      } catch (_) {}
      try {
        await File(zipPath).delete();
      } catch (_) {}
      rethrow;
    }

    if (!context.mounted) return;
    report(0.96, safeName);
    await FileManager.exportTempFile(
      zipPath,
      '$safeName.${opts.container.extension}',
      saveToPath: saveToPath,
      context: context,
    );
  } else {
    final archiveFiles = <ArchiveFile>[];
    final ext = opts.format == FolderExportContentFormat.sba ? 'sba' : 'pdf';

    for (var i = 0; i < notePaths.length; i++) {
      if (i > 0 && i % 3 == 0) await Future<void>.delayed(Duration.zero);
      if (!context.mounted) break;

      final entry = notePaths[i];
      report(noteBase(i), entry.archivePath);

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
          sba = await SbaEncryption.encryptForExport(
            Uint8List.fromList(sba),
            opts.sbaPassword!,
          );
        }
        archiveFiles.add(ArchiveFile(archiveFileName, sba.length, sba));
      } else {
        if (!pdfContext.mounted) break;
        final invert = getEffectiveNoteInvertInDarkModeForFile(
          coreInfo.filePath,
        );
        final data = await EditorExporter.generatePdfData(
          coreInfo,
          pdfContext,
          invert: invert,
          onProgress: (done, total) {
            final span = 0.85 / n;
            final tot = math.max(total, 1);
            report(
              noteBase(i) + span * (done / tot),
              '${entry.archivePath} $done/$total',
            );
          },
        );
        final List<int> bytes;
        if (data.bytes != null) {
          bytes = data.bytes!;
        } else {
          final pdfTemp = data.tempPdfPath!;
          try {
            bytes = await File(pdfTemp).readAsBytes();
          } finally {
            try {
              await File(pdfTemp).delete();
            } catch (_) {}
          }
        }
        archiveFiles.add(ArchiveFile(archiveFileName, bytes.length, bytes));
      }
    }

    final archive = Archive();
    for (final dir in _uniqueParentDirsForFolderArchive(
      archiveFiles.map((f) => f.name),
    )) {
      archive.add(ArchiveFile.directory('$dir/'));
    }
    for (final f in archiveFiles) {
      archive.addFile(f);
    }

    if (!context.mounted) return;
    report(0.92, safeName);
    final archiveBytes = await FileManager.encodeFolderArchiveAsync(
      archive,
      opts.container,
    );
    if (!context.mounted) return;
    report(0.96, safeName);
    await FileManager.exportFile(
      '$safeName.${opts.container.extension}',
      archiveBytes,
      saveToPath: saveToPath,
      context: context,
    );
  }
}

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
      _fileWriteDebounce = Timer(const Duration(milliseconds: 320), () {
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
      // Invalida o cache para qualquer pasta, garantindo que o listener atualize a UI
      HomeDataCache.instance.invalidate();
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
          final val = entry.value.toLowerCase();
          if (val.endsWith('.sbn') ||
              val.endsWith('.sbn2') ||
              val.endsWith('.pdf')) {
            linkedFiles[entry.key] = entry.value;
          } else {
            linkedDirs[entry.key] = entry.value;
          }
        }
      } catch (e) {}

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
        
        try {
          await SortNotes.sortNotes(
            linkedPaths,
            context: SortContext.browse,
            forced: true,
          );
        } catch (e) {
        }
        
        Map<String, String> sortedLinkedDirs = {};
        for (var p in linkedPaths) {
          final key = pathToName[p];
          if (key != null) sortedLinkedDirs[key] = p;
        }
        linkedDirs = sortedLinkedDirs;
      }

      Map<String, int> extraCounts = {};
      if (linkedDirs.isNotEmpty) {
        try {
          extraCounts = await FileManager.getFolderFileCountsBatch(
            linkedDirs.values.toList(),
          );
        } catch (e) {
          FileManager.log.warning('Failed to get extra counts for links: $e');
        }
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
        final val = entry.value.toLowerCase();
        if (val.endsWith('.sbn') ||
            val.endsWith('.sbn2') ||
            val.endsWith('.pdf')) {
          linkedFiles[entry.key] = entry.value;
        } else {
          linkedDirs[entry.key] = entry.value;
        }
      }
    } catch (e) {}

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
        
        try {
          await SortNotes.sortNotes(
            linkedPaths,
            context: SortContext.browse,
            forced: true,
          );
        } catch (e) {
        }
        
        Map<String, String> sortedLinkedDirs = {};
        for (var p in linkedPaths) {
          final key = pathToName[p];
          if (key != null) sortedLinkedDirs[key] = p;
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

      try {
        final folderPaths = [
          for (final folderName in filteredDirs) '${path ?? ''}/$folderName',
          for (final linkPath in linkedDirs.values) linkPath,
        ];
        final countResults = await Future.wait([
          FileManager.getFolderFileCountsBatch(folderPaths),
          FileManager.getTotalFileCount(),
        ]);
        folderCounts = countResults[0] as Map<String, int>;
      } catch (e) {
        FileManager.log.warning('Failed to fetch folder counts: $e');
      }

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
      path = p.dirname(path ?? '/').replaceAll('\\', '/');
      if (path == '/') path = null;
    } else {
      // Force POSIX separators (/) instead of platform-specific p.join
      // so path matching inside subfolders works correctly for links.
      path = path == null || path == '/' ? '/$folder' : '$path/$folder';
    }

    if (oldPath != path) {
      context.go(HomeRoutes.browseFilePath(path ?? '/'));
    }
  }

  void onPathComponentTap(String? newPath) {
    selectedFiles.value = [];
    if (newPath == null || newPath.isEmpty || newPath == '/') {
      newPath = null;
    } else {
      newPath = newPath.replaceAll('\\', '/');
      if (newPath.length > 1 && newPath.endsWith('/')) {
        newPath = newPath.substring(0, newPath.length - 1);
      }
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
    if (!mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.1),
      pageBuilder: (context, _, __) {
        return RenameFolderDialog(
          folderName: folderName,
          doesFolderExist: (name) {
            if (name == folderName) return false;
            final c = children;
            if (c == null) return false;
            return c.directories.contains(name) ||
                c.linkedDirectories.containsKey(name);
          },
          renameFolder: (newName) async {
            final oldPath = '${path ?? ''}/$folderName';
            final newPath = '${path ?? ''}/$newName';

            final folderColors = stows.folderColors.value;
            if (folderColors.containsKey(oldPath)) {
              final newColors = <String, int>{...folderColors};
              newColors[newPath] = folderColors[oldPath]!;
              newColors.remove(oldPath);
              stows.folderColors.value = Map<String, int>.from(newColors);
            }

            await FileManager.renameDirectory(oldPath, newName);
            findChildrenOfPath();
          },
        );
      },
    );
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
        final newPath = p.join(destination, folderName).replaceAll('\\', '/');
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
      // Força a invalidação agressiva do cache global para refletir o novo link imediatamente
      HomeDataCache.instance.invalidate();
      // Dá um breve tempo para o arquivo ser escrito no disco antes de recarregar
      await Future.delayed(const Duration(milliseconds: 200));
      await findChildrenOfPath();
      if (mounted) setState(() {});
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

    // Paleta expandida organizada como um "swatch board" profissional (Tons primários e tons pasteis)
    const colors = [
      Color(0xFFF44336),
      Color(0xFFE91E63),
      Color(0xFF9C27B0),
      Color(0xFF673AB7),
      Color(0xFF3F51B5),
      Color(0xFF2196F3),
      Color(0xFF03A9F4),
      Color(0xFF00BCD4),
      Color(0xFF009688),
      Color(0xFF4CAF50),
      Color(0xFF8BC34A),
      Color(0xFFCDDC39),
      Color(0xFFFFEB3B),
      Color(0xFFFFC107),
      Color(0xFFFF9800),
      Color(0xFFFF5722),
      Color(0xFF795548),
      Color(0xFF9E9E9E),
      Color(0xFF607D8B),
      Color(0xFF000000),

      Color(0xFFEF9A9A),
      Color(0xFFF48FB1),
      Color(0xFFCE93D8),
      Color(0xFFB39DDB),
      Color(0xFF9FA8DA),
      Color(0xFF90CAF9),
      Color(0xFF81D4FA),
      Color(0xFF80DEEA),
      Color(0xFF80CBC4),
      Color(0xFFA5D6A7),
      Color(0xFFC5E1A5),
      Color(0xFFE6EE9C),
      Color(0xFFFFF59D),
      Color(0xFFFFE082),
      Color(0xFFFFCC80),
      Color(0xFFFFAB91),
      Color(0xFFBCAAA4),
      Color(0xFFEEEEEE),
      Color(0xFFB0BEC5),
      Color(0xFFFFFFFF),
    ];

    final currentColorValue = stows.folderColors.value[folderPath];
    final currentColor = currentColorValue != null
        ? Color(currentColorValue)
        : null;

    final newColor = await showDialog<Color>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.all(24),
          child: Container(
            width: 360, // Janela mais concisa
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t.home.folderColorTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.35,
                  ),
                ),
                const SizedBox(height: 20),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    itemCount: colors.length + 1,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 8,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                        ),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        // Botão para remover a cor / cor padrão
                        final isSelected = currentColor == null;
                        return InkWell(
                          onTap: () =>
                              Navigator.pop(context, Colors.transparent),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : theme.dividerColor,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Icon(
                              Icons.format_color_reset_rounded,
                              size: 18,
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      }

                      final color = colors[index - 1];
                      final isSelected = currentColor?.value == color.value;
                      final isWhite = color == const Color(0xFFFFFFFF);

                      return InkWell(
                        onTap: () => Navigator.pop(context, color),
                        borderRadius: BorderRadius.circular(8),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? (isDark ? Colors.white : Colors.black87)
                                  : (isWhite
                                        ? Colors.black12
                                        : Colors.transparent),
                              width: isSelected ? 2.5 : 1,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: color.withValues(alpha: 0.4),
                                      blurRadius: 6,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                          child: isSelected
                              ? Icon(
                                  Icons.check_rounded,
                                  color: color.computeLuminance() > 0.5
                                      ? Colors.black87
                                      : Colors.white,
                                  size: 16,
                                )
                              : null,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: () => Navigator.pop(context),
                    child: Text(t.common.cancel),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.export.exportFolderEmpty)));
      return;
    }

    final saveToPath = stows.defaultExportPath.value.isNotEmpty
        ? stows.defaultExportPath.value
        : null;

    final safeName = p
        .basename(folderName)
        .replaceAll(RegExp(r'[^\w\-.]'), '_');

    final pdfContext =
        Navigator.of(context, rootNavigator: true).overlay?.context ?? context;

    try {
      await ExportManager.exportInBackground(t.export.exportFolder, (
        onProgress,
      ) async {
        VaultAdapter.preventLock = true;
        try {
          onProgress(0.02, t.export.preparingExport);
          await _runFolderExportBody(
            opts: opts,
            notePaths: notePaths,
            safeName: safeName,
            saveToPath: saveToPath,
            context: context,
            pdfContext: pdfContext,
            onProgress: onProgress,
          );
        } finally {
          VaultAdapter.preventLock = false;
        }
        if (context.mounted) {
          onProgress(1.0, t.export.exportComplete);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t.export.exportComplete)));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.export.exportFailed(error: e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final platform = theme.platform;
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

                    final isDark =
                        Theme.of(context).brightness == Brightness.dark;

                    return CustomPaint(
                      painter: _WorkspaceBackgroundPainter(
                        isDark
                            // Increased opacity for better depth visibility in dark mode
                            ? Colors.white.withValues(alpha: 0.12)
                            // Increased opacity for better depth visibility in light mode
                            : Colors.black.withValues(alpha: 0.08),
                      ),
                      child: RefreshIndicator(
                        onRefresh: () => Future.wait([
                          findChildrenOfPath(),
                          Future.delayed(const Duration(milliseconds: 500)),
                        ]),
                        child: CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          cacheExtent: 1000,
                          slivers: [
                            SliverAppBar(
                              primary: false,
                              pinned: true,
                              toolbarHeight: kBrowseAppBarToolbarHeight,
                              collapsedHeight: kBrowseAppBarToolbarHeight,
                              expandedHeight: kBrowseAppBarToolbarHeight,
                              scrolledUnderElevation: 2,
                              surfaceTintColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              leading: null,
                              titleSpacing: 16,
                              backgroundColor: homeAppBarBackgroundColor(
                                context,
                              ),
                              title: ValueListenableBuilder<String>(
                                valueListenable: _searchText,
                                builder: (context, currentSearchText, _) {
                                  return TextField(
                                    controller: _searchController,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: colorScheme.onSurface,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: t.home.titles.browse,
                                      hintStyle: theme.textTheme.bodyLarge
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                      prefixIcon: Icon(
                                        Icons.search,
                                        color: colorScheme.onSurfaceVariant,
                                        size: 22,
                                      ),
                                      suffixIcon: currentSearchText.isNotEmpty
                                          ? IconButton(
                                              style:
                                                  homeToolbarCompactIconStyle(
                                                    context,
                                                  ),
                                              icon: const Icon(Icons.clear),
                                              onPressed: () {
                                                _searchController.clear();
                                                _filterFiles('');
                                              },
                                            )
                                          : null,
                                    ),
                                  );
                                },
                              ),
                              actions: [
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    end: 12,
                                  ),
                                  child: ValueListenableBuilder<bool>(
                                    valueListenable:
                                        stows.localEncryptionEnabled,
                                    builder: (context, encryptionOn, _) {
                                      return ValueListenableBuilder<bool>(
                                        valueListenable:
                                            VaultAdapter.unlockListenable,
                                        builder: (context, vaultUnlocked, _) {
                                          return _BrowseToolbarActionsStrip(
                                            listMode: listMode,
                                            glassStripHeight: 54,
                                            showVaultLock:
                                                encryptionOn && vaultUnlocked,
                                            onToggleViewMode: () {
                                              stows.homeListMode.value =
                                                  !listMode;
                                            },
                                            onNewFolder: () => showDialog(
                                              context: context,
                                              builder: (context) =>
                                                  NewFolderDialog(
                                                    createFolder: createFolder,
                                                    doesFolderExist:
                                                        (String folderName) {
                                                          return children
                                                                  ?.directories
                                                                  .contains(
                                                                    folderName,
                                                                  ) ??
                                                              false;
                                                        },
                                                  ),
                                            ),
                                            onAddLink: _showAddLinkDialog,
                                            onLockVault: () {
                                              unawaited(
                                                VaultAdapter.lockAndGoToLogin(),
                                              );
                                            },
                                            sortButton: SortButton(
                                              sortContext: SortContext.browse,
                                              callback: () async {
                                                if (SortNotes.isNeeded) {
                                                  if (_isSearching) {
                                                    await SortNotes.sortNotes(
                                                      _filteredSearchFiles,
                                                      context:
                                                          SortContext.browse,
                                                      forced: true,
                                                    );
                                                  } else {
                                                    await findChildrenOfPath(
                                                      fromSort: true,
                                                    );
                                                  }
                                                  setState(() {});
                                                }
                                              },
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
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
                                    key: ValueKey(
                                      'browse_search_${path ?? ''}_$notesCrossAxisCount',
                                    ),
                                    crossAxisCount: notesCrossAxisCount,
                                    files: _filteredSearchFiles,
                                    selectedFiles: selectedFiles,
                                  ),
                                ),
                            ] else ...[
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    16,
                                    12,
                                  ),
                                  child: PathComponents(
                                    path,
                                    trailingSectionLabel:
                                        children != null &&
                                            (_cachedNotesInCwd.isNotEmpty ||
                                                children!
                                                    .linkedFiles
                                                    .isNotEmpty)
                                        ? 'Notes'
                                        : null,
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
                                    SliverPadding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        0,
                                        16,
                                        4,
                                      ),
                                      sliver: SliverList.separated(
                                        itemCount:
                                            children!.directories.length +
                                            children!.linkedDirectories.length,
                                        itemBuilder: (context, index) {
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
                                          final folderPath = isLink
                                              ? targetPath!
                                              : '${path ?? ''}/$folderName';
                                          return ValueListenableBuilder(
                                            valueListenable: stows.folderColors,
                                            builder: (context, folderColors, _) {
                                              final colorValue =
                                                  folderColors[folderPath];
                                              final folderColor =
                                                  colorValue != null
                                                  ? Color(colorValue)
                                                  : colorScheme.primary;
                                                  
                                              // We use BrowseFolderListRow instead of the custom Row
                                              // to display rich metadata like Size and Last Modified.
                                              return BrowseFolderListRow(
                                                folderName: folderName,
                                                folderPath: folderPath,
                                                accentColor: folderColor,
                                                isLink: isLink,
                                                isManaging: _isManagingFolders,
                                                cachedNoteCount: _getFolderFileCountFromCache(folderPath),
                                                onLongPressStart: (details) =>
                                                    _showFolderContextMenu(
                                                      context,
                                                      details.globalPosition,
                                                      folderName,
                                                      isLink: isLink,
                                                      targetPath: targetPath,
                                                    ),
                                                onTap: () async {
                                                  if (isLink) {
                                                    if (!(await FileManager.isDirectory(
                                                      targetPath!,
                                                    ))) {
                                                      await FolderLinkManager.showBrokenLinkDialog(
                                                        context,
                                                      );
                                                      await _deleteFolderLink(
                                                        folderName,
                                                      );
                                                      return;
                                                    }
                                                    onPathComponentTap(
                                                      targetPath,
                                                    );
                                                  } else {
                                                    onDirectoryTap(
                                                      folderName,
                                                    );
                                                  }
                                                },
                                              );
                                            },
                                          );
                                        },
                                        separatorBuilder: (context, index) =>
                                            const SizedBox.shrink(),
                                      ),
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
                                              childAspectRatio: 0.85,
                                            ),
                                        delegate: SliverChildBuilderDelegate(
                                          (context, index) {
                                            final isLink =
                                                index >=
                                                children!.directories.length;
                                            final folderName = isLink
                                                ? children!
                                                      .linkedDirectories
                                                      .keys
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
                                              children!
                                                  .linkedDirectories
                                                  .length,
                                        ),
                                      ),
                                    ),
                                ],

                                if (_cachedNotesInCwd.isNotEmpty ||
                                    children!.linkedFiles.isNotEmpty) ...[
                                  SliverSafeArea(
                                    top: false,
                                    minimum: EdgeInsets.only(
                                      left: 16,
                                      right: 16,
                                      bottom: isSelecting ? 16 : 100,
                                    ),
                                    sliver: MasonryFiles(
                                      key: ValueKey(
                                        'browse_notes_${path ?? ''}_$notesCrossAxisCount',
                                      ),
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
                        onDeleted: findChildrenOfPath,
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
              )
            : null,
        floatingActionButton: isSelecting
            ? null
            : NewNoteButton(cupertino: platform.isCupertino, path: path),
      ),
    );
  }

  int _getFolderFileCountFromCache(String folderPath) {
    final normalized = FileManager.normalizeFolderCountPath(folderPath);
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

        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          builder: (context, anim, child) {
            return Transform.scale(
              scale: 0.95 + (0.05 * anim),
              child: Opacity(opacity: anim, child: child),
            );
          },
          child: GestureDetector(
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
              borderRadius: BorderRadius.circular(12),
              splashColor: accentColor.withValues(alpha: 0.1),
              highlightColor: accentColor.withValues(alpha: 0.05),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scale = (constraints.maxWidth / 180.0).clamp(0.5, 1.5);

                  return Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 8 * scale,
                      vertical: 12 * scale,
                    ),
                    color:
                        Colors.transparent, // Nenhuma caixa prendendo a pasta
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Pasta desenhada diretamente no Flutter (Mac/Windows Desktop Style)
                        SizedBox(
                          width: 72 * scale,
                          height: 56 * scale,
                          child: Stack(
                            alignment: Alignment.bottomCenter,
                            clipBehavior: Clip.none,
                            children: [
                              // Aba Traseira da Pasta
                              Positioned(
                                top: 0,
                                left: 0,
                                right: 28 * scale,
                                bottom: 10 * scale,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(6 * scale),
                                    ),
                                  ),
                                ),
                              ),
                              // Aba Frontal da Pasta com Relevo
                              Positioned(
                                top: 12 * scale,
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        accentColor.withValues(alpha: 0.75),
                                        accentColor,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      6 * scale,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: accentColor.withValues(
                                          alpha: 0.35,
                                        ),
                                        blurRadius: 12 * scale,
                                        offset: Offset(0, 6 * scale),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (isLink)
                                Positioned(
                                  bottom: -4 * scale,
                                  left: -4 * scale,
                                  child: Container(
                                    padding: EdgeInsets.all(4 * scale),
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surface,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.15,
                                          ),
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      Icons.shortcut_rounded,
                                      size: 14 * scale,
                                      color: accentColor,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        SizedBox(height: 16 * scale),
                        Text(
                          folderName,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13 * scale,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurface,
                            height: 1.2,
                          ),
                        ),
                        SizedBox(height: 4 * scale),
                        Text(
                          '${_getFolderFileCountFromCache(folderPath)} itens',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11 * scale,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
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
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kSaberContainerRadius),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.18),
        ),
      ),
      color: homeAppBarBackgroundColor(context),
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

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        child: RuggedDialogShell(
          maxWidth: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t.home.properties,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.35,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                folderName,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              _BrowseFolderPropRow(
                icon: Icons.folder_outlined,
                label: t.home.path,
                value: folderPath,
              ),
              _BrowseFolderPropRow(
                icon: Icons.sd_storage_outlined,
                label: t.home.size,
                value: sizeStr,
              ),
              _BrowseFolderPropRow(
                icon: Icons.calendar_today_outlined,
                label: 'Created',
                value: createdStr,
              ),
              _BrowseFolderPropRow(
                icon: Icons.edit_note_outlined,
                label: t.home.lastModified,
                value: modifiedStr,
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(t.common.done),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrowseFolderPropRow extends StatelessWidget {
  const _BrowseFolderPropRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: SelectableText(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
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

    path.cubicTo(w - (slantWidth * 0.5), 0, w - (slantWidth * 0.5), h, w, h);

    path.lineTo(0, h);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class _WorkspaceBackgroundPainter extends CustomPainter {
  final Color color;
  _WorkspaceBackgroundPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    const spacing = 24.0;
    for (var x = 0.0; x < size.width; x += spacing) {
      for (var y = 0.0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
    try {
      final paths = <String>[];
      final dirs = ['/'];

      // Recursive directory traversal
      while (dirs.isNotEmpty) {
        final current = dirs.removeLast();
        final children = await FileManager.getChildrenOfDirectory(
          current,
          includeExtensions: true,
        );
        if (children == null) continue;

        for (final dir in children.directories) {
          if (dir.startsWith('.')) continue;

          final p = current == '/' ? '/$dir' : '$current/$dir';
          dirs.add(p);

          final c = widget.currentPath.replaceAll('\\', '/');
          final isAncestorOrSelf = p == c || c.startsWith('$p/');
          if (!isAncestorOrSelf && p != '/') {
            paths.add(p);
          }
        }
        for (final file in children.files) {
          if (file.startsWith('.')) continue;
          final p = current == '/' ? '/$file' : '$current/$file';
          paths.add(p);
        }
      }
      
      paths.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      
      if (mounted) {
        setState(() {
          _allPaths = paths;
          _filteredPaths = paths;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: RuggedDialogShell(
        maxWidth: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Create Shortcut Link',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: -0.35,
              ),
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search files and folders...',
                  prefixIcon: Icon(Icons.search, color: colorScheme.onSurfaceVariant),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Material(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  height: 300,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.builder(
                    itemCount: _filteredPaths.length,
                    itemBuilder: (context, index) {
                      final path = _filteredPaths[index];
                      final isFile =
                          path.endsWith('.sbn') ||
                          path.endsWith('.sbn2') ||
                          path.endsWith('.pdf');
                      return InkWell(
                          onTap: () => Navigator.pop(context, path),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Icon(
                                  isFile ? Icons.insert_drive_file_outlined : Icons.folder_outlined,
                                  color: colorScheme.primary,
                                  size: 22,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        path.split('/').last,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        path,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                    },
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: () => Navigator.pop(context),
                child: Text(t.common.cancel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrowseToolbarActionsStrip extends StatelessWidget {
  const _BrowseToolbarActionsStrip({
    required this.listMode,
    this.glassStripHeight = 48,
    required this.showVaultLock,
    required this.onToggleViewMode,
    required this.onNewFolder,
    required this.onAddLink,
    required this.onLockVault,
    required this.sortButton,
  });

  final bool listMode;
  final double glassStripHeight;
  final bool showVaultLock;
  final VoidCallback onToggleViewMode;
  final VoidCallback onNewFolder;
  final VoidCallback onAddLink;
  final VoidCallback onLockVault;
  final Widget sortButton;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final actionStyle = homeToolbarCompactIconStyle(context);

    return HomeGlassIconStrip(
      height: glassStripHeight,
      children: [
        IconButton(
          style: actionStyle,
          tooltip: t.home.tooltips.viewMode,
          onPressed: onToggleViewMode,
          icon: Icon(
            listMode ? Icons.grid_view_rounded : Icons.view_list_rounded,
            size: 22,
          ),
        ),
        const HomeToolbarDivider(),
        IconButton(
          style: actionStyle,
          icon: const Icon(Icons.create_new_folder_outlined, size: 22),
          tooltip: 'New Folder',
          onPressed: onNewFolder,
        ),
        const HomeToolbarDivider(),
        IconButton(
          style: actionStyle,
          icon: const Icon(Icons.add_link, size: 22),
          tooltip: 'Create Shortcut Link',
          onPressed: onAddLink,
        ),
        if (showVaultLock) ...[
          const HomeToolbarDivider(),
          IconButton(
            style: actionStyle.copyWith(
              foregroundColor: WidgetStatePropertyAll(colorScheme.primary),
            ),
            tooltip: 'Lock Vault',
            onPressed: onLockVault,
            icon: const Icon(Icons.power_settings_new, size: 22),
          ),
        ],
        const HomeToolbarDivider(),
        IconTheme.merge(
          data: IconThemeData(size: 22, color: colorScheme.onSurfaceVariant),
          child: Theme(
            data: theme.copyWith(
              iconButtonTheme: IconButtonThemeData(style: actionStyle),
            ),
            child: sortButton,
          ),
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

    path.cubicTo(slantWidth * 0.5, h, slantWidth * 0.5, 0, 0, 0);

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
