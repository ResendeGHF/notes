// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';

void main() {
  test('showPdfLinkBoxes defaults true and round-trips binary', () async {
    final info = EditorCoreInfo(filePath: '/tmp/linkboxes-note', readOnly: false);
    info.pages.add(EditorPage());
    expect(info.showPdfLinkBoxes, isTrue);

    // Default true: omitted from payload, loads back as true.
    final bytesDefault = info.saveToBinary(currentPageIndex: 0);
    final loadedDefault = EditorCoreInfo.fromBinary(
      buffer: bytesDefault,
      filePath: '/tmp/linkboxes-note',
      readOnly: false,
      onlyFirstPage: false,
    );
    expect(loadedDefault.showPdfLinkBoxes, isTrue);

    final loadedDefaultAsync = await EditorCoreInfo.fromBinaryAsync(
      buffer: bytesDefault,
      filePath: '/tmp/linkboxes-note',
      readOnly: false,
      onlyFirstPage: false,
    );
    expect(loadedDefaultAsync.showPdfLinkBoxes, isTrue);

    // Disabled: persisted and restored on both readers.
    info.showPdfLinkBoxes = false;
    final bytesOff = info.saveToBinary(currentPageIndex: 0);
    final loadedOff = EditorCoreInfo.fromBinary(
      buffer: bytesOff,
      filePath: '/tmp/linkboxes-note',
      readOnly: false,
      onlyFirstPage: false,
    );
    expect(loadedOff.showPdfLinkBoxes, isFalse);

    final loadedOffAsync = await EditorCoreInfo.fromBinaryAsync(
      buffer: bytesOff,
      filePath: '/tmp/linkboxes-note',
      readOnly: false,
      onlyFirstPage: false,
    );
    expect(loadedOffAsync.showPdfLinkBoxes, isFalse);

    for (final p in info.pages) {
      p.dispose();
    }
  });

  test('showPdfLinkBoxes survives copyWith used by background saves', () async {
    final info = EditorCoreInfo(filePath: '/tmp/linkboxes-note', readOnly: false);
    info.pages.add(EditorPage());
    info.showPdfLinkBoxes = false;

    // _runBackgroundSave replaces coreInfo via copyWith on every save: the
    // flag must survive, otherwise the toggle silently resets to true and the
    // saved file omits it.
    final copied = info.copyWith(lastModification: 123);
    expect(copied.showPdfLinkBoxes, isFalse);

    final bytes = copied.saveToBinary(currentPageIndex: 0);
    final loaded = EditorCoreInfo.fromBinary(
      buffer: bytes,
      filePath: '/tmp/linkboxes-note',
      readOnly: false,
      onlyFirstPage: false,
    );
    expect(loaded.showPdfLinkBoxes, isFalse);

    for (final p in info.pages) {
      p.dispose();
    }
  });

  test('showPdfLinkBoxes round-trips json', () {
    final info = EditorCoreInfo(filePath: '/tmp/linkboxes-note', readOnly: false);
    info.pages.add(EditorPage());
    info.showPdfLinkBoxes = false;
    final json = info.toJson();
    expect(json['showLinkBoxes'], isFalse);

    final back = EditorCoreInfo.fromJson(
      json,
      filePath: '/tmp/linkboxes-note',
      readOnly: false,
      onlyFirstPage: false,
    );
    expect(back.showPdfLinkBoxes, isFalse);

    final infoDefault = EditorCoreInfo(
      filePath: '/tmp/linkboxes-note',
      readOnly: false,
    );
    infoDefault.pages.add(EditorPage());
    final backDefault = EditorCoreInfo.fromJson(
      infoDefault.toJson(),
      filePath: '/tmp/linkboxes-note',
      readOnly: false,
      onlyFirstPage: false,
    );
    expect(backDefault.showPdfLinkBoxes, isTrue);

    for (final p in info.pages) {
      p.dispose();
    }
    for (final p in back.pages) {
      p.dispose();
    }
    for (final p in infoDefault.pages) {
      p.dispose();
    }
    for (final p in backDefault.pages) {
      p.dispose();
    }
  });

  test('showPdfLinkBoxes round-trips saveToBinaryAsync (editor autosave path)',
      () async {
    final info = EditorCoreInfo(filePath: '/tmp/linkboxes-note', readOnly: false);
    info.pages.add(EditorPage());

    // Autosave uses saveToBinaryAsync: disabled must survive it.
    info.showPdfLinkBoxes = false;
    final bytesOff = await info.saveToBinaryAsync(currentPageIndex: 0);
    final loadedOff = EditorCoreInfo.fromBinary(
      buffer: bytesOff,
      filePath: '/tmp/linkboxes-note',
      readOnly: false,
      onlyFirstPage: false,
    );
    expect(loadedOff.showPdfLinkBoxes, isFalse);
    final loadedOffAsync = await EditorCoreInfo.fromBinaryAsync(
      buffer: bytesOff,
      filePath: '/tmp/linkboxes-note',
      readOnly: false,
      onlyFirstPage: false,
    );
    expect(loadedOffAsync.showPdfLinkBoxes, isFalse);

    // Default true stays true.
    info.showPdfLinkBoxes = true;
    final bytesOn = await info.saveToBinaryAsync(currentPageIndex: 0);
    final loadedOn = EditorCoreInfo.fromBinary(
      buffer: bytesOn,
      filePath: '/tmp/linkboxes-note',
      readOnly: false,
      onlyFirstPage: false,
    );
    expect(loadedOn.showPdfLinkBoxes, isTrue);

    for (final p in info.pages) {
      p.dispose();
    }
  });
}
