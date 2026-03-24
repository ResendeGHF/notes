import 'dart:math' as math;

import 'dart:ui' show Offset, Rect;

/// Shape discriminators for post-recognition disambiguation.
/// These heuristics help correct misclassifications when similar shapes
/// receive close recognition scores.

/// Returns a roundness score in [0, 1]: 1 = smooth/elliptical, 0 = angular/rectangular.
///
/// Rectangles have exactly 4 sharp corners (~90°). Ellipses have 0–2 (at narrow ends).
/// Elongated ellipses can have sharp curvature at ends, so we use corner count, not max angle.
double computeRoundness(List<Offset> points) {
  if (points.length < 4) return 0.5;
  int sharpCorners = 0; // points with turn angle > 55°
  const sharpThreshold = 55.0 * math.pi / 180;
  for (int i = 1; i < points.length - 1; i++) {
    final a = points[i] - points[i - 1];
    final b = points[i + 1] - points[i];
    final la = a.distance;
    final lb = b.distance;
    if (la < 1e-6 || lb < 1e-6) continue;
    final cross = a.dx * b.dy - a.dy * b.dx;
    final dot = a.dx * b.dx + a.dy * b.dy;
    final angle = math.atan2(cross.abs(), dot.clamp(-1e10, 1e10));
    if (angle > sharpThreshold) sharpCorners++;
  }
  // Rectangles: 4 corners. Ellipses: 0–2 (elongated have 2 at ends). Circle: 0.
  // roundness = 1 when sharpCorners <= 2, 0 when >= 4
  if (sharpCorners >= 4) return 0.0;
  if (sharpCorners <= 2) return 1.0;
  return 1.0 - (sharpCorners - 2) / 2.0; // 3 corners -> 0.5
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
