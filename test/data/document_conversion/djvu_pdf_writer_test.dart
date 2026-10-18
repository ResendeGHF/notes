// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Tests for the streaming PDF writer, validated structurally with the
// minimal reader in `djvu_pdf_validate.dart` and, for streams, against the
// decompressed bytes of the fixture planes.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:saber/data/document_conversion/djvu/djvu_pdf_writer.dart';

import 'djvu/djvu_fixture.dart';
import 'djvu/djvu_pdf_validate.dart';

void main() {
  group('DjvuPdfWriter', () {
    test('writes a valid xref table and trailer', () {
      final builder = BytesBuilder();
      final writer = DjvuPdfWriter(builder.add);
      final catalogId = writer.reserveId();
      final pagesId = writer.reserveId();
      writer.writeObject(
        pagesId,
        utf8.encode('<< /Type /Pages /Kids [] /Count 0 >>'),
      );
      writer.writeObject(
        catalogId,
        utf8.encode('<< /Type /Catalog /Pages $pagesId 0 R >>'),
      );
      writer.finish();
      expect(writer.bytesWritten, builder.length);

      final pdf = parsePdf(builder.toBytes());
      expect(pdf.objectCount, 3);
      expect(pdf.xrefInUse, [false, true, true]);
      expect(pdf.xrefGenerations, [65535, 0, 0]);
      expect(pdf.trailer['Size'], 3);
      expect(pdf.trailer['Root'], const PdfRef(1));
      expect(pdf.object(catalogId).dict['Type'], 'Catalog');
      expect(pdf.object(pagesId).dict['Type'], 'Pages');
      expect(
        pdf.bytes.sublist(0, 8),
        utf8.encode('%PDF-1.4'),
      );
    });

    test('honours pre-allocated ids written out of order', () {
      final builder = BytesBuilder();
      final writer = DjvuPdfWriter(builder.add);
      final catalogId = writer.reserveId();
      final pagesId = writer.reserveId();
      final ids = [for (var i = 0; i < 3; i++) writer.reserveId()];
      // Write the last reserved object first.
      writer.writeObject(ids[2], utf8.encode('<< /Index 2 >>'));
      writer.writeObject(ids[0], utf8.encode('<< /Index 0 >>'));
      writer.writeObject(pagesId, utf8.encode('<< /Type /Pages /Count 0 >>'));
      writer.writeObject(ids[1], utf8.encode('<< /Index 1 >>'));
      writer.writeObject(catalogId, utf8.encode('<< /Type /Catalog >>'));
      writer.finish();

      final pdf = parsePdf(builder.toBytes());
      expect(pdf.objects.length, 5);
      for (final id in ids) {
        final record = pdf.object(id);
        expect(pdf.xrefOffsets[id], record.offset);
        expect(
          latin1.decode(
            pdf.bytes.sublist(record.offset, record.offset + 4 + '$id'.length),
          ),
          '$id 0 o',
        );
        expect(record.dict['Index'], ids.indexOf(id));
      }
    });

    test('rejects unreserved and duplicate ids', () {
      final writer = DjvuPdfWriter(BytesBuilder().add);
      expect(() => writer.writeObject(7, [0x30]), throwsArgumentError);
      final catalogId = writer.reserveId();
      final objectId = writer.reserveId();
      writer.writeObject(objectId, utf8.encode('null'));
      expect(() => writer.writeObject(objectId, utf8.encode('null')),
          throwsArgumentError);
      writer.writeObject(catalogId, utf8.encode('<< /Type /Catalog >>'));
      writer.finish();
      expect(writer.reserveId, throwsStateError);
      expect(writer.finish, throwsStateError);
    });

    test('rejects finishing without the root object', () {
      final writer = DjvuPdfWriter(BytesBuilder().add);
      final firstId = writer.reserveId();
      final secondId = writer.reserveId();
      expect(firstId, 1);
      writer.writeObject(secondId, utf8.encode('<< /Type /Pages >>'));
      expect(writer.finish, throwsStateError);
    });

    test('addFlateStream writes a stream with an explicit id', () {
      final builder = BytesBuilder();
      final writer = DjvuPdfWriter(builder.add);
      final catalogId = writer.reserveId();
      final streamId = writer.reserveId();
      writer.writeFlateStream(streamId, ' /Note (hi)', utf8.encode('body'));
      writer.writeObject(catalogId, utf8.encode('<< /Type /Catalog >>'));
      writer.finish();

      final pdf = parsePdf(builder.toBytes());
      final record = pdf.object(streamId);
      expect(record.dict['Filter'], 'FlateDecode');
      expect(record.dict['Note'], 'hi');
      expect(record.dict['Length'], record.streamBytes.length);
      expect(latin1.decode(pdf.inflate(record)), 'body');
    });
  });

  group('stream helpers', () {
    test('makePdfStream frames the data with an exact /Length', () {
      final data = Uint8List.fromList(
        List.generate(1000, (i) => (i * 37) & 0xff),
      );
      final body = makePdfStream(' /Custom true', data);
      final (:pdf, :ids) = pdfWithObjects([body]);
      final record = pdf.object(ids.single);
      expect(record.dict['Length'], 1000);
      expect(record.dict['Custom'], true);
      expect(record.streamBytes, orderedEquals(data));
      expect(pdf.bytes.sublist(record.offset, record.offset + 16),
          utf8.encode('3 0 obj\n<< /Leng'));
    });

    test('makeFlateStream round-trips through zlib', () {
      final data = Uint8List.fromList(
        List.generate(5000, (i) => (i ^ (i >> 3)) & 0xff),
      );
      final (:pdf, :ids) = pdfWithObjects([
        makeFlateStream(' /Type /XObject', data),
      ]);
      final record = pdf.object(ids.single);
      expect(record.dict['Filter'], 'FlateDecode');
      expect(record.dict['Type'], 'XObject');
      expect(record.dict['Length'], record.streamBytes.length);
      expect(pdf.inflate(record), orderedEquals(data));
    });

    test('makeDctStream passes JPEG bytes through unchanged', () {
      final jpeg = Uint8List.fromList([
        0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, //
        0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
        0xff, 0xd9,
      ]);
      final (:pdf, :ids) = pdfWithObjects([
        makeDctStream(' /Width 1 /Height 1', jpeg),
      ]);
      final record = pdf.object(ids.single);
      expect(record.dict['Filter'], 'DCTDecode');
      expect(record.streamBytes, orderedEquals(jpeg));
    });

    test('makeMaskBody matches the fixture mask bit for bit', () {
      final mask = readMaskFixture('bilevel', 0);
      expect(mask.width, 1240);
      expect(mask.height, 1600);
      final (:pdf, :ids) = pdfWithObjects([makeMaskBody(mask)]);
      final record = pdf.object(ids.single);
      expect(record.dict['Type'], 'XObject');
      expect(record.dict['Subtype'], 'Image');
      expect(record.dict['Width'], 1240);
      expect(record.dict['Height'], 1600);
      expect(record.dict['ImageMask'], true);
      expect(record.dict['BitsPerComponent'], 1);
      expect(record.dict['Decode'], [1, 0]);
      expect(record.dict['Filter'], 'FlateDecode');
      final raw = pdf.inflate(record);
      expect(raw.length, mask.stride * mask.height);
      expect(raw, orderedEquals(mask.data));
    });
  });

  group('raster bodies', () {
    test('keeps near-flat RGB rasters on FlateDecode', () {
      const width = 96;
      const height = 64;
      final rgb = Uint8List(width * height * 3)
        ..fillRange(0, width * height * 3, 0xef);
      final (:pdf, :ids) = pdfWithObjects([
        makeRgbImageBody(rgb, width, height),
      ]);
      final record = pdf.object(ids.single);
      expect(record.dict['Filter'], 'FlateDecode');
      expect(record.dict['ColorSpace'], 'DeviceRGB');
      expect(record.dict['BitsPerComponent'], 8);
      expect(record.dict['Width'], width);
      expect(record.dict['Height'], height);
      expect(pdf.inflate(record), orderedEquals(rgb));
    });

    test('never tries JPEG below the minimum raster size', () {
      // A detailed 32x32 raster: the ratio guard alone would try JPEG, the
      // size floor must keep it on FlateDecode.
      const width = 32;
      const height = 32;
      final rgb = Uint8List(width * height * 3);
      for (var i = 0; i < rgb.length; i++) {
        rgb[i] = (i * 97) & 0xff;
      }
      expect(rgb.length, lessThan(kRasterMinAdaptiveJpegBytes));
      final body = makeRgbImageBody(rgb, width, height);
      final (:pdf, :ids) = pdfWithObjects([body]);
      expect(pdf.object(ids.single).dict['Filter'], 'FlateDecode');
    });

    test('picks DCTDecode for a detailed fixture background', () {
      final image = readPngFixture('refs/photo/p0.bg.png');
      final rgb = rgbBytesOf(image);
      final flateBody = makeRgbImageBody(
        rgb,
        image.width,
        image.height,
        jpegQuality: null,
      );
      final adaptiveBody = makeRgbImageBody(rgb, image.width, image.height);
      expect(adaptiveBody.length, lessThan(flateBody.length));

      final (:pdf, :ids) = pdfWithObjects([adaptiveBody]);
      final record = pdf.object(ids.single);
      expect(record.dict['Filter'], 'DCTDecode');
      expect(record.dict['ColorSpace'], 'DeviceRGB');
      expect(record.dict['Width'], image.width);
      expect(record.dict['Height'], image.height);
      final decoded = img.decodeJpg(record.streamBytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, image.width);
      expect(decoded.height, image.height);
      expect(meanAbsRgbError(rgb, decoded), lessThan(10));
    });

    test('adaptive: false always encodes JPEG', () {
      final gray = Uint8List(48 * 48)..fillRange(0, 48 * 48, 0x80);
      final body = makeGrayImageBody(
        gray,
        48,
        48,
        adaptive: false,
      );
      final (:pdf, :ids) = pdfWithObjects([body]);
      final record = pdf.object(ids.single);
      expect(record.dict['Filter'], 'DCTDecode');
      // The bundled JPEG encoder only writes 3-component streams, so the
      // grayscale candidate is declared DeviceRGB.
      expect(record.dict['ColorSpace'], 'DeviceRGB');
    });

    test('keeps near-flat grayscale rasters on DeviceGray FlateDecode', () {
      const width = 160;
      const height = 120;
      final gray = Uint8List(width * height);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          gray[y * width + x] = (x < width ~/ 2) ? 0xf8 : 0x10;
        }
      }
      final (:pdf, :ids) = pdfWithObjects([
        makeGrayImageBody(gray, width, height),
      ]);
      final record = pdf.object(ids.single);
      expect(record.dict['Filter'], 'FlateDecode');
      expect(record.dict['ColorSpace'], 'DeviceGray');
      expect(record.dict['BitsPerComponent'], 8);
      expect(pdf.inflate(record), orderedEquals(gray));
    });

    test('picks JPEG for a detailed grayscale raster', () {
      final image = readPngFixture('refs/photo/p0.bg.png');
      final gray = Uint8List(image.width * image.height);
      for (var y = 0, i = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final p = image.getPixel(x, y);
          gray[i++] =
              (p.r.toInt() * 299 + p.g.toInt() * 587 + p.b.toInt() * 114) ~/
                  1000;
        }
      }
      final flateBody = makeGrayImageBody(
        gray,
        image.width,
        image.height,
        jpegQuality: null,
      );
      final adaptiveBody = makeGrayImageBody(gray, image.width, image.height);
      expect(adaptiveBody.length, lessThan(flateBody.length));

      final (:pdf, :ids) = pdfWithObjects([adaptiveBody]);
      final record = pdf.object(ids.single);
      expect(record.dict['Filter'], 'DCTDecode');
      final decoded = img.decodeJpg(record.streamBytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, image.width);
      expect(meanAbsGrayError(gray, decoded), lessThan(10));
    });
  });

  group('formatting', () {
    test('fmtPt writes exact zero and four decimals otherwise', () {
      expect(fmtPt(0), '0');
      expect(fmtPt(12.5), '12.5000');
      expect(fmtPt(595.2756), '595.2756');
      expect(fmtPt(1234.56789), '1234.5679');
    });

    test('fmtRgComponent short-circuits 0 and 255', () {
      expect(fmtRgComponent(0), '0');
      expect(fmtRgComponent(255), '1');
      expect(fmtRgComponent(128), '0.5020');
      expect(fmtRgComponent(1), '0.0039');
      expect(fmtRgComponent(254), '0.9961');
    });

    test('pdfStringLiteral escapes ASCII literal syntax', () {
      expect(pdfStringLiteral('plain'), '(plain)');
      expect(pdfStringLiteral(''), '()');
      expect(pdfStringLiteral(r'a(b)c\d'), r'(a\(b\)c\\d)');
      expect(pdfStringLiteral('line\nbreak\ttab'), r'(line\nbreak\ttab)');
    });

    test('non-ASCII and escaped strings round-trip through the parser', () {
      const strings = [
        'Chapter 1 — Beginning',
        'Ünïcödé (parens) \\ slashes',
        '日本語のテキスト',
        'emoji 📕 and 𝔘𝔫𝔦𝔠𝔬𝔡𝔢',
        'line\nfeed\tand(r)escapes',
      ];
      final (:pdf, :ids) = pdfWithObjects([
        utf8.encode(
          '<< ${[
            for (var i = 0; i < strings.length; i++)
              '/K$i ${pdfStringLiteral(strings[i])}',
          ].join(' ')} >>',
        ),
      ]);
      final dict = pdf.object(ids.single).dict;
      for (var i = 0; i < strings.length; i++) {
        expect(dict['K$i'], strings[i]);
      }
    });
  });

  group('validator', () {
    test('rejects corrupted startxref', () {
      final (:pdf, :ids) = pdfWithObjects([utf8.encode('<< /X 1 >>')]);
      expect(ids, isNotEmpty);
      final bytes = Uint8List.fromList(pdf.bytes);
      final marker = utf8.encode('startxref\n${pdf.xrefOffset}\n');
      final index = _indexOf(bytes, marker);
      expect(index, greaterThan(0));
      bytes[index + marker.length - 2] =
          bytes[index + marker.length - 2] == 0x30 ? 0x39 : 0x30;
      expect(() => parsePdf(bytes), throwsA(isA<PdfFormatException>()));
    });

    test('rejects a corrupted stream length', () {
      final data = Uint8List.fromList(List.filled(300, 0x41));
      final (:pdf, :ids) = pdfWithObjects([
        makeFlateStream('', data),
      ]);
      expect(ids, isNotEmpty);
      final bytes = Uint8List.fromList(pdf.bytes);
      final marker = utf8.encode('/Length ${pdf.object(ids.single).streamBytes.length}');
      final index = _indexOf(bytes, marker);
      expect(index, greaterThan(0));
      bytes[index + marker.length - 1] =
          bytes[index + marker.length - 1] == 0x39 ? 0x38 : 0x39;
      expect(() => parsePdf(bytes), throwsA(isA<PdfFormatException>()));
    });

    test('rejects trailing garbage', () {
      final (:pdf, :ids) = pdfWithObjects([utf8.encode('<< /X 1 >>')]);
      final bytes = Uint8List.fromList([...pdf.bytes, 0x58]);
      expect(() => parsePdf(bytes), throwsA(isA<PdfFormatException>()));
    });
  });

  group('integration', () {
    test('emits a realistic two-page document that parses cleanly', () {
      final builder = BytesBuilder();
      final writer = DjvuPdfWriter(builder.add);
      final catalogId = writer.reserveId();
      final pagesId = writer.reserveId();
      final outlineId = writer.reserveId();
      final outlineItemIds = [writer.reserveId(), writer.reserveId()];
      final pageIds = [writer.reserveId(), writer.reserveId()];

      final mask = readMaskFixture('bilevel', 0);
      final imgId = writer.addObject(makeMaskBody(mask));
      final annotUri = writer.addObject(
        utf8.encode(
          '<< /Type /Annot /Subtype /Link'
          ' /Rect [10.0000 20.0000 30.0000 40.0000] /Border [0 0 0]'
          ' /A << /S /URI /URI ${pdfStringLiteral('https://example.com/a(b)')} >> >>',
        ),
      );
      final annotDest = writer.addObject(
        utf8.encode(
          '<< /Type /Annot /Subtype /Link'
          ' /Rect [1.0000 2.0000 3.0000 4.0000] /Border [0 0 0]'
          ' /Dest [${pageIds[1]} 0 R /Fit] >>',
        ),
      );
      final pageWidth = fmtPt(1240 * 72 / 300);
      final pageHeight = fmtPt(1600 * 72 / 300);
      final content0 = writer.addFlateStream(
        '',
        utf8.encode('0 0 0 rg\nq $pageWidth 0 0 $pageHeight 0 0 cm /Im0 Do Q\n'),
      );
      final content1 = writer.addFlateStream('', utf8.encode(''));
      final annots = [annotUri, annotDest]
          .map((id) => ' $id 0 R')
          .join();
      writer.writeObject(
        pageIds[0],
        utf8.encode(
          '<< /Type /Page /Parent $pagesId 0 R'
          ' /MediaBox [0 0 $pageWidth $pageHeight]'
          ' /Contents $content0 0 R'
          ' /Resources << /XObject << /Im0 $imgId 0 R >> >>'
          ' /Annots [$annots ] >>',
        ),
      );
      writer.writeObject(
        pageIds[1],
        utf8.encode(
          '<< /Type /Page /Parent $pagesId 0 R'
          ' /MediaBox [0 0 $pageWidth $pageHeight]'
          ' /Contents $content1 0 R /Resources << >> >>',
        ),
      );

      final titles = ['Chapter 1 — Beginning', 'Chapter 2'];
      final firstItem = outlineItemIds[0];
      final lastItem = outlineItemIds[1];
      writer.writeObject(
        outlineItemIds[0],
        utf8.encode(
          '<< /Title ${pdfStringLiteral(titles[0])} /Parent $outlineId 0 R'
          ' /Next ${outlineItemIds[1]} 0 R /Dest [${pageIds[0]} 0 R /Fit] >>',
        ),
      );
      writer.writeObject(
        outlineItemIds[1],
        utf8.encode(
          '<< /Title ${pdfStringLiteral(titles[1])} /Parent $outlineId 0 R'
          ' /Prev ${outlineItemIds[0]} 0 R /Dest [${pageIds[1]} 0 R /Fit] >>',
        ),
      );
      writer.writeObject(
        outlineId,
        utf8.encode(
          '<< /Type /Outlines /First $firstItem 0 R /Last $lastItem 0 R'
          ' /Count 2 >>',
        ),
      );

      final kids = pageIds.map((id) => '$id 0 R').join(' ');
      writer.writeObject(
        pagesId,
        utf8.encode('<< /Type /Pages /Kids [$kids ] /Count 2 >>'),
      );
      writer.writeObject(
        catalogId,
        utf8.encode(
          '<< /Type /Catalog /Pages $pagesId 0 R'
          ' /Outlines $outlineId 0 R /PageMode /UseOutlines >>',
        ),
      );
      writer.finish();

      final pdf = parsePdf(builder.toBytes());
      expect(pdf.objectCount, 13);
      expect(pdf.trailer['Root'], const PdfRef(1));

      final pages = pdf.object(pagesId).dict;
      expect(pages['Count'], 2);
      expect(pages['Kids'], [PdfRef(pageIds[0]), PdfRef(pageIds[1])]);

      final page0 = pdf.object(pageIds[0]).dict;
      expect(page0['MediaBox'], [0, 0, 297.6, 384.0]);
      expect(page0['Rotate'], isNull);
      expect(page0['Annots'], [PdfRef(annotUri), PdfRef(annotDest)]);
      final uri = pdf.object(annotUri).dict['A'] as Map<String, Object?>;
      expect(uri['URI'], 'https://example.com/a(b)');
      expect(pdf.object(annotDest).dict['Dest'], [PdfRef(pageIds[1]), 'Fit']);

      expect(
        pdf.contentText(pdf.object(content0)),
        '0 0 0 rg\nq 297.6000 0 0 384.0000 0 0 cm /Im0 Do Q\n',
      );
      final img0 = pdf.object(imgId);
      expect(img0.dict['ImageMask'], true);
      expect(pdf.inflate(img0), orderedEquals(mask.data));

      final catalog = pdf.object(catalogId).dict;
      expect(catalog['PageMode'], 'UseOutlines');
      expect(catalog['Outlines'], const PdfRef(3));
      final outline = pdf.object(outlineId).dict;
      expect(outline['Type'], 'Outlines');
      expect(outline['Count'], 2);
      expect(outline['First'], PdfRef(firstItem));
      expect(pdf.object(firstItem).dict['Title'], titles[0]);
      expect(pdf.object(lastItem).dict['Title'], titles[1]);
      expect(pdf.object(firstItem).dict['Next'], PdfRef(lastItem));
      expect(pdf.object(lastItem).dict['Prev'], PdfRef(firstItem));
    });
  });
}

/// Builds a minimal valid PDF whose objects 3.. are [bodies], then parses it.
({ParsedPdf pdf, List<int> ids}) pdfWithObjects(List<List<int>> bodies) {
  final builder = BytesBuilder();
  final writer = DjvuPdfWriter(builder.add);
  final catalogId = writer.reserveId();
  final pagesId = writer.reserveId();
  final ids = [for (final _ in bodies) writer.reserveId()];
  for (var i = 0; i < bodies.length; i++) {
    writer.writeObject(ids[i], bodies[i]);
  }
  writer.writeObject(pagesId, utf8.encode('<< /Type /Pages /Count 0 >>'));
  writer.writeObject(
    catalogId,
    utf8.encode('<< /Type /Catalog /Pages $pagesId 0 R >>'),
  );
  writer.finish();
  return (pdf: parsePdf(builder.toBytes()), ids: ids);
}

/// Packed RGB bytes of [image] (3 per pixel, row-major).
Uint8List rgbBytesOf(img.Image image) {
  final rgb = Uint8List(image.width * image.height * 3);
  for (var y = 0, i = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      rgb[i++] = pixel.r.toInt();
      rgb[i++] = pixel.g.toInt();
      rgb[i++] = pixel.b.toInt();
    }
  }
  return rgb;
}

/// Mean absolute per-channel error between packed RGB and a decoded image.
double meanAbsRgbError(Uint8List rgb, img.Image decoded) {
  var sum = 0;
  var n = 0;
  for (var y = 0, i = 0; y < decoded.height; y++) {
    for (var x = 0; x < decoded.width; x++) {
      final pixel = decoded.getPixel(x, y);
      sum += (rgb[i++] - pixel.r.toInt()).abs();
      sum += (rgb[i++] - pixel.g.toInt()).abs();
      sum += (rgb[i++] - pixel.b.toInt()).abs();
      n += 3;
    }
  }
  return sum / n;
}

/// Mean absolute error between 8-bit luminance and a decoded image's red channel.
double meanAbsGrayError(Uint8List gray, img.Image decoded) {
  var sum = 0;
  var n = 0;
  for (var y = 0, i = 0; y < decoded.height; y++) {
    for (var x = 0; x < decoded.width; x++) {
      sum += (gray[i++] - decoded.getPixel(x, y).r.toInt()).abs();
      n += 1;
    }
  }
  return sum / n;
}

int _indexOf(Uint8List haystack, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}
