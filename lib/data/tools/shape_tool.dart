// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:saber/components/canvas/_shape_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/_tool.dart';

class ShapeTool extends Tool {
  ShapeTool({ShapeConfig? config, Color? color, Color? fillColor})
    : config = config ?? ShapeConfig.defaultConfig(),
      color = color ?? Colors.black,
      fillColor = fillColor ?? (color ?? Colors.black).withOpacity(0.2);

  ShapeConfig config;
  Color color;
  Color fillColor;

  int _currentStep = 0;
  List<Offset> _controlPoints = [];
  ShapeStroke? _preview;

  static ShapeTool currentShapeTool = ShapeTool();

  static List<ShapeKind> get selectableShapes =>
      ShapeKind.values.where((k) => k.isToolSelectable).toList();

  @override
  ToolId get toolId => ToolId.shapeTool;

  ShapeStroke? get preview => _preview;

  void onDragStart(Offset position, EditorPage page, int pageIndex) {
    if (_currentStep == 0) {

      _controlPoints = [position, position];
    } else {

      _controlPoints.add(position);
    }
    _updatePreview(page, pageIndex);
  }

  void onDragUpdate(Offset position, EditorPage page, int pageIndex) {
    if (_controlPoints.isEmpty) return;

    if (_controlPoints.length == 1) {
      _controlPoints.add(position);
    } else {
      _controlPoints[_controlPoints.length - 1] = position;
    }
    _updatePreview(page, pageIndex);
  }

  ShapeStroke? onDragEnd(EditorPage page, int pageIndex) {
    if (_controlPoints.isEmpty) return null;

    if (_preview == null) return null;

    final finalStroke = ShapeStroke(
      color: _preview!.color,
      fillColor: _preview!.fillColor,
      fill: _preview!.fill,
      options: _preview!.options.copyWith(isComplete: true),
      pressureEnabled: _preview!.pressureEnabled,
      pageIndex: _preview!.pageIndex,
      page: _preview!.page,
      toolId: _preview!.toolId,
      config: _preview!.config,
    );

    _currentStep = 0;
    _controlPoints = [];
    _preview = null;

    return finalStroke;
  }

  void _updatePreview(EditorPage page, int pageIndex) {
    if (_controlPoints.isEmpty) {
      _preview = null;
      return;
    }

    final vertices = List<Offset>.from(_controlPoints);

    if (vertices.isEmpty) {
      _preview = null;
      return;
    }

    double minX = vertices.first.dx;
    double maxX = vertices.first.dx;
    double minY = vertices.first.dy;
    double maxY = vertices.first.dy;

    for (final v in vertices) {
      minX = math.min(minX, v.dx);
      maxX = math.max(maxX, v.dx);
      minY = math.min(minY, v.dy);
      maxY = math.max(maxY, v.dy);
    }

    final safeWidth = (maxX - minX) < 1.0 ? 1.0 : (maxX - minX);
    final safeHeight = (maxY - minY) < 1.0 ? 1.0 : (maxY - minY);

    final bounds = Rect.fromLTWH(minX, minY, safeWidth, safeHeight);

    final shapeConfig = config.copyWith(
      bounds: bounds,
      start: vertices.isNotEmpty ? vertices.first : null,
      end: vertices.length > 1 ? vertices.last : null,
      vertices: vertices,
    );

    _preview = ShapeStroke(
      color: color,
      fillColor: shapeConfig.fill ? fillColor : Colors.transparent,
      fill: shapeConfig.fill,
      options: ShapeStroke.defaultOptions.copyWith(
        isComplete: false,
        size: config.strokeWidth,
      ),
      pressureEnabled: false,
      pageIndex: pageIndex,
      page: page,
      toolId: toolId,
      config: shapeConfig,
    );
  }

  void cancel() {
    _currentStep = 0;
    _controlPoints = [];
    _preview = null;
  }
}

enum ShapeKind {

  rectangle,
  circle,
  ellipse,
  line,
  arrow,
  doubleArrow,

  triangleIsosceles,
  triangleRight,

  parabola,
  cylinder,
  cube,
  sphere,
  halfSphere,

  pendulum,
  spring,
  fixedEnd,
  harmonicOscillator,
  coordinateSystem,
  coordinateSystem3D,
  polygon,

  nabla,
  summatory,
  productory,
  leftBracket,
  rightBracket,
  leftAngleBracket,
  rightAngleBracket,
  leftBrace,
  rightBrace,
  star,
  infinity,
}

extension ShapeKindVisibility on ShapeKind {
  bool get isToolSelectable {
    return !const [
      ShapeKind.nabla,
      ShapeKind.summatory,
      ShapeKind.productory,
      ShapeKind.leftBracket,
      ShapeKind.rightBracket,
      ShapeKind.leftAngleBracket,
      ShapeKind.rightAngleBracket,
      ShapeKind.leftBrace,
      ShapeKind.rightBrace,
    ].contains(this);
  }
}

ShapeKind shapeKindFromStored(int index) {
  const legacyRemovedIndices = {13, 18, 19};
  if (legacyRemovedIndices.contains(index)) return ShapeKind.rectangle;
  if (index < 0 || index >= ShapeKind.values.length) return ShapeKind.rectangle;
  return ShapeKind.values[index];
}

enum ShapeStrokeStyle {
  solid,
  dashed,
  dotted,
}

ShapeStrokeStyle shapeStrokeStyleFromJson(dynamic v) {
  if (v == null) return ShapeStrokeStyle.solid;
  final i = v is int
      ? v
      : (v as num?)?.toInt() ?? int.tryParse('$v') ?? 0;
  if (i < 0 || i >= ShapeStrokeStyle.values.length) {
    return ShapeStrokeStyle.solid;
  }
  return ShapeStrokeStyle.values[i];
}

class ShapeConfig {
  ShapeConfig({
    required this.kind,
    required this.bounds,
    this.start,
    this.end,
    this.rotationDeg = 0,
    this.eccentricity = 0.0,
    this.angleDeg = 45,
    this.strokeWidth = 3,
    this.detail = 12,
    this.vertices,
    this.fill = false,
    this.strokeStyle = ShapeStrokeStyle.solid,
    this.data = const {},
  });

  final ShapeKind kind;
  final Rect bounds;
  final Offset? start;
  final Offset? end;
  final double rotationDeg;
  final double eccentricity;
  final double angleDeg;
  final double strokeWidth;
  final int detail;
  final List<Offset>? vertices;
  final bool fill;
  final ShapeStrokeStyle strokeStyle;
  final Map<String, dynamic> data;

  ShapeConfig copyWith({
    ShapeKind? kind,
    Rect? bounds,
    Offset? start,
    Offset? end,
    double? rotationDeg,
    double? eccentricity,
    double? angleDeg,
    double? strokeWidth,
    int? detail,
    List<Offset>? vertices,
    bool? fill,
    ShapeStrokeStyle? strokeStyle,
    Map<String, dynamic>? data,
  }) {
    return ShapeConfig(
      kind: kind ?? this.kind,
      bounds: bounds ?? this.bounds,
      start: start ?? this.start,
      end: end ?? this.end,
      rotationDeg: rotationDeg ?? this.rotationDeg,
      eccentricity: eccentricity ?? this.eccentricity,
      angleDeg: angleDeg ?? this.angleDeg,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      detail: detail ?? this.detail,
      vertices: vertices ?? this.vertices,
      fill: fill ?? this.fill,
      strokeStyle: strokeStyle ?? this.strokeStyle,
      data: data ?? this.data,
    );
  }

  static ShapeConfig defaultConfig() => ShapeConfig(
    kind: ShapeKind.rectangle,
    bounds: const Rect.fromLTWH(0, 0, 120, 80),
  );

  Map<String, dynamic> toJson() {

    Map<String, double>? normalize(Offset? p) {
      if (p == null) return null;
      if (bounds.width == 0 || bounds.height == 0) return {'x': 0, 'y': 0};
      return {
        'x': (p.dx - bounds.left) / bounds.width,
        'y': (p.dy - bounds.top) / bounds.height,
      };
    }

    final jsonVertices = vertices?.map((v) => normalize(v)!).toList();

    return {
      'kind': kind.index,
      'bounds': {
        'left': bounds.left,
        'top': bounds.top,
        'width': bounds.width,
        'height': bounds.height,
      },
      'start': normalize(start),
      'end': normalize(end),
      'rotationDeg': rotationDeg,
      'eccentricity': eccentricity,
      'angleDeg': angleDeg,
      'strokeWidth': strokeWidth,
      'detail': detail,
      'fill': fill,
      'strokeStyle': strokeStyle.index,
      'vertices': jsonVertices,
      'data': data,
    };
  }

  factory ShapeConfig.fromJson(Map<String, dynamic> json) {
    final bounds = _parseBoundsFromJson(json);

    Offset? denormalize(dynamic data) {
      if (data == null) return null;

      final valX = toDouble(data['x'] ?? data['dx']);
      final valY = toDouble(data['y'] ?? data['dy']);

      bool isLikelyNormalized =
          (valX >= -0.5 && valX <= 1.5) && (valY >= -0.5 && valY <= 1.5);

      if (!isLikelyNormalized && (valX.abs() > 2 || valY.abs() > 2)) {
        return Offset(valX, valY);
      }

      return Offset(
        bounds.left + (valX * bounds.width),
        bounds.top + (valY * bounds.height),
      );
    }

    List<Offset>? loadedVertices;
    if (json['vertices'] != null) {
      loadedVertices = (json['vertices'] as List)
          .map((v) => denormalize(v)!)
          .toList();
    }

    Offset? start = denormalize(json['start']);
    Offset? end = denormalize(json['end']);

    // CRITICAL: NEVER recalculate bounds from vertices when loading.

    Rect finalBounds = bounds;

    if (finalBounds.width <= 0) {
      finalBounds = Rect.fromLTWH(
        finalBounds.left,
        finalBounds.top,
        1,
        finalBounds.height,
      );
    }
    if (finalBounds.height <= 0) {
      finalBounds = Rect.fromLTWH(
        finalBounds.left,
        finalBounds.top,
        finalBounds.width,
        1,
      );
    }

    return ShapeConfig(
      kind: shapeKindFromStored(json['kind'] as int? ?? 0),
      bounds: finalBounds,
      start: start,
      end: end,
      rotationDeg: toDouble(json['rotationDeg']),
      eccentricity: toDouble(json['eccentricity']),
      angleDeg: json['angleDeg'] != null ? toDouble(json['angleDeg']) : 45.0,
      strokeWidth: json['strokeWidth'] != null
          ? toDouble(json['strokeWidth'])
          : 3.0,
      detail: (json['detail'] as num?)?.toInt() ?? 12,
      fill: json['fill'] as bool? ?? false,
      strokeStyle: shapeStrokeStyleFromJson(json['strokeStyle']),
      vertices: loadedVertices,
      data: (json['data'] as Map<String, dynamic>?) ?? {},
    );
  }

  static double toDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? 0.0;
    return 0.0;
  }

  static Rect _parseBoundsFromJson(Map<String, dynamic> json) {
    try {
      final boundsJson = json['bounds'] as Map<String, dynamic>?;
      if (boundsJson != null) {
        final left = toDouble(boundsJson['left']);
        final top = toDouble(boundsJson['top']);
        final width = toDouble(boundsJson['width']);
        final height = toDouble(boundsJson['height']);

        return Rect.fromLTWH(
          left,
          top,
          width < 0 ? 1 : width,
          height < 0 ? 1 : height,
        );
      }
    } catch (e) {

    }
    return const Rect.fromLTWH(0, 0, 100, 100);
  }
}
