// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/mesh_warmup_worker.dart';
import 'package:saber/data/editor/stroke_paint.dart';
import 'package:saber/data/tools/_tool.dart';

import '../../helpers/test_stroke_factory.dart';

bool _f32Equals(Float32List a, Float32List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _u16Equals(Uint16List a, Uint16List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Float32List _pack(Stroke s) {
  final pts = s.points;
  final xyz = Float32List(pts.length * 3);
  for (var k = 0; k < pts.length; k++) {
    xyz[k * 3] = pts[k].x;
    xyz[k * 3 + 1] = pts[k].y;
    xyz[k * 3 + 2] = pts[k].pressure ?? 0.5;
  }
  return xyz;
}

/// UI reference through the same static core the worker drives (no instance
/// warming side effects here; paint-path equivalence is covered by the
/// tiled suites).
Map<String, Object?>? _uiReference(Stroke s) {
  if (!strokeNeedsMeshWarmup(s)) return null;
  final arrays = Stroke.buildSpineMeshArrays(
    packedBase: _pack(s),
    predictedTail: null,
    toolId: s.toolId,
    flatEdge: s.flatEdge,
    size: s.options.size,
    smoothing: s.options.smoothing,
    simulatePressure: s.options.simulatePressure,
    isComplete: s.options.isComplete,
    startCap: s.options.start.cap,
    startTaper: s.options.start.taperEnabled,
    startCustomTaper: s.options.start.customTaper,
    endCap: s.options.end.cap,
    endTaper: s.options.end.taperEnabled,
    endCustomTaper: s.options.end.customTaper,
    pressureMapsToCoverage: s.paint.pressureMapsToCoverage,
    pressureEnabled: s.pressureEnabled,
    targetScale: 1.0,
  );
  if (arrays == null) return null;
  return <String, Object?>{
    'pos': arrays.positions,
    'idx': arrays.indices,
    'col': arrays.colors,
  };
}

List<Stroke> _corpus() {
  final strokes = <Stroke>[
    testPolylineStroke(toolId: ToolId.ballpointPen, y: 80, points: 90),
    testPolylineStroke(toolId: ToolId.fountainPen, y: 160, points: 90),
    testPolylineStroke(toolId: ToolId.calligraphyPen, y: 240, points: 90),
    testPolylineStroke(
      toolId: ToolId.ballpointPen,
      y: 320,
      x0: 10,
      x1: 700,
      points: 300,
    ),
    testPolylineStroke(toolId: ToolId.ballpointPen, y: 400, points: 2),
  ];
  final neon = testPolylineStroke(toolId: ToolId.ballpointPen, y: 480);
  neon.neon = true;
  strokes.add(neon);
  final pencil = testPolylineStroke(toolId: ToolId.advancedPencil, y: 560);
  pencil.paint = const StrokePaint(
    mode: StrokePaintMode.pencilNoise,
    pressureMapsToCoverage: true,
  );
  strokes.add(pencil);
  // Path-only tool: worker must decline (null), UI paints it via paths.
  strokes.add(testPolylineStroke(toolId: ToolId.advancedPen, y: 640));
  return strokes;
}

void main() {
  test('strokeNeedsMeshWarmup gate', () {
    expect(
      strokeNeedsMeshWarmup(
        testPolylineStroke(toolId: ToolId.ballpointPen),
      ),
      isTrue,
    );
    expect(
      strokeNeedsMeshWarmup(
        testPolylineStroke(toolId: ToolId.highlighter),
      ),
      isFalse,
    );
    expect(
      strokeNeedsMeshWarmup(
        testPolylineStroke(toolId: ToolId.advancedPen),
      ),
      isFalse,
    );
    final one = testPolylineStroke(toolId: ToolId.ballpointPen);
    one.points.removeRange(1, one.points.length);
    expect(strokeNeedsMeshWarmup(one), isFalse);
  });

  test('worker meshes are byte-identical to UI meshes', () async {
    final strokes = _corpus();
    final gated = <int>[
      for (var i = 0; i < strokes.length; i++)
        if (strokeNeedsMeshWarmup(strokes[i])) i,
    ];
    expect(gated, isNotEmpty);
    final dtos = [
      for (final i in gated) meshWarmupRequestFor(strokes[i]),
    ];
    final uiRefs = <Map<String, Object?>?>[
      for (final i in gated) _uiReference(strokes[i]),
    ];

    // Real isolate (also proves the transitive imports are isolate-safe).
    final results = await warmStrokeMeshesInBackground({'strokes': dtos});
    expect(results, isNotNull);
    expect(results!.length, dtos.length);

    var compared = 0;
    for (var k = 0; k < gated.length; k++) {
      final i = gated[k];
      final res = results[k];
      final ref = uiRefs[k];
      if (ref == null) {
        expect(res, isNull, reason: 'worker should decline stroke $i');
        continue;
      }
      expect(res, isNotNull, reason: 'worker declined stroke $i');
      expect(
        _f32Equals(
          res!['pos'] as Float32List,
          ref['pos'] as Float32List,
        ),
        isTrue,
        reason: 'positions differ for stroke $i',
      );
      expect(
        _u16Equals(res['idx'] as Uint16List, ref['idx'] as Uint16List),
        isTrue,
        reason: 'indices differ for stroke $i',
      );
      final refColors = ref['col'] as Int32List?;
      final resColors = res['col'] as Int32List?;
      if (refColors == null) {
        expect(resColors, isNull);
      } else {
        expect(resColors, isNotNull);
        expect(resColors!.length, refColors.length);
        for (var j = 0; j < refColors.length; j++) {
          expect(resColors[j], refColors[j]);
        }
      }
      compared++;
    }
    expect(compared, greaterThan(0));
  });

  test('adoptBackgroundMesh guards stale results', () async {
    final s = testPolylineStroke(
      toolId: ToolId.ballpointPen,
      y: 100,
      points: 120,
    );
    final dto = meshWarmupRequestFor(s);
    final results = await warmStrokeMeshesInBackground({
      'strokes': [dto],
    });
    final res = results![0]!;
    final shipCount = s.points.length;
    final first = s.points.first;
    final last = s.points.last;

    // Mutated after shipping: must refuse.
    s.points.removeAt(0);
    expect(
      s.adoptBackgroundMesh(
        positions: res['pos'] as Float32List,
        indices: res['idx'] as Uint16List,
        colors: res['col'] as Int32List?,
        pointCount: shipCount,
        firstX: first.x,
        firstY: first.y,
        lastX: last.x,
        lastY: last.y,
      ),
      isFalse,
    );
    expect(s.hasCachedMesh, isFalse);

    // Identical twin attaches fine.
    final t = testPolylineStroke(
      toolId: ToolId.ballpointPen,
      y: 100,
      points: 120,
    );
    expect(
      t.adoptBackgroundMesh(
        positions: res['pos'] as Float32List,
        indices: res['idx'] as Uint16List,
        colors: res['col'] as Int32List?,
        pointCount: t.points.length,
        firstX: t.points.first.x,
        firstY: t.points.first.y,
        lastX: t.points.last.x,
        lastY: t.points.last.y,
      ),
      isTrue,
    );
    expect(t.hasCachedMesh, isTrue);
  });
}
