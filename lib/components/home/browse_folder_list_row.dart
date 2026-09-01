// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/home/home_list_meta_formatters.dart';
import 'package:saber/components/home/home_list_row_chrome.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';

/// List-mode folder row aligned with [PreviewCard] list layout: rugged panel,
/// compact folder glyph (same treatment as grid cards), and trailing metadata.
class BrowseFolderListRow extends StatefulWidget {
  const BrowseFolderListRow({
    super.key,
    required this.folderName,
    required this.folderPath,
    required this.accentColor,
    this.isLink = false,
    this.isManaging = false,
    this.cachedNoteCount,
    required this.onTap,
    required this.onLongPressStart,
  });

  final String folderName;
  final String folderPath;
  final Color accentColor;
  final bool isLink;
  final bool isManaging;
  final int? cachedNoteCount;
  final VoidCallback onTap;
  final void Function(LongPressStartDetails details) onLongPressStart;

  @override
  State<BrowseFolderListRow> createState() => _BrowseFolderListRowState();
}

class _BrowseFolderListRowState extends State<BrowseFolderListRow> {
  Map<String, dynamic>? _props;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProps();
  }

  @override
  void didUpdateWidget(covariant BrowseFolderListRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.folderPath != widget.folderPath) {
      _props = null;
      _loading = true;
      _loadProps();
    }
  }

  Future<void> _loadProps() async {
    final props = await FileManager.getFolderProperties(widget.folderPath);
    if (!mounted) return;
    setState(() {
      _props = props;
      _loading = false;
    });
  }

  int? _resolvedNoteCount() {
    final p = _props;
    if (p != null && p['file_count'] != null) {
      final n = p['file_count'];
      if (n is int) return n;
      if (n is num) return n.toInt();
    }
    return widget.cachedNoteCount;
  }

  int? _resolvedTotalSize() {
    final p = _props;
    if (p == null || p['total_size'] == null) return null;
    final n = p['total_size'];
    if (n is int) return n;
    if (n is num) return n.toInt();
    return null;
  }

  DateTime? _resolvedModified() {
    final p = _props;
    if (p == null || p['last_modified'] == null) return null;
    final n = p['last_modified'];
    if (n is int) return DateTime.fromMillisecondsSinceEpoch(n);
    if (n is num) {
      return DateTime.fromMillisecondsSinceEpoch(n.toInt());
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    final count = _resolvedNoteCount();
    final modified = _resolvedModified();

    final modifiedStr = modified != null
        ? formatHomeListDate(context, modified)
        : '--';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: widget.isManaging ? null : widget.onTap,
        borderRadius: BorderRadius.circular(16),
        child: GestureDetector(
          onLongPressStart: widget.onLongPressStart,
          behavior: HitTestBehavior.opaque,
          child: HomeListRowSurface(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    widget.isLink ? Icons.folder_shared_rounded : Icons.folder_rounded,
                    color: widget.accentColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                
                // Name Column
                Expanded(
                  flex: 3,
                  child: Text(
                    widget.folderName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                
                // Date Modified Column (Swapped from Creation to Modification properly)
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: HomeListMetaChip(
                      icon: Icons.edit_calendar_outlined,
                      text: modifiedStr,
                      tooltip: 'Date Modified',
                    ),
                  ),
                ),
                
                // Items/Type Column
                Expanded(
                  flex: 1,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: HomeListMetaChip(
                      icon: Icons.insert_drive_file_outlined,
                      text: count != null ? '$count' : 'Folder',
                      tooltip: 'Items Count',
                    ),
                  ),
                ),
                
                if (widget.isManaging) ...[
                  const SizedBox(width: 16),
                  Icon(
                    Icons.drag_handle,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}