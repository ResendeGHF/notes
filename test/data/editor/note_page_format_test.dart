// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/editor/note_page_format.dart';

void main() {
  test('A4 is the first entry so the persisted default index 0 is A4', () {
    expect(NotePageFormat.values.first, NotePageFormat.a4);
  });

  test('every format is portrait with its physical proportion', () {
    for (final format in NotePageFormat.values) {
      final size = format.portraitSize;
      expect(
        size.height,
        greaterThan(size.width),
        reason: '${format.name} must be taller than wide',
      );
      expect(
        size.aspectRatio,
        closeTo(format.widthMm / format.heightMm, 0.002),
        reason: '${format.name} keeps its physical proportion',
      );
    }
  });

  test('A4 keeps the historical 1000-unit width', () {
    final a4 = NotePageFormat.a4.portraitSize;
    expect(a4.width, 1000);
    expect(a4.height, closeTo(1000 * 297 / 210, 0.01));
  });

  test('Samsung Notes matches the .sdocx native page size', () {
    expect(NotePageFormat.samsungNotes.portraitSize, const Size(1440, 2036));
  });

  test('sizeFor swaps the axes for landscape', () {
    for (final format in NotePageFormat.values) {
      final portrait = format.portraitSize;
      expect(format.sizeFor(), portrait);
      expect(
        format.sizeFor(landscape: true),
        Size(portrait.height, portrait.width),
      );
    }
  });

  test('notePageFormatFromName resolves names and falls back to A4', () {
    for (final format in NotePageFormat.values) {
      expect(notePageFormatFromName(format.name), format);
    }
    expect(notePageFormatFromName('not-a-format'), NotePageFormat.a4);
  });
}
