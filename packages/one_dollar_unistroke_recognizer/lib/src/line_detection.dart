import 'dart:math';

import 'package:flutter/material.dart' show visibleForTesting, Offset;

/// A line between two points.
@visibleForTesting
class Line {
  // ignore: public_member_api_docs
  Line(this.start, this.end);

  /// The start point of the line.
  final Offset start;

  /// The end point of the line.
  final Offset end;

  /// The [a] in the equation [ax + by + c = 0].
  late final a = end.dy - start.dy;

  /// The [b] in the equation [ax + by + c = 0].
  late final b = start.dx - end.dx;

  /// The [c] in the equation [ax + by + c = 0].
  late final c = (-a * start.dx) + (-b * start.dy);

  /// The denominator in the equation for the distance from a point to a line.
  /// See https://en.wikipedia.org/wiki/Distance_from_a_point_to_a_line.
  late final denominator = sqrt(a * a + b * b);

  /// Returns the min distance from a point to this line.
  /// See https://en.wikipedia.org/wiki/Distance_from_a_point_to_a_line.
  double distanceToPoint(Offset point) {
    return (a * point.dx + b * point.dy + c).abs() / denominator;
  }
}

/// Returns the mean absolute error between the inputPoints
/// and the line between the first and last point.
///
/// See https://en.m.wikipedia.org/wiki/Mean_absolute_error.
double meanAbsoluteError(List<Offset> inputPoints) {
  final line = Line(inputPoints.first, inputPoints.last);
  final sumAbsoluteError = inputPoints
      .map((point) => line.distanceToPoint(point))
      .reduce((a, b) => a + b);
  final meanAbsoluteError = sumAbsoluteError / inputPoints.length;
  return meanAbsoluteError;
}

/// Fits the best straight line through [points] and returns the projected
/// extent: the two points on that line that best represent the stroke.
///
/// When [useChordDirection] is true (e.g. for replacing a user-drawn straight
/// line), uses the chord (first → last) for the angular coefficient, ensuring
/// the inclination matches the user's stroke. When false (e.g. for ellipse
/// major axis), uses PCA orthogonal regression.
///
/// The result is the closest straight line through the user's stroke,
/// working at any angle.
(Offset start, Offset end) fitLineAndProjectExtent(
  List<Offset> points, {
  bool useChordDirection = false,
}) {
  if (points.length < 2) {
    final p = points.isEmpty ? Offset.zero : points.single;
    return (p, p);
  }
  if (points.length == 2) return (points.first, points.last);

  final first = points.first;
  final last = points.last;
  double vx, vy;
  double tMin, tMax;

  if (useChordDirection) {
    // Use chord direction (first → last) for the angular coefficient.
    // Matches user's stroke inclination; PCA can be skewed by uneven
    // point distribution.
    final chordDx = last.dx - first.dx;
    final chordDy = last.dy - first.dy;
    final chordLen = sqrt(chordDx * chordDx + chordDy * chordDy);
    if (chordLen < 1e-10) return (first, last);

    vx = chordDx / chordLen;
    vy = chordDy / chordLen;
    tMin = 0.0;
    tMax = chordLen;
    for (final p in points) {
      final t = (p.dx - first.dx) * vx + (p.dy - first.dy) * vy;
      if (t < tMin) tMin = t;
      if (t > tMax) tMax = t;
    }
  } else {
    // PCA orthogonal regression for shapes (ellipses, etc.)
    var sumX = 0.0, sumY = 0.0;
    for (final p in points) {
      sumX += p.dx;
      sumY += p.dy;
    }
    final n = points.length;
    final cx = sumX / n, cy = sumY / n;
    var xx = 0.0, yy = 0.0, xy = 0.0;
    for (final p in points) {
      final dx = p.dx - cx, dy = p.dy - cy;
      xx += dx * dx;
      yy += dy * dy;
      xy += dx * dy;
    }

    final trace = xx + yy;
    final det = xx * yy - xy * xy;
    final disc = sqrt(trace * trace - 4 * det);
    final eig1 = (trace + disc) / 2;
    final eig2 = (trace - disc) / 2;
    final eig = eig1 >= eig2 ? eig1 : eig2;
    if (xy.abs() < 1e-10) {
      vx = xx >= yy ? 1.0 : 0.0;
      vy = xx >= yy ? 0.0 : 1.0;
    } else {
      vx = xy;
      vy = eig - xx;
    }
    final len = sqrt(vx * vx + vy * vy);
    if (len < 1e-10) return (first, last);
    vx /= len;
    vy /= len;

    final midX = (first.dx + last.dx) / 2;
    final midY = (first.dy + last.dy) / 2;
    final t1 = (first.dx - midX) * vx + (first.dy - midY) * vy;
    final t2 = (last.dx - midX) * vx + (last.dy - midY) * vy;
    tMin = t1 < t2 ? t1 : t2;
    tMax = t1 < t2 ? t2 : t1;

    final startPt = Offset(midX + tMin * vx, midY + tMin * vy);
    final endPt = Offset(midX + tMax * vx, midY + tMax * vy);
    return (startPt, endPt);
  }

  final start = Offset(first.dx + tMin * vx, first.dy + tMin * vy);
  final end = Offset(first.dx + tMax * vx, first.dy + tMax * vy);
  return (start, end);
}
