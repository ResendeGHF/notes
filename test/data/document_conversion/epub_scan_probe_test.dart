// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// EPUB scan probe tests: encode a synthetic text-like page, run it through
// the engine decoders the way the pre-pass does, and check the verdict.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:saber/data/document_conversion/epub/epub_scan_probe.dart';
import 'package:saber/data/document_conversion/scan_orientation.dart';

import 'epub/epub_test_utils.dart';

/// A synthetic scan page: left-aligned dark bars with a ragged right edge.
img.Image textLikePage({int width = 260, int height = 200}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  final ink = img.ColorRgb8(20, 20, 20);
  img.fillRect(image, x1: 20, y1: 14, x2: 140, y2: 26, color: ink);
  const lengths = [200, 170, 210, 150, 190, 120, 205, 175, 160, 195];
  var y = 44;
  for (final length in lengths) {
    if (y + 7 >= height - 8) break;
    img.fillRect(
      image,
      x1: 20,
      y1: y,
      x2: 20 + length,
      y2: y + 7,
      color: ink,
    );
    y += 13;
  }
  return image;
}

/// A blank white page, as page separators in real scans.
img.Image blankPage({int width = 200, int height = 260}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  return image;
}

Future<ScanOrientation?> probe(img.Image image) async {
  final bytes = Uint8List.fromList(img.encodeJpg(image));
  return (await probeEncodedImageOrientation(bytes))?.orientation;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an upright scan reads as upright', () async {
    final score = await probeEncodedImageOrientation(
      Uint8List.fromList(img.encodePng(textLikePage())),
    );
    expect(score, isNotNull);
    expect(score!.orientation, ScanOrientation.upright);
    expect(score.contrast, greaterThan(kScanMinContrast));
  });

  test('a page stored with a clockwise turn asks for a counter turn', () async {
    // `copyRotate(angle: 90)` turns the image 90° clockwise, so display needs
    // the opposite.
    final stored = img.copyRotate(textLikePage(), angle: 90);
    expect(await probe(stored), ScanOrientation.rotateCounterClockwise);
  });

  test('a page stored with a counter-clockwise turn asks for a clockwise one',
      () async {
    final stored = img.copyRotate(textLikePage(), angle: 270);
    expect(await probe(stored), ScanOrientation.rotateClockwise);
  });

  test('the JPEG path matches the PNG path', () async {
    final upright = await probe(textLikePage());
    expect(upright, ScanOrientation.upright);
  });

  test('a blank page is inconclusive rather than rotated', () async {
    final score = await probeEncodedImageOrientation(
      Uint8List.fromList(img.encodePng(blankPage())),
    );
    expect(score, isNotNull);
    expect(score!.orientation, ScanOrientation.unknown);
    expect(score.isInconclusive, isFalse);
  });

  test('undecodable bytes yield no score', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
    expect(await probeEncodedImageOrientation(bytes), isNull);
  });

  test('a dissenting turn aligns with the document majority', () async {
    // A scan batch stores every page the same way. Five pages that read
    // sideways overwhelmingly agree on clockwise; one page whose cue picked
    // the other turn is noise, not a differently stored page.
    final storedCounter = Uint8List.fromList(
      img.encodeJpg(img.copyRotate(textLikePage(), angle: 270)),
    );
    final storedClockwise = Uint8List.fromList(
      img.encodeJpg(img.copyRotate(textLikePage(), angle: 90)),
    );
    final directory = Directory.systemTemp.createTempSync('epub_scan_probe');
    addTearDown(() => directory.deleteSync(recursive: true));
    final epub = File('${directory.path}/scans.epub')
      ..writeAsBytesSync(
        buildScanEpub({
          for (var i = 1; i <= 5; i++) 'OEBPS/scan$i.jpg': storedCounter,
          'OEBPS/scan6.jpg': storedClockwise,
        }),
      );

    final orientations = await detectEpubScanOrientations(epub.path);
    expect(orientations, hasLength(6));
    for (final orientation in orientations.values) {
      expect(orientation, ScanOrientation.rotateClockwise);
    }
  });

  test('a handful of pages keeps the direction each cue picked', () async {
    // Below the four-rotated-page floor there is no majority to defer to.
    final storedClockwise = Uint8List.fromList(
      img.encodeJpg(img.copyRotate(textLikePage(), angle: 90)),
    );
    final directory = Directory.systemTemp.createTempSync('epub_scan_probe');
    addTearDown(() => directory.deleteSync(recursive: true));
    final epub = File('${directory.path}/scan.epub')
      ..writeAsBytesSync(
        buildScanEpub({'OEBPS/scan1.jpg': storedClockwise}),
      );

    final orientations = await detectEpubScanOrientations(epub.path);
    expect(orientations, {
      'OEBPS/scan1.jpg': ScanOrientation.rotateCounterClockwise,
    });
  });
}
