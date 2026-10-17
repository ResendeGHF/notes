// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

// Regression tests for long-stroke lag / crash / OOM (all pens).
//
// Root cause: every committed sample invalidated all caches, so each frame
// re-splined + re-tessellated the whole stroke — O(n) per frame, O(n²) per
// stroke — with unbounded transient buffers and Uint16 index overflow on top.
// The fix bounds the work: live input decimation, live render staging
// (frozen butt-jointed chunks + bounded tail), a per-stroke sample cap,
// mesh/index guards, and tile-local clipping for committed replay.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';
import 'package:saber/data/tools/_tool.dart';

Stroke _liveStroke(ToolId toolId, {double size = 4}) {
  final stroke = Stroke(
    color: Colors.black,
    pressureEnabled: toolId == ToolId.fountainPen,
    options: StrokeOptions(
      size: size,
      thinning: toolId == ToolId.fountainPen ? 0.55 : 0,
      smoothing: 0.42,
      streamline: 0.18,
      simulatePressure: toolId == ToolId.fountainPen,
      isComplete: false,
      start: StrokeEndOptions.start(cap: true, taperEnabled: false),
      end: StrokeEndOptions.end(cap: true, taperEnabled: false),
    ),
    pageIndex: 0,
    page: HasSize(EditorPage.defaultSize),
    toolId: toolId,
  );
  if (toolId == ToolId.advancedPen) {
    // Exercise the shared input path (stabilization + decimation). The
    // modeled builder (default) has its own spring-lag semantics and is
    // covered separately below.
    stroke.brushOptions = stroke.brushOptions.copyWith(
      builderType: AdvancedPenBuilderType.curved,
    );
  }
  return stroke;
}

void _drawSmoothLine(Stroke stroke, int samples) {
  for (var i = 0; i < samples; i++) {
    stroke.addPoint(
      Offset(20.0 + i * 2.0, 90.0 + i * 0.5 + (i % 7) * 0.1),
      stroke.pressureEnabled ? 0.5 : null,
      Duration(microseconds: i * 4166),
    );
  }
}

void _drawZigzag(Stroke stroke, int samples) {
  for (var i = 0; i < samples; i++) {
    stroke.addPoint(
      Offset(20.0 + i * 2.5, 90.0 + (i % 2 == 0 ? -15.0 : 15.0)),
      stroke.pressureEnabled ? 0.5 : null,
      Duration(microseconds: i * 4166),
    );
  }
}

const _inkTools = [
  ToolId.ballpointPen,
  ToolId.fountainPen,
  ToolId.calligraphyPen,
  ToolId.advancedPen,
  ToolId.highlighter,
  ToolId.pencil,
];

void main() {
  group('live input decimation', () {
    for (final toolId in _inkTools) {
      test('$toolId absorbs sub-pixel jitter while drawing', () {
        final stroke = _liveStroke(toolId);
        for (var i = 0; i < 2000; i++) {
          stroke.addPoint(
            Offset(50.0 + (i % 3) * 0.2, 50.0 + (i % 4) * 0.2),
            stroke.pressureEnabled ? 0.5 : null,
            Duration(microseconds: i * 4166),
          );
        }
        // 2000 motion events, ~1px of actual travel: must not bank samples.
        expect(stroke.length, lessThan(32));
      });

      test('$toolId keeps real travel samples', () {
        final stroke = _liveStroke(toolId);
        _drawSmoothLine(stroke, 200);
        // 2px steps are all optically relevant: (nearly) all must survive.
        expect(stroke.length, greaterThan(180));
        final tip = stroke.points.last;
        // Stabilization trails the stylus slightly; the tip must still track
        // the end of the drawn run, not an absorbed/decimated position.
        expect(tip.x, greaterThan(20.0 + 199 * 2.0 - 8));
        expect(tip.x, lessThanOrEqualTo(20.0 + 199 * 2.0 + 1));
      });
    }

    test('press-in-place without moving is kept (fountain width)', () {
      final stroke = _liveStroke(ToolId.fountainPen);
      stroke.addPoint(
        const Offset(100, 100),
        0.4,
        const Duration(microseconds: 0),
      );
      stroke.addPoint(
        const Offset(100, 100),
        0.9,
        const Duration(microseconds: 4166),
      );
      expect(stroke.length, 2);
    });

    test('dot tap still yields a dot after decimation', () {
      final stroke = _liveStroke(ToolId.ballpointPen);
      stroke.addPoint(
        const Offset(100, 100),
        null,
        const Duration(microseconds: 0),
      );
      stroke.addPoint(
        const Offset(100.1, 100.1),
        null,
        const Duration(microseconds: 4166),
      );
      expect(stroke.length, greaterThanOrEqualTo(1));
      expect(stroke.highQualityPath.getBounds().isEmpty, isFalse);
    });
  });

  group('live staging bounds per-frame work', () {
    for (final toolId in _inkTools) {
      test('$toolId long smooth stroke stages prefix and bounds tail', () {
        final stroke = _liveStroke(toolId);
        _drawSmoothLine(stroke, 4000);

        // Prefix frozen once: only the tail rebuilds per frame.
        expect(stroke.hasLiveStaging, isTrue);
        expect(stroke.debugLiveChunkCount, greaterThan(0));
        final tailPoints = stroke.length - 1 - stroke.debugLiveFrozenEnd;
        expect(tailPoints, lessThanOrEqualTo(512));

        // Staged visuals cover the whole extent for the render path.
        final chunks = stroke.liveStagedChunks;
        expect(chunks, isNotEmpty);
        var minX = double.infinity, maxX = double.negativeInfinity;
        for (final c in chunks) {
          final b = c.bounds;
          if (b == null || b.isEmpty) continue;
          if (b.left < minX) minX = b.left;
          if (b.right > maxX) maxX = b.right;
        }
        expect(minX, lessThan(60));
        expect(maxX, greaterThan(20.0 + 3999 * 2.0 - 60));

        // Committed one-time builds stay in mesh/index budget.
        final mesh = stroke.ensureMeshVertices();
        expect(mesh, isNotNull);
        expect(
          stroke.getRawPositions().length ~/ 2,
          lessThanOrEqualTo(Stroke.kMaxMeshVertices),
        );
      });

      test('$toolId dense zigzag stages without OOM/crash', () {
        final stroke = _liveStroke(toolId);
        _drawZigzag(stroke, 3000);

        expect(stroke.hasLiveStaging, isTrue);
        final tailPoints = stroke.length - 1 - stroke.debugLiveFrozenEnd;
        expect(tailPoints, lessThanOrEqualTo(512));
        expect(stroke.highQualityPath.getBounds().isEmpty, isFalse);

        final mesh = stroke.ensureMeshVertices();
        expect(mesh, isNotNull);
        final vertexCount = stroke.getRawPositions().length ~/ 2;
        expect(vertexCount, greaterThan(0));
        expect(vertexCount, lessThanOrEqualTo(Stroke.kMaxMeshVertices));
        for (final index in stroke.getRawIndices()) {
          expect(index, lessThan(vertexCount));
        }
      });
    }

    test('live per-frame work stops growing with stroke length', () {
      // The reported bug: longer stroke => more jank per frame. With
      // staging, a 4x longer smooth stroke keeps the same bounded tail.
      final short = _liveStroke(ToolId.ballpointPen);
      _drawSmoothLine(short, 1000);
      final long = _liveStroke(ToolId.ballpointPen);
      _drawSmoothLine(long, 4000);
      expect(short.hasLiveStaging, isTrue);
      expect(long.hasLiveStaging, isTrue);
      final shortTail = short.length - 1 - short.debugLiveFrozenEnd;
      final longTail = long.length - 1 - long.debugLiveFrozenEnd;
      expect(shortTail, lessThanOrEqualTo(512));
      expect(longTail, lessThanOrEqualTo(512));
      // Frozen prefix absorbs the growth: same tail window either way.
      expect((longTail - shortTail).abs(), lessThan(256));
    });

    test('modeled Advanced pen (default builder) stages long strokes', () {
      // Default brush pipeline (spring-mass modeler, Rnote-style): raw input
      // is its event stream, so decimation does not apply — but staging and
      // the sample cap still bound the work.
      final stroke = Stroke(
        color: Colors.black,
        pressureEnabled: true,
        options: StrokeOptions(
          size: 4,
          smoothing: 0.42,
          streamline: 0.18,
          simulatePressure: false,
          isComplete: false,
        ),
        pageIndex: 0,
        page: HasSize(EditorPage.defaultSize),
        toolId: ToolId.advancedPen,
      );
      expect(stroke.brushOptions.builderType, AdvancedPenBuilderType.modeled);
      _drawSmoothLine(stroke, 4000);

      expect(stroke.hasLiveStaging, isTrue);
      final chunks = stroke.liveStagedChunks;
      expect(chunks, isNotEmpty);
      expect(chunks.any((c) => c.path != null), isTrue);
      final bounds = stroke.highQualityPath.getBounds();
      expect(bounds.isEmpty, isFalse);
      expect(bounds.left, lessThan(40));
    });
  });

  group('sample cap (no OOM)', () {
    test('minutes-long scribble stays one bounded stroke', () {
      final stroke = _liveStroke(ToolId.ballpointPen);
      for (var i = 0; i < 9000; i++) {
        final x = 20.0 + i * 2.5;
        final y = 90.0 + (i % 23) * 1.7 + (i % 5) * 0.3;
        stroke.addPoint(
          Offset(x, y),
          null,
          Duration(microseconds: i * 4166),
        );
      }

      expect(stroke.length, lessThanOrEqualTo(Stroke.kMaxStrokeSamples));
      // Endpoints survive thinning: caps/joins stay where the pen was.
      expect(stroke.points.first.x, closeTo(20.0, 1.0));
      expect(
        stroke.points.last.x,
        greaterThan(20.0 + 8999 * 2.5 - 32),
      );

      expect(stroke.highQualityPath.getBounds().isEmpty, isFalse);
      expect(stroke.ensureMeshVertices(), isNotNull);
      expect(
        stroke.getRawPositions().length ~/ 2,
        lessThanOrEqualTo(Stroke.kMaxMeshVertices),
      );
    });

    test('pre-existing huge stroke (old file) meshes without overflow', () {
      final stroke = _liveStroke(ToolId.fountainPen);
      // Bypass live decimation to simulate a stroke saved before the fix.
      for (var i = 0; i < 6000; i++) {
        stroke.points.add(PointVector(10.0 + i * 1.5, 80.0 + (i % 11), 0.6));
      }
      stroke.finishLiveGeometry();

      final mesh = stroke.ensureMeshVertices();
      expect(mesh, isNotNull);
      final vertexCount = stroke.getRawPositions().length ~/ 2;
      expect(vertexCount, greaterThan(0));
      expect(vertexCount, lessThan(65535));
      for (final index in stroke.getRawIndices()) {
        expect(index, lessThan(vertexCount));
      }
      expect(stroke.highQualityPath.getBounds().isEmpty, isFalse);
    });
  });
}
