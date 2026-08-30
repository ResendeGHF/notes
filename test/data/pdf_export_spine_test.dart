// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/editor/pdf_export_spine.dart';
import 'package:saber/data/file_manager/file_manager.dart';

void main() {
  group('buildSpineFromRows', () {
    setUp(() {
      FileManager.documentsDirectory = '/app/SaberDocuments';
    });

    test('contiguous same file: one segment', () {
      const a = '/app/SaberDocuments/vault/doc.pdf';
      final segs = buildSpineFromRows([
        (path: a, pdfPage: 2),
        (path: a, pdfPage: 3),
        (path: a, pdfPage: 4),
      ]);
      expect(segs, isNotNull);
      expect(segs!.length, 1);
      expect(segs.single.logicalPath, a);
      expect(segs.single.startPage0, 2);
      expect(segs.single.endPage0Inclusive, 4);
    });

    test('path normalization: different prefixes same logical asset → one segment', () {
      final segs = buildSpineFromRows([
        (path: '/app/SaberDocuments/x/a.pdf', pdfPage: 0),
        (path: '/x/a.pdf', pdfPage: 1),
      ]);
      expect(segs, isNotNull);
      expect(segs!.length, 1);
      expect(segs.single.startPage0, 0);
      expect(segs.single.endPage0Inclusive, 1);
    });

    test('new file may start at non-zero pdfPage', () {
      final segs = buildSpineFromRows([
        (path: '/app/SaberDocuments/a.pdf', pdfPage: 0),
        (path: '/app/SaberDocuments/b.pdf', pdfPage: 7),
        (path: '/app/SaberDocuments/b.pdf', pdfPage: 8),
      ]);
      expect(segs, isNotNull);
      expect(segs!.length, 2);
      expect(segs[0].logicalPath, endsWith('a.pdf'));
      expect(segs[0].startPage0, 0);
      expect(segs[0].endPage0Inclusive, 0);
      expect(segs[1].startPage0, 7);
      expect(segs[1].endPage0Inclusive, 8);
    });

    test('gap within same file → null', () {
      final segs = buildSpineFromRows([
        (path: '/app/SaberDocuments/a.pdf', pdfPage: 0),
        (path: '/app/SaberDocuments/a.pdf', pdfPage: 2),
      ]);
      expect(segs, isNull);
    });

    test('empty rows → null', () {
      expect(buildSpineFromRows([]), isNull);
    });
  });
}
