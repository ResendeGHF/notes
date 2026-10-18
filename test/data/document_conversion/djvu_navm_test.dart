// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/document_conversion/djvu/djvu_bzz.dart';
import 'package:saber/data/document_conversion/djvu/djvu_iff.dart';
import 'package:saber/data/document_conversion/djvu/djvu_navm.dart';

import 'djvu/djvu_fixture.dart';

/// Compares a parsed tree against the manifest's bookmark JSON.
void _expectBookmarks(List<DjvuBookmark> actual, List<dynamic> expected) {
  expect(actual, hasLength(expected.length));
  for (var i = 0; i < expected.length; i++) {
    final entry = expected[i] as Map<String, dynamic>;
    expect(actual[i].title, entry['title'], reason: 'bookmark $i title');
    expect(actual[i].url, entry['url'], reason: 'bookmark $i url');
    _expectBookmarks(actual[i].children, entry['children'] as List<dynamic>);
  }
}

/// Builds a NAVM payload for [entries] `(children, title, url)` tuples.
Uint8List _payload(List<(int, List<int>, List<int>)> entries) {
  final out = BytesBuilder(copy: false)
    ..add([(entries.length >> 8) & 0xff, entries.length & 0xff]);
  for (final (children, title, url) in entries) {
    out.add([children]);
    for (final text in [title, url]) {
      out.add([
        (text.length >> 16) & 0xff,
        (text.length >> 8) & 0xff,
        text.length & 0xff,
      ]);
      out.add(text);
    }
  }
  return out.takeBytes();
}

void main() {
  group('parseNavmBookmarks', () {
    test('matches the annotated fixture manifest', () {
      final chunk = readDjvuRef('annotated', 'root.NAVM.bin');
      final manifest = readDjvuManifest('annotated');

      expect(
        bzzDecode(chunk),
        equals(readDjvuRef('annotated', 'root.NAVM.dec.bin')),
        reason: 'BZZ-decoded payload',
      );

      final bookmarks = parseNavmBookmarks(chunk);
      _expectBookmarks(bookmarks, manifest['bookmarks'] as List<dynamic>);
      expect(bookmarks, hasLength(2));
      expect(bookmarks.first.children, hasLength(2));
      expect(bookmarks.first.children.first.title, 'Section 1.1');
      expect(bookmarks.last.children, isEmpty);
    });

    test('decodes the payload without a BZZ pass too', () {
      final manifest = readDjvuManifest('annotated');
      final bookmarks = parseNavmPayload(
        readDjvuRef('annotated', 'root.NAVM.dec.bin'),
      );
      _expectBookmarks(bookmarks, manifest['bookmarks'] as List<dynamic>);
    });
  });

  group('parseNavmPayload edge cases', () {
    test('short payloads and zero counts mean no bookmarks', () {
      expect(parseNavmPayload(Uint8List(0)), isEmpty);
      expect(parseNavmPayload(Uint8List.fromList([0])), isEmpty);
      expect(parseNavmPayload(Uint8List.fromList([0, 0])), isEmpty);
      // A count with no following entry is malformed, not silently empty.
      expect(
        () => parseNavmPayload(Uint8List.fromList([0, 1])),
        throwsA(isA<DjvuFormatException>()),
      );
    });

    test('parses nested entries and CP1252 titles', () {
      final payload = _payload([
        // One child; title "Cha\x96pter" (CP1252 en dash).
        (1, 'Cha\x96pter'.codeUnits, '#page_1'.codeUnits),
        (0, 'Sub'.codeUnits, '#page_2'.codeUnits),
        (0, 'End'.codeUnits, 'https://example.com/x'.codeUnits),
      ]);
      final bookmarks = parseNavmPayload(payload);
      expect(bookmarks, hasLength(2));
      expect(bookmarks.first.title, 'Cha\u2013pter');
      expect(bookmarks.first.url, '#page_1');
      expect(bookmarks.first.children, hasLength(1));
      expect(bookmarks.first.children.single.title, 'Sub');
      expect(bookmarks.last.url, 'https://example.com/x');
    });

    test('rejects truncated strings and entries', () {
      // Entry with no title-length bytes at all.
      expect(
        () => parseNavmPayload(Uint8List.fromList([0, 1, 0])),
        throwsA(isA<DjvuFormatException>()),
      );
      // Title length claims 5 bytes but only 2 follow.
      expect(
        () => parseNavmPayload(
          Uint8List.fromList([0, 1, 0, 0, 0, 5, 0x61, 0x62]),
        ),
        throwsA(isA<DjvuFormatException>()),
      );
      // Child count claims an entry that never arrives.
      expect(
        () => parseNavmPayload(
          Uint8List.fromList([0, 2, 1, 0, 0, 0, 0, 0, 0]),
        ),
        throwsA(isA<DjvuFormatException>()),
      );
    });

    test('caps the nesting depth at 256 levels', () {
      // A single chain of entries, each with one child. 250 levels is within
      // the cap; 300 exceeds it (the reference errors rather than recursing).
      Uint8List chain(int depth) => _payload([
        for (var i = 0; i < depth; i++) (i == depth - 1 ? 0 : 1, <int>[], <int>[]),
      ]);

      final deep = parseNavmPayload(chain(250));
      var node = deep.single;
      var levels = 1;
      while (node.children.isNotEmpty) {
        node = node.children.single;
        levels += 1;
      }
      expect(levels, 250);

      expect(
        () => parseNavmPayload(chain(300)),
        throwsA(isA<DjvuFormatException>()),
      );
    });
  });

  group('bookmarkPageIndex', () {
    test('accepts every internal spelling', () {
      expect(bookmarkPageIndex('#page_1'), 0);
      expect(bookmarkPageIndex('#page_3'), 2);
      expect(bookmarkPageIndex('#page=2'), 1);
      expect(bookmarkPageIndex('#page2'), 1);
      expect(bookmarkPageIndex('#page 4'), 3);
      expect(bookmarkPageIndex('#1'), 0);
      expect(bookmarkPageIndex('#5'), 4);
      expect(bookmarkPageIndex('# 3 '), 2);
      expect(bookmarkPageIndex('#+2'), 1);
      expect(bookmarkPageIndex('#-2'), 0);
      expect(bookmarkPageIndex('#0'), 0);
      expect(bookmarkPageIndex('#page_0'), 0);
    });

    test('rejects external, relative and unparseable targets', () {
      expect(bookmarkPageIndex('not-a-page-url'), isNull);
      expect(bookmarkPageIndex('#pageXYZ'), isNull);
      expect(bookmarkPageIndex('#page'), isNull);
      expect(bookmarkPageIndex('#page='), isNull);
      expect(bookmarkPageIndex('#page-3'), isNull);
      expect(bookmarkPageIndex(''), isNull);
      expect(bookmarkPageIndex('#'), isNull);
      expect(bookmarkPageIndex('https://example.com/#page_2'), isNull);
      expect(bookmarkPageIndex('file.djvu#page_2'), isNull);
      expect(bookmarkPageIndex('#pages_2'), isNull);
    });
  });
}
