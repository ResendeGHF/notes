// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/tools/lasso_coverage_mask.dart';

void main() {
  group('LassoCoverageMask', () {
    test('rejects a loop with no area', () {
      expect(
        LassoCoverageMask.fromPolyline(const [Offset(1, 1), Offset(2, 2)]),
        isNull,
      );
      expect(
        LassoCoverageMask.fromPolyline(const [
          Offset.zero,
          Offset(10, 0),
          Offset(20, 0),
        ]),
        isNull,
      );
    });

    test('square agrees with Path.contains away from the boundary', () {
      final poly = <Offset>[
        const Offset(10, 10),
        const Offset(110, 10),
        const Offset(110, 80),
        const Offset(10, 80),
      ];
      final mask = LassoCoverageMask.fromPolyline(poly);
      expect(mask, isNotNull);
      final path = Path()..addPolygon(poly, true);

      var checked = 0;
      var mismatches = 0;
      for (var y = 0.0; y <= 100; y += 2) {
        for (var x = 0.0; x <= 130; x += 2) {
          final point = Offset(x, y);
          if (_nearRectEdge(point, const Rect.fromLTRB(10, 10, 110, 80), 1.5)) {
            continue;
          }
          checked++;
          if (mask!.contains(point) != path.contains(point)) mismatches++;
        }
      }
      expect(checked, greaterThan(200));
      expect(mismatches, 0);
    });

    test('concave notch stays empty', () {
      // Rectangle with a rectangular bite taken out of the left side.
      final poly = <Offset>[
        Offset.zero,
        const Offset(100, 0),
        const Offset(100, 100),
        const Offset(0, 100),
        const Offset(0, 70),
        const Offset(60, 70),
        const Offset(60, 30),
        const Offset(0, 30),
      ];
      final mask = LassoCoverageMask.fromPolyline(poly)!;
      final path = Path()..addPolygon(poly, true);

      expect(mask.contains(const Offset(80, 50)), isTrue);
      expect(path.contains(const Offset(80, 50)), isTrue);
      expect(mask.contains(const Offset(20, 50)), isFalse);
      expect(path.contains(const Offset(20, 50)), isFalse);
      expect(mask.contains(const Offset(80, 20)), isTrue);
      expect(mask.contains(const Offset(-10, 50)), isFalse);
    });

    test('self-intersecting bowtie matches nonzero Path.contains', () {
      final poly = <Offset>[
        Offset.zero,
        const Offset(100, 100),
        const Offset(0, 100),
        const Offset(100, 0),
      ];
      final mask = LassoCoverageMask.fromPolyline(poly)!;
      final path = Path()..addPolygon(poly, true);

      var mismatches = 0;
      var checked = 0;
      for (var y = 5.0; y < 95; y += 5) {
        for (var x = 5.0; x < 95; x += 5) {
          final point = Offset(x, y);
          final distDiag = (x - y).abs() / math.sqrt2;
          final distAnti = (x + y - 100).abs() / math.sqrt2;
          if (distDiag < 1.5 || distAnti < 1.5) continue;
          checked++;
          if (mask.contains(point) != path.contains(point)) mismatches++;
        }
      }
      expect(checked, greaterThan(50));
      expect(mismatches, 0);
    });
  });
}

bool _nearRectEdge(Offset point, Rect rect, double band) {
  final inside =
      point.dx >= rect.left - band &&
      point.dx <= rect.right + band &&
      point.dy >= rect.top - band &&
      point.dy <= rect.bottom + band;
  if (!inside) return false;
  final dx = math.min(
    (point.dx - rect.left).abs(),
    (point.dx - rect.right).abs(),
  );
  final dy = math.min(
    (point.dy - rect.top).abs(),
    (point.dy - rect.bottom).abs(),
  );
  final outside = !rect.contains(point);
  if (outside) return dx <= band || dy <= band || (dx <= band && dy <= band);
  return dx <= band || dy <= band;
}
