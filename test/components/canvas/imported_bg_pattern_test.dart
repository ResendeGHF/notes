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
import 'package:saber/data/prefs.dart';

class _Harness {
  _Harness({ThemeData? theme, this.useRasterCache = true})
      : theme = theme ?? ThemeData(),
        manager = PageRasterCacheManager(),
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
  final ThemeData theme;
  final bool useRasterCache;
  double scale = 1.0;

  Widget build() => MaterialApp(
    theme: theme,
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
                  // The editor always passes the page's line color through
                  // (see Editor's Canvas); keep the harness faithful.
                  lineColor: page.lineColor,
                  pageRasterCache: useRasterCache ? manager : null,
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

/// Pattern "ink" metrics used to compare the raster blit against the vector
/// fallback: how much ink the pattern puts down and in which hue.
class _InkStats {
  const _InkStats(this.count, this.inkR, this.inkG, this.inkB);

  final int count;
  final double inkR, inkG, inkB;

  double get total => inkR + inkG + inkB;

  /// Normalized per-channel ink, i.e. the pattern's perceived hue.
  (double, double, double) get color => total <= 0
      ? (0.0, 0.0, 0.0)
      : (inkR / total, inkG / total, inkB / total);

  @override
  String toString() =>
      'count=$count ink=${total.toStringAsFixed(0)} color=('
      '${color.$1.toStringAsFixed(3)}, ${color.$2.toStringAsFixed(3)}, '
      '${color.$3.toStringAsFixed(3)})';
}

Future<_InkStats> _inkStats(
  WidgetTester tester,
  GlobalKey boundaryKey, {
  double pixelRatio = 0.5,
}) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final stats = await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (data == null) return const _InkStats(0, 0, 0, 0);
    return _inkStatsFromBytes(data);
  });
  return stats!;
}

Future<_InkStats> _imageInkStats(WidgetTester tester, ui.Image image) async {
  final stats = await tester.runAsync(() async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return const _InkStats(0, 0, 0, 0);
    return _inkStatsFromBytes(data);
  });
  return stats!;
}

_InkStats _inkStatsFromBytes(ByteData data) {
  var count = 0;
  double inkR = 0, inkG = 0, inkB = 0;
  for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
    // The page background is near-white (0xFFFCFCFC); ignore that baseline
    // and accumulate the pattern's per-channel darkening.
    final dr = 255 - data.getUint8(i);
    final dg = 255 - data.getUint8(i + 1);
    final db = 255 - data.getUint8(i + 2);
    if (dr + dg + db <= 12) continue;
    count++;
    inkR += dr;
    inkG += dg;
    inkB += db;
  }
  return _InkStats(count, inkR, inkG, inkB);
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
                        lineColor: page.lineColor,
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

  testWidgets('raster bake and vector path share the default line color', (
    tester,
  ) async {
    // A page that keeps the default line color (0xFF9E9E9E) must paint the
    // pattern in that same gray on both paths. If the raster bake resolves it
    // to a theme color (colorScheme.primary) instead, then in a dark theme the
    // light primary at the pattern's 20% alpha all but vanishes on the white
    // page: the pattern blinks/disappears as the editor switches between the
    // baked blit and the crisp vector fallback on move/zoom, while the strokes
    // stay visible.
    final previousAutoInvert = stows.editorAutoInvert.value;
    stows.editorAutoInvert.value = false; // keep the page white in dark mode
    PageRasterCacheManager.debugForceSyncRaster = true;
    final darkTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6750A4),
        brightness: Brightness.dark,
      ),
    );

    // --- Vector path: the settled fallback the user sees. ---
    final vector = _Harness(theme: darkTheme, useRasterCache: false);
    await tester.pumpWidget(vector.build());
    await tester.pump(const Duration(milliseconds: 16));
    final vectorStats = await _inkStats(tester, vector.boundaryKey);
    debugPrint('default line vector: $vectorStats');

    // --- Raster path: the bitmap the painter blits while moving/sharp. ---
    final raster = _Harness(theme: darkTheme, useRasterCache: true);
    await tester.pumpWidget(raster.build());
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final entry = raster.manager.debugBgEntry(0);
    expect(entry, isNotNull, reason: 'raster was baked');
    final rasterStats = await _imageInkStats(tester, entry!.image);
    debugPrint('default line raster: $rasterStats');

    expect(vectorStats.count, greaterThan(1000), reason: 'vector visible');
    expect(rasterStats.count, greaterThan(1000), reason: 'raster visible');

    // Both paths must paint the pattern with the same color...
    final (vr, vg, vb) = vectorStats.color;
    final (rr, rg, rb) = rasterStats.color;
    expect((rr - vr).abs(), lessThan(0.05), reason: 'same red channel');
    expect((rg - vg).abs(), lessThan(0.05), reason: 'same green channel');
    expect((rb - vb).abs(), lessThan(0.05), reason: 'same blue channel');

    // ...and that color must be the neutral gray default, not a theme tint.
    for (final channel in [vr, vg, vb, rr, rg, rb]) {
      expect(
        channel,
        inInclusiveRange(0.30, 0.37),
        reason: 'default pattern line color is the neutral gray',
      );
    }

    // Let the manager's timers drain before teardown.
    PageRasterCacheManager.debugResetViewportLod();
    PageRasterCacheManager.updateViewportMoving(false);
    await tester.pump(const Duration(seconds: 2));
    PageRasterCacheManager.debugResetViewportLod();

    vector.dispose();
    raster.dispose();
    stows.editorAutoInvert.value = previousAutoInvert;
  });
}
