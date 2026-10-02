// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/stroke_geometry/motion_event_predictor.dart';

void _cruise(
  MotionEventPredictor p, {
  int n = 30,
  double step = 12.5,
  double dtMs = 4,
  double pressure = 0.6,
}) {
  for (var i = 0; i < n; i++) {
    p.record(i * step, 0, pressure, i * dtMs);
  }
}

void main() {
  group('MotionEventPredictor (Kalman port)', () {
    test('cold filter predicts nothing', () {
      final p = MotionEventPredictor();
      _cruise(p, n: 3);
      expect(p.predictPolyline(predictionTargetMs: 16), isEmpty);
    });

    test('steady cruise projects a forward polyline', () {
      final p = MotionEventPredictor();
      _cruise(p);
      final tips = p.predictPolyline(predictionTargetMs: 16);
      expect(tips, isNotEmpty);
      // Last sample x=362.5; the polyline advances along +x past it.
      final tip = tips.last;
      expect(tip.x, greaterThan(362.5 + 10.0));
      for (final t in tips) {
        expect(t.y.abs(), lessThan(2.0));
        expect(t.x.isFinite && t.y.isFinite, isTrue);
      }
      // Monotonic advance along motion (no backtracking kinks).
      for (var i = 1; i < tips.length; i++) {
        expect(tips[i].x, greaterThanOrEqualTo(tips[i - 1].x));
      }
      expect(tip.pressure, closeTo(0.6, 0.05));
    });

    test('stationary pointer predicts nothing', () {
      final p = MotionEventPredictor();
      for (var i = 0; i < 8; i++) {
        p.record(50, 50, 0.6, i * 8.0);
      }
      // Duplicates are ignored, so the filter stays cold.
      expect(p.predictPolyline(predictionTargetMs: 16), isEmpty);
    });

    test('sharp reversal stays bounded (no overshoot explosion)', () {
      final p = MotionEventPredictor();
      for (var i = 0; i < 24; i++) {
        p.record(1000 + i * 12.5, 0, 0.6, i * 4.0);
      }
      // Hard reverse.
      for (var i = 1; i <= 3; i++) {
        p.record(1000 + 23 * 12.5 - i * 12.5, 0, 0.6, (23 + i) * 4.0);
      }
      final lastX = 1000 + 23 * 12.5 - 3 * 12.5;
      final tips = p.predictPolyline(predictionTargetMs: 16);
      if (tips.isNotEmpty) {
        // The polyline must stay in the neighborhood, never flung across
        // the canvas by stale velocity.
        for (final tip in tips) {
          expect((tip.x - lastX).abs(), lessThan(120.0));
          expect(tip.y.abs(), lessThan(60.0));
        }
      }
    });

    test('stylus predicts at full speed factor, finger ramps', () {
      MotionEventPredictor cruised() {
        final p = MotionEventPredictor();
        // 1 dp/ms cruise, long enough for the filter to settle.
        for (var i = 0; i < 30; i++) {
          p.record(i * 4.0, 0, 0.6, i * 4.0);
        }
        return p;
      }

      // Last sample is x=116.
      final stylusTips = cruised().predictPolyline(
        predictionTargetMs: 24,
        accurateTool: true,
      );
      final fingerTips = cruised().predictPolyline(
        predictionTargetMs: 24,
        accurateTool: false,
      );
      expect(stylusTips, isNotEmpty);
      expect(fingerTips, isNotEmpty);
      // Finger at 1 dp/ms moves at half the speed factor of stylus, so its
      // lead is roughly half the stylus lead.
      expect(
        stylusTips.last.x - 116.0,
        greaterThan((fingerTips.last.x - 116.0) * 1.2),
      );
    });

    test('velocity tracks per-sample travel', () {
      final p = MotionEventPredictor();
      expect(p.velocity.distance, 0.0);
      _cruise(p);
      // 12.5 px per 4 ms sample along +x.
      expect(p.velocity.dx, greaterThan(8.0));
      expect(p.velocity.dy.abs(), lessThan(2.0));
    });

    test('reset returns to cold', () {      final p = MotionEventPredictor();
      _cruise(p);
      expect(p.predictPolyline(predictionTargetMs: 16), isNotEmpty);
      p.reset();
      expect(p.predictPolyline(predictionTargetMs: 16), isEmpty);
    });

    test('slowing to a stop damps the lead', () {
      final p = MotionEventPredictor();
      var t = 0.0;
      var x = 0.0;
      var v = 20.0;
      for (var i = 0; i < 10; i++) {
        p.record(x, 0, 0.6, t);
        x += v;
        t += 8.0;
        v *= 0.55;
      }
      final tips = p.predictPolyline(predictionTargetMs: 16);
      // Nearly stopped: lead collapses instead of coasting on stale speed.
      for (final tip in tips) {
        expect((tip.x - x).abs(), lessThan(30.0));
      }
    });
  });
}
