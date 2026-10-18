// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Converter tests: every fixture is converted to PDF and checked against the
// oracle corpus — mask bytes, palette stencil geometry, embedded JPEGs, the
// outline tree and link annotations are all verified structurally and, where
// possible, bit for bit.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:saber/data/document_conversion/djvu/djvu_bitmap.dart';
import 'package:saber/data/document_conversion/djvu/djvu_converter.dart';
import 'package:saber/data/document_conversion/djvu/djvu_document.dart';
import 'package:saber/data/document_conversion/djvu/djvu_fgbz.dart';
import 'package:saber/data/document_conversion/scan_orientation.dart';

import 'djvu/djvu_fixture.dart';
import 'djvu/djvu_pdf_validate.dart';

DjvuConversionResult convertFixture(
  String name, {
  DjvuPdfOptions options = const DjvuPdfOptions(),
}) => convertDjvuToPdf(readDjvuFile(name), options: options);

ParsedPdf parseFixture(
  String name, {
  DjvuPdfOptions options = const DjvuPdfOptions(),
}) => parsePdf(convertFixture(name, options: options).pdf);

/// One page of a converted PDF: its object id and dictionary.
({int id, Map<String, Object?> dict}) pageAt(ParsedPdf pdf, int index) {
  final catalog = pdf.object((pdf.trailer['Root']! as PdfRef).id).dict;
  final pages = pdf.object((catalog['Pages']! as PdfRef).id).dict;
  final kids = (pages['Kids']! as List).cast<PdfRef>();
  return (id: kids[index].id, dict: pdf.object(kids[index].id).dict);
}

List<({int id, Map<String, Object?> dict})> pagesOf(ParsedPdf pdf) => [
  for (var i = 0; i < pageCountOf(pdf); i++) pageAt(pdf, i),
];

int pageCountOf(ParsedPdf pdf) {
  final catalog = pdf.object((pdf.trailer['Root']! as PdfRef).id).dict;
  final pages = pdf.object((catalog['Pages']! as PdfRef).id).dict;
  return (pages['Kids']! as List).length;
}

/// The page's `/XObject` resource dictionary, keyed by resource name.
Map<String, PdfRef> xobjectsOf(ParsedPdf pdf, Map<String, Object?> page) {
  final resources = page['Resources']! as Map<String, Object?>;
  final xobjects = resources['XObject']! as Map<String, Object?>;
  return xobjects.cast<String, PdfRef>();
}

/// The inflated content stream of [page] as text.
String contentOf(ParsedPdf pdf, Map<String, Object?> page) =>
    pdf.contentText(pdf.object((page['Contents']! as PdfRef).id));

/// Decodes one ImageMask XObject into its packed bitmap.
DjvuBitmap decodeMaskObject(ParsedPdf pdf, PdfRef ref) {
  final record = pdf.object(ref.id);
  final data = pdf.inflate(record);
  final width = record.dict['Width']! as int;
  final height = record.dict['Height']! as int;
  expect(data, hasLength(((width + 7) >> 3) * height));
  return DjvuBitmap.fromPacked(width, height, data);
}

/// One `q r g b rg sw 0 0 sh tx ty cm /MaskN Do Q` stencil command.
final _stencilCommand = RegExp(
  r'q (\d+(?:\.\d+)?) (\d+(?:\.\d+)?) (\d+(?:\.\d+)?) rg '
  r'(\d+(?:\.\d+)?) 0 0 (\d+(?:\.\d+)?) (\d+(?:\.\d+)?) (\d+(?:\.\d+)?) cm '
  r'/(Mask\d+) Do Q',
);

/// Reconstructs a palette page from its stencil commands and compares it with
/// the oracle mask, blit map and palette.
///
/// This pins the whole crop workflow: every stencil is placed back at its
/// pixel bounding box (via the `cm` transform), never overlaps another, and
/// the painted colour of every marked pixel equals its palette entry — the
/// strongest end-to-end check short of rasterizing the PDF.
void expectPaletteReconstruction(String name, int pageIndex) {
  final pdf = parseFixture(name);
  final pages = pagesOf(pdf);
  final info =
      (readDjvuManifest(name)['pages'] as List)[pageIndex]
          as Map<String, dynamic>;
  final width = info['width'] as int;
  final height = info['height'] as int;
  final dpi = (info['dpi'] as num).toDouble();
  final mask = readMaskFixture(name, pageIndex);
  final palette = parseFgbzPalette(readDjvuRef(name, 'p$pageIndex.FGbz.bin'));
  final document = DjvuDocument.parse(readDjvuFile(name));
  final (_, blitMap) = document.page(pageIndex).decodeMaskIndexed()!;

  final xobjects = xobjectsOf(pdf, pages[pageIndex].dict);
  final matches = _stencilCommand
      .allMatches(contentOf(pdf, pages[pageIndex].dict))
      .toList();
  expect(matches, isNotEmpty, reason: '$name p$pageIndex has stencils');

  // Rasterize every stencil command into one colour per page pixel.
  final raster = Uint32List(width * height);
  raster.fillRange(0, raster.length, 0xffffffff);
  var overlaps = 0;
  var colourMismatches = 0;
  var unmarkedPainted = 0;
  var firstProblem = '';

  void note(String message) {
    if (firstProblem.isEmpty) firstProblem = message;
  }

  for (final match in matches) {
    final r = (double.parse(match.group(1)!) * 255).round();
    final g = (double.parse(match.group(2)!) * 255).round();
    final b = (double.parse(match.group(3)!) * 255).round();
    final sw = double.parse(match.group(4)!);
    final sh = double.parse(match.group(5)!);
    final tx = double.parse(match.group(6)!);
    final ty = double.parse(match.group(7)!);
    final name0 = match.group(8)!;
    final plane = decodeMaskObject(pdf, xobjects[name0]!);

    // The `cm` transform maps the stencil back to a pixel box; both the box
    // size and the plane size come from the same bounding box.
    final px = (tx * dpi / 72.0).round();
    final py = height - ((ty + sh) * dpi / 72.0).round();
    final boxW = (sw * dpi / 72.0).round();
    final boxH = (sh * dpi / 72.0).round();
    expect(boxW, plane.width, reason: '$name p$pageIndex $name0 width');
    expect(boxH, plane.height, reason: '$name p$pageIndex $name0 height');

    for (var y = 0; y < plane.height; y++) {
      for (var x = 0; x < plane.width; x++) {
        if (!plane.get(x, y)) continue;
        final dx = px + x;
        final dy = py + y;
        if (dx < 0 || dx >= width || dy < 0 || dy >= height) {
          note('$name0 paints outside the page at ($dx, $dy)');
          continue;
        }
        final cell = dy * width + dx;
        if (raster[cell] != 0xffffffff) {
          overlaps++;
          note('stencils overlap at ($dx, $dy)');
          continue;
        }
        raster[cell] = (r << 16) | (g << 8) | b;
      }
    }
  }

  var marked = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final cell = y * width + x;
      final painted = raster[cell];
      if (!mask.get(x, y)) {
        if (painted != 0xffffffff) {
          unmarkedPainted++;
          note('unmarked pixel ($x, $y) painted 0x${painted.toRadixString(16)}');
        }
        continue;
      }
      marked++;
      final blit = blitMap[cell];
      final index = blit >= 0 && blit < palette.indices.length
          ? palette.indices[blit]
          : 0;
      final color = palette.colors[index];
      final want = (color.r << 16) | (color.g << 8) | color.b;
      if (painted != want) {
        colourMismatches++;
        note(
          'pixel ($x, $y): painted 0x${painted.toRadixString(16)}, '
          'want 0x${want.toRadixString(16)}',
        );
      }
    }
  }
  expect(marked, greaterThan(0), reason: '$name p$pageIndex mask is empty');
  expect(overlaps, 0, reason: '$name p$pageIndex: $firstProblem');
  expect(unmarkedPainted, 0, reason: '$name p$pageIndex: $firstProblem');
  expect(colourMismatches, 0, reason: '$name p$pageIndex: $firstProblem');
}

void main() {
  group('bilevel pages', () {
    test('mask-only page embeds the JB2 stencil bit for bit', () {
      final result = convertFixture('bilevel');
      final pdf = parsePdf(result.pdf);
      expect(result.pageCount, 3);
      expect(result.bookmarks, isEmpty);

      final pages = pagesOf(pdf);
      expect(pages, hasLength(3));
      for (var i = 0; i < 3; i++) {
        final page = pages[i].dict;
        expect(page['MediaBox'], [0, 0, 297.6, 384.0]);
        expect(page['Rotate'], isNull);
        expect(
          (page['Parent']! as PdfRef).id,
          (pdf.object(1).dict['Pages']! as PdfRef).id,
        );
        expect(page['Annots'], isNull, reason: 'no links on page $i');
        expect(
          contentOf(pdf, page),
          '0 0 0 rg\nq 297.6000 0 0 384.0000 0 0 cm /Im0 Do Q\n',
        );

        final xobjects = xobjectsOf(pdf, page);
        expect(xobjects.keys, ['Im0']);
        final im0 = pdf.object(xobjects['Im0']!.id);
        expect(im0.dict['ImageMask'], isTrue);
        expect(im0.dict['BitsPerComponent'], 1);
        expect(im0.dict['Decode'], [1, 0]);
        expect(im0.dict['Filter'], 'FlateDecode');
        expect([im0.dict['Width'], im0.dict['Height']], [1240, 1600]);
        expect(pdf.inflate(im0), readMaskFixture('bilevel', i).data);
      }
    });
  });

  group('palette pages', () {
    test('layered: stencils reconstruct the palette foreground', () {
      expectPaletteReconstruction('layered', 0);
      expectPaletteReconstruction('layered', 1);
    });

    test('archival: stencils reconstruct the palette foreground', () {
      expectPaletteReconstruction('archival', 0);
    });

    test('background stays at its native (subsampled) resolution', () {
      for (final (name, index, bgW, bgH) in [
        ('layered', 0, 104, 134),
        ('archival', 0, 207, 267),
      ]) {
        final pdf = parseFixture(name);
        final page = pageAt(pdf, index).dict;
        final im0 = pdf.object(xobjectsOf(pdf, page)['Im0']!.id);
        expect(
          [im0.dict['Width'], im0.dict['Height']],
          [bgW, bgH],
          reason: '$name p$index background resolution',
        );
        // The page transform scales it to the MediaBox instead of upsampling.
        expect(
          contentOf(pdf, page),
          startsWith('q 297.6000 0 0 384.0000 0 0 cm /Im0 Do Q\n'),
        );
      }
    });
  });

  group('continuous-tone pages', () {
    test('photo: a single background XObject, JPEG or Flate', () {
      final pdf = parseFixture('photo');
      final page = pageAt(pdf, 0).dict;
      expect(page['MediaBox'], [0, 0, 245.76, 184.32]);
      expect(
        contentOf(pdf, page),
        'q 245.7600 0 0 184.3200 0 0 cm /Im0 Do Q\n',
      );
      expect(page['Annots'], isNull);

      final xobjects = xobjectsOf(pdf, page);
      expect(xobjects.keys, ['Im0']);
      final im0 = pdf.object(xobjects['Im0']!.id);
      expect([im0.dict['Width'], im0.dict['Height']], [1024, 768]);
      expect(im0.dict['ColorSpace'], 'DeviceRGB');
      final filter = im0.dict['Filter'];
      if (filter == 'DCTDecode') {
        final jpeg = img.decodeJpg(im0.streamBytes)!;
        expect([jpeg.width, jpeg.height], [1024, 768]);
      } else {
        expect(filter, 'FlateDecode');
        expect(pdf.inflate(im0), hasLength(1024 * 768 * 3));
      }
    });

    test('photo: jpegQuality null pins the lossless RGB raster', () {
      const options = DjvuPdfOptions(jpegQuality: null);
      final pdf = parseFixture('photo', options: options);
      final im0 = pdf.object(
        xobjectsOf(pdf, pageAt(pdf, 0).dict)['Im0']!.id,
      );
      expect(im0.dict['Filter'], 'FlateDecode');
      expect(im0.dict['ColorSpace'], 'DeviceRGB');
      final background = DjvuDocument.parse(
        readDjvuFile('photo'),
      ).page(0).decodeBackground()!.toRgb();
      expect(pdf.inflate(im0), background.toRgbBytes());
    });

    test('grayscale: lossless output is a true DeviceGray raster', () {
      const options = DjvuPdfOptions(jpegQuality: null);
      final data = readDjvuFile('grayscale');
      final pdf = parsePdf(convertDjvuToPdf(data, options: options).pdf);
      final page = pageAt(pdf, 0).dict;
      expect(page['MediaBox'], [0, 0, 76.8, 57.6]);
      final im0 = pdf.object(xobjectsOf(pdf, page)['Im0']!.id);
      expect(im0.dict['Filter'], 'FlateDecode');
      expect(im0.dict['ColorSpace'], 'DeviceGray');
      expect(im0.dict['BitsPerComponent'], 8);
      final gray = DjvuDocument.parse(
        data,
      ).page(0).decodeBackground()!.toGray8();
      expect(pdf.inflate(im0), gray.data);
    });

    test('grayscale: adaptive policy still yields a decodable raster', () {
      final pdf = parseFixture('grayscale');
      final im0 = pdf.object(
        xobjectsOf(pdf, pageAt(pdf, 0).dict)['Im0']!.id,
      );
      expect([im0.dict['Width'], im0.dict['Height']], [320, 240]);
      final filter = im0.dict['Filter'];
      if (filter == 'DCTDecode') {
        // The JPEG candidate expands gray to RGB (the encoder has no
        // 1-component mode), so it is declared DeviceRGB.
        expect(im0.dict['ColorSpace'], 'DeviceRGB');
        final jpeg = img.decodeJpg(im0.streamBytes)!;
        expect([jpeg.width, jpeg.height], [320, 240]);
      } else {
        expect(filter, 'FlateDecode');
        expect(im0.dict['ColorSpace'], 'DeviceGray');
        expect(pdf.inflate(im0), hasLength(320 * 240));
      }
    });
  });

  group('JPEG backgrounds', () {
    test('bgjp: the original JPEG is embedded byte for byte', () {
      final data = readDjvuFile('bgjp');
      final pdf = parsePdf(convertDjvuToPdf(data).pdf);
      final page = pageAt(pdf, 0).dict;
      expect(page['MediaBox'], [0, 0, 1.44, 1.08]);

      final im0 = pdf.object(xobjectsOf(pdf, page)['Im0']!.id);
      expect(im0.dict['Filter'], 'DCTDecode');
      expect([im0.dict['Width'], im0.dict['Height']], [512, 384]);
      expect(im0.dict['ColorSpace'], 'DeviceRGB');
      final original = DjvuDocument.parse(data).page(0).rawChunk('BGjp')!;
      expect(im0.streamBytes, original);
    });
  });

  group('masked continuous foreground', () {
    /// Adjoins [fgChunks] to the `archival` page (mask + background), with
    /// the palette removed, so the continuous-tone foreground path is
    /// exercised.
    Uint8List archivalWithForeground(List<(String, List<int>)> fgChunks) {
      final archival = DjvuDocument.parse(readDjvuFile('archival')).page(0);
      return buildDjvuForm('DJVU', [
        for (final chunk in archival.chunks)
          if (chunk.id != 'FGbz') (chunk.id, chunk.data),
        ...fgChunks,
      ]);
    }

    test('FG44: multi-colour foreground becomes /Im1 with /Mask', () {
      final photo = DjvuDocument.parse(readDjvuFile('photo')).page(0);
      final bytes = archivalWithForeground([
        for (final chunk in photo.findChunks('BG44')) ('FG44', chunk.data),
      ]);
      final pdf = parsePdf(convertDjvuToPdf(bytes).pdf);
      final page = pageAt(pdf, 0).dict;
      final xobjects = xobjectsOf(pdf, page);
      expect(xobjects.keys.toList()..sort(), ['Im0', 'Im1']);
      expect(page['MediaBox'], [0, 0, 297.6, 384.0]);
      expect(
        contentOf(pdf, page),
        'q 297.6000 0 0 384.0000 0 0 cm /Im0 Do Q\n'
        'q 297.6000 0 0 384.0000 0 0 cm /Im1 Do Q\n',
      );

      // The masked image carries the page mask as its /Mask.
      final im1 = pdf.object(xobjects['Im1']!.id);
      expect(im1.dict['ColorSpace'], 'DeviceRGB');
      final maskRef = im1.dict['Mask']! as PdfRef;
      final maskRecord = pdf.object(maskRef.id);
      expect(maskRecord.dict['ImageMask'], isTrue);
      expect(pdf.inflate(maskRecord), readMaskFixture('archival', 0).data);
    });

    test('FGjp: the original JPEG passes through behind the mask', () {
      final data = readDjvuFile('bgjp');
      final bgjp = DjvuDocument.parse(data).page(0).rawChunk('BGjp')!;
      final bytes = archivalWithForeground([('FGjp', bgjp)]);
      final pdf = parsePdf(convertDjvuToPdf(bytes).pdf);
      final xobjects = xobjectsOf(pdf, pageAt(pdf, 0).dict);
      final im1 = pdf.object(xobjects['Im1']!.id);
      expect(im1.dict['Filter'], 'DCTDecode');
      expect([im1.dict['Width'], im1.dict['Height']], [512, 384]);
      expect(im1.streamBytes, bgjp);
      expect(im1.dict['Mask'], isA<PdfRef>());
    });
  });

  group('outline and links', () {
    test('annotated: NAVM bookmarks become a linked outline tree', () {
      final result = convertFixture('annotated');
      final pdf = parsePdf(result.pdf);
      final pages = pagesOf(pdf);
      final pageIds = [for (final page in pages) page.id];

      final catalog = pdf.object((pdf.trailer['Root']! as PdfRef).id).dict;
      expect(catalog['PageMode'], 'UseOutlines');
      final outlineRef = catalog['Outlines']! as PdfRef;
      final outline = pdf.object(outlineRef.id).dict;
      expect(outline['Type'], 'Outlines');
      expect(outline['Count'], 4);

      final first = pdf.object((outline['First']! as PdfRef).id).dict;
      expect(first['Title'], 'Chapter 1 — Beginning');
      expect(first['Parent'], outlineRef);
      expect(first['Dest'], [PdfRef(pageIds[0]), 'Fit']);
      expect(first['Prev'], isNull);
      expect(first['Count'], 2);
      final second = pdf.object((first['Next']! as PdfRef).id).dict;
      expect(second['Title'], 'Chapter 2 — End');
      expect(second['Dest'], [PdfRef(pageIds[2]), 'Fit']);
      expect(second['Next'], isNull);
      expect(second['First'], isNull);
      expect(second['Parent'], outlineRef);
      expect((outline['Last']! as PdfRef).id, (first['Next']! as PdfRef).id);

      final child1 = pdf.object((first['First']! as PdfRef).id).dict;
      expect(child1['Title'], 'Section 1.1');
      expect(child1['Dest'], [PdfRef(pageIds[0]), 'Fit']);
      expect(child1['Parent'], (outline['First']! as PdfRef));
      expect(child1['Prev'], isNull);
      final child2Id = (child1['Next']! as PdfRef).id;
      final child2 = pdf.object(child2Id).dict;
      expect(child2['Title'], 'Section 1.2');
      expect(child2['Dest'], [PdfRef(pageIds[1]), 'Fit']);
      expect(child2['Next'], isNull);
      expect(child2['Parent'], (outline['First']! as PdfRef));
      expect(first['Last'], PdfRef(child2Id));
      expect((child1['Next']! as PdfRef).id, child2Id);
    });

    test('annotated: ANTz areas become internal destinations and URIs', () {
      final pdf = parseFixture('annotated');
      final pages = pagesOf(pdf);
      final pageIds = [for (final page in pages) page.id];
      final areas = (readDjvuLinks('annotated', 0)!['areas'] as List)
          .cast<Map<String, dynamic>>();

      final annots = (pages[0].dict['Annots']! as List).cast<PdfRef>();
      expect(annots, hasLength(areas.length));
      for (var i = 0; i < areas.length; i++) {
        final annot = pdf.object(annots[i].id).dict;
        expect(annot['Type'], 'Annot');
        expect(annot['Subtype'], 'Link');
        expect(annot['Border'], [0, 0, 0]);

        final shape = areas[i]['shape'] as Map<String, dynamic>;
        const scale = 72.0 / 300.0; // annotated pages are 300 dpi
        final rect = annot['Rect']! as List;
        expect(rect[0], closeTo((shape['x'] as int) * scale, 1e-9));
        expect(rect[1], closeTo((shape['y'] as int) * scale, 1e-9));
        expect(
          rect[2],
          closeTo(((shape['x'] as int) + (shape['w'] as int)) * scale, 1e-9),
        );
        expect(
          rect[3],
          closeTo(((shape['y'] as int) + (shape['h'] as int)) * scale, 1e-9),
        );

        final url = areas[i]['url'] as String;
        if (url == '#page_2') {
          expect(annot['Dest'], [PdfRef(pageIds[1]), 'Fit']);
        } else if (url == '#page_3') {
          expect(annot['Dest'], [PdfRef(pageIds[2]), 'Fit']);
        } else {
          expect(annot['Dest'], isNull);
          expect(annot['A'], {'S': 'URI', 'URI': url});
        }
      }
      expect(pages[1].dict['Annots'], isNull);
      expect(pages[2].dict['Annots'], isNull);
    });
  });

  group('geometry and streaming', () {
    test('INFO rotation becomes /Rotate and blank pages stay blank', () {
      for (final (rotationByte, angle) in [(0, 0), (1, 270), (2, 180), (3, 90)]) {
        final info = Uint8List.fromList([
          0x00,
          0x64, // width 100
          0x00,
          0xc8, // height 200
          24, // version
          0xff, // single-byte version marker
          100,
          0, // dpi 100
          22, // gamma 2.2
          rotationByte,
        ]);
        final bytes = buildDjvuForm('DJVU', [('INFO', info)]);
        final pdf = parsePdf(convertDjvuToPdf(bytes).pdf);
        final page = pageAt(pdf, 0).dict;
        expect(page['MediaBox'], [0, 0, 72.0, 144.0]);
        if (angle == 0) {
          expect(page['Rotate'], isNull);
        } else {
          expect(page['Rotate'], angle);
        }
        expect(contentOf(pdf, page), '');
        expect(xobjectsOf(pdf, page), isEmpty);
        expect(page['Annots'], isNull);
      }
    });

    test('an empty catalog is rejected', () {
      // Bundled DIRM with zero components: a valid container, an empty
      // document.
      final document = DjvuDocument.parse(
        buildDjvuForm('DJVM', [('DIRM', Uint8List.fromList([0x80, 0, 0]))]),
      );
      expect(document.pageCount, 0);
      expect(
        () => convertDjvuDocumentToPdf(document),
        throwsA(isA<DjvuDocumentException>()),
      );
    });

    test('streaming writeDjvuPdf produces the same bytes', () {
      final data = readDjvuFile('annotated');
      final expected = convertDjvuToPdf(data);
      final builder = BytesBuilder(copy: false);
      final bookmarks = writeDjvuPdf(DjvuDocument.parse(data), builder.add);
      expect(builder.takeBytes(), expected.pdf);
      expect(
        [for (final bookmark in bookmarks) bookmark.title],
        [for (final bookmark in expected.bookmarks) bookmark.title],
      );
    });
  });

  group('scan orientation', () {
    // The bilevel fixture's pages carry an upright 1240x1600 text mask and a
    // plain INFO tag. Their JB2 masks share a dictionary, so a single page
    // cannot be rebuilt from the reference chunks alone; the tag byte is
    // doctored inside the real file instead, which keeps everything else
    // (including that dictionary) intact.
    Uint8List retaggedFixture(int rotationByte) {
      final bytes = Uint8List.fromList(readDjvuFile('bilevel'));
      final info = readDjvuRef('bilevel', 'p0.INFO.bin');
      const infoId = [0x49, 0x4e, 0x46, 0x4f]; // 'INFO'
      for (var i = 0; i + 8 <= bytes.length; i++) {
        if (bytes[i] != infoId[0] ||
            bytes[i + 1] != infoId[1] ||
            bytes[i + 2] != infoId[2] ||
            bytes[i + 3] != infoId[3]) {
          continue;
        }
        final length =
            (bytes[i + 4] << 24) |
            (bytes[i + 5] << 16) |
            (bytes[i + 6] << 8) |
            bytes[i + 7];
        if (length != info.length) continue;
        var matches = true;
        for (var j = 0; j < info.length; j++) {
          if (bytes[i + 8 + j] != info[j]) {
            matches = false;
            break;
          }
        }
        if (!matches) continue;
        bytes[i + 8 + info.length - 1] = rotationByte;
        return bytes;
      }
      throw StateError('no INFO chunk matching p0.INFO.bin');
    }

    test('an upright raster clears a bogus INFO rotation tag', () {
      for (final (bogus, angle) in [(1, 270), (3, 90)]) {
        // Control: with detection off, the tag is emitted as stored.
        final raw = parsePdf(
          convertDjvuToPdf(
            retaggedFixture(bogus),
            options: const DjvuPdfOptions(autoOrientScans: false),
          ).pdf,
        );
        expect(pageAt(raw, 0).dict['Rotate'], angle);

        // Detection on: the upright pixels win.
        final detected = parsePdf(convertDjvuToPdf(retaggedFixture(bogus)).pdf);
        expect(pageAt(detected, 0).dict['Rotate'], isNull);
      }
    });

    test('an already-upright page is left alone', () {
      final pdf = parsePdf(convertDjvuToPdf(retaggedFixture(0)).pdf);
      expect(pageAt(pdf, 0).dict['Rotate'], isNull);
    });

    test('djvuDisplayRotation only overrides what the pixels prove', () {
      int rotate(ScanOrientation orientation, int tag) =>
          djvuDisplayRotation(orientation, tag, autoOrient: true);

      expect(rotate(ScanOrientation.upright, 0), 0);
      expect(rotate(ScanOrientation.upright, 90), 0);
      expect(rotate(ScanOrientation.upright, 270), 0);
      expect(rotate(ScanOrientation.upright, 180), 180);
      expect(rotate(ScanOrientation.rotateClockwise, 0), 90);
      expect(rotate(ScanOrientation.rotateClockwise, 90), 90);
      expect(rotate(ScanOrientation.rotateClockwise, 270), 90);
      expect(rotate(ScanOrientation.rotateCounterClockwise, 0), 270);
      for (final tag in [0, 90, 180, 270]) {
        expect(rotate(ScanOrientation.unknown, tag), tag);
        expect(
          djvuDisplayRotation(ScanOrientation.upright, tag, autoOrient: false),
          tag,
        );
      }
    });
  });
}
