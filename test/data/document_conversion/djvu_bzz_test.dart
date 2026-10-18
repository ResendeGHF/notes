// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/document_conversion/djvu/djvu_bzz.dart';
import 'package:saber/data/document_conversion/djvu/djvu_iff.dart';

import 'djvu/djvu_fixture.dart';

void main() {
  group('bzzDecode', () {
    test('decodes DIRM metadata of every fixture', () {
      for (final name in djvuFixtures) {
        final manifest = readDjvuManifest(name);
        final hasDirm = (manifest['rootChunks'] as List<dynamic>).any(
          (chunk) => (chunk as List<dynamic>)[0] == 'DIRM',
        );
        if (!hasDirm) continue;
        // Only the tail of the DIRM chunk is BZZ-compressed.
        final dirm = parseDirmPayload(readDjvuRef(name, 'root.DIRM.bin'));
        expect(
          bzzDecode(dirm.metadata),
          equals(
            readDjvuRef(
              name,
              'root.DIRM.dec.bin',
            ),
          ),
          reason: '$name DIRM metadata',
        );
      }
    });

    test('decodes NAVM bookmarks and ANTz annotations', () {
      expect(
        bzzDecode(readDjvuRef('annotated', 'root.NAVM.bin')),
        equals(readDjvuRef('annotated', 'root.NAVM.dec.bin')),
        reason: 'NAVM',
      );
      expect(
        bzzDecode(readDjvuRef('annotated', 'p0.ANTz.bin')),
        equals(readDjvuRef('annotated', 'p0.ANTz.dec.bin')),
        reason: 'ANTz',
      );
    });

    test('rejects empty and too-short inputs', () {
      expect(() => bzzDecode(Uint8List(0)), throwsA(isA<BzzException>()));
      expect(() => bzzDecode(Uint8List(1)), throwsA(isA<BzzException>()));
    });

    test('rejects a truncated stream instead of spinning', () {
      final whole = readDjvuRef('annotated', 'root.NAVM.bin');
      final truncated = Uint8List.sublistView(whole, 0, 20);
      expect(() => bzzDecode(truncated), throwsA(isA<BzzException>()));
    });
  });
}
