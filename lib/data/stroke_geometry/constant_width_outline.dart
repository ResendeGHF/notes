// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui';

import 'package:saber/data/stroke_geometry/point_vector.dart';
import 'package:saber/data/stroke_geometry/stroke_options.dart';

/// Lightweight replacement for perfect_freehand's [getStroke].
///
/// Returns a single closed outline (no triangulated mesh), so translucent fills
/// do not show darker overlap artifacts.
List<Offset> getStroke(
  List<PointVector> points, {
  StrokeOptions? options,
  bool rememberSimulatedPressure = false,

  /// Fountain-style tips: skip tip-radius blending and chord cap tangents.
  bool preserveLegacyTips = false,

  /// When set, overrides [StrokeEndOptions.cap] for the start of this outline.
  bool? startCap,

  /// When set, overrides [StrokeEndOptions.cap] for the end of this outline.
  bool? endCap,

  /// When false, start taper is ignored (open ribbon / interior chunk).
  bool applyStartTaper = true,

  /// When false, end taper is ignored (open ribbon / interior chunk).
  bool applyEndTaper = true,

  /// Advanced Pen: chord-orient caps only on true capped ends.
  bool capChordOnlyAtCappedEnds = false,

  /// Advanced Pen: round both sides of a hairpin into a ballpoint-style tip bulb.
  bool dualSidedReturnJoins = false,

  /// Minimum arc length used when estimating cap tangents. Null keeps the
  /// default lookahead (other pens). Advanced Pen passes a larger value so
  /// put-down jitter does not rotate the hemisphere.
  double? capTangentMinLookahead,

  /// Legacy: tipTravelTangent on the decimated spine (stops at the first
  /// corner). Production Advanced Pen leaves this off — short put-down stems
  /// rotate caps off the travel tangent that Ballpoint / Advanced Pencil use.
  bool preferStemCapTangents = false,

  /// Advanced Pen: Ballpoint-style hemispheres along the local travel chord,
  /// with the first/last spine edge forced onto that chord so the bulb is not
  /// a rotated arc centered on the tip.
  bool meshStyleCaps = false,

  /// When set (Advanced Pen), start-cap travel ignores Catmull tip bending.
  (double, double)? startTravelTangent,

  /// When set (Advanced Pen), end-cap travel ignores Catmull tip bending.
  (double, double)? endTravelTangent,
}) {
  // Simulated-pressure rewriting is intentionally unsupported; callers that
  // need pressure already bake it into [PointVector.pressure] or use mesh pens.
  // ignore: unused_local_variable
  final _ = rememberSimulatedPressure;

  options ??= StrokeOptions();
  if (points.isEmpty || options.size <= 0) return const [];

  final capStart = startCap ?? options.start.cap;
  final capEnd = endCap ?? options.end.cap;
  final startTaper = applyStartTaper && options.start.taperEnabled
      ? (options.start.customTaper ?? options.size)
      : 0.0;
  final endTaper = applyEndTaper && options.end.taperEnabled
      ? (options.end.customTaper ?? options.size)
      : 0.0;

  final effectiveThinning = options.thinning * options.pressureSensitivity;
  final useVariable =
      effectiveThinning != 0 ||
      options.velocityThinning > 0 ||
      startTaper > 0 ||
      endTaper > 0 ||
      options.minSizeRatio != StrokeOptions.defaultMinSizeRatio ||
      options.maxSizeRatio != StrokeOptions.defaultMaxSizeRatio;

  if (!useVariable) {
    return buildConstantWidthOutline(
      points,
      radius: options.size / 2,
      roundCaps: capStart || capEnd,
      startCap: capStart,
      endCap: capEnd,
      capChordOnlyAtCappedEnds: capChordOnlyAtCappedEnds,
      dualSidedReturnJoins: dualSidedReturnJoins,
      capTangentMinLookahead: capTangentMinLookahead,
      preferStemCapTangents: preferStemCapTangents,
      meshStyleCaps: meshStyleCaps,
      startTravelTangent: startTravelTangent,
      endTravelTangent: endTravelTangent,
    );
  }

  return buildVariableWidthOutline(
    points,
    size: options.size,
    thinning: effectiveThinning,
    easing: options.easing,
    roundCaps: capStart || capEnd,
    startCap: capStart,
    endCap: capEnd,
    startTaper: startTaper,
    endTaper: endTaper,
    startEasing: options.start.easing,
    endEasing: options.end.easing,
    velocityThinning: options.velocityThinning,
    minSizeRatio: options.minSizeRatio,
    maxSizeRatio: options.maxSizeRatio,
    stabilizeTips: !preserveLegacyTips,
    useChordCapTangents: !preserveLegacyTips,
    capChordOnlyAtCappedEnds: capChordOnlyAtCappedEnds,
    dualSidedReturnJoins: dualSidedReturnJoins,
    capTangentMinLookahead: capTangentMinLookahead,
    preferStemCapTangents: preferStemCapTangents,
    meshStyleCaps: meshStyleCaps,
    startTravelTangent: startTravelTangent,
    endTravelTangent: endTravelTangent,
  );
}

/// Builds a single closed outline for a constant-width stroke.
///
/// Unlike a triangulated ribbon mesh, this outline is filled once, so
/// translucent ink (highlighter) does not show darker overlap artifacts.
///
/// The spine is decimated and joins use stable segment normals (with round
/// outer joins) so slow/jittery input and sharp turns do not flip caps or
/// self-intersect into "holes" inside the stroke body.
List<Offset> buildConstantWidthOutline(
  List<PointVector> points, {
  required double radius,
  required bool roundCaps,
  bool? startCap,
  bool? endCap,
  int capSegments = 10,
  int joinSegments = 6,
  bool capChordOnlyAtCappedEnds = false,
  bool dualSidedReturnJoins = false,
  double? capTangentMinLookahead,
  bool preferStemCapTangents = false,
  bool meshStyleCaps = false,
  (double, double)? startTravelTangent,
  (double, double)? endTravelTangent,
}) {
  if (points.isEmpty || radius <= 0) return const [];

  final capStart = startCap ?? roundCaps;
  final capEnd = endCap ?? roundCaps;

  final spine = decimateStrokeSpine(
    points,
    minDistance: math.max(0.5, radius * 0.28),
  );
  if (spine.isEmpty) return const [];
  if (spine.length == 1) {
    return _singlePointOutline(
      spine.first,
      radius,
      roundCaps: capStart || capEnd,
      capSegments: capSegments,
    );
  }

  final radii = List<double>.filled(spine.length, radius);
  return _outlineFromRadii(
    spine,
    radii,
    startCap: capStart,
    endCap: capEnd,
    capSegments: capSegments,
    joinSegments: joinSegments,
    useChordCapTangents: true,
    capChordOnlyAtCappedEnds: capChordOnlyAtCappedEnds,
    dualSidedReturnJoins: dualSidedReturnJoins,
    capTangentMinLookahead: capTangentMinLookahead,
    preferStemCapTangents: preferStemCapTangents,
    meshStyleCaps: meshStyleCaps,
    startTravelTangent: startTravelTangent,
    endTravelTangent: endTravelTangent,
    // Ballpoint mesh uses options.size/2 — not the (possibly tapered) tip radius.
    capChordBaseSize: radius,
  );
}

List<Offset> buildVariableWidthOutline(
  List<PointVector> points, {
  required double size,
  required double thinning,
  required double Function(double) easing,
  required bool roundCaps,
  bool? startCap,
  bool? endCap,
  required double startTaper,
  required double endTaper,
  required double Function(double) startEasing,
  required double Function(double) endEasing,
  double velocityThinning = 0,
  double minSizeRatio = 0.12,
  double maxSizeRatio = 1.0,
  int capSegments = 10,
  int joinSegments = 6,
  bool stabilizeTips = true,
  bool useChordCapTangents = true,
  bool capChordOnlyAtCappedEnds = false,
  bool dualSidedReturnJoins = false,
  double? capTangentMinLookahead,
  bool preferStemCapTangents = false,
  bool meshStyleCaps = false,
  (double, double)? startTravelTangent,
  (double, double)? endTravelTangent,
}) {
  if (points.isEmpty || size <= 0) return const [];
  final half = size / 2;
  final minR = half * minSizeRatio.clamp(0.01, 2.0);
  final maxR = half * maxSizeRatio.clamp(0.01, 3.0);

  // Advanced mesh caps need the opening stem preserved; aggressive second
  // decimation chords short tip runs into later bends and shears hemispheres.
  final spine = decimateStrokeSpine(
    points,
    minDistance: meshStyleCaps
        ? math.max(0.45, half * 0.12)
        : math.max(0.5, half * 0.28),
  );
  final capStart = startCap ?? roundCaps;
  final capEnd = endCap ?? roundCaps;

  if (spine.isEmpty) return const [];
  if (spine.length == 1) {
    final r = math.max(
      minR,
      math.min(
        maxR,
        size * easing(0.5 - thinning * (0.5 - (spine.first.pressure ?? 0.5))),
      ),
    );
    return _singlePointOutline(
      spine.first,
      r,
      roundCaps: capStart || capEnd,
      capSegments: capSegments,
    );
  }

  // Running length along the polyline.
  final n = spine.length;
  final running = List<double>.filled(n, 0);
  final segLen = List<double>.filled(n, 0);
  for (var i = 1; i < n; i++) {
    final dx = spine[i].x - spine[i - 1].x;
    final dy = spine[i].y - spine[i - 1].y;
    segLen[i] = math.sqrt(dx * dx + dy * dy);
    running[i] = running[i - 1] + segLen[i];
  }
  final total = running.last;
  final taperStart = startTaper > 0 ? startTaper : 0.0;
  final taperEnd = endTaper > 0 ? endTaper : 0.0;
  final velAmt = velocityThinning.clamp(0.0, 1.0);

  final radii = List<double>.filled(n, half);
  for (var i = 0; i < n; i++) {
    final pressure = spine[i].pressure ?? 0.5;
    var radius = thinning == 0
        ? half
        : size * easing(0.5 - thinning * (0.5 - pressure));

    if (velAmt > 0) {
      final speed = i == 0
          ? segLen[1]
          : (i == n - 1 ? segLen[i] : (segLen[i] + segLen[i + 1]) * 0.5);
      final speedNorm = (speed / (size * 2.5)).clamp(0.0, 1.0);
      radius *= 1.0 - velAmt * speedNorm * 0.65;
    }

    final ts = (taperStart > 0 && running[i] < taperStart)
        ? startEasing((running[i] / taperStart).clamp(0.0, 1.0))
        : 1.0;
    final te = (taperEnd > 0 && total - running[i] < taperEnd)
        ? endEasing(((total - running[i]) / taperEnd).clamp(0.0, 1.0))
        : 1.0;
    radii[i] = (radius * math.min(ts, te)).clamp(minR, maxR);
  }

  if (stabilizeTips) {
    stabilizeOutlineTipRadii(
      radii,
      stabilizeStart: capStart || startTaper > 0,
      stabilizeEnd: capEnd || endTaper > 0,
      roundStart: capStart,
      roundEnd: capEnd,
    );
  }

  return _outlineFromRadii(
    spine,
    radii,
    startCap: capStart,
    endCap: capEnd,
    capSegments: math.max(capSegments, (capStart || capEnd) ? 12 : capSegments),
    joinSegments: math.max(joinSegments, 8),
    useChordCapTangents: useChordCapTangents,
    capChordOnlyAtCappedEnds: capChordOnlyAtCappedEnds,
    dualSidedReturnJoins: dualSidedReturnJoins,
    capTangentMinLookahead: capTangentMinLookahead,
    preferStemCapTangents: preferStemCapTangents,
    meshStyleCaps: meshStyleCaps,
    startTravelTangent: startTravelTangent,
    endTravelTangent: endTravelTangent,
    capChordBaseSize: half,
  );
}

/// Tip direction from a short run of non-jitter edges near the start.
///
/// Default: direct local chord (Ballpoint-compatible). Pass [useDirectChord]
/// false... actually prefer [tipTravelTangent] via [startTravelTangent] on
/// Advanced outlines when a stem must stop at the first corner.
(double, double) localOpeningChordTangent(
  List<PointVector> points, {
  required double baseSize,
  double? minLookahead,
  bool useDirectChord = false,
}) {
  final count = points.length;
  if (count < 2) return (1.0, 0.0);
  return _directOpeningChord(points, baseSize, minLookahead);
}

/// Tip direction from a short run of non-jitter edges near the end.
(double, double) localClosingChordTangent(
  List<PointVector> points, {
  required double baseSize,
  double? minLookahead,
  bool useDirectChord = false,
}) {
  final count = points.length;
  if (count < 2) return (1.0, 0.0);
  return _directClosingChord(points, baseSize, minLookahead);
}

(double, double) _directOpeningChord(
  List<PointVector> points,
  double baseSize,
  double? minLookahead,
) {
  final count = points.length;
  if (count < 2) return (1.0, 0.0);
  final ax = points.first.x, ay = points.first.y;
  if (count == 2) {
    final tx = points[1].x - ax, ty = points[1].y - ay;
    final len = math.sqrt(tx * tx + ty * ty);
    return len > 1e-6 ? (tx / len, ty / len) : (1.0, 0.0);
  }
  const maxEdges = 8;
  var maxArc = math.min(math.max(baseSize * 2.25, 5.5), 16.5);
  if (minLookahead != null) {
    maxArc = math.min(math.max(maxArc, minLookahead), 16.5);
  }
  var j = 0;
  double acc = 0;
  for (var e = 0; e < maxEdges && j + 1 < count; e++) {
    final sx = points[j + 1].x - points[j].x;
    final sy = points[j + 1].y - points[j].y;
    acc += math.sqrt(sx * sx + sy * sy);
    j++;
    if (acc >= maxArc) break;
  }
  if (j < 1) j = 1;
  if (j >= count) j = count - 1;
  var tx = points[j].x - ax;
  var ty = points[j].y - ay;
  var len = math.sqrt(tx * tx + ty * ty);
  if (len > 1e-6) return (tx / len, ty / len);
  for (var k = 1; k < count; k++) {
    tx = points[k].x - ax;
    ty = points[k].y - ay;
    final l2 = tx * tx + ty * ty;
    if (l2 > 1e-8) {
      len = math.sqrt(l2);
      return (tx / len, ty / len);
    }
  }
  return (1.0, 0.0);
}

(double, double) _directClosingChord(
  List<PointVector> points,
  double baseSize,
  double? minLookahead,
) {
  final count = points.length;
  if (count < 2) return (1.0, 0.0);
  final lastI = count - 1;
  final lx = points[lastI].x, ly = points[lastI].y;
  if (count == 2) {
    final tx = lx - points[0].x, ty = ly - points[0].y;
    final len = math.sqrt(tx * tx + ty * ty);
    return len > 1e-6 ? (tx / len, ty / len) : (1.0, 0.0);
  }
  const maxEdges = 8;
  var maxArc = math.min(math.max(baseSize * 2.25, 5.5), 16.5);
  if (minLookahead != null) {
    maxArc = math.min(math.max(maxArc, minLookahead), 16.5);
  }
  var anchor = lastI;
  double acc = 0;
  for (var e = 0; e < maxEdges && anchor > 0; e++) {
    final sx = points[anchor].x - points[anchor - 1].x;
    final sy = points[anchor].y - points[anchor - 1].y;
    acc += math.sqrt(sx * sx + sy * sy);
    anchor--;
    if (acc >= maxArc) break;
  }
  if (anchor >= lastI) anchor = math.max(0, lastI - 1);
  var tx = lx - points[anchor].x;
  var ty = ly - points[anchor].y;
  var len = math.sqrt(tx * tx + ty * ty);
  if (len > 1e-6) return (tx / len, ty / len);
  for (var k = lastI - 1; k >= 0; k--) {
    tx = lx - points[k].x;
    ty = ly - points[k].y;
    final l2 = tx * tx + ty * ty;
    if (l2 > 1e-8) {
      len = math.sqrt(l2);
      return (tx / len, ty / len);
    }
  }
  return (1.0, 0.0);
}

/// First or last travel direction along the tip stem.
///
/// End caps use [_closingTravelTangent] directly. Start caps recycle that same
/// estimator on a reversed spine and negate, so both tips share one algorithm.
(double, double)? tipTravelTangent(
  List<PointVector> samples, {
  required bool atStart,
  required double size,
  double? minLookahead,
}) {
  final baseSize = size / 2;
  final look = minLookahead ?? math.min(math.max(size * 0.45, 3.0), 12.0);
  if (!atStart) {
    return _closingTravelTangent(
      samples,
      baseSize: baseSize,
      minLookahead: look,
    );
  }
  if (samples.length < 2) return null;
  final closing = _closingTravelTangent(
    samples.reversed.toList(growable: false),
    baseSize: baseSize,
    minLookahead: look,
  );
  if (closing == null) return null;
  return (-closing.$1, -closing.$2);
}

/// End-tip travel direction (lift-off). Also powers start caps via reverse+negate.
(double, double)? _closingTravelTangent(
  List<PointVector> points, {
  required double baseSize,
  double? minLookahead,
}) {
  final count = points.length;
  if (count < 2) return null;

  final tipBall = math.max(0.75, math.min(2.5, baseSize * 0.22));
  final mediumReach = minLookahead == null
      ? math.min(math.max(baseSize * 1.35, 3.5), 10.0)
      : math.min(math.max(minLookahead, 3.5), 12.0);

  Offset tipOf(int i) => Offset(points[i].x, points[i].y);
  final tipIndex = count - 1;
  final tip = tipOf(tipIndex);

  (double, double)? normalize(double dx, double dy) {
    final len = math.sqrt(dx * dx + dy * dy);
    return len > 1e-6 ? (dx / len, dy / len) : null;
  }

  (double, double)? chordFromTip(double reach) {
    double acc = 0;
    var best = tipIndex - 1;
    for (var i = tipIndex; i > 0; i--) {
      acc += (tipOf(i) - tipOf(i - 1)).distance;
      best = i - 1;
      if (acc >= reach || (tipOf(i - 1) - tip).distance >= reach) break;
    }
    return normalize(tip.dx - tipOf(best).dx, tip.dy - tipOf(best).dy);
  }

  /// Path length vs net displacement near the tip — high ratio ⇒ put-down wiggle.
  bool tipClusterIsJittery() {
    double arc = 0;
    var last = tip;
    var net = 0.0;
    final limit = tipBall * 2.5;
    for (var i = tipIndex - 1; i >= 0; i--) {
      final cur = tipOf(i);
      arc += (last - cur).distance;
      last = cur;
      net = math.max(net, (tip - cur).distance);
      if (net >= limit || arc >= limit * 2) break;
    }
    if (arc < tipBall * 0.6) return false;
    return arc > net * 1.55 + 0.45;
  }

  /// First aligned run into the tip (real corner stems). Jitter is handled
  /// by [tipClusterIsJittery] + medium chord.
  ({double tx, double ty, double arc})? shortStem() {
    double? refTx, refTy;
    double sx = 0, sy = 0, acc = 0;
    final need = math.max(tipBall, 2.0);

    bool consider(double dx, double dy) {
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 1e-6) return false;
      final tx = dx / len;
      final ty = dy / len;
      if (refTx != null) {
        if (refTx! * tx + refTy! * ty < 0.86) return true; // turn
      } else {
        refTx = tx;
        refTy = ty;
      }
      sx += dx;
      sy += dy;
      acc += len;
      return false;
    }

    for (var j = tipIndex; j > 0; j--) {
      if (consider(
        tipOf(j).dx - tipOf(j - 1).dx,
        tipOf(j).dy - tipOf(j - 1).dy,
      )) {
        break;
      }
      if (acc >= need) break;
    }

    final sl = math.sqrt(sx * sx + sy * sy);
    if (sl <= 1e-6) return null;
    return (tx: sx / sl, ty: sy / sl, arc: acc);
  }

  final medium = chordFromTip(mediumReach);
  final stem = shortStem();
  final jittery = tipClusterIsJittery();

  if (stem == null) return medium;
  if (medium == null) return (stem.tx, stem.ty);

  final agree = stem.tx * medium.$1 + stem.ty * medium.$2;

  // Put-down scribble: trust the medium travel chord.
  if (jittery && agree < 0.75) return medium;

  // Real tip stem before a corner: keep it even if a longer chord cuts.
  if (stem.arc >= tipBall * 0.9 && agree >= -0.05) {
    return (stem.tx, stem.ty);
  }

  if (agree >= 0.5) return (stem.tx, stem.ty);
  return medium;
}

double _stemCapRadius(List<double> radii, {required bool atStart}) {
  if (radii.isEmpty) return 0;
  final i0 = atStart ? 0 : radii.length - 1;
  var r = radii[i0];
  var sum = 0.0;
  var n = 0;
  if (atStart) {
    for (var k = 1; k <= radii.length - 1 && k <= 6; k++) {
      sum += radii[k];
      n++;
    }
  } else {
    for (var k = math.max(0, radii.length - 6); k <= radii.length - 2; k++) {
      sum += radii[k];
      n++;
    }
  }
  if (n > 0) r = math.max(r, (sum / n) * 0.93);
  return r;
}

/// Ballpoint mesh forces the first/last spine segment onto the cap chord so
/// hemisphere/arc normals and the opening ribbon cannot disagree.
void _alignTipEdgeToChord(
  List<PointVector> points, {
  required List<double> segTx,
  required List<double> segTy,
  required bool atStart,
  required double tx,
  required double ty,
}) {
  final n = points.length;
  if (n < 2) return;
  var tLen = math.sqrt(tx * tx + ty * ty);
  if (tLen < 1e-6) return;
  tx /= tLen;
  ty /= tLen;

  if (atStart) {
    final p0 = points[0];
    final p1 = points[1];
    final cur = math.sqrt(
      (p1.x - p0.x) * (p1.x - p0.x) + (p1.y - p0.y) * (p1.y - p0.y),
    );
    final len = math.max(cur, 1e-3);
    points[1] = PointVector(p0.x + tx * len, p0.y + ty * len, p1.pressure);
    segTx[0] = tx;
    segTy[0] = ty;

    // Update the adjacent segment vector because points[1] has moved.
    if (n > 2) {
      final dx = points[2].x - points[1].x;
      final dy = points[2].y - points[1].y;
      final dLen = math.sqrt(dx * dx + dy * dy);
      if (dLen > 1e-6) {
        segTx[1] = dx / dLen;
        segTy[1] = dy / dLen;
      }
    }
  } else {
    final pN = points[n - 1];
    final pPrev = points[n - 2];
    final cur = math.sqrt(
      (pN.x - pPrev.x) * (pN.x - pPrev.x) + (pN.y - pPrev.y) * (pN.y - pPrev.y),
    );
    final len = math.max(cur, 1e-3);
    points[n - 2] = PointVector(
      pN.x - tx * len,
      pN.y - ty * len,
      pPrev.pressure,
    );
    segTx[n - 2] = tx;
    segTy[n - 2] = ty;

    // Update the adjacent segment vector because points[n - 2] has moved.
    if (n > 2) {
      final dx = points[n - 2].x - points[n - 3].x;
      final dy = points[n - 2].y - points[n - 3].y;
      final dLen = math.sqrt(dx * dx + dy * dy);
      if (dLen > 1e-6) {
        segTx[n - 3] = dx / dLen;
        segTy[n - 3] = dy / dLen;
      }
    }
  }
}

void _appendHemispherePairs({
  required List<Offset> left,
  required List<Offset> right,
  required Offset origin,
  required double tx,
  required double ty,
  required double radius,
  required int segments,
  required bool atStart,
}) {
  var tLen = math.sqrt(tx * tx + ty * ty);
  if (tLen < 1e-6) {
    tx = 1;
    ty = 0;
    tLen = 1;
  } else {
    tx /= tLen;
    ty /= tLen;
  }
  // One code path: end-cap samples from stem → tip along [outward]. Start
  // flips travel so the bulb sits behind the tip, then reverses sample order.
  final outwardTx = atStart ? -tx : tx;
  final outwardTy = atStart ? -ty : ty;
  final nx = -ty;
  final ny = tx;
  final steps = math.max(2, segments);
  final tmpLeft = <Offset>[];
  final tmpRight = <Offset>[];
  for (var i = 1; i <= steps; i++) {
    final angle = (math.pi / 2) * (i / steps);
    final cx = origin.dx + outwardTx * math.sin(angle) * radius;
    final cy = origin.dy + outwardTy * math.sin(angle) * radius;
    final w = math.cos(angle) * radius;
    tmpLeft.add(Offset(cx + nx * w, cy + ny * w));
    tmpRight.add(Offset(cx - nx * w, cy - ny * w));
  }
  if (atStart) {
    for (var i = tmpLeft.length - 1; i >= 0; i--) {
      _appendDistinct(left, tmpLeft[i]);
      _appendDistinct(right, tmpRight[i]);
    }
  } else {
    for (var i = 0; i < tmpLeft.length; i++) {
      _appendDistinct(left, tmpLeft[i]);
      _appendDistinct(right, tmpRight[i]);
    }
  }
}

/// Pulls tip radii toward a short interior average so round caps don't pinch or
/// balloon when pressure/taper spikes at lift-off (fountain/advanced pattern).
void stabilizeOutlineTipRadii(
  List<double> radii, {
  bool roundCaps = true,
  bool? stabilizeStart,
  bool? stabilizeEnd,
  bool? roundStart,
  bool? roundEnd,
}) {
  final count = radii.length;
  if (count < 3) return;
  final doStart = stabilizeStart ?? true;
  final doEnd = stabilizeEnd ?? true;
  final capStart = roundStart ?? roundCaps;
  final capEnd = roundEnd ?? roundCaps;
  const w = 4;
  var n0 = 0;
  var s0 = 0.0;
  for (var i = 1; i < count && i <= w; i++) {
    s0 += radii[i];
    n0++;
  }
  var n1 = 0;
  var s1 = 0.0;
  for (var i = count - 2; i >= 0 && n1 < w; i--) {
    s1 += radii[i];
    n1++;
  }
  if (doStart && n0 > 0) {
    final ref = s0 / n0;
    radii[0] = radii[0] * 0.35 + ref * 0.65;
    if (capStart) {
      radii[0] = math.max(radii[0], ref * 0.88);
    }
  }
  if (doEnd && n1 > 0) {
    final ref = s1 / n1;
    radii[count - 1] = radii[count - 1] * 0.35 + ref * 0.65;
    if (capEnd) {
      radii[count - 1] = math.max(radii[count - 1], ref * 0.88);
    }
  }
}

/// Drops near-duplicate samples that make stroke normals unstable.
///
/// Always keeps the first and last points. Intermediate points closer than
/// [minDistance] to the last kept sample are skipped.
List<PointVector> decimateStrokeSpine(
  List<PointVector> points, {
  required double minDistance,
}) {
  if (points.length <= 2) return List<PointVector>.of(points);
  final minDistSq = minDistance * minDistance;
  final out = <PointVector>[points.first];
  for (var i = 1; i < points.length - 1; i++) {
    final p = points[i];
    final prev = out.last;
    final dx = p.x - prev.x;
    final dy = p.y - prev.y;
    if (dx * dx + dy * dy >= minDistSq) {
      out.add(p);
    }
  }
  final last = points.last;
  final prev = out.last;
  final dx = last.x - prev.x;
  final dy = last.y - prev.y;
  if (dx * dx + dy * dy >= minDistSq * 0.25) {
    out.add(last);
  } else if (out.length == 1) {
    out.add(last);
  } else {
    // Keep the true tip; replace the last intermediate sample.
    out[out.length - 1] = last;
  }
  return out;
}

List<Offset> _singlePointOutline(
  PointVector p,
  double radius, {
  required bool roundCaps,
  required int capSegments,
}) {
  if (!roundCaps) {
    final r = radius;
    // Axis-aligned square (butt tip with no travel direction yet).
    return [
      Offset(p.x - r, p.y - r),
      Offset(p.x + r, p.y - r),
      Offset(p.x + r, p.y + r),
      Offset(p.x - r, p.y + r),
    ];
  }
  return _circleOutline(Offset(p.x, p.y), radius, capSegments * 2);
}

List<Offset> _outlineFromRadii(
  List<PointVector> points,
  List<double> radii, {
  required bool startCap,
  required bool endCap,
  required int capSegments,
  required int joinSegments,
  bool useChordCapTangents = true,
  bool capChordOnlyAtCappedEnds = false,
  bool dualSidedReturnJoins = false,
  double? capTangentMinLookahead,
  bool preferStemCapTangents = false,
  bool meshStyleCaps = false,
  (double, double)? startTravelTangent,
  (double, double)? endTravelTangent,

  /// Ballpoint uses pen radius (size/2). Tip radius under taper is too small
  /// and makes local chords chase put-down jitter.
  double? capChordBaseSize,
}) {
  final n = points.length;
  assert(n >= 2);
  assert(radii.length == n);

  // Unit segment directions (spine[i] → spine[i+1]).
  final segTx = List<double>.filled(n - 1, 1.0);
  final segTy = List<double>.filled(n - 1, 0.0);
  for (var i = 0; i < n - 1; i++) {
    final dx = points[i + 1].x - points[i].x;
    final dy = points[i + 1].y - points[i].y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-9) {
      if (i > 0) {
        segTx[i] = segTx[i - 1];
        segTy[i] = segTy[i - 1];
      }
    } else {
      segTx[i] = dx / len;
      segTy[i] = dy / len;
    }
  }

  // Propagate valid directions over any residual zero-length segments.
  for (var i = 1; i < n - 1; i++) {
    final dx = points[i + 1].x - points[i].x;
    final dy = points[i + 1].y - points[i].y;
    if (dx * dx + dy * dy < 1e-12) {
      segTx[i] = segTx[i - 1];
      segTy[i] = segTy[i - 1];
    }
  }
  for (var i = n - 3; i >= 0; i--) {
    final dx = points[i + 1].x - points[i].x;
    final dy = points[i + 1].y - points[i].y;
    if (dx * dx + dy * dy < 1e-12) {
      segTx[i] = segTx[i + 1];
      segTy[i] = segTy[i + 1];
    }
  }

  final left = <Offset>[];
  final right = <Offset>[];

  void addLeft(Offset o) => _appendDistinct(left, o);
  void addRight(Offset o) => _appendDistinct(right, o);

  final avgRadius = radii.reduce((a, b) => a + b) / n;
  final tangentSize = math.max(avgRadius, math.max(radii.first, radii.last));
  // Match Ballpoint mesh: chord window scales with pen radius, not tip taper.
  final chordBase = math.max(capChordBaseSize ?? tangentSize, tangentSize);
  late final double startTx;
  late final double startTy;
  late final double endTx;
  late final double endTy;
  final useStartChord =
      useChordCapTangents &&
      !meshStyleCaps &&
      (!capChordOnlyAtCappedEnds || startCap);
  final useEndChord =
      useChordCapTangents &&
      !meshStyleCaps &&
      (!capChordOnlyAtCappedEnds || endCap);
  if (meshStyleCaps) {
    // Legacy hemisphere path (tests): chords on *this* spine + tip edges
    // forced onto the chord — same as Ballpoint mesh first/last segment.
    final opening =
        startTravelTangent ??
        _directOpeningChord(points, chordBase, capTangentMinLookahead);
    startTx = opening.$1;
    startTy = opening.$2;
    final closing =
        endTravelTangent ??
        _directClosingChord(points, chordBase, capTangentMinLookahead);
    endTx = closing.$1;
    endTy = closing.$2;
    _alignTipEdgeToChord(
      points,
      segTx: segTx,
      segTy: segTy,
      atStart: true,
      tx: startTx,
      ty: startTy,
    );
    _alignTipEdgeToChord(
      points,
      segTx: segTx,
      segTy: segTy,
      atStart: false,
      tx: endTx,
      ty: endTy,
    );
    segTx[0] = startTx;
    segTy[0] = startTy;
    segTx[n - 2] = endTx;
    segTy[n - 2] = endTy;
  } else if (useStartChord) {
    final opening =
        startTravelTangent ??
        (preferStemCapTangents
            ? tipTravelTangent(
                points,
                atStart: true,
                size: chordBase * 2,
                minLookahead: capTangentMinLookahead,
              )
            : null) ??
        localOpeningChordTangent(
          points,
          baseSize: chordBase,
          minLookahead: capTangentMinLookahead,
        );
    startTx = opening.$1;
    startTy = opening.$2;
    // Do not move authored tip points — only override the virtual first
    // segment direction so the hemisphere matches the ribbon opening.
    segTx[0] = startTx;
    segTy[0] = startTy;
  } else {
    startTx = segTx.first;
    startTy = segTy.first;
  }
  if (!meshStyleCaps) {
    if (useEndChord) {
      // End caps use the local closing chord (stable on live tip windows).
      // Stem-stop tangents are start-only — they are for L-bend put-down.
      final closing =
          endTravelTangent ??
          localClosingChordTangent(
            points,
            baseSize: chordBase,
            minLookahead: capTangentMinLookahead,
          );
      endTx = closing.$1;
      endTy = closing.$2;
      segTx[n - 2] = endTx;
      segTy[n - 2] = endTy;
    } else {
      endTx = segTx.last;
      endTy = segTy.last;
    }
  }

  final startCapR = startCap
      ? _stemCapRadius(radii, atStart: true)
      : radii.first;
  final endCapR = endCap ? _stemCapRadius(radii, atStart: false) : radii.last;

  if (meshStyleCaps && startCap) {
    _appendHemispherePairs(
      left: left,
      right: right,
      origin: Offset(points.first.x, points.first.y),
      tx: startTx,
      ty: startTy,
      radius: startCapR,
      segments: capSegments,
      atStart: true,
    );
  }

  // Start cap side points — oriented by local opening chord (not only seg[0]).
  {
    final r = startCap ? startCapR : radii.first;
    final nx = -startTy;
    final ny = startTx;
    addLeft(Offset(points.first.x + nx * r, points.first.y + ny * r));
    addRight(Offset(points.first.x - nx * r, points.first.y - ny * r));
  }

  for (var i = 1; i < n - 1; i++) {
    final px = points[i].x;
    final py = points[i].y;
    final r = radii[i];

    final t0x = segTx[i - 1];
    final t0y = segTy[i - 1];
    final t1x = segTx[i];
    final t1y = segTy[i];

    final n0x = -t0y, n0y = t0x;
    final n1x = -t1y, n1y = t1x;

    final turn = t0x * t1y - t0y * t1x; // >0 left turn
    final align = (t0x * t1x + t0y * t1y).clamp(-1.0, 1.0);

    final l0 = Offset(px + n0x * r, py + n0y * r);
    final l1 = Offset(px + n1x * r, py + n1y * r);
    final r0 = Offset(px - n0x * r, py - n0y * r);
    final r1 = Offset(px - n1x * r, py - n1y * r);

    if (align > 0.995) {
      // Nearly straight — one averaged offset.
      final ax = n0x + n1x;
      final ay = n0y + n1y;
      final al = math.sqrt(ax * ax + ay * ay);
      if (al > 1e-9) {
        addLeft(Offset(px + ax / al * r, py + ay / al * r));
        addRight(Offset(px - ax / al * r, py - ay / al * r));
      } else {
        addLeft(l0);
        addRight(r0);
      }
      continue;
    }

    // Ballpoint mesh fans normals whenever the join is sharp (dot < 0.5).
    // Advanced Pen mirrors that on the outline: round BOTH sides into a tip
    // bulb. Collapsing the inner side onto the centerline left a flat diameter.
    if (dualSidedReturnJoins && align < 0.5) {
      final cuspSegments = math.max(joinSegments, align < -0.5 ? 14 : 8);
      final apex = Offset(px, py);
      var outX = -(n0x + n1x);
      var outY = -(n0y + n1y);
      var outLen = math.sqrt(outX * outX + outY * outY);
      if (outLen < 1e-6) {
        // Exact reverse: normals cancel — aim the bulb along the tip bisector.
        outX = t0x - t1x;
        outY = t0y - t1y;
        outLen = math.sqrt(outX * outX + outY * outY);
        if (outLen < 1e-6) {
          outX = t0x;
          outY = t0y;
          outLen = math.sqrt(outX * outX + outY * outY);
        }
      }
      if (outLen > 1e-6) {
        outX /= outLen;
        outY /= outLen;
      }
      addLeft(l0);
      _appendArc(
        left,
        center: apex,
        from: l0,
        to: l1,
        outwardTangentX: -outX,
        outwardTangentY: -outY,
        radius: r,
        segments: cuspSegments,
      );
      addLeft(l1);
      addRight(r0);
      _appendArc(
        right,
        center: apex,
        from: r0,
        to: r1,
        outwardTangentX: outX,
        outwardTangentY: outY,
        radius: r,
        segments: cuspSegments,
      );
      addRight(r1);
      continue;
    }

    // Legacy single-sided hairpin (ballpoint / pencil outline path).
    if (align < -0.5) {
      final cuspSegments = math.max(joinSegments, 10);
      addLeft(l0);
      _appendArc(
        left,
        center: Offset(px, py),
        from: l0,
        to: l1,
        outwardTangentX: t0x,
        outwardTangentY: t0y,
        radius: r,
        segments: cuspSegments,
      );
      addLeft(l1);
      addRight(r0);
      addRight(r1);
      continue;
    }

    // Outer side gets a round join; inner side bevels (avoids spikes/holes).
    // Arc "outward" direction is the outer normal (not the travel tangent).
    final joinSegs = align < 0.5 ? math.max(joinSegments, 8) : joinSegments;
    if (turn >= 0) {
      // Left turn: left is inner, right is outer.
      addLeft(l0);
      addLeft(l1);
      addRight(r0);
      _appendArc(
        right,
        center: Offset(px, py),
        from: r0,
        to: r1,
        outwardTangentX: -(n0x + n1x),
        outwardTangentY: -(n0y + n1y),
        radius: r,
        segments: joinSegs,
      );
      addRight(r1);
    } else {
      // Right turn: right is inner, left is outer.
      addLeft(l0);
      _appendArc(
        left,
        center: Offset(px, py),
        from: l0,
        to: l1,
        outwardTangentX: n0x + n1x,
        outwardTangentY: n0y + n1y,
        radius: r,
        segments: joinSegs,
      );
      addLeft(l1);
      addRight(r0);
      addRight(r1);
    }
  }

  // End cap side points — oriented by local closing chord.
  {
    final r = endCap ? endCapR : radii.last;
    final nx = -endTy;
    final ny = endTx;
    addLeft(Offset(points.last.x + nx * r, points.last.y + ny * r));
    addRight(Offset(points.last.x - nx * r, points.last.y - ny * r));
  }

  if (meshStyleCaps && endCap) {
    _appendHemispherePairs(
      left: left,
      right: right,
      origin: Offset(points.last.x, points.last.y),
      tx: endTx,
      ty: endTy,
      radius: endCapR,
      segments: capSegments,
      atStart: false,
    );
  }

  final outline = <Offset>[];
  outline.addAll(left);

  if (endCap && !meshStyleCaps) {
    outline.addAll(
      _capArc(
        center: Offset(points.last.x, points.last.y),
        from: left.last,
        to: right.last,
        tangentX: endTx,
        tangentY: endTy,
        radius: endCapR,
        segments: capSegments,
      ),
    );
  }

  for (var i = right.length - 1; i >= 0; i--) {
    outline.add(right[i]);
  }

  if (startCap && !meshStyleCaps) {
    outline.addAll(
      _capArc(
        center: Offset(points.first.x, points.first.y),
        from: right.first,
        to: left.first,
        tangentX: -startTx,
        tangentY: -startTy,
        radius: startCapR,
        segments: capSegments,
      ),
    );
  }

  return outline;
}

void _appendDistinct(List<Offset> list, Offset o, [double eps = 1e-4]) {
  if (list.isEmpty) {
    list.add(o);
    return;
  }
  final prev = list.last;
  if ((prev.dx - o.dx).abs() > eps || (prev.dy - o.dy).abs() > eps) {
    list.add(o);
  }
}

void _appendArc(
  List<Offset> list, {
  required Offset center,
  required Offset from,
  required Offset to,
  required double outwardTangentX,
  required double outwardTangentY,
  required double radius,
  required int segments,
}) {
  final pts = _capArc(
    center: center,
    from: from,
    to: to,
    tangentX: outwardTangentX,
    tangentY: outwardTangentY,
    radius: radius,
    segments: segments,
  );
  for (final p in pts) {
    _appendDistinct(list, p);
  }
}

List<Offset> _circleOutline(Offset c, double r, int segments) {
  final out = <Offset>[];
  final n = math.max(8, segments);
  for (var i = 0; i < n; i++) {
    final a = (i / n) * math.pi * 2;
    out.add(Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r));
  }
  return out;
}

/// Semicircle from [from] to [to] around [center], bulging along the outward
/// [tangentX]/[tangentY] (unit travel pointing out of the tip).
///
/// Built in the (tangent, perpendicular) frame so orientation is exactly the
/// given tip tangent — not an atan2 sweep that can pick the inward half.
List<Offset> _capArc({
  required Offset center,
  required Offset from,
  required Offset to,
  required double tangentX,
  required double tangentY,
  required double radius,
  required int segments,
}) {
  var tLen = math.sqrt(tangentX * tangentX + tangentY * tangentY);
  if (tLen < 1e-6) {
    tangentX = 1.0;
    tangentY = 0.0;
    tLen = 1.0;
  } else {
    tangentX /= tLen;
    tangentY /= tLen;
  }

  // Left-handed perpendicular of outward tangent.
  final nx = -tangentY;
  final ny = tangentX;

  // Which rim is [from]? Positive → +perp side.
  final fromDot = (from.dx - center.dx) * nx + (from.dy - center.dy) * ny;
  final startTheta = fromDot >= 0 ? math.pi / 2 : -math.pi / 2;
  final endTheta = -startTheta;

  final out = <Offset>[];
  final steps = math.max(2, segments);
  for (var i = 1; i < steps; i++) {
    final t = i / steps;
    final theta = startTheta + (endTheta - startTheta) * t;
    final cosT = math.cos(theta);
    final sinT = math.sin(theta);
    // theta=0 → outward tip; ±π/2 → side rims.
    out.add(
      Offset(
        center.dx + (tangentX * cosT + nx * sinT) * radius,
        center.dy + (tangentY * cosT + ny * sinT) * radius,
      ),
    );
  }
  return out;
}
