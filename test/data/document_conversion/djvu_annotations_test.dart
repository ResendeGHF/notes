// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/document_conversion/djvu/djvu_annotations.dart';
import 'package:saber/data/document_conversion/djvu/djvu_bzz.dart';
import 'package:saber/data/document_conversion/djvu/djvu_color.dart';
import 'package:saber/data/document_conversion/djvu/djvu_iff.dart';

import 'djvu/djvu_fixture.dart';

/// Compares a parsed shape against the oracle's `links.json` representation.
void _expectShape(DjvuShape actual, Map<String, dynamic> expected) {
  switch (expected['kind'] as String) {
    case 'rect':
      expect(actual, isA<DjvuRectShape>());
      final rect = actual as DjvuRectShape;
      expect(
        [rect.x, rect.y, rect.width, rect.height],
        [expected['x'], expected['y'], expected['w'], expected['h']],
      );
    case 'oval':
      expect(actual, isA<DjvuOvalShape>());
      final oval = actual as DjvuOvalShape;
      expect(
        [oval.x, oval.y, oval.width, oval.height],
        [expected['x'], expected['y'], expected['w'], expected['h']],
      );
    case 'text':
      expect(actual, isA<DjvuTextShape>());
      final text = actual as DjvuTextShape;
      expect(
        [text.x, text.y, text.width, text.height],
        [expected['x'], expected['y'], expected['w'], expected['h']],
      );
    case 'line':
      expect(actual, isA<DjvuLineShape>());
      final line = actual as DjvuLineShape;
      expect(
        [line.x1, line.y1, line.x2, line.y2],
        [expected['x1'], expected['y1'], expected['x2'], expected['y2']],
      );
    case 'poly':
      expect(actual, isA<DjvuPolyShape>());
      final expectedPoints = (expected['points'] as List<dynamic>)
          .map((p) => (p as List<dynamic>))
          .map((p) => (p[0] as int, p[1] as int))
          .toList();
      expect((actual as DjvuPolyShape).points, expectedPoints);
    default:
      fail('unknown shape kind ${expected['kind']}');
  }
}

void main() {
  group('parseDjvuAnnotations fixture', () {
    test('matches the annotated page links', () {
      final chunk = readDjvuRef('annotated', 'p0.ANTz.bin');
      final decoded = readDjvuRef('annotated', 'p0.ANTz.dec.bin');
      expect(bzzDecode(chunk), equals(decoded), reason: 'BZZ payload');

      final (annotation, areas) = parseDjvuAnnotations(decoded);
      final reference = readDjvuLinks('annotated', 0)!;

      final expectedAreas =
          (reference['areas'] as List<dynamic>).cast<Map<String, dynamic>>();
      expect(areas, hasLength(expectedAreas.length));
      expect(
        areas,
        hasLength(
          (readDjvuManifest('annotated')['pages'] as List<dynamic>)[0]['linkCount']
              as int,
        ),
        reason: 'link count',
      );
      for (var i = 0; i < expectedAreas.length; i++) {
        expect(areas[i].url, expectedAreas[i]['url'], reason: 'area $i url');
        expect(
          areas[i].description,
          expectedAreas[i]['description'],
          reason: 'area $i description',
        );
        expect(areas[i].target, isNull, reason: 'area $i target');
        _expectShape(
          areas[i].shape,
          expectedAreas[i]['shape'] as Map<String, dynamic>,
        );
      }

      expect(annotation.background, isNull);
      expect(annotation.zoom, reference['zoom']);
      expect(annotation.mode, reference['mode']);
      expect(annotation.extra, isEmpty);
    });

    test('parses the decoded payload as plain annotation text', () {
      // The page's ANTa fallback is the same content uncompressed.
      final decoded = readDjvuRef('annotated', 'p0.ANTz.dec.bin');
      final (annotation, areas) = parseDjvuAnnotations(decoded);
      expect(areas.map((a) => a.url), ['#page_2', 'https://example.com/', '#page_3']);
      expect(annotation.zoom, 100);
      expect(annotation.mode, 'color');
    });
  });

  group('parseDjvuAnnotationText', () {
    test('empty text yields defaults', () {
      final (annotation, areas) = parseDjvuAnnotationText('  \n');
      expect(annotation.background, isNull);
      expect(annotation.zoom, isNull);
      expect(annotation.mode, isNull);
      expect(annotation.extra, isEmpty);
      expect(areas, isEmpty);
    });

    test('parses background, zoom and mode', () {
      final (annotation, _) = parseDjvuAnnotationText(
        '(background #ff0000)(zoom 150)(mode color)',
      );
      expect(annotation.background, const DjvuColor(255, 0, 0));
      expect(annotation.zoom, 150);
      expect(annotation.mode, 'color');
      // `d150` is the DjVuLibre spelling.
      final (dZoom, _) = parseDjvuAnnotationText('(zoom d150)');
      expect(dZoom.zoom, 150);
      expect(dZoom.extra, isEmpty);
      // Symbolic zooms stay in extra.
      final (symbolic, _) = parseDjvuAnnotationText('(zoom page)');
      expect(symbolic.zoom, isNull);
      expect(symbolic.extra, ['(zoom page)']);
    });

    test('parses every known shape', () {
      const cases = {
        '(rect 10 20 100 50)': 'rect',
        '(oval 1 2 30 40)': 'oval',
        '(text 5 10 100 50)': 'text',
        '(line 0 0 100 100)': 'line',
        '(poly 0 0 10 0 10 10 0 10)': 'poly',
      };
      for (final MapEntry(key: shape, value: kind) in cases.entries) {
        final (_, areas) = parseDjvuAnnotationText(
          '(maparea "u" "d" $shape)',
        );
        expect(areas, hasLength(1), reason: kind);
        expect(areas.single.url, 'u');
        expect(areas.single.description, 'd');
        expect(areas.single.target, isNull, reason: kind);
      }
      final poly = parseDjvuAnnotationText(
        '(maparea "" "" (poly 0 0 10 0 10 10 0 10))',
      ).$2.single.shape as DjvuPolyShape;
      expect(poly.points, [(0, 0), (10, 0), (10, 10), (0, 10)]);
    });

    test('parses a url wrapper with a browser target', () {
      final (_, areas) = parseDjvuAnnotationText(
        '(maparea (url "http://e.x" "_blank") "d" (rect 0 0 1 1))',
      );
      expect(areas.single.url, 'http://e.x');
      expect(areas.single.target, '_blank');
    });

    test('decodes CP1252 bytes in urls and descriptions', () {
      final payload = Uint8List.fromList(
        '(maparea "http://example.com/a\x96b" "Ex\x93ample" (rect 10 20 100 50))'
            .codeUnits,
      );
      final (_, areas) = parseDjvuAnnotations(payload);
      expect(areas.single.url, 'http://example.com/a\u2013b');
      expect(areas.single.description, 'Ex\u201cample');
    });

    test('parses border and hilite options', () {
      final (_, areas) = parseDjvuAnnotationText(
        '(maparea "" "" (rect 0 0 10 10) (border #FF0000) (hilite #00ff00))',
      );
      expect(areas.single.border, 'border #FF0000');
      expect(areas.single.highlight, const DjvuColor(0, 255, 0));
      expect(areas.single.extra, isEmpty);
    });

    test('parses the DjVuLibre border options verbatim', () {
      final (_, areas) = parseDjvuAnnotationText(
        '(maparea "" "" (rect 0 0 1 1) (xor))\n'
        '(maparea "" "" (rect 0 0 1 1) (shadow_in 3 ))\n'
        '(maparea "" "" (rect 0 0 1 1) (none))',
      );
      expect(areas.map((a) => a.border), ['xor', 'shadow_in 3', 'none']);
    });

    test('reads the legacy (border keyword) spelling', () {
      final (_, areas) = parseDjvuAnnotationText(
        '(maparea "" "" (rect 0 0 1 1) (border xor))',
      );
      expect(areas.single.border, 'xor');
    });

    test('keeps untyped forms and options in extra', () {
      final (annotation, areas) = parseDjvuAnnotationText(
        '(background #8F8F8F)\n'
        '(zoom d150)\n'
        '(mode bw)\n'
        '(align center top)\n'
        '(metadata (Title "A \\"quoted\\" title") (Year "1999"))\n'
        '(maparea (url "#1" "_self") "note" (rect 1 2 3 4) (shadow_in 3)\n'
        '  (hilite #FFFF00) (border_avis) (opacity 50))\n'
        '(maparea "" "" (line 0 0 9 9) (none) (arrow) (width 2) (lineclr #FF0000))',
      );
      expect(annotation.background, const DjvuColor(0x8f, 0x8f, 0x8f));
      expect(annotation.zoom, 150);
      expect(annotation.mode, 'bw');
      expect(annotation.extra, [
        '(align center top)',
        '(metadata (Title "A \\"quoted\\" title") (Year "1999"))',
      ]);

      expect(areas, hasLength(2));
      expect(areas[0].target, '_self');
      expect(areas[0].border, 'shadow_in 3');
      expect(areas[0].highlight, const DjvuColor(255, 255, 0));
      expect(areas[0].extra, ['(border_avis)', '(opacity 50)']);
      expect(areas[1].border, 'none');
      expect(areas[1].extra, ['(arrow)', '(width 2)', '(lineclr #FF0000)']);
    });

    test('drops mapareas without a shape list', () {
      expect(
        parseDjvuAnnotationText('(maparea "url" "desc" notalist)').$2,
        isEmpty,
      );
      expect(parseDjvuAnnotationText('(maparea)').$2, isEmpty);
    });

    test('defaults non-atom url and description to empty strings', () {
      final (_, areas) = parseDjvuAnnotationText(
        '(maparea () () (rect 0 0 10 10))',
      );
      expect(areas.single.url, '');
      expect(areas.single.description, '');
    });

    test('rejects malformed typed values', () {
      expect(
        () => parseDjvuAnnotationText('(background #fff)'),
        throwsA(isA<DjvuFormatException>()),
      );
      expect(
        () => parseDjvuAnnotationText('(background #gggggg)'),
        throwsA(isA<DjvuFormatException>()),
      );
      expect(
        () => parseDjvuAnnotationText('(maparea "" "" (circle 0 0 10))'),
        throwsA(isA<DjvuFormatException>()),
      );
      expect(
        () => parseDjvuAnnotationText('(maparea "" "" ())'),
        throwsA(isA<DjvuFormatException>()),
      );
      expect(
        () => parseDjvuAnnotationText('(maparea "" "" (rect 0 0 abc 10))'),
        throwsA(isA<DjvuFormatException>()),
      );
      expect(
        () => parseDjvuAnnotationText('(maparea "" "" (rect 0 0))'),
        throwsA(isA<DjvuFormatException>()),
      );
    });

    test('accepts a color without the leading hash', () {
      final (annotation, _) = parseDjvuAnnotationText('(background 00ff00)');
      expect(annotation.background, const DjvuColor(0, 255, 0));
    });

    test('does not overflow on deeply nested input', () {
      final deep = '(' * 200 + ')' * 200;
      expect(() => parseDjvuAnnotationText(deep), returnsNormally);
    });
  });

  group('djvuShapeBbox', () {
    test('passes rect, oval and text through when non-degenerate', () {
      expect(
        djvuShapeBbox(const DjvuRectShape(3, 7, 11, 13)),
        (x: 3, y: 7, width: 11, height: 13),
      );
      expect(
        djvuShapeBbox(const DjvuOvalShape(3, 7, 11, 13)),
        (x: 3, y: 7, width: 11, height: 13),
      );
      expect(
        djvuShapeBbox(const DjvuTextShape(3, 7, 11, 13)),
        (x: 3, y: 7, width: 11, height: 13),
      );
      expect(djvuShapeBbox(const DjvuRectShape(5, 5, 0, 10)), isNull);
      expect(djvuShapeBbox(const DjvuRectShape(5, 5, 10, 0)), isNull);
    });

    test('computes the point-cloud bounding box of a polygon', () {
      expect(
        djvuShapeBbox(const DjvuPolyShape([(10, 4), (2, 20), (8, 1), (5, 12)])),
        (x: 2, y: 1, width: 8, height: 19),
      );
      expect(djvuShapeBbox(const DjvuPolyShape([])), isNull);
      expect(djvuShapeBbox(const DjvuPolyShape([(0, 0)])), isNull);
      expect(djvuShapeBbox(const DjvuPolyShape([(9, 9)])), isNull);
      expect(djvuShapeBbox(const DjvuPolyShape([(4, 6), (4, 6)])), isNull);
    });

    test('computes the endpoint box of a line, order-independent', () {
      expect(
        djvuShapeBbox(const DjvuLineShape(2, 3, 12, 18)),
        (x: 2, y: 3, width: 10, height: 15),
      );
      expect(
        djvuShapeBbox(const DjvuLineShape(12, 18, 2, 3)),
        (x: 2, y: 3, width: 10, height: 15),
      );
      expect(djvuShapeBbox(const DjvuLineShape(2, 5, 20, 5)), isNull);
      expect(djvuShapeBbox(const DjvuLineShape(5, 2, 5, 20)), isNull);
    });
  });
}
