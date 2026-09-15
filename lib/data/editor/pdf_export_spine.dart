// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/file_manager/file_manager.dart';

/// One contiguous page range inside a single PDF asset file for unmodified
/// multi-asset export passthrough.
class PdfSpineSegment {
  const PdfSpineSegment({
    required this.logicalPath,
    required this.startPage0,
    required this.endPage0Inclusive,
  });

  /// Filesystem or vault path for [_resolvePlainPdfPathForExport]; kept as the
  /// first raw path seen for this segment (may differ from other rows’ strings
  /// while [FileManager.toRelativePath] matches).
  final String logicalPath;
  final int startPage0;
  final int endPage0Inclusive;
}

/// True when this page cannot use unmodified PDF spine passthrough (Quill text,
/// ink, overlays, non-PDF background, rotation, or invalid PDF ref).
bool pageBlocksPdfPassthrough(EditorPage page) {
  final doc = page.quill.controller.document;
  if (!doc.isEmpty() && doc.toPlainText().trim().isNotEmpty) return true;
  if (page.allStrokesInDrawOrder.isNotEmpty) return true;
  if (page.allImagesInDrawOrder.isNotEmpty) return true;
  final bg = page.backgroundImage;
  if (bg is! PdfEditorImage) return true;
  if (bg.rotationDeg.abs() > 0.01) return true;
  final path = bg.pdfFile?.path;
  if (path == null || path.isEmpty) return true;
  if (bg.pdfPage < 0) return true;
  return false;
}

/// Builds spine segments from hydrated PDF-background rows (paths may differ
/// by prefix while representing the same vault asset).
List<PdfSpineSegment>? buildSpineFromRows(List<({String path, int pdfPage})> rows) {
  if (rows.isEmpty) return null;
  final segments = <PdfSpineSegment>[];
  String? prevNorm;
  int? prevLocal;

  for (final row in rows) {
    final path = row.path;
    if (path.isEmpty) return null;
    final lp = row.pdfPage;
    if (lp < 0) return null;
    final norm = FileManager.toRelativePath(path);

    if (prevNorm == null) {
      segments.add(
        PdfSpineSegment(
          logicalPath: path,
          startPage0: lp,
          endPage0Inclusive: lp,
        ),
      );
    } else if (norm == prevNorm) {
      if (lp != prevLocal! + 1) return null;
      final last = segments.removeLast();
      segments.add(
        PdfSpineSegment(
          logicalPath: last.logicalPath,
          startPage0: last.startPage0,
          endPage0Inclusive: lp,
        ),
      );
    } else {
      segments.add(
        PdfSpineSegment(
          logicalPath: path,
          startPage0: lp,
          endPage0Inclusive: lp,
        ),
      );
    }
    prevNorm = norm;
    prevLocal = lp;
  }
  return segments;
}

/// Unmodified PDF-background pages only: ordered segments where within each
/// file local page indices are consecutive; a new file may start at any local
/// page index. Respects arbitrary [pageIndices] (subset / reorder).
List<PdfSpineSegment>? buildUnmodifiedPdfSpine(
  EditorCoreInfo info,
  List<int> pageIndices,
) {
  if (pageIndices.isEmpty) return null;
  final rows = <({String path, int pdfPage})>[];
  for (final editorIdx in pageIndices) {
    info.ensurePageHydrated(editorIdx);
    final page = info.pages[editorIdx];
    if (pageBlocksPdfPassthrough(page)) return null;
    final bg = page.backgroundImage! as PdfEditorImage;
    final path = bg.pdfFile!.path;
    rows.add((path: path, pdfPage: bg.pdfPage));
  }
  return buildSpineFromRows(rows);
}
