// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
import 'package:saber/services/vault_adapter.dart';
import 'package:saber/components/theming/font_fallbacks.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';

class SettingsDirectorySelector extends StatelessWidget {
  const SettingsDirectorySelector({
    super.key,
    required this.title,
    required this.icon,
    this.afterChange,
    this.isUnsupported = true,
  });

  final String title;
  final IconData icon;
  final ValueChanged<Color?>? afterChange;
  final bool isUnsupported;

  void onPressed(BuildContext context) async {
    final oldDir = Directory(FileManager.documentsDirectory);
    final oldDirIsEmpty = oldDir.existsSync()
        ? oldDir.listSync().isEmpty
        : true;
    await showAdaptiveDialog(
      context: context,
      builder: (context) => DirectorySelector(
        title: title,
        initialDirectory: FileManager.documentsDirectory,
        mustBeEmpty: !oldDirIsEmpty,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onPressed(context),
      child: ListTile(
        contentPadding: const .symmetric(vertical: 4, horizontal: 16),
        leading: AnimatedSwitcher(
          duration: const Duration(milliseconds: 100),
          child: Icon(icon, key: ValueKey(icon)),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontStyle:
                stows.customDataDir.value != stows.customDataDir.defaultValue
                ? FontStyle.italic
                : null,
          ),
        ),
        subtitle: ValueListenableBuilder(
          valueListenable: stows.customDataDir,
          builder: (context, _, _) => Text(
            FileManager.documentsDirectory,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ),
    );
  }
}

class DirectorySelector extends StatefulWidget {
  const DirectorySelector({
    super.key,
    required this.title,
    required this.initialDirectory,
    this.mustBeEmpty = true,
  });

  final String title;
  final String initialDirectory;
  final bool mustBeEmpty;

  @override
  State<DirectorySelector> createState() => _DirectorySelectorState();
}

class _DirectorySelectorState extends State<DirectorySelector> {
  late String _directory = widget.initialDirectory;
  late var _isEmpty = true;

  Future<void> _pickDir() async {
    VaultAdapter.preventLock = true;
    String? directory;
    try {
      directory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: widget.title,
        initialDirectory: _directory,
      );
    } finally {
      VaultAdapter.preventLock = false;
    }

    if (directory == null) return;
    if (directory == _directory) return;

    final dir = Directory(directory);
    _directory = directory;
    _isEmpty = dir.existsSync() ? dir.listSync().isEmpty : true;

    if (!mounted) return;

    setState(() {});
  }

  Future<void> _pickDefaultDir() async {
    final directory = await FileManager.getDefaultDocumentsDirectory();

    final dir = Directory(directory);
    _directory = directory;
    _isEmpty = dir.existsSync() ? dir.listSync().isEmpty : true;

    if (!mounted) return;
    setState(() {});
  }

  void _onConfirm() {
    stows.customDataDir.value = _directory;
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    final emptyError = widget.mustBeEmpty && !_isEmpty;
    final anyErrors = emptyError;

    return AdaptiveAlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: .min,
        children: [
          Text(
            t.settings.customDataDir.unsupported,
            style: TextStyle(color: colorScheme.error),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  _directory,
                  style: const TextStyle(
                    fontSize: 13,
                    fontFamily: 'FiraMono',
                    fontFamilyFallback: saberMonoFontFallbacks,
                  ),
                ),
              ),
              IconButton(icon: const Icon(Icons.folder), onPressed: _pickDir),
              if (stows.customDataDir.value != null)
                IconButton(
                  icon: const Icon(Icons.undo),
                  onPressed: _pickDefaultDir,
                ),
            ],
          ),
          if (emptyError)
            Text(
              t.settings.customDataDir.mustBeEmpty,
              style: TextStyle(color: colorScheme.error),
            ),
        ],
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => context.pop(),
          child: Text(t.settings.customDataDir.cancel),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: anyErrors ? null : _onConfirm,
          child: Text(t.settings.customDataDir.select),
        ),
      ],
    );
  }
}
