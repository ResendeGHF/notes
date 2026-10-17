import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/select.dart';
import '../../helpers/test_stroke_factory.dart';

void main() {
  group('Select tool (lasso)', () {
    tearDown(() {
      Select.currentSelect.unselect();
    });

    test('onDragStart/onDragUpdate/onDragEnd closes path and marks done', () {
      final s = Select.currentSelect;
      s.onDragStart(Offset.zero, 0);
      s.onDragUpdate(const Offset(40, 0));
      s.onDragUpdate(const Offset(40, 40));
      s.onDragEnd(<Stroke>[], <EditorImage>[]);

      expect(s.doneSelecting, isTrue);
      expect(s.selectResult.pageIndex, 0);
    });

    test('getDominantStrokeColor weights by stroke length', () {
      final s = Select.currentSelect;
      final a = testPolylineStroke(
        toolId: ToolId.ballpointPen,
        y: 10,
        x0: 0,
        x1: 50,
        points: 10,
      );
      a.color = const Color(0xFFFF0000);
      final b = testPolylineStroke(
        toolId: ToolId.ballpointPen,
        y: 20,
        x0: 0,
        x1: 200,
        points: 40,
      );
      b.color = const Color(0xFF0000FF);

      s.selectResult = s.selectResult.copyWith(strokes: [a, b]);
      s.doneSelecting = true;

      expect(s.getDominantStrokeColor(), const Color(0xFF0000FF));
    });

    test('polygonPercentInside is 0 for an empty outline', () {
      expect(Select.polygonPercentInside(Path(), const []), 0);
    });

    test('small lasso keeps the outline threshold', () {
      final inside = testPolylineStroke(
        toolId: ToolId.ballpointPen,
        y: 40,
        x0: 20,
        x1: 80,
      );
      final outside = testPolylineStroke(
        toolId: ToolId.ballpointPen,
        y: 40,
        x0: 200,
        x1: 280,
      );
      final partial = testPolylineStroke(
        toolId: ToolId.ballpointPen,
        y: 40,
        x0: 0,
        x1: 200,
        points: 21,
      );

      final s = Select.currentSelect;
      s.onDragStart(Offset.zero, 0);
      s.onDragUpdate(const Offset(100, 0));
      s.onDragUpdate(const Offset(100, 80));
      s.onDragUpdate(const Offset(0, 80));
      final closed = Path.from(s.selectResult.path)..close();
      final partialSelected =
          Select.polygonPercentInside(closed, partial.lowQualityPolygon) >
          Select.minPercentInside;

      s.onDragEnd([inside, outside, partial], const <EditorImage>[]);

      expect(s.selectResult.strokes.contains(inside), isTrue);
      expect(s.selectResult.strokes.contains(outside), isFalse);
      expect(s.selectResult.strokes.contains(partial), partialSelected);
      expect(
        s.selectResult.strokes.length,
        lessThan(Select.rasterStrokeThreshold),
      );
    });

    test('large lasso selects by coverage mask without outlining', () {
      const insideCount = 2500;
      final inside = <Stroke>[
        for (var i = 0; i < insideCount; i++)
          testPolylineStroke(
            toolId: ToolId.ballpointPen,
            y: 20 + (i % 200) * 4,
            x0: 20,
            x1: 80,
            points: 12,
          ),
      ];
      final outside = <Stroke>[
        for (var i = 0; i < 300; i++)
          testPolylineStroke(
            toolId: ToolId.ballpointPen,
            y: 20 + i * 4,
            x0: 420,
            x1: 480,
            points: 12,
          ),
      ];
      final mostlyIn = testPolylineStroke(
        toolId: ToolId.ballpointPen,
        y: 30,
        x0: 10,
        x1: 100,
        points: 21,
      );
      final mostlyOut = testPolylineStroke(
        toolId: ToolId.ballpointPen,
        y: 50,
        x0: 0,
        x1: 400,
        points: 21,
      );

      final s = Select.currentSelect;
      s.onDragStart(Offset.zero, 0);
      s.onDragUpdate(const Offset(150, 0));
      s.onDragUpdate(const Offset(150, 900));
      s.onDragUpdate(const Offset(0, 900));

      final elapsed = Stopwatch()..start();
      s.onDragEnd([
        ...inside,
        ...outside,
        mostlyIn,
        mostlyOut,
      ], const <EditorImage>[]);
      final bounds = s.selectResult.getBounds();
      elapsed.stop();

      expect(s.selectResult.strokes.length, insideCount + 1);
      expect(s.selectResult.strokes.contains(mostlyIn), isTrue);
      expect(s.selectResult.strokes.contains(mostlyOut), isFalse);
      expect(outside.any(s.selectResult.strokes.contains), isFalse);
      expect(bounds.width, greaterThan(0));
      expect(
        s.selectResult.strokes.every(
          (stroke) => !stroke.hasCachedHighQualityPolygon,
        ),
        isTrue,
      );
      expect(
        elapsed.elapsedMilliseconds,
        lessThan(1500),
        reason:
            'pen-up hit testing stalled (${elapsed.elapsedMilliseconds} ms)',
      );
    });

    test('large selection rotation pivot stays on the bounds center', () {
      final strokes = <Stroke>[
        for (var i = 0; i < Select.rasterStrokeThreshold; i++)
          testPolylineStroke(
            toolId: ToolId.ballpointPen,
            y: 15.0 + i * 2,
            x0: 10,
            x1: 90,
            points: 8,
          ),
      ];
      final selection = SelectResult(
        pageIndex: 0,
        pageIndexStart: 0,
        strokes: strokes,
        images: const [],
        path: Path(),
      );
      final preview = SelectionTransformPreview.fromSelection(selection);
      const step = 25 * math.pi / 180;
      for (final stroke in strokes) {
        stroke.rotate(step, preview.pivot);
      }
      selection.rotationDeg = 25;
      selection.displayBounds = null;
      selection.recomputeBoundsAround(preview.pivot);
      expect(
        (selection.displayBounds!.center - preview.pivot).distance,
        lessThan(1e-4),
      );

      for (final stroke in strokes) {
        stroke.rotate(-step, preview.pivot);
      }
      selection.rotationDeg = 0;
      selection.displayBounds = null;
      selection.recomputeBoundsAround(preview.pivot);
      expect(
        (selection.displayBounds!.center - preview.pivot).distance,
        lessThan(1e-4),
      );
      expect(
        strokes.every((stroke) => !stroke.hasCachedHighQualityPolygon),
        isTrue,
      );
    });
  });
}
