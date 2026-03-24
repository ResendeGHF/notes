// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:saber/i18n/strings.g.dart';

class RenameFolderButton extends StatelessWidget {
  const RenameFolderButton({
    super.key,
    required this.folderName,
    required this.doesFolderExist,
    required this.renameFolder,
  });

  final String folderName;
  final bool Function(String) doesFolderExist;
  final Future<void> Function(String newName) renameFolder;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: .zero,
      tooltip: t.home.renameFolder.renameFolder,
      onPressed: () {
        showGeneralDialog(
          context: context,
          barrierDismissible: true,
          barrierLabel: 'Dismiss',
          barrierColor: Colors.black.withValues(alpha: 0.2),
          transitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (context, anim1, anim2) {
            return _RenameFolderDialog(
              folderName: folderName,
              doesFolderExist: doesFolderExist,
              renameFolder: renameFolder,
            );
          },
          transitionBuilder: (context, anim1, anim2, child) {
            return FadeTransition(
              opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOut),
              child: SlideTransition(
                position:
                    Tween<Offset>(
                      begin: const Offset(0, -0.05),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: anim1,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                child: child,
              ),
            );
          },
        );
      },
      icon: const Icon(Icons.edit_square),
    );
  }
}

class _RenameFolderDialog extends StatefulWidget {
  const _RenameFolderDialog({

    super.key,
    required this.folderName,
    required this.doesFolderExist,
    required this.renameFolder,
  });

  final String folderName;
  final bool Function(String) doesFolderExist;
  final Future<void> Function(String newName) renameFolder;

  @override
  State<_RenameFolderDialog> createState() => _RenameFolderDialogState();
}

class _RenameFolderDialogState extends State<_RenameFolderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  String? validateFolderName(String? folderName) {
    if (folderName == null || folderName.isEmpty) {
      return t.home.renameFolder.folderNameEmpty;
    }
    if (folderName.contains('/') || folderName.contains('\\')) {
      return t.home.renameFolder.folderNameContainsSlash;
    }
    if (folderName != widget.folderName && widget.doesFolderExist(folderName)) {
      return t.home.renameFolder.folderNameExists;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _controller.text = widget.folderName;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 100, left: 24, right: 24),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 340,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.home.renameFolder.renameFolder,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _controller,
                    autofocus: true,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.done,
                    style: TextStyle(
                      fontSize: 15,
                      color: colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: t.home.renameFolder.folderName,
                      filled: true,
                      fillColor: colorScheme.surface,
                      prefixIcon: Icon(
                        CupertinoIcons.pencil,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    validator: validateFolderName,
                    onFieldSubmitted: (_) async {
                      if (!_formKey.currentState!.validate()) return;
                      if (_controller.text != widget.folderName) {
                        await widget.renameFolder(_controller.text);
                      }
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        child: Text(
                          t.common.cancel,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          if (!_formKey.currentState!.validate()) return;
                          if (_controller.text != widget.folderName) {
                            await widget.renameFolder(_controller.text);
                          }
                          if (!context.mounted) return;
                          Navigator.of(context).pop();
                        },
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          t.home.renameFolder.rename,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
