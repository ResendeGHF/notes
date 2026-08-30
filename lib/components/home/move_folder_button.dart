// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:saber/components/home/home_toolbar_chrome.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';

class MoveFolderDialog extends StatefulWidget {
  const MoveFolderDialog({
    super.key,
    required this.folderName,
    required this.currentPath,
  });

  final String folderName;
  final String currentPath;

  @override
  State<MoveFolderDialog> createState() => _MoveFolderDialogState();
}

class _MoveFolderDialogState extends State<MoveFolderDialog> {
  late String currentDirectory;
  List<String> subFolders = [];

  @override
  void initState() {
    super.initState();

    currentDirectory = '/';
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    final children = await FileManager.getChildrenOfDirectory(currentDirectory);
    if (mounted && children != null) {
      setState(() {

        subFolders = children.directories.where((dir) {
          final fullPath = p.join(currentDirectory, dir);
          final folderBeingMoved = p.join(
            widget.currentPath,
            widget.folderName,
          );

          return fullPath != folderBeingMoved &&
              !fullPath.startsWith('$folderBeingMoved/');
        }).toList();
      });
    }
  }

  void _navigateUp() {
    if (currentDirectory == '/') return;
    setState(() {
      currentDirectory = p.dirname(currentDirectory);
      if (currentDirectory == '.') currentDirectory = '/';
    });
    _loadFolders();
  }

  void _enterFolder(String folderName) {
    setState(() {
      currentDirectory = p.join(currentDirectory, folderName);
    });
    _loadFolders();
  }

  @override
  Widget build(BuildContext context) {

    final isOriginalLocation =
        currentDirectory == widget.currentPath ||
        (widget.currentPath.isEmpty && currentDirectory == '/');

    final isInvalidMove =
        p.join(widget.currentPath, widget.folderName) == currentDirectory;

    final h = (MediaQuery.sizeOf(context).height * 0.52).clamp(320.0, 620.0);
    return AlertDialog(
      backgroundColor: homeAppBarBackgroundColor(context),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kSaberContainerRadius),
        side: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.18),
        ),
      ),
      title: Text(t.home.moveFolderTo(name: widget.folderName)),
      content: SizedBox(
        width: double.maxFinite,
        height: h,
        child: Column(
          children: [

            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: currentDirectory == '/' ? null : _navigateUp,
                  tooltip: 'Go up',
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.3),
                  ),
                ),
                title: Text(
                  currentDirectory == '/'
                      ? t.home.root
                      : p.basename(currentDirectory),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                    letterSpacing: -0.3,
                  ),
                ),
                subtitle: Text(
                  currentDirectory,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            ),

            Expanded(
              child: subFolders.isEmpty
                  ? Center(
                      child: Text(
                        t.home.noSubfolders,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: subFolders.length,
                      itemBuilder: (context, index) {
                        final folder = subFolders[index];
                        var destPath = p.join(currentDirectory, folder);
                        if (!destPath.startsWith('/')) {
                          destPath = '/$destPath';
                        }
                        return ListTile(
                          leading: ValueListenableBuilder<Map<String, int>>(
                            valueListenable: stows.folderColors,
                            builder: (context, colors, _) {
                              final v = colors[destPath];
                              final folderColor = v != null
                                  ? Color(v)
                                  : Theme.of(context).colorScheme.primary;
                              return Icon(Icons.folder, color: folderColor);
                            },
                          ),
                          title: Text(
                            folder,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          onTap: () => _enterFolder(folder),
                          trailing: Icon(
                            Icons.chevron_right,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.5),
                          ),
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
          child: Text(t.common.cancel),
        ),
        FilledButton(
          onPressed: (isOriginalLocation || isInvalidMove)
              ? null
              : () => Navigator.pop(context, currentDirectory),
          child: Text(t.editor.selectionBar.move),
        ),
      ],
    );
  }
}
