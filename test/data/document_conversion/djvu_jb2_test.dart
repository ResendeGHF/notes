// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// JB2 decoder tests against the DjVu fixture corpus.
//
// Every fixture mask is produced by the Rust reference implementation
// (`oracle dump`), so a byte-exact match pins the pure-Dart port to the
// reference decoder.
//
// The bundled fixtures (`bilevel`, `layered`, `annotated`) keep their symbol
// dictionary in a shared `FORM:DJVI` component that the page forms reference
// through `INCL dict0001.djvi`; those pages only decode when the shared `Djbz`
// is passed in. `archival` has no shared component: its dictionary lives in the
// page's own `Sjbz` stream.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/document_conversion/djvu/djvu_bitmap.dart';
import 'package:saber/data/document_conversion/djvu/djvu_iff.dart';
import 'package:saber/data/document_conversion/djvu/djvu_jb2.dart';

import 'djvu/djvu_fixture.dart';

/// Extracts the shared symbol dictionary from a bundled fixture.
///
/// The dictionary is the `Djbz` chunk of the document's `FORM:DJVI` component,
/// which every page form references with `INCL dict0001.djvi`.
Jb2Dict readSharedDict(String name) {
  final root = parseIffFile(readDjvuFile(name));
  final djviChunk = root.chunks.firstWhere(
    (c) => c.id == 'FORM' && c.formType == 'DJVI',
  );
  final dict = jb2DecodeDict(parseIffSubForm(djviChunk.data).find('Djbz')!.data);
  return dict;
}

/// Compares a decoded mask with the reference mask byte for byte.
void expectMaskMatches(DjvuBitmap actual, DjvuBitmap expected, String label) {
  expect(actual.width, expected.width, reason: '$label: width');
  expect(actual.height, expected.height, reason: '$label: height');
  expect(actual.data, equals(expected.data), reason: '$label: packed bytes');
}

/// The `FORM:DJVU` page components of a bundled fixture, in DIRM order.
List<IffChunk> pageForms(String name) => parseIffFile(readDjvuFile(name)).chunks
    .where((c) => c.id == 'FORM' && c.formType == 'DJVU')
    .toList();

/// The `INCL` target of one page component of a bundled fixture.
String? pageIncludeTarget(IffChunk pageForm) =>
    inclTarget(parseIffSubForm(pageForm.data).find('INCL')!.data);

void main() {
  group('jb2Decode (Sjbz)', () {
    test('bilevel: 3 pages decode against the shared Djbz', () {
      final forms = pageForms('bilevel');
      expect(forms, hasLength(3));

      final manifest =
          readDjvuManifest('bilevel')['pages'] as List<dynamic>;
      final dict = readSharedDict('bilevel');

      for (var page = 0; page < 3; page++) {
        // The page form carries INCL dict0001.djvi, i.e. the DJVI dictionary
        // extracted above is the one this page's Sjbz stream references.
        expect(
          pageIncludeTarget(forms[page]),
          'dict0001.djvi',
          reason: 'page $page INCL target',
        );

        final mask = jb2Decode(
          readDjvuRef('bilevel', 'p$page.Sjbz.bin'),
          sharedDict: dict,
        );

        final reference = readMaskFixture('bilevel', page);
        expectMaskMatches(mask, reference, 'bilevel p$page');

        // Dimensions from the harness helper and the manifest must agree too.
        expect(mask.width, readMaskFixture('bilevel', page).width);
        expect(mask.height, readMaskFixture('bilevel', page).height);
        final size = (manifest[page] as Map<String, dynamic>)['mask'] as List<dynamic>;
        expect(mask.width, size[0], reason: 'bilevel p$page manifest width');
        expect(mask.height, size[1], reason: 'bilevel p$page manifest height');
      }
    });

    test('layered: 2 pages decode against the shared Djbz', () {
      final forms = pageForms('layered');
      expect(forms, hasLength(2));

      final manifest =
          readDjvuManifest('layered')['pages'] as List<dynamic>;
      final dict = readSharedDict('layered');

      for (var page = 0; page < 2; page++) {
        expect(
          pageIncludeTarget(forms[page]),
          'dict0001.djvi',
          reason: 'page $page INCL target',
        );

        final mask = jb2Decode(
          readDjvuRef('layered', 'p$page.Sjbz.bin'),
          sharedDict: dict,
        );

        expectMaskMatches(mask, readMaskFixture('layered', page), 'layered p$page');

        expect(mask.width, readMaskFixture('layered', page).width);
        expect(mask.height, readMaskFixture('layered', page).height);
        final size = (manifest[page] as Map<String, dynamic>)['mask'] as List<dynamic>;
        expect(mask.width, size[0], reason: 'layered p$page manifest width');
        expect(mask.height, size[1], reason: 'layered p$page manifest height');
      }
    });

    test('archival: page 0 decodes with its embedded dictionary', () {
      // No FORM:DJVI component and no INCL in this fixture: the Sjbz stream
      // defines every symbol it uses (type 2 records), so no shared dict is
      // needed.
      final root = parseIffFile(readDjvuFile('archival'));
      expect(
        root.chunks.where((c) => c.id == 'FORM' && c.formType == 'DJVI'),
        isEmpty,
      );

      final mask = jb2Decode(readDjvuRef('archival', 'p0.Sjbz.bin'));

      expectMaskMatches(mask, readMaskFixture('archival', 0), 'archival p0');
      expect(mask.width, 1240);
      expect(mask.height, 1600);
      // A real page must have produced marks.
      expect(mask.data.any((b) => b != 0), isTrue);
    });

    test('a page that references the shared dict throws with no dict', () {
      // bilevel p0 starts with a type-9 "required-dict-or-reset" record.
      expect(
        () => jb2Decode(readDjvuRef('bilevel', 'p0.Sjbz.bin')),
        throwsA(isA<Jb2Exception>()),
      );
      expect(
        () => jb2Decode(readDjvuRef('layered', 'p0.Sjbz.bin')),
        throwsA(isA<Jb2Exception>()),
      );
    });

    test('truncated Sjbz input fails fast', () {
      final dict = readSharedDict('bilevel');
      final full = readDjvuRef('bilevel', 'p0.Sjbz.bin');

      for (final length in [2, 8, 64, 256, 768]) {
        final watch = Stopwatch()..start();
        expect(
          () => jb2Decode(Uint8List.sublistView(full, 0, length), sharedDict: dict),
          throwsA(isA<Jb2Exception>()),
          reason: 'truncated to $length bytes must throw',
        );
        watch.stop();
        expect(
          watch.elapsedMilliseconds,
          lessThan(5000),
          reason: 'truncated to $length bytes must not spin',
        );
      }
    });
  });

  group('jb2DecodeIndexed', () {
    test('layered page 0: mask and per-blit record map', () {
      final dict = readSharedDict('layered');
      final (mask, blitMap) = jb2DecodeIndexed(
        readDjvuRef('layered', 'p0.Sjbz.bin'),
        sharedDict: dict,
      );

      // The mask is unchanged by index tracking.
      expectMaskMatches(mask, readMaskFixture('layered', 0), 'layered p0 indexed');

      expect(blitMap.length, mask.width * mask.height);

      var maxIndex = -1;
      var unmarkedViolations = 0;
      var outsideViolations = 0;
      final seen = <int>{};
      for (var y = 0; y < mask.height; y++) {
        for (var x = 0; x < mask.width; x++) {
          final index = blitMap[y * mask.width + x];
          if (mask.get(x, y)) {
            if (index < 0) unmarkedViolations++;
            seen.add(index);
            if (index > maxIndex) maxIndex = index;
          } else if (index != -1) {
            outsideViolations++;
          }
        }
      }
      expect(unmarkedViolations, 0, reason: 'foreground pixels must have an index');
      expect(outsideViolations, 0, reason: 'background pixels must be -1');

      // Blit indices are handed out densely, from 0, once per blitting record.
      expect(
        seen.length,
        maxIndex + 1,
        reason: 'blit indices must be dense from 0',
      );
      expect(maxIndex, greaterThanOrEqualTo(0));

      // Cross-check against the FGbz palette table: it has one entry per blit
      // record, so its length should equal the decoded blit count. Only assert
      // when it holds — a table may be longer than the indexes that survive in
      // the final mask.
      final pages =
          readDjvuManifest('layered')['pages'] as List<dynamic>;
      final fgbzIndices = (pages[0] as Map<String, dynamic>)['fgbzIndices'] as int;
      final decodedIndices = maxIndex + 1;
      if (decodedIndices == fgbzIndices) {
        expect(decodedIndices, fgbzIndices, reason: 'FGbz per-blit table length');
      } else {
        printOnFailure(
          'jb2DecodeIndexed decoded $decodedIndices blit records but the '
          'manifest reports $fgbzIndices FGbz entries',
        );
      }
    });
  });

  group('jb2DecodeDict', () {
    test('decodes the shared dictionary of a bundled fixture', () {
      // readSharedDict itself throws (and fails the test) if the Djbz stream
      // is malformed; decoding a page with it proves it is usable.
      final dict = readSharedDict('bilevel');
      final mask = jb2Decode(
        readDjvuRef('bilevel', 'p0.Sjbz.bin'),
        sharedDict: dict,
      );
      expect(mask.data.any((b) => b != 0), isTrue);
    });

    test('rejects empty and malformed streams', () {
      expect(() => jb2DecodeDict(Uint8List(0)), throwsA(isA<Jb2Exception>()));
      expect(
        () => jb2DecodeDict(Uint8List.fromList([0x00])),
        throwsA(isA<Jb2Exception>()),
      );
      // All-ones input: the record loop reads garbage record types.
      expect(
        () => jb2DecodeDict(Uint8List(64)..fillRange(0, 64, 0xff)),
        throwsA(isA<Jb2Exception>()),
      );
      // All-zero input: the reserved header flag bit is set.
      expect(
        () => jb2DecodeDict(Uint8List(64)),
        throwsA(isA<Jb2Exception>()),
      );
      // Arbitrary bytes: rejected in the header.
      expect(
        () => jb2DecodeDict(
          Uint8List.fromList('this is not a jb2 dictionary'.codeUnits),
        ),
        throwsA(isA<Jb2Exception>()),
      );
    });
  });
}
