// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/document_conversion/djvu/djvu_color.dart';
import 'package:saber/data/document_conversion/djvu/djvu_fgbz.dart';

import 'djvu/djvu_fixture.dart';

void main() {
  group('parseFgbzPalette', () {
    test('matches the reference on every layered palette', () {
      const pages = {'archival': [0], 'layered': [0, 1]};
      for (final MapEntry(key: name, value: indices) in pages.entries) {
        final manifest = readDjvuManifest(name);
        for (final i in indices) {
          final palette = parseFgbzPalette(readDjvuRef(name, 'p$i.FGbz.bin'));
          final reference = readDjvuFgbz(name, i)!;
          final expectedColors =
              (reference['colors'] as List<dynamic>).cast<List<dynamic>>();

          expect(
            palette.colors,
            hasLength(expectedColors.length),
            reason: '$name page $i colors',
          );
          for (var c = 0; c < expectedColors.length; c++) {
            final rgb = expectedColors[c];
            expect(
              palette.colors[c],
              DjvuColor(rgb[0] as int, rgb[1] as int, rgb[2] as int),
              reason: '$name page $i color $c',
            );
          }

          final expectedIndices =
              (reference['indices'] as List<dynamic>).cast<int>();
          expect(
            palette.indices,
            expectedIndices,
            reason: '$name page $i indices',
          );
          expect(
            palette.indices,
            hasLength(
              (manifest['pages'] as List<dynamic>)[i]['fgbzIndices'] as int,
            ),
            reason: '$name page $i index count',
          );
        }
      }
    });

    test('short and empty chunks yield an empty palette', () {
      expect(parseFgbzPalette(Uint8List(0)).colors, isEmpty);
      expect(parseFgbzPalette(Uint8List.fromList([0])).colors, isEmpty);
      expect(parseFgbzPalette(Uint8List.fromList([0, 0])).colors, isEmpty);
      final zeroColors = parseFgbzPalette(Uint8List.fromList([0, 0, 0]));
      expect(zeroColors.colors, isEmpty);
      expect(zeroColors.indices, isEmpty);
    });

    test('fills truncated color entries with black', () {
      // Two colors announced, only one BGR triple present.
      final palette = parseFgbzPalette(
        Uint8List.fromList([0, 0, 2, 10, 20, 30]),
      );
      expect(palette.colors, [
        const DjvuColor(30, 20, 10),
        const DjvuColor(0, 0, 0),
      ]);
      expect(palette.indices, isEmpty);
    });

    test('version bit 7 without an index payload leaves indices empty', () {
      final palette = parseFgbzPalette(
        Uint8List.fromList([0x80, 0, 1, 10, 20, 30]),
      );
      expect(palette.colors, [const DjvuColor(30, 20, 10)]);
      expect(palette.indices, isEmpty);
    });
  });
}
