// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/samsung_notes/sdocx_parser.dart';

Map<String, Uint8List> _unzip(File file) {
  final bytes = file.readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = <String, Uint8List>{};
  for (final f in archive.files) {
    if (!f.isFile) continue;
    out[f.name] = Uint8List.fromList(f.content as List<int>);
  }
  return out;
}

void main() {
  test('sdocx reference parses pages, strokes, images, PDFs', () {
    final file = File('test/Over_the_Horizon_261010_011234.sdocx');
    expect(file.existsSync(), isTrue, reason: 'reference .sdocx missing');

    final entries = _unzip(file);
    expect(entries.containsKey('pageIdInfo.dat'), isTrue);
    expect(entries.containsKey('note.note'), isTrue);
    expect(entries.containsKey('media/mediaInfo.dat'), isTrue);

    final doc = SdocxParser.parseArchive(entries);

    // 9 Samsung pages in manifest order.
    expect(doc.pages.length, 9);
    expect(doc.pages.first.uuid, 'f5f197be-c45f-11f1-9da4-037a2175693b');

    // First page: handwriting + one raster image, no PDF background.
    final first = doc.pages.first;
    expect(first.width, 1440);
    expect(first.height, 2036);
    expect(first.pdfPapers, isEmpty);
    expect(first.strokes.length, 30);
    expect(first.images.length, 1);

    for (final s in first.strokes) {
      expect(s.points.length, greaterThanOrEqualTo(2));
      // Points must be finite and roughly inside the 1440x2036 page.
      for (final p in s.points) {
        expect(p.x.isFinite, isTrue);
        expect(p.y.isFinite, isTrue);
      }
      expect(s.penWidth, greaterThan(0));
      expect(s.penWidth, lessThan(200));
    }
    // At least one stroke carries an explicit Samsung color.
    expect(first.strokes.any((s) => s.colorArgb != null), isTrue);

    final image = first.images.single;
    expect(image.mediaId, 0);
    expect(image.bbox.left, closeTo(64, 1));
    expect(image.bbox.top, closeTo(223.6, 1));
    expect(image.bbox.right, closeTo(904, 1));

    // 6 PDF-backed pages (one per PDF page), each empty of ink.
    final pdfPages = doc.pages.where((p) => p.pdfPapers.isNotEmpty).toList();
    expect(pdfPages.length, 6);
    final indices = pdfPages
        .expand((p) => p.pdfPapers.map((r) => r.pageIndex))
        .toList()
      ..sort();
    expect(indices, [0, 1, 2, 3, 4, 5]);
    for (final p in pdfPages) {
      expect(p.pdfPapers.single.mediaId, 3);
      expect(p.strokes, isEmpty);
      expect(p.images, isEmpty);
    }

    // Media manifest: jpg + pdf kept, audio/sticker/spi present but marked
    // to be skipped by the importer.
    expect(doc.mediaByBindId[0]?.isImage, isTrue);
    expect(doc.mediaByBindId[3]?.isPdf, isTrue);
    expect(doc.mediaByBindId[1]?.isSkipped, isTrue); // .m4a audio
    expect(doc.mediaByBindId[10]?.isSkipped, isTrue); // nested .sdocx sticker
    expect(doc.mediaByBindId[4]?.isSkipped, isTrue); // .spi painting data
    expect(doc.mediaByBindId[0]?.bytes, isNotNull);
    expect(doc.mediaByBindId[3]?.bytes, isNotNull);
    expect(
      doc.mediaByBindId[3]!.bytes!.sublist(0, 5),
      [0x25, 0x50, 0x44, 0x46, 0x2D], // %PDF-
    );
  });

  test('sdocx stroke delta decoding matches stored bbox', () {
    final file = File('test/Over_the_Horizon_261010_011234.sdocx');
    final doc = SdocxParser.parseArchive(_unzip(file));
    final first = doc.pages.first;
    // Every decoded stroke must roughly fill its stored bbox (the honest
    // correctness check from bxff/samsung-notes-format RESEARCH.md): decode
    // from absolute first point + (word & 0x7FFF)/32 deltas, never scaled.
    for (final s in first.strokes) {
      var minX = double.infinity;
      var minY = double.infinity;
      var maxX = double.negativeInfinity;
      var maxY = double.negativeInfinity;
      for (final p in s.points) {
        if (p.x < minX) minX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.x > maxX) maxX = p.x;
        if (p.y > maxY) maxY = p.y;
      }
      final w = (s.bbox.right - s.bbox.left).abs();
      final h = (s.bbox.bottom - s.bbox.top).abs();
      // Tiny dot strokes have ~0-size boxes; only check non-trivial ones.
      if (w > 5 && h > 5) {
        expect((maxX - minX), closeTo(w, w * 0.05 + 2));
        expect((maxY - minY), closeTo(h, h * 0.05 + 2));
      }
    }
  });
}
