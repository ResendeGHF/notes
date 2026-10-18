// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/document_conversion/djvu/djvu_sexp.dart';

/// Renders the single top-level expression of [input] back to text.
String _print(String input) => parseDjvuSexprs(input).single.toSexprText();

void main() {
  group('parseDjvuSexprs', () {
    test('parses a flat list into atoms', () {
      final exprs = parseDjvuSexprs('(zoom 100)');
      expect(exprs, hasLength(1));
      final list = exprs.single as DjvuSList;
      expect(list.items.first, isA<DjvuAtom>());
      expect(list.items.first.text, 'zoom');
      expect(list.items[1].text, '100');
    });

    test('keeps quoted strings distinct from atoms', () {
      final exprs = parseDjvuSexprs('(title "My Book")');
      final list = exprs.single as DjvuSList;
      expect(list.items[0], isA<DjvuAtom>());
      expect(list.items[1], isA<DjvuQuoted>());
      expect(list.items[1].text, 'My Book');
    });

    test('quoted UTF-8 survives tokenizing', () {
      final list = parseDjvuSexprs('(title "Caf\u00e9 \u2014 \u041a\u0430\u0444\u0435")')
          .single as DjvuSList;
      expect((list.items[1] as DjvuQuoted).value, 'Caf\u00e9 \u2014 \u041a\u0430\u0444\u0435');
    });

    test('decodes backslash escapes inside quoted strings', () {
      final list = parseDjvuSexprs(r'(k "a\"b\\c")').single as DjvuSList;
      expect(list.items[1].text, r'a"b\c');
    });

    test('skips line comments', () {
      expect(parseDjvuSexprs('; a comment\n(a b)'), hasLength(1));
    });

    test('print-back produces an equivalent tree', () {
      expect(
        _print(
          '(metadata  (Title "A \\"quoted\\" \\\\ name")\n (Year 1999) ( ) )',
        ),
        '(metadata (Title "A \\"quoted\\" \\\\ name") (Year 1999) ())',
      );
      // Re-reading what we printed yields the same text again.
      final printed = _print('(metadata (Title "x") (Year 1999) ())');
      expect(_print(printed), printed);
    });

    test('bounds recursion on deeply nested input', () {
      // All of these must terminate without a stack overflow, in one
      // top-level expression (matching the Rust reader).
      for (final depth in [64, 65, 66, 129, 200, 10000]) {
        final deep = '(' * depth + ')' * depth;
        expect(parseDjvuSexprs(deep), hasLength(1), reason: 'depth $depth');
      }
    });

    test('recovers from unterminated input', () {
      expect(parseDjvuSexprs('(k "unterminated'), hasLength(1));
      expect(parseDjvuSexprs('(unclosed'), hasLength(1));
      final bare = parseDjvuSexprs('"unclosed');
      expect(bare, hasLength(1));
      expect(bare.single.text, 'unclosed');
    });

    test('skips unexpected close parens', () {
      // The stray `)` is skipped, leaving the two well-formed forms.
      final exprs = parseDjvuSexprs(')(a) ) (b)');
      expect(exprs, hasLength(2));
      expect((exprs[0] as DjvuSList).items.first.text, 'a');
      expect((exprs[1] as DjvuSList).items.first.text, 'b');
    });
  });

  group('quoted strings', () {
    test('writeQuoted escapes quotes and backslashes', () {
      final out = StringBuffer();
      writeQuoted(r'a "b" \c', out);
      expect(out.toString(), r'"a \"b\" \\c"');
      expect(parseDjvuSexprs(out.toString()).single.text, r'a "b" \c');
    });
  });
}
