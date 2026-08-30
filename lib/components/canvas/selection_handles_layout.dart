// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Resize vs rotate affordances for the select tool. Tapping the mode chip
/// toggles between them.
enum SelectionHandlesInteractionMode { resize, rotate }

/// Geometry shared by [SelectionHandlesOverlay] and editor pointer hit-testing.
abstract final class SelectionHandlesLayout {
  SelectionHandlesLayout._();

  static double _viewportScale(double currentScale) {
    if (!currentScale.isFinite || currentScale <= 0) return 1.0;
    return currentScale.clamp(0.06, 2048.0);
  }

  /// Corner handle diameter in **page / canvas** coordinates.
  static double cornerDiameter(Rect rect, double viewportScale) {
    final s = _viewportScale(viewportScale);
    const double targetScreenDp = 20.0;
    final fromScreen = targetScreenDp / s;
    final capByBox = rect.shortestSide * 0.42;
    return math.min(fromScreen, capByBox).clamp(5.5 / s, 72.0 / s);
  }

  static Size chipSize(Rect rect, double viewportScale) {
    final s = _viewportScale(viewportScale);
    double w = (44.0 / s).clamp(30.0 / s, 78.0 / s);
    double h = (30.0 / s).clamp(22.0 / s, 48.0 / s);
    final cap = math.max(rect.shortestSide * 1.75, 32.0 / s);
    if (w > cap) {
      w = cap;
      h = math.min(h, cap * 0.68);
    }
    return Size(w, h);
  }

  static double chipGapAboveFrame(double viewportScale) =>
      10.0 / _viewportScale(viewportScale);

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

  /// Unrotated selection [rect], [rotationDeg], [viewportScale] → chip center in page space.
  static Offset chipCenter(Rect rect, double rotationDeg, double viewportScale) {
    final rad = rotationDeg * math.pi / 180.0;
    final origin = rect.center;
    final topCenter = Offset(rect.center.dx, rect.top);
    final sz = chipSize(rect, viewportScale);
    final gap = chipGapAboveFrame(viewportScale);
    final unrotated =
        topCenter - Offset(0, gap + sz.height / 2);
    return rotateAround(unrotated, origin, rad);
  }

  static double cornerHitRadius(
    Rect rect,
    double viewportScale, {
    required bool stylus,
  }) {
    final s = _viewportScale(viewportScale);
    final d = cornerDiameter(rect, viewportScale);
    final pad = stylus ? 10.0 / s : 18.0 / s;
    return math.max(d * 0.65, (d / 2) + pad);
  }

  static double chipHitRadius(Rect rect, double viewportScale) {
    final s = _viewportScale(viewportScale);
    final sz = chipSize(rect, viewportScale);
    return math.max(
          math.max(sz.width, sz.height) / 2,
          cornerDiameter(rect, viewportScale),
        ) +
        (14.0 / s);
  }

  /// Maximum movement (page coords) to still count as a tap on the chip.
  static double chipTapMovementTolerance(double viewportScale) {
    final s = _viewportScale(viewportScale);
    return math.max(5.5, 9.5 / s);
  }

  static const Duration chipTapMaxDuration = Duration(milliseconds: 420);
}
