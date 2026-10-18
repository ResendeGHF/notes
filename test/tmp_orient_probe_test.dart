// Temporary probe: reproduce the tagged-page test and print internals.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/document_conversion/djvu/djvu_converter.dart';
import 'package:saber/data/document_conversion/djvu/djvu_document.dart';
import 'package:saber/data/document_conversion/scan_orientation.dart';

import 'data/document_conversion/djvu/djvu_fixture.dart';
import 'data/document_conversion/djvu/djvu_pdf_validate.dart';

void main() {
  test('tagged page internals', () {
    final info = Uint8List.fromList(readDjvuRef('bilevel', 'p0.INFO.bin'));
    info[info.length - 1] = 1;
    final bytes = buildDjvuForm('DJVU', [
      ('INFO', info),
      ('Sjbz', readDjvuRef('bilevel', 'p0.Sjbz.bin')),
    ]);
    final page = DjvuDocument.parse(bytes).page(0);
    print('rotation=${page.rotation} size=${page.width}x${page.height}');
    print('mask chunk=${page.rawChunk('Sjbz') != null} '
        'bg44=${page.bg44Chunks().length} bgjp=${page.rawChunk('BGjp') != null}');
    final mask = page.decodeMask();
    print('decoded mask=${mask?.width}x${mask?.height}');
    if (mask != null) {
      final grid = ScanInkGrid.sample(
        width: mask.width,
        height: mask.height,
        inkAt: (x, y) => mask.get(x, y) ? 1.0 : 0.0,
      );
      final score = scoreScanOrientationDetailed(grid);
      print(
        'score=${score.orientation} contrast=${score.contrast} '
        'row=${score.rowSignal} col=${score.colSignal}',
      );
    }
    for (final auto in [true, false]) {
      final pdf = parsePdf(
        convertDjvuToPdf(
          bytes,
          options: DjvuPdfOptions(autoOrientScans: auto),
        ).pdf,
      );
      final catalog = pdf.object((pdf.trailer['Root']! as PdfRef).id).dict;
      final pages = pdf.object((catalog['Pages']! as PdfRef).id).dict;
      final kids = (pages['Kids']! as List).cast<PdfRef>();
      print('auto=$auto rotate=${pdf.object(kids[0].id).dict['Rotate']}');
    }
  });
}
