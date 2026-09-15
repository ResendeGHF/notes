import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/editor/editor_exporter.dart';

void main() {
  group('EditorExporter (PDF / export palette)', () {
    test('export line gray matches page default line color', () {
      expect(EditorExporter.exportDefaultLineGray, const Color(0xFF9E9E9E));
    });
  });
}
