// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:saber/services/math_engine/format.dart';
import 'package:saber/services/math_engine/grid.dart';

class OdeSample {
  const OdeSample({required this.t, required this.state});

  final double t;
  final List<double> state;
}

class OdeVisualizerController {
  void Function()? zoomIn;
  void Function()? zoomOut;
}

class OdeTrajectoryVisualizer extends StatefulWidget {
  const OdeTrajectoryVisualizer({
    super.key,
    required this.samples,
    required this.dimension,
    required this.isDarkMode,
    this.showLabels = true,
    this.showGrid = true,
    this.controller,
  });

  final List<OdeSample> samples;
  final int dimension;
  final bool isDarkMode;
  final bool showLabels;
  final bool showGrid;
  final OdeVisualizerController? controller;

  @override
  State<OdeTrajectoryVisualizer> createState() =>
      _OdeTrajectoryVisualizerState();
}

class _OdeTrajectoryVisualizerState extends State<OdeTrajectoryVisualizer> {
  double _zoom2D = 1.0;
  Offset _pan2D = Offset.zero;
  double _yaw = 45;
  double _pitch = -30;
  double _zoom3D = 1.0;
  double _centerX = 0;
  double _centerY = 0;
  double _centerZ = 0;

  @override
  void initState() {
    super.initState();
    _attachController();
  }

  @override
  void didUpdateWidget(covariant OdeTrajectoryVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _attachController();
  }

  void _attachController() {
    final c = widget.controller;
    if (c == null) return;
    c.zoomIn = _zoomIn;
    c.zoomOut = _zoomOut;
  }

  void _zoomIn() {
    setState(() {
      if (widget.dimension == 3) {
        _zoom3D = (_zoom3D * 1.2).clamp(0.3, 15.0);
      } else {
        _zoom2D = (_zoom2D * 1.2).clamp(0.2, 20.0);
      }
    });
  }

  void _zoomOut() {
    setState(() {
      if (widget.dimension == 3) {
        _zoom3D = (_zoom3D / 1.2).clamp(0.3, 15.0);
      } else {
        _zoom2D = (_zoom2D / 1.2).clamp(0.2, 20.0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.dimension == 3) {
      return GestureDetector(
        onScaleStart: (_) {},
        onScaleUpdate: (details) {
          setState(() {
            if (details.scale == 1.0) {
              _yaw -= details.focalPointDelta.dx * 0.5;
              _pitch += details.focalPointDelta.dy * 0.5;
            } else {
              _zoom3D = (_zoom3D * details.scale).clamp(0.3, 15.0);
            }
          });
        },
        child: CustomPaint(
          painter: _OdeTrajectoryPainter(
            samples: widget.samples,
            dimension: widget.dimension,
            isDarkMode: widget.isDarkMode,
            showLabels: widget.showLabels,
            showGrid: widget.showGrid,
            zoom2D: 1.0,
            pan2D: Offset.zero,
            yawDeg: _yaw,
            pitchDeg: _pitch,
            zoom3D: _zoom3D,
            centerX: _centerX,
            centerY: _centerY,
            centerZ: _centerZ,
          ),
          child: const SizedBox.expand(),
        ),
      );
    }

    return GestureDetector(
      onScaleUpdate: (details) {
        setState(() {
          if (details.scale != 1.0) {
            _zoom2D = (_zoom2D * details.scale).clamp(0.2, 20.0);
          }
          _pan2D += details.focalPointDelta;
        });
      },
      child: CustomPaint(
        painter: _OdeTrajectoryPainter(
          samples: widget.samples,
          dimension: widget.dimension,
          isDarkMode: widget.isDarkMode,
          showLabels: widget.showLabels,
          showGrid: widget.showGrid,
          zoom2D: _zoom2D,
          pan2D: _pan2D,
          yawDeg: _yaw,
          pitchDeg: _pitch,
          zoom3D: _zoom3D,
          centerX: _centerX,
          centerY: _centerY,
          centerZ: _centerZ,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _OdeTrajectoryPainter extends CustomPainter {
  const _OdeTrajectoryPainter({
    required this.samples,
    required this.dimension,
    required this.isDarkMode,
    required this.showLabels,
    required this.showGrid,
    required this.zoom2D,
    required this.pan2D,
    required this.yawDeg,
    required this.pitchDeg,
    required this.zoom3D,
    required this.centerX,
    required this.centerY,
    required this.centerZ,
  });

  final List<OdeSample> samples;
  final int dimension;
  final bool isDarkMode;
  final bool showLabels;
  final bool showGrid;
  final double zoom2D;
  final Offset pan2D;
  final double yawDeg;
  final double pitchDeg;
  final double zoom3D;
  final double centerX;
  final double centerY;
  final double centerZ;

  @override
  void paint(Canvas canvas, Size size) {
    final bgColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = bgColor,
    );

    if (samples.isEmpty) {
      _drawHint(canvas, size);
      return;
    }

    if (dimension == 2) {
      _draw2D(canvas, size);
    } else {
      _draw3D(canvas, size);
    }
  }

  void _drawHint(Canvas canvas, Size size) {
    final color = isDarkMode ? Colors.white54 : Colors.black54;
    final tp = TextPainter(
      text: TextSpan(
        text: 'Run solver to animate trajectory',
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
    );
  }

  void _draw2D(Canvas canvas, Size size) {
    final pathColor = isDarkMode ? Colors.cyanAccent : Colors.blue;
    final pointColor = isDarkMode ? Colors.amberAccent : Colors.deepOrange;
    final axisColor = isDarkMode ? Colors.white54 : Colors.black54;
    final gridColor = isDarkMode
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);

    double minX = samples.first.state[0];
    double maxX = minX;
    double minY = samples.first.state[1];
    double maxY = minY;
    for (final s in samples) {
      final x = s.state[0];
      final y = s.state[1];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    final xRange = (maxX - minX).abs() < 1e-12 ? 1.0 : (maxX - minX);
    final yRange = (maxY - minY).abs() < 1e-12 ? 1.0 : (maxY - minY);
    const pad = 32.0;
    final w = (size.width - pad * 2).clamp(1.0, double.infinity);
    final h = (size.height - pad * 2).clamp(1.0, double.infinity);

    final cx = pad + w / 2;
    final cy = pad + h / 2;

    if (showGrid) {
      final gridPaint = Paint()
        ..color = gridColor
        ..strokeWidth = 1;
      const div = 10;
      for (int i = 1; i < div; i++) {
        final x = pad + w * i / div;
        final y = pad + h * i / div;
        canvas.drawLine(Offset(x, pad), Offset(x, size.height - pad), gridPaint);
        canvas.drawLine(Offset(pad, y), Offset(size.width - pad, y), gridPaint);
      }
    }

    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(cx, pad),
      Offset(cx, size.height - pad),
      axisPaint,
    );
    canvas.drawLine(
      Offset(pad, cy),
      Offset(size.width - pad, cy),
      axisPaint,
    );

    Offset mapPoint(OdeSample s) {
      final nx = (s.state[0] - minX) / xRange;
      final ny = (s.state[1] - minY) / yRange;
      final p = Offset(pad + nx * w, size.height - pad - ny * h);
      return _applyPanZoom2D(size, cx, cy, p);
    }

    final path = Path();
    for (int i = 0; i < samples.length; i++) {
      final p = mapPoint(samples[i]);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = pathColor
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    final last = mapPoint(samples.last);
    canvas.drawCircle(last, 5.0, Paint()..color = pointColor);

    if (showLabels) {
      final textStyle = TextStyle(
        color: axisColor,
        fontWeight: FontWeight.w600,
        fontSize: 11,
      );
      _drawLabel(canvas, 'x', Offset(size.width - 22, cy + 4), textStyle);
      _drawLabel(canvas, 'y', const Offset(8, 10), textStyle);
    }
  }

  void _draw3D(Canvas canvas, Size size) {
    final pathColor = isDarkMode ? Colors.cyanAccent : Colors.blue;
    final pointColor = isDarkMode ? Colors.amberAccent : Colors.deepOrange;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final scale = 15.0 * zoom3D;

    final radYaw = yawDeg * math.pi / 180;
    final radPitch = pitchDeg * math.pi / 180;

    final cz = math.cos(radYaw);
    final sz = math.sin(radYaw);
    final cp = math.cos(radPitch - math.pi / 2);
    final sp = math.sin(radPitch - math.pi / 2);

    final r00 = cz;
    final r01 = -sz;
    final r02 = 0.0;
    final r10 = cp * sz;
    final r11 = cp * cz;
    final r12 = -sp;

    Offset proj(double x, double y, double z) {
      final rx = r00 * (x - centerX) + r01 * (y - centerY) + r02 * (z - centerZ);
      final ry = r10 * (x - centerX) + r11 * (y - centerY) + r12 * (z - centerZ);
      return Offset(cx + rx * scale, cy - ry * scale);
    }

    if (showGrid || showLabels) {
      _draw3DAxesAndGrid(
        canvas,
        size,
        proj,
        scale,
        r00,
        r01,
        r02,
        r10,
        r11,
        r12,
      );
    }

    double minX = samples.first.state[0];
    double maxX = minX;
    double minY = samples.first.state[1];
    double maxY = minY;
    double minZ = samples.first.state[2];
    double maxZ = minZ;
    for (final s in samples) {
      if (s.state[0] < minX) minX = s.state[0];
      if (s.state[0] > maxX) maxX = s.state[0];
      if (s.state[1] < minY) minY = s.state[1];
      if (s.state[1] > maxY) maxY = s.state[1];
      if (s.state[2] < minZ) minZ = s.state[2];
      if (s.state[2] > maxZ) maxZ = s.state[2];
    }

    final path = Path();
    for (int i = 0; i < samples.length; i++) {
      final p = proj(
        samples[i].state[0],
        samples[i].state[1],
        samples[i].state[2],
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = pathColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    final lastP = proj(
      samples.last.state[0],
      samples.last.state[1],
      samples.last.state[2],
    );
    canvas.drawCircle(lastP, 5.0, Paint()..color = pointColor);
  }

  void _draw3DAxesAndGrid(
    Canvas canvas,
    Size size,
    Offset Function(double x, double y, double z) proj,
    double scale,
    double r00,
    double r01,
    double r02,
    double r10,
    double r11,
    double r12,
  ) {
    final axisAlpha = isDarkMode ? 0.5 : 0.6;
    final axisPaint = Paint()..strokeWidth = 1.5;

    const L = 1000.0;
    axisPaint.color = Colors.red.withValues(alpha: axisAlpha);
    canvas.drawLine(proj(-L, 0, 0), proj(L, 0, 0), axisPaint);
    axisPaint.color = Colors.green.withValues(alpha: axisAlpha);
    canvas.drawLine(proj(0, -L, 0), proj(0, L, 0), axisPaint);
    axisPaint.color = Colors.blue.withValues(alpha: axisAlpha);
    canvas.drawLine(proj(0, 0, -L), proj(0, 0, L), axisPaint);

    if (showGrid) {
      final tickStep = MathGrid.calculateStepSize(80.0, scale);
      final gridPaint = Paint()
        ..color = (isDarkMode ? Colors.white30 : Colors.black26)
            .withValues(alpha: 0.25)
        ..strokeWidth = 1;
      const int ticks = 6;
      for (int i = -ticks; i <= ticks; i++) {
        if (i == 0) continue;
        final v = i * tickStep;
        final pX = proj(v, 0, 0);
        final pY = proj(0, v, 0);
        final pZ = proj(0, 0, v);
        if (pX.dx >= -50 && pX.dx <= size.width + 50) {
          canvas.drawLine(proj(v, -L, 0), proj(v, L, 0), gridPaint);
          canvas.drawLine(proj(v, 0, -L), proj(v, 0, L), gridPaint);
        }
        if (pY.dy >= -50 && pY.dy <= size.height + 50) {
          canvas.drawLine(proj(-L, v, 0), proj(L, v, 0), gridPaint);
          canvas.drawLine(proj(0, v, -L), proj(0, v, L), gridPaint);
        }
        if (pZ.dx >= -50 && pZ.dx <= size.width + 50) {
          canvas.drawLine(proj(-L, 0, v), proj(L, 0, v), gridPaint);
          canvas.drawLine(proj(0, -L, v), proj(0, L, v), gridPaint);
        }
      }
    }

    if (showLabels) {
      final tickStep = MathGrid.calculateStepSize(80.0, scale);
      final labelStyle = TextStyle(
        color: isDarkMode ? Colors.white70 : Colors.black87,
        fontSize: 10,
        backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      );
      const int ticks = 6;
      void drawTicks(String axis) {
        for (int i = -ticks; i <= ticks; i++) {
          if (i == 0) continue;
          final v = i * tickStep;
          double wx = centerX, wy = centerY, wz = centerZ;
          if (axis == 'x') wx += v;
          else if (axis == 'y') wy += v;
          else wz += v;
          final p = proj(wx, wy, wz);
          if (p.dx < -50 ||
              p.dx > size.width + 50 ||
              p.dy < -50 ||
              p.dy > size.height + 50) continue;
          final val = axis == 'x' ? wx : (axis == 'y' ? wy : wz);
          final tp = TextPainter(
            text: TextSpan(
              text: MathFormatter.formatAxisLabel(val, precision: 2),
              style: labelStyle,
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, p + const Offset(4, 4));
        }
      }
      drawTicks('x');
      drawTicks('y');
      drawTicks('z');
    }

    _draw3DGizmo(canvas, size, r00, r01, r02, r10, r11, r12);
  }

  void _draw3DGizmo(
    Canvas canvas,
    Size size,
    double r00,
    double r01,
    double r02,
    double r10,
    double r11,
    double r12,
  ) {
    final origin = Offset(36, size.height - 36);
    const len = 22.0;
    final paint = Paint()..strokeWidth = 2.0;

    double rx(double x, double y, double z) =>
        r00 * x + r01 * y + r02 * z;
    double ry(double x, double y, double z) =>
        r10 * x + r11 * y + r12 * z;

    paint.color = Colors.red;
    canvas.drawLine(origin, origin + Offset(rx(len, 0, 0), -ry(len, 0, 0)), paint);
    paint.color = Colors.green;
    canvas.drawLine(origin, origin + Offset(rx(0, len, 0), -ry(0, len, 0)), paint);
    paint.color = Colors.blue;
    canvas.drawLine(origin, origin + Offset(rx(0, 0, len), -ry(0, 0, len)), paint);

    if (showLabels) {
      final tp = TextPainter(textDirection: TextDirection.ltr);
      void drawLabel(String text, double x, double y, double z, Color color) {
        final p = origin + Offset(rx(x, y, z), -ry(x, y, z));
        tp.text = TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 10,
          ),
        );
        tp.layout();
        tp.paint(canvas, p);
      }
      drawLabel('X', len + 4, 0, 0, Colors.red);
      drawLabel('Y', 0, len + 4, 0, Colors.green);
      drawLabel('Z', 0, 0, len + 4, Colors.blue);
    }
  }

  Offset _applyPanZoom2D(Size size, double cx, double cy, Offset p) {
    final center = Offset(cx, cy);
    final moved = p - center;
    return center + (moved * zoom2D) + pan2D;
  }

  void _drawLabel(
    Canvas canvas,
    String text,
    Offset offset,
    TextStyle style,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _OdeTrajectoryPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.dimension != dimension ||
        oldDelegate.isDarkMode != isDarkMode ||
        oldDelegate.showLabels != showLabels ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.zoom2D != zoom2D ||
        oldDelegate.pan2D != pan2D ||
        oldDelegate.yawDeg != yawDeg ||
        oldDelegate.pitchDeg != pitchDeg ||
        oldDelegate.zoom3D != zoom3D ||
        oldDelegate.centerX != centerX ||
        oldDelegate.centerY != centerY ||
        oldDelegate.centerZ != centerZ;
  }
}
