// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:saber/data/stroke_geometry/point_vector.dart' show PointVector;
import 'package:saber/data/tools/google_ink_brush.dart';

/// Dart fallback for the Google Ink stroke pipeline.
///
/// Deliberately independent from `perfect_freehand` (`getStroke`): it mirrors
/// the native stack at test fidelity —
/// 1. sliding-window input model (time-based averaging, like
///    `BrushFamily.InputModel.SlidingWindowModel`),
/// 2. family-specific tip mapping (round pressure pen / flat marker /
///    translucent highlighter / angled calligraphy nib),
/// 3. epsilon decimation (like `Brush.epsilon` geometry fidelity).
///
/// The native `InProgressStrokesView` does (1)+(2) at 120Hz+ with shaders;
/// this port exists so committed experimental strokes paint identically on
/// every platform (iOS / desktop / tests) and flow through the same tiled
/// Picture + temporary-raster LOD path as all other ink.

/// Time-weighted sliding average over raw samples. Window in seconds.
List<PointVector> googleInkSmoothSpine(
  List<PointVector> input, {
  double windowSec = 0.016,
  List<double>? timesSec,
}) {
  if (input.length < 3 || windowSec <= 0) return input;
  // Without timestamps assume ~60Hz spacing.
  final t = timesSec ??
      List<double>.generate(input.length, (i) => i / 60.0);
  final out = <PointVector>[];
  var accX = 0.0;
  var accY = 0.0;
  var accP = 0.0;
  var accW = 0.0;
  var start = 0;
  for (var i = 0; i < input.length; i++) {
    final ti = t[i];
    while (start < i && ti - t[start] > windowSec) {
      start++;
    }
    // Recompute window average (windows are tiny; clarity > micro-opt).
    accX = 0;
    accY = 0;
    accP = 0;
    accW = 0;
    for (var j = start; j <= i; j++) {
      // Newer samples weigh more (triangular kernel toward the tip).
      final w = 1.0 + (j - start);
      accX += input[j].x * w;
      accY += input[j].y * w;
      accP += (input[j].pressure ?? 0.5) * w;
      accW += w;
    }
    out.add(PointVector(accX / accW, accY / accW, accP / accW));
  }
  return out;
}

/// Ramer-Douglas-Peucker decimation driven by Brush.epsilon.
List<PointVector> googleInkDecimate(
  List<PointVector> points, {
  double epsilon = 0.1,
}) {
  if (points.length < 3 || epsilon <= 0) return points;
  final keep = List<bool>.filled(points.length, false);
  keep[0] = true;
  keep[points.length - 1] = true;
  final stack = <int>[0, points.length - 1];
  final epsSq = epsilon * epsilon;
  while (stack.isNotEmpty) {
    final end = stack.removeLast();
    final start = stack.removeLast();
    if (end - start < 2) continue;
    double maxD = 0;
    var idx = start;
    final ax = points[start].x;
    final ay = points[start].y;
    final bx = points[end].x;
    final by = points[end].y;
    final dx = bx - ax;
    final dy = by - ay;
    final magSq = dx * dx + dy * dy;
    for (var i = start + 1; i < end; i++) {
      double d;
      if (magSq == 0) {
        final px = points[i].x - ax;
        final py = points[i].y - ay;
        d = px * px + py * py;
      } else {
        final u = ((points[i].x - ax) * dx + (points[i].y - ay) * dy) / magSq;
        final c = u.clamp(0.0, 1.0);
        final qx = ax + c * dx - points[i].x;
        final qy = ay + c * dy - points[i].y;
        d = qx * qx + qy * qy;
      }
      if (d > maxD) {
        maxD = d;
        idx = i;
      }
    }
    if (maxD > epsSq) {
      keep[idx] = true;
      stack.addAll([start, idx, idx, end]);
    }
  }
  final out = <PointVector>[];
  for (var i = 0; i < points.length; i++) {
    if (keep[i]) out.add(points[i]);
  }
  return out;
}

double _widthAt(
  GoogleInkBrushConfig cfg,
  double pressure, {
  double velocityNorm = 0.0,
  double tiltRad = 0.0,
}) {
  final p = (pressure.isFinite ? pressure : 0.5).clamp(0.0, 1.0);
  final sens = cfg.pressureSensitivity.clamp(0.0, 2.0);
  // Map stylus pressure [0..1] around 0.5 center so light touches thin out.
  final pm = (0.5 + (p - 0.5) * sens).clamp(0.0, 1.0);
  final minW = cfg.size * cfg.minSizeRatio.clamp(0.01, 1.0);
  final maxW = cfg.size * cfg.maxSizeRatio.clamp(0.2, 2.0);
  switch (cfg.family) {
    case GoogleInkBrushFamily.marker:
    case GoogleInkBrushFamily.dashedLine:
      return cfg.size;
    case GoogleInkBrushFamily.highlighter:
      return cfg.size;
    case GoogleInkBrushFamily.calligraphy:
      // Flat nib: tilt opens the edge, pressure adds weight.
      final tiltGain = 1.0 + cfg.tiltResponse * tiltRad.clamp(0.0, 1.2);
      return (minW + (maxW - minW) * (0.35 + 0.65 * pm)) * tiltGain;
    case GoogleInkBrushFamily.brush:
      // Soft brush: strong pressure + velocity swell.
      final v = velocityNorm.clamp(0.0, 1.0);
      final w = minW +
          (maxW - minW) * (pm * (1.0 - 0.5 * cfg.velocityResponse * v));
      return w.clamp(minW, maxW * 1.15);
    case GoogleInkBrushFamily.pressurePen:
      final v = velocityNorm.clamp(0.0, 1.0);
      final thin = cfg.velocityResponse * v * 0.45;
      final w = minW + (maxW - minW) * (pm * (1.0 - thin));
      return w.clamp(minW, maxW);
  }
}

/// Smoothed + decimated spine shared by the ribbon and dash builders.
List<PointVector> _inkSpine(
  List<PointVector> rawPoints,
  GoogleInkBrushConfig cfg, {
  List<double>? timesSec,
}) {
  var spine = googleInkSmoothSpine(
    rawPoints,
    windowSec: (cfg.smoothingWindowMs / 1000.0).clamp(0.0, 0.12),
    timesSec: timesSec,
  );
  return googleInkDecimate(spine, epsilon: cfg.epsilon.clamp(0.01, 1.0));
}

/// Builds the closed outline polygon for an experimental (Google Ink) stroke.
///
/// Returns outline points (left side forward + round-cap fans + right side
/// reversed). Renders with `Path.addPolygon(closed)` / nonZero fill — same
/// contract as the other outline pens, so batching, tiling and raster LOD
/// treat it identically.
///
/// NOTE: this is only the ribbon representation. The dashed family paints via
/// [buildGoogleInkPath] (separate ovals — a single concatenated polygon would
/// bridge the dots with bow-ties whose winding cancels out).
List<Offset> buildGoogleInkPolygon(
  List<PointVector> rawPoints,
  GoogleInkBrushConfig cfg, {
  List<double>? timesSec,
  List<double>? tiltsRad,
  bool isComplete = true,
}) {
  if (rawPoints.isEmpty) return const [];
  if (rawPoints.length == 1) {
    final p = rawPoints.first;
    final r = _widthAt(cfg, p.pressure ?? 0.5) / 2;
    return _circlePolygon(Offset(p.x, p.y), r);
  }
  final spine = _inkSpine(rawPoints, cfg, timesSec: timesSec);
  if (spine.length < 2) {
    final p = spine.first;
    return _circlePolygon(
      Offset(p.x, p.y),
      _widthAt(cfg, p.pressure ?? 0.5) / 2,
    );
  }

  // Velocity per sample for velocity-thinning (normalized exponentially).
  final speeds = List<double>.filled(spine.length, 0);
  if (timesSec != null && timesSec.length == rawPoints.length) {
    // Resample speeds roughly: use raw spacing (good enough for tests).
    for (var i = 1; i < spine.length; i++) {
      final dx = spine[i].x - spine[i - 1].x;
      final dy = spine[i].y - spine[i - 1].y;
      speeds[i] = math.sqrt(dx * dx + dy * dy);
    }
  } else {
    for (var i = 1; i < spine.length; i++) {
      final dx = spine[i].x - spine[i - 1].x;
      final dy = spine[i].y - spine[i - 1].y;
      speeds[i] = math.sqrt(dx * dx + dy * dy);
    }
  }
  double maxS = 0;
  for (final s in speeds) {
    if (s > maxS) maxS = s;
  }
  if (maxS < 1e-6) maxS = 1;

  final isNib = cfg.family.isNib;
  // Nib edge direction (unit, screen coords). Broad-nib physics live in the
  // per-sample loop: width follows the travel/edge projection while the
  // offset itself always rides the *travel* normal.
  const nibAngle = -40 * math.pi / 180;
  final edgeDx = math.cos(nibAngle);
  final edgeDy = math.sin(nibAngle);

  /// Travel direction at [i] (central differences). Never degenerate: falls
  /// back to the nearest valid chord so duplicate samples cannot collapse
  /// the ribbon into a bow-tie.
  Offset travelAt(int i) {
    PointVector a = spine[math.max(0, i - 1)];
    PointVector b = spine[math.min(spine.length - 1, i + 1)];
    var dx = b.x - a.x;
    var dy = b.y - a.y;
    var len = math.sqrt(dx * dx + dy * dy);
    if (len >= 1e-6) return Offset(dx / len, dy / len);
    for (var k = 2; k < spine.length; k++) {
      a = spine[math.max(0, i - k)];
      b = spine[math.min(spine.length - 1, i + k)];
      dx = b.x - a.x;
      dy = b.y - a.y;
      len = math.sqrt(dx * dx + dy * dy);
      if (len >= 1e-6) return Offset(dx / len, dy / len);
    }
    return const Offset(1, 0);
  }

  final left = <Offset>[];
  final right = <Offset>[];
  for (var i = 0; i < spine.length; i++) {
    final p = spine[i];
    final v = (speeds[i] / maxS).clamp(0.0, 1.0);
    final tilt = (tiltsRad != null && i < tiltsRad.length)
        ? tiltsRad[i]
        : 0.0;
    var w = _widthAt(
      cfg,
      p.pressure ?? 0.5,
      velocityNorm: v,
      tiltRad: tilt,
    ) / 2;

    final t = travelAt(i);
    if (isNib) {
      // Flat nib: project the width onto the travel direction — full nib
      // width when moving along the edge, hairline floor when moving across
      // it. Offsetting along the travel normal (instead of a fixed nib
      // normal) keeps the ribbon a simple loop: hairpin folds overlap with
      // the same winding (added ink) instead of bow-tying into winding-0
      // holes that erase ink where orientations oppose.
      final proj = (t.dx * edgeDx + t.dy * edgeDy).abs().clamp(0.0, 1.0);
      w *= 0.18 + 0.82 * proj;
    }
    final nx = -t.dy;
    final ny = t.dx;
    final lo = Offset(p.x + nx * w, p.y + ny * w);
    final ro = Offset(p.x - nx * w, p.y - ny * w);
    // Collapse inner-corner spikes: on turns tighter than half the width the
    // inner offset retreats (dot < 0), looping back over itself — a pinhole
    // bow-tie. Skipping the retreating point bevels the corner instead. The
    // outer side always advances, so only the inner side can trigger this.
    // First/last are always kept (caps anchor on them).
    if (i == 0 || i == spine.length - 1) {
      left.add(lo);
      right.add(ro);
    } else {
      final lp = left.last;
      final rp = right.last;
      if ((lo.dx - lp.dx) * t.dx + (lo.dy - lp.dy) * t.dy >= 0) {
        left.add(lo);
      }
      if ((ro.dx - rp.dx) * t.dx + (ro.dy - rp.dy) * t.dy >= 0) {
        right.add(ro);
      }
    }
  }
  // Pathological spiral (everything skipped): fall back to full sides rather
  // than a degenerate polygon.
  if (left.length < 2 || right.length < 2) {
    left.clear();
    right.clear();
    for (var i = 0; i < spine.length; i++) {
      final p = spine[i];
      final v = (speeds[i] / maxS).clamp(0.0, 1.0);
      var w = _widthAt(cfg, p.pressure ?? 0.5, velocityNorm: v) / 2;
      final t = travelAt(i);
      if (isNib) {
        final proj = (t.dx * edgeDx + t.dy * edgeDy).abs().clamp(0.0, 1.0);
        w *= 0.18 + 0.82 * proj;
      }
      left.add(Offset(p.x - t.dy * w, p.y + t.dx * w));
      right.add(Offset(p.x + t.dy * w, p.y - t.dx * w));
    }
  }
  // Tip gap (spine units) decides how the two ends terminate.
  final closeDx = spine.last.x - spine.first.x;
  final closeDy = spine.last.y - spine.first.y;
  final tipGap = math.sqrt(closeDx * closeDx + closeDy * closeDy);

  // Closed loop (last sample back on the first, e.g. a drawn circle): the
  // duplicated seam sample puts L[n-1]≈R[0] and R[n-1]≈L[0], so keeping it
  // spans the seam cross-section twice as an X (two butt joints crossing
  // through the tip center — holes), and stacking caps fans both sides
  // bow-ties the same way. Drop the duplicate's side pair and join
  // butt-to-butt: one cross-section per seam end, always simple.
  final closedLoop =
      spine.length >= 3 && tipGap <= math.max(2.0, cfg.size * 0.15);
  if (closedLoop) {
    final l = left.sublist(0, left.length - 1);
    final r = right.sublist(0, right.length - 1);
    return [...l, ...r.reversed];
  }

  // Round caps when complete; butt caps live (avoids tip bulbs mid-draw).
  // Boundary order walks each cap from one side to the other with small
  // adjacent steps: [...left, endCap(L->R), ...right.reversed, startCap(R->L)].
  // Leading with a fan before left.first (or jumping across the cap mouth)
  // spans >90° chords that cross each other inside the cap — a bow-tie whose
  // nonzero winding cancels into a hole at the tip.
  if (isComplete) {
    // Abutting tips (gap smaller than the two cap radii, e.g. a tight
    // hairpin): round fans would overlap and bow-tie each other. Flat butt
    // joints give a clean silhouette with no winding holes instead.
    final r0 =
        math.sqrt(
          math.pow(left.first.dx - right.first.dx, 2) +
              math.pow(left.first.dy - right.first.dy, 2),
        ) /
        2;
    final r1 =
        math.sqrt(
          math.pow(left.last.dx - right.last.dx, 2) +
              math.pow(left.last.dy - right.last.dy, 2),
        ) /
        2;
    if (tipGap < r0 + r1) return [...left, ...right.reversed];

    final t0 = travelAt(0);
    final tn = travelAt(spine.length - 1);
    final startCap = _arcCap(
      spine.first,
      right.first,
      left.first,
      Offset(-t0.dx, -t0.dy),
    );
    final endCap = _arcCap(
      spine.last,
      left.last,
      right.last,
      Offset(tn.dx, tn.dy),
    );
    return [...left, ...endCap, ...right.reversed, ...startCap];
  }
  return [...left, ...right.reversed];
}

/// Paint-ready path for an experimental stroke.
///
/// Ribbon families share [buildGoogleInkPolygon]; the dashed family gets one
/// oval subpath per dot (concatenating dots into a single polygon would
/// bridge them with bow-ties whose nonzero winding cancels into holes).
Path buildGoogleInkPath(
  List<PointVector> rawPoints,
  GoogleInkBrushConfig cfg, {
  bool isComplete = true,
}) {
  final path = Path()..fillType = PathFillType.nonZero;
  if (rawPoints.isEmpty) return path;
  if (cfg.family == GoogleInkBrushFamily.dashedLine) {
    final spine = _inkSpine(rawPoints, cfg);
    if (spine.isEmpty) return path;
    final r = math.max(cfg.size / 2, 0.5);
    final gap = (cfg.size * 1.15).clamp(4.0, 28.0);
    void dot(PointVector p) {
      path.addOval(Rect.fromCircle(center: Offset(p.x, p.y), radius: r));
    }

    dot(spine.first);
    var acc = 0.0;
    for (var i = 1; i < spine.length; i++) {
      final dx = spine[i].x - spine[i - 1].x;
      final dy = spine[i].y - spine[i - 1].y;
      acc += math.sqrt(dx * dx + dy * dy);
      if (acc >= gap) {
        dot(spine[i]);
        acc = 0.0;
      }
    }
    if (acc > gap / 2) dot(spine.last);
    return path;
  }
  final poly = buildGoogleInkPolygon(
    rawPoints,
    cfg,
    isComplete: isComplete,
  );
  if (poly.length >= 3) {
    path.addPolygon(poly, true);
  } else if (poly.length == 1) {
    path.addOval(Rect.fromCircle(center: poly.first, radius: 0.5));
  }
  return path;
}

List<Offset> _circlePolygon(Offset c, double r, {int segments = 12}) {
  if (r <= 0.01) return [c];
  final out = <Offset>[];
  for (var i = 0; i < segments; i++) {
    final a = (i / segments) * math.pi * 2;
    out.add(Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r));
  }
  return out;
}

double _normPi(double a) {
  while (a > math.pi) {
    a -= math.pi * 2;
  }
  while (a <= -math.pi) {
    a += math.pi * 2;
  }
  return a;
}

double _angDist(double a, double b) {
  final d = (a - b).abs() % (math.pi * 2);
  return d > math.pi ? math.pi * 2 - d : d;
}

/// Round-cap fan around [tip], from the [from] side to the [to] side.
///
/// [outerDir] is the travel-aware outer direction (-travel at the start tip,
/// +travel at the end tip). The side pair alone cannot tell outer from inner
/// side (they sit ~180° apart), and fanning the inner side folds the cap back
/// over the ribbon: a bow-tie whose nonzero winding cancels into a hole at
/// the tip instead of a solid cap. The sweep whose midpoint tracks [outerDir]
/// is always the solid one, for round and nib tips alike. Interior points
/// only (endpoints are the adjacent side points in the outline order), so
/// every consecutive boundary step spans a small arc that cannot cross its
/// neighbors.
List<Offset> _arcCap(
  PointVector tip,
  Offset from,
  Offset to,
  Offset outerDir,
) {
  // 4-segment fan around the tip center.
  final c = Offset(tip.x, tip.y);
  final a0 = (from - c).direction;
  final a1 = (to - c).direction;
  final outer = outerDir.direction;
  final sweep = _normPi(a1 - a0);
  final alt = sweep > 0 ? sweep - math.pi * 2 : sweep + math.pi * 2;
  final useAlt =
      _angDist(a0 + alt / 2, outer) < _angDist(a0 + sweep / 2, outer);
  final chosen = useAlt ? alt : sweep;
  final radius = ((from - c).distance + (to - c).distance) / 2;
  if (radius <= 1e-6) return const [];
  final out = <Offset>[];
  for (var i = 1; i < 4; i++) {
    final a = a0 + chosen * (i / 4);
    out.add(Offset(c.dx + math.cos(a) * radius, c.dy + math.sin(a) * radius));
  }
  return out;
}

/// Triangle-mesh chunks for the batched `drawVertices` path, mirroring the
/// spine-mesh pens. Kept intentionally simple: ear-clip-free strip
/// triangulation of the outline polygon.
(Float32List, Uint16List)? googleInkMeshChunks(
  List<Offset> polygon,
) {
  if (polygon.length < 3) return null;
  final pos = Float32List(polygon.length * 2);
  for (var i = 0; i < polygon.length; i++) {
    pos[i * 2] = polygon[i].dx;
    pos[i * 2 + 1] = polygon[i].dy;
  }
  // Fan triangulation (outline is star-shaped around its centroid for ink).
  var cx = 0.0;
  var cy = 0.0;
  for (final p in polygon) {
    cx += p.dx;
    cy += p.dy;
  }
  cx /= polygon.length;
  cy /= polygon.length;
  final total = polygon.length + 1;
  final fullPos = Float32List(total * 2);
  fullPos[0] = cx;
  fullPos[1] = cy;
  fullPos.setAll(2, pos);
  final idx = Uint16List(polygon.length * 3);
  for (var i = 0; i < polygon.length; i++) {
    idx[i * 3] = 0;
    idx[i * 3 + 1] = 1 + i;
    idx[i * 3 + 2] = 1 + ((i + 1) % polygon.length);
  }
  return (fullPos, idx);
}
