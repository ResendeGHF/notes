// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/services/math_text_utils.dart';

import '../helpers/test_stroke_factory.dart';

void main() {
  group('solveMathChain', () {
    test('solves a single expression with trailing equals', () {
      expect(solveMathChain('2+2='), 4);
    });

    test('chains through intermediate results', () {
      // 2+2=4 then 4x2= (result appended by the user) -> 8.
      expect(solveMathChain('2+2=4x2='), 8);
    });

    test('requires a trailing equals as the solve request', () {
      expect(solveMathChain('2+2'), isNull);
      expect(solveMathChain('2+2=4'), isNull);
    });

    test('fails on unevaluable segments instead of guessing', () {
      expect(solveMathChain('x2='), isNull);
      expect(solveMathChain('2+*2='), isNull);
      expect(solveMathChain('='), isNull);
    });

    test('handles decimal commas, implicit multiplication and percent', () {
      expect(solveMathChain('3,14*2='), closeTo(6.28, 1e-9));
      expect(solveMathChain('2(3+1)='), 8);
      expect(solveMathChain('(2+1)(3+2)='), 15);
      expect(solveMathChain('50%='), closeTo(0.5, 1e-9));
      expect(solveMathChain('10%3='), 1);
    });

    test('handles pi, euler, powers and unicode operators', () {
      expect(solveMathChain('pi*2='), closeTo(6.283185307179586, 1e-9));
      expect(solveMathChain('2^3='), 8);
      expect(solveMathChain('2×3='), 6);
      expect(solveMathChain('8÷2='), 4);
      expect(solveMathChain('−2+5='), 3);
      expect(solveMathChain('√4+1='), 3);
    });
  });

  group('isMathLine', () {
    test('classifies equations, math and text', () {
      expect(isMathLine('2+2=4'), isTrue);
      expect(isMathLine('42'), isTrue);
      expect(isMathLine('hello'), isFalse);
      expect(isMathLine('call me at 5'), isFalse);
      expect(isMathLine(''), isFalse);
    });
  });

  group('latex', () {
    test('escapes text specials', () {
      expect(latexEscape('100% & _x_'), r'100\% \& \_x\_');
    });

    test('converts math operators', () {
      expect(mathToLatex('2×2=4'), contains(r'\times'));
      expect(mathToLatex('π+1'), contains(r'\pi'));
    });

    test('wraps blocks vs inline vs text', () {
      expect(latexLineForRecognizedText('2+2=4'), startsWith(r'\['));
      expect(latexLineForRecognizedText('42'), startsWith(r'\('));
      expect(latexLineForRecognizedText('hello'), 'hello');
      expect(latexLineForRecognizedText('hello', indent: 2), startsWith(r'\quad'));
    });
  });

  group('splitLineTokens', () {
    test('orders by x and groups known answers', () {
      final left = testPolylineStroke(
        toolId: ToolId.fountainPen,
        y: 100,
        x0: 0,
        x1: 100,
      );
      final answer = testPolylineStroke(
        toolId: ToolId.fountainPen,
        y: 100,
        x0: 120,
        x1: 160,
      );
      final right = testPolylineStroke(
        toolId: ToolId.fountainPen,
        y: 100,
        x0: 200,
        x1: 300,
      );
      tagSolverResultStrokes([answer], '4');

      // Pass in scrambled order; tokens must come out x-ordered.
      final tokens = splitLineTokens([right, answer, left]);
      expect(tokens.length, 3);
      expect(tokens[0].isKnown, isFalse);
      expect(tokens[0].run, contains(left));
      expect(tokens[1].isKnown, isTrue);
      expect(tokens[1].knownText, '4');
      expect(tokens[1].known, contains(answer));
      expect(tokens[2].isKnown, isFalse);
      expect(tokens[2].run, contains(right));
    });

    test('plain ink yields a single run', () {
      final a = testPolylineStroke(
        toolId: ToolId.ballpointPen,
        y: 50,
        x0: 10,
        x1: 60,
      );
      final tokens = splitLineTokens([a]);
      expect(tokens.length, 1);
      expect(tokens.single.isKnown, isFalse);
    });
  });

  group('tagSolverResultStrokes', () {
    test('unknown strokes have no token', () {
      final s = testPolylineStroke(toolId: ToolId.fountainPen);
      expect(knownResultOf(s), isNull);
    });
  });
}
