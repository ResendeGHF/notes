import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
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

    test('stroke mode erases the frontmost overlapping stroke first', () {
      final olderStroke = testPolylineStroke(toolId: ToolId.ballpointPen);
      final newerStroke = testPolylineStroke(toolId: ToolId.ballpointPen);
      final strokes = <Stroke>[olderStroke, newerStroke];
      final eraser = Eraser(mode: EraserMode.stroke, size: 20);

      final result = eraser.apply(
        const Offset(100, 100),
        strokes,
        areaTimeBudgetMs: null,
      );

      expect(result.removed, [newerStroke]);
      expect(result.removed, isNot(contains(olderStroke)));
      expect(result.added, isEmpty);
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

    test('area mode cuts a small frontmost overlapping stack first', () {
      final backStroke = testPolylineStroke(toolId: ToolId.ballpointPen);
      final middleStroke = testPolylineStroke(toolId: ToolId.ballpointPen);
      final frontStroke = testPolylineStroke(toolId: ToolId.ballpointPen);
      final strokes = <Stroke>[backStroke, middleStroke, frontStroke];
      final eraser = Eraser(mode: EraserMode.area, size: 15);
      eraser.clearState();

      final result = eraser.apply(
        const Offset(100, 100),
        strokes,
        areaTimeBudgetMs: null,
      );

      expect(result.removed, [frontStroke, middleStroke, backStroke]);
      expect(result.added, isNotEmpty);
    });

    test(
      'area mode with no budget processes every overlapping stroke in one apply',
      () {
        final strokes = <Stroke>[
          for (var i = 0; i < 6; i++) testPolylineStroke(toolId: ToolId.ballpointPen),
        ];
        final eraser = Eraser(mode: EraserMode.area, size: 15);
        eraser.clearState();

        final result = eraser.apply(
          const Offset(100, 100),
          strokes,
          areaTimeBudgetMs: null,
        );

        expect(result.removed, hasLength(6));
        expect(result.removed, containsAll(strokes));
        expect(result.added, isNotEmpty);
        expect(result.areaWorkRemaining, isFalse);
      },
    );

    test('area mode with budget still processes more than four overlapping strokes', () {
      final strokes = <Stroke>[
        for (var i = 0; i < 8; i++) testPolylineStroke(toolId: ToolId.ballpointPen),
      ];
      final eraser = Eraser(mode: EraserMode.area, size: 15);
      eraser.clearState();

      final result = eraser.apply(
        const Offset(100, 100),
        strokes,
        // Generous budget so soft yield does not fire; must not hard-cap at 4.
        areaTimeBudgetMs: 50,
      );

      expect(result.removed.length, greaterThan(4));
      expect(result.removed, containsAll(strokes));
      expect(result.areaWorkRemaining, isFalse);
    });

    test('area mode cuts stroke in two under the eraser circle', () {
      final stroke = testPolylineStroke(
        toolId: ToolId.ballpointPen,
        x0: 0,
        x1: 200,
        points: 41,
      );
      final strokes = <Stroke>[stroke];
      final eraser = Eraser(mode: EraserMode.area, size: 8);
      eraser.clearState();

      final result = eraser.apply(
        const Offset(100, 100),
        strokes,
        areaTimeBudgetMs: null,
      );

      expect(result.removed, [stroke]);
      expect(result.added, hasLength(2));
      final left = result.added[0].points;
      final right = result.added[1].points;
      expect(left.first.x, lessThan(100));
      expect(left.last.x, lessThan(100));
      expect(right.first.x, greaterThan(100));
      expect(right.last.x, greaterThan(100));
    });

    test('area mode trims an end when eraser covers the tip', () {
      final stroke = testPolylineStroke(
        toolId: ToolId.ballpointPen,
        x0: 0,
        x1: 200,
        points: 41,
      );
      final eraser = Eraser(mode: EraserMode.area, size: 12);
      eraser.clearState();

      final result = eraser.apply(
        const Offset(0, 100),
        [stroke],
        areaTimeBudgetMs: null,
      );

      expect(result.removed, [stroke]);
      expect(result.added, hasLength(1));
      expect(result.added.single.points.first.x, greaterThan(0));
    });

    test('area mode fully erases when the circle covers the stroke', () {
      final stroke = testPolylineStroke(
        toolId: ToolId.ballpointPen,
        x0: 95,
        x1: 105,
        points: 5,
      );
      final eraser = Eraser(mode: EraserMode.area, size: 40);
      eraser.clearState();

      final result = eraser.apply(
        const Offset(100, 100),
        [stroke],
        areaTimeBudgetMs: null,
      );

      expect(result.removed, [stroke]);
      expect(result.added, isEmpty);
    });

    test('area mode re-cuts a fragment in the same drag', () {
      final stroke = testPolylineStroke(
        toolId: ToolId.ballpointPen,
        x0: 0,
        x1: 200,
        points: 41,
      );
      final strokes = <Stroke>[stroke];
      final eraser = Eraser(mode: EraserMode.area, size: 8);
      eraser.clearState();

      final first = eraser.apply(
        const Offset(50, 100),
        strokes,
        areaTimeBudgetMs: null,
      );
      expect(first.removed, [stroke]);
      expect(first.added.length, greaterThanOrEqualTo(1));

      // Simulate page applying the delta.
      strokes
        ..remove(stroke)
        ..addAll(first.added);

      final fragment = first.added.last;
      final second = eraser.apply(
        Offset(fragment.points[fragment.points.length ~/ 2].x, 100),
        strokes,
        areaTimeBudgetMs: null,
      );
      expect(second.removed, contains(fragment));

      final (erased, added, _) = eraser.onDragEnd();
      expect(erased, [stroke]);
      expect(added, isNot(contains(fragment)));
      expect(added, isNotEmpty);
    });

    test('area mode can return areaWorkRemaining when budget is tiny', () {
      final stroke = testPolylineStroke(
        toolId: ToolId.ballpointPen,
        points: 50,
      );
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

    test('spatial index can be scoped to the active layer', () {
      final inactiveStroke = testPolylineStroke(
        toolId: ToolId.ballpointPen,
        y: 100,
      );
      final activeStroke = testPolylineStroke(
        toolId: ToolId.ballpointPen,
        y: 300,
      );
      final page = EditorPage(strokes: [inactiveStroke]);
      page.addLayer();
      page.activeLayerIndex = 1;
      page.strokes.add(activeStroke);

      page.buildSpatialIndex(activeLayerOnly: true);

      final candidates = page.strokeSpatialIndex!.query(
        const Rect.fromLTWH(90, 90, 20, 20),
      );
      expect(candidates, isNot(contains(inactiveStroke)));
      expect(candidates, isNot(contains(activeStroke)));

      final activeCandidates = page.strokeSpatialIndex!.query(
        const Rect.fromLTWH(90, 290, 20, 20),
      );
      expect(activeCandidates, contains(activeStroke));
      expect(activeCandidates, isNot(contains(inactiveStroke)));
    });

    test('draw-order map is reused across misses on a stable stroke list', () {
      final strokes = <Stroke>[
        for (var i = 0; i < 80; i++)
          testPolylineStroke(
            toolId: ToolId.ballpointPen,
            y: 40.0 + i * 12.0,
            x0: 0,
            x1: 200,
          ),
      ];
      final eraser = Eraser(mode: EraserMode.stroke, size: 5);
      const miss = Offset(800, 40);

      final first = eraser.apply(miss, strokes);
      expect(first.removed, isEmpty);
      final rebuilds = eraser.debugOrderMapRebuildCount;
      expect(rebuilds, 1);

      final second = eraser.apply(miss.translate(4, 0), strokes);
      expect(second.removed, isEmpty);
      expect(eraser.debugOrderMapRebuildCount, rebuilds);
    });

    test('eraser spatial candidates ignore non-active layer strokes', () {
      final inactiveStroke = testPolylineStroke(
        toolId: ToolId.ballpointPen,
        y: 100,
      );
      final activeStroke = testPolylineStroke(
        toolId: ToolId.ballpointPen,
        y: 300,
      );
      final page = EditorPage(strokes: [inactiveStroke]);
      page.addLayer();
      page.activeLayerIndex = 1;
      page.strokes.add(activeStroke);
      page.buildSpatialIndex(activeLayerOnly: true);

      final eraser = Eraser(mode: EraserMode.stroke, size: 20);
      final result = eraser.apply(
        const Offset(100, 100),
        page.strokes,
        spatialIndex: page.strokeSpatialIndex,
      );

      expect(result.removed, isEmpty);
      expect(result.added, isEmpty);
      expect(result.areaWorkRemaining, isFalse);
    });
  });
}
