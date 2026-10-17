// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

// Tile-local clipping: committed long strokes must replay only local
// geometry per tile (zoom/pan), instead of the whole mesh/path per tile.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';
import 'package:saber/data/tools/_tool.dart';

Stroke _committedLine({int samples = 3000}) {
  final stroke = Stroke(
    color: Colors.black,
    pressureEnabled: false,
    options: StrokeOptions(
      size: 4,
      smoothing: 0.42,
      streamline: 0.18,
      simulatePressure: false,
      isComplete: true,
    ),
    pageIndex: 0,
    page: HasSize(EditorPage.defaultSize),
    toolId: ToolId.ballpointPen,
  );
  for (var i = 0; i < samples; i++) {
    stroke.points.add(PointVector(10.0 + i * 2.0, 100.0, 0.5));
  }
  stroke.markPolygonNeedsUpdating();
  return stroke;
}

void main() {
  group('clipPolygonToRect', () {
    test('fully-inside polygon returns identical', () {
      final poly = [
        const Offset(10, 10),
        const Offset(50, 10),
        const Offset(50, 50),
        const Offset(10, 50),
      ];
      final out = Stroke.clipPolygonToRect(
        poly,
        const Rect.fromLTWH(0, 0, 100, 100),
      );
      expect(out, equals(poly));
    });

    test('fully-outside polygon returns empty', () {
      final poly = [
        const Offset(200, 200),
        const Offset(250, 200),
        const Offset(250, 250),
      ];
      final out = Stroke.clipPolygonToRect(
        poly,
        const Rect.fromLTWH(0, 0, 100, 100),
      );
      expect(out, isEmpty);
    });

    test('straddling polygon stays inside the clip', () {
      final poly = [
        const Offset(-50, 50),
        const Offset(50, 50),
        const Offset(50, 150),
        const Offset(-50, 150),
      ];
      const clip = Rect.fromLTWH(0, 0, 100, 100);
      final out = Stroke.clipPolygonToRect(poly, clip);
      expect(out, isNotEmpty);
      expect(out.length, lessThan(poly.length + 8));
      for (final p in out) {
        expect(p.dx, greaterThanOrEqualTo(-1e-6));
        expect(p.dx, lessThanOrEqualTo(100 + 1e-6));
        expect(p.dy, greaterThanOrEqualTo(-1e-6));
        expect(p.dy, lessThanOrEqualTo(100 + 1e-6));
      }
    });
  });

  group('clipMeshArrays', () {
    test('buckets triangles and compacts vertices', () {
      // Two disjoint quads (4 verts / 2 tris each) far apart.
      final positions = Float32List.fromList([
        0, 0, 10, 0, 10, 10, 0, 10, // quad A
        1000, 1000, 1010, 1000, 1010, 1010, 1000, 1010, // quad B
      ]);
      final indices = Uint16List.fromList([0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7]);
      final part = Stroke.clipMeshArrays(
        positions,
        indices,
        null,
        const Rect.fromLTWH(-50, -50, 200, 200),
      );
      expect(part, isNotNull);
      // Only quad A's triangles survive, compacted to 4 verts.
      expect(part!.indices.length, equals(6));
      expect(part.positions.length, equals(8));
      for (final index in part.indices) {
        expect(index, lessThan(4));
      }
      // Fully-outside clip returns null.
      expect(
        Stroke.clipMeshArrays(
          positions,
          indices,
          null,
          const Rect.fromLTWH(5000, 5000, 100, 100),
        ),
        isNull,
      );
      // Fully-inside clip returns the original arrays (no copy).
      final whole = Stroke.clipMeshArrays(
        positions,
        indices,
        null,
        const Rect.fromLTWH(-100, -100, 10000, 10000),
      );
      expect(whole, isNotNull);
      expect(identical(whole!.positions, positions), isTrue);
    });
  });

  group('committed long stroke tile replay', () {
    test('per-tile mesh replay is a fraction of the full mesh', () {
      final stroke = _committedLine(samples: 3000);
      final full = stroke.getRawPositions();
      expect(full.length ~/ 2, greaterThan(1000));

      // Left quarter tile of the 6k-long stroke.
      const tile = Rect.fromLTWH(0, 0, 1500, 512);
      final part = Stroke.clipMeshArrays(
        stroke.getRawPositions(),
        stroke.getRawIndices(),
        stroke.getRawColors(),
        tile,
      );
      expect(part, isNotNull);
      expect(
        part!.positions.length,
        lessThan(full.length ~/ 2),
        reason: 'tile must replay far less than the full mesh',
      );
      final vcount = part.positions.length ~/ 2;
      for (final index in part.indices) {
        expect(index, lessThan(vcount));
      }
    });

    test('per-tile path replay is a fraction of the full outline', () {
      final stroke = _committedLine(samples: 3000);
      final full = stroke.highQualityPolygon;
      expect(full.length, greaterThan(1000));

      const tile = Rect.fromLTWH(0, 0, 1500, 512);
      final clipped = Stroke.clipPolygonToRect(full, tile, bleed: 1.0);
      expect(clipped, isNotEmpty);
      expect(
        clipped.length,
        lessThan(full.length ~/ 2),
        reason: 'tile must replay far less than the full outline',
      );
      for (final p in clipped) {
        expect(p.dx, greaterThanOrEqualTo(-1 - 1e-6));
        expect(p.dx, lessThanOrEqualTo(1501 + 1e-6));
      }
    });
  });
}
