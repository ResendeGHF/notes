// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

class MathGrid {
  static double calculateStepSize(double targetStepPx, double zoom) {
    final desired = targetStepPx / zoom;
    final exponent = (math.log(desired) / math.ln10).floor();
    final magnitude = math.pow(10, exponent).toDouble();
    final mant = desired / magnitude;
    double step;
    if (mant < 2) {
      step = 1 * magnitude;
    } else if (mant < 5) {
      step = 2 * magnitude;
    } else {
      step = 5 * magnitude;
    }
    return step;
  }

  static (double min, double max) calculateBounds(
    double center,
    double range,
    double stepSize,
  ) {
    final min = (center - range).floorToDouble();
    final max = (center + range).ceilToDouble();
    final snappedMin = (min / stepSize).floor() * stepSize;
    final snappedMax = (max / stepSize).ceil() * stepSize;
    return (snappedMin, snappedMax);
  }
}
