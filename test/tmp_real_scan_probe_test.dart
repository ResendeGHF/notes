// Temporary: run the EPUB scan probe on the user's real scans and dump the
// two candidate rotations for visual ground-truthing.
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:saber/data/document_conversion/epub/epub_scan_probe.dart';
import 'package:saber/data/document_conversion/scan_orientation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('real scan verdicts', () async {
    final bytes = File('/tmp/opencode/import_test/rudin.epub').readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = [
      'OEBPS/image_rsrc2HH.jpg',
      'OEBPS/image_rsrc2HJ.jpg',
      'OEBPS/image_rsrc2HK.jpg',
      'OEBPS/image_rsrc2SC.jpg',
      'OEBPS/image_rsrc34D.jpg',
      'OEBPS/image_rsrc2HE.jpg',
    ];
    for (final name in names) {
      final file = archive.findFile(name);
      if (file == null) {
        print('MISSING $name');
        continue;
      }
      final data = file.readBytes()!;
      final score = await probeEncodedImageOrientation(data);
      print(
        'SCAN $name: ${score?.orientation} contrast=${score?.contrast} '
        'row=${score?.rowSignal} col=${score?.colSignal}',
      );
      final decoded = img.decodeImage(data)!;
      final dir = '/tmp/opencode/import_test/real';
      Directory(dir).createSync(recursive: true);
      final short = name.split('/').last.replaceAll('.jpg', '');
      File('$dir/${short}_stored.png').writeAsBytesSync(
        img.encodePng(img.copyResize(decoded, width: 150)),
      );
      File('$dir/${short}_cw.png').writeAsBytesSync(
        img.encodePng(img.copyResize(img.copyRotate(decoded, angle: 90), width: 150)),
      );
      File('$dir/${short}_ccw.png').writeAsBytesSync(
        img.encodePng(img.copyResize(img.copyRotate(decoded, angle: 270), width: 150)),
      );
    }
    // ignore: unused_local_variable
    final _ = Uint8List(0);
  });
}
