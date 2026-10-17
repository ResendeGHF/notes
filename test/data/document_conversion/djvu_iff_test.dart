// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/document_conversion/djvu/djvu_bzz.dart';
import 'package:saber/data/document_conversion/djvu/djvu_iff.dart';

import 'djvu/djvu_fixture.dart';

/// Chunk ids the oracle records in manifests (it deliberately skips INCL and
/// TH44, which are container/thumbnail details rather than page data).
const _recordedChunkIds = {
  'INFO',
  'Sjbz',
  'Djbz',
  'BG44',
  'FG44',
  'FGbz',
  'ANTa',
  'ANTz',
  'TXTz',
  'BGjp',
  'FGjp',
  'Smmr',
};

List<IffForm> _pageForms(IffForm root) {
  if (root.formType == 'DJVU' ||
      root.formType == 'BM44' ||
      root.formType == 'PM44') {
    return [root];
  }
  return [
    for (final chunk in root.chunks)
      if (chunk.id == 'FORM' &&
          (chunk.formType == 'DJVU' ||
              chunk.formType == 'BM44' ||
              chunk.formType == 'PM44'))
        parseIffSubForm(chunk.data),
  ];
}

String _rotationName(DjvuRotation rotation) => switch (rotation) {
  DjvuRotation.none => 'None',
  DjvuRotation.ccw90 => 'Ccw90',
  DjvuRotation.rot180 => 'Rot180',
  DjvuRotation.cw90 => 'Cw90',
};

void main() {
  group('parseIffFile', () {
    test('parses every fixture container', () {
      for (final name in djvuFixtures) {
        final manifest = readDjvuManifest(name);
        final form = parseIffFile(readDjvuFile(name));

        final isBundled = [
          'bilevel',
          'layered',
          'annotated',
        ].contains(name);
        expect(
          form.formType,
          isBundled ? 'DJVM' : 'DJVU',
          reason: '$name root form type',
        );

        final actualRoot = [
          for (final chunk in form.chunks) [chunk.id, chunk.data.length],
        ];
        final expectedRoot = [
          for (final chunk in manifest['rootChunks'] as List<dynamic>)
            [
              (chunk as List<dynamic>)[0] as String,
              chunk[1] as int,
            ],
        ];
        expect(actualRoot, expectedRoot, reason: '$name root chunks');

        final pages = _pageForms(form);
        final pageManifests = manifest['pages'] as List<dynamic>;
        expect(pages, hasLength(pageManifests.length), reason: '$name pages');

        for (var i = 0; i < pages.length; i++) {
          final page = pages[i];
          final pageManifest = pageManifests[i] as Map<String, dynamic>;

          // Page data chunks match the oracle's chunk list, in order.
          final actualChunks = [
            for (final chunk in page.chunks)
              if (_recordedChunkIds.contains(chunk.id))
                [chunk.id, chunk.data.length],
          ];
          final expectedChunks = [
            for (final chunk in pageManifest['chunks'] as List<dynamic>)
              [
                (chunk as List<dynamic>)[0] as String,
                chunk[1] as int,
              ],
          ];
          expect(
            actualChunks,
            expectedChunks,
            reason: '$name page $i chunks',
          );

          // INFO matches the oracle's page geometry.
          final infoChunk = page.find('INFO');
          expect(infoChunk, isNotNull, reason: '$name page $i INFO');
          final info = parseDjvuPageInfo(infoChunk!.data);
          expect(info.width, pageManifest['width'], reason: '$name page $i');
          expect(info.height, pageManifest['height'], reason: '$name page $i');
          expect(info.dpi, pageManifest['dpi'], reason: '$name page $i');
          expect(
            _rotationName(info.rotation),
            pageManifest['rotation'],
            reason: '$name page $i rotation',
          );
          expect(info.gamma, closeTo(2.2, 1e-9), reason: '$name page $i gamma');
        }
      }
    });

    test('rejects files with a bad magic or truncated FORM', () {
      final valid = readDjvuFile('archival');
      expect(
        () => parseIffFile(Uint8List.fromList([0, 1, 2, 3, 4, 5])),
        throwsA(isA<DjvuFormatException>()),
      );
      final badMagic = Uint8List.fromList(valid)..[0] = 0;
      expect(
        () => parseIffFile(badMagic),
        throwsA(isA<DjvuFormatException>()),
      );
      final truncated = Uint8List.sublistView(valid, 0, 40);
      expect(
        () => parseIffFile(truncated),
        throwsA(isA<DjvuFormatException>()),
      );
    });
  });

  group('INCL', () {
    test('points at the shared symbol dictionary', () {
      for (final name in ['bilevel', 'layered']) {
        final form = parseIffFile(readDjvuFile(name));
        final sharedForms = [
          for (final chunk in form.chunks)
            if (chunk.id == 'FORM' && chunk.formType == 'DJVI')
              parseIffSubForm(chunk.data),
        ];
        expect(sharedForms, hasLength(1), reason: '$name shared FORM');
        expect(
          sharedForms.single.find('Djbz'),
          isNotNull,
          reason: '$name shared dictionary',
        );

        for (final page in _pageForms(form)) {
          final incl = page.find('INCL');
          expect(incl, isNotNull, reason: '$name page INCL');
          expect(inclTarget(incl!.data), 'dict0001.djvi');
        }

        // The INCL target is a component of the DIRM directory.
        final dirm = parseDirmPayload(readDjvuRef(name, 'root.DIRM.bin'));
        final components = dirm.components(bzzDecode);
        expect(
          components.map((c) => c.id),
          contains('dict0001.djvi'),
          reason: '$name DIRM target',
        );
      }
    });

    test('strips NUL and whitespace padding', () {
      final bytes = Uint8List.fromList([
        ...'dict0001.djvi'.codeUnits,
        0,
        0x20,
        0x0a,
        0,
      ]);
      expect(inclTarget(bytes), 'dict0001.djvi');
      expect(inclTarget(Uint8List.fromList([0, 0x20, 0])), isNull);
    });
  });

  group('INFO', () {
    test('clamps gamma and rejects future format versions', () {
      Uint8List info(List<int> bytes) => Uint8List.fromList(bytes);

      final dark = parseDjvuPageInfo(
        info([0, 100, 0, 200, 24, 0, 0x2c, 0x01, 0, 0]),
      );
      expect(dark.gamma, 0.3);
      expect(dark.dpi, 300);

      final bright = parseDjvuPageInfo(
        info([0, 100, 0, 200, 24, 0, 0x2c, 0x01, 200, 0]),
      );
      expect(bright.gamma, 5.0);

      final rotations = [
        (0, DjvuRotation.none),
        (1, DjvuRotation.ccw90),
        (2, DjvuRotation.rot180),
        (3, DjvuRotation.cw90),
      ];
      for (final (flags, expected) in rotations) {
        final parsed = parseDjvuPageInfo(
          info([0, 100, 0, 200, 24, 0, 0x2c, 0x01, 22, flags]),
        );
        expect(parsed.rotation, expected);
      }

      expect(
        () => parseDjvuPageInfo(info([0, 100, 0, 200, 50, 0])),
        throwsA(isA<DjvuFormatException>()),
      );
      expect(
        () => parseDjvuPageInfo(info([0, 100])),
        throwsA(isA<DjvuFormatException>()),
      );
    });
  });

  group('DIRM', () {
    test('decodes bundled directories and their offsets', () {
      for (final name in ['bilevel', 'layered', 'annotated']) {
        final file = readDjvuFile(name);
        final dirm = parseDirmPayload(readDjvuRef(name, 'root.DIRM.bin'));
        final manifest = readDjvuManifest(name);

        expect(dirm.isBundled, isTrue, reason: '$name bundled');
        expect(
          dirm.metadata,
          equals(readDjvuRef(name, 'root.DIRM.dec.bin')),
          reason: '$name metadata',
        );
        expect(
          dirm.offsets,
          hasLength(dirm.nfiles),
          reason: '$name offset table',
        );

        final components = dirm.components(bzzDecode);
        expect(components, hasLength(dirm.nfiles), reason: '$name components');
        expect(components.first.kind, DirmKind.shared, reason: '$name dictionary');
        expect(components.first.id, 'dict0001.djvi');
        expect(
          components.skip(1).map((c) => c.kind),
          everyElement(DirmKind.page),
          reason: '$name pages',
        );
        expect(
          components.skip(1).map((c) => c.id).toList(),
          [for (var i = 1; i <= manifest['pageCount']; i++) 'p${i.toString().padLeft(4, '0')}.djvu'],
          reason: '$name page ids',
        );

        // Every DIRM offset points at the FORM header of the component, and
        // the recorded size is the FORM header plus its payload.
        for (var i = 0; i < dirm.nfiles; i++) {
          final offset = dirm.offsets[i];
          expect(
            String.fromCharCodes(file, offset, offset + 4),
            'FORM',
            reason: '$name component $i offset',
          );
          final payloadLength =
              (file[offset + 4] << 24) |
              (file[offset + 5] << 16) |
              (file[offset + 6] << 8) |
              file[offset + 7];
          expect(
            components[i].size,
            payloadLength + 8,
            reason: '$name component $i size',
          );
        }
      }
    });

    test('rejects truncated chunks', () {
      expect(
        () => parseDirmPayload(Uint8List.fromList([0x81, 0, 2])),
        throwsA(isA<DjvuFormatException>()),
      );
      expect(
        () => parseDirmPayload(Uint8List(2)),
        throwsA(isA<DjvuFormatException>()),
      );
    });
  });
}
