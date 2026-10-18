// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:saber/data/document_conversion/epub/epub_converter.dart';
import 'package:saber/data/document_conversion/epub/epub_parser.dart';
import 'package:saber/data/document_conversion/scan_orientation.dart';

import 'epub/epub_test_utils.dart';

void main() {
  group('convertEpubToPdf', () {
    late EpubConversionResult result;
    late ParsedPdf pdf;
    late Map<String, int> destinations;
    late List<ParsedPdfOutline> outline;
    late List<ParsedPdfLink> links;

    setUpAll(() async {
      result = await convertEpubToPdf(
        readEpubFixture('book.epub'),
        options: readEpubFonts(),
      );
      pdf = parsePdf(result.pdf);
      destinations = pdfNamedDestinations(pdf);
      outline = pdfOutline(pdf);
      links = pdfLinks(pdf);
    });

    test('writes a structurally valid PDF', () {
      expect(
        ascii.decode(result.pdf.sublist(0, 5)),
        '%PDF-',
      );
      expect(result.pageCount, pdfPageObjectIds(pdf).length);
      expect(result.pageCount, greaterThan(10));
      expect(pdf.objectCount, greaterThan(result.pageCount));
    });

    test('records the EPUB metadata', () {
      final info = pdfInfo(pdf)!;
      expect(info['Title'], 'The Test Book');
      expect(info['Author'], 'A. Author');
    });

    test('builds the outline from the navigation document', () {
      expect(outline.map((node) => node.title), [
        'Chapter 1 — Start',
        'Chapter 2 — Middle',
        'Chapter 3 — Unknown Fragment',
      ]);
      expect(outline.first.children.map((node) => node.title), [
        'Section 1.1',
        'Section 1.2',
      ]);
      // External table-of-contents entries have no page to point at.
      final titles = <String>[];
      void collect(List<ParsedPdfOutline> nodes) {
        for (final node in nodes) {
          titles.add(node.title);
          collect(node.children);
        }
      }

      collect(outline);
      expect(titles, isNot(contains('External Entry')));
      // An entry whose fragment does not exist falls back to the chapter.
      expect(outline.last.pageIndex, greaterThan(outline[1].pageIndex));
      for (final node in outline) {
        expect(node.pageIndex, inInclusiveRange(0, result.pageCount - 1));
      }
    });

    test('anchors outline entries at the first page of their block', () {
      // Section 1.1 is the start of a paragraph that spans many pages, so its
      // named destination is the first painted page, not the last.
      final sections = outline.first.children;
      expect(sections[0].pageIndex, outline.first.pageIndex);
      expect(sections[1].pageIndex, greaterThan(sections[0].pageIndex + 3));

      expect(destinations['ch_0_id_sec-1-1'], outline.first.pageIndex);
      expect(destinations['ch_0_id_sec-1-2'], sections[1].pageIndex);
      expect(destinations['ch_1_top'], outline[1].pageIndex);
      expect(destinations['ch_2_top'], outline[2].pageIndex);
    });

    test('returns the same outline as the PDF', () {
      void compare(
        List<EpubOutlineEntry> app,
        List<ParsedPdfOutline> file,
      ) {
        expect(app.map((entry) => entry.title), file.map((entry) => entry.title));
        expect(
          app.map((entry) => entry.pageIndex),
          file.map((entry) => entry.pageIndex),
        );
        for (var i = 0; i < app.length; i++) {
          compare(app[i].children ?? const [], file[i].children);
        }
      }

      compare(result.outline, outline);
    });

    test('resolves internal links to named destinations', () {
      final gotos = links
          .where((link) => link.destination != null)
          .toList();
      expect(gotos.map((link) => link.destination), [
        'ch_0_id_sec-1-2',
        'ch_1_id_ch2',
      ]);
      for (final link in gotos) {
        expect(destinations, contains(link.destination));
      }
      expect(
        destinations[gotos[0].destination!],
        outline.first.children[1].pageIndex,
      );
      expect(destinations[gotos[1].destination!], outline[1].pageIndex);
    });

    test('keeps external links as URI annotations', () {
      expect(
        links
            .where((link) => link.url != null)
            .map((link) => link.url)
            .toSet(),
        {'https://example.com/read'},
      );
      // Two internal links plus the two rectangles of the wrapped external
      // link; the stylesheet link has no destination and is dropped.
      expect(links, hasLength(4));
      expect(
        links.any((link) => link.destination == null && link.url == null),
        isFalse,
      );
    });

    test('embeds the chapter image', () {
      final images = pdfImages(pdf);
      expect(images, hasLength(1));
      expect(images.single['Width'], 4);
      expect(images.single['Height'], 3);
    });
  });

  test('converts an EPUB2 NCX table of contents', () async {
    final result = await convertEpubToPdf(
      readEpubFixture('ncx.epub'),
      options: readEpubFonts(),
    );
    final pdf = parsePdf(result.pdf);
    final outline = pdfOutline(pdf);
    expect(outline.map((node) => node.title), ['Only Chapter']);
    expect(outline.single.pageIndex, 0);
    expect(pdfPageObjectIds(pdf), hasLength(result.pageCount));
  });

  test('converts without custom fonts', () async {
    final bytes = buildEpubZip({
      'META-INF/container.xml':
          '<?xml version="1.0"?><container version="1.0" '
          'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
          '<rootfiles><rootfile full-path="EPUB/package.opf" '
          'media-type="application/oebps-package+xml"/></rootfiles>'
          '</container>',
      'EPUB/package.opf':
          '<?xml version="1.0"?><package '
          'xmlns="http://www.idpf.org/2007/opf" version="3.0" '
          'unique-identifier="uid"><metadata '
          'xmlns:dc="http://purl.org/dc/elements/1.1/">'
          '<dc:identifier id="uid">urn:uuid:plain</dc:identifier>'
          '<dc:title>Plain</dc:title></metadata><manifest>'
          '<item id="c1" href="ch1.xhtml" '
          'media-type="application/xhtml+xml"/></manifest>'
          '<spine><itemref idref="c1"/></spine></package>',
      'EPUB/ch1.xhtml':
          '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
          '<title>Plain</title></head><body><h1>Plain</h1>'
          '<p>ASCII only.</p></body></html>',
    });
    final result = await convertEpubToPdf(bytes);
    expect(result.pageCount, 1);
    expect(result.outline, isEmpty);
  });

  test('renders an SVG cover whose raster is namespaced', () async {
    // Scanned fixed-layout EPUBs carry the page raster in an SVG that only
    // provides the page box, and the reference is `xlink:href` — a namespaced
    // attribute that plain lookups on package:html miss.
    final cover = img.Image(width: 40, height: 60);
    img.fill(cover, color: img.ColorRgb8(255, 255, 255));
    img.fillRect(
      cover,
      x1: 8,
      y1: 10,
      x2: 32,
      y2: 20,
      color: img.ColorRgb8(0, 0, 0),
    );
    final result = await convertEpubToPdf(
      buildEpubZip(
        {
          'META-INF/container.xml':
              '<?xml version="1.0"?><container version="1.0" '
              'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
              '<rootfiles><rootfile full-path="EPUB/package.opf" '
              'media-type="application/oebps-package+xml"/></rootfiles>'
              '</container>',
          'EPUB/package.opf':
              '<?xml version="1.0"?><package '
              'xmlns="http://www.idpf.org/2007/opf" version="3.0" '
              'unique-identifier="uid"><metadata '
              'xmlns:dc="http://purl.org/dc/elements/1.1/">'
              '<dc:identifier id="uid">urn:uuid:cover</dc:identifier>'
              '<dc:title>Cover</dc:title></metadata><manifest>'
              '<item id="c1" href="cover.xhtml" '
              'media-type="application/xhtml+xml"/>'
              '<item id="img" href="cover.jpg" media-type="image/jpeg"/>'
              '</manifest><spine><itemref idref="c1"/></spine></package>',
          'EPUB/cover.xhtml':
              '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
              '<title>Cover</title></head><body>'
              '<svg xmlns="http://www.w3.org/2000/svg" '
              'xmlns:xlink="http://www.w3.org/1999/xlink" '
              'viewBox="0 0 40 60">'
              '<image xlink:href="cover.jpg" width="40" height="60"/>'
              '</svg></body></html>',
        },
        files: {'EPUB/cover.jpg': scanJpeg(cover)},
      ),
    );
    expect(result.pageCount, 1);
    expect(result.outline, isEmpty);
    final images = pdfImages(parsePdf(result.pdf));
    expect(images, hasLength(1));
    expect(images.single['Width'], 40);
    expect(images.single['Height'], 60);
  });

  test('converts in an isolate', () async {
    final bytes = readEpubFixture('book.epub');
    final fonts = readEpubFonts();
    final isolated = await Isolate.run(
      () => convertEpubToPdf(bytes, options: fonts),
    );
    final reference = await convertEpubToPdf(bytes, options: fonts);
    expect(isolated.pageCount, reference.pageCount);
    expect(
      isolated.outline.map((entry) => entry.title),
      reference.outline.map((entry) => entry.title),
    );
  });

  group('scan orientations', () {
    // A landscape scan page, plus the same page stored sideways the two ways
    // (`copyRotate` turns clockwise for positive angles).
    late Uint8List storedCw;
    late Uint8List storedCcw;
    late Uint8List portrait;

    setUpAll(() {
      final page = textLikePage();
      storedCw = scanJpeg(img.copyRotate(page, angle: 90));
      storedCcw = scanJpeg(img.copyRotate(page, angle: 270));
      portrait = scanJpeg(textLikePage(width: 200, height: 260));
    });

    Future<ParsedPdf> convert(
      Map<String, Uint8List> images, [
      Map<String, ScanOrientation> orientations = const {},
    ]) async {
      final result = await convertEpubToPdf(
        buildScanEpub(images),
        options: EpubPdfOptions(scanOrientations: orientations),
      );
      return parsePdf(result.pdf);
    }

    test('a chapter of sideways landscape scans gets landscape pages', () async {
      final pdf = await convert(
        {'OEBPS/page1.jpg': storedCcw, 'OEBPS/page2.jpg': storedCcw},
        {
          'OEBPS/page1.jpg': ScanOrientation.rotateClockwise,
          'OEBPS/page2.jpg': ScanOrientation.rotateClockwise,
        },
      );
      expect(pdfPageObjectIds(pdf), hasLength(2));
      for (var i = 0; i < 2; i++) {
        final page = pageAt(pdf, i).dict;
        final box = (page['MediaBox']! as List).cast<num>();
        expect(box[2], greaterThan(box[3]), reason: 'page $i is landscape');
        // 90° clockwise on screen is rotateBox(-pi/2), whose matrix prints as
        // `0 -1 1 0` (the writer trims cos(-pi/2) to 0).
        expect(contentOf(pdf, page), contains('0 -1 1 0 '));
      }
    });

    test('without corrections the scans stay sideways on portrait pages', () async {
      final pdf = await convert({
        'OEBPS/page1.jpg': storedCcw,
        'OEBPS/page2.jpg': storedCcw,
      });
      final pages = [
        for (final id in pdfPageObjectIds(pdf)) pdf.object(id).dict,
      ];
      expect(pages, isNotEmpty);
      for (final page in pages) {
        final box = (page['MediaBox']! as List).cast<num>();
        expect(box[2], lessThan(box[3]));
        expect(contentOf(pdf, page), isNot(contains('0 -1 1 0 ')));
        expect(contentOf(pdf, page), isNot(contains('0 1 -1 0 ')));
      }
      expect(pdfImages(pdf), hasLength(2));
    });

    test('the map direction decides which way a scan is turned', () async {
      final pdf = await convert(
        {'OEBPS/page1.jpg': storedCw, 'OEBPS/page2.jpg': storedCw},
        {
          'OEBPS/page1.jpg': ScanOrientation.rotateCounterClockwise,
          'OEBPS/page2.jpg': ScanOrientation.rotateCounterClockwise,
        },
      );
      expect(pdfPageObjectIds(pdf), hasLength(2));
      for (var i = 0; i < 2; i++) {
        expect(contentOf(pdf, pageAt(pdf, i).dict), contains('0 1 -1 0 '));
      }
    });

    test('one sideways scan alone keeps the chapter portrait', () async {
      final pdf = await convert(
        {'OEBPS/page1.jpg': storedCcw},
        {'OEBPS/page1.jpg': ScanOrientation.rotateClockwise},
      );
      final page = pageAt(pdf, 0).dict;
      final box = (page['MediaBox']! as List).cast<num>();
      expect(box[2], lessThan(box[3]));
      expect(contentOf(pdf, page), contains('0 -1 1 0 '));
    });

    test('an upright portrait page keeps the chapter portrait', () async {
      final pdf = await convert(
        {
          'OEBPS/page1.jpg': storedCcw,
          'OEBPS/page2.jpg': storedCcw,
          'OEBPS/figure.jpg': portrait,
        },
        {
          'OEBPS/page1.jpg': ScanOrientation.rotateClockwise,
          'OEBPS/page2.jpg': ScanOrientation.rotateClockwise,
          'OEBPS/figure.jpg': ScanOrientation.upright,
        },
      );
      expect(pdfPageObjectIds(pdf), hasLength(3));
      for (var i = 0; i < 3; i++) {
        final page = pageAt(pdf, i).dict;
        final box = (page['MediaBox']! as List).cast<num>();
        expect(box[2], lessThan(box[3]), reason: 'page $i is portrait');
      }
      // The sideways scans are still turned; the upright page is untouched.
      expect(contentOf(pdf, pageAt(pdf, 0).dict), contains('0 -1 1 0 '));
      expect(contentOf(pdf, pageAt(pdf, 2).dict), isNot(contains('0 -1 1 0 ')));
    });
  });

  group('rejects malformed input', () {
    const container = '<?xml version="1.0"?><container version="1.0" '
        'xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>'
        '<rootfile full-path="EPUB/package.opf" '
        'media-type="application/oebps-package+xml"/></rootfiles></container>';

    Future<void> expectMessage(
      Uint8List bytes,
      String message,
    ) async {
      await expectLater(
        convertEpubToPdf(bytes),
        throwsA(
          isA<EpubConversionException>().having(
            (error) => error.message,
            'message',
            contains(message),
          ),
        ),
      );
    }

    test('empty file', () async {
      await expectMessage(Uint8List(0), 'empty');
    });

    test('truncated archives are rejected', () async {
      // The archive reader may either reject the damaged ZIP or read an empty
      // archive; both must surface as a conversion error.
      await expectLater(
        convertEpubToPdf(readEpubFixture('book.epub').sublist(0, 60)),
        throwsA(isA<EpubConversionException>()),
      );
    });

    test('missing container', () async {
      await expectMessage(buildEpubZip({}), 'Missing META-INF/container.xml');
    });

    test('container without a rootfile', () async {
      await expectMessage(
        buildEpubZip({
          'META-INF/container.xml':
              '<?xml version="1.0"?><container version="1.0" '
              'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
              '<rootfiles/></container>',
        }),
        'has no rootfile',
      );
    });

    test('missing package document', () async {
      await expectMessage(
        buildEpubZip({'META-INF/container.xml': container}),
        'Missing package document',
      );
    });

    test('malformed package document', () async {
      await expectMessage(
        buildEpubZip({
          'META-INF/container.xml': container,
          'EPUB/package.opf': '<<< not xml',
        }),
        'Malformed package document',
      );
    });

    test('package without a manifest or spine', () async {
      await expectMessage(
        buildEpubZip({
          'META-INF/container.xml': container,
          'EPUB/package.opf':
              '<?xml version="1.0"?><package '
              'xmlns="http://www.idpf.org/2007/opf" version="3.0" '
              'unique-identifier="uid"><metadata '
              'xmlns:dc="http://purl.org/dc/elements/1.1/">'
              '<dc:identifier id="uid">urn:uuid:empty</dc:identifier>'
              '<dc:title>Empty</dc:title></metadata>'
              '<manifest/><spine/></package>',
        }),
        'no manifest or spine',
      );
    });

    test('spine referencing missing files', () async {
      await expectMessage(
        buildEpubZip({
          'META-INF/container.xml': container,
          'EPUB/package.opf':
              '<?xml version="1.0"?><package '
              'xmlns="http://www.idpf.org/2007/opf" version="3.0" '
              'unique-identifier="uid"><metadata '
              'xmlns:dc="http://purl.org/dc/elements/1.1/">'
              '<dc:identifier id="uid">urn:uuid:missing</dc:identifier>'
              '<dc:title>Missing</dc:title></metadata><manifest>'
              '<item id="c1" href="gone.xhtml" '
              'media-type="application/xhtml+xml"/></manifest>'
              '<spine><itemref idref="c1"/></spine></package>',
        }),
        'no readable spine documents',
      );
    });
  });
}
