// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:saber/data/extensions/color_extensions.dart';

import 'package:saber/components/canvas/selection_handles_layout.dart';
import 'package:saber/data/tools/select.dart';

/// Corner order matches editor hit-testing:
/// top-left → top-right → bottom-right → bottom-left.
const _expandIconTwists = <double>[
  -math.pi / 2,
  0,
  math.pi / 2,
  math.pi,
];

class SelectionHandlesOverlay extends StatelessWidget {
  const SelectionHandlesOverlay({
    super.key,
    required this.selection,
    this.selectionPreview,
    required this.primaryColor,
    required this.invert,
    required this.currentScale,
    this.interactionMode = SelectionHandlesInteractionMode.resize,
  });

  final SelectResult selection;
  final SelectionTransformPreview? selectionPreview;
  final Color primaryColor;
  final bool invert;
  final double currentScale;
  final SelectionHandlesInteractionMode interactionMode;

  @override
  Widget build(BuildContext context) {
    final bounds = selection.getBounds();
    final rect =
        selectionPreview?.visualBounds ?? selection.displayBounds ?? bounds;
    final rotationRad =
        (selectionPreview?.effectiveRotationDeg ?? selection.rotationDeg) *
        math.pi /
        180.0;
    final centroid = rect.center;

    Offset rotate(Offset p) {
      return SelectionHandlesLayout.rotateAround(p, centroid, rotationRad);
    }

    final cornerCentersCanvas = [
      rotate(rect.topLeft),
      rotate(rect.topRight),
      rotate(rect.bottomRight),
      rotate(rect.bottomLeft),
    ];

    final chipCtr = SelectionHandlesLayout.chipCenter(
      rect,
      selectionPreview?.effectiveRotationDeg ?? selection.rotationDeg,
      currentScale,
    );
    final chipSz = SelectionHandlesLayout.chipSize(rect, currentScale);

    final fillColor = invert ? const Color(0xFF1E1E1E) : Colors.white;
    final handleD =
        SelectionHandlesLayout.cornerDiameter(rect, currentScale);
    final iconBox = math.max(handleD * 0.52, handleD - 6.0 / _safeScale(currentScale));

    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = 0; i < cornerCentersCanvas.length; i++)
          _buildCornerHandle(
            context,
            center: cornerCentersCanvas[i],
            diameter: handleD,
            fillColor: fillColor,
            iconSize: iconBox,
            iconTwist: interactionMode == SelectionHandlesInteractionMode.resize
                ? _expandIconTwists[i]
                : 0.0,
            icon: interactionMode == SelectionHandlesInteractionMode.resize
                ? Icons.north_east
                : Icons.rotate_right,
          ),
        _buildModeChip(
          context,
          center: chipCtr,
          size: chipSz,
          fillColor: fillColor,
        ),
      ],
    );
  }

  static double _safeScale(double s) =>
      s.isFinite && s > 0 ? s.clamp(0.06, 2048.0) : 1.0;

  Widget _buildCornerHandle(
    BuildContext context, {
    required Offset center,
    required double diameter,
    required Color fillColor,
    required double iconSize,
    required double iconTwist,
    required IconData icon,
  }) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    double snap(double value) => (value * dpr).roundToDouble() / dpr;
    final strokeColor = Colors.black.withInversion(invert);
    final scale = _safeScale(currentScale);

    return Positioned(
      left: snap(center.dx - diameter / 2),
      top: snap(center.dy - diameter / 2),
      width: diameter,
      height: diameter,
      child: RepaintBoundary(
        child: Material(
          type: MaterialType.circle,
          color: fillColor,
          elevation: 1.2,
          shadowColor: Colors.black.withValues(alpha: 0.14),
          clipBehavior: Clip.antiAlias,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: strokeColor, width: 1.3 / scale),
            ),
            child: Center(
              child: Transform.rotate(
                angle: iconTwist,
                child: Icon(
                  icon,
                  size: iconSize,
                  color: strokeColor.withValues(alpha: 0.92),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeChip(
    BuildContext context, {
    required Offset center,
    required Size size,
    required Color fillColor,
  }) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    double snap(double value) => (value * dpr).roundToDouble() / dpr;
    final modeIcon = interactionMode == SelectionHandlesInteractionMode.resize
        ? Icons.rotate_right
        : Icons.open_in_full;
    final iconDim = math.min(size.width, size.height) * 0.48;
    final strokeColor = Colors.black.withInversion(invert);
    final scale = _safeScale(currentScale);

    return Positioned(
      left: snap(center.dx - size.width / 2),
      top: snap(center.dy - size.height / 2),
      width: size.width,
      height: size.height,
      child: RepaintBoundary(
        child: Material(
          color: fillColor,
          elevation: 1.4,
          shadowColor: Colors.black.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
          clipBehavior: Clip.antiAlias,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: strokeColor.withValues(alpha: 0.45),
                width: 1.2 / scale,
              ),
            ),
            child: Center(
              child: Icon(
                modeIcon,
                size: iconDim,
                color: strokeColor.withValues(alpha: 0.95),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
