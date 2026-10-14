// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' show FilterQuality, FlutterView;

import 'package:saber/data/prefs.dart';

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

  // ---------------------------------------------------------------------------
  // Canvas raster-LOD performance preset (Settings → Performance → Canvas).
  // 0 = Performance, 1 = Balanced (= previous behavior, the default),
  // 2 = Battery saver. Read live from prefs, so switching applies instantly.
  // ---------------------------------------------------------------------------

  /// Raw preset index; out-of-range values fall back to Balanced.
  int get canvasPerfPreset {
    final v = stows.canvasPerfPreset.value;
    if (v < 0 || v > 2) return 1;
    return v;
  }

  /// Delay after pan/zoom stops before rebaking raster LOD / mesh upgrades.
  /// Slightly longer at 60 Hz so settle work does not thrash mid-fling.
  /// Performance settles fast (snappier sharpness); Battery waits longer
  /// (fewer rebakes, less heat).
  Duration get viewportSettleDelay {
    switch (canvasPerfPreset) {
      case 0:
        return const Duration(milliseconds: 120);
      case 2:
        return const Duration(milliseconds: 320);
      default:
        if (isLowRefresh) return const Duration(milliseconds: 250);
        if (_refreshHz < 100) return const Duration(milliseconds: 250);
        return const Duration(milliseconds: 180);
    }
  }

  /// Tile blit filter while moving, sharpened by zoom level: zoomed in, few
  /// tiles cover the screen, so a sharper (GPU-side, nearly free) blit reads
  /// much better; zoomed out, cheap blits win. Battery saver always takes
  /// the cheapest path.
  FilterQuality movingBlitFilterQualityForScale(double scale) {
    switch (canvasPerfPreset) {
      case 0:
        if (scale >= 2.0) return FilterQuality.high;
        if (scale >= 1.0) return FilterQuality.medium;
        return isLowRefresh ? FilterQuality.none : FilterQuality.low;
      case 2:
        return FilterQuality.none;
      default:
        if (scale >= 1.5) return FilterQuality.medium;
        if (scale >= 1.0) return FilterQuality.low;
        return movingBlitFilterQuality;
    }
  }

  /// Canvas scale at/above which tiles stay as vectors (no bitmap LOD).
  /// Performance drops it (crisper sooner, more vector frames); Battery
  /// raises it (more bitmap blits, fewer expensive vector frames).
  /// Balanced keeps the historical 1.5 (see RasterLodTuning).
  double get vectorLodThreshold {
    switch (canvasPerfPreset) {
      case 0:
        return 1.25;
      case 2:
        return 2.0;
      default:
        return 1.5;
    }
  }

  /// Sparse-page raster sharpness boost (few strokes = cheap to bake sharp).
  /// Battery skips the boost to keep bakes cheap.
  double get sparseQualityBoost {
    switch (canvasPerfPreset) {
      case 0:
        return 1.3;
      case 2:
        return 1.0;
      default:
        // Matches RasterLodTuning.sparseQualityMul.
        return 1.18;
    }
  }

  /// Min interval between transform-driven chrome rebuilds (HUD / scrollbars /
  /// page index) while the viewport is moving at low refresh.
  Duration get chromeThrottleInterval {
    if (isLowRefresh) return const Duration(milliseconds: 60);
    return const Duration(milliseconds: 16);
  }

  // ---------------------------------------------------------------------------
  // PDF page rendering policy (same Settings → Performance → Canvas preset).
  // Read live, so switching profiles applies to the next tile instantly
  // (keys embed the width, so a profile switch just cold-misses once).
  // 0 = Performance (biggest tiles, fastest settle, sharpest previews),
  // 1 = Balanced, 2 = Battery saver (small tiles, lazy settle, tiny tiles).
  // ---------------------------------------------------------------------------

  /// Longest edge (px) of a deep-zoom tile bitmap. Bounds per-tile VRAM
  /// (~4 bytes/px BGRA) and the UI-thread decode of each settled tile.
  int get pdfTileMaxEdge {
    switch (canvasPerfPreset) {
      case 0:
        return 3072;
      case 2:
        return 1536;
      default:
        return 2048;
    }
  }

  /// Longest edge (px) of the full-page base texture. The base is always
  /// mounted (pans glide over it), so even Battery keeps it usable.
  int get pdfBaseMaxEdge {
    switch (canvasPerfPreset) {
      case 0:
        return 2048;
      case 2:
        return 1536;
      default:
        return 2048;
    }
  }

  /// Settle-confirm delay before a requested tile commits to a render.
  /// Performance sharpens fast; Battery waits out micro-settles (fewer
  /// renders, less heat).
  Duration get pdfSettleConfirm {
    switch (canvasPerfPreset) {
      case 0:
        return const Duration(milliseconds: 150);
      case 2:
        return const Duration(milliseconds: 450);
      default:
        return const Duration(milliseconds: 280);
    }
  }

  /// Width (px) of the low-res placeholder tile painted under/instead of
  /// the full raster. Battery keeps the legacy 360px tile; Balanced steps
  /// up to a much sharper default; Performance renders higher still.
  int get pdfPreviewWidthPx {
    switch (canvasPerfPreset) {
      case 0:
        return 1080;
      case 2:
        return 360;
      default:
        return 720;
    }
  }

  /// JPEG quality of the placeholder tile.
  int get pdfPreviewJpegQuality {
    switch (canvasPerfPreset) {
      case 0:
        return 80;
      case 2:
        return 68;
      default:
        return 75;
    }
  }
}
