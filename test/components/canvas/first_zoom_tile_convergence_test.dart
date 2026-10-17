// Regression: a budget-starved tile refill must not freeze behind the
// whole-page ink bitmap.
//
// Pen-up refills dirty tiles under a tight time budget; a skip is bridged by
// the cheap spine fallback. Once the page ink bitmap becomes current it used
// to own every settled frame, so `TiledStrokePictureCache.paint` was never
// called again and the missing tile stayed at fallback quality (decimated
// centerline, pen width, round caps) until a later zoom flipped back to
// vectors — seen as cap/thickness artifacts during the first zoom only.
// Settled frames must now keep the exact tile path until tiles catch up.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
import 'package:saber/components/canvas/page_raster_cache.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/stroke_geometry/point_vector.dart';
import 'package:saber/data/stroke_geometry/stroke_options.dart';
import 'package:saber/data/tools/_tool.dart';

Stroke _makeStroke() {
  final s = Stroke(
    color: Colors.black,
    pressureEnabled: true,
    options: StrokeOptions(
      size: 8,
      smoothing: 0.3,
      simulatePressure: false,
      isComplete: true,
      start: StrokeEndOptions.start(cap: true, taperEnabled: false),
      end: StrokeEndOptions.end(cap: true, taperEnabled: false),
    ),
    pageIndex: 0,
    page: HasSize(EditorPage.defaultSize),
    toolId: ToolId.ballpointPen,
  );
  for (var i = 0; i < 220; i++) {
    final p = i < 70 ? 0.12 : (i < 150 ? 0.5 : 1.0);
    s.points.add(PointVector(20.0 + i * 3.0, 100.0, p));
  }
  s.markPolygonNeedsUpdating();
  return s;
}

void main() {
  testWidgets('first zoom finds converged tiles, not frozen fallback', (
    tester,
  ) async {
    TiledStrokePictureCache.debugResetViewportLod();
    TiledStrokePictureCache.viewportMoving = false;
    TiledStrokePictureCache.debugSetViewportSlowMotion(false);
    TiledStrokePictureCache.debugForceSyncRaster = false;

    final manager = PageRasterCacheManager();
    final coreInfo = EditorCoreInfo(
      filePath: '/tmp/first-zoom-convergence',
      readOnly: false,
    );
    final page = EditorPage();
    page.insertStroke(_makeStroke());
    coreInfo.pages.add(page);

    final boundaryKey = GlobalKey();

    Widget canvasFor(double scale) => MaterialApp(
      home: Scaffold(
        body: RepaintBoundary(
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
    );

    Future<void> settle() async {
      for (var i = 0; i < 35; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    // Settle at 1.0. The stroke crosses exactly two 512px tiles; even if the
    // first paint's 8ms budget starves the second one, the tile layer must
    // recover on its own while the ink bitmap owns the frames.
    await tester.pumpWidget(canvasFor(1.0));
    await settle();
    final cache = page.strokePictureCache;
    expect(
      cache.visibleTilesCaughtUp,
      isTrue,
      reason: 'visible tiles must converge while the ink bitmap is current',
    );
    expect(cache.recordedTileCount, 2);
    expect(
      cache.debugFallbackPaintedTileCount,
      0,
      reason: 'the last settled paint must not fall back to spine vectors',
    );

    // First zoom-in: moving frames blit the bitmap/rasters, then the settle
    // must keep the converged tiles — no fallback spine may resurface.
    TiledStrokePictureCache.viewportMoving = true;
    for (final s in [1.2, 1.4, 1.6, 1.8, 2.0, 2.2]) {
      await tester.pumpWidget(canvasFor(s));
      await tester.pump(const Duration(milliseconds: 16));
      expect(cache.recordedTileCount, 2);
    }
    TiledStrokePictureCache.viewportMoving = false;
    await settle();
    expect(cache.visibleTilesCaughtUp, isTrue);
    expect(cache.recordedTileCount, 2);
    expect(cache.debugFallbackPaintedTileCount, 0);

    TiledStrokePictureCache.debugResetViewportLod();
    TiledStrokePictureCache.viewportMoving = false;
    TiledStrokePictureCache.debugForceSyncRaster = false;
    manager.dispose();
    page.dispose();
  });
}
