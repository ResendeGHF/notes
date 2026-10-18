// Temporary: inspect how the cover SVG parses.
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/document_conversion/epub/epub_parser.dart';

void main() {
  test('cover svg parse', () {
    final bytes = File('/tmp/opencode/import_test/rudin.epub').readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final file = archive.findFile('OEBPS/part0000.xhtml')!;
    final text = String.fromCharCodes(file.content as List<int>);
    final document = parseEpubHtml(text)!;
    final svgs = document.querySelectorAll('svg');
    print('svg elements: ${svgs.length}');
    for (final svg in svgs) {
      print('svg localName=${svg.localName} attrs=${svg.attributes}');
      print('  querySelectorAll(image)=${svg.querySelectorAll('image').length}');
      print('  querySelectorAll(*)=${svg.querySelectorAll('*').map((e) => '${e.localName}[${e.attributes}]').toList()}');
      for (final child in svg.children) {
        print('  child localName=${child.localName} attrs=${child.attributes}');
      }
    }
    print('body children: ${document.body?.children.map((e) => e.localName).toList()}');
    final div = document.querySelector('div');
    print('div children: ${div?.children.map((e) => '${e.localName}(${e.attributes})').toList()}');
    // ignore: unused_local_variable
    final _ = Uint8List(0);
  });
}
