// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

class MoveNoteButton extends StatelessWidget {
  const MoveNoteButton({
    super.key,
    required this.filesToMove,
    required this.unselectNotes,
  });

  final List<String> filesToMove;
  final void Function() unselectNotes;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: .zero,
      tooltip: t.home.moveNote.moveNote,
      onPressed: () {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return MoveNoteDialog(
              filesToMove: filesToMove,
              unselectNotes: unselectNotes,
            );
          },
        );
      },
      icon: const Icon(Icons.drive_file_move),
    );
  }
}

class MoveNoteDialog extends StatefulWidget {
  const MoveNoteDialog({

    super.key,
    required this.filesToMove,
    required this.unselectNotes,
  });

  final List<String> filesToMove;
  final void Function() unselectNotes;

  @override
  State<MoveNoteDialog> createState() => _MoveNoteDialogState();
}

class _MoveNoteDialogState extends State<MoveNoteDialog> {

  late final List<String> originalFileNames = widget.filesToMove
      .map((path) => path.substring(path.lastIndexOf('/') + 1))
      .toList();

  late final List<String> parentFolders = widget.filesToMove
      .map((path) => path.substring(0, path.lastIndexOf('/') + 1))
      .toList();

  late List<bool> oldExtensions = widget.filesToMove.map((_) => false).toList();
  Future<void> findOldExtensions() async {
    oldExtensions = [
      for (int i = 0; i < widget.filesToMove.length; ++i)
        await FileManager.doesFileExist(
          '${widget.filesToMove[i]}${Editor.extensionOldJson}',
        ),
    ];
  }

  late String _currentFolder;

  String get currentFolder => _currentFolder;
  set currentFolder(String folder) {

    if (folder != '/' && !folder.endsWith('/')) {
      folder = '$folder/';
    }
    _currentFolder = folder;
    currentFolderChildren = null;
    findChildrenOfCurrentFolder();
  }

  DirectoryChildren? currentFolderChildren;

  late List<String> newFileNames = [];

  late List<String> changedFileNames = [];

  Future findChildrenOfCurrentFolder() async {
    currentFolderChildren = await FileManager.getChildrenOfDirectory(
      currentFolder,
    );

    newFileNames = [];
    changedFileNames = [];
    for (int i = 0; i < widget.filesToMove.length; ++i) {
      final oldExtension = oldExtensions[i];
      final newFileName = await FileManager.suffixFilePathToMakeItUnique(
        p.join(currentFolder, originalFileNames[i]),
        intendedExtension: oldExtension
            ? Editor.extensionOldJson
            : Editor.extension,
        currentPath:
            '${widget.filesToMove[i]}${oldExtension ? Editor.extensionOldJson : Editor.extension}',
      ).then((newPath) => newPath.substring(newPath.lastIndexOf('/') + 1));

      newFileNames.add(newFileName);

      if (newFileName != originalFileNames[i]) {
        changedFileNames.add(newFileName);
      }
    }

    if (!mounted) return;
    setState(() {});
  }

  Future<void> createFolder(String folderName) async {
    final folderPath = p.join(currentFolder, folderName);
    await FileManager.createFolder(folderPath);
    findChildrenOfCurrentFolder();
  }

  @override
  void initState() {
    super.initState();
    String folder = _findMostCommonParentFolder();
    if (!folder.startsWith('/')) {
      folder = '/$folder';
    }

    currentFolder = folder;

    findOldExtensions().then((_) => findChildrenOfCurrentFolder());
  }

  String _findMostCommonParentFolder() {
    final parentFolderCounts = <String, int>{};
    for (final parentFolder in parentFolders) {
      parentFolderCounts[parentFolder] =
          (parentFolderCounts[parentFolder] ?? 0) + 1;
    }
    return parentFolderCounts.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveAlertDialog(
      title: originalFileNames.length < 5
          ? Text(
              t.home.moveNote.moveName(f: originalFileNames.join(', ')),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
              ),
            )
          : Text(
              t.home.moveNote.moveNotes(n: originalFileNames.length),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
              ),
            ),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
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
                  onPressed: currentFolder == '/'
                      ? null
                      : () {
                          setState(() {
                            currentFolder = p.dirname(currentFolder);
                            if (currentFolder == '.') currentFolder = '/';
                          });
                        },
                  tooltip: 'Go up',
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.3),
                  ),
                ),
                title: Text(
                  currentFolder == '/'
                      ? t.home.root
                      : p.basename(currentFolder),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                    letterSpacing: -0.3,
                  ),
                ),
                subtitle: Text(
                  currentFolder,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            Expanded(
              child: (currentFolderChildren?.directories.isEmpty ?? true)
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
                      itemCount: currentFolderChildren!.directories.length,
                      itemBuilder: (context, index) {
                        final folder =
                            currentFolderChildren!.directories[index];
                        return ListTile(
                          leading: Icon(
                            CupertinoIcons.folder_fill,
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.8),
                          ),
                          title: Text(
                            folder,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          onTap: () {
                            setState(() {
                              currentFolder = p.join(currentFolder, folder);
                            });
                          },
                          trailing: Icon(
                            CupertinoIcons.chevron_right,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.5),
                          ),
                        );
                      },
                    ),
            ),
            if (changedFileNames.length == 1)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  t.home.moveNote.renamedTo(newName: changedFileNames.single),
                  style: const TextStyle(fontSize: 12),
                ),
              )
            else if (changedFileNames.length > 1)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  t.home.moveNote.numberRenamedTo(n: changedFileNames.length),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(t.common.cancel),
        ),
        CupertinoDialogAction(
          onPressed: () async {

            widget.unselectNotes();
            if (context.mounted) {
              Navigator.of(context).pop();
            }

            for (int i = 0; i < widget.filesToMove.length; ++i) {
              final extension = oldExtensions[i]
                  ? Editor.extensionOldJson
                  : Editor.extension;
              await FileManager.moveFile(
                '${widget.filesToMove[i]}$extension',
                p.join(currentFolder, '${newFileNames[i]}$extension'),
              );
            }
          },
          child: Text(t.home.moveNote.move),
        ),
      ],
    );
  }
}
