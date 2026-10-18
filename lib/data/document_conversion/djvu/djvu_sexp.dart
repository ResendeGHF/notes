// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Shared S-expression reader for DjVu text chunks (ANTa/ANTz annotations,
// METa/METz metadata).
//
// The syntax is parenthesised lists of unquoted atoms and `"`-quoted strings,
// with `;` line comments. The reader is lenient and best-effort: malformed
// fragments (unmatched parens, payload past the depth limit) are dropped
// rather than reported, so a partially-valid chunk still yields the forms it
// can.
//
// Ported from djvu-rs `src/sexp.rs` (MIT, https://github.com/matyushkin/djvu-rs),
// including the recursion-depth guard.

/// A node in a parsed S-expression tree.
///
/// Unquoted atoms and quoted strings stay distinct so that a form the caller
/// does not interpret can be printed back unchanged ([writeTo]); readers that
/// do not care use [text].
sealed class DjvuSExpr {
  const DjvuSExpr();

  /// The text of an atom or a quoted string; null for a list.
  String? get text;

  /// Appends this node to [out] as S-expression text: one space between list
  /// items, quoted strings re-escaped. Reading the output back yields the
  /// same tree.
  void writeTo(StringBuffer out);

  /// Convenience: [writeTo] as a string.
  String toSexprText() {
    final out = StringBuffer();
    writeTo(out);
    return out.toString();
  }
}

/// An unquoted atom (e.g. `rect`, `150`, `#ff0000`).
class DjvuAtom extends DjvuSExpr {
  const DjvuAtom(this.value);

  final String value;

  @override
  String? get text => value;

  @override
  void writeTo(StringBuffer out) => out.write(value);
}

/// A `"`-quoted string.
class DjvuQuoted extends DjvuSExpr {
  const DjvuQuoted(this.value);

  final String value;

  @override
  String? get text => value;

  @override
  void writeTo(StringBuffer out) => writeQuoted(value, out);
}

/// A parenthesised list of nodes.
class DjvuSList extends DjvuSExpr {
  DjvuSList(this.items);

  final List<DjvuSExpr> items;

  @override
  String? get text => null;

  @override
  void writeTo(StringBuffer out) {
    out.writeCharCode(0x28); // (
    for (var i = 0; i < items.length; i++) {
      if (i > 0) out.writeCharCode(0x20);
      items[i].writeTo(out);
    }
    out.writeCharCode(0x29); // )
  }
}

/// Appends [s] as a `"`-quoted string, backslash-escaping `"` and `\`.
void writeQuoted(String s, StringBuffer out) {
  out.writeCharCode(0x22); // "
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c == 0x22 || c == 0x5c) out.writeCharCode(0x5c); // escapes " and \
    out.writeCharCode(c);
  }
  out.writeCharCode(0x22);
}

/// Maximum nesting depth for parsed lists.
///
/// Bounds recursion in [parseDjvuSexprs] so a deeply nested payload cannot
/// overflow the stack. Lists deeper than this are truncated at the limit.
const _maxSexprDepth = 64;

enum _TokenKind { lparen, rparen, atom, quoted }

class _Token {
  const _Token(this.kind, [this.text]);

  final _TokenKind kind;
  final String? text;
}

/// Parses [input] into a flat list of top-level S-expressions.
///
/// Lenient: see the file docs.
List<DjvuSExpr> parseDjvuSexprs(String input) {
  final reader = _SexprReader(_tokenize(input));
  final result = <DjvuSExpr>[];
  while (reader.pos < reader.tokens.length) {
    final expr = reader.parseOne(0);
    if (expr != null) result.add(expr);
  }
  return result;
}

/// Tokenizes an S-expression string into a flat list of tokens.
List<_Token> _tokenize(String input) {
  final tokens = <_Token>[];
  final length = input.length;
  var i = 0;

  while (i < length) {
    switch (input.codeUnitAt(i)) {
      case 0x28: // (
        tokens.add(const _Token(_TokenKind.lparen));
        i += 1;
      case 0x29: // )
        tokens.add(const _Token(_TokenKind.rparen));
        i += 1;
      case 0x22: // "
        i += 1;
        final buffer = StringBuffer();
        while (i < length) {
          final c = input.codeUnitAt(i);
          if (c == 0x5c && i + 1 < length) {
            // Escaped character: drop the backslash, keep the next unit.
            i += 1;
            buffer.writeCharCode(input.codeUnitAt(i));
            i += 1;
          } else if (c == 0x22) {
            i += 1;
            break;
          } else {
            buffer.writeCharCode(c);
            i += 1;
          }
        }
        tokens.add(_Token(_TokenKind.quoted, buffer.toString()));
      case 0x20 || 0x09 || 0x0a || 0x0d: // space / tab / LF / CR
        i += 1;
      case 0x3b: // ;
        while (i < length && input.codeUnitAt(i) != 0x0a) {
          i += 1;
        }
      default:
        final start = i;
        while (i < length) {
          final c = input.codeUnitAt(i);
          if (c == 0x28 ||
              c == 0x29 ||
              c == 0x22 ||
              c == 0x20 ||
              c == 0x09 ||
              c == 0x0a ||
              c == 0x0d) {
            break;
          }
          i += 1;
        }
        if (i > start) {
          tokens.add(_Token(_TokenKind.atom, input.substring(start, i)));
        }
    }
  }

  return tokens;
}

class _SexprReader {
  _SexprReader(this.tokens);

  final List<_Token> tokens;
  var pos = 0;

  /// Parses the next node. Returns null without consuming input when the
  /// depth guard trips or the token stream ends.
  DjvuSExpr? parseOne(int depth) {
    if (depth > _maxSexprDepth) return null;
    if (pos >= tokens.length) return null;
    final token = tokens[pos];
    switch (token.kind) {
      case _TokenKind.lparen:
        pos += 1;
        final items = <DjvuSExpr>[];
        while (pos < tokens.length) {
          if (tokens[pos].kind == _TokenKind.rparen) {
            pos += 1;
            break;
          }
          final child = parseOne(depth + 1);
          if (child == null) break;
          items.add(child);
        }
        return DjvuSList(items);
      case _TokenKind.rparen:
        // Unexpected close paren — skip it.
        pos += 1;
        return null;
      case _TokenKind.atom:
        pos += 1;
        return DjvuAtom(token.text!);
      case _TokenKind.quoted:
        pos += 1;
        return DjvuQuoted(token.text!);
    }
  }
}
