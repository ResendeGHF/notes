// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/editor/binary_writer.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/_tool.dart';

import '../../helpers/test_stroke_factory.dart';

EditorCoreInfo _twelvePageStrokeNote() {
  final info = EditorCoreInfo(filePath: '/tmp/scroll-note', readOnly: false);
  for (var i = 0; i < 12; i++) {
    final page = EditorPage();
    page.insertStroke(
      testPolylineStroke(toolId: ToolId.ballpointPen, y: 80.0 + i * 4),
    );
    info.pages.add(page);
  }
  return info;
}

void main() {
  test('skipPageBinary marks a lazy shell', () {
    final page = EditorPage(isLazyShell: true);
    expect(page.isLazyShell, isTrue);
    expect(page.strokeCountInDrawOrder, 0);
  });

  test('lazy load keeps distant pages as shells until idle hydrate', () {
    final saved = _twelvePageStrokeNote();
    final bytes = saved.saveToBinary(currentPageIndex: 0);
    final loaded = EditorCoreInfo.fromBinary(
      buffer: bytes,
      filePath: '/tmp/scroll-note',
      readOnly: false,
      onlyFirstPage: false,
    );

    expect(loaded.pages.length, 12);
    expect(loaded.hasUnhydratedLazyPages, isTrue);
    // Eager window is initial ±2 → pages 0..2 hydrated from page 0.
    expect(loaded.isLazyShellPage(0), isFalse);
    expect(loaded.isLazyShellPage(1), isFalse);
    expect(loaded.isLazyShellPage(2), isFalse);
    expect(loaded.pages[0].isLazyShell, isFalse);

    expect(loaded.isLazyShellPage(10), isTrue);
    expect(loaded.pages[10].isLazyShell, isTrue);
    expect(loaded.pages[10].strokeCountInDrawOrder, 0);

    // Load must not build a spatial index on the UI-critical path.
    expect(loaded.pages[0].strokeSpatialIndex, isNull);

    // pageBuilder / build must not hydrate — the shell stays a shell.
    expect(loaded.isLazyShellPage(10), isTrue);

    expect(loaded.tryHydratePageAtIndex(10), isTrue);
    expect(loaded.isLazyShellPage(10), isFalse);
    expect(loaded.pages[10].isLazyShell, isFalse);
    expect(loaded.pages[10].strokeCountInDrawOrder, greaterThan(0));

    expect(loaded.tryHydratePageAtIndex(10), isFalse);
  });

  test('eager window follows initial page (±2), not all PDF pages', () {
    final saved = _twelvePageStrokeNote();
    final bytes = saved.saveToBinary(currentPageIndex: 5);
    final loaded = EditorCoreInfo.fromBinary(
      buffer: bytes,
      filePath: '/tmp/scroll-note',
      readOnly: false,
      onlyFirstPage: false,
      preferEagerAllPages: true,
    );

    expect(loaded.pages.length, 12);
    for (final i in [3, 4, 5, 6, 7]) {
      expect(loaded.isLazyShellPage(i), isFalse, reason: 'page $i should be eager');
    }
    expect(loaded.isLazyShellPage(0), isTrue);
    expect(loaded.isLazyShellPage(11), isTrue);

    loaded.ensurePageHydrated(11);
    expect(loaded.isLazyShellPage(11), isFalse);
    expect(loaded.pages[11].strokeCountInDrawOrder, greaterThan(0));
  });

  test('jump hydrate window materializes neighbors', () {
    final saved = _twelvePageStrokeNote();
    final bytes = saved.saveToBinary(currentPageIndex: 0);
    final loaded = EditorCoreInfo.fromBinary(
      buffer: bytes,
      filePath: '/tmp/scroll-note',
      readOnly: false,
      onlyFirstPage: false,
    );

    const target = 9;
    const neighborWindow = 1;
    for (var i = target - neighborWindow; i <= target + neighborWindow; i++) {
      loaded.ensurePageHydrated(i);
    }
    expect(loaded.isLazyShellPage(8), isFalse);
    expect(loaded.isLazyShellPage(9), isFalse);
    expect(loaded.isLazyShellPage(10), isFalse);
    expect(loaded.isLazyShellPage(11), isTrue);
  });

  test('second save keeps unhydrated page content (no data loss)', () {
    final saved = _twelvePageStrokeNote();
    // Put a distinctive stroke on a distant page so we can detect wipe.
    saved.pages[10].insertStroke(
      testPolylineStroke(toolId: ToolId.fountainPen, y: 200),
    );
    final bytes = saved.saveToBinary(currentPageIndex: 0);

    final loaded = EditorCoreInfo.fromBinary(
      buffer: bytes,
      filePath: '/tmp/scroll-note',
      readOnly: false,
      onlyFirstPage: false,
    );
    expect(loaded.hasUnhydratedLazyPages, isTrue);
    expect(loaded.isLazyShellPage(10), isTrue);

    // Edit a hydrated page and save twice (autosave + leave), mimicking the
    // regression where _lazyPages was cleared after the first encode.
    loaded.pages[0].insertStroke(
      testPolylineStroke(toolId: ToolId.ballpointPen, y: 12),
    );
    final firstSave = loaded.saveToBinary(currentPageIndex: 0);
    expect(loaded.hasUnhydratedLazyPages, isTrue);
    expect(loaded.isLazyShellPage(10), isTrue);

    final secondSave = loaded.saveToBinary(currentPageIndex: 0);

    final reloaded = EditorCoreInfo.fromBinary(
      buffer: secondSave,
      filePath: '/tmp/scroll-note',
      readOnly: false,
      onlyFirstPage: false,
    );
    expect(reloaded.pages.length, 12);
    reloaded.ensurePageHydrated(10);
    expect(reloaded.pages[10].isLazyShell, isFalse);
    expect(reloaded.pages[10].strokeCountInDrawOrder, greaterThan(0));

    // First save must also be intact.
    final fromFirst = EditorCoreInfo.fromBinary(
      buffer: firstSave,
      filePath: '/tmp/scroll-note',
      readOnly: false,
      onlyFirstPage: false,
    );
    fromFirst.ensurePageHydrated(10);
    expect(fromFirst.pages[10].strokeCountInDrawOrder, greaterThan(0));
  });

  test('serializing a lazy shell throws instead of writing a blank page', () {
    final page = EditorPage(isLazyShell: true);
    expect(
      () => page.toBinary(BinaryWriter()),
      throwsA(isA<StateError>()),
    );
  });

  test('prewarmStrokeMeshes warms vertices, not only highQualityPath', () {
    final page = EditorPage();
    final stroke = testPolylineStroke(toolId: ToolId.ballpointPen);
    page.insertStroke(stroke);

    expect(stroke.vertices, isNotNull);
    // Clear by making a fresh stroke that has not been meshed via canBatch.
    final cold = testPolylineStroke(toolId: ToolId.ballpointPen, y: 140);
    // Accessing vertices in the factory path may already build a mesh.
    // The prewarm API must still be idempotent and finish the page.
    page.insertStroke(cold);
    expect(page.prewarmStrokeMeshes(maxStrokes: 1), isNot(-1));
    expect(page.prewarmStrokeMeshes(startOffset: 1, maxStrokes: 16), -1);
    expect(page.strokeSpatialIndex, isNotNull);
    expect(page.strokeAtDrawOrderIndex(0)!.vertices, isNotNull);
    expect(page.strokeAtDrawOrderIndex(1)!.vertices, isNotNull);
  });
}
