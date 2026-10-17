// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/lasso_coverage_mask.dart';
import 'package:vector_math/vector_math_64.dart' as vmath;

class Select extends Tool {
  Select._();

  static final _currentSelect = Select._();
  static Select get currentSelect => _currentSelect;

  static const minPercentInside = 0.7;

  /// At or above this many strokes overlapping the lasso, hit-testing switches
  /// from outlined polygons to a temporary coverage mask. Outlining every
  /// stroke and running [Path.contains] on a stylus-density lasso is what
  /// freezes pen-up; the mask keeps that case interactive.
  static const rasterStrokeThreshold = 48;

  /// Centerline samples that also force the mask, so a few very long strokes
  /// cannot stall pen-up on their own.
  static const rasterSampleThreshold = 6000;

  /// Centerline samples per stroke while probing the mask. Enough for a stable
  /// 70% decision without walking multi-thousand-point strokes point by point.
  static const rasterSamplesPerStroke = 96;

  final List<Offset> _lassoPoints = [];

  var selectResult = SelectResult(
    pageIndex: -1,
    strokes: const [],
    images: const [],
    path: Path(),
    pageIndexStart: -1,
  );
  var doneSelecting = false;

  @override
  ToolId get toolId => .select;

  void unselect() {
    doneSelecting = false;
    _lassoPoints.clear();
    selectResult = SelectResult(
      pageIndex: -1,
      strokes: const [],
      images: const [],
      path: Path(),
      pageIndexStart: -1,
    );
  }

  Color? getDominantStrokeColor() {
    if (!doneSelecting) return null;
    if (selectResult.strokes.isEmpty) return null;

    final colorDistribution = <Color, int>{};
    for (final stroke in selectResult.strokes) {
      colorDistribution.update(
        stroke.color,
        (value) => value + stroke.length,
        ifAbsent: () => stroke.length,
      );
    }
    assert(colorDistribution.isNotEmpty);

    return colorDistribution.entries.reduce((a, b) {
      return a.value > b.value ? a : b;
    }).key;
  }

  void onDragStart(Offset position, int pageIndex) {
    doneSelecting = false;
    selectResult = SelectResult(
      pageIndex: pageIndex,
      strokes: [],
      images: [],
      path: Path(),
      pageIndexStart: pageIndex,
    );
    _lassoPoints
      ..clear()
      ..add(position);
    selectResult.path.moveTo(position.dx, position.dy);
    onDragUpdate(position);
  }

  void onDragUpdate(Offset position) {
    selectResult.path.lineTo(position.dx, position.dy);
    if (_lassoPoints.isEmpty || _lassoPoints.last != position) {
      _lassoPoints.add(position);
    }
  }

  void onDragEnd(List<Stroke> strokes, List<EditorImage> images) {
    selectResult.path.close();
    doneSelecting = true;

    final lassoBounds = selectResult.path.getBounds();
    final candidates = <Stroke>[];
    var candidateSamples = 0;
    if (lassoBounds.width > 0 || lassoBounds.height > 0) {
      for (final stroke in strokes) {
        if (stroke.sampleCount == 0) continue;
        // Bounds already include half the pen width. A little extra slack
        // keeps wide outlines that poke past that box in the precise test.
        final rejectBounds = stroke.bounds.inflate(stroke.options.size);
        if (!rejectBounds.overlaps(lassoBounds)) continue;
        candidates.add(stroke);
        candidateSamples += stroke.sampleCount;
      }
    }

    final useMask =
        candidates.isNotEmpty &&
        _lassoPoints.length >= 3 &&
        (candidates.length >= rasterStrokeThreshold ||
            candidateSamples >= rasterSampleThreshold);
    if (useMask) {
      final mask = LassoCoverageMask.fromPolyline(_lassoPoints);
      if (mask != null) {
        for (final stroke in candidates) {
          if (_centerlineMostlyInside(mask, stroke)) {
            selectResult.strokes.add(stroke);
          }
        }
      }
    } else {
      final path = selectResult.path;
      for (final stroke in candidates) {
        if (_polygonMostlyInside(path, stroke.lowQualityPolygon)) {
          selectResult.strokes.add(stroke);
        }
      }
    }

    for (int i = 0; i < images.length; i++) {
      final image = images[i];
      if (lassoBounds.width > 0 || lassoBounds.height > 0) {
        if (!image.dstRect.overlaps(lassoBounds)) continue;
      }
      final percentInside = rectPercentInside(selectResult.path, image.dstRect);
      if (percentInside >= minPercentInside) {
        selectResult.images.add(image);
      }
    }

    if (selectResult.images.isNotEmpty) {
      final firstImage = selectResult.images.first;
      if (firstImage.rotationDeg != 0.0) {
        selectResult.rotationDeg = firstImage.rotationDeg;
      }
    } else if (selectResult.strokes.isNotEmpty) {
      final firstStroke = selectResult.strokes.first;
      if (firstStroke.rotationDeg != 0.0) {
        selectResult.rotationDeg = firstStroke.rotationDeg;
      }
    }
  }

  static double rectPercentInside(Path selection, Rect rect) {
    const int gridSize = 5;
    final gridCellWidth = rect.width / (gridSize - 1);
    final gridCellHeight = rect.height / (gridSize - 1);

    int pointsInside = 0;
    for (int x = 0; x < gridSize; x++) {
      for (int y = 0; y < gridSize; y++) {
        if (selection.contains(
          Offset(rect.left + gridCellWidth * x, rect.top + gridCellHeight * y),
        )) {
          pointsInside++;
        }
      }
    }

    return pointsInside / (gridSize * gridSize) * 1.25;
  }

  static double polygonPercentInside(Path selection, List<Offset> polygon) {
    if (polygon.isEmpty) return 0;
    int pointsInside = 0;
    for (final point in polygon) {
      if (selection.contains(point)) {
        pointsInside++;
      }
    }
    return pointsInside / polygon.length;
  }

  /// Same threshold as [polygonPercentInside], but stops once the stroke is
  /// clearly inside or clearly outside so a miss does not walk the whole
  /// outline against a long lasso.
  static bool _polygonMostlyInside(Path selection, List<Offset> polygon) {
    final total = polygon.length;
    if (total == 0) return false;
    var inside = 0;
    for (var seen = 0; seen < total; seen++) {
      if (selection.contains(polygon[seen])) inside++;
      final remaining = total - seen - 1;
      if (inside / total > minPercentInside) return true;
      if ((inside + remaining) / total <= minPercentInside) return false;
    }
    return false;
  }

  static bool _centerlineMostlyInside(LassoCoverageMask mask, Stroke stroke) {
    final points = stroke.pointsForEraser;
    final n = points.length;
    if (n == 0) return false;
    final step = math.max(1, n ~/ rasterSamplesPerStroke);
    final last = n - 1;
    final extraLast = last % step != 0;
    final total = ((n + step - 1) ~/ step) + (extraLast ? 1 : 0);
    var inside = 0;
    var seen = 0;
    for (var i = 0; i < n; i += step) {
      seen++;
      final p = points[i];
      if (mask.contains(Offset(p.x, p.y))) inside++;
      final remaining = total - seen;
      if (inside / total > minPercentInside) return true;
      if ((inside + remaining) / total <= minPercentInside) return false;
    }
    if (extraLast) {
      final p = points[last];
      if (mask.contains(Offset(p.x, p.y))) inside++;
    }
    return inside / total > minPercentInside;
  }
}

class SelectResult {
  int pageIndex;
  final List<Stroke> strokes;
  final List<EditorImage> images;
  Path path;

  int pageIndexStart;

  double _rotationDeg = 0.0;
  double get rotationDeg => _rotationDeg;
  set rotationDeg(double value) {
    _rotationDeg = value;
  }

  Rect? displayBounds;
  List<SelectionGuideLine> alignmentGuides = const [];

  SelectResult({
    required this.pageIndex,
    required this.strokes,
    required this.images,
    required this.path,
    required this.pageIndexStart,
    double rotationDeg = 0.0,
    this.displayBounds,
  }) : _rotationDeg = rotationDeg;

  bool get isEmpty {
    return strokes.isEmpty && images.isEmpty;
  }

  SelectResult copyWith({
    int? pageIndex,
    List<Stroke>? strokes,
    List<EditorImage>? images,
    Path? path,
    int? pageIndexStart,
    double? rotationDeg,
    Rect? displayBounds,
    List<SelectionGuideLine>? alignmentGuides,
  }) {
    return SelectResult(
      pageIndex: pageIndex ?? this.pageIndex,
      strokes: strokes ?? this.strokes,
      images: images ?? this.images,
      path: path ?? this.path,
      pageIndexStart: pageIndexStart ?? this.pageIndexStart,
      rotationDeg: rotationDeg ?? this.rotationDeg,
      displayBounds: displayBounds ?? this.displayBounds,
    )..alignmentGuides = alignmentGuides ?? this.alignmentGuides;
  }

  void clearAlignmentGuides() {
    alignmentGuides = const [];
  }

  Rect getBounds() {
    if (displayBounds != null) return displayBounds!;
    if (isEmpty) return Rect.zero;

    // Un-rotation is a no-op at 0°, and [getCentroid] would otherwise walk
    // every selected sample (or outline) only to discard the result.
    final pivot = rotationDeg == 0 ? Offset.zero : getCentroid();
    displayBounds = _boundsUnrotatedAround(pivot);
    return displayBounds!;
  }

  /// Recomputes [displayBounds] in the selection's unrotated frame,
  /// un-rotating current geometry around [pivot] instead of the
  /// point-average centroid.
  ///
  /// Commits must use the gesture pivot: un-rotating around a drifting
  /// centroid moves the box on every rotation, so the next rotation orbits
  /// a new center (content visibly translates and the overlay detaches).
  /// Un-rotating around the gesture pivot returns the exact pre-transform
  /// box, keeping the pivot fixed across rotations and making a
  /// rotate-forth-and-back round trip identity.
  void recomputeBoundsAround(Offset pivot) {
    if (isEmpty) {
      displayBounds = Rect.zero;
      return;
    }
    displayBounds = _boundsUnrotatedAround(pivot);
  }

  Rect _boundsUnrotatedAround(Offset center) {
    Rect? bounds;
    final rotationRad = rotationDeg * math.pi / 180.0;
    final cosUnrotate = math.cos(-rotationRad);
    final sinUnrotate = math.sin(-rotationRad);

    Offset unrotateAroundSelection(Offset p) {
      if (rotationDeg == 0) return p;
      final dx = p.dx - center.dx;
      final dy = p.dy - center.dy;
      return Offset(
        center.dx + dx * cosUnrotate - dy * sinUnrotate,
        center.dy + dx * sinUnrotate + dy * cosUnrotate,
      );
    }

    if (strokes.length >= Select.rasterStrokeThreshold) {
      // Union of stroke bounds (or unrotated centerline samples). Building
      // the high-quality outline of every selected stroke just to size the
      // box repeats the pen-up stall after a large lasso.
      bounds = _fastStrokeBounds(unrotateAroundSelection);
    } else {
      for (final stroke in strokes) {
        final poly = stroke.highQualityPolygon;

        for (final pt in poly) {
          final transformedPt = unrotateAroundSelection(pt);

          final pointRect = Rect.fromLTWH(
            transformedPt.dx,
            transformedPt.dy,
            0,
            0,
          );
          final currentBounds = bounds;
          bounds = currentBounds == null
              ? pointRect
              : currentBounds.expandToInclude(pointRect);
        }
      }
    }

    for (final image in images) {
      final imageRotationRad = image.rotationDeg * math.pi / 180.0;
      final imageCos = math.cos(imageRotationRad);
      final imageSin = math.sin(imageRotationRad);
      final imageCenter = image.dstRect.center;
      final corners = <Offset>[
        image.dstRect.topLeft,
        image.dstRect.topRight,
        image.dstRect.bottomRight,
        image.dstRect.bottomLeft,
      ];

      for (final corner in corners) {
        final cornerDx = corner.dx - imageCenter.dx;
        final cornerDy = corner.dy - imageCenter.dy;
        final rotatedCorner = image.rotationDeg == 0
            ? corner
            : Offset(
                imageCenter.dx + cornerDx * imageCos - cornerDy * imageSin,
                imageCenter.dy + cornerDx * imageSin + cornerDy * imageCos,
              );
        final transformedCorner = unrotateAroundSelection(rotatedCorner);
        final pointRect = Rect.fromLTWH(
          transformedCorner.dx,
          transformedCorner.dy,
          0,
          0,
        );
        final currentBounds = bounds;
        bounds = currentBounds == null
            ? pointRect
            : currentBounds.expandToInclude(pointRect);
      }
    }

    return bounds ?? Rect.zero;
  }

  Rect? _fastStrokeBounds(Offset Function(Offset) unrotate) {
    Rect? bounds;
    if (rotationDeg == 0) {
      for (final stroke in strokes) {
        if (stroke.sampleCount == 0) continue;
        final strokeBounds = stroke.bounds;
        final currentBounds = bounds;
        bounds = currentBounds == null
            ? strokeBounds
            : currentBounds.expandToInclude(strokeBounds);
      }
      return bounds;
    }

    for (final stroke in strokes) {
      final points = stroke.pointsForEraser;
      if (points.isEmpty) continue;
      var minX = double.infinity;
      var minY = double.infinity;
      var maxX = double.negativeInfinity;
      var maxY = double.negativeInfinity;
      for (final point in points) {
        final unrotated = unrotate(Offset(point.x, point.y));
        if (unrotated.dx < minX) minX = unrotated.dx;
        if (unrotated.dy < minY) minY = unrotated.dy;
        if (unrotated.dx > maxX) maxX = unrotated.dx;
        if (unrotated.dy > maxY) maxY = unrotated.dy;
      }
      final margin = stroke.options.size / 2;
      final strokeBounds = Rect.fromLTRB(
        minX - margin,
        minY - margin,
        maxX + margin,
        maxY + margin,
      );
      final currentBounds = bounds;
      bounds = currentBounds == null
          ? strokeBounds
          : currentBounds.expandToInclude(strokeBounds);
    }
    return bounds;
  }

  bool contains(Offset position) {
    if (isEmpty) return false;
    final centroid = getCentroid();
    final rotationRad = rotationDeg * math.pi / 180.0;
    final dx = position.dx - centroid.dx;
    final dy = position.dy - centroid.dy;
    final unrotatedPos = Offset(
      centroid.dx + dx * math.cos(-rotationRad) - dy * math.sin(-rotationRad),
      centroid.dy + dx * math.sin(-rotationRad) + dy * math.cos(-rotationRad),
    );
    return getBounds().contains(unrotatedPos);
  }

  Offset getCentroid() {
    if (isEmpty) return Offset.zero;
    final bounds = displayBounds;
    if (bounds != null) return bounds.center;
    if (strokes.length >= Select.rasterStrokeThreshold) {
      return _sampleCentroid();
    }

    final allPoints = <Offset>[];
    for (final stroke in strokes) {
      allPoints.addAll(stroke.highQualityPolygon);
    }
    for (final image in images) {
      allPoints.add(image.dstRect.center);
    }

    return getCentroidForPoints(allPoints);
  }

  /// Average of stored centerline samples. Used when outlining every stroke
  /// just to find a pivot would stall. [getBounds] calls this while
  /// [displayBounds] is still null, so it must not call back into [getBounds].
  Offset _sampleCentroid() {
    var x = 0.0;
    var y = 0.0;
    var count = 0;
    for (final stroke in strokes) {
      final points = stroke.pointsForEraser;
      if (points.isEmpty) continue;
      final step = math.max(1, points.length ~/ 32);
      for (var i = 0; i < points.length; i += step) {
        x += points[i].x;
        y += points[i].y;
        count++;
      }
    }
    for (final image in images) {
      final center = image.dstRect.center;
      x += center.dx;
      y += center.dy;
      count++;
    }
    if (count == 0) return Offset.zero;
    return Offset(x / count, y / count);
  }

  static Offset getCentroidForPoints(Iterable<Offset> points) {
    if (points.isEmpty) return Offset.zero;
    double x = 0, y = 0;
    for (final p in points) {
      x += p.dx;
      y += p.dy;
    }
    return Offset(x / points.length, y / points.length);
  }
}

class SelectionTransformPreview {
  const SelectionTransformPreview({
    required this.baseBounds,
    required this.pivot,
    required this.baseRotationDeg,
    this.translation = Offset.zero,
    this.scale = 1.0,
    this.rotationDeltaDeg = 0.0,
  });

  factory SelectionTransformPreview.fromSelection(SelectResult selection) {
    final bounds = selection.displayBounds ?? selection.getBounds();
    return SelectionTransformPreview(
      baseBounds: bounds,
      pivot: bounds.center,
      baseRotationDeg: selection.rotationDeg,
    );
  }

  final Rect baseBounds;
  final Offset pivot;
  final double baseRotationDeg;
  final Offset translation;
  final double scale;
  final double rotationDeltaDeg;

  bool get isIdentity =>
      translation == Offset.zero && scale == 1.0 && rotationDeltaDeg == 0.0;

  double get effectiveRotationDeg => baseRotationDeg + rotationDeltaDeg;

  Rect get visualBounds => Rect.fromCenter(
    center: transformPoint(baseBounds.center, includeRotation: false),
    width: baseBounds.width * scale,
    height: baseBounds.height * scale,
  );

  vmath.Matrix4 get transformMatrix => vmath.Matrix4.identity()
    ..translate(translation.dx, translation.dy)
    ..translate(pivot.dx, pivot.dy)
    ..rotateZ(rotationDeltaDeg * math.pi / 180.0)
    ..scale(scale, scale)
    ..translate(-pivot.dx, -pivot.dy);

  Offset transformPoint(Offset point, {bool includeRotation = true}) {
    final scaled = Offset(
      pivot.dx + (point.dx - pivot.dx) * scale,
      pivot.dy + (point.dy - pivot.dy) * scale,
    );
    final rotated = includeRotation && rotationDeltaDeg != 0.0
        ? _rotateAround(scaled, pivot, rotationDeltaDeg * math.pi / 180.0)
        : scaled;
    return rotated.translate(translation.dx, translation.dy);
  }

  Rect transformRect(Rect rect) {
    final scaledCenter = Offset(
      pivot.dx + (rect.center.dx - pivot.dx) * scale,
      pivot.dy + (rect.center.dy - pivot.dy) * scale,
    );
    final rotatedCenter = rotationDeltaDeg == 0.0
        ? scaledCenter
        : _rotateAround(
            scaledCenter,
            pivot,
            rotationDeltaDeg * math.pi / 180.0,
          );
    return Rect.fromCenter(
      center: rotatedCenter.translate(translation.dx, translation.dy),
      width: rect.width * scale,
      height: rect.height * scale,
    );
  }

  SelectionTransformPreview copyWith({
    Rect? baseBounds,
    Offset? pivot,
    double? baseRotationDeg,
    Offset? translation,
    double? scale,
    double? rotationDeltaDeg,
  }) {
    return SelectionTransformPreview(
      baseBounds: baseBounds ?? this.baseBounds,
      pivot: pivot ?? this.pivot,
      baseRotationDeg: baseRotationDeg ?? this.baseRotationDeg,
      translation: translation ?? this.translation,
      scale: scale ?? this.scale,
      rotationDeltaDeg: rotationDeltaDeg ?? this.rotationDeltaDeg,
    );
  }

  static Offset _rotateAround(Offset point, Offset center, double angleRad) {
    final dx = point.dx - center.dx;
    final dy = point.dy - center.dy;
    final cosTheta = math.cos(angleRad);
    final sinTheta = math.sin(angleRad);
    return Offset(
      center.dx + dx * cosTheta - dy * sinTheta,
      center.dy + dx * sinTheta + dy * cosTheta,
    );
  }
}

class SelectionGuideLine {
  final Offset start;
  final Offset end;

  const SelectionGuideLine({required this.start, required this.end});
}
