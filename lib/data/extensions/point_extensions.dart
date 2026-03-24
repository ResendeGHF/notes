// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:bson/bson.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

import 'package:saber/data/extensions/dynamic_extensions.dart';

extension PointExtensions on PointVector {
  @Deprecated(
    'Use fromBsonBinary instead; fromJson is only for backward compatibility',
  )
  static Point fromJson({
    required Map<String, dynamic> json,
    Offset offset = .zero,
  }) =>
      Point(
        toDoubleSafe(json['x'])! + offset.dx,
        toDoubleSafe(json['y'])! + offset.dy,
        toDoubleSafe(json['p']),
      );

  static PointVector fromBsonBinary({
    required BsonBinary json,
    Offset offset = .zero,
  }) {
    final point = json.byteList.buffer.asFloat32List();
    return PointVector(
      point[0] + offset.dx,
      point[1] + offset.dy,
      point.length == 2 ? null : point[2],
    );
  }

  BsonBinary toBsonBinary() {
    final Float32List point = Float32List.fromList([
      x,
      y,
      if (pressure != null) pressure!,
    ]);
    return BsonBinary.from(point.buffer.asUint8List());
  }

  PointVector operator +(Offset offset) =>
      PointVector(x + offset.dx, y + offset.dy, pressure);
}
