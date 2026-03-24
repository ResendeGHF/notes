// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/binary_writer.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/dynamic_extensions.dart';
import 'package:saber/data/tools/_tool.dart';

class CircleStroke extends Stroke {
  Offset center;
  double radius;

  CircleStroke({
    required super.color,
    required super.pressureEnabled,
    required super.options,
    required super.pageIndex,
    required super.page,
    required super.toolId,
    required this.center,
    required this.radius,
  }) {
    options.isComplete = true;
  }

  factory CircleStroke.fromJson(
    Map<String, dynamic> json, {
    required int fileVersion,
    required int pageIndex,
    required HasSize page,
  }) {
    assert(json['shape'] == 'circle');
    assert(json['i'] == pageIndex || json['i'] == null);

    final Color color;
    switch (json['c']) {
      case (final int value):
        color = Color(value);
      case (final Int64 value):
        color = Color(value.toInt());
      case null:
        color = Stroke.defaultColor;
      default:
        throw Exception(
          'Invalid color value: (${json['c'].runtimeType}) ${json['c']}',
        );
    }

    return CircleStroke(
      color: color,
      pressureEnabled: json['pe'] ?? Stroke.defaultPressureEnabled,
      options: StrokeOptions.fromJson(json),
      pageIndex: pageIndex,
      page: page,
      toolId: .parsePenType(json['ty'], fallback: .shapePen),
      center: Offset(
        toDoubleSafe(json['cx']) ?? 0,
        toDoubleSafe(json['cy']) ?? 0,
      ),
      radius: toDoubleSafe(json['r']) ?? 0,
    );
  }

  @override
  void toBinary(BinaryWriter writer) {
    writer.writeString(StrokeBinaryKeys.shape, 'circle');
    writer.writeInt(StrokeBinaryKeys.pageIndex, pageIndex);
    writer.writeScaledFloat(StrokeBinaryKeys.cx, center.dx);
    writer.writeScaledFloat(StrokeBinaryKeys.cy, center.dy);
    writer.writeScaledFloat(StrokeBinaryKeys.r, radius);
    writer.writeBool(StrokeBinaryKeys.pressureEnabled, pressureEnabled);
    writer.writeInt(StrokeBinaryKeys.color, color.toARGB32());
    BinaryOptions().optionsToBinary(writer, options);
  }

  factory CircleStroke.fromBinary(
    BinaryReader reader, {
    required HasSize page,
  }) {
    int key;
    int? pageIndex;
    Offset? center;
    double? radius;
    bool? pressureEnabled;
    Color? color;

    key = reader.readKey();
    while (key != StrokeBinaryKeys.size &&
        key != StrokeBinaryKeys.thinning &&
        key != StrokeBinaryKeys.smoothing &&
        key != StrokeBinaryKeys.streamline &&
        key != StrokeBinaryKeys.simulatePressure &&
        key != StrokeBinaryKeys.isComplete &&
        key != StrokeBinaryKeys.startTaperEnabled &&
        key != StrokeBinaryKeys.startCustomTaper &&
        key != StrokeBinaryKeys.startCap &&
        key != StrokeBinaryKeys.endTaperEnabled &&
        key != StrokeBinaryKeys.endCustomTaper &&
        key != StrokeBinaryKeys.endCap &&
        key != StrokeBinaryKeys.endOptions) {
      switch (key) {
        case StrokeBinaryKeys.pageIndex:
          pageIndex = reader.readIntNoKey();
          break;
        case StrokeBinaryKeys.cx:
          center = Offset(
            reader.readScaledFloat(),
            center?.dy ?? 0,
          );
          break;
        case StrokeBinaryKeys.cy:
          center = Offset(center?.dx ?? 0, reader.readScaledFloat());
          break;
        case StrokeBinaryKeys.r:
          radius = reader.readScaledFloat();
          break;
        case StrokeBinaryKeys.pressureEnabled:
          pressureEnabled = reader.readBoolNoKey();
          break;
        case StrokeBinaryKeys.color:
          color = reader.readColor();
          break;
      }
      key = reader.readKey();
    }

    if (pageIndex == null) throw Exception('StrokefromBinary no pageIndex');
    if (center == null) throw Exception('StrokefromBinary no center');
    if (radius == null) throw Exception('StrokefromBinary no radius');
    if (pressureEnabled == null) {
      throw Exception('StrokefromBinary no pressureEnabled');
    }
    if (color == null) throw Exception('StrokefromBinary no color');

    final options = BinaryOptions().optionsFromBinary(reader);

    return CircleStroke(
      color: color,
      pressureEnabled: pressureEnabled,
      options: options,
      pageIndex: pageIndex,
      page: page,
      toolId: ToolId.shapePen,
      center: center,
      radius: radius,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'shape': 'circle',
      'i': pageIndex,
      'cx': center.dx,
      'cy': center.dy,
      'r': radius,
      'pe': pressureEnabled,
      'c': color.toARGB32(),
    }..addAll(options.toJson());
  }

  @override
  bool get isEmpty => radius <= 0;
  @override
  int get length => 25;

  @override
  List<Offset> getPolygon({required StrokeQuality quality}) {
    final numPoints = 24 ~/ quality.N;
    return List.generate(numPoints, (i) => i / numPoints * 2 * pi)
        .map((radians) => Offset(cos(radians), sin(radians)))
        .map((unitDir) => unitDir * radius + center)
        .toList();
  }

  @override
  List<PointVector> get pointsForEraser {
    const numPoints = 24;
    return List.generate(numPoints, (i) => i / numPoints * 2 * pi)
        .map((radians) => Offset(cos(radians), sin(radians)))
        .map((unitDir) => unitDir * radius + center)
        .map((o) => PointVector(o.dx, o.dy, 0.5))
        .toList();
  }

  @override
  Path getPath(List<Offset> polygon, {bool smooth = true}) {
    const n = 64;
    final p = Path();
    for (int i = 0; i < n; i++) {
      final t = 2 * pi * i / n;
      final x = center.dx + radius * cos(t);
      final y = center.dy + radius * sin(t);
      if (i == 0)
        p.moveTo(x, y);
      else
        p.lineTo(x, y);
    }
    p.close();
    return p;
  }

  @override
  @Deprecated('Cannot add points to a circle stroke.')
  void addPoint(Offset point, [double? pressure, Duration? timestamp]) {
    throw UnsupportedError('Cannot add points to a circle stroke.');
  }

  @override
  @Deprecated('Cannot pop points from a circle stroke.')
  void popFirstPoint() {
    throw UnsupportedError('Cannot pop points from a circle stroke.');
  }

  @override
  void optimisePoints({double thresholdMultiplier = 0}) {

  }

  @override
  String toSvgPath() {
    return 'M${center.dx},${center.dy} m${-radius},0 a$radius,$radius 0 1,0 ${radius * 2},0 a$radius,$radius 0 1,0 ${-radius * 2},0';
  }

  @override
  double get maxY {
    return center.dy + radius;
  }

  @override
  void shift(Offset offset) {
    center += offset;
    super.shift(offset);
  }

  @override
  @Deprecated('We already know the shape is a circle.')
  RecognizedUnistroke detectShape() {
    return RecognizedUnistroke(
      DefaultUnistrokeNames.circle,
      1,
      originalPoints: lowQualityPolygon,
      referenceUnistrokes: default$1Unistrokes,
    );
  }

  @override
  @Deprecated('We already know the shape is a circle.')
  bool isStraightLine([int minLength = 0]) => false;

  @override
  CircleStroke copy() => CircleStroke(
    color: color,
    pressureEnabled: pressureEnabled,
    options: options.copyWith(),
    pageIndex: pageIndex,
    page: page,
    toolId: toolId,
    center: center,
    radius: radius,
  )..rotationDeg = rotationDeg;

  @override
  void scale(double factor, Offset center) {
    if (factor == 1.0) return;
    this.center = Offset(
      center.dx + (this.center.dx - center.dx) * factor,
      center.dy + (this.center.dy - center.dy) * factor,
    );
    radius *= factor;
    markPolygonNeedsUpdating();
  }
}
