// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:saber/services/math_engine/math_engine.dart';

enum CoordSystem2D { cartesian, polar }

class PlotLine2D {
  final String expression;
  final Color color;
  final bool fillArea;
  final double tMin;
  final double tMax;
  final int durationMs;
  final double? xMin, xMax, yMin, yMax;
  final CoordSystem2D coordSystem;

  PlotLine2D({
    required this.expression,
    required this.color,
    this.fillArea = false,
    this.tMin = 0,
    this.tMax = 0,
    this.durationMs = 0,
    this.xMin,
    this.xMax,
    this.yMin,
    this.yMax,
    this.coordSystem = CoordSystem2D.cartesian,
  });

  bool get hasAnimation => tMax > tMin && durationMs > 0;
}

class Plot2DPainter extends CustomPainter {
  final List<PlotLine2D> functions;
  final double offsetX;
  final double offsetY;
  final double zoom2D;
  final bool isDarkMode;
  final Color accentColor;
  final bool isComplex;
  final double resolutionScale;
  final bool showAxisLabels;
  final CoordSystem2D gridCoordSystem;

  final double animationClockMs;

  static final ComplexParser _complexParser = ComplexParser();

  Plot2DPainter({
    required this.functions,
    required this.offsetX,
    required this.offsetY,
    required this.zoom2D,
    required this.isDarkMode,
    required this.accentColor,
    this.isComplex = false,
    this.resolutionScale = 1.0,
    this.showAxisLabels = true,
    this.gridCoordSystem = CoordSystem2D.cartesian,
    this.animationClockMs = 0,
  });

  double _computeAnimatedT(PlotLine2D line) {
    if (!line.hasAnimation) return line.tMin;
    final duration = line.durationMs.toDouble();
    if (duration <= 0 || line.tMax <= line.tMin) return line.tMin;
    final progress = (animationClockMs % duration) / duration;
    return line.tMin + (line.tMax - line.tMin) * progress;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2 + offsetX;
    final cy = size.height / 2 + offsetY;

    final paintAxis = Paint()
      ..color = isDarkMode ? Colors.white38 : Colors.black38
      ..strokeWidth = 1.5 * resolutionScale;

    final paintGrid = Paint()
      ..color = isDarkMode ? Colors.white10 : Colors.black.withOpacity(0.05)
      ..strokeWidth = 1 * resolutionScale;

    _drawGrid(canvas, size, cx, cy, paintGrid, paintAxis);

    for (var plotLine in functions) {
      if (plotLine.expression.trim().isEmpty) continue;

      try {
        final expression = plotLine.expression
            .replaceAll('×', '*')
            .replaceAll('^', '^');
        _paintSingleGraph(canvas, size, cx, cy, expression, plotLine);
      } catch (e) {}
    }

    if (isComplex) {
      _drawComplexLabel(canvas, size);
    }
  }

  void _paintSingleGraph(
    Canvas canvas,
    Size size,
    double cx,
    double cy,
    String expression,
    PlotLine2D plotLine,
  ) {
    final path = Path();
    final fillPath = Path();

    final paintStroke = Paint()
      ..color = isComplex ? Colors.purpleAccent : plotLine.color
      ..strokeWidth = 2.5 * resolutionScale
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    Paint? paintFill;
    if (plotLine.fillArea && !isComplex) {
      paintFill = Paint()
        ..color = plotLine.color.withOpacity(0.2)
        ..style = PaintingStyle.fill;
    }

    final tValue = _computeAnimatedT(plotLine);

    bool first = true;
    bool hasPoints = false;

    if (plotLine.coordSystem == CoordSystem2D.polar) {
      double tMin = plotLine.xMin ?? 0.0;
      double tMax = plotLine.xMax ?? 2 * math.pi;
      int steps = (size.width * resolutionScale).toInt().clamp(500, 3000);
      double dTheta = (tMax - tMin) / steps;

      for (int i = 0; i <= steps; i++) {
        double theta = tMin + i * dTheta;
        final variables = <String, Complex>{
          'x': Complex(theta),
          'theta': Complex(theta),
          'y': const Complex(0),
          if (plotLine.hasAnimation) 't': Complex(tValue),
        };
        try {
          final result = _complexParser.evaluate(
            expression,
            variables: variables,
          );
          final rVal = isComplex ? result.abs() : result.real;

          bool inBounds = true;
          if (plotLine.yMin != null && rVal < plotLine.yMin!) inBounds = false;
          if (plotLine.yMax != null && rVal > plotLine.yMax!) inBounds = false;

          double xVal = rVal * math.cos(theta);
          double yVal = rVal * math.sin(theta);
          double xPx = cx + (xVal * zoom2D);
          double yPx = cy - (yVal * zoom2D);

          if (rVal.isFinite && inBounds) {
            if (xPx >= -size.width &&
                xPx <= size.width * 2 &&
                yPx >= -size.height &&
                yPx <= size.height * 2) {
              if (first) {
                path.moveTo(xPx, yPx);
                if (plotLine.fillArea) {
                  fillPath.moveTo(xPx, cy);
                  fillPath.lineTo(xPx, yPx);
                }
                first = false;
              } else {
                path.lineTo(xPx, yPx);
                if (plotLine.fillArea) fillPath.lineTo(xPx, yPx);
              }
              hasPoints = true;
            } else {
              first = true;
              if (plotLine.fillArea && hasPoints) fillPath.lineTo(xPx, cy);
            }
          } else {
            first = true;
            if (plotLine.fillArea && hasPoints) fillPath.lineTo(xPx, cy);
          }
        } catch (_) {
          first = true;
        }
      }
    } else {
      final step = resolutionScale > 2 ? 1.0 : 1.0;
      double startX = 0;
      double endX = size.width;
      if (plotLine.xMin != null) {
        double px = cx + plotLine.xMin! * zoom2D;
        if (px > startX) startX = px;
      }
      if (plotLine.xMax != null) {
        double px = cx + plotLine.xMax! * zoom2D;
        if (px < endX) endX = px;
      }

      for (double xPx = startX; xPx <= endX; xPx += step) {
        final xVal = (xPx - cx) / zoom2D;
        final variables = <String, Complex>{
          'x': Complex(xVal),
          'y': const Complex(0),
          if (plotLine.hasAnimation) 't': Complex(tValue),
        };

        try {
          final result = _complexParser.evaluate(
            expression,
            variables: variables,
          );
          final yVal = isComplex ? result.abs() : result.real;

          bool inBounds = true;
          if (plotLine.yMin != null && yVal < plotLine.yMin!) inBounds = false;
          if (plotLine.yMax != null && yVal > plotLine.yMax!) inBounds = false;

          if (yVal.isFinite && inBounds) {
            final yPx = cy - (yVal * zoom2D);

            if (yPx >= -size.height * 2 && yPx <= size.height * 2) {
              if (first) {
                path.moveTo(xPx, yPx);
                if (plotLine.fillArea) {
                  fillPath.moveTo(xPx, cy);
                  fillPath.lineTo(xPx, yPx);
                }
                first = false;
              } else {
                path.lineTo(xPx, yPx);
                if (plotLine.fillArea) fillPath.lineTo(xPx, yPx);
              }
              hasPoints = true;
            } else {
              first = true;
              if (plotLine.fillArea && hasPoints) fillPath.lineTo(xPx, cy);
            }
          } else {
            first = true;
            if (plotLine.fillArea && hasPoints) fillPath.lineTo(xPx, cy);
          }
        } catch (_) {
          first = true;
        }
      }
    }

    if (plotLine.fillArea && hasPoints) {
      fillPath.lineTo(size.width, cy);
      fillPath.close();
      canvas.drawPath(fillPath, paintFill!);
    }

    canvas.drawPath(path, paintStroke);
  }

  void _drawGrid(
    Canvas canvas,
    Size size,
    double cx,
    double cy,
    Paint grid,
    Paint axis,
  ) {
    if (gridCoordSystem == CoordSystem2D.polar) {
      _drawPolarGrid(canvas, size, cx, cy, grid, axis);
      return;
    }

    final targetStepPx = 80.0 * resolutionScale;
    final stepUnit = MathGrid.calculateStepSize(targetStepPx, zoom2D);

    final stepPx = stepUnit * zoom2D;

    final textStyle = TextStyle(
      color: isDarkMode ? Colors.white54 : Colors.black54,
      fontSize: 10 * resolutionScale,
    );

    final startXIndex = (-cx / stepPx).floor();
    final endXIndex = ((size.width - cx) / stepPx).ceil();

    for (int i = startXIndex; i <= endXIndex; i++) {
      final x = cx + i * stepPx;
      final val = i * stepUnit;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      if (showAxisLabels && val != 0) {
        final span = TextSpan(
          text: MathFormatter.formatAxisLabel(val, precision: 1),
          style: textStyle,
        );
        final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
          ..layout();
        double yPos = cy + 4 * resolutionScale;
        yPos = yPos.clamp(0.0, size.height - tp.height);
        tp.paint(canvas, Offset(x - tp.width / 2, yPos));
      }
    }

    final startYIndex = (-cy / stepPx).floor();
    final endYIndex = ((size.height - cy) / stepPx).ceil();

    for (int i = startYIndex; i <= endYIndex; i++) {
      final y = cy + i * stepPx;
      final val = -i * stepUnit;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);

      if (showAxisLabels && val != 0) {
        final span = TextSpan(
          text: MathFormatter.formatAxisLabel(val, precision: 1),
          style: textStyle,
        );
        final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
          ..layout();
        double xPos = cx - tp.width - 4 * resolutionScale;
        xPos = xPos.clamp(0.0, size.width - tp.width);
        tp.paint(canvas, Offset(xPos, y - tp.height / 2));
      }
    }

    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), axis);
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), axis);

    if (showAxisLabels) {
      final span = TextSpan(text: "0", style: textStyle);
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(cx - tp.width - 2, cy + 2));
    }
  }

  void _drawPolarGrid(
    Canvas canvas,
    Size size,
    double cx,
    double cy,
    Paint grid,
    Paint axis,
  ) {
    final targetStepPx = 80.0 * resolutionScale;
    final stepUnit = MathGrid.calculateStepSize(targetStepPx, zoom2D);
    final stepPx = stepUnit * zoom2D;
    final maxRadius = math.sqrt(
      math.pow(math.max(cx, size.width - cx), 2) +
          math.pow(math.max(cy, size.height - cy), 2),
    );
    final textStyle = TextStyle(
      color: isDarkMode ? Colors.white54 : Colors.black54,
      fontSize: 10 * resolutionScale,
    );

    for (double r = stepPx; r <= maxRadius; r += stepPx) {
      canvas.drawCircle(Offset(cx, cy), r, grid);
      if (showAxisLabels) {
        final label = MathFormatter.formatAxisLabel(r / zoom2D, precision: 1);
        final tp = TextPainter(
          text: TextSpan(text: label, style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final p = Offset(cx + r + 4 * resolutionScale, cy + 2);
        if (p.dx + tp.width < size.width) {
          tp.paint(canvas, p);
        }
      }
    }

    const angleStep = math.pi / 12;
    for (double a = 0; a < math.pi * 2; a += angleStep) {
      final end = Offset(
        cx + math.cos(a) * maxRadius,
        cy - math.sin(a) * maxRadius,
      );
      final start = Offset(
        cx - math.cos(a) * maxRadius,
        cy + math.sin(a) * maxRadius,
      );
      canvas.drawLine(start, end, grid);
    }

    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), axis);
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), axis);

    if (showAxisLabels) {
      final tp = TextPainter(
        text: TextSpan(text: '0', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width - 2, cy + 2));
    }
  }

  void _drawComplexLabel(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: "Plotting Magnitude |f(x)|",
        style: TextStyle(
          color: isDarkMode ? Colors.white60 : Colors.black54,
          fontSize: 10 * resolutionScale,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(8, size.height - (20 * resolutionScale)));
  }

  @override
  bool shouldRepaint(covariant Plot2DPainter oldDelegate) {
    if (oldDelegate.animationClockMs != animationClockMs) return true;
    if (oldDelegate.functions.length != functions.length) return true;
    if (oldDelegate.offsetX != offsetX ||
        oldDelegate.offsetY != offsetY ||
        oldDelegate.zoom2D != zoom2D ||
        oldDelegate.gridCoordSystem != gridCoordSystem)
      return true;
    return false;
  }
}

class Plot2DWidget extends StatefulWidget {
  const Plot2DWidget({
    super.key,
    required this.functions,
    required this.offsetX,
    required this.offsetY,
    required this.zoom2D,
    required this.isDarkMode,
    required this.accentColor,
    this.isComplex = false,
    this.showAxisLabels = true,
    this.gridCoordSystem = CoordSystem2D.cartesian,
  });

  final List<PlotLine2D> functions;
  final double offsetX;
  final double offsetY;
  final double zoom2D;
  final bool isDarkMode;
  final Color accentColor;
  final bool isComplex;
  final bool showAxisLabels;
  final CoordSystem2D gridCoordSystem;

  @override
  State<Plot2DWidget> createState() => _Plot2DWidgetState();
}

class _Plot2DWidgetState extends State<Plot2DWidget>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _animationClockMs = 0;
  int _lastTickMs = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final elapsedMs = elapsed.inMilliseconds;
      final deltaMs = _lastTickMs == 0 ? 0 : (elapsedMs - _lastTickMs);
      _lastTickMs = elapsedMs;
      if (deltaMs > 0) _animationClockMs += deltaMs;

      final hasAnimated = widget.functions.any((f) => f.hasAnimation);
      if (hasAnimated) setState(() {});
    });
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: Plot2DPainter(
        functions: widget.functions,
        offsetX: widget.offsetX,
        offsetY: widget.offsetY,
        zoom2D: widget.zoom2D,
        isDarkMode: widget.isDarkMode,
        accentColor: widget.accentColor,
        isComplex: widget.isComplex,
        resolutionScale: 1.0,
        showAxisLabels: widget.showAxisLabels,
        gridCoordSystem: widget.gridCoordSystem,
        animationClockMs: _animationClockMs,
      ),
    );
  }
}
