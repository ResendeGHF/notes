// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/document_conversion/djvu/djvu_text.dart';

import 'djvu/djvu_fixture.dart';

void main() {
  group('decodeDjvuText', () {
    test('matches the Rust reference on the whole conformance corpus', () {
      final fixture =
          jsonDecode(
                File(
                  '$djvuFixtureRoot/text_conformance.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final cases = (fixture['cases'] as List<dynamic>)
          .cast<List<dynamic>>();
      expect(cases, hasLength(2680));

      final mismatches = <String>[];
      for (final pair in cases) {
        final encoded = pair[0] as String;
        final expected = pair[1] as String;
        final actual = decodeDjvuText(base64Decode(encoded));
        if (actual != expected) {
          mismatches.add('$encoded: got "$actual", want "$expected"');
        }
      }
      expect(mismatches, isEmpty);
    });

    test('decodes CP1252 dashes, quotes, euro and latin1', () {
      expect(
        decodeDjvuText(Uint8List.fromList('Chapter 1 \x96 Intro'.codeUnits)),
        'Chapter 1 \u2013 Intro',
      );
      expect(
        decodeDjvuText(Uint8List.fromList('a\x97b'.codeUnits)),
        'a\u2014b',
      );
      expect(
        decodeDjvuText(Uint8List.fromList('\x93hi\x94 \x80 caf\xE9'.codeUnits)),
        '\u201Chi\u201D \u20AC caf\u00E9',
      );
    });

    test('passes undefined CP1252 bytes through as C1 controls', () {
      expect(
        decodeDjvuText(Uint8List.fromList([0x81, 0x8d, 0x8f, 0x90, 0x9d])),
        '\u0081\u008d\u008f\u0090\u009d',
      );
    });

    test('keeps valid UTF-8 runs intact around stray bytes', () {
      // "Glava " in UTF-8 Cyrillic + one stray CP1252 en dash + " odin".
      final bytes = Uint8List.fromList([
        0xd0, 0x93, 0xd0, 0xbb, 0xd0, 0xb0, 0xd0, 0xb2, 0xd0, 0xb0, //
        0x20, 0x96, 0x20, //
        0xd0, 0xbe, 0xd0, 0xb4, 0xd0, 0xb8, 0xd0, 0xbd,
      ]);
      expect(decodeDjvuText(bytes), '\u0413\u043b\u0430\u0432\u0430 \u2013 \u043e\u0434\u0438\u043d');
    });

    test('maps a truncated tail through CP1252, matching Rust', () {
      // 0xD0 opens a 2-byte sequence that never completes: the reference
      // consumes every remaining byte via CP1252 instead of U+FFFD.
      expect(decodeDjvuText(Uint8List.fromList([0x61, 0x62, 0xd0])), 'ab\u00d0');
      // A truncated 3-byte sequence with a valid continuation byte.
      expect(
        decodeDjvuText(Uint8List.fromList([0xe0, 0xa0])),
        '\u00e0\u00a0',
      );
      // The same byte with an invalid continuation is only itself consumed.
      expect(decodeDjvuText(Uint8List.fromList([0xe0, 0x41])), '\u00e0A');
    });

    test('every single byte value decodes without loss', () {
      for (var b = 0; b < 256; b++) {
        final decoded = decodeDjvuText(Uint8List.fromList([b]));
        expect(decoded, hasLength(1), reason: 'byte $b');
        expect(decoded.runes.single == b || decoded.runes.single >= 0x100, isTrue,
            reason: 'byte $b');
        expect(decoded.runes.single, isNot(0xfffd), reason: 'byte $b');
      }
    });

    test('leaves valid UTF-8 untouched, including astral planes', () {
      const text = 'caf\u00e9 \u2014 \u20ac \u0416 \u{1F600}';
      expect(decodeDjvuText(Uint8List.fromList(utf8.encode(text))), text);
    });
  });
}
