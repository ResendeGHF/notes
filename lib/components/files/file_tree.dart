// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:saber/components/files/file_tree_skeleton.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/file_tree_cache.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/routes.dart';

/// Max grapheme clusters shown in the navbar file tree; longer names are cut
/// with "…". Font size stays fixed (no FittedBox scale-down).
const _kFileTreeNameMaxChars = 64;

String _elideFileTreeName(String name) {
  final ch = name.characters;
  if (ch.length <= _kFileTreeNameMaxChars) return name;
  return '${ch.take(_kFileTreeNameMaxChars)}…';
}

DirectoryChildren? _filterChildren(
  DirectoryChildren? raw, {
  required Map<String, String> linkedDirs,
  required Map<String, String> linkedFiles,
}) {
  if (raw == null) return null;
  final directories = raw.directories.where((d) => !d.startsWith('.')).toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  final files = raw.files.where((f) => !f.startsWith('.')).toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  final sortedDirs = Map.fromEntries(
    linkedDirs.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase())),
  );
  final sortedFiles = Map.fromEntries(
    linkedFiles.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase())),
  );
  return DirectoryChildren(
    directories,
    files,
    linkedDirectories: sortedDirs,
    linkedFiles: sortedFiles,
  );
}

void _splitLinks(
  Map<String, String> links, {
  required Map<String, String> linkedDirs,
  required Map<String, String> linkedFiles,
}) {
  for (final entry in links.entries) {
    if (entry.value.endsWith('.sbn') ||
        entry.value.endsWith('.sbn2') ||
        entry.value.endsWith('.pdf')) {
      linkedFiles[entry.key] = entry.value;
    } else {
      linkedDirs[entry.key] = entry.value;
    }
  }
}

class FileTree extends StatefulWidget {
  const FileTree({super.key});

  @override
  State<FileTree> createState() => _FileTreeState();
}

class _FileTreeState extends State<FileTree> {
  StreamSubscription? _fileSystemSubscription;
  DirectoryChildren? _rootChildren;
  var _isLoading = true;
  var _isReloadPending = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    // Instant paint from cache (warmed by HomeDataCache.preload / prior visit).
    final cached = FileTreeCache.instance.peekChildren('/');
    final cachedLinks = FileTreeCache.instance.peekLinks('/') ?? const {};
    if (cached != null) {
      final linkedDirs = <String, String>{};
      final linkedFiles = <String, String>{};
      _splitLinks(
        cachedLinks,
        linkedDirs: linkedDirs,
        linkedFiles: linkedFiles,
      );
      _rootChildren = _filterChildren(
        cached,
        linkedDirs: linkedDirs,
        linkedFiles: linkedFiles,
      );
      _isLoading = false;
    }
    _loadRoot(backgroundRefresh: cached != null);

    _fileSystemSubscription = FileManager.fileWriteStream.stream.listen((
      event,
    ) {
      FileTreeCache.instance.invalidateForFileEvent(event.filePath);

      final eventPath = event.filePath;
      String normalizedPath = eventPath.replaceAll('\\', '/');
      if (!normalizedPath.startsWith('/')) normalizedPath = '/$normalizedPath';
      if (normalizedPath.endsWith('/') && normalizedPath.length > 1) {
        normalizedPath = normalizedPath.substring(0, normalizedPath.length - 1);
      }

      final pathParts = normalizedPath
          .split('/')
          .where((s) => s.isNotEmpty)
          .toList();

      if (normalizedPath.isEmpty ||
          normalizedPath == '/' ||
          pathParts.length <= 1 ||
          event.type == FileOperationType.delete) {
        _scheduleRootReload();
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _fileSystemSubscription?.cancel();
    super.dispose();
  }

  void _scheduleRootReload() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _loadRoot(backgroundRefresh: true);
    });
  }

  Future<void> _loadRoot({bool backgroundRefresh = false}) async {
    if (_isLoading && _rootChildren != null && !backgroundRefresh) {
      _isReloadPending = true;
      return;
    }

    // Only flash the skeleton when we have nothing to show yet.
    if (mounted && _rootChildren == null && !_isLoading) {
      setState(() => _isLoading = true);
    }

    try {
      final results = await Future.wait([
        backgroundRefresh
            ? FileTreeCache.instance.refreshChildren('/')
            : FileTreeCache.instance.getChildren('/'),
        backgroundRefresh
            ? FileTreeCache.instance.refreshLinks('/')
            : FileTreeCache.instance.getLinks('/'),
      ]);
      if (!mounted) return;

      final rawChildren = results[0] as DirectoryChildren?;
      final links = results[1] as Map<String, String>;
      final linkedDirs = <String, String>{};
      final linkedFiles = <String, String>{};
      _splitLinks(links, linkedDirs: linkedDirs, linkedFiles: linkedFiles);

      final filteredChildren = _filterChildren(
        rawChildren,
        linkedDirs: linkedDirs,
        linkedFiles: linkedFiles,
      );

      setState(() {
        _rootChildren = filteredChildren;
        _isLoading = false;
      });

      if (_isReloadPending) {
        _isReloadPending = false;
        _loadRoot(backgroundRefresh: true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: _buildChild(context),
    );
  }

  Widget _buildChild(BuildContext context) {
    if (_isLoading && _rootChildren == null) {
      return const KeyedSubtree(
        key: ValueKey('file_tree_loading'),
        child: FileTreeLoadingPanel(),
      );
    }

    if (_rootChildren == null || _rootChildren!.isEmpty) {
      return KeyedSubtree(
        key: const ValueKey('file_tree_empty'),
        child: _FileTreeEmptyState(onRefresh: () => _loadRoot()),
      );
    }

    final content = SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final folder in _rootChildren!.directories)
            _FileTreeFolder(
              key: ValueKey('/$folder'),
              path: '/$folder',
              name: folder,
              level: 0,
            ),
          for (final linkedFolder in _rootChildren!.linkedDirectories.entries)
            _FileTreeFolder(
              key: ValueKey('link_${linkedFolder.key}'),
              path: linkedFolder.value,
              name: linkedFolder.key,
              level: 0,
              isLink: true,
              parentPath: '/',
              onLinkDeleted: _scheduleRootReload,
            ),
          for (final file in _rootChildren!.files)
            _FileTreeFile(
              key: ValueKey('/$file'),
              path: '/$file',
              name: file,
              level: 0,
            ),
          for (final linkedFile in _rootChildren!.linkedFiles.entries)
            _FileTreeFile(
              key: ValueKey('link_${linkedFile.key}'),
              path: linkedFile.value,
              name: linkedFile.key,
              level: 0,
              isLink: true,
              parentPath: '/',
              onLinkDeleted: _scheduleRootReload,
            ),
        ],
      ),
    );

    return KeyedSubtree(
      key: const ValueKey('file_tree_content'),
      child: content,
    );
  }
}

class _FileTreeEmptyState extends StatelessWidget {
  const _FileTreeEmptyState({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: .20),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: .18),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.folder,
                size: 28,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 10),
              Text(
                'No files yet',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Create or import a note to see it here.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileTreeFolder extends StatefulWidget {
  final String path;
  final String name;
  final int level;
  final bool isLink;
  final String? parentPath;
  final VoidCallback? onLinkDeleted;

  const _FileTreeFolder({
    super.key,
    required this.path,
    required this.name,
    required this.level,
    this.isLink = false,
    this.parentPath,
    this.onLinkDeleted,
  });

  @override
  State<_FileTreeFolder> createState() => _FileTreeFolderState();
}

class _FileTreeFolderState extends State<_FileTreeFolder>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  DirectoryChildren? _children;
  bool _isLoading = false;
  bool _isReloadPending = false;

  StreamSubscription? _folderSubscription;
  late AnimationController _controller;
  late Animation<double> _iconTurns;
  late Animation<double> _heightFactor;

  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _iconTurns = Tween<double>(
      begin: 0.0,
      end: 0.25,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _heightFactor = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

    final cachedExpanded = FileTreeCache.instance.peekExpanded(widget.path);
    if (cachedExpanded == true) {
      _isExpanded = true;
      _controller.value = 1.0;
      final cached = FileTreeCache.instance.peekChildren(widget.path);
      final cachedLinks =
          FileTreeCache.instance.peekLinks(widget.path) ?? const {};
      if (cached != null) {
        final linkedDirs = <String, String>{};
        final linkedFiles = <String, String>{};
        _splitLinks(
          cachedLinks,
          linkedDirs: linkedDirs,
          linkedFiles: linkedFiles,
        );
        _children = _filterChildren(
          cached,
          linkedDirs: linkedDirs,
          linkedFiles: linkedFiles,
        );
      }
      _loadChildren(backgroundRefresh: _children != null);
    } else {
      _loadPersistedState();
    }

    _folderSubscription = FileManager.fileWriteStream.stream.listen((event) {
      if (!mounted) return;

      String normalize(String raw) {
        String s = raw.replaceAll('\\', '/');
        if (!s.startsWith('/')) s = '/$s';
        if (s.endsWith('/') && s.length > 1) s = s.substring(0, s.length - 1);
        return s;
      }

      final eventPath = normalize(event.filePath);
      final myPath = normalize(widget.path);

      bool isDescendantOrSelf = false;
      if (eventPath.length >= myPath.length && eventPath.startsWith(myPath)) {
        if (eventPath.length == myPath.length) {
          isDescendantOrSelf = true;
        } else if (eventPath.length > myPath.length &&
            (myPath == '/' || eventPath[myPath.length] == '/')) {
          isDescendantOrSelf = true;
        }
      }

      if (isDescendantOrSelf && _isExpanded) {
        _scheduleReload();
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    _folderSubscription?.cancel();
    super.dispose();
  }

  void _scheduleReload() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        _loadChildren(backgroundRefresh: true);
      }
    });
  }

  Future<void> _loadPersistedState() async {
    try {
      await FileTreeCache.instance.loadExpandedPrefs();
      if (!mounted) return;
      final wasExpanded =
          FileTreeCache.instance.peekExpanded(widget.path) ?? false;
      if (!wasExpanded) return;
      setState(() {
        _isExpanded = true;
      });
      _controller.value = 1.0;
      _loadChildren();
    } catch (_) {}
  }

  Future<void> _savePersistedState() async {
    await FileTreeCache.instance.setExpanded(widget.path, _isExpanded);
  }

  Future<void> _loadChildren({bool backgroundRefresh = false}) async {
    if (_isLoading && !backgroundRefresh) {
      _isReloadPending = true;
      return;
    }

    if (mounted && _children == null) {
      setState(() => _isLoading = true);
    }

    try {
      final results = await Future.wait([
        backgroundRefresh
            ? FileTreeCache.instance.refreshChildren(widget.path)
            : FileTreeCache.instance.getChildren(widget.path),
        backgroundRefresh
            ? FileTreeCache.instance.refreshLinks(widget.path)
            : FileTreeCache.instance.getLinks(widget.path),
      ]);
      if (!mounted) return;

      final rawChildren = results[0] as DirectoryChildren?;
      final links = results[1] as Map<String, String>;
      final linkedDirs = <String, String>{};
      final linkedFiles = <String, String>{};
      _splitLinks(links, linkedDirs: linkedDirs, linkedFiles: linkedFiles);

      setState(() {
        _children = _filterChildren(
          rawChildren,
          linkedDirs: linkedDirs,
          linkedFiles: linkedFiles,
        );
        _isLoading = false;
      });

      if (_isReloadPending) {
        _isReloadPending = false;
        _loadChildren(backgroundRefresh: true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _handleTap() async {
    if (widget.isLink) {
      if (!(await FileManager.isDirectory(widget.path))) {
        if (!mounted) return;
        await FolderLinkManager.showBrokenLinkDialog(context);
        if (widget.parentPath != null) {
          await FolderLinkManager.removeLink(widget.parentPath!, widget.name);
          widget.onLinkDeleted?.call();
        }
        return;
      }
    }
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
        _loadChildren(backgroundRefresh: _children != null);
      } else {
        _controller.reverse();
      }
    });
    _savePersistedState();
  }

  void _navigateToFolder() async {
    if (widget.isLink) {
      if (!(await FileManager.isDirectory(widget.path))) {
        if (!mounted) return;
        await FolderLinkManager.showBrokenLinkDialog(context);
        if (widget.parentPath != null) {
          await FolderLinkManager.removeLink(widget.parentPath!, widget.name);
          widget.onLinkDeleted?.call();
        }
        return;
      }
    }
    if (!mounted) return;
    context.go(HomeRoutes.browseFilePath(widget.path));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final indent = 12.0 + (widget.level * 16.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _handleTap,
          onLongPress: _navigateToFolder,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: EdgeInsets.only(left: indent, right: 8, top: 6, bottom: 6),
            child: Row(
              children: [
                RotationTransition(
                  turns: _iconTurns,
                  child: Icon(
                    FluentIcons.chevron_right_16_regular,
                    size: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                ValueListenableBuilder<Map<String, int>>(
                  valueListenable: stows.folderColors,
                  builder: (context, colors, _) {
                    final colorValue = colors[widget.path];
                    final color = colorValue != null
                        ? Color(colorValue)
                        : colorScheme.primary;

                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          _isExpanded
                              ? FluentIcons.folder_open_20_filled
                              : FluentIcons.folder_20_filled,
                          size: 20,
                          color: color,
                        ),
                        if (widget.isLink)
                          Positioned(
                            bottom: -2,
                            right: -4,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    blurRadius: 2,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Icon(
                                FluentIcons.link_16_filled,
                                size: 10,
                                color: color,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _elideFileTreeName(widget.name),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _isExpanded
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: _isExpanded
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                ),
              ],
            ),
          ),
        ),
        SizeTransition(
          sizeFactor: _heightFactor,
          axisAlignment: -1.0,
          child: Builder(
            builder: (context) {
              if (_isLoading && _children == null) {
                return FileTreeFolderLoadingRow(parentLevel: widget.level);
              }

              if (_children != null) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final subFolder in _children!.directories)
                      _FileTreeFolder(
                        key: ValueKey(p.join(widget.path, subFolder)),
                        path: p.join(widget.path, subFolder),
                        name: subFolder,
                        level: widget.level + 1,
                      ),
                    for (final linkedFolder
                        in _children!.linkedDirectories.entries)
                      _FileTreeFolder(
                        key: ValueKey('link_${linkedFolder.key}'),
                        path: linkedFolder.value,
                        name: linkedFolder.key,
                        level: widget.level + 1,
                        isLink: true,
                        parentPath: widget.path,
                        onLinkDeleted: _scheduleReload,
                      ),
                    for (final subFile in _children!.files)
                      _FileTreeFile(
                        key: ValueKey(p.join(widget.path, subFile)),
                        path: p.join(widget.path, subFile),
                        name: subFile,
                        level: widget.level + 1,
                      ),
                    for (final linkedFile in _children!.linkedFiles.entries)
                      _FileTreeFile(
                        key: ValueKey('link_${linkedFile.key}'),
                        path: linkedFile.value,
                        name: linkedFile.key,
                        level: widget.level + 1,
                        isLink: true,
                        parentPath: widget.path,
                        onLinkDeleted: _scheduleReload,
                      ),
                  ],
                );
              }

              return const SizedBox.shrink();
            },
          ),
        ),
      ],
    );
  }
}

class _FileTreeFile extends StatelessWidget {
  final String path;
  final String name;
  final int level;
  final bool isLink;
  final String? parentPath;
  final VoidCallback? onLinkDeleted;

  const _FileTreeFile({
    super.key,
    required this.path,
    required this.name,
    required this.level,
    this.isLink = false,
    this.parentPath,
    this.onLinkDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final indent = 12.0 + 22.0 + (level * 16.0);

    IconData iconData = FluentIcons.document_20_regular;
    if (name.endsWith('.pdf')) {
      iconData = FluentIcons.document_pdf_20_regular;
    } else if (name.endsWith('.sbn') || name.endsWith('.sbn2')) {
      iconData = FluentIcons.document_edit_20_regular;
    }

    String displayName = name;
    if (name.endsWith('.sbn2')) {
      displayName = name.substring(0, name.length - 5);
    } else if (name.endsWith('.sbn')) {
      displayName = name.substring(0, name.length - 4);
    }

    return InkWell(
      onTap: () async {
        String target = path;
        if (isLink) {
          final bool exists = await FileManager.doesFileExist(target);
          if (!exists) {
            if (!context.mounted) return;
            await FolderLinkManager.showBrokenLinkDialog(context);
            if (parentPath != null) {
              await FolderLinkManager.removeLink(parentPath!, name);
              onLinkDeleted?.call();
            }
            return;
          }
        }
        if (target.endsWith('.sbn2')) {
          target = target.substring(0, target.length - 5);
        } else if (target.endsWith('.sbn')) {
          target = target.substring(0, target.length - 4);
        }
        if (context.mounted) {
          context.push(RoutePaths.editFilePath(target));
        }
      },
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: EdgeInsets.only(left: indent, right: 8, top: 6, bottom: 6),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(iconData, size: 20, color: colorScheme.onSurfaceVariant),
                if (isLink)
                  Positioned(
                    bottom: -2,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Icon(
                        FluentIcons.link_16_filled,
                        size: 10,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _elideFileTreeName(displayName),
                style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
