// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:saber/data/tools/select.dart';

class SelectionHandlesOverlay extends StatelessWidget {
  const SelectionHandlesOverlay({
    super.key,
    required this.selection,
    this.selectionPreview,
    required this.primaryColor,
    required this.invert,
    required this.currentScale,
  });

  final SelectResult selection;
  final SelectionTransformPreview? selectionPreview;
  final Color primaryColor;
  final bool invert;
  final double currentScale;

  static const double _cornerDiameter = 10.0;
  static const double _rotDiameter = 12.0;
  static const double _rotOffset = 42.0;

  @override
  Widget build(BuildContext context) {
    final bounds = selection.getBounds();
    final rect = selectionPreview?.visualBounds ?? selection.displayBounds ?? bounds;
    final rotationRad =
        (selectionPreview?.effectiveRotationDeg ?? selection.rotationDeg) *
        math.pi /
        180.0;
    final centroid = rect.center;

    Offset rotate(Offset p) {
      final dx = p.dx - centroid.dx;
      final dy = p.dy - centroid.dy;
      return Offset(
        centroid.dx + dx * math.cos(rotationRad) - dy * math.sin(rotationRad),
        centroid.dy + dx * math.sin(rotationRad) + dy * math.cos(rotationRad),
      );
    }

    final corners = [
      rotate(rect.topLeft),
      rotate(rect.topRight),
      rotate(rect.bottomLeft),
      rotate(rect.bottomRight),
    ];

    final topCenter = Offset(rect.center.dx, rect.top);
    final handleCenter = rotate(topCenter - Offset(0, _rotOffset / currentScale));

    final fillColor = invert ? const Color(0xFF1E1E1E) : Colors.white;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final c in corners) _buildHandle(context, c, _cornerDiameter, fillColor),
        _buildHandle(context, handleCenter, _rotDiameter, fillColor),
      ],
    );
  }

  Widget _buildHandle(
    BuildContext context,
    Offset center,
    double diameter,
    Color fillColor,
  ) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    double snap(double value) => (value * dpr).roundToDouble() / dpr;
    return Positioned(
      left: snap(center.dx - diameter / 2),
      top: snap(center.dy - diameter / 2),
      width: diameter,
      height: diameter,
      child: RepaintBoundary(
        child: Material(
          type: MaterialType.circle,
          color: fillColor,
          elevation: 1.5,
          shadowColor: Colors.black.withValues(alpha: 0.18),
          clipBehavior: Clip.antiAlias,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: primaryColor, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}
