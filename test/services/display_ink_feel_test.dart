// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' show FilterQuality;

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/services/display_ink_feel.dart';

void main() {
  group('DisplayInkFeel', () {
    tearDown(() {
      DisplayInkFeel.instance.updateRefreshHz(60);
    });

    test('60 Hz boosts prediction and eases stabilization', () {
      final feel = DisplayInkFeel.instance..updateRefreshHz(60);
      expect(feel.isLowRefresh, isTrue);
      expect(feel.stabilizationScale, closeTo(0.32, 0.001));
      expect(feel.predictionLookaheadBoostSec, closeTo(0.022, 0.001));
      expect(feel.predictionDistanceScale, greaterThan(1.4));
      expect(feel.rawTipBlend, closeTo(0.86, 0.001));
      expect(feel.maxGapFills, 2);
      expect(feel.panTouchSlopFactor, closeTo(0.35, 0.001));
      expect(feel.panDeltaGain, greaterThan(1.04));
      expect(feel.panVelocityLeadSec, greaterThan(0.01));
      expect(feel.zoomDeltaGain, greaterThan(1.05));
      expect(feel.movingBlitFilterQuality, FilterQuality.none);
      expect(feel.chromeThrottleInterval.inMilliseconds, greaterThanOrEqualTo(40));
      expect(feel.viewportSettleDelay.inMilliseconds, 120);
    });

    test('120 Hz keeps neutral knobs', () {
      final feel = DisplayInkFeel.instance..updateRefreshHz(120);
      expect(feel.isLowRefresh, isFalse);
      expect(feel.stabilizationScale, 1.0);
      expect(feel.predictionLookaheadBoostSec, 0.0);
      expect(feel.predictionDistanceScale, 1.0);
      expect(feel.rawTipBlend, 0.0);
      expect(feel.maxGapFills, 3);
      expect(feel.panTouchSlopFactor, 1.0);
      expect(feel.panDeltaGain, 1.0);
      expect(feel.panVelocityLeadSec, 0.0);
      expect(feel.zoomDeltaGain, 1.0);
      expect(feel.movingBlitFilterQuality, FilterQuality.low);
      expect(feel.viewportSettleDelay.inMilliseconds, 80);
    });

    test('settle delay is longer at 60 Hz than at 90 Hz', () {
      final feel = DisplayInkFeel.instance;
      feel.updateRefreshHz(60);
      final low = feel.viewportSettleDelay;
      feel.updateRefreshHz(90);
      final mid = feel.viewportSettleDelay;
      expect(low.inMilliseconds, greaterThan(mid.inMilliseconds));
      expect(mid.inMilliseconds, 90);
    });
  });
}
