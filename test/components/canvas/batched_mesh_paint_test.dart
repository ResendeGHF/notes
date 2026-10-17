// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_canvas_painter.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/inner_canvas.dart'
    show buildOrderedMeshBatches;
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/stroke_geometry/point_vector.dart';
import 'package:saber/data/tools/_tool.dart';

import '../../helpers/test_stroke_factory.dart';

void main() {
  testWidgets(
    'ordered mesh runs paint in the painter walk',
    (tester) async {
      final stroke = testPolylineStroke(toolId: ToolId.ballpointPen);
      expect(stroke.canBatchSolidMesh, isTrue);

      final page = EditorPage();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 220, 220));

      // Ordered runs are built from the same stroke list the painter walks:
      // the first present member draws the whole run in place (temporal
      // order preserved across colors).
      final ordered = buildOrderedMeshBatches([stroke], 1.0);
      expect(ordered, isNotNull);
      expect(ordered!.runs, hasLength(1));
      CanvasPainter(
        invert: false,
        strokes: [stroke],
        orderedBatches: ordered,
        laserStrokes: const [],
        currentStroke: null,
        currentSelection: null,
        primaryColor: Colors.blue,
        page: page,
        showPageIndicator: false,
        pageIndex: 0,
        totalPages: 1,
        currentScale: 1,
        defaultTextStyle: const TextStyle(),
        doneSelecting: true,
      ).paint(canvas, const Size(220, 220));

      final picture = recorder.endRecording();
      late ui.Image image;
      late ByteData? bytes;
      await tester.runAsync(() async {
        image = await picture.toImage(220, 220);
        bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      });
      expect(bytes, isNotNull);

      var opaquePixels = 0;
      final data = bytes!;
      for (var i = 3; i < data.lengthInBytes; i += 4) {
        if (data.getUint8(i) > 0) opaquePixels++;
      }
      expect(opaquePixels, greaterThan(0));
    },
  );

  testWidgets(
    'newer color wins at crossings regardless of batching',
    (tester) async {
      // Red horizontal, then blue vertical crossing it: temporal order means
      // blue on top at the crossing even though batching merges same colors.
      Stroke hBar(Color color) {
        final s = testPolylineStroke(toolId: ToolId.ballpointPen);
        s.color = color;
        s.points.clear();
        for (var i = 0; i <= 20; i++) {
          s.points.add(PointVector(10.0 + i * 10.0, 110.0, 0.5));
        }
        s.markPolygonNeedsUpdating();
        return s;
      }

      Stroke vBar(Color color) {
        final s = testPolylineStroke(toolId: ToolId.ballpointPen);
        s.color = color;
        s.points.clear();
        for (var i = 0; i <= 20; i++) {
          s.points.add(PointVector(110.0, 10.0 + i * 10.0, 0.5));
        }
        s.markPolygonNeedsUpdating();
        return s;
      }

      Future<ByteData> paintPixels(List<Stroke> strokes) async {
        final page = EditorPage();
        final ordered = buildOrderedMeshBatches(strokes, 1.0);
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 220, 220));
        CanvasPainter(
          invert: false,
          strokes: strokes,
          orderedBatches: ordered,
          laserStrokes: const [],
          currentStroke: null,
          currentSelection: null,
          primaryColor: Colors.blue,
          page: page,
          showPageIndicator: false,
          pageIndex: 0,
          totalPages: 1,
          currentScale: 1,
          defaultTextStyle: const TextStyle(),
          doneSelecting: true,
        ).paint(canvas, const Size(220, 220));
        final picture = recorder.endRecording();
        late ui.Image image;
        late ByteData? bytes;
        await tester.runAsync(() async {
          image = await picture.toImage(220, 220);
          bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        });
        page.dispose();
        return bytes!;
      }

      Color pixelAt(ByteData bytes, int x, int y) {
        final o = (y * 220 + x) * 4;
        return Color.fromARGB(
          255,
          bytes.getUint8(o),
          bytes.getUint8(o + 1),
          bytes.getUint8(o + 2),
        );
      }

      // Red then blue: blue on top at (110,110).
      final redFirst = [hBar(const Color(0xFFFF0000)), vBar(const Color(0xFF0000FF))];
      final blueOnTop = pixelAt(await paintPixels(redFirst), 110, 110);
      expect(blueOnTop.b, greaterThan(0.8));
      expect(blueOnTop.r, lessThan(0.3));

      // Blue then red: red on top at (110,110).
      final blueFirst = [vBar(const Color(0xFF0000FF)), hBar(const Color(0xFFFF0000))];
      final redOnTop = pixelAt(await paintPixels(blueFirst), 110, 110);
      expect(redOnTop.r, greaterThan(0.8));
      expect(redOnTop.b, lessThan(0.3));
    },
  );
}
