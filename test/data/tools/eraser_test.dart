import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/eraser.dart';

import '../../helpers/test_stroke_factory.dart';

/// Mirrors editor.dart `_applyEraserResultToPage`: each removed stroke is
/// replaced at its own index by its replacement group (empty = deleted).
void applyEraserDelta(List<Stroke> strokes, EraserResult result) {
  final indexed = <(int, int)>[];
  for (var i = 0; i < result.removed.length; i++) {
    final idx = strokes.indexOf(result.removed[i]);
    if (idx >= 0) indexed.add((idx, i));
  }
  indexed.sort((a, b) => b.$1.compareTo(a.$1));
  for (final (idx, i) in indexed) {
    strokes.removeAt(idx);
    final group = i < result.replacementGroups.length
        ? result.replacementGroups[i]
        : const <Stroke>[];
    if (group.isNotEmpty) {
      strokes.insertAll(idx, group);
    }
  }
}

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
      // Every original sample outside the bite is still in a fragment.
      const hitRadius = 8 + 8 / 2;
      for (final p in stroke.points) {
        if ((p - const Offset(100, 100)).distance <= hitRadius) continue;
        final kept = result.added.any(
          (frag) => frag.points.any((q) => q.x == p.x && q.y == p.y),
        );
        expect(kept, isTrue, reason: 'dropped untouched sample $p');
      }
    });

    test('area mode splits a sparse stroke at the bite instead of deleting it', () {
      final stroke = testPolylineStroke(
        toolId: ToolId.ballpointPen,
        x0: 0,
        x1: 200,
        points: 3,
        width: 8,
      );
      final eraser = Eraser(mode: EraserMode.area, size: 8);
      eraser.clearState();

      final result = eraser.apply(
        const Offset(100, 100),
        [stroke],
        areaTimeBudgetMs: null,
      );

      expect(result.removed, [stroke]);
      expect(result.added, hasLength(2));
      expect(result.added.first.points.first.x, 0);
      expect(result.added.last.points.last.x, 200);
      expect(result.added.first.points.last.x, lessThan(100));
      expect(result.added.last.points.first.x, greaterThan(100));
    });

    test(
      'area mode keeps the end fragment when it collapses to a single point',
      () {
        // Reproduces the reported bug: a stroke sampled densely near the
        // start (a sample sits inside the bite) but with a single sparse
        // sample at the end. The user cuts the middle; the end-side run
        // collapses to that one sample and must NOT be dropped.
        final stroke = testPolylineStroke(
          toolId: ToolId.ballpointPen,
          x0: 0,
          x1: 96,
          points: 25,
          width: 8,
        );
        stroke.points.add(const PointVector(200, 100, 0.5));
        stroke.markPolygonNeedsUpdating();

        final eraser = Eraser(mode: EraserMode.area, size: 8);
        eraser.clearState();
        final result = eraser.apply(
          const Offset(100, 100),
          [stroke],
          areaTimeBudgetMs: null,
        );

        expect(result.removed, [stroke]);
        expect(
          result.added,
          hasLength(2),
          reason: 'the single-point end fragment must survive the cut',
        );
        expect(result.added.first.points.first.x, 0);
        expect(result.added.first.points.last.x, lessThan(100));
        expect(result.added.last.points.last.x, 200);
        expect(result.added.last.points.first.x, greaterThan(88));
      },
    );

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

    test('area mode re-cut replaces every live fragment exactly once', () {
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
        const Offset(100, 90),
        strokes,
        areaTimeBudgetMs: null,
      );
      expect(first.added, hasLength(2));
      strokes
        ..remove(stroke)
        ..addAll(first.added);

      // Continue the sweep onto the stroke: both fragment tips sit well
      // inside the new capsule, so the candidate list holds both live
      // fragments of the same original. Cutting the first one replaces the
      // pair; the second candidate is stale and must not be treated as a
      // brand-new stroke (that dropped the end-side replacement from the
      // page and left only the start half behind).
      final second = eraser.apply(
        const Offset(100, 100),
        strokes,
        areaTimeBudgetMs: null,
      );

      // Each live fragment is replaced exactly once.
      expect(second.removed, hasLength(2));
      expect(second.removed.toSet(), strokes.toSet());
      expect(second.replacementGroups, hasLength(second.removed.length));
      final replaced = <Stroke>{};
      for (final group in second.replacementGroups) {
        expect(replaced.intersection(group.toSet()), isEmpty);
        replaced.addAll(group);
      }
      expect(replaced, second.added.toSet());

      // Simulate the page applying the delta.
      applyEraserDelta(strokes, second);
      expect(
        strokes.any((s) => s.points.first.x == 0),
        isTrue,
        reason: 'start-side fragment disappeared after the re-cut',
      );
      expect(
        strokes.any((s) => s.points.last.x == 200),
        isTrue,
        reason: 'end-side fragment disappeared after the re-cut',
      );
    });

    test('area mode keeps both sides when the sweep ends on the bite', () {
      final stroke = testPolylineStroke(
        toolId: ToolId.ballpointPen,
        x0: 0,
        x1: 200,
        points: 41,
      );
      final strokes = <Stroke>[stroke];
      final eraser = Eraser(mode: EraserMode.area, size: 8);
      eraser.clearState();

      // Dragging across the stroke: the first contact bites, then the sweep
      // walks over the cut and out the other side.
      for (final p in const [
        Offset(96, 92),
        Offset(98, 96),
        Offset(100, 100),
        Offset(100, 106),
        Offset(98, 112),
      ]) {
        if (!eraser.shouldApplyAt(p)) continue;
        final result = eraser.apply(p, strokes, areaTimeBudgetMs: null);
        applyEraserDelta(strokes, result);
      }

      expect(
        strokes.any((s) => s.points.first.x == 0),
        isTrue,
        reason: 'start-side fragment disappeared',
      );
      expect(
        strokes.any((s) => s.points.last.x == 200),
        isTrue,
        reason: 'end-side fragment disappeared',
      );
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

  group('Carve mode', () {
    test('carve punches pixels without splitting the stroke or adding caps', () {
      final stroke = testPolylineStroke(
        toolId: ToolId.ballpointPen,
        x0: 0,
        x1: 200,
        points: 41,
      );
      final eraser = Eraser(mode: EraserMode.carve, size: 8);
      eraser.clearState();

      final result = eraser.apply(
        const Offset(100, 100),
        [stroke],
        areaTimeBudgetMs: null,
      );

      // One replacement stroke, same samples: a diagonal bite is a mask,
      // not two triangles with new caps.
      expect(result.removed, [stroke]);
      expect(result.added, hasLength(1));
      final carved = result.added.single;
      expect(carved.points.length, stroke.points.length);
      expect(carved.points.first.x, stroke.points.first.x);
      expect(carved.points.last.x, stroke.points.last.x);
      expect(carved.hasCarve, isTrue);
      expect(carved.options.start.cap, isTrue);
      expect(carved.options.end.cap, isTrue);
      expect(carved.carveMask!.distanceSq(100, 100), 0);
      // Ink far from the bite is outside the eraser radius.
      expect(carved.carveMask!.distanceSq(0, 100), greaterThan(8 * 8));
    });

    test('carve keeps pressure samples instead of retargeting widths', () {
      final stroke = testPolylineStroke(
        toolId: ToolId.fountainPen,
        x0: 0,
        x1: 200,
        points: 41,
      );
      final eraser = Eraser(mode: EraserMode.carve, size: 8);
      eraser.clearState();

      final result = eraser.apply(
        const Offset(100, 100),
        [stroke],
        areaTimeBudgetMs: null,
      );

      expect(result.added, hasLength(1));
      final carved = result.added.single;
      expect(carved.points.length, stroke.points.length);
      for (var i = 0; i < carved.points.length; i++) {
        expect(carved.points[i].pressure, stroke.points[i].pressure);
      }
    });

    test('carve fully erases a covered stroke', () {
      final stroke = testPolylineStroke(
        toolId: ToolId.ballpointPen,
        x0: 95,
        x1: 105,
        points: 5,
      );
      final eraser = Eraser(mode: EraserMode.carve, size: 40);
      eraser.clearState();

      final result = eraser.apply(
        const Offset(100, 100),
        [stroke],
        areaTimeBudgetMs: null,
      );

      expect(result.removed, [stroke]);
      expect(result.added, isEmpty);
    });

    test('a second carve extends the same stroke mask', () {
      final stroke = testPolylineStroke(
        toolId: ToolId.highlighter,
        x0: 0,
        x1: 200,
        points: 41,
        width: 40,
      );
      final strokes = <Stroke>[stroke];
      final eraser = Eraser(mode: EraserMode.carve, size: 8);
      eraser.clearState();

      final first = eraser.apply(const Offset(40, 100), strokes);
      expect(first.added, hasLength(1));
      strokes
        ..remove(stroke)
        ..addAll(first.added);
      final carved = first.added.single;
      final runsBefore = carved.carveMask!.runCount;

      final second = eraser.apply(const Offset(160, 100), strokes);
      expect(second.removed, isEmpty);
      expect(second.contentMutated, isTrue);
      expect(identical(strokes.single, carved), isTrue);
      expect(carved.carveMask!.runCount, greaterThanOrEqualTo(runsBefore));
      expect(carved.points.length, 41);
    });

    test('carve does not draw a line between separate gestures', () {
      final stroke = testPolylineStroke(
        toolId: ToolId.highlighter,
        x0: 0,
        x1: 200,
        points: 41,
        width: 40,
      );
      final strokes = <Stroke>[stroke];
      final eraser = Eraser(mode: EraserMode.carve, size: 8);
      eraser.clearState();

      final first = eraser.apply(const Offset(40, 100), strokes);
      strokes
        ..remove(stroke)
        ..addAll(first.added);
      eraser.onDragEnd();

      final second = eraser.apply(const Offset(160, 100), strokes);
      final carved = second.added.single;
      expect(carved.carveMask!.runCount, 2);
      expect(carved.points.length, stroke.points.length);
      // The chord from the previous contact to this one is not a deletion.
      expect(carved.carveMask!.distanceSq(100, 100), greaterThan(30 * 30));
    });

    test('carve misses cleanly with no cloning', () {
      final stroke = testPolylineStroke(
        toolId: ToolId.ballpointPen,
        x0: 0,
        x1: 20,
        points: 5,
      );
      final eraser = Eraser(mode: EraserMode.carve, size: 8);
      eraser.clearState();

      final result = eraser.apply(
        const Offset(300, 300),
        [stroke],
        areaTimeBudgetMs: null,
      );

      expect(result.removed, isEmpty);
      expect(result.added, isEmpty);
      expect(result.areaWorkRemaining, isFalse);
    });
  });

  group('Sweep and budgets', () {
    test('fast flick leaves no tunnels between gated samples', () {
      final stroke = testPolylineStroke(
        toolId: ToolId.ballpointPen,
        x0: 0,
        x1: 400,
        points: 81,
      );
      final strokes = <Stroke>[stroke];
      final eraser = Eraser(mode: EraserMode.area, size: 10);
      eraser.clearState();

      // shouldApplyAt gates at step≈4.5px; jump 120px between applies.
      expect(eraser.shouldApplyAt(const Offset(60, 100)), isTrue);
      var result = eraser.apply(
        const Offset(60, 100),
        strokes,
        areaTimeBudgetMs: null,
      );
      expect(result.removed, [stroke]);
      strokes
        ..remove(stroke)
        ..addAll(result.added);

      expect(eraser.shouldApplyAt(const Offset(180, 100)), isTrue);
      result = eraser.apply(
        const Offset(180, 100),
        strokes,
        areaTimeBudgetMs: null,
      );
      // Apply the second delta like the editor does.
      for (final s in result.removed) {
        strokes.remove(s);
      }
      strokes.addAll(result.added);
      // The whole swept segment is gone: every surviving fragment sits
      // outside the swept capsule (no mid-segment leftovers).
      for (final frag in strokes) {
        for (final p in frag.points) {
          final inFirst = (p - const Offset(60, 100)).distance <= 14.0;
          final inSecond = (p - const Offset(180, 100)).distance <= 14.0;
          final between =
              p.x > 60 - 14 && p.x < 180 + 14 && (p.y - 100).abs() <= 14.0;
          expect(inFirst || inSecond || !between, isTrue,
              reason: 'tunnel point $p');
        }
      }
    });

    test('fragment budgets bound pathological subdivision', () {
      final strokes = <Stroke>[
        for (var i = 0; i < 4; i++)
          testPolylineStroke(toolId: ToolId.ballpointPen),
      ];
      final eraser = Eraser(mode: EraserMode.area, size: 15);
      eraser.clearState();

      var totalAdded = 0;
      for (var k = 0; k < 30; k++) {
        final result = eraser.apply(
          Offset(40.0 + k * 4, 100),
          strokes,
          areaTimeBudgetMs: null,
        );
        totalAdded += result.added.length;
        for (final s in result.removed) {
          strokes.remove(s);
        }
        strokes.addAll(result.added);
        if (result.removed.isEmpty && result.added.isEmpty) break;
      }
      // Re-cuts replace fragments instead of nesting them. Every real
      // surviving piece is kept (no quality cap), and the live set stays
      // linear in the strokes rather than exploding per sample.
      expect(totalAdded, lessThan(400));
      expect(strokes.length, lessThan(60));
    });
  });

  group('Draw-order slots (eraser children)', () {
    // Five same-position strokes of different colors, oldest first. The
    // eraser must never make a child jump relative to another stroke: every
    // fragment/carved copy replaces its parent in the parent's own slot, so
    // the stacking order (and the real-time paint order) cannot flicker.
    const colors = [
      Colors.red,
      Colors.green,
      Colors.blue,
      Colors.orange,
      Colors.purple,
    ];

    List<Stroke> stackedStrokes() => <Stroke>[
      for (var i = 0; i < colors.length; i++)
        testPolylineStroke(toolId: ToolId.ballpointPen)..color = colors[i],
    ];

    void expectColorOrder(List<Stroke> strokes, int repeats) {
      expect(strokes, hasLength(colors.length * repeats));
      for (var i = 0; i < colors.length; i++) {
        for (var k = 0; k < repeats; k++) {
          expect(
            strokes[i * repeats + k].color,
            colors[i],
            reason: 'parent $i keeps its slot (repeat $k)',
          );
        }
      }
    }

    test('area fragments replace their parent in its own slot', () {
      final strokes = stackedStrokes();
      final eraser = Eraser(mode: EraserMode.area, size: 15);
      eraser.clearState();

      final result = eraser.apply(
        const Offset(100, 100),
        strokes,
        areaTimeBudgetMs: null,
      );
      expect(result.removed, hasLength(colors.length));
      applyEraserDelta(strokes, result);

      expectColorOrder(strokes, 2);
    });

    test('area drag re-cut never shuffles parent slots', () {
      final strokes = stackedStrokes();
      final eraser = Eraser(mode: EraserMode.area, size: 8);
      eraser.clearState();

      final first = eraser.apply(
        const Offset(100, 90),
        strokes,
        areaTimeBudgetMs: null,
      );
      applyEraserDelta(strokes, first);
      expectColorOrder(strokes, 2);

      // Continue the sweep onto the stack: all live fragments are re-cut.
      final second = eraser.apply(
        const Offset(100, 100),
        strokes,
        areaTimeBudgetMs: null,
      );
      applyEraserDelta(strokes, second);
      expectColorOrder(strokes, 2);
    });

    test('carve replaces each stroke in its own slot', () {
      final strokes = stackedStrokes();
      final eraser = Eraser(mode: EraserMode.carve, size: 15);
      eraser.clearState();

      final result = eraser.apply(
        const Offset(100, 100),
        strokes,
        areaTimeBudgetMs: null,
      );
      expect(result.removed, hasLength(colors.length));
      applyEraserDelta(strokes, result);

      // Same count, same order: the carve is an edit, not a restack.
      expectColorOrder(strokes, 1);
      for (final stroke in strokes) {
        expect(stroke.hasCarve, isTrue);
      }
    });

    test('area fragment keeps the parent carve mask', () {
      final stroke = testPolylineStroke(
        toolId: ToolId.ballpointPen,
        x0: 0,
        x1: 200,
        points: 41,
      );
      final strokes = <Stroke>[stroke];

      // Carve first, then trim with the area eraser.
      final carver = Eraser(mode: EraserMode.carve, size: 8);
      carver.clearState();
      final carve = carver.apply(
        const Offset(60, 100),
        strokes,
        areaTimeBudgetMs: null,
      );
      applyEraserDelta(strokes, carve);
      expect(strokes.single.hasCarve, isTrue);

      final trimmer = Eraser(mode: EraserMode.area, size: 8);
      trimmer.clearState();
      final trim = trimmer.apply(
        const Offset(150, 100),
        strokes,
        areaTimeBudgetMs: null,
      );
      applyEraserDelta(strokes, trim);

      expect(strokes, isNotEmpty);
      for (final fragment in strokes) {
        expect(
          fragment.hasCarve,
          isTrue,
          reason: 'area trim must not resurrect carved-away ink',
        );
      }
    });
  });
}
