// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:saber/services/math_engine/math_engine.dart';
import 'package:vector_math/vector_math_64.dart' as vmath;

class VectorFieldDef {
  final String exprX, exprY, exprZ;
  final String funcP, funcQ, funcR;
  final double uMin, uMax, vMin, vMax;
  final double tMin, tMax;
  final int durationMs;

  VectorFieldDef({
    required this.exprX,
    required this.exprY,
    required this.exprZ,
    required this.funcP,
    required this.funcQ,
    required this.funcR,
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

class Vector3DWidget extends StatefulWidget {
  final List<VectorFieldDef> fields;
  final double yaw, pitch, zoom;
  final double centerX, centerY, centerZ;
  final bool isDarkMode, showLabels;
  final bool autoRotate;

  const Vector3DWidget({
    super.key,
    required this.fields,
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
  State<Vector3DWidget> createState() => _Vector3DWidgetState();
}

class _Vector3DWidgetState extends State<Vector3DWidget>
    with SingleTickerProviderStateMixin {
  List<_RenderItem> _renderItems = [];
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

      final hasAnimatedFields = widget.fields.any((f) => f.hasAnimation);
      final shouldAnimateFunction =
          hasAnimatedFields && (_isInteracting == false);

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
  void didUpdateWidget(covariant Vector3DWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fields != oldWidget.fields ||
        widget.zoom != oldWidget.zoom ||
        widget.centerX != oldWidget.centerX ||
        widget.centerY != oldWidget.centerY) {
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

  void _calculateData() {
    _renderItems.clear();

    for (var def in widget.fields) {
      try {
        final exX = _normalizeExpr(def.exprX);
        final exY = _normalizeExpr(def.exprY);
        final exZ = _normalizeExpr(def.exprZ);
        final exP = _normalizeExpr(def.funcP);
        final exQ = _normalizeExpr(def.funcQ);
        final exR = _normalizeExpr(def.funcR);
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

        int surfSteps = 30;
        int vecSteps = 12;

        double uStep = (uEnd - uStart) / surfSteps;
        double vStep = (vEnd - vStart) / surfSteps;

        List<List<vmath.Vector3?>> sGrid = List.generate(
          surfSteps + 1,
          (_) => List.filled(surfSteps + 1, null),
        );

        for (int i = 0; i <= surfSteps; i++) {
          double u = uStart + i * uStep;
          for (int j = 0; j <= surfSteps; j++) {
            double v = vStart + j * vStep;
            vars['u'] = Complex(u);
            vars['v'] = Complex(v);
            final x = evalReal(exX);
            final y = evalReal(exY);
            final z = evalReal(exZ);
            if (x != null && y != null && z != null)
              sGrid[i][j] = vmath.Vector3(x, y, z);
          }
        }

        for (int i = 0; i < surfSteps; i++) {
          for (int j = 0; j < surfSteps; j++) {
            var p1 = sGrid[i][j];
            var p2 = sGrid[i + 1][j];
            var p3 = sGrid[i + 1][j + 1];
            var p4 = sGrid[i][j + 1];
            if (p1 != null && p2 != null && p3 != null && p4 != null) {
              _renderItems.add(
                _RenderItem(
                  type: _Type.surface,
                  p1: p1,
                  p2: p2,
                  p3: p3,
                  p4: p4,
                ),
              );
            }
          }
        }

        uStep = (uEnd - uStart) / vecSteps;
        vStep = (vEnd - vStart) / vecSteps;
        double maxMag = 0.0;
        List<_RawVector> tempVecs = [];

        for (int i = 0; i <= vecSteps; i++) {
          double u = uStart + i * uStep;
          for (int j = 0; j <= vecSteps; j++) {
            double v = vStart + j * vStep;
            vars['u'] = Complex(u);
            vars['v'] = Complex(v);
            final x = evalReal(exX);
            final y = evalReal(exY);
            final z = evalReal(exZ);

            if (x != null && y != null && z != null) {
              vars['x'] = Complex(x);
              vars['y'] = Complex(y);
              vars['z'] = Complex(z);
              final p = evalReal(exP);
              final q = evalReal(exQ);
              final r = evalReal(exR);

              if (p != null && q != null && r != null) {
                final vec = vmath.Vector3(p, q, r);
                double mag = vec.length;
                if (mag > maxMag) maxMag = mag;
                tempVecs.add(_RawVector(vmath.Vector3(x, y, z), vec, mag));
              }
            }
          }
        }

        double scale = maxMag > 0 ? 2.0 / maxMag : 1.0;

        for (var v in tempVecs) {
          vmath.Vector3 end = v.origin + (v.dir * scale);
          double intensity = maxMag > 0 ? v.mag / maxMag : 0;
          double hue = 240 - (240 * intensity);
          Color c = HSLColor.fromAHSL(1.0, hue, 1.0, 0.5).toColor();
          _renderItems.add(
            _RenderItem(type: _Type.vector, p1: v.origin, p2: end, color: c),
          );
        }
      } catch (e) {
        debugPrint("Vector error: $e");
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
      builder: (ctx, box) {
        if (_needsRecalc) _calculateData();
        return Listener(
          onPointerDown: (_) => _isInteracting = true,
          onPointerUp: (_) => _isInteracting = false,
          onPointerCancel: (_) => _isInteracting = false,
          child: CustomPaint(
            size: Size(box.maxWidth, box.maxHeight),
            painter: _VectorPainter(
              _renderItems,
              widget.yaw + _autoRotationOffset,
              widget.pitch,
              widget.zoom,
              widget.centerX,
              widget.centerY,
              widget.centerZ,
              widget.isDarkMode,
              widget.showLabels,
            ),
          ),
        );
      },
    );
  }
}

enum _Type { surface, vector }

class _RawVector {
  vmath.Vector3 origin, dir;
  double mag;
  _RawVector(this.origin, this.dir, this.mag);
}

class _RenderItem {
  _Type type;
  vmath.Vector3 p1;
  vmath.Vector3? p2, p3, p4;
  Color? color;
  _RenderItem({
    required this.type,
    required this.p1,
    this.p2,
    this.p3,
    this.p4,
    this.color,
  });
}

class _VectorPainter extends CustomPainter {
  final List<_RenderItem> items;
  final double yaw, pitch, zoom, cx, cy, cz;
  final bool isDark, showLabels;

  _VectorPainter(
    this.items,
    this.yaw,
    this.pitch,
    this.zoom,
    this.cx,
    this.cy,
    this.cz,
    this.isDark,
    this.showLabels,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / 2;
    final h = size.height / 2;
    final s = 15.0 * zoom;
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

    List<Map<String, dynamic>> drawList = [];

    for (var item in items) {
      if (item.type == _Type.surface) {
        var r1 = proj(item.p1);
        var r2 = proj(item.p2!);
        var r3 = proj(item.p3!);
        var r4 = proj(item.p4!);
        double d = (r1.z + r2.z + r3.z + r4.z) / 4;
        drawList.add({
          't': 0,
          'd': d,
          'p': Path()
            ..moveTo(w + r1.x * s, h - r1.y * s)
            ..lineTo(w + r2.x * s, h - r2.y * s)
            ..lineTo(w + r3.x * s, h - r3.y * s)
            ..lineTo(w + r4.x * s, h - r4.y * s)
            ..close(),
          'c': isDark ? Colors.white10 : Colors.black12,
        });
      } else {
        var r1 = proj(item.p1);
        var r2 = proj(item.p2!);
        double d = (r1.z + r2.z) / 2;
        Offset start = Offset(w + r1.x * s, h - r1.y * s);
        Offset end = Offset(w + r2.x * s, h - r2.y * s);
        drawList.add({'t': 1, 'd': d, 's': start, 'e': end, 'c': item.color});
      }
    }

    drawList.sort((a, b) => (a['d'] as double).compareTo(b['d'] as double));

    if (showLabels) {
      _drawGridAndLabels(canvas, size, rot, s, w, h);
    }

    Paint p = Paint();
    for (var d in drawList) {
      if (d['t'] == 0) {
        canvas.drawPath(
          d['p'],
          p
            ..color = d['c']
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.5,
        );
      } else {
        p
          ..color = d['c']
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        Offset start = d['s'];
        Offset end = d['e'];
        canvas.drawLine(start, end, p);

        double ang = (end - start).direction;
        Offset a1 =
            end + Offset(math.cos(ang + 2.5) * 6, math.sin(ang + 2.5) * 6);
        Offset a2 =
            end + Offset(math.cos(ang - 2.5) * 6, math.sin(ang - 2.5) * 6);
        p.style = PaintingStyle.fill;
        canvas.drawPath(
          Path()
            ..moveTo(end.dx, end.dy)
            ..lineTo(a1.dx, a1.dy)
            ..lineTo(a2.dx, a2.dy)
            ..close(),
          p,
        );
      }
    }
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
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.3)
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
      color: isDark ? Colors.white70 : Colors.black87,
      fontSize: 10,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
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
          axisPaint..color = (isDark ? Colors.white : Colors.black),
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
  bool shouldRepaint(covariant _VectorPainter old) =>
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.zoom != zoom ||
      old.cx != cx ||
      old.cy != cy ||
      old.cz != cz ||
      old.showLabels != showLabels;
}
