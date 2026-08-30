// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:saber/components/home/home_toolbar_chrome.dart';
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
          barrierColor: Colors.black.withValues(alpha: 0.1),
          pageBuilder: (context, _, __) {
            return RenameFolderDialog(
              folderName: folderName,
              doesFolderExist: doesFolderExist,
              renameFolder: renameFolder,
            );
          },
        );
      },
      icon: const Icon(Icons.edit_square),
    );
  }
}

class RenameFolderDialog extends StatefulWidget {
  const RenameFolderDialog({
    super.key,
    required this.folderName,
    required this.doesFolderExist,
    required this.renameFolder,
  });

  final String folderName;
  final bool Function(String) doesFolderExist;
  final Future<void> Function(String newName) renameFolder;

  @override
  State<RenameFolderDialog> createState() => _RenameFolderDialogState();
}

class _RenameFolderDialogState extends State<RenameFolderDialog>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  String? validateFolderName(String? folderName) {
    if (folderName == null || folderName.isEmpty) {
      return t.home.renameFolder.folderNameEmpty;
    }
    if (folderName.contains('/') || folderName.contains('\\')) {
      return t.home.renameFolder.folderNameContainsSlash;
    }
    if (folderName != widget.folderName &&
        widget.doesFolderExist(folderName)) {
      return t.home.renameFolder.folderNameExists;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _controller.text = widget.folderName;
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, -0.05), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final newName = _controller.text;
    if (mounted) {
      Navigator.of(context).pop();
    }
    if (newName != widget.folderName) {
      await widget.renameFolder(newName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 60, right: 16),
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 320,
                decoration: homeRuggedPanelDecoration(context),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
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
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _controller,
                          autofocus: true,
                          style: TextStyle(
                            fontSize: 14,
                            color: colorScheme.onSurface,
                          ),
                          decoration: InputDecoration(
                            hintText: t.home.renameFolder.folderName,
                            prefixIcon: Icon(
                              Icons.folder_outlined,
                              color: colorScheme.primary,
                              size: 20,
                            ),
                            filled: true,
                            fillColor: colorScheme.surface,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: colorScheme.outlineVariant,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: colorScheme.outlineVariant,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: colorScheme.primary,
                                width: 2,
                              ),
                            ),
                          ),
                          validator: validateFolderName,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: TextButton.styleFrom(
                                foregroundColor: colorScheme.onSurfaceVariant,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: Text(
                                t.common.cancel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _submit,
                              style: FilledButton.styleFrom(
                                backgroundColor: colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                elevation: 0,
                              ),
                              child: Text(
                                t.home.renameFolder.rename,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
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
          ),
        ),
      ),
    );
  }
}
