// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:isolate';
import 'dart:typed_data';

import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_shape_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/tools/_tool.dart';

/// Background mesh triangulation for dense pages.
///
/// Triangulating thousands of strokes costs hundreds of milliseconds on the
/// UI isolate. This worker runs the EXACT same geometry ([Stroke.buildSpineMeshArrays],
/// single source of truth — no duplicated math) in a background isolate and
/// returns raw mesh arrays, which the UI attaches via [Stroke.adoptBackgroundMesh]
/// (guarded, identical).
///
/// Isolate-safety contract (do NOT break — `mesh_warmup_worker_test` runs a
/// real isolate and detonates loudly on violations):
/// - Messages carry only primitives, typed data, and plain Maps/Lists.
/// - Execution touches no platform channels, no GPU objects ([ui.Vertices]
///   is constructed on the UI side during attach), no singletons, no prefs.
///   Transitive imports may load UI libraries; using their bound resources
///   here would throw.
/// - Only committed-stroke inputs are warmed (no live prediction state).

/// Maximum strokes triangulated per worker call (bounds transient memory,
/// keeps each call to a few hundred milliseconds off-thread, and pipelines
/// attach progress across calls).
const int kMeshWarmupMaxStrokesPerCall = 750;

/// Minimum mesh-needing strokes for a page to be worth a worker call.
/// Smaller pages warm synchronously in microseconds; spawning costs more.
const int kMeshWarmupMinStrokes = 300;

/// Cheap gate: warming this stroke in the worker is plausible AND not yet
/// done. Must never build anything (reading `vertices` would triangulate on
/// the calling isolate, defeating the worker).
bool strokeNeedsMeshWarmup(Stroke s) {
  if (s.points.length < 2 || s.hasCachedMesh) return false;
  final tool = s.toolId;
  if (tool == ToolId.highlighter || tool == ToolId.advancedPen) return false;
  if (s is ShapeStroke || s is CircleStroke || s is RectangleStroke) {
    return false;
  }
  if (s.hasNonSolidPaint) return false;
  return true;
}

/// Sendable DTO for one stroke: packed samples plus every scalar the mesh
/// core reads. Keep in sync with [Stroke.buildSpineMeshArrays] parameters.
Map<String, Object?> meshWarmupRequestFor(Stroke s) {
  final pts = s.points;
  final xyz = Float32List(pts.length * 3);
  for (var k = 0; k < pts.length; k++) {
    final p = pts[k];
    xyz[k * 3] = p.x;
    xyz[k * 3 + 1] = p.y;
    xyz[k * 3 + 2] = p.pressure ?? 0.5;
  }
  return <String, Object?>{
    'xyz': xyz,
    'tool': s.toolId.index,
    'size': s.options.size,
    'smo': s.options.smoothing,
    'simP': s.options.simulatePressure,
    'complete': s.options.isComplete,
    'scap': s.options.start.cap,
    'stap': s.options.start.taperEnabled,
    'sct': s.options.start.customTaper,
    'ecap': s.options.end.cap,
    'etap': s.options.end.taperEnabled,
    'ect': s.options.end.customTaper,
    'flat': s.flatEdge,
    'pmc': s.paint.pressureMapsToCoverage,
    'pe': s.pressureEnabled,
  };
}

/// Runs [warmStrokeMeshes] in a background isolate. Returns null on any
/// failure — callers must treat null as "warm synchronously instead".
Future<List<Map<String, Object?>?>?> warmStrokeMeshesInBackground(
  Map<String, Object?> request,
) async {
  try {
    return await Isolate.run(() => warmStrokeMeshes(request));
  } catch (_) {
    return null;
  }
}

/// Isolate entry: triangulate one batch. Pure function of [request].
Future<List<Map<String, Object?>?>> warmStrokeMeshes(
  Map<String, Object?> request,
) async {
  final raw = request['strokes'] as List;
  final out = <Map<String, Object?>?>[];
  for (final item in raw) {
    out.add(_warmOneStroke(item as Map<String, Object?>));
  }
  return out;
}

Map<String, Object?>? _warmOneStroke(Map<String, Object?> r) {
  try {
    final xyz = r['xyz'] as Float32List;
    if (xyz.length < 6) return null;
    final arrays = Stroke.buildSpineMeshArrays(
      packedBase: xyz,
      predictedTail: null,
      toolId: ToolId.values[(r['tool'] as num).toInt()],
      flatEdge: r['flat'] as bool,
      size: (r['size'] as num).toDouble(),
      smoothing: (r['smo'] as num).toDouble(),
      simulatePressure: r['simP'] as bool,
      isComplete: r['complete'] as bool,
      startCap: r['scap'] as bool,
      startTaper: r['stap'] as bool,
      startCustomTaper: (r['sct'] as num?)?.toDouble(),
      endCap: r['ecap'] as bool,
      endTaper: r['etap'] as bool,
      endCustomTaper: (r['ect'] as num?)?.toDouble(),
      pressureMapsToCoverage: r['pmc'] as bool,
      pressureEnabled: r['pe'] as bool,
      targetScale: 1.0,
    );
    if (arrays == null ||
        arrays.positions.isEmpty ||
        arrays.indices.isEmpty) {
      return null;
    }
    return <String, Object?>{
      'pos': arrays.positions,
      'idx': arrays.indices,
      'col': arrays.colors,
    };
  } catch (_) {
    // One bad stroke never kills the batch; the UI warms it on demand.
    return null;
  }
}
