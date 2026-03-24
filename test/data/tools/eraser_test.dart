import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/eraser.dart';
import '../../helpers/test_stroke_factory.dart';

void main() {
  group('Eraser modes', () {
    test('stroke mode removes whole stroke when circle hits', () {
      final stroke = testPolylineStroke(toolId: ToolId.ballpointPen);
      final strokes = <Stroke>[stroke];
      final eraser = Eraser(mode: EraserMode.stroke, size: 20);

      final result = eraser.apply(
        const Offset(100, 100),
        strokes,
        areaTimeBudgetMs: null,
      );
      expect(result.removed, contains(stroke));
      expect(result.added, isEmpty);
      expect(result.areaWorkRemaining, isFalse);
    });

    test('area mode splits stroke under cursor', () {
      final stroke = testPolylineStroke(toolId: ToolId.ballpointPen);
      final strokes = <Stroke>[stroke];
      final eraser = Eraser(mode: EraserMode.area, size: 15);
      eraser.clearState();

      final result = eraser.apply(
        const Offset(100, 100),
        strokes,
        areaTimeBudgetMs: null,
      );
      expect(result.removed, contains(stroke));
      expect(result.added.length, greaterThanOrEqualTo(1));
      expect(result.areaWorkRemaining, isFalse);
    });

    test('area mode can return areaWorkRemaining when budget is tiny', () {
      final stroke = testPolylineStroke(toolId: ToolId.ballpointPen, points: 50);
      final strokes = <Stroke>[stroke];
      final eraser = Eraser(mode: EraserMode.area, size: 12);
      eraser.clearState();

      final result = eraser.apply(
        const Offset(50, 100),
        strokes,
        areaTimeBudgetMs: 0,
      );
      expect(result.areaWorkRemaining, isTrue);
    });

    test('shouldApplyAt throttles in area mode', () {
      final eraser = Eraser(mode: EraserMode.area, size: 10);
      expect(eraser.shouldApplyAt(Offset.zero), isTrue);
      expect(eraser.shouldApplyAt(const Offset(0.1, 0.1)), isFalse);
      expect(eraser.shouldApplyAt(const Offset(50, 0)), isTrue);
    });
  });
}
