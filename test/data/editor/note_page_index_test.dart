// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/note_page_index.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/_tool.dart';

import '../../helpers/test_stroke_factory.dart';

void main() {
  test('page index matches lazy offsets and round-trips', () async {
    final info = EditorCoreInfo(filePath: '/tmp/index-note', readOnly: false);
    info.initialPageIndex = 4;
    for (var p = 0; p < 8; p++) {
      final page = EditorPage(width: 800 + p.toDouble(), height: 1100);
      page.id = 10 + p;
      page.insertStroke(
        testPolylineStroke(
          toolId: ToolId.ballpointPen,
          y: 40.0 + p,
          points: 80,
        ),
      );
      info.pages.add(page);
    }
    final bytes = info.saveToBinary(currentPageIndex: 4);

    final scanned = EditorCoreInfo.scanNotePageDirectory(bytes);
    expect(scanned.pageCount, 8);
    expect(scanned.structurallyValid(bytes), isTrue);

    final viaSync = EditorCoreInfo.fromBinary(
      buffer: bytes,
      filePath: '/tmp/index-note',
      readOnly: false,
      onlyFirstPage: false,
    );
    final offsets = viaSync.debugLazyPageByteOffsets;
    expect(offsets, isNotNull);
    for (var i = 0; i < scanned.pageCount; i++) {
      expect(scanned.spans[i].start, offsets![i], reason: 'start $i');
      expect(scanned.spans[i].end, offsets[i + 1], reason: 'end $i');
      expect(scanned.spans[i].id, 10 + i);
    }

    final encoded = NotePageIndex.encode(scanned);
    final decoded = NotePageIndex.decode(encoded);
    expect(decoded, isNotNull);
    expect(decoded!.structurallyValid(bytes), isTrue);

    final dir = await Directory.systemTemp.createTemp('nix');
    final bodyPath = '${dir.path}/note.sbn2';
    await File(bodyPath).writeAsBytes(bytes);
    await NotePageIndex.store(bodyPath, scanned);
    final loaded = NotePageIndex.tryLoad(bodyPath, bytes);
    expect(loaded, isNotNull);
    expect(loaded!.spans[4].start, scanned.spans[4].start);

    final opened = await EditorCoreInfo.fromBinaryAsync(
      buffer: bytes,
      filePath: '/tmp/index-note',
      readOnly: false,
      onlyFirstPage: false,
      pageDirectory: scanned,
    );
    expect(opened.isLazyShellPage(4), isFalse);
    expect(opened.pages[4].allStrokesInDrawOrder.length, 1);
    expect(opened.pages[4].allStrokesInDrawOrder.first.points.length, 80);
    expect(opened.isLazyShellPage(0), isTrue);
    expect(opened.isLazyShellPage(6), isTrue);
    expect(opened.pages[0].size.width, closeTo(800, 0.01));

    final hydrated = await opened.hydratePageChunked(0);
    expect(hydrated, isNotNull);
    expect(hydrated!.allStrokesInDrawOrder.first.points.length, 80);
    expect(opened.isLazyShellPage(0), isFalse);
  });
}
