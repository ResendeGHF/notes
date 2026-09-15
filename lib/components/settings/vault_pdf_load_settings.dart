// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/i18n/strings.g.dart';

class VaultPdfLoadSettings extends StatelessWidget {
  const VaultPdfLoadSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ValueListenableBuilder<String>(
        valueListenable: stows.vaultPdfLoadMode,
        builder: (context, mode, _) {
          final isRamOnly = mode == 'ram_only';
          return ExpansionTile(
            leading: Icon(
              isRamOnly ? Icons.memory : Icons.speed,
              color: colorScheme.primary,
            ),
            title: const Text('Secure PDF loading'),
            subtitle: Text(
              isRamOnly
                  ? 'Decrypted content stays in RAM only — never written to disk'
                  : 'Large PDFs decrypt to a temp file (mmap) · Deleted when closed',
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              _buildExpandedContent(context),
            ],
          );
        },
      ),
    );
  }

  Widget _buildExpandedContent(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [

        ValueListenableBuilder<String>(
          valueListenable: stows.vaultPdfLoadMode,
          builder: (context, mode, _) {
            return SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'ram_only',
                  icon: Icon(Icons.memory, size: 18),
                  label: Text('RAM'),
                ),
                ButtonSegment(
                  value: 'temp_file',
                  icon: Icon(Icons.speed, size: 18),
                  label: Text('Temp'),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (selection) {
                stows.vaultPdfLoadMode.value = selection.first;
                // Listener on VaultAdapter prunes plaintext temps for RAM-only paths.
              },
              style: ButtonStyle(
                padding: WidgetStateProperty.all(
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                visualDensity: VisualDensity.compact,
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        Text(
          'RAM keeps plaintext off disk (default). Temp is faster for large PDFs and may write short-lived decrypted files.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),

        ValueListenableBuilder<bool>(
          valueListenable: stows.vaultPdfAllowLargeRam,
          builder: (context, allowLargeRam, _) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          context.t.editor.vaultPdfLargeRam.allowLarge,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          allowLargeRam
                              ? context.t.editor.vaultPdfLargeRam
                                  .allowLargeSubtitleOn
                              : context.t.editor.vaultPdfLargeRam
                                  .allowLargeSubtitleOff,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: allowLargeRam,
                    onChanged: (v) =>
                        stows.vaultPdfAllowLargeRam.value = v,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),

        TextButton.icon(
          onPressed: () {
            context.push(RoutePaths.vaultPdfLoadOverrides);
          },
          icon: Icon(Icons.tune_rounded, size: 18, color: colorScheme.primary),
          label: const Text('Manage per-file overrides'),
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.primary,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }
}
