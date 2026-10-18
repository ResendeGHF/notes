// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later

// Repro: an imported Samsung-notes style page (explicit local grid pattern,
// page units scaled to 1440x2036) must keep its background pattern visible on
// every settled frame — on open, during zoom/pan and after gestures settle.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
import 'package:saber/components/canvas/page_raster_cache.dart';
import 'package:saber/data/editor/canvas_background_pattern.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';

class _Harness {
  _Harness()
      : manager = PageRasterCacheManager(),
        coreInfo = EditorCoreInfo(
          filePath: '/tmp/imported-bg-pattern',
          readOnly: false,
        ) {
    page.backgroundPattern = CanvasBackgroundPattern.grid;
    page.hasLocalPattern = true;
    page.backgroundColor = const Color(0xFFFFFFFF);
    page.lineHeight = 46; // 32 * (1440 / 1000), like the importer
    page.lineThickness = 1.44;
    page.hasLocalLineHeight = true;
    page.hasLocalLineThickness = true;
    coreInfo.pages.add(page);
  }

  final PageRasterCacheManager manager;
  final EditorCoreInfo coreInfo;
  final EditorPage page = EditorPage(width: 1440, height: 2036);
  final GlobalKey boundaryKey = GlobalKey();
  double scale = 1.0;

  Widget build() => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 800,
          height: 1000,
          child: FittedBox(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: page.size.width,
                height: page.size.height,
                child: InnerCanvas(
                  pageIndex: 0,
                  redrawPageListenable: page,
                  width: page.size.width,
                  height: page.size.height,
                  coreInfo: coreInfo,
                  currentStroke: null,
                  currentStrokeDetectedShape: null,
                  currentSelection: null,
                  currentToolIsSelect: false,
                  currentScale: scale,
                  pageRasterCache: manager,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  void dispose() {
    manager.dispose();
    page.dispose();
  }
}

Future<int> _nonWhitePixels(
  WidgetTester tester,
  GlobalKey boundaryKey, {
  double pixelRatio = 0.25,
}) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final count = await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (data == null) return -1;
    return _countNonWhite(data);
  });
  return count!;
}

int _countNonWhite(ByteData data) {
  var count = 0;
  for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
    final r = data.getUint8(i);
    final g = data.getUint8(i + 1);
    final b = data.getUint8(i + 2);
    if (r < 250 || g < 250 || b < 250) count++;
  }
  return count;
}

/// Phone-like viewport: the page (1440 page units) is shrunk into a 400px box
/// and the captured frame is at a real-device pixel ratio, so the raster blit
/// is minified ~2.6x — the regime where `FilterQuality.low` eats thin lines.
class _PhoneHarness {
  _PhoneHarness()
      : manager = PageRasterCacheManager(),
        coreInfo = EditorCoreInfo(
          filePath: '/tmp/imported-bg-pattern-phone',
          readOnly: false,
        ) {
    page.backgroundPattern = CanvasBackgroundPattern.grid;
    page.hasLocalPattern = true;
    page.backgroundColor = const Color(0xFFFFFFFF);
    page.lineHeight = 46;
    page.lineThickness = 1.44;
    page.hasLocalLineHeight = true;
    page.hasLocalLineThickness = true;
    coreInfo.pages.add(page);
  }

  static const Size viewport = Size(400, 565.6);
  static const double captureRatio = 2.75;

  final PageRasterCacheManager manager;
  final EditorCoreInfo coreInfo;
  final EditorPage page = EditorPage(width: 1440, height: 2036);
  final GlobalKey boundaryKey = GlobalKey();
  final GlobalKey viewportKey = GlobalKey();
  double scale = 1.0;
  double panY = 0;

  Widget build() => MaterialApp(
    home: Scaffold(
      body: Center(
        child: RepaintBoundary(
          key: viewportKey,
          child: ClipRect(
            child: SizedBox(
              width: viewport.width,
              height: viewport.height,
              child: Transform.translate(
                offset: Offset(0, -panY),
                child: FittedBox(
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: SizedBox(
                      width: page.size.width,
                      height: page.size.height,
                      child: InnerCanvas(
                        pageIndex: 0,
                        redrawPageListenable: page,
                        width: page.size.width,
                        height: page.size.height,
                        coreInfo: coreInfo,
                        currentStroke: null,
                        currentStrokeDetectedShape: null,
                        currentSelection: null,
                        currentToolIsSelect: false,
                        currentScale: scale,
                        pageRasterCache: manager,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  void dispose() {
    manager.dispose();
    page.dispose();
  }
}

Future<String> _rasterStats(WidgetTester tester, PageCacheEntry? entry) async {
  if (entry == null) return 'no raster';
  final stats = await tester.runAsync(() async {
    final data = await entry.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (data == null) return 'null bytes';
    return '${entry.image.width}x${entry.image.height} res=${entry.res} '
        'nonWhite=${_countNonWhite(data)}';
  });
  return stats!;
}

void main() {
  setUp(() {
    PageRasterCacheManager.debugResetViewportLod();
    PageRasterCacheManager.debugForceSyncRaster = false;
  });

  tearDown(() {
    PageRasterCacheManager.debugForceSyncRaster = false;
    PageRasterCacheManager.debugResetViewportLod();
  });

  testWidgets('sync bakes: imported page keeps its grid across open/zoom/settle', (
    tester,
  ) async {
    PageRasterCacheManager.debugForceSyncRaster = true;
    final h = _Harness();

    Future<void> settle() async {
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    // --- Open ---
    await tester.pumpWidget(h.build());
    await settle();
    final opened = await _nonWhitePixels(tester, h.boundaryKey);
    debugPrint(
      'sync open: nonWhite=$opened bgCaches=${h.manager.debugBgCacheCount} '
      'raster=${await _rasterStats(tester, h.manager.debugBgEntry(0))}',
    );

    // --- Zoom gesture frames ---
    final zoomCounts = <int>[];
    for (final s in [1.1, 1.2, 1.3, 1.5, 1.8]) {
      PageRasterCacheManager.notifyViewportMotion(scale: s);
      h.scale = s;
      await tester.pumpWidget(h.build());
      await tester.pump(const Duration(milliseconds: 16));
      zoomCounts.add(await _nonWhitePixels(tester, h.boundaryKey));
    }
    debugPrint('sync zoom frames: $zoomCounts');

    // --- Settle after zoom ---
    PageRasterCacheManager.updateViewportMoving(false);
    await settle();
    final settled = await _nonWhitePixels(tester, h.boundaryKey);
    debugPrint(
      'sync settled: nonWhite=$settled bgCaches=${h.manager.debugBgCacheCount} '
      'raster=${await _rasterStats(tester, h.manager.debugBgEntry(0))}',
    );

    expect(opened, greaterThan(100), reason: 'pattern visible on open');
    for (final c in zoomCounts) {
      expect(c, greaterThan(100), reason: 'pattern visible during zoom');
    }
    expect(settled, greaterThan(100), reason: 'pattern visible after zoom');

    h.dispose();
  });

  testWidgets('async engine: imported page keeps its grid across open/zoom/settle', (
    tester,
  ) async {
    final h = _Harness();

    Future<void> pumpReal([
      Duration d = const Duration(milliseconds: 25),
    ]) async {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(d));
      await tester.pump();
    }

    Future<void> settle() async {
      for (var i = 0; i < 60; i++) {
        await pumpReal();
      }
    }

    // --- Open ---
    await tester.pumpWidget(h.build());
    final openCounts = <int>[];
    for (var i = 0; i < 40; i++) {
      await pumpReal();
      if (i % 5 == 4) openCounts.add(await _nonWhitePixels(tester, h.boundaryKey));
    }
    debugPrint(
      'async open frames: $openCounts bgCaches=${h.manager.debugBgCacheCount} '
      'pending=${h.manager.debugHasPendingBg}',
    );
    final opened = await _nonWhitePixels(tester, h.boundaryKey);
    debugPrint(
      'async open: nonWhite=$opened '
      'raster=${await _rasterStats(tester, h.manager.debugBgEntry(0))}',
    );

    // --- Zoom gesture frames ---
    final zoomCounts = <int>[];
    for (final s in [1.1, 1.2, 1.3, 1.5, 1.8]) {
      PageRasterCacheManager.notifyViewportMotion(scale: s);
      h.scale = s;
      await tester.pumpWidget(h.build());
      await pumpReal(const Duration(milliseconds: 16));
      zoomCounts.add(await _nonWhitePixels(tester, h.boundaryKey));
    }
    debugPrint('async zoom frames: $zoomCounts');

    // --- Settle after zoom ---
    PageRasterCacheManager.updateViewportMoving(false);
    await settle();
    final settled = await _nonWhitePixels(tester, h.boundaryKey);
    debugPrint(
      'async settled: nonWhite=$settled bgCaches=${h.manager.debugBgCacheCount} '
      'raster=${await _rasterStats(tester, h.manager.debugBgEntry(0))}',
    );

    expect(opened, greaterThan(100), reason: 'pattern visible on open');
    for (final c in zoomCounts) {
      expect(c, greaterThan(100), reason: 'pattern visible during zoom');
    }
    expect(settled, greaterThan(100), reason: 'pattern visible after zoom');

    // Drain the manager's settle/queue timers so the test framework does not
    // report "A Timer is still pending" at teardown.
    PageRasterCacheManager.debugResetViewportLod();
    PageRasterCacheManager.updateViewportMoving(false);
    await tester.pump(const Duration(seconds: 2));
    PageRasterCacheManager.debugResetViewportLod();

    h.dispose();
  });

  testWidgets('phone viewport: panned minified raster keeps the pattern', (
    tester,
  ) async {
    final h = _PhoneHarness();

    Future<void> pumpReal([
      Duration d = const Duration(milliseconds: 25),
    ]) async {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(d));
      await tester.pump();
    }

    await tester.pumpWidget(h.build());
    for (var i = 0; i < 60; i++) {
      await pumpReal();
    }
    expect(h.manager.debugBgEntry(0), isNotNull, reason: 'raster was baked');

    // Settled: the raster is not "sharp" for the raw zoom target, so the
    // painter falls back to the crisp vector pattern — the reference density.
    final settled = await _nonWhitePixels(
      tester,
      h.viewportKey,
      pixelRatio: _PhoneHarness.captureRatio,
    );
    debugPrint('phone settled (vector): nonWhite=$settled');

    // Pan: the painter blits the ~2.6x-minified raster, sweeping subpixel
    // sampling phases. With FilterQuality.low the thin pattern lines alias
    // away on most phases — the "pattern blinks while panning" report.
    final panCounts = <int>[];
    for (final dy in [0.0, 0.37, 0.73, 1.11, 1.51, 1.89, 2.27, 2.71]) {
      PageRasterCacheManager.notifyViewportMotion(scale: h.scale);
      h.panY = dy;
      await tester.pumpWidget(h.build());
      await tester.pump(const Duration(milliseconds: 16));
      panCounts.add(
        await _nonWhitePixels(
          tester,
          h.viewportKey,
          pixelRatio: _PhoneHarness.captureRatio,
        ),
      );
    }
    debugPrint('phone pan frames: $panCounts');

    // The minified blit must not wipe the pattern: every pan phase keeps at
    // least half of the settled (vector) pattern pixels.
    for (final count in panCounts) {
      expect(
        count,
        greaterThan((settled * 0.5).round()),
        reason: 'pattern visible while panning (blit quality)',
      );
    }

    // Let the manager's timers drain before teardown.
    PageRasterCacheManager.debugResetViewportLod();
    PageRasterCacheManager.updateViewportMoving(false);
    await tester.pump(const Duration(seconds: 2));
    PageRasterCacheManager.debugResetViewportLod();

    h.dispose();
  });
}
