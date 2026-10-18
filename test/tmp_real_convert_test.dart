// Temporary: convert the user's real files through the app code path.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/document_conversion/document_converter.dart';

Future<void> convert(String path, DocumentFormat format, String out) async {
  final sw = Stopwatch()..start();
  var scans = 0;
  final result = await convertDocumentFileToPdf(
    path,
    format: format,
    outputPath: out,
    onScanProgress: (done, total) {
      scans = total;
    },
  );
  final bytes = File(out).lengthSync();
  print(
    'RESULT $path: ${sw.elapsedMilliseconds}ms pages=${result.pageCount} '
    'outline=${result.outline.length} bytes=$bytes scans=$scans '
    'returnedPdf=${result.pdf.length}',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rudin.djvu', () async {
    await convert(
      '/tmp/opencode/import_test/rudin.djvu',
      DocumentFormat.djvu,
      '/tmp/opencode/import_test/out/rudin.djvu.pdf',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('rudin.epub', () async {
    await convert(
      '/tmp/opencode/import_test/rudin.epub',
      DocumentFormat.epub,
      '/tmp/opencode/import_test/out/rudin.epub.pdf',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
