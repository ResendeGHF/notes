// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/components/canvas/selection_handles_layout.dart';
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

  static double _safeScale(double s) =>
      s.isFinite && s > 0 ? s.clamp(0.06, 2048.0) : 1.0;

  @override
  Widget build(BuildContext context) {
    final bounds = selection.getBounds();
    final rect = selectionPreview?.visualBounds ?? selection.displayBounds ?? bounds;
    final rotationDeg = selectionPreview?.effectiveRotationDeg ?? selection.rotationDeg;
    final rotationRad = rotationDeg * math.pi / 180.0;
    final centroid = rect.center;

    Offset rotate(Offset p) => SelectionHandlesLayout.rotateAround(p, centroid, rotationRad);

    final cornerCentersCanvas = [
      rotate(rect.topLeft),
      rotate(rect.topRight),
      rotate(rect.bottomRight),
      rotate(rect.bottomLeft),
    ];

    final unrotatedTopCenter = Offset(rect.center.dx, rect.top);
    final unrotatedRotHandle = SelectionHandlesLayout.rotationHandleCenterUnrotated(rect, currentScale);
    
    final topCenterCanvas = rotate(unrotatedTopCenter);
    final rotHandleCanvas = rotate(unrotatedRotHandle);

    final safeScale = _safeScale(currentScale);
    final handleD = SelectionHandlesLayout.cornerDiameter(currentScale);

    final bool isActivelyRotating = selectionPreview != null && selectionPreview!.rotationDeltaDeg != 0.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Linha conectora da caixa de rotação
        Positioned.fill(
          child: CustomPaint(
            painter: _RotationConnectorPainter(
              start: topCenterCanvas,
              end: rotHandleCanvas,
              color: primaryColor,
              scale: safeScale,
            ),
          ),
        ),
        
        // Cantos (Redimensionamento)
        for (var i = 0; i < cornerCentersCanvas.length; i++)
          _buildHandle(
            center: cornerCentersCanvas[i],
            diameter: handleD,
            color: primaryColor,
            strokeColor: invert ? const Color(0xFF1E1E1E) : Colors.white,
            scale: safeScale,
          ),

        // Alça de Rotação (Topo)
        _buildHandle(
          center: rotHandleCanvas,
          diameter: handleD * 1.15,
          color: invert ? const Color(0xFF1E1E1E) : Colors.white,
          strokeColor: primaryColor,
          scale: safeScale,
          isRotator: true,
        ),

        // Mostrador de Ângulo
        if (isActivelyRotating)
          Positioned(
            left: centroid.dx - (44 / safeScale),
            top: centroid.dy - (18 / safeScale),
            child: Transform.scale(
              scale: 1 / safeScale,
              child: Container(
                width: 88,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black26, blurRadius: 6, offset: const Offset(0, 3))
                  ]
                ),
                child: Text(
                  '${(rotationDeg % 360).toStringAsFixed(1)}°',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHandle({
    required Offset center,
    required double diameter,
    required Color color,
    required Color strokeColor,
    required double scale,
    bool isRotator = false,
  }) {
    return Positioned(
      left: center.dx - diameter / 2,
      top: center.dy - diameter / 2,
      width: diameter,
      height: diameter,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: strokeColor, width: (isRotator ? 2.5 : 2.0) / scale),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 4 / scale,
              spreadRadius: 1 / scale,
            ),
          ],
        ),
      ),
    );
  }
}

class _RotationConnectorPainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;
  final double scale;

  _RotationConnectorPainter({required this.start, required this.end, required this.color, required this.scale});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0 / scale
      ..style = PaintingStyle.stroke;
    canvas.drawLine(start, end, paint);
  }

  @override
  bool shouldRepaint(covariant _RotationConnectorPainter oldDelegate) =>
      start != oldDelegate.start || end != oldDelegate.end || scale != oldDelegate.scale;
}