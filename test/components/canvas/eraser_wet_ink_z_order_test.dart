// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

// Eraser children must keep the parent's z-position in real time. The
// wet-ink overlay paints above every tile, so only a topmost pen-up append
// may ride it; erase replacements (fragments / carved copies inserted at
// their parent's slot) must render from the tiles, or they flick above
// newer strokes until the tiles catch up.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
import 'package:saber/components/canvas/page_raster_cache.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/eraser.dart';

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
    Eraser.isDragging = false;
    TiledStrokePictureCache.debugResetViewportLod();
    TiledStrokePictureCache.viewportMoving = false;
    TiledStrokePictureCache.debugSetViewportSlowMotion(false);
    TiledStrokePictureCache.debugForceSyncRaster = false;
  });

  Future<InnerCanvasState> pumpCanvas(
    WidgetTester tester,
    EditorCoreInfo coreInfo,
    EditorPage page,
    PageRasterCacheManager manager,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
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
              currentStroke: null,
              currentStrokeDetectedShape: null,
              currentSelection: null,
              currentToolIsSelect: false,
              currentScale: 1.0,
              pageRasterCache: manager,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return tester.state<InnerCanvasState>(find.byType(InnerCanvas));
  }

  testWidgets('area-erase replacement never rides the wet-ink overlay',
      (tester) async {
    final manager = PageRasterCacheManager();
    final coreInfo = EditorCoreInfo(
      filePath: '/tmp/eraser-wet-ink',
      readOnly: false,
    );
    final page = EditorPage();
    for (var i = 0; i < 5; i++) {
      page.strokes.add(testPolylineStroke(toolId: ToolId.ballpointPen));
    }
    coreInfo.pages.add(page);

    final state = await pumpCanvas(tester, coreInfo, page, manager);

    // Simulate _applyEraserResultToPage mid-drag: the bottom stroke is
    // replaced in its own slot by two fragments (count grows by one, z must
    // stay put, so the fragments must not flash above the 4 newer strokes).
    Eraser.isDragging = true;
    final bottom = page.strokes.first;
    final startFrag = testPolylineStroke(
      toolId: ToolId.ballpointPen,
      x0: 0,
      x1: 90,
    );
    final endFrag = testPolylineStroke(
      toolId: ToolId.ballpointPen,
      x0: 110,
      x1: 200,
    );
    page.strokes
      ..remove(bottom)
      ..insertAll(0, [startFrag, endFrag]);
    page.redrawStrokes();

    // The delta sync runs synchronously on the page notification: the
    // replacements must not be pending above the newer strokes.
    expect(
      state.debugPendingInkStrokes,
      isEmpty,
      reason: 'erase children must render from tiles, not above them',
    );

    await tester.pump();
    // Let chained tile refills and raster settle timers drain.
    for (var i = 0; i < 35; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(state.debugPendingInkStrokes, isEmpty);
    manager.dispose();
    page.dispose();
  });

  testWidgets('topmost pen-up append still uses the wet cover',
      (tester) async {
    final manager = PageRasterCacheManager();
    final coreInfo = EditorCoreInfo(
      filePath: '/tmp/penup-wet-ink',
      readOnly: false,
    );
    final page = EditorPage();
    for (var i = 0; i < 3; i++) {
      page.strokes.add(testPolylineStroke(toolId: ToolId.ballpointPen));
    }
    coreInfo.pages.add(page);

    final state = await pumpCanvas(tester, coreInfo, page, manager);

    // Pen-up on the top of the draw order: the wet cover is z-correct here
    // and keeps the fresh stroke full quality while its tiles record.
    final fresh = testPolylineStroke(
      toolId: ToolId.ballpointPen,
      y: 300,
    );
    page.strokes.add(fresh);
    page.redrawStrokes();

    expect(state.debugPendingInkStrokes, [fresh]);

    await tester.pump();
    // Let chained tile refills and raster settle timers drain.
    for (var i = 0; i < 35; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    manager.dispose();
    page.dispose();
  });

  testWidgets('append beneath existing ink is not wet-covered', (tester) async {
    final manager = PageRasterCacheManager();
    final coreInfo = EditorCoreInfo(
      filePath: '/tmp/lower-layer-wet-ink',
      readOnly: false,
    );
    final page = EditorPage();
    for (var i = 0; i < 3; i++) {
      page.strokes.add(testPolylineStroke(toolId: ToolId.ballpointPen));
    }
    coreInfo.pages.add(page);

    final state = await pumpCanvas(tester, coreInfo, page, manager);

    // A stroke landing beneath existing ink (lower layer) must not paint
    // above it: the complex eager refill shows it in its real slot.
    final lower = testPolylineStroke(
      toolId: ToolId.ballpointPen,
      y: 300,
    );
    page.strokes.insert(0, lower);
    page.redrawStrokes();

    expect(state.debugPendingInkStrokes, isEmpty);

    await tester.pump();
    // Let chained tile refills and raster settle timers drain.
    for (var i = 0; i < 35; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    manager.dispose();
    page.dispose();
  });
}
