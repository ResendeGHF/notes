// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Tests for the document dispatcher that normalizes `.djvu`/`.epub` imports
// to PDF and maps their outlines to the editor's model.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/document_conversion/document_converter.dart';

import 'djvu/djvu_fixture.dart';
import 'epub/epub_test_utils.dart';

List<String> _titles(List<ConvertedOutlineEntry> entries) => [
  for (final entry in entries) entry.title,
];

void main() {
  group('documentFormatForPath', () {
    test('detects the supported formats', () {
      expect(documentFormatForPath('book.pdf'), DocumentFormat.pdf);
      expect(documentFormatForPath('BOOK.PDF'), DocumentFormat.pdf);
      expect(documentFormatForPath('/a/b/book.epub'), DocumentFormat.epub);
      expect(documentFormatForPath('book.djvu'), DocumentFormat.djvu);
      expect(documentFormatForPath('book.djv'), DocumentFormat.djvu);
      expect(documentFormatForPath('book.sbn2'), isNull);
      expect(documentFormatForPath('book'), isNull);
      expect(documentFormatForPath('book.'), isNull);
    });
  });

  group('convertDocumentToPdf', () {
    test('converts DjVu and maps NAVM bookmarks', () async {
      final result = await convertDocumentToPdf(
        readDjvuFile('annotated'),
        format: DocumentFormat.djvu,
      );

      expect(result.pageCount, 3);
      expect(ascii.decode(result.pdf.sublist(0, 5)), '%PDF-');
      expect(_titles(result.outline), [
        'Chapter 1 — Beginning',
        'Chapter 2 — End',
      ]);
      expect(result.outline[0].pageIndex, 0);
      expect(_titles(result.outline[0].children), [
        'Section 1.1',
        'Section 1.2',
      ]);
      expect(result.outline[0].children[1].pageIndex, 1);
      expect(result.outline[1].pageIndex, 2);
    });

    test('converts EPUB and maps the navigation document', () async {
      final result = await convertDocumentToPdf(
        readEpubFixture('book.epub'),
        format: DocumentFormat.epub,
        epubOptions: readEpubFonts(),
      );

      expect(result.pageCount, greaterThan(10));
      expect(_titles(result.outline), [
        'Chapter 1 — Start',
        'Chapter 2 — Middle',
        'Chapter 3 — Unknown Fragment',
      ]);
      expect(_titles(result.outline.first.children), [
        'Section 1.1',
        'Section 1.2',
      ]);
      // A section anchored at the start of a spanning block keeps the first
      // painted page.
      expect(
        result.outline.first.children.first.pageIndex,
        result.outline.first.pageIndex,
      );
      expect(
        result.outline.first.children.last.pageIndex,
        greaterThan(result.outline.first.children.first.pageIndex),
      );
      for (final entry in result.outline) {
        expect(entry.pageIndex, inInclusiveRange(0, result.pageCount - 1));
      }
    });

    test('rejects PDF input', () {
      expect(
        () => convertDocumentToPdf(
          Uint8List(0),
          format: DocumentFormat.pdf,
        ),
        throwsArgumentError,
      );
    });
  });

  group('convertDocumentFileToPdf', () {
    test('reads the document inside the isolate', () async {
      final result = await convertDocumentFileToPdf(
        '$djvuFixtureRoot/annotated.djvu',
        format: DocumentFormat.djvu,
      );
      expect(result.pageCount, 3);
      expect(_titles(result.outline), [
        'Chapter 1 — Beginning',
        'Chapter 2 — End',
      ]);
    });

    test('propagates file errors', () async {
      await expectLater(
        convertDocumentFileToPdf(
          '$djvuFixtureRoot/missing.djvu',
          format: DocumentFormat.djvu,
        ),
        throwsA(isA<PathNotFoundException>()),
      );
    });
  });
}
