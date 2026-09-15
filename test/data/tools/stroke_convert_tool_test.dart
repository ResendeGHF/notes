// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/pen.dart';

void main() {
  test('convertStroke Advanced → Ballpoint keeps path and remaps tool', () {
    final page = HasSize(const Size(800, 600));
    final stroke = Stroke(
      color: Colors.indigo,
      pressureEnabled: true,
      options: Pen.advancedPenOptions.copyWith(size: 3.5, isComplete: true),
      pageIndex: 0,
      page: page,
      toolId: ToolId.advancedPen,
    );
    for (var i = 0; i < 12; i++) {
      stroke.points.add(PointVector(10.0 + i * 4.0, 40.0, 0.6));
    }

    final converted = Pen.convertStroke(stroke, ToolId.ballpointPen);

    expect(converted.toolId, ToolId.ballpointPen);
    expect(converted.color, Colors.indigo);
    expect(converted.options.size, 3.5);
    expect(converted.pressureEnabled, isFalse);
    expect(converted.points.length, stroke.points.length);
    expect(converted.points.first.x, stroke.points.first.x);
    expect(converted.points.last.x, stroke.points.last.x);
    expect(converted.neon, Pen.neonEnabledForTool(ToolId.ballpointPen));
    expect(converted.canConvertStrokeType, isTrue);
  });

  test('convertStroke Ballpoint → Advanced enables pressure-style options', () {
    final page = HasSize(const Size(800, 600));
    final stroke = Stroke(
      color: Colors.black,
      pressureEnabled: false,
      options: Pen.ballpointPenOptions.copyWith(size: 2, isComplete: true),
      pageIndex: 0,
      page: page,
      toolId: ToolId.ballpointPen,
    );
    stroke.points.addAll(const [
      PointVector(0, 0, 0.5),
      PointVector(20, 0, 0.5),
      PointVector(40, 8, 0.5),
    ]);

    final converted = Pen.convertStroke(stroke, ToolId.advancedPen);
    expect(converted.toolId, ToolId.advancedPen);
    expect(converted.pressureEnabled, isTrue);
    expect(converted.neon, isFalse);
    expect(converted.options.size, 2);
    expect(converted.paint.isSolid, isTrue);
    expect(converted.vertices, isNull);
  });

  test('same tool returns a copy without changing identity fields', () {
    final page = HasSize(const Size(800, 600));
    final stroke = Stroke(
      color: Colors.red,
      pressureEnabled: false,
      options: Pen.ballpointPenOptions.copyWith(isComplete: true),
      pageIndex: 0,
      page: page,
      toolId: ToolId.ballpointPen,
    );
    stroke.points.addAll(const [
      PointVector(1, 1, 0.5),
      PointVector(2, 2, 0.5),
    ]);
    final copy = Pen.convertStroke(stroke, ToolId.ballpointPen);
    expect(identical(copy, stroke), isFalse);
    expect(copy.toolId, ToolId.ballpointPen);
    expect(copy.points.length, 2);
  });
}
