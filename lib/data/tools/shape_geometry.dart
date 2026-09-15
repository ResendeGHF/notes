// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui';

import 'package:saber/data/tools/shape_tool.dart';

/// Geometric fitters and control-point helpers for parametric [ShapeStroke]s.
abstract final class ShapeGeometry {
  ShapeGeometry._();

  static bool isVertexEditable(ShapeKind kind) {
    return const {
      ShapeKind.line,
      ShapeKind.arrow,
      ShapeKind.doubleArrow,
      ShapeKind.rectangle,
      ShapeKind.circle,
      ShapeKind.ellipse,
      ShapeKind.triangleIsosceles,
      ShapeKind.triangleRight,
      ShapeKind.polygon,
      ShapeKind.star,
    }.contains(kind);
  }

  /// Control points used for direct manipulation (source of truth for core kinds).
  static List<Offset> controlPointsOf(ShapeConfig config) {
    final verts = config.vertices;
    if (verts != null && verts.isNotEmpty) {
      if (config.kind == ShapeKind.ellipse && verts.length == 4) {
        final p = ellipseParamsFromControlPoints(verts);
        if (p != null) {
          return ellipseControlPoints(p.center, p.rx, p.ry, p.angleRad);
        }
      }
      if (config.kind == ShapeKind.circle && verts.length >= 4) {
        final box = boundsOf(verts);
        final r = math.min(box.width, box.height) / 2;
        return [box.center, Offset(box.center.dx + r, box.center.dy)];
      }
      return List<Offset>.from(verts);
    }
    return ensureControlPoints(config);
  }

  /// Reconstruct control points from legacy bounds/start/end when vertices missing.
  static List<Offset> ensureControlPoints(ShapeConfig config) {
    final b = config.bounds;
    switch (config.kind) {
      case ShapeKind.line:
      case ShapeKind.arrow:
      case ShapeKind.doubleArrow:
      case ShapeKind.parabola:
      case ShapeKind.spring:
      case ShapeKind.fixedEnd:
        return [
          config.start ?? b.topLeft,
          config.end ?? b.bottomRight,
        ];
      case ShapeKind.triangleIsosceles:
      case ShapeKind.triangleRight:
      case ShapeKind.nabla:
        if (config.kind == ShapeKind.triangleRight) {
          return [b.bottomLeft, b.bottomRight, b.topLeft];
        }
        if (config.kind == ShapeKind.nabla ||
            (config.data['upward'] == false)) {
          return [
            b.topLeft,
            b.topRight,
            Offset(b.center.dx, b.bottom),
          ];
        }
        return [
          Offset(b.center.dx, b.top),
          b.bottomLeft,
          b.bottomRight,
        ];
      case ShapeKind.polygon:
        return _regularPolygonVertices(b, math.max(3, config.detail));
      case ShapeKind.star:
        return _starVertices(b);
      case ShapeKind.circle:
        final r = math.min(b.width, b.height) / 2;
        return [b.center, Offset(b.center.dx + r, b.center.dy)];
      case ShapeKind.ellipse:
        return ellipseControlPoints(
          b.center,
          math.max(b.width / 2, 1),
          math.max(b.height / 2, 1),
          config.rotationDeg * math.pi / 180,
        );
      case ShapeKind.rectangle:
      default:
        return [b.topLeft, b.topRight, b.bottomRight, b.bottomLeft];
    }
  }

  /// Ellipse control points: focus1, focus2, major-axis tip.
  static List<Offset> ellipseControlPoints(
    Offset center,
    double rx,
    double ry,
    double angleRad,
  ) {
    var a = math.max(rx, 1.0);
    var b = math.max(ry, 1.0);
    var ang = angleRad;
    if (b > a) {
      final t = a;
      a = b;
      b = t;
      ang += math.pi / 2;
    }
    final cLin = math.sqrt(math.max(a * a - b * b, 0));
    final cosA = math.cos(ang);
    final sinA = math.sin(ang);
    return [
      Offset(center.dx - cosA * cLin, center.dy - sinA * cLin),
      Offset(center.dx + cosA * cLin, center.dy + sinA * cLin),
      Offset(center.dx + cosA * a, center.dy + sinA * a),
    ];
  }

  /// Resolves oriented ellipse params from foci control points or legacy corners.
  static ({
    Offset center,
    double rx,
    double ry,
    double angleRad,
  })? ellipseParamsFromControlPoints(List<Offset> pts) {
    if (pts.length == 3) {
      return _ellipseParamsFromFoci(pts[0], pts[1], pts[2]);
    }
    if (pts.length == 2) {
      final center = pts[0];
      final r = math.max((pts[1] - pts[0]).distance, 1.0);
      return (center: center, rx: r, ry: r, angleRad: 0);
    }
    if (pts.length >= 4) {
      // Legacy box corners — recover orientation from the parallelogram when possible.
      final c0 = pts[0], c1 = pts[1], c2 = pts[2], c3 = pts[3];
      final mid01 = Offset((c0.dx + c1.dx) / 2, (c0.dy + c1.dy) / 2);
      final mid23 = Offset((c2.dx + c3.dx) / 2, (c2.dy + c3.dy) / 2);
      final center = Offset((mid01.dx + mid23.dx) / 2, (mid01.dy + mid23.dy) / 2);
      final axis = c1 - c0;
      final perp = c3 - c0;
      final rx = math.max(axis.distance / 2, 1.0);
      final ry = math.max(perp.distance / 2, 1.0);
      final ang = math.atan2(axis.dy, axis.dx);
      return (center: center, rx: rx, ry: ry, angleRad: ang);
    }
    return null;
  }

  static ({
    Offset center,
    double rx,
    double ry,
    double angleRad,
  }) _ellipseParamsFromFoci(Offset f1, Offset f2, Offset majorTip) {
    final center = Offset((f1.dx + f2.dx) / 2, (f1.dy + f2.dy) / 2);
    final cLin = (f2 - f1).distance / 2;
    final ang = math.atan2(f2.dy - f1.dy, f2.dx - f1.dx);
    var a = ((majorTip - f1).distance + (majorTip - f2).distance) / 2;
    a = math.max(a, cLin + 1e-3);
    final b = math.sqrt(math.max(a * a - cLin * cLin, 1e-6));
    return (center: center, rx: a, ry: b, angleRad: ang);
  }

  /// Constrained ellipse edit: drag focus or major tip.
  static ShapeConfig moveEllipseControlPoint(
    ShapeConfig base,
    int index,
    Offset position,
  ) {
    final pts = controlPointsOf(base);
    final params = ellipseParamsFromControlPoints(pts);
    if (params == null || pts.length < 2) {
      final next = List<Offset>.from(pts);
      if (next.isEmpty) return base;
      next[index.clamp(0, next.length - 1)] = position;
      return withControlPoints(base, next);
    }

    Offset f1 = pts[0];
    Offset f2 = pts.length > 1 ? pts[1] : pts[0];
    final a0 = params.rx;

    if (index >= 2) {
      final tip = position;
      final center = Offset((f1.dx + f2.dx) / 2, (f1.dy + f2.dy) / 2);
      final cLin = (f2 - f1).distance / 2;
      final a = math.max(
        ((tip - f1).distance + (tip - f2).distance) / 2,
        cLin + 1e-3,
      );
      final b = math.sqrt(math.max(a * a - cLin * cLin, 1e-6));
      final ang = math.atan2(f2.dy - f1.dy, f2.dx - f1.dx);
      return withControlPoints(
        base.copyWith(
          kind: ShapeKind.ellipse,
          rotationDeg: 0,
        ),
        ellipseControlPoints(center, a, b, ang),
      );
    }

    if (index == 0) {
      f1 = position;
    } else {
      f2 = position;
    }
    var center = Offset((f1.dx + f2.dx) / 2, (f1.dy + f2.dy) / 2);
    var cLin = (f2 - f1).distance / 2;
    final a = math.max(a0, cLin + 1e-3);
    if (cLin >= a) {
      final ang = math.atan2(f2.dy - f1.dy, f2.dx - f1.dx);
      final maxC = a - 1e-3;
      f1 = Offset(
        center.dx - math.cos(ang) * maxC,
        center.dy - math.sin(ang) * maxC,
      );
      f2 = Offset(
        center.dx + math.cos(ang) * maxC,
        center.dy + math.sin(ang) * maxC,
      );
      center = Offset((f1.dx + f2.dx) / 2, (f1.dy + f2.dy) / 2);
      cLin = maxC;
    }
    final b = math.sqrt(math.max(a * a - cLin * cLin, 1e-6));
    final ang = math.atan2(f2.dy - f1.dy, f2.dx - f1.dx);
    return withControlPoints(
      base.copyWith(
        kind: ShapeKind.ellipse,
        rotationDeg: 0,
      ),
      ellipseControlPoints(center, a, b, ang),
    );
  }

  static ShapeConfig moveCircleControlPoint(
    ShapeConfig base,
    int index,
    Offset position,
  ) {
    final pts = controlPointsOf(base);
    final center = pts.isNotEmpty ? pts.first : base.bounds.center;
    final r0 = pts.length >= 2
        ? (pts[1] - pts[0]).distance
        : math.min(base.bounds.width, base.bounds.height) / 2;
    if (index == 0) {
      final r = math.max(r0, 1.0);
      return withControlPoints(
        base.copyWith(kind: ShapeKind.circle, rotationDeg: 0),
        [position, Offset(position.dx + r, position.dy)],
      );
    }
    final r = math.max((position - center).distance, 1.0);
    return withControlPoints(
      base.copyWith(kind: ShapeKind.circle, rotationDeg: 0),
      [center, Offset(center.dx + r, center.dy)],
    );
  }

  /// Interior corner angles (degrees) for a closed polygonal control polygon.
  static List<({Offset at, double degrees})> interiorAngles(
    List<Offset> verts,
  ) {
    if (verts.length < 3) return const [];
    final n = verts.length;
    final out = <({Offset at, double degrees})>[];
    for (var i = 0; i < n; i++) {
      final prev = verts[(i - 1 + n) % n];
      final cur = verts[i];
      final next = verts[(i + 1) % n];
      final v1 = prev - cur;
      final v2 = next - cur;
      final d1 = v1.distance;
      final d2 = v2.distance;
      if (d1 < 1e-6 || d2 < 1e-6) continue;
      final dot = ((v1.dx * v2.dx + v1.dy * v2.dy) / (d1 * d2)).clamp(-1.0, 1.0);
      final deg = math.acos(dot) * 180 / math.pi;
      out.add((at: cur, degrees: deg));
    }
    return out;
  }

  static bool showsInteriorAngles(ShapeKind kind) {
    return const {
      ShapeKind.rectangle,
      ShapeKind.triangleIsosceles,
      ShapeKind.triangleRight,
      ShapeKind.polygon,
      ShapeKind.star,
    }.contains(kind);
  }

  /// AABB of [points], expanded to at least 1×1.
  static Rect boundsOf(Iterable<Offset> points) {
    final list = points.toList();
    if (list.isEmpty) return const Rect.fromLTWH(0, 0, 1, 1);
    var minX = list.first.dx, maxX = list.first.dx;
    var minY = list.first.dy, maxY = list.first.dy;
    for (final p in list) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    if (maxX - minX < 1) maxX = minX + 1;
    if (maxY - minY < 1) maxY = minY + 1;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Sync bounds/start/end from vertices for a config of [kind].
  static ShapeConfig withControlPoints(
    ShapeConfig base,
    List<Offset> controlPoints,
  ) {
    final pts = List<Offset>.from(controlPoints);
    final b = boundsOf(pts);
    final start = pts.isNotEmpty ? pts.first : b.topLeft;
    final end = pts.length > 1 ? pts.last : b.bottomRight;
    return base.copyWith(
      bounds: b,
      start: start,
      end: end,
      vertices: pts,
    );
  }

  static ShapeConfig seedFromDrag(
    ShapeConfig template,
    Offset a,
    Offset b,
  ) {
    final kind = template.kind;
    switch (kind) {
      case ShapeKind.line:
      case ShapeKind.arrow:
      case ShapeKind.doubleArrow:
      case ShapeKind.parabola:
      case ShapeKind.spring:
      case ShapeKind.fixedEnd:
        return withControlPoints(template.copyWith(kind: kind), [a, b]);
      case ShapeKind.triangleIsosceles:
      case ShapeKind.triangleRight:
        final box = Rect.fromPoints(a, b);
        final verts = kind == ShapeKind.triangleRight
            ? <Offset>[
                box.bottomLeft,
                box.bottomRight,
                box.topLeft,
              ]
            : <Offset>[
                Offset(box.center.dx, box.top),
                box.bottomLeft,
                box.bottomRight,
              ];
        return withControlPoints(
          template.copyWith(kind: kind, data: {...template.data, 'equilateral': false}),
          verts,
        );
      case ShapeKind.polygon:
        final box = Rect.fromPoints(a, b);
        return withControlPoints(
          template,
          _regularPolygonVertices(box, math.max(3, template.detail)),
        );
      case ShapeKind.star:
        return withControlPoints(template, _starVertices(Rect.fromPoints(a, b)));
      case ShapeKind.circle:
        final c = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
        final r = math.max((b - a).distance / 2, 0.5);
        return withControlPoints(template.copyWith(kind: kind, rotationDeg: 0), [
          c,
          Offset(c.dx + r, c.dy),
        ]);
      case ShapeKind.ellipse:
        final box = Rect.fromPoints(a, b);
        return withControlPoints(
          template.copyWith(kind: kind, rotationDeg: 0),
          ellipseControlPoints(
            box.center,
            math.max(box.width / 2, 0.5),
            math.max(box.height / 2, 0.5),
            0,
          ),
        );
      default:
        final box = Rect.fromPoints(a, b);
        return withControlPoints(template, [
          box.topLeft,
          box.topRight,
          box.bottomRight,
          box.bottomLeft,
        ]);
    }
  }

  // —— Fitters (stroke points → ShapeConfig) ——————————————————————————————

  static ShapeConfig? fitLine(List<Offset> points, {ShapeKind kind = ShapeKind.line}) {
    if (points.length < 2) return null;
    final (start, end) = _fitLineEndpoints(points);
    if ((end - start).distance < 2) return null;
    return withControlPoints(
      ShapeConfig(kind: kind, bounds: boundsOf([start, end])),
      [start, end],
    );
  }

  static ShapeConfig? fitRectangle(List<Offset> points) {
    if (points.length < 3) return null;
    final oriented = fitOrientedRect(points);
    if (oriented == null) return null;
    final corners = oriented.corners;
    final aspect = oriented.width / math.max(oriented.height, 1e-6);
    final isSquare = aspect > 0.9 && aspect < 1.1;
    final verts = isSquare
        ? _squareCorners(
            oriented.center,
            math.max(oriented.width, oriented.height) / 2,
            oriented.angleRad,
          )
        : corners;
    return withControlPoints(
      ShapeConfig(
        kind: ShapeKind.rectangle,
        bounds: boundsOf(verts),
        rotationDeg: 0, // rotation baked into vertices
      ),
      verts,
    );
  }

  /// Always an ellipse. A round stroke yields rx≈ry (a circle as a special case).
  static ShapeConfig? fitEllipse(List<Offset> points) {
    if (points.length < 5) {
      final box = boundsOf(points);
      if (box.width < 2 || box.height < 2) return null;
      final center = box.center;
      return withControlPoints(
        ShapeConfig(kind: ShapeKind.ellipse, bounds: box, rotationDeg: 0),
        ellipseControlPoints(center, box.width / 2, box.height / 2, 0),
      );
    }
    final fit = fitEllipseAlgebraic(points);
    if (fit == null) return null;
    final cps = ellipseControlPoints(fit.center, fit.rx, fit.ry, fit.angleRad);
    return withControlPoints(
      ShapeConfig(
        kind: ShapeKind.ellipse,
        bounds: boundsOf(cps),
        rotationDeg: 0, // orientation baked into foci
      ),
      cps,
    );
  }

  static ShapeConfig? fitTriangle(List<Offset> points) {
    if (points.length < 3) return null;
    final corners = fitTriangleCorners(points);
    if (corners == null || corners.length != 3) return null;
    return withControlPoints(
      ShapeConfig(
        kind: ShapeKind.triangleIsosceles,
        bounds: boundsOf(corners),
        data: const {'equilateral': false},
      ),
      corners,
    );
  }

  static ShapeConfig? fitPolygon(List<Offset> points, {int sides = 5}) {
    final box = boundsOf(points);
    if (box.shortestSide < 2) return null;
    final n = math.max(3, sides);
    return withControlPoints(
      ShapeConfig(kind: ShapeKind.polygon, bounds: box, detail: n),
      _regularPolygonVertices(box, n),
    );
  }

  static ShapeConfig? fitStar(List<Offset> points) {
    final box = boundsOf(points);
    if (box.shortestSide < 2) return null;
    return withControlPoints(
      ShapeConfig(kind: ShapeKind.star, bounds: box),
      _starVertices(box),
    );
  }

  /// Oriented min-area rect via convex-hull edge calipers (PCA fallback).
  static ({
    Offset center,
    double width,
    double height,
    double angleRad,
    List<Offset> corners,
  })? fitOrientedRect(List<Offset> points) {
    if (points.length < 2) return null;
    final hull = _convexHull(points);
    if (hull.length >= 3) {
      final fromHull = _minAreaRectFromHull(hull);
      if (fromHull != null) return fromHull;
    }
    return _orientedRectFromPca(points);
  }

  static ({
    Offset center,
    double width,
    double height,
    double angleRad,
    List<Offset> corners,
  })? _minAreaRectFromHull(List<Offset> hull) {
    final n = hull.length;
    var bestArea = double.infinity;
    ({
      Offset center,
      double width,
      double height,
      double angleRad,
      List<Offset> corners,
    })? best;
    for (var i = 0; i < n; i++) {
      final a = hull[i];
      final b = hull[(i + 1) % n];
      final edge = b - a;
      final len = edge.distance;
      if (len < 1e-6) continue;
      final vx = edge.dx / len;
      final vy = edge.dy / len;
      final px = -vy;
      final py = vx;
      var tMin = double.infinity, tMax = -double.infinity;
      var sMin = double.infinity, sMax = -double.infinity;
      for (final p in hull) {
        final dx = p.dx - a.dx, dy = p.dy - a.dy;
        final t = dx * vx + dy * vy;
        final s = dx * px + dy * py;
        if (t < tMin) tMin = t;
        if (t > tMax) tMax = t;
        if (s < sMin) sMin = s;
        if (s > sMax) sMax = s;
      }
      final w = math.max(tMax - tMin, 1.0);
      final h = math.max(sMax - sMin, 1.0);
      final area = w * h;
      if (area >= bestArea) continue;
      bestArea = area;
      final midT = (tMin + tMax) / 2;
      final midS = (sMin + sMax) / 2;
      final c = Offset(a.dx + vx * midT + px * midS, a.dy + vy * midT + py * midS);
      final ang = _snapRectAngle(math.atan2(vy, vx));
      // Rebuild corners in snapped frame if snapped.
      final cosA = math.cos(ang), sinA = math.sin(ang);
      final hw = w / 2, hh = h / 2;
      // If angle snapped, reproject extents in snapped axes for consistent corners.
      final useSnap = (ang - math.atan2(vy, vx)).abs() > 1e-6;
      late final List<Offset> corners;
      late final Offset center;
      late final double outW, outH, outAng;
      if (useSnap) {
        var uMin = double.infinity, uMax = -double.infinity;
        var vMin = double.infinity, vMax = -double.infinity;
        for (final p in hull) {
          final dx = p.dx - c.dx, dy = p.dy - c.dy;
          final u = dx * cosA + dy * sinA;
          final v = -dx * sinA + dy * cosA;
          if (u < uMin) uMin = u;
          if (u > uMax) uMax = u;
          if (v < vMin) vMin = v;
          if (v > vMax) vMax = v;
        }
        outW = math.max(uMax - uMin, 1.0);
        outH = math.max(vMax - vMin, 1.0);
        final midU = (uMin + uMax) / 2;
        final midV = (vMin + vMax) / 2;
        center = Offset(c.dx + cosA * midU - sinA * midV, c.dy + sinA * midU + cosA * midV);
        final ohw = outW / 2, ohh = outH / 2;
        corners = [
          Offset(center.dx - cosA * ohw + sinA * ohh, center.dy - sinA * ohw - cosA * ohh),
          Offset(center.dx + cosA * ohw + sinA * ohh, center.dy + sinA * ohw - cosA * ohh),
          Offset(center.dx + cosA * ohw - sinA * ohh, center.dy + sinA * ohw + cosA * ohh),
          Offset(center.dx - cosA * ohw - sinA * ohh, center.dy - sinA * ohw + cosA * ohh),
        ];
        outAng = ang;
      } else {
        center = c;
        outW = w;
        outH = h;
        outAng = math.atan2(vy, vx);
        corners = [
          Offset(c.dx - vx * hw - px * hh, c.dy - vy * hw - py * hh),
          Offset(c.dx + vx * hw - px * hh, c.dy + vy * hw - py * hh),
          Offset(c.dx + vx * hw + px * hh, c.dy + vy * hw + py * hh),
          Offset(c.dx - vx * hw + px * hh, c.dy - vy * hw + py * hh),
        ];
      }
      best = (
        center: center,
        width: outW,
        height: outH,
        angleRad: outAng,
        corners: corners,
      );
    }
    return best;
  }

  static ({
    Offset center,
    double width,
    double height,
    double angleRad,
    List<Offset> corners,
  })? _orientedRectFromPca(List<Offset> points) {
    final center = _centroid(points);
    final (vx, vy) = _principalAxis(points, center);
    final perpX = -vy, perpY = vx;
    var tMin = double.infinity, tMax = -double.infinity;
    var sMin = double.infinity, sMax = -double.infinity;
    for (final p in points) {
      final dx = p.dx - center.dx, dy = p.dy - center.dy;
      final t = dx * vx + dy * vy;
      final s = dx * perpX + dy * perpY;
      if (t < tMin) tMin = t;
      if (t > tMax) tMax = t;
      if (s < sMin) sMin = s;
      if (s > sMax) sMax = s;
    }
    final w = math.max(tMax - tMin, 1.0);
    final h = math.max(sMax - sMin, 1.0);
    final midT = (tMin + tMax) / 2;
    final midS = (sMin + sMax) / 2;
    final c = Offset(center.dx + vx * midT + perpX * midS, center.dy + vy * midT + perpY * midS);
    final hw = w / 2, hh = h / 2;
    final ang = _snapRectAngle(math.atan2(vy, vx));
    final cosA = math.cos(ang), sinA = math.sin(ang);
    final corners = <Offset>[
      Offset(c.dx - cosA * hw + sinA * hh, c.dy - sinA * hw - cosA * hh),
      Offset(c.dx + cosA * hw + sinA * hh, c.dy + sinA * hw - cosA * hh),
      Offset(c.dx + cosA * hw - sinA * hh, c.dy + sinA * hw + cosA * hh),
      Offset(c.dx - cosA * hw - sinA * hh, c.dy - sinA * hw + cosA * hh),
    ];
    return (
      center: c,
      width: w,
      height: h,
      angleRad: ang,
      corners: corners,
    );
  }

  /// Snap near-axis angles so upright squares/rects stay upright.
  static double _snapRectAngle(double ang) {
    const snap = 10 * math.pi / 180;
    final n = (ang / (math.pi / 2)).round();
    final snapped = n * (math.pi / 2);
    var d = ang - snapped;
    while (d > math.pi) {
      d -= 2 * math.pi;
    }
    while (d < -math.pi) {
      d += 2 * math.pi;
    }
    if (d.abs() <= snap) return snapped;
    return ang;
  }

  /// Direct least-squares ellipse with geometric angle refinement.
  ///
  /// PCA on freehand perimeter points is biased toward denser sampling, so
  /// inclination is taken from the algebraic conic (then refined), while
  /// radii use scaled extents in that frame.
  static ({Offset center, double rx, double ry, double angleRad})?
      fitEllipseAlgebraic(List<Offset> points) {
    if (points.length < 5) return null;
    final c0 = _centroid(points);
    final xs = <double>[];
    final ys = <double>[];
    for (final p in points) {
      xs.add(p.dx - c0.dx);
      ys.add(p.dy - c0.dy);
    }
    final n = xs.length;

    var center = c0;
    double? seedAngle;

    try {
      final a = List.generate(n, (i) => xs[i] * xs[i]);
      final b = List.generate(n, (i) => xs[i] * ys[i]);
      final c = List.generate(n, (i) => ys[i] * ys[i]);
      final d = List.generate(n, (i) => xs[i]);
      final e = List.generate(n, (i) => ys[i]);
      final ata = List.generate(5, (_) => List<double>.filled(5, 0));
      final atb = List<double>.filled(5, 0);
      for (var i = 0; i < n; i++) {
        final row = [a[i], b[i], c[i], d[i], e[i]];
        for (var r = 0; r < 5; r++) {
          atb[r] += row[r];
          for (var k = 0; k < 5; k++) {
            ata[r][k] += row[r] * row[k];
          }
        }
      }
      final sol = _solve5(ata, atb);
      if (sol != null) {
        final A = sol[0], B = sol[1], C = sol[2], D = sol[3], E = sol[4];
        const F = -1.0;
        final disc = B * B - 4 * A * C;
        if (disc < 0) {
          seedAngle = 0.5 * math.atan2(B, A - C);
          final geo = _ellipseFromConic(A, B, C, D, E, F, c0);
          if (geo != null) {
            seedAngle = geo.angleRad;
            center = geo.center;
          } else {
            final denom = disc;
            final cx = (2 * C * D - B * E) / denom;
            final cy = (2 * A * E - B * D) / denom;
            if (cx.isFinite && cy.isFinite) {
              center = Offset(c0.dx + cx, c0.dy + cy);
            }
          }
        }
      }
    } catch (_) {
      // Fall through to geometric refine from PCA seed.
    }

    if (seedAngle == null || !seedAngle.isFinite) {
      final (vx, vy) = _principalAxis(points, center);
      seedAngle = math.atan2(vy, vx);
    }

    return _refineOrientedEllipse(points, center, seedAngle);
  }

  /// Convert conic Ax²+Bxy+Cy²+Dx+Ey+F=0 (in coords relative to [origin]) to
  /// geometric ellipse. Returns null if not an ellipse.
  static ({Offset center, double rx, double ry, double angleRad})?
      _ellipseFromConic(
    double A,
    double B,
    double C,
    double D,
    double E,
    double F,
    Offset origin,
  ) {
    final disc = B * B - 4 * A * C;
    if (disc >= 0) return null;
    final denom = disc;
    final cx = (2 * C * D - B * E) / denom;
    final cy = (2 * A * E - B * D) / denom;
    if (!cx.isFinite || !cy.isFinite) return null;

    final F2 = A * cx * cx + B * cx * cy + C * cy * cy + D * cx + E * cy + F;
    if (F2.abs() < 1e-18) return null;

    final angle = 0.5 * math.atan2(B, A - C);
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    final Ap = A * cosA * cosA + B * cosA * sinA + C * sinA * sinA;
    final Cp = A * sinA * sinA - B * cosA * sinA + C * cosA * cosA;
    if (Ap.abs() < 1e-18 || Cp.abs() < 1e-18) return null;
    if (-F2 / Ap <= 0 || -F2 / Cp <= 0) return null;

    var rx = math.sqrt((-F2 / Ap).abs());
    var ry = math.sqrt((-F2 / Cp).abs());
    var ang = angle;
    if (ry > rx) {
      final t = rx;
      rx = ry;
      ry = t;
      ang += math.pi / 2;
    }
    if (!rx.isFinite || !ry.isFinite || rx < 1e-3 || ry < 1e-3) return null;
    return (
      center: Offset(origin.dx + cx, origin.dy + cy),
      rx: rx,
      ry: ry,
      angleRad: ang,
    );
  }

  /// Search nearby orientations; pick the angle with lowest geometric residual.
  static ({Offset center, double rx, double ry, double angleRad})
      _refineOrientedEllipse(
    List<Offset> points,
    Offset center,
    double seedAngle,
  ) {
    var bestAngle = seedAngle;
    var bestCost = double.infinity;
    ({double rx, double ry})? bestAxes;

    void consider(double ang) {
      final axes = _ellipseAxesAtAngle(points, center, ang);
      final cost = _ellipseResidual(points, center, axes.rx, axes.ry, ang);
      if (cost < bestCost) {
        bestCost = cost;
        bestAngle = ang;
        bestAxes = axes;
      }
    }

    // ±35° around seed in 2.5° steps, plus axis-swap candidates.
    for (var i = -14; i <= 14; i++) {
      consider(seedAngle + i * (2.5 * math.pi / 180));
    }
    consider(seedAngle + math.pi / 2);
    consider(seedAngle - math.pi / 2);

    // Fine pass ±4° around best in 0.5° steps.
    final coarse = bestAngle;
    for (var i = -8; i <= 8; i++) {
      consider(coarse + i * (0.5 * math.pi / 180));
    }

    final axes = bestAxes ?? _ellipseAxesAtAngle(points, center, bestAngle);
    var rx = axes.rx;
    var ry = axes.ry;
    var ang = bestAngle;
    if (ry > rx) {
      final t = rx;
      rx = ry;
      ry = t;
      ang += math.pi / 2;
    }
    return (
      center: center,
      rx: math.max(rx, 1.0),
      ry: math.max(ry, 1.0),
      angleRad: ang,
    );
  }

  static ({double rx, double ry}) _ellipseAxesAtAngle(
    List<Offset> points,
    Offset center,
    double angleRad,
  ) {
    final cosA = math.cos(angleRad);
    final sinA = math.sin(angleRad);
    var tMax = 0.0, sMax = 0.0;
    for (final p in points) {
      final dx = p.dx - center.dx, dy = p.dy - center.dy;
      final t = dx * cosA + dy * sinA;
      final s = -dx * sinA + dy * cosA;
      tMax = math.max(tMax, t.abs());
      sMax = math.max(sMax, s.abs());
    }
    var rx = math.max(tMax, 1.0);
    var ry = math.max(sMax, 1.0);
    var sumQ = 0.0;
    for (final p in points) {
      final dx = p.dx - center.dx, dy = p.dy - center.dy;
      final t = dx * cosA + dy * sinA;
      final s = -dx * sinA + dy * cosA;
      sumQ += (t / rx) * (t / rx) + (s / ry) * (s / ry);
    }
    if (points.isNotEmpty && sumQ > 1e-8) {
      final scale = math.sqrt(sumQ / points.length);
      rx *= scale;
      ry *= scale;
    }
    return (rx: math.max(rx, 1.0), ry: math.max(ry, 1.0));
  }

  static double _ellipseResidual(
    List<Offset> points,
    Offset center,
    double rx,
    double ry,
    double angleRad,
  ) {
    if (rx < 1e-6 || ry < 1e-6) return double.infinity;
    final cosA = math.cos(angleRad);
    final sinA = math.sin(angleRad);
    var sum = 0.0;
    for (final p in points) {
      final dx = p.dx - center.dx, dy = p.dy - center.dy;
      final u = dx * cosA + dy * sinA;
      final v = -dx * sinA + dy * cosA;
      final q = (u / rx) * (u / rx) + (v / ry) * (v / ry);
      if (q <= 1e-12) {
        sum += 1.0;
        continue;
      }
      final radial = math.sqrt(q) - 1.0;
      sum += radial * radial;
    }
    return sum;
  }

  /// Mean squared radial residual for an algebraic ellipse fit (lower = better).
  static double ellipseFitError(
    List<Offset> points, {
    required Offset center,
    required double rx,
    required double ry,
    required double angleRad,
  }) {
    if (points.isEmpty) return double.infinity;
    return _ellipseResidual(points, center, rx, ry, angleRad) / points.length;
  }

  /// Mean squared distance of points to the nearest edge of an oriented rect,
  /// normalized by half the longer side so it is comparable to [ellipseFitError].
  static double orientedRectFitError(
    List<Offset> points, {
    required Offset center,
    required double width,
    required double height,
    required double angleRad,
  }) {
    if (points.isEmpty || width < 1e-6 || height < 1e-6) {
      return double.infinity;
    }
    final cosA = math.cos(angleRad);
    final sinA = math.sin(angleRad);
    final hw = width / 2;
    final hh = height / 2;
    final scale = math.max(hw, hh);
    if (scale < 1e-6) return double.infinity;
    final invScaleSq = 1.0 / (scale * scale);
    var sum = 0.0;
    for (final p in points) {
      final dx = p.dx - center.dx, dy = p.dy - center.dy;
      final u = dx * cosA + dy * sinA;
      final v = -dx * sinA + dy * cosA;
      final ou = u.abs() - hw;
      final ov = v.abs() - hh;
      double d;
      if (ou <= 0 && ov <= 0) {
        // Inside: distance to nearest edge.
        d = math.min(-ou, -ov);
      } else if (ou > 0 && ov > 0) {
        d = math.sqrt(ou * ou + ov * ov);
      } else if (ou > 0) {
        d = ou;
      } else {
        d = ov;
      }
      sum += d * d * invScaleSq;
    }
    return sum / points.length;
  }

  static ({Offset center, double rx, double ry, double angleRad})
      _ellipseFromPcaExtents(List<Offset> points, Offset center) {
    final (vx, vy) = _principalAxis(points, center);
    return _refineOrientedEllipse(points, center, math.atan2(vy, vx));
  }

  /// Dominant 3 corners via convex hull + max-area triangle (or DP extrema).
  static List<Offset>? fitTriangleCorners(List<Offset> points) {
    if (points.length < 3) return null;
    final hull = _convexHull(points);
    if (hull.length < 3) return null;
    if (hull.length == 3) return hull;
    // Pick 3 hull points maximizing triangle area.
    var bestArea = -1.0;
    List<Offset> best = [hull[0], hull[1], hull[2]];
    for (var i = 0; i < hull.length; i++) {
      for (var j = i + 1; j < hull.length; j++) {
        for (var k = j + 1; k < hull.length; k++) {
          final area = _triangleArea(hull[i], hull[j], hull[k]).abs();
          if (area > bestArea) {
            bestArea = area;
            best = [hull[i], hull[j], hull[k]];
          }
        }
      }
    }
    if (bestArea < 1.0) return null;
    // Order CCW starting from top-most for stable editing.
    best.sort((a, b) {
      if (a.dy != b.dy) return a.dy.compareTo(b.dy);
      return a.dx.compareTo(b.dx);
    });
    final tip = best.first;
    final rest = best.sublist(1)..sort((a, b) => a.dx.compareTo(b.dx));
    return [tip, rest[0], rest[1]];
  }

  // —— Internals ——————————————————————————————————————————————————————————

  static (Offset, Offset) _fitLineEndpoints(List<Offset> points) {
    final center = _centroid(points);
    final (vx, vy) = _principalAxis(points, center);
    var tMin = double.infinity, tMax = -double.infinity;
    for (final p in points) {
      final t = (p.dx - center.dx) * vx + (p.dy - center.dy) * vy;
      if (t < tMin) tMin = t;
      if (t > tMax) tMax = t;
    }
    // Prefer chord direction if endpoints of stroke are meaningful.
    final chord = points.last - points.first;
    if (chord.distance > 2) {
      final cvx = chord.dx / chord.distance;
      final cvy = chord.dy / chord.distance;
      var cMin = double.infinity, cMax = -double.infinity;
      for (final p in points) {
        final t = (p.dx - points.first.dx) * cvx + (p.dy - points.first.dy) * cvy;
        if (t < cMin) cMin = t;
        if (t > cMax) cMax = t;
      }
      return (
        Offset(points.first.dx + cvx * cMin, points.first.dy + cvy * cMin),
        Offset(points.first.dx + cvx * cMax, points.first.dy + cvy * cMax),
      );
    }
    return (
      Offset(center.dx + vx * tMin, center.dy + vy * tMin),
      Offset(center.dx + vx * tMax, center.dy + vy * tMax),
    );
  }

  static Offset _centroid(List<Offset> points) {
    var sx = 0.0, sy = 0.0;
    for (final p in points) {
      sx += p.dx;
      sy += p.dy;
    }
    return Offset(sx / points.length, sy / points.length);
  }

  static (double, double) _principalAxis(List<Offset> points, Offset center) {
    var sxx = 0.0, syy = 0.0, sxy = 0.0;
    for (final p in points) {
      final dx = p.dx - center.dx, dy = p.dy - center.dy;
      sxx += dx * dx;
      syy += dy * dy;
      sxy += dx * dy;
    }
    final angle = 0.5 * math.atan2(2 * sxy, sxx - syy);
    return (math.cos(angle), math.sin(angle));
  }

  static List<Offset> _squareCorners(
    Offset center,
    double half,
    double angleRad,
  ) {
    final c = math.cos(angleRad), s = math.sin(angleRad);
    Offset local(double x, double y) => Offset(
          center.dx + x * c - y * s,
          center.dy + x * s + y * c,
        );
    return [
      local(-half, -half),
      local(half, -half),
      local(half, half),
      local(-half, half),
    ];
  }

  static List<Offset> _ellipseBoxCorners(
    Offset center,
    double rx,
    double ry,
    double angleRad,
  ) {
    final c = math.cos(angleRad), s = math.sin(angleRad);
    Offset local(double x, double y) => Offset(
          center.dx + x * c - y * s,
          center.dy + x * s + y * c,
        );
    return [
      local(-rx, -ry),
      local(rx, -ry),
      local(rx, ry),
      local(-rx, ry),
    ];
  }

  static List<Offset> _regularPolygonVertices(Rect rect, int sides) {
    final n = math.max(3, sides);
    final cx = rect.center.dx, cy = rect.center.dy;
    final rx = rect.width / 2, ry = rect.height / 2;
    final out = <Offset>[];
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + (2 * math.pi * i / n);
      out.add(Offset(cx + rx * math.cos(a), cy + ry * math.sin(a)));
    }
    return out;
  }

  static List<Offset> _starVertices(Rect rect) {
    final cx = rect.center.dx, cy = rect.center.dy;
    final ro = math.min(rect.width, rect.height) / 2;
    final ri = ro * 0.4;
    final out = <Offset>[];
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + (math.pi * i / 5);
      final r = i.isEven ? ro : ri;
      out.add(Offset(cx + r * math.cos(a), cy + r * math.sin(a)));
    }
    return out;
  }

  static double _triangleArea(Offset a, Offset b, Offset c) {
    return ((b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx)) / 2;
  }

  static List<Offset> _convexHull(List<Offset> points) {
    final pts = List<Offset>.from(points)
      ..sort((a, b) {
        if (a.dx != b.dx) return a.dx.compareTo(b.dx);
        return a.dy.compareTo(b.dy);
      });
    if (pts.length <= 2) return pts;

    double cross(Offset o, Offset a, Offset b) =>
        (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);

    final lower = <Offset>[];
    for (final p in pts) {
      while (lower.length >= 2 &&
          cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }
    final upper = <Offset>[];
    for (final p in pts.reversed) {
      while (upper.length >= 2 &&
          cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }
    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  static List<double>? _solve5(List<List<double>> a, List<double> b) {
    // Gaussian elimination with partial pivot.
    final m = List.generate(5, (i) => [...a[i], b[i]]);
    for (var col = 0; col < 5; col++) {
      var pivot = col;
      for (var r = col + 1; r < 5; r++) {
        if (m[r][col].abs() > m[pivot][col].abs()) pivot = r;
      }
      if (m[pivot][col].abs() < 1e-12) return null;
      final tmp = m[col];
      m[col] = m[pivot];
      m[pivot] = tmp;
      final div = m[col][col];
      for (var c = col; c < 6; c++) {
        m[col][c] /= div;
      }
      for (var r = 0; r < 5; r++) {
        if (r == col) continue;
        final f = m[r][col];
        for (var c = col; c < 6; c++) {
          m[r][c] -= f * m[col][c];
        }
      }
    }
    return [m[0][5], m[1][5], m[2][5], m[3][5], m[4][5]];
  }
}
