// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:saber/components/canvas/_shape_stroke.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/data/tools/shape_geometry.dart';

/// Draggable control points for a selected parametric [ShapeStroke].
class ShapeControlPointsOverlay extends StatelessWidget {
  const ShapeControlPointsOverlay({
    super.key,
    required this.shape,
    required this.primaryColor,
    required this.invert,
    required this.currentScale,
    this.selectionPreview,
    this.showAngles = true,
  });

  final ShapeStroke shape;
  final Color primaryColor;
  final bool invert;
  final double currentScale;
  final SelectionTransformPreview? selectionPreview;
  final bool showAngles;

  static double handleDiameter(double viewportScale) {
    final s = (!viewportScale.isFinite || viewportScale <= 0)
        ? 1.0
        : viewportScale.clamp(0.06, 2048.0);
    return (18.0 / s).clamp(6.0 / s, 48.0 / s);
  }

  static double hitRadius(double viewportScale, {required bool stylus}) {
    final d = handleDiameter(viewportScale);
    final s = (!viewportScale.isFinite || viewportScale <= 0)
        ? 1.0
        : viewportScale.clamp(0.06, 2048.0);
    // Finger gets a larger target; stylus uses selection bbox by default.
    final pad = stylus ? 6.0 / s : 18.0 / s;
    return math.max(d * 0.7, d / 2 + pad);
  }

  /// Returns index of nearest control point within hit radius, or null.
  /// Vertex editing is intended for finger/touch; stylus should use bbox handles.
  static int? hitTest({
    required ShapeStroke shape,
    required Offset pagePosition,
    required double viewportScale,
    required bool stylus,
  }) {
    if (!shape.isVertexEditable) return null;
    if (stylus) return null;
    final pts = shape.controlPoints;
    if (pts.isEmpty) return null;
    final r = hitRadius(viewportScale, stylus: stylus);
    final r2 = r * r;
    var bestI = -1;
    var bestD = double.infinity;
    for (var i = 0; i < pts.length; i++) {
      final d = (pts[i] - pagePosition).distanceSquared;
      if (d <= r2 && d < bestD) {
        bestD = d;
        bestI = i;
      }
    }
    return bestI >= 0 ? bestI : null;
  }

  @override
  Widget build(BuildContext context) {
    final rawPts = shape.controlPoints;
    if (rawPts.isEmpty) return const SizedBox.shrink();

    // Follow selection translate/scale/rotate preview (same as stroke paint).
    final preview = selectionPreview;
    final pts = preview == null || preview.isIdentity
        ? rawPts
        : rawPts.map(preview.transformPoint).toList(growable: false);

    final fillColor = invert ? const Color(0xFF1E1E1E) : Colors.white;
    final border = primaryColor.withInversion(invert);
    final d = handleDiameter(currentScale);
    final s = currentScale.clamp(0.06, 2048.0);
    final angleColor = const Color(0xFF1E88E5).withInversion(invert);
    // Angles from untransformed geometry (scale/rotate preserve interior angles
    // under uniform selection transforms); positions use transformed points.
    final rawAngles =
        showAngles && ShapeGeometry.showsInteriorAngles(shape.config.kind)
        ? ShapeGeometry.interiorAngles(rawPts)
        : const <({Offset at, double degrees})>[];

    Offset mapPoint(Offset p) =>
        preview == null || preview.isIdentity ? p : preview.transformPoint(p);

    // Inward label offset from corner toward polygon centroid (in preview space).
    Offset? centroid;
    if (rawAngles.isNotEmpty) {
      var sx = 0.0, sy = 0.0;
      for (final p in pts) {
        sx += p.dx;
        sy += p.dy;
      }
      centroid = Offset(sx / pts.length, sy / pts.length);
    }

    final fontSize = (11.0 / s).clamp(7.0 / s, 16.0 / s);
    final labelOffset = (14.0 / s).clamp(8.0 / s, 28.0 / s);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = 0; i < pts.length; i++)
          Positioned(
            left: pts[i].dx - d / 2,
            top: pts[i].dy - d / 2,
            width: d,
            height: d,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fillColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: border,
                  width: math.max(1.5 / s, 0.5),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 2 / s,
                  ),
                ],
              ),
            ),
          ),
        for (final a in rawAngles)
          Builder(
            builder: (context) {
              final at = mapPoint(a.at);
              var pos = at;
              if (centroid != null) {
                final dir = centroid! - at;
                final len = dir.distance;
                if (len > 1e-3) {
                  pos = at + dir * (labelOffset / len);
                }
              }
              final label = '${a.degrees.round()}°';
              return Positioned(
                left: pos.dx - fontSize * 1.2,
                top: pos.dy - fontSize * 0.7,
                child: Text(
                  label,
                  style: TextStyle(
                    color: angleColor,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Shared geometry helper kept next to overlay for editor hit tests.
abstract final class ShapeControlPointsLayout {
  static double handleDiameter(double viewportScale) =>
      ShapeControlPointsOverlay.handleDiameter(viewportScale);

  static double hitRadius(double viewportScale, {required bool stylus}) =>
      ShapeControlPointsOverlay.hitRadius(viewportScale, stylus: stylus);

  static int? hitTest({
    required ShapeStroke shape,
    required Offset pagePosition,
    required double viewportScale,
    required bool stylus,
  }) =>
      ShapeControlPointsOverlay.hitTest(
        shape: shape,
        pagePosition: pagePosition,
        viewportScale: viewportScale,
        stylus: stylus,
      );
}
