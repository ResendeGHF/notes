// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Pure-Dart port of Rnote's smooth-stroke ribbon composer
// (`crates/rnote-compose/src/style/smooth/mod.rs`):
// `compose_lines_variable_width` + the `PenPath` fill path that calls it per
// segment with `PressureCurve::apply(stroke_width, pressure)` end widths.
//
// Each consecutive point pair is treated as one `Line`; per-line widths are
// linearly interpolated between the segment's start/end widths, offset points
// are built along the perpendicular, round caps are cubic bulges, and the
// outline is filled once (so translucent ink never shows overlap seams).

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:saber/data/stroke_geometry/point_vector.dart';
import 'package:saber/data/stroke_geometry/advanced_pen_options.dart';
import 'package:saber/data/stroke_geometry/constant_width_outline.dart'
    show localClosingChordTangent, localOpeningChordTangent;

/// Builds a single closed variable-width outline polygon from modeled
/// centerline points, as Rnote's smooth composer does.
///
/// [strokeWidth] is the base width (`SmoothOptions::stroke_width` in Rnote);
/// per-point widths come from [curve]. Set [roundedCaps] false for a
/// constant-width marker / straight-cap look (butt caps). Returns `const []`
/// for empty input or non-positive width, and a filled circle for a single
/// dot — mirroring Rnote's single-position branch.
List<Offset> composeAdvancedOutline(
  List<PointVector> points, {
  required double strokeWidth,
  required AdvancedPenPressureCurve curve,
  bool roundedCaps = true,
  // Split cap control for staged chunks: butt-cut ends join invisibly.
  // Default to [roundedCaps] so existing callers are unaffected.
  bool? startRounded,
  bool? endRounded,
}) {
  if (points.isEmpty || strokeWidth <= 0) return const [];
  if (points.length == 1) {
    final p = points.first;
    final w = curve.apply(strokeWidth, p.pressure ?? 0.5);
    return _circleOutline(
      Offset(p.x, p.y),
      math.max(0.0, w * 0.5),
      math.max(24, (w * 2).round().clamp(24, 64)),
    );
  }

  // Condition the modeled spine: drop ghosted micro-edges, absorb
  // spring-settling transients at the tips, despike pressures, and subdivide
  // coarse spans with Centripetal Catmull-Rom (matching Rnote's segment
  // subdivision in `crates/rnote-compose/src/style/smooth/mod.rs`).
  final conditioned = _conditionSpine(points, strokeWidth: strokeWidth);
  if (conditioned.length == 1) {
    final p = conditioned.first;
    final w = curve.apply(strokeWidth, p.pressure ?? 0.5);
    return _circleOutline(
      Offset(p.x, p.y),
      math.max(0.0, w * 0.5),
      math.max(24, (w * 2).round().clamp(24, 64)),
    );
  }

  // Travel tangents on the sparse conditioned spine. These look past
  // put-down stems and lift-off hooks into the travel direction (tested,
  // jitter-robust), so caps sit oriented even when the raw tip wiggles.
  final chordBase = math.max(strokeWidth / 2, 1.0);
  final startTangent =
      localOpeningChordTangent(conditioned, baseSize: chordBase);
  final endTangent =
      localClosingChordTangent(conditioned, baseSize: chordBase);
  final pts = sampleCatmullRom(conditioned, samplesPerSegment: 4);
  if (pts.length == 1) {
    final p = pts.first;
    final w = curve.apply(strokeWidth, p.pressure ?? 0.5);
    return _circleOutline(
      Offset(p.x, p.y),
      math.max(0.0, w * 0.5),
      math.max(24, (w * 2).round().clamp(24, 64)),
    );
  }

  final n = pts.length;
  // Raw widths track pressure exactly (Rnote-faithful): the spine pressures
  // were already despiked in [_conditionSpine], so no width filtering here —
  // filtering would smear genuine pressure ramps and inflate/deflate the
  // caps relative to the true tip width.
  final radii = List<double>.filled(n, strokeWidth * 0.5);
  for (var i = 0; i < n; i++) {
    final w = curve.apply(strokeWidth, (pts[i].pressure ?? 0.5).clamp(0.0, 1.0));
    radii[i] = math.max(0.05, w * 0.5);
  }

  // Unit segment directions (pts[i] -> pts[i + 1]).
  final segTx = List<double>.filled(n - 1, 1.0);
  final segTy = List<double>.filled(n - 1, 0.0);
  for (var i = 0; i < n - 1; i++) {
    final dx = pts[i + 1].x - pts[i].x;
    final dy = pts[i + 1].y - pts[i].y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len > 1e-9) {
      segTx[i] = dx / len;
      segTy[i] = dy / len;
    } else if (i > 0) {
      segTx[i] = segTx[i - 1];
      segTy[i] = segTy[i - 1];
    }
  }
  for (var i = n - 3; i >= 0; i--) {
    final dx = pts[i + 1].x - pts[i].x;
    final dy = pts[i + 1].y - pts[i].y;
    if (dx * dx + dy * dy <= 1e-18) {
      segTx[i] = segTx[i + 1];
      segTy[i] = segTy[i + 1];
    }
  }

  // Lock the immediate tip segments onto the travel tangents so the cap
  // mouths are exactly G1-continuous with the ribbon walls. Post-absorption
  // the first/last real segments already agree with travel, so this only
  // removes residual sub-pixel mismatch (never a visible rotation).
  segTx[0] = startTangent.$1;
  segTy[0] = startTangent.$2;
  segTx[n - 2] = endTangent.$1;
  segTy[n - 2] = endTangent.$2;

  final avgRadius = radii.reduce((a, b) => a + b) / n;
  // Generous arc density: caps and join bulbs are the most visible curves,
  // and flattened arcs read as "square" well before straight rails do.
  final capSegments = (24 + (avgRadius * 1.5).round()).clamp(24, 44);
  final baseJoinSegments = (10 + (avgRadius * 0.8).round()).clamp(10, 24);

  final posRail = <Offset>[];
  final negRail = <Offset>[];

  // Start tip side points (orthogonal to startTangent).
  final startNx = -startTangent.$2;
  final startNy = startTangent.$1;
  final rStart = radii.first;
  _appendDistinct(
    posRail,
    Offset(pts.first.x + startNx * rStart, pts.first.y + startNy * rStart),
  );
  _appendDistinct(
    negRail,
    Offset(pts.first.x - startNx * rStart, pts.first.y - startNy * rStart),
  );

  // Interior vertices: smooth miter-bisector on gentle bends, high-density
  // circular join arc on outer turns, and clamped inner bisector on inner turns.
  for (var i = 1; i < n - 1; i++) {
    final px = pts[i].x;
    final py = pts[i].y;
    final r = radii[i];

    final t0x = segTx[i - 1];
    final t0y = segTy[i - 1];
    final t1x = segTx[i];
    final t1y = segTy[i];

    final n0x = -t0y;
    final n0y = t0x;
    final n1x = -t1y;
    final n1y = t1x;

    final align = (t0x * t1x + t0y * t1y).clamp(-1.0, 1.0);
    final turn = t0x * t1y - t0y * t1x;

    // Bisector normal.
    var bx = n0x + n1x;
    var by = n0y + n1y;
    final bLen = math.sqrt(bx * bx + by * by);
    if (bLen > 1e-6) {
      bx /= bLen;
      by /= bLen;
    } else {
      bx = n0x;
      by = n0y;
    }

    if (align > 0.95) {
      // Gentle curve: exact symmetric miter on both rails. At these angles
      // the miter factor is ~1.0, so this only removes faceting without
      // ever stepping a rail backward.
      final miter = (1.0 / math.sqrt(math.max(0.25, (1.0 + align) * 0.5)))
          .clamp(1.0, 1.25);
      _appendDistinct(
        posRail,
        Offset(px + bx * r * miter, py + by * r * miter),
      );
      _appendDistinct(
        negRail,
        Offset(px - bx * r * miter, py - by * r * miter),
      );
      continue;
    }

    final p0 = Offset(px + n0x * r, py + n0y * r);
    final p1 = Offset(px + n1x * r, py + n1y * r);
    final m0 = Offset(px - n0x * r, py - n0y * r);
    final m1 = Offset(px - n1x * r, py - n1y * r);
    final center = Offset(px, py);

    // Sharp hairpin return (> 115 degrees): round both sides into a clean bulb.
    if (align < -0.42) {
      final cuspSegs = math.max(baseJoinSegments, 16);
      var outX = -(n0x + n1x);
      var outY = -(n0y + n1y);
      var outLen = math.sqrt(outX * outX + outY * outY);
      if (outLen < 1e-6) {
        outX = t0x - t1x;
        outY = t0y - t1y;
        outLen = math.sqrt(outX * outX + outY * outY);
      }
      if (outLen > 1e-6) {
        outX /= outLen;
        outY /= outLen;
      } else {
        outX = t0x;
        outY = t0y;
      }
      _appendDistinct(posRail, p0);
      _appendCircularArc(
        posRail,
        center: center,
        from: p0,
        to: p1,
        outwardX: -outX,
        outwardY: -outY,
        radius: r,
        segments: cuspSegs,
      );
      _appendDistinct(posRail, p1);

      _appendDistinct(negRail, m0);
      _appendCircularArc(
        negRail,
        center: center,
        from: m0,
        to: m1,
        outwardX: outX,
        outwardY: outY,
        radius: r,
        segments: cuspSegs,
      );
      _appendDistinct(negRail, m1);
      continue;
    }

    final angleRad = math.acos(align);
    final arcSegs =
        (baseJoinSegments * (angleRad / (math.pi * 0.5))).ceil().clamp(
          6,
          baseJoinSegments + 8,
        );

    if (turn >= 0) {
      // Left turn: posRail is inner, negRail is outer.
      _appendDistinct(posRail, Offset(px + bx * r, py + by * r));
      _appendDistinct(negRail, m0);
      _appendCircularArc(
        negRail,
        center: center,
        from: m0,
        to: m1,
        outwardX: -bx,
        outwardY: -by,
        radius: r,
        segments: arcSegs,
      );
      _appendDistinct(negRail, m1);
    } else {
      // Right turn: negRail is inner, posRail is outer.
      _appendDistinct(posRail, p0);
      _appendCircularArc(
        posRail,
        center: center,
        from: p0,
        to: p1,
        outwardX: bx,
        outwardY: by,
        radius: r,
        segments: arcSegs,
      );
      _appendDistinct(posRail, p1);
      _appendDistinct(negRail, Offset(px - bx * r, py - by * r));
    }
  }

  // End tip side points (orthogonal to endTangent).
  final endNx = -endTangent.$2;
  final endNy = endTangent.$1;
  final rEnd = radii.last;
  _appendDistinct(
    posRail,
    Offset(pts.last.x + endNx * rEnd, pts.last.y + endNy * rEnd),
  );
  _appendDistinct(
    negRail,
    Offset(pts.last.x - endNx * rEnd, pts.last.y - endNy * rEnd),
  );

  if (posRail.isEmpty || negRail.isEmpty) return const [];

  final outline = <Offset>[];
  final bool doStartCap = startRounded ?? roundedCaps;
  final bool doEndCap = endRounded ?? roundedCaps;
  // Start cap: exact semicircle in the (-startTangent, startNormal) frame.
  // Butt joints skip the arc so staged chunks join invisibly.
  if (doStartCap && rStart > 0 && posRail.first != negRail.first) {
    outline.add(negRail.first);
    _appendCircularArc(
      outline,
      center: Offset(pts.first.x, pts.first.y),
      from: negRail.first,
      to: posRail.first,
      outwardX: -startTangent.$1,
      outwardY: -startTangent.$2,
      radius: rStart,
      segments: capSegments,
    );
    _appendDistinct(outline, posRail.first);
  } else {
    outline.add(posRail.first);
  }

  for (final p in posRail) {
    _appendDistinct(outline, p);
  }

  // End cap: exact semicircle in the (+endTangent, endNormal) frame.
  if (doEndCap && rEnd > 0 && posRail.last != negRail.last) {
    _appendCircularArc(
      outline,
      center: Offset(pts.last.x, pts.last.y),
      from: posRail.last,
      to: negRail.last,
      outwardX: endTangent.$1,
      outwardY: endTangent.$2,
      radius: rEnd,
      segments: capSegments,
    );
    _appendDistinct(outline, negRail.last);
  } else {
    _appendDistinct(outline, negRail.last);
  }

  for (var i = negRail.length - 1; i >= 0; i--) {
    _appendDistinct(outline, negRail[i]);
  }

  if (outline.isNotEmpty && outline.first != outline.last) {
    outline.add(outline.first);
  }
  return outline;
}

/// Samples a Centripetal Catmull-Rom spline through [points] (matching Rnote's
/// `CubicBezier::new_w_catmull_rom` then `approx_with_lines`, upgraded to
/// centripetal parameterization so decelerating stylus lifts never overshoot
/// or hook at the stroke tip).
List<PointVector> sampleCatmullRom(
  List<PointVector> points, {
  int samplesPerSegment = 8,
}) {
  if (points.length < 3) return List<PointVector>.of(points);

  // Deduplicate coincident samples before computing centripetal knots.
  final clean = <PointVector>[points.first];
  for (var i = 1; i < points.length; i++) {
    final p = points[i];
    final prev = clean.last;
    final dx = p.x - prev.x;
    final dy = p.y - prev.y;
    if (dx * dx + dy * dy > 1e-4) {
      clean.add(p);
    } else if (i == points.length - 1) {
      clean[clean.length - 1] = p;
    }
  }
  if (clean.length < 3) return clean;

  final n = clean.length;
  final out = <PointVector>[clean.first];

  for (var i = 0; i < n - 1; i++) {
    final p1 = clean[i];
    final p2 = clean[i + 1];
    final p0 = i > 0
        ? clean[i - 1]
        : PointVector(2 * p1.x - p2.x, 2 * p1.y - p2.y, p1.pressure);
    final p3 = i + 2 < n
        ? clean[i + 2]
        : PointVector(2 * p2.x - p1.x, 2 * p2.y - p1.y, p2.pressure);

    final segDx = p2.x - p1.x;
    final segDy = p2.y - p1.y;
    final segLen = math.sqrt(segDx * segDx + segDy * segDy);
    if (segLen < 1e-6) continue;

    final steps = math.max(
      2,
      math.min(32, math.max(samplesPerSegment, (segLen / 0.85).ceil())),
    );

    final tangents = _centripetalHermiteTangents(p0, p1, p2, p3);
    final m1x = tangents.$1;
    final m1y = tangents.$2;
    final m2x = tangents.$3;
    final m2y = tangents.$4;

    final pr1 = p1.pressure ?? 0.5;
    final pr2 = p2.pressure ?? 0.5;

    for (var s = 1; s <= steps; s++) {
      final t = s / steps;
      final t2 = t * t;
      final t3 = t2 * t;
      final h00 = 2 * t3 - 3 * t2 + 1;
      final h10 = t3 - 2 * t2 + t;
      final h01 = -2 * t3 + 3 * t2;
      final h11 = t3 - t2;

      final x = h00 * p1.x + h10 * m1x + h01 * p2.x + h11 * m2x;
      final y = h00 * p1.y + h10 * m1y + h01 * p2.y + h11 * m2y;
      final pressure = pr1 + (pr2 - pr1) * t;
      out.add(PointVector(x, y, pressure));
    }
  }
  return out;
}

/// Computes Centripetal Catmull-Rom (alpha = 0.5) Hermite tangents (m1, m2)
/// for segment [p1] -> [p2], clamped so the cubic never overshoots when
/// adjacent segments have wildly different lengths.
(double, double, double, double) _centripetalHermiteTangents(
  PointVector p0,
  PointVector p1,
  PointVector p2,
  PointVector p3,
) {
  final d01 = math.sqrt(
    (p1.x - p0.x) * (p1.x - p0.x) + (p1.y - p0.y) * (p1.y - p0.y),
  );
  final d12 = math.sqrt(
    (p2.x - p1.x) * (p2.x - p1.x) + (p2.y - p1.y) * (p2.y - p1.y),
  );
  final d23 = math.sqrt(
    (p3.x - p2.x) * (p3.x - p2.x) + (p3.y - p2.y) * (p3.y - p2.y),
  );

  final dt0 = math.max(1e-3, math.sqrt(d01));
  final dt1 = math.max(1e-3, math.sqrt(d12));
  final dt2 = math.max(1e-3, math.sqrt(d23));

  final vx01 = (p1.x - p0.x) / dt0;
  final vy01 = (p1.y - p0.y) / dt0;
  final vx12 = (p2.x - p1.x) / dt1;
  final vy12 = (p2.y - p1.y) / dt1;
  final vx23 = (p3.x - p2.x) / dt2;
  final vy23 = (p3.y - p2.y) / dt2;

  var m1x = dt1 * ((dt1 * vx01 + dt0 * vx12) / (dt0 + dt1));
  var m1y = dt1 * ((dt1 * vy01 + dt0 * vy12) / (dt0 + dt1));
  var m2x = dt1 * ((dt2 * vx12 + dt1 * vx23) / (dt1 + dt2));
  var m2y = dt1 * ((dt2 * vy12 + dt1 * vy23) / (dt1 + dt2));

  // Fritsch-Carlson / Hermite monotonicity bound: prevent any overshoot
  // beyond 2.5x the segment chord length.
  final maxLen = d12 * 2.5;
  final len1 = math.sqrt(m1x * m1x + m1y * m1y);
  if (len1 > maxLen && len1 > 1e-9) {
    final scale = maxLen / len1;
    m1x *= scale;
    m1y *= scale;
  }
  final len2 = math.sqrt(m2x * m2x + m2y * m2y);
  if (len2 > maxLen && len2 > 1e-9) {
    final scale = maxLen / len2;
    m2x *= scale;
    m2y *= scale;
  }

  return (m1x, m1y, m2x, m2y);
}

/// Conditions the raw input spine: drops non-finite and ghosted samples,
/// absorbs spring-settling transients at both tips, and despikes pressures.
/// Does NOT subdivide (call [sampleCatmullRom] afterwards).
///
/// The returned points keep the true endpoints; only interior tip-run points
/// redundant with their neighbors are removed, so caps keep their position.
List<PointVector> _conditionSpine(
  List<PointVector> points, {
  required double strokeWidth,
}) {
  final clean = <PointVector>[];
  for (var i = 0; i < points.length; i++) {
    final p = points[i];
    if (!p.x.isFinite || !p.y.isFinite) continue;
    if (clean.isEmpty) {
      clean.add(p);
    } else {
      final prev = clean.last;
      final dx = p.x - prev.x;
      final dy = p.y - prev.y;
      if (dx * dx + dy * dy > 1e-4) {
        clean.add(p);
      } else if (i == points.length - 1) {
        clean[clean.length - 1] = p;
      }
    }
  }
  if (clean.length <= 2) return clean;

  // Absorb spring-settling transients at both tips (greedy tip-anchored
  // RDP): drop leading points redundant with the tip chord while the run
  // stays inside a small arc window. Sub-pixel put-down/lift-off dust and
  // small direction wiggles vanish; genuine corners deviate more and
  // survive for the join logic. Endpoints are never moved.
  _absorbTipTransient(clean, strokeWidth, atStart: true);
  _absorbTipTransient(clean, strokeWidth, atStart: false);

  if (clean.length < 3) return clean;

  // Despike pressures (3-tap median) before subdivision so a single-sample
  // hardware glitch never becomes a pinch/bulb, and linear interpolation
  // cannot smear it across neighbors first.
  return _despikePressures(clean);
}

/// Greedy tip-anchored simplification of one tip run.
///
/// Starting at the tip, drops points whose perpendicular deviation from the
/// local chord (neighbors) stays within [devTol], while the arc length from
/// the tip stays within [window]. A settling wiggle collapses onto the travel
/// chord; a committed corner exceeds the tolerance and stops absorption, so
/// the rails and joins that follow still see it.
void _absorbTipTransient(
  List<PointVector> pts,
  double strokeWidth, {
  required bool atStart,
}) {
  if (pts.length < 3) return;
  final devTol = (strokeWidth * 0.15).clamp(0.35, 0.9);
  final window = (strokeWidth * 0.9).clamp(2.0, 6.0);

  PointVector at(int i) =>
      atStart ? pts[i] : pts[pts.length - 1 - i];

  double arc = 0.0;
  var j = 1;
  while (j + 1 < pts.length) {
    final prev = at(j - 1);
    final cur = at(j);
    final next = at(j + 1);
    final ax = cur.x - prev.x, ay = cur.y - prev.y;
    final segLen = math.sqrt(ax * ax + ay * ay);
    arc += segLen;
    if (arc > window) break;
    final cx = next.x - prev.x, cy = next.y - prev.y;
    final cl = math.sqrt(cx * cx + cy * cy);
    double dev;
    if (cl < 1e-9) {
      // Neighbors coincide: pure out-and-back hook; deviation is the whole
      // excursion.
      dev = segLen;
    } else {
      dev = (ax * cy - ay * cx).abs() / cl;
    }
    if (dev <= devTol) {
      if (atStart) {
        pts.removeAt(j);
      } else {
        pts.removeAt(pts.length - 1 - j);
      }
      // Re-examine the new adjacency without advancing.
    } else {
      break;
    }
  }
}

/// Removes single-sample pressure glitches with a 3-tap median.
///
/// The median is an exact no-op on monotone ramps (genuine pressure lifts
/// and presses pass through untouched, tips included), and it collapses an
/// isolated spike onto its neighbors without touching them — unlike a mean
/// filter, which smears the spike into a thin-then-thick wobble. Endpoints
/// track the true tip pressure, as Rnote does.
List<PointVector> _despikePressures(List<PointVector> pts) {
  final n = pts.length;
  if (n < 3) return pts;
  final out = List<PointVector>.of(pts);
  for (var i = 1; i < n - 1; i++) {
    final p = pts[i].pressure;
    if (p == null) continue;
    final a = pts[i - 1].pressure ?? 0.5;
    final c = pts[i + 1].pressure ?? 0.5;
    final m = a < p
        ? (p < c ? p : (a < c ? c : a))
        : (a < c ? a : (p < c ? c : p));
    if (m != p) out[i] = PointVector(pts[i].x, pts[i].y, m);
  }
  return out;
}


void _appendCircularArc(
  List<Offset> out, {
  required Offset center,
  required Offset from,
  required Offset to,
  required double outwardX,
  required double outwardY,
  required double radius,
  required int segments,
}) {
  if (radius <= 0) return;
  final v0x = from.dx - center.dx;
  final v0y = from.dy - center.dy;
  final v1x = to.dx - center.dx;
  final v1y = to.dy - center.dy;

  final a0 = math.atan2(v0y, v0x);
  final a1 = math.atan2(v1y, v1x);
  var sweep = a1 - a0;
  while (sweep <= -math.pi) sweep += math.pi * 2;
  while (sweep > math.pi) sweep -= math.pi * 2;

  // Ensure the arc bulges along [outwardX, outwardY] (Crucial for 180-deg caps).
  final midAngle = a0 + sweep * 0.5;
  final midDot =
      math.cos(midAngle) * outwardX + math.sin(midAngle) * outwardY;
  if (midDot < 0) {
    sweep = sweep > 0 ? sweep - math.pi * 2 : sweep + math.pi * 2;
  }

  final steps = math.max(2, segments);
  for (var i = 1; i < steps; i++) {
    final t = i / steps;
    final theta = a0 + sweep * t;
    _appendDistinct(
      out,
      Offset(
        center.dx + math.cos(theta) * radius,
        center.dy + math.sin(theta) * radius,
      ),
    );
  }
}

List<Offset> _circleOutline(Offset c, double r, int segments) {
  if (r <= 0) return [c];
  final n = math.max(12, segments);
  return [
    for (var i = 0; i < n; i++)
      Offset(
        c.dx + math.cos(i / n * math.pi * 2) * r,
        c.dy + math.sin(i / n * math.pi * 2) * r,
      ),
  ];
}

void _appendDistinct(List<Offset> list, Offset o, [double eps = 1e-5]) {
  if (list.isEmpty) {
    list.add(o);
    return;
  }
  final prev = list.last;
  if ((prev.dx - o.dx).abs() > eps || (prev.dy - o.dy).abs() > eps) {
    list.add(o);
  }
}
