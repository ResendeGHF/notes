// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// Global viewport-motion bus for PDF tiling.
///
/// The editor's `TransformationController` notifies on every pan/zoom tick.
/// Plumbing it through five widget layers is brittle; instead the editor
/// ticks this bus and PDF renderers debounce their own retiling off it.
/// Gesture end flushes immediately via [settle] (no perceptual debounce
/// lag after finger lift). App-lifetime singleton: never disposed.
abstract final class PdfViewportBus {
  static final ValueNotifier<int> epoch = ValueNotifier<int>(0);
  static final ValueNotifier<int> settleEpoch = ValueNotifier<int>(0);

  static void tick() {
    epoch.value++;
  }

  static void settle() {
    settleEpoch.value++;
  }
}

/// Visible region of one PDF page widget, in displayed-page points.
class PdfVisibleRegion {
  const PdfVisibleRegion({
    required this.clip,
    required this.fraction,
    required this.fullyOffscreen,
  });

  /// Visible sub-rect in displayed page points (empty when offscreen).
  final Rect clip;

  /// 0..1 fraction of the widget area currently on screen.
  final double fraction;
  final bool fullyOffscreen;
}

/// Pure math for viewport-tiled PDF renders (unit-tested; no widgets).
abstract final class PdfTileMath {
  /// Base-layer bitmap for a page box: layout x devicePixelRatio fitted
  /// into [edgeCap], preserving aspect. Deterministic and shared: the base
  /// surface (both backends) AND [tilePlan] derive from it, so tiles refine
  /// (never drift from) the base sampling grid. Tile density is always an
  /// integer multiple of `bitmap.width / pageSize.width`.
  static Size baseBitmap({
    required Size boxSize,
    required double devicePixelRatio,
    int edgeCap = 2048,
  }) {
    if (boxSize.isEmpty) return const Size(1, 1);
    final dpr = devicePixelRatio.clamp(1.0, 4.0);
    var w = boxSize.width * dpr;
    var h = boxSize.height * dpr;
    if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0) {
      return const Size(1, 1);
    }
    final longest = w > h ? w : h;
    if (longest > edgeCap) {
      final s = edgeCap / longest;
      w *= s;
      h *= s;
    }
    return Size(w.round().clamp(1, edgeCap).toDouble(), h.round().clamp(1, edgeCap).toDouble());
  }

  /// Deep-zoom threshold: above this canvas scale a clipped tile replaces
  /// the full-page raster. Hysteresis band ([tiledZoomExit]) prevents mode
  /// flapping (and base re-renders) when hovering the threshold.
  ///
  /// Full-page surfaces render at layout x devicePixelRatio, which stays
  /// sharp to ~1.2x; tiling takes over above 1.5x so mid-zoom text sharpens
  /// instead of GPU-stretching.
  static const double tiledZoomThreshold = 1.5;
  static const double tiledZoomExit = 1.3;

  /// At/above this visible fraction a full-page raster is cheaper than a
  /// tile (no point clipping 95% of a page).
  static const double fullPageFractionThreshold = 0.8;

  /// Tiling is exact only for unrotated pages. Rotated pages fall back to
  /// full-page renders (correct, just softer at extreme zoom).
  static bool supportsTiling(int rotationIndex) => rotationIndex == 0;

  /// Displayed page size given the stored (unrotated) natural size and the
  /// pdfrx rotation quarter-turn index.
  static Size displaySize(Size naturalSize, int rotationIndex) {
    if (rotationIndex & 1 == 1) {
      return Size(naturalSize.height, naturalSize.width);
    }
    return naturalSize;
  }

  /// Computes the on-screen region of a page widget.
  ///
  /// - [box]: the page widget's [RenderBox] (local space == layout units).
  /// - [screenSize]: screen size in the same CSS px as global coordinates.
  /// - [pageSizePt]: displayed page size in points; the widget is assumed to
  ///   fill its box with the page ([BoxFit.fill] mapping).
  ///
  /// The global rect MUST come from the full transform
  /// (`getTransformTo(null)`): `localToGlobal(origin) & box.size` attaches
  /// the *unscaled* local size and silently drops canvas zoom (scale reads
  /// 1.0, centered pans report offscreen, clips map to wrong coordinates).
  static PdfVisibleRegion computeVisible({
    required RenderBox box,
    required Size screenSize,
    required Size pageSizePt,
  }) {
    if (!box.hasSize || box.size.isEmpty || pageSizePt.isEmpty) {
      return const PdfVisibleRegion(
        clip: Rect.zero,
        fraction: 0,
        fullyOffscreen: true,
      );
    }
    late Rect global;
    try {
      global = MatrixUtils.transformRect(
        box.getTransformTo(null),
        Offset.zero & box.size,
      );
    } catch (_) {
      return const PdfVisibleRegion(
        clip: Rect.zero,
        fraction: 0,
        fullyOffscreen: true,
      );
    }
    if (!global.isFinite || global.isEmpty) {
      return const PdfVisibleRegion(
        clip: Rect.zero,
        fraction: 0,
        fullyOffscreen: true,
      );
    }
    final screen = Offset.zero & screenSize;
    final vis = global.intersect(screen);
    final area = global.width * global.height;
    if (vis.isEmpty || area <= 0) {
      return const PdfVisibleRegion(
        clip: Rect.zero,
        fraction: 0,
        fullyOffscreen: true,
      );
    }
    final fraction = (vis.width * vis.height / area).clamp(0.0, 1.0);
    // Per-axis global→local scale (uniform in practice; kept separate to
    // survive odd transforms without skewing the clip).
    final kx = global.width / box.size.width;
    final ky = global.height / box.size.height;
    if (!kx.isFinite || !ky.isFinite || kx <= 0 || ky <= 0) {
      return PdfVisibleRegion(
        clip: Offset.zero & pageSizePt,
        fraction: fraction,
        fullyOffscreen: false,
      );
    }
    final local = Rect.fromLTWH(
      (vis.left - global.left) / kx,
      (vis.top - global.top) / ky,
      vis.width / kx,
      vis.height / ky,
    );
    final sx = pageSizePt.width / box.size.width;
    final sy = pageSizePt.height / box.size.height;
    final clip = Rect.fromLTWH(
      local.left * sx,
      local.top * sy,
      local.width * sx,
      local.height * sy,
    ).intersect(Offset.zero & pageSizePt);
    if (clip.isEmpty) {
      return const PdfVisibleRegion(
        clip: Rect.zero,
        fraction: 0,
        fullyOffscreen: true,
      );
    }
    return PdfVisibleRegion(
      clip: clip,
      fraction: fraction,
      fullyOffscreen: false,
    );
  }

  /// Live canvas scale from the box's full transform. Immune to the
  /// debounced `renderScale` prop (which still holds the pre-zoom value when
  /// a settle flush fires): callers take `max(prop, live)` for decisions.
  static double liveScaleOf(RenderBox box, double fallback) {
    try {
      if (!box.hasSize || box.size.width <= 0) return fallback;
      final global = MatrixUtils.transformRect(
        box.getTransformTo(null),
        Offset.zero & box.size,
      );
      if (global.width <= 0 || !global.width.isFinite) return fallback;
      final s = global.width / box.size.width;
      if (!s.isFinite || s <= 0) return fallback;
      return s;
    } catch (_) {
      return fallback;
    }
  }

  /// Bitmap size for a tile: exactly the physical pixels the visible rect
  /// occupies on screen ([visibleGlobalSize] x [devicePixelRatio]), fitted
  /// into [cap] preserving the clip aspect. Rendering at physical need =
  /// razor sharp at any zoom; the cap bounds VRAM.
  ///
  /// DPR note: [visibleGlobalSize] MUST already be physical pixels
  /// (`globalRect.size * MediaQuery.devicePixelRatioOf`), because
  /// Flutter's transform/viewport math runs in logical points while phone
  /// panels run at 2.625x-3x. Rendering at logical size looks fuzzy on OLED.
  /// Callers therefore pass `devicePixelRatio: 1.0` when [visibleGlobalSize]
  /// is pre-multiplied (kept as a parameter so the contract is explicit).
  static ({int width, int height}) bitmapSizeFor({
    required Rect clipPt,
    required Size visibleGlobalSize,
    required double devicePixelRatio,
    int cap = 3072,
  }) {
    if (clipPt.isEmpty || visibleGlobalSize.isEmpty) {
      return (width: 1, height: 1);
    }
    var w = (visibleGlobalSize.width * devicePixelRatio).round();
    var h = (visibleGlobalSize.height * devicePixelRatio).round();
    // Guard degenerate transforms (page scaled to sub-pixel on screen).
    w = w.clamp(1, cap * 2);
    h = h.clamp(1, cap * 2);
    // Preserve clip aspect against rounding in the global rect.
    final clipAspect = clipPt.width / clipPt.height;
    final bitAspect = w / h;
    if ((clipAspect - bitAspect).abs() > 0.02) {
      if (clipAspect > bitAspect) {
        h = (w / clipAspect).round().clamp(1, cap * 2);
      } else {
        w = (h * clipAspect).round().clamp(1, cap * 2);
      }
    }
    final longest = w > h ? w : h;
    if (longest > cap) {
      final s = cap / longest;
      w = (w * s).round().clamp(1, cap);
      h = (h * s).round().clamp(1, cap);
    }
    // Exact aspect lock: the tile box is laid out from the clip aspect, so
    // the bitmap MUST match it to the pixel — even a ~2% rounding skew
    // visibly stretches/shifts text against the base layer and ink, growing
    // with zoom. Snap h to w (uniform resample is invisible; skew is not).
    h = (w / clipAspect).round().clamp(1, cap);
    return (width: w, height: h);
  }

  /// Snaps a tile box to physical device pixels. A fractional logical
  /// origin (e.g. left=412.37) bilinear-resamples text with a phase offset
  /// that reads as a vertical shift — multiplied by zoom into several
  /// physical pixels. Snapping keeps at most half a physical pixel of error
  /// (invisible) instead. Idempotent: snapping twice changes nothing.
  static Rect snapRectToDevicePixels(Rect r, double dpr) {
    if (r.isEmpty || dpr <= 0 || !dpr.isFinite) return r;
    final l = (r.left * dpr).floor() / dpr;
    final t = (r.top * dpr).floor() / dpr;
    final rr = (r.right * dpr).ceil() / dpr;
    final bb = (r.bottom * dpr).ceil() / dpr;
    final out = Rect.fromLTRB(l, t, rr, bb);
    if (!out.isFinite || out.isEmpty) return r;
    return out;
  }

  /// Tile render plan on a shared sampling grid (map-tile discipline).
  ///
  /// The base layer samples the page at [baseDensity] px/pt. Rendering a
  /// tile at an unrelated density samples the same glyphs with a different
  /// sub-pixel phase — at high zoom that half-pixel offset becomes several
  /// physical pixels and reads as text shifting between base and tile.
  /// Instead the tile density is an INTEGER multiple of the base density and
  /// the clip origin/size snap to the base grid, so tile samples are a
  /// strict refinement: zero phase drift, ever. [needPhysical] is the
  /// visible region in physical pixels (optimal sharpness target).
  static ({Rect clip, int width, int height, double density}) tilePlan({
    required Rect want,
    required Size pageSize,
    required Size needPhysical,
    required double baseDensity,
    int cap = 3072,
  }) {
    if (want.isEmpty ||
        pageSize.isEmpty ||
        !baseDensity.isFinite ||
        baseDensity <= 0) {
      return (clip: Rect.zero, width: 1, height: 1, density: baseDensity);
    }
    final clip = want.intersect(Offset.zero & pageSize);
    if (clip.isEmpty) {
      return (clip: Rect.zero, width: 1, height: 1, density: baseDensity);
    }
    // Snap origin down / far edge up to base-grid multiples: coverage never
    // shrinks, and every edge lands exactly on a base sample.
    final gx = 1.0 / baseDensity;
    final l = (clip.left / gx).floor() * gx;
    final t = (clip.top / gx).floor() * gx;
    final r = (clip.right / gx).ceil() * gx;
    final b = (clip.bottom / gx).ceil() * gx;
    final snapped = Rect.fromLTRB(
      l.clamp(0.0, pageSize.width),
      t.clamp(0.0, pageSize.height),
      r.clamp(0.0, pageSize.width),
      b.clamp(0.0, pageSize.height),
    );
    if (snapped.isEmpty) {
      return (clip: Rect.zero, width: 1, height: 1, density: baseDensity);
    }
    // Integer density multiple covering the physical need, within the cap.
    final needDensity = needPhysical.width > 0 && snapped.width > 0
        ? needPhysical.width / snapped.width
        : baseDensity;
    var k = (needDensity / baseDensity).round().clamp(1, 1 << 20);
    final atK1W = snapped.width * baseDensity;
    final atK1H = snapped.height * baseDensity;
    final longest1 = atK1W > atK1H ? atK1W : atK1H;
    if (longest1 > 0) {
      final kMax = (cap / longest1).floor().clamp(1, 1 << 20);
      if (k > kMax) k = kMax.clamp(1, 1 << 20);
    }
    final density = baseDensity * k;
    // Exact integers: snapped edges are grid multiples and density is k×.
    final w = ((snapped.right - snapped.left) * density).round().clamp(
      1,
      cap,
    );
    final h = ((snapped.bottom - snapped.top) * density).round().clamp(
      1,
      cap,
    );
    return (clip: snapped, width: w, height: h, density: density);
  }

  /// Document-space box for painting a tile: maps [clipPt] (displayed page
  /// points) into widget-local units for a [Positioned] overlay.
  ///
  /// Tiles are positioned elements in DOCUMENT space, never screen space:
  /// the overlay sits at its render-time sourceRect inside the transformed
  /// page subtree, so pans glide it along with the ink instead of snapping
  /// it to the live viewport (no drift/jitter between render and paint).
  static Rect tileBox({
    required Rect clipPt,
    required Size boxSize,
    required Size pageSizePt,
  }) {
    if (clipPt.isEmpty || boxSize.isEmpty || pageSizePt.isEmpty) {
      return Rect.zero;
    }
    final sx = boxSize.width / pageSizePt.width;
    final sy = boxSize.height / pageSizePt.height;
    if (!sx.isFinite || !sy.isFinite || sx <= 0 || sy <= 0) {
      return Rect.zero;
    }
    return Rect.fromLTWH(
      clipPt.left * sx,
      clipPt.top * sy,
      clipPt.width * sx,
      clipPt.height * sy,
    );
  }
}
