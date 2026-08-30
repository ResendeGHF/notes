// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/stroke_geometry/outline_triangulate.dart';

void main() {
  group('OutlineTriangulator', () {
    test('triangulates a CCW square', () {
      const ring = [
        Offset.zero,
        Offset(10, 0),
        Offset(10, 10),
        Offset(0, 10),
      ];
      final mesh = OutlineTriangulator.triangulate(ring);
      expect(mesh, isNotNull);
      expect(mesh!.positions.length, 8);
      expect(mesh.indices.length, 6);
    });

    test('triangulates a clockwise triangle after reversing', () {
      const ring = [
        Offset.zero,
        Offset(0, 4),
        Offset(3, 0),
      ];
      final mesh = OutlineTriangulator.triangulate(ring);
      expect(mesh, isNotNull);
      expect(mesh!.indices.length, 3);
    });

    test('returns null for a self-intersecting bowtie', () {
      const ring = [
        Offset.zero,
        Offset(4, 4),
        Offset(4, 0),
        Offset(0, 4),
      ];
      expect(OutlineTriangulator.triangulate(ring), isNull);
    });

    test('returns null for a degenerate line', () {
      const ring = [Offset.zero, Offset(1, 0), Offset(2, 0)];
      expect(OutlineTriangulator.triangulate(ring), isNull);
    });
  });

  group('mergeStrokeMeshes', () {
    test('concatenates two triangles into one Vertices', () {
      final a = (
        Float32List.fromList(const [0, 0, 1, 0, 0, 1]),
        Uint16List.fromList(const [0, 1, 2]),
      );
      final b = (
        Float32List.fromList(const [2, 0, 3, 0, 2, 1]),
        Uint16List.fromList(const [0, 1, 2]),
      );
      final merged = mergeStrokeMeshes([a, b]);
      expect(merged, hasLength(1));
    });
  });
}
