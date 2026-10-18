// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Pixel-exact tests for the IW44 decoder against the Rust reference corpus
// (`refs/<name>/…`, see test/data/document_conversion/fixtures/djvu/README.md).
// The reference PNGs were produced by the djvu-rs implementation, so every
// comparison here is exact — no tolerance.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:saber/data/document_conversion/djvu/djvu_bitmap.dart';
import 'package:saber/data/document_conversion/djvu/djvu_iff.dart';
import 'package:saber/data/document_conversion/djvu/djvu_iw44.dart';

import 'djvu/djvu_fixture.dart';

/// The BG44 chunk payloads for page [page] of fixture [name], in document
/// order.
///
/// The oracle stores the first chunk as `p<i>.BG44.bin` and the following
/// ones as `p<i>.BG44.1.bin`, `p<i>.BG44.2.bin`, …; the manifest's per-page
/// chunk list gives the count.
List<Uint8List> bg44Chunks(String name, int page) {
  final manifest = readDjvuManifest(name);
  final pages = manifest['pages'] as List<dynamic>;
  final chunks =
      (pages[page] as Map<String, dynamic>)['chunks'] as List<dynamic>;
  var count = 0;
  for (final chunk in chunks) {
    if ((chunk as List<dynamic>)[0] == 'BG44') count++;
  }
  return [
    for (var i = 0; i < count; i++)
      readDjvuRef(name, i == 0 ? 'p$page.BG44.bin' : 'p$page.BG44.$i.bin'),
  ];
}

/// Decodes every BG44 chunk of page [page] of fixture [name].
Iw44Image decodeBg44(String name, int page) {
  final image = Iw44Image();
  for (final chunk in bg44Chunks(name, page)) {
    image.decodeChunk(chunk);
  }
  return image;
}

/// Asserts that every RGB pixel of [actual] equals the 8-bit RGB PNG
/// [expected] (the reference `to_rgb()` output).
void expectRgbMatches(RgbaImage actual, img.Image expected, String label) {
  expect(actual.width, expected.width, reason: '$label: width');
  expect(actual.height, expected.height, reason: '$label: height');
  final want = expected.getBytes(order: img.ChannelOrder.rgb);
  var mismatches = 0;
  var maxDelta = 0;
  var first = '';
  for (var y = 0; y < actual.height; y++) {
    var a = y * actual.width * 4;
    var e = y * actual.width * 3;
    for (var x = 0; x < actual.width; x++) {
      for (var c = 0; c < 3; c++) {
        final d = (actual.data[a + c] - want[e + c]).abs();
        if (d > 0) {
          mismatches++;
          if (d > maxDelta) maxDelta = d;
          if (first.isEmpty) {
            first =
                'first mismatch at ($x, $y) channel $c: '
                'got ${actual.data[a + c]}, want ${want[e + c]}';
          }
        }
      }
      a += 4;
      e += 3;
    }
  }
  expect(
    mismatches,
    0,
    reason:
        '$label: $mismatches channel values differ '
        '(max delta $maxDelta; $first)',
  );
}

/// FNV-1a 64-bit hash over [bytes].
///
/// The expected `toGray8` constants below come from the Rust reference
/// implementation (`dump_gray8 <dir> <prefix>` decodes the same chunks with
/// `djvu_iw44::Iw44Image::to_gray8` and prints this same hash); the VM's
/// `int` wraps at 64 bits just like Rust's `u64`, so the literal matches.
int fnv1a64(Uint8List bytes) {
  var hash = 0xcbf29ce484222325;
  for (final b in bytes) {
    hash ^= b;
    hash *= 0x100000001b3;
  }
  return hash;
}

void main() {
  group('Iw44Image', () {
    test('layered pages decode chunk by chunk and match the reference bg', () {
      for (final page in [0, 1]) {
        final chunks = bg44Chunks('layered', page);
        expect(chunks, hasLength(10), reason: 'layered p$page BG44 count');

        final image = Iw44Image();
        for (final chunk in chunks) {
          image.decodeChunk(chunk); // Must not throw at any layer.
        }

        final expected = readPngFixture('refs/layered/p$page.bg.png');
        // The manifest reports bg [104, 134]; the BG44 header (and the
        // reference PNG) carry those dimensions, not the 1240x1600 page.
        expect(image.width, expected.width, reason: 'layered p$page width');
        expect(image.height, expected.height, reason: 'layered p$page height');
        expect(image.isColor, isTrue);
        expectRgbMatches(image.toRgb(), expected, 'layered p$page');
      }
    });

    test('archival page 0 matches the subsampled reference bg', () {
      final image = decodeBg44('archival', 0);
      final expected = readPngFixture('refs/archival/p0.bg.png');
      // The archival BG44 background is stored subsampled: 207x267.
      expect(image.width, 207);
      expect(image.height, 267);
      expect(image.width, expected.width);
      expect(image.height, expected.height);
      expectRgbMatches(image.toRgb(), expected, 'archival p0');
    });

    test('photo page 0 matches the reference bg', () {
      final image = decodeBg44('photo', 0);
      expect(image.width, 1024);
      expect(image.height, 768);
      expect(image.isColor, isTrue);
      expectRgbMatches(
        image.toRgb(),
        readPngFixture('refs/photo/p0.bg.png'),
        'photo p0',
      );
    });

    test('gray page 0 matches the reference bg and luma', () {
      final image = decodeBg44('gray', 0);
      final expected = readPngFixture('refs/gray/p0.bg.png');
      expectRgbMatches(image.toRgb(), expected, 'gray p0');

      // Despite the fixture's name, its BG44 stream is colour-format: the
      // first header selects the YCbCr codec and the picture has real
      // chroma (R and G differ by up to 169 in the reference PNG, which is
      // `toRgb()` output). So the PNG's red channel is *not* the Gray8
      // luma: `toGray8()` of a colour stream is clamp(Y + 128, 0, 255)
      // from the internal luma plane (a grayscale stream would instead
      // give 127 - Y). Pin the exact bytes against the Rust reference
      // implementation, which decoded these same chunks.
      expect(image.isColor, isTrue);
      final gray = image.toGray8();
      expect(gray.width, expected.width);
      expect(gray.height, expected.height);
      expect(gray.data, hasLength(expected.width * expected.height));
      expect(fnv1a64(gray.data), 0xa00aaf75df479a50, reason: 'gray p0');
      // The reference dump's sampled bytes, kept for readable failures.
      final n = gray.data.length;
      expect(gray.data[0], 154);
      expect(gray.data[1], 153);
      expect(gray.data[2], 153);
      expect(gray.data[n ~/ 4], 171);
      expect(gray.data[n ~/ 2], 182);
      expect(gray.data[3 * n ~/ 4], 196);
      expect(gray.data[n - 2], 193);
      expect(gray.data[n - 1], 193);
    });

    test('a wrong serial number is rejected', () {
      final chunks = bg44Chunks('layered', 0);
      final image = Iw44Image();
      image.decodeChunk(chunks[0]);
      // Repeating the first chunk is rejected instead of restarting.
      expect(
        () => image.decodeChunk(chunks[0]),
        throwsA(isA<Iw44Exception>()),
      );
      // Skipping ahead is rejected too: after chunk 1 the next serial is 2.
      image.decodeChunk(chunks[1]);
      expect(
        () => image.decodeChunk(chunks[3]),
        throwsA(isA<Iw44Exception>()),
      );
    });

    test('short chunks are rejected', () {
      final image = Iw44Image();
      expect(
        () => image.decodeChunk(Uint8List(0)),
        throwsA(isA<Iw44Exception>()),
      );
      expect(
        () => image.decodeChunk(Uint8List(1)),
        throwsA(isA<Iw44Exception>()),
      );
    });

    test('a subsequent chunk before the first is rejected', () {
      final image = Iw44Image();
      expect(
        () => image.decodeChunk(Uint8List.fromList([0x01, 0x01])),
        throwsA(isA<Iw44Exception>()),
      );
    });

    test('output conversion before any chunk is rejected', () {
      final image = Iw44Image();
      expect(() => image.toRgb(), throwsA(isA<Iw44Exception>()));
      expect(() => image.toGray8(), throwsA(isA<Iw44Exception>()));
      expect(image.width, 0);
      expect(image.height, 0);
    });

    test('zero-dimension headers are rejected', () {
      final image = Iw44Image();
      // serial=0, slices=1, major=0, minor=2, width=0, height=100, delay=0.
      expect(
        () => image.decodeChunk(
          Uint8List.fromList([0x00, 0x01, 0x00, 0x02, 0x00, 0x00, 0x00, 0x64, 0x00]),
        ),
        throwsA(isA<Iw44Exception>()),
      );
      // width=100, height=0.
      expect(
        () => image.decodeChunk(
          Uint8List.fromList([0x00, 0x01, 0x00, 0x02, 0x00, 0x64, 0x00, 0x00, 0x00]),
        ),
        throwsA(isA<Iw44Exception>()),
      );
      expect(image.width, 0);
      expect(image.height, 0);
    });

    test('a truncated first-chunk header is rejected', () {
      final image = Iw44Image();
      expect(
        () => image.decodeChunk(
          Uint8List.fromList([0x00, 0x01, 0x00, 0x02, 0x00]),
        ),
        throwsA(isA<Iw44Exception>()),
      );
    });

    test('layered page 0 TH44 thumbnail decodes', () {
      final file = parseIffFile(readDjvuFile('layered'));
      IffForm? page0;
      for (final chunk in file.chunks) {
        if (chunk.id == 'FORM' && chunk.formType == 'DJVU') {
          page0 = parseIffSubForm(chunk.data);
          break;
        }
      }
      expect(page0, isNotNull, reason: 'layered has a FORM:DJVU page 0');
      final thumbs = page0!.findAll('TH44');
      expect(thumbs, isNotEmpty, reason: 'page 0 carries a TH44 thumbnail');

      final thumb = Iw44Image();
      for (final chunk in thumbs) {
        thumb.decodeChunk(chunk.data);
      }
      // Structural checks only: the oracle does not dump a reference image
      // for TH44. The header of this thumbnail is 99x128.
      expect(thumb.width, 99);
      expect(thumb.height, 128);
      expect(thumb.isColor, isTrue);
      final rgb = thumb.toRgb();
      expect(rgb.width, 99);
      expect(rgb.height, 128);
      expect(thumb.toGray8().data, hasLength(99 * 128));
    });
  });
}
