// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Temporary 1-bit coverage of a lasso polyline.
///
/// [Path.contains] walks every lasso verb, so testing outlined polygons of
/// thousands of strokes stalls pen-up. This mask answers the same inside test
/// with one pixel read. It is built for a single hit-test and then dropped.
class LassoCoverageMask {
  LassoCoverageMask._({
    required this.origin,
    required this.scale,
    required this.width,
    required this.height,
    required Uint8List coverage,
  }) : _coverage = coverage;

  /// Longest bitmap edge. A page-sized lasso stays near 1 cell per logical px;
  /// larger regions get coarser cells, which is still fine for a 70% test.
  static const maxSide = 1024;

  /// Caps cost on a tiny lasso (no multi-megapixel mask for a short loop).
  static const double maxCellsPerUnit = 4;

  /// Page-space top-left of pixel (0, 0). Includes a 1px pad so boundary
  /// samples are not clipped off the bitmap.
  final Offset origin;

  /// Pixels per page unit.
  final double scale;

  final int width;
  final int height;

  final Uint8List _coverage;

  /// Nonzero fill of [points] (open or closed). Returns null when the loop
  /// has no area.
  static LassoCoverageMask? fromPolyline(List<Offset> points) {
    if (points.length < 3) return null;

    final ring = _decimate(points, 4096);
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    var valid = 0;
    for (final p in ring) {
      if (!p.dx.isFinite || !p.dy.isFinite) continue;
      valid++;
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    if (valid < 3) return null;
    final spanX = maxX - minX;
    final spanY = maxY - minY;
    // A collapsed edge has no interior. Padding must not turn a line into a box.
    if (spanX < 1e-4 || spanY < 1e-4) return null;

    // One logical pixel of padding so samples that sit on the lasso bounds
    // still land inside the grid.
    const pad = 1.0;
    minX -= pad;
    minY -= pad;
    maxX += pad;
    maxY += pad;
    final paddedSpanX = maxX - minX;
    final paddedSpanY = maxY - minY;
    final longest = math.max(paddedSpanX, paddedSpanY);
    var scale = math.min(maxCellsPerUnit, maxSide / longest);
    var width = math.max(1, (paddedSpanX * scale).ceil());
    var height = math.max(1, (paddedSpanY * scale).ceil());
    if (width > maxSide || height > maxSide) {
      scale *= maxSide / math.max(width, height);
      width = math.max(1, (paddedSpanX * scale).ceil());
      height = math.max(1, (paddedSpanY * scale).ceil());
    }
    width = math.min(width, maxSide);
    height = math.min(height, maxSide);

    final pixelPoints = <Offset>[];
    for (final p in ring) {
      if (!p.dx.isFinite || !p.dy.isFinite) continue;
      final pixel = Offset((p.dx - minX) * scale, (p.dy - minY) * scale);
      if (pixelPoints.isNotEmpty &&
          (pixelPoints.last - pixel).distanceSquared < 1e-8) {
        continue;
      }
      pixelPoints.add(pixel);
    }
    if (pixelPoints.length >= 2 &&
        (pixelPoints.first - pixelPoints.last).distanceSquared > 1e-8) {
      pixelPoints.add(pixelPoints.first);
    }
    if (pixelPoints.length < 4) return null;

    final coverage = Uint8List(width * height);
    _rasterizeNonZero(pixelPoints, width, height, coverage);
    // Path.contains treats the boundary as inside. One cell of dilation covers
    // the pixel that owns an edge sample (its center sits just outside).
    _dilate4(coverage, width, height);
    return LassoCoverageMask._(
      origin: Offset(minX, minY),
      scale: scale,
      width: width,
      height: height,
      coverage: coverage,
    );
  }

  bool contains(Offset point) {
    if (!point.dx.isFinite || !point.dy.isFinite || scale == 0) return false;
    final x = ((point.dx - origin.dx) * scale).floor();
    final y = ((point.dy - origin.dy) * scale).floor();
    if (x < 0 || y < 0 || x >= width || y >= height) return false;
    return _coverage[y * width + x] != 0;
  }

  /// Keeps the first, last, and a uniform stride so a minutes-long lasso
  /// cannot blow the scanline tables. Dense stylus points make the stride
  /// visually lossless at selection tolerance.
  static List<Offset> _decimate(List<Offset> points, int maxPoints) {
    if (points.length <= maxPoints) return points;
    final step = (points.length / maxPoints).ceil();
    final reduced = <Offset>[];
    for (var i = 0; i < points.length; i += step) {
      reduced.add(points[i]);
    }
    final last = points.last;
    if (reduced.last != last) reduced.add(last);
    return reduced;
  }
}

void _dilate4(Uint8List coverage, int width, int height) {
  if (width == 0 || height == 0) return;
  final src = Uint8List.fromList(coverage);
  for (var j = 0; j < height; j++) {
    final row = j * width;
    for (var i = 0; i < width; i++) {
      if (src[row + i] == 0) continue;
      if (i > 0) coverage[row + i - 1] = 1;
      if (i + 1 < width) coverage[row + i + 1] = 1;
      if (j > 0) coverage[row - width + i] = 1;
      if (j + 1 < height) coverage[row + width + i] = 1;
    }
  }
}

void _rasterizeNonZero(
  List<Offset> closed,
  int width,
  int height,
  Uint8List coverage,
) {
  final rows = List<List<_SpanHit>>.generate(height, (_) => <_SpanHit>[]);
  final edgeCount = closed.length - 1;
  for (var i = 0; i < edgeCount; i++) {
    final a = closed[i];
    final b = closed[i + 1];
    final dy = b.dy - a.dy;
    if (dy.abs() < 1e-9) continue;
    final winding = dy > 0 ? 1 : -1;
    final double topY;
    final double botY;
    final double topX;
    final double botX;
    if (a.dy < b.dy) {
      topY = a.dy;
      botY = b.dy;
      topX = a.dx;
      botX = b.dx;
    } else {
      topY = b.dy;
      botY = a.dy;
      topX = b.dx;
      botX = a.dx;
    }
    final span = botY - topY;
    // Half-open [topY, botY) so a shared vertex is emitted by only one edge.
    var j0 = (topY - 0.5).ceil();
    var j1 = (botY - 0.5).ceil() - 1;
    if (j0 < 0) j0 = 0;
    if (j1 >= height) j1 = height - 1;
    if (j0 > j1) continue;
    final dx = botX - topX;
    for (var j = j0; j <= j1; j++) {
      final t = ((j + 0.5) - topY) / span;
      rows[j].add(_SpanHit(topX + dx * t, winding));
    }
  }

  for (var j = 0; j < height; j++) {
    final hits = rows[j];
    if (hits.isEmpty) continue;
    hits.sort((a, b) => a.x.compareTo(b.x));
    var winding = 0;
    double? spanStart;
    for (final hit in hits) {
      final wasInside = winding != 0;
      winding += hit.winding;
      final isInside = winding != 0;
      if (!wasInside && isInside) {
        spanStart = hit.x;
      } else if (wasInside && !isInside && spanStart != null) {
        _fillSpan(coverage, width, j, spanStart, hit.x);
        spanStart = null;
      }
    }
  }
}

void _fillSpan(
  Uint8List coverage,
  int width,
  int j,
  double left,
  double right,
) {
  if (right <= left) return;
  // Pixel i is inside when its center (i + 0.5) lies in [left, right).
  var i0 = (left - 0.5).ceil();
  var i1 = (right - 0.5).ceil() - 1;
  if (i0 < 0) i0 = 0;
  if (i1 >= width) i1 = width - 1;
  if (i0 > i1) return;
  final row = j * width;
  for (var i = i0; i <= i1; i++) {
    coverage[row + i] = 1;
  }
}

class _SpanHit {
  const _SpanHit(this.x, this.winding);

  final double x;
  final int winding;
}
