// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Document-model tests: container parsing, catalog assembly, shared
// dictionaries and the page decode accessors, checked against the oracle
// manifests, masks and link tables in `fixtures/djvu/refs/`.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:saber/data/document_conversion/djvu/djvu_annotations.dart';
import 'package:saber/data/document_conversion/djvu/djvu_bitmap.dart';
import 'package:saber/data/document_conversion/djvu/djvu_bzz.dart';
import 'package:saber/data/document_conversion/djvu/djvu_document.dart';
import 'package:saber/data/document_conversion/djvu/djvu_fgbz.dart';
import 'package:saber/data/document_conversion/djvu/djvu_iff.dart';
import 'package:saber/data/document_conversion/djvu/djvu_jb2.dart';
import 'package:saber/data/document_conversion/djvu/djvu_navm.dart';

import 'djvu/djvu_fixture.dart';

/// Compares a decoded bitmap with an oracle mask, bit for bit.
void expectMask(DjvuBitmap actual, DjvuBitmap expected, {String? reason}) {
  expect(actual.width, expected.width, reason: reason);
  expect(actual.height, expected.height, reason: reason);
  expect(actual.data, expected.data, reason: reason);
}

/// The oracle records page-data chunks only (it omits INCL and TH44).
List<String> recordedChunkIds(DjvuPage page) => [
  for (final chunk in page.chunks)
    if (chunk.id != 'INCL' && chunk.id != 'TH44') chunk.id,
];

List<String> manifestChunkIds(Map<String, dynamic> page) => [
  for (final chunk in page['chunks'] as List) (chunk as List).first as String,
];

/// The BG44 payload lengths the oracle recorded for [page].
List<int> manifestBg44Lengths(Map<String, dynamic> page) => [
  for (final chunk in page['chunks'] as List)
    if ((chunk as List).first == 'BG44') chunk[1] as int,
];

/// Compares a decoded bookmark tree with the oracle manifest's.
void expectBookmark(DjvuBookmark actual, Map<String, dynamic> expected) {
  expect(actual.title, expected['title']);
  expect(actual.url, expected['url']);
  final children = (expected['children'] as List).cast<Map<String, dynamic>>();
  expect(actual.children, hasLength(children.length));
  for (var i = 0; i < children.length; i++) {
    expectBookmark(actual.children[i], children[i]);
  }
}

void main() {
  group('bundled catalogs', () {
    test('bilevel: one shared dictionary serves three page masks', () {
      final manifest = readDjvuManifest('bilevel');
      final doc = DjvuDocument.parse(readDjvuFile('bilevel'));
      expect(doc.pageCount, manifest['pageCount']);
      expect(doc.bookmarks, isEmpty);
      expect([for (final c in doc.globalChunks) c.id], ['DIRM']);

      final pages = (manifest['pages'] as List).cast<Map<String, dynamic>>();
      for (var i = 0; i < doc.pageCount; i++) {
        final page = doc.page(i);
        final info = pages[i];
        expect(page.index, i);
        expect(page.formType, 'DJVU');
        expect(page.width, info['width']);
        expect(page.height, info['height']);
        expect(page.dpi, info['dpi']);
        expect(page.rotation.name.toLowerCase(), info['rotation'].toString().toLowerCase());
        expect(recordedChunkIds(page), manifestChunkIds(info));
        expect(page.findChunks('INCL'), hasLength(1));
        expect(page.sharedDict, isNotNull);
        // All pages INCL the same component, so decoding reuses one instance.
        expect(page.sharedDict, same(doc.page(0).sharedDict));
        expectMask(page.decodeMask()!, readMaskFixture('bilevel', i), reason: 'page $i');
      }
    });

    test('layered: background, FGbz palette and thumbnails are exposed', () {
      final manifest = readDjvuManifest('layered');
      final pages = (manifest['pages'] as List).cast<Map<String, dynamic>>();
      final doc = DjvuDocument.parse(readDjvuFile('layered'));
      expect(doc.pageCount, 2);

      final page = doc.page(0);
      expect(page.findChunks('INCL'), hasLength(1));
      expect(page.sharedDict, isNotNull);
      expect(page.rawChunk('TH44'), isNotNull, reason: 'thumbnail present');
      expect(page.fg44Chunks(), isEmpty);
      expect(
        [for (final c in page.bg44Chunks()) c.length],
        manifestBg44Lengths(pages[0]),
      );

      final bg = page.decodeBackground()!;
      expect(bg.isColor, isTrue);
      final rgb = bg.toRgb();
      expect([rgb.width, rgb.height], [104, 134]);

      final palette = parseFgbzPalette(page.rawChunk('FGbz')!);
      final reference = readDjvuFgbz('layered', 0)!;
      expect(palette.colors, hasLength(147));
      expect(palette.indices, (reference['indices'] as List).cast<int>());
    });

    test('annotated: NAVM bookmarks and ANTz links match the oracle', () {
      final manifest = readDjvuManifest('annotated');
      final doc = DjvuDocument.parse(readDjvuFile('annotated'));
      expect(doc.pageCount, manifest['pageCount']);

      final expected = (manifest['bookmarks'] as List).cast<Map<String, dynamic>>();
      expect(doc.bookmarks, hasLength(expected.length));
      for (var i = 0; i < expected.length; i++) {
        expectBookmark(doc.bookmarks[i], expected[i]);
      }

      final links = doc.page(0).hyperlinks();
      final areas = (readDjvuLinks('annotated', 0)!['areas'] as List)
          .cast<Map<String, dynamic>>();
      expect(links, hasLength(areas.length));
      for (var i = 0; i < areas.length; i++) {
        final shape = areas[i]['shape'] as Map<String, dynamic>;
        expect(links[i].url, areas[i]['url']);
        expect(links[i].description, areas[i]['description']);
        final bbox = djvuShapeBbox(links[i].shape)!;
        expect(
          [bbox.x, bbox.y, bbox.width, bbox.height],
          [shape['x'], shape['y'], shape['w'], shape['h']],
          reason: 'area $i',
        );
      }
      expect(links[0].shape, isA<DjvuRectShape>());
      expect(links[1].shape, isA<DjvuRectShape>());
      expect(links[2].shape, isA<DjvuOvalShape>());
      expect(doc.page(1).hyperlinks(), isEmpty);
      expect(doc.page(2).hyperlinks(), isEmpty);
    });
  });

  group('single-page forms', () {
    test('archival: inline mask, subsampled background and FGbz', () {
      final manifest = readDjvuManifest('archival');
      final info = (manifest['pages'] as List).single as Map<String, dynamic>;
      final page = DjvuDocument.parse(readDjvuFile('archival')).page(0);
      expect(page.formType, 'DJVU');
      expect(page.sharedDict, isNull);
      expect(recordedChunkIds(page), manifestChunkIds(info));

      final (mask, blitMap) = page.decodeMaskIndexed()!;
      expectMask(mask, readMaskFixture('archival', 0));
      expect(blitMap, hasLength(1240 * 1600));
      expect(blitMap.fold<int>(-1, math.max) + 1, info['fgbzIndices']);

      final bg = page.decodeBackground()!;
      expect(bg.isColor, isTrue);
      final rgb = bg.toRgb();
      expect([rgb.width, rgb.height], [207, 267]);
      expect(page.extractForeground(), isNull);
    });

    test('photo: colour IW44 background and no mask', () {
      final page = DjvuDocument.parse(readDjvuFile('photo')).page(0);
      expect(page.decodeMask(), isNull);
      expect(page.fg44Chunks(), isEmpty);
      expect(page.extractForeground(), isNull);
      final bg = page.decodeBackground()!;
      expect(bg.isColor, isTrue);
      expect([bg.width, bg.height], [1024, 768]);
    });

    test('gray: BG44-only background decodes', () {
      final page = DjvuDocument.parse(readDjvuFile('gray')).page(0);
      // Despite the fixture's name, its BG44 stream is colour-format (see
      // djvu_iw44_test.dart); the document layer exposes what the chunks
      // carry.
      final bg = page.decodeBackground()!;
      expect(bg.isColor, isTrue);
      expect([bg.width, bg.height], [1024, 768]);
      expect(page.decodeMask(), isNull);
    });

    test('grayscale: grayscale-format IW44 decodes to the reference', () {
      final manifest = readDjvuManifest('grayscale');
      final info = (manifest['pages'] as List).single as Map<String, dynamic>;
      final page = DjvuDocument.parse(readDjvuFile('grayscale')).page(0);
      expect(page.sharedDict, isNull);
      expect([page.width, page.height, page.dpi], [
        info['width'],
        info['height'],
        info['dpi'],
      ]);
      expect(page.decodeMask(), isNull);
      expect(page.extractForeground(), isNull);

      final bg = page.decodeBackground()!;
      expect(bg.isColor, isFalse);
      final gray = bg.toGray8();
      expect([gray.width, gray.height], [info['width'], info['height']]);
      // For a grayscale stream, `toGray8` is `127 - Y` and `toRgb` writes that
      // same byte to every channel, so both must reproduce the oracle plane.
      final expected = readPngFixture('refs/grayscale/p0.bg.png');
      expect([expected.width, expected.height], [gray.width, gray.height]);
      final want = expected.getBytes(order: img.ChannelOrder.rgb);
      var mismatches = 0;
      for (var i = 0; i < gray.data.length; i++) {
        final v = gray.data[i];
        if (want[i * 3] != v || want[i * 3 + 1] != v || want[i * 3 + 2] != v) {
          mismatches++;
        }
      }
      expect(mismatches, 0, reason: 'grayscale p0 luma mismatches');
      final rgb = bg.toRgb();
      final (r, g, b) = rgb.getRgb(123, 45);
      final single = gray.data[45 * gray.width + 123];
      expect([r, g, b], [single, single, single]);
    });

    test('bgjp: JPEG background only', () {
      final data = readDjvuFile('bgjp');
      final page = DjvuDocument.parse(data).page(0);
      expect(page.formType, 'DJVU');
      expect([page.width, page.height, page.dpi], [512, 384, 25600]);
      expect(recordedChunkIds(page), ['INFO', 'BGjp']);
      expect(page.decodeMask(), isNull);
      expect(page.bg44Chunks(), isEmpty);
      expect(page.extractForeground(), isNull);
      expect(page.rawChunk('FGjp'), isNull);
    });
  });

  group('legacy IW44 forms', () {
    test('FORM:PM44 colour chunks become a 100 dpi page', () {
      final photoForm = parseIffFile(readDjvuFile('photo'));
      final chunks = [
        for (final c in photoForm.chunks)
          if (c.id == 'BG44') c,
      ];
      expect(chunks, hasLength(10));
      final bytes = buildDjvuForm('PM44', [
        for (final c in chunks) ('PM44', c.data),
      ]);
      final page = DjvuDocument.parse(bytes).page(0);
      expect(page.formType, 'PM44');
      expect([page.width, page.height, page.dpi], [1024, 768, 100]);
      expect(page.rotation, DjvuRotation.none);
      expect([for (final c in page.chunks) c.id], everyElement('PM44'));
      expect(page.bg44Chunks(), hasLength(10));

      // The same byte-exact chunks must decode to the same picture.
      final reference = DjvuDocument.parse(
        readDjvuFile('photo'),
      ).page(0).decodeBackground()!.toGray8();
      final legacy = page.decodeBackground()!.toGray8();
      expect(legacy.data, reference.data);
    });

    test('FORM:BM44/PM44 require a matching IW44 stream', () {
      // `grayscale` carries a grayscale-format stream, `photo` a colour one;
      // each legacy form accepts only its own kind.
      final grayChunks = [
        for (final c in parseIffFile(readDjvuFile('grayscale')).chunks)
          if (c.id == 'BG44') c,
      ];
      final gray = DjvuDocument.parse(
        buildDjvuForm('BM44', [for (final c in grayChunks) ('BM44', c.data)]),
      ).page(0);
      expect(gray.formType, 'BM44');
      expect(gray.decodeBackground()!.isColor, isFalse);

      expect(
        () => DjvuDocument.parse(
          buildDjvuForm('PM44', [
            for (final c in grayChunks) ('PM44', c.data),
          ]),
        ),
        throwsA(isA<DjvuDocumentException>()),
      );

      final photoChunks = [
        for (final c in parseIffFile(readDjvuFile('photo')).chunks)
          if (c.id == 'BG44') c,
      ];
      expect(
        () => DjvuDocument.parse(
          buildDjvuForm('BM44', [
            for (final c in photoChunks) ('BM44', c.data),
          ]),
        ),
        throwsA(isA<DjvuDocumentException>()),
      );
    });
  });

  group('indirect catalogs', () {
    /// Rebuilds `bilevel` as an indirect catalog: the DIRM metadata is reused
    /// verbatim, components are supplied by [resolver] instead of by offset.
    (Uint8List, Map<String, Uint8List>, List<DirmComponent>) indirectBilevel() {
      final bundled = parseIffFile(readDjvuFile('bilevel'));
      final dirm = parseDirmPayload(bundled.find('DIRM')!.data);
      final entries = dirm.components(bzzDecode);
      final subForms = [
        for (final c in bundled.chunks)
          if (c.id == 'FORM') c,
      ];
      expect(entries, hasLength(subForms.length));
      final components = <String, Uint8List>{
        for (var i = 0; i < entries.length; i++)
          entries[i].id: buildDjvuComponent(subForms[i]),
      };
      final indirectDirm = Uint8List.fromList([
        0, // flags: not bundled, so the offset table is absent
        (entries.length >> 8) & 0xff,
        entries.length & 0xff,
        ...dirm.metadata,
      ]);
      return (
        buildDjvuForm('DJVM', [('DIRM', indirectDirm)]),
        components,
        entries,
      );
    }

    test('resolves named components and their shared dictionaries', () {
      final (djvm, components, _) = indirectBilevel();
      final doc = DjvuDocument.parse(
        djvm,
        resolver: (name) => components[name],
      );
      expect(doc.pageCount, 3);
      for (var i = 0; i < 3; i++) {
        expect(doc.page(i).sharedDict, isNotNull, reason: 'page $i');
        expectMask(doc.page(i).decodeMask()!, readMaskFixture('bilevel', i));
      }
    });

    test('cannot open without a resolver', () {
      final (djvm, _, _) = indirectBilevel();
      expect(
        () => DjvuDocument.parse(djvm),
        throwsA(isA<DjvuDocumentException>()),
      );
    });

    test('missing pages fail the open, missing shared components degrade', () {
      final (djvm, components, entries) = indirectBilevel();
      final pageNames = {
        for (final entry in entries)
          if (entry.kind == DirmKind.page) entry.id,
      };
      expect(
        () => DjvuDocument.parse(
          djvm,
          resolver: (name) => pageNames.contains(name) ? null : components[name],
        ),
        throwsA(isA<DjvuDocumentException>()),
      );

      // A shared component that cannot be supplied is skipped; its pages open
      // and fail only when their dictionary is needed.
      final noDict = DjvuDocument.parse(
        djvm,
        resolver: (name) => name.endsWith('.djvi') ? null : components[name],
      );
      expect(noDict.pageCount, 3);
      expect(noDict.page(0).sharedDict, isNull);
      expect(
        () => noDict.page(0).decodeMask(),
        throwsA(isA<Jb2Exception>()),
      );
    });
  });

  group('malformed input', () {
    test('rejects bad containers and unsupported forms', () {
      expect(
        () => DjvuDocument.parse(Uint8List(0)),
        throwsA(isA<DjvuFormatException>()),
      );
      expect(
        () => DjvuDocument.parse(buildDjvuForm('DJVM', [])),
        throwsA(isA<DjvuDocumentException>()),
      );
      expect(
        () => DjvuDocument.parse(buildDjvuForm('XXXX', [])),
        throwsA(isA<DjvuDocumentException>()),
      );
      // A page without INFO, and a legacy form without image chunks.
      expect(
        () => DjvuDocument.parse(buildDjvuForm('DJVU', [])),
        throwsA(isA<DjvuDocumentException>()),
      );
      expect(
        () => DjvuDocument.parse(buildDjvuForm('BM44', [])),
        throwsA(isA<DjvuDocumentException>()),
      );
      expect(
        () => DjvuDocument.parse(buildDjvuForm('PM44', [])),
        throwsA(isA<DjvuDocumentException>()),
      );
    });
  });
}
