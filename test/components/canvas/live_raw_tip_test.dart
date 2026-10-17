// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

// Live raw-tip truth: the displayed stroke must touch the pen at stroke ends.
//
// Committed samples trail the 1€ stabilization filter while the Kalman
// lookahead collapses exactly when decelerating/stopping, so without a raw
// truth connector the last millimetres of ink only appear after pen-up —
// worse the heavier the smoothing. These tests pin the connector (live) and
// its commit (pen-up keeps what was shown, no snap-back).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/services/display_ink_feel.dart';

Stroke _liveBallpoint() => Stroke(
      color: Colors.black,
      pressureEnabled: false,
      options: StrokeOptions(
        size: 4,
        smoothing: 0.42,
        streamline: 0.18,
        thinning: 0,
        simulatePressure: false,
        isComplete: false,
        start: StrokeEndOptions.start(cap: true, taperEnabled: false),
        end: StrokeEndOptions.end(cap: true, taperEnabled: false),
      ),
      pageIndex: 0,
      page: HasSize(EditorPage.defaultSize),
      toolId: ToolId.ballpointPen,
    );

/// Fast cruise (as production feeds it: predictor + raw note + stabilization
/// per sample) followed by a slow decel tail, mirroring a pen slowing into a
/// stop. Returns the last raw event position (the pen truth).
Offset _cruiseThenDecel(
  Stroke stroke, {
  double decelStep = 1.0,
  int decelSamples = 6,
}) {
  for (var i = 0; i < 30; i++) {
    final pos = Offset(i * 12.5, i * 6.0);
    final time = Duration(milliseconds: i * 4);
    stroke.recordPredictionSample(pos, 0.6, time, accurateTool: true);
    stroke.noteRawLiveTip(pos, 0.6, time);
    stroke.addPoint(pos, 0.6, time);
  }
  final cruiseTip = stroke.points.last;
  var lastRaw = Offset.zero;
  for (var i = 1; i <= decelSamples; i++) {
    lastRaw = Offset(
      cruiseTip.x + i * decelStep,
      cruiseTip.y + i * decelStep * 0.5,
    );
    final time = Duration(milliseconds: 120 + i * 8);
    stroke.recordPredictionSample(lastRaw, 0.6, time, accurateTool: true);
    // Production notes every raw event, even absorbed sub-threshold ones.
    stroke.noteRawLiveTip(lastRaw, 0.6, time);
    stroke.addPoint(lastRaw, 0.6, time);
  }
  return lastRaw;
}

double _liveCovers(Stroke stroke, Offset rawTip) {
  var best = double.infinity;
  for (final p in stroke.livePoints) {
    final d = (p - rawTip).distance;
    if (d < best) best = d;
  }
  return best;
}

void main() {
  group('live raw-tip truth', () {
    test('decel end reaches the pen live and stays on pen-up', () {
      final stroke = _liveBallpoint();
      final lastRaw = _cruiseThenDecel(stroke);
      // The live ink must touch the last raw event (nib radius + epsilon).
      expect(_liveCovers(stroke, lastRaw), lessThan(4.0 / 2 + 1.5));
      final liveBounds = stroke.highQualityPath.getBounds();
      stroke.finishLiveGeometry();
      final committedBounds = stroke.highQualityPath.getBounds();
      // No snap-back of the shown end, and the truth is kept.
      expect(committedBounds.right,
          greaterThanOrEqualTo(liveBounds.right - 4.0));
      expect(committedBounds.right, greaterThan(lastRaw.dx - 2.0));
    });

    test('heavy smoothing: raw truth fills the filter lag', () {
      final prevPred = stows.strokePrediction.value;
      final prevStab = stows.strokeStabilizationAmount.value;
      stows.strokePrediction.value = false;
      stows.strokeStabilizationAmount.value = 1.0;
      DisplayInkFeel.instance.updateRefreshHz(120);
      try {
        final stroke = _liveBallpoint();
        final lastRaw = _cruiseThenDecel(stroke, decelStep: 4.0);
        final filterGap = (stroke.points.last - lastRaw).distance;
        // Sanity: the filter really does trail here (else the test is vacuous).
        expect(filterGap, greaterThan(0.75));
        // Live ink still reaches the raw pen despite the lag.
        expect(_liveCovers(stroke, lastRaw), lessThan(4.0 / 2 + 1.5));
        stroke.finishLiveGeometry();
        expect(stroke.highQualityPath.getBounds().right,
            greaterThan(lastRaw.dx - 2.0));
      } finally {
        stows.strokePrediction.value = prevPred;
        stows.strokeStabilizationAmount.value = prevStab;
        DisplayInkFeel.instance.updateRefreshHz(60);
      }
    });

    test('mesh live path carries the raw tip too (ballpoint tail mesh)', () {
      final prevPred = stows.strokePrediction.value;
      final prevStab = stows.strokeStabilizationAmount.value;
      stows.strokePrediction.value = false;
      stows.strokeStabilizationAmount.value = 1.0;
      DisplayInkFeel.instance.updateRefreshHz(120);
      try {
        final stroke = _liveBallpoint();
        final lastRaw = _cruiseThenDecel(stroke, decelStep: 4.0);
        final verts = stroke.vertices;
        expect(verts, isNotNull);
        // The GPU mesh (what the painter draws for mesh pens) must reach the
        // raw pen, not just the polygon path.
        final rawPositions = stroke.getRawPositions();
        var meshRight = double.negativeInfinity;
        for (var i = 0; i + 1 < rawPositions.length; i += 2) {
          if (rawPositions[i] > meshRight) meshRight = rawPositions[i];
        }
        expect(meshRight, greaterThan(lastRaw.dx - 2.0));
      } finally {
        stows.strokePrediction.value = prevPred;
        stows.strokeStabilizationAmount.value = prevStab;
        DisplayInkFeel.instance.updateRefreshHz(60);
      }
    });
  });
}
