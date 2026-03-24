// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/binary_writer.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/dynamic_extensions.dart';
import 'package:saber/data/tools/_tool.dart';

class RectangleStroke extends Stroke {
  Rect rect;

  RectangleStroke({
    required super.color,
    required super.pressureEnabled,
    required super.options,
    required super.pageIndex,
    required super.page,
    required super.toolId,
    required this.rect,
  }) {
    options.isComplete = true;
  }

  factory RectangleStroke.fromJson(
    Map<String, dynamic> json, {
    required int fileVersion,
    required int pageIndex,
    required HasSize page,
  }) {
    assert(json['shape'] == 'rect');
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

    return RectangleStroke(
      color: color,
      pressureEnabled: json['pe'] ?? Stroke.defaultPressureEnabled,
      options: StrokeOptions.fromJson(json),
      pageIndex: pageIndex,
      page: page,
      toolId: .parsePenType(json['ty'], fallback: .shapePen),
      rect: .fromLTWH(
        toDoubleSafe(json['rl']) ?? 0,
        toDoubleSafe(json['rt']) ?? 0,
        toDoubleSafe(json['rw']) ?? 0,
        toDoubleSafe(json['rh']) ?? 0,
      ),
    );
  }
  @override
  Map<String, dynamic> toJson() {
    return {
      'shape': 'rect',
      'i': pageIndex,
      'rl': rect.left,
      'rt': rect.top,
      'rw': rect.width,
      'rh': rect.height,
      'pe': pressureEnabled,
      'c': color.toARGB32(),
    }..addAll(options.toJson());
  }

  @override
  void toBinary(BinaryWriter writer) {
    writer.writeString(StrokeBinaryKeys.shape, 'rect');
    writer.writeInt(StrokeBinaryKeys.pageIndex, pageIndex);
    writer.writeScaledFloat(StrokeBinaryKeys.left, rect.left);
    writer.writeScaledFloat(StrokeBinaryKeys.top, rect.top);
    writer.writeScaledFloat(StrokeBinaryKeys.width, rect.width);
    writer.writeScaledFloat(StrokeBinaryKeys.height, rect.height);
    writer.writeBool(StrokeBinaryKeys.pressureEnabled, pressureEnabled);
    writer.writeInt(StrokeBinaryKeys.color, color.toARGB32());
    BinaryOptions().optionsToBinary(writer, options);
  }

  factory RectangleStroke.fromBinary(
    BinaryReader reader, {
    required HasSize page,
  }) {
    int key;
    int? pageIndex;
    Rect? rect;
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
        case StrokeBinaryKeys.left:
          rect = Rect.fromLTWH(
            reader.readScaledFloat(),
            rect?.top ?? 0,
            rect?.width ?? 0,
            rect?.height ?? 0,
          );
          break;
        case StrokeBinaryKeys.top:
          rect = Rect.fromLTWH(
            rect?.left ?? 0,
            reader.readScaledFloat(),
            rect?.width ?? 0,
            rect?.height ?? 0,
          );
          break;
        case StrokeBinaryKeys.width:
          rect = Rect.fromLTWH(
            rect?.left ?? 0,
            rect?.top ?? 0,
            reader.readScaledFloat(),
            rect?.height ?? 0,
          );
          break;
        case StrokeBinaryKeys.height:
          rect = Rect.fromLTWH(
            rect?.left ?? 0,
            rect?.top ?? 0,
            rect?.width ?? 0,
            reader.readScaledFloat(),
          );
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
    if (rect == null) throw Exception('StrokefromBinary no rect');
    if (pressureEnabled == null) {
      throw Exception('StrokefromBinary no pressureEnabled');
    }
    if (color == null) throw Exception('StrokefromBinary no color');

    final options = BinaryOptions().optionsFromBinary(reader);

    return RectangleStroke(
      color: color,
      pressureEnabled: pressureEnabled,
      options: options,
      pageIndex: pageIndex,
      page: page,
      toolId: ToolId.shapePen,
      rect: rect,
    );
  }

  @override
  bool get isEmpty => rect.isEmpty;
  @override
  int get length => 100;

  @override
  List<Offset> getPolygon({required StrokeQuality quality}) => [

    for (int i = 0; i < 24 / quality.N; ++i)
      Offset(rect.left, rect.top + rect.height * i / 24),

    for (int i = 0; i < 24 / quality.N; ++i)
      Offset(rect.left + rect.width * i / 24, rect.bottom),

    for (int i = 0; i < 24 / quality.N; ++i)
      Offset(rect.right, rect.bottom - rect.height * i / 24),

    for (int i = 0; i < 24 / quality.N; ++i)
      Offset(rect.right - rect.width * i / 24, rect.top),
  ];

  @override
  List<PointVector> get pointsForEraser {
    const n = 24;
    return [
      for (int i = 0; i < n; ++i)
        PointVector(rect.left, rect.top + rect.height * i / n, 0.5),
      for (int i = 0; i < n; ++i)
        PointVector(rect.left + rect.width * i / n, rect.bottom, 0.5),
      for (int i = 0; i < n; ++i)
        PointVector(rect.right, rect.bottom - rect.height * i / n, 0.5),
      for (int i = 0; i < n; ++i)
        PointVector(rect.right - rect.width * i / n, rect.top, 0.5),
    ];
  }

  @override
  Path getPath(List<Offset> polygon, {bool smooth = true}) =>
      Path()..addRect(rect);

  @override
  @Deprecated('Cannot add points to a rectangle stroke.')
  void addPoint(Offset point, [double? pressure, Duration? timestamp]) {
    throw UnsupportedError('Cannot add points to a rectangle stroke.');
  }

  @override
  @Deprecated('Cannot pop points from a rectangle stroke.')
  void popFirstPoint() {
    throw UnsupportedError('Cannot pop points from a rectangle stroke.');
  }

  @override
  void optimisePoints({double thresholdMultiplier = 0}) {

  }

  @override
  String toSvgPath() {
    return 'M${rect.left},${rect.top} '
        'L${rect.right},${rect.top} '
        'L${rect.right},${rect.bottom} '
        'L${rect.left},${rect.bottom} '
        'Z';
  }

  @override
  double get maxY {
    return rect.bottom;
  }

  @override
  void shift(Offset offset) {
    rect = rect.shift(offset);
    super.shift(offset);
  }

  @override
  @Deprecated('We already know the shape is a rectangle.')
  RecognizedUnistroke detectShape() {
    return RecognizedUnistroke(
      DefaultUnistrokeNames.rectangle,
      1,
      originalPoints: lowQualityPolygon,
      referenceUnistrokes: default$1Unistrokes,
    );
  }

  @override
  @Deprecated('We already know the shape is a rectangle.')
  bool isStraightLine([int minLength = 0]) => false;

  @override
  RectangleStroke copy() => RectangleStroke(
    color: color,
    pressureEnabled: pressureEnabled,
    options: options.copyWith(),
    pageIndex: pageIndex,
    page: page,
    toolId: toolId,
    rect: rect,
  )..rotationDeg = rotationDeg;

  @override
  void scale(double factor, Offset center) {
    if (factor == 1.0) return;
    rect = Rect.fromLTRB(
      center.dx + (rect.left - center.dx) * factor,
      center.dy + (rect.top - center.dy) * factor,
      center.dx + (rect.right - center.dx) * factor,
      center.dy + (rect.bottom - center.dy) * factor,
    );
    markPolygonNeedsUpdating();
  }
}
