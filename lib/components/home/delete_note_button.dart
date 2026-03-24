// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/theming/glassmorphic_confirm_dialog.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

class DeleteNoteButton extends StatelessWidget {
  const DeleteNoteButton({
    super.key,
    required this.selectedFiles,
    required this.unselectNotes,
    required this.onDeleted,
  });

  final List<String> selectedFiles;
  final VoidCallback unselectNotes;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: t.home.deleteNote,
      onPressed: () => showDialog(
        context: context,
        builder: (context) => _DeleteNoteDialog(
          selectedFiles: selectedFiles,
          unselectNotes: unselectNotes,
          onDeleted: onDeleted,
        ),
      ),
      icon: const Icon(Icons.delete_outline),
    );
  }
}

class _DeleteNoteDialog extends StatelessWidget {
  const _DeleteNoteDialog({
    required this.selectedFiles,
    required this.unselectNotes,
    required this.onDeleted,
  });

  final List<String> selectedFiles;
  final VoidCallback unselectNotes;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return GlassmorphicConfirmDialog(
      title: selectedFiles.length == 1
          ? t.home.deleteNote
          : 'Delete ${selectedFiles.length} notes',
      subtitle: selectedFiles.length == 1
          ? 'Are you sure you want to delete this note?'
          : 'Are you sure you want to delete these ${selectedFiles.length} notes?',
      confirmText: t.common.delete,
      cancelText: t.common.cancel,
      isDestructive: true,
      onCancel: () => Navigator.of(context).pop(),
      onConfirm: () async {
        final filesToDelete = List<String>.from(selectedFiles);
        unselectNotes();
        Navigator.of(context).pop();

        for (final filePath in filesToDelete) {
          final ext =
              await FileManager.doesFileExist(
                filePath + Editor.extensionOldJson,
              )
              ? Editor.extensionOldJson
              : Editor.extension;
          await FileManager.deleteFile(filePath + ext);
        }

        onDeleted();
      },
    );
  }
}
