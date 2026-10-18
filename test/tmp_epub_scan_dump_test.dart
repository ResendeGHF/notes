// Temporary probe: dump the converted scan EPUB's pages.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:saber/data/document_conversion/epub/epub_converter.dart';
import 'package:saber/data/document_conversion/scan_orientation.dart';

import 'data/document_conversion/epub/epub_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('dump', () async {
    final page = textLikePage();
    final storedCcw = scanJpeg(img.copyRotate(page, angle: 270));
    final epub = buildScanEpub({
      'OEBPS/page1.jpg': storedCcw,
      'OEBPS/page2.jpg': storedCcw,
    });
    final result = await convertEpubToPdf(
      epub,
      options: EpubPdfOptions(
        scanOrientations: {
          'OEBPS/page1.jpg': ScanOrientation.rotateClockwise,
          'OEBPS/page2.jpg': ScanOrientation.rotateClockwise,
        },
      ),
    );
    final pdf = parsePdf(result.pdf);
    final pages = pdfPageObjectIds(pdf);
    print('pageCount=${result.pageCount} pages=${pages.length}');
    for (var i = 0; i < pages.length; i++) {
      final dict = pdf.object(pages[i]).dict;
      print('--- page $i box=${dict['MediaBox']}');
      print(contentOf(pdf, dict));
    }
  });
}
