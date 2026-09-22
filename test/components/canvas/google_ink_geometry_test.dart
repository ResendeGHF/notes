// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/stroke_geometry/google_ink_geometry.dart';
import 'package:saber/data/stroke_geometry/point_vector.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/google_ink_brush.dart';
import 'package:saber/data/tools/pen.dart';

EditorPage _testPage() => EditorPage();

/// Shoelace area (absolute) of an unclosed outline polygon.
double _polyArea(List<Offset> poly) {
  if (poly.length < 3) return 0;
  var s = 0.0;
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % poly.length];
    s += a.dx * b.dy - b.dx * a.dy;
  }
  return s.abs() / 2;
}

double _segSide(Offset o, Offset x, Offset y) =>
    (x.dx - o.dx) * (y.dy - o.dy) - (x.dy - o.dy) * (y.dx - o.dx);

bool _segmentsCrossStrict(Offset a1, Offset a2, Offset b1, Offset b2) {
  final d1 = _segSide(b1, b2, a1);
  final d2 = _segSide(b1, b2, a2);
  final d3 = _segSide(a1, a2, b1);
  final d4 = _segSide(a1, a2, b2);
  return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
      ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
}

/// Proper (interior) self-intersections of a closed outline. Adjacent edges
/// and shared endpoints do not count: any crossing found here is a bow-tie
/// whose nonzero winding cancels fill into a hole.
int _selfIntersections(List<Offset> poly) {
  var n = 0;
  for (var i = 0; i < poly.length; i++) {
    final a1 = poly[i];
    final a2 = poly[(i + 1) % poly.length];
    for (var j = i + 2; j < poly.length; j++) {
      if (i == 0 && j == poly.length - 1) continue; // closure neighbors
      if (_segmentsCrossStrict(a1, a2, poly[j], poly[(j + 1) % poly.length])) {
        n++;
      }
    }
  }
  return n;
}

void main() {
  group('GoogleInk geometry (experimental pen, no perfect_freehand)', () {
    test('families produce distinct looks', () {
      final spine = List<PointVector>.generate(
        24,
        (i) => PointVector(i * 8.0, i * 3.0, 0.3 + 0.5 * (i / 24)),
      );
      final areas = <String, double>{};
      for (final family in GoogleInkBrushFamily.values) {
        // Dashed paints disjoint ovals (see dedicated test); its ribbon
        // stand-in is marker-like by construction.
        if (family == GoogleInkBrushFamily.dashedLine) continue;
        final cfg = GoogleInkBrushConfig(
          family: family,
          size: 6,
          epsilon: 0.1,
        );
        final poly = buildGoogleInkPolygon(spine, cfg, isComplete: true);
        expect(poly.length, greaterThan(4), reason: '${family.id} polygon');
        areas[family.id] = _polyArea(poly);
      }
      // Pressure ramp vs constant marker vs nib projection must differ.
      expect(areas.values.toSet().length, greaterThan(1));
    });

    test('start/end caps are solid (no holes at tips)', () {
      // Straight stroke: the caps must cover the spine tips. A cap fanned to
      // the inner side folds over the ribbon (bow-tie) and leaves the tip
      // outside the fill — the reported "buraco" at start/end points.
      final spine = List<PointVector>.generate(
        16,
        (i) => PointVector(i * 8.0, 0.0, 0.6),
      );
      for (final family in [
        GoogleInkBrushFamily.pressurePen,
        GoogleInkBrushFamily.marker,
        GoogleInkBrushFamily.highlighter,
        GoogleInkBrushFamily.brush,
        GoogleInkBrushFamily.calligraphy,
      ]) {
        final cfg = GoogleInkBrushConfig(family: family, size: 8);
        final path = buildGoogleInkPath(spine, cfg, isComplete: true);
        expect(
          path.contains(const Offset(-1.5, 0)),
          isTrue,
          reason: '${family.id} start cap covers behind tip',
        );
        expect(
          path.contains(const Offset(121.5, 0)),
          isTrue,
          reason: '${family.id} end cap covers ahead of tip',
        );
        expect(
          path.contains(const Offset(60, 0)),
          isTrue,
          reason: '${family.id} covers spine middle',
        );
      }
    });

    test('ribbon outlines never self-intersect (ink always adds)', () {
      // Bow-ties cancel nonzero fill into erased patches — both at caps and
      // where calligraphy orientation opposes the motion.
      final straight = List<PointVector>.generate(
        16,
        (i) => PointVector(i * 8.0, 0.0, 0.6),
      );
      final zigzag = List<PointVector>.generate(
        25,
        (i) => PointVector(i * 10.0, (i.isEven ? 1.0 : -1.0) * 20.0, 0.6),
      );
      final circle = List<PointVector>.generate(
        33,
        (i) {
          final a = (i / 32) * math.pi * 2;
          return PointVector(
            (100 + 40 * math.cos(a)).toDouble(),
            (100 + 40 * math.sin(a)).toDouble(),
            0.6,
          );
        },
      );
      // Hairpin fold: outbound and return overlap — overlap must ADD ink
      // (same winding), never carve a hole.
      final hairpin = <PointVector>[
        for (var i = 0; i <= 8; i++) PointVector(i * 8.0, 0.0, 0.6),
        for (var i = 8; i >= 0; i--) PointVector(i * 8.0, 4.0, 0.6),
      ];
      for (final family in [
        GoogleInkBrushFamily.pressurePen,
        GoogleInkBrushFamily.marker,
        GoogleInkBrushFamily.highlighter,
        GoogleInkBrushFamily.brush,
        GoogleInkBrushFamily.calligraphy,
      ]) {
        final cfg = GoogleInkBrushConfig(family: family, size: 8);
        for (final entry in {
          'straight': straight,
          'zigzag': zigzag,
          'circle': circle,
          'hairpin': hairpin,
        }.entries) {
          final poly = buildGoogleInkPolygon(
            entry.value,
            cfg,
            isComplete: true,
          );
          expect(
            _selfIntersections(poly),
            0,
            reason: '${family.id} ${entry.key} outline is simple',
          );
        }
      }
    });

    test('calligraphy nib stays oriented without erasing', () {
      // Nib edge at -40°: a stroke along the edge must be much wider than one
      // across it, and both must cover their own spines (no winding-0 gaps).
      List<PointVector> along(double len) => List<PointVector>.generate(
            16,
            (i) => PointVector(
              (i * len / 15) * 0.7660423023038937,
              (i * len / 15) * -0.6427878083091681,
              0.6,
            ),
          );
      List<PointVector> across(double len) => List<PointVector>.generate(
            16,
            (i) => PointVector(
              (i * len / 15) * 0.6427878083091681,
              (i * len / 15) * 0.7660423023038937,
              0.6,
            ),
          );
      final cfg = GoogleInkBrushConfig(
        family: GoogleInkBrushFamily.calligraphy,
        size: 8,
      );
      final areaAlong = _polyArea(buildGoogleInkPolygon(along(120), cfg));
      final areaAcross = _polyArea(buildGoogleInkPolygon(across(120), cfg));
      expect(areaAlong, greaterThan(areaAcross * 3));
      for (final spine in [along(120), across(120)]) {
        final path = buildGoogleInkPath(spine, cfg);
        for (var i = 0; i < spine.length; i += 3) {
          expect(
            path.contains(Offset(spine[i].x, spine[i].y)),
            isTrue,
            reason: 'nib covers its own spine (sample $i)',
          );
        }
      }
    });

    test('dashed paints disjoint ovals, not a bridged polygon', () {
      final spine = List<PointVector>.generate(
        40,
        (i) => PointVector(i * 5.0, 0.0, 0.6),
      );
      final cfg = GoogleInkBrushConfig(
        family: GoogleInkBrushFamily.dashedLine,
        size: 8,
      );
      final path = buildGoogleInkPath(spine, cfg, isComplete: true);
      final contours = path.computeMetrics().length;
      expect(contours, greaterThan(1), reason: 'one contour per dot');
      expect(path.contains(const Offset(0, 0)), isTrue);
      // Ribbon stand-in (hit-test/culling/export approx) still builds.
      expect(
        buildGoogleInkPolygon(spine, cfg, isComplete: true).length,
        greaterThan(4),
      );
    });

    test('epsilon controls decimation', () {
      final spine = List<PointVector>.generate(
        40,
        (i) => PointVector(i * 5.0, (i % 2) * 0.4, 0.5),
      );
      final fine = buildGoogleInkPolygon(
        spine,
        GoogleInkBrushConfig(epsilon: 0.01),
        isComplete: true,
      );
      final coarse = buildGoogleInkPolygon(
        spine,
        GoogleInkBrushConfig(epsilon: 1.0),
        isComplete: true,
      );
      expect(fine.length, greaterThanOrEqualTo(coarse.length));
    });

    test('experimental stroke uses google-ink path + persists brush', () {
      final page = _testPage();
      final pen = Pen.experimental();
      pen.inkBrush.family = GoogleInkBrushFamily.marker;
      pen.inkBrush.epsilon = 0.2;
      pen.inkBrush.size = 6;
      pen.options.size = 6;
      pen.onDragStart(
        const Offset(10, 10),
        page,
        0,
        0.6,
        const Duration(milliseconds: 0),
      );
      for (var i = 1; i < 12; i++) {
        pen.onDragUpdate(
          Offset(10 + i * 9.0, 10 + i * 4.0),
          0.6,
          Duration(milliseconds: i * 16),
        );
      }
      final stroke = pen.onDragEnd()!;
      expect(stroke.toolId, ToolId.experimentalPen);
      expect(stroke.googleInkFamily, 'marker');
      expect(stroke.highQualityPolygon.length, greaterThan(4));
      // Path-only like Advanced Pen: no batched mesh, but raster LOD still
      // bakes the vector path (canBatch false, vertices null).
      expect(stroke.canBatchSolidMesh, isFalse);
      expect(stroke.vertices, isNull);

      final json = stroke.toJson();
      expect(json['giF'], 'marker');
      final restored = Stroke.fromJson(
        Map<String, dynamic>.from(json),
        fileVersion: 99,
        pageIndex: 0,
        page: _testPage(),
      );
      expect(restored.toolId, ToolId.experimentalPen);
      expect(restored.googleInkFamily, 'marker');
      expect(restored.googleInkEpsilon, closeTo(0.2, 1e-6));
      expect(restored.highQualityPolygon.length, greaterThan(4));
    });

    test('smoothing window changes output', () {
      final spine = List<PointVector>.generate(
        20,
        (i) => PointVector(i * 7.0, (i.isEven ? 1.0 : -1.0) * 2.0, 0.5),
      );
      final sharp = buildGoogleInkPolygon(
        spine,
        GoogleInkBrushConfig(smoothingWindowMs: 0),
        isComplete: true,
      );
      final smooth = buildGoogleInkPolygon(
        spine,
        GoogleInkBrushConfig(smoothingWindowMs: 64),
        isComplete: true,
      );
      // Smoothed zigzag must stay a valid closed outline.
      expect(sharp.length, greaterThan(4));
      expect(smooth.length, greaterThan(4));
      expect(sharp, isNot(equals(smooth)));
    });
  });
}
