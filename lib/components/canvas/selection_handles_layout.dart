// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'package:flutter/material.dart';

abstract class SelectionHandlesLayout {
  SelectionHandlesLayout._();

  static double _viewportScale(double currentScale) {
    if (!currentScale.isFinite || currentScale <= 0) return 1.0;
    return currentScale.clamp(0.06, 2048.0);
  }

  static double cornerDiameter(double viewportScale) {
    final s = _viewportScale(viewportScale);
    return (16.0 / s).clamp(8.0 / s, 48.0 / s);
  }

  static double rotationHandleGap(double viewportScale) {
    return 32.0 / _viewportScale(viewportScale);
  }

  static Offset rotateAround(Offset point, Offset origin, double rotationRad) {
    final dx = point.dx - origin.dx;
    final dy = point.dy - origin.dy;
    final cos = math.cos(rotationRad);
    final sin = math.sin(rotationRad);
    return Offset(
      origin.dx + dx * cos - dy * sin,
      origin.dy + dx * sin + dy * cos,
    );
  }

  static Offset rotationHandleCenterUnrotated(Rect rect, double viewportScale) {
    final gap = rotationHandleGap(viewportScale);
    return Offset(rect.center.dx, rect.top - gap);
  }

  static double cornerHitRadius(double viewportScale, {required bool stylus}) {
    final s = _viewportScale(viewportScale);
    final d = cornerDiameter(viewportScale);
    final pad = stylus ? 12.0 / s : 24.0 / s;
    return (d / 2) + pad;
  }

  static double rotationHandleHitRadius(double viewportScale) {
    final s = _viewportScale(viewportScale);
    return (14.0 / s) + (24.0 / s); // Generous hit area for easy rotation
  }
}