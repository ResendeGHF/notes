// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

// Carve-eraser editions must persist transforms: select-tool resize (scale),
// translation and rotation, duplicates, and every copy/reconstruction path
// used by undo/redo and the selection commit. A carve mask is a page-space
// mark on the ink, so it must scale/rotate/translate with the stroke it
// belongs to instead of being dropped or left behind.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_shape_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/shape_geometry.dart';
import 'package:saber/data/tools/shape_tool.dart';

import '../../helpers/test_stroke_factory.dart';

HasSize _page() => testPageSize();

ShapeStroke _rectShape() {
  final verts = <Offset>[
    const Offset(60, 40),
    const Offset(140, 40),
    const Offset(140, 120),
    const Offset(60, 120),
  ];
  final config = ShapeGeometry.withControlPoints(
    ShapeConfig(
      kind: ShapeKind.rectangle,
      bounds: ShapeGeometry.boundsOf(verts),
      data: const {'equilateral': false},
    ),
    verts,
  );
  return ShapeStroke(
    color: Colors.black,
    pressureEnabled: false,
    options: ShapeStroke.defaultOptions.copyWith(isComplete: true),
    pageIndex: 0,
    page: _page(),
    toolId: ToolId.shapeTool,
    config: config,
  );
}

void main() {
  group('carve mask survives select-tool transforms', () {
    test('freehand: scale, translate and rotate move the bite', () {
      final stroke = testPolylineStroke(toolId: ToolId.ballpointPen);
      stroke.addCarveSweep(const Offset(100, 95), const Offset(100, 105), 8);
      expect(stroke.hasCarve, isTrue);
      expect(stroke.carveMask!.distanceSq(100, 100), 0);
      expect(stroke.carveMask!.maxRadius, 8);

      // Resize (select-tool pivot scale): bite scales with the stroke.
      stroke.scale(2, const Offset(0, 100));
      expect(stroke.hasCarve, isTrue, reason: 'scale dropped the mask');
      expect(stroke.carveMask!.distanceSq(200, 100), 0);
      expect(stroke.carveMask!.maxRadius, 16);

      // Translation: bite moves with the stroke.
      stroke.shift(const Offset(10, 0));
      expect(stroke.carveMask!.distanceSq(210, 100), 0);

      // Rotation: bite orbits the pivot with the stroke.
      stroke.rotate(math.pi / 2, const Offset(0, 100));
      expect(stroke.carveMask!.distanceSq(0, 310), 0);
    });

    test('shape: scaled() copies the mask instead of resetting the stroke', () {
      final shape = _rectShape();
      shape.addCarveSweep(const Offset(100, 80), const Offset(100, 80), 8);
      expect(shape.hasCarve, isTrue);

      final scaled = shape.scaled(2, const Offset(100, 80));
      expect(scaled.hasCarve, isTrue, reason: 'scaled() dropped the mask');
      expect(scaled.carveMask!.distanceSq(100, 80), 0);
      expect(scaled.carveMask!.maxRadius, 16);
      expect(
        identical(scaled.carveMask, shape.carveMask),
        isFalse,
        reason: 'mask must be cloned, not shared',
      );
    });

    test('shape: rotate and scale move the bite', () {
      final shape = _rectShape();
      shape.addCarveSweep(const Offset(100, 80), const Offset(100, 80), 8);

      shape.shift(const Offset(30, 0));
      expect(shape.carveMask!.distanceSq(130, 80), 0);

      shape.rotate(math.pi / 2, Offset.zero);
      // (130,80) rotated 90° about origin → (-80,130).
      expect(shape.carveMask!.distanceSq(-80, 130), 0);

      shape.scale(2, Offset.zero);
      // Bite doubles with the shape: (-160,260), radius 16.
      expect(shape.carveMask!.distanceSq(-160, 260), 0);
      expect(shape.carveMask!.maxRadius, 16);
    });

    test('circle and rectangle copies keep the mask', () {
      final circle = CircleStroke(
        color: Colors.black,
        pressureEnabled: false,
        options: StrokeOptions(
          size: 4,
          simulatePressure: false,
          isComplete: true,
        ),
        pageIndex: 0,
        page: _page(),
        toolId: ToolId.shapeTool,
        center: const Offset(100, 100),
        radius: 60,
      );
      circle.addCarveSweep(const Offset(100, 40), const Offset(100, 40), 8);
      final circleCopy = circle.copy();
      expect(circleCopy.hasCarve, isTrue, reason: 'circle copy dropped mask');
      expect(circleCopy.carveMask!.distanceSq(100, 40), 0);
      circle.scale(2, const Offset(100, 100));
      expect(circle.hasCarve, isTrue);
      expect(circle.carveMask!.distanceSq(100, -20), 0);
      expect(circle.carveMask!.maxRadius, 16);

      final rect = RectangleStroke(
        color: Colors.black,
        pressureEnabled: false,
        options: StrokeOptions(
          size: 4,
          simulatePressure: false,
          isComplete: true,
        ),
        pageIndex: 0,
        page: _page(),
        toolId: ToolId.shapeTool,
        rect: const Rect.fromLTWH(40, 40, 120, 80),
      );
      rect.addCarveSweep(const Offset(100, 80), const Offset(100, 80), 8);
      final rectCopy = rect.copy();
      expect(rectCopy.hasCarve, isTrue, reason: 'rectangle copy dropped mask');
      expect(rectCopy.carveMask!.distanceSq(100, 80), 0);
      rect.scale(2, Offset.zero);
      expect(rect.hasCarve, isTrue);
      expect(rect.carveMask!.distanceSq(200, 160), 0);
      expect(rect.carveMask!.maxRadius, 16);
    });

    test('eraser fragments keep the parent mask', () {
      final stroke = testPolylineStroke(toolId: ToolId.ballpointPen);
      stroke.addCarveSweep(const Offset(60, 100), const Offset(60, 100), 8);
      expect(stroke.hasCarve, isTrue);

      final fragment = stroke.cloneForEraserFragment();
      expect(
        fragment.hasCarve,
        isTrue,
        reason: 'area fragments must not resurrect carved-away ink',
      );
      expect(fragment.carveMask!.distanceSq(60, 100), 0);
      expect(identical(fragment.carveMask, stroke.carveMask), isFalse);
    });
  });
}
