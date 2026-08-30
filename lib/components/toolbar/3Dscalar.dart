// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:saber/components/toolbar/3Dplot.dart'
    show
        AxisGizmoPainter3D,
        CoordSystem3D,
        MainAxesLabelsPainter3D,
        SurfacePainter3D,
        SurfaceTriangle3D;
import 'package:saber/services/math_engine/math_engine.dart';
import 'package:vector_math/vector_math_64.dart' as vmath;

class ScalarSurfaceDef {
  final String exprX;
  final String exprY;
  final String exprZ;
  final String scalarField;

  final double uMin, uMax;
  final double vMin, vMax;
  final double tMin, tMax;
  final int durationMs;
  final double? xMin, xMax, yMin, yMax, zMin, zMax;
  final CoordSystem3D coordSystem;

  ScalarSurfaceDef({
    required this.exprX,
    required this.exprY,
    required this.exprZ,
    required this.scalarField,
    this.uMin = -3.14,
    this.uMax = 3.14,
    this.vMin = -3.14,
    this.vMax = 3.14,
    this.tMin = 0,
    this.tMax = 0,
    this.durationMs = 0,
    this.xMin,
    this.xMax,
    this.yMin,
    this.yMax,
    this.zMin,
    this.zMax,
    this.coordSystem = CoordSystem3D.cartesian,
  });

  bool get hasAnimation => tMax > tMin && durationMs > 0;
}

class Scalar3DWidget extends StatefulWidget {
  final List<ScalarSurfaceDef> surfaces;
  final double yaw;
  final double pitch;
  final double zoom;
  final double centerX;
  final double centerY;
  final double centerZ;
  final bool isDarkMode;
  final bool showLabels;
  final bool autoRotate;
  final CoordSystem3D gridCoordSystem;

  const Scalar3DWidget({
    super.key,
    required this.surfaces,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.centerX,
    required this.centerY,
    required this.centerZ,
    required this.isDarkMode,
    required this.showLabels,
    this.autoRotate = false,
    this.gridCoordSystem = CoordSystem3D.cartesian,
  });

  @override
  State<Scalar3DWidget> createState() => _Scalar3DWidgetState();
}

class _Scalar3DWidgetState extends State<Scalar3DWidget>
    with SingleTickerProviderStateMixin {
  List<SurfaceTriangle3D> _triangles = [];
  bool _needsRecalc = true;
  final ComplexParser _parser = ComplexParser();
  late final Ticker _ticker;
  double _autoRotationOffset = 0.0;
  bool _isInteracting = false;
  double _animationClockMs = 0.0;
  int _lastTickMs = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final elapsedMs = elapsed.inMilliseconds;
      final deltaMs = _lastTickMs == 0 ? 0 : (elapsedMs - _lastTickMs);
      _lastTickMs = elapsedMs;
      if (deltaMs > 0) {
        _animationClockMs += deltaMs;
      }

      final hasAnimatedSurfaces = widget.surfaces.any((s) => s.hasAnimation);
      final shouldAnimateFunction =
          hasAnimatedSurfaces && (_isInteracting == false);

      setState(() {
        if (widget.autoRotate && !_isInteracting) {
          _autoRotationOffset += 0.2;
          if (_autoRotationOffset >= 360) _autoRotationOffset -= 360;
        }
        if (shouldAnimateFunction) {
          _needsRecalc = true;
        }
      });
    });
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant Scalar3DWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.surfaces != oldWidget.surfaces ||
        widget.zoom != oldWidget.zoom ||
        widget.centerX != oldWidget.centerX ||
        widget.centerY != oldWidget.centerY ||
        widget.centerZ != oldWidget.centerZ) {
      _needsRecalc = true;
    }
  }

  static String _normalizeExpr(String expr) {
    return expr
        .trim()
        .replaceAll('×', '*')
        .replaceAll('√', 'sqrt')
        .replaceAll('÷', '/')
        .replaceAll('π', 'pi');
  }

  Color _getColor(double val, double min, double max) {
    if (max == min) return const Color(0xFF0000FF);
    double t = (val - min) / (max - min);

    double hue = 240.0 * (1.0 - t.clamp(0.0, 1.0));
    return HSLColor.fromAHSL(1.0, hue, 1.0, 0.5).toColor();
  }

  double _visibleHalfRange() {
    final range = 15.0 / widget.zoom.clamp(0.001, 1000000.0);
    return range.clamp(0.01, 100000.0);
  }

  int _gridSteps() {
    final rangeScale = math.sqrt(_visibleHalfRange() / 15.0).clamp(0.75, 1.9);
    final zoomDetail = widget.zoom < 0.7
        ? 1.12
        : (widget.zoom > 1.6 ? 1.08 : 1.0);
    return (78 * rangeScale * zoomDetail).round().clamp(64, 150);
  }

  void _calculateGeometry() {
    _triangles = [];

    for (var def in widget.surfaces) {
      try {
        final exprX = _normalizeExpr(def.exprX);
        final exprY = _normalizeExpr(def.exprY);
        final exprZ = _normalizeExpr(def.exprZ);
        final exprS = _normalizeExpr(def.scalarField);
        final vars = <String, Complex>{
          'u': const Complex(0),
          'v': const Complex(0),
          'x': const Complex(0),
          'y': const Complex(0),
          'z': const Complex(0),
          't': const Complex(0),
        };
        final tValue = def.hasAnimation
            ? _computeAnimatedT(def.tMin, def.tMax, def.durationMs)
            : 0.0;
        vars['t'] = Complex(tValue);

        double? evalReal(String expr) {
          try {
            final res = _parser.evaluate(expr, variables: vars);
            if (!res.real.isFinite || !res.imag.isFinite) return null;
            return res.real;
          } catch (_) {
            return null;
          }
        }

        final isCart = def.coordSystem == CoordSystem3D.cartesian;
        final isCyl = def.coordSystem == CoordSystem3D.cylindrical;
        final isSph = def.coordSystem == CoordSystem3D.spherical;

        final viewRange = _visibleHalfRange();
        final double uStart =
            def.xMin ?? (isCart ? widget.centerX - viewRange : 0.0);
        final double uEnd =
            def.xMax ?? (isCart ? widget.centerX + viewRange : 2 * math.pi);
        final double vStart =
            def.yMin ??
            (isCart ? widget.centerY - viewRange : (isSph ? 0.0 : -math.pi));
        final double vEnd =
            def.yMax ?? (isCart ? widget.centerY + viewRange : math.pi);

        final steps = _gridSteps();
        double uStep = (uEnd - uStart) / steps;
        double vStep = (vEnd - vStart) / steps;

        List<List<vmath.Vector3?>> points = List.generate(
          steps + 1,
          (_) => List.filled(steps + 1, null),
        );
        List<List<double?>> scalars = List.generate(
          steps + 1,
          (_) => List.filled(steps + 1, null),
        );

        double minVal = double.infinity;
        double maxVal = double.negativeInfinity;

        for (int i = 0; i <= steps; i++) {
          double u = uStart + i * uStep;
          for (int j = 0; j <= steps; j++) {
            double v = vStart + j * vStep;
            vars['u'] = Complex(u);
            vars['v'] = Complex(v);

            final xRaw = evalReal(exprX);
            final yRaw = evalReal(exprY);
            final zRaw = evalReal(exprZ);

            if (xRaw != null && yRaw != null && zRaw != null) {
              double finalX = xRaw, finalY = yRaw, finalZ = zRaw;
              if (isCyl) {
                finalX = xRaw * math.cos(yRaw);
                finalY = xRaw * math.sin(yRaw);
                finalZ = zRaw;
              } else if (isSph) {
                finalX = xRaw * math.sin(zRaw) * math.cos(yRaw);
                finalY = xRaw * math.sin(zRaw) * math.sin(yRaw);
                finalZ = xRaw * math.cos(zRaw);
              }

              if (def.zMin != null && finalZ < def.zMin!) continue;
              if (def.zMax != null && finalZ > def.zMax!) continue;

              points[i][j] = vmath.Vector3(finalX, finalY, finalZ);

              vars['x'] = Complex(finalX);
              vars['y'] = Complex(finalY);
              vars['z'] = Complex(finalZ);
              final s = evalReal(exprS);
              if (s != null && s.isFinite) {
                scalars[i][j] = s;
                if (s < minVal) minVal = s;
                if (s > maxVal) maxVal = s;
              }
            }
          }
        }

        for (int i = 0; i < steps; i++) {
          for (int j = 0; j < steps; j++) {
            void addTri(int i1, int j1, int i2, int j2, int i3, int j3) {
              final pA = points[i1][j1];
              final pB = points[i2][j2];
              final pC = points[i3][j3];

              final sA = scalars[i1][j1];
              final sB = scalars[i2][j2];
              final sC = scalars[i3][j3];

              if (pA != null &&
                  pB != null &&
                  pC != null &&
                  sA != null &&
                  sB != null &&
                  sC != null &&
                  minVal != double.infinity) {
                final sAvg = (sA + sB + sC) / 3;
                _triangles.add(
                  SurfaceTriangle3D(
                    vmath.Vector3(
                      pA.x - widget.centerX,
                      pA.y - widget.centerY,
                      pA.z - widget.centerZ,
                    ),
                    vmath.Vector3(
                      pB.x - widget.centerX,
                      pB.y - widget.centerY,
                      pB.z - widget.centerZ,
                    ),
                    vmath.Vector3(
                      pC.x - widget.centerX,
                      pC.y - widget.centerY,
                      pC.z - widget.centerZ,
                    ),
                    _getColor(sAvg, minVal, maxVal),
                  ),
                );
              }
            }

            addTri(i, j, i + 1, j, i + 1, j + 1);
            addTri(i, j, i + 1, j + 1, i, j + 1);
          }
        }
      } catch (e) {
        debugPrint('Scalar calc error: $e');
      }
    }
    _needsRecalc = false;
  }

  double _computeAnimatedT(double tMin, double tMax, int durationMs) {
    if (durationMs <= 0 || tMax <= tMin) return tMin;
    final progress = (_animationClockMs % durationMs) / durationMs;
    return tMin + ((tMax - tMin) * progress);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        if (_needsRecalc) _calculateGeometry();
        final halfRange = _visibleHalfRange();
        final yaw = widget.yaw + _autoRotationOffset;
        return Listener(
          onPointerDown: (_) => _isInteracting = true,
          onPointerUp: (_) => _isInteracting = false,
          onPointerCancel: (_) => _isInteracting = false,
          child: Stack(
            children: [
              if (widget.showLabels)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: MainAxesLabelsPainter3D(
                        yawDeg: yaw,
                        pitchDeg: widget.pitch,
                        isDarkMode: widget.isDarkMode,
                        zoom: widget.zoom,
                        centerX: widget.centerX,
                        centerY: widget.centerY,
                        centerZ: widget.centerZ,
                        halfRange: halfRange,
                        gridCoordSystem: widget.gridCoordSystem,
                        showGrid: true,
                        showAxesAndLabels: false,
                      ),
                    ),
                  ),
                ),
              Positioned.fill(
                child: CustomPaint(
                  painter: SurfacePainter3D(
                    triangles: _triangles,
                    yawDeg: yaw,
                    pitchDeg: widget.pitch,
                    zoom: widget.zoom,
                    isDarkMode: widget.isDarkMode,
                  ),
                ),
              ),
              if (widget.showLabels)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: MainAxesLabelsPainter3D(
                        yawDeg: yaw,
                        pitchDeg: widget.pitch,
                        isDarkMode: widget.isDarkMode,
                        zoom: widget.zoom,
                        centerX: widget.centerX,
                        centerY: widget.centerY,
                        centerZ: widget.centerZ,
                        halfRange: halfRange,
                        gridCoordSystem: widget.gridCoordSystem,
                        showGrid: false,
                        showAxesAndLabels: true,
                      ),
                    ),
                  ),
                ),
              if (widget.showLabels)
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: IgnorePointer(
                    child: CustomPaint(
                      size: const Size(92, 92),
                      painter: AxisGizmoPainter3D(
                        yawDeg: yaw,
                        pitchDeg: widget.pitch,
                        isDarkMode: widget.isDarkMode,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
