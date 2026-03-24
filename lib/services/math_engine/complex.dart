// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'special_functions.dart';

class Complex {
  final double real;
  final double imag;

  const Complex(this.real, [this.imag = 0.0]);

  static const i = Complex(0, 1);

  Complex operator +(Complex other) =>
      Complex(real + other.real, imag + other.imag);
  Complex operator -(Complex other) =>
      Complex(real - other.real, imag - other.imag);

  Complex operator *(Complex other) => Complex(
        real * other.real - imag * other.imag,
        real * other.imag + imag * other.real,
      );

  Complex operator /(Complex other) {
    final denom = other.real * other.real + other.imag * other.imag;
    return Complex(
      (real * other.real + imag * other.imag) / denom,
      (imag * other.real - real * other.imag) / denom,
    );
  }

  Complex operator -() => Complex(-real, -imag);

  double abs() => math.sqrt(real * real + imag * imag);
  double arg() => math.atan2(imag, real);

  Complex conjugate() => Complex(real, -imag);

  Complex exp() {
    final e = math.exp(real);
    return Complex(e * math.cos(imag), e * math.sin(imag));
  }

  Complex log() => Complex(math.log(abs()), arg());

  Complex pow(Complex other) {
    if (real == 0 && imag == 0) return const Complex(0);
    final logZ = log();
    final product = logZ * other;
    return product.exp();
  }

  Complex sqrt() => pow(const Complex(0.5));

  Complex sin() =>
      Complex(math.sin(real) * _cosh(imag), math.cos(real) * _sinh(imag));
  Complex cos() =>
      Complex(math.cos(real) * _cosh(imag), -math.sin(real) * _sinh(imag));
  Complex tan() {
    final den = cos();
    if (den.abs() < 1e-10) {
      throw FormatException('Tan undefined');
    }
    return sin() / den;
  }

  Complex sinh() {
    final e1 = exp();
    final e2 = (-this).exp();
    return (e1 - e2) * const Complex(0.5);
  }

  Complex cosh() {
    final e1 = exp();
    final e2 = (-this).exp();
    return (e1 + e2) * const Complex(0.5);
  }

  Complex tanh() => sinh() / cosh();

  Complex asin() {
    final root = (const Complex(1) - (this * this)).sqrt();
    final term = (i * this) + root;
    return term.log() * i * const Complex(-1);
  }

  Complex acos() {
    return const Complex(math.pi / 2) - asin();
  }

  Complex atan() {
    final n = const Complex(1) - (i * this);
    final d = const Complex(1) + (i * this);
    return (n / d).log() * i * const Complex(0.5);
  }

  Complex asinh() {
    final root = (this * this + const Complex(1)).sqrt();
    return (this + root).log();
  }

  Complex acosh() {
    final root = (this * this - const Complex(1)).sqrt();
    return (this + root).log();
  }

  Complex atanh() {
    final n = const Complex(1) + this;
    final d = const Complex(1) - this;
    return (n / d).log() * const Complex(0.5);
  }

  Complex gamma() {
    if (imag == 0) {
      return Complex(SpecialFunctions.gamma(real));
    }
    return _gammaComplex();
  }

  @override
  String toString({int precision = 4}) {
    final r = _fmt(real, precision);
    final i = _fmt(imag.abs(), precision);
    if (imag == 0) return r;
    if (real == 0) return '${imag < 0 ? "-" : ""}i$i';
    return '$r ${imag < 0 ? "-" : "+"} ${i}i';
  }

  String _fmt(double v, int p) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v
        .toStringAsFixed(p)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;
  double _cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;

  static Complex fromPolar(double r, double theta) =>
      Complex(r * math.cos(theta), r * math.sin(theta));

  static Complex nCr(Complex n, Complex r) {
    final ni = n.real.round();
    final ri = r.real.round();
    if (ri < 0 || ri > ni) return const Complex(0);
    return Complex(SpecialFunctions.combinations(ni, ri).toDouble());
  }

  static Complex nPr(Complex n, Complex r) {
    final ni = n.real.round();
    final ri = r.real.round();
    if (ri < 0 || ri > ni) return const Complex(0);
    return Complex(SpecialFunctions.permutations(ni, ri).toDouble());
  }

  Complex _gammaComplex() {

    const g = 7;
    const p = [
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

    Complex z = this;
    if (z.real < 0.5) {
      final pi = math.pi;
      return Complex(pi) /
          ((Complex(pi) * z).sin() * (Complex(1) - z)._gammaComplex());
    }

    z = z - const Complex(1);
    var x = Complex(p[0]);
    for (int i = 1; i < p.length; i++) {
      x += Complex(p[i]) / (z + Complex(i.toDouble()));
    }
    final t = z + const Complex(g + 0.5);
    final sqrtTwoPi = math.sqrt(2 * math.pi);
    return Complex(sqrtTwoPi) * t.pow(z + const Complex(0.5)) * (-t).exp() * x;
  }
}
