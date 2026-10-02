// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_canvas_painter.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';
import 'package:saber/data/tools/_tool.dart';

/// The live stroke must render fully opaque, exactly like committed ink.
/// Regression test: the paper-bleed underlay once leaked its 0.20 alpha
/// into the shared paint, so the live "crisp" core drew semi-transparent
/// while the baked commit stayed solid.
void main() {
  group('Live stroke opacity', () {
    late bool prevPrediction;
    late bool prevStabilization;

    setUp(() {
      prevPrediction = stows.strokePrediction.value;
      prevStabilization = stows.strokeStabilization.value;
      stows.strokePrediction.value = false;
      stows.strokeStabilization.value = false;
    });

    tearDown(() {
      stows.strokePrediction.value = prevPrediction;
      stows.strokeStabilization.value = prevStabilization;
    });

    Stroke diagonalStroke({required bool complete}) {
      final stroke = Stroke(
        color: Colors.black,
        pressureEnabled: true,
        options: StrokeOptions(
          size: 10,
          simulatePressure: false,
          isComplete: complete,
        ),
        pageIndex: 0,
        page: HasSize(EditorPage.defaultSize),
        toolId: ToolId.advancedPen,
      );
      for (var i = 0; i < 8; i++) {
        stroke.addPoint(
          Offset(60.0 + i * 12.0, 60.0 + i * 12.0),
          0.6,
          Duration(milliseconds: i * 8),
        );
      }
      if (complete) stroke.finishLiveGeometry();
      return stroke;
    }

    Future<ByteData> rasterize({
      Stroke? live,
      List<Stroke> committed = const [],
    }) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 200, 200));
      CanvasPainter(
        strokes: committed,
        laserStrokes: const [],
        currentStroke: live,
        currentSelection: null,
        primaryColor: Colors.blue,
        page: EditorPage(),
        showPageIndicator: false,
        pageIndex: 0,
        totalPages: 1,
        currentScale: 1.0,
        defaultTextStyle: const TextStyle(),
      ).paint(canvas, const Size(200, 200));
      final picture = recorder.endRecording();
      final image = await picture.toImage(200, 200);
      final bytes =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      picture.dispose();
      image.dispose();
      expect(bytes, isNotNull);
      return bytes!;
    }

    Future<int> centerAlpha({
      Stroke? live,
      List<Stroke> committed = const [],
    }) async {
      final data = await rasterize(
        live: live,
        committed: committed,
      );
      // Deep inside the size-10 diagonal (center), far from AA edges.
      final offset = (100 * 200 + 100) * 4;
      return data.getUint8(offset + 3);
    }

    test('live advanced stroke is fully opaque', () async {
      final alpha = await centerAlpha(
        live: diagonalStroke(complete: false),
      );
      expect(alpha, greaterThanOrEqualTo(250));
    });

    test('committed advanced stroke is fully opaque', () async {
      final alpha = await centerAlpha(
        committed: [diagonalStroke(complete: true)],
      );
      expect(alpha, greaterThanOrEqualTo(250));
    });
  });
}
