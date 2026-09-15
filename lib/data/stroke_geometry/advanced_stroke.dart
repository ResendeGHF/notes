// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:saber/data/stroke_geometry/point_vector.dart';

/// EMA streamline of input samples (Advanced pen / freehand feel).
List<PointVector> streamlinePoints(
  List<PointVector> points, {
  required double streamline,
}) {
  if (points.length < 2 || streamline <= 0) return points;
  final keep = (1.0 - streamline.clamp(0.0, 0.95));
  final out = <PointVector>[points.first];
  var px = points.first.x;
  var py = points.first.y;
  for (var i = 1; i < points.length; i++) {
    final p = points[i];
    px += (p.x - px) * keep;
    py += (p.y - py) * keep;
    out.add(PointVector(px, py, p.pressure));
  }
  // Always keep the latest raw tip so drawing feels responsive.
  if (out.length >= 2) {
    final last = points.last;
    out[out.length - 1] = PointVector(last.x, last.y, last.pressure);
  }
  return out;
}

/// Synthesize pressure from inverse speed (when stylus has no pressure).
List<PointVector> bakeSimulatedPressure(
  List<PointVector> points, {
  double sensitivity = 1.0,
  bool stabilizeStart = true,
  bool stabilizeEnd = true,
}) {
  if (points.length < 2) return points;
  final sens = sensitivity.clamp(0.1, 3.0);
  final out = <PointVector>[];
  for (var i = 0; i < points.length; i++) {
    final prev = points[i == 0 ? 0 : i - 1];
    final next = points[i == points.length - 1 ? i : i + 1];
    final dx = next.x - prev.x;
    final dy = next.y - prev.y;
    final speed = math.sqrt(dx * dx + dy * dy);
    // Slow → thick (high pressure); fast → thin.
    final raw = 1.0 / (1.0 + speed * 0.08 * sens);
    final pressure = (0.2 + 0.8 * raw).clamp(0.05, 1.0);
    out.add(PointVector(points[i].x, points[i].y, pressure));
  }
  return stabilizeAdvancedTipPressures(
    out,
    stabilizeStart: stabilizeStart,
    stabilizeEnd: stabilizeEnd,
  );
}

/// Softens tip pressure spikes the way fountain mesh caps do, so Advanced
/// round caps and return bulbs stay smooth instead of pinching or flaring.
List<PointVector> stabilizeAdvancedTipPressures(
  List<PointVector> points, {
  bool stabilizeStart = true,
  bool stabilizeEnd = true,
}) {
  if (points.length < 3) return points;
  final out = List<PointVector>.of(points);
  const w = 4;
  var n0 = 0;
  var s0 = 0.0;
  for (var i = 1; i < out.length && i <= w; i++) {
    s0 += out[i].pressure ?? 0.5;
    n0++;
  }
  var n1 = 0;
  var s1 = 0.0;
  for (var i = out.length - 2; i >= 0 && n1 < w; i--) {
    s1 += out[i].pressure ?? 0.5;
    n1++;
  }
  if (stabilizeStart && n0 > 0) {
    final ref = s0 / n0;
    final p0 = out.first.pressure ?? 0.5;
    out[0] = PointVector(
      out[0].x,
      out[0].y,
      (p0 * 0.28 + ref * 0.72).clamp(0.05, 1.0),
    );
  }
  if (stabilizeEnd && n1 > 0) {
    final ref = s1 / n1;
    final pN = out.last.pressure ?? 0.5;
    final last = out.length - 1;
    out[last] = PointVector(
      out[last].x,
      out[last].y,
      (pN * 0.28 + ref * 0.72).clamp(0.05, 1.0),
    );
  }
  return out;
}
