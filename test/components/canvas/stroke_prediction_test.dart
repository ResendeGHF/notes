// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/highlighter.dart';

/// Live-tip behavior of the EventMotionPredictor port wired into [Stroke]:
/// the transient tip extends live geometry along motion and vanishes on
/// commit (never persisted, never erased against).
void main() {
  group('Stroke EventMotionPredictor live tip', () {
    Stroke liveStroke(ToolId id, {double size = 4}) => Stroke(
          color: id == ToolId.highlighter
              ? Colors.yellow.withValues(alpha: 0.4)
              : Colors.black,
          pressureEnabled: true,
          options: StrokeOptions(
            size: size,
            simulatePressure: false,
            isComplete: false,
          ),
          pageIndex: 0,
          page: HasSize(EditorPage.defaultSize),
          toolId: id,
        );

    /// Fast diagonal flick at S-Pen rate: 12.5 px per 4 ms sample.
    /// Mirrors production: every raw sample is recorded, then committed.
    void cruise(Stroke stroke, {int n = 30, bool accurate = true}) {
      for (var i = 0; i < n; i++) {
        final pos = Offset(i * 12.5, i * 6.0);
        final time = Duration(milliseconds: i * 4);
        stroke.recordPredictionSample(pos, 0.6, time, accurateTool: accurate);
        stroke.addPoint(pos, 0.6, time);
      }
    }

    for (final id in [
      ToolId.ballpointPen,
      ToolId.fountainPen,
      ToolId.calligraphyPen,
      ToolId.advancedPen,
      ToolId.advancedPencil,
    ]) {
      test('$id live tip leads cruise, commit snaps back', () {
        final stroke = liveStroke(id);
        cruise(stroke);
        final last = stroke.points.last;
        final live = stroke.highQualityPath.getBounds();
        expect(
          live.right,
          greaterThan(last.x + 5.0),
          reason: '$id live leads past the last sample',
        );
        expect(
          live.bottom,
          greaterThan(last.y + 5.0),
          reason: '$id live leads diagonally',
        );
        stroke.finishLiveGeometry();
        final committed = stroke.highQualityPath.getBounds();
        expect(
          committed.right,
          lessThanOrEqualTo(last.x + stroke.options.size / 2 + 2.0),
          reason: '$id commit drops the transient tip',
        );
      });
    }

    test('freehand highlighter predicts; straight-line assist does not', () {
      final freehand = liveStroke(ToolId.highlighter, size: 20);
      cruise(freehand);
      final freeLast = freehand.points.last;
      expect(
        freehand.highQualityPath.getBounds().right,
        greaterThan(freeLast.x + 5.0),
        reason: 'freehand highlighter leads',
      );

      final prev = Highlighter.straightLine.value;
      Highlighter.straightLine.value = true;
      try {
        final snapped = liveStroke(ToolId.highlighter, size: 20);
        snapped.addPoint(const Offset(0, 0), null, Duration.zero);
        snapped.addPoint(
          const Offset(200, 3),
          null,
          const Duration(milliseconds: 16),
        );
        // Snapped to exactly 2 committed samples on y=0...
        expect(snapped.points.length, 2);
        // ...with no predicted tip dragging the end chord off the line.
        for (final pt in snapped.highQualityPolygon) {
          expect(
            pt.dy.abs(),
            lessThanOrEqualTo(10.5 + 20 / 2),
            reason: 'cap point $pt leaves the snapped band',
          );
        }
        final bounds = snapped.highQualityPath.getBounds();
        expect(
          bounds.right,
          lessThanOrEqualTo(200 + 20 / 2 + 2.0),
          reason: 'no prediction lead past the snapped end',
        );
      } finally {
        Highlighter.straightLine.value = prev;
      }
    });

    test('lead stays short: no giant tangent ruler', () {
      // Regression test for the oversized tangent lead: even on a fast
      // flick, the live tip stays within ~one frame of travel past the
      // last sample instead of stretching a long straight chord.
      final stroke = liveStroke(ToolId.ballpointPen);
      cruise(stroke);
      final last = stroke.points.last;
      final live = stroke.highQualityPath.getBounds();
      expect(live.right, greaterThan(last.x + 5.0));
      expect(
        live.right,
        lessThan(last.x + 60.0),
        reason: 'lead must stay on the order of one frame',
      );
    });

    test('tail continues forward without sideways sprout', () {
      // The anchored tail must extend along travel — never jump far or
      // sideways off the tip (the tangent-ruler artifact). Gap-fill
      // densifies committed steps, so the bound is scaled to the raw
      // sample step (12.5, 6.0), not to densified body steps.
      final stroke = liveStroke(ToolId.ballpointPen);
      cruise(stroke);
      final live = stroke.livePoints;
      expect(live.length, greaterThan(stroke.points.length));
      const rawStep = 13.9; // |(12.5, 6.0)|
      const travelX = 12.5 / rawStep;
      const travelY = 6.0 / rawStep;
      for (var i = stroke.points.length; i < live.length; i++) {
        final a = live[i - 1];
        final b = live[i];
        final dx = b.x - a.x;
        final dy = b.y - a.y;
        final len = math.sqrt(dx * dx + dy * dy);
        expect(len, lessThanOrEqualTo(rawStep * 1.5 + 2.0),
            reason: 'tail segment $i jumps');
        if (len > 1e-6) {
          final cos = (dx * travelX + dy * travelY) / len;
          expect(cos, greaterThan(0.7), reason: 'tail segment $i kinks');
        }
      }
    });

    test('stationary pointer grows no tail', () {
      final stroke = liveStroke(ToolId.ballpointPen);
      for (var i = 0; i < 8; i++) {
        stroke.addPoint(const Offset(50, 50), 0.6, Duration(milliseconds: i * 8));
      }
      final live = stroke.highQualityPath.getBounds();
      // A round dot, not a lead streak.
      expect(live.width, lessThan(12.0));
      expect(live.height, lessThan(12.0));
    });

    test('stylus leads further than touch at the same speed', () {
      Stroke cruised({required bool accurate}) {
        final stroke = liveStroke(ToolId.ballpointPen);
        // 1 dp/ms at pen rate.
        for (var i = 0; i < 30; i++) {
          final pos = Offset(i * 4.0, 0);
          final time = Duration(milliseconds: i * 4);
          stroke.recordPredictionSample(pos, 0.6, time, accurateTool: accurate);
          stroke.addPoint(pos, 0.6, time);
        }
        return stroke;
      }

      final stylus = cruised(accurate: true);
      final touch = cruised(accurate: false);
      final stylusLead =
          stylus.highQualityPath.getBounds().right - stylus.points.last.x;
      final touchLead =
          touch.highQualityPath.getBounds().right - touch.points.last.x;
      expect(stylusLead, greaterThan(2.0));
      expect(stylusLead, greaterThan(touchLead * 1.2));
    });

    test('turning tip drops the lead, straight run resumes it', () {
      // At a sharp turn the Kalman velocity still aims along the old
      // travel: projecting would spike a kink across the bend (bow-tie
      // hole + leaning end cap). Like a real pen, ink stays exactly under
      // the tip through the turn.
      final stroke = liveStroke(ToolId.ballpointPen);
      cruise(stroke);
      expect(stroke.livePoints.length, greaterThan(stroke.points.length),
          reason: 'straight cruise leads');
      // Hard 90° turn upward, 3 samples.
      final tip = stroke.points.last;
      for (var i = 1; i <= 3; i++) {
        final pos = Offset(tip.x, tip.y + i * 12.5);
        final time = Duration(milliseconds: 120 + i * 4);
        stroke.recordPredictionSample(pos, 0.6, time, accurateTool: true);
        stroke.addPoint(pos, 0.6, time);
      }
      expect(stroke.livePoints.length, stroke.points.length,
          reason: 'no lead across the turn');
      // Straighten out: the lead comes back once travel realigns.
      final tip2 = stroke.points.last;
      for (var i = 1; i <= 30; i++) {
        final pos = Offset(tip2.dx, tip2.dy + i * 12.5);
        final time = Duration(milliseconds: 132 + i * 4);
        stroke.recordPredictionSample(pos, 0.6, time, accurateTool: true);
        stroke.addPoint(pos, 0.6, time);
      }
      expect(stroke.livePoints.length, greaterThan(stroke.points.length),
          reason: 'lead resumes on straight run');
    });

    test('laser pointer stays prediction-free', () {
      final stroke = liveStroke(ToolId.laserPointer);
      cruise(stroke);
      final last = stroke.points.last;
      expect(
        stroke.highQualityPath.getBounds().right,
        lessThanOrEqualTo(last.x + stroke.options.size / 2 + 2.0),
      );
    });
  });
}
