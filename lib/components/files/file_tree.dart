// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:saber/components/files/file_tree_skeleton.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/routes.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    _loadRoot();

    _fileSystemSubscription = FileManager.fileWriteStream.stream.listen((
      event,
    ) {
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
      if (mounted) _loadRoot();
    });
  }

  Future<void> _loadRoot() async {

    if (_isLoading && _rootChildren != null) {
      _isReloadPending = true;
      return;
    }

    if (mounted && !_isLoading) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final rawChildren = await FileManager.getChildrenOfDirectory('/');
      if (mounted) {
        DirectoryChildren? filteredChildren;
        if (rawChildren != null) {

          final directories = rawChildren.directories
              .where((d) => !d.startsWith('.'))
              .toList();

          directories.sort(
            (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
          );

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
          } catch (_) {}

          linkedDirs = Map.fromEntries(
            linkedDirs.entries.toList()..sort(
              (a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()),
            ),
          );
          linkedFiles = Map.fromEntries(
            linkedFiles.entries.toList()..sort(
              (a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()),
            ),
          );

          filteredChildren = DirectoryChildren(
            directories,
            rawChildren.files.where((f) => !f.startsWith('.')).toList()
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
            linkedDirectories: linkedDirs,
            linkedFiles: linkedFiles,
          );
        }

        setState(() {
          _rootChildren = filteredChildren;
          _isLoading = false;
        });

        if (_isReloadPending) {
          _isReloadPending = false;
          _loadRoot();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: child,
        ),
      ),
      child: _buildChild(context),
    );
  }

  Widget _buildChild(BuildContext context) {
    if (_isLoading && _rootChildren == null) {
      return KeyedSubtree(
        key: const ValueKey('file_tree_skeleton'),
        child: const FileTreeSkeleton(rowCount: 7),
      );
    }

    if (_rootChildren == null || _rootChildren!.isEmpty) {
      return KeyedSubtree(
        key: const ValueKey('file_tree_empty'),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'No files',
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    var index = 0;
    final content = SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final folder in _rootChildren!.directories)
            _FileTreeItemEntrance(
              index: index++,
              child: _FileTreeFolder(
                key: ValueKey('/$folder'),
                path: '/$folder',
                name: folder,
                level: 0,
              ),
            ),
          for (final linkedFolder in _rootChildren!.linkedDirectories.entries)
            _FileTreeItemEntrance(
              index: index++,
              child: _FileTreeFolder(
                key: ValueKey('link_${linkedFolder.key}'),
                path: linkedFolder.value,
                name: linkedFolder.key,
                level: 0,
                isLink: true,
                parentPath: '/',
                onLinkDeleted: _scheduleRootReload,
              ),
            ),
          for (final file in _rootChildren!.files)
            _FileTreeItemEntrance(
              index: index++,
              child: _FileTreeFile(
                key: ValueKey('/$file'),
                path: '/$file',
                name: file,
                level: 0,
              ),
            ),
          for (final linkedFile in _rootChildren!.linkedFiles.entries)
            _FileTreeItemEntrance(
              index: index++,
              child: _FileTreeFile(
                key: ValueKey('link_${linkedFile.key}'),
                path: linkedFile.value,
                name: linkedFile.key,
                level: 0,
                isLink: true,
                parentPath: '/',
                onLinkDeleted: _scheduleRootReload,
              ),
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

class _FileTreeItemEntrance extends StatefulWidget {
  const _FileTreeItemEntrance({
    required this.index,
    required this.child,
  });

  final int index;
  final Widget child;

  @override
  State<_FileTreeItemEntrance> createState() => _FileTreeItemEntranceState();
}

class _FileTreeItemEntranceState extends State<_FileTreeItemEntrance>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 280),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    Future.delayed(Duration(milliseconds: widget.index * 25), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(_animation),
        child: widget.child,
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

  String get _prefKey => 'tree_expanded_${widget.path}';

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

    _loadPersistedState();

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
        _loadChildren();
      }
    });
  }

  Future<void> _loadPersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        final wasExpanded = prefs.getBool(_prefKey) ?? false;
        setState(() {
          _isExpanded = wasExpanded;
        });

        if (wasExpanded) {
          _controller.value = 1.0;
          _loadChildren();
        }
      }
    } catch (e) {

    }
  }

  Future<void> _savePersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, _isExpanded);
    } catch (e) {

    }
  }

  Future<void> _loadChildren() async {
    if (_isLoading) {
      _isReloadPending = true;
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final rawChildren = await FileManager.getChildrenOfDirectory(widget.path);

      if (!mounted) return;

      DirectoryChildren? filteredChildren;
      if (rawChildren != null) {

        var directories = rawChildren.directories
            .where((d) => !d.startsWith('.'))
            .toList();

        directories.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

        Map<String, String> linkedDirs = {};
        Map<String, String> linkedFiles = {};
        try {
          final links = await FolderLinkManager.getLinks(widget.path);
          for (final entry in links.entries) {
            if (entry.value.endsWith('.sbn') ||
                entry.value.endsWith('.sbn2') ||
                entry.value.endsWith('.pdf')) {
              linkedFiles[entry.key] = entry.value;
            } else {
              linkedDirs[entry.key] = entry.value;
            }
          }
        } catch (_) {}

        linkedDirs = Map.fromEntries(
          linkedDirs.entries.toList()..sort(
            (a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()),
          ),
        );
        linkedFiles = Map.fromEntries(
          linkedFiles.entries.toList()..sort(
            (a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()),
          ),
        );

        filteredChildren = DirectoryChildren(
          directories,
          rawChildren.files.where((f) => !f.startsWith('.')).toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
          linkedDirectories: linkedDirs,
          linkedFiles: linkedFiles,
        );
      }

      setState(() {
        _children = filteredChildren;
        _isLoading = false;
      });

      if (_isReloadPending) {
        _isReloadPending = false;
        _loadChildren();
      }
    } catch (e) {
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
        _loadChildren();
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
                    CupertinoIcons.chevron_right,
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
                              ? CupertinoIcons.folder_open
                              : CupertinoIcons.folder_fill,
                          size: 18,
                          color: color,
                        ),
                        if (widget.isLink)
                          Positioned(
                            bottom: -2,
                            left: -2,
                            child: Container(
                              padding: const EdgeInsets.all(1),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.shortcut,
                                size: 8,
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
                    widget.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _isExpanded
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: _isExpanded
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
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
                return FileTreeFolderSkeleton(
                  parentLevel: widget.level,
                  rowCount: 4,
                );
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

    IconData iconData = Icons.insert_drive_file_outlined;
    if (name.endsWith('.pdf')) {
      iconData = Icons.picture_as_pdf;
    } else if (name.endsWith('.sbn') || name.endsWith('.sbn2')) {
      iconData = Icons.edit_note;
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
                Icon(iconData, size: 18, color: colorScheme.onSurfaceVariant),
                if (isLink)
                  Positioned(
                    bottom: -2,
                    left: -2,
                    child: Container(
                      padding: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.shortcut,
                        size: 8,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                displayName,
                style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
