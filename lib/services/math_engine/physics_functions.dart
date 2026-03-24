// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'complex.dart';
import 'special_functions.dart';

class PhysicsFunctions {
  static double legendre(int l, double x) {
    if (l == 0) return 1.0;
    if (l == 1) return x;
    double p0 = 1.0;
    double p1 = x;
    for (int n = 2; n <= l; n++) {
      final pn = ((2 * n - 1) * x * p1 - (n - 1) * p0) / n;
      p0 = p1;
      p1 = pn;
    }
    return p1;
  }

  static double assocLegendre(int l, int m, double x) {
    if (m < 0) {
      final sign = (m.abs() % 2 == 0) ? 1.0 : -1.0;
      return sign *
          SpecialFunctions.gamma(l - m + 1.0) /
          SpecialFunctions.gamma(l + m + 1.0) *
          assocLegendre(l, -m, x);
    }
    if (l == m) {
      final pmm = math.pow(-1.0, m) *
          SpecialFunctions.doubleFactorial(2 * m - 1) *
          math.pow(1.0 - x * x, m / 2.0);
      return pmm.toDouble();
    }
    if (l == m + 1) {
      return x * (2 * m + 1) * assocLegendre(m, m, x);
    }
    double pmm = assocLegendre(m, m, x);
    double pm1m = x * (2 * m + 1) * pmm;
    double pll = 0.0;
    for (int n = m + 2; n <= l; n++) {
      pll = ((2 * n - 1) * x * pm1m - (n + m - 1) * pmm) / (n - m);
      pmm = pm1m;
      pm1m = pll;
    }
    return pll;
  }

  static double hermite(int n, double x) {
    if (n == 0) return 1.0;
    if (n == 1) return 2.0 * x;
    double h0 = 1.0;
    double h1 = 2.0 * x;
    for (int k = 2; k <= n; k++) {
      final hk = 2.0 * x * h1 - 2.0 * (k - 1) * h0;
      h0 = h1;
      h1 = hk;
    }
    return h1;
  }

  static double laguerre(int n, double x) {
    if (n == 0) return 1.0;
    if (n == 1) return 1.0 - x;
    double l0 = 1.0;
    double l1 = 1.0 - x;
    for (int k = 2; k <= n; k++) {
      final lk = ((2 * k - 1 - x) * l1 - (k - 1) * l0) / k;
      l0 = l1;
      l1 = lk;
    }
    return l1;
  }

  static double assocLaguerre(int n, int m, double x) {
    if (n == 0) return 1.0;
    double l0 = 1.0;
    double l1 = 1.0 + m - x;
    if (n == 1) return l1;
    for (int k = 2; k <= n; k++) {
      final lk = ((2 * k - 1 + m - x) * l1 - (k - 1 + m) * l0) / k;
      l0 = l1;
      l1 = lk;
    }
    return l1;
  }

  static Complex sphericalHarmonic(int l, int m, double theta, double phi) {
    final mAbs = m.abs();
    final pref = math.sqrt(
      ((2 * l + 1) / (4 * math.pi)) *
          (SpecialFunctions.factorial(l - mAbs) /
              SpecialFunctions.factorial(l + mAbs)),
    );
    final leg = assocLegendre(l, mAbs, math.cos(theta));
    final phase = Complex.fromPolar(1.0, m * phi);
    final result = phase * Complex(pref * leg);
    if (m < 0) {
      final sign = (mAbs % 2 == 0) ? 1.0 : -1.0;
      return Complex(sign) * result.conjugate();
    }
    return result;
  }

  static double sphericalBesselJ(int n, double x) {
    if (n == 0) return x == 0 ? 1.0 : math.sin(x) / x;
    if (n == 1) {
      if (x == 0) return 0.0;
      return math.sin(x) / (x * x) - math.cos(x) / x;
    }
    double j0 = math.sin(x) / x;
    double j1 = math.sin(x) / (x * x) - math.cos(x) / x;
    for (int k = 1; k < n; k++) {
      final j2 = ((2 * k + 1) / x) * j1 - j0;
      j0 = j1;
      j1 = j2;
    }
    return j1;
  }

  static double sphericalBesselY(int n, double x) {
    if (n == 0) return -math.cos(x) / x;
    if (n == 1) return -math.cos(x) / (x * x) - math.sin(x) / x;
    double y0 = -math.cos(x) / x;
    double y1 = -math.cos(x) / (x * x) - math.sin(x) / x;
    for (int k = 1; k < n; k++) {
      final y2 = ((2 * k + 1) / x) * y1 - y0;
      y0 = y1;
      y1 = y2;
    }
    return y1;
  }
}
