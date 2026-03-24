// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

class FunctionPlotter {
  static Future<Uint8List?> plotFunction({
    required String function,
    double xMin = -10,
    double xMax = 10,
    int width = 800,
    int height = 600,
  }) async {
    final evaluator = ExpressionEvaluator();
    late double Function(double) fn;
    try {
      fn = evaluator.compile(function);
    } catch (e) {

      debugPrint('Function plotter error: $e');
      return null;
    }

    final samples = 800;
    final xs = List<double>.generate(
      samples,
      (i) => xMin + (xMax - xMin) * i / (samples - 1),
    );
    final ys = <double>[];
    for (final x in xs) {
      final y = fn(x);
      if (y.isFinite) ys.add(y);
    }
    if (ys.isEmpty) return null;
    final minY = ys.reduce(math.min);
    final maxY = ys.reduce(math.max);
    final yPad = (maxY - minY).abs() * 0.1 + 1e-6;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final bg = ui.Paint()..color = const ui.Color(0xFFFFFFFF);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      bg,
    );

    final axisPaint = ui.Paint()
      ..color = const ui.Color(0xFFAAAAAA)
      ..strokeWidth = 1;
    final originX = ((0 - xMin) / (xMax - xMin) * width).clamp(
      0.0,
      width.toDouble(),
    );
    final originY =
        (height -
                ((0 - (minY - yPad)) /
                    ((maxY + yPad) - (minY - yPad)) *
                    height))
            .clamp(0.0, height.toDouble());
    canvas.drawLine(
      ui.Offset(0, originY),
      ui.Offset(width.toDouble(), originY),
      axisPaint,
    );
    canvas.drawLine(
      ui.Offset(originX, 0),
      ui.Offset(originX, height.toDouble()),
      axisPaint,
    );

    final path = ui.Path();
    bool started = false;
    for (int i = 0; i < xs.length; i++) {
      final x = xs[i];
      final y = fn(x);
      if (!y.isFinite) continue;
      final px = (x - xMin) / (xMax - xMin) * width;
      final py =
          height -
          (y - (minY - yPad)) / ((maxY + yPad) - (minY - yPad)) * height;
      if (!started) {
        path.moveTo(px, py);
        started = true;
      } else {
        path.lineTo(px, py);
      }
    }
    final line = ui.Paint()
      ..color = const ui.Color(0xFF1976D2)
      ..strokeWidth = 2
      ..style = ui.PaintingStyle.stroke;
    canvas.drawPath(path, line);

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  static Future<Uint8List?> plotPolar({
    required String function,
    double thetaMin = 0,
    double thetaMax = 2 * math.pi,
    int width = 800,
    int height = 800,
  }) async {
    final evaluator = ExpressionEvaluator();
    late double Function(double) fr;
    try {
      fr = evaluator.compile(function);
    } catch (e) {
      debugPrint('Polar plot error: $e');
      return null;
    }

    final samples = 900;
    final thetas = List<double>.generate(
      samples,
      (i) => thetaMin + (thetaMax - thetaMin) * i / (samples - 1),
    );

    final points = <ui.Offset>[];
    for (final t in thetas) {
      final r = fr(t);
      if (!r.isFinite) continue;
      final x = r * math.cos(t);
      final y = r * math.sin(t);
      points.add(ui.Offset(x, y));
    }
    if (points.isEmpty) return null;

    double minX = points.first.dx, maxX = points.first.dx;
    double minY = points.first.dy, maxY = points.first.dy;
    for (final p in points) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    final padX = (maxX - minX).abs() * 0.1 + 1e-6;
    final padY = (maxY - minY).abs() * 0.1 + 1e-6;
    minX -= padX;
    maxX += padX;
    minY -= padY;
    maxY += padY;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final bg = ui.Paint()..color = const ui.Color(0xFFFFFFFF);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      bg,
    );

    final axisPaint = ui.Paint()
      ..color = const ui.Color(0xFFAAAAAA)
      ..strokeWidth = 1;
    final originX = ((0 - minX) / (maxX - minX) * width).clamp(
      0.0,
      width.toDouble(),
    );
    final originY = (height - ((0 - minY) / ((maxY) - (minY)) * height)).clamp(
      0.0,
      height.toDouble(),
    );
    canvas.drawLine(
      ui.Offset(0, originY),
      ui.Offset(width.toDouble(), originY),
      axisPaint,
    );
    canvas.drawLine(
      ui.Offset(originX, 0),
      ui.Offset(originX, height.toDouble()),
      axisPaint,
    );

    final path = ui.Path();
    bool started = false;
    for (final p in points) {
      final px = (p.dx - minX) / (maxX - minX) * width;
      final py = height - (p.dy - minY) / (maxY - minY) * height;
      if (!started) {
        path.moveTo(px, py);
        started = true;
      } else {
        path.lineTo(px, py);
      }
    }
    final line = ui.Paint()
      ..color = const ui.Color(0xFF1976D2)
      ..strokeWidth = 2
      ..style = ui.PaintingStyle.stroke;
    canvas.drawPath(path, line);

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  static Future<Uint8List?> plotSurface({
    required String function,
    double xMin = -5,
    double xMax = 5,
    double yMin = -5,
    double yMax = 5,
    int width = 800,
    int height = 600,
    int samples = 120,
  }) async {
    final evaluator = ExpressionEvaluator();
    late double Function(double, double) fn;
    try {
      fn = evaluator.compile2(function);
    } catch (_) {
      return null;
    }

    final xs = List<double>.generate(
      samples,
      (i) => xMin + (xMax - xMin) * i / (samples - 1),
    );
    final ys = List<double>.generate(
      samples,
      (j) => yMin + (yMax - yMin) * j / (samples - 1),
    );

    final values = <double>[];
    for (final y in ys) {
      for (final x in xs) {
        final z = fn(x, y);
        if (z.isFinite) values.add(z);
      }
    }
    if (values.isEmpty) return null;
    final minZ = values.reduce(math.min);
    final maxZ = values.reduce(math.max);
    final range = (maxZ - minZ).abs() + 1e-6;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final bg = ui.Paint()..color = const ui.Color(0xFFFFFFFF);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      bg,
    );

    final cellW = width / samples;
    final cellH = height / samples;
    for (int j = 0; j < samples; j++) {
      for (int i = 0; i < samples; i++) {
        final x = xs[i];
        final y = ys[j];
        final z = fn(x, y);
        if (!z.isFinite) continue;
        final t = ((z - minZ) / range).clamp(0.0, 1.0);
        final color = _lerpColor(
          const ui.Color(0xFF1E88E5),
          const ui.Color(0xFFE53935),
          t,
        );
        final paint = ui.Paint()..color = color;
        canvas.drawRect(
          ui.Rect.fromLTWH(i * cellW, j * cellH, cellW + 0.5, cellH + 0.5),
          paint,
        );
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  static Future<Uint8List?> plotSurfaceSpherical({
    required String function,
    double thetaMin = 0,
    double thetaMax = math.pi,
    double phiMin = 0,
    double phiMax = 2 * math.pi,
    int width = 800,
    int height = 600,
    int samples = 140,
  }) async {
    final evaluator = ExpressionEvaluator();
    late double Function(double, double) fn;
    try {
      fn = evaluator.compile2(function);
    } catch (e) {
      debugPrint('Spherical plot error: $e');
      return null;
    }

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final bg = ui.Paint()..color = const ui.Color(0xFFFFFFFF);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      bg,
    );

    double minZ = double.infinity;
    double maxZ = -double.infinity;
    final points = <(double, double, double)>[];

    for (int i = 0; i < samples; i++) {
      final theta = thetaMin + (thetaMax - thetaMin) * i / (samples - 1);
      for (int j = 0; j < samples; j++) {
        final phi = phiMin + (phiMax - phiMin) * j / (samples - 1);
        final r = fn(theta, phi);
        if (!r.isFinite) continue;
        final x = r * math.sin(theta) * math.cos(phi);
        final y = r * math.sin(theta) * math.sin(phi);
        final z = r * math.cos(theta);
        points.add((x, y, z));
        minZ = math.min(minZ, z);
        maxZ = math.max(maxZ, z);
      }
    }
    if (points.isEmpty) return null;
    final rangeZ = (maxZ - minZ).abs() + 1e-6;

    double minX = points.first.$1, maxX = points.first.$1;
    double minY = points.first.$2, maxY = points.first.$2;
    for (final p in points) {
      minX = math.min(minX, p.$1);
      maxX = math.max(maxX, p.$1);
      minY = math.min(minY, p.$2);
      maxY = math.max(maxY, p.$2);
    }
    final padX = (maxX - minX).abs() * 0.1 + 1e-6;
    final padY = (maxY - minY).abs() * 0.1 + 1e-6;
    minX -= padX;
    maxX += padX;
    minY -= padY;
    maxY += padY;

    for (final p in points) {
      final px = (p.$1 - minX) / (maxX - minX) * width;
      final py = height - (p.$2 - minY) / (maxY - minY) * height;
      final t = ((p.$3 - minZ) / rangeZ).clamp(0.0, 1.0);
      final color = _lerpColor(
        const ui.Color(0xFF1565C0),
        const ui.Color(0xFFE53935),
        t,
      );
      final paint = ui.Paint()
        ..color = color
        ..style = ui.PaintingStyle.fill;
      canvas.drawRect(
        ui.Rect.fromCenter(center: ui.Offset(px, py), width: 3, height: 3),
        paint,
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  static Future<Uint8List?> plotVectorField2D({
    required String fx,
    required String fy,
    double xMin = -5,
    double xMax = 5,
    double yMin = -5,
    double yMax = 5,
    int width = 800,
    int height = 600,
    int grid = 20,
  }) async {
    final evalX = ExpressionEvaluator();
    final evalY = ExpressionEvaluator();
    late double Function(double, double) fxFn;
    late double Function(double, double) fyFn;
    try {
      fxFn = evalX.compile2(fx);
      fyFn = evalY.compile2(fy);
    } catch (e) {
      debugPrint('Vector field 2D error: $e');
      return null;
    }

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final bg = ui.Paint()..color = const ui.Color(0xFFFFFFFF);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      bg,
    );

    final axisPaint = ui.Paint()
      ..color = const ui.Color(0xFFAAAAAA)
      ..strokeWidth = 1;
    final originX = ((0 - xMin) / (xMax - xMin) * width).clamp(
      0.0,
      width.toDouble(),
    );
    final originY = (height - ((0 - yMin) / ((yMax) - (yMin)) * height)).clamp(
      0.0,
      height.toDouble(),
    );
    canvas.drawLine(
      ui.Offset(0, originY),
      ui.Offset(width.toDouble(), originY),
      axisPaint,
    );
    canvas.drawLine(
      ui.Offset(originX, 0),
      ui.Offset(originX, height.toDouble()),
      axisPaint,
    );

    double maxMag = 1e-6;
    final arrows = <(ui.Offset, ui.Offset, double)>[];
    for (int i = 0; i < grid; i++) {
      final x = xMin + (xMax - xMin) * i / (grid - 1);
      for (int j = 0; j < grid; j++) {
        final y = yMin + (yMax - yMin) * j / (grid - 1);
        final vx = fxFn(x, y);
        final vy = fyFn(x, y);
        if (!vx.isFinite || !vy.isFinite) continue;
        final mag = math.sqrt(vx * vx + vy * vy);
        maxMag = math.max(maxMag, mag);
        final px = (x - xMin) / (xMax - xMin) * width;
        final py = height - (y - yMin) / (yMax - yMin) * height;
        arrows.add((ui.Offset(px, py), ui.Offset(vx, vy), mag));
      }
    }

    for (final a in arrows) {
      final base = a.$1;
      final v = a.$2;
      final mag = a.$3;
      final norm = mag == 0 ? ui.Offset.zero : v / mag;
      final len = 12 + 24 * (mag / maxMag).clamp(0.0, 1.0);
      final tip = base + norm * len;
      final colorT = (mag / maxMag).clamp(0.0, 1.0);
      final color = _lerpColor(
        const ui.Color(0xFF1E88E5),
        const ui.Color(0xFFE53935),
        colorT,
      );
      final paint = ui.Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = ui.PaintingStyle.stroke;
      canvas.drawLine(base, tip, paint);

      final angle = math.atan2(norm.dy, norm.dx);
      final headLen = 6;
      final left =
          tip +
          ui.Offset(
            -headLen * math.cos(angle - math.pi / 6),
            -headLen * math.sin(angle - math.pi / 6),
          );
      final right =
          tip +
          ui.Offset(
            -headLen * math.cos(angle + math.pi / 6),
            -headLen * math.sin(angle + math.pi / 6),
          );
      canvas.drawLine(tip, left, paint);
      canvas.drawLine(tip, right, paint);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  static Future<Uint8List?> plotVectorField3D({
    required String fx,
    required String fy,
    required String fz,
    double xMin = -5,
    double xMax = 5,
    double yMin = -5,
    double yMax = 5,
    double z0 = 0,
    int width = 800,
    int height = 600,
    int grid = 18,
  }) async {
    final evalX = ExpressionEvaluator();
    final evalY = ExpressionEvaluator();
    final evalZ = ExpressionEvaluator();
    late double Function(double, double, double) fxFn;
    late double Function(double, double, double) fyFn;
    late double Function(double, double, double) fzFn;
    try {
      fxFn = evalX.compile3(fx);
      fyFn = evalY.compile3(fy);
      fzFn = evalZ.compile3(fz);
    } catch (e) {
      debugPrint('Vector field 3D error: $e');
      return null;
    }

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final bg = ui.Paint()..color = const ui.Color(0xFFFFFFFF);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      bg,
    );

    final axisPaint = ui.Paint()
      ..color = const ui.Color(0xFFAAAAAA)
      ..strokeWidth = 1;
    final originX = ((0 - xMin) / (xMax - xMin) * width).clamp(
      0.0,
      width.toDouble(),
    );
    final originY = (height - ((0 - yMin) / ((yMax) - (yMin)) * height)).clamp(
      0.0,
      height.toDouble(),
    );
    canvas.drawLine(
      ui.Offset(0, originY),
      ui.Offset(width.toDouble(), originY),
      axisPaint,
    );
    canvas.drawLine(
      ui.Offset(originX, 0),
      ui.Offset(originX, height.toDouble()),
      axisPaint,
    );

    double maxMag = 1e-6;
    final arrows = <(ui.Offset, ui.Offset, double)>[];
    for (int i = 0; i < grid; i++) {
      final x = xMin + (xMax - xMin) * i / (grid - 1);
      for (int j = 0; j < grid; j++) {
        final y = yMin + (yMax - yMin) * j / (grid - 1);
        final vx = fxFn(x, y, z0);
        final vy = fyFn(x, y, z0);
        final vz = fzFn(x, y, z0);
        if (!vx.isFinite || !vy.isFinite || !vz.isFinite) continue;
        final mag = math.sqrt(vx * vx + vy * vy + vz * vz);
        maxMag = math.max(maxMag, mag);
        final px = (x - xMin) / (xMax - xMin) * width;
        final py = height - (y - yMin) / (yMax - yMin) * height;

        final vzFactor = 1 + 0.5 * (vz / (maxMag + 1e-6));
        arrows.add((
          ui.Offset(px, py),
          ui.Offset(vx * vzFactor, vy * vzFactor),
          mag,
        ));
      }
    }

    for (final a in arrows) {
      final base = a.$1;
      final v = a.$2;
      final mag = a.$3;
      final normMag = mag == 0 ? 0.0 : mag / maxMag;
      final norm = v.distance == 0 ? ui.Offset.zero : v / v.distance;
      final len = 12 + 24 * normMag;
      final tip = base + norm * len;
      final color = _lerpColor(
        const ui.Color(0xFF1E88E5),
        const ui.Color(0xFFE53935),
        normMag,
      );
      final paint = ui.Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = ui.PaintingStyle.stroke;
      canvas.drawLine(base, tip, paint);
      final angle = math.atan2(norm.dy, norm.dx);
      final headLen = 6;
      final left =
          tip +
          ui.Offset(
            -headLen * math.cos(angle - math.pi / 6),
            -headLen * math.sin(angle - math.pi / 6),
          );
      final right =
          tip +
          ui.Offset(
            -headLen * math.cos(angle + math.pi / 6),
            -headLen * math.sin(angle + math.pi / 6),
          );
      canvas.drawLine(tip, left, paint);
      canvas.drawLine(tip, right, paint);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  static ui.Color _lerpColor(ui.Color a, ui.Color b, double t) {
    return ui.Color.fromARGB(
      255,
      (a.red + (b.red - a.red) * t).round(),
      (a.green + (b.green - a.green) * t).round(),
      (a.blue + (b.blue - a.blue) * t).round(),
    );
  }
}

class ExpressionEvaluator {
  late List<_Token> _tokens;
  int _pos = 0;
  double _currentX = 0;
  double _currentY = 0;
  double _currentZ = 0;
  bool _allowY = false;
  bool _allowZ = false;

  double Function(double) compile(String src) {
    _tokens = _Tokenizer(src).tokenize();
    _pos = 0;
    _allowY = false;
    _allowZ = false;
    final expr = _parseExpression();
    return (double x) {
      _currentX = x;
      return expr();
    };
  }

  double Function(double, double) compile2(String src) {
    _tokens = _Tokenizer(src).tokenize();
    _pos = 0;
    _allowY = true;
    _allowZ = false;
    final expr = _parseExpression();
    return (double x, double y) {
      _currentX = x;
      _currentY = y;
      return expr();
    };
  }

  double Function(double, double, double) compile3(String src) {
    _tokens = _Tokenizer(src).tokenize();
    _pos = 0;
    _allowY = true;
    _allowZ = true;
    final expr = _parseExpression();
    return (double x, double y, double z) {
      _currentX = x;
      _currentY = y;
      _currentZ = z;
      return expr();
    };
  }

  double Function() _parseExpression() {
    var node = _parseTerm();
    while (_match([_TokenType.plus, _TokenType.minus])) {
      final op = _previous();
      final right = _parseTerm();
      final left = node;
      node = () =>
          op.type == _TokenType.plus ? left() + right() : left() - right();
    }
    return node;
  }

  double Function() _parseTerm() {
    var node = _parseFactor();
    while (_match([_TokenType.star, _TokenType.slash])) {
      final op = _previous();
      final right = _parseFactor();
      final left = node;
      node = () =>
          op.type == _TokenType.star ? left() * right() : left() / right();
    }
    return node;
  }

  double Function() _parseFactor() {
    var node = _parseUnary();

    if (_match([_TokenType.caret])) {
      final right =
          _parseFactor();
      final left = node;
      node = () => math.pow(left(), right()).toDouble();
    }
    return node;
  }

  double Function() _parseUnary() {
    if (_match([_TokenType.minus])) {
      final expr = _parseUnary();
      return () => -expr();
    }
    return _parsePrimary();
  }

  double Function() _parsePrimary() {
    if (_match([_TokenType.number])) {
      final value = double.parse(_previous().lexeme);
      return () => value;
    }
    if (_match([_TokenType.identifier])) {
      final name = _previous().lexeme;
      if (_match([_TokenType.leftParen])) {

        if (name == 'perm' ||
            name == 'permutation' ||
            name == 'comb' ||
            name == 'combination') {
          final arg1 = _parseExpression();
          if (_match([_TokenType.comma])) {
            final arg2 = _parseExpression();
            _consume(_TokenType.rightParen);
            if (name == 'perm' || name == 'permutation') {
              return () {
                final n = arg1().round();
                final r = arg2().round();
                if (n < 0 || r < 0 || r > n)
                  throw FormatException('Invalid permutation parameters');
                double result = 1;
                for (int i = 0; i < r; i++) {
                  result *= (n - i);
                }
                return result;
              };
            } else {

              return () {
                final n = arg1().round();
                final r = arg2().round();
                if (n < 0 || r < 0 || r > n)
                  throw FormatException('Invalid combination parameters');

                final k = r > n - r ? n - r : r;
                double result = 1;
                for (int i = 0; i < k; i++) {
                  result = result * (n - i) / (i + 1);
                }
                return result;
              };
            }
          }

          _consume(_TokenType.rightParen);
          return () {
            final n = arg1().round();
            if (n < 0) throw FormatException('Factorial requires n >= 0');
            if (n > 170) throw FormatException('Factorial too large');
            double result = 1;
            for (int i = 2; i <= n; i++) {
              result *= i;
            }
            return result;
          };
        }
        final arg = _parseExpression();
        _consume(_TokenType.rightParen);
        switch (name) {
          case 'sin':
            return () => math.sin(arg());
          case 'cos':
            return () => math.cos(arg());
          case 'tan':
            return () => math.tan(arg());
          case 'asin':
            return () => math.asin(arg());
          case 'acos':
            return () => math.acos(arg());
          case 'atan':
            return () => math.atan(arg());
          case 'sinh':
            return () {
              final x = arg();
              return (math.exp(x) - math.exp(-x)) / 2;
            };
          case 'cosh':
            return () {
              final x = arg();
              return (math.exp(x) + math.exp(-x)) / 2;
            };
          case 'tanh':
            return () {
              final x = arg();
              final exp2x = math.exp(2 * x);
              return (exp2x - 1) / (exp2x + 1);
            };
          case 'asinh':
            return () {
              final x = arg();
              return math.log(x + math.sqrt(x * x + 1));
            };
          case 'acosh':
            return () {
              final x = arg();
              if (x < 1) throw FormatException('acosh requires x >= 1');
              return math.log(x + math.sqrt(x * x - 1));
            };
          case 'atanh':
            return () {
              final x = arg();
              if (x.abs() >= 1) throw FormatException('atanh requires |x| < 1');
              return 0.5 * math.log((1 + x) / (1 - x));
            };
          case 'factorial':
          case 'fact':
            return () {
              final n = arg().round();
              if (n < 0) throw FormatException('Factorial requires n >= 0');
              if (n > 170) throw FormatException('Factorial too large');
              double result = 1;
              for (int i = 2; i <= n; i++) {
                result *= i;
              }
              return result;
            };
          case 'exp':
            return () => math.exp(arg());
          case 'ln':
            return () => math.log(arg());
          case 'log':
            return () => math.log(arg());
          case 'sqrt':
            return () => math.sqrt(arg());
          case 'abs':
            return () => arg().abs();
          default:
            throw FormatException('Unknown function $name');
        }
      }
      if (name == 'x') return () => _currentX;
      if (name == 'y' && _allowY) return () => _currentY;
      if (name == 'z' && _allowZ) return () => _currentZ;
      if (name == 'pi' || name == 'π') return () => math.pi;
      if (name == 'e') return () => math.e;
      throw FormatException('Unknown identifier $name');
    }
    if (_match([_TokenType.leftParen])) {
      final expr = _parseExpression();
      _consume(_TokenType.rightParen);
      return expr;
    }
    throw FormatException('Unexpected token ${_peek().lexeme}');
  }

  bool _match(List<_TokenType> types) {
    for (final type in types) {
      if (_check(type)) {
        _advance();
        return true;
      }
    }
    return false;
  }

  bool _check(_TokenType type) => !_isAtEnd() && _peek().type == type;
  _Token _advance() => _isAtEnd() ? _peek() : _tokens[_pos++];
  bool _isAtEnd() => _peek().type == _TokenType.eof;
  _Token _peek() => _tokens[_pos];
  _Token _previous() => _tokens[_pos - 1];
  void _consume(_TokenType type) {
    if (_check(type)) {
      _advance();
      return;
    }
    throw FormatException('Expected ${type.name}');
  }
}

class _Tokenizer {
  _Tokenizer(this.src);
  final String src;
  final List<_Token> tokens = [];
  int start = 0;
  int current = 0;

  List<_Token> tokenize() {
    while (!_isAtEnd()) {
      start = current;
      _scanToken();
    }
    tokens.add(_Token(_TokenType.eof, ''));
    return tokens;
  }

  void _scanToken() {
    final c = _advance();
    switch (c) {
      case ' ':
      case '\t':
      case '\r':
      case '\n':
        break;
      case '+':
        _add(_TokenType.plus);
        break;
      case '-':
        _add(_TokenType.minus);
        break;
      case '*':
        if (_peek() == '*') {
          _advance();
          _add(_TokenType.caret);
        } else {
          _add(_TokenType.star);
        }
        break;
      case '/':
        _add(_TokenType.slash);
        break;
      case '^':
        _add(_TokenType.caret);
        break;
      case '(':
        _add(_TokenType.leftParen);
        break;
      case ')':
        _add(_TokenType.rightParen);
        break;
      case ',':
        _add(_TokenType.comma);
        break;
      default:
        if (_isDigit(c) || (c == '.' && _isDigit(_peek()))) {
          _number();
        } else if (_isAlpha(c)) {
          _identifier();
        } else {
          throw FormatException('Unexpected character $c');
        }
    }
  }

  void _number() {
    while (_isDigit(_peek())) _advance();
    if (_peek() == '.' && _isDigit(_peekNext())) {
      _advance();
      while (_isDigit(_peek())) _advance();
    }
    _add(_TokenType.number);
  }

  void _identifier() {
    while (_isAlphaNumeric(_peek())) _advance();
    _add(_TokenType.identifier);
  }

  bool _isDigit(String c) {
    final code = c.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }

  bool _isAlpha(String c) =>
      (c.codeUnitAt(0) >= 65 && c.codeUnitAt(0) <= 90) ||
      (c.codeUnitAt(0) >= 97 && c.codeUnitAt(0) <= 122) ||
      c == '_';
  bool _isAlphaNumeric(String c) => _isAlpha(c) || _isDigit(c);

  String _advance() => src[current++];
  String _peek() => _isAtEnd() ? '\u0000' : src[current];
  String _peekNext() =>
      (current + 1 >= src.length) ? '\u0000' : src[current + 1];
  bool _isAtEnd() => current >= src.length;

  void _add(_TokenType type) {
    tokens.add(_Token(type, src.substring(start, current)));
  }
}

class _Token {
  _Token(this.type, this.lexeme);
  final _TokenType type;
  final String lexeme;
}

enum _TokenType {
  number,
  identifier,
  plus,
  minus,
  star,
  slash,
  caret,
  leftParen,
  rightParen,
  comma,
  eof,
}
