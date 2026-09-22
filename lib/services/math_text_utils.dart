// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:math_expressions/math_expressions.dart';
import 'package:saber/components/canvas/_stroke.dart';

/// Token pairing solver-generated answer strokes with the text they render.
///
/// Strokes produced by [tagSolverResultStrokes] carry the full answer text so
/// later recognition passes can splice the known text in instead of feeding
/// mechanical glyph outlines back into ML Kit (which misreads them).
typedef MathResultToken = ({int group, String text});

/// Process-wide registry of solver-generated answer strokes. Keyed by object
/// identity (entries vanish with their strokes), so nothing is persisted and
/// reopened notes simply behave as plain ink again.
final Expando<MathResultToken> solverResultTokens =
    Expando<MathResultToken>('solverResultTokens');

int _nextResultGroup = 0;

/// Tags [strokes] as rendering [text] (one answer per call; every stroke of
/// the answer shares a group id so joining never duplicates it).
void tagSolverResultStrokes(List<Stroke> strokes, String text) {
  if (strokes.isEmpty || text.isEmpty) return;
  final group = _nextResultGroup++;
  for (final s in strokes) {
    solverResultTokens[s] = (group: group, text: text);
  }
}

/// Known answer token for [stroke], or null for regular handwriting.
MathResultToken? knownResultOf(Stroke stroke) => solverResultTokens[stroke];

/// One x-ordered unit of a writing line: either a run of handwriting to
/// recognize, or a group of answer strokes with already-known text.
class LineToken {
  const LineToken.run(this.run) : known = null, knownText = null;
  const LineToken.known(this.known, this.knownText) : run = null;

  final List<Stroke>? run;
  final List<Stroke>? known;
  final String? knownText;

  bool get isKnown => known != null;
}

double _minXOf(Stroke s) {
  final b = s.bounds;
  return b.left.isFinite ? b.left : 0;
}

/// Splits [strokes] into x-ordered tokens, grouping consecutive answer
/// strokes of the same answer and runs of handwriting in between.
List<LineToken> splitLineTokens(List<Stroke> strokes) {
  final ordered = List<Stroke>.from(strokes)
    ..sort((a, b) => _minXOf(a).compareTo(_minXOf(b)));
  final out = <LineToken>[];
  var run = <Stroke>[];
  List<Stroke>? openKnown;
  int? openGroup;
  String? openText;

  void flushRun() {
    if (run.isNotEmpty) {
      out.add(LineToken.run(List<Stroke>.from(run)));
      run = <Stroke>[];
    }
  }

  void flushKnown() {
    if (openKnown != null) {
      out.add(LineToken.known(openKnown!, openText!));
      openKnown = null;
      openGroup = null;
      openText = null;
    }
  }

  for (final s in ordered) {
    final token = knownResultOf(s);
    if (token == null) {
      flushKnown();
      run.add(s);
    } else if (token.group == openGroup) {
      openKnown!.add(s);
    } else {
      flushRun();
      flushKnown();
      openKnown = [s];
      openGroup = token.group;
      openText = token.text;
    }
  }
  flushRun();
  flushKnown();
  return out;
}

/// Minimum x of [strokes], or 0 when empty. Used for indent estimation.
double minXOfStrokes(List<Stroke> strokes) {
  var minX = double.infinity;
  for (final s in strokes) {
    final x = _minXOf(s);
    if (x < minX) minX = x;
  }
  return minX == double.infinity ? 0 : minX;
}

/// Maps common handwriting/OCR variants to canonical math syntax. Math-line
/// context only: letters that double as operators are intentionally folded.
String normalizeMathAliases(String raw) {
  var s = raw;
  const fw = '０１２３４５６７８９＋－×÷＝（）．，';
  const asc = '0123456789+-*/=().,';
  for (var i = 0; i < fw.length; i++) {
    s = s.replaceAll(fw[i], asc[i]);
  }
  s = s
      .replaceAll('−', '-')
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll('×', '*')
      .replaceAll('✕', '*')
      .replaceAll('∗', '*')
      .replaceAll('·', '*')
      .replaceAll('⋅', '*')
      .replaceAll('x', '*')
      .replaceAll('X', '*')
      .replaceAll('÷', '/')
      .replaceAll('（', '(')
      .replaceAll('）', ')')
      .replaceAll('[', '(')
      .replaceAll(']', ')')
      .replaceAll('{', '(')
      .replaceAll('}', ')')
      .replaceAll('π', 'pi')
      .replaceAll('Π', 'pi');
  // Bare square root of a number: √4 -> sqrt(4).
  s = s.replaceAllMapped(
    RegExp(r'√\s*(\d+(?:[.,]\d+)?)'),
    (m) => 'sqrt(${m[1]})',
  );
  s = s.replaceAll('√', 'sqrt');
  // Decimal comma between digits: 3,14 -> 3.14.
  s = s.replaceAllMapped(
    RegExp(r'(\d),(\d)'),
    (m) => '${m[1]}.${m[2]}',
  );
  // Standalone euler constant: the parser cannot bind a bare `e`
  // (tokenizer reads it as scientific notation), so inline its value.
  s = s.replaceAllMapped(
    RegExp(r'\be\b'),
    (_) => '(2.718281828459045)',
  );
  s = s.replaceAllMapped(
    RegExp(r'\bE\b'),
    (_) => '(2.718281828459045)',
  );
  return s;
}

/// Inserts explicit multiplication where handwriting omits it: 2(3+1),
/// (2+1)(3+2), 2pi. The parser rejects all of these without the operator.
String insertImplicitMultiplication(String s) {
  var r = s;
  r = r.replaceAllMapped(RegExp(r'(\d|\))(\()'), (m) => '${m[1]}*${m[2]}');
  r = r.replaceAllMapped(RegExp(r'(\))(\d)'), (m) => '${m[1]}*${m[2]}');
  r = r.replaceAllMapped(RegExp(r'(\d)(pi\b)'), (m) => '${m[1]}*${m[2]}');
  r = r.replaceAllMapped(RegExp(r'(\))(pi\b)'), (m) => '${m[1]}*${m[2]}');
  return r;
}

/// Trailing percent becomes a fraction: 50% -> (50/100). A `%` between two
/// numbers is kept as modulo.
String percentToFraction(String s) {
  return s.replaceAllMapped(
    RegExp(r'(\d+(?:\.\d+)?)%(?![\d(])'),
    (m) => '(${m[1]}/100)',
  );
}

/// Full math normalization pipeline (whitespace-free output).
String normalizeMathExpression(String raw) {
  var s = raw.replaceAll(RegExp(r'\s+'), '');
  s = normalizeMathAliases(s);
  s = percentToFraction(s);
  s = insertImplicitMultiplication(s);
  return s;
}

double _evaluateNormalized(String segment) {
  if (segment.isEmpty) throw const FormatException('empty expression');
  final exp = Parser().parse(segment);
  final cm = ContextModel();
  cm.bindVariable(Variable('pi'), Number(math.pi));
  cm.bindVariable(Variable('e'), Number(math.e));
  return exp.evaluate(EvaluationType.REAL, cm);
}

/// Evaluates chained `=` expressions left to right (`2+2=4x2=` -> 8).
/// A trailing `=` is required as the explicit solve request; any
/// unevaluable segment fails the whole chain (never guess).
double? solveMathChain(String raw) {
  final normalized = normalizeMathExpression(raw);
  if (!normalized.endsWith('=')) return null;
  double? last;
  var solvedAny = false;
  for (final part in normalized.split('=')) {
    final seg = part.trim();
    if (seg.isEmpty) continue;
    try {
      last = _evaluateNormalized(seg);
      solvedAny = true;
    } catch (_) {
      return null;
    }
  }
  return solvedAny ? last : null;
}

/// Heuristic text-vs-math classification for export. Lines with `=` are
/// equations; otherwise digit/operator density decides.
bool isMathLine(String text) {
  final t = text.trim();
  if (t.isEmpty) return false;
  if (t.contains('=')) return true;
  var digits = 0;
  var mathOps = 0;
  var letters = 0;
  for (final rune in t.runes) {
    final c = String.fromCharCode(rune);
    if (c.contains(RegExp(r'[0-9]'))) {
      digits++;
    } else if ('+-*/×÷−·().%^'.contains(c)) {
      mathOps++;
    } else if (RegExp(r'[A-Za-zπ]').hasMatch(c)) {
      letters++;
    }
  }
  if (digits == 0) return false;
  return mathOps > 0 || digits >= letters * 2;
}

/// Escapes LaTeX special characters in running text.
String latexEscape(String text) {
  return text
      .replaceAll('\\', r'\textbackslash{}')
      .replaceAll('{', r'\{')
      .replaceAll('}', r'\}')
      .replaceAll('#', r'\#')
      .replaceAll('\$', r'\$')
      .replaceAll('%', r'\%')
      .replaceAll('&', r'\&')
      .replaceAll('~', r'\textasciitilde{}')
      .replaceAll('_', r'\_')
      .replaceAll('^', r'\textasciicircum{}');
}

/// Converts a recognized math string to LaTeX math content (no delimiters).
String mathToLatex(String expr) {
  var s = expr.replaceAll(RegExp(r'\s+'), '');
  s = s
      .replaceAll('×', r'\times ')
      .replaceAll('✕', r'\times ')
      .replaceAll('∗', r'\times ')
      .replaceAll('*', r'\cdot ')
      .replaceAll('·', r'\cdot ')
      .replaceAll('⋅', r'\cdot ')
      .replaceAll('÷', r'\div ')
      .replaceAll('−', '-')
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll('π', r'\pi ')
      .replaceAll('Π', r'\pi ');
  s = s.replaceAllMapped(
    RegExp(r'√\s*(\d+(?:[.,]\d+)?)'),
    (m) => '\\sqrt{${m[1]}}',
  );
  s = s.replaceAll('√', r'\sqrt{}');
  s = s.replaceAll('%', r'\%');
  return s;
}

/// Indent level (0-4) from a line's minimum x. Handwriting rarely carries
/// explicit tabs, so coarse levels keep exported structure readable.
int indentLevelForMinX(double minX) {
  if (!minX.isFinite || minX <= 0) return 0;
  return (minX / 140).floor().clamp(0, 4);
}

/// Renders one recognized line as a LaTeX fragment: `\[...\]` blocks for
/// equations, `\(...\)` for inline math, escaped text otherwise, with indent.
String latexLineForRecognizedText(String text, {int indent = 0}) {
  final t = text.trim();
  if (t.isEmpty) return '';
  final prefix = r'\quad ' * indent;
  if (isMathLine(t)) {
    final math = mathToLatex(t);
    if (t.contains('=')) return '$prefix\\[$math\\]';
    return '$prefix\\($math\\)';
  }
  return '$prefix${latexEscape(t)}';
}
