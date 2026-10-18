// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// NAVM bookmarks: the DjVu table of contents.
//
// A NAVM chunk is a BZZ-compressed tree of bookmark entries: a big-endian u16
// total node count, then the root entries, each a child count byte, a
// length-prefixed (u24) title, a length-prefixed URL, and its children.
//
// Ported from djvu-rs (`src/djvu_document/bookmark.rs`, `src/export_common.rs`,
// MIT, https://github.com/matyushkin/djvu-rs), including its guards: a nesting
// depth cap and lenient title decoding (legacy files carry CP1252 bytes).

import 'dart:typed_data';

import 'package:saber/data/document_conversion/djvu/djvu_bzz.dart';
import 'package:saber/data/document_conversion/djvu/djvu_iff.dart';
import 'package:saber/data/document_conversion/djvu/djvu_text.dart';

/// One table-of-contents entry from a document's NAVM chunk.
class DjvuBookmark {
  DjvuBookmark(this.title, this.url, this.children);

  /// Display title, decoded leniently (see `djvu_text.dart`).
  final String title;

  /// Target in DjVu's internal URL format (`#page_3` for the fourth page) or
  /// an external URL.
  final String url;

  /// Nested child entries, in document order.
  final List<DjvuBookmark> children;
}

/// Maximum bookmark nesting depth (real outlines are a few levels deep).
///
/// Bounds the recursive parse so a crafted deep chain cannot overflow the
/// stack, matching the reference.
const _maxNavmDepth = 256;

/// Parses the NAVM chunk of a document into its bookmark tree.
///
/// Returns an empty list when the chunk holds fewer than two bytes (the
/// reference treats that as "no bookmarks").
///
/// Throws [BzzException] when the chunk is not a valid BZZ stream and
/// [DjvuFormatException] when the decoded tree is malformed or nests deeper
/// than [_maxNavmDepth]. Callers that want bookmarks to degrade gracefully
/// should catch both.
List<DjvuBookmark> parseNavmBookmarks(Uint8List navmChunk) =>
    parseNavmPayload(bzzDecode(navmChunk));

/// Parses an already BZZ-decoded NAVM payload into its bookmark tree.
///
/// Exposed separately so callers that already decoded the chunk (or tests with
/// reference payloads) can skip the BZZ pass.
List<DjvuBookmark> parseNavmPayload(Uint8List data) {
  if (data.length < 2) return const [];
  final totalCount = (data[0] << 8) | data[1];
  final state = _NavmParser(data);
  final bookmarks = <DjvuBookmark>[];
  while (state.count < totalCount) {
    bookmarks.add(state.parseEntry(0));
  }
  return bookmarks;
}

/// Mutable position/counter shared across the recursive descent, mirroring
/// the reference's `(pos, total_counter)` pair.
class _NavmParser {
  _NavmParser(this.data);

  final Uint8List data;
  var pos = 2;

  /// Total nodes emitted so far, across every recursion level.
  var count = 0;

  DjvuBookmark parseEntry(int depth) {
    if (depth > _maxNavmDepth) {
      throw const DjvuFormatException('NAVM bookmark nesting is too deep');
    }
    if (pos >= data.length) {
      throw const DjvuFormatException('NAVM bookmark entry is truncated');
    }
    final nChildren = data[pos++];
    final title = _readString();
    final url = _readString();
    count += 1;
    final children = <DjvuBookmark>[];
    for (var i = 0; i < nChildren; i++) {
      children.add(parseEntry(depth + 1));
    }
    return DjvuBookmark(title, url, children);
  }

  /// Reads a `[u24 big-endian length][bytes]` string.
  String _readString() {
    if (pos + 3 > data.length) {
      throw const DjvuFormatException('NAVM string length is truncated');
    }
    final len = (data[pos] << 16) | (data[pos + 1] << 8) | data[pos + 2];
    pos += 3;
    if (pos + len > data.length) {
      throw const DjvuFormatException('NAVM string bytes are truncated');
    }
    final text = decodeDjvuText(Uint8List.sublistView(data, pos, pos + len));
    pos += len;
    return text;
  }
}

/// Resolves a DjVu bookmark or link URL to a 0-based page index, when it
/// points inside the document.
///
/// Handles every internal spelling the reference accepts: `#page=N`,
/// `#page_N` and `#pageN` (all 1-based), the bare numeric `#N`, and the
/// relative `#+N` / `#-N` forms (resolved as 1-based absolute). Returns null
/// for external URLs, bare anchors, and anything unparseable, leaving the
/// caller to decide how those render as links.
int? bookmarkPageIndex(String url) {
  if (!url.startsWith('#')) return null;
  final frag = url.substring(1);
  if (frag.startsWith('page')) {
    var digits = frag.substring(4);
    if (digits.startsWith('=') || digits.startsWith('_')) {
      digits = digits.substring(1);
    }
    digits = digits.trim();
    // A signed parse: `usize::from_str` accepts `+N`/`N` but not `-N`.
    if (!digits.startsWith('-')) {
      final n = _parseDecimal(digits);
      if (n != null) return n < 1 ? 0 : n - 1;
    }
  }
  final n = _parseDecimal(frag.trim());
  if (n == null) return null;
  return n < 1 ? 0 : n - 1;
}

/// Strict decimal parser matching Rust's `str::parse::<i64>`: an optional
/// sign followed by decimal digits, with overflows rejected.
int? _parseDecimal(String s) {
  if (s.isEmpty) return null;
  var i = 0;
  var negative = false;
  if (s.startsWith('+')) {
    i = 1;
  } else if (s.startsWith('-')) {
    negative = true;
    i = 1;
  }
  if (i == s.length) return null;
  var value = 0;
  for (; i < s.length; i++) {
    final digit = s.codeUnitAt(i) - 0x30;
    if (digit < 0 || digit > 9) return null;
    value = value * 10 + digit;
    if (value > 0x7fffffffffffffff) return null;
  }
  return negative ? -value : value;
}
