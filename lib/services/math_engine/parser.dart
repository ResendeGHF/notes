// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'complex.dart';
import 'special_functions.dart';
import 'physics_functions.dart';

class ComplexParser {
  String _input = '';
  int _pos = 0;
  bool _isRad = true;
  Complex? _ans;
  Map<String, Complex> _vars = const {};

  Complex evaluate(
    String input, {
    bool isRad = true,
    Complex? ans,
    Map<String, Complex> variables = const {},
  }) {
    _input = input.replaceAll(' ', '').toLowerCase();
    _pos = 0;
    _isRad = isRad;
    _ans = ans;
    _vars = variables;
    return _parseExpression();
  }

  Complex _parseExpression() {
    Complex left = _parseTerm();
    while (_pos < _input.length) {
      if (_match('+')) {
        left += _parseTerm();
      } else if (_match('-')) {
        left -= _parseTerm();
      } else {
        break;
      }
    }
    return left;
  }

  Complex _parseTerm() {
    Complex left = _parseFactor();
    while (_pos < _input.length) {
      if (_match('*')) {
        left *= _parseFactor();
      } else if (_match('/')) {
        left /= _parseFactor();
      } else if (_peek() == '(' || _peekAlpha()) {

        left *= _parseFactor();
      } else {
        break;
      }
    }
    return left;
  }

  Complex _parseFactor() {
    Complex base = _parseUnary();
    if (_match('!')) {
      base = _callFunction('factorial', [base]);
    }
    while (_match('^')) {
      base = base.pow(_parseUnary());
    }
    return base;
  }

  Complex _parseUnary() {
    if (_match('+')) return _parseUnary();
    if (_match('-')) return -_parseUnary();
    return _parsePrimary();
  }

  static const int _maxSumProductIterations = 25000;

  Complex _parsePrimary() {
    if (_match('(')) {
      final expr = _parseExpression();
      _expectOrAssumeClosingParen();
      return expr;
    }
    if (_peekAlpha()) {
      final name = _parseIdentifier();
      if (_match('(')) {
        if (name == 'sum' || name == 'sigma' || name == 'product' || name == 'prod') {
          final actual = (name == 'sigma') ? 'sum' : (name == 'prod' ? 'product' : name);
          return _parseSumOrProduct(actual);
        }
        final args = <Complex>[];
        if (!_match(')')) {
          args.add(_parseExpression());
          while (_match(',')) {
            args.add(_parseExpression());
          }
          _expectOrAssumeClosingParen();
        }
        return _callFunction(name, args);
      }
      return _variableValue(name);
    }
    return _parseNumber();
  }

  Complex _parseSumOrProduct(String name) {
    if (!_peekAlpha()) {
      throw FormatException('sum/product: expected index variable name');
    }
    final indexVar = _parseIdentifier();
    _expect(',');
    final fromExpr = _parseExpression();
    _expect(',');
    final toExpr = _parseExpression();
    _expectOrAssumeClosingParen();
    _expect('(');
    final bodyStart = _pos;
    _parseExpression();
    final bodyEnd = _pos;
    final bodyStr = _input.substring(bodyStart, bodyEnd);
    _expectOrAssumeClosingParen();

    final fromVal = fromExpr.real.round();
    final toVal = toExpr.real.round();
    if (fromVal > toVal) {
      return name == 'sum' ? const Complex(0) : const Complex(1);
    }
    int steps = toVal - fromVal + 1;
    if (steps > _maxSumProductIterations) {
      throw FormatException(
        'sum/product: too many iterations ($steps). Max ${_maxSumProductIterations}',
      );
    }

    final savedInput = _input;
    final savedPos = _pos;
    try {
      if (name == 'sum') {
        Complex acc = const Complex(0);
        for (int k = fromVal; k <= toVal; k++) {
          final vars = Map<String, Complex>.from(_vars)..[indexVar] = Complex(k.toDouble());
          acc += evaluate(bodyStr, isRad: _isRad, ans: _ans, variables: vars);
        }
        return acc;
      } else {
        Complex acc = const Complex(1);
        for (int k = fromVal; k <= toVal; k++) {
          final vars = Map<String, Complex>.from(_vars)..[indexVar] = Complex(k.toDouble());
          acc *= evaluate(bodyStr, isRad: _isRad, ans: _ans, variables: vars);
        }
        return acc;
      }
    } finally {
      _input = savedInput;
      _pos = savedPos;
    }
  }

  Complex _variableValue(String name) {
    if (name == 'pi') return Complex(math.pi);
    if (name == 'e') return Complex(math.e);
    if (name == 'i') return Complex.i;
    if (name == 'ans' && _ans != null) return _ans!;
    final v = _vars[name];
    if (v != null) return v;
    throw FormatException('Unknown variable: $name');
  }

  Complex _callFunction(String name, List<Complex> args) {
    Complex arg1() => args.isNotEmpty ? args[0] : const Complex(0);
    Complex arg2() => args.length > 1 ? args[1] : const Complex(0);

    double asReal(Complex c) {
      if (c.imag.abs() > 1e-9) {
        throw FormatException('Function $name expects a real value');
      }
      return c.real;
    }

    switch (name) {
      case 'sin':
        return arg1().sin();
      case 'cos':
        return arg1().cos();
      case 'tan':
        return arg1().tan();
      case 'asin':
        return arg1().asin();
      case 'acos':
        return arg1().acos();
      case 'atan':
        return arg1().atan();
      case 'sinh':
        return arg1().sinh();
      case 'cosh':
        return arg1().cosh();
      case 'tanh':
        return arg1().tanh();
      case 'asinh':
        return arg1().asinh();
      case 'acosh':
        return arg1().acosh();
      case 'atanh':
        return arg1().atanh();
      case 'exp':
        return arg1().exp();
      case 'log':
        return arg1().log();
      case 'sqrt':
        return arg1().sqrt();
      case 'abs':
        return Complex(arg1().abs());
      case 'arg':
        return Complex(arg1().arg());
      case 're':
      case 'real':
        return Complex(arg1().real);
      case 'im':
      case 'imag':
      case 'imaginary':
        return Complex(arg1().imag);
      case 'deg':
        return Complex(arg1().real * math.pi / 180.0);
      case 'rad':
        return Complex(arg1().real * 180.0 / math.pi);
      case 'gamma':
        return arg1().gamma();
      case 'beta':
        return Complex(
          SpecialFunctions.beta(asReal(arg1()), asReal(arg2())),
        );
      case 'factorial':
        return Complex(SpecialFunctions.factorial(asReal(arg1()).round()));
      case 'ncr':
        return Complex(
          SpecialFunctions.combinations(
            asReal(arg1()).round(),
            asReal(arg2()).round(),
          ),
        );
      case 'npr':
        return Complex(
          SpecialFunctions.permutations(
            asReal(arg1()).round(),
            asReal(arg2()).round(),
          ),
        );
      case 'zeta':
        return Complex(SpecialFunctions.zeta(asReal(arg1())));
      case 'digamma':
        return Complex(SpecialFunctions.digamma(asReal(arg1())));
      case 'trigamma':
        return Complex(SpecialFunctions.trigamma(asReal(arg1())));
      case 'polylog':
        return Complex(
          SpecialFunctions.polylog(asReal(arg1()), asReal(arg2())),
        );
      case 'erf':
        return Complex(SpecialFunctions.erf(asReal(arg1())));
      case 'erfc':
        return Complex(SpecialFunctions.erfc(asReal(arg1())));
      case 'sinc':
        return Complex(SpecialFunctions.sinc(asReal(arg1())));
      case 'si':
        return Complex(SpecialFunctions.si(asReal(arg1())));
      case 'ci':
        return Complex(SpecialFunctions.ci(asReal(arg1())));
      case 'dawson':
        return Complex(SpecialFunctions.dawson(asReal(arg1())));
      case 'besselj':
        return Complex(
          SpecialFunctions.besselJn(asReal(arg2()).round(), asReal(arg1())),
        );
      case 'besselj0':
        return Complex(SpecialFunctions.besselJ0(asReal(arg1())));
      case 'besselj1':
        return Complex(SpecialFunctions.besselJ1(asReal(arg1())));
      case 'airyai':
        return Complex(SpecialFunctions.airyAi(asReal(arg1())));
      case 'airyb':
        return Complex(SpecialFunctions.airyBi(asReal(arg1())));
      case 'legendre':
        return Complex(
          PhysicsFunctions.legendre(asReal(arg2()).round(), asReal(arg1())),
        );
      case 'assoclegendre':
        return Complex(
          PhysicsFunctions.assocLegendre(
            asReal(arg2()).round(),
            args.length > 2 ? asReal(args[2]).round() : 0,
            asReal(arg1()),
          ),
        );
      case 'hermite':
        return Complex(
          PhysicsFunctions.hermite(asReal(arg2()).round(), asReal(arg1())),
        );
      case 'laguerre':
        return Complex(
          PhysicsFunctions.laguerre(asReal(arg2()).round(), asReal(arg1())),
        );
    }

    throw FormatException('Unknown function: $name');
  }

  Complex _parseNumber() {
    final start = _pos;
    while (_pos < _input.length) {
      final c = _input[_pos];
      if ((c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) ||
          c == '.' ||
          c == 'e') {
        _pos++;
      } else {
        break;
      }
    }
    if (start == _pos) {
      throw FormatException('Unexpected token at $_pos');
    }
    final str = _input.substring(start, _pos);
    final value = double.tryParse(str);
    if (value == null) throw FormatException('Invalid number: $str');
    return Complex(value);
  }

  String _parseIdentifier() {
    final start = _pos;
    while (_pos < _input.length && _isAlphaNum(_input[_pos])) {
      _pos++;
    }
    return _input.substring(start, _pos);
  }

  bool _match(String ch) {
    if (_pos < _input.length && _input[_pos] == ch) {
      _pos++;
      return true;
    }
    return false;
  }

  void _expect(String ch) {
    if (!_match(ch)) {
      throw FormatException('Expected $ch at $_pos');
    }
  }

  void _expectOrAssumeClosingParen() {
    if (_match(')')) return;
    if (_pos >= _input.length) return;
    _expect(')');
  }

  String _peek() => _pos < _input.length ? _input[_pos] : '';

  bool _peekAlpha() =>
      _pos < _input.length && _isAlphaNum(_input[_pos], allowDigitFirst: false);

  bool _isAlphaNum(String c, {bool allowDigitFirst = true}) {
    final code = c.codeUnitAt(0);
    final isAlpha = (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
    final isDigit = code >= 48 && code <= 57;
    if (!allowDigitFirst && isDigit) return false;
    return isAlpha || isDigit || c == '_';
  }
}
