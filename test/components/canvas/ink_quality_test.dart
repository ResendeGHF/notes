// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/stroke_geometry/point_vector.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/pen.dart';

/// Ink quality for the five freehand pens: detailed round caps that sit on
/// the tip under any motion/jitter, true-circle taps, identical live and
/// committed geometry (no pop), and the paper-bleed realism params.
void main() {
  // Geometry tests run with stabilization off so committed samples equal
  // raw input (stabilization lag would shift micro-stroke expectations;
  // it has its own suite and applies identically live/committed).
  setUp(() {
    stows.strokeStabilization.value = false;
  });
  tearDown(() {
    stows.strokeStabilization.value = true;
  });

  group('Ink caps and dots', () {
    Stroke strokeFor(ToolId id, {double size = 6}) => Stroke(
          color: Colors.black,
          pressureEnabled: true,
          options: StrokeOptions(size: size, simulatePressure: false),
          pageIndex: 0,
          page: HasSize(EditorPage.defaultSize),
          toolId: id,
        );

    Path livePath(Stroke s) => s.highQualityPath;

    test('ballpoint tap is a round dot, not a bar', () {
      final stroke = strokeFor(ToolId.ballpointPen);
      stroke.addPoint(const Offset(50, 50), 0.5, Duration.zero);
      stroke.addPoint(
        const Offset(50.1, 50.1),
        0.5,
        const Duration(milliseconds: 8),
      );
      final bounds = livePath(stroke).getBounds();
      expect(bounds.width, closeTo(bounds.height, 1.2));
      expect(bounds.width, greaterThan(2.0));
      expect(livePath(stroke).contains(const Offset(47.5, 50)), isTrue);
      expect(livePath(stroke).contains(const Offset(52.5, 50)), isTrue);
    });

    test('fountain tap is a round dot, not a sliver', () {
      final stroke = strokeFor(ToolId.fountainPen);
      stroke.addPoint(const Offset(50, 50), 0.6, Duration.zero);
      stroke.addPoint(
        const Offset(50.1, 50.1),
        0.6,
        const Duration(milliseconds: 8),
      );
      final bounds = livePath(stroke).getBounds();
      expect(bounds.width, closeTo(bounds.height, 1.5));
      expect(bounds.width, greaterThan(1.5));
      expect(livePath(stroke).contains(const Offset(50, 50)), isTrue);
    });

    test('short strokes cap round from the first frame', () {
      for (final id in [
        ToolId.ballpointPen,
        ToolId.fountainPen,
        ToolId.advancedPen,
      ]) {
        final stroke = strokeFor(id);
        stroke.addPoint(Offset.zero, 0.6, Duration.zero);
        stroke.addPoint(
          const Offset(3, 0),
          0.6,
          const Duration(milliseconds: 8),
        );
        final path = livePath(stroke);
        // Cap bulbs extend past both tips immediately (no butt-then-pop).
        expect(path.contains(const Offset(-1.5, 0)), isTrue,
            reason: '$id start cap');
        expect(path.contains(const Offset(4.5, 0)), isTrue,
            reason: '$id end cap');
      }
    });

    test('jittered put-down keeps symmetric start caps', () {
      // Single-sample spike at pen down must not lean the start fan: both
      // sides of the tip stay covered, like the Advanced Pen guarantee.
      // NB: Path.contains excludes the boundary, so the behind-tip probe
      // sits at 94% of the nominal radius (exact-circle caps otherwise make
      // this a float-dust lottery).
      for (final id in [ToolId.ballpointPen, ToolId.advancedPen]) {
        final stroke = strokeFor(id);
        const pts = [
          Offset(0, 0),
          Offset(3, 3),
          Offset(8, 0),
          Offset(16, 0),
          Offset(100, 0),
        ];
        for (var i = 0; i < pts.length; i++) {
          stroke.addPoint(pts[i], 0.6, Duration(milliseconds: i * 8));
        }
        final path = livePath(stroke);
        expect(path.contains(const Offset(-1.7, 0)), isTrue,
            reason: '$id cap behind tip');
        expect(path.contains(const Offset(0, 1.5)), isTrue,
            reason: '$id cap symmetric +');
        expect(path.contains(const Offset(0, -1.5)), isTrue,
            reason: '$id cap symmetric -');
      }
    });

    test('wide caps earn more outline detail', () {
      // Cap-region point count (within 1.3r of the start tip) grows with
      // nib radius instead of faceting: total outline length is dominated
      // by spine decimation, so count the fan itself.
      int capCount(double size) {
        final poly = List<PointVector>.generate(
          10,
          (i) => PointVector(i * 10.0, 0.0, 0.6),
        ).toStrokePolygon(size);
        final r = size / 2;
        return poly
            .where((p) =>
                (p.dx * p.dx + p.dy * p.dy) <= (r * 1.3) * (r * 1.3))
            .length;
      }

      expect(capCount(32), greaterThan(capCount(4)));
      expect(capCount(4), greaterThanOrEqualTo(8));
    });

    test('calligraphy nib keeps oriented caps without holes', () {
      final stroke = strokeFor(ToolId.calligraphyPen, size: 8);
      for (var i = 0; i < 14; i++) {
        stroke.addPoint(
          Offset(i * 8.0, i * -2.0),
          0.6,
          Duration(milliseconds: i * 8),
        );
      }
      final path = livePath(stroke);
      expect(path.getBounds().isEmpty, isFalse);
      // Start mouth closed: tip and pen-down dwell bulb covered.
      expect(path.contains(const Offset(0, 0)), isTrue);
      expect(path.contains(const Offset(-3.5, 0.8)), isTrue);
      // Stem start continuous, end capped along travel.
      expect(path.contains(const Offset(3, -0.7)), isTrue);
      expect(path.contains(const Offset(106, -26.5)), isTrue);
      // Spine interior covered (no winding holes).
      expect(path.contains(const Offset(48, -12)), isTrue);
    });

    test('ballpoint U-turns bulb round instead of square', () {
      // Tight overlapping U (arms 4px apart, width 8): both sides of the
      // return fan into a round bulb. A single-sided bevel reads square-ish
      // and leaves the outer apex thin.
      final spine = <PointVector>[
        for (var i = 0; i <= 8; i++) PointVector(i * 8.0, 0.0, 0.6),
        for (var i = 8; i >= 0; i--) PointVector(i * 8.0, 4.0, 0.6),
      ];
      final poly = Stroke.buildBallpointStyleOutline(spine, size: 8);
      expect(poly.length, greaterThan(8));
      final path = Path()..addPolygon(poly, true);
      // Outer apex bulb extends past the turn on both sides of the fold.
      expect(path.contains(const Offset(66, -1)), isTrue,
          reason: 'outer bulb past apex');
      expect(path.contains(const Offset(66, 5)), isTrue,
          reason: 'outer bulb other side');
      // Fold interior solid (no winding holes).
      expect(path.contains(const Offset(32, 2)), isTrue);
      // No square kink: visible outline turns stay distributed (closure
      // joint excluded; sub-2px degenerate fan/wall junctions ignored —
      // zero-area spikes are invisible and harmless to nonzero fill).
      var maxTurn = 0.0;
      for (var i = 0; i + 2 < poly.length; i++) {
        final a = poly[i];
        final b = poly[(i + 1) % poly.length];
        final c = poly[(i + 2) % poly.length];
        final d1x = b.dx - a.dx, d1y = b.dy - a.dy;
        final d2x = c.dx - b.dx, d2y = c.dy - b.dy;
        final l1 = math.sqrt(d1x * d1x + d1y * d1y);
        final l2 = math.sqrt(d2x * d2x + d2y * d2y);
        if (l1 < 2.0 || l2 < 2.0) continue;
        final dot = ((d1x * d2x + d1y * d2y) / (l1 * l2)).clamp(-1.0, 1.0);
        final turn = math.acos(dot);
        if (turn > maxTurn) maxTurn = turn;
      }
      expect(maxTurn, lessThan(2.0), reason: 'no square kink');
    });

    test('live and committed geometry match (no cap pop)', () {
      final prev = stows.strokePrediction.value;
      stows.strokePrediction.value = false;
      try {
        for (final id in [
          ToolId.ballpointPen,
          ToolId.fountainPen,
          ToolId.calligraphyPen,
          ToolId.advancedPen,
        ]) {
          final stroke = strokeFor(id);
          for (var i = 0; i < 12; i++) {
            stroke.addPoint(
              Offset(i * 9.0, i * 4.0 + (i.isEven ? 0.7 : -0.7)),
              0.6,
              Duration(milliseconds: i * 8),
            );
          }
          final liveBounds = livePath(stroke).getBounds();
          stroke.finishLiveGeometry();
          final committedBounds = stroke.highQualityPath.getBounds();
          for (final r in [liveBounds, committedBounds]) {
            expect(r.isEmpty, isFalse, reason: '$id bounds');
          }
          expect(
            (committedBounds.left - liveBounds.left).abs(),
            lessThanOrEqualTo(0.5),
            reason: '$id left edge stable',
          );
          expect(
            (committedBounds.right - liveBounds.right).abs(),
            lessThanOrEqualTo(0.5),
            reason: '$id right edge stable',
          );
          expect(
            (committedBounds.top - liveBounds.top).abs(),
            lessThanOrEqualTo(0.5),
            reason: '$id top edge stable',
          );
          expect(
            (committedBounds.bottom - liveBounds.bottom).abs(),
            lessThanOrEqualTo(0.5),
            reason: '$id bottom edge stable',
          );
        }
      } finally {
        stows.strokePrediction.value = prev;
      }
    });
  });

  group('Solid picture bake', () {
    test('solid bake caches crisp picture for ink pens', () {
      final stroke = Stroke(
        color: Colors.black,
        pressureEnabled: true,
        options: StrokeOptions(size: 4, simulatePressure: false),
        pageIndex: 0,
        page: HasSize(EditorPage.defaultSize),
        toolId: ToolId.ballpointPen,
      );
      for (var i = 0; i < 8; i++) {
        stroke.addPoint(
          Offset(i * 10.0, 0),
          0.6,
          Duration(milliseconds: i * 8),
        );
      }
      stroke.finishLiveGeometry();
      final picture = stroke.ensureSolidPathPicture(
        invert: false,
        color: Colors.black,
      );
      expect(picture, isNotNull);
      picture!.dispose();
    });
  });

  group('Calligraphy robust caps', () {
    Stroke nibStroke({
      required List<Offset> pts,
      List<double>? pressures,
      double size = 8,
    }) {
      final stroke = Stroke(
        color: Colors.black,
        pressureEnabled: true,
        options: StrokeOptions(size: size, simulatePressure: false),
        pageIndex: 0,
        page: HasSize(EditorPage.defaultSize),
        toolId: ToolId.calligraphyPen,
      );
      for (var i = 0; i < pts.length; i++) {
        stroke.addPoint(
          pts[i],
          pressures != null ? pressures[i] : 0.6,
          Duration(milliseconds: i * 8),
        );
      }
      return stroke;
    }

    test('degenerate micro-stroke closes without crash', () {
      final stroke = nibStroke(
        pts: const [Offset(50, 50), Offset(50.2, 50.1)],
      );
      final path = stroke.highQualityPath;
      expect(path.getBounds().isEmpty, isFalse);
      expect(path.contains(const Offset(50, 50)), isTrue);
    });

    test('short vertical stroke caps along travel, not sideways', () {
      // 3 samples spanning 6px: the min-distance scan finds nothing, so the
      // stable arc chord must orient the caps (a +x fallback would lay them
      // sideways on this vertical stroke).
      final stroke = nibStroke(
        pts: const [Offset(0, 0), Offset(0.5, 3), Offset(0, 6)],
      );
      final path = stroke.highQualityPath;
      // Ahead of the tip along +y.
      expect(path.contains(const Offset(0, 8.5)), isTrue);
      // Tip itself covered.
      expect(path.contains(const Offset(0, 6)), isTrue);
    });

    test('tip pressure spike does not balloon the cap', () {
      List<Offset> line() => List<Offset>.generate(
            12,
            (i) => Offset(i * 8.0, 0.0),
          );
      final calm = nibStroke(
        pts: line(),
        pressures: List<double>.filled(12, 0.5),
      );
      final spiked = nibStroke(
        pts: line(),
        pressures: [...List<double>.filled(11, 0.5), 1.0],
      );
      final calmBounds = calm.highQualityPath.getBounds();
      final spikedBounds = spiked.highQualityPath.getBounds();
      // A lift-off spike blends toward its neighbor: bounded growth only.
      expect(
        spikedBounds.width,
        lessThanOrEqualTo(calmBounds.width + 3.0),
      );
      expect(
        spikedBounds.height,
        lessThanOrEqualTo(calmBounds.height + 3.0),
      );
    });
  });

  group('Fountain Apple look', () {
    test('options: short taper, lively thinning, hairline floor', () {
      final opts = Pen.fountainPenOptions;
      expect(opts.start.customTaper, 6);
      expect(opts.end.customTaper, 6);
      expect(opts.thinning, closeTo(0.55, 1e-9));
      expect(opts.minSizeRatio, closeTo(0.07, 1e-9));
      // Tapered nib ends kept (no round caps).
      expect(opts.start.cap, isFalse);
      expect(opts.end.cap, isFalse);
      expect(opts.start.taperEnabled, isTrue);
      expect(opts.end.taperEnabled, isTrue);
    });

    Stroke fountainLine({required double pressure, int n = 14}) {
      final stroke = Stroke(
        color: Colors.black,
        pressureEnabled: true,
        options: Pen.fountainPenOptions.copyWith(size: 4),
        pageIndex: 0,
        page: HasSize(EditorPage.defaultSize),
        toolId: ToolId.fountainPen,
      );
      for (var i = 0; i < n; i++) {
        stroke.addPoint(
          Offset(i * 5.0, 0),
          pressure,
          Duration(milliseconds: i * 8),
        );
      }
      return stroke;
    }

    test('pressure response spans hairline to full', () {
      final soft = fountainLine(pressure: 0.15);
      final hard = fountainLine(pressure: 0.9);
      final softW = soft.highQualityPath.getBounds().height;
      final hardW = hard.highQualityPath.getBounds().height;
      expect(hardW, greaterThan(softW + 1.0));
    });

    test('taper stays short near the tip', () {
      // 65px line at size 4: 6px before the end the nib is still ~full.
      final stroke = fountainLine(pressure: 0.6, n: 14);
      final poly = stroke.highQualityPolygon;
      double maxHalf = 0;
      double nearTipHalf = 0;
      for (final p in poly) {
        final ax = p.dx.abs();
        if (p.dx >= 0 && p.dx <= 65) {
          if (ax > maxHalf && p.dx > 10 && p.dx < 50) maxHalf = ax;
          if ((p.dx - 59).abs() <= 1.0 && ax > nearTipHalf) {
            nearTipHalf = ax;
          }
        }
      }
      expect(maxHalf, greaterThan(0.5));
      expect(nearTipHalf, greaterThanOrEqualTo(maxHalf * 0.85));
    });

    test('single pressure spike does not lump the edge', () {
      List<Offset> line() => List<Offset>.generate(
            14,
            (i) => Offset(i * 5.0, 0.0),
          );
      Stroke build(List<double> pressures) {
        final stroke = Stroke(
          color: Colors.black,
          pressureEnabled: true,
          options: Pen.fountainPenOptions.copyWith(size: 4),
          pageIndex: 0,
          page: HasSize(EditorPage.defaultSize),
          toolId: ToolId.fountainPen,
        );
        for (var i = 0; i < line().length; i++) {
          stroke.addPoint(
            line()[i],
            pressures[i],
            Duration(milliseconds: i * 8),
          );
        }
        return stroke;
      }

      final calm = build(List<double>.filled(14, 0.6));
      final spiked = build(
        [...List<double>.filled(7, 0.6), 1.0, ...List<double>.filled(6, 0.6)],
      );
      final calmH = calm.highQualityPath.getBounds().height;
      final spikedH = spiked.highQualityPath.getBounds().height;
      expect(spikedH, lessThanOrEqualTo(calmH + 0.8));
    });
  });
}

extension on List<PointVector> {
  List<Offset> toStrokePolygon(double size) {
    final stroke = Stroke(
      color: Colors.black,
      pressureEnabled: true,
      options: StrokeOptions(size: size, simulatePressure: false),
      pageIndex: 0,
      page: HasSize(EditorPage.defaultSize),
      toolId: ToolId.ballpointPen,
    );
    for (var i = 0; i < length; i++) {
      final p = this[i];
      stroke.addPoint(
        Offset(p.x, p.y),
        p.pressure,
        Duration(milliseconds: i * 8),
      );
    }
    return stroke.highQualityPolygon;
  }
}
