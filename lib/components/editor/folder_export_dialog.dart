// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/editor/sba_export_dialog.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/i18n/strings.g.dart';

enum FolderExportContentFormat {
  sba,
  pdf,
}

Future<({
  FolderExportContentFormat format,
  FolderArchiveFormat container,
  String? sbaPassword,
  bool sbaIncludeExportMetadata,
})?> showFolderExportDialog(
  BuildContext context,
  String folderName,
) async {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final isDark = theme.brightness == Brightness.dark;

  final result = await showDialog<
      (
        FolderExportContentFormat,
        FolderArchiveFormat,
        String?,
        bool,
      )?>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: colorScheme.surfaceContainerHigh,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: 340,
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t.export.exportFolder,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '"$folderName"',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t.export.exportFolderSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 24),
                _FormatOption(
                  icon: Icons.note_outlined,
                  label: t.export.exportFolderAsSba,
                  value: FolderExportContentFormat.sba,
                  onTap: () async {
                    final mode = await showSbaExportModeDialog(ctx);
                    if (mode.ok && ctx.mounted) {
                      Navigator.pop(
                        ctx,
                        (FolderExportContentFormat.sba,
                            FolderArchiveFormat.zip,
                            mode.password,
                            mode.includeExportMetadata),
                      );
                    }
                  },
                ),
                const SizedBox(height: 10),
                _FormatOption(
                  icon: CupertinoIcons.doc_text,
                  label: t.export.exportFolderAsPdf,
                  value: FolderExportContentFormat.pdf,
                  onTap: () => Navigator.pop(
                    ctx,
                    (
                      FolderExportContentFormat.pdf,
                      FolderArchiveFormat.zip,
                      null,
                      false,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          foregroundColor: colorScheme.onSurface,
                        ),
                        child: Text(t.common.cancel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );


  if (result == null) return null;

  return (
    format: result.$1,
    container: result.$2,
    sbaPassword: result.$3,
    sbaIncludeExportMetadata: result.$4,
  );
}

class _FormatOption extends StatelessWidget {
  const _FormatOption({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final FolderExportContentFormat value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : colorScheme.outlineVariant.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: colorScheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
