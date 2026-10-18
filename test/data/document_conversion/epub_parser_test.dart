// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/document_conversion/epub/epub_parser.dart';

import 'epub/epub_test_utils.dart';

void main() {
  group('parseEpub', () {
    late EpubBook book;

    setUpAll(() {
      book = parseEpub(readEpubFixture('book.epub'));
    });

    test('reads the package metadata', () {
      expect(book.title, 'The Test Book');
      expect(book.author, 'A. Author');
      expect(book.language, 'en');
      expect(book.opfPath, 'EPUB/package.opf');
    });

    test('maps the manifest', () {
      expect(book.manifest, hasLength(7));
      final nav = book.manifestById['nav']!;
      expect(nav.href, 'EPUB/nav.xhtml');
      expect(nav.mediaType, 'application/xhtml+xml');
      expect(nav.properties, contains('nav'));
      expect(book.manifestById['pic']!.href, 'EPUB/images/pic.png');
      expect(book.manifestById['pic']!.mediaType, 'image/png');
    });

    test('keeps the spine in reading order', () {
      expect(book.spine, hasLength(3));
      expect(book.spine.map((item) => item.index), [0, 1, 2]);
      expect(book.spine.map((item) => item.item?.href), [
        'EPUB/text/ch1.xhtml',
        'EPUB/text/ch2.xhtml',
        'EPUB/text/ch3.xhtml',
      ]);
      expect(book.spine.every((item) => item.linear), isTrue);
    });

    test('parses the EPUB3 navigation document', () {
      expect(book.tocBasePath, 'EPUB/nav.xhtml');
      expect(book.toc.map((entry) => entry.title), [
        'Chapter 1 — Start',
        'Chapter 2 — Middle',
        'Chapter 3 — Unknown Fragment',
        'External Entry',
      ]);
      expect(book.toc.first.href, 'text/ch1.xhtml');
      expect(book.toc.first.children.map((entry) => entry.title), [
        'Section 1.1',
        'Section 1.2',
      ]);
      expect(book.toc.first.children.first.href, 'text/ch1.xhtml#sec-1-1');
    });

    test('parses the EPUB2 NCX document', () {
      final ncx = parseEpub(readEpubFixture('ncx.epub'));
      expect(ncx.title, 'NCX Book');
      expect(ncx.tocBasePath, 'EPUB/toc.ncx');
      expect(ncx.toc.single.title, 'Only Chapter');
      expect(ncx.toc.single.href, 'ch1.xhtml');
      expect(ncx.toc.single.children, isEmpty);
    });

    test('caps table-of-contents nesting', () {
      final nav = StringBuffer(
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Deep</title>'
        '</head><body><nav><ol>',
      );
      for (var i = 0; i < kEpubMaxTocDepth + 6; i++) {
        nav.write('<li><a href="ch1.xhtml#s$i">Level $i</a><ol>');
      }
      for (var i = 0; i < kEpubMaxTocDepth + 6; i++) {
        nav.write('</ol></li>');
      }
      nav.write('</ol></nav></body></html>');

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
            '<dc:identifier id="uid">urn:uuid:deep</dc:identifier>'
            '<dc:title>Deep</dc:title></metadata><manifest>'
            '<item id="nav" href="nav.xhtml" '
            'media-type="application/xhtml+xml" properties="nav"/>'
            '<item id="c1" href="ch1.xhtml" '
            'media-type="application/xhtml+xml"/></manifest>'
            '<spine><itemref idref="c1"/></spine></package>',
        'EPUB/nav.xhtml': nav.toString(),
      });
      final parsed = parseEpub(bytes);

      var depth = 0;
      var entries = parsed.toc;
      while (entries.isNotEmpty) {
        depth++;
        entries = entries.first.children;
      }
      expect(depth, lessThanOrEqualTo(kEpubMaxTocDepth));
      expect(depth, greaterThan(1));
    });

    test('rejects empty input', () {
      expect(
        () => parseEpub(Uint8List(0)),
        throwsA(
          isA<EpubConversionException>().having(
            (error) => error.message,
            'message',
            contains('empty'),
          ),
        ),
      );
    });

    test('rejects input that is not a ZIP archive', () {
      expect(
        () => parseEpub(Uint8List.fromList(ascii.encode('not a zip'))),
        throwsA(isA<EpubConversionException>()),
      );
    });
  });

  group('EpubArchive', () {
    test('looks up entries tolerantly', () {
      final archive = parseEpub(readEpubFixture('book.epub')).archive;
      expect(archive.findFile('EPUB/text/ch1.xhtml'), isNotNull);
      expect(archive.findFile('./EPUB/text/ch1.xhtml'), isNotNull);
      expect(archive.findFile('EPUB/TEXT/CH1.XHTML'), isNotNull);
      expect(archive.findFile('EPUB/text/%63h1.xhtml'), isNotNull);
      expect(archive.findFile('EPUB/missing.xhtml'), isNull);
      expect(archive.readFile('EPUB/images/pic.png'), isNotNull);
      expect(archive.readFile('EPUB/missing.png'), isNull);
    });
  });

  group('path helpers', () {
    test('resolveArchivePath resolves relative document paths', () {
      expect(
        resolveArchivePath('EPUB/text/ch1.xhtml', '../images/pic.png'),
        'EPUB/images/pic.png',
      );
      expect(
        resolveArchivePath('EPUB/text/ch1.xhtml', 'ch2.xhtml#ch2'),
        'EPUB/text/ch2.xhtml',
      );
      expect(
        resolveArchivePath('EPUB/nav.xhtml', 'text/ch1.xhtml'),
        'EPUB/text/ch1.xhtml',
      );
      expect(
        resolveArchivePath('EPUB/text/ch1.xhtml', '/EPUB/abs.xhtml'),
        'EPUB/abs.xhtml',
      );
      expect(
        resolveArchivePath('EPUB/text/ch1.xhtml', 'ch1.xhtml?q=1#frag'),
        'EPUB/text/ch1.xhtml',
      );
      expect(resolveArchivePath('', 'EPUB/package.opf'), 'EPUB/package.opf');
      expect(resolveArchivePath('ch1.xhtml', '../outside.xhtml'), isNull);
      expect(
        resolveArchivePath('EPUB/text/ch1.xhtml', 'https://example.com/a.png'),
        isNull,
      );
      expect(resolveArchivePath('EPUB/text/ch1.xhtml', ''), isNull);
      expect(resolveArchivePath('EPUB/text/ch1.xhtml', '#frag'), isNull);
    });

    test('splitHref splits path and fragment', () {
      expect(splitHref('a.xhtml#sec'), (path: 'a.xhtml', fragment: 'sec'));
      expect(splitHref('#sec').path, '');
      expect(splitHref('#sec').fragment, 'sec');
      expect(splitHref('a.xhtml').fragment, '');
      expect(splitHref('a.xhtml#a#b').fragment, 'a#b');
    });

    test('decodeHref percent-decodes and tolerates garbage', () {
      expect(decodeHref('%E2%80%94'), '—');
      expect(decodeHref('%20file%20name'), ' file name');
      expect(decodeHref('plain'), 'plain');
      expect(decodeHref('%zz'), '%zz');
    });

    test('hrefHasScheme detects absolute URLs', () {
      expect(hrefHasScheme('https://example.com/'), isTrue);
      expect(hrefHasScheme('mailto:reader@example.com'), isTrue);
      expect(hrefHasScheme('ch1.xhtml#x'), isFalse);
      expect(hrefHasScheme('#anchor'), isFalse);
      expect(hrefHasScheme('../images/pic.png'), isFalse);
    });

    test('isXhtmlMediaType accepts HTML/XML documents', () {
      expect(isXhtmlMediaType('application/xhtml+xml'), isTrue);
      expect(isXhtmlMediaType('TEXT/HTML'), isTrue);
      expect(isXhtmlMediaType('application/xml'), isTrue);
      expect(isXhtmlMediaType(''), isFalse);
      expect(isXhtmlMediaType('text/css'), isFalse);
      expect(isXhtmlMediaType('image/png'), isFalse);
    });
  });
}
