# `lib/components/toolbar/3Dplot.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

View-dependent LOD: zoomed out = coarser (fewer triangles), zoomed in = finer.
 Keeps quality where the user looks while avoiding lag when viewing the whole surface.

### Block 2

Same as _effectiveGridSteps but for an arbitrary zoom (used to detect tier changes).

### Block 3

// moved to math_engine.dart
class _Complex {
  final double real;
  final double imag;
  const _Complex(this.real, [this.imag = 0.0]);

  static const i = _Complex(0, 1);

  _Complex operator +(_Complex o) => _Complex(real + o.real, imag + o.imag);
  _Complex operator -(_Complex o) => _Complex(real - o.real, imag - o.imag);
  _Complex operator *(_Complex o) =>
      _Complex(real * o.real - imag * o.imag, real * o.imag + imag * o.real);
  _Complex operator /(_Complex o) {
    final double d = o.real * o.real + o.imag * o.imag;
    return _Complex(
      (real * o.real + imag * o.imag) / d,
      (imag * o.real - real * o.imag) / d,
    );
  }

  _Complex pow(_Complex o) {
    if (real == 0 && imag == 0) return const _Complex(0);
    return (log() * o).exp();
  }

  double abs() => math.sqrt(real * real + imag * imag);
  double arg() => math.atan2(imag, real);
  _Complex log() => _Complex(math.log(abs()), arg());
  _Complex exp() {
    final double e = math.exp(real);
    return _Complex(e * math.cos(imag), e * math.sin(imag));
  }

  _Complex sin() =>
      _Complex(math.sin(real) * _cosh(imag), math.cos(real) * _sinh(imag));
  _Complex cos() =>
      _Complex(math.cos(real) * _cosh(imag), -math.sin(real) * _sinh(imag));
  _Complex tan() {
    final n = sin(), d = cos();
    if (d.abs() < 1e-10) return const _Complex(0);
    return n / d;
  }

  _Complex sqrt() => pow(const _Complex(0.5));
  double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;
  double _cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;

  // Gamma Function Approximation (Lanczos)
  static const List<double> _p = [
    0.99999999999980993,
    676.5203681218851,
    -1259.1392167224028,
    771.32342877765313,
    -176.61502916214059,
    12.507343278686905,
    -0.13857109526572012,
    9.9843695780195716e-6,
    1.5056327351493116e-7,
  ];
  _Complex gamma() {
    if (real < 0.5) {
      final pi = const _Complex(math.pi);
      final sinPiZ = (this * pi).sin();
      if (sinPiZ.abs() < 1e-15) return const _Complex(0); // Pole check
      return pi / (sinPiZ * ((const _Complex(1) - this).gamma()));
    }
    final _Complex z = this - const _Complex(1);
    _Complex x = _Complex(_p[0]);
    for (int i = 1; i < _p.length; i++) {
      x += _Complex(_p[i]) / (z + _Complex(i.toDouble()));
    }
    final _Complex t = z + const _Complex(7.5);
    return _Complex(2.50662827463) *
        (t.pow(z + const _Complex(0.5))) *
        (t * const _Complex(-1)).exp() *
        x;
  }
}

class _ComplexParser {
  String _input = '';
  int _pos = 0;
  Map<String, _Complex> _vars = {};

  _Complex evaluate(String input, Map<String, _Complex> vars) {
    _input = input.toLowerCase().replaceAll(' ', '');
    _pos = 0;
    _vars = vars;
    return _parseExpression();
  }

  _Complex _parseExpression() {
    _Complex left = _parseTerm();
    while (_pos < _input.length) {
      if (_match('+'))
        left += _parseTerm();
      else if (_match('-'))
        left -= _parseTerm();
      else
        break;
    }
    return left;
  }

  _Complex _parseTerm() {
    _Complex left = _parseFactor();
    while (_pos < _input.length) {
      if (_match('*'))
        left *= _parseFactor();
      else if (_match('/'))
        left /= _parseFactor();
      else if (_peek() == '(' ||
          _peekAlpha() ||
          _peekDigit() ||
          _peek() == 'i') {
        left *= _parseFactor();
      } else
        break;
    }
    return left;
  }

  _Complex _parseFactor() {
    if (_match('+')) return _parseFactor();
    if (_match('-')) return _parseFactor() * const _Complex(-1);

    _Complex base;
    if (_match('(')) {
      base = _parseExpression();
      _consume(')');
    } else if (_peekDigit() || _peek() == '.') {
      base = _Complex(_parseNumber());
    } else if (_peekAlpha()) {
      base = _parseFunctionOrVar();
    } else {
      throw FormatException('Unexpected char');
    }

    if (_match('^')) {
      final _Complex exp = _parseFactor();
      base = base.pow(exp);
    }
    return base;
  }

  _Complex _parseFunctionOrVar() {
    String name = '';
    while (_pos < _input.length && _peekAlpha()) name += _consumeChar();

    if (name == 'i') return _Complex.i;
    if (name == 'pi') return _Complex(math.pi);
    if (name == 'e') return _Complex(math.e);
    if (_vars.containsKey(name)) return _vars[name]!;

    if (_match('(')) {
      final _Complex arg = _parseExpression();
      _consume(')');
      switch (name) {
        case 'sin':
          return arg.sin();
        case 'cos':
          return arg.cos();
        case 'tan':
          return arg.tan();
        case 'exp':
          return arg.exp();
        case 'log':
        case 'ln':
          return arg.log();
        case 'sqrt':
          return arg.sqrt();
        case 'abs':
          return _Complex(arg.abs());
        case 'gamma':
          return arg.gamma();
        default:
          return arg;
      }
    }
    return const _Complex(0);
  }

  double _parseNumber() {
    final int start = _pos;
    while (_pos < _input.length && (_peekDigit() || _peek() == '.')) _pos++;
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
    if (!_match(char)) throw FormatException();
  }

  String _consumeChar() => _input[_pos++];
  String _peek() => _pos < _input.length ? _input[_pos] : '';
  bool _peekDigit() =>
      _pos < _input.length && RegExp(r'[0-9]').hasMatch(_input[_pos]);
  bool _peekAlpha() =>
      _pos < _input.length && RegExp(r'[a-z]').hasMatch(_input[_pos]);
}

## Imports

- `dart:math`
- `dart:typed_data`
- `dart:ui`
- `package:flutter/material.dart`
- `package:flutter/scheduler.dart`
- `package:saber/services/math_engine/math_engine.dart`
- `package:vector_math/vector_math_64.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `_Complex`
- `PlotLine3D`
- `Plot3DWidget`
- `_Plot3DWidgetState`
- `_Point3D`
- `_Triangle`
- `_ProcessedMesh`
- `_SortableTri`
- `_VertexMeshPainter`
- `initState()`
- `dispose()`
- `didUpdateWidget()`
- `getZ()`
- `addTri()`
- `build()`
- `paint()`
- `getColor()`
- `proj()`
- `drawTicks()`
- `drawLabel()`
- `shouldRepaint()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
