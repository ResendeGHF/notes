// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/editor/pdf_outline.dart';

void main() {
  final tree = [
    PdfOutlineItem(
      title: 'Chapter 1',
      pageIndex: 0,
      children: [
        PdfOutlineItem(
          title: 'Section 1.1',
          pageIndex: 1,
          children: [
            PdfOutlineItem(title: '1.1.a', pageIndex: 2),
          ],
        ),
        PdfOutlineItem(title: 'Section 1.2', pageIndex: 3),
      ],
    ),
    PdfOutlineItem(title: 'Chapter 2', pageIndex: 4),
  ];

  test('starts collapsed: only root sections visible', () {
    final rows = flattenPdfOutlineTree(tree);
    expect(rows.map((r) => r.title), ['Chapter 1', 'Chapter 2']);
    expect(rows.first.hasChildren, isTrue);
    expect(rows.first.expanded, isFalse);
    expect(rows.last.hasChildren, isFalse);
  });

  test('expanding a section reveals only its children', () {
    final rows = flattenPdfOutlineTree(tree, expandedKeys: {'0'});
    expect(rows.map((r) => r.title), [
      'Chapter 1',
      'Section 1.1',
      'Section 1.2',
      'Chapter 2',
    ]);
    expect(rows[1].depth, 1);
    expect(rows[1].hasChildren, isTrue);
    expect(rows[1].expanded, isFalse);
  });

  test('nested expand shows sub-subsections', () {
    final rows = flattenPdfOutlineTree(tree, expandedKeys: {'0', '0/0'});
    expect(rows.map((r) => r.title), [
      'Chapter 1',
      'Section 1.1',
      '1.1.a',
      'Section 1.2',
      'Chapter 2',
    ]);
    expect(rows[2].depth, 2);
  });
}
