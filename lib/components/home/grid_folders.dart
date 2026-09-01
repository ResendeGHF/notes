// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:path/path.dart' as p;
import 'package:saber/components/home/new_folder_dialog.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';

class GridFolders extends StatelessWidget {
  const GridFolders({
    super.key,
    required this.onTap,
    required this.crossAxisCount,
    required this.renameFolder,
    required this.isFolderEmpty,
    required this.deleteFolder,
    required this.doesFolderExist,
    required this.moveFolder,
    required this.folders,
    this.linkedFolders = const {},
    required this.parentPath,
  });

  final Function(String) onTap;
  final int crossAxisCount;

  final bool Function(String) doesFolderExist;
  final Future<void> Function(String oldName, String newName) renameFolder;
  final Future<void> Function(String folderName) moveFolder;
  final Future<bool> Function(String) isFolderEmpty;
  final Future<void> Function(String) deleteFolder;

  final List<String> folders;
  final Map<String, String> linkedFolders;
  final String? parentPath;

  @override
  Widget build(BuildContext context) {
    if (folders.isEmpty && linkedFolders.isEmpty)
      return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      sliver: SliverAlignedGrid.count(
        itemCount: folders.length + linkedFolders.length,
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        itemBuilder: (context, index) {
          final isLink = index >= folders.length;
          final folderName = isLink
              ? linkedFolders.keys.elementAt(index - folders.length)
              : folders[index];
          final targetPath = isLink ? linkedFolders[folderName] : null;
          final relativePath = isLink
              ? targetPath!
              : p.join(parentPath ?? '/', folderName);

          return _GridFolder(
            folderName: folderName,
            relativePath: relativePath,
            isLink: isLink,
            doesFolderExist: doesFolderExist,
            renameFolder: renameFolder,
            moveFolder: moveFolder,
            isFolderEmpty: isFolderEmpty,
            deleteFolder: deleteFolder,
            onTap: onTap,
          );
        },
      ),
    );
  }
}

class _GridFolder extends StatelessWidget {
  const _GridFolder({
    required this.folderName,
    required this.relativePath,
    this.isLink = false,
    required this.doesFolderExist,
    required this.renameFolder,
    required this.moveFolder,
    required this.isFolderEmpty,
    required this.deleteFolder,
    required this.onTap,
  });

  final String folderName;
  final String relativePath;
  final bool isLink;
  final bool Function(String) doesFolderExist;
  final Future<void> Function(String oldName, String newName) renameFolder;
  final Future<void> Function(String folderName) moveFolder;
  final Future<bool> Function(String) isFolderEmpty;
  final Future<void> Function(String) deleteFolder;
  final Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    return ValueListenableBuilder(
      valueListenable: stows.folderColors,
      builder: (context, folderColors, child) {
        final colorValue = folderColors[relativePath];
        final folderColor = colorValue != null
            ? Color(colorValue)
            : const Color(0xFF2196F3);

        return Card(
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onTap(folderName),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AdaptiveIcon(
                        icon: Icons.folder,
                        cupertinoIcon: CupertinoIcons.folder_fill,
                        size: 28,
                        color: folderColor,
                      ),
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
                            child: Icon(
                              Icons.shortcut,
                              size: 12,
                              color: folderColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      folderName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _FolderContextMenu(
                    folderName: folderName,
                    relativePath: relativePath,
                    doesFolderExist: doesFolderExist,
                    renameFolder: renameFolder,
                    moveFolder: moveFolder,
                    isFolderEmpty: isFolderEmpty,
                    deleteFolder: deleteFolder,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FolderContextMenu extends StatelessWidget {
  const _FolderContextMenu({
    required this.folderName,
    required this.relativePath,
    required this.doesFolderExist,
    required this.renameFolder,
    required this.moveFolder,
    required this.isFolderEmpty,
    required this.deleteFolder,
  });

  final String folderName;
  final String relativePath;
  final bool Function(String) doesFolderExist;
  final Future<void> Function(String oldName, String newName) renameFolder;
  final Future<void> Function(String folderName) moveFolder;
  final Future<bool> Function(String) isFolderEmpty;
  final Future<void> Function(String) deleteFolder;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      padding: EdgeInsets.zero,
      onSelected: (value) async {
        if (value == 'rename') {
          showDialog(
            context: context,
            builder: (context) => NewFolderDialog(
              initialName: folderName,
              createFolder: (newName) => renameFolder(folderName, newName),
              doesFolderExist: doesFolderExist,
            ),
          );
        } else if (value == 'move') {
          await moveFolder(folderName);
        } else if (value == 'color') {
          final color = await showDialog<Color>(
            context: context,
            builder: (context) => _FolderColorDialog(
              initialColor: stows.folderColors.value[relativePath] != null
                  ? Color(stows.folderColors.value[relativePath]!)
                  : const Color(0xFF2196F3),
            ),
          );
          if (color != null) {
            final newColors = <String, int>{...stows.folderColors.value};
            if (color.toARGB32() == const Color(0xFF2196F3).toARGB32()) {
              newColors.remove(relativePath);
            } else {
              newColors[relativePath] = color.toARGB32();
            }
            stows.folderColors.value = Map<String, int>.from(newColors);
          }
        } else if (value == 'delete') {
          final isEmpty = await isFolderEmpty(folderName);
          if (!context.mounted) return;

          if (!isEmpty) {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(t.home.deleteFolder.deleteFolder),
                content: Text(t.home.deleteFolder.deleteName(f: folderName)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(
                      MaterialLocalizations.of(context).cancelButtonLabel,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(t.home.deleteFolder.delete),
                  ),
                ],
              ),
            );
            if (confirm != true) return;
          }
          await deleteFolder(folderName);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'rename',
          child: ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(t.home.renameFolder.renameFolder),
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),
        PopupMenuItem(
          value: 'move',
          child: ListTile(
            leading: const Icon(Icons.drive_file_move_outlined),
            title: Text(t.editor.selectionBar.move),
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),
        PopupMenuItem(
          value: 'color',
          child: ListTile(
            leading: const Icon(Icons.color_lens_outlined),
            title: Text(t.home.folderColor.changeColor),
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: Text(
              t.home.deleteFolder.deleteFolder,
              style: const TextStyle(color: Colors.red),
            ),
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}

class _FolderColorDialog extends StatelessWidget {
  const _FolderColorDialog({required this.initialColor});

  final Color initialColor;

  static const colors = [
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
    Colors.grey,
    Colors.blueGrey,
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.home.folderColor.chooseColor),
      content: SizedBox(
        width: 300,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final color in colors)
              GestureDetector(
                onTap: () => Navigator.pop(context, color),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: initialColor.toARGB32() == color.toARGB32()
                          ? Colors.white
                          : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: [
                      if (initialColor.toARGB32() == color.toARGB32())
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, const Color(0xFF2196F3)),
          child: Text(t.home.folderColor.reset),
        ),
      ],
    );
  }
}
