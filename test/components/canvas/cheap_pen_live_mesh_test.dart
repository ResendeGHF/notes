// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/eraser.dart';

import '../../helpers/test_stroke_factory.dart';

Stroke _liveCheapPen({
  required ToolId toolId,
  required int samples,
}) {
  final stroke = Stroke(
    color: Colors.black,
    pressureEnabled: false,
    options: StrokeOptions(
      size: 8,
      thinning: 0,
      smoothing: 0.3,
      streamline: 0.15,
      simulatePressure: false,
      isComplete: false,
      start: StrokeEndOptions.start(cap: true, taperEnabled: false),
      end: StrokeEndOptions.end(cap: true, taperEnabled: false),
    ),
    pageIndex: 0,
    page: HasSize(EditorPage.defaultSize),
    toolId: toolId,
  );
  for (var i = 0; i < samples; i++) {
    stroke.addPoint(Offset(20.0 + i * 2.5, 90.0 + (i % 5) * 0.2));
    if (stroke.length >= 2) stroke.vertices;
  }
  return stroke;
}

void main() {
  for (final toolId in [
    ToolId.ballpointPen,
    ToolId.fountainPen,
    ToolId.calligraphyPen,
  ]) {
    test('$toolId live samples keep a spine mesh without Advanced outline', () {
      final stroke = _liveCheapPen(toolId: toolId, samples: 180);
      expect(stroke.length, 180);
      expect(stroke.usesSolidOutlineMesh, isFalse);
      expect(stroke.vertices, isNotNull);
      expect(stroke.liveIncrementalMeshes, isNull);
      expect(stroke.debugLiveLockedPointCount, greaterThan(0));

      stroke.finishLiveGeometry();
      expect(stroke.options.isComplete, isTrue);
      expect(stroke.vertices, isNotNull);
      expect(stroke.canBatchSolidMesh, isTrue);
      expect(stroke.debugLiveLockedPointCount, 0);
    });
  }

  test('area eraser still splits a stroke under the cursor', () {
    final stroke = testPolylineStroke(toolId: ToolId.ballpointPen);
    final strokes = <Stroke>[stroke];
    final eraser = Eraser(mode: EraserMode.area, size: 15);
    eraser.clearState();
    addTearDown(eraser.clearState);

    final result = eraser.apply(
      const Offset(100, 100),
      strokes,
      areaTimeBudgetMs: null,
    );
    expect(result.removed, contains(stroke));
    expect(result.added, isNotEmpty);
  });
}
