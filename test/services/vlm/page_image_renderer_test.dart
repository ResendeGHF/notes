// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/editor/canvas_background_pattern.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/services/vlm/page_image_renderer.dart';

import '../../helpers/test_stroke_factory.dart';

Future<int> _recordedBytes(EditorPage page, {Rect? crop}) {
  final full = Offset.zero & page.size;
  final src = crop == null ? full : crop.intersect(full);
  final (w, h) = PageImageRenderer.outputSizeFor(src, 1568);
  return PageImageRenderer.recordPagePicture(
    page: page,
    pageIndex: 0,
    totalPages: 1,
    invert: false,
    backgroundColor: const Color(0xFFFCFCFC),
    backgroundPattern: CanvasBackgroundPattern.lined,
    lineHeight: 40,
    lineThickness: 1.0,
    primaryColor: Colors.blue,
    secondaryColor: Colors.blue,
    src: src,
    outputWidth: w,
    outputHeight: h,
  ).then((picture) {
    try {
      return picture.approximateBytesUsed;
    } finally {
      picture.dispose();
    }
  });
}

void main() {
  testWidgets('records draw ops for an ink page', (tester) async {
    final page = EditorPage();
    page.insertStroke(
      testPolylineStroke(toolId: ToolId.fountainPen, y: 200, x0: 50, x1: 800),
    );
    page.insertStroke(
      testPolylineStroke(toolId: ToolId.ballpointPen, y: 400, x0: 50, x1: 800),
    );

    // Blank background is the default for model input: ruled lines are
    // stripped, so this measures ink ops only.
    expect(await _recordedBytes(page), greaterThan(200));
    page.dispose();
  });

  testWidgets('records a selection crop', (tester) async {
    final page = EditorPage();
    page.insertStroke(
      testPolylineStroke(toolId: ToolId.fountainPen, y: 200, x0: 50, x1: 800),
    );

    expect(
      await _recordedBytes(page, crop: const Rect.fromLTWH(0, 0, 500, 500)),
      greaterThan(100),
    );
    page.dispose();
  });

  testWidgets('blankBackground strips pattern lines for model input', (
    tester,
  ) async {
    Future<int> record({required bool blank}) {
      final page = EditorPage();
      page.insertStroke(
        testPolylineStroke(toolId: ToolId.fountainPen, y: 200, x0: 50, x1: 800),
      );
      final full = Offset.zero & page.size;
      final (w, h) = PageImageRenderer.outputSizeFor(full, 1568);
      return PageImageRenderer.recordPagePicture(
        page: page,
        pageIndex: 0,
        totalPages: 1,
        invert: false,
        backgroundColor: const Color(0xFFFCFCFC),
        backgroundPattern: CanvasBackgroundPattern.lined,
        lineHeight: 40,
        lineThickness: 1.0,
        primaryColor: Colors.blue,
        secondaryColor: Colors.blue,
        src: full,
        outputWidth: w,
        outputHeight: h,
        blankBackground: blank,
      ).then((picture) {
        try {
          return picture.approximateBytesUsed;
        } finally {
          picture.dispose();
          page.dispose();
        }
      });
    }

    final patterned = await record(blank: false);
    final blank = await record(blank: true);
    // Ruled lines are real draw ops: stripping them changes the picture.
    expect(patterned, isNot(equals(blank)));
    expect(blank, greaterThan(100));
  });

  testWidgets('output size respects the long-edge bound', (tester) async {
    final page = EditorPage();
    final full = Offset.zero & page.size;
    final (w, h) = PageImageRenderer.outputSizeFor(full, 1568);
    expect(w <= 1568 && h <= 1568, isTrue);
    expect(w > 0 && h > 0, isTrue);
    page.dispose();
  });

  testWidgets('empty crop throws instead of recording blanks', (
    tester,
  ) async {
    final page = EditorPage();
    await expectLater(
      PageImageRenderer.renderPagePng(
        page: page,
        pageIndex: 0,
        totalPages: 1,
        invert: false,
        backgroundColor: const Color(0xFFFCFCFC),
        backgroundPattern: CanvasBackgroundPattern.lined,
        lineHeight: 40,
        lineThickness: 1.0,
        primaryColor: Colors.blue,
        secondaryColor: Colors.blue,
        crop: Rect.zero,
      ),
      throwsA(isA<VlmPageRenderException>()),
    );
    page.dispose();
  });
}
