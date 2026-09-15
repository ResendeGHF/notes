// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/i18n/strings.g.dart';

class DuplicateNoteButton extends StatelessWidget {
  const DuplicateNoteButton({
    super.key,
    required this.filePath,
    required this.onDuplicated,
  });

  final String filePath;
  final VoidCallback onDuplicated;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: t.editor.selectionBar.duplicate,
      onPressed: () async {
        await FileManager.duplicateFile(filePath);
        onDuplicated();
      },
      icon: const Icon(Icons.copy_outlined),
    );
  }
}

