// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/binary_writer.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/dynamic_extensions.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/shape_geometry.dart';
import 'package:saber/data/tools/shape_tool.dart';
import 'package:vector_math/vector_math_64.dart' as vmath;

class ShapeStroke extends Stroke {
  ShapeStroke({
    required super.color,
    required super.pressureEnabled,
    required super.options,
    required super.pageIndex,
    required super.page,
    required super.toolId,
    required ShapeConfig config,
    bool fill = false,
    Color? fillColor,
    List<Offset>? shapeVertices,
  }) : fill = _isLinearShape(config.kind) ? false : fill,
       fillColor = fillColor ?? color.withOpacity(0.7),
       shapeVertices = shapeVertices,
       _config = config.ensuredControlPoints(),
       super() {
    _config = _config.copyWith(strokeWidth: options.size);

    options.size = _config.strokeWidth;
    options.isComplete = true;

    options.smoothing = 0;
    options.streamline = 0;
    options.simulatePressure = false;
    options.thinning = 0;

    _regeneratePoints();
  }

  ShapeConfig _config;
  ShapeConfig get config => _config;
  set config(ShapeConfig value) {
    _config = value.ensuredControlPoints();
    _cachedPath = null;
    markPolygonNeedsUpdating();
    _regeneratePoints();
  }

  /// Editable control points (canonical geometry).
  List<Offset> get controlPoints => ShapeGeometry.controlPointsOf(config);

  bool get isVertexEditable => config.kind.isVertexEditable;

  final bool fill;
  final Color fillColor;

  final List<Offset>? shapeVertices;

  Path? _cachedPath;

  static final defaultOptions = StrokeOptions(
    size: 3,
    smoothing: 0,
    streamline: 0,
    simulatePressure: false,
  );

  static bool _isLinearShape(ShapeKind kind) {
    return const [
      ShapeKind.line,
      ShapeKind.arrow,
      ShapeKind.doubleArrow,
      ShapeKind.parabola,
      ShapeKind.spring,
      ShapeKind.fixedEnd,
      ShapeKind.coordinateSystem,
      ShapeKind.nabla,
      ShapeKind.summatory,
      ShapeKind.productory,
      ShapeKind.leftBracket,
      ShapeKind.rightBracket,
      ShapeKind.leftAngleBracket,
      ShapeKind.rightAngleBracket,
      ShapeKind.leftBrace,
      ShapeKind.rightBrace,
      ShapeKind.infinity,
    ].contains(kind);
  }

  static bool _isMatrixRotatedShape(ShapeKind kind) {
    return const [
      ShapeKind.rectangle,
      ShapeKind.circle,
      ShapeKind.ellipse,
      ShapeKind.polygon,
      ShapeKind.star,
      ShapeKind.triangleIsosceles,
      ShapeKind.triangleRight,
      ShapeKind.nabla,
      ShapeKind.summatory,
      ShapeKind.productory,
      ShapeKind.leftBracket,
      ShapeKind.rightBracket,
      ShapeKind.leftAngleBracket,
      ShapeKind.rightAngleBracket,
      ShapeKind.leftBrace,
      ShapeKind.rightBrace,
      ShapeKind.infinity,
      ShapeKind.cylinder,
      ShapeKind.cube,
      ShapeKind.sphere,
      ShapeKind.halfSphere,
      ShapeKind.coordinateSystem,
      ShapeKind.coordinateSystem3D,
    ].contains(kind);
  }

  void _regeneratePoints() {
    _cachedPath = null;
    final path = shapePath;
    points.clear();
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      final length = metric.length;
      if (length <= 0) continue;
      final step = math.max(1.0, length / 2048.0);
      for (double d = 0; d < length; d += step) {
        final tangent = metric.getTangentForOffset(d);
        if (tangent != null)
          points.add(
            PointVector(tangent.position.dx, tangent.position.dy, 0.5),
          );
      }
      final endTangent = metric.getTangentForOffset(length);
      if (endTangent != null)
        points.add(
          PointVector(endTangent.position.dx, endTangent.position.dy, 0.5),
        );
    }
    if (points.isEmpty && !config.bounds.isEmpty) {
      final center = config.bounds.center;
      points.add(PointVector(center.dx, center.dy, 0.5));
    }
    markPolygonNeedsUpdating();
  }

  factory ShapeStroke.fromJson(
    Map<String, dynamic> json, {
    required int fileVersion,
    required int pageIndex,
    required HasSize page,
  }) {
    ShapeConfig shapeConfig;

    if (json['shapeConfig'] != null) {
      try {
        final map = json['shapeConfig'] as Map<String, dynamic>;

        double toD(dynamic v) => toDoubleSafe(v) ?? 0.0;

        Offset parseAbs(dynamic d) {
          if (d == null) return Offset.zero;
          return Offset(toD(d['x'] ?? d['dx']), toD(d['y'] ?? d['dy']));
        }

        List<Offset> verts = [];
        if (map['vertices'] != null && (map['vertices'] as List).isNotEmpty) {
          verts = (map['vertices'] as List).map(parseAbs).toList();
        }

        Rect bounds = const Rect.fromLTWH(0, 0, 100, 100);
        if (map['bounds'] != null) {
          final b = map['bounds'];
          bounds = Rect.fromLTWH(
            toD(b['left']),
            toD(b['top']),
            toD(b['width']),
            toD(b['height']),
          );
        }

        shapeConfig = ShapeConfig(
          kind: shapeKindFromStored(map['kind'] as int? ?? 0),
          bounds: bounds,
          start: parseAbs(map['start']),
          end: parseAbs(map['end']),
          rotationDeg: toD(map['rotationDeg']),
          eccentricity: toD(map['eccentricity']),
          angleDeg: toD(map['angleDeg']),
          strokeWidth: toD(map['strokeWidth']),
          detail: (map['detail'] as num?)?.toInt() ?? 12,
          fill: map['fill'] as bool? ?? false,
          strokeStyle: shapeStrokeStyleFromJson(map['strokeStyle']),
          vertices: verts,
          data: (map['data'] as Map<String, dynamic>?) ?? {},
        );
      } catch (e) {
        shapeConfig = _parseLegacyShapeConfig(json);
      }
    } else {
      shapeConfig = _parseLegacyShapeConfig(json);
    }

    final bool fillValue = json['f'] ?? shapeConfig.fill;
    if (shapeConfig.fill != fillValue) {
      shapeConfig = shapeConfig.copyWith(fill: fillValue);
    }

    final stroke = ShapeStroke(
      color: Color(toIntSafe(json['c']) ?? Stroke.defaultColor.value),
      fillColor: Color(
        toIntSafe(json['fc']) ?? Stroke.defaultColor.withOpacity(0.7).value,
      ),
      fill: fillValue,
      pressureEnabled: json['pe'] ?? false,
      options: StrokeOptions.fromJson(json),
      pageIndex: pageIndex,
      page: page,
      toolId: ToolId.shapeTool,
      config: shapeConfig,
      shapeVertices: shapeConfig.vertices,
    )..rotationDeg = toDoubleSafe(json['rot']) ?? shapeConfig.rotationDeg;

    stroke._regeneratePoints();

    return stroke;
  }

  @override
  Map<String, dynamic> toJson() {
    final safeBounds = config.bounds;
    List<Offset> safeVertices;
    if (config.vertices != null && config.vertices!.isNotEmpty) {
      safeVertices = List.from(config.vertices!);
    } else {
      safeVertices = [
        safeBounds.topLeft,
        safeBounds.topRight,
        safeBounds.bottomRight,
        safeBounds.bottomLeft,
      ];
    }
    final Offset safeStart =
        config.start ??
        (safeVertices.isNotEmpty ? safeVertices.first : safeBounds.topLeft);
    final Offset safeEnd =
        config.end ??
        (safeVertices.isNotEmpty && safeVertices.length > 1
            ? safeVertices.last
            : safeBounds.bottomRight);

    final shapeConfigMap = {
      'kind': config.kind.index,
      'bounds': {
        'left': safeBounds.left,
        'top': safeBounds.top,
        'width': safeBounds.width,
        'height': safeBounds.height,
      },
      'start': {'x': safeStart.dx, 'y': safeStart.dy},
      'end': {'x': safeEnd.dx, 'y': safeEnd.dy},
      'rotationDeg': config.rotationDeg,
      'eccentricity': config.eccentricity,
      'angleDeg': config.angleDeg,
      'strokeWidth': config.strokeWidth,
      'detail': config.detail,
      'fill': fill,
      'strokeStyle': config.strokeStyle.index,
      'vertices': safeVertices.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
      'data': config.data,
      'version': 3,
    };

    return <String, dynamic>{
      'shape': 'shapeCustom',
      'type': 'ShapeStroke',
      'i': pageIndex,
      'ty': toolId.id,
      'c': color.toARGB32(),
      'fc': fillColor.toARGB32(),
      'f': fill,
      'pe': pressureEnabled,
      'rot': rotationDeg,
      'shapeConfig': shapeConfigMap,
    }..addAll(options.toJson());
  }

  static ShapeConfig _parseLegacyShapeConfig(Map<String, dynamic> json) {
    double val(dynamic v) => toDoubleSafe(v) ?? 0.0;

    final kind = ShapeKind.values.firstWhere(
      (k) => k.name == json['k'],
      orElse: () => ShapeKind.rectangle,
    );
    final bounds = Rect.fromLTWH(
      val(json['rl']),
      val(json['rt']),
      val(json['rw']),
      val(json['rh']),
    );

    final sx = val(json['sx']);
    final sy = val(json['sy']);
    final start = (sx == 0 && sy == 0) ? bounds.topLeft : Offset(sx, sy);

    final ex = val(json['ex']);
    final ey = val(json['ey']);
    final end = (ex == 0 && ey == 0) ? bounds.bottomRight : Offset(ex, ey);

    return ShapeConfig(
      kind: kind,
      bounds: bounds,
      start: start,
      end: end,
      rotationDeg: val(json['rot']),
      eccentricity: val(json['ecc']),
      angleDeg: val(json['ang']),
      strokeWidth: val(json['w']),
      detail: toIntSafe(json['d']) ?? 12,
      fill: json['f'] ?? false,
    );
  }

  @override
  void shift(Offset offset) {
    _cachedPath = null;
    super.shift(offset);

    final newVerts = config.vertices?.map((v) => v + offset).toList();
    final newStart = config.start != null ? config.start! + offset : null;
    final newEnd = config.end != null ? config.end! + offset : null;

    config = config.copyWith(
      bounds: config.bounds.shift(offset),
      start: newStart,
      end: newEnd,
      vertices: newVerts,
    );
  }

  @override
  void rotate(double angleRad, Offset center) {
    _cachedPath = null;

    final cos = math.cos(angleRad);
    final sin = math.sin(angleRad);
    Offset rot(Offset p) => Offset(
      center.dx + (p.dx - center.dx) * cos - (p.dy - center.dy) * sin,
      center.dy + (p.dx - center.dx) * sin + (p.dy - center.dy) * cos,
    );

    if (_isMatrixRotatedShape(config.kind) &&
        (config.vertices == null ||
            config.vertices!.isEmpty ||
            !config.kind.isVertexEditable)) {
      final currentCenter = config.bounds.center;
      final newCenter = rot(currentCenter);
      final diff = newCenter - currentCenter;

      final newStart = config.start != null ? config.start! + diff : null;
      final newEnd = config.end != null ? config.end! + diff : null;
      final newVerts = config.vertices?.map((v) => v + diff).toList();

      config = config.copyWith(
        rotationDeg: (config.rotationDeg + angleRad * 180.0 / math.pi) % 360.0,
        bounds: config.bounds.shift(diff),
        start: newStart,
        end: newEnd,
        vertices: newVerts,
      );
    } else {
      final newStart = config.start != null ? rot(config.start!) : null;
      final newEnd = config.end != null ? rot(config.end!) : null;
      final newVerts = config.vertices?.map(rot).toList();

      Rect newBounds = config.bounds;
      List<Offset> allPoints = [];
      if (newStart != null) allPoints.add(newStart);
      if (newEnd != null) allPoints.add(newEnd);
      if (newVerts != null) allPoints.addAll(newVerts);

      if (allPoints.isNotEmpty) {
        double minX = allPoints.first.dx, maxX = allPoints.first.dx;
        double minY = allPoints.first.dy, maxY = allPoints.first.dy;
        for (final p in allPoints) {
          if (p.dx < minX) minX = p.dx;
          if (p.dx > maxX) maxX = p.dx;
          if (p.dy < minY) minY = p.dy;
          if (p.dy > maxY) maxY = p.dy;
        }
        if (minX == maxX) maxX += 1;
        if (minY == maxY) maxY += 1;
        newBounds = Rect.fromLTRB(minX, minY, maxX, maxY);
      } else {
        final newCenter = rot(config.bounds.center);
        newBounds = Rect.fromCenter(
          center: newCenter,
          width: config.bounds.width,
          height: config.bounds.height,
        );
      }

      config = config.copyWith(
        start: newStart,
        end: newEnd,
        vertices: newVerts,
        bounds: newBounds,
      );
    }

    _regeneratePoints();
  }

  @override
  void scale(double factor, Offset center) {
    if (factor == 1.0) return;
    _cachedPath = null;
    markPolygonNeedsUpdating();
    Offset scl(Offset p) => Offset(
      center.dx + (p.dx - center.dx) * factor,
      center.dy + (p.dy - center.dy) * factor,
    );

    final newStart = config.start != null ? scl(config.start!) : null;
    final newEnd = config.end != null ? scl(config.end!) : null;
    final newVertices = config.vertices?.map(scl).toList();

    final pointsForBounds = <Offset>[
      if (newStart != null) newStart,
      if (newEnd != null) newEnd,
      ...?newVertices,
    ];

    Rect newBounds;
    if (pointsForBounds.isNotEmpty) {
      double minX = pointsForBounds.first.dx;
      double maxX = pointsForBounds.first.dx;
      double minY = pointsForBounds.first.dy;
      double maxY = pointsForBounds.first.dy;
      for (final p in pointsForBounds) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }
      if (minX == maxX) maxX += 1;
      if (minY == maxY) maxY += 1;
      newBounds = Rect.fromLTRB(minX, minY, maxX, maxY);
    } else {
      final scaledCenter = Offset(
        center.dx + (config.bounds.center.dx - center.dx) * factor,
        center.dy + (config.bounds.center.dy - center.dy) * factor,
      );
      newBounds = Rect.fromCenter(
        center: scaledCenter,
        width: math.max(1, config.bounds.width * factor),
        height: math.max(1, config.bounds.height * factor),
      );
    }

    config = config.copyWith(
      bounds: newBounds,
      start: newStart,
      end: newEnd,
      vertices: newVertices,
      strokeWidth: config.strokeWidth * factor,
    );
    options.size *= factor;

    _regeneratePoints();
  }

  @override
  void toBinary(BinaryWriter writer) {
    writer.writeString(StrokeBinaryKeys.shape, 'shapeCustom');
    writer.writeInt(StrokeBinaryKeys.pageIndex, pageIndex);
    writer.writeInt(StrokeBinaryKeys.color, color.toARGB32());
    writer.writeInt(StrokeBinaryKeys.color + 1, fillColor.toARGB32());
    writer.writeBool(StrokeBinaryKeys.pressureEnabled, fill);

    final safeBounds = config.bounds;
    List<Offset> safeVertices;
    if (config.vertices != null && config.vertices!.isNotEmpty) {
      safeVertices = List.from(config.vertices!);
    } else {
      safeVertices = [
        safeBounds.topLeft,
        safeBounds.topRight,
        safeBounds.bottomRight,
        safeBounds.bottomLeft,
      ];
    }
    final Offset s =
        config.start ??
        (safeVertices.isNotEmpty ? safeVertices.first : safeBounds.topLeft);
    final Offset e =
        config.end ??
        (safeVertices.isNotEmpty && safeVertices.length > 1
            ? safeVertices.last
            : safeBounds.bottomRight);

    final packedData =
        '${config.kind.name};${s.dx};${s.dy};${e.dx};${e.dy};${config.strokeStyle.index}';
    writer.writeString(StrokeBinaryKeys.penType, packedData);

    writer.writeScaledFloat(StrokeBinaryKeys.left, safeBounds.left);
    writer.writeScaledFloat(StrokeBinaryKeys.top, safeBounds.top);
    writer.writeScaledFloat(StrokeBinaryKeys.width, safeBounds.width);
    writer.writeScaledFloat(StrokeBinaryKeys.height, safeBounds.height);

    writer.writeFloat(StrokeBinaryKeys.thinning, config.rotationDeg);
    writer.writeFloat(StrokeBinaryKeys.smoothing, config.eccentricity);
    writer.writeFloat(StrokeBinaryKeys.streamline, config.angleDeg);
    writer.writeFloat(
      StrokeBinaryKeys.endCustomTaper,
      config.detail.toDouble(),
    );
    writer.writeFloat(StrokeBinaryKeys.size, config.strokeWidth);

    final cps = ShapeGeometry.controlPointsOf(config);
    if (cps.isNotEmpty) {
      final packed = cps.map((p) => '${p.dx},${p.dy}').join(';');
      writer.writeString(StrokeBinaryKeys.shapeControlPoints, packed);
    }

    writer.writeKey(StrokeBinaryKeys.endOptions);
  }

  factory ShapeStroke.fromBinary(BinaryReader reader, {required HasSize page}) {
    int key = reader.readKey();
    int? pageIndex;
    Color? color, fillColor;
    bool? fill;
    String? packedData;
    String? controlPointsPacked;
    Rect bounds = Rect.zero;

    double rot = 0, ecc = 0, ang = 45, width = 3;
    int detail = 12;
    ShapeStrokeStyle strokeStyle = ShapeStrokeStyle.solid;

    while (key != StrokeBinaryKeys.endOptions) {
      switch (key) {
        case StrokeBinaryKeys.pageIndex:
          pageIndex = reader.readIntNoKey();
          break;
        case StrokeBinaryKeys.color:
          color = reader.readColor();
          break;
        case StrokeBinaryKeys.color + 1:
          fillColor = reader.readColor();
          break;
        case StrokeBinaryKeys.pressureEnabled:
          fill = reader.readBoolNoKey();
          break;
        case StrokeBinaryKeys.penType:
          packedData = reader.readStringNoKey();
          break;
        case StrokeBinaryKeys.shapeControlPoints:
          controlPointsPacked = reader.readStringNoKey();
          break;
        case StrokeBinaryKeys.left:
          bounds = Rect.fromLTWH(
            reader.readScaledFloat(),
            bounds.top,
            bounds.width,
            bounds.height,
          );
          break;
        case StrokeBinaryKeys.top:
          bounds = Rect.fromLTWH(
            bounds.left,
            reader.readScaledFloat(),
            bounds.width,
            bounds.height,
          );
          break;
        case StrokeBinaryKeys.width:
          bounds = Rect.fromLTWH(
            bounds.left,
            bounds.top,
            reader.readScaledFloat(),
            bounds.height,
          );
          break;
        case StrokeBinaryKeys.height:
          bounds = Rect.fromLTWH(
            bounds.left,
            bounds.top,
            bounds.width,
            reader.readScaledFloat(),
          );
          break;
        case StrokeBinaryKeys.cy:
          reader.readFloatNoKey();
          break;
        case StrokeBinaryKeys.r:
          reader.readFloatNoKey();
          break;
        case StrokeBinaryKeys.startCustomTaper:
          reader.readFloatNoKey();
          break;
        case StrokeBinaryKeys.size:
          width = reader.readFloatNoKey();
          break;
        case StrokeBinaryKeys.thinning:
          rot = reader.readFloatNoKey();
          break;
        case StrokeBinaryKeys.smoothing:
          ecc = reader.readFloatNoKey();
          break;
        case StrokeBinaryKeys.streamline:
          ang = reader.readFloatNoKey();
          break;
        case StrokeBinaryKeys.endCustomTaper:
          detail = reader.readFloatNoKey().toInt();
          break;
        case StrokeBinaryKeys.simulatePressure:
          reader.readBoolNoKey();
          break;
        case StrokeBinaryKeys.isComplete:
          reader.readBoolNoKey();
          break;
        case StrokeBinaryKeys.startTaperEnabled:
        case StrokeBinaryKeys.endTaperEnabled:
        case StrokeBinaryKeys.startCap:
        case StrokeBinaryKeys.endCap:
          reader.readBoolNoKey();
          break;
      }
      key = reader.readKey();
    }

    ShapeKind kind = ShapeKind.rectangle;
    Offset start = bounds.topLeft;
    Offset end = bounds.bottomRight;

    if (packedData != null) {
      if (packedData.contains(';')) {
        try {
          final parts = packedData.split(';');
          final kindName = parts[0];
          kind = ShapeKind.values.firstWhere(
            (k) => k.name == kindName,
            orElse: () => ShapeKind.rectangle,
          );

          if (parts.length >= 5) {
            start = Offset(double.parse(parts[1]), double.parse(parts[2]));
            end = Offset(double.parse(parts[3]), double.parse(parts[4]));
          }
          if (parts.length >= 6) {
            strokeStyle = shapeStrokeStyleFromJson(int.tryParse(parts[5]));
          }
        } catch (e) {
          print("Erro ao parsear ShapeStroke data: $e");
        }
      } else {
        kind = ShapeKind.values.firstWhere(
          (k) => k.name == packedData,
          orElse: () => ShapeKind.rectangle,
        );
      }
    }

    if (start == Offset.zero && end == Offset.zero && !bounds.isEmpty) {
      start = bounds.topLeft;
      end = bounds.bottomRight;
    }

    List<Offset>? loadedVerts;
    if (controlPointsPacked != null && controlPointsPacked.isNotEmpty) {
      loadedVerts = [];
      for (final part in controlPointsPacked.split(';')) {
        final xy = part.split(',');
        if (xy.length >= 2) {
          final x = double.tryParse(xy[0]);
          final y = double.tryParse(xy[1]);
          if (x != null && y != null) loadedVerts.add(Offset(x, y));
        }
      }
      if (loadedVerts.isEmpty) loadedVerts = null;
    }

    final stroke = ShapeStroke(
      color: color ?? Colors.black,
      fillColor: fillColor ?? (color ?? Colors.black).withOpacity(0.7),
      fill: fill ?? false,
      pressureEnabled: false,
      options: defaultOptions.copyWith(size: width),
      pageIndex: pageIndex ?? 0,
      page: page,
      toolId: ToolId.shapeTool,
      config: ShapeConfig(
        kind: kind,
        bounds: bounds,
        start: start,
        end: end,
        rotationDeg: rot,
        eccentricity: ecc,
        angleDeg: ang,
        strokeWidth: width,
        detail: detail,
        fill: fill ?? false,
        strokeStyle: strokeStyle,
        vertices: loadedVerts,
      ),
      shapeVertices: loadedVerts,
    );
    stroke.rotationDeg = rot;
    return stroke;
  }

  static void skipFromBinary(BinaryReader reader) {
    int key = reader.readKey();
    while (key != StrokeBinaryKeys.endOptions) {
      switch (key) {
        case StrokeBinaryKeys.pageIndex:
          reader.readIntNoKey();
          break;
        case StrokeBinaryKeys.color:
        case StrokeBinaryKeys.color + 1:
          reader.readColor();
          break;
        case StrokeBinaryKeys.pressureEnabled:
          reader.readBoolNoKey();
          break;
        case StrokeBinaryKeys.penType:
        case StrokeBinaryKeys.shapeControlPoints:
          reader.readStringNoKey();
          break;
        case StrokeBinaryKeys.left:
        case StrokeBinaryKeys.top:
        case StrokeBinaryKeys.width:
        case StrokeBinaryKeys.height:
          reader.readScaledFloat();
          break;
        case StrokeBinaryKeys.cy:
        case StrokeBinaryKeys.r:
        case StrokeBinaryKeys.startCustomTaper:
        case StrokeBinaryKeys.size:
        case StrokeBinaryKeys.thinning:
        case StrokeBinaryKeys.smoothing:
        case StrokeBinaryKeys.streamline:
        case StrokeBinaryKeys.endCustomTaper:
          reader.readFloatNoKey();
          break;
        case StrokeBinaryKeys.simulatePressure:
        case StrokeBinaryKeys.isComplete:
        case StrokeBinaryKeys.startTaperEnabled:
        case StrokeBinaryKeys.endTaperEnabled:
        case StrokeBinaryKeys.startCap:
        case StrokeBinaryKeys.endCap:
          reader.readBoolNoKey();
          break;
        default:
          break;
      }
      key = reader.readKey();
    }
  }

  Path get shapePath {
    if (_cachedPath != null) return _cachedPath!;
    _cachedPath = _buildPath(config);
    return _cachedPath!;
  }

  /// Outline path used for stroking (solid, dashed, or dotted).
  Path get strokeDrawPath {
    final path = shapePath;
    final w = options.size;
    switch (config.strokeStyle) {
      case ShapeStrokeStyle.solid:
        return path;
      case ShapeStrokeStyle.dashed:
        final on = math.max(6.0, w * 2.5);
        final off = math.max(4.0, w * 2.0);
        return dashPath(
          path,
          dashArray: CircularIntervalList<double>([on, off]),
        );
      case ShapeStrokeStyle.dotted:
        final dot = math.max(1.5, w * 0.65);
        final gap = math.max(3.0, w * 2.2);
        return dashPath(
          path,
          dashArray: CircularIntervalList<double>([dot, gap]),
        );
      default:
        return path;
    }
  }

  ShapeStroke scaled(double factor, Offset center) {
    if (factor == 1.0) return this;
    final n = copy();
    n.scale(factor, center);
    return n;
  }

  @override
  bool get isEmpty =>
      config.bounds.width == 0 &&
      config.bounds.height == 0 &&
      (config.vertices == null || config.vertices!.isEmpty);

  @override
  get vertices => null;

  @override
  List<Offset> getPolygon({required StrokeQuality quality}) {
    return _defaultPolygon();
  }

  List<Offset> _defaultPolygon() {
    final p = shapePath;
    final m = p.computeMetrics();
    final l = <Offset>[];
    for (final me in m) {
      for (double d = 0; d < me.length; d += 5)
        l.add(me.getTangentForOffset(d)!.position);
    }
    return l;
  }

  @override
  Path getPath(List<Offset> polygon, {bool smooth = true}) {
    return shapePath;
  }

  @override
  bool contains(Offset position) {
    if (isEmpty) return false;
    if (fill && shapePath.contains(position)) return true;
    for (final p in points) {
      if ((Offset(p.x, p.y) - position).distance <
          math.max(10, options.size + 5))
        return true;
    }
    return false;
  }

  @override
  void addPoint(Offset point, [double? pressure, Duration? timestamp]) {
    super.addPoint(point, pressure, timestamp);
    // Use the first recorded point as the fixed start
    final start =
        config.start ??
        (points.isNotEmpty ? Offset(points.first.x, points.first.y) : point);

    // Mutate the private _config to skip the setter's _regeneratePoints() wipeout
    _config = _config.copyWith(
      start: start,
      end: point,
      bounds: Rect.fromPoints(start, point),
    );

    _cachedPath = null;
    markPolygonNeedsUpdating();
  }

  @override
  void popFirstPoint() {
    super.popFirstPoint();
  }

  @override
  void optimisePoints({double thresholdMultiplier = 0}) {
    _regeneratePoints();
  }

  @override
  ShapeStroke copy() {
    return ShapeStroke(
      color: color,
      pressureEnabled: pressureEnabled,
      options: options.copyWith(),
      pageIndex: pageIndex,
      page: page,
      toolId: toolId,
      config: config,
      fill: fill,
      fillColor: fillColor,
      shapeVertices: shapeVertices,
    )..rotationDeg = rotationDeg;
  }

  Path _buildPath(ShapeConfig cfg) {
    final rect = cfg.bounds;
    final center = rect.center;
    final verts = cfg.vertices;

    final start = cfg.start ?? rect.topLeft;
    final end = cfg.end ?? rect.bottomRight;

    Path base;

    switch (cfg.kind) {
      case ShapeKind.rectangle:
        if (verts != null && verts.length >= 4) {
          base = Path()
            ..moveTo(verts[0].dx, verts[0].dy)
            ..lineTo(verts[1].dx, verts[1].dy)
            ..lineTo(verts[2].dx, verts[2].dy)
            ..lineTo(verts[3].dx, verts[3].dy)
            ..close();
        } else if (verts != null && verts.length >= 2) {
          base = Path()..addRect(Rect.fromPoints(verts.first, verts.last));
        } else {
          base = Path()..addRect(rect);
        }
        break;
      case ShapeKind.circle:
        {
          final pts = verts ?? const <Offset>[];
          final params = ShapeGeometry.ellipseParamsFromControlPoints(pts);
          if (params != null) {
            final r = (params.rx + params.ry) / 2;
            base = _orientedOvalPath(params.center, r, r, 0);
          } else {
            base = _highQualityOvalPath(
              Rect.fromCircle(
                center: center,
                radius: math.min(rect.width, rect.height) / 2,
              ),
            );
          }
        }
        break;
      case ShapeKind.ellipse:
        {
          final pts = verts ?? const <Offset>[];
          final params = ShapeGeometry.ellipseParamsFromControlPoints(pts);
          if (params != null) {
            base = _orientedOvalPath(
              params.center,
              params.rx,
              params.ry,
              params.angleRad,
            );
          } else {
            base = _highQualityOvalPath(rect);
          }
        }
        break;
      case ShapeKind.polygon:
        if (verts != null && verts.length >= 3) {
          base = Path()
            ..moveTo(verts.first.dx, verts.first.dy);
          for (var i = 1; i < verts.length; i++) {
            base.lineTo(verts[i].dx, verts[i].dy);
          }
          base.close();
        } else {
          base = _regularPolygonPath(rect, cfg);
        }
        break;
      case ShapeKind.star:
        if (verts != null && verts.length >= 3) {
          base = Path()
            ..moveTo(verts.first.dx, verts.first.dy);
          for (var i = 1; i < verts.length; i++) {
            base.lineTo(verts[i].dx, verts[i].dy);
          }
          base.close();
        } else {
          base = _starPath(rect);
        }
        break;

      case ShapeKind.line:
        base = Path()
          ..moveTo(start.dx, start.dy)
          ..lineTo(end.dx, end.dy);
        break;
      case ShapeKind.arrow:
        base = _arrowPath(start, end, false);
        break;
      case ShapeKind.doubleArrow:
        base = _arrowPath(start, end, true);
        break;
      case ShapeKind.parabola:
        base = _parabolaPath(start, end, cfg);
        break;

      case ShapeKind.triangleIsosceles:
        if (verts != null && verts.length >= 3) {
          base = _triangleFromVertices(verts.take(3).toList());
        } else if (cfg.data['equilateral'] == true) {
          base = _equilateralTrianglePath(
            rect,
            upward: cfg.data['upward'] != false,
          );
        } else {
          base = _triangleIsoscelesPath(start, end);
        }
        break;
      case ShapeKind.triangleRight:
        if (verts != null && verts.length >= 3) {
          base = _triangleFromVertices(verts.take(3).toList());
        } else {
          base = _triangleRightPath(start, end);
        }
        break;
      case ShapeKind.cube:
        base = _cubePathFixed(rect, start, end);
        break;
      case ShapeKind.cylinder:
        base = _cylinderPathRobust(rect);
        break;
      case ShapeKind.sphere:
        base = _spherePath(rect);
        break;
      case ShapeKind.halfSphere:
        base = _halfSpherePath3DFixed(rect, start, end);
        break;
      case ShapeKind.pendulum:
        base = _pendulumPath(start, end);
        break;
      case ShapeKind.spring:
        base = _springPath(start, end);
        break;
      case ShapeKind.fixedEnd:
        base = _fixedEndPath(start, end);
        break;
      case ShapeKind.harmonicOscillator:
        base = _harmonicOscillatorPathFixed(start, end);
        break;
      case ShapeKind.coordinateSystem:
        base = _coordinateSystemPath(rect);
        break;

      case ShapeKind.nabla:
        base = Path()
          ..moveTo(rect.topLeft.dx, rect.topLeft.dy)
          ..lineTo(rect.topRight.dx, rect.topRight.dy)
          ..lineTo(rect.center.dx, rect.bottom)
          ..close();
        break;
      case ShapeKind.summatory:
        base = _summatoryPath(rect);
        break;
      case ShapeKind.productory:
        base = _productoryPath(rect);
        break;
      case ShapeKind.leftBracket:
        base = _bracketPath(rect, isLeft: true);
        break;
      case ShapeKind.rightBracket:
        base = _bracketPath(rect, isLeft: false);
        break;
      case ShapeKind.leftAngleBracket:
        base = _angleBracketPath(rect, isLeft: true);
        break;
      case ShapeKind.rightAngleBracket:
        base = _angleBracketPath(rect, isLeft: false);
        break;
      case ShapeKind.leftBrace:
        base = _bracePath(rect, isLeft: true);
        break;
      case ShapeKind.rightBrace:
        base = _bracePath(rect, isLeft: false);
        break;
      case ShapeKind.infinity:
        base = _infinityPath(rect);
        break;

      default:
        if (cfg.kind.name == 'coordinateSystem3D') {
          base = _coordinateSystem3DPath(rect);
        } else {
          base = Path()..addRect(rect);
        }
    }

    if (fill &&
        const {
          ShapeKind.cube,
          ShapeKind.harmonicOscillator,
        }.contains(cfg.kind)) {
      base.fillType = PathFillType.evenOdd;
    }

    if (cfg.rotationDeg != 0) {
      final orientationBakedInVerts = verts != null &&
          verts.isNotEmpty &&
          const {
            ShapeKind.rectangle,
            ShapeKind.ellipse,
            ShapeKind.circle,
            ShapeKind.triangleIsosceles,
            ShapeKind.triangleRight,
            ShapeKind.polygon,
            ShapeKind.star,
            ShapeKind.line,
            ShapeKind.arrow,
            ShapeKind.doubleArrow,
          }.contains(cfg.kind);
      if (!orientationBakedInVerts) {
        final rads = cfg.rotationDeg * math.pi / 180;
        base = base.transform(
          (vmath.Matrix4.identity()
                ..translate(center.dx, center.dy)
                ..rotateZ(rads)
                ..translate(-center.dx, -center.dy))
              .storage,
        );
      }
    }
    return base;
  }

  Path _cubePathFixed(
    Rect rect,
    Offset? start,
    Offset? end, {
    bool fill = true,
  }) {
    final p = Path()..fillType = PathFillType.nonZero;

    final drag = (start != null && end != null) ? end - start : null;
    final baseDepth = math.min(rect.width, rect.height) * 0.28;
    final depth = baseDepth.clamp(10.0, 80.0);

    final dirX = drag == null || drag.dx >= 0 ? 1.0 : -1.0;
    final dirY = drag == null || drag.dy >= 0 ? -1.0 : 1.0;

    final dx = depth * dirX;
    final dy = depth * 0.72 * dirY;

    final front = rect;
    final back = rect.translate(dx, dy);

    final showTopFace = dy < 0;
    final showRightFace = dx > 0;

    p.addPolygon([
      front.topLeft,
      front.topRight,
      front.bottomRight,
      front.bottomLeft,
    ], true);

    if (showTopFace) {
      p.addPolygon([
        front.topLeft,
        back.topLeft,
        back.topRight,
        front.topRight,
      ], true);
    } else {
      p.addPolygon([
        front.bottomLeft,
        front.bottomRight,
        back.bottomRight,
        back.bottomLeft,
      ], true);
    }

    if (showRightFace) {
      p.addPolygon([
        front.topRight,
        back.topRight,
        back.bottomRight,
        front.bottomRight,
      ], true);
    } else {
      p.addPolygon([
        front.topLeft,
        front.bottomLeft,
        back.bottomLeft,
        back.topLeft,
      ], true);
    }

    if (!fill) {
      final hiddenBackCorner = Offset(
        showRightFace ? back.left : back.right,
        showTopFace ? back.bottom : back.top,
      );

      final hiddenFrontCorner = Offset(
        showRightFace ? front.left : front.right,
        showTopFace ? front.bottom : front.top,
      );
      final adjacentBack1 = Offset(
        hiddenBackCorner.dx,
        showTopFace ? back.top : back.bottom,
      );
      final adjacentBack2 = Offset(
        showRightFace ? back.right : back.left,
        hiddenBackCorner.dy,
      );

      p.moveTo(hiddenFrontCorner.dx, hiddenFrontCorner.dy);
      p.lineTo(hiddenBackCorner.dx, hiddenBackCorner.dy);

      p.moveTo(adjacentBack1.dx, adjacentBack1.dy);
      p.lineTo(hiddenBackCorner.dx, hiddenBackCorner.dy);

      p.moveTo(adjacentBack2.dx, adjacentBack2.dy);
      p.lineTo(hiddenBackCorner.dx, hiddenBackCorner.dy);
    }

    return p;
  }

  Path _halfSpherePath3DFixed(Rect rect, Offset start, Offset end) {
    final p = Path();
    final center = rect.center;

    final isTop = start.dy < end.dy;
    final baseHeight = math.min(rect.width, rect.height) * 0.3;

    final baseCenter = isTop
        ? Offset(center.dx, rect.bottom - baseHeight / 2)
        : Offset(center.dx, rect.top + baseHeight / 2);

    final baseRect = Rect.fromCenter(
      center: baseCenter,
      width: rect.width,
      height: baseHeight,
    );

    if (!fill) p.addOval(baseRect);

    final domePath = Path();

    final domeHeight = isTop
        ? (baseCenter.dy - rect.top)
        : (rect.bottom - baseCenter.dy);

    final domeRect = Rect.fromCenter(
      center: baseCenter,
      width: rect.width,
      height: domeHeight * 2,
    );

    domePath.addArc(domeRect, isTop ? -math.pi : 0, math.pi);
    domePath.close();

    p.addPath(domePath, Offset.zero);
    if (fill) {
      p.addArc(baseRect, 0, math.pi);
    }

    return p;
  }

  Path _harmonicOscillatorPathFixed(Offset start, Offset end) {
    final p = Path();
    final boxSize = 30.0;

    final dir = (end - start);
    final angle = dir.direction;
    final massCenter = end;

    final connectionPoint =
        massCenter - Offset(math.cos(angle), math.sin(angle)) * (boxSize / 2);

    p.addRect(
      Rect.fromCenter(center: massCenter, width: boxSize, height: boxSize),
    );

    _drawSpringInternal(p, start, connectionPoint, loopBack: fill);

    return p;
  }

  void _drawSpringInternal(
    Path path,
    Offset start,
    Offset end, {
    bool loopBack = false,
  }) {
    final diff = end - start;
    final dist = diff.distance;
    if (dist < 1) {
      path.moveTo(start.dx, start.dy);
      return;
    }

    final angle = diff.direction;
    final zigs = (dist / 10).floor().clamp(5, 50);
    final width = 15.0;
    final normal = Offset(-math.sin(angle), math.cos(angle));

    final List<Offset> points = [];
    points.add(start);

    for (int i = 0; i <= zigs; i++) {
      final t = i / zigs;
      final centerOnLine = Offset.lerp(start, end, t)!;
      final offset = (i % 2 == 0 ? 1 : -1) * width;

      if (i == 0 || i == zigs) {
        points.add(centerOnLine);
      } else {
        final zigPoint = centerOnLine + (normal * offset);
        points.add(zigPoint);
      }
    }

    path.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    if (loopBack) {
      for (int i = points.length - 2; i >= 0; i--) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      path.close();
    }
  }

  Path _cylinderPathRobust(Rect rect) {
    final p = Path();
    final topHeight = rect.height * 0.20;

    final topOval = Rect.fromLTWH(rect.left, rect.top, rect.width, topHeight);
    final bottomOval = Rect.fromLTWH(
      rect.left,
      rect.bottom - topHeight,
      rect.width,
      topHeight,
    );

    if (fill) {
      final bodyTopY = rect.top + topHeight * 0.5;
      final bodyBottomY = rect.bottom - topHeight * 0.5;
      p.moveTo(rect.left, bodyTopY);
      p.lineTo(rect.left, bodyBottomY);
      p.arcTo(bottomOval, math.pi, -math.pi, false);
      p.lineTo(rect.right, bodyTopY);
      p.arcTo(topOval, 0, -math.pi, false);
      p.close();
    } else {
      p.addOval(topOval);
      p.moveTo(rect.left, topOval.center.dy);
      p.lineTo(rect.left, bottomOval.center.dy);
      p.moveTo(rect.right, topOval.center.dy);
      p.lineTo(rect.right, bottomOval.center.dy);
      p.addArc(bottomOval, 0, math.pi);
    }

    return p;
  }

  Path _coordinateSystem3DPath(Rect rect) {
    final p = Path();
    final center = rect.center;
    final radius = math.min(rect.width, rect.height) / 2 * 0.85;
    final zEnd = center + Offset(0, -radius);
    final xEnd =
        center +
        Offset(
          radius * math.cos(5 * math.pi / 6),
          radius * math.sin(5 * math.pi / 6),
        );

    final yEnd =
        center +
        Offset(radius * math.cos(math.pi / 6), radius * math.sin(math.pi / 6));

    _drawArrowInternal(p, center, zEnd);
    _drawArrowInternal(p, center, xEnd);
    _drawArrowInternal(p, center, yEnd);

    return p;
  }

  Path _arrowPath(Offset start, Offset end, bool doubleHead) {
    final p = Path();
    p.moveTo(start.dx, start.dy);
    p.lineTo(end.dx, end.dy);
    final headSize = math.min(
      (end - start).distance * 0.25,
      30.0 + super.options.size * 2,
    );
    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    Offset head(Offset pt, double ang, bool rev) {
      final dir = rev ? -1 : 1;
      return pt +
          Offset(
            -headSize * math.cos(ang - dir * math.pi / 6),
            -headSize * math.sin(ang - dir * math.pi / 6),
          );
    }

    final l1 = head(end, angle, false);
    final r1 = head(end, angle, true);
    p.moveTo(end.dx, end.dy);
    p.lineTo(l1.dx, l1.dy);
    p.moveTo(end.dx, end.dy);
    p.lineTo(r1.dx, r1.dy);
    if (doubleHead) {
      final l2 = head(start, angle + math.pi, true);
      final r2 = head(start, angle + math.pi, false);
      p.moveTo(start.dx, start.dy);
      p.lineTo(l2.dx, l2.dy);
      p.moveTo(start.dx, start.dy);
      p.lineTo(r2.dx, r2.dy);
    }
    return p;
  }

  Path _triangleIsoscelesPath(Offset start, Offset end) {
    final p = Path();
    final bl = Offset(math.min(start.dx, end.dx), math.max(start.dy, end.dy));
    final br = Offset(math.max(start.dx, end.dx), math.max(start.dy, end.dy));
    final apex = Offset((bl.dx + br.dx) / 2, math.min(start.dy, end.dy));
    p.moveTo(bl.dx, bl.dy);
    p.lineTo(br.dx, br.dy);
    p.lineTo(apex.dx, apex.dy);
    p.close();
    return p;
  }

  Path _triangleRightPath(Offset start, Offset end) {
    final p = Path();
    final rightAngle = start;
    final baseEnd = Offset(end.dx, start.dy);
    final heightEnd = Offset(start.dx, end.dy);
    p.moveTo(rightAngle.dx, rightAngle.dy);
    p.lineTo(baseEnd.dx, baseEnd.dy);
    p.lineTo(heightEnd.dx, heightEnd.dy);
    p.close();
    return p;
  }

  Path _highQualityOvalPath(Rect rect) {
    return _orientedOvalPath(
      rect.center,
      rect.width / 2,
      rect.height / 2,
      0,
    );
  }

  Path _orientedOvalPath(
    Offset center,
    double rx,
    double ry,
    double angleRad,
  ) {
    final p = Path();
    const n = 64;
    final cosA = math.cos(angleRad);
    final sinA = math.sin(angleRad);
    for (int i = 0; i < n; i++) {
      final t0 = 2 * math.pi * i / n;
      final t1 = 2 * math.pi * (i + 1) / n;
      Offset pt(double t) {
        final lx = rx * math.cos(t);
        final ly = ry * math.sin(t);
        return Offset(
          center.dx + lx * cosA - ly * sinA,
          center.dy + lx * sinA + ly * cosA,
        );
      }

      final p0 = pt(t0);
      final p1 = pt(t1);
      if (i == 0) p.moveTo(p0.dx, p0.dy);
      p.lineTo(p1.dx, p1.dy);
    }
    p.close();
    return p;
  }

  Path _starPath(Rect rect) {
    const n = 5;
    const innerRatio = 0.4;
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final r = math.min(rect.width, rect.height) / 2;
    final p = Path();
    for (int i = 0; i < n * 2; i++) {
      final angle = -math.pi / 2 + (2 * math.pi * i / (n * 2));
      final radius = i.isEven ? r : r * innerRatio;
      final x = cx + radius * math.cos(angle);
      final y = cy + radius * math.sin(angle);
      if (i == 0)
        p.moveTo(x, y);
      else
        p.lineTo(x, y);
    }
    p.close();
    return p;
  }

  Path _equilateralTrianglePath(Rect rect, {bool upward = true}) {
    final cx = rect.center.dx;
    final w = rect.width;
    final h = rect.height;
    final sqrt3 = math.sqrt(3);
    final side = math.min(w, h * 2 / sqrt3);
    final triHeight = side * sqrt3 / 2;
    final halfBase = side / 2;
    final p = Path();
    if (upward) {
      p.moveTo(cx, rect.bottom - triHeight);
      p.lineTo(cx + halfBase, rect.bottom);
      p.lineTo(cx - halfBase, rect.bottom);
    } else {
      p.moveTo(cx, rect.top + triHeight);
      p.lineTo(cx - halfBase, rect.top);
      p.lineTo(cx + halfBase, rect.top);
    }
    p.close();
    return p;
  }

  Path _triangleFromVertices(List<Offset> verts) {
    final p = Path();
    p.moveTo(verts[0].dx, verts[0].dy);
    p.lineTo(verts[1].dx, verts[1].dy);
    p.lineTo(verts[2].dx, verts[2].dy);
    p.close();
    return p;
  }

  Path _infinityPath(Rect rect) {
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final w = rect.width * 0.46;
    final h = rect.height * 0.46;

    final p = Path();
    p.moveTo(cx, cy);
    p.cubicTo(cx + w * 0.5, cy - h, cx + w, cy - h, cx + w, cy);
    p.cubicTo(cx + w, cy + h, cx + w * 0.5, cy + h, cx, cy);
    p.cubicTo(cx - w * 0.5, cy - h, cx - w, cy - h, cx - w, cy);
    p.cubicTo(cx - w, cy + h, cx - w * 0.5, cy + h, cx, cy);
    p.close();

    return p;
  }

  Path _summatoryPath(Rect rect) {
    final l = rect.left;
    final r = rect.right;
    final t = rect.top;
    final b = rect.bottom;
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final p = Path();
    p.moveTo(r, t);
    p.lineTo(l, t);
    p.lineTo(cx, cy);
    p.lineTo(l, b);
    p.lineTo(r, b);
    return p;
  }

  Path _productoryPath(Rect rect) {
    final l = rect.left;
    final r = rect.right;
    final t = rect.top;
    final b = rect.bottom;
    final overhang = math.max(4, rect.width * 0.1);
    final p = Path();
    p.moveTo(l, b);
    p.lineTo(l, t);
    p.lineTo(l - overhang, t);
    p.lineTo(r + overhang, t);
    p.lineTo(r, t);
    p.lineTo(r, b);
    return p;
  }

  Path _bracketPath(Rect rect, {required bool isLeft}) {
    final l = rect.left;
    final r = rect.right;
    final t = rect.top;
    final b = rect.bottom;
    final w = rect.width;
    final h = rect.height;
    final serifLen = math.max(3, math.min(w * 0.6, h * 0.2));
    final p = Path();
    if (isLeft) {
      p.moveTo(l + serifLen, t);
      p.lineTo(l, t);
      p.lineTo(l, b);
      p.lineTo(l + serifLen, b);
    } else {
      p.moveTo(r - serifLen, t);
      p.lineTo(r, t);
      p.lineTo(r, b);
      p.lineTo(r - serifLen, b);
    }
    return p;
  }

  Path _angleBracketPath(Rect rect, {required bool isLeft}) {
    final l = rect.left;
    final r = rect.right;
    final t = rect.top;
    final b = rect.bottom;
    final cy = rect.center.dy;
    final p = Path();
    if (isLeft) {
      p.moveTo(r, t);
      p.lineTo(l, cy);
      p.lineTo(r, b);
    } else {
      p.moveTo(l, t);
      p.lineTo(r, cy);
      p.lineTo(l, b);
    }
    return p;
  }

  Path _bracePath(Rect rect, {required bool isLeft}) {
    final w = rect.width;
    final h = rect.height;
    final l = rect.left;
    final r = rect.right;
    final t = rect.top;
    final b = rect.bottom;
    final cy = rect.center.dy;

    final tipX = isLeft ? r : l;
    final beakX = isLeft ? l : r;
    final spineX = isLeft ? l + w * 0.5 : r - w * 0.5;

    final dir = isLeft ? -1 : 1;

    final p = Path();

    p.moveTo(tipX, t);

    p.cubicTo(
      tipX + dir * w * 0.6,
      t,
      spineX,
      t + h * 0.05,
      spineX,
      t + h * 0.2,
    );

    p.cubicTo(spineX, cy - h * 0.1, spineX, cy, beakX, cy);

    p.cubicTo(spineX, cy, spineX, cy + h * 0.1, spineX, b - h * 0.2);

    p.cubicTo(spineX, b - h * 0.05, tipX + dir * w * 0.6, b, tipX, b);

    return p;
  }

  Path _regularPolygonPath(Rect rect, ShapeConfig cfg) {
    final p = Path();
    final center = rect.center;
    final radius = math.min(rect.width, rect.height) / 2;
    final sides = cfg.detail.clamp(3, 12).toInt();

    for (int i = 0; i < sides; i++) {
      final angle = -math.pi / 2 + (2 * math.pi * i / sides);
      final vertex = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      if (i == 0) {
        p.moveTo(vertex.dx, vertex.dy);
      } else {
        p.lineTo(vertex.dx, vertex.dy);
      }
    }
    p.close();
    return p;
  }

  Path _coordinateSystemPath(Rect rect) {
    final p = Path();

    final paddingX = rect.width * 0.1;
    final paddingY = rect.height * 0.1;

    _drawArrowInternal(
      p,
      Offset(rect.center.dx, rect.bottom - paddingY),
      Offset(rect.center.dx, rect.top + paddingY),
    );

    _drawArrowInternal(
      p,
      Offset(rect.left + paddingX, rect.center.dy),
      Offset(rect.right - paddingX, rect.center.dy),
    );

    return p;
  }

  void _drawArrowInternal(Path path, Offset start, Offset end) {
    path.moveTo(start.dx, start.dy);
    path.lineTo(end.dx, end.dy);
    final headSize = math.min((end - start).distance * 0.25, 15.0);
    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    path.moveTo(end.dx, end.dy);
    path.lineTo(
      end.dx - headSize * math.cos(angle - math.pi / 6),
      end.dy - headSize * math.sin(angle - math.pi / 6),
    );
    path.moveTo(end.dx, end.dy);
    path.lineTo(
      end.dx - headSize * math.cos(angle + math.pi / 6),
      end.dy - headSize * math.sin(angle + math.pi / 6),
    );
  }

  Path _parabolaPath(Offset start, Offset end, ShapeConfig cfg) {
    final p = Path();
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final nx = -dy;
    final ny = dx;
    final h = (cfg.eccentricity.clamp(0.0, 0.9) + 0.1) * cfg.bounds.height;
    const steps = 32;
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final lx = start.dx + t * dx;
      final ly = start.dy + t * dy;
      final curve = 4 * t * (1 - t) * h;
      final x =
          lx +
          (nx != 0 || ny != 0
              ? (nx / math.sqrt(nx * nx + ny * ny)) * curve
              : 0);
      final y =
          ly +
          (nx != 0 || ny != 0
              ? (ny / math.sqrt(nx * nx + ny * ny)) * curve
              : 0);
      if (i == 0)
        p.moveTo(x, y);
      else
        p.lineTo(x, y);
    }
    return p;
  }

  Path _pendulumPath(Offset start, Offset end) {
    final p = Path();
    const pivotWidth = 40.0;

    final supportLeft = start + const Offset(-pivotWidth / 2, 0);
    final supportRight = start + const Offset(pivotWidth / 2, 0);
    p.moveTo(supportLeft.dx, supportLeft.dy);
    p.lineTo(supportRight.dx, supportRight.dy);
    for (double i = -pivotWidth / 2; i <= pivotWidth / 2; i += 8) {
      final base = start + Offset(i, 0);
      final hatchTip = base + const Offset(6, -8);
      p.moveTo(base.dx, base.dy);
      p.lineTo(hatchTip.dx, hatchTip.dy);
    }

    p.addOval(Rect.fromCircle(center: start, radius: 3.0));

    p.moveTo(start.dx, start.dy);
    p.lineTo(end.dx, end.dy);

    final massRadius = math
        .min(15.0, (end - start).distance * 0.1)
        .clamp(5.0, 25.0);
    p.addOval(Rect.fromCircle(center: end, radius: massRadius));

    return p;
  }

  Path _springPath(Offset start, Offset end) {
    final p = Path();
    _drawSpringInternal(p, start, end, loopBack: false);
    return p;
  }

  Path _spherePath(Rect rect, {bool fill = true}) {
    final p = Path();
    final center = rect.center;
    final radius = math.min(rect.width, rect.height) / 2;

    final outlineRect = Rect.fromCircle(center: center, radius: radius);
    p.addOval(outlineRect);

    final equatorRect = Rect.fromCenter(
      center: center,
      width: radius * 2,
      height: radius * 0.6,
    );

    final meridianRect = Rect.fromCenter(
      center: center,
      width: radius * 0.6,
      height: radius * 2,
    );

    if (fill) {
      p.addArc(equatorRect, 0, math.pi);
      p.addArc(meridianRect, -math.pi / 2, math.pi);
    } else {
      p.addOval(equatorRect);
      p.addOval(meridianRect);
    }

    return p;
  }

  Path _fixedEndPath(Offset start, Offset end) {
    final p = Path();
    p.moveTo(start.dx, start.dy);
    p.lineTo(end.dx, end.dy);

    final dir = end - start;
    final length = dir.distance;
    if (length < 1) return p;
    final angle = dir.direction;

    final hatchAngle = angle + math.pi * 0.75;

    const markLength = 10.0;
    final hatchOffset =
        Offset(math.cos(hatchAngle), math.sin(hatchAngle)) * markLength;

    const markSpacing = 10.0;

    for (double d = 0; d <= length; d += markSpacing) {
      final t = d / length;
      final point = Offset.lerp(start, end, t)!;
      final markEnd = point + hatchOffset;

      p.moveTo(point.dx, point.dy);
      p.lineTo(markEnd.dx, markEnd.dy);
    }

    return p;
  }
}
