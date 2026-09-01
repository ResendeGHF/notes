// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

class DeleteFolderButton extends StatelessWidget {
  const DeleteFolderButton({
    super.key,
    required this.folderName,
    required this.deleteFolder,
    required this.isFolderEmpty,
  });

  final String folderName;
  final Future<void> Function(String) deleteFolder;
  final Future<bool> Function(String) isFolderEmpty;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: .zero,
      tooltip: t.home.deleteFolder.deleteFolder,
      onPressed: () async {
        await showDialog(
          context: context,
          builder: (context) => _DeleteFolderDialog(
            folderName: folderName,
            deleteFolder: deleteFolder,
            isFolderEmpty: isFolderEmpty,
          ),
        );
      },
      icon: const Icon(Icons.delete_forever),
    );
  }
}

class _DeleteFolderDialog extends StatefulWidget {
  const _DeleteFolderDialog({

    super.key,
    required this.folderName,
    required this.deleteFolder,
    required this.isFolderEmpty,
  });

  final String folderName;
  final Future<void> Function(String) deleteFolder;
  final Future<bool> Function(String) isFolderEmpty;

  @override
  State<_DeleteFolderDialog> createState() => _DeleteFolderDialogState();
}

class _DeleteFolderDialogState extends State<_DeleteFolderDialog> {
  var isFolderEmpty = false;
  var alsoDeleteContents = false;

  @override
  void initState() {
    super.initState();
    checkIfFolderIsEmpty();
  }

  Future<void> checkIfFolderIsEmpty() async {
    isFolderEmpty = await widget.isFolderEmpty(widget.folderName);
    if (isFolderEmpty) alsoDeleteContents = false;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final deleteAllowed = isFolderEmpty || alsoDeleteContents;
    return AdaptiveAlertDialog(
      title: Text(t.home.deleteFolder.deleteName(f: widget.folderName)),
      content: isFolderEmpty
          ? const SizedBox.shrink()
          : Row(
              children: [
                Checkbox(
                  value: alsoDeleteContents,
                  onChanged: isFolderEmpty
                      ? null
                      : (value) {
                          setState(() => alsoDeleteContents = value!);
                        },
                ),
                Expanded(child: Text(t.home.deleteFolder.alsoDeleteContents)),
              ],
            ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.common.cancel),
        ),
        CupertinoDialogAction(
          onPressed: deleteAllowed
              ? () async {
                  await widget.deleteFolder(widget.folderName);
                  if (context.mounted) Navigator.of(context).pop();
                }
              : null,
          isDestructiveAction: true,
          child: Text(t.home.deleteFolder.delete),
        ),
      ],
    );
  }
}
