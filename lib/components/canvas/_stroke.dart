// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_shape_stroke.dart';
import 'package:saber/data/editor/binary_writer.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/dynamic_extensions.dart';
import 'package:saber/data/extensions/list_extensions.dart';
import 'package:saber/data/extensions/point_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/highlighter.dart';

class BinaryOptions {
  void optionsToBinary(BinaryWriter writer, StrokeOptions options) {
    if (options.size != StrokeOptions.defaultSize) {
      writer.writeFloat(StrokeBinaryKeys.size, options.size);
    }
    if (options.thinning != StrokeOptions.defaultThinning) {
      writer.writeFloat(StrokeBinaryKeys.thinning, options.thinning);
    }
    if (options.smoothing != StrokeOptions.defaultSmoothing) {
      writer.writeFloat(StrokeBinaryKeys.smoothing, options.smoothing);
    }
    if (options.streamline != StrokeOptions.defaultStreamline) {
      writer.writeFloat(StrokeBinaryKeys.streamline, options.streamline);
    }
    if (options.simulatePressure != StrokeOptions.defaultSimulatePressure) {
      writer.writeBool(
        StrokeBinaryKeys.simulatePressure,
        options.simulatePressure,
      );
    }
    if (options.isComplete != StrokeOptions.defaultIsComplete) {
      writer.writeBool(StrokeBinaryKeys.isComplete, options.isComplete);
    }
    if (options.start.taperEnabled) {
      writer.writeBool(
        StrokeBinaryKeys.startTaperEnabled,
        options.start.taperEnabled,
      );
      if (options.start.customTaper != null) {
        writer.writeFloat(
          StrokeBinaryKeys.startCustomTaper,
          options.start.customTaper!,
        );
      }
    } else {
      writer.writeBool(
        StrokeBinaryKeys.startTaperEnabled,
        options.start.taperEnabled,
      );
    }
    if (options.start.cap != StrokeEndOptions.defaultCap) {
      writer.writeBool(
        StrokeBinaryKeys.endTaperEnabled,
        options.end.taperEnabled,
      );
      writer.writeBool(StrokeBinaryKeys.startCap, options.start.cap);
    }
    if (options.end.taperEnabled) {
      writer.writeBool(
        StrokeBinaryKeys.endTaperEnabled,
        options.end.taperEnabled,
      );
      if (options.end.customTaper != null) {
        writer.writeFloat(
          StrokeBinaryKeys.endCustomTaper,
          options.end.customTaper!,
        );
      }
    } else {
      writer.writeBool(StrokeBinaryKeys.endTaperEnabled, false);
    }
    if (options.end.cap != StrokeEndOptions.defaultCap) {
      writer.writeBool(StrokeBinaryKeys.endCap, options.end.cap);
    }
    writer.writeKey(StrokeBinaryKeys.endOptions);
  }

  StrokeOptions optionsFromBinary(BinaryReader reader, {int? initialKey}) {
    int key;
    double size = StrokeOptions.defaultSize;
    double thinning = StrokeOptions.defaultThinning;
    double smoothing = StrokeOptions.defaultSmoothing;
    double streamLine = StrokeOptions.defaultStreamline;
    bool simulatePressure = StrokeOptions.defaultSimulatePressure;
    bool isComplete = StrokeOptions.defaultIsComplete;
    double? startCustomTaper;
    double? endCustomTaper;
    bool startCap = StrokeEndOptions.defaultCap;
    bool endCap = StrokeEndOptions.defaultCap;
    bool startTaperEnabled = false;
    bool endTaperEnabled = false;
    key = initialKey ?? reader.readKey();
    while (key != StrokeBinaryKeys.endOptions) {
      switch (key) {
        case StrokeBinaryKeys.size:
          size = reader.readFloat();
        case StrokeBinaryKeys.thinning:
          thinning = reader.readFloat();
        case StrokeBinaryKeys.smoothing:
          smoothing = reader.readFloat();
        case StrokeBinaryKeys.streamline:
          streamLine = reader.readFloat();
        case StrokeBinaryKeys.simulatePressure:
          simulatePressure = reader.readBoolNoKey();
        case StrokeBinaryKeys.isComplete:
          isComplete = reader.readBoolNoKey();
        case StrokeBinaryKeys.startTaperEnabled:
          startTaperEnabled = reader.readBoolNoKey();
        case StrokeBinaryKeys.startCustomTaper:
          startCustomTaper = reader.readFloat();
        case StrokeBinaryKeys.startCap:
          startCap = reader.readBoolNoKey();
        case StrokeBinaryKeys.endTaperEnabled:
          endTaperEnabled = reader.readBoolNoKey();
        case StrokeBinaryKeys.endCustomTaper:
          endCustomTaper = reader.readFloat();
        case StrokeBinaryKeys.endCap:
          endCap = reader.readBoolNoKey();
      }
      key = reader.readKey();
    }

    final start = StrokeEndOptions.start(
      customTaper: startCustomTaper,
      taperEnabled: startTaperEnabled,
      cap: startCap,
      easing: StrokeOptions.defaultEasing,
    );
    final end = StrokeEndOptions.end(
      customTaper: endCustomTaper,
      taperEnabled: endTaperEnabled,
      cap: endCap,
      easing: StrokeOptions.defaultEasing,
    );
    return StrokeOptions(
      size: size,
      thinning: thinning,
      smoothing: smoothing,
      streamline: streamLine,
      easing: StrokeOptions.defaultEasing,
      simulatePressure: simulatePressure,
      start: start,
      end: end,
      isComplete: isComplete,
    );
  }
}

class Stroke implements HasBounds, Comparable<Stroke> {
  static final log = Logger('Stroke');

  int zIndex = 0;

  @visibleForTesting
  @protected
  final List<PointVector> points = [];

  Float32List? _packedPoints;

  void _ensurePackedPoints() {
    final List<PointVector> src = _pointsForLiveRender(points);
    final int len = src.length;
    if (_packedPoints != null && _packedPoints!.length == len * 3) return;
    _packedPoints = Float32List(len * 3);
    for (int i = 0; i < len; i++) {
      final p = src[i];
      final int o = i * 3;
      _packedPoints![o] = p.x;
      _packedPoints![o + 1] = p.y;
      _packedPoints![o + 2] = p.pressure ?? 0.5;
    }
  }

  List<PointVector> get pointsForEraser => points;

  void replacePointsFromEraser(List<PointVector> newPoints) {
    points
      ..clear()
      ..addAll(newPoints);
    _cachedBounds = null;
    _packedPoints = null;
    _cachedAveragePressure = null;
    markPolygonNeedsUpdating();
  }

  void replacePointRangeFromEraser(
    List<PointVector> source,
    int start,
    int end,
  ) {
    points.clear();
    for (int i = start; i <= end; i++) {
      points.add(source[i]);
    }
    _cachedBounds = null;
    _packedPoints = null;
    _cachedAveragePressure = null;
    markPolygonNeedsUpdating();
  }

  bool get isEmpty => points.isEmpty;

  @override
  int compareTo(Stroke other) => zIndex.compareTo(other.zIndex);
  int get length => points.length;

  int pageIndex;
  HasSize page;
  final ToolId toolId;

  String get penType => toolId.id;

  static const defaultColor = Colors.black;
  static const defaultPressureEnabled = true;

  Color color;
  bool pressureEnabled;
  final StrokeOptions options;
  double? _cachedAveragePressure;

  double rotationDeg = 0.0;

  bool flatEdge = stows.highlighterFlatEdge.value;

  double get averagePressure {
    if (_cachedAveragePressure != null) return _cachedAveragePressure!;
    if (points.isEmpty) return _cachedAveragePressure = 0.5;
    double sum = 0;
    int count = 0;
    for (final point in points) {
      sum += point.pressure ?? 0.5;
      count++;
    }
    return _cachedAveragePressure = count == 0 ? 0.5 : (sum / count);
  }

  Rect? _cachedBounds;

  @override
  Rect get bounds {
    if (_cachedBounds != null) return _cachedBounds!;

    if (this is ShapeStroke) {
      final shapeBounds = (this as ShapeStroke).shapePath.getBounds();
      final double margin = options.size / 2;
      return _cachedBounds = shapeBounds.inflate(margin);
    }

    if (points.isEmpty) return _cachedBounds = Rect.zero;

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    final double margin = options.size / 2;

    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }

    _cachedBounds = Rect.fromLTRB(
      minX - margin,
      minY - margin,
      maxX + margin,
      maxY + margin,
    );

    return _cachedBounds!;
  }

  int get geometricFingerprint {
    if (points.isEmpty) {
      return Object.hash(color, options.size, toolId.index, 0);
    }
    final first = points.first;
    final last = points.last;
    return Object.hash(
      first.x.toInt(),
      first.y.toInt(),
      last.x.toInt(),
      last.y.toInt(),
      points.length,
      color.value,
      (options.size * 1000).round(),
      toolId.index,
    );
  }

  void _invalidateSpatialData() {
    _cachedBounds = null;
  }

  List<Offset>? _lowQualityPolygon, _highQualityPolygon;
  List<Offset> get lowQualityPolygon =>
      _lowQualityPolygon ??= getPolygon(quality: StrokeQuality.low);
  List<Offset> get highQualityPolygon =>
      _highQualityPolygon ??= getPolygon(quality: StrokeQuality.high);

  Path? _lowQualityPath;
  Path get lowQualityPath =>
      _lowQualityPath ??= getPath(lowQualityPolygon, smooth: true);

  Path get highQualityPath {
    if (_cachedPath != null && _cachedPathValid) return _cachedPath!;

    _cachedPath ??= Path();
    _cachedPath!.reset();

    final poly = getPolygon(quality: StrokeQuality.high);
    if (poly.isEmpty) return _cachedPath!;

    const epsilon = 1e-6;
    final List<Offset> reduced = [poly[0]];
    for (int i = 1; i < poly.length; i++) {
      final prev = reduced.last;
      final p = poly[i];
      if ((p.dx - prev.dx).abs() > epsilon ||
          (p.dy - prev.dy).abs() > epsilon) {
        reduced.add(p);
      }
    }

    if (reduced.length >= 2) {
      final first = reduced.first;
      final last = reduced.last;
      if ((last.dx - first.dx).abs() <= epsilon &&
          (last.dy - first.dy).abs() <= epsilon) {
        reduced.removeLast();
      }
    }
    if (reduced.isEmpty) return _cachedPath!;

    final pathPoints = reduced;

    if (toolId == ToolId.calligraphyPen &&
        options.isComplete &&
        pathPoints.length >= 3) {
      _cachedPath!.moveTo(pathPoints[0].dx, pathPoints[0].dy);
      for (int i = 1; i < pathPoints.length - 1; i++) {
        final p1 = pathPoints[i];
        final p2 = pathPoints[i + 1];
        final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        _cachedPath!.quadraticBezierTo(p1.dx, p1.dy, mid.dx, mid.dy);
      }
      _cachedPath!.lineTo(pathPoints.last.dx, pathPoints.last.dy);
      _cachedPath!.close();
    } else if (pathPoints.length >= 3) {
      _cachedPath!.addPath(smoothPathFromPolygon(pathPoints), Offset.zero);
    } else {
      _cachedPath!.moveTo(pathPoints[0].dx, pathPoints[0].dy);
      for (int i = 1; i < pathPoints.length; i++) {
        _cachedPath!.lineTo(pathPoints[i].dx, pathPoints[i].dy);
      }
      _cachedPath!.close();
    }

    if (toolId == ToolId.calligraphyPen || toolId == ToolId.advancedPen) {
      _cachedPath!.fillType = PathFillType.nonZero;
    }

    _cachedPathValid = true;
    return _cachedPath!;
  }

  void shift(Offset offset) {
    if (offset == Offset.zero) return;

    points.shift(offset);
    _packedPoints = null;
    _lowQualityPolygon?.shift(offset);
    _highQualityPolygon?.shift(offset);
    _lowQualityPath = _lowQualityPath?.shift(offset);

    _cachedPath = _cachedPath?.shift(offset);

    if (_cachedBounds != null) {
      _cachedBounds = _cachedBounds!.shift(offset);
    }

    _cachedVertices = null;
  }

  void rotate(double angleRad, Offset center) {
    if (angleRad == 0.0) return;

    final cos = math.cos(angleRad);
    final sin = math.sin(angleRad);

    for (int i = 0; i < points.length; i++) {
      final point = points[i];
      final dx = point.x - center.dx;
      final dy = point.y - center.dy;
      final newX = center.dx + dx * cos - dy * sin;
      final newY = center.dy + dx * sin + dy * cos;
      points[i] = PointVector(newX, newY, point.pressure);
    }
    _packedPoints = null;

    void rotatePolygon(List<Offset>? polygon) {
      if (polygon == null) return;
      for (int i = 0; i < polygon.length; i++) {
        final p = polygon[i];
        final dx = p.dx - center.dx;
        final dy = p.dy - center.dy;
        polygon[i] = Offset(
          center.dx + dx * cos - dy * sin,
          center.dy + dx * sin + dy * cos,
        );
      }
    }

    rotatePolygon(_lowQualityPolygon);
    rotatePolygon(_highQualityPolygon);

    rotationDeg = (rotationDeg + angleRad * 180.0 / math.pi) % 360.0;

    _lowQualityPath = null;
    _cachedPath = null;
    _cachedPathValid = false;
    _cachedVertices = null;
    _invalidateSpatialData();
  }

  void markPolygonNeedsUpdating({bool preserveBounds = false}) {
    _lowQualityPolygon = null;
    _highQualityPolygon = null;
    _lowQualityPath = null;
    _cachedPathValid = false;
    _cachedVertices = null;
    _cachedVerticesHash = null;
    _packedPoints = null;
    if (!preserveBounds) _invalidateSpatialData();
  }

  void scale(double factor, Offset center) {
    if (factor == 1.0) return;
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final dx = p.x - center.dx;
      final dy = p.y - center.dy;
      points[i] = PointVector(
        center.dx + dx * factor,
        center.dy + dy * factor,
        p.pressure,
      );
    }
    markPolygonNeedsUpdating();
  }

  bool contains(Offset position) {
    if (isEmpty) return false;

    final double tolerance = math.max(10, options.size);
    if (!bounds.inflate(tolerance).contains(position)) return false;

    final double toleranceSq = tolerance * tolerance;
    for (final p in points) {
      final double dx = p.x - position.dx;
      final double dy = p.y - position.dy;
      if ((dx * dx + dy * dy) < toleranceSq) return true;
    }
    return false;
  }

  bool isHitByCircle(Offset center, double radius) {
    if (isEmpty) return false;

    final effectiveRadius = radius + (options.size / 2);
    final hitRect = Rect.fromCircle(center: center, radius: effectiveRadius);
    if (!bounds.inflate(options.size / 2).overlaps(hitRect)) return false;

    final points = this.points;
    if (points.length < 2) {
      if (points.length == 1) {
        final p = points.first;
        final dx = p.x - center.dx;
        final dy = p.y - center.dy;
        return (dx * dx + dy * dy) <= (effectiveRadius * effectiveRadius);
      }
      return false;
    }

    final effectiveRadiusSq = effectiveRadius * effectiveRadius;
    final eraserLeft = center.dx - effectiveRadius;
    final eraserRight = center.dx + effectiveRadius;
    final eraserTop = center.dy - effectiveRadius;
    final eraserBottom = center.dy + effectiveRadius;

    final int stride = points.length <= 8 ? 1 : 5;
    final double looseRadiusSq = (effectiveRadius * 4) * (effectiveRadius * 4);
    bool possibleHit = false;
    for (int i = 0; i < points.length; i += stride) {
      final p = points[i];
      final dx = p.x - center.dx;
      final dy = p.y - center.dy;
      if (dx * dx + dy * dy <= looseRadiusSq) {
        possibleHit = true;
        break;
      }
    }
    if (!possibleHit) return false;

    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      final minX = math.min(p1.x, p2.x);
      final maxX = math.max(p1.x, p2.x);
      if (minX > eraserRight || maxX < eraserLeft) continue;
      final minY = math.min(p1.y, p2.y);
      final maxY = math.max(p1.y, p2.y);
      if (minY > eraserBottom || maxY < eraserTop) continue;

      if (_distToSegmentSq(center, Offset(p1.x, p1.y), Offset(p2.x, p2.y)) <=
          effectiveRadiusSq) {
        return true;
      }
    }
    return false;
  }

  static double _distToSegmentSq(Offset p, Offset v, Offset w) {
    final l2 = (v - w).distanceSquared;
    if (l2 == 0) return (p - v).distanceSquared;
    final t =
        ((p.dx - v.dx) * (w.dx - v.dx) + (p.dy - v.dy) * (w.dy - v.dy)) / l2;
    final tClamped = t.clamp(0.0, 1.0);
    final proj = Offset(
      v.dx + tClamped * (w.dx - v.dx),
      v.dy + tClamped * (w.dy - v.dy),
    );
    return (p - proj).distanceSquared;
  }

  Stroke({
    required this.color,
    required this.pressureEnabled,
    required this.options,
    required this.pageIndex,
    required this.page,
    required this.toolId,
  }) {
    resetStabilization();
  }

  factory Stroke.fromJson(
    Map<String, dynamic> json, {
    required int fileVersion,
    required int pageIndex,
    required HasSize page,
  }) {
    assert(json['i'] == pageIndex || json['i'] == null);

    if (json['type'] == 'ShapeStroke') {
      return ShapeStroke.fromJson(
        json,
        fileVersion: fileVersion,
        pageIndex: pageIndex,
        page: page,
      );
    }

    switch (json['shape'] as String?) {
      case null:
        break;
      case 'circle':
        return CircleStroke.fromJson(
          json,
          fileVersion: fileVersion,
          pageIndex: pageIndex,
          page: page,
        );
      case 'rect':
        return RectangleStroke.fromJson(
          json,
          fileVersion: fileVersion,
          pageIndex: pageIndex,
          page: page,
        );
      case 'shapeCustom':
        return ShapeStroke.fromJson(
          json,
          fileVersion: fileVersion,
          pageIndex: pageIndex,
          page: page,
        );
      default:
        log.severe("Unknown shape: ${json['shape']}");
    }

    final ToolId toolId = ToolId.parsePenType(
      json['ty'],
      fallback: ToolId.fountainPen,
    );
    final options = StrokeOptions.fromJson(json);
    final bool flatEdge = json['fe'] ?? !options.start.cap;
    final pressureEnabled = json['pe'] ?? defaultPressureEnabled;

    if (toolId == ToolId.shapePen) {
      options.smoothing = 0;
      options.streamline = 0;
    }

    final Color color;
    switch (json['c']) {
      case (final int value):
        color = Color(value);
      case (final Int64 value):
        color = Color(value.toInt());
      case null:
        color = defaultColor;
      default:
        throw Exception(
          "Invalid color value: (${json['c'].runtimeType}) ${json['c']}",
        );
    }

    final offset = Offset(
      toDoubleSafe(json['ox']) ?? 0,
      toDoubleSafe(json['oy']) ?? 0,
    );
    final pointsJson = json['p'] as List<dynamic>;
    final Iterable<PointVector> points;
    if (fileVersion >= 13) {
      points = pointsJson.map(
        (point) => PointExtensions.fromBsonBinary(json: point, offset: offset),
      );
    } else {
      points = pointsJson.map(
        (point) => PointExtensions.fromJson(
          json: Map<String, dynamic>.from(point),
          offset: offset,
        ),
      );
    }

    return Stroke(
        color: color,
        pressureEnabled: pressureEnabled,
        options: options,
        pageIndex: pageIndex,
        page: page,
        toolId: toolId,
      )
      ..points.addAll(
        points.where(
          (point) =>
              point.x.isFinite &&
              point.y.isFinite &&
              (point.pressure == null || point.pressure!.isFinite),
        ),
      )
      ..rotationDeg = toDoubleSafe(json['rot']) ?? 0
      ..flatEdge = flatEdge;
  }
  Map<String, dynamic> toJson() {
    if (toolId == ToolId.highlighter) {
      options.start.cap = !flatEdge;
      options.end.cap = !flatEdge;
    }

    return {
      'shape': null,
      'p': points
          .where((point) => point.isFinite)
          .map((PointVector point) => point.toBsonBinary())
          .toList(),
      'i': pageIndex,
      'ty': toolId.id,
      'fe': flatEdge,
      'pe': pressureEnabled,
      'c': color.toARGB32(),
      'rot': rotationDeg,
    }..addAll(options.toJson());
  }

  void toBinary(BinaryWriter writer) {
    if (toolId == ToolId.highlighter) {
      options.start.cap = !flatEdge;
      options.end.cap = !flatEdge;
    }

    final finitePoints = points
        .where(
          (point) =>
              point.x.isFinite &&
              point.y.isFinite &&
              (!pressureEnabled ||
                  point.pressure == null ||
                  point.pressure!.isFinite),
        )
        .toList(growable: false);

    writer.writeString(StrokeBinaryKeys.shape, '');
    writer.writeInt(StrokeBinaryKeys.pointCount, finitePoints.length);
    writer.writeBool(StrokeBinaryKeys.pressureEnabled, pressureEnabled);
    for (final point in finitePoints) {
      writer.writeScaledFloatNoKey(point.x);
      writer.writeScaledFloatNoKey(point.y);
      if (pressureEnabled) {
        writer.writeScaledFloatNoKey(point.pressure ?? 0.5);
      }
    }

    writer.writeInt(StrokeBinaryKeys.pageIndex, pageIndex);
    writer.writeString(StrokeBinaryKeys.penType, penType);
    writer.writeInt(StrokeBinaryKeys.color, color.toARGB32());

    BinaryOptions().optionsToBinary(writer, options);
  }

  factory Stroke.fromBinary(
    BinaryReader reader, {
    int offset = 0,
    required int fileVersion,
    required HasSize page,
  }) {
    int key;
    final int pointCount;

    key = reader.readKey();
    if (key != StrokeBinaryKeys.shape) {
      throw Exception('StrokefromBinary no shape');
    }
    final shape = reader.readStringNoKey();
    switch (shape) {
      case '':
        break;
      case 'circle':
        return CircleStroke.fromBinary(reader, page: page);
      case 'rect':
        return RectangleStroke.fromBinary(reader, page: page);
      case 'shapeCustom':
        return ShapeStroke.fromBinary(reader, page: page);
      default:
        log.severe('StrokeFromBinary Unknown shape: $shape');
    }

    key = reader.readKey();
    if (key != StrokeBinaryKeys.pointCount) {
      throw Exception('StrokefromBinary no pointCount');
    }
    pointCount = reader.readIntNoKey();

    final bool pressureEnabled;
    key = reader.readKey();
    if (key != StrokeBinaryKeys.pressureEnabled) {
      throw Exception('StrokefromBinary no pressureEnabled');
    }
    pressureEnabled = reader.readBoolNoKey();
    final points = <PointVector>[];
    for (int i = 0; i < pointCount; i++) {
      double x = reader.readScaledFloat();
      double y = reader.readScaledFloat();
      if (pressureEnabled) {
        double pressure = reader.readScaledFloat();
        points.add(PointVector(x, y, pressure));
      } else {
        points.add(PointVector(x, y));
      }
    }

    final int pageIndex;
    key = reader.readKey();
    if (key != StrokeBinaryKeys.pageIndex) {
      throw Exception('StrokefromBinary no pageIndex');
    }
    pageIndex = reader.readIntNoKey();

    final String penType;
    key = reader.readKey();
    if (key != StrokeBinaryKeys.penType) {
      throw Exception('StrokefromBinary no penType');
    }
    penType = reader.readStringNoKey();

    final Color color;
    key = reader.readKey();
    if (key != StrokeBinaryKeys.color) {
      throw Exception('StrokefromBinary no color');
    }
    color = reader.readColor();

    key = reader.readKey();
    if (key == StrokeBinaryKeys.pencilTextureIndex) {
      reader.readIntNoKey();
      key = reader.readKey();
    }
    final options = BinaryOptions().optionsFromBinary(reader, initialKey: key);

    return Stroke(
        color: color,
        pressureEnabled: pressureEnabled,
        options: options,
        pageIndex: pageIndex,
        page: page,
        toolId: ToolId.parsePenType(penType, fallback: ToolId.fountainPen),
      )
      ..flatEdge = !options.start.cap
      ..points.addAll(
        points.where(
          (point) =>
              point.x.isFinite &&
              point.y.isFinite &&
              (point.pressure == null || point.pressure!.isFinite),
        ),
      );
  }

  /// When pointer steps are far apart (fast motion), insert points along the chord
  /// so stroke meshes stay smooth instead of faceted.
  static const double _interpolateThresholdPx = 1.75;

  static const double _interpolateStepPx = 0.88;

  static const int _maxInterpolateSegments = 96;

  double? _drawSampleTimeSec;
  double? _prevDrawSampleTimeSec;

  Offset? _predictionTip;
  double? _predictionPressure;

  /// Raw pointer kinematics for live stroke prediction (not affected by stabilization).
  Offset? _predPrevRawPos;
  double? _predPrevRawTimeSec;
  Offset? _predEmaVelocity;
  Offset? _predInstantVelPrev;
  Offset? _predInstantVelLast;

  void addPoint(Offset point, [double? pressure, Duration? timestamp]) {
    if (!pressureEnabled) {
      pressure = null;
    } else if (pressure != null) {
      options.simulatePressure = false;
    }

    final stabilizedPoint = _applyStabilization(point, timestamp);

    final double eventTimeSec = timestamp != null
        ? timestamp.inMicroseconds / 1e6
        : (_drawSampleTimeSec ?? 0.0) + 1.0 / 60.0;

    _updateRawPredictionKinematics(point, eventTimeSec);

    if (toolId == ToolId.highlighter && Highlighter.straightLine.value) {
      if (points.isEmpty) {
        _commitStabilizedSample(stabilizedPoint, pressure, eventTimeSec);
      } else {
        final first = points.first;
        final current = PointVector(
          stabilizedPoint.dx,
          stabilizedPoint.dy,
          pressure,
        );
        final snapped = snapLine(first, current);
        points.clear();
        _packedPoints = null;
        _commitStabilizedSample(Offset(first.x, first.y), first.pressure, eventTimeSec);
        _commitStabilizedSample(Offset(snapped.$2.x, snapped.$2.y), snapped.$2.pressure, eventTimeSec);
      }
    } else if (points.isEmpty) {
      _commitStabilizedSample(stabilizedPoint, pressure, eventTimeSec);
    } else {
      final last = points.last;
      final ox = last.x;
      final oy = last.y;
      final dx = stabilizedPoint.dx - ox;
      final dy = stabilizedPoint.dy - oy;
      final dist = math.sqrt(dx * dx + dy * dy);
      final double tPrev = _drawSampleTimeSec!;

      int steps = 1;
      if (dist > _interpolateThresholdPx) {
        steps = math.min(
          _maxInterpolateSegments,
          math.max(2, (dist / _interpolateStepPx).ceil()),
        );
      }

      for (int s = 1; s <= steps; s++) {
        final frac = s / steps;
        final sx = ox + dx * frac;
        final sy = oy + dy * frac;
        double? pr;
        if (!pressureEnabled) {
          pr = null;
        } else {
          final lp = last.pressure ?? 0.5;
          final np = pressure ?? lp;
          pr = lp + (np - lp) * frac;
        }
        final t = tPrev + (eventTimeSec - tPrev) * frac;
        final isLast = s == steps;
        _commitStabilizedSample(
          Offset(sx, sy),
          pr,
          t,
          recomputePrediction: isLast,
        );
      }
    }
  }

  void _commitStabilizedSample(
    Offset stabilizedPoint,
    double? pressure,
    double timeSec, {
    bool recomputePrediction = true,
  }) {
    _prevDrawSampleTimeSec = _drawSampleTimeSec;
    _drawSampleTimeSec = timeSec;

    points.add(PointVector(stabilizedPoint.dx, stabilizedPoint.dy, pressure));
    _packedPoints = null;
    _cachedAveragePressure = null;

    final double r = options.size / 2;
    final double x = stabilizedPoint.dx;
    final double y = stabilizedPoint.dy;
    if (_cachedBounds != null) {
      _cachedBounds = Rect.fromLTRB(
        math.min(_cachedBounds!.left, x - r),
        math.min(_cachedBounds!.top, y - r),
        math.max(_cachedBounds!.right, x + r),
        math.max(_cachedBounds!.bottom, y + r),
      );
    }

    if (recomputePrediction) {
      _recomputePredictionTip();
      if (_predictionTip != null && _cachedBounds != null) {
        final px = _predictionTip!.dx;
        final py = _predictionTip!.dy;
        _cachedBounds = Rect.fromLTRB(
          math.min(_cachedBounds!.left, px - r),
          math.min(_cachedBounds!.top, py - r),
          math.max(_cachedBounds!.right, px + r),
          math.max(_cachedBounds!.bottom, py + r),
        );
      }
    }

    markPolygonNeedsUpdating(preserveBounds: true);
  }

  void _updateRawPredictionKinematics(Offset rawPosition, double timeSec) {
    if (_predPrevRawPos != null && _predPrevRawTimeSec != null) {
      final dt = (timeSec - _predPrevRawTimeSec!).clamp(1e-4, 0.25);
      final ix = (rawPosition.dx - _predPrevRawPos!.dx) / dt;
      final iy = (rawPosition.dy - _predPrevRawPos!.dy) / dt;
      final instant = Offset(ix, iy);
      final beta = dt < 0.011 ? 0.68 : 0.56;
      _predEmaVelocity = _predEmaVelocity == null
          ? instant
          : Offset(
              _predEmaVelocity!.dx * (1 - beta) + instant.dx * beta,
              _predEmaVelocity!.dy * (1 - beta) + instant.dy * beta,
            );
      _predInstantVelPrev = _predInstantVelLast;
      _predInstantVelLast = instant;
    }
    _predPrevRawPos = rawPosition;
    _predPrevRawTimeSec = timeSec;
  }

  Offset? _filteredPoint;
  Offset? _filteredVelocity;
  double? _lastTimestampSeconds;

  double _alpha(double cutoff, double dt) {
    final tau = 1.0 / (2 * math.pi * cutoff);
    return 1.0 / (1.0 + tau / dt);
  }

  Offset _lowPass(Offset current, Offset? prev, double alpha) {
    if (prev == null) return current;
    return Offset(
      prev.dx + alpha * (current.dx - prev.dx),
      prev.dy + alpha * (current.dy - prev.dy),
    );
  }

  Offset _applyStabilization(Offset point, Duration? timestamp) {
    if (!stows.strokeStabilization.value ||
        stows.strokeStabilizationAmount.value <= 0) {
      return point;
    }

    final amount = stows.strokeStabilizationAmount.value;

    final minCutoff = 10.0 * math.pow(0.05, amount);
    final beta = 0.1 * math.pow(0.01, amount);
    const dCutoff = 1.0;

    final double now =
        timestamp?.inMicroseconds.toDouble() ??
        (_lastTimestampSeconds == null
            ? 0.0
            : _lastTimestampSeconds! + 16666.0);
    final double nowSeconds = now / 1000000.0;

    if (_lastTimestampSeconds == null) {
      _lastTimestampSeconds = nowSeconds;
      _filteredPoint = point;
      _filteredVelocity = Offset.zero;
      return point;
    }

    final dt = (nowSeconds - _lastTimestampSeconds!).clamp(0.001, 0.1);
    _lastTimestampSeconds = nowSeconds;

    final velocity = (point - _filteredPoint!) / dt;
    final alphaD = _alpha(dCutoff, dt);
    _filteredVelocity = _lowPass(velocity, _filteredVelocity, alphaD);
    final speed = _filteredVelocity!.distance;

    final cutoff = minCutoff + beta * speed;
    final alphaPos = _alpha(cutoff, dt);

    _filteredPoint = _lowPass(point, _filteredPoint, alphaPos);

    return _filteredPoint!;
  }

  void resetStabilization() {
    _filteredPoint = null;
    _filteredVelocity = null;
    _lastTimestampSeconds = null;
    _drawSampleTimeSec = null;
    _prevDrawSampleTimeSec = null;
    _predictionTip = null;
    _predictionPressure = null;
    _predPrevRawPos = null;
    _predPrevRawTimeSec = null;
    _predEmaVelocity = null;
    _predInstantVelPrev = null;
    _predInstantVelLast = null;
  }

  void clearLivePrediction() {
    _predictionTip = null;
    _predictionPressure = null;
  }

  void _recomputePredictionTip() {
    _predictionTip = null;
    _predictionPressure = null;
    if (options.isComplete || !stows.strokePrediction.value) return;
    if (toolId == ToolId.highlighter && Highlighter.straightLine.value) return;
    if (points.length < 2) return;

    Offset v;
    if (_predEmaVelocity != null && _predEmaVelocity!.distance > 1e-3) {
      v = _predEmaVelocity!;
    } else if (_drawSampleTimeSec != null && _prevDrawSampleTimeSec != null) {
      final dt = (_drawSampleTimeSec! - _prevDrawSampleTimeSec!).clamp(
        1.2e-3,
        0.12,
      );
      final prev = points[points.length - 2];
      final last = points.last;
      v = Offset((last.x - prev.x) / dt, (last.y - prev.y) / dt);
    } else {
      return;
    }

    if (stows.strokeStabilization.value &&
        _filteredVelocity != null &&
        _filteredVelocity!.distance > 18) {
      final f = _filteredVelocity!;
      v = Offset(v.dx * 0.52 + f.dx * 0.48, v.dy * 0.52 + f.dy * 0.48);
    }

    final speed = v.distance;
    if (speed < 2.5) return;

    final amount = stows.strokePredictionAmount.value.clamp(0.0, 1.0);

    var turnFactor = 1.0;
    if (_predInstantVelPrev != null && _predInstantVelLast != null) {
      final a = _predInstantVelPrev!;
      final b = _predInstantVelLast!;
      final la = a.distance;
      final lb = b.distance;
      if (la > 2.0 && lb > 2.0) {
        final cos = (a.dx * b.dx + a.dy * b.dy) / (la * lb);
        turnFactor = (0.22 + 0.78 * ((cos + 1) * 0.5)).clamp(0.18, 1.0);
      }
    } else if (points.length >= 3) {
      final p0 = points[points.length - 3];
      final prev = points[points.length - 2];
      final last = points.last;
      final v0dx = prev.x - p0.x;
      final v0dy = prev.y - p0.y;
      final v1dx = last.x - prev.x;
      final v1dy = last.y - prev.y;
      final len0 = math.sqrt(v0dx * v0dx + v0dy * v0dy);
      final len1 = math.sqrt(v1dx * v1dx + v1dy * v1dy);
      if (len0 > 1e-4 && len1 > 1e-4) {
        final cos = (v0dx * v1dx + v0dy * v1dy) / (len0 * len1);
        if (cos < 0.2) {
          turnFactor = 0.26;
        } else if (cos < 0.5) {
          turnFactor = 0.5;
        } else if (cos < 0.72) {
          turnFactor = 0.76;
        }
      }
    }

    final speedNorm = (speed / (speed + 88.0)).clamp(0.0, 1.0);
    final lookaheadSec =
        (0.009 + 0.056 * amount) * turnFactor * speedNorm;

    var dx = v.dx * lookaheadSec;
    var dy = v.dy * lookaheadSec;
    var dist = math.sqrt(dx * dx + dy * dy);
    final maxDist = (options.size * (2.3 + 3.4 * amount)).clamp(6.0, 54.0);
    if (dist > maxDist && dist > 0) {
      final s = maxDist / dist;
      dx *= s;
      dy *= s;
      dist = maxDist;
    }
    if (dist < 0.28) return;

    final last = points.last;
    _predictionTip = Offset(last.x + dx, last.y + dy);
    _predictionPressure = last.pressure;
  }

  List<PointVector> _pointsForLiveRender(List<PointVector> source) {
    if (options.isComplete ||
        !stows.strokePrediction.value ||
        _predictionTip == null) {
      return source;
    }
    if (toolId == ToolId.highlighter && Highlighter.straightLine.value) {
      return source;
    }
    if (source.isEmpty) return source;

    final p = _predictionPressure ?? source.last.pressure;
    return [...source, PointVector(_predictionTip!.dx, _predictionTip!.dy, p)];
  }

  void addPoints(List<Offset> points) {
    for (final point in points) {
      addPoint(point);
    }
  }

  void popFirstPoint() {
    points.removeAt(0);
    _cachedAveragePressure = null;
    markPolygonNeedsUpdating();
  }

  static const _optimisePointsThreshold = 0.1;

  void optimisePoints({double thresholdMultiplier = _optimisePointsThreshold}) {
    if (points.length <= 3) return;

    final minDistance = options.size * thresholdMultiplier;

    points.removeWhere((point) => point.pressure == null);

    for (int i = 1; i < points.length - 1; i++) {
      final point = points[i];
      final prev = points[i - 1];
      final next = points[i + 1];

      if (prev.distanceSquaredTo(point) < minDistance * minDistance &&
          point.distanceSquaredTo(next) < minDistance * minDistance) {
        points.removeAt(i);
        i--;
      }
    }
    _packedPoints = null;
  }

  @protected
  List<Offset> getPolygon({required StrokeQuality quality}) {
    if (!pressureEnabled) {
      options.simulatePressure = false;
    }

    // 1. Get points WITH the prediction tip appended FIRST
    final List<PointVector> basePoints = _pointsForLiveRender(points);

    // 2. Create a temporary packed array including the prediction tip
    Float32List? packedBase;
    if (basePoints.length >= 2) {
      packedBase = Float32List(basePoints.length * 3);
      for (int i = 0; i < basePoints.length; i++) {
        packedBase[i * 3] = basePoints[i].x;
        packedBase[i * 3 + 1] = basePoints[i].y;
        packedBase[i * 3 + 2] = basePoints[i].pressure ?? 0.5;
      }
    }

    final List<PointVector> sourcePoints;
    if (toolId == ToolId.highlighter) {
      if (basePoints.length >= 3) {
        sourcePoints = _getSmoothSpine(basePoints);
      } else {
        sourcePoints = basePoints;
      }
    } else if (toolId == ToolId.advancedPen) {
      if (quality == StrokeQuality.high && basePoints.length >= 3) {
        sourcePoints = _getSmoothSpine(basePoints);
      } else {
        sourcePoints = quality == StrokeQuality.high
            ? basePoints
            : skipPoints(basePoints, quality.N);
      }
    } else if (toolId == ToolId.calligraphyPen ||
        toolId == ToolId.fountainPen ||
        toolId == ToolId.ballpointPen) {
      if (basePoints.length >= 3 && packedBase != null) {
        final scale = _targetScale.clamp(0.1, 5.0);
        final toleranceSq = (0.12 / scale) * (0.12 / scale);
        final smooth = _getAdaptiveSpineFast(packedBase, toleranceSq);
        final n = smooth.length ~/ 3;
        sourcePoints = List.generate(
          n,
          (i) =>
              PointVector(smooth[i * 3], smooth[i * 3 + 1], smooth[i * 3 + 2]),
        );
      } else {
        sourcePoints = basePoints;
      }
    } else {
      if (quality == StrokeQuality.high &&
          basePoints.length >= 3 &&
          packedBase != null) {
        final scale = _targetScale.clamp(0.1, 5.0);
        final toleranceSq = (0.14 / scale) * (0.14 / scale);
        final smooth = _getAdaptiveSpineFast(packedBase, toleranceSq);
        final n = smooth.length ~/ 3;
        sourcePoints = List.generate(
          n,
          (i) =>
              PointVector(smooth[i * 3], smooth[i * 3 + 1], smooth[i * 3 + 2]),
        );
      } else {
        sourcePoints = quality == StrokeQuality.high
            ? basePoints
            : _ramerDouglasPeucker(basePoints, epsilon: 0.05 * options.size);
      }
    }

    // 3. Render the specific tool using our splined sourcePoints
    if (toolId == ToolId.calligraphyPen) {
      var strokePoints = sourcePoints;
      if (strokePoints.length == 1)
        strokePoints = [strokePoints.first, strokePoints.first];
      if (strokePoints.length < 2) return [];
      return _getCalligraphyPolygon(strokePoints, quality: quality);
    }

    if (toolId == ToolId.fountainPen) {
      var strokePoints = sourcePoints;
      if (strokePoints.length == 1)
        strokePoints = [strokePoints.first, strokePoints.first];
      return getStroke(
        strokePoints,
        options: options.copyWith(
          thinning: 0.35,
          smoothing: 0.95,
          streamline: 0.88,
          simulatePressure: true,
          start: StrokeEndOptions.start(
            taperEnabled: true,
            customTaper: 12,
            cap: false,
          ),
          end: StrokeEndOptions.end(
            taperEnabled: true,
            customTaper: 12,
            cap: false,
          ),
        ),
        rememberSimulatedPressure: false,
      );
    }

    if (toolId == ToolId.highlighter) {
      final isStraight = sourcePoints.length <= 3;
      final highlighterOptions = options.copyWith(
        thinning: 0,
        simulatePressure: false,
        smoothing: isStraight ? 0.0 : 0.8,
        streamline: isStraight ? 0.0 : 0.6,
        start: StrokeEndOptions.start(cap: !flatEdge),
        end: StrokeEndOptions.end(cap: !flatEdge),
      );
      var strokePoints = sourcePoints;
      if (strokePoints.length == 1)
        strokePoints = [strokePoints.first, strokePoints.first];
      return getStroke(strokePoints, options: highlighterOptions);
    }

    if (toolId == ToolId.ballpointPen) {
      final ballpointOptions = options.copyWith(
        thinning: 0,
        simulatePressure: false,
        smoothing: 0.52,
        streamline: 0.32,
        start: StrokeEndOptions.start(
          taperEnabled: false,
          cap: true,
          easing: StrokeOptions.defaultEasing,
        ),
        end: StrokeEndOptions.end(
          taperEnabled: false,
          cap: true,
          easing: StrokeOptions.defaultEasing,
        ),
      );
      var strokePoints = sourcePoints;
      if (strokePoints.length == 1)
        strokePoints = [strokePoints.first, strokePoints.first];
      return getStroke(strokePoints, options: ballpointOptions);
    }

    final useFullOptions =
        quality == StrokeQuality.high || toolId != ToolId.advancedPen;
    StrokeOptions effectiveOptions = useFullOptions
        ? options
        : options.copyWith(
            simulatePressure: false,
            smoothing: 0.35,
            streamline: 0.15,
          );

    return getStroke(
      sourcePoints,
      options: effectiveOptions,
      rememberSimulatedPressure: false,
    );
  }

  List<Offset> _getCalligraphyPolygon(
    List<PointVector> strokePoints, {
    required StrokeQuality quality,
  }) {
    final int len = strokePoints.length;
    if (len < 2) return [];

    const double nibAngle = -40 * math.pi / 180;
    final double size = options.size;

    final double cosTheta = math.cos(nibAngle);
    final double sinTheta = math.sin(nibAngle);

    final double minDistSq = math.max(400.0, (size * 2.0) * (size * 2.0));

    final List<Offset> leftSide = List<Offset>.filled(len, Offset.zero);
    final List<Offset> rightSide = List<Offset>.filled(len, Offset.zero);

    double prevVx = 0.0;
    double prevVy = 0.0;
    double startDirX = 0.0;
    double startDirY = 0.0;
    double endDirX = 0.0;
    double endDirY = 0.0;

    for (int i = 0; i < len; i++) {
      final p = strokePoints[i];
      final double px = p.x;
      final double py = p.y;

      final double pressure = (p.pressure ?? 0.5).clamp(0.0, 1.0);
      double pressureScale = 0.5 + pressure * 0.5;

      double tanDx = 0.0;
      double tanDy = 0.0;
      if (i == 0) {
        for (int step = 1; step < len; step++) {
          tanDx = strokePoints[step].x - px;
          tanDy = strokePoints[step].y - py;
          if (tanDx * tanDx + tanDy * tanDy > minDistSq) break;
        }
        if (tanDx == 0 && tanDy == 0 && len > 1) {
          tanDx = strokePoints[1].x - px;
          tanDy = strokePoints[1].y - py;
        }
        startDirX = tanDx;
        startDirY = tanDy;
      } else if (i == len - 1) {
        for (int step = 1; step < len; step++) {
          tanDx = px - strokePoints[len - 1 - step].x;
          tanDy = py - strokePoints[len - 1 - step].y;
          if (tanDx * tanDx + tanDy * tanDy > minDistSq) break;
        }
        if (tanDx == 0 && tanDy == 0 && len > 1) {
          tanDx = px - strokePoints[len - 2].x;
          tanDy = py - strokePoints[len - 2].y;
        }
        endDirX = tanDx;
        endDirY = tanDy;
      } else {
        double pPrevX = strokePoints[i - 1].x;
        double pPrevY = strokePoints[i - 1].y;
        for (int step = 1; step <= i; step++) {
          pPrevX = strokePoints[i - step].x;
          pPrevY = strokePoints[i - step].y;
          if ((px - pPrevX) * (px - pPrevX) + (py - pPrevY) * (py - pPrevY) >
              minDistSq)
            break;
        }
        double pNextX = strokePoints[i + 1].x;
        double pNextY = strokePoints[i + 1].y;
        for (int step = 1; step < len - i; step++) {
          pNextX = strokePoints[i + step].x;
          pNextY = strokePoints[i + step].y;
          if ((pNextX - px) * (pNextX - px) + (pNextY - py) * (pNextY - py) >
              minDistSq)
            break;
        }
        tanDx = pNextX - pPrevX;
        tanDy = pNextY - pPrevY;
      }

      double distSq = tanDx * tanDx + tanDy * tanDy;
      if (distSq < 0.000001) {
        tanDx = 1.0;
        tanDy = 0.0;
        distSq = 1.0;
      }
      final double invLen = 1.0 / math.sqrt(distSq);
      double nxNorm = -tanDy * invLen;
      double nyNorm = tanDx * invLen;

      final double rx = size * 0.65 * pressureScale;
      final double ry = size * 0.12 * pressureScale;
      final double rx2 = rx * rx;
      final double ry2 = ry * ry;

      final double localNx = nxNorm * cosTheta + nyNorm * sinTheta;
      final double localNy = -nxNorm * sinTheta + nyNorm * cosTheta;

      final double scale =
          1.0 / math.sqrt(rx2 * localNx * localNx + ry2 * localNy * localNy);
      final double localVx = rx2 * localNx * scale;
      final double localVy = ry2 * localNy * scale;

      double vx = localVx * cosTheta - localVy * sinTheta;
      double vy = localVx * sinTheta + localVy * cosTheta;

      if (i > 0 && (vx * prevVx + vy * prevVy) < 0) {
        vx = -vx;
        vy = -vy;
      }
      prevVx = vx;
      prevVy = vy;

      leftSide[i] = Offset(px - vx, py - vy);
      rightSide[i] = Offset(px + vx, py + vy);
    }

    if (len >= 3) {
      for (int pass = 0; pass < 2; pass++) {
        final prevL = List<Offset>.from(leftSide);
        final prevR = List<Offset>.from(rightSide);
        for (int i = 1; i < len - 1; i++) {
          leftSide[i] = Offset(
            prevL[i - 1].dx * 0.25 + prevL[i].dx * 0.5 + prevL[i + 1].dx * 0.25,
            prevL[i - 1].dy * 0.25 + prevL[i].dy * 0.5 + prevL[i + 1].dy * 0.25,
          );
          rightSide[i] = Offset(
            prevR[i - 1].dx * 0.25 + prevR[i].dx * 0.5 + prevR[i + 1].dx * 0.25,
            prevR[i - 1].dy * 0.25 + prevR[i].dy * 0.5 + prevR[i + 1].dy * 0.25,
          );
        }
      }
    }

    const int ellipseSegments = 6;
    final List<Offset> result = [];

    void addEllipticalCap(
      double cx,
      double cy,
      double dirX,
      double dirY,
      double rxVal,
      double ryVal,
      bool towardStroke,
    ) {
      final dist = math.sqrt(dirX * dirX + dirY * dirY);
      if (dist < 0.001) return;
      final tx = dirX / dist;
      final ty = dirY / dist;
      final nx = -ty;
      final ny = tx;

      final sign = towardStroke ? 1.0 : -1.0;
      for (int k = 0; k <= ellipseSegments; k++) {
        final angle = sign * (math.pi * (k / ellipseSegments) - math.pi / 2);
        final ex =
            cx + rxVal * tx * math.cos(angle) + ryVal * nx * math.sin(angle);
        final ey =
            cy + rxVal * ty * math.cos(angle) + ryVal * ny * math.sin(angle);
        result.add(Offset(ex, ey));
      }
    }

    if (len >= 2) {
      final p0 = strokePoints[0];
      final pressure0 = (p0.pressure ?? 0.5).clamp(0.0, 1.0);
      final r0 = size * 0.65 * (0.5 + pressure0 * 0.5);
      final r0y = size * 0.12 * (0.5 + pressure0 * 0.5);
      addEllipticalCap(p0.x, p0.y, startDirX, startDirY, r0, r0y, true);

      for (int i = 1; i < len; i++) result.add(rightSide[i]);

      final pLast = strokePoints[len - 1];
      final pressureN = (pLast.pressure ?? 0.5).clamp(0.0, 1.0);
      final rN = size * 0.65 * (0.5 + pressureN * 0.5);
      final rNy = size * 0.12 * (0.5 + pressureN * 0.5);
      addEllipticalCap(pLast.x, pLast.y, endDirX, endDirY, rN, rNy, false);

      for (int i = len - 2; i >= 0; i--) result.add(leftSide[i]);
    }

    return result;
  }

  List<Offset> _getHighlighterPolygonFromStamp() {
    if (points.length < 2) return [];
    final path = _buildHighlighterStampPathInternal();
    if (path == null) return [];
    final bounds = path.getBounds();
    if (bounds.isEmpty) return [];
    return [
      Offset(bounds.left, bounds.top),
      Offset(bounds.right, bounds.top),
      Offset(bounds.right, bounds.bottom),
      Offset(bounds.left, bounds.bottom),
    ];
  }

  Path? _buildHighlighterStampPathInternal({bool lowQuality = false}) {
    if (points.length < 2) return null;
    _ensurePackedPoints();
    if (_packedPoints == null || _packedPoints!.length < 6) return null;

    final scale = _targetScale.clamp(0.1, 5.0);
    final toleranceSq = (0.5 / scale) * (0.5 / scale);
    Float32List smooth = _getAdaptiveSpineFast(_packedPoints!, toleranceSq);
    final int n = smooth.length ~/ 3;
    if (n < 2) return null;

    final double r = (options.size / 2.0) * highlighterStrokeScaleFactor;

    final double step = lowQuality ? r * 0.4 : r * 0.2;

    final List<Offset> samples = [];
    double accLen = 0.0;
    double nextSampleAt = 0.0;

    for (int i = 0; i < n - 1; i++) {
      final double x0 = smooth[i * 3];
      final double y0 = smooth[i * 3 + 1];
      final double x1 = smooth[(i + 1) * 3];
      final double y1 = smooth[(i + 1) * 3 + 1];
      final double dx = x1 - x0;
      final double dy = y1 - y0;
      final double segLen = math.sqrt(dx * dx + dy * dy);
      if (segLen < 1e-9) continue;

      while (nextSampleAt <= accLen + segLen - 1e-9) {
        final double localT = (nextSampleAt - accLen) / segLen;
        samples.add(Offset(x0 + dx * localT, y0 + dy * localT));
        nextSampleAt += step;
      }
      accLen += segLen;
    }
    samples.add(Offset(smooth[(n - 1) * 3], smooth[(n - 1) * 3 + 1]));

    if (samples.isEmpty) return null;

    final path = Path();
    final double dirX0 = smooth[3] - smooth[0];
    final double dirY0 = smooth[4] - smooth[1];
    final double dirXn = smooth[(n - 1) * 3] - smooth[(n - 2) * 3];
    final double dirYn = smooth[(n - 1) * 3 + 1] - smooth[(n - 2) * 3 + 1];

    for (int i = 0; i < samples.length; i++) {
      final Offset p = samples[i];
      final double x = p.dx;
      final double y = p.dy;
      final bool atStart = i == 0;
      final bool atEnd = i == samples.length - 1;

      if (flatEdge && (atStart || atEnd)) {
        final double dirX = atStart ? dirX0 : dirXn;
        final double dirY = atStart ? dirY0 : dirYn;
        final double len = math.sqrt(dirX * dirX + dirY * dirY);
        if (len > 0.001) {
          final double nx = -dirY / len;
          final double ny = dirX / len;
          final double tx = dirX / len;
          final double ty = dirY / len;
          final double halfThick = r * 0.13;
          path.addRect(
            Rect.fromPoints(
              Offset(x - nx * r - tx * halfThick, y - ny * r - ty * halfThick),
              Offset(x + nx * r + tx * halfThick, y + ny * r + ty * halfThick),
            ),
          );
        } else {
          path.addOval(Rect.fromCircle(center: p, radius: r));
        }
      } else {
        path.addOval(Rect.fromCircle(center: p, radius: r));
      }
    }
    path.fillType = PathFillType.nonZero;
    return path;
  }

  @protected
  Path getPath(List<Offset> polygon, {bool smooth = true}) {
    if (toolId == ToolId.calligraphyPen && polygon.isNotEmpty) {
      if (smooth && options.isComplete) {
        return smoothPathFromPolygon(polygon)..fillType = PathFillType.nonZero;
      }
      return Path()
        ..fillType = PathFillType.nonZero
        ..addPolygon(polygon, true);
    }

    if (smooth && options.isComplete) {
      return smoothPathFromPolygon(polygon)..fillType = PathFillType.nonZero;
    }

    return Path()
      ..fillType = PathFillType.nonZero
      ..addPolygon(polygon, true);
  }

  static List<PointVector> skipPoints(List<PointVector> points, int N) {
    if (N <= 1) return points;

    final divided = points.length / N;
    const minDivided = 8;
    if (divided < minDivided) {
      N = (N * divided / minDivided).floor();
      if (N <= 1) return points;
    }

    return [
      for (int i = 0; i < points.length - 1; i += N) points[i],
      points.last,
    ];
  }

  static Path smoothPathFromPolygon(List<Offset> polygon) {
    if (polygon.length < 2) return Path();
    final path = Path();
    path.moveTo(polygon.first.dx, polygon.first.dy);
    if (polygon.length == 2) {
      path.lineTo(polygon.last.dx, polygon.last.dy);
      return path..close();
    }

    for (int i = 1; i < polygon.length; i++) {
      final p1 = polygon[i];
      final p2 = polygon[(i + 1) % polygon.length];
      final mid = (p1 + p2) / 2;
      path.quadraticBezierTo(p1.dx, p1.dy, mid.dx, mid.dy);
    }
    return path..close();
  }

  String toSvgPath() {
    String toSvgPoint(Offset point) {
      return '${point.dx} '
          '${page.size.height - point.dy}';
    }

    final svgPoints = highQualityPolygon
        .where((offset) => offset.isFinite)
        .map(toSvgPoint);

    return svgPoints.isNotEmpty ? 'M${svgPoints.join('L')}' : '';
  }

  double get maxY {
    return points.isEmpty ? 0 : points.map((point) => point.y).reduce(math.max);
  }

  RecognizedUnistroke? detectShape() {
    if (points.length < 2) return null;
    final centerline = points
        .map((p) => Offset(p.x, p.y))
        .toList(growable: false);

    if (centerline.length < 25 && isAngleBracketPreferred(centerline)) {
      final angleOnly = default$1Unistrokes
          .where(
            (u) =>
                u.name == DefaultUnistrokeNames.leftAngleBracket ||
                u.name == DefaultUnistrokeNames.rightAngleBracket,
          )
          .toList();
      if (angleOnly.isNotEmpty) {
        final angleResult = recognizeUnistroke(
          centerline,
          overrideReferenceUnistrokes: angleOnly,
        );
        if (angleResult != null && angleResult.score >= 0.5) {
          return angleResult;
        }
      }
    }
    return recognizeUnistroke(centerline);
  }

  bool isStraightLine([int minLength = 5]) {
    if (points.length < 3) return false;

    final sqrLength = points.first.distanceSquaredTo(points.last);
    final sqrMinLength = minLength * minLength * options.size * options.size;
    if (sqrLength < sqrMinLength) return false;

    final recognized = recognizeUnistroke(
      points,
      overrideReferenceUnistrokes: default$1Unistrokes
          .where((unistroke) => unistroke.name == DefaultUnistrokeNames.line)
          .toList(),
    );
    if (recognized == null) return false;
    assert(recognized.name == DefaultUnistrokeNames.line);
    return recognized.score >= 0.7;
  }

  void densifyStraightLine() {
    if (points.length < 2) return;
    final first = points.first;
    final last = points.last;
    final pressure = points.map((p) => p.pressure ?? 0.5).average;
    final dx = last.x - first.x;
    final dy = last.y - first.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) return;

    final stepPx = 8.0;
    final n = math.max(24, (len / stepPx).ceil() + 1).clamp(24, 512);

    final result = <PointVector>[];
    for (var i = 0; i <= n; i++) {
      final t = i / n;
      result.add(PointVector(first.x + t * dx, first.y + t * dy, pressure));
    }
    points.clear();
    points.addAll(result);
    _cachedBounds = null;
    _packedPoints = null;
    _cachedPath = null;
    _cachedPathValid = false;
    markPolygonNeedsUpdating();
  }

  void convertToLine() {
    assert(points.length >= 2);

    final offsets = points.map((p) => Offset(p.x, p.y)).toList();
    final (start, end) = fitLineAndProjectExtent(
      offsets,
      useChordDirection: true,
    );

    final pressure = points.map((point) => point.pressure ?? 0.5).average;
    var firstPoint = PointVector.fromOffset(offset: start, pressure: pressure);
    var lastPoint = PointVector.fromOffset(offset: end, pressure: pressure);

    (firstPoint, lastPoint) = snapLine(firstPoint, lastPoint);

    final midPoint = PointVector(
      (firstPoint.dx + lastPoint.dx) / 2,
      (firstPoint.dy + lastPoint.dy) / 2,
      pressure,
    );

    points.clear();
    points.add(firstPoint);
    points.add(midPoint);
    points.add(lastPoint);

    options.isComplete = true;
    options.start.taperEnabled = false;
    options.end.taperEnabled = false;

    _cachedBounds = null;
    _cachedVertices = null;
    _cachedPath = null;
    _cachedPathValid = false;
    markPolygonNeedsUpdating();
  }

  static (PointVector firstPoint, PointVector lastPoint) snapLine(
    PointVector firstPoint,
    PointVector lastPoint,
  ) {
    final dx = lastPoint.dx - firstPoint.dx;
    final dy = lastPoint.dy - firstPoint.dy;
    final angle = math.atan2(dy, dx);

    final snapAngle = 15 * math.pi / 180;
    final step = math.pi / 4;

    final closestStep = (angle / step).round() * step;
    if ((angle - closestStep).abs() < snapAngle) {
      final dist = math.sqrt(dx * dx + dy * dy);
      return (
        firstPoint,
        PointVector(
          firstPoint.x + dist * math.cos(closestStep),
          firstPoint.y + dist * math.sin(closestStep),
          lastPoint.pressure,
        ),
      );
    }

    return (firstPoint, lastPoint);
  }

  Stroke copy() =>
      Stroke(
          color: color,
          pressureEnabled: pressureEnabled,
          options: options.copyWith(),
          pageIndex: pageIndex,
          page: page,
          toolId: toolId,
        )
        ..points.addAll(points)
        ..rotationDeg = rotationDeg
        ..flatEdge = flatEdge;

  Stroke cloneForEraserFragment() =>
      Stroke(
          color: color,
          pressureEnabled: pressureEnabled,
          options: options.copyWith(),
          pageIndex: pageIndex,
          page: page,
          toolId: toolId,
        )
        ..rotationDeg = rotationDeg
        ..flatEdge = flatEdge;

  static List<PointVector> _ramerDouglasPeucker(
    List<PointVector> points, {
    required double epsilon,
  }) {
    if (points.length < 3) return points;

    final double epsilonSq = epsilon * epsilon;
    final int len = points.length;

    final Uint8List keep = Uint8List(len);
    keep[0] = 1;
    keep[len - 1] = 1;

    final List<int> stack = [0, len - 1];

    while (stack.isNotEmpty) {
      final end = stack.removeLast();
      final start = stack.removeLast();

      if (end - start < 2) continue;

      double maxDistSq = 0.0;
      int index = start;

      final pStart = points[start];
      final pEnd = points[end];

      for (int i = start + 1; i < end; i++) {
        final double distSq = _perpendicularDistanceSq(points[i], pStart, pEnd);
        if (distSq > maxDistSq) {
          maxDistSq = distSq;
          index = i;
        }
      }

      if (maxDistSq > epsilonSq) {
        keep[index] = 1;

        stack.add(index);
        stack.add(end);

        stack.add(start);
        stack.add(index);
      }
    }

    final List<PointVector> result = [];
    for (int i = 0; i < len; i++) {
      if (keep[i] == 1) result.add(points[i]);
    }

    return result;
  }

  static double _perpendicularDistanceSq(
    PointVector point,
    PointVector lineStart,
    PointVector lineEnd,
  ) {
    double dx = lineEnd.x - lineStart.x;
    double dy = lineEnd.y - lineStart.y;
    final double magSq = dx * dx + dy * dy;

    if (magSq == 0.0) {
      return point.distanceSquaredTo(lineStart);
    }

    final double u =
        ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / magSq;

    final double closestX, closestY;
    if (u < 0) {
      closestX = lineStart.x;
      closestY = lineStart.y;
    } else if (u > 1) {
      closestX = lineEnd.x;
      closestY = lineEnd.y;
    } else {
      closestX = lineStart.x + u * dx;
      closestY = lineStart.y + u * dy;
    }

    final double diffX = point.x - closestX;
    final double diffY = point.y - closestY;
    return diffX * diffX + diffY * diffY;
  }

  ui.Vertices? _cachedVertices;
  Path? _cachedPath;
  bool _cachedPathValid = false;

  double _targetScale = 1.0;

  void setLodScale(double scale) {
    final s = scale.clamp(0.1, 5.0);
    if ((_targetScale - s).abs() > 0.1) _targetScale = s;
  }

  int get _predictionLiveFingerprint {
    if (options.isComplete || !stows.strokePrediction.value) return 0;
    final tip = _predictionTip;
    if (tip == null) return 0;
    return Object.hash(
      (tip.dx * 128).round(),
      (tip.dy * 128).round(),
    );
  }

  int get visualFingerprint {
    final double lodBucket = _targetScale < 0.5
        ? 0.25
        : (_targetScale < 1.0 ? 0.5 : (_targetScale < 2.0 ? 1.0 : 2.0));
    return Object.hash(
      geometricFingerprint,
      lodBucket,
      toolId == ToolId.highlighter ? flatEdge : null,
      _predictionLiveFingerprint,
    );
  }

  static const double highlighterStrokeScaleFactor = 1.0;

  Float32List? _rawPositions;
  Uint16List? _rawIndices;

  int? _cachedVerticesHash;

  static final Map<int, _StrokeMeshData> _globalVertexCache = {};
  static const int _kMaxVertexCacheSize = 1000;
  static final List<int> _vertexCacheLru = [];

  Float32List getRawPositions() {
    if (_rawPositions == null) _ensureVertices();
    return _rawPositions ?? Float32List(0);
  }

  Uint16List getRawIndices() {
    if (_rawIndices == null) _ensureVertices();
    return _rawIndices ?? Uint16List(0);
  }

  ui.Vertices? get vertices {
    if (points.length < 2) return null;

    if (toolId == ToolId.advancedPen || toolId == ToolId.highlighter)
      return null;
    return _ensureVertices();
  }

  ui.Vertices? _ensureVertices() {
    final int currentHash = visualFingerprint;
    if (_cachedVertices != null && _cachedVerticesHash == currentHash) {
      return _cachedVertices;
    }
    final _StrokeMeshData? cached = _globalVertexCache[currentHash];
    if (cached != null) {
      _cachedVertices = cached.vertices;
      _cachedVerticesHash = currentHash;
      _rawPositions = cached.positions;
      _rawIndices = cached.indices;
      _bumpVertexCacheLru(currentHash);
      return _cachedVertices;
    }

    final _StrokeMeshData? meshData = _generateSpineMeshLOD();

    if (meshData == null) return null;
    _cachedVertices = meshData.vertices;
    _cachedVerticesHash = currentHash;
    _rawPositions = meshData.positions;
    _rawIndices = meshData.indices;
    while (_globalVertexCache.length >= _kMaxVertexCacheSize &&
        _vertexCacheLru.isNotEmpty) {
      final evictKey = _vertexCacheLru.removeAt(0);
      _globalVertexCache.remove(evictKey);
      // Do not dispose: other strokes may still reference this mesh.
    }
    _globalVertexCache[currentHash] = meshData;
    _vertexCacheLru.add(currentHash);
    return _cachedVertices;
  }

  static void _bumpVertexCacheLru(int key) {
    _vertexCacheLru.remove(key);
    _vertexCacheLru.add(key);
  }

  void dispose() {
    _cachedVertices = null;
    _cachedVerticesHash = null;
    _rawPositions = null;
    _rawIndices = null;
    _cachedPath = null;
    _cachedPathValid = false;
  }

  static const int _capSegments = 10;
  static final Float64List _sinLUT = Float64List.fromList(
    List.generate(
      _capSegments + 1,
      (i) => math.sin((math.pi / 2) * (i / _capSegments)),
    ),
  );
  static final Float64List _cosLUT = Float64List.fromList(
    List.generate(
      _capSegments + 1,
      (i) => math.cos((math.pi / 2) * (i / _capSegments)),
    ),
  );

  _StrokeMeshData? _generateSpineMeshLOD() {
    if (points.length < 2) return null;
    _ensurePackedPoints();
    if (_packedPoints == null || _packedPoints!.length < 6) return null;

    final double scale = _targetScale;

    final int targetCapSegments = _capSegments;

    Float32List smoothPoints;

    // Match getPolygon tolerance while drawing; committed strokes keep a looser LOD.
    final double splineErrorSq = !options.isComplete
        ? (0.13 / scale) * (0.13 / scale)
        : (0.5 / scale) * (0.5 / scale);
    Float32List rawSmooth = _getAdaptiveSpineFast(
      _packedPoints!,
      splineErrorSq,
    );
    final int rawCount = rawSmooth.length ~/ 3;
    if (rawCount < 2) return null;
    final _Float32Builder dedupe = _Float32Builder(estimatedSize: rawCount * 3);
    double lastX = rawSmooth[0];
    double lastY = rawSmooth[1];
    dedupe.add(lastX, lastY, rawSmooth[2]);
    for (int i = 1; i < rawCount; i++) {
      final int o = i * 3;
      final double x = rawSmooth[o];
      final double y = rawSmooth[o + 1];
      final double p = rawSmooth[o + 2];
      final double dx = x - lastX;
      final double dy = y - lastY;
      if ((dx * dx + dy * dy) > 0.0001) {
        dedupe.add(x, y, p);
        lastX = x;
        lastY = y;
      }
    }
    smoothPoints = dedupe.finish();

    int count = smoothPoints.length ~/ 3;
    if (count == 1) {
      final _Float32Builder two = _Float32Builder(estimatedSize: 6);
      two.add(smoothPoints[0], smoothPoints[1], smoothPoints[2]);
      two.add(smoothPoints[0] + 0.1, smoothPoints[1], smoothPoints[2]);
      smoothPoints = two.finish();
      count = 2;
    }
    if (count < 2) return null;

    final bool isHighlighter = toolId == ToolId.highlighter;
    final bool isBallpoint = toolId == ToolId.ballpointPen;
    final bool isCalligraphy = toolId == ToolId.calligraphyPen;

    final double baseSize = isHighlighter
        ? (options.size / 2.0) * highlighterStrokeScaleFactor
        : options.size / 2.0;

    final bool canTaper = !isCalligraphy;

    final double calliCos = isCalligraphy ? math.cos(-40 * math.pi / 180) : 1.0;
    final double calliSin = isCalligraphy ? math.sin(-40 * math.pi / 180) : 0.0;

    final bool highlighterWantsCaps = isHighlighter && !flatEdge;

    final bool generateStartCap =
        targetCapSegments > 0 &&
        (isHighlighter
            ? highlighterWantsCaps
            : (isCalligraphy ? false : (options.start.cap || isBallpoint))) &&
        (!options.start.taperEnabled || !canTaper);
    final bool generateEndCap =
        targetCapSegments > 0 &&
        (isHighlighter
            ? highlighterWantsCaps
            : (isCalligraphy ? false : (options.end.cap || isBallpoint))) &&
        (!options.end.taperEnabled || !canTaper || !options.isComplete);

    final int startOffset = generateStartCap ? targetCapSegments : 0;
    final int endOffset = generateEndCap ? targetCapSegments : 0;

    final int maxTotalVertices =
        count * (_capSegments + 2) + startOffset + endOffset + 2;
    final Float32List positions = Float32List(maxTotalVertices * 4);
    final Uint16List indices = Uint16List(maxTotalVertices * 2);
    int vIndex = 0;
    int iIndex = 0;

    void addVertexPair(
      double px,
      double py,
      double nx,
      double ny,
      double w,
      double pressure,
    ) {
      double vx = nx * w;
      double vy = ny * w;

      if (isCalligraphy) {
        double pressureScale = 0.5 + pressure * 0.5;
        double rxNorm = 1.3 * pressureScale;
        double ryNorm = 0.24 * pressureScale;

        double len = math.sqrt(nx * nx + ny * ny);
        if (len > 0.0001) {
          double dirX = nx / len;
          double dirY = ny / len;

          double localNx = dirX * calliCos + dirY * calliSin;
          double localNy = -dirX * calliSin + dirY * calliCos;

          double scale =
              1.0 /
              math.sqrt(
                rxNorm * rxNorm * localNx * localNx +
                    ryNorm * ryNorm * localNy * localNy,
              );
          double localVx = rxNorm * rxNorm * localNx * scale;
          double localVy = ryNorm * ryNorm * localNy * scale;

          vx = (localVx * calliCos - localVy * calliSin) * w;
          vy = (localVx * calliSin + localVy * calliCos) * w;
        }
      }

      positions[vIndex++] = px + vx;
      positions[vIndex++] = py + vy;
      positions[vIndex++] = px - vx;
      positions[vIndex++] = py - vy;

      indices[iIndex] = iIndex;
      iIndex++;
      indices[iIndex] = iIndex;
      iIndex++;
    }

    double capSin(int i, int max) {
      if (max == _capSegments) return _sinLUT[i];
      return math.sin((math.pi / 2) * (i / max));
    }

    double capCos(int i, int max) {
      if (max == _capSegments) return _cosLUT[i];
      return math.cos((math.pi / 2) * (i / max));
    }

    final bool usePressure =
        (options.simulatePressure || pressureEnabled) &&
        toolId != ToolId.ballpointPen &&
        toolId != ToolId.highlighter;

    if (generateStartCap) {
      final double p0x = smoothPoints[0];
      final double p0y = smoothPoints[1];
      final double p0p = smoothPoints[2];

      double startDx = 0, startDy = 0;
      for (int step = 1; step < count; step++) {
        startDx = smoothPoints[step * 3] - p0x;
        startDy = smoothPoints[step * 3 + 1] - p0y;
        if (startDx * startDx + startDy * startDy > 4.0) break;
      }
      final len = math.sqrt(startDx * startDx + startDy * startDy);
      if (len > 0.0001) {
        startDx /= len;
        startDy /= len;
      } else {
        startDx = 1;
        startDy = 0;
      }
      final nx = -startDy;
      final ny = startDx;

      double startPressure = usePressure ? p0p : 0.5;
      if (canTaper && options.start.taperEnabled) startPressure *= 0.0;
      final double width =
          (toolId == ToolId.ballpointPen || isHighlighter || isCalligraphy)
          ? baseSize
          : math.max(0.1, baseSize * (0.2 + 0.8 * startPressure * 2));

      for (int i = 0; i < targetCapSegments; i++) {
        final double sinA = capSin(targetCapSegments - i, targetCapSegments);
        final double cosA = capCos(targetCapSegments - i, targetCapSegments);
        addVertexPair(
          p0x - startDx * (sinA * width),
          p0y - startDy * (sinA * width),
          nx,
          ny,
          cosA * width,
          startPressure,
        );
      }
    }

    for (int i = 0; i < count; i++) {
      final int o = i * 3;
      final double px = smoothPoints[o];
      final double py = smoothPoints[o + 1];
      final double pp = smoothPoints[o + 2];

      double bdx = 0, bdy = 0;
      if (i > 0) {
        bdx = px - smoothPoints[o - 3];
        bdy = py - smoothPoints[o - 2];
      }
      double fdx = 0, fdy = 0;
      if (i < count - 1) {
        fdx = smoothPoints[o + 3] - px;
        fdy = smoothPoints[o + 4] - py;
      }

      if (i == 0) {
        bdx = fdx;
        bdy = fdy;
      }
      if (i == count - 1) {
        fdx = bdx;
        fdy = bdy;
      }

      double lenB = math.sqrt(bdx * bdx + bdy * bdy);
      double lenF = math.sqrt(fdx * fdx + fdy * fdy);

      double nBx = 0, nBy = 0;
      if (lenB > 0.0001) {
        nBx = -bdy / lenB;
        nBy = bdx / lenB;
      }

      double nFx = 0, nFy = 0;
      if (lenF > 0.0001) {
        nFx = -fdy / lenF;
        nFy = fdx / lenF;
      }

      if (lenB <= 0.0001 && lenF > 0.0001) {
        nBx = nFx;
        nBy = nFy;
        lenB = lenF;
        bdx = fdx;
        bdy = fdy;
      }
      if (lenF <= 0.0001 && lenB > 0.0001) {
        nFx = nBx;
        nFy = nBy;
        lenF = lenB;
        fdx = bdx;
        fdy = bdy;
      }

      double dx = fdx * 0.5 + bdx * 0.5;
      double dy = fdy * 0.5 + bdy * 0.5;
      double lenM = math.sqrt(dx * dx + dy * dy);
      double nx = 0, ny = 0;
      if (lenM > 0.0001) {
        nx = -dy / lenM;
        ny = dx / lenM;
      } else {
        nx = nBx;
        ny = nBy;
      }

      double pressure = usePressure ? pp : 0.5;
      final int taperLen = toolId == ToolId.fountainPen ? 12 : 6;
      if (canTaper) {
        if (options.start.taperEnabled && i < taperLen) {
          final double t = i / taperLen;
          pressure *= (t * (2 - t));
        } else if (options.end.taperEnabled &&
            options.isComplete &&
            i > count - (taperLen + 1)) {
          final double t = (count - 1 - i) / taperLen;
          pressure *= (t * (2 - t));
        }
      }
      final double width =
          (toolId == ToolId.ballpointPen || isHighlighter || isCalligraphy)
          ? baseSize
          : math.max(0.1, baseSize * (0.2 + 0.8 * pressure * 2));

      final double dot = (lenB > 0.0001 && lenF > 0.0001)
          ? (bdx * fdx + bdy * fdy) / (lenB * lenF)
          : 1.0;

      if (dot < 0.5 && targetCapSegments > 0 && lenB > 0.01 && lenF > 0.01) {
        int segments = (targetCapSegments * (1.0 - dot)).ceil().clamp(
          1,
          _capSegments,
        );
        double angleB = math.atan2(nBy, nBx);
        double angleF = math.atan2(nFy, nFx);
        double diff = angleF - angleB;
        while (diff > math.pi) diff -= 2 * math.pi;
        while (diff < -math.pi) diff += 2 * math.pi;

        for (int step = 0; step <= segments; step++) {
          double t = step / segments;
          double a = angleB + diff * t;
          addVertexPair(px, py, math.cos(a), math.sin(a), width, pressure);
        }
      } else {
        addVertexPair(px, py, nx, ny, width, pressure);
      }
    }

    if (generateEndCap) {
      final int lastO = (count - 1) * 3;
      final double pLx = smoothPoints[lastO];
      final double pLy = smoothPoints[lastO + 1];
      final double pLp = smoothPoints[lastO + 2];

      double endDx = 0, endDy = 0;
      for (int step = 1; step < count; step++) {
        endDx = pLx - smoothPoints[lastO - step * 3];
        endDy = pLy - smoothPoints[lastO - step * 3 + 1];
        if (endDx * endDx + endDy * endDy > 4.0) break;
      }
      final len = math.sqrt(endDx * endDx + endDy * endDy);
      if (len > 0.0001) {
        endDx /= len;
        endDy /= len;
      } else {
        endDx = 1;
        endDy = 0;
      }
      final nx = -endDy;
      final ny = endDx;

      double endPressure = usePressure ? pLp : 0.5;
      if (canTaper && options.end.taperEnabled) endPressure *= 0.0;
      final double width =
          (toolId == ToolId.ballpointPen || isHighlighter || isCalligraphy)
          ? baseSize
          : math.max(0.1, baseSize * (0.2 + 0.8 * endPressure * 2));
      for (int i = 1; i <= targetCapSegments; i++) {
        final double sinA = capSin(i, targetCapSegments);
        final double cosA = capCos(i, targetCapSegments);
        addVertexPair(
          pLx + endDx * (sinA * width),
          pLy + endDy * (sinA * width),
          nx,
          ny,
          cosA * width,
          endPressure,
        );
      }
    }

    final Float32List finalPositions = Float32List.sublistView(
      positions,
      0,
      vIndex,
    );
    final Uint16List finalIndices = Uint16List.sublistView(indices, 0, iIndex);

    final Int32List? finalColors = null;

    final ui.Vertices verts = ui.Vertices.raw(
      ui.VertexMode.triangleStrip,
      finalPositions,
      indices: finalIndices,
      colors: finalColors,
    );
    return _StrokeMeshData(verts, finalPositions, finalIndices);
  }

  static Float32List _getAdaptiveSpineFast(
    Float32List input,
    double toleranceSq,
  ) {
    final int n = input.length ~/ 3;
    if (n < 3) return input;
    final _Float32Builder out = _Float32Builder(estimatedSize: n * 8);
    out.add(input[0], input[1], input[2]);

    for (int i = 0; i < n - 1; i++) {
      final int i0 = math.max(0, i - 1) * 3;
      final int i1 = i * 3;
      final int i2 = (i + 1) * 3;
      final int i3 = math.min(n - 1, i + 2) * 3;

      final double p0x = input[i0], p0y = input[i0 + 1];
      final double p1x = input[i1], p1y = input[i1 + 1], p1p = input[i1 + 2];
      final double p2x = input[i2], p2y = input[i2 + 1], p2p = input[i2 + 2];
      final double p3x = input[i3], p3y = input[i3 + 1];

      // Calculate the actual distance of this line segment
      final double dx = p2x - p1x;
      final double dy = p2y - p1y;
      final double segDist = math.sqrt(dx * dx + dy * dy);

      // Dynamically add a spline point every ~2.5 pixels to guarantee perfect smoothness
      final int steps = (segDist / 2.5).ceil().clamp(1, 64);

      if (steps > 1) {
        for (int j = 1; j < steps; j++) {
          _addSplinePointFast(
            out,
            p0x,
            p0y,
            p1x,
            p1y,
            p1p,
            p2x,
            p2y,
            p2p,
            p3x,
            p3y,
            j / steps,
          );
        }
      }
      out.add(p2x, p2y, p2p);
    }
    return out.finish();
  }

  static void _addSplinePointFast(
    _Float32Builder out,
    double p0x,
    double p0y,
    double p1x,
    double p1y,
    double p1p,
    double p2x,
    double p2y,
    double p2p,
    double p3x,
    double p3y,
    double t,
  ) {
    final double t2 = t * t;
    final double t3 = t2 * t;
    final double x =
        0.5 *
        ((2 * p1x) +
            (-p0x + p2x) * t +
            (2 * p0x - 5 * p1x + 4 * p2x - p3x) * t2 +
            (-p0x + 3 * p1x - 3 * p2x + p3x) * t3);
    final double y =
        0.5 *
        ((2 * p1y) +
            (-p0y + p2y) * t +
            (2 * p0y - 5 * p1y + 4 * p2y - p3y) * t2 +
            (-p0y + 3 * p1y - 3 * p2y + p3y) * t3);
    final double pressure = p1p + (p2p - p1p) * t;
    out.add(x, y, pressure);
  }

  static double _distPointToSegmentSq(
    double px,
    double py,
    double x1,
    double y1,
    double x2,
    double y2,
  ) {
    final double l2 = (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2);
    if (l2 == 0) return (px - x1) * (px - x1) + (py - y1) * (py - y1);
    final double t = ((px - x1) * (x2 - x1) + (py - y1) * (y2 - y1)) / l2;
    final double tClamped = t.clamp(0.0, 1.0);
    final double projX = x1 + tClamped * (x2 - x1);
    final double projY = y1 + tClamped * (y2 - y1);
    return (px - projX) * (px - projX) + (py - projY) * (py - projY);
  }

  List<PointVector> _getSmoothSpine(List<PointVector> inputPoints) {
    if (inputPoints.length < 3) return inputPoints;

    final List<PointVector> result = [];
    result.add(inputPoints.first);

    for (int i = 0; i < inputPoints.length - 1; i++) {
      final p0 = inputPoints[math.max(0, i - 1)];
      final p1 = inputPoints[i];
      final p2 = inputPoints[i + 1];
      final p3 = inputPoints[math.min(inputPoints.length - 1, i + 2)];

      double dist = math.sqrt(
        math.pow(p2.x - p1.x, 2) + math.pow(p2.y - p1.y, 2),
      );

      double segFactor = dist / 4.0;
      if (i > 0 && i < inputPoints.length - 2) {
        final ax = p1.x - inputPoints[i - 1].x;
        final ay = p1.y - inputPoints[i - 1].y;
        final bx = inputPoints[i + 2].x - p2.x;
        final by = inputPoints[i + 2].y - p2.y;
        final amag = math.sqrt(ax * ax + ay * ay);
        final bmag = math.sqrt(bx * bx + by * by);
        if (amag > 0.001 && bmag > 0.001) {
          final cosTheta = (ax * bx + ay * by) / (amag * bmag).clamp(-1.0, 1.0);
          final curvature = 1.0 - cosTheta;
          if (curvature > 0.3) segFactor *= (1.0 + curvature * 0.4);
        }
      }
      final int segments = segFactor.ceil().clamp(3, 16);

      for (int t = 1; t <= segments; t++) {
        final double tNorm = t / segments.toDouble();

        final double t2 = tNorm * tNorm;
        final double t3 = t2 * tNorm;

        final double x =
            0.5 *
            ((2 * p1.x) +
                (-p0.x + p2.x) * tNorm +
                (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 +
                (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3);

        final double y =
            0.5 *
            ((2 * p1.y) +
                (-p0.y + p2.y) * tNorm +
                (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 +
                (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3);

        double pressure = 0.5;
        if (p1.pressure != null && p2.pressure != null) {
          pressure = p1.pressure! + (p2.pressure! - p1.pressure!) * tNorm;
        }

        result.add(PointVector(x, y, pressure));
      }
    }

    return result;
  }
}

class _Float32Builder {
  Float32List _buffer;
  int _count = 0;

  _Float32Builder({int estimatedSize = 32})
    : _buffer = Float32List(estimatedSize);

  void add(double x, double y, double p) {
    if (_count + 3 > _buffer.length) {
      final next = Float32List(_buffer.length * 2);
      next.setRange(0, _count, _buffer);
      _buffer = next;
    }
    _buffer[_count++] = x;
    _buffer[_count++] = y;
    _buffer[_count++] = p;
  }

  Float32List finish() {
    if (_count == 0) return Float32List(0);
    return Float32List.view(_buffer.buffer, _buffer.offsetInBytes, _count);
  }
}

class _StrokeMeshData {
  final ui.Vertices vertices;
  final Float32List positions;
  final Uint16List indices;
  _StrokeMeshData(this.vertices, this.positions, this.indices);
}

enum StrokeQuality {
  low(4),
  high(1);

  const StrokeQuality(this.N);

  final int N;
}

abstract class HasBounds {
  Rect get bounds;
}

extension PointVectorBounds on PointVector {
  Rect get bounds => Rect.fromLTWH(x, y, 0.001, 0.001);
}

class QuadTree<T> {
  final Rect boundary;
  final int capacity;
  final List<T> items = [];
  final Rect Function(T item) _getBounds;

  bool divided = false;
  QuadTree<T>? northeast;
  QuadTree<T>? northwest;
  QuadTree<T>? southeast;
  QuadTree<T>? southwest;

  static final List<QuadTree<dynamic>> _insertStack = [];
  static final List<QuadTree<dynamic>> _queryStack = [];
  static final List<QuadTree<dynamic>> _removeStack = [];

  QuadTree(
    this.boundary, {
    this.capacity = 10,
    Rect Function(T item)? getBounds,
  }) : _getBounds =
           getBounds ??
           ((item) {
             if (item is HasBounds) return item.bounds;
             if (item is PointVector) return (item as PointVector).bounds;
             if (item is Stroke) return item.bounds;
             throw UnimplementedError(
               'Item must implement HasBounds or provide getBounds',
             );
           });

  bool insert(T item) {
    final itemBounds = _getBounds(item);
    if (!boundary.overlaps(itemBounds)) return false;

    final stack = _insertStack;
    stack.clear();
    stack.add(this as QuadTree<dynamic>);
    bool inserted = false;

    while (stack.isNotEmpty) {
      final node = stack.removeLast() as QuadTree<T>;
      if (!node.boundary.overlaps(itemBounds)) continue;

      if (node.items.length < node.capacity && !node.divided) {
        node.items.add(item);
        inserted = true;
        continue;
      }

      if (!node.divided) {
        node.subdivide();
      }

      stack.add(node.northeast! as QuadTree<dynamic>);
      stack.add(node.northwest! as QuadTree<dynamic>);
      stack.add(node.southeast! as QuadTree<dynamic>);
      stack.add(node.southwest! as QuadTree<dynamic>);
    }

    return inserted;
  }

  void subdivide() {
    final x = boundary.left;
    final y = boundary.top;
    final w = boundary.width / 2;
    final h = boundary.height / 2;

    northeast = QuadTree(
      Rect.fromLTWH(x + w, y, w, h),
      capacity: capacity,
      getBounds: _getBounds,
    );
    northwest = QuadTree(
      Rect.fromLTWH(x, y, w, h),
      capacity: capacity,
      getBounds: _getBounds,
    );
    southeast = QuadTree(
      Rect.fromLTWH(x + w, y + h, w, h),
      capacity: capacity,
      getBounds: _getBounds,
    );
    southwest = QuadTree(
      Rect.fromLTWH(x, y + h, w, h),
      capacity: capacity,
      getBounds: _getBounds,
    );
    divided = true;
  }

  List<T> query(Rect range, [List<T>? found]) {
    found ??= [];

    final stack = _queryStack;
    stack.clear();
    stack.add(this as QuadTree<dynamic>);

    while (stack.isNotEmpty) {
      final node = stack.removeLast() as QuadTree<T>;
      if (!node.boundary.overlaps(range)) continue;

      for (int i = 0; i < node.items.length; i++) {
        final item = node.items[i];
        if (range.overlaps(_getBounds(item))) {
          found.add(item);
        }
      }

      if (node.divided) {
        stack.add(node.northeast! as QuadTree<dynamic>);
        stack.add(node.northwest! as QuadTree<dynamic>);
        stack.add(node.southeast! as QuadTree<dynamic>);
        stack.add(node.southwest! as QuadTree<dynamic>);
      }
    }

    return found;
  }

  bool remove(T item) {
    final itemBounds = _getBounds(item);
    if (!boundary.overlaps(itemBounds)) return false;

    final stack = _removeStack;
    stack.clear();
    stack.add(this as QuadTree<dynamic>);
    bool removed = false;

    while (stack.isNotEmpty) {
      final node = stack.removeLast() as QuadTree<T>;
      if (!node.boundary.overlaps(itemBounds)) continue;

      if (node.items.remove(item)) {
        removed = true;
      }

      if (node.divided) {
        stack.add(node.northeast! as QuadTree<dynamic>);
        stack.add(node.northwest! as QuadTree<dynamic>);
        stack.add(node.southeast! as QuadTree<dynamic>);
        stack.add(node.southwest! as QuadTree<dynamic>);
      }
    }

    return removed;
  }
}

class SpatialGrid {
  SpatialGrid({this.cellSize = 100.0});

  final double cellSize;
  final Map<int, List<int>> _grid = {};

  int _cellHash(int cx, int cy) {
    return (cx * 73856093) ^ (cy * 19349663);
  }

  void clear() {
    _grid.clear();
  }

  void insert(int strokeIndex, Rect bounds) {
    final startX = (bounds.left / cellSize).floor();
    final endX = (bounds.right / cellSize).floor();
    final startY = (bounds.top / cellSize).floor();
    final endY = (bounds.bottom / cellSize).floor();

    for (var cx = startX; cx <= endX; cx++) {
      for (var cy = startY; cy <= endY; cy++) {
        final h = _cellHash(cx, cy);
        _grid.putIfAbsent(h, () => []).add(strokeIndex);
      }
    }
  }

  List<int> query(Rect rect) {
    final startX = (rect.left / cellSize).floor();
    final endX = (rect.right / cellSize).floor();
    final startY = (rect.top / cellSize).floor();
    final endY = (rect.bottom / cellSize).floor();

    final Set<int> seen = {};
    for (var cx = startX; cx <= endX; cx++) {
      for (var cy = startY; cy <= endY; cy++) {
        final list = _grid[_cellHash(cx, cy)];
        if (list != null) {
          for (final i in list) {
            seen.add(i);
          }
        }
      }
    }
    final out = seen.toList();
    out.sort();
    return out;
  }
}
