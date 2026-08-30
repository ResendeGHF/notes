// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/pen.dart';

import '../../helpers/test_stroke_factory.dart';

void _paintCache(
  TiledStrokePictureCache cache,
  EditorPage page, {
  required List<Stroke> strokes,
  int maxNewTilesPerPaint = 1,
  int? tileRecordBudgetMs,
  Rect? clip,
  double currentScale = 1,
  bool enableRasterLod = true,
  bool followLiveViewportScale = true,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, page.size.width, page.size.height),
  );
  canvas.clipRect(clip ?? (Offset.zero & page.size));
  cache.paint(
    canvas: canvas,
    size: page.size,
    invert: false,
    strokes: strokes,
    page: page,
    primaryColor: Colors.blue,
    pageIndex: 0,
    totalPages: 1,
    currentScale: currentScale,
    enableRasterLod: enableRasterLod,
    followLiveViewportScale: followLiveViewportScale,
    defaultTextStyle: const TextStyle(),
    maxNewTilesPerPaint: maxNewTilesPerPaint,
    tileRecordBudgetMs: tileRecordBudgetMs,
  );
  recorder.endRecording().dispose();
}

bool _rastersMatchLod(TiledStrokePictureCache cache, double lod) {
  return cache.debugRasterCount > 0 &&
      cache.debugRasterCount == cache.recordedTileCount &&
      cache.debugRasterScales.every((s) => (s - lod).abs() < 0.01);
}

void _paintUntilRasterLod(
  TiledStrokePictureCache cache,
  EditorPage page, {
  required List<Stroke> strokes,
  required double currentScale,
}) {
  final lod = TiledStrokePictureCache.rasterLodScale(
    TiledStrokePictureCache.effectiveScale(currentScale),
  );
  for (var i = 0; i < 24; i++) {
    _paintCache(
      cache,
      page,
      strokes: strokes,
      maxNewTilesPerPaint: 32,
      currentScale: currentScale,
    );
    if (_rastersMatchLod(cache, lod)) return;
  }
  fail('rasters did not reach lod $lod: ${cache.debugRasterScales.toList()}');
}

Future<void> _pumpUntilAsyncRasterLod(
  WidgetTester tester,
  TiledStrokePictureCache cache,
  EditorPage page, {
  required List<Stroke> strokes,
  required double currentScale,
}) async {
  final lod = TiledStrokePictureCache.rasterLodScale(
    TiledStrokePictureCache.effectiveScale(currentScale),
  );
  for (var i = 0; i < 40; i++) {
    _paintCache(
      cache,
      page,
      strokes: strokes,
      maxNewTilesPerPaint: 32,
      currentScale: currentScale,
    );
    if (_rastersMatchLod(cache, lod)) return;
    await tester.pump();
    await tester.pump(Duration.zero);
  }
  fail(
    'async rasters did not reach lod $lod: ${cache.debugRasterScales.toList()}',
  );
}

void _prewarm(EditorPage page) {
  var offset = 0;
  while (offset != -1) {
    offset = page.prewarmStrokeMeshes(startOffset: offset, maxStrokes: 64);
  }
}

List<Stroke> _spreadStrokes() => [
  testPolylineStroke(toolId: ToolId.ballpointPen, y: 80, x0: 20, x1: 180),
  testPolylineStroke(toolId: ToolId.ballpointPen, y: 700, x0: 20, x1: 180),
  testPolylineStroke(toolId: ToolId.ballpointPen, y: 80, x0: 600, x1: 780),
];

void main() {
  setUp(() {
    TiledStrokePictureCache.debugResetViewportLod();
    TiledStrokePictureCache.debugForceSyncRaster = true;
  });

  tearDown(() {
    TiledStrokePictureCache.debugResetViewportLod();
    Eraser.isDragging = false;
    Pen.currentStroke = null;
  });

  testWidgets('moving viewport does not record new tiles (blit-only)', (
    tester,
  ) async {
    TiledStrokePictureCache.viewportMoving = false;
    final page = EditorPage();
    final strokes = _spreadStrokes();
    for (final stroke in strokes) {
      page.insertStroke(stroke);
    }
    _prewarm(page);

    final cache = page.strokePictureCache;
    _paintCache(
      cache,
      page,
      strokes: strokes,
      clip: const Rect.fromLTWH(0, 0, 400, 400),
    );
    final settledCount = cache.recordedTileCount;
    expect(settledCount, greaterThan(0));

    TiledStrokePictureCache.viewportMoving = true;
    _paintCache(cache, page, strokes: strokes);
    expect(
      cache.recordedTileCount,
      settledCount,
      reason: 'pan/zoom must not record new Pictures; only blit existing rasters',
    );
    expect(cache.debugLivePaintedTileCount, 0);

    page.dispose();
  });

  testWidgets('invalidateRect refills every dirty visible tile in one paint', (
    tester,
  ) async {
    final page = EditorPage();
    final strokes = _spreadStrokes();
    for (final stroke in strokes) {
      page.insertStroke(stroke);
    }
    _prewarm(page);

    final cache = page.strokePictureCache;
    _paintCache(cache, page, strokes: strokes, maxNewTilesPerPaint: 32);
    final filled = cache.recordedTileCount;
    expect(filled, greaterThan(1));

    cache.invalidateRect(const Rect.fromLTWH(0, 0, 1000, 1400));
    expect(cache.willEagerRefillVisibleTiles, isTrue);
    expect(cache.recordedTileCount, 0);

    _paintCache(cache, page, strokes: strokes, maxNewTilesPerPaint: 1);
    expect(cache.recordedTileCount, filled);
    expect(cache.willEagerRefillVisibleTiles, isFalse);

    page.dispose();
  });

  testWidgets('scrolling cold cache skips recording while viewport is moving', (
    tester,
  ) async {
    TiledStrokePictureCache.viewportMoving = true;
    final page = EditorPage();
    final strokes = _spreadStrokes();
    for (final stroke in strokes) {
      page.insertStroke(stroke);
    }

    final cache = page.strokePictureCache;
    _paintCache(cache, page, strokes: strokes, maxNewTilesPerPaint: 1);
    expect(
      cache.recordedTileCount,
      0,
      reason: 'cold tiles are not recorded mid-motion (tileBudget 0)',
    );
    expect(cache.debugLivePaintedTileCount, 0);

    TiledStrokePictureCache.viewportMoving = false;
    await tester.pump(TiledStrokePictureCache.viewportSettleDelay);
    _paintCache(cache, page, strokes: strokes, maxNewTilesPerPaint: 1);
    expect(cache.recordedTileCount, greaterThan(1));
    expect(cache.debugPathOnlyTileCount, 0);
    expect(
      strokes.every((s) => s.hasCachedMesh),
      isTrue,
      reason: 'ballpoint tiles must record drawVertices, not path fill',
    );

    page.dispose();
  });

  testWidgets('opening records ballpoint mesh tiles immediately', (
    tester,
  ) async {
    TiledStrokePictureCache.viewportMoving = false;
    final page = EditorPage();
    final strokes = _spreadStrokes();
    for (final stroke in strokes) {
      page.insertStroke(stroke);
    }

    final cache = page.strokePictureCache;
    _paintCache(cache, page, strokes: strokes, maxNewTilesPerPaint: 1);
    expect(cache.recordedTileCount, greaterThan(1));
    expect(cache.debugPathOnlyTileCount, 0);
    expect(cache.debugLivePaintedTileCount, 0);
    expect(
      strokes.any((s) => s.needsTileMeshWarmup),
      isFalse,
      reason: 'spine-mesh pens must not wait on path-only warmup',
    );
    expect(strokes.every((s) => s.hasCachedMesh), isTrue);

    page.dispose();
  });

  testWidgets('opening shows Advanced Pen without a new stroke', (
    tester,
  ) async {
    TiledStrokePictureCache.viewportMoving = false;
    final page = EditorPage();
    final stroke = testPolylineStroke(
      toolId: ToolId.advancedPen,
      y: 80,
      x0: 20,
      x1: 400,
      points: 80,
    );
    page.insertStroke(stroke);

    expect(stroke.needsTileMeshWarmup, isFalse);
    expect(stroke.vertices, isNull);
    final cache = page.strokePictureCache;
    _paintCache(cache, page, strokes: [stroke], maxNewTilesPerPaint: 1);
    expect(cache.recordedTileCount, greaterThan(0));
    expect(cache.debugLivePaintedTileCount, 0);
    expect(stroke.highQualityPath.getBounds().isEmpty, isFalse);
    expect(stroke.vertices, isNull);

    _prewarm(page);
    _paintCache(
      cache,
      page,
      strokes: [stroke],
      tileRecordBudgetMs: TiledStrokePictureCache.idleTileBudgetMs,
    );
    expect(cache.recordedTileCount, greaterThan(0));
    expect(stroke.vertices, isNull);
    expect(stroke.needsTileMeshWarmup, isFalse);

    page.dispose();
  });

  testWidgets('idle time budget can record more than one warmed tile', (
    tester,
  ) async {
    final page = EditorPage();
    final strokes = _spreadStrokes();
    for (final stroke in strokes) {
      page.insertStroke(stroke);
    }
    _prewarm(page);

    final cache = page.strokePictureCache;
    _paintCache(
      cache,
      page,
      strokes: strokes,
      tileRecordBudgetMs: TiledStrokePictureCache.idleTileBudgetMs,
    );
    expect(cache.recordedTileCount, greaterThan(1));

    page.dispose();
  });

  testWidgets('eraser dirty rect records tiles again while dragging', (
    tester,
  ) async {
    Eraser.isDragging = true;
    final page = EditorPage();
    final strokes = _spreadStrokes();
    for (final stroke in strokes) {
      page.insertStroke(stroke);
    }
    _prewarm(page);

    final cache = page.strokePictureCache;
    _paintCache(cache, page, strokes: strokes, maxNewTilesPerPaint: 32);
    final filled = cache.recordedTileCount;
    expect(filled, greaterThan(1));

    cache.invalidateRect(
      const Rect.fromLTWH(0, 0, 1000, 1400),
      eagerRefill: true,
    );
    expect(cache.willEagerRefillVisibleTiles, isTrue);
    expect(cache.recordedTileCount, 0);

    _paintCache(cache, page, strokes: strokes, maxNewTilesPerPaint: 1);
    expect(cache.recordedTileCount, filled);
    expect(cache.debugLivePaintedTileCount, 0);
    expect(cache.willEagerRefillVisibleTiles, isFalse);

    page.dispose();
  });

  test('raster LOD snaps zoom to quarter-stops', () {
    expect(TiledStrokePictureCache.rasterLodScale(1), 1);
    expect(TiledStrokePictureCache.rasterLodScale(2.4), 2.5);
    expect(TiledStrokePictureCache.rasterLodScale(2.45), 2.5);
    expect(TiledStrokePictureCache.rasterLodScale(3), 3);
    expect(TiledStrokePictureCache.rasterLodScale(3.1), 3);
    expect(TiledStrokePictureCache.usesVectorStrokes(3.99), isFalse);
    expect(TiledStrokePictureCache.usesVectorStrokes(4), isTrue);
    expect(
      TiledStrokePictureCache.rasterQuality(0.3),
      greaterThan(TiledStrokePictureCache.rasterQuality(0.7)),
    );
    expect(
      TiledStrokePictureCache.rasterQuality(0.7),
      greaterThan(TiledStrokePictureCache.rasterQuality(1)),
    );
    expect(
      TiledStrokePictureCache.rasterQuality(1),
      lessThan(TiledStrokePictureCache.rasterQuality(1.5)),
    );
    expect(
      TiledStrokePictureCache.rasterQuality(1.5),
      lessThan(TiledStrokePictureCache.rasterQuality(2.5)),
    );
    expect(TiledStrokePictureCache.maxRasterEdgePxForScale(1), 1280);
    expect(
      TiledStrokePictureCache.maxRasterEdgePxForScale(1.5),
      greaterThan(TiledStrokePictureCache.maxRasterEdgePxForScale(1)),
    );
    expect(
      TiledStrokePictureCache.maxRasterEdgePxForScale(2),
      greaterThan(TiledStrokePictureCache.maxRasterEdgePxForScale(1.5)),
    );
    expect(
      TiledStrokePictureCache.maxRasterEdgePxForScale(3),
      greaterThan(TiledStrokePictureCache.maxRasterEdgePxForScale(2)),
    );
  });

  test('raster LOD quality follows stroke density and fine-ink pens', () {
    expect(
      TiledStrokePictureCache.rasterQuality(1, strokeCount: 10),
      greaterThan(TiledStrokePictureCache.rasterQuality(1, strokeCount: 90)),
    );
    expect(
      TiledStrokePictureCache.rasterQuality(1, strokeCount: 90),
      greaterThan(TiledStrokePictureCache.rasterQuality(1, strokeCount: 250)),
    );
    expect(
      TiledStrokePictureCache.rasterQuality(1, fineInk: true),
      closeTo(
        TiledStrokePictureCache.rasterQuality(1) *
            RasterLodTuning.fineInkQualityBoost,
        1e-9,
      ),
    );
    expect(
      TiledStrokePictureCache.rasterQuality(
        1,
        strokeCount: 90,
        fineInk: false,
      ),
      TiledStrokePictureCache.rasterQuality(1),
    );
    expect(
      TiledStrokePictureCache.maxRasterEdgePxForScale(1, fineInk: true),
      (1280 * RasterLodTuning.fineInkCapMul).round(),
    );
    expect(
      TiledStrokePictureCache.maxRasterEdgePxForScale(1, fineInk: false),
      1280,
    );
  });

  testWidgets('settled tiles rasterize at the current zoom', (tester) async {
    final page = EditorPage();
    final strokes = _spreadStrokes();
    for (final stroke in strokes) {
      page.insertStroke(stroke);
    }
    _prewarm(page);

    final cache = page.strokePictureCache;
    _paintCache(
      cache,
      page,
      strokes: strokes,
      maxNewTilesPerPaint: 32,
      currentScale: 1,
    );
    expect(cache.recordedTileCount, greaterThan(0));
    expect(cache.debugRasterCount, greaterThan(0));
    expect(cache.debugAnyRasterScale, closeTo(1, 0.01));

    page.dispose();
  });

  testWidgets('zoom keeps stale rasters until the viewport settles', (
    tester,
  ) async {
    final page = EditorPage();
    final strokes = _spreadStrokes();
    for (final stroke in strokes) {
      page.insertStroke(stroke);
    }
    _prewarm(page);

    final cache = page.strokePictureCache;
    _paintCache(
      cache,
      page,
      strokes: strokes,
      maxNewTilesPerPaint: 32,
      currentScale: 1,
    );
    expect(cache.debugAnyRasterScale, closeTo(1, 0.01));
    final baked = cache.debugRasterCount;

    TiledStrokePictureCache.updateViewportMoving(true);
    _paintCache(
      cache,
      page,
      strokes: strokes,
      maxNewTilesPerPaint: 32,
      currentScale: 2.4,
    );
    expect(cache.debugRasterCount, baked);
    expect(cache.debugAnyRasterScale, closeTo(1, 0.01));

    TiledStrokePictureCache.updateViewportMoving(false);
    expect(TiledStrokePictureCache.viewportSettled, isFalse);

    await tester.pump(TiledStrokePictureCache.viewportSettleDelay);
    expect(TiledStrokePictureCache.viewportSettled, isTrue);

    _paintUntilRasterLod(cache, page, strokes: strokes, currentScale: 2.4);
    expect(
      cache.debugRasterScales,
      everyElement(closeTo(TiledStrokePictureCache.rasterLodScale(2.4), 0.01)),
    );
    final settledCount = cache.debugRasterCount;

    // Pan/fling at the same zoom must keep that LOD — no vector replay, no rebake.
    TiledStrokePictureCache.updateViewportMoving(true);
    _paintCache(
      cache,
      page,
      strokes: strokes,
      maxNewTilesPerPaint: 32,
      currentScale: 2.4,
    );
    expect(
      cache.debugAnyRasterScale,
      closeTo(TiledStrokePictureCache.rasterLodScale(2.4), 0.01),
    );
    expect(cache.debugRasterCount, settledCount);

    TiledStrokePictureCache.updateViewportMoving(false);
    await tester.pump(TiledStrokePictureCache.viewportSettleDelay);
    _paintCache(
      cache,
      page,
      strokes: strokes,
      maxNewTilesPerPaint: 32,
      currentScale: 2.45,
    );
    expect(
      cache.debugAnyRasterScale,
      closeTo(TiledStrokePictureCache.rasterLodScale(2.4), 0.01),
      reason: '2.45 stays in the same quarter-stop LOD as 2.4',
    );
    expect(cache.debugRasterCount, settledCount);

    page.dispose();
  });

  testWidgets('pan inertia keeps stale rasters; bake after motion settles', (
    tester,
  ) async {
    final page = EditorPage();
    final strokes = _spreadStrokes();
    for (final stroke in strokes) {
      page.insertStroke(stroke);
    }
    _prewarm(page);

    final cache = page.strokePictureCache;
    _paintCache(
      cache,
      page,
      strokes: strokes,
      maxNewTilesPerPaint: 32,
      currentScale: 1,
    );
    expect(cache.debugAnyRasterScale, closeTo(1, 0.01));
    final settledCount = cache.debugRasterCount;

    TiledStrokePictureCache.updateViewportMoving(true);
    _paintCache(
      cache,
      page,
      strokes: strokes,
      maxNewTilesPerPaint: 32,
      currentScale: 3,
    );
    expect(
      cache.debugAnyRasterScale,
      closeTo(1, 0.01),
      reason: 'mid-pan must blit stale LOD, not rebake',
    );
    expect(cache.debugRasterCount, settledCount);
    expect(TiledStrokePictureCache.zoomLodSettled, isFalse);

    // Zoom LOD may settle while inertia still holds viewportMoving.
    await tester.pump(TiledStrokePictureCache.viewportSettleDelay);
    expect(TiledStrokePictureCache.viewportMoving, isTrue);
    _paintCache(
      cache,
      page,
      strokes: strokes,
      maxNewTilesPerPaint: 32,
      currentScale: 3,
    );
    expect(
      cache.debugAnyRasterScale,
      closeTo(1, 0.01),
      reason: 'viewportMoving still blocks raster bake',
    );

    TiledStrokePictureCache.updateViewportMoving(false);
    await tester.pump(TiledStrokePictureCache.viewportSettleDelay);
    _paintUntilRasterLod(cache, page, strokes: strokes, currentScale: 3);
    expect(
      cache.debugRasterScales,
      everyElement(closeTo(TiledStrokePictureCache.rasterLodScale(3), 0.01)),
    );

    page.dispose();
  });

  testWidgets('same zoom settle does not rebake rasters', (tester) async {
    final page = EditorPage();
    final strokes = _spreadStrokes();
    for (final stroke in strokes) {
      page.insertStroke(stroke);
    }
    _prewarm(page);

    final cache = page.strokePictureCache;
    _paintUntilRasterLod(cache, page, strokes: strokes, currentScale: 3);
    expect(
      cache.debugRasterScales,
      everyElement(closeTo(TiledStrokePictureCache.rasterLodScale(3), 0.01)),
    );
    final baked = cache.debugRasterCount;
    final first = cache.debugFirstRaster;
    expect(first, isNotNull);

    TiledStrokePictureCache.updateViewportMoving(true);
    TiledStrokePictureCache.updateViewportMoving(false);
    await tester.pump(TiledStrokePictureCache.viewportSettleDelay);
    _paintCache(
      cache,
      page,
      strokes: strokes,
      maxNewTilesPerPaint: 32,
      currentScale: 3,
    );
    expect(cache.debugRasterCount, baked);
    expect(
      identical(cache.debugFirstRaster, first),
      isTrue,
      reason: 'same zoom LOD must reuse the already-baked raster',
    );

    page.dispose();
  });

  testWidgets('zoom LOD settle keeps the old raster on the trigger frame', (
    tester,
  ) async {
    final page = EditorPage();
    final strokes = _spreadStrokes();
    for (final stroke in strokes) {
      page.insertStroke(stroke);
    }
    _prewarm(page);

    final cache = page.strokePictureCache;
    TiledStrokePictureCache.debugForceSyncRaster = true;
    _paintUntilRasterLod(cache, page, strokes: strokes, currentScale: 1);
    final first = cache.debugFirstRaster;
    expect(first, isNotNull);

    TiledStrokePictureCache.debugForceSyncRaster = false;
    TiledStrokePictureCache.setViewportScale(3);
    await tester.pump(TiledStrokePictureCache.viewportSettleDelay);
    _paintCache(
      cache,
      page,
      strokes: strokes,
      maxNewTilesPerPaint: 32,
      currentScale: 3,
    );
    expect(
      identical(cache.debugFirstRaster, first),
      isTrue,
      reason: 'settle paint must blit the old raster, not bake in-frame',
    );
    expect(cache.debugAnyRasterScale, closeTo(1, 0.01));

    page.dispose();
    await tester.pump();
    await tester.pump(Duration.zero);
  });

  testWidgets('zoom LOD async bake swaps rasters without a new stroke', (
    tester,
  ) async {
    final page = EditorPage();
    final strokes = _spreadStrokes();
    for (final stroke in strokes) {
      page.insertStroke(stroke);
    }
    _prewarm(page);

    final cache = page.strokePictureCache;
    _paintUntilRasterLod(cache, page, strokes: strokes, currentScale: 1);
    expect(cache.debugAnyRasterScale, closeTo(1, 0.01));

    TiledStrokePictureCache.debugForceSyncRaster = false;
    TiledStrokePictureCache.setViewportScale(3);
    await tester.pump(TiledStrokePictureCache.viewportSettleDelay);
    expect(TiledStrokePictureCache.zoomLodSettled, isTrue);

    await _pumpUntilAsyncRasterLod(
      tester,
      cache,
      page,
      strokes: strokes,
      currentScale: 1,
    );
    expect(
      cache.debugRasterScales,
      everyElement(closeTo(TiledStrokePictureCache.rasterLodScale(3), 0.01)),
    );

    page.dispose();
  });

  testWidgets('live viewport scale rebakes without a widget scale rebuild', (
    tester,
  ) async {
    final page = EditorPage();
    final strokes = _spreadStrokes();
    for (final stroke in strokes) {
      page.insertStroke(stroke);
    }
    _prewarm(page);

    final cache = page.strokePictureCache;
    _paintUntilRasterLod(cache, page, strokes: strokes, currentScale: 1);
    expect(cache.debugAnyRasterScale, closeTo(1, 0.01));

    TiledStrokePictureCache.setViewportScale(3);
    expect(TiledStrokePictureCache.zoomLodSettled, isFalse);

    await tester.pump(TiledStrokePictureCache.viewportSettleDelay);
    expect(TiledStrokePictureCache.zoomLodSettled, isTrue);

    _paintUntilRasterLod(cache, page, strokes: strokes, currentScale: 1);
    expect(
      cache.debugRasterScales,
      everyElement(closeTo(TiledStrokePictureCache.rasterLodScale(3), 0.01)),
    );

    page.dispose();
  });

  testWidgets('zoom 4 keeps vector strokes and does not rebake rasters', (
    tester,
  ) async {
    final page = EditorPage();
    final strokes = _spreadStrokes();
    for (final stroke in strokes) {
      page.insertStroke(stroke);
    }
    _prewarm(page);

    final cache = page.strokePictureCache;
    _paintUntilRasterLod(cache, page, strokes: strokes, currentScale: 1);
    final baked = cache.debugRasterCount;
    expect(cache.debugAnyRasterScale, closeTo(1, 0.01));

    _paintCache(
      cache,
      page,
      strokes: strokes,
      maxNewTilesPerPaint: 32,
      currentScale: 4,
    );
    expect(cache.debugRasterCount, baked);
    expect(cache.debugAnyRasterScale, closeTo(1, 0.01));

    page.dispose();
  });

  testWidgets('drawing a new stroke still updates committed rasters', (
    tester,
  ) async {
    final page = EditorPage();
    final strokes = _spreadStrokes();
    for (final stroke in strokes) {
      page.insertStroke(stroke);
    }
    _prewarm(page);

    final cache = page.strokePictureCache;
    _paintUntilRasterLod(cache, page, strokes: strokes, currentScale: 1);

    Pen.currentStroke = testPolylineStroke(
      toolId: ToolId.ballpointPen,
      y: 200,
      x0: 20,
      x1: 80,
    );

    TiledStrokePictureCache.setViewportScale(2.5);
    await tester.pump(TiledStrokePictureCache.viewportSettleDelay);
    _paintUntilRasterLod(cache, page, strokes: strokes, currentScale: 1);
    expect(
      cache.debugRasterScales,
      everyElement(closeTo(TiledStrokePictureCache.rasterLodScale(2.5), 0.01)),
    );

    page.dispose();
  });

  testWidgets('sidebar resize session keeps raster blit and ignores pan-idle', (
    tester,
  ) async {
    final page = EditorPage();
    final strokes = _spreadStrokes();
    for (final stroke in strokes) {
      page.insertStroke(stroke);
    }
    _prewarm(page);

    final cache = page.strokePictureCache;
    _paintUntilRasterLod(cache, page, strokes: strokes, currentScale: 1);
    final baked = cache.debugRasterCount;
    final first = cache.debugFirstRaster;

    TiledStrokePictureCache.beginLayoutResizeSession();
    expect(TiledStrokePictureCache.viewportMoving, isTrue);
    TiledStrokePictureCache.updateViewportMoving(false);
    expect(
      TiledStrokePictureCache.viewportMoving,
      isTrue,
      reason: 'sidebar animation frames must not drop raster LOD',
    );

    _paintCache(
      cache,
      page,
      strokes: strokes,
      maxNewTilesPerPaint: 32,
      currentScale: 1,
    );
    expect(cache.debugRasterCount, baked);
    expect(identical(cache.debugFirstRaster, first), isTrue);

    TiledStrokePictureCache.endLayoutResizeSession();
    expect(TiledStrokePictureCache.viewportMoving, isFalse);
    await tester.pump(TiledStrokePictureCache.viewportSettleDelay);

    page.dispose();
  });

  testWidgets('layout occlusion keeps raster LOD active while docked', (
    tester,
  ) async {
    final page = EditorPage();
    final strokes = _spreadStrokes();
    for (final stroke in strokes) {
      page.insertStroke(stroke);
    }
    _prewarm(page);

    final cache = page.strokePictureCache;
    _paintUntilRasterLod(cache, page, strokes: strokes, currentScale: 1);

    TiledStrokePictureCache.pushLayoutOcclusion();
    expect(TiledStrokePictureCache.viewportMoving, isTrue);
    TiledStrokePictureCache.beginLayoutResizeSession();
    TiledStrokePictureCache.endLayoutResizeSession();
    expect(
      TiledStrokePictureCache.viewportMoving,
      isTrue,
      reason: 'docked sidebar must keep temporal raster LOD after resize ends',
    );

    TiledStrokePictureCache.popLayoutOcclusion();
    expect(TiledStrokePictureCache.viewportMoving, isFalse);
    await tester.pump(TiledStrokePictureCache.viewportSettleDelay);

    page.dispose();
  });

  test('sidebar preview raster composes baked tile LOD', () async {
    final page = EditorPage();
    final strokes = _spreadStrokes();
    for (final stroke in strokes) {
      page.insertStroke(stroke);
    }
    _prewarm(page);

    final cache = TiledStrokePictureCache();
    const previewScale = 0.35;
    _paintUntilRasterLod(
      cache,
      page,
      strokes: strokes,
      currentScale: previewScale,
    );
    final image = await cache.bakeSidebarPreviewRaster(
      pageSize: page.size,
      strokes: strokes,
      page: page,
      primaryColor: Colors.blue,
      pageIndex: 0,
      totalPages: 1,
      defaultTextStyle: const TextStyle(),
      previewScale: previewScale,
      devicePixelRatio: 1,
    );
    expect(image, isNotNull);
    expect(image!.width, greaterThan(32));
    expect(image.height, greaterThan(32));
    image.dispose();
    page.dispose();
  });

  testWidgets('preview paints do not steal the editor zoom LOD', (
    tester,
  ) async {
    final page = EditorPage();
    final strokes = _spreadStrokes();
    for (final stroke in strokes) {
      page.insertStroke(stroke);
    }
    _prewarm(page);

    final editorCache = page.strokePictureCache;
    _paintUntilRasterLod(editorCache, page, strokes: strokes, currentScale: 1);
    TiledStrokePictureCache.setViewportScale(3);
    await tester.pump(TiledStrokePictureCache.viewportSettleDelay);
    expect(TiledStrokePictureCache.zoomLodSettled, isTrue);

    final previewCache = TiledStrokePictureCache();
    _paintCache(
      previewCache,
      page,
      strokes: strokes,
      maxNewTilesPerPaint: 32,
      currentScale: 0.4,
      followLiveViewportScale: false,
    );
    expect(TiledStrokePictureCache.zoomLodSettled, isTrue);
    expect(previewCache.debugRasterCount, greaterThan(0));
    expect(
      previewCache.debugAnyRasterScale,
      closeTo(TiledStrokePictureCache.rasterLodScale(0.4), 0.01),
    );
    expect(
      editorCache.debugAnyRasterScale,
      closeTo(1, 0.01),
      reason: 'preview cache must not rebake the editor page cache',
    );

    previewCache.dispose();
    page.dispose();
  });

  testWidgets('off-origin tile rasters keep ink, not an empty origin crop', (
    tester,
  ) async {
    final page = EditorPage();
    final stroke = testPolylineStroke(
      toolId: ToolId.ballpointPen,
      y: 80,
      x0: 600,
      x1: 780,
    );
    page.insertStroke(stroke);
    _prewarm(page);

    final cache = page.strokePictureCache;
    _paintCache(
      cache,
      page,
      strokes: [stroke],
      maxNewTilesPerPaint: 32,
      currentScale: 1,
    );
    expect(cache.debugRasterCount, greaterThan(0));
    final raster = cache.debugFirstRaster;
    expect(raster, isNotNull);
    expect(raster!.width, greaterThan(16));
    expect(raster.height, greaterThan(16));
    expect(
      raster.width,
      lessThanOrEqualTo(
        TiledStrokePictureCache.maxRasterEdgePxForScale(1, fineInk: true),
      ),
      reason: 'raster is the 512px tile, not the full page',
    );

    page.dispose();
  });

  testWidgets('eraser invalidate during bake does not stall that page LOD', (
    tester,
  ) async {
    final page = EditorPage();
    final strokes = _spreadStrokes();
    for (final stroke in strokes) {
      page.insertStroke(stroke);
    }
    _prewarm(page);

    final cache = page.strokePictureCache;
    _paintUntilRasterLod(cache, page, strokes: strokes, currentScale: 1);

    TiledStrokePictureCache.debugForceSyncRaster = false;
    TiledStrokePictureCache.setViewportScale(3);
    await tester.pump(TiledStrokePictureCache.viewportSettleDelay);
    _paintCache(
      cache,
      page,
      strokes: strokes,
      maxNewTilesPerPaint: 32,
      currentScale: 1,
    );
    await tester.pump(Duration.zero);

    cache.invalidateRect(
      const Rect.fromLTWH(0, 0, 400, 400),
      eagerRefill: true,
    );
    expect(cache.debugBakingKeyCount, 0);

    await _pumpUntilAsyncRasterLod(
      tester,
      cache,
      page,
      strokes: strokes,
      currentScale: 1,
    );
    expect(cache.debugRasterCount, greaterThan(0));
    expect(cache.debugBakingKeyCount, 0);

    page.dispose();
  });

  testWidgets('eraser on one page does not drop raster LOD on another', (
    tester,
  ) async {
    final pageA = EditorPage();
    final pageB = EditorPage();
    final strokesA = _spreadStrokes();
    final strokesB = _spreadStrokes();
    for (final stroke in strokesA) {
      pageA.insertStroke(stroke);
    }
    for (final stroke in strokesB) {
      pageB.insertStroke(stroke);
    }
    _prewarm(pageA);
    _prewarm(pageB);

    final cacheA = pageA.strokePictureCache;
    final cacheB = pageB.strokePictureCache;
    _paintUntilRasterLod(cacheA, pageA, strokes: strokesA, currentScale: 1);
    _paintUntilRasterLod(cacheB, pageB, strokes: strokesB, currentScale: 1);

    TiledStrokePictureCache.debugForceSyncRaster = false;
    cacheA.invalidateAll(eagerRefill: true);
    await _pumpUntilAsyncRasterLod(
      tester,
      cacheA,
      pageA,
      strokes: strokesA,
      currentScale: 1,
    );

    _paintCache(
      cacheB,
      pageB,
      strokes: strokesB,
      maxNewTilesPerPaint: 32,
      currentScale: 1,
    );
    expect(
      cacheB.debugRasterCount,
      greaterThan(0),
      reason: 'unrelated pages must keep sampling rasters after an erase',
    );
    expect(cacheA.debugRasterCount, greaterThan(0));
    expect(cacheA.debugBakingKeyCount, 0);
    expect(cacheB.debugBakingKeyCount, 0);

    pageA.dispose();
    pageB.dispose();
  });
}
