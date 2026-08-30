import 'package:flutter_test/flutter_test.dart';
import 'package:saber/services/math_engine/math_engine.dart';

void main() {
  group('ComplexParser (floating calculator engine)', () {
    final parser = ComplexParser();

    test('basic arithmetic', () {
      expect(parser.evaluate('2+3').real, closeTo(5, 1e-9));
      expect(parser.evaluate('10-4').real, closeTo(6, 1e-9));
      expect(parser.evaluate('3*4').real, closeTo(12, 1e-9));
      expect(parser.evaluate('15/3').real, closeTo(5, 1e-9));
    });

    test('parentheses and power', () {
      expect(parser.evaluate('(1+2)*3').real, closeTo(9, 1e-9));
      expect(parser.evaluate('2^8').real, closeTo(256, 1e-9));
    });

    test('implicit multiplication', () {
      expect(parser.evaluate('2pi').real, closeTo(2 * 3.141592653589793, 1e-6));
    });

    test('sum supports both syntaxes', () {
      expect(parser.evaluate('sum(n,1,4)(n^2)').real, closeTo(30, 1e-9));
      expect(parser.evaluate('sum(n^2,n,1,4)').real, closeTo(30, 1e-9));
    });

    test('product supports both syntaxes', () {
      expect(parser.evaluate('product(n,1,4)(n)').real, closeTo(24, 1e-9));
      expect(parser.evaluate('product(n,n,1,4)').real, closeTo(24, 1e-9));
    });

    test('sum/product can be nested with expressions', () {
      final expr = 'sum(product(k,k,1,n),n,1,4)';
      expect(parser.evaluate(expr).real, closeTo(33, 1e-9));
    });
  });
}
