// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' show FilterQuality, FlutterView;

/// Refresh-rate aware knobs for live ink and pan/zoom "feel".
///
/// At 90–120 Hz a short prediction + light stabilization already feels tight.
/// Battery saver often locks the panel at ~60 Hz: each missed vsync is ~16 ms,
/// so the same filters read as rubber-banding / heavy drag. We boost motion
/// prediction, ease stabilization, and bias pan/zoom toward earlier, cheaper
/// frames so the UI stays closer to Samsung Notes–like responsiveness without
/// a native front-buffer path.
class DisplayInkFeel {
  DisplayInkFeel._();

  static final DisplayInkFeel instance = DisplayInkFeel._();

  /// Last observed display refresh rate (Hz). Defaults to 60 until updated.
  double _refreshHz = 60;

  double get refreshHz => _refreshHz;

  /// True when the panel is effectively battery-saver / 60 Hz class.
  bool get isLowRefresh => _refreshHz > 0 && _refreshHz <= 72;

  void updateFromView(FlutterView? view) {
    if (view == null) return;
    final hz = view.display.refreshRate;
    if (hz > 1 && (hz - _refreshHz).abs() > 0.5) {
      _refreshHz = hz;
    } else if (hz > 1 && _refreshHz <= 1) {
      _refreshHz = hz;
    }
  }

  void updateRefreshHz(double hz) {
    if (hz > 1) _refreshHz = hz;
  }

  /// Multiplier on user stabilization amount. Lower = tip tracks stylus closer.
  double get stabilizationScale {
    final hz = _refreshHz;
    if (hz >= 100) return 1.0;
    if (hz >= 80) return 0.85;
    // ~60 Hz battery saver: ease the 1€ filter so tip lag is less visible.
    if (hz <= 72) return 0.32;
    return 0.65;
  }

  /// Extra seconds of motion-prediction lookahead beyond the user amount curve.
  double get predictionLookaheadBoostSec {
    final hz = _refreshHz;
    if (hz >= 100) return 0.0;
    if (hz >= 80) return 0.006;
    // Slightly more than one 60 Hz frame of tip lead.
    if (hz <= 72) return 0.022;
    return 0.010;
  }

  /// Scales max prediction tip distance (page px).
  double get predictionDistanceScale {
    final hz = _refreshHz;
    if (hz >= 100) return 1.0;
    if (hz >= 80) return 1.15;
    if (hz <= 72) return 1.55;
    return 1.3;
  }

  /// How much the live tip origin leans toward the raw (unfiltered) stylus
  /// position. At low Hz this hides stabilization lag at the visible tip.
  double get rawTipBlend {
    final hz = _refreshHz;
    if (hz >= 100) return 0.0;
    if (hz >= 80) return 0.35;
    if (hz <= 72) return 0.86;
    return 0.55;
  }

  /// Gap-fill midpoints. At 60 Hz allow one midpoint (`2` with the existing
  /// `gapFillCount > 1` loop) so sparse samples do not leave a rubbery tip.
  int get maxGapFills {
    if (_refreshHz <= 72) return 2;
    return 3;
  }

  /// Fraction of [kTouchSlop] before pan/zoom wins the arena.
  /// Lower at 60 Hz so the viewport starts moving a frame sooner.
  double get panTouchSlopFactor {
    final hz = _refreshHz;
    if (hz >= 100) return 1.0;
    if (hz >= 80) return 0.75;
    if (hz <= 72) return 0.35;
    return 0.55;
  }

  /// Multiplies scene-space pan deltas. Mild gain only; most of the 60 Hz
  /// snappiness comes from [panVelocityLeadSec] (constant lead, no drift).
  double get panDeltaGain {
    final hz = _refreshHz;
    if (hz >= 100) return 1.0;
    if (hz >= 80) return 1.03;
    if (hz <= 72) return 1.06;
    return 1.04;
  }

  /// Extra scene translation = velocity * this (seconds) while panning.
  double get panVelocityLeadSec {
    final hz = _refreshHz;
    if (hz >= 100) return 0.0;
    if (hz >= 80) return 0.004;
    // ~¾ of a 60 Hz frame of lead from measured pan velocity.
    if (hz <= 72) return 0.012;
    return 0.007;
  }

  /// Multiplies pinch scale-change toward the finger (1 = exact).
  double get zoomDeltaGain {
    final hz = _refreshHz;
    if (hz >= 100) return 1.0;
    if (hz >= 80) return 1.04;
    if (hz <= 72) return 1.1;
    return 1.06;
  }

  /// Tile blit filter while the viewport is moving. Nearest is much cheaper
  /// at 60 Hz and reads as snappier than bilinear on large stroke rasters.
  FilterQuality get movingBlitFilterQuality {
    if (isLowRefresh) return FilterQuality.none;
    return FilterQuality.low;
  }

  /// Delay after pan/zoom stops before rebaking raster LOD / mesh upgrades.
  /// Slightly longer at 60 Hz so settle work does not thrash mid-fling.
  Duration get viewportSettleDelay {
    if (isLowRefresh) return const Duration(milliseconds: 250);
    if (_refreshHz < 100) return const Duration(milliseconds: 250);
    return const Duration(milliseconds: 180);
  }

  /// Min interval between transform-driven chrome rebuilds (HUD / scrollbars /
  /// page index) while the viewport is moving at low refresh.
  Duration get chromeThrottleInterval {
    if (isLowRefresh) return const Duration(milliseconds: 60);
    return const Duration(milliseconds: 16);
  }
}
