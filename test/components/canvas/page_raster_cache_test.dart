// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/page_raster_cache.dart';
import 'package:saber/data/editor/canvas_background_pattern.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/_tool.dart';

import '../../helpers/test_stroke_factory.dart';

void main() {
  setUp(() {
    PageRasterCacheManager.debugResetViewportLod();
    PageRasterCacheManager.debugForceSyncRaster = true;
  });

  tearDown(() {
    PageRasterCacheManager.debugForceSyncRaster = false;
    PageRasterCacheManager.debugResetViewportLod();
  });

  test('clampedRes caps bitmap resolution at maxCachePx long edge', () {
    const pageSize = Size(800, 1200);
    final res = PageRasterCacheManager.clampedRes(4, pageSize);
    expect(res * 1200, lessThanOrEqualTo(PageRasterCacheManager.maxCachePx + 1));
    expect(res, closeTo(PageRasterCacheManager.maxCachePx / 1200, 0.001));
  });

  test('clampedRes scales with device pixel ratio', () {
    const pageSize = Size(200, 300);
    final withoutDpr = PageRasterCacheManager.clampedRes(
      2,
      pageSize,
      devicePixelRatio: 1,
    );
    final withDpr = PageRasterCacheManager.clampedRes(
      2,
      pageSize,
      devicePixelRatio: 2,
    );
    expect(withDpr, closeTo(withoutDpr * 2, 0.001));
  });

  test('higher-res ink job replaces queued lower-res job', () async {
    final manager = PageRasterCacheManager();
    final page = EditorPage();
    page.strokes.add(testPolylineStroke(toolId: ToolId.ballpointPen));
    PageRasterCacheManager.viewportMoving = false;
    PageRasterCacheManager.debugForceSyncRaster = false;

    final baseParams = PageRasterInkParams(
      invert: false,
      strokes: page.strokes,
      page: page,
      primaryColor: Colors.blue,
      pageIndex: 0,
      totalPages: 1,
      currentScale: 1,
      defaultTextStyle: const TextStyle(),
    );

    manager.inkForOrSchedule(
      pageIndex: 0,
      pageSize: page.size,
      scale: 1,
      devicePixelRatio: 1,
      params: baseParams,
    );
    manager.inkForOrSchedule(
      pageIndex: 0,
      pageSize: page.size,
      scale: 4,
      devicePixelRatio: 2,
      params: PageRasterInkParams(
        invert: false,
        strokes: page.strokes,
        page: page,
        primaryColor: Colors.blue,
        pageIndex: 0,
        totalPages: 1,
        currentScale: 4,
        defaultTextStyle: const TextStyle(),
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(manager.debugInkCacheCount, 1);
    manager.dispose();
  });

  test('prepareForSettledScale clears pending so zoom upgrade can schedule', () {
    final manager = PageRasterCacheManager();
    final page = EditorPage();
    page.strokes.add(testPolylineStroke(toolId: ToolId.ballpointPen));
    PageRasterCacheManager.viewportMoving = true;

    manager.inkForOrSchedule(
      pageIndex: 0,
      pageSize: page.size,
      scale: 1,
      devicePixelRatio: 1,
      params: PageRasterInkParams(
        invert: false,
        strokes: page.strokes,
        page: page,
        primaryColor: Colors.blue,
        pageIndex: 0,
        totalPages: 1,
        currentScale: 1,
        defaultTextStyle: const TextStyle(),
      ),
    );
    expect(manager.debugHasPendingInk, isFalse);

    manager.prepareForSettledScale(scale: 4, devicePixelRatio: 2);
    expect(manager.debugHasPendingInk, isFalse);

    manager.inkForOrSchedule(
      pageIndex: 0,
      pageSize: page.size,
      scale: 4,
      devicePixelRatio: 2,
      forceSchedule: true,
      params: PageRasterInkParams(
        invert: false,
        strokes: page.strokes,
        page: page,
        primaryColor: Colors.blue,
        pageIndex: 0,
        totalPages: 1,
        currentScale: 4,
        defaultTextStyle: const TextStyle(),
      ),
    );
    expect(manager.debugHasPendingInk, isTrue);
    manager.dispose();
  });

  test('forceSchedule schedules ink while viewportMoving', () {
    final manager = PageRasterCacheManager();
    final page = EditorPage();
    page.strokes.add(testPolylineStroke(toolId: ToolId.ballpointPen));
    PageRasterCacheManager.viewportMoving = true;

    manager.inkForOrSchedule(
      pageIndex: 0,
      pageSize: page.size,
      scale: 4,
      devicePixelRatio: 2,
      forceSchedule: true,
      params: PageRasterInkParams(
        invert: false,
        strokes: page.strokes,
        page: page,
        primaryColor: Colors.blue,
        pageIndex: 0,
        totalPages: 1,
        currentScale: 4,
        defaultTextStyle: const TextStyle(),
      ),
    );

    expect(manager.debugHasPendingInk, isTrue);
    manager.dispose();
  });

  test('viewportMoving does not schedule new ink raster jobs', () {
    final manager = PageRasterCacheManager();
    final page = EditorPage();
    page.strokes.add(testPolylineStroke(toolId: ToolId.ballpointPen));
    PageRasterCacheManager.viewportMoving = true;

    manager.inkForOrSchedule(
      pageIndex: 0,
      pageSize: page.size,
      scale: 1,
      params: PageRasterInkParams(
        invert: false,
        strokes: page.strokes,
        page: page,
        primaryColor: Colors.blue,
        pageIndex: 0,
        totalPages: 1,
        currentScale: 1,
        defaultTextStyle: const TextStyle(),
      ),
    );

    expect(manager.debugHasPendingInk, isFalse);
    manager.dispose();
  });

  test('invalidateInk keeps stale blit until rebake replaces it', () async {
    final manager = PageRasterCacheManager();
    final page = EditorPage();
    page.strokes.add(testPolylineStroke(toolId: ToolId.ballpointPen));
    PageRasterCacheManager.viewportMoving = false;

    manager.inkForOrSchedule(
      pageIndex: 0,
      pageSize: page.size,
      scale: 1,
      params: PageRasterInkParams(
        invert: false,
        strokes: page.strokes,
        page: page,
        primaryColor: Colors.blue,
        pageIndex: 0,
        totalPages: 1,
        currentScale: 1,
        defaultTextStyle: const TextStyle(),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(manager.debugInkCacheCount, 1);

    manager.invalidateInk(0);
    // Stale bitmap retained so drawing does not fall back to full vector paint.
    expect(manager.debugInkCacheCount, 1);

    manager.invalidateInk(0, discardStale: true);
    expect(manager.debugInkCacheCount, 0);
    manager.dispose();
  });

  test('maintainVisibleBand drops caches outside prefetch window', () async {
    final manager = PageRasterCacheManager();
    final coreInfo = EditorCoreInfo(
      filePath: '/tmp/test.sbn2',
      readOnly: false,
    );
    for (var i = 0; i < 3; i++) {
      final page = EditorPage();
      page.strokes.add(testPolylineStroke(toolId: ToolId.ballpointPen));
      coreInfo.pages.add(page);
    }

    manager.maintainVisibleBand(
      coreInfo: coreInfo,
      visibleStart: 1,
      visibleEnd: 1,
      scale: 1,
      invert: false,
      primaryColor: Colors.blue,
      secondaryColor: Colors.red,
      defaultTextStyle: const TextStyle(),
      defaultLineHeight: 32,
      defaultLineThickness: 1,
      defaultPattern: CanvasBackgroundPattern.lined,
      defaultBackgroundColor: Colors.white,
    );

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(manager.debugInkCacheCount, lessThanOrEqualTo(3));
    manager.dispose();
  });

  test('open path does not eagerly build HQ polygons', () {
    final stroke = testPolylineStroke(toolId: ToolId.ballpointPen);
    expect(stroke.hasCachedHighQualityPolygon, isFalse);
    stroke.lowQualityPath;
    expect(stroke.hasCachedHighQualityPolygon, isFalse);
  });

  List<Stroke> densePageStrokes() {
    // Diverse strokes (varying position/width) so the geometry warmup spans
    // several time slices and actually yields to the event loop.
    return [
      for (var i = 0; i < 80; i++)
        testPolylineStroke(
          toolId: ToolId.ballpointPen,
          y: 20.0 + i * 3,
          width: 4 + (i % 5) * 2,
        ),
    ];
  }

  PageRasterInkParams inkParamsFor(EditorPage page, List<Stroke> strokes) {
    return PageRasterInkParams(
      invert: false,
      strokes: strokes,
      page: page,
      primaryColor: Colors.blue,
      pageIndex: 0,
      totalPages: 1,
      currentScale: 1,
      defaultTextStyle: const TextStyle(),
    );
  }

  test('in-flight ink bake is preempted when viewport motion starts', () async {
    final manager = PageRasterCacheManager();
    final page = EditorPage();
    page.strokes.addAll(densePageStrokes());
    PageRasterCacheManager.viewportMoving = false;
    PageRasterCacheManager.debugForceSyncRaster = false;

    manager.inkForOrSchedule(
      pageIndex: 0,
      pageSize: page.size,
      scale: 1,
      devicePixelRatio: 1,
      params: inkParamsFor(page, page.strokes),
    );
    // The job starts synchronously and suspends at its first slice yield (or
    // at toImage); it cannot complete before we flip the flag below.
    expect(manager.debugBuildJobCalls, 1);

    // User grabs the canvas again while the bake is in flight.
    PageRasterCacheManager.updateViewportMoving(true);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    PageRasterCacheManager.updateViewportMoving(false);

    // The aborted bake must not land a cache entry...
    expect(manager.debugInkCacheCount, 0);
    expect(manager.debugHasPendingInk, isFalse);

    // ...and the settle flow still produces a raster afterwards.
    manager.prepareForSettledScale(scale: 1, devicePixelRatio: 1);
    manager.inkForOrSchedule(
      pageIndex: 0,
      pageSize: page.size,
      scale: 1,
      devicePixelRatio: 1,
      forceSchedule: true,
      params: inkParamsFor(page, page.strokes),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(manager.debugInkCacheCount, 1);
    expect(manager.debugHasPendingInk, isFalse);
    manager.dispose();
  });

  test('content invalidation preempts an in-flight bake', () async {
    final manager = PageRasterCacheManager();
    final page = EditorPage();
    page.strokes.addAll(densePageStrokes());
    PageRasterCacheManager.viewportMoving = false;
    PageRasterCacheManager.debugForceSyncRaster = false;

    manager.inkForOrSchedule(
      pageIndex: 0,
      pageSize: page.size,
      scale: 1,
      devicePixelRatio: 1,
      params: inkParamsFor(page, page.strokes),
    );
    // Stroke committed mid-bake: content epoch + generation + cache epoch all
    // move, so the in-flight job must abort instead of landing stale ink.
    manager.invalidateInk(0);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(manager.debugInkCacheCount, 0);
    expect(manager.debugHasPendingInk, isFalse);
    manager.dispose();
  });

  test('queued job with stale generation is dropped before warmup', () async {
    final manager = PageRasterCacheManager();
    final page0 = EditorPage();
    page0.strokes.add(testPolylineStroke(toolId: ToolId.ballpointPen));
    final page1 = EditorPage();
    page1.strokes.add(testPolylineStroke(toolId: ToolId.ballpointPen));
    PageRasterCacheManager.viewportMoving = false;
    PageRasterCacheManager.debugForceSyncRaster = false;

    // Job A starts immediately; job B stays queued behind it.
    manager.inkForOrSchedule(
      pageIndex: 0,
      pageSize: page0.size,
      scale: 1,
      devicePixelRatio: 1,
      params: inkParamsFor(page0, page0.strokes),
    );
    manager.inkForOrSchedule(
      pageIndex: 1,
      pageSize: page1.size,
      scale: 1,
      devicePixelRatio: 1,
      params: PageRasterInkParams(
        invert: false,
        strokes: page1.strokes,
        page: page1,
        primaryColor: Colors.blue,
        pageIndex: 1,
        totalPages: 2,
        currentScale: 1,
        defaultTextStyle: const TextStyle(),
      ),
    );
    // Invalidate page 1 while its job is still queued.
    manager.invalidateInk(1);
    await Future<void>.delayed(const Duration(milliseconds: 80));

    // Only job A ever reached the build; B was dropped by the pre-checks, so
    // no stale geometry was warmed for it and no entry landed.
    expect(manager.debugBuildJobCalls, 1);
    expect(manager.debugInkCacheCount, 0);
    expect(manager.debugHasPendingInk, isFalse);
    manager.dispose();
  });
}
