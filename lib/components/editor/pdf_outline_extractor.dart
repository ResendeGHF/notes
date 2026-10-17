// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:logging/logging.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:saber/data/editor/pdf_outline.dart';

class PdfOutlineExtractor {
  static final log = Logger('PdfOutlineExtractor');
  
  static final Expando<List<PdfOutlineItem>> _outlineCache = Expando();

  static Future<List<PdfOutlineItem>?> extractOutlines(
    PdfDocument pdfDocument,
  ) async {
    final cached = _outlineCache[pdfDocument];
    if (cached != null) return cached;

    try {
      final outlines = await pdfDocument.loadOutline();
      
      if (outlines.isEmpty) {
        _outlineCache[pdfDocument] = const [];
        return null;
      }

      final result = _mapPdfrxOutlines(outlines);
      _outlineCache[pdfDocument] = result;
      return result;
    } catch (e) {
      log.warning('Failed to extract PDF outlines via pdfrx: $e');
      return null;
    }
  }

  static Future<List<PdfOutlineItem>?> extractOutlinesFromFile(dynamic file) async {
    return null;
  }

  static List<PdfOutlineItem> _mapPdfrxOutlines(List<PdfOutlineNode> nodes) {
    final result = <PdfOutlineItem>[];

    for (int i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      int pageIndex = (node.dest?.pageNumber ?? 1) - 1;
      if (pageIndex < 0) pageIndex = 0;

      result.add(PdfOutlineItem(
        title: node.title,
        pageIndex: pageIndex,
        children: node.children.isNotEmpty 
            ? _mapPdfrxOutlines(node.children) 
            : null,
      ));
    }

    return result;
  }
}
