// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';
import 'package:saber/data/tools/_tool.dart';

import '../../helpers/test_stroke_factory.dart';

Stroke _straightAdvancedPen({
  required int samples,
  double size = 8,
  bool complete = false,
}) {
  final stroke = Stroke(
    color: Colors.black,
    pressureEnabled: false,
    options: StrokeOptions(
      size: size,
      thinning: 0,
      smoothing: 0.2,
      streamline: 0.15,
      simulatePressure: false,
      isComplete: false,
      start: StrokeEndOptions.start(cap: true, taperEnabled: false),
      end: StrokeEndOptions.end(cap: true, taperEnabled: false),
    ),
    pageIndex: 0,
    page: HasSize(EditorPage.defaultSize),
    toolId: ToolId.advancedPen,
  );
  for (var i = 0; i < samples; i++) {
    stroke.addPoint(Offset(20.0 + i * 3.0, 80.0));
  }
  if (complete) stroke.finishLiveGeometry();
  return stroke;
}

void main() {
  test('long live Advanced Pen strokes stay path-only', () {
    final stroke = Stroke(
      color: Colors.black,
      pressureEnabled: false,
      options: StrokeOptions(
        size: 8,
        thinning: 0.45,
        smoothing: 0.55,
        streamline: 0.45,
        simulatePressure: false,
        isComplete: false,
      ),
      pageIndex: 0,
      page: HasSize(EditorPage.defaultSize),
      toolId: ToolId.advancedPen,
    );

    const samples = 240;
    for (var i = 0; i < samples; i++) {
      stroke.addPoint(Offset(20.0 + i * 3.0, 80.0 + (i % 7) * 0.4));
    }

    expect(stroke.length, samples);
    expect(stroke.usesSolidOutlineMesh, isFalse);
    expect(stroke.vertices, isNull);
    expect(stroke.liveIncrementalMeshes, isNull);

    final liveBounds = stroke.highQualityPath.getBounds();
    expect(liveBounds.isEmpty, isFalse);
    expect(liveBounds.left, lessThanOrEqualTo(stroke.points.first.x + 16));
    expect(liveBounds.right, greaterThanOrEqualTo(stroke.points.last.x - 16));

    stroke.finishLiveGeometry();
    expect(stroke.options.isComplete, isTrue);
    expect(stroke.vertices, isNull);
    expect(stroke.usesSolidOutlineMesh, isFalse);
    expect(stroke.length, samples);
    final committed = stroke.highQualityPath.getBounds();
    expect(committed.isEmpty, isFalse);
    expect(committed.left, lessThanOrEqualTo(stroke.points.first.x + 16));
    expect(committed.right, greaterThanOrEqualTo(stroke.points.last.x - 16));
  });

  test('loaded Advanced Pen strokes stay path-only without a live session', () {
    final stroke = testPolylineStroke(
      toolId: ToolId.advancedPen,
      y: 80,
      x0: 20,
      x1: 400,
      points: 120,
    );
    expect(stroke.options.isComplete, isTrue);
    expect(stroke.usesSolidOutlineMesh, isFalse);
    expect(stroke.needsTileMeshWarmup, isFalse);
    expect(stroke.vertices, isNull);
    expect(stroke.canBatchSolidMesh, isFalse);
    final bounds = stroke.highQualityPath.getBounds();
    expect(bounds.isEmpty, isFalse);
    expect(bounds.left, lessThanOrEqualTo(stroke.points.first.x + 16));
    expect(bounds.right, greaterThanOrEqualTo(stroke.points.last.x - 16));
  });

  test('pen-up keeps the authored Advanced Pen path', () {
    final stroke = Stroke(
      color: Colors.black,
      pressureEnabled: false,
      options: StrokeOptions(
        size: 8,
        thinning: 0.45,
        smoothing: 0.55,
        streamline: 0.45,
        simulatePressure: false,
        isComplete: false,
      ),
      pageIndex: 0,
      page: HasSize(EditorPage.defaultSize),
      toolId: ToolId.advancedPen,
    );

    const samples = 400;
    for (var i = 0; i < samples; i++) {
      stroke.addPoint(Offset(20.0 + i * 3.0, 80.0 + (i % 7) * 0.4));
    }

    expect(stroke.vertices, isNull);
    stroke.finishLiveGeometry();

    expect(stroke.length, samples);
    expect(stroke.options.isComplete, isTrue);
    expect(stroke.vertices, isNull);
    expect(stroke.canBatchSolidMesh, isFalse);
    final bounds = stroke.highQualityPath.getBounds();
    expect(bounds.isEmpty, isFalse);
    expect(bounds.left, lessThanOrEqualTo(stroke.points.first.x + 16));
    expect(bounds.right, greaterThanOrEqualTo(stroke.points.last.x - 16));
  });

  test('copy and shift of a long Advanced Pen stroke keeps the full path', () {
    final stroke = testPolylineStroke(
      toolId: ToolId.advancedPen,
      y: 80,
      x0: 20,
      x1: 400,
      points: 120,
    );
    final copied = stroke.copy()..shift(const Offset(20, 20));
    expect(copied.vertices, isNull);
    expect(copied.drawableSolidMeshes, isEmpty);
    final bounds = copied.highQualityPath.getBounds();
    expect(bounds.isEmpty, isFalse);
    expect(bounds.left, lessThanOrEqualTo(copied.points.first.x + 16));
    expect(bounds.right, greaterThanOrEqualTo(copied.points.last.x - 16));
  });

  test('Advanced Pen L-bend start cap follows the opening travel chord', () {
    final stroke = Stroke(
      color: Colors.black,
      pressureEnabled: false,
      options: StrokeOptions(
        size: 16,
        thinning: 0.45,
        smoothing: 0.55,
        streamline: 0.45,
        simulatePressure: false,
        isComplete: true,
        start: StrokeEndOptions.start(cap: true, taperEnabled: true),
        end: StrokeEndOptions.end(cap: true, taperEnabled: true),
      ),
      pageIndex: 0,
      page: HasSize(EditorPage.defaultSize),
      toolId: ToolId.advancedPen,
    );
    // Long +Y stem so the Ballpoint local chord stays on the opening tangent
    // (a 4px put-down stem is jitter, not travel).
    for (final p in const [
      PointVector(80, 40, 0.6),
      PointVector(80, 48, 0.6),
      PointVector(80, 56, 0.65),
      PointVector(80, 64, 0.65),
      PointVector(88, 64, 0.6),
      PointVector(120, 64, 0.6),
    ]) {
      stroke.points.add(p);
    }
    stroke.markPolygonNeedsUpdating();
    final bounds = stroke.highQualityPath.getBounds();
    expect(
      bounds.top,
      lessThan(40 - 4),
      reason: 'start round cap must sit behind the +Y travel',
    );
    expect(
      (bounds.left - 80).abs(),
      lessThan(14),
      reason: 'must not rotate the start cap toward the later +X run',
    );
  });

  test('Advanced Pen start/end caps follow travel, not put-down jitter', () {
    final stroke = Stroke(
      color: Colors.black,
      pressureEnabled: false,
      options: StrokeOptions(
        size: 16,
        thinning: 0.45,
        smoothing: 0.55,
        streamline: 0.45,
        simulatePressure: false,
        isComplete: true,
        start: StrokeEndOptions.start(cap: true, taperEnabled: true),
        end: StrokeEndOptions.end(cap: true, taperEnabled: true),
      ),
      pageIndex: 0,
      page: HasSize(EditorPage.defaultSize),
      toolId: ToolId.advancedPen,
    );
    for (final p in const [
      PointVector(20, 80, 0.5),
      PointVector(20.3, 81.2, 0.5),
      PointVector(20.2, 79.2, 0.5),
      PointVector(24, 80.1, 0.6),
      PointVector(36, 80.0, 0.65),
      PointVector(80, 80.0, 0.6),
      PointVector(80.4, 81.1, 0.55),
      PointVector(80.1, 79.3, 0.5),
    ]) {
      stroke.points.add(p);
    }
    stroke.markPolygonNeedsUpdating();
    final bounds = stroke.highQualityPath.getBounds();
    expect(
      bounds.left,
      lessThan(20 - 2),
      reason: 'start round cap sits behind +X travel',
    );
    expect(
      (bounds.top + bounds.bottom) / 2,
      closeTo(80, 6),
      reason: 'start/end bulbs stay on the +X axis, not the Y jitter',
    );
    expect(
      bounds.right,
      greaterThan(80 + 2),
      reason: 'end round cap sits ahead of +X travel',
    );
    expect(
      bounds.top,
      greaterThan(80 - 16),
      reason: 'must not stand the end cap on the lift-off jitter',
    );
    expect(bounds.bottom, lessThan(80 + 16));
  });

  test('stroke prediction is not baked into the committed Advanced path', () {
    final stroke = _straightAdvancedPen(samples: 80);
    expect(stroke.vertices, isNull);
    final last = stroke.points.last;
    stroke.debugSetLivePrediction(Offset(last.x + 80, last.y));
    for (var i = 80; i < 160; i++) {
      stroke.addPoint(Offset(20.0 + i * 3.0, 80.0));
      stroke.debugSetLivePrediction(
        Offset(stroke.points.last.x + 80, stroke.points.last.y),
      );
    }
    expect(stroke.length, 160);
    stroke.finishLiveGeometry();
    final committed = stroke.highQualityPath.getBounds();
    expect(committed.right, lessThan(stroke.points.last.x + 20));
    expect(stroke.length, 160);
    expect(stroke.vertices, isNull);
  });

  test('live Advanced Pen end tip stays on the stroke axis (circular cap)', () {
    final stroke = Stroke(
      color: Colors.black,
      pressureEnabled: false,
      options: StrokeOptions(
        size: 14,
        thinning: 0.4,
        smoothing: 0.45,
        streamline: 0.35,
        simulatePressure: false,
        isComplete: false,
        start: StrokeEndOptions.start(cap: true, taperEnabled: true),
        end: StrokeEndOptions.end(cap: true, taperEnabled: true),
      ),
      pageIndex: 0,
      page: HasSize(EditorPage.defaultSize),
      toolId: ToolId.advancedPen,
    );
    for (var i = 0; i < 40; i++) {
      stroke.addPoint(
        Offset(30.0 + i * 4.0, 100.0 + (i > 30 ? (i - 30) * 0.4 : 0.0)),
      );
    }
    final bounds = stroke.highQualityPath.getBounds();
    final tip = stroke.points.last;
    // Sideways displacement of the whole tip bulb (the old tic-tac artifact).
    final midY = (bounds.top + bounds.bottom) / 2;
    expect(
      (midY - tip.y).abs(),
      lessThan(stroke.options.size * 0.65),
      reason: 'end bulb must not be displaced sideways off the tip',
    );
    expect(
      bounds.height,
      lessThan(stroke.options.size * 2.2),
      reason: 'circular end must not grow a tall sideways tic-tac',
    );
  });
}
