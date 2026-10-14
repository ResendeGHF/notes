// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:math' as math;
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/stroke_geometry/point_vector.dart';
import 'package:saber/data/stroke_geometry/advanced_pen_composer.dart';
import 'package:saber/data/stroke_geometry/advanced_pen_modeler.dart';
import 'package:saber/data/stroke_geometry/advanced_pen_options.dart';
import 'package:saber/data/stroke_geometry/stroke_options.dart';
import 'package:saber/data/tools/_tool.dart';

void main() {
  group('AdvancedPenModelerParams', () {
    test('advanced defaults validate', () {
      expect(AdvancedPenModelerParams.advancedDefaults.validate(), isNull);
    });

    test('rejects inverted wobble range', () {
      const bad = AdvancedPenModelerParams(
        wobbleTimeout: 0.04,
        wobbleSpeedFloor: 2.0,
        wobbleSpeedCeiling: 1.0,
        springMassConstant: 11.0 / 32400.0,
        dragConstant: 72.0,
        minOutputRate: 120.0,
        endOfStrokeStoppingDistance: 0.01,
        endOfStrokeMaxIterations: 20,
        maxOutputsPerCall: 200,
        maxInputSamples: 20,
      );
      expect(bad.validate(), isNotNull);
    });

    test('json round trip', () {
      const params = AdvancedPenModelerParams.advancedDefaults;
      final restored = AdvancedPenModelerParams.fromJson(params.toJson());
      expect(restored, equals(params));
    });
  });

  group('AdvancedPenPressureCurve', () {
    test('matches the PressureCurve::apply port', () {
      expect(AdvancedPenPressureCurve.constant.apply(4.0, 0.25), 4.0);
      expect(AdvancedPenPressureCurve.linear.apply(4.0, 0.5), 2.0);
      expect(AdvancedPenPressureCurve.sqrt.apply(4.0, 0.25), closeTo(2.0, 1e-9));
      expect(AdvancedPenPressureCurve.pow2.apply(4.0, 0.5), 1.0);
      expect(AdvancedPenPressureCurve.pow3.apply(8.0, 0.5), 1.0);
    });
  });

  group('AdvancedPenStrokeModeler', () {
    test('down/move/up produces modeled results', () {
      final modeler = AdvancedPenStrokeModeler();
      final down = modeler.update(
        const AdvancedPenModelerInput(
          eventType: AdvancedPenInputEventType.down,
          x: 0,
          y: 0,
          time: 0,
          pressure: 0.5,
        ),
      );
      expect(down, hasLength(1));
      expect(down.first.x, 0);
      expect(down.first.y, 0);

      final move = modeler.update(
        const AdvancedPenModelerInput(
          eventType: AdvancedPenInputEventType.move,
          x: 10,
          y: 0,
          time: 1 / 60,
          pressure: 0.6,
        ),
      );
      // Upsampled at 120 Hz over a 1/60s gap -> 2 outputs.
      expect(move.length, greaterThanOrEqualTo(1));

      final end = modeler.update(
        AdvancedPenModelerInput(
          eventType: AdvancedPenInputEventType.up,
          x: 10,
          y: 0,
          time: 2 / 60,
          pressure: 0.6,
        ),
      );
      expect(end, isNotEmpty);
      // End-of-stroke catch-up lands near the lift position.
      expect(end.last.x, closeTo(10.0, 1.0));
    });

    test('slow straight line stays on the line (spring sanity)', () {
      final modeler = AdvancedPenStrokeModeler();
      modeler.update(
        const AdvancedPenModelerInput(
          eventType: AdvancedPenInputEventType.down,
          x: 0,
          y: 0,
          time: 0,
          pressure: 0.5,
        ),
      );
      var lastY = 0.0;
      for (var i = 1; i <= 10; i++) {
        final out = modeler.update(
          AdvancedPenModelerInput(
            eventType: AdvancedPenInputEventType.move,
            x: i * 5.0,
            y: 0,
            time: i / 60.0,
            pressure: 0.5,
          ),
        );
        for (final r in out) {
          expect(r.y.abs(), lessThan(2.0));
          lastY = r.y;
        }
      }
      expect(lastY.abs(), lessThan(2.0));
    });

    test('duplicate and rewound inputs throw like upstream', () {
      final modeler = AdvancedPenStrokeModeler();
      modeler.update(
        const AdvancedPenModelerInput(
          eventType: AdvancedPenInputEventType.down,
          x: 1,
          y: 1,
          time: 1.0,
          pressure: 0.5,
        ),
      );
      const move = AdvancedPenModelerInput(
        eventType: AdvancedPenInputEventType.move,
        x: 2,
        y: 1,
        time: 1.01,
        pressure: 0.5,
      );
      modeler.update(move);
      // Exact repeat is a duplicate.
      expect(
        () => modeler.update(move),
        throwsA(isA<AdvancedPenModelerException>()),
      );
      // Rewound time is rejected.
      expect(
        () => modeler.update(
          const AdvancedPenModelerInput(
            eventType: AdvancedPenInputEventType.move,
            x: 3,
            y: 1,
            time: 1.005,
            pressure: 0.5,
          ),
        ),
        throwsA(isA<AdvancedPenModelerException>()),
      );
    });

    test('predict returns catch-up tail without consuming', () {
      final modeler = AdvancedPenStrokeModeler();
      modeler.update(
        const AdvancedPenModelerInput(
          eventType: AdvancedPenInputEventType.down,
          x: 0,
          y: 0,
          time: 0,
          pressure: 0.5,
        ),
      );
      modeler.update(
        const AdvancedPenModelerInput(
          eventType: AdvancedPenInputEventType.move,
          x: 20,
          y: 0,
          time: 1 / 60,
          pressure: 0.5,
        ),
      );
      final tail = modeler.predict();
      // Tail may be empty when already caught up; either way it must not
      // throw and a subsequent update must still work.
      expect(tail, isA<List<AdvancedPenModelerResult>>());
      final more = modeler.update(
        const AdvancedPenModelerInput(
          eventType: AdvancedPenInputEventType.move,
          x: 30,
          y: 0,
          time: 2 / 60,
          pressure: 0.5,
        ),
      );
      expect(more, isNotEmpty);
    });
  });

  group('composeAdvancedOutline', () {
    test('dot becomes a circle', () {
      final poly = composeAdvancedOutline(
        const [PointVector(10, 20, 0.5)],
        strokeWidth: 4,
        curve: AdvancedPenPressureCurve.linear,
      );
      expect(poly.length, greaterThan(8));
      // Radius ~ width*pressure/2 = 1.
      final cx = poly.map((p) => p.dx).reduce((a, b) => a + b) / poly.length;
      final cy = poly.map((p) => p.dy).reduce((a, b) => a + b) / poly.length;
      expect(cx, closeTo(10.0, 0.5));
      expect(cy, closeTo(20.0, 0.5));
    });

    test('straight stroke builds a closed ribbon', () {
      final pts = [
        for (var i = 0; i <= 10; i++) PointVector(i * 10.0, 0.0, 0.5),
      ];
      final poly = composeAdvancedOutline(
        pts,
        strokeWidth: 4,
        curve: AdvancedPenPressureCurve.linear,
      );
      expect(poly.length, greaterThan(10));
      expect(poly.first, equals(poly.last));
    });

    test('constant curve ignores pressure', () {
      final pts = [
        for (var i = 0; i <= 5; i++) PointVector(i * 10.0, 0.0, 0.1 + i * 0.15),
      ];
      final constant = composeAdvancedOutline(
        pts,
        strokeWidth: 6,
        curve: AdvancedPenPressureCurve.constant,
      );
      final linear = composeAdvancedOutline(
        pts,
        strokeWidth: 6,
        curve: AdvancedPenPressureCurve.linear,
      );
      expect(constant, isNotEmpty);
      expect(linear, isNotEmpty);
      expect(constant, isNot(equals(linear)));
    });

    test('brush options json round trip', () {
      final opts = AdvancedPenOptions.advancedDefaults();
      final restored = AdvancedPenOptions.fromJson(opts.toJson());
      expect(restored, equals(opts));
    });
  });

  group('Advanced Stroke integration', () {
    Stroke strokeForAdvanced() => Stroke(
          color: Colors.black,
          pressureEnabled: true,
          options: StrokeOptions(size: 4, simulatePressure: false),
          pageIndex: 0,
          page: HasSize(EditorPage.defaultSize),
          toolId: ToolId.advancedPen,
        );

    test('modeled stroke builds a filled ribbon path', () {
      final stroke = strokeForAdvanced();
      for (var i = 0; i <= 10; i++) {
        stroke.addPoint(
          Offset(i * 10.0, i.isEven ? 0.0 : 4.0),
          0.5,
          Duration(milliseconds: i * 16),
        );
      }
      final path = stroke.highQualityPath;
      expect(path.getBounds().isEmpty, isFalse);
      expect(path.getBounds().width, greaterThan(50));
    });

    test('stroke survives json round trip with brush options', () {
      final stroke = strokeForAdvanced();
      stroke.brushOptions.pressureCurve = AdvancedPenPressureCurve.pow2;
      stroke.brushOptions.builderType = AdvancedPenBuilderType.modeled;
      for (var i = 0; i <= 5; i++) {
        stroke.addPoint(
          Offset(i * 10.0, 0.0),
          0.6,
          Duration(milliseconds: i * 16),
        );
      }
      stroke.finishLiveGeometry();
      final json = stroke.toJson();
      expect(json['ty'], ToolId.advancedPen.id);
      expect(json['brush'], isA<Map>());
      final restored = Stroke.fromJson(
        Map<String, dynamic>.from(json.map(
          (k, v) => MapEntry(
            k.toString(),
            v is List ? List<dynamic>.from(v) : v,
          ),
        )),
        fileVersion: 99,
        pageIndex: 0,
        page: HasSize(EditorPage.defaultSize),
      );
      expect(restored.toolId, ToolId.advancedPen);
      expect(
        restored.brushOptions.pressureCurve,
        AdvancedPenPressureCurve.pow2,
      );
      expect(restored.highQualityPath.getBounds().isEmpty, isFalse);
    });
  });

  group('Advanced width topology under pressure change', () {
    List<PointVector> straightRamp({
      required int n,
      required double p0,
      required double p1,
    }) {
      return [
        for (var i = 0; i < n; i++)
          PointVector(i * 6.0, 0.0, p0 + (p1 - p0) * i / (n - 1)),
      ];
    }

    /// Effective half-width of the outline at each spine x (vertical extent
    /// of the closed polygon intersected with x = p.x, divided by two).
    List<double> halfWidthsAt(
      List<PointVector> spine, {
      double strokeWidth = 8.0,
      AdvancedPenPressureCurve curve = AdvancedPenPressureCurve.linear,
    }) {
      final outline = composeAdvancedOutline(
        spine,
        strokeWidth: strokeWidth,
        curve: curve,
      );
      expect(outline.length, greaterThan(8));
      final res = <double>[];
      for (final p in spine) {
        var top = double.infinity;
        var bottom = double.negativeInfinity;
        for (var i = 0; i < outline.length; i++) {
          final a = outline[i];
          final b = outline[(i + 1) % outline.length];
          if ((a.dx <= p.x && b.dx >= p.x) ||
              (b.dx <= p.x && a.dx >= p.x)) {
            if ((b.dx - a.dx).abs() < 1e-9) continue;
            final t = (p.x - a.dx) / (b.dx - a.dx);
            final y = a.dy + t * (b.dy - a.dy);
            if (y < top) top = y;
            if (y > bottom) bottom = y;
          }
        }
        expect(top.isFinite, isTrue, reason: 'outline covers x=${p.x}');
        res.add((bottom - top) / 2);
      }
      return res;
    }

    List<double> rawHalfWidths(
      List<PointVector> spine, {
      double strokeWidth = 8.0,
      AdvancedPenPressureCurve curve = AdvancedPenPressureCurve.linear,
    }) {
      return [
        for (final p in spine)
          curve.apply(strokeWidth, (p.pressure ?? 0.5).clamp(0.0, 1.0)) / 2,
      ];
    }

    test('steep lift-off tip matches the true tip width', () {
      final spine = straightRamp(n: 12, p0: 0.8, p1: 0.8);
      spine[10] = PointVector(spine[10].x, spine[10].y, 0.45);
      spine[11] = PointVector(spine[11].x, spine[11].y, 0.12);
      final eff = halfWidthsAt(spine);
      final raw = rawHalfWidths(spine);
      // The cap must not inflate the tip relative to the true end width.
      expect(eff.last, closeTo(raw.last, 0.05));
      expect(eff[10], closeTo(raw[10], 0.05));
    });

    test('steep pen-down tip matches the true tip width', () {
      final spine = straightRamp(n: 12, p0: 0.8, p1: 0.8);
      spine[0] = PointVector(spine[0].x, spine[0].y, 0.12);
      spine[1] = PointVector(spine[1].x, spine[1].y, 0.45);
      final eff = halfWidthsAt(spine);
      final raw = rawHalfWidths(spine);
      expect(eff.first, closeTo(raw.first, 0.05));
      expect(eff[1], closeTo(raw[1], 0.05));
    });

    test('pressure ramp stays monotone (no thin-thick wobble)', () {
      final spine = straightRamp(n: 12, p0: 0.8, p1: 0.1);
      final eff = halfWidthsAt(spine);
      for (var i = 1; i < eff.length; i++) {
        expect(eff[i], lessThanOrEqualTo(eff[i - 1] + 1e-9));
      }
    });

    test('single-sample mid spike is removed, neighbors untouched', () {
      final spine = straightRamp(n: 12, p0: 0.6, p1: 0.6);
      spine[6] = PointVector(spine[6].x, spine[6].y, 0.05);
      final eff = halfWidthsAt(spine);
      final flat = rawHalfWidths(straightRamp(n: 12, p0: 0.6, p1: 0.6));
      for (var i = 0; i < eff.length; i++) {
        expect(eff[i], closeTo(flat[i], 0.05), reason: 'i=$i');
      }
    });

    test('sharp turn with pressure drop stays a single closed outline',
        () {
      final spine = <PointVector>[
        const PointVector(0, 0, 0.8),
        const PointVector(20, 0, 0.8),
        const PointVector(40, 0, 0.7),
        const PointVector(42, 2, 0.5),
        const PointVector(40, 20, 0.3),
        const PointVector(38, 40, 0.2),
      ];
      final outline = composeAdvancedOutline(
        spine,
        strokeWidth: 8.0,
        curve: AdvancedPenPressureCurve.linear,
      );
      expect(outline.length, greaterThan(20));
      // Closed.
      expect(outline.first, equals(outline.last));
      // Every spine sample is inside its own outline.
      final path = Path()..addPolygon(outline, true);
      for (final p in spine) {
        expect(path.contains(Offset(p.x, p.y)), isTrue,
            reason: 'spine $p inside');
      }
    });
  });

  group('Advanced cap placement and smoothness', () {
    Stroke liveStroke() => Stroke(
          color: Colors.black,
          pressureEnabled: true,
          options: StrokeOptions(size: 4, simulatePressure: false),
          pageIndex: 0,
          page: HasSize(EditorPage.defaultSize),
          toolId: ToolId.advancedPen,
        );

    /// Max turning angle between consecutive outline edges in [poly[from],
    /// poly[to]]. Cap arcs and join arcs keep this near the arc step angle;
    /// anything much larger is a kink or fold.
    double maxKink(List<Offset> poly, int from, int to) {
      var worst = 0.0;
      for (var i = from; i < to && i + 2 < poly.length; i++) {
        final ax = poly[i + 1].dx - poly[i].dx;
        final ay = poly[i + 1].dy - poly[i].dy;
        final bx = poly[i + 2].dx - poly[i + 1].dx;
        final by = poly[i + 2].dy - poly[i + 1].dy;
        final la = math.sqrt(ax * ax + ay * ay);
        final lb = math.sqrt(bx * bx + by * by);
        if (la < 1e-9 || lb < 1e-9) continue;
        final dot = ((ax * bx + ay * by) / (la * lb)).clamp(-1.0, 1.0);
        final deg = math.acos(dot) * 180 / math.pi;
        if (deg > worst) worst = deg;
      }
      return worst;
    }

    test('jittered put-down cap follows travel, mouth without kink', () {
      final stroke = liveStroke();
      const pts = [
        Offset(0, 0),
        Offset(3, 3),
        Offset(8, 0),
        Offset(16, 0),
        Offset(100, 0),
      ];
      for (var i = 0; i < pts.length; i++) {
        stroke.addPoint(pts[i], 0.7, Duration(milliseconds: i * 8));
      }
      final poly = stroke.highQualityPolygon;
      // Nominal radius 4*0.7/2 = 1.4: the cap must reach nearly full extent
      // behind the tip (a 46-degree-rotated cap would only reach ~-0.97).
      final minX = poly.map((p) => p.dx).reduce(math.min);
      expect(minX, lessThan(-1.2));
      // Mouth region (cap arc + first rail edges) stays near arc faceting.
      expect(maxKink(poly, 0, 40), lessThan(12.0));
    });

    test('straight cap arc faceting stays bounded', () {
      final stroke = liveStroke();
      for (var i = 0; i <= 10; i++) {
        stroke.addPoint(
            Offset(i * 10.0, 0.0), 0.7, Duration(milliseconds: i * 8));
      }
      stroke.finishLiveGeometry();
      final poly = stroke.highQualityPolygon;
      expect(
        maxKink(poly, 0, poly.length ~/ 4),
        lessThan(9.0),
        reason: 'cap arc edges turn smoothly',
      );
    });
  });
}
