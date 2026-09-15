// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/editor/pdf_outline.dart';

void main() {
  group('remapPdfOutlinesForExport', () {
    test('maps by pageId after shareLinks-style page insertion', () {
      final pages = [
        EditorPage(id: 10),
        EditorPage(id: 99), // inserted linked PDF page
        EditorPage(id: 11),
      ];
      final roots = [
        PdfOutlineItem(title: 'Intro', pageIndex: 0, pageId: 10),
        PdfOutlineItem(
          title: 'Chapter',
          pageIndex: 1,
          pageId: 11,
          children: [
            PdfOutlineItem(title: 'Section', pageIndex: 1, pageId: 11),
          ],
        ),
      ];

      final remapped = remapPdfOutlinesForExport(
        roots,
        pages: pages,
        resolvedNoteIndices: [0, 1, 2],
      );

      expect(remapped, isNotNull);
      expect(remapped!.length, 2);
      expect(remapped[0].pageIndex, 0);
      expect(remapped[1].pageIndex, 2);
      expect(remapped[1].children!.single.pageIndex, 2);
    });

    test('drops outlines whose pages are not exported', () {
      final pages = [
        EditorPage(id: 1),
        EditorPage(id: 2),
        EditorPage(id: 3),
      ];
      final roots = [
        PdfOutlineItem(title: 'A', pageIndex: 0, pageId: 1),
        PdfOutlineItem(title: 'B', pageIndex: 2, pageId: 3),
      ];

      final remapped = remapPdfOutlinesForExport(
        roots,
        pages: pages,
        resolvedNoteIndices: [0, 1], // page 3 not exported
      );

      expect(remapped!.length, 1);
      expect(remapped.single.title, 'A');
      expect(remapped.single.pageIndex, 0);
    });

    test('syncPdfOutlinesWithPages updates indices from pageId', () {
      final pages = [
        EditorPage(id: 5),
        EditorPage(id: 6),
      ];
      final roots = [
        PdfOutlineItem(title: 'Late', pageIndex: 0, pageId: 6),
      ];

      syncPdfOutlinesWithPages(roots, pages);
      expect(roots.single.pageIndex, 1);
      expect(roots.single.pageId, 6);
    });
  });
}
