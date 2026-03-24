// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
  });

  @override
  State<Scalar3DWidget> createState() => _Scalar3DWidgetState();
}

class _Scalar3DWidgetState extends State<Scalar3DWidget>
    with SingleTickerProviderStateMixin {
  List<_RenderTriangle> _triangles = [];
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

  void _calculateGeometry() {
    _triangles.clear();

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

        final double viewRange = 12.0;
        final double uStart = widget.centerX - viewRange;
        final double uEnd = widget.centerX + viewRange;
        final double vStart = widget.centerY - viewRange;
        final double vEnd = widget.centerY + viewRange;

        int steps = 45;
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

            final x = evalReal(exprX);
            final y = evalReal(exprY);
            final z = evalReal(exprZ);

            if (x != null && y != null && z != null) {
              points[i][j] = vmath.Vector3(x, y, z);

              vars['x'] = Complex(x);
              vars['y'] = Complex(y);
              vars['z'] = Complex(z);
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

                Color cA = _getColor(sA, minVal, maxVal);
                Color cB = _getColor(sB, minVal, maxVal);
                Color cC = _getColor(sC, minVal, maxVal);

                double zAvg = (pA.z + pB.z + pC.z) / 3;

                _triangles.add(_RenderTriangle(pA, pB, pC, cA, cB, cC, zAvg));
              }
            }

            addTri(i, j, i + 1, j, i + 1, j + 1);
            addTri(i, j, i + 1, j + 1, i, j + 1);
          }
        }
      } catch (e) {
        debugPrint("Scalar calc error: $e");
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
        return Listener(
          onPointerDown: (_) => _isInteracting = true,
          onPointerUp: (_) => _isInteracting = false,
          onPointerCancel: (_) => _isInteracting = false,
          child: CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _ScalarPainter(
              triangles: _triangles,
              yaw: widget.yaw + _autoRotationOffset,
              pitch: widget.pitch,
              zoom: widget.zoom,
              cx: widget.centerX,
              cy: widget.centerY,
              cz: widget.centerZ,
              showLabels: widget.showLabels,
              isDarkMode: widget.isDarkMode,
            ),
          ),
        );
      },
    );
  }
}

class _RenderTriangle {
  final vmath.Vector3 p1, p2, p3;
  final Color c1, c2, c3;
  final double zCentroid;
  _RenderTriangle(
    this.p1,
    this.p2,
    this.p3,
    this.c1,
    this.c2,
    this.c3,
    this.zCentroid,
  );
}

class _SortedTriIndex {
  final int index;
  final double depth;
  _SortedTriIndex(this.index, this.depth);
}

class _ScalarPainter extends CustomPainter {
  final List<_RenderTriangle> triangles;
  final double yaw, pitch, zoom, cx, cy, cz;
  final bool showLabels, isDarkMode;

  _ScalarPainter({
    required this.triangles,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.cx,
    required this.cy,
    required this.cz,
    required this.showLabels,
    required this.isDarkMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / 2;
    final h = size.height / 2;
    final scale = 15.0 * zoom;

    final rot =
        vmath.Matrix3.rotationX(vmath.radians(pitch) - math.pi / 2) *
        vmath.Matrix3.rotationZ(vmath.radians(yaw));

    vmath.Vector3 proj(vmath.Vector3 v) {
      double x = v.x - cx;
      double y = v.y - cy;
      double z = v.z - cz;
      return vmath.Vector3(
        rot[0] * x + rot[3] * y + rot[6] * z,
        rot[1] * x + rot[4] * y + rot[7] * z,
        rot[2] * x + rot[5] * y + rot[8] * z,
      );
    }

    List<_SortedTriIndex> sortList = [];
    List<Float32List> projectedVerts = [];

    for (int i = 0; i < triangles.length; i++) {
      var tri = triangles[i];

      var r1 = proj(tri.p1);
      var r2 = proj(tri.p2);
      var r3 = proj(tri.p3);

      projectedVerts.add(
        Float32List.fromList([w + r1.x * scale, h - r1.y * scale]),
      );
      projectedVerts.add(
        Float32List.fromList([w + r2.x * scale, h - r2.y * scale]),
      );
      projectedVerts.add(
        Float32List.fromList([w + r3.x * scale, h - r3.y * scale]),
      );

      double depth = (r1.z + r2.z + r3.z) / 3;
      sortList.add(_SortedTriIndex(i, depth));
    }

    sortList.sort((a, b) => a.depth.compareTo(b.depth));

    int vertexCount = triangles.length * 3;
    Float32List positions = Float32List(vertexCount * 2);
    Int32List colors = Int32List(vertexCount);

    for (int i = 0; i < sortList.length; i++) {
      int triIdx = sortList[i].index;
      _RenderTriangle tri = triangles[triIdx];

      int vBase = triIdx * 3;
      int bufBase = i * 6;
      int colBase = i * 3;

      var v1 = projectedVerts[vBase];
      positions[bufBase] = v1[0];
      positions[bufBase + 1] = v1[1];
      colors[colBase] = tri.c1.value;

      var v2 = projectedVerts[vBase + 1];
      positions[bufBase + 2] = v2[0];
      positions[bufBase + 3] = v2[1];
      colors[colBase + 1] = tri.c2.value;

      var v3 = projectedVerts[vBase + 2];
      positions[bufBase + 4] = v3[0];
      positions[bufBase + 5] = v3[1];
      colors[colBase + 2] = tri.c3.value;
    }

    if (showLabels) {
      _drawGridAndLabels(canvas, size, rot, scale, w, h);
    }

    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      colors: colors,
    );

    Paint paint = Paint()..style = PaintingStyle.fill;
    canvas.drawVertices(vertices, BlendMode.srcOver, paint);
  }

  void _drawGridAndLabels(
    Canvas canvas,
    Size size,
    vmath.Matrix3 rot,
    double scale,
    double cx,
    double cy,
  ) {
    final axisPaint = Paint()
      ..color = (isDarkMode ? Colors.white : Colors.black).withValues(
        alpha: 0.3,
      )
      ..strokeWidth = 1.0;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    Offset project(double x, double y, double z) {
      final relX = x - this.cx;
      final relY = y - this.cy;
      final relZ = z - this.cz;
      final rx = rot[0] * relX + rot[3] * relY + rot[6] * relZ;
      final ry = rot[1] * relX + rot[4] * relY + rot[7] * relZ;
      return Offset(cx + rx * scale, cy - ry * scale);
    }

    final double step = MathGrid.calculateStepSize(80.0, scale);

    final double L = 10000.0;
    canvas.drawLine(
      project(-L, 0, 0),
      project(L, 0, 0),
      axisPaint..color = Colors.red.withOpacity(0.4),
    );
    canvas.drawLine(
      project(0, -L, 0),
      project(0, L, 0),
      axisPaint..color = Colors.green.withOpacity(0.4),
    );
    canvas.drawLine(
      project(0, 0, -L),
      project(0, 0, L),
      axisPaint..color = Colors.blue.withOpacity(0.4),
    );

    final int ticks = 6;
    TextStyle style = TextStyle(
      color: isDarkMode ? Colors.white70 : Colors.black87,
      fontSize: 10,
      backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
    );

    final lx = math.sqrt(rot[0] * rot[0] + rot[1] * rot[1]);
    final ly = math.sqrt(rot[3] * rot[3] + rot[4] * rot[4]);
    final lz = math.sqrt(rot[6] * rot[6] + rot[7] * rot[7]);
    final ax = lx > 1e-6 ? Offset(rot[0] / lx, -rot[1] / lx) : Offset.zero;
    final ay = ly > 1e-6 ? Offset(rot[3] / ly, -rot[4] / ly) : Offset.zero;
    final az = lz > 1e-6 ? Offset(rot[6] / lz, -rot[7] / lz) : Offset.zero;
    const labelOffset = 8.0;

    void drawTicks(String axis) {
      final unit = axis == 'x' ? ax : (axis == 'y' ? ay : az);

      double centerVal = axis == 'x'
          ? this.cx
          : (axis == 'y' ? this.cy : this.cz);
      double start = (centerVal / step).floor() * step;

      for (int i = -ticks; i <= ticks; i++) {
        double val = start + (i * step);
        if (val.abs() < 1e-5) continue;

        double wx = 0, wy = 0, wz = 0;
        if (axis == 'x') {
          wx = val;
        } else if (axis == 'y') {
          wy = val;
        } else {
          wz = val;
        }

        Offset p = project(wx, wy, wz);
        if (p.dx < -50 ||
            p.dx > size.width + 50 ||
            p.dy < -50 ||
            p.dy > size.height + 50)
          continue;
        canvas.drawCircle(
          p,
          2,
          axisPaint..color = (isDarkMode ? Colors.white : Colors.black),
        );
        textPainter.text = TextSpan(
          text: MathFormatter.formatAxisLabel(val, precision: 2),
          style: style,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          p + Offset(unit.dx * labelOffset, unit.dy * labelOffset),
        );
      }
    }

    drawTicks('x');
    drawTicks('y');
    drawTicks('z');
    _drawGizmo(canvas, size, rot);
  }

  void _drawGizmo(Canvas canvas, Size size, vmath.Matrix3 rot) {
    final paint = Paint()..strokeWidth = 2.0;
    final origin = Offset(35, size.height - 35);
    final len = 20.0;
    const labelOffset = 10.0;
    Offset proj(double x, double y, double z) {
      final rx = rot[0] * x + rot[3] * y + rot[6] * z;
      final ry = rot[1] * x + rot[4] * y + rot[7] * z;
      return origin + Offset(rx, -ry);
    }

    canvas.drawLine(origin, proj(len, 0, 0), paint..color = Colors.red);
    canvas.drawLine(origin, proj(0, len, 0), paint..color = Colors.green);
    canvas.drawLine(origin, proj(0, 0, len), paint..color = Colors.blue);

    final lx = math.sqrt(rot[0] * rot[0] + rot[1] * rot[1]);
    final ly = math.sqrt(rot[3] * rot[3] + rot[4] * rot[4]);
    final lz = math.sqrt(rot[6] * rot[6] + rot[7] * rot[7]);
    final ux = lx > 1e-6 ? Offset(rot[0] / lx, -rot[1] / lx) : Offset.zero;
    final uy = ly > 1e-6 ? Offset(rot[3] / ly, -rot[4] / ly) : Offset.zero;
    final uz = lz > 1e-6 ? Offset(rot[6] / lz, -rot[7] / lz) : Offset.zero;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    void lbl(String s, Offset axisTip, Offset unit, Color c) {
      final p = axisTip + Offset(unit.dx * labelOffset, unit.dy * labelOffset);
      tp.text = TextSpan(
        text: s,
        style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 9),
      );
      tp.layout();
      tp.paint(canvas, p);
    }

    lbl("X", proj(len, 0, 0), ux, Colors.red);
    lbl("Y", proj(0, len, 0), uy, Colors.green);
    lbl("Z", proj(0, 0, len), uz, Colors.blue);
  }

  @override
  bool shouldRepaint(covariant _ScalarPainter old) =>
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.zoom != zoom ||
      old.cx != cx ||
      old.cy != cy ||
      old.cz != cz ||
      old.showLabels != showLabels;
}
