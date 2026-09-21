// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/_tool.dart';

import '../../helpers/test_stroke_factory.dart';

EditorCoreInfo _layeredNote() {
  final info = EditorCoreInfo(filePath: '/tmp/parity-note', readOnly: false);
  for (var p = 0; p < 6; p++) {
    final page = EditorPage();
    page.insertStroke(
      testPolylineStroke(toolId: ToolId.ballpointPen, y: 60.0 + p),
    );
    page.addLayer();
    page.activeLayerIndex = 1;
    page.insertStroke(
      testPolylineStroke(
        toolId: ToolId.fountainPen,
        y: 300.0 + p * 3,
        x0: 50,
        x1: 500,
        points: 60,
      ),
    );
    page.activeLayerIndex = 0;
    page.lineHeight = 32 + p;
    page.hasLocalLineHeight = true;
    info.pages.add(page);
  }
  return info;
}

void _expectSamePage(EditorPage a, EditorPage b) {
  expect(b.size, a.size);
  expect(b.hasLocalLineHeight, a.hasLocalLineHeight);
  expect(b.lineHeight, a.lineHeight);
  expect(b.layerCount, a.layerCount);
  expect(
    b.allStrokesInDrawOrder.length,
    a.allStrokesInDrawOrder.length,
  );
  final sa = a.allStrokesInDrawOrder.toList();
  final sb = b.allStrokesInDrawOrder.toList();
  for (var i = 0; i < sa.length; i++) {
    expect(sb[i].toolId, sa[i].toolId);
    expect(sb[i].points.length, sa[i].points.length);
    expect(sb[i].bounds, sa[i].bounds);
    expect(sb[i].color.value, sa[i].color.value);
  }
  expect(
    b.quill.controller.document.toPlainText(),
    a.quill.controller.document.toPlainText(),
  );
}

void main() {
  test('chunked hydrate matches sync hydrate', () async {
    final saved = _layeredNote();
    final bytes = saved.saveToBinary(currentPageIndex: 0);

    final viaSync = EditorCoreInfo.fromBinary(
      buffer: bytes,
      filePath: '/tmp/parity-note',
      readOnly: false,
      onlyFirstPage: false,
    );
    final viaChunked = EditorCoreInfo.fromBinary(
      buffer: bytes,
      filePath: '/tmp/parity-note',
      readOnly: false,
      onlyFirstPage: false,
    );
    // Pages 3..5 are lazy shells in both (eager window is 0..2).
    for (final i in [3, 4, 5]) {
      expect(viaSync.isLazyShellPage(i), isTrue);
      expect(viaChunked.isLazyShellPage(i), isTrue);
    }

    for (final i in [3, 4, 5]) {
      viaSync.ensurePageHydrated(i);
      final page = await viaChunked.hydratePageChunked(i);
      expect(page, isNotNull);
      expect(viaChunked.isLazyShellPage(i), isFalse);
      _expectSamePage(viaSync.pages[i], page!);
    }

    // Unknown / duplicate calls collapse to null.
    expect(await viaChunked.hydratePageChunked(4), isNull);
    expect(await viaChunked.hydratePageChunked(99), isNull);

    for (final p in saved.pages) {
      p.dispose();
    }
    for (final p in viaSync.pages) {
      p.dispose();
    }
    for (final p in viaChunked.pages) {
      p.dispose();
    }
  });

  test('parse precomputes exact stroke bounds', () {
    final saved = _layeredNote();
    final original = saved.pages[0].allStrokesInDrawOrder.first;
    final expectedBounds = original.bounds;
    final bytes = saved.saveToBinary(currentPageIndex: 0);

    final loaded = EditorCoreInfo.fromBinary(
      buffer: bytes,
      filePath: '/tmp/parity-note',
      readOnly: false,
      onlyFirstPage: false,
    );
    final reloaded = loaded.pages[0].allStrokesInDrawOrder.first;
    // Bounds survived the round trip without lazy recompute drift.
    expect(reloaded.bounds, expectedBounds);

    for (final p in saved.pages) {
      p.dispose();
    }
    for (final p in loaded.pages) {
      p.dispose();
    }
  });
}
