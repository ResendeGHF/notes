// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' show FilterQuality;

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/prefs.dart';
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
      expect(feel.maxGapFills, 2);
      expect(feel.panTouchSlopFactor, closeTo(0.35, 0.001));
      expect(feel.panDeltaGain, greaterThan(1.04));
      expect(feel.panVelocityLeadSec, greaterThan(0.01));
      expect(feel.zoomDeltaGain, greaterThan(1.05));
      expect(feel.movingBlitFilterQuality, FilterQuality.none);
      expect(feel.chromeThrottleInterval.inMilliseconds, greaterThanOrEqualTo(40));
      expect(feel.viewportSettleDelay.inMilliseconds, 250);
    });

    test('120 Hz keeps neutral knobs', () {
      final feel = DisplayInkFeel.instance..updateRefreshHz(120);
      expect(feel.isLowRefresh, isFalse);
      expect(feel.stabilizationScale, 1.0);
      expect(feel.maxGapFills, 3);
      expect(feel.panTouchSlopFactor, 1.0);
      expect(feel.panDeltaGain, 1.0);
      expect(feel.panVelocityLeadSec, 0.0);
      expect(feel.zoomDeltaGain, 1.0);
      expect(feel.movingBlitFilterQuality, FilterQuality.low);
      expect(feel.viewportSettleDelay.inMilliseconds, 180);
    });

    test('settle delay is longer at 60 Hz than at 90 Hz', () {
      final feel = DisplayInkFeel.instance;
      feel.updateRefreshHz(60);
      final low = feel.viewportSettleDelay;
      feel.updateRefreshHz(90);
      final mid = feel.viewportSettleDelay;
      expect(low.inMilliseconds, greaterThanOrEqualTo(mid.inMilliseconds));
      expect(mid.inMilliseconds, 250);
    });
  });

  group('DisplayInkFeel canvas performance presets', () {
    setUp(() {
      DisplayInkFeel.instance.updateRefreshHz(120);
    });

    tearDown(() {
      stows.canvasPerfPreset.value = 1;
      DisplayInkFeel.instance.updateRefreshHz(120);
    });

    test('balanced preset keeps historical behavior', () {
      stows.canvasPerfPreset.value = 1;
      final feel = DisplayInkFeel.instance;
      expect(feel.viewportSettleDelay, const Duration(milliseconds: 180));
      expect(feel.vectorLodThreshold, 1.5);
      expect(feel.sparseQualityBoost, 1.18);
      // Zoomed out stays cheap; ~1x stays as before.
      expect(feel.movingBlitFilterQualityForScale(0.5), FilterQuality.low);
      expect(feel.movingBlitFilterQualityForScale(1.0), FilterQuality.low);
    });

    test('performance preset responds faster and sharper', () {
      stows.canvasPerfPreset.value = 0;
      final feel = DisplayInkFeel.instance;
      expect(feel.viewportSettleDelay, const Duration(milliseconds: 120));
      expect(feel.vectorLodThreshold, 1.25);
      expect(feel.sparseQualityBoost, greaterThan(1.18));
      // Zoomed in: sharper moving blits (GPU-side, nearly free).
      expect(feel.movingBlitFilterQualityForScale(1.0), FilterQuality.medium);
      expect(feel.movingBlitFilterQualityForScale(2.5), FilterQuality.high);
      expect(feel.movingBlitFilterQualityForScale(0.5), FilterQuality.low);
    });

    test('battery preset is slower and cheaper', () {
      stows.canvasPerfPreset.value = 2;
      final feel = DisplayInkFeel.instance;
      expect(feel.viewportSettleDelay, const Duration(milliseconds: 320));
      expect(feel.vectorLodThreshold, 2.0);
      expect(feel.sparseQualityBoost, 1.0);
      // Always the cheapest blit, even zoomed in.
      expect(feel.movingBlitFilterQualityForScale(3.0), FilterQuality.none);
      expect(feel.movingBlitFilterQualityForScale(0.5), FilterQuality.none);
    });

    test('PDF policy follows the same preset tiers', () {
      final feel = DisplayInkFeel.instance;
      stows.canvasPerfPreset.value = 1;
      expect(feel.pdfTileMaxEdge, 2048);
      expect(feel.pdfBaseMaxEdge, 2048);
      expect(feel.pdfSettleConfirm, const Duration(milliseconds: 280));
      expect(feel.pdfPreviewWidthPx, 720);
      expect(feel.pdfPreviewJpegQuality, 75);

      stows.canvasPerfPreset.value = 0;
      expect(feel.pdfTileMaxEdge, 3072);
      expect(feel.pdfPreviewWidthPx, 1080);
      expect(feel.pdfSettleConfirm, const Duration(milliseconds: 150));

      stows.canvasPerfPreset.value = 2;
      expect(feel.pdfTileMaxEdge, 1536);
      expect(feel.pdfBaseMaxEdge, 1536);
      expect(feel.pdfPreviewWidthPx, 360);
      expect(feel.pdfSettleConfirm, const Duration(milliseconds: 450));

      // Larger tiles always cost more VRAM: tiers strictly shrink.
      stows.canvasPerfPreset.value = 1;
    });

    test('out-of-range preset falls back to balanced', () {
      stows.canvasPerfPreset.value = 99;
      final feel = DisplayInkFeel.instance;
      expect(feel.canvasPerfPreset, 1);
      expect(feel.viewportSettleDelay, const Duration(milliseconds: 180));
    });
  });
}
