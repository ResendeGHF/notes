// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/home/home_list_meta_formatters.dart';
import 'package:saber/components/home/home_list_row_chrome.dart';
import 'package:saber/data/file_manager/file_manager.dart';
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

  DateTime? _resolvedCreated() {
    final p = _props;
    if (p == null || p['created_at'] == null) return null;
    final n = p['created_at'];
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
    final fl = t.home.fileList;

    Widget metaRow() {
      if (_loading) {
        return SizedBox(
          height: 26,
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary.withValues(alpha: 0.85),
              ),
            ),
          ),
        );
      }

      final count = _resolvedNoteCount();
      final sizeBytes = _resolvedTotalSize();
      final created = _resolvedCreated();
      final modified = _resolvedModified();

      final countStr = count != null ? '$count' : '—';
      final sizeStr = sizeBytes != null ? formatHomeListBytes(sizeBytes) : '—';
      final createdStr = created != null
          ? formatHomeListDate(context, created)
          : '—';
      final modifiedStr = modified != null
          ? formatHomeListDate(context, modified)
          : '—';

      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          HomeListMetaChip(
            icon: Icons.sticky_note_2_outlined,
            text: countStr,
            tooltip: fl.metaNotesInside,
          ),
          HomeListMetaChip(
            icon: Icons.sd_storage_outlined,
            text: sizeStr,
            tooltip: fl.metaSize,
          ),
          HomeListMetaChip(
            icon: Icons.event_note_outlined,
            text: createdStr,
            tooltip: 'Created',
          ),
          HomeListMetaChip(
            icon: Icons.edit_calendar_outlined,
            text: modifiedStr,
            tooltip: fl.metaModified,
          ),
        ],
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.isManaging ? null : widget.onTap,
        onLongPressStart: widget.onLongPressStart,
        child: HomeListRowSurface(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 68,
                height: 84,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: widget.accentColor.withValues(
                            alpha: theme.brightness == Brightness.dark
                                ? 0.16
                                : 0.10,
                          ),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: widget.accentColor.withValues(
                              alpha: theme.brightness == Brightness.dark
                                  ? 0.30
                                  : 0.20,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 13,
                      bottom: 13,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              widget.accentColor.withValues(alpha: 0.82),
                              widget.accentColor.withValues(alpha: 0.38),
                            ],
                          ),
                        ),
                        child: const SizedBox(width: 4),
                      ),
                    ),
                    Icon(
                      CupertinoIcons.folder_fill,
                      color: widget.accentColor,
                      size: 38,
                    ),
                    if (widget.isLink)
                      Positioned(
                        bottom: 14,
                        right: 12,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colorScheme.outlineVariant.withValues(
                                alpha: 0.30,
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: Icon(
                              Icons.shortcut,
                              size: 12,
                              color: widget.accentColor,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.folderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        letterSpacing: -0.25,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    metaRow(),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (widget.isManaging)
                Icon(
                  Icons.drag_handle,
                  color: colorScheme.onSurfaceVariant,
                  size: 22,
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.48),
                  size: 24,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
