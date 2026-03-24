// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:vector_math/vector_math_64.dart' as vmath;

class Select extends Tool {
  Select._();

  static final _currentSelect = Select._();
  static Select get currentSelect => _currentSelect;

  static const minPercentInside = 0.7;

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
    selectResult.pageIndex = -1;
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
    selectResult.path.moveTo(position.dx, position.dy);
    onDragUpdate(position);
  }

  void onDragUpdate(Offset position) {
    selectResult.path.lineTo(position.dx, position.dy);
  }

  void onDragEnd(List<Stroke> strokes, List<EditorImage> images) {
    selectResult.path.close();
    doneSelecting = true;

    for (int i = 0; i < strokes.length; i++) {
      final stroke = strokes[i];
      final percentInside = polygonPercentInside(
        selectResult.path,
        stroke.lowQualityPolygon,
      );
      if (percentInside > minPercentInside) {
        selectResult.strokes.add(stroke);
      }
    }

    for (int i = 0; i < images.length; i++) {
      final image = images[i];
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
    int pointsInside = 0;
    for (final point in polygon) {
      if (selection.contains(point)) {
        pointsInside++;
      }
    }
    return pointsInside / polygon.length;
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

    final centroid = getCentroid();
    Rect? bounds;
    final rotationRad = rotationDeg * math.pi / 180.0;
    final cosUnrotate = math.cos(-rotationRad);
    final sinUnrotate = math.sin(-rotationRad);

    Offset unrotateAroundSelection(Offset p) {
      if (rotationDeg == 0) return p;
      final dx = p.dx - centroid.dx;
      final dy = p.dy - centroid.dy;
      return Offset(
        centroid.dx + dx * cosUnrotate - dy * sinUnrotate,
        centroid.dy + dx * sinUnrotate + dy * cosUnrotate,
      );
    }
    

    for (final stroke in strokes) {
      final poly = stroke.highQualityPolygon;
      
      for (final pt in poly) {
        final transformedPt = unrotateAroundSelection(pt);
        
        final pointRect = Rect.fromLTWH(transformedPt.dx, transformedPt.dy, 0, 0);
        final currentBounds = bounds;
        bounds = currentBounds == null
            ? pointRect
            : currentBounds.expandToInclude(pointRect);
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
    
    displayBounds = bounds ?? Rect.zero;
    return displayBounds!;
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
    
    final allPoints = <Offset>[];
    for (final stroke in strokes) {
      allPoints.addAll(stroke.highQualityPolygon);
    }
    for (final image in images) {
      allPoints.add(image.dstRect.center);
    }
    
    return getCentroidForPoints(allPoints);
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
      translation == Offset.zero &&
      scale == 1.0 &&
      rotationDeltaDeg == 0.0;

  double get effectiveRotationDeg => baseRotationDeg + rotationDeltaDeg;

  Rect get visualBounds => Rect.fromCenter(
    center: transformPoint(baseBounds.center, includeRotation: false),
    width: baseBounds.width * scale,
    height: baseBounds.height * scale,
  );

  vmath.Matrix4 get transformMatrix =>
      vmath.Matrix4.identity()
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
