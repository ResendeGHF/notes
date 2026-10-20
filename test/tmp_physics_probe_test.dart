// Temporary probe for the advanced-pen physics fixes.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_canvas_background_painter.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/canvas_background_pattern.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/stroke_geometry/advanced_pen_options.dart';
import 'package:saber/data/stroke_geometry/stroke_options.dart';
import 'package:saber/data/tools/_tool.dart';

Stroke _makeStroke(AdvancedPenOptions brush) => Stroke(
  color: Colors.black,
  pressureEnabled: true,
  options: StrokeOptions(size: 12, simulatePressure: false),
  pageIndex: 0,
  page: EditorPage(),
  toolId: ToolId.advancedPen,
  brushOptions: brush,
);

(double, double) _meshRect(Stroke s) {
  final v = s.ensureMeshVertices();
  if (v == null) return (-1, -1);
  final pos = s.getRawPositions();
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (var i = 0; i + 1 < pos.length; i += 2) {
    if (pos[i] < minX) minX = pos[i];
    if (pos[i] > maxX) maxX = pos[i];
    if (pos[i + 1] < minY) minY = pos[i + 1];
    if (pos[i + 1] > maxY) maxY = pos[i + 1];
  }
  return (maxX - minX, maxY - minY);
}

Rect _polygonRect(List<Offset> poly) {
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final o in poly) {
    if (o.dx < minX) minX = o.dx;
    if (o.dx > maxX) maxX = o.dx;
    if (o.dy < minY) minY = o.dy;
    if (o.dy > maxY) maxY = o.dy;
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

void main() {
  test('ink pooling: stationary stroke widens mesh AND baked outline', () {
    for (final pool in [0.0, 1.0]) {
      final brush = AdvancedPenOptions.advancedDefaults()..inkPooling = pool;
      final s = _makeStroke(brush);
      s.addPoint(const Offset(100, 100), 0.8, Duration.zero);
      for (var i = 1; i <= 240; i++) {
        s.addPoint(
          const Offset(100, 100),
          0.8,
          Duration(microseconds: (i / 120 * 1e6).round()),
        );
      }
      final (w, h) = _meshRect(s);
      final poly = s.highQualityPolygon;
      final pr = _polygonRect(poly);
      debugPrint(
        'pool=$pool mesh=${w.toStringAsFixed(1)}x${h.toStringAsFixed(1)} '
        'poly=${pr.width.toStringAsFixed(1)}x${pr.height.toStringAsFixed(1)} '
        'lastP=${s.points.last.pressure}',
      );
    }
  });

  test('surface friction: visible deviation at handwriting speed', () {
    for (final friction in [0.0, 1.0]) {
      final brush = AdvancedPenOptions.advancedDefaults()
        ..surfaceFriction = friction;
      final s = _makeStroke(brush);
      // ~140 px/s: a slow but normal handwriting stroke.
      for (var i = 0; i < 200; i++) {
        s.addPoint(
          Offset(100 + i * 1.2, 100),
          0.5,
          Duration(microseconds: (i / 120 * 1e6).round()),
        );
      }
      var maxDev = 0.0;
      for (final p in s.points) {
        final d = (p.y - 100).abs();
        if (d > maxDev) maxDev = d;
      }
      final (w, h) = _meshRect(s);
      final pos = s.getRawPositions();
      var minX = double.infinity, maxX = -double.infinity;
      for (var i = 0; i + 1 < pos.length; i += 2) {
        if (pos[i] < minX) minX = pos[i];
        if (pos[i] > maxX) maxX = pos[i];
      }
      var maxPointX = -double.infinity;
      for (final p in s.points) {
        if (p.x > maxPointX) maxPointX = p.x;
      }
      debugPrint(
        'friction=$friction pointDev=${maxDev.toStringAsFixed(2)} '
        'mesh=${w.toStringAsFixed(1)}x${h.toStringAsFixed(1)} '
        'floats=${pos.length} chunks=${s.debugLiveChunkCount} '
        'frozenEnd=${s.debugLiveFrozenEnd} '
        'meshX=(${minX.toStringAsFixed(1)}..${maxX.toStringAsFixed(1)}) '
        'pointsX=${maxPointX.toStringAsFixed(1)} n=${s.points.length}',
      );
    }
  });

  test('ink pooling: live cached mesh invalidates while holding still', () {
    final brush = AdvancedPenOptions.advancedDefaults()..inkPooling = 1.0;
    final s = _makeStroke(brush);
    // Draw a short line, then build (and cache) the live mesh.
    for (var i = 0; i <= 20; i++) {
      s.addPoint(
        Offset(100 + i * 2.0, 100),
        0.8,
        Duration(microseconds: (i / 120 * 1e6).round()),
      );
    }
    final (w0, h0) = _meshRect(s);
    // Now hold the stylus still for ~1 s, as the editor now forwards
    // throttled resting samples.
    for (var i = 21; i <= 140; i++) {
      s.addPoint(
        const Offset(140, 100),
        0.8,
        Duration(microseconds: (i / 120 * 1e6).round()),
      );
    }
    final (w1, h1) = _meshRect(s);
    debugPrint(
      'live-hold: before=${w0.toStringAsFixed(1)}x${h0.toStringAsFixed(1)} '
      'after=${w1.toStringAsFixed(1)}x${h1.toStringAsFixed(1)} '
      'lastP=${s.points.last.pressure}',
    );
    expect(h1, greaterThan(h0 + 3));
  });

  test('wantsRestingSamples follows pooling/inertia', () {
    final s = _makeStroke(AdvancedPenOptions.advancedDefaults());
    expect(s.wantsRestingSamples, isFalse);
    s.brushOptions.inkPooling = 0.5;
    expect(s.wantsRestingSamples, isTrue);
    s.brushOptions.inkPooling = 0.0;
    s.brushOptions.pressureInertia = 0.5;
    expect(s.wantsRestingSamples, isTrue);
  });

  test('background painter survives lineHeight 0 / infinite size', () {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const painter = CanvasBackgroundPainter(
      invert: false,
      backgroundColor: Colors.white,
      backgroundPattern: CanvasBackgroundPattern.grid,
      lineHeight: 0,
      lineThickness: 1,
    );
    painter.paint(canvas, const Size(300, 300));
    painter.paint(canvas, const Size(double.infinity, 300));
    painter.paint(canvas, Size(double.nan, 300));
    recorder.endRecording().dispose();
    expect(
      CanvasBackgroundPainter.getPatternElements(
        pattern: CanvasBackgroundPattern.grid,
        size: const Size(300, 300),
        lineHeight: 0,
      ),
      isEmpty,
    );
    expect(
      CanvasBackgroundPainter.getPatternElements(
        pattern: CanvasBackgroundPattern.grid,
        size: const Size(double.infinity, 300),
        lineHeight: 20,
      ),
      isEmpty,
    );
    expect(
      CanvasBackgroundPainter.getPatternElements(
        pattern: CanvasBackgroundPattern.grid,
        size: const Size(300, 300),
        lineHeight: 20,
      ),
      isNotEmpty,
    );
  });
}
