# `lib/components/toolbar/floating_calculator.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Context of the overlay that hosts the calculator; use for dropdowns/menus so they render on top.

### Block 2

Captures the current plot tab as an image for insertion into the note.
 Uses RepaintBoundary keys to locate the correct graph widget per tab:
 - 2D: _graphKey (CustomPainter fallback)
 - 3D Parametric: _plot3dKey
 - Scalar 3D: _scalarKey
 - Vector 3D: _vectorKey
 - ODE: _odeKey
 - Extrema: _extremaKey (with capture-mode toggle)

### Block 3

// moved to math_engine.dart
class Complex {
  final double real;
  final double imag;

  const Complex(this.real, [this.imag = 0.0]);

  static const i = Complex(0, 1);

  Complex operator +(Complex other) =>
      Complex(real + other.real, imag + other.imag);
  Complex operator -(Complex other) =>
      Complex(real - other.real, imag - other.imag);

  // (a+bi)(c+di) = (ac-bd) + (ad+bc)i
  Complex operator *(Complex other) => Complex(
    real * other.real - imag * other.imag,
    real * other.imag + imag * other.real,
  );

  // (a+bi)/(c+di) = (ac+bd)/(c^2+d^2) + (bc-ad)/(c^2+d^2)i
  Complex operator /(Complex other) {
    double denom = other.real * other.real + other.imag * other.imag;
    return Complex(
      (real * other.real + imag * other.imag) / denom,
      (imag * other.real - real * other.imag) / denom,
    );
  }

  // Z^W = e^(W * ln(Z))
  Complex pow(Complex other) {
    if (real == 0 && imag == 0) return const Complex(0);
    final logZ = log(); // ln(r) + i*theta
    final product = logZ * other; // (lnZ * w)
    return product.exp(); // e^(lnZ * w)
  }

  double abs() => math.sqrt(real * real + imag * imag);
  double arg() => math.atan2(imag, real);

  // --- Circular Trig ---
  Complex sin() =>
      Complex(math.sin(real) * _cosh(imag), math.cos(real) * _sinh(imag));
  Complex cos() =>
      Complex(math.cos(real) * _cosh(imag), -math.sin(real) * _sinh(imag));
  Complex tan() {
    final num = sin();
    final den = cos();
    if (den.abs() < 1e-10) throw FormatException('Tan undefined');
    return num / den;
  }

  // --- Hyperbolic Trig ---
  Complex exp() {
    final e = math.exp(real);
    return Complex(e * math.cos(imag), e * math.sin(imag));
  }

  Complex sinh() {
    final e1 = exp();
    final e2 = (this * const Complex(-1)).exp();
    return (e1 - e2) * const Complex(0.5);
  }

  Complex cosh() {
    final e1 = exp();
    final e2 = (this * const Complex(-1)).exp();
    return (e1 + e2) * const Complex(0.5);
  }

  Complex tanh() => sinh() / cosh();

  // --- Inverse Circular Trig ---
  Complex asin() {
    final i = Complex.i;
    final z = this;
    final root = (const Complex(1) - (z * z)).sqrt();
    final term = (i * z) + root;
    return term.log() * i * const Complex(-1);
  }

  Complex acos() {
    return const Complex(math.pi / 2) - asin();
  }

  Complex atan() {
    final i = Complex.i;
    final z = this;
    final n = const Complex(1) - (i * z);
    final d = const Complex(1) + (i * z);
    return (n / d).log() * i * const Complex(0.5);
  }

  // --- Inverse Hyperbolic Trig ---
  Complex asinh() {
    final z = this;
    final root = (z * z + const Complex(1)).sqrt();
    return (z + root).log();
  }

  Complex acosh() {
    final z = this;
    final root = (z * z - const Complex(1)).sqrt();
    return (z + root).log();
  }

  Complex atanh() {
    final z = this;
    final n = const Complex(1) + z;
    final d = const Complex(1) - z;
    return (n / d).log() * const Complex(0.5);
  }

  Complex log() => Complex(math.log(abs()), arg());

  // sqrt(z) = z^0.5
  Complex sqrt() => pow(const Complex(0.5));

  double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;
  double _cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;

  // --- Combinatorics Logic ---
  static Complex nCr(Complex n, Complex r) {
    int ni = n.real.round();
    int ri = r.real.round();
    if (ri < 0 || ri > ni) return const Complex(0);
    return Complex(_combinations(ni, ri).toDouble());
  }

  static Complex nPr(Complex n, Complex r) {
    int ni = n.real.round();
    int ri = r.real.round();
    if (ri < 0 || ri > ni) return const Complex(0);
    return Complex(_permutations(ni, ri).toDouble());
  }

  static double _combinations(int n, int k) {
    if (k < 0 || k > n) return 0;
    if (k == 0 || k == n) return 1;
    if (k > n / 2) k = n - k;
    double res = 1;
    for (int i = 1; i <= k; i++) {
      res = res * (n - i + 1) / i;
    }
    return res;
  }

  static double _permutations(int n, int k) {
    if (k < 0 || k > n) return 0;
    double res = 1;
    for (int i = 0; i < k; i++) {
      res = res * (n - i);
    }
    return res;
  }

  @override
  String toString({int precision = 4}) {
    String r = _fmt(real, precision);
    String i = _fmt(imag.abs(), precision);
    if (imag == 0) return r;
    if (real == 0) return '${imag < 0 ? "-" : ""}i$i';
    return '$r ${imag < 0 ? "-" : "+"} $i'
        'i';
  }

  String _fmt(double v, int p) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v
        .toStringAsFixed(p)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }
}

class _ComplexParser {
  String _input = '';
  int _pos = 0;
  bool _isRad = true;
  Complex? _ans;

  Complex evaluate(String input, {bool isRad = true, Complex? ans}) {
    _input = input.replaceAll(' ', '').toLowerCase();
    _pos = 0;
    _isRad = isRad;
    _ans = ans;
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
      } else if (_peek() == '(' ||
          _peekAlpha() ||
          _peekDigit() ||
          _peek() == 'i') {
        left *= _parseFactor();
      } else {
        break;
      }
    }
    return left;
  }

  Complex _parseFactor() {
    if (_match('+')) return _parseFactor();
    if (_match('-')) return _parseFactor() * const Complex(-1);

    Complex base;
    if (_match('(')) {
      base = _parseExpression();
      _consume(')');
    } else if (_match('i')) {
      base = Complex.i;
    } else if (_peekDigit() || _peek() == '.') {
      base = Complex(_parseNumber());
    } else if (_peekAlpha()) {
      base = _parseFunction();
    } else {
      if (_input.startsWith('pi', _pos)) {
        _pos += 2;
        base = Complex(math.pi);
      } else if (_match('e')) {
        base = Complex(math.e);
      } else if (_input.startsWith('ans', _pos)) {
        _pos += 3;
        base = _ans ?? const Complex(0);
      } else {
        throw FormatException('Unexpected char at $_pos');
      }
    }

    if (_match('^')) {
      Complex exponent = _parseFactor();
      return base.pow(exponent);
    }

    return base;
  }

  Complex _parseFunction() {
    String name = '';
    while (_pos < _input.length && _peekAlpha()) {
      name += _consumeChar();
    }

    if (name == 'log' && _pos < _input.length && _peekDigit()) {
      while (_pos < _input.length && _peekDigit()) {
        name += _consumeChar();
      }
    }

    if (name == 'pi') return Complex(math.pi);
    if (name == 'e') return Complex(math.e);
    if (name == 'i') return Complex.i;
    if (name == 'ans') return _ans ?? const Complex(0);

    if (_match('(')) {
      List<Complex> args = [];
      args.add(_parseExpression());
      while (_match(',')) {
        args.add(_parseExpression());
      }
      _consume(')');

      if (!_isRad && args.isNotEmpty && ['sin', 'cos', 'tan'].contains(name)) {
        args[0] = args[0] * Complex(math.pi / 180.0);
      }

      Complex res;
      switch (name) {
        case 'sin':
          res = args[0].sin();
          break;
        case 'cos':
          res = args[0].cos();
          break;
        case 'tan':
          res = args[0].tan();
          break;
        case 'asin':
          res = args[0].asin();
          break;
        case 'acos':
          res = args[0].acos();
          break;
        case 'atan':
          res = args[0].atan();
          break;
        case 'sinh':
          res = args[0].sinh();
          break;
        case 'cosh':
          res = args[0].cosh();
          break;
        case 'tanh':
          res = args[0].tanh();
          break;
        case 'asinh':
          res = args[0].asinh();
          break;
        case 'acosh':
          res = args[0].acosh();
          break;
        case 'atanh':
          res = args[0].atanh();
          break;
        case 'abs':
          res = Complex(args[0].abs());
          break;
        case 'sqrt':
          res = args[0].sqrt();
          break;
        case 'log':
        case 'ln':
          res = args[0].log();
          break;
        case 'exp':
          res = args[0].exp();
          break;
        case 'log10':
          res = args[0].log() / Complex(math.ln10);
          break;
        case 'ncr':
          if (args.length < 2) throw FormatException('nCr needs 2 arguments');
          res = Complex.nCr(args[0], args[1]);
          break;
        case 'npr':
          if (args.length < 2) throw FormatException('nPr needs 2 arguments');
          res = Complex.nPr(args[0], args[1]);
          break;
        default:
          throw FormatException('Unknown func: $name');
      }

      if (!_isRad && ['asin', 'acos', 'atan'].contains(name)) {
        res = res * Complex(180.0 / math.pi);
      }

      return res;
    }
    throw FormatException('Function needs parens');
  }

  double _parseNumber() {
    int start = _pos;
    while (_pos < _input.length && (_peekDigit() || _peek() == '.')) {
      _pos++;
    }
    return double.parse(_input.substring(start, _pos));
  }

  bool _match(String char) {
    if (_pos < _input.length && _input[_pos] == char) {
      _pos++;
      return true;
    }
    return false;
  }

  void _consume(String char) {
    if (!_match(char)) throw FormatException('Expected $char');
  }

  String _consumeChar() => _input[_pos++];
  String _peek() => _pos < _input.length ? _input[_pos] : '';
  bool _peekDigit() =>
      _pos < _input.length && RegExp(r'[0-9]').hasMatch(_input[_pos]);
  bool _peekAlpha() =>
      _pos < _input.length && RegExp(r'[a-z]').hasMatch(_input[_pos]);
}

## Imports

- `dart:async`
- `dart:math`
- `dart:ui`
- `package:flutter/foundation.dart`
- `package:flutter/material.dart`
- `package:flutter/rendering.dart`
- `package:flutter/scheduler.dart`
- `package:flutter/services.dart`
- `package:saber/components/toolbar/2Dplot.dart`
- `package:saber/components/toolbar/3Dplot.dart`
- `package:saber/components/toolbar/3Dscalar.dart`
- `package:saber/components/toolbar/3Dvector.dart`
- `package:saber/components/toolbar/calculus_pane.dart`
- `package:saber/components/toolbar/extrema_pane.dart`
- `package:saber/components/toolbar/ode_isolate.dart`
- `package:saber/components/toolbar/ode_visualizer.dart`
- `package:saber/components/toolbar/plot_animation_metadata.dart`
- `package:saber/components/toolbar/unit_converter.dart`
- `package:saber/services/math_engine/math_engine.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `OnInsertImage`
- `FunctionDef`
- `ScalarFuncDef`
- `VectorFuncDef`
- `OdeIntegrationMethod`
- `OdeIntegrationMethodLabel`
- `OdePresetConfig`
- `_CalcCache`
- `FloatingCalculator`
- `_FloatingCalculatorState`
- `_KeyType`
- `_Key`
- `Function()`
- `dispose()`
- `initState()`
- `PointerInterceptor()`
- `build()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
