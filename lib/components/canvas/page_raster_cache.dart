// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:saber/components/canvas/_canvas_background_painter.dart';
import 'package:saber/components/canvas/_canvas_painter.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/canvas_background_pattern.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/services/display_ink_feel.dart';

/// One baked bitmap layer for a page (ink or background).
final class PageCacheEntry {
  const PageCacheEntry({
    required this.image,
    required this.res,
    required this.generation,
    this.strokeCount = 0,
  });

  final ui.Image image;
  final double res;
  final int generation;

  /// Number of ink strokes rasterized into [image] (for cheap suffix overlays).
  final int strokeCount;
}

/// Parameters for rasterizing page background (pattern/grid only).
final class PageRasterBgParams {
  const PageRasterBgParams({
    required this.invert,
    required this.backgroundColor,
    required this.backgroundPattern,
    required this.lineHeight,
    required this.lineThickness,
    required this.primaryColor,
    required this.secondaryColor,
    this.marginLeft = 0,
    this.marginRight = 0,
    this.marginTop = 0,
    this.marginBottom = 0,
    this.borderColor,
  });

  final bool invert;
  final Color backgroundColor;
  final CanvasBackgroundPattern backgroundPattern;
  final int lineHeight;
  final int lineThickness;
  final Color primaryColor;
  final Color secondaryColor;
  final double marginLeft;
  final double marginRight;
  final double marginTop;
  final double marginBottom;
  final Color? borderColor;
}

/// Parameters for rasterizing committed ink (no highlighter).
final class PageRasterInkParams {
  const PageRasterInkParams({
    required this.invert,
    required this.strokes,
    required this.page,
    required this.primaryColor,
    required this.pageIndex,
    required this.totalPages,
    required this.currentScale,
    required this.defaultTextStyle,
    this.lineHeight,
    this.lineThickness,
    this.lineColor,
  });

  final bool invert;
  final List<Stroke> strokes;
  final EditorPage page;
  final Color primaryColor;
  final int pageIndex;
  final int totalPages;
  final double currentScale;
  final TextStyle defaultTextStyle;
  final int? lineHeight;
  final double? lineThickness;
  final Color? lineColor;
}

/// xnotes-style per-page ink + background raster caches built off the UI
/// critical path and blitted during scroll.
final class PageRasterCacheManager {
  PageRasterCacheManager({this.onRepaintRequested});

  static const double maxCachePx = 4096.0;

  final VoidCallback? onRepaintRequested;

  /// Bumped when motion starts and when zoom has been still long enough to
  /// bake at the rest scale.
  static final ValueNotifier<int> lodEpoch = ValueNotifier(0);

  /// Bumped when a cache entry lands or is invalidated.
  final ValueNotifier<int> repaintEpoch = ValueNotifier(0);

  int _cacheGen = 0;
  final Map<int, PageCacheEntry> _inkCaches = {};
  final Map<int, PageCacheEntry> _bgCaches = {};
  final Map<int, int> _pageInkGeneration = {};
  final Map<int, int> _pageBgGeneration = {};
  final Map<int, Size> _pageSizes = {};
  final Set<int> _pendingInk = {};
  final Set<int> _pendingBg = {};
  bool _disposed = false;
  bool _jobRunning = false;
  final Queue<_RasterJob> _jobQueue = Queue();

  // --- Viewport / zoom LOD (shared with gesture detector) ---

  static bool viewportMoving = false;
  static bool layoutResizeSession = false;
  static int _layoutOcclusionDepth = 0;

  static bool get layoutOccluded =>
      layoutResizeSession || _layoutOcclusionDepth > 0;

  static void pushLayoutOcclusion() {
    _layoutOcclusionDepth++;
    updateViewportMoving(true);
  }

  static void popLayoutOcclusion() {
    if (_layoutOcclusionDepth <= 0) return;
    _layoutOcclusionDepth--;
    if (_layoutOcclusionDepth == 0 && !layoutResizeSession) {
      updateViewportMoving(false);
    }
  }

  static bool viewportSettled = true;
  static Duration get viewportSettleDelay =>
      DisplayInkFeel.instance.viewportSettleDelay;
  static bool zoomLodSettled = true;

  static double? get liveViewportScale => _liveViewportScale;

  static Timer? _settleTimer;
  static Timer? _zoomSettleTimer;
  static double _zoomLod = 0;
  static double? _liveViewportScale;

  @visibleForTesting
  static bool debugForceSyncRaster = false;

  static void updateViewportMoving(bool moving) {
    if (layoutOccluded && !moving) return;
    if (moving) {
      _settleTimer?.cancel();
      _settleTimer = null;
      final started = !viewportMoving;
      viewportMoving = true;
      viewportSettled = false;
      if (started) lodEpoch.value++;
      return;
    }
    viewportMoving = false;
    if (viewportSettled || _settleTimer != null) return;
    _settleTimer = Timer(viewportSettleDelay, () {
      _settleTimer = null;
      viewportSettled = true;
      lodEpoch.value++;
      _notifyLodSettled();
      SchedulerBinding.instance.ensureVisualUpdate();
    });
  }

  static void endProgrammaticViewportJump() {
    _settleTimer?.cancel();
    _settleTimer = null;
    if (viewportMoving) {
      viewportMoving = false;
      lodEpoch.value++;
    }
    viewportSettled = true;
  }

  static void beginLayoutResizeSession() {
    layoutResizeSession = true;
    updateViewportMoving(true);
  }

  static void endLayoutResizeSession() {
    if (!layoutResizeSession) return;
    layoutResizeSession = false;
    updateViewportMoving(false);
  }

  static void setViewportScale(double scale) {
    _liveViewportScale = scale;
    _observeZoomScale(scale);
  }

  static double effectiveScale(double fallback) =>
      liveViewportScale ?? fallback;

  static void _observeZoomScale(double scale) {
    final lod = rasterLodScale(scale);
    if (_zoomLod <= 0) {
      _zoomLod = lod;
      zoomLodSettled = true;
      return;
    }
    // Debounce on every scale update so page rasters rebuild after zoom stops,
    // not only when the quantized LOD bucket changes.
    _zoomLod = lod;
    zoomLodSettled = false;
    _zoomSettleTimer?.cancel();
    _zoomSettleTimer = Timer(viewportSettleDelay, () {
      _zoomSettleTimer = null;
      zoomLodSettled = true;
      lodEpoch.value++;
      _notifyLodSettled();
      SchedulerBinding.instance.ensureVisualUpdate();
    });
  }

  static final List<VoidCallback> _lodSettledListeners = [];

  static void addLodSettledListener(VoidCallback listener) {
    if (!_lodSettledListeners.contains(listener)) {
      _lodSettledListeners.add(listener);
    }
  }

  static void removeLodSettledListener(VoidCallback listener) {
    _lodSettledListeners.remove(listener);
  }

  static void _notifyLodSettled() {
    for (final listener in List<VoidCallback>.from(_lodSettledListeners)) {
      listener();
    }
  }

  static double rasterLodScale(double scale) {
    final s = scale.clamp(0.25, 8.0);
    return (s * 4).round() / 4;
  }

  @visibleForTesting
  static void debugResetViewportLod() {
    _settleTimer?.cancel();
    _settleTimer = null;
    _zoomSettleTimer?.cancel();
    _zoomSettleTimer = null;
    viewportMoving = false;
    viewportSettled = true;
    zoomLodSettled = true;
    layoutResizeSession = false;
    _layoutOcclusionDepth = 0;
    _zoomLod = 0;
    _liveViewportScale = null;
    debugForceSyncRaster = false;
  }

  // --- Resolution ---

  static double _devicePixelRatio() {
    final views = ui.PlatformDispatcher.instance.views;
    if (views.isEmpty) return 1.0;
    return views.first.devicePixelRatio.clamp(1.0, 4.0);
  }

  /// Pixels-per-logical-pixel for page bitmaps (zoom × DPR), capped at
  /// [maxCachePx] on the page long edge.
  static double clampedRes(
    double scale,
    Size pageSize, {
    double? devicePixelRatio,
  }) {
    final dpr = devicePixelRatio ?? _devicePixelRatio();
    final zoom = effectiveScale(scale);
    final longEdge = math.max(pageSize.width, pageSize.height);
    if (longEdge <= 0) return (zoom * dpr).clamp(0.25, 12.0);
    final desiredPx = zoom * dpr * longEdge;
    if (desiredPx <= maxCachePx) return zoom * dpr;
    return maxCachePx / longEdge;
  }

  static bool _resSufficient(double cachedRes, double targetRes) =>
      cachedRes >= targetRes * 0.98;

  // --- Cache access ---

  int _inkGen(int pageIndex) => _pageInkGeneration[pageIndex] ?? 0;
  int _bgGen(int pageIndex) => _pageBgGeneration[pageIndex] ?? 0;

  /// True while stylus/finger ink or eraser must own the UI isolate.
  static bool get inkInputBusy =>
      Pen.currentStroke != null || Eraser.isDragging;

  PageCacheEntry? inkForOrSchedule({
    required int pageIndex,
    required Size pageSize,
    required double scale,
    required PageRasterInkParams params,
    double? devicePixelRatio,
    bool forceSchedule = false,
  }) {
    if (_disposed) return null;
    final dpr = devicePixelRatio ?? _devicePixelRatio();
    _pageSizes[pageIndex] = pageSize;
    final res = clampedRes(scale, pageSize, devicePixelRatio: dpr);
    final existing = _inkCaches[pageIndex];
    final gen = _inkGen(pageIndex);
    if (existing != null &&
        existing.generation == gen &&
        _resSufficient(existing.res, res)) {
      return existing;
    }
    _scheduleInkJob(
      pageIndex: pageIndex,
      pageSize: pageSize,
      res: res,
      generation: gen,
      devicePixelRatio: dpr,
      viewportScale: scale,
      inkParams: params,
      forceSchedule: forceSchedule,
    );

    // Prefer any retained bitmap over a null miss. A miss forces the painter
    // into a full vector paint of every committed stroke, which starves
    // stylus sampling and produces "square-ish" interrupted ink.
    return existing;
  }

  PageCacheEntry? backgroundForOrSchedule({
    required int pageIndex,
    required Size pageSize,
    required double scale,
    required PageRasterBgParams params,
    required bool hasFullBleedBackground,
    double? devicePixelRatio,
    bool forceSchedule = false,
  }) {
    if (_disposed || hasFullBleedBackground) return null;
    final dpr = devicePixelRatio ?? _devicePixelRatio();
    _pageSizes[pageIndex] = pageSize;
    final res = clampedRes(scale, pageSize, devicePixelRatio: dpr);
    final existing = _bgCaches[pageIndex];
    final gen = _bgGen(pageIndex);
    if (existing != null &&
        existing.generation == gen &&
        _resSufficient(existing.res, res)) {
      return existing;
    }
    _scheduleBgJob(
      pageIndex: pageIndex,
      pageSize: pageSize,
      res: res,
      generation: gen,
      devicePixelRatio: dpr,
      viewportScale: scale,
      bgParams: params,
      forceSchedule: forceSchedule,
    );
    

    if (existing != null && existing.generation == gen) {
      return existing;
    }
    return null;
  }

  void _scheduleInkJob({
    required int pageIndex,
    required Size pageSize,
    required double res,
    required int generation,
    required double devicePixelRatio,
    required double viewportScale,
    required PageRasterInkParams inkParams,
    bool forceSchedule = false,
  }) {
    if ((viewportMoving || inkInputBusy) && !forceSchedule) return;
    _dropInferiorQueuedJobs(pageIndex: pageIndex, isInk: true, minRes: res);
    final hasQueued = _jobQueue.any(
      (j) => j.isInk && j.pageIndex == pageIndex && j.generation == generation && _resSufficient(j.res, res),
    );
    if (hasQueued) {
      _pendingInk.add(pageIndex);
      return;
    }
    _pendingInk.add(pageIndex);
    _enqueue(
      _RasterJob.ink(
        pageIndex: pageIndex,
        pageSize: pageSize,
        res: res,
        generation: generation,
        cacheGen: _cacheGen,
        devicePixelRatio: devicePixelRatio,
        viewportScale: viewportScale,
        inkParams: inkParams,
      ),
    );
  }

  void _scheduleBgJob({
    required int pageIndex,
    required Size pageSize,
    required double res,
    required int generation,
    required double devicePixelRatio,
    required double viewportScale,
    required PageRasterBgParams bgParams,
    bool forceSchedule = false,
  }) {
    if (viewportMoving && !forceSchedule) return;
    _dropInferiorQueuedJobs(pageIndex: pageIndex, isInk: false, minRes: res);
    final hasQueued = _jobQueue.any(
      (j) => !j.isInk && j.pageIndex == pageIndex && j.generation == generation && _resSufficient(j.res, res),
    );
    if (hasQueued) {
      _pendingBg.add(pageIndex);
      return;
    }
    _pendingBg.add(pageIndex);
    _enqueue(
      _RasterJob.bg(
        pageIndex: pageIndex,
        pageSize: pageSize,
        res: res,
        generation: generation,
        cacheGen: _cacheGen,
        devicePixelRatio: devicePixelRatio,
        viewportScale: viewportScale,
        bgParams: bgParams,
      ),
    );
  }

  void _dropInferiorQueuedJobs({
    required int pageIndex,
    required bool isInk,
    required double minRes,
  }) {
    _jobQueue.removeWhere(
      (j) =>
          j.isInk == isInk &&
          j.pageIndex == pageIndex &&
          j.res + 1e-6 < minRes,
    );
  }

  /// After pan/zoom settles, drop stale jobs and force-schedule HQ rebuilds at
  /// the current zoom × DPR (even if [viewportMoving] is still latched).
  void prepareForSettledScale({
    required double scale,
    double? devicePixelRatio,
  }) {
    if (_disposed) return;
    final dpr = devicePixelRatio ?? _devicePixelRatio();
    final liveScale = effectiveScale(scale);
    for (final pageIndex in {..._inkCaches.keys, ..._pendingInk, ..._pageSizes.keys}) {
      final pageSize = _pageSizes[pageIndex];
      if (pageSize == null) continue;
      final target = clampedRes(liveScale, pageSize, devicePixelRatio: dpr);
      final existing = _inkCaches[pageIndex];
      if (existing != null && _resSufficient(existing.res, target)) continue;
      _dropInferiorQueuedJobs(pageIndex: pageIndex, isInk: true, minRes: target);
      _pendingInk.remove(pageIndex);
    }
    for (final pageIndex in {..._bgCaches.keys, ..._pendingBg, ..._pageSizes.keys}) {
      final pageSize = _pageSizes[pageIndex];
      if (pageSize == null) continue;
      final target = clampedRes(liveScale, pageSize, devicePixelRatio: dpr);
      final existing = _bgCaches[pageIndex];
      if (existing != null && _resSufficient(existing.res, target)) continue;
      _dropInferiorQueuedJobs(pageIndex: pageIndex, isInk: false, minRes: target);
      _pendingBg.remove(pageIndex);
    }
    if (!_jobRunning && _jobQueue.isNotEmpty) {
      unawaited(_processQueue());
    }
    _bumpRepaint();
  }

  /// Marks ink stale and schedules a rebake.
  ///
  /// By default the previous bitmap is kept so the painter can blit it (plus a
  /// cheap suffix overlay for newly added strokes) instead of synchronously
  /// vector-painting the whole page — that path caused stylus lag / square ink.
  /// Pass [discardStale] when content was removed (eraser/undo) so ghosts do not
  /// linger.
  void invalidateInk(int pageIndex, {bool discardStale = false}) {
    _pageInkGeneration[pageIndex] = _inkGen(pageIndex) + 1;
    _cacheGen++;
    if (discardStale) {
      _inkCaches.remove(pageIndex)?.image.dispose();
    }
    _pendingInk.remove(pageIndex);
    _bumpRepaint();
  }

  void invalidateBg(int pageIndex) {
    _pageBgGeneration[pageIndex] = _bgGen(pageIndex) + 1;
    _cacheGen++;
    final old = _bgCaches.remove(pageIndex);
    old?.image.dispose();
    _pendingBg.remove(pageIndex);
    _bumpRepaint();
  }

  void invalidatePage(int pageIndex, {bool ink = true, bool bg = true}) {
    if (ink) invalidateInk(pageIndex);
    if (bg) invalidateBg(pageIndex);
  }

  void invalidateForZoom() {
    _cacheGen++;
    for (final entry in _inkCaches.values) {
      entry.image.dispose();
    }
    for (final entry in _bgCaches.values) {
      entry.image.dispose();
    }
    _inkCaches.clear();
    _bgCaches.clear();
    _pendingInk.clear();
    _pendingBg.clear();
    _bumpRepaint();
  }

  void dropExcept(Set<int> keep) {
    for (final key in _inkCaches.keys.toList()) {
      if (keep.contains(key)) continue;
      _inkCaches.remove(key)?.image.dispose();
    }
    for (final key in _bgCaches.keys.toList()) {
      if (keep.contains(key)) continue;
      _bgCaches.remove(key)?.image.dispose();
    }
  }

  void releaseOffBandGeometry(EditorCoreInfo coreInfo, Set<int> keep) {
    for (var i = 0; i < coreInfo.pages.length; i++) {
      if (keep.contains(i)) continue;
      final page = coreInfo.pages[i];
      for (final stroke in page.allStrokesInDrawOrder) {
        if (stroke.hasCachedHighQualityPolygon) {
          stroke.markPolygonNeedsUpdating();
        }
      }
    }
  }

  /// Prefetch ink/bg for the visible band ± [radius] neighbors.
  void prefetchBand({
    required EditorCoreInfo coreInfo,
    required int bandStart,
    required int bandEnd,
    required double scale,
    required bool invert,
    required Color primaryColor,
    required Color secondaryColor,
    required TextStyle defaultTextStyle,
    required int defaultLineHeight,
    required double defaultLineThickness,
    required CanvasBackgroundPattern defaultPattern,
    required Color defaultBackgroundColor,
    double? devicePixelRatio,
    bool forceSchedule = false,
  }) {
    if (_disposed || coreInfo.pages.isEmpty) return;
    final start = bandStart.clamp(0, coreInfo.pages.length - 1);
    final end = bandEnd.clamp(0, coreInfo.pages.length - 1);
    final center = ((start + end) / 2).round();
    final maxDist = math.max(center - start, end - center);
    for (var dist = 0; dist <= maxDist; dist++) {
      for (final i in <int>{center - dist, if (dist > 0) center + dist}) {
        if (i < start || i > end) continue;
        _schedulePage(
          coreInfo: coreInfo,
          pageIndex: i,
          scale: scale,
          devicePixelRatio: devicePixelRatio,
          invert: invert,
          primaryColor: primaryColor,
          secondaryColor: secondaryColor,
          defaultTextStyle: defaultTextStyle,
          defaultLineHeight: defaultLineHeight,
          defaultLineThickness: defaultLineThickness,
          defaultPattern: defaultPattern,
          defaultBackgroundColor: defaultBackgroundColor,
          forceSchedule: forceSchedule,
        );
      }
    }
  }

  void maintainVisibleBand({
    required EditorCoreInfo coreInfo,
    required int visibleStart,
    required int visibleEnd,
    required double scale,
    required bool invert,
    required Color primaryColor,
    required Color secondaryColor,
    required TextStyle defaultTextStyle,
    required int defaultLineHeight,
    required double defaultLineThickness,
    required CanvasBackgroundPattern defaultPattern,
    required Color defaultBackgroundColor,
    double? devicePixelRatio,
    bool forceSchedule = false,
  }) {
    if (_disposed || coreInfo.pages.isEmpty) return;
    final visibleCount = (visibleEnd - visibleStart + 1).clamp(1, 64);
    final radius = math.max(2, visibleCount);
    final bandStart = (visibleStart - radius).clamp(0, coreInfo.pages.length - 1);
    final bandEnd = (visibleEnd + radius).clamp(0, coreInfo.pages.length - 1);
    final keep = <int>{
      for (var i = bandStart; i <= bandEnd; i++) i,
    };
    dropExcept(keep);
    releaseOffBandGeometry(coreInfo, keep);
    prefetchBand(
      coreInfo: coreInfo,
      bandStart: bandStart,
      bandEnd: bandEnd,
      scale: scale,
      devicePixelRatio: devicePixelRatio,
      invert: invert,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
      defaultTextStyle: defaultTextStyle,
      defaultLineHeight: defaultLineHeight,
      defaultLineThickness: defaultLineThickness,
      defaultPattern: defaultPattern,
      defaultBackgroundColor: defaultBackgroundColor,
      forceSchedule: forceSchedule,
    );
  }

  void _schedulePage({
    required EditorCoreInfo coreInfo,
    required int pageIndex,
    required double scale,
    double? devicePixelRatio,
    required bool invert,
    required Color primaryColor,
    required Color secondaryColor,
    required TextStyle defaultTextStyle,
    required int defaultLineHeight,
    required double defaultLineThickness,
    required CanvasBackgroundPattern defaultPattern,
    required Color defaultBackgroundColor,
    bool forceSchedule = false,
  }) {
    if (pageIndex < 0 || pageIndex >= coreInfo.pages.length) return;
    if (coreInfo.isLazyShellPage(pageIndex)) return;
    final page = coreInfo.pages[pageIndex];
    final pageSize = page.size;
    final inkStrokes = page.allStrokesInDrawOrder
        .where((s) => s.toolId != ToolId.highlighter)
        .toList(growable: false);
    final bgParams = pageRasterBgParamsFor(
      page: page,
      coreInfo: coreInfo,
      invert: invert,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
      defaultLineHeight: defaultLineHeight,
      defaultLineThickness: defaultLineThickness,
      defaultPattern: defaultPattern,
      defaultBackgroundColor: defaultBackgroundColor,
    );
    backgroundForOrSchedule(
      pageIndex: pageIndex,
      pageSize: pageSize,
      scale: scale,
      devicePixelRatio: devicePixelRatio,
      params: bgParams,
      hasFullBleedBackground: page.backgroundImage != null,
      forceSchedule: forceSchedule,
    );
    // We deliberately DO NOT schedule ink here. Whole-page ink toImage() calls 
    // block the raster thread and cause severe lag/flicker. Ink caching is 
    // handled efficiently via TiledStrokePictureCache inside InnerCanvas.
  }

  void _enqueue(_RasterJob job) {
    _jobQueue.add(job);
    if (!_jobRunning) {
      unawaited(_processQueue());
    }
  }

  Future<void> _processQueue() async {
    _jobRunning = true;
    while (_jobQueue.isNotEmpty && !_disposed) {
      // Never run CanvasPainter + toImage on the UI isolate mid-stroke —
      // that is the classic cause of dropped pointer samples / square ink.
      if (inkInputBusy && !debugForceSyncRaster) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
        continue;
      }
      final job = _jobQueue.removeFirst();
      if (job.cacheGen != _cacheGen) {
        _clearPending(job);
        continue;
      }
      final targetRes = clampedRes(
        effectiveScale(job.viewportScale),
        job.pageSize,
        devicePixelRatio: job.devicePixelRatio,
      );
      if (!_resSufficient(job.res, targetRes)) {
        _clearPending(job);
        continue;
      }
      if (inkInputBusy && !debugForceSyncRaster) {
        _jobQueue.addFirst(job);
        await Future<void>.delayed(const Duration(milliseconds: 16));
        continue;
      }
      final image = await _buildJob(job);
      if (_disposed || job.cacheGen != _cacheGen) {
        image?.dispose();
        _clearPending(job);
        continue;
      }
      final expectedGen = job.isInk ? _inkGen(job.pageIndex) : _bgGen(job.pageIndex);
      if (job.generation != expectedGen) {
        image?.dispose();
        _clearPending(job);
        continue;
      }
      if (image == null) {
        _clearPending(job);
        continue;
      }
      final entry = PageCacheEntry(
        image: image,
        res: job.res,
        generation: job.generation,
        strokeCount: job.isInk ? (job.inkParams?.strokes.length ?? 0) : 0,
      );
      if (job.isInk) {
        _inkCaches[job.pageIndex]?.image.dispose();
        _inkCaches[job.pageIndex] = entry;
        _pendingInk.remove(job.pageIndex);
      } else {
        _bgCaches[job.pageIndex]?.image.dispose();
        _bgCaches[job.pageIndex] = entry;
        _pendingBg.remove(job.pageIndex);
      }
      _bumpRepaint();
      await Future<void>.delayed(Duration.zero);
    }
    _jobRunning = false;
  }

  void _clearPending(_RasterJob job) {
    if (job.isInk) {
      _pendingInk.remove(job.pageIndex);
    } else {
      _pendingBg.remove(job.pageIndex);
    }
  }

  Future<ui.Image?> _buildJob(_RasterJob job) async {
    final w = math.max(1, (job.pageSize.width * job.res).ceil());
    final h = math.max(1, (job.pageSize.height * job.res).ceil());
    
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    canvas.scale(job.res, job.res);
    
    if (job.isInk) {
      final params = job.inkParams!;
      CanvasPainter(
        invert: params.invert,
        strokes: params.strokes,
        laserStrokes: const [],
        currentStroke: null,
        currentSelection: null,
        primaryColor: params.primaryColor,
        page: params.page,
        showPageIndicator: false,
        pageIndex: params.pageIndex,
        totalPages: params.totalPages,
        currentScale: params.currentScale,
        defaultTextStyle: params.defaultTextStyle,
        lineHeight: params.lineHeight,
        lineThickness: params.lineThickness,
        lineColor: params.lineColor,
        doneSelecting: true,
      ).paint(canvas, job.pageSize);
    } else {
      final params = job.bgParams!;
      CanvasBackgroundPainter(
        invert: params.invert,
        backgroundColor: params.backgroundColor,
        backgroundPattern: params.backgroundPattern,
        lineHeight: params.lineHeight,
        lineThickness: params.lineThickness,
        primaryColor: params.primaryColor,
        secondaryColor: params.secondaryColor,
        marginLeft: params.marginLeft,
        marginRight: params.marginRight,
        marginTop: params.marginTop,
        marginBottom: params.marginBottom,
        borderColor: params.borderColor,
      ).paint(canvas, job.pageSize);
    }
    
    final picture = recorder.endRecording();
    
    if (debugForceSyncRaster) {
      final image = picture.toImageSync(w, h);
      picture.dispose();
      return image;
    }

    if (_disposed) {
      picture.dispose();
      return null;
    }

    final image = await picture.toImage(w, h);
    picture.dispose();
    return image;
  }

  void _bumpRepaint() {
    repaintEpoch.value++;
    onRepaintRequested?.call();
  }

  void dispose() {
    _disposed = true;
    _jobQueue.clear();
    for (final entry in _inkCaches.values) {
      entry.image.dispose();
    }
    for (final entry in _bgCaches.values) {
      entry.image.dispose();
    }
    _inkCaches.clear();
    _bgCaches.clear();
    _pendingInk.clear();
    _pendingBg.clear();
  }

  @visibleForTesting
  int get debugInkCacheCount => _inkCaches.length;

  @visibleForTesting
  int get debugBgCacheCount => _bgCaches.length;

  @visibleForTesting
  bool get debugHasPendingInk => _pendingInk.isNotEmpty;

  @visibleForTesting
  bool get debugHasPendingBg => _pendingBg.isNotEmpty;
}

final class _RasterJob {
  _RasterJob.ink({
    required this.pageIndex,
    required this.pageSize,
    required this.res,
    required this.generation,
    required this.cacheGen,
    required this.devicePixelRatio,
    required this.viewportScale,
    required PageRasterInkParams inkParams,
  }) : isInk = true,
       inkParams = inkParams,
       bgParams = null;

  _RasterJob.bg({
    required this.pageIndex,
    required this.pageSize,
    required this.res,
    required this.generation,
    required this.cacheGen,
    required this.devicePixelRatio,
    required this.viewportScale,
    required PageRasterBgParams bgParams,
  }) : isInk = false,
       inkParams = null,
       bgParams = bgParams;

  final bool isInk;
  final int pageIndex;
  final Size pageSize;
  final double res;
  final int generation;
  final int cacheGen;
  final double devicePixelRatio;
  final double viewportScale;
  final PageRasterInkParams? inkParams;
  final PageRasterBgParams? bgParams;
}

/// Background raster params for a page (pattern/grid; not full-bleed images).
PageRasterBgParams pageRasterBgParamsFor({
  required EditorPage page,
  required EditorCoreInfo coreInfo,
  required bool invert,
  required Color primaryColor,
  required Color secondaryColor,
  required int defaultLineHeight,
  required double defaultLineThickness,
  required CanvasBackgroundPattern defaultPattern,
  required Color defaultBackgroundColor,
}) {
  final hasBgImage = page.backgroundImage != null;
  return PageRasterBgParams(
    invert: invert,
    backgroundColor: hasBgImage
        ? Colors.white
        : (page.backgroundColor.value != 0xFFFFFFFF
              ? page.backgroundColor
              : defaultBackgroundColor),
    backgroundPattern: hasBgImage
        ? CanvasBackgroundPattern.none
        : (page.backgroundPattern ?? defaultPattern),
    lineHeight: page.hasLocalLineHeight
        ? page.lineHeight
        : defaultLineHeight,
    lineThickness: page.hasLocalLineThickness
        ? page.lineThickness.toInt()
        : defaultLineThickness.toInt(),
    primaryColor: page.lineColor.value != 0xFF9E9E9E
        ? page.lineColor
        : primaryColor,
    secondaryColor: (page.lineColor.value != 0xFF9E9E9E
            ? page.lineColor
            : secondaryColor)
        .withValues(alpha: 0.5),
    marginLeft: page.marginLeft,
    marginRight: page.marginRight,
    marginTop: page.marginTop,
    marginBottom: page.marginBottom,
    borderColor:
        page.hasLocalBorderColor ||
            (page.marginLeft > 0 ||
                page.marginRight > 0 ||
                page.marginTop > 0 ||
                page.marginBottom > 0)
        ? page.borderColor
        : null,
  );
}

/// Blit helper used by [InnerCanvas] painters.
void paintPageCacheImage(
  Canvas canvas,
  Size size,
  PageCacheEntry entry, {
  required double targetRes,
  required bool lowQualityFilter,
}) {
  final src = Rect.fromLTWH(
    0,
    0,
    entry.image.width.toDouble(),
    entry.image.height.toDouble(),
  );
  final staleUpscale = !_resSufficientForBlit(entry.res, targetRes);
  final filter = lowQualityFilter || staleUpscale
      ? FilterQuality.low
      : (entry.res >= targetRes * 0.99
            ? FilterQuality.high
            : FilterQuality.medium);
  canvas.drawImageRect(
    entry.image,
    src,
    Offset.zero & size,
    Paint()..filterQuality = filter,
  );
}

bool _resSufficientForBlit(double cachedRes, double targetRes) =>
    cachedRes >= targetRes * 0.98;

/// Whether [cachedRes] is enough to blit without upscaling artifacts.
bool pageRasterCacheResCoversTarget(double cachedRes, double targetRes) =>
    _resSufficientForBlit(cachedRes, targetRes);
