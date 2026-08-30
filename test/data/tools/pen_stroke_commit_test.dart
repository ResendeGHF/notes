import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/_tool.dart';

/// Exercises pen-style stroke pipeline without prefs-backed [Pen] constructors.
void main() {
  group('Pen stroke pipeline (tool markers)', () {
    test('ballpoint stroke accumulates points and completes', () {
      final page = HasSize(EditorPage.defaultSize);
      final stroke = Stroke(
        color: Colors.black,
        pressureEnabled: false,
        options: StrokeOptions(
          size: 3,
          simulatePressure: false,
          isComplete: false,
        ),
        pageIndex: 0,
        page: page,
        toolId: ToolId.ballpointPen,
      );

      stroke.addPoint(const Offset(0, 0), null, const Duration(milliseconds: 0));
      stroke.addPoint(const Offset(5, 0), null, const Duration(milliseconds: 16));
      expect(stroke.length, greaterThanOrEqualTo(2));

      stroke.options.isComplete = true;
      stroke.clearLivePrediction();
      stroke.markPolygonNeedsUpdating();

      expect(stroke.toolId, ToolId.ballpointPen);
      expect(stroke.highQualityPath.getBounds().isEmpty, isFalse);
    });

    test('fountain pen stroke uses fluid tool id', () {
      final page = HasSize(EditorPage.defaultSize);
      final stroke = Stroke(
        color: Colors.teal,
        pressureEnabled: true,
        options: StrokeOptions(
          size: 4,
          simulatePressure: true,
          isComplete: true,
        ),
        pageIndex: 0,
        page: page,
        toolId: ToolId.fountainPen,
      );
      stroke.addPoint(const Offset(1, 1), 0.8, const Duration(milliseconds: 0));
      stroke.addPoint(const Offset(20, 5), 0.6, const Duration(milliseconds: 16));
      stroke.markPolygonNeedsUpdating();
      expect(stroke.toolId, ToolId.fountainPen);
    });

    test('highlighter stroke keeps highlighter tool id', () {
      final page = HasSize(EditorPage.defaultSize);
      final stroke = Stroke(
        color: Colors.yellow.withValues(alpha: 0.4),
        pressureEnabled: false,
        options: StrokeOptions(
          size: 20,
          simulatePressure: false,
          isComplete: true,
        ),
        pageIndex: 0,
        page: page,
        toolId: ToolId.highlighter,
      );
      stroke.addPoint(const Offset(0, 0), null, const Duration(milliseconds: 0));
      stroke.addPoint(const Offset(30, 0), null, const Duration(milliseconds: 16));
      stroke.markPolygonNeedsUpdating();
      expect(stroke.toolId, ToolId.highlighter);
    });

    test('flat-edge highlighter live path stays rectangular with 2 points', () {
      // Straight-line assist keeps only start/end while drawing. Midpoint path
      // smoothing used to collapse that 4-vertex outline.
      final page = HasSize(EditorPage.defaultSize);
      const size = 24.0;
      final stroke = Stroke(
        color: Colors.yellow.withValues(alpha: 0.4),
        pressureEnabled: false,
        options: StrokeOptions(
          size: size,
          simulatePressure: false,
          isComplete: false,
        ),
        pageIndex: 0,
        page: page,
        toolId: ToolId.highlighter,
      )..flatEdge = true;

      stroke.points.add(const PointVector(10, 50, 0.5));
      stroke.points.add(const PointVector(210, 50, 0.5));
      stroke.markPolygonNeedsUpdating();

      final bounds = stroke.highQualityPath.getBounds();
      expect(bounds.width, closeTo(200, 1));
      expect(bounds.height, closeTo(size, 1));
      expect(bounds.center.dy, closeTo(50, 1));
    });
  });
}
