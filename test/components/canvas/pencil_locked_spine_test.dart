// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/pencil_shader.dart';
import 'package:saber/data/stroke_geometry/point_vector.dart';

void main() {
  group('PencilShader.extendLockedSpine', () {
    test('freezes interior samples; only the tip moves', () {
      final locked = <PointVector>[];
      PencilShader.extendLockedSpine(
        locked: locked,
        tip: const PointVector(0, 0, 0.5),
        minSegLen: 8,
      );
      PencilShader.extendLockedSpine(
        locked: locked,
        tip: const PointVector(10, 0, 0.5),
        minSegLen: 8,
      );
      expect(locked, hasLength(2));

      PencilShader.extendLockedSpine(
        locked: locked,
        tip: const PointVector(12, 0.2, 0.5),
        minSegLen: 8,
      );
      // (10,0) already traveled minSeg from the start, so it freezes.
      expect(locked, hasLength(3));
      expect(locked[0].dx, 0);
      expect(locked[0].dy, 0);
      expect(locked[1].dx, 10);
      expect(locked[1].dy, 0);

      PencilShader.extendLockedSpine(
        locked: locked,
        tip: const PointVector(14, 0.1, 0.5),
        minSegLen: 8,
      );
      expect(locked, hasLength(3));
      expect(locked[1].dx, 10);
      expect(locked[1].dy, 0);
      expect(locked[2].dx, 14);
    });

    test('does not move earlier samples when the stroke loops', () {
      final locked = <PointVector>[];
      const tips = [
        PointVector(0, 0, 0.5),
        PointVector(10, 0, 0.5),
        PointVector(20, 0, 0.5),
        PointVector(20, 10, 0.5),
        PointVector(10, 10, 0.5),
        PointVector(0, 10, 0.5),
        PointVector(0, 0, 0.5),
      ];
      for (final tip in tips) {
        PencilShader.extendLockedSpine(locked: locked, tip: tip, minSegLen: 8);
      }
      expect(locked.first.dx, 0);
      expect(locked.first.dy, 0);
      expect(locked[1].dx, 10);
      expect(locked[1].dy, 0);
      expect(locked[2].dx, 20);
      expect(locked[2].dy, 0);
    });
  });
}
