// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/editor/canvas_background_pattern.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/note_page_format.dart';
import 'package:saber/data/editor/page.dart';

/// Removes the `notePageFormat` header entry (key 28 + length-prefixed name),
/// simulating a file written before the format key existed.
Uint8List _stripPageFormatKey(Uint8List bytes, NotePageFormat format) {
  final name = format.name;
  final pattern = <int>[28, name.length, 0, 0, 0, ...name.codeUnits];
  var found = -1;
  for (var i = 0; i + pattern.length <= bytes.length; i++) {
    var match = true;
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      expect(found, -1, reason: 'format key must appear exactly once');
      found = i;
    }
  }
  expect(found, isNot(-1), reason: 'format key not found in payload');
  final out = Uint8List(bytes.length - pattern.length);
  out.setRange(0, found, bytes);
  out.setRange(found, out.length, bytes, found + pattern.length);
  return out;
}

void main() {
  test('notePageFormat round-trips every header path', () async {
    final info = EditorCoreInfo(
      filePath: '/tmp/pageformat-note',
      readOnly: false,
    );
    info.pages.add(EditorPage(width: 1440, height: 2036));
    info.notePageFormat = NotePageFormat.samsungNotes;

    final bytes = info.saveToBinary(currentPageIndex: 0);
    final loaded = EditorCoreInfo.fromBinary(
      buffer: bytes,
      filePath: '/tmp/pageformat-note',
      readOnly: false,
      onlyFirstPage: false,
    );
    expect(loaded.notePageFormat, NotePageFormat.samsungNotes);

    final loadedAsync = await EditorCoreInfo.fromBinaryAsync(
      buffer: bytes,
      filePath: '/tmp/pageformat-note',
      readOnly: false,
      onlyFirstPage: false,
    );
    expect(loadedAsync.notePageFormat, NotePageFormat.samsungNotes);

    final bytesAsync = await info.saveToBinaryAsync(currentPageIndex: 0);
    final loadedAsyncSave = EditorCoreInfo.fromBinary(
      buffer: bytesAsync,
      filePath: '/tmp/pageformat-note',
      readOnly: false,
      onlyFirstPage: false,
    );
    expect(loadedAsyncSave.notePageFormat, NotePageFormat.samsungNotes);

    // Background saves replace coreInfo via copyWith: the format must survive
    // or it silently resets to A4 (and stops being written).
    final copied = info.copyWith(lastModification: 7);
    expect(copied.notePageFormat, NotePageFormat.samsungNotes);

    for (final page in [
      ...info.pages,
      ...loaded.pages,
      ...loadedAsync.pages,
      ...loadedAsyncSave.pages,
    ]) {
      page.dispose();
    }
  });

  test('imported page keeps its local pattern across a save+load', () {
    final info = EditorCoreInfo(
      filePath: '/tmp/pageformat-imported',
      readOnly: false,
    );
    final page = EditorPage(width: 1440, height: 2036);
    // Exactly what the .sdocx importer writes for a templated Samsung page.
    page.backgroundPattern = CanvasBackgroundPattern.grid;
    page.hasLocalPattern = true;
    page.backgroundColor = const Color(0xFFFFFFFF);
    page.hasLocalBackgroundColor = true;
    page.lineHeight = 46;
    page.lineThickness = 1.44;
    page.hasLocalLineHeight = true;
    page.hasLocalLineThickness = true;
    info.pages.add(page);

    final bytes = info.saveToBinary(currentPageIndex: 0);
    final loaded = EditorCoreInfo.fromBinary(
      buffer: bytes,
      filePath: '/tmp/pageformat-imported',
      readOnly: false,
      onlyFirstPage: false,
    );
    final loadedPage = loaded.pages.single;
    expect(loadedPage.backgroundPattern, CanvasBackgroundPattern.grid);
    expect(loadedPage.hasLocalPattern, isTrue);
    expect(loadedPage.lineHeight, 46);
    expect(loadedPage.hasLocalLineHeight, isTrue);
    expect(loadedPage.hasLocalLineThickness, isTrue);
    expect(loadedPage.lineThickness, greaterThan(0));

    for (final p in [page, loadedPage]) {
      p.dispose();
    }
  });

  test('legacy file without the key infers Samsung Notes from page size', () async {
    final info = EditorCoreInfo(
      filePath: '/tmp/pageformat-legacy',
      readOnly: false,
    );
    info.pages.add(EditorPage(width: 1440, height: 2036));
    expect(info.notePageFormat, NotePageFormat.a4);

    final bytes = _stripPageFormatKey(
      info.saveToBinary(currentPageIndex: 0),
      NotePageFormat.a4,
    );
    final loaded = EditorCoreInfo.fromBinary(
      buffer: bytes,
      filePath: '/tmp/pageformat-legacy',
      readOnly: false,
      onlyFirstPage: false,
    );
    expect(loaded.notePageFormat, NotePageFormat.samsungNotes);

    final loadedAsync = await EditorCoreInfo.fromBinaryAsync(
      buffer: bytes,
      filePath: '/tmp/pageformat-legacy',
      readOnly: false,
      onlyFirstPage: false,
    );
    expect(loadedAsync.notePageFormat, NotePageFormat.samsungNotes);

    for (final page in [...info.pages, ...loaded.pages, ...loadedAsync.pages]) {
      page.dispose();
    }
  });

  test('legacy file without the key infers A4 for default-sized pages', () {
    final info = EditorCoreInfo(
      filePath: '/tmp/pageformat-legacy2',
      readOnly: false,
    );
    info.pages.add(EditorPage());

    final bytes = _stripPageFormatKey(
      info.saveToBinary(currentPageIndex: 0),
      NotePageFormat.a4,
    );
    final loaded = EditorCoreInfo.fromBinary(
      buffer: bytes,
      filePath: '/tmp/pageformat-legacy2',
      readOnly: false,
      onlyFirstPage: false,
    );
    expect(loaded.notePageFormat, NotePageFormat.a4);

    for (final page in [...info.pages, ...loaded.pages]) {
      page.dispose();
    }
  });
}
