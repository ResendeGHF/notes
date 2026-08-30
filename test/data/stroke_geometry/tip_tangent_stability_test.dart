import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/stroke_geometry/constant_width_outline.dart';
import 'package:saber/data/stroke_geometry/point_vector.dart';

void main() {
  group('tip tangents ignore put-down / lift jitter', () {
    test('opening tangent follows the stroke, not a micro wiggle', () {
      // Tiny sideways jitter at the start, then a clear rightward stroke.
      final points = <PointVector>[
        const PointVector(0, 0),
        const PointVector(0.05, 0.8), // jitter
        const PointVector(0.1, -0.6), // jitter
        const PointVector(3, 0.1),
        const PointVector(8, 0.2),
        const PointVector(16, 0.15),
      ];
      final (tx, ty) = localOpeningChordTangent(points, baseSize: 2);
      // Should be mostly +X.
      expect(tx, greaterThan(0.85));
      expect(ty.abs(), lessThan(0.5));
      final len = math.sqrt(tx * tx + ty * ty);
      expect(len, closeTo(1.0, 1e-6));
    });

    test('closing tangent follows the stroke, not a tip flick', () {
      final points = <PointVector>[
        const PointVector(0, 0),
        const PointVector(8, 0),
        const PointVector(16, 0.1),
        const PointVector(16.05, 0.9), // flick
        const PointVector(16.1, -0.5), // flick
      ];
      final (tx, ty) = localClosingChordTangent(points, baseSize: 2);
      expect(tx, greaterThan(0.7));
      expect(ty.abs(), lessThan(0.55));
    });

    test('mesh packed tip helpers stay unit-length', () {
      // Smoke: packed xyz floats (pressure in z) used by Stroke mesh path.
      final pts = Float32List.fromList([
        0, 0, 0.5,
        0.04, 0.7, 0.5,
        4, 0.05, 0.5,
        10, 0.1, 0.5,
      ]);
      // Exercise outline helpers which mirror mesh logic.
      final opening = localOpeningChordTangent(
        [
          PointVector(pts[0], pts[1], pts[2]),
          PointVector(pts[3], pts[4], pts[5]),
          PointVector(pts[6], pts[7], pts[8]),
          PointVector(pts[9], pts[10], pts[11]),
        ],
        baseSize: 2,
      );
      expect(math.sqrt(opening.$1 * opening.$1 + opening.$2 * opening.$2),
          closeTo(1.0, 1e-6));
    });
  });
}
