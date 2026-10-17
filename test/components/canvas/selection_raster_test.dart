// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

// Raster-drag for massive selections: threshold gating, one-shot capture,
// and blit painting without crashing.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_canvas_painter.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/select.dart';

import '../../helpers/test_stroke_factory.dart';

void main() {
  group('SelectionRasterTuning', () {
    test('thresholds gate small selections to vectors', () {
      expect(
        SelectionRasterTuning.shouldRasterize(strokeCount: 10, pointCount: 200),
        isFalse,
      );
      expect(
        SelectionRasterTuning.shouldRasterize(
            strokeCount: 150, pointCount: 200),
        isTrue,
      );
      expect(
        SelectionRasterTuning.shouldRasterize(
            strokeCount: 5, pointCount: 15000),
        isTrue,
      );
    });
  });

  group('captureSelectionRaster', () {
    test('empty selection returns null', () {
      final page = EditorPage();
      expect(
        CanvasPainter.captureSelectionRaster(
          strokes: const [],
          selectionForTint: null,
          page: page,
          invert: false,
          primaryColor: Colors.blue,
          pageIndex: 0,
          totalPages: 1,
          currentScale: 1.0,
          defaultTextStyle: const TextStyle(),
        ),
        isNull,
      );
      page.dispose();
    });

    test('dense selection captures a bitmap covering its bounds', () {
      final page = EditorPage();
      final strokes = <Stroke>[
        for (var i = 0; i < 200; i++)
          testPolylineStroke(
            toolId: ToolId.ballpointPen,
            y: 20.0 + i * 5,
            x0: 20,
            x1: 400,
          ),
      ];
      final captured = CanvasPainter.captureSelectionRaster(
        strokes: strokes,
        selectionForTint: null,
        page: page,
        invert: false,
        primaryColor: Colors.blue,
        pageIndex: 0,
        totalPages: 1,
        currentScale: 1.0,
        defaultTextStyle: const TextStyle(),
      );
      expect(captured, isNotNull);
      final image = captured!.image;
      final bounds = captured.bounds;
      expect(image.width, greaterThan(0));
      expect(image.height, greaterThan(0));
      expect(bounds.width, greaterThan(0));
      // Bitmap covers the union bounds at ~2x.
      expect(image.width, greaterThan(bounds.width));
      image.dispose();
      page.dispose();
    });

    test('painter blits the raster instead of vectors', () {
      final page = EditorPage();
      final strokes = <Stroke>[
        for (var i = 0; i < 200; i++)
          testPolylineStroke(
            toolId: ToolId.ballpointPen,
            y: 20.0 + i * 5,
            x0: 20,
            x1: 400,
          ),
      ];
      final captured = CanvasPainter.captureSelectionRaster(
        strokes: strokes,
        selectionForTint: null,
        page: page,
        invert: false,
        primaryColor: Colors.blue,
        pageIndex: 0,
        totalPages: 1,
        currentScale: 1.0,
        defaultTextStyle: const TextStyle(),
      )!;
      final selection = SelectResult(
        pageIndex: 0,
        pageIndexStart: 0,
        strokes: strokes,
        images: const [],
        path: Path(),
      );
      final preview = SelectionTransformPreview.fromSelection(selection);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Offset.zero & page.size);
      // Exercises the raster branch (identity transform): one blit, no
      // per-stroke vector replay.
      CanvasPainter(
        invert: false,
        strokes: strokes,
        laserStrokes: const [],
        currentStroke: null,
        currentSelection: selection,
        selectionPreview: preview,
        selectionRasterImage: captured.image,
        selectionRasterBounds: captured.bounds,
        primaryColor: Colors.blue,
        page: page,
        showPageIndicator: false,
        pageIndex: 0,
        totalPages: 1,
        currentScale: 1.0,
        defaultTextStyle: const TextStyle(),
        doneSelecting: true,
      ).paint(canvas, page.size);
      recorder.endRecording().dispose();
      captured.image.dispose();
      page.dispose();
    });
  });
}
