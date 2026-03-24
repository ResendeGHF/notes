// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/files/file_tree.dart';
import 'package:saber/components/home/new_note_button.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/i18n/strings.g.dart';

class VerticalNavbar extends StatefulWidget {
  const VerticalNavbar({
    super.key,
    required this.destinations,
    this.selectedIndex = 0,
    this.onDestinationSelected,
  });

  final List<NavigationRailDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int>? onDestinationSelected;

  @override
  State<VerticalNavbar> createState() => _VerticalNavbarState();
}

class _VerticalNavbarState extends State<VerticalNavbar> {
  var expanded = true;

  void _toggleExpanded() {
    setState(() => expanded = !expanded);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final surfaceColor = isDark ? const Color(0xFF111111) : colorScheme.surface;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      width: expanded ? 320 : 72,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
        border: Border(
          right: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
      ),
      child: Theme(
        data: theme.copyWith(highlightColor: Colors.transparent),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _toggleExpanded,
                      icon: AdaptiveIcon(
                        icon: expanded ? Icons.menu_open : Icons.menu,
                        cupertinoIcon: expanded
                            ? CupertinoIcons.sidebar_left
                            : CupertinoIcons.sidebar_right,
                      ),
                      tooltip: expanded ? 'Collapse sidebar' : 'Expand sidebar',
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic,
                      child: expanded
                          ? Row(
                              key: const ValueKey('expanded'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(width: 8),
                                Text(
                                  t.editor.navigation.title,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ],
                            )
                          : const SizedBox.shrink(key: ValueKey('collapsed')),
                    ),
                  ],
                ),
              ),
            ),

            Column(
              mainAxisSize: MainAxisSize.min,
              children: widget.destinations.asMap().entries.map((entry) {
                final index = entry.key;
                final d = entry.value;
                final isSelected = widget.selectedIndex == index;

                final color = isSelected
                    ? (isDark ? Colors.white : Colors.black)
                    : colorScheme.onSurfaceVariant;
                final icon = (isSelected ? d.selectedIcon : null) ?? d.icon;

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: InkWell(
                    onTap: () => widget.onDestinationSelected?.call(index),
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      height: 48,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.blueGrey.withValues(alpha: 0.25)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.centerLeft,
                          maxWidth: 296,
                          minWidth: 296,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 48,
                                child: IconTheme(
                                  data: IconThemeData(color: color, size: 24),
                                  child: icon,
                                ),
                              ),
                              Expanded(
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 350),
                                  curve: Curves.easeOutCubic,
                                  opacity: expanded ? 1.0 : 0.0,
                                  child: DefaultTextStyle(
                                    style: theme.textTheme.labelLarge!.copyWith(
                                      color: color,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    child: d.label,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            Expanded(
              child: AnimatedOpacity(
                opacity: expanded ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Divider(height: 1),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 8,
                          ),
                          child: Text(
                            'FILES',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              letterSpacing: 1.0,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Expanded(child: FileTree()),
                        ValueListenableBuilder<ImportStatus>(
                          valueListenable: ImportManager.status,
                          builder: (context, status, child) {
                            return AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                              child: status.isImporting
                                  ? Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      margin: const EdgeInsets.fromLTRB(
                                        16,
                                        8,
                                        16,
                                        16,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorScheme
                                            .surfaceContainerHighest
                                            .withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: colorScheme.outlineVariant
                                              .withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(
                                            children: [
                                              const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  status.isParsing
                                                      ? 'Parsing files...'
                                                      : 'Importing...',
                                                  style: theme
                                                      .textTheme
                                                      .labelSmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (!status.isParsing &&
                                                  status.countText.isNotEmpty)
                                                Text(
                                                  status.countText,
                                                  style: theme
                                                      .textTheme
                                                      .labelSmall
                                                      ?.copyWith(
                                                        color: colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                            ],
                                          ),
                                          if (!status.isParsing) ...[
                                            const SizedBox(height: 12),
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: LinearProgressIndicator(
                                                value: status.progress,
                                                minHeight: 4,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              status.fileName,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: colorScheme
                                                        .onSurfaceVariant,
                                                    fontSize: 10,
                                                  ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ],
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            );
                          },
                        ),
                        ValueListenableBuilder<ExportStatus>(
                          valueListenable: ExportManager.status,
                          builder: (context, status, child) {
                            return AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                              child: status.isExporting
                                  ? Container(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: colorScheme.surfaceContainerHigh,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color:
                                                  colorScheme.primaryContainer,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Icon(
                                              Icons.save_rounded,
                                              size: 18,
                                              color: colorScheme
                                                  .onPrimaryContainer,
                                            ),
                                          ),
                                          if (expanded) ...[
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    t.export.exportingNote,
                                                    style: theme
                                                        .textTheme
                                                        .labelMedium
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 6),
                                                  ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          2,
                                                        ),
                                                    child:
                                                        LinearProgressIndicator(
                                                          value:
                                                              status.progress,
                                                          minHeight: 4,
                                                        ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    status.currentFile,
                                                    style: theme
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: colorScheme
                                                              .onSurfaceVariant,
                                                          fontSize: 10,
                                                        ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            );
                          },
                        ),
                        ValueListenableBuilder<BackupStatus>(
                          valueListenable: BackupManager.status,
                          builder: (context, status, child) {
                            return AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                              child: status.isRunning
                                  ? Container(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: colorScheme.surfaceContainerHigh,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color:
                                                  colorScheme.primaryContainer,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Icon(
                                              Icons.cloud_upload_rounded,
                                              size: 18,
                                              color: colorScheme
                                                  .onPrimaryContainer,
                                            ),
                                          ),
                                          if (expanded) ...[
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Backing up...',
                                                    style: theme
                                                        .textTheme
                                                        .labelMedium
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 6),
                                                  ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          2,
                                                        ),
                                                    child:
                                                        LinearProgressIndicator(
                                                          value:
                                                              status.progress,
                                                          minHeight: 4,
                                                        ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    status.currentFile,
                                                    style: theme
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: colorScheme
                                                              .onSurfaceVariant,
                                                          fontSize: 10,
                                                        ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.close,
                                                size: 16,
                                              ),
                                              onPressed:
                                                  BackupManager.cancelBackup,
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                              tooltip: 'Cancel Backup',
                                            ),
                                          ],
                                        ],
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            );
                          },
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
