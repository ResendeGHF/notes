// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:saber/services/math_engine/math_engine.dart';

class CalculusResult {
  const CalculusResult({
    required this.value,
    required this.errorEstimate,
    this.details,
  });

  final double value;
  final double errorEstimate;
  final String? details;
}

enum DerivativeMethod {
  complexStep,
  richardson,
  ridders,
  fivePointStencil,
  adaptiveCentral,
}

extension DerivativeMethodExt on DerivativeMethod {
  String get label {
    switch (this) {
      case DerivativeMethod.complexStep:
        return 'Complex-step';
      case DerivativeMethod.richardson:
        return 'Richardson extrapolation';
      case DerivativeMethod.ridders:
        return "Ridders' method";
      case DerivativeMethod.fivePointStencil:
        return 'Five-point stencil';
      case DerivativeMethod.adaptiveCentral:
        return 'Adaptive central difference';
    }
  }
}

enum IntegrationMethod {
  gaussKronrod,
  adaptiveSimpson,
  clenshawCurtis,
  romberg,
  tanhSinh,
}

extension IntegrationMethodExt on IntegrationMethod {
  String get label {
    switch (this) {
      case IntegrationMethod.gaussKronrod:
        return 'Gauss–Kronrod (7–15)';
      case IntegrationMethod.adaptiveSimpson:
        return 'Adaptive Simpson';
      case IntegrationMethod.clenshawCurtis:
        return 'Clenshaw–Curtis';
      case IntegrationMethod.romberg:
        return 'Romberg';
      case IntegrationMethod.tanhSinh:
        return 'Tanh-sinh (double exponential)';
    }
  }
}

class CalculusPane extends StatefulWidget {
  const CalculusPane({
    super.key,
    required this.colorScheme,
    required this.isDark,
    this.overlayContext,
  });

  final ColorScheme colorScheme;
  final bool isDark;

  final BuildContext? overlayContext;

  @override
  State<CalculusPane> createState() => _CalculusPaneState();
}

class _CalculusPaneState extends State<CalculusPane> {

  bool _isDerivative = true;

  bool _is2D = true;

  final _exprCtrl = TextEditingController(text: 'x^2*sin(x)');
  final _xPointCtrl = TextEditingController(text: '1');
  final _yPointCtrl = TextEditingController(text: '0');
  final _dirXCtrl = TextEditingController(text: '1');
  final _dirYCtrl = TextEditingController(text: '0');
  final _aCtrl = TextEditingController(text: '0');
  final _bCtrl = TextEditingController(text: '1');
  final _yMinCtrl = TextEditingController(text: '0');
  final _yMaxCtrl = TextEditingController(text: '1');

  DerivativeMethod _derivMethod = DerivativeMethod.complexStep;
  IntegrationMethod _integMethod = IntegrationMethod.gaussKronrod;

  bool _isDerivMethodExpanded = false;
  bool _isIntegMethodExpanded = false;

  String _resultText = '';
  String _errorText = '';
  bool _isComputing = false;

  static final _parser = ComplexParser();

  @override
  void dispose() {
    _exprCtrl.dispose();
    _xPointCtrl.dispose();
    _yPointCtrl.dispose();
    _dirXCtrl.dispose();
    _dirYCtrl.dispose();
    _aCtrl.dispose();
    _bCtrl.dispose();
    _yMinCtrl.dispose();
    _yMaxCtrl.dispose();
    super.dispose();
  }

  String get _expr => _exprCtrl.text
      .replaceAll('×', '*')
      .replaceAll('√', 'sqrt')
      .replaceAll('÷', '/')
      .replaceAll('π', 'pi')
      .trim();

  double _eval2D(double x) {
    final r = _parser.evaluate(_expr, variables: {'x': Complex(x)});
    if (r.imag.abs() > 1e-12) {
      throw FormatException('Function must be real-valued at x=$x');
    }
    return r.real;
  }

  Complex _eval2DComplex(Complex x) {
    return _parser.evaluate(_expr, variables: {'x': x});
  }

  double _eval3D(double x, double y) {
    final r = _parser.evaluate(
      _expr,
      variables: {'x': Complex(x), 'y': Complex(y)},
    );
    if (r.imag.abs() > 1e-12) {
      throw FormatException('Function must be real-valued at ($x,$y)');
    }
    return r.real;
  }

  CalculusResult _derivativeComplexStep2D(double x) {
    const h = 1e-20;
    final scale = math.max(1.0, x.abs());
    final step = h * scale;
    final im = _eval2DComplex(Complex(x, step)).imag;
    final deriv = im / step;
    final err = step * step * 1e-10;
    return CalculusResult(value: deriv, errorEstimate: err.abs());
  }

  CalculusResult _derivativeRichardson2D(double x) {
    double h = 0.1 * (1 + x.abs());
    double d2 = (_eval2D(x + h) - _eval2D(x - h)) / (2 * h);
    for (int i = 0; i < 8; i++) {
      h /= 2;
      final d1 = d2;
      d2 = (_eval2D(x + h) - _eval2D(x - h)) / (2 * h);
      final extrapolated = (4 * d2 - d1) / 3;
      if ((d2 - d1).abs() < 1e-15 * (extrapolated.abs() + 1e-15)) {
        return CalculusResult(
          value: extrapolated,
          errorEstimate: (extrapolated - d2).abs(),
        );
      }
    }
    final h2 = h * 2;
    final d1 = (_eval2D(x + h2) - _eval2D(x - h2)) / (2 * h2);
    return CalculusResult(value: d2, errorEstimate: (d2 - d1).abs());
  }

  CalculusResult _derivativeRidders2D(double x) {
    const n = 10;
    final h0 = 0.1 * (1 + x.abs());
    final d = List.filled(n + 1, 0.0);
    final h = List.filled(n + 1, 0.0);
    for (int i = 0; i <= n; i++) {
      h[i] = h0 / (1 << i);
      d[i] = (_eval2D(x + h[i]) - _eval2D(x - h[i])) / (2 * h[i]);
    }
    for (int k = 1; k <= n; k++) {
      for (int i = n; i >= k; i--) {
        final c = (h[i] * h[i]) / (h[i - k] * h[i - k]);
        d[i] = (c * d[i] - d[i - 1]) / (c - 1);
      }
    }
    final value = d[n];
    final err = (d[n] - d[n - 1]).abs();
    return CalculusResult(value: value, errorEstimate: err);
  }

  CalculusResult _derivativeFivePoint2D(double x) {
    final scale = 1e-4 * (1 + x.abs());
    final h = scale.clamp(1e-10, 0.1);
    final fm2 = _eval2D(x - 2 * h);
    final fm1 = _eval2D(x - h);
    final fp1 = _eval2D(x + h);
    final fp2 = _eval2D(x + 2 * h);
    final deriv = (fm2 - 8 * fm1 + 8 * fp1 - fp2) / (12 * h);
    final err = h * h * h * h / 30;
    return CalculusResult(value: deriv, errorEstimate: err);
  }

  CalculusResult _derivativeAdaptiveCentral2D(double x) {
    double h = 0.01 * (1 + x.abs());
    double bestD = 0;
    double bestErr = double.infinity;
    for (int step = 0; step < 20; step++) {
      final fp = _eval2D(x + h);
      final fm = _eval2D(x - h);
      final d = (fp - fm) / (2 * h);
      final truncErr = h * h / 6;
      final roundErr = 2e-16 * (_eval2D(x).abs() + 1) / h;
      final totalErr = truncErr + roundErr;
      if (totalErr < bestErr) {
        bestErr = totalErr;
        bestD = d;
      }
      h /= 1.5;
      if (h < 1e-15) break;
    }
    return CalculusResult(value: bestD, errorEstimate: bestErr);
  }

  CalculusResult _derivative2D(double x) {
    switch (_derivMethod) {
      case DerivativeMethod.complexStep:
        return _derivativeComplexStep2D(x);
      case DerivativeMethod.richardson:
        return _derivativeRichardson2D(x);
      case DerivativeMethod.ridders:
        return _derivativeRidders2D(x);
      case DerivativeMethod.fivePointStencil:
        return _derivativeFivePoint2D(x);
      case DerivativeMethod.adaptiveCentral:
        return _derivativeAdaptiveCentral2D(x);
    }
  }

  double _partialX3D(double x, double y, [double hScale = 1.0]) {
    final h = 1e-8 * (1 + x.abs()) * hScale;
    final fp = _eval3D(x + h, y);
    final fm = _eval3D(x - h, y);
    return (fp - fm) / (2 * h);
  }

  double _partialY3D(double x, double y, [double hScale = 1.0]) {
    final h = 1e-8 * (1 + y.abs()) * hScale;
    final fp = _eval3D(x, y + h);
    final fm = _eval3D(x, y - h);
    return (fp - fm) / (2 * h);
  }

  CalculusResult _derivative3D(double x, double y) {
    final dx = double.tryParse(_dirXCtrl.text) ?? 1.0;
    final dy = double.tryParse(_dirYCtrl.text) ?? 0.0;
    final px = _partialX3D(x, y);
    final py = _partialY3D(x, y);
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-20) {
      return CalculusResult(
        value: 0,
        errorEstimate: 0,
        details: '∂f/∂x = $px, ∂f/∂y = $py',
      );
    }
    final ux = dx / len;
    final uy = dy / len;
    final directional = px * ux + py * uy;
    final err = 1e-10 * (px.abs() + py.abs() + 1);
    return CalculusResult(
      value: directional,
      errorEstimate: err,
      details:
          '∂f/∂x = $px, ∂f/∂y = $py; directional (${ux.toStringAsPrecision(3)}, ${uy.toStringAsPrecision(3)})',
    );
  }

  static const _gkNodes7 = [
    -0.9491079123427585,
    -0.7415311855993945,
    -0.4058451513773972,
    0.0,
    0.4058451513773972,
    0.7415311855993945,
    0.9491079123427585,
  ];
  static const _gkWeights7 = [
    0.1294849661688697,
    0.2797053914892766,
    0.3818300505051189,
    0.4179591836734694,
    0.3818300505051189,
    0.2797053914892766,
    0.1294849661688697,
  ];
  static const _gkNodes15 = [
    -0.9914553711208126,
    -0.9491079123427585,
    -0.8648644233597691,
    -0.7415311855993945,
    -0.5860872354676911,
    -0.4058451513773972,
    -0.2077849550078985,
    0.0,
    0.2077849550078985,
    0.4058451513773972,
    0.5860872354676911,
    0.7415311855993945,
    0.8648644233597691,
    0.9491079123427585,
    0.9914553711208126,
  ];
  static const _gkWeights15 = [
    0.02293532201052922,
    0.06309209262997855,
    0.1047900103222502,
    0.1406532597155259,
    0.1690047266392679,
    0.1903505780647854,
    0.2044329400752982,
    0.2094821410847278,
    0.2044329400752982,
    0.1903505780647854,
    0.1690047266392679,
    0.1406532597155259,
    0.1047900103222502,
    0.06309209262997855,
    0.02293532201052922,
  ];

  CalculusResult _integrateGaussKronrod2D(double a, double b) {
    final mid = (a + b) / 2;
    final half = (b - a) / 2;
    double g7 = 0, k15 = 0;
    for (int i = 0; i < 7; i++) {
      final x = mid + half * _gkNodes7[i];
      g7 += _gkWeights7[i] * _eval2D(x);
    }
    for (int i = 0; i < 15; i++) {
      final x = mid + half * _gkNodes15[i];
      k15 += _gkWeights15[i] * _eval2D(x);
    }
    g7 *= half;
    k15 *= half;
    final value = k15;
    final err = (200 * (k15 - g7).abs()).clamp(1e-20, double.infinity);
    return CalculusResult(value: value, errorEstimate: err);
  }

  double _simpson2D(double a, double b) {
    final m = (a + b) / 2;
    return (b - a) / 6 * (_eval2D(a) + 4 * _eval2D(m) + _eval2D(b));
  }

  double _adaptiveSimpsonRecurse(
    double a,
    double b,
    double tol,
    double sAb,
    int depth,
  ) {
    if (depth > 50) return sAb;
    final m = (a + b) / 2;
    final sAm = _simpson2D(a, m);
    final sMb = _simpson2D(m, b);
    final sAmMb = sAm + sMb;
    if ((sAmMb - sAb).abs() < 15 * tol) {
      return sAmMb + (sAmMb - sAb) / 15;
    }
    return _adaptiveSimpsonRecurse(a, m, tol / 2, sAm, depth + 1) +
        _adaptiveSimpsonRecurse(m, b, tol / 2, sMb, depth + 1);
  }

  CalculusResult _integrateAdaptiveSimpson2D(double a, double b) {
    const tol = 1e-10;
    final s0 = _simpson2D(a, b);
    final value = _adaptiveSimpsonRecurse(a, b, tol, s0, 0);
    final err = tol * (b - a).abs();
    return CalculusResult(value: value, errorEstimate: err);
  }

  CalculusResult _integrateClenshawCurtis2D(double a, double b) {
    const n = 32;
    final angles = List.generate(n + 1, (i) => math.pi * i / n);
    final nodes = angles
        .map((t) => (a + b) / 2 + (b - a) / 2 * math.cos(t))
        .toList();
    final f = nodes.map((x) => _eval2D(x)).toList();
    final coeff = List.filled(n + 1, 0.0);
    for (int k = 0; k <= n; k++) {
      for (int j = 0; j <= n; j++) {
        coeff[k] += f[j] * math.cos(k * angles[j]);
      }
      coeff[k] *= (k == 0 || k == n ? 0.5 : 1.0) / n;
    }
    double sum = 0;
    for (int k = 0; k <= n; k += 2) {
      if (k == 0) {
        sum += coeff[k] * (1 - 1 / (k * k - 1 + 1e-30));
      } else {
        sum += coeff[k] * 2.0 / (1 - k * k);
      }
    }
    final value = (b - a) / 2 * sum;
    final err =
        (b - a).abs() *
        1e-12 *
        (coeff.map((c) => c.abs()).reduce((a, b) => a + b));
    return CalculusResult(value: value, errorEstimate: err);
  }

  CalculusResult _integrateRomberg2D(double a, double b) {
    const maxLevel = 20;
    final r = List.filled(maxLevel + 1, 0.0);
    int n = 1;
    double h = b - a;
    r[0] = h / 2 * (_eval2D(a) + _eval2D(b));
    for (int level = 1; level <= maxLevel; level++) {
      n *= 2;
      h /= 2;
      double sum = 0;
      for (int i = 1; i < n; i += 2) {
        sum += _eval2D(a + i * h);
      }
      r[level] = r[level - 1] / 2 + h * sum;
      for (int k = level - 1; k >= 0; k--) {
        final factor = 1 << (2 * (level - k));
        r[k] = (factor * r[k + 1] - r[k]) / (factor - 1);
      }
      if (level >= 3 && (r[0] - r[1]).abs() < 1e-14 * (r[0].abs() + 1)) {
        return CalculusResult(value: r[0], errorEstimate: (r[0] - r[1]).abs());
      }
    }
    return CalculusResult(value: r[0], errorEstimate: (r[0] - r[1]).abs());
  }

  static double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;
  static double _cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;
  static double _tanh(double x) => _sinh(x) / _cosh(x);

  CalculusResult _integrateTanhSinh2D(double a, double b) {
    const n = 64;
    double sum = 0;
    double maxWeight = 0;
    for (int i = -n; i <= n; i++) {
      final t = i * 0.5;
      final s = math.pi / 2 * _sinh(t);
      final u = _tanh(s);
      final ch = _cosh(math.pi / 2 * _sinh(t));
      final du = math.pi / 2 * _cosh(t) / (ch * ch);
      final x = (a + b) / 2 + (b - a) / 2 * u;
      final w = (b - a) / 2 * du;
      if (w > maxWeight) maxWeight = w;
      sum += w * _eval2D(x);
    }
    final value = sum;
    final err = (b - a).abs() * 1e-12 * maxWeight * n;
    return CalculusResult(value: value, errorEstimate: err);
  }

  CalculusResult _integrate2D(double a, double b) {
    switch (_integMethod) {
      case IntegrationMethod.gaussKronrod:
        return _integrateGaussKronrod2D(a, b);
      case IntegrationMethod.adaptiveSimpson:
        return _integrateAdaptiveSimpson2D(a, b);
      case IntegrationMethod.clenshawCurtis:
        return _integrateClenshawCurtis2D(a, b);
      case IntegrationMethod.romberg:
        return _integrateRomberg2D(a, b);
      case IntegrationMethod.tanhSinh:
        return _integrateTanhSinh2D(a, b);
    }
  }

  double _integrateXForFixedY(double xMin, double xMax, double yFixed) {
    final mid = (xMin + xMax) / 2;
    final half = (xMax - xMin) / 2;
    double k15 = 0;
    for (int i = 0; i < 15; i++) {
      final x = mid + half * _gkNodes15[i];
      k15 += _gkWeights15[i] * _eval3D(x, yFixed);
    }
    return k15 * half;
  }

  CalculusResult _integrate3D(
    double xMin,
    double xMax,
    double yMin,
    double yMax,
  ) {
    const ny = 48;
    final dy = (yMax - yMin) / ny;
    double total = 0;
    double errSum = 0;
    for (int j = 0; j < ny; j++) {
      final y = yMin + (j + 0.5) * dy;
      final inner = _integrateXForFixedY(xMin, xMax, y);
      total += inner * dy;
      errSum += 1e-10 * (xMax - xMin) * dy;
    }
    final err = errSum + 1e-10 * (xMax - xMin) * (yMax - yMin);
    return CalculusResult(value: total, errorEstimate: err);
  }

  Widget _buildMethodSelector<T>({
    required T value,
    required List<T> items,
    required String label,
    required String Function(T) itemLabel,
    required ValueChanged<T> onChanged,
    required bool isExpanded,
    required ValueChanged<bool> onExpandChanged,
  }) {
    final c = widget.colorScheme;
    final borderSide = BorderSide(color: c.outline.withValues(alpha: 0.5));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => onExpandChanged(!isExpanded),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border.fromBorderSide(borderSide),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          color: c.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        itemLabel(value),
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: c.onSurface,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  isExpanded ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  color: c.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: widget.isDark
                  ? c.surfaceContainerHigh
                  : c.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: c.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              children: items.map((item) {
                final isSelected = item == value;
                return InkWell(
                  onTap: () {
                    onChanged(item);
                    onExpandChanged(false);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            itemLabel(item),
                            style: TextStyle(
                              fontFamily: 'monospace',
                              color: isSelected ? c.primary : c.onSurface,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Icon(Icons.check, size: 18, color: c.primary),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Future<void> _compute() async {
    if (_expr.isEmpty) {
      setState(() {
        _resultText = '';
        _errorText = 'Enter a function';
      });
      return;
    }
    setState(() {
      _isComputing = true;
      _resultText = '';
      _errorText = '';
    });

    await Future<void>.delayed(Duration.zero);

    if (!mounted) return;
    try {
      if (_isDerivative) {
        if (_is2D) {
          final x = double.tryParse(_xPointCtrl.text);
          if (x == null) {
            setState(() {
              _errorText = 'Invalid point x';
              _isComputing = false;
            });
            return;
          }
          final res = _derivative2D(x);
          setState(() {
            _resultText = 'f\'(x) ≈ ${res.value}';
            _errorText = 'Est. error: ±${res.errorEstimate}';
            if (res.details != null) _errorText += '\n${res.details}';
            _isComputing = false;
          });
        } else {
          final x = double.tryParse(_xPointCtrl.text);
          final y = double.tryParse(_yPointCtrl.text);
          if (x == null || y == null) {
            setState(() {
              _errorText = 'Invalid point (x, y)';
              _isComputing = false;
            });
            return;
          }
          final res = _derivative3D(x, y);
          setState(() {
            _resultText = 'Directional deriv ≈ ${res.value}';
            _errorText = 'Est. error: ±${res.errorEstimate}';
            if (res.details != null) _errorText += '\n${res.details}';
            _isComputing = false;
          });
        }
      } else {
        if (_is2D) {
          final a = double.tryParse(_aCtrl.text);
          final b = double.tryParse(_bCtrl.text);
          if (a == null || b == null || a >= b) {
            setState(() {
              _errorText = 'Invalid bounds: a < b required';
              _isComputing = false;
            });
            return;
          }
          final res = _integrate2D(a, b);
          setState(() {
            _resultText = '∫f dx ≈ ${res.value}';
            _errorText = 'Est. error: ±${res.errorEstimate}';
            _isComputing = false;
          });
        } else {
          final xMin = double.tryParse(_aCtrl.text);
          final xMax = double.tryParse(_bCtrl.text);
          final yMin = double.tryParse(_yMinCtrl.text);
          final yMax = double.tryParse(_yMaxCtrl.text);
          if (xMin == null ||
              xMax == null ||
              yMin == null ||
              yMax == null ||
              xMin >= xMax ||
              yMin >= yMax) {
            setState(() {
              _errorText = 'Invalid bounds: xMin<xMax, yMin<yMax';
              _isComputing = false;
            });
            return;
          }
          final res = _integrate3D(xMin, xMax, yMin, yMax);
          setState(() {
            _resultText = '∬f dA ≈ ${res.value}';
            _errorText = 'Est. error: ±${res.errorEstimate}';
            _isComputing = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _resultText = '';
          _errorText = 'Error: $e';
          _isComputing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colorScheme;
    final isDark = widget.isDark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Derivative')),
                    ButtonSegment(value: false, label: Text('Integral')),
                  ],
                  selected: {_isDerivative},
                  onSelectionChanged: (s) =>
                      setState(() => _isDerivative = s.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('2D')),
                    ButtonSegment(value: false, label: Text('3D')),
                  ],
                  selected: {_is2D},
                  onSelectionChanged: (s) => setState(() => _is2D = s.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _exprCtrl,
            decoration: InputDecoration(
              labelText: _is2D ? 'f(x)' : 'f(x,y)',
              hintText: _is2D ? 'e.g. x^2*sin(x)' : 'e.g. x^2+y^2',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
            ),
            style: TextStyle(fontFamily: 'monospace', color: c.onSurface),
          ),
          const SizedBox(height: 12),
          if (_isDerivative) ...[
            if (_is2D)
              TextField(
                controller: _xPointCtrl,
                decoration: InputDecoration(
                  labelText: 'Point x',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                style: TextStyle(fontFamily: 'monospace', color: c.onSurface),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _xPointCtrl,
                      decoration: InputDecoration(
                        labelText: 'x',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: c.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _yPointCtrl,
                      decoration: InputDecoration(
                        labelText: 'y',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: c.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Direction (for directional derivative):',
                style: TextStyle(color: c.onSurfaceVariant, fontSize: 12),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dirXCtrl,
                      decoration: const InputDecoration(
                        labelText: 'dx',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: c.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _dirYCtrl,
                      decoration: const InputDecoration(
                        labelText: 'dy',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: c.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            _buildMethodSelector<DerivativeMethod>(
              value: _derivMethod,
              items: DerivativeMethod.values,
              label: 'Method',
              itemLabel: (m) => m.label,
              onChanged: (v) => setState(() => _derivMethod = v),
              isExpanded: _isDerivMethodExpanded,
              onExpandChanged:
                  (v) => setState(() => _isDerivMethodExpanded = v),
            ),
          ] else ...[
            if (_is2D) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _aCtrl,
                      decoration: InputDecoration(
                        labelText: 'Lower bound a',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: c.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _bCtrl,
                      decoration: InputDecoration(
                        labelText: 'Upper bound b',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: c.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Text(
                'Bounds (xMin, xMax, yMin, yMax):',
                style: TextStyle(color: c.onSurfaceVariant, fontSize: 12),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _aCtrl,
                      decoration: const InputDecoration(
                        labelText: 'xMin',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: c.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: _bCtrl,
                      decoration: const InputDecoration(
                        labelText: 'xMax',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: c.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: _yMinCtrl,
                      decoration: const InputDecoration(
                        labelText: 'yMin',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: c.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: _yMaxCtrl,
                      decoration: const InputDecoration(
                        labelText: 'yMax',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: c.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            if (_is2D)
              _buildMethodSelector<IntegrationMethod>(
                value: _integMethod,
                items: IntegrationMethod.values,
                label: 'Method',
                itemLabel: (m) => m.label,
                onChanged: (v) => setState(() => _integMethod = v),
                isExpanded: _isIntegMethodExpanded,
                onExpandChanged:
                    (v) => setState(() => _isIntegMethodExpanded = v),
              ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _isComputing ? null : _compute,
            icon: _isComputing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.calculate),
            label: Text(_isComputing ? 'Computing...' : 'Compute'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (_resultText.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark
                    ? c.surfaceContainerHigh
                    : c.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: c.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    _resultText,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: c.onSurface,
                    ),
                  ),
                  if (_errorText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      _errorText,
                      style: TextStyle(
                        fontSize: 13,
                        color: c.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
