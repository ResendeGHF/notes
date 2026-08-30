// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:saber/components/canvas/_shape_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/binary_writer.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/shape_geometry.dart';
import 'package:saber/data/tools/shape_recognition.dart';
import 'package:saber/data/tools/shape_tool.dart';

HasSize _page([Size size = EditorPage.defaultSize]) => HasSize(size);

Stroke _strokeFromPoints(List<Offset> points) {
  final page = _page();
  final stroke = Stroke(
    color: Colors.black,
    pressureEnabled: false,
    options: StrokeOptions(
      size: 3,
      simulatePressure: false,
      isComplete: true,
    ),
    pageIndex: 0,
    page: page,
    toolId: ToolId.fountainPen,
  );
  for (final p in points) {
    stroke.points.add(PointVector(p.dx, p.dy, 0.5));
  }
  stroke.markPolygonNeedsUpdating();
  return stroke;
}

RecognizedUnistroke _detected(
  DefaultUnistrokeNames name,
  List<Offset> points,
) {
  return RecognizedUnistroke(
    name,
    0.9,
    originalPoints: points,
    referenceUnistrokes: const [],
  );
}

ShapeStroke _triangleStroke() {
  final verts = <Offset>[
    const Offset(100, 40),
    const Offset(40, 160),
    const Offset(160, 160),
  ];
  final config = ShapeGeometry.withControlPoints(
    ShapeConfig(
      kind: ShapeKind.triangleIsosceles,
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
  group('ShapeGeometry fitters', () {
    test('ellipse fitter recovers center/axes from noisy ellipse points', () {
      const center = Offset(120, 80);
      const rx = 50.0;
      const ry = 30.0;
      const angle = 0.35;
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);
      final rng = math.Random(7);
      final points = <Offset>[];
      for (var i = 0; i < 48; i++) {
        final t = 2 * math.pi * i / 48;
        final lx = rx * math.cos(t) + (rng.nextDouble() - 0.5) * 1.5;
        final ly = ry * math.sin(t) + (rng.nextDouble() - 0.5) * 1.5;
        points.add(
          Offset(
            center.dx + lx * cosA - ly * sinA,
            center.dy + lx * sinA + ly * cosA,
          ),
        );
      }

      final fit = ShapeGeometry.fitEllipse(points);
      expect(fit, isNotNull);
      expect(fit!.kind, ShapeKind.ellipse);
      final params = ShapeGeometry.ellipseParamsFromControlPoints(fit.vertices!);
      expect(params, isNotNull);
      expect((params!.center - center).distance, lessThan(8));
      expect((params.rx - rx).abs(), lessThan(8));
      expect((params.ry - ry).abs(), lessThan(8));
      var dang = (params.angleRad - angle);
      while (dang > math.pi / 2) {
        dang -= math.pi;
      }
      while (dang < -math.pi / 2) {
        dang += math.pi;
      }
      expect(dang.abs(), lessThan(0.08)); // ~4.5°
      expect(fit.vertices!.length, 3);
    });

    test('ellipse angle stays accurate with uneven freehand-like sampling', () {
      const center = Offset(200, 150);
      const rx = 70.0;
      const ry = 28.0;
      const angle = -0.55; // ~-31.5°
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);
      final rng = math.Random(3);
      final points = <Offset>[];
      // Cluster more samples near the ends of the major axis (common freehand bias).
      for (var i = 0; i < 60; i++) {
        final u = rng.nextDouble();
        final t = (u < 0.55)
            ? (rng.nextBool() ? 0.0 : math.pi) + (rng.nextDouble() - 0.5) * 0.7
            : 2 * math.pi * rng.nextDouble();
        final lx = rx * math.cos(t) + (rng.nextDouble() - 0.5) * 2.0;
        final ly = ry * math.sin(t) + (rng.nextDouble() - 0.5) * 2.0;
        points.add(
          Offset(
            center.dx + lx * cosA - ly * sinA,
            center.dy + lx * sinA + ly * cosA,
          ),
        );
      }

      final fit = ShapeGeometry.fitEllipseAlgebraic(points);
      expect(fit, isNotNull);
      var dang = fit!.angleRad - angle;
      while (dang > math.pi / 2) {
        dang -= math.pi;
      }
      while (dang < -math.pi / 2) {
        dang += math.pi;
      }
      expect(dang.abs(), lessThan(0.12)); // ~7°
    });

    test('round stroke fits as an ellipse with equal axes', () {
      const center = Offset(100, 100);
      const r = 40.0;
      final points = <Offset>[
        for (var i = 0; i < 36; i++)
          Offset(
            center.dx + r * math.cos(2 * math.pi * i / 36),
            center.dy + r * math.sin(2 * math.pi * i / 36),
          ),
      ];
      final fit = ShapeGeometry.fitEllipse(points);
      expect(fit, isNotNull);
      expect(fit!.kind, ShapeKind.ellipse);
      final params = ShapeGeometry.ellipseParamsFromControlPoints(fit.vertices!);
      expect(params, isNotNull);
      expect((params!.rx - r).abs(), lessThan(3));
      expect((params.ry - r).abs(), lessThan(3));
    });

    test('ellipse foci drag keeps other focus when moving tip', () {
      final cps = ShapeGeometry.ellipseControlPoints(
        const Offset(100, 80),
        50,
        30,
        0.2,
      );
      final base = ShapeGeometry.withControlPoints(
        ShapeConfig(kind: ShapeKind.ellipse, bounds: ShapeGeometry.boundsOf(cps)),
        cps,
      );
      final moved = ShapeGeometry.moveEllipseControlPoint(
        base,
        2,
        cps[2] + const Offset(20, 0),
      );
      expect(moved.vertices!.length, 3);
      // Foci stay on same line through center (angle preserved-ish).
      final p = ShapeGeometry.ellipseParamsFromControlPoints(moved.vertices!);
      expect(p, isNotNull);
      expect(p!.rx, greaterThan(50));
    });

    test('triangle fitter recovers three freehand corners', () {
      const a = Offset(50, 30);
      const b = Offset(20, 140);
      const c = Offset(170, 150);
      final points = <Offset>[
        a,
        Offset.lerp(a, b, 0.33)!,
        Offset.lerp(a, b, 0.66)!,
        b,
        Offset.lerp(b, c, 0.33)!,
        Offset.lerp(b, c, 0.66)!,
        c,
        Offset.lerp(c, a, 0.33)!,
        Offset.lerp(c, a, 0.66)!,
        a,
      ];

      final corners = ShapeGeometry.fitTriangleCorners(points);
      expect(corners, isNotNull);
      expect(corners!.length, 3);

      final expected = [a, b, c];
      for (final e in expected) {
        final nearest = corners
            .map((p) => (p - e).distance)
            .reduce(math.min);
        expect(nearest, lessThan(8));
      }
    });

    test('line fitter returns two endpoints near chord', () {
      final points = [
        for (var i = 0; i <= 20; i++) Offset(10.0 + i * 5, 40.0 + i * 2),
      ];
      final cfg = ShapeGeometry.fitLine(points);
      expect(cfg, isNotNull);
      expect(cfg!.vertices, isNotNull);
      expect(cfg.vertices!.length, 2);
      expect((cfg.vertices!.first - points.first).distance, lessThan(6));
      expect((cfg.vertices!.last - points.last).distance, lessThan(6));
    });
  });

  group('ShapeStroke control points', () {
    test('moving one triangle vertex leaves others fixed', () {
      final stroke = _triangleStroke();
      final before = List<Offset>.from(stroke.controlPoints);
      expect(before.length, 3);

      final moved = List<Offset>.from(before);
      moved[1] = const Offset(10, 200);
      final updated = ShapeGeometry.withControlPoints(stroke.config, moved);
      stroke.config = updated;

      final after = stroke.controlPoints;
      expect(after.length, 3);
      expect(after[0], before[0]);
      expect(after[2], before[2]);
      expect(after[1], const Offset(10, 200));
      expect(
        stroke.config.bounds.inflate(0.01).contains(after[1]),
        isTrue,
      );
    });

    test('JSON round-trip preserves vertices', () {
      final stroke = _triangleStroke();
      final json = stroke.toJson();
      final loaded = ShapeStroke.fromJson(
        json,
        page: _page(),
        pageIndex: 0,
        fileVersion: 19,
      );
      expect(loaded.controlPoints.length, stroke.controlPoints.length);
      for (var i = 0; i < stroke.controlPoints.length; i++) {
        expect(
          (loaded.controlPoints[i] - stroke.controlPoints[i]).distance,
          lessThan(0.5),
        );
      }
      expect(loaded.config.kind, ShapeKind.triangleIsosceles);
    });

    test('binary round-trip preserves vertices', () {
      final stroke = _triangleStroke();
      final writer = BinaryWriter();
      stroke.toBinary(writer);
      final reader = BinaryReader(writer.toBytes());
      final loaded = Stroke.fromBinary(
        reader,
        fileVersion: 19,
        page: _page(),
      );
      expect(loaded, isA<ShapeStroke>());
      final shape = loaded as ShapeStroke;
      expect(shape.controlPoints.length, stroke.controlPoints.length);
      for (var i = 0; i < stroke.controlPoints.length; i++) {
        expect(
          (shape.controlPoints[i] - stroke.controlPoints[i]).distance,
          lessThan(0.5),
        );
      }
    });
  });

  group('Recognition classify+fit', () {
    test('returns ShapeStroke for line/rect/ellipse/triangle', () {
      final linePts = [
        for (var i = 0; i <= 10; i++) Offset(i * 10.0, 50.0),
      ];
      final rectPts = <Offset>[
        const Offset(10, 10),
        const Offset(110, 10),
        const Offset(110, 70),
        const Offset(10, 70),
        const Offset(10, 10),
      ];
      final ellipsePts = <Offset>[
        for (var i = 0; i < 36; i++)
          Offset(
            80 + 40 * math.cos(2 * math.pi * i / 36),
            60 + 25 * math.sin(2 * math.pi * i / 36),
          ),
      ];
      final triPts = <Offset>[
        const Offset(100, 20),
        const Offset(40, 70),
        const Offset(30, 130),
        const Offset(100, 150),
        const Offset(170, 130),
        const Offset(160, 70),
        const Offset(100, 20),
      ];

      final cases = <(DefaultUnistrokeNames, List<Offset>, ShapeKind)>[
        (DefaultUnistrokeNames.line, linePts, ShapeKind.line),
        (DefaultUnistrokeNames.rectangle, rectPts, ShapeKind.rectangle),
        (DefaultUnistrokeNames.circle, ellipsePts, ShapeKind.ellipse),
        (DefaultUnistrokeNames.triangle, triPts, ShapeKind.triangleIsosceles),
      ];

      for (final (name, pts, kind) in cases) {
        final raw = _strokeFromPoints(pts);
        final out = convertStrokeToShapeStroke(raw, _detected(name, pts));
        expect(out, isA<ShapeStroke>(), reason: '$name should be ShapeStroke');
        final shape = out as ShapeStroke;
        expect(shape.controlPoints, isNotEmpty, reason: '$name control points');
        expect(shape.config.kind, kind);
        if (shape.config.kind == ShapeKind.ellipse) {
          expect(shape.controlPoints.length, 3);
        }
      }
    });
  });
}
