// Temporary: render the synthetic sideways scan both ways and write PNGs.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:saber/data/document_conversion/epub/epub_converter.dart';
import 'package:saber/data/document_conversion/scan_orientation.dart';

import 'data/document_conversion/epub/epub_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('write direction samples', () async {
    final page = textLikePage();
    // Ground truth: the uncorrected page as generated (heading at top-left).
    File(
      '/tmp/opencode/import_test/dir/upright.png',
    ).writeAsBytesSync(img.encodePng(page));

    // Stored sideways the way the user's scans are (per the earlier
    // forensics: a clockwise turn makes them readable).
    final stored = img.copyRotate(page, angle: 270);
    File(
      '/tmp/opencode/import_test/dir/stored.png',
    ).writeAsBytesSync(img.encodePng(stored));

    for (final verdict in [
      (ScanOrientation.rotateClockwise, 'verdict_cw'),
      (ScanOrientation.rotateCounterClockwise, 'verdict_ccw'),
    ]) {
      final result = await convertEpubToPdf(
        buildScanEpub({
          'OEBPS/page1.jpg': scanJpeg(stored),
          'OEBPS/page2.jpg': scanJpeg(stored),
        }),
        options: EpubPdfOptions(
          scanOrientations: {
            'OEBPS/page1.jpg': verdict.$1,
            'OEBPS/page2.jpg': verdict.$1,
          },
        ),
      );
      File(
        '/tmp/opencode/import_test/dir/${verdict.$2}.pdf',
      ).writeAsBytesSync(result.pdf);
    }
  });
}
