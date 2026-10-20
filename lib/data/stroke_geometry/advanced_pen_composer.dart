// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:saber/data/stroke_geometry/point_vector.dart';
import 'package:saber/data/stroke_geometry/advanced_pen_options.dart';
import 'package:saber/data/stroke_geometry/constant_width_outline.dart'
    show localClosingChordTangent, localOpeningChordTangent;

double _widthAt(
  AdvancedPenPressureCurve curve,
  double strokeWidth,
  double pressure,
) {
  double w = curve.apply(strokeWidth, pressure.clamp(0.0, 1.0));
  if (pressure > 1.0) w *= 1.0 + (pressure - 1.0);
  return w;
}

List<Offset> composeAdvancedOutline(
  List<PointVector> points, {
  required double strokeWidth,
  required AdvancedPenOptions brushOptions,
  bool roundedCaps = true,
  bool? startRounded,
  bool? endRounded,
}) {
  final curve = brushOptions.pressureCurve;
  if (points.isEmpty || strokeWidth <= 0) return const [];
  if (points.length == 1) {
    final p = points.first;
    final w = _widthAt(curve, strokeWidth, p.pressure ?? 0.5);
    return _circleOutline(
      Offset(p.x, p.y),
      math.max(0.0, w * 0.5),
      math.max(16, (w * 2).round().clamp(16, 64)),
    );
  }

  final conditioned = _conditionSpine(points, strokeWidth: strokeWidth);
  if (conditioned.length == 1) {
    final p = conditioned.first;
    final w = _widthAt(curve, strokeWidth, p.pressure ?? 0.5);
    return _circleOutline(
      Offset(p.x, p.y),
      math.max(0.0, w * 0.5),
      math.max(16, (w * 2).round().clamp(16, 64)),
    );
  }

  final pts = sampleCatmullRom(conditioned, samplesPerSegment: 4);
  if (pts.length == 1) {
    final p = pts.first;
    final w = _widthAt(curve, strokeWidth, p.pressure ?? 0.5);
    return _circleOutline(
      Offset(p.x, p.y),
      math.max(0.0, w * 0.5),
      math.max(16, (w * 2).round().clamp(16, 64)),
    );
  }

  final n = pts.length;
  final radii = List<double>.filled(n, strokeWidth * 0.5);
  
  final speeds = List<double>.filled(n, 0.0);
  for (var i = 1; i < n; i++) {
    final dx = pts[i].x - pts[i - 1].x;
    final dy = pts[i].y - pts[i - 1].y;
    speeds[i] = math.sqrt(dx * dx + dy * dy) * 8.0;
  }
  speeds[0] = n > 1 ? speeds[1] : 0.0;
  
  final smoothedSpeeds = List<double>.filled(n, 0.0);
  double s = speeds[0];
  for (var i = 0; i < n; i++) {
    s = s * 0.8 + speeds[i] * 0.2;
    smoothedSpeeds[i] = math.min(1.0, s / 15.0);
  }

  for (var i = 0; i < n; i++) {
    final pt = pts[i];
    final pressure = pt.pressure ?? 0.5;
    final clampedP = pressure.clamp(0.0, 1.0);
    final poolOverdrive = math.max(0.0, pressure - 1.0);
    
    double w = math.max(0.05, curve.apply(strokeWidth * 2, clampedP) / 2);
    if (poolOverdrive > 0.0) {
      w *= 1.0 + poolOverdrive;
    }

    final speedNorm = smoothedSpeeds[i];

    if (brushOptions.velocityThinning != 0.0) {
      w *= (1.0 - brushOptions.velocityThinning * speedNorm).clamp(0.1, 4.0);
    }
    
    if (brushOptions.surfaceFriction > 0.0) {
      final double hf1 = math.sin(pt.x * 0.15 + pt.y * 0.22) * math.sin(pt.x * 0.27 - pt.y * 0.18);
      final double hf2 = math.cos(pt.x * 0.19 + pt.y * 0.25) * math.sin(pt.x * 0.14 - pt.y * 0.21);
      w *= (1.0 + (hf1 + hf2 * 0.5) * brushOptions.surfaceFriction * speedNorm * 0.6).clamp(0.2, 2.5);
    }

    radii[i] = math.max(0.05, w * 0.5);
  }

  final doStartCap = startRounded ?? roundedCaps;
  final doEndCap = endRounded ?? roundedCaps;

  if (brushOptions.builderType == AdvancedPenBuilderType.stamped) {
    return _buildStampedOutline(
      pts,
      radii,
      startRounded: doStartCap,
      endRounded: doEndCap,
    );
  }

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

  final chordBase = math.max(strokeWidth / 2, 1.0);
  final startTangent =
      localOpeningChordTangent(conditioned, baseSize: chordBase);
  final endTangent =
      localClosingChordTangent(conditioned, baseSize: chordBase);

  segTx[0] = startTangent.$1;
  segTy[0] = startTangent.$2;
  segTx[n - 2] = endTangent.$1;
  segTy[n - 2] = endTangent.$2;

  final avgRadius = radii.reduce((a, b) => a + b) / n;
  final capSegments = (24 + (avgRadius * 1.5).round()).clamp(24, 44);
  final baseJoinSegments = (10 + (avgRadius * 0.8).round()).clamp(10, 24);

  final posRail = <Offset>[];
  final negRail = <Offset>[];

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
  
  if (doStartCap && rStart > 0 && posRail.first != negRail.first) {
    outline.add(negRail.first);
    
    final center = Offset(pts.first.x, pts.first.y);
    final outwardX = -startTangent.$1;
    final outwardY = -startTangent.$2;
    
    final v0x = negRail.first.dx - center.dx;
    final v0y = negRail.first.dy - center.dy;
    final a0 = math.atan2(v0y, v0x);
    
    final v1x = posRail.first.dx - center.dx;
    final v1y = posRail.first.dy - center.dy;
    final a1 = math.atan2(v1y, v1x);
    
    var sweep = a1 - a0;
    while (sweep <= -math.pi) sweep += math.pi * 2;
    while (sweep > math.pi) sweep -= math.pi * 2;
    
    final midAngle = a0 + sweep * 0.5;
    final midDot = math.cos(midAngle) * outwardX + math.sin(midAngle) * outwardY;
    if (midDot < 0) {
      sweep = sweep > 0 ? sweep - math.pi * 2 : sweep + math.pi * 2;
    }
    
    final fullSweep = sweep > 0 ? math.pi * 2 : -math.pi * 2;
    final steps = math.max(8, capSegments * 2);
    
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      final theta = a0 + fullSweep * t;
      _appendDistinct(
        outline,
        Offset(
          center.dx + math.cos(theta) * rStart,
          center.dy + math.sin(theta) * rStart,
        ),
      );
    }
    
    _appendDistinct(outline, posRail.first);
  } else {
    outline.add(posRail.first);
  }

  for (final p in posRail) {
    _appendDistinct(outline, p);
  }

  if (doEndCap && rEnd > 0 && posRail.last != negRail.last) {
    final center = Offset(pts.last.x, pts.last.y);
    final outwardX = endTangent.$1;
    final outwardY = endTangent.$2;
    
    final v0x = posRail.last.dx - center.dx;
    final v0y = posRail.last.dy - center.dy;
    final a0 = math.atan2(v0y, v0x);
    
    final v1x = negRail.last.dx - center.dx;
    final v1y = negRail.last.dy - center.dy;
    final a1 = math.atan2(v1y, v1x);
    
    var sweep = a1 - a0;
    while (sweep <= -math.pi) sweep += math.pi * 2;
    while (sweep > math.pi) sweep -= math.pi * 2;
    
    final midAngle = a0 + sweep * 0.5;
    final midDot = math.cos(midAngle) * outwardX + math.sin(midAngle) * outwardY;
    if (midDot < 0) {
      sweep = sweep > 0 ? sweep - math.pi * 2 : sweep + math.pi * 2;
    }
    
    final fullSweep = sweep > 0 ? math.pi * 2 : -math.pi * 2;
    final steps = math.max(8, capSegments * 2);
    
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      final theta = a0 + fullSweep * t;
      _appendDistinct(
        outline,
        Offset(
          center.dx + math.cos(theta) * rEnd,
          center.dy + math.sin(theta) * rEnd,
        ),
      );
    }
    
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

List<Offset> _buildStampedOutline(
  List<PointVector> pts,
  List<double> radii, {
  required bool startRounded,
  required bool endRounded,
}) {
  final n = pts.length;
  final filtered = <int>[];
  for (var i = 0; i < n; i++) {
    bool swallowed = false;
    while (filtered.isNotEmpty) {
      final last = filtered.last;
      final d = (Offset(pts[i].x, pts[i].y) - Offset(pts[last].x, pts[last].y)).distance;
      if (d + radii[i] <= radii[last] + 1e-4) {
        swallowed = true;
        break;
      }
      if (d + radii[last] <= radii[i] + 1e-4) {
        filtered.removeLast();
        continue;
      }
      break;
    }
    if (!swallowed) {
      filtered.add(i);
    }
  }

  final m = filtered.length;
  if (m == 0) return const [];
  if (m == 1) {
    final p = pts[filtered[0]];
    final r = radii[filtered[0]];
    return _circleOutline(Offset(p.x, p.y), r, math.max(16, (r * 2).round().clamp(16, 64)));
  }

  final alphaL = List<double>.filled(m - 1, 0.0);
  final alphaR = List<double>.filled(m - 1, 0.0);
  final angles = List<double>.filled(m - 1, 0.0);

  for (var k = 0; k < m - 1; k++) {
    final i = filtered[k];
    final j = filtered[k + 1];
    final p0 = pts[i];
    final r0 = radii[i];
    final p1 = pts[j];
    final r1 = radii[j];

    final dx = p1.x - p0.x;
    final dy = p1.y - p0.y;
    final d = math.sqrt(dx * dx + dy * dy);
    final angle = math.atan2(dy, dx);
    
    double ratio = (r0 - r1) / d;
    ratio = ratio.clamp(-0.9999, 0.9999);
    final gamma = math.asin(ratio);

    angles[k] = angle;
    alphaL[k] = angle - math.pi / 2 - gamma;
    alphaR[k] = angle + math.pi / 2 + gamma;
  }

  final outline = <Offset>[];

  void addShortestArc(Offset center, double r, double a0, double a1) {
    if (r <= 0) return;
    double sweep = a1 - a0;
    while (sweep > math.pi) sweep -= math.pi * 2;
    while (sweep < -math.pi) sweep += math.pi * 2;
    if (sweep.abs() < 1e-4) return;
    int steps = math.max(2, (sweep.abs() / (math.pi * 2) * 24).ceil());
    for (int i = 1; i <= steps; i++) {
      double theta = a0 + sweep * (i / steps);
      _appendDistinct(outline, Offset(center.dx + r * math.cos(theta), center.dy + r * math.sin(theta)));
    }
  }

  void addCapArc(Offset center, double r, double a0, double a1, double targetAngle) {
    if (r <= 0) return;
    double sweep = a1 - a0;
    while (sweep > math.pi * 2) sweep -= math.pi * 2;
    while (sweep < 0) sweep += math.pi * 2;
    
    double midAngle = a0 + sweep / 2;
    double dot = math.cos(midAngle) * math.cos(targetAngle) + math.sin(midAngle) * math.sin(targetAngle);
    if (dot < 0) {
      sweep -= math.pi * 2;
    }
    int steps = math.max(6, (sweep.abs() / (math.pi * 2) * 32).ceil());
    for (int i = 1; i < steps; i++) {
      double theta = a0 + sweep * (i / steps);
      _appendDistinct(outline, Offset(center.dx + r * math.cos(theta), center.dy + r * math.sin(theta)));
    }
  }

  final firstIdx = filtered[0];
  final cFirst = Offset(pts[firstIdx].x, pts[firstIdx].y);
  final rFirst = radii[firstIdx];
  if (startRounded && rFirst > 0) {
    _appendDistinct(outline, Offset(cFirst.dx + rFirst * math.cos(alphaR[0]), cFirst.dy + rFirst * math.sin(alphaR[0])));
    addCapArc(cFirst, rFirst, alphaR[0], alphaL[0], angles[0] + math.pi);
    _appendDistinct(outline, Offset(cFirst.dx + rFirst * math.cos(alphaL[0]), cFirst.dy + rFirst * math.sin(alphaL[0])));
  } else {
    _appendDistinct(outline, Offset(cFirst.dx + rFirst * math.cos(alphaR[0]), cFirst.dy + rFirst * math.sin(alphaR[0])));
    _appendDistinct(outline, Offset(cFirst.dx + rFirst * math.cos(alphaL[0]), cFirst.dy + rFirst * math.sin(alphaL[0])));
  }

  for (var k = 0; k < m - 1; k++) {
    if (k > 0) {
      final idx = filtered[k];
      final c = Offset(pts[idx].x, pts[idx].y);
      addShortestArc(c, radii[idx], alphaL[k - 1], alphaL[k]);
    }
    final nextIdx = filtered[k + 1];
    _appendDistinct(outline, Offset(pts[nextIdx].x + radii[nextIdx] * math.cos(alphaL[k]), pts[nextIdx].y + radii[nextIdx] * math.sin(alphaL[k])));
  }

  final lastIdx = filtered[m - 1];
  final cLast = Offset(pts[lastIdx].x, pts[lastIdx].y);
  final rLast = radii[lastIdx];
  if (endRounded && rLast > 0) {
    addCapArc(cLast, rLast, alphaL[m - 2], alphaR[m - 2], angles[m - 2]);
    _appendDistinct(outline, Offset(cLast.dx + rLast * math.cos(alphaR[m - 2]), cLast.dy + rLast * math.sin(alphaR[m - 2])));
  } else {
    _appendDistinct(outline, Offset(cLast.dx + rLast * math.cos(alphaR[m - 2]), cLast.dy + rLast * math.sin(alphaR[m - 2])));
  }

  for (var k = m - 2; k >= 0; k--) {
    if (k < m - 2) {
      final idx = filtered[k + 1];
      final c = Offset(pts[idx].x, pts[idx].y);
      addShortestArc(c, radii[idx], alphaR[k + 1], alphaR[k]);
    }
    final prevIdx = filtered[k];
    _appendDistinct(outline, Offset(pts[prevIdx].x + radii[prevIdx] * math.cos(alphaR[k]), pts[prevIdx].y + radii[prevIdx] * math.sin(alphaR[k])));
  }

  if (outline.isNotEmpty && outline.first != outline.last) {
    outline.add(outline.first);
  }

  return outline;
}

List<PointVector> sampleCatmullRom(
  List<PointVector> points, {
  int samplesPerSegment = 8,
}) {
  if (points.length < 3) return List<PointVector>.of(points);

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

  _absorbTipTransient(clean, strokeWidth, atStart: true);
  _absorbTipTransient(clean, strokeWidth, atStart: false);

  if (clean.length < 3) return clean;

  return _despikePressures(clean);
}

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
    } else {
      break;
    }
  }
}

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