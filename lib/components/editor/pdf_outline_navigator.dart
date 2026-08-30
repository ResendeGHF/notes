// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:saber/components/home/home_toolbar_chrome.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/data/editor/pdf_outline.dart';
import 'package:saber/i18n/strings.g.dart';

/// Scrollable collapsible PDF outline tree for the editor Pages side panel.
///
/// Sections start collapsed so only root-level entries show; expand chevrons
/// reveal subsection / sub-subsection levels. When [readOnly] is false, users
/// can add / rename / delete handwritten outline entries.
class PdfOutlineListView extends StatefulWidget {
  const PdfOutlineListView({
    super.key,
    required this.outlines,
    required this.onPageSelected,
    this.readOnly = true,
    this.onAddOutline,
    this.onRenameOutline,
    this.onDeleteOutline,
  });

  final List<PdfOutlineItem> outlines;
  final void Function(int pageIndex) onPageSelected;
  final bool readOnly;
  final VoidCallback? onAddOutline;
  final void Function(PdfOutlineItem item, String newTitle)? onRenameOutline;
  final void Function(PdfOutlineItem item)? onDeleteOutline;

  @override
  State<PdfOutlineListView> createState() => _PdfOutlineListViewState();
}

class _PdfOutlineListViewState extends State<PdfOutlineListView> {
  /// Path keys of expanded nodes. Empty ⇒ only roots visible.
  final Set<String> _expandedKeys = {};

  void _toggleExpanded(String key) {
    setState(() {
      if (!_expandedKeys.remove(key)) {
        _expandedKeys.add(key);
      }
    });
  }

  Future<void> _promptRename(PdfOutlineItem item) async {
    final controller = TextEditingController(text: item.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(t.editor.navigation.renameOutline),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: t.editor.navigation.outlineTitle,
            ),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t.common.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: Text(t.common.done),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (newTitle == null) return;
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;
    widget.onRenameOutline?.call(item, trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = !widget.readOnly;
    final flatRows = widget.outlines.isEmpty
        ? const <PdfOutlineFlatRow>[]
        : flattenPdfOutlineTree(
            widget.outlines,
            expandedKeys: _expandedKeys,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canEdit)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: FilledButton.tonalIcon(
              onPressed: widget.onAddOutline,
              icon: const Icon(Icons.bookmark_add_outlined, size: 20),
              label: Text(t.editor.navigation.addOutlineForPage),
            ),
          ),
        Expanded(
          child: flatRows.isEmpty
              ? _EmptyOutlineBody(canEdit: canEdit)
              : Scrollbar(
                  thumbVisibility: true,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
                    itemCount: flatRows.length,
                    addRepaintBoundaries: true,
                    addAutomaticKeepAlives: false,
                    itemBuilder: (context, index) {
                      final row = flatRows[index];
                      final item = findPdfOutlineByKey(
                        widget.outlines,
                        row.key,
                      );
                      return _OutlineTreeRow(
                        row: row,
                        onToggleExpand: row.hasChildren
                            ? () => _toggleExpanded(row.key)
                            : null,
                        onSelect: () => widget.onPageSelected(row.pageIndex),
                        onRename: canEdit && item != null
                            ? () => _promptRename(item)
                            : null,
                        onDelete: canEdit && item != null
                            ? () => widget.onDeleteOutline?.call(item)
                            : null,
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _EmptyOutlineBody extends StatelessWidget {
  const _EmptyOutlineBody({required this.canEdit});

  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 40,
              color: cs.onSurfaceVariant.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 12),
            Text(
              canEdit
                  ? t.editor.navigation.noOutlineEntriesHint
                  : t.editor.navigation.noPdfOutlineEntries,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutlineTreeRow extends StatelessWidget {
  const _OutlineTreeRow({
    required this.row,
    required this.onSelect,
    this.onToggleExpand,
    this.onRename,
    this.onDelete,
  });

  final PdfOutlineFlatRow row;
  final VoidCallback onSelect;
  final VoidCallback? onToggleExpand;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isRoot = row.depth == 0;
    final indent = row.depth * 14.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: homeRuggedPanelDecoration(context, borderAlpha: 0.14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(width: 4 + indent),
              if (row.hasChildren)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 40,
                  ),
                  tooltip: row.expanded ? 'Collapse' : 'Expand',
                  onPressed: onToggleExpand,
                  icon: Icon(
                    row.expanded
                        ? Icons.expand_more_rounded
                        : Icons.chevron_right_rounded,
                    size: 22,
                    color: cs.onSurfaceVariant,
                  ),
                )
              else
                const SizedBox(width: 36),
              Expanded(
                child: InkWell(
                  onTap: onSelect,
                  onLongPress: onRename,
                  borderRadius: BorderRadius.circular(kSaberContainerRadius),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(2, 11, 4, 11),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            row.title,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight:
                                  isRoot ? FontWeight.w600 : FontWeight.w500,
                              fontSize: isRoot ? 15 : 14,
                              height: 1.35,
                              letterSpacing: -0.12,
                            ),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest
                                .withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color:
                                  cs.outlineVariant.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            child: Text(
                              '${row.pageIndex + 1}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.15,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (onDelete != null || onRename != null)
                PopupMenuButton<String>(
                  tooltip: t.editor.navigation.outlineActions,
                  padding: EdgeInsets.zero,
                  onSelected: (value) {
                    if (value == 'rename') onRename?.call();
                    if (value == 'delete') onDelete?.call();
                  },
                  itemBuilder: (context) => [
                    if (onRename != null)
                      PopupMenuItem(
                        value: 'rename',
                        child: Text(t.editor.navigation.renameOutline),
                      ),
                    if (onDelete != null)
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(t.editor.navigation.deleteOutline),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
