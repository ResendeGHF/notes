// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_canvas_painter.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/_tool.dart';

import '../../helpers/test_stroke_factory.dart';

void main() {
  testWidgets(
    'batched meshes still paint when every stroke was stripped from the list',
    (tester) async {
      final stroke = testPolylineStroke(toolId: ToolId.ballpointPen);
      expect(stroke.canBatchSolidMesh, isTrue);

      final mesh = ui.Vertices.raw(
        ui.VertexMode.triangles,
        stroke.getRawPositions(),
        indices: stroke.getRawIndices(),
      );
      final page = EditorPage();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 220, 220));

      // Tile recording used to pass only non-mesh leftovers. When every
      // glyph in the tile was a solid mesh, that list was empty and
      // `_drawBatchedMeshes` returned before drawVertices.
      CanvasPainter(
        invert: false,
        strokes: const [],
        batchedStrokes: {
          stroke.color.toARGB32(): [mesh],
        },
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
}
