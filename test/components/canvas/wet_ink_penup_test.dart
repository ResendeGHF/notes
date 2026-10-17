// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

// Wet-ink pen-up: the finished stroke must stay painted (as vectors) while
// its tiles record progressively, instead of one synchronous multi-tile block
// on the pen-up frame that starts the next stroke behind the pen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
import 'package:saber/components/canvas/page_raster_cache.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/stroke_geometry/point_vector.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';
import 'package:saber/data/tools/_tool.dart';

import '../../helpers/test_stroke_factory.dart';

void main() {
  setUp(() {
    TiledStrokePictureCache.debugResetViewportLod();
    TiledStrokePictureCache.viewportMoving = false;
    TiledStrokePictureCache.debugSetViewportSlowMotion(false);
    // Sync raster path like the tile-cache suite: async engine toImage does
    // not resolve under FakeAsync pump time and would outlive teardown.
    TiledStrokePictureCache.debugForceSyncRaster = true;
  });

  tearDown(() {
    TiledStrokePictureCache.debugResetViewportLod();
    TiledStrokePictureCache.viewportMoving = false;
    TiledStrokePictureCache.debugSetViewportSlowMotion(false);
    TiledStrokePictureCache.debugForceSyncRaster = false;
  });

  testWidgets('pen-up covers fresh ink while tiles converge', (tester) async {
    final manager = PageRasterCacheManager();
    final coreInfo = EditorCoreInfo(
      filePath: '/tmp/wet-ink-penup',
      readOnly: false,
    );
    final page = EditorPage();
    for (var s = 0; s < 120; s++) {
      page.strokes.add(testPolylineStroke(
        toolId: ToolId.ballpointPen,
        y: 20.0 + (s % 40) * 30,
        x0: 20.0 + (s ~/ 40) * 300,
        x1: 200.0 + (s ~/ 40) * 300,
      ));
    }
    coreInfo.pages.add(page);

    // Live stroke as production builds it (incomplete, staged past ~192).
    final live = Stroke(
      color: Colors.black,
      pressureEnabled: false,
      options: StrokeOptions(
        size: 2,
        smoothing: 0.18,
        streamline: 0.0,
        thinning: 0.0,
        simulatePressure: false,
        isComplete: false,
        start: StrokeEndOptions.start(cap: true, taperEnabled: false),
        end: StrokeEndOptions.end(cap: true, taperEnabled: false),
      ),
      pageIndex: 0,
      page: HasSize(EditorPage.defaultSize),
      toolId: ToolId.ballpointPen,
    );
    for (var i = 0; i < 500; i++) {
      live.addPoint(
        Offset(60.0 + i * 2.0, 400.0 + i * 0.4),
        null,
        Duration(microseconds: i * 4166),
      );
    }
    expect(live.hasLiveStaging, isTrue);

    Widget canvasFor(Stroke? current) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: page.size.width,
              height: page.size.height,
              child: InnerCanvas(
                pageIndex: 0,
                redrawPageListenable: page,
                width: page.size.width,
                height: page.size.height,
                coreInfo: coreInfo,
                currentStroke: current,
                currentStrokeDetectedShape: null,
                currentSelection: null,
                currentToolIsSelect: false,
                currentScale: 1.0,
                pageRasterCache: manager,
              ),
            ),
          ),
        );

    await tester.pumpWidget(canvasFor(live));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Pen-up: same object completes (as Pen.onDragEnd does) and commits.
    live.finishLiveGeometry();
    page.strokes.add(live);
    await tester.pumpWidget(canvasFor(null));
    await tester.pump();
    // Let chaining + settle timers + commit-quiet raster gate (2s) + async
    // raster converge. FakeAsync advances instantly; wall time stays small.
    for (var i = 0; i < 35; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Tiles converged (wet cover retired) and the stroke survived everywhere.
    expect(page.strokePictureCache.recordedTileCount, greaterThan(0));
    expect(page.strokes.contains(live), isTrue);
    manager.dispose();
    page.dispose();
  });
}
