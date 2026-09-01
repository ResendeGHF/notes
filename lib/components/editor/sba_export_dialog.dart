// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:saber/i18n/strings.g.dart';

Widget _buildM3Dialog({
  required BuildContext context,
  required Widget child,
}) {
  final colorScheme = Theme.of(context).colorScheme;

  return Dialog(
    backgroundColor: colorScheme.surfaceContainerHigh,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(28),
    ),
    insetPadding: const EdgeInsets.all(24),
    child: SizedBox(
      width: 420,
      child: child,
    ),
  );
}

typedef SbaExportModeResult = ({
  bool ok,
  String? password,
  bool shareLinks,
  bool includeExportMetadata,
});

Future<SbaExportModeResult> showSbaExportModeDialog(
  BuildContext context, {
  bool hasExternalLinks = false,

  bool encryptionApplicable = true,
}) async {
  ({
    bool? useEncryption,
    bool shareLinks,
    bool includeExportMetadata,
  })? step1Result;
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final isDark = theme.brightness == Brightness.dark;

  step1Result = await showDialog<
          ({bool? useEncryption, bool shareLinks, bool includeExportMetadata})>(
        context: context,
        builder: (ctx) {
          var shareLinks = false;
          var includeExportMetadata = true;
          return StatefulBuilder(
            builder: (context, setState) => _buildM3Dialog(
              context: ctx,
              child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Text(
                  encryptionApplicable ? t.export.exportSba : t.export.pdf,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  encryptionApplicable
                      ? t.export.exportSbaContent
                      : t.export.shareLinksSubtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (encryptionApplicable) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.export.exportMetadata,
                              style: theme.textTheme.bodyLarge,
                            ),
                            Text(
                              t.export.exportMetadataSubtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: includeExportMetadata,
                        onChanged: (v) =>
                            setState(() => includeExportMetadata = v),
                      ),
                    ],
                  ),
                ),
              ],
              if (hasExternalLinks) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.export.shareLinks,
                              style: theme.textTheme.bodyLarge,
                            ),
                            Text(
                              t.export.shareLinksSubtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: shareLinks,
                        onChanged: (v) => setState(() => shareLinks = v),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (encryptionApplicable) ...[
                      FilledButton.tonal(
                        onPressed: () => Navigator.pop(
                          ctx,
                          (
                            useEncryption: false,
                            shareLinks: shareLinks,
                            includeExportMetadata: includeExportMetadata,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(t.export.unencrypted),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => Navigator.pop(
                          ctx,
                          (
                            useEncryption: true,
                            shareLinks: shareLinks,
                            includeExportMetadata: includeExportMetadata,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(t.export.encrypted),
                      ),
                    ] else ...[
                      FilledButton(
                        onPressed: () => Navigator.pop(
                          ctx,
                          (
                            useEncryption: false,
                            shareLinks: shareLinks,
                            includeExportMetadata: false,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(t.export.export),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, null),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(t.common.cancel),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  if (step1Result == null) {
    return (
      ok: false,
      password: null,
      shareLinks: false,
      includeExportMetadata: true,
    );
  }
  final useEncryption = step1Result.useEncryption ?? false;
  final shareLinks = step1Result.shareLinks;
  final includeExportMetadata = step1Result.includeExportMetadata;
  if (!useEncryption) {
    return (
      ok: true,
      password: null,
      shareLinks: shareLinks,
      includeExportMetadata: includeExportMetadata,
    );
  }

  final controller = TextEditingController();
  final confirmController = TextEditingController();
  String? errorText;

  final resultPassword = await showDialog<String?>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setState) => _buildM3Dialog(
        context: ctx,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Text(
                t.export.setSharedPassword,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.export.setPasswordContent,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: t.vault.password,
                        errorText: errorText,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: t.export.confirmPassword,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, null),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(t.common.cancel),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      final p1 = controller.text;
                      final p2 = confirmController.text;
                      if (p1.isEmpty) {
                        setState(() => errorText = t.export.passwordRequired);
                        return;
                      }
                      if (p1 != p2) {
                        setState(
                          () => errorText = t.export.passwordsDoNotMatch,
                        );
                        return;
                      }
                      setState(() => errorText = null);
                      Navigator.pop(ctx, p1);
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(t.export.export),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  controller.dispose();
  confirmController.dispose();

  if (resultPassword == null) {
    return (
      ok: false,
      password: null,
      shareLinks: false,
      includeExportMetadata: true,
    );
  }
  return (
    ok: true,
    password: resultPassword,
    shareLinks: shareLinks,
    includeExportMetadata: includeExportMetadata,
  );
}

Future<String?> showSbaImportPasswordDialog(BuildContext context) async {
  final controller = TextEditingController();
  String? errorText;

  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final isDark = theme.brightness == Brightness.dark;

  final password = await showDialog<String?>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setState) => _buildM3Dialog(
        context: ctx,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Text(
                t.export.encryptedSba,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.export.encryptedSbaContent,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      obscureText: true,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: t.vault.password,
                        errorText: errorText,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, null),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(t.common.cancel),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      final p = controller.text;
                      if (p.isEmpty) {
                        setState(() => errorText = t.export.passwordRequired);
                        return;
                      }
                      Navigator.pop(ctx, p);
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(t.export.import),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  controller.dispose();
  return password;
}
