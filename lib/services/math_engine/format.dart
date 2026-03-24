// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

class MathFormatter {
  static String formatNumber(double value, {int precision = 4}) {
    if (value.isNaN) return 'NaN';
    if (value.isInfinite) return value.isNegative ? '-∞' : '∞';
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsFixed(precision)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  static String formatAxisLabel(double value, {int precision = 1}) {
    if (value.abs() < 1e-6) return '0';
    if (value.abs() >= 10000 || value.abs() < 1e-3) {
      return formatScientific(value, precision: precision);
    }
    return formatNumber(value, precision: precision);
  }

  static String formatScientific(double value, {int precision = 2}) {
    if (value == 0) return '0';
    final exp = math.log(value.abs()) / ln10;
    final exponent = exp.floor();
    final mantissa = value / math.pow(10, exponent);
    return '${formatNumber(mantissa, precision: precision)}e$exponent';
  }
}

const double ln10 = 2.302585092994046;
