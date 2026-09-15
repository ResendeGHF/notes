// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/editor/pdf_stroke_vector_encoder.dart';
import 'package:saber/data/tools/_tool.dart';

import '../../helpers/test_stroke_factory.dart';

void main() {
  test('exportPolygon decimates dense outlines', () {
    final stroke = testPolylineStroke(
      toolId: ToolId.ballpointPen,
      points: 5000,
      x1: 5000,
    );
    final poly = PdfStrokeVectorEncoder.exportPolygon(stroke);
    expect(
      poly.length,
      lessThanOrEqualTo(PdfStrokeVectorEncoder.maxExportPolygonPoints),
    );
    expect(poly.length, greaterThan(2));
  });

  test('native overlay blob has magic and page header', () {
    final page = EditorPage();
    final stroke = testPolylineStroke(
      toolId: ToolId.ballpointPen,
      points: 40,
    );
    page.insertStroke(stroke);

    final blob = PdfStrokeVectorEncoder.packNativeOverlayBlob(
      pages: [page],
      invert: false,
      exportSizeOf: (p) => p.size,
      strokeBasisOf: (_) => (tx: 0, ty: 0, sx: 1, sy: 1),
    );
    expect(
      blob.sublist(0, 8),
      PdfStrokeVectorEncoder.nativeOverlayMagic,
    );
    final pageCount =
        ByteData.sublistView(blob, 8, 12).getUint32(0, Endian.little);
    expect(pageCount, 1);
    expect(PdfStrokeVectorEncoder.pagesAreNativeEncodable([page]), isTrue);
  });

  test('pdfY flips flutter coordinates', () {
    expect(PdfStrokeVectorEncoder.pdfY(0, 100), 100);
    expect(PdfStrokeVectorEncoder.pdfY(25, 100), 75);
  });
}
