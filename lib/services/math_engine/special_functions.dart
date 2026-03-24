// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

class SpecialFunctions {
  static double gamma(double z) {
    if (z < 0.5) {
      return math.pi / (math.sin(math.pi * z) * gamma(1 - z));
    }
    z -= 1;
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
    const g = 7;
    double x = p[0];
    for (int i = 1; i < p.length; i++) {
      x += p[i] / (z + i);
    }
    final t = z + g + 0.5;
    return math.sqrt(2 * math.pi) *
        math.pow(t, z + 0.5) *
        math.exp(-t) *
        x;
  }

  static double logGamma(double z) => math.log(gamma(z));

  static double beta(double a, double b) =>
      gamma(a) * gamma(b) / gamma(a + b);

  static double factorial(int n) => gamma(n + 1.0);

  static double doubleFactorial(int n) {
    if (n <= 0) return 1.0;
    double result = 1.0;
    for (int k = n; k > 1; k -= 2) {
      result *= k;
    }
    return result;
  }

  static double combinations(int n, int k) {
    if (k < 0 || k > n) return 0;
    if (k == 0 || k == n) return 1;
    if (k > n / 2) k = n - k;
    double res = 1;
    for (int i = 1; i <= k; i++) {
      res = res * (n - i + 1) / i;
    }
    return res;
  }

  static double permutations(int n, int k) {
    if (k < 0 || k > n) return 0;
    double res = 1;
    for (int i = 0; i < k; i++) {
      res = res * (n - i);
    }
    return res;
  }

  static double erf(double x) {
    const a1 = 0.254829592;
    const a2 = -0.284496736;
    const a3 = 1.421413741;
    const a4 = -1.453152027;
    const a5 = 1.061405429;
    const p = 0.3275911;
    final sign = x < 0 ? -1 : 1;
    x = x.abs();
    final t = 1.0 / (1.0 + p * x);
    final y = 1.0 -
        (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) *
            t *
            math.exp(-x * x);
    return sign * y;
  }

  static double erfc(double x) => 1.0 - erf(x);

  static double zeta(double s, {int terms = 2000}) {
    if (s <= 1.0) return double.nan;
    double sum = 0.0;
    for (int k = 1; k <= terms; k++) {
      sum += 1.0 / math.pow(k, s);
    }
    return sum;
  }

  static double digamma(double x) {
    double result = 0.0;
    while (x < 6.0) {
      result -= 1.0 / x;
      x += 1.0;
    }
    final inv = 1.0 / x;
    final inv2 = inv * inv;
    result += math.log(x) - 0.5 * inv - inv2 / 12.0 + inv2 * inv2 / 120.0;
    return result;
  }

  static double trigamma(double x) {
    double result = 0.0;
    while (x < 6.0) {
      result += 1.0 / (x * x);
      x += 1.0;
    }
    final inv = 1.0 / x;
    final inv2 = inv * inv;
    result += inv + inv2 / 2.0 + inv2 * inv / 6.0 - inv2 * inv2 / 30.0;
    return result;
  }

  static double polylog(double s, double z, {int terms = 1000}) {
    double sum = 0.0;
    for (int k = 1; k <= terms; k++) {
      sum += math.pow(z, k) / math.pow(k.toDouble(), s);
    }
    return sum;
  }

  static double sinc(double x) => x == 0 ? 1.0 : math.sin(x) / x;

  static double si(double x, {int terms = 80}) {
    double sum = 0.0;
    double power = x;
    double factorial = 1.0;
    for (int n = 0; n < terms; n++) {
      final sign = n.isEven ? 1.0 : -1.0;
      sum += sign * power / ((2 * n + 1) * factorial);
      power *= x * x;
      factorial *= (2 * n + 2) * (2 * n + 3);
    }
    return sum;
  }

  static double ci(double x, {int terms = 80}) {
    const eulerGamma = 0.5772156649015329;
    double sum = 0.0;
    double power = x * x;
    double factorial = 2.0;
    for (int n = 1; n < terms; n++) {
      final sign = n.isEven ? 1.0 : -1.0;
      sum += sign * power / ((2 * n) * factorial);
      power *= x * x;
      factorial *= (2 * n + 1) * (2 * n + 2);
    }
    return eulerGamma + math.log(x.abs()) + sum;
  }

  static double dawson(double x, {int terms = 40}) {
    double sum = 0.0;
    double term = x;
    for (int n = 0; n < terms; n++) {
      final sign = n.isEven ? 1.0 : -1.0;
      sum += sign * term / (2 * n + 1);
      term *= x * x;
    }
    return math.exp(-x * x) * sum;
  }

  static double besselJ0(double x) {
    final ax = x.abs();
    if (ax < 8.0) {
      final y = x * x;
      final num = 57568490574.0 +
          y *
              (-13362590354.0 +
                  y * (651619640.7 +
                      y * (-11214424.18 +
                          y * (77392.33017 + y * (-184.9052456)))));
      final den = 57568490411.0 +
          y *
              (1029532985.0 +
                  y * (9494680.718 +
                      y * (59272.64853 + y * (267.8532712 + y))));
      return num / den;
    }
    final z = 8.0 / ax;
    final y = z * z;
    final xx = ax - 0.785398164;
    final p = 1.0 +
        y *
            (-0.1098628627e-2 +
                y * (0.2734510407e-4 + y * (-0.2073370639e-5 + y * 0.2093887211e-6)));
    final q = -0.1562499995e-1 +
        y *
            (0.1430488765e-3 +
                y * (-0.6911147651e-5 + y * (0.7621095161e-6 - y * 0.934945152e-7)));
    return math.sqrt(0.636619772 / ax) * (math.cos(xx) * p - z * math.sin(xx) * q);
  }

  static double besselJ1(double x) {
    final ax = x.abs();
    if (ax < 8.0) {
      final y = x * x;
      final num = x *
          (72362614232.0 +
              y *
                  (-7895059235.0 +
                      y * (242396853.1 +
                          y * (-2972611.439 +
                              y * (15704.48260 + y * (-30.16036606))))));
      final den = 144725228442.0 +
          y *
              (2300535178.0 +
                  y * (18583304.74 +
                      y * (99447.43394 + y * (376.9991397 + y))));
      return num / den;
    }
    final z = 8.0 / ax;
    final y = z * z;
    final xx = ax - 2.356194491;
    final p = 1.0 +
        y *
            (0.183105e-2 +
                y * (-0.3516396496e-4 + y * (0.2457520174e-5 + y * (-0.240337019e-6))));
    final q = 0.04687499995 +
        y *
            (-0.2002690873e-3 +
                y * (0.8449199096e-5 + y * (-0.88228987e-6 + y * 0.105787412e-6)));
    final result =
        math.sqrt(0.636619772 / ax) * (math.cos(xx) * p - z * math.sin(xx) * q);
    return x < 0 ? -result : result;
  }

  static double besselJn(int n, double x) {
    if (n == 0) return besselJ0(x);
    if (n == 1) return besselJ1(x);
    double a = besselJ0(x);
    double b = besselJ1(x);
    for (int k = 1; k < n; k++) {
      final c = (2 * k / x) * b - a;
      a = b;
      b = c;
    }
    return b;
  }

  static double airyAi(double x) {

    if (x.abs() < 1.0) {
      final x3 = x * x * x;
      return 0.355028053887817 + (-0.258819403792807) * x + 0.0208333333333333 * x3;
    }
    final t = (2.0 / 3.0) * math.pow(x.abs(), 1.5);
    final pref = 0.5 / math.sqrt(math.pi) / math.pow(x.abs(), 0.25);
    return x > 0 ? pref * math.exp(-t) : pref * math.sin(t + math.pi / 4);
  }

  static double airyBi(double x) {
    if (x.abs() < 1.0) {
      final x3 = x * x * x;
      return 0.614926627446001 + 0.448288357353826 * x + 0.0208333333333333 * x3;
    }
    final t = (2.0 / 3.0) * math.pow(x.abs(), 1.5);
    final pref = 1.0 / math.sqrt(math.pi) / math.pow(x.abs(), 0.25);
    return x > 0 ? pref * math.exp(t) : pref * math.cos(t + math.pi / 4);
  }
}
