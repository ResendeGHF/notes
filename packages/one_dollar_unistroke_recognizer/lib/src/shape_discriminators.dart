import 'dart:math' as math;

import 'dart:ui' show Offset, Rect;

/// Shape discriminators for post-recognition disambiguation.
/// These heuristics help correct misclassifications when similar shapes
/// receive close recognition scores.

/// Returns a roundness score in [0, 1]: 1 = smooth/elliptical, 0 = angular/rectangular.
///
/// Rectangles have four ~90° corners. Ellipses are mostly smooth (tips may be a
/// bit sharper when elongated). We downsample so dense sampling does not invent
/// dozens of fake corners, then score from sharp/strong turn counts.
double computeRoundness(List<Offset> points) {
  if (points.length < 4) return 0.5;

  final sampled = _resampleClosedPolyline(points, targetCount: 48);
  if (sampled.length < 4) return 0.5;

  // Higher thresholds: freehand ellipse tips often sit around 30–45°.
  const sharpThreshold = 48.0 * math.pi / 180;
  const strongThreshold = 70.0 * math.pi / 180;
  final n = sampled.length;
  var sharpSamples = 0;
  var strongSamples = 0;
  for (var i = 0; i < n; i++) {
    final prev = sampled[(i - 1 + n) % n];
    final cur = sampled[i];
    final next = sampled[(i + 1) % n];
    final a = cur - prev;
    final b = next - cur;
    final la = a.distance;
    final lb = b.distance;
    if (la < 1e-6 || lb < 1e-6) continue;
    final cross = a.dx * b.dy - a.dy * b.dx;
    final dot = a.dx * b.dx + a.dy * b.dy;
    final angle = math.atan2(cross.abs(), dot.clamp(-1e10, 1e10));
    if (angle > sharpThreshold) sharpSamples++;
    if (angle > strongThreshold) strongSamples++;
  }

  // Rectangles: several near-90° corner samples. Ellipses: few milder tips.
  if (strongSamples >= 4 || sharpSamples >= 10) return 0.0;
  if (sharpSamples <= 2 && strongSamples == 0) return 1.0;
  if (strongSamples >= 3 || sharpSamples >= 7) return 0.3;
  if (sharpSamples >= 4) return 0.55;
  return 0.8;
}

/// Evenly spaced samples along the polyline (treated as closed when ends meet).
List<Offset> _resampleClosedPolyline(List<Offset> points, {required int targetCount}) {
  if (points.length <= targetCount) return List<Offset>.from(points);
  final closed = (points.first - points.last).distance <=
      math.max(4.0, _polylineLength(points) * 0.02);
  final ring = <Offset>[...points];
  if (closed && (ring.first - ring.last).distance > 1e-6) {
    ring.add(ring.first);
  }

  final total = _polylineLength(ring);
  if (total < 1e-6) return points.sublist(0, math.min(points.length, targetCount));

  final out = <Offset>[];
  final step = total / targetCount;
  var seg = 0;
  var segStart = 0.0;
  out.add(ring.first);
  for (var i = 1; i < targetCount; i++) {
    final target = i * step;
    while (seg < ring.length - 1) {
      final a = ring[seg];
      final b = ring[seg + 1];
      final len = (b - a).distance;
      if (segStart + len >= target || seg == ring.length - 2) {
        final t = len < 1e-9 ? 0.0 : ((target - segStart) / len).clamp(0.0, 1.0);
        out.add(Offset.lerp(a, b, t)!);
        break;
      }
      segStart += len;
      seg++;
    }
  }
  return out;
}

double _polylineLength(List<Offset> points) {
  var len = 0.0;
  for (var i = 1; i < points.length; i++) {
    len += (points[i] - points[i - 1]).distance;
  }
  return len;
}

/// Returns true if stroke is V-shaped and simple (few segments), favoring angle bracket over brace.
/// Angle brackets are two straight lines with an angle; braces have loops (curved).
bool isAngleBracketPreferred(List<Offset> points) {
  if (points.length < 3) return true;
  if (isBracePreferred(points)) return false; // Braces have loops, not angle brackets
  // Angle brackets: short strokes, few direction changes. Braces: longer, curvier.
  if (points.length < 12) return true; // Very short stroke → likely angle bracket
  // Count significant direction changes (inflection points)
  int inflections = 0;
  for (int i = 2; i < points.length; i++) {
    final a = points[i - 1] - points[i - 2];
    final b = points[i] - points[i - 1];
    final la = a.distance;
    final lb = b.distance;
    if (la < 1e-6 || lb < 1e-6) continue;
    final cross = a.dx * b.dy - a.dy * b.dx;
    if (cross.abs() > la * lb * 0.12) inflections++;
  }
  // Angle brackets have ≤5 inflections; braces have many more (loops)
  return inflections <= 5;
}

/// Returns true if stroke has loops/curves typical of braces { }.
/// Braces have a loop when handwritten; angle brackets are two straight lines.
bool isBracePreferred(List<Offset> points) {
  if (points.length < 8) return false;
  // Path length vs chord length: loops make path longer
  double pathLen = 0;
  for (int i = 1; i < points.length; i++) {
    pathLen += (points[i] - points[i - 1]).distance;
  }
  final chordLen = (points.last - points.first).distance;
  if (chordLen < 1) return false;
  final pathRatio = pathLen / chordLen;
  // Braces: path winds (ratio > 1.4). Angle brackets: almost straight (ratio < 1.3)
  if (pathRatio > 1.4) return true;
  // Also check curvature: braces are smooth, angle brackets have one sharp corner
  final roundness = computeRoundness(points);
  int inflections = 0;
  for (int i = 2; i < points.length; i++) {
    final a = points[i - 1] - points[i - 2];
    final b = points[i] - points[i - 1];
    final la = a.distance;
    final lb = b.distance;
    if (la < 1e-6 || lb < 1e-6) continue;
    final cross = a.dx * b.dy - a.dy * b.dx;
    if (cross.abs() > la * lb * 0.12) inflections++;
  }
  return roundness > 0.5 && inflections > 6;
}

/// Returns true if stroke is tall with dominant vertical segments (bracket-like).
/// Brackets [ ] have two vertical bars; productory has horizontal top; summatory has diagonal.
bool isBracketPreferred(List<Offset> points) {
  if (points.length < 4) return false;
  final box = _boundsOf(points);
  if (box.height < 1) return false;
  final aspect = box.width / box.height;
  // Brackets are typically taller than wide (aspect < 0.6)
  if (aspect > 0.8) return false;
  // Check vertical extent: bracket strokes spend most length on vertical movement
  double verticalLength = 0.0, totalLength = 0.0;
  for (int i = 1; i < points.length; i++) {
    final d = points[i] - points[i - 1];
    totalLength += d.distance;
    verticalLength += d.dy.abs();
  }
  if (totalLength < 1) return false;
  // Brackets: vertical component dominates (typically > 60% of path)
  return verticalLength / totalLength > 0.6;
}

Rect _boundsOf(List<Offset> points) {
  if (points.isEmpty) return Rect.zero;
  var minX = points.first.dx, maxX = minX;
  var minY = points.first.dy, maxY = minY;
  for (final p in points) {
    if (p.dx < minX) minX = p.dx;
    if (p.dx > maxX) maxX = p.dx;
    if (p.dy < minY) minY = p.dy;
    if (p.dy > maxY) maxY = p.dy;
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}
