// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:pdf/pdf.dart';
import 'package:saber/data/editor/page.dart';

/// One visible row in a collapsible outline list (depth 0 = PDF root level).
class PdfOutlineFlatRow {
  const PdfOutlineFlatRow({
    required this.key,
    required this.title,
    required this.pageIndex,
    required this.depth,
    required this.hasChildren,
    required this.expanded,
  });

  /// Stable path key, e.g. `0/2/1`, for expand/collapse state.
  final String key;
  final String title;
  final int pageIndex;
  final int depth;
  final bool hasChildren;
  final bool expanded;
}

/// Pre-order flatten of the outline tree, honoring [expandedKeys].
///
/// Nodes whose ancestors are collapsed are omitted. When [expandedKeys] is
/// empty, only root-level entries are returned (sections start collapsed).
List<PdfOutlineFlatRow> flattenPdfOutlineTree(
  List<PdfOutlineItem> roots, {
  Set<String> expandedKeys = const {},
}) {
  final out = <PdfOutlineFlatRow>[];
  void visit(PdfOutlineItem node, int depth, String key) {
    final children = node.children;
    final hasChildren = children != null && children.isNotEmpty;
    final expanded = hasChildren && expandedKeys.contains(key);
    out.add(
      PdfOutlineFlatRow(
        key: key,
        title: node.title,
        pageIndex: node.pageIndex,
        depth: depth,
        hasChildren: hasChildren,
        expanded: expanded,
      ),
    );
    if (!hasChildren || !expanded) return;
    for (var i = 0; i < children.length; i++) {
      visit(children[i], depth + 1, '$key/$i');
    }
  }

  for (var i = 0; i < roots.length; i++) {
    visit(roots[i], 0, '$i');
  }
  return out;
}

/// Looks up an outline node by flatten path key (`0`, `0/2`, …).
PdfOutlineItem? findPdfOutlineByKey(List<PdfOutlineItem> roots, String key) {
  final parts = key.split('/');
  if (parts.isEmpty) return null;
  PdfOutlineItem? node;
  var list = roots;
  for (final part in parts) {
    final i = int.tryParse(part);
    if (i == null || i < 0 || i >= list.length) return null;
    node = list[i];
    list = node.children ?? const [];
  }
  return node;
}

/// Removes [target] from the tree. Returns true if found.
bool removePdfOutlineItem(List<PdfOutlineItem> roots, PdfOutlineItem target) {
  for (var i = 0; i < roots.length; i++) {
    if (identical(roots[i], target)) {
      roots.removeAt(i);
      return true;
    }
    final children = roots[i].children;
    if (children != null && removePdfOutlineItem(children, target)) {
      if (children.isEmpty) roots[i].children = null;
      return true;
    }
  }
  return false;
}

/// Keeps [pageIndex] and [PdfOutlineItem.pageId] aligned with [pages].
///
/// Prefer [pageId] when present (stable across insert/delete/reorder and
/// self-contained PDF export expansion). Drops nodes whose target page no
/// longer exists; orphans' children are promoted.
void syncPdfOutlinesWithPages(
  List<PdfOutlineItem>? roots,
  List<EditorPage> pages,
) {
  if (roots == null || roots.isEmpty) return;

  List<PdfOutlineItem> syncList(List<PdfOutlineItem> items) {
    final out = <PdfOutlineItem>[];
    for (final item in items) {
      final syncedChildren = item.children != null
          ? syncList(item.children!)
          : null;

      var pageIndex = item.pageIndex;
      var pageId = item.pageId;

      if (pageId != null) {
        final idx = pages.indexWhere((p) => p.id == pageId);
        if (idx < 0) {
          if (syncedChildren != null) out.addAll(syncedChildren);
          continue;
        }
        pageIndex = idx;
      } else if (pageIndex >= 0 && pageIndex < pages.length) {
        pageId = pages[pageIndex].id;
      } else {
        if (syncedChildren != null) out.addAll(syncedChildren);
        continue;
      }

      item.pageIndex = pageIndex;
      item.pageId = pageId;
      item.children = syncedChildren == null || syncedChildren.isEmpty
          ? null
          : syncedChildren;
      out.add(item);
    }
    return out;
  }

  final synced = syncList(roots);
  roots
    ..clear()
    ..addAll(synced);
}

/// Remaps outline destinations to export page indices (0-based in the output
/// PDF). Uses [pageId] when possible so linked-PDF expansion / page selection
/// does not break bookmarks.
///
/// Nodes whose target is not in [resolvedNoteIndices] are dropped; children
/// with valid targets are promoted.
List<PdfOutlineItem>? remapPdfOutlinesForExport(
  List<PdfOutlineItem>? roots, {
  required List<EditorPage> pages,
  required List<int> resolvedNoteIndices,
}) {
  if (roots == null || roots.isEmpty || resolvedNoteIndices.isEmpty) {
    return null;
  }

  final pageIdToExportIndex = <int, int>{};
  final noteIndexToExportIndex = <int, int>{};
  for (var exportIdx = 0; exportIdx < resolvedNoteIndices.length; exportIdx++) {
    final noteIdx = resolvedNoteIndices[exportIdx];
    if (noteIdx < 0 || noteIdx >= pages.length) continue;
    noteIndexToExportIndex[noteIdx] = exportIdx;
    final id = pages[noteIdx].id;
    if (id != null) pageIdToExportIndex[id] = exportIdx;
  }

  List<PdfOutlineItem>? remapList(List<PdfOutlineItem>? items) {
    if (items == null || items.isEmpty) return null;
    final out = <PdfOutlineItem>[];
    for (final item in items) {
      final children = remapList(item.children);
      int? exportPage;
      final pid = item.pageId;
      if (pid != null) {
        exportPage = pageIdToExportIndex[pid];
      }
      exportPage ??= noteIndexToExportIndex[item.pageIndex];
      if (exportPage == null) {
        if (children != null) out.addAll(children);
        continue;
      }
      out.add(
        PdfOutlineItem(
          title: item.title,
          pageIndex: exportPage,
          pageId: item.pageId,
          children: children,
        ),
      );
    }
    return out.isEmpty ? null : out;
  }

  return remapList(roots);
}

/// Attaches [roots] as bookmarks on an in-progress [PdfDocument].
///
/// [PdfOutlineItem.pageIndex] must already be the export page index.
void attachPdfOutlinesToDocument(
  PdfDocument doc,
  List<PdfOutlineItem> roots,
) {
  if (roots.isEmpty) return;
  final pages = doc.pdfPageList.pages;
  if (pages.isEmpty) return;

  void addNodes(PdfOutline parent, List<PdfOutlineItem> items) {
    for (final item in items) {
      final destIndex = item.pageIndex.clamp(0, pages.length - 1);
      final node = PdfOutline(
        doc,
        title: item.title,
        dest: pages[destIndex],
      );
      parent.add(node);
      final children = item.children;
      if (children != null && children.isNotEmpty) {
        addNodes(node, children);
      }
    }
  }

  addNodes(doc.outline, roots);
}

/// Serializes outline tree for the Android PDFBox bookmark injector.
List<Map<String, dynamic>> pdfOutlinesToNativeMaps(List<PdfOutlineItem> roots) {
  List<Map<String, dynamic>> mapList(List<PdfOutlineItem> items) {
    return items
        .map(
          (item) => <String, dynamic>{
            'title': item.title,
            'pageIndex': item.pageIndex,
            if (item.children != null && item.children!.isNotEmpty)
              'children': mapList(item.children!),
          },
        )
        .toList();
  }

  return mapList(roots);
}

class PdfOutlineItem {
  String title;
  int pageIndex;

  /// Stable [EditorPage.id] for this destination. Preferred over [pageIndex]
  /// when remapping across insert/delete/reorder or self-contained export.
  int? pageId;

  List<PdfOutlineItem>? children;

  PdfOutlineItem({
    required this.title,
    required this.pageIndex,
    this.pageId,
    this.children,
  });

  Map<String, dynamic> toJson() {
    return {
      't': title,
      'p': pageIndex,
      if (pageId != null) 'pid': pageId,
      if (children != null) 'c': children!.map((c) => c.toJson()).toList(),
    };
  }

  factory PdfOutlineItem.fromJson(Map<String, dynamic> json) {
    return PdfOutlineItem(
      title: json['t'] as String,
      pageIndex: json['p'] as int,
      pageId: (json['pid'] as num?)?.toInt(),
      children: json['c'] != null
          ? (json['c'] as List)
              .map((c) => PdfOutlineItem.fromJson(c as Map<String, dynamic>))
              .toList()
          : null,
    );
  }
}
