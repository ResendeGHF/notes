// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';

Path _outlinePath(List<Offset> outline) {
  return Path()
    ..fillType = PathFillType.nonZero
    ..addPolygon(outline, true);
}

void main() {
  group('buildConstantWidthOutline', () {
    test('straight segment yields closed ribbon of correct width', () {
      final points = [
        const PointVector(0, 0),
        const PointVector(100, 0),
      ];
      final flat = buildConstantWidthOutline(
        points,
        radius: 10,
        roundCaps: false,
      );
      expect(flat.length, greaterThanOrEqualTo(4));
      final ys = flat.map((p) => p.dy).toList();
      expect(ys.reduce((a, b) => a < b ? a : b), closeTo(-10, 0.01));
      expect(ys.reduce((a, b) => a > b ? a : b), closeTo(10, 0.01));

      final round = buildConstantWidthOutline(
        points,
        radius: 10,
        roundCaps: true,
      );
      expect(round.length, greaterThan(flat.length));
    });

    test('single point with round caps is a circle', () {
      final outline = buildConstantWidthOutline(
        [const PointVector(5, 5)],
        radius: 8,
        roundCaps: true,
      );
      expect(outline.length, greaterThanOrEqualTo(8));
      for (final p in outline) {
        expect((p - const Offset(5, 5)).distance, closeTo(8, 0.5));
      }
    });

    test('getStroke constant-width path matches radius size/2', () {
      final outline = getStroke(
        [
          const PointVector(0, 0),
          const PointVector(50, 0),
          const PointVector(100, 0),
        ],
        options: StrokeOptions(
          size: 20,
          thinning: 0,
          simulatePressure: false,
          start: StrokeEndOptions.start(cap: true),
          end: StrokeEndOptions.end(cap: true),
        ),
      );
      expect(outline, isNotEmpty);
      final ys = outline.map((p) => p.dy).toList();
      expect(ys.reduce((a, b) => a < b ? a : b), lessThan(-8));
      expect(ys.reduce((a, b) => a > b ? a : b), greaterThan(8));
    });

    test('flat caps do not add round arcs', () {
      final flat = buildConstantWidthOutline(
        [const PointVector(0, 0), const PointVector(40, 0)],
        radius: 5,
        roundCaps: false,
      );
      final round = buildConstantWidthOutline(
        [const PointVector(0, 0), const PointVector(40, 0)],
        radius: 5,
        roundCaps: true,
      );
      expect(round.length, greaterThan(flat.length));
      final xs = flat.map((p) => p.dx);
      expect(xs.reduce((a, b) => a < b ? a : b), closeTo(0, 0.01));
      expect(xs.reduce((a, b) => a > b ? a : b), closeTo(40, 0.01));
    });

    test('startCap and endCap can be enabled independently', () {
      final points = [
        const PointVector(0, 0),
        const PointVector(80, 0),
      ];
      double minX(List<Offset> o) =>
          o.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
      double maxX(List<Offset> o) =>
          o.map((p) => p.dx).reduce((a, b) => a > b ? a : b);

      final open = buildConstantWidthOutline(
        points,
        radius: 10,
        roundCaps: false,
      );
      final startOnly = buildConstantWidthOutline(
        points,
        radius: 10,
        roundCaps: false,
        startCap: true,
        endCap: false,
      );
      final endOnly = buildConstantWidthOutline(
        points,
        radius: 10,
        roundCaps: false,
        startCap: false,
        endCap: true,
      );

      expect(minX(open), closeTo(0, 0.05));
      expect(maxX(open), closeTo(80, 0.05));
      expect(minX(startOnly), lessThan(-6));
      expect(maxX(startOnly), closeTo(80, 0.6));
      expect(minX(endOnly), closeTo(0, 0.6));
      expect(maxX(endOnly), greaterThan(86));

      final viaGetStroke = getStroke(
        points,
        options: StrokeOptions(
          size: 20,
          thinning: 0,
          start: StrokeEndOptions.start(cap: true, taperEnabled: false),
          end: StrokeEndOptions.end(cap: false, taperEnabled: false),
        ),
        startCap: true,
        endCap: false,
      );
      expect(minX(viaGetStroke), lessThan(-6));
      expect(maxX(viaGetStroke), closeTo(80, 0.6));
    });

    test('jittery slow freehand keeps spine samples inside the fill', () {
      // Simulate holding the pen nearly still: many near-duplicate samples
      // with tiny noise — previously flipped normals and punched holes.
      final rng = math.Random(7);
      final points = <PointVector>[];
      for (var i = 0; i < 120; i++) {
        final t = i / 119.0;
        points.add(
          PointVector(
            t * 180 + (rng.nextDouble() - 0.5) * 0.8,
            40 + (rng.nextDouble() - 0.5) * 0.8,
          ),
        );
      }

      for (final roundCaps in [true, false]) {
        final outline = buildConstantWidthOutline(
          points,
          radius: 12,
          roundCaps: roundCaps,
        );
        final path = _outlinePath(outline);
        // Skip endpoints: flat butt caps place them on the boundary, where
        // Path.contains is unreliable.
        for (var i = 8; i < points.length - 8; i += 5) {
          expect(
            path.contains(Offset(points[i].x, points[i].y)),
            isTrue,
            reason: 'roundCaps=$roundCaps spine[$i] should stay inside fill',
          );
        }
      }
    });

    test('sharp corner with flat caps does not erase the bend', () {
      final points = [
        const PointVector(0, 0),
        const PointVector(100, 0),
        const PointVector(100, 80),
      ];
      final outline = buildConstantWidthOutline(
        points,
        radius: 14,
        roundCaps: false,
      );
      final path = _outlinePath(outline);
      // Near the corner, on the spine — must remain filled.
      expect(path.contains(const Offset(100, 0)), isTrue);
      expect(path.contains(const Offset(100, 40)), isTrue);
      expect(path.contains(const Offset(50, 0)), isTrue);
    });

    test('decimateStrokeSpine keeps endpoints and thins clusters', () {
      final dense = <PointVector>[
        for (var i = 0; i < 50; i++) PointVector(i * 0.1, 0),
      ];
      final thin = decimateStrokeSpine(dense, minDistance: 2);
      expect(thin.first.x, dense.first.x);
      expect(thin.last.x, dense.last.x);
      expect(thin.length, lessThan(dense.length));
      expect(thin.length, greaterThanOrEqualTo(2));
    });

    test('U-turn return gets a rounded tip bulb, not a flat bevel', () {
      final points = [
        const PointVector(0, 0),
        const PointVector(80, 0),
        const PointVector(100, 0),
        const PointVector(80, 0.5), // slight return
        const PointVector(20, 1),
      ];
      final outline = buildConstantWidthOutline(
        points,
        radius: 10,
        roundCaps: true,
      );
      final path = Path()
        ..fillType = PathFillType.nonZero
        ..addPolygon(outline, true);

      // Tip of the return should extend past the turnaround point.
      expect(path.contains(const Offset(100, 0)), isTrue);
      expect(path.contains(const Offset(108, 0)), isTrue);
      // Body near the return stays filled (no self-erase hole).
      expect(path.contains(const Offset(90, 0)), isTrue);
      expect(path.contains(const Offset(50, 0)), isTrue);
    });

    test('local opening/closing chord tangents ignore far-spine swing', () {
      final points = [
        const PointVector(0, 0),
        const PointVector(10, 0),
        const PointVector(20, 0),
        const PointVector(40, 30), // later bend must not yank start tangent
        const PointVector(60, 60),
      ];
      final (stx, sty) = localOpeningChordTangent(points, baseSize: 8);
      expect(stx, greaterThan(0.9));
      expect(sty.abs(), lessThan(0.25));

      final (etx, ety) = localClosingChordTangent(points, baseSize: 8);
      expect(etx, greaterThan(0.4));
      expect(ety, greaterThan(0.4));
    });

    test('advanced variable-width U-turn keeps body and round tip', () {
      final points = [
        const PointVector(0, 0, 0.6),
        const PointVector(60, 0, 0.7),
        const PointVector(100, 0, 0.8),
        const PointVector(60, 1, 0.7),
        const PointVector(10, 2, 0.55),
      ];
      final outline = getStroke(
        points,
        options: StrokeOptions(
          size: 16,
          thinning: 0.45,
          simulatePressure: false,
          start: StrokeEndOptions.start(cap: true, taperEnabled: true),
          end: StrokeEndOptions.end(cap: true, taperEnabled: true),
        ),
      );
      final path = Path()
        ..fillType = PathFillType.nonZero
        ..addPolygon(outline, true);
      expect(path.contains(const Offset(100, 0)), isTrue);
      expect(path.contains(const Offset(50, 0)), isTrue);
      expect(path.contains(const Offset(106, 0)), isTrue);
    });

    test('Advanced Pen start/end caps use Ballpoint local chords (jitter-stable)', () {
      final points = [
        const PointVector(0, 0, 0.5),
        const PointVector(0.04, 0.9, 0.5),
        const PointVector(0.08, -0.7, 0.5),
        const PointVector(8, 0.1, 0.6),
        const PointVector(24, 0.15, 0.65),
        const PointVector(48, 0.1, 0.6),
      ];
      final opening = localOpeningChordTangent(points, baseSize: 4);
      final closing = localClosingChordTangent(points, baseSize: 4);
      expect(opening.$1, greaterThan(0.9));
      expect(opening.$2.abs(), lessThan(0.25));
      expect(closing.$1, greaterThan(0.9));
      expect(closing.$2.abs(), lessThan(0.25));

      final outline = getStroke(
        points,
        options: StrokeOptions(
          size: 8,
          thinning: 0.45,
          simulatePressure: false,
          start: StrokeEndOptions.start(cap: true, taperEnabled: true),
          end: StrokeEndOptions.end(cap: true, taperEnabled: true),
        ),
        capChordOnlyAtCappedEnds: true,
        dualSidedReturnJoins: true,
        meshStyleCaps: true,
        startTravelTangent: opening,
        endTravelTangent: closing,
      );
      final back = outline.reduce((a, b) => a.dx < b.dx ? a : b);
      expect(back.dx, lessThan(-1));
      expect(
        back.dy.abs(),
        lessThan(2.0),
        reason: 'start hemisphere follows Ballpoint +X chord, not Y jitter',
      );
      final tip = outline.reduce((a, b) => a.dx > b.dx ? a : b);
      expect(tip.dx, greaterThan(48));
      expect(
        tip.dy.abs(),
        lessThan(2.0),
        reason: 'end hemisphere follows Ballpoint +X chord',
      );
    });

    test('Advanced Pen start cap sits on the opening tangent, not the jitter', () {
      final points = [
        const PointVector(0, 0, 0.5),
        const PointVector(0.04, 0.9, 0.5),
        const PointVector(0.08, -0.7, 0.5),
        const PointVector(8, 0.1, 0.6),
        const PointVector(24, 0.15, 0.65),
        const PointVector(48, 0.1, 0.6),
      ];
      final outline = getStroke(
        points,
        options: StrokeOptions(
          size: 8,
          thinning: 0.45,
          simulatePressure: false,
          start: StrokeEndOptions.start(cap: true, taperEnabled: true),
          end: StrokeEndOptions.end(cap: true, taperEnabled: true),
        ),
        capChordOnlyAtCappedEnds: true,
        dualSidedReturnJoins: true,
        meshStyleCaps: true,
      );
      final capPts = outline.where((p) => p.dx < -1);
      expect(capPts, isNotEmpty);
      final meanY =
          capPts.map((p) => p.dy).reduce((a, b) => a + b) / capPts.length;
      expect(
        meanY.abs(),
        lessThan(2.0),
        reason: 'start hemisphere should sit on +X tangent, not the Y jitter',
      );
      final back = outline.reduce((a, b) => a.dx < b.dx ? a : b);
      expect(
        back.dy.abs(),
        lessThan(1.5),
        reason: 'hemisphere tip must lie on the travel axis',
      );
    });

    test('Ballpoint local opening chord looks past a short stem into travel', () {
      final points = [
        const PointVector(0, 0, 0.6),
        const PointVector(0, 2, 0.6),
        const PointVector(0, 4, 0.65),
        const PointVector(2, 4, 0.65),
        const PointVector(8, 4, 0.6),
        const PointVector(24, 4, 0.6),
      ];
      final (tx, ty) = localOpeningChordTangent(points, baseSize: 8);
      expect(tx, greaterThan(0.5));
      expect(ty, greaterThan(0.1));
    });

    test('Advanced Pen start/end caps agree on a straight run', () {
      final points = [
        for (var i = 0; i < 12; i++) PointVector(i * 4.0, 0.0, 0.6),
      ];
      final startT = localOpeningChordTangent(points, baseSize: 8);
      final endT = localClosingChordTangent(points, baseSize: 8);
      expect(startT.$1, closeTo(1.0, 0.05));
      expect(endT.$1, closeTo(1.0, 0.05));
      expect(startT.$2.abs(), lessThan(0.1));
      expect(endT.$2.abs(), lessThan(0.1));
    });

    test('Advanced Pen caps ignore put-down jitter via Ballpoint chords', () {
      final points = [
        const PointVector(0, 0, 0.5),
        const PointVector(0.3, 1.2, 0.5),
        const PointVector(0.2, -0.8, 0.5),
        const PointVector(1.0, 0.2, 0.55),
        const PointVector(4, 0.1, 0.6),
        const PointVector(12, 0.0, 0.65),
        const PointVector(40, 0.0, 0.6),
      ];
      for (final size in [8.0, 16.0, 28.0]) {
        final opening = localOpeningChordTangent(points, baseSize: size / 2);
        final closing = localClosingChordTangent(points, baseSize: size / 2);
        expect(opening.$1, greaterThan(0.85));
        expect(opening.$2.abs(), lessThan(0.4));
        expect(closing.$1, greaterThan(0.85));

        final outline = getStroke(
          points,
          options: StrokeOptions(
            size: size,
            thinning: 0.45,
            simulatePressure: false,
            start: StrokeEndOptions.start(cap: true, taperEnabled: true),
            end: StrokeEndOptions.end(cap: true, taperEnabled: true),
          ),
          capChordOnlyAtCappedEnds: true,
          dualSidedReturnJoins: true,
          meshStyleCaps: true,
          startTravelTangent: opening,
          endTravelTangent: closing,
        );
        final back = outline.reduce((a, b) => a.dx < b.dx ? a : b);
        expect(back.dx, lessThan(-1));
        expect(back.dy.abs(), lessThan(size * 0.35));
        final tip = outline.reduce((a, b) => a.dx > b.dx ? a : b);
        expect(tip.dx, greaterThan(40));
        expect(tip.dy.abs(), lessThan(size * 0.35));
      }
    });

    test('localOpeningChordTangent spans a local window like Ballpoint', () {
      final points = [
        const PointVector(0, 0, 0.6),
        const PointVector(0, 3, 0.6),
        const PointVector(0, 6, 0.65),
        const PointVector(3, 6, 0.65),
        const PointVector(20, 6, 0.6),
        const PointVector(40, 6, 0.6),
      ];
      final t = localOpeningChordTangent(points, baseSize: 8);
      expect(t.$1, greaterThan(0.4));
    });

    test('localOpeningChordTangent stays on a long first stem', () {
      final points = [
        const PointVector(0, 0, 0.6),
        const PointVector(0, 8, 0.6),
        const PointVector(0, 16, 0.65),
        const PointVector(0, 24, 0.65),
        const PointVector(8, 24, 0.6),
        const PointVector(40, 24, 0.6),
      ];
      final t = localOpeningChordTangent(points, baseSize: 8);
      expect(t.$2, greaterThan(0.85));
      expect(t.$1.abs(), lessThan(0.4));
    });

    test('Advanced Pen production caps use circular arcs (not mesh hemispheres)', () {
      // Mirrors _advancedOutlineFromSpine: circular _capArc, first/last-segment
      // travel — no meshStyleCaps / tip-edge shear.
      final points = [
        for (var i = 0; i < 12; i++) PointVector(i * 4.0, 0.0, 0.6),
      ];
      final s0 = points.first;
      final s1 = points[1];
      final e0 = points[points.length - 2];
      final e1 = points.last;
      final sdx = s1.x - s0.x, sdy = s1.y - s0.y;
      final edx = e1.x - e0.x, edy = e1.y - e0.y;
      final sLen = math.sqrt(sdx * sdx + sdy * sdy);
      final eLen = math.sqrt(edx * edx + edy * edy);
      final outline = getStroke(
        points,
        options: StrokeOptions(
          size: 16,
          thinning: 0.45,
          simulatePressure: false,
          start: StrokeEndOptions.start(
            cap: true,
            taperEnabled: true,
            customTaper: 10,
          ),
          end: StrokeEndOptions.end(
            cap: true,
            taperEnabled: true,
            customTaper: 10,
          ),
        ),
        capChordOnlyAtCappedEnds: true,
        dualSidedReturnJoins: true,
        meshStyleCaps: false,
        startTravelTangent: sLen > 1e-6 ? (sdx / sLen, sdy / sLen) : null,
        endTravelTangent: eLen > 1e-6 ? (edx / eLen, edy / eLen) : null,
      );
      final back = outline.reduce((a, b) => a.dx < b.dx ? a : b);
      final tip = outline.reduce((a, b) => a.dx > b.dx ? a : b);
      expect(back.dx, lessThan(-2));
      expect(back.dy.abs(), lessThan(2.5), reason: 'start cap on +X travel');
      expect(tip.dx, greaterThan(40));
      expect(tip.dy.abs(), lessThan(2.5), reason: 'circular end tip stays on axis');
    });

    test('circular start cap stays centered on the tip (no sideways tic-tac)', () {
      // Mild put-down bend: a long opening chord leans the diameter off the
      // first stem. Circular _capArc on the first segment must stay centered.
      final points = [
        const PointVector(0, 2.0, 0.55),
        const PointVector(4, 1.2, 0.6),
        for (var i = 2; i < 12; i++) PointVector(i * 5.0, 0.0, 0.65),
      ];
      final a = points.first;
      final b = points[1];
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final len = math.sqrt(dx * dx + dy * dy);
      final tx = dx / len;
      final ty = dy / len;
      final nx = -ty;
      final ny = tx;
      final outline = getStroke(
        points,
        options: StrokeOptions(
          size: 12,
          thinning: 0.35,
          simulatePressure: false,
          start: StrokeEndOptions.start(cap: true, taperEnabled: true),
          end: StrokeEndOptions.end(cap: true, taperEnabled: true),
        ),
        capChordOnlyAtCappedEnds: true,
        dualSidedReturnJoins: true,
        meshStyleCaps: false,
        startTravelTangent: (tx, ty),
      );
      final tip = Offset(a.x, a.y);
      // Points behind the tip along -travel belong to the circular start cap.
      final capPts = outline.where((p) {
        final along = (p.dx - tip.dx) * tx + (p.dy - tip.dy) * ty;
        return along < -0.5;
      }).toList();
      expect(capPts, isNotEmpty);
      final meanAcross =
          capPts
              .map((p) => (p.dx - tip.dx) * nx + (p.dy - tip.dy) * ny)
              .reduce((a, b) => a + b) /
          capPts.length;
      expect(
        meanAcross.abs(),
        lessThan(1.0),
        reason: 'start cap centroid must sit on the tip axis, not offset sideways',
      );
      final farthest = capPts.reduce((a, b) {
        final da = (a.dx - tip.dx) * tx + (a.dy - tip.dy) * ty;
        final db = (b.dx - tip.dx) * tx + (b.dy - tip.dy) * ty;
        return da <= db ? a : b;
      });
      final tipAcross =
          (farthest.dx - tip.dx) * nx + (farthest.dy - tip.dy) * ny;
      expect(
        tipAcross.abs(),
        lessThan(1.2),
        reason: 'circular start apex stays on the travel axis',
      );
    });

    test('Advanced Pen start cap follows the first stem, not a later chord', () {
      final points = [
        const PointVector(0, 0, 0.6),
        const PointVector(0, 6, 0.6),
        const PointVector(0, 12, 0.65),
        const PointVector(4, 12, 0.65),
        const PointVector(20, 12, 0.6),
        const PointVector(40, 12, 0.6),
      ];
      final a = points.first;
      final b = points[1];
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final len = math.sqrt(dx * dx + dy * dy);
      final outline = getStroke(
        points,
        options: StrokeOptions(
          size: 16,
          thinning: 0.45,
          simulatePressure: false,
          start: StrokeEndOptions.start(cap: true, taperEnabled: true),
          end: StrokeEndOptions.end(cap: true, taperEnabled: true),
        ),
        capChordOnlyAtCappedEnds: true,
        dualSidedReturnJoins: true,
        meshStyleCaps: false,
        startTravelTangent: len > 1e-6 ? (dx / len, dy / len) : null,
      );
      final back = outline.reduce((a, b) => a.dy < b.dy ? a : b);
      expect(
        back.dy,
        lessThan(0 - 4),
        reason: 'start hemisphere must sit behind the +Y stem',
      );
      expect(
        (back.dx - 0).abs(),
        lessThan(5),
        reason: 'must not rotate toward the later +X run',
      );
    });

    test('circular end cap stays centered on the tip (no sideways tic-tac)', () {
      // Mild tip bend: mesh-style hemisphere + tip-edge align used to shove the
      // bulb off-axis. Circular _capArc on the last segment must stay centered.
      final points = [
        for (var i = 0; i < 10; i++) PointVector(i * 5.0, 0.0, 0.65),
        const PointVector(52, 1.2, 0.6),
        const PointVector(56, 2.0, 0.55),
      ];
      final a = points[points.length - 2];
      final b = points.last;
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final len = math.sqrt(dx * dx + dy * dy);
      final tx = dx / len;
      final ty = dy / len;
      final nx = -ty;
      final ny = tx;
      final outline = getStroke(
        points,
        options: StrokeOptions(
          size: 12,
          thinning: 0.35,
          simulatePressure: false,
          start: StrokeEndOptions.start(cap: true, taperEnabled: true),
          end: StrokeEndOptions.end(cap: true, taperEnabled: true),
        ),
        capChordOnlyAtCappedEnds: true,
        dualSidedReturnJoins: true,
        meshStyleCaps: false,
        endTravelTangent: (tx, ty),
      );
      final tip = Offset(b.x, b.y);
      // Points past the tip along travel belong to the circular cap.
      final capPts = outline.where((p) {
        final along = (p.dx - tip.dx) * tx + (p.dy - tip.dy) * ty;
        return along > 0.5;
      }).toList();
      expect(capPts, isNotEmpty);
      final meanAcross =
          capPts
              .map((p) => (p.dx - tip.dx) * nx + (p.dy - tip.dy) * ny)
              .reduce((a, b) => a + b) /
          capPts.length;
      expect(
        meanAcross.abs(),
        lessThan(1.0),
        reason: 'end cap centroid must sit on the tip axis, not offset sideways',
      );
      final farthest = capPts.reduce((a, b) {
        final da = (a.dx - tip.dx) * tx + (a.dy - tip.dy) * ty;
        final db = (b.dx - tip.dx) * tx + (b.dy - tip.dy) * ty;
        return da >= db ? a : b;
      });
      final tipAcross =
          (farthest.dx - tip.dx) * nx + (farthest.dy - tip.dy) * ny;
      expect(
        tipAcross.abs(),
        lessThan(1.2),
        reason: 'circular tip apex stays on the travel axis',
      );
    });

    test('Advanced Pen end cap follows the last stem, not a earlier chord', () {
      final points = [
        const PointVector(0, 4, 0.6),
        const PointVector(16, 4, 0.6),
        const PointVector(32, 4, 0.65),
        const PointVector(36, 4, 0.65),
        const PointVector(36, 6, 0.6),
        const PointVector(36, 12, 0.6),
      ];
      final outline = getStroke(
        points,
        options: StrokeOptions(
          size: 16,
          thinning: 0.45,
          simulatePressure: false,
          start: StrokeEndOptions.start(cap: true, taperEnabled: true),
          end: StrokeEndOptions.end(cap: true, taperEnabled: true),
        ),
        capChordOnlyAtCappedEnds: true,
        dualSidedReturnJoins: true,
        meshStyleCaps: true,
      );
      final tip = outline.reduce((a, b) => a.dy > b.dy ? a : b);
      expect(
        tip.dy,
        greaterThan(12 + 4),
        reason: 'end hemisphere must sit ahead of the +Y stem',
      );
      expect(
        (tip.dx - 36).abs(),
        lessThan(5),
        reason: 'must not rotate toward the earlier +X run',
      );
    });

    test('open interior window does not grow a start-cap bulb', () {
      final points = [
        const PointVector(40, 0, 0.6),
        const PointVector(80, 0, 0.65),
        const PointVector(120, 0, 0.6),
      ];
      final outline = getStroke(
        points,
        options: StrokeOptions(
          size: 8,
          thinning: 0.45,
          simulatePressure: false,
          start: StrokeEndOptions.start(cap: true, taperEnabled: true),
          end: StrokeEndOptions.end(cap: true, taperEnabled: true),
        ),
        startCap: false,
        endCap: false,
        applyStartTaper: false,
        applyEndTaper: false,
        capChordOnlyAtCappedEnds: true,
        capTangentMinLookahead: 6,
        meshStyleCaps: true,
      );
      final minX = outline.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
      expect(minX, greaterThan(40 - 5));
    });

    test('dual-sided Advanced Pen U-turn stays round at the return', () {
      final points = [
        const PointVector(0, 0, 0.6),
        const PointVector(60, 0, 0.7),
        const PointVector(100, 0, 0.8),
        const PointVector(60, 1, 0.7),
        const PointVector(10, 2, 0.55),
      ];
      final outline = getStroke(
        points,
        options: StrokeOptions(
          size: 16,
          thinning: 0.45,
          simulatePressure: false,
          start: StrokeEndOptions.start(cap: true, taperEnabled: true),
          end: StrokeEndOptions.end(cap: true, taperEnabled: true),
        ),
        capChordOnlyAtCappedEnds: true,
        dualSidedReturnJoins: true,
        capTangentMinLookahead: 6,
        meshStyleCaps: true,
      );
      final path = Path()
        ..fillType = PathFillType.nonZero
        ..addPolygon(outline, true);
      expect(path.contains(const Offset(100, 0)), isTrue);
      expect(path.contains(const Offset(50, 0)), isTrue);
      expect(path.contains(const Offset(106, 0)), isTrue);
      // Ballpoint-style bulb: no flat diameter through the apex — both
      // forward tip and the sides of the return stay filled.
      expect(path.contains(const Offset(100, 6)), isTrue);
      expect(path.contains(const Offset(100, -6)), isTrue);
    });

    test('Advanced Pen sharp reverse fills a round tip bulb like ballpoint', () {
      final points = [
        const PointVector(0, 0, 0.6),
        const PointVector(40, 0, 0.7),
        const PointVector(80, 0, 0.8),
        const PointVector(100, 0, 0.85),
        const PointVector(80, 0.2, 0.8),
        const PointVector(40, 0.4, 0.7),
        const PointVector(0, 0.6, 0.55),
      ];
      final advanced = getStroke(
        points,
        options: StrokeOptions(
          size: 16,
          thinning: 0,
          simulatePressure: false,
          start: StrokeEndOptions.start(cap: true, taperEnabled: false),
          end: StrokeEndOptions.end(cap: true, taperEnabled: false),
        ),
        capChordOnlyAtCappedEnds: true,
        dualSidedReturnJoins: true,
        meshStyleCaps: true,
      );
      final ballpoint = buildConstantWidthOutline(
        points.map((p) => PointVector(p.x, p.y)).toList(),
        radius: 8,
        roundCaps: true,
      );
      final advPath = Path()
        ..fillType = PathFillType.nonZero
        ..addPolygon(advanced, true);
      final ballPath = Path()
        ..fillType = PathFillType.nonZero
        ..addPolygon(ballpoint, true);
      for (final sample in [
        const Offset(100, 0),
        const Offset(106, 0),
        const Offset(100, 6),
        const Offset(100, -6),
      ]) {
        expect(
          advPath.contains(sample),
          ballPath.contains(sample),
          reason: 'Advanced return fill should match ballpoint at $sample',
        );
      }
    });

    test('Advanced Pen U-turn does not fill the crotch', () {
      final points = [
        const PointVector(0, 0, 0.6),
        const PointVector(80, 0, 0.7),
        const PointVector(100, 0, 0.8),
        const PointVector(80, 20, 0.7),
        const PointVector(0, 20, 0.55),
      ];
      final outline = getStroke(
        points,
        options: StrokeOptions(
          size: 8,
          thinning: 0,
          simulatePressure: false,
          start: StrokeEndOptions.start(cap: true, taperEnabled: false),
          end: StrokeEndOptions.end(cap: true, taperEnabled: false),
        ),
        capChordOnlyAtCappedEnds: true,
        dualSidedReturnJoins: true,
        meshStyleCaps: true,
      );
      final path = Path()
        ..fillType = PathFillType.nonZero
        ..addPolygon(outline, true);
      expect(path.contains(const Offset(100, 0)), isTrue);
      expect(path.contains(const Offset(50, 0)), isTrue);
      expect(
        path.contains(const Offset(50, 10)),
        isFalse,
        reason: 'inner diameter must not close the U',
      );
    });
  });
}
