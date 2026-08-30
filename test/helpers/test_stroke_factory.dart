import 'package:flutter/material.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/_tool.dart';

/// Minimal [HasSize] for constructing [Stroke] in tests.
HasSize testPageSize([Size size = EditorPage.defaultSize]) => HasSize(size);

/// Straight horizontal stroke for hit-testing / eraser tests.
Stroke testPolylineStroke({
  required ToolId toolId,
  double y = 100,
  double x0 = 0,
  double x1 = 200,
  int points = 20,
  double width = 8,
}) {
  final page = testPageSize();
  final stroke = Stroke(
    color: Colors.black,
    pressureEnabled: false,
    options: StrokeOptions(
      size: width,
      simulatePressure: false,
      isComplete: true,
    ),
    pageIndex: 0,
    page: page,
    toolId: toolId,
  );
  for (var i = 0; i < points; i++) {
    final t = i / (points - 1);
    stroke.points.add(
      PointVector(x0 + (x1 - x0) * t, y, 0.5),
    );
  }
  stroke.markPolygonNeedsUpdating();
  return stroke;
}
