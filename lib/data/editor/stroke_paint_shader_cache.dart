// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:saber/data/editor/stroke_paint.dart';

/// Reuses [ImageShader] / gradient shaders across frames and strokes.
///
/// Creating a new shader every [Canvas.drawPath] is a major cost for Advanced
/// Pen image/SVG/gradient fills while writing.
class StrokePaintShaderCache {
  StrokePaintShaderCache._();
  static final StrokePaintShaderCache instance = StrokePaintShaderCache._();

  static const int _maxGradientEntries = 48;

  final Map<String, ui.ImageShader> _imageShaders = {};
  final Map<String, ui.Shader> _gradients = {};
  final List<String> _gradientLru = [];

  ui.ImageShader imageShader(ui.Image texture, double imageScale) {
    final s = imageScale.clamp(0.02, 8.0);
    final key =
        '${identityHashCode(texture)}:${(s * 1000).round()}';
    final hit = _imageShaders[key];
    if (hit != null) return hit;
    final shader = ui.ImageShader(
      texture,
      TileMode.repeated,
      TileMode.repeated,
      Matrix4.diagonal3Values(s, s, 1).storage,
    );
    _imageShaders[key] = shader;
    return shader;
  }

  ui.Shader? linearGradient(StrokePaint paint, Rect bounds) {
    final colors = paint.stops.map((s) => s.color).toList();
    final offsets = paint.stops.map((s) => s.offset.clamp(0.0, 1.0)).toList();
    if (colors.length < 2) return null;
    final q = _quantizeBounds(bounds);
    final key = 'L:${paint.gradientStart.dx.toStringAsFixed(3)},'
        '${paint.gradientStart.dy.toStringAsFixed(3)}>'
        '${paint.gradientEnd.dx.toStringAsFixed(3)},'
        '${paint.gradientEnd.dy.toStringAsFixed(3)}|'
        '${_stopsKey(colors, offsets)}|$q';
    final hit = _gradients[key];
    if (hit != null) {
      _touchGradient(key);
      return hit;
    }
    final start = Offset(
      bounds.left + paint.gradientStart.dx * bounds.width,
      bounds.top + paint.gradientStart.dy * bounds.height,
    );
    final end = Offset(
      bounds.left + paint.gradientEnd.dx * bounds.width,
      bounds.top + paint.gradientEnd.dy * bounds.height,
    );
    final shader = ui.Gradient.linear(start, end, colors, offsets);
    _putGradient(key, shader);
    return shader;
  }

  ui.Shader? radialGradient(StrokePaint paint, Rect bounds) {
    final colors = paint.stops.map((s) => s.color).toList();
    final offsets = paint.stops.map((s) => s.offset.clamp(0.0, 1.0)).toList();
    if (colors.length < 2) return null;
    final q = _quantizeBounds(bounds);
    final key = 'R:${paint.gradientCenter.dx.toStringAsFixed(3)},'
        '${paint.gradientCenter.dy.toStringAsFixed(3)},'
        '${paint.gradientRadius.toStringAsFixed(3)}|'
        '${_stopsKey(colors, offsets)}|$q';
    final hit = _gradients[key];
    if (hit != null) {
      _touchGradient(key);
      return hit;
    }
    final diag =
        math.sqrt(
          bounds.width * bounds.width + bounds.height * bounds.height,
        ) /
        2;
    final shader = ui.Gradient.radial(
      Offset(
        bounds.left + paint.gradientCenter.dx * bounds.width,
        bounds.top + paint.gradientCenter.dy * bounds.height,
      ),
      (paint.gradientRadius.clamp(0.01, 2.0)) * diag,
      colors,
      offsets,
    );
    _putGradient(key, shader);
    return shader;
  }

  void clear() {
    _imageShaders.clear();
    _gradients.clear();
    _gradientLru.clear();
  }

  void _putGradient(String key, ui.Shader shader) {
    while (_gradientLru.length >= _maxGradientEntries) {
      final evict = _gradientLru.removeAt(0);
      _gradients.remove(evict);
    }
    _gradients[key] = shader;
    _gradientLru.add(key);
  }

  void _touchGradient(String key) {
    _gradientLru.remove(key);
    _gradientLru.add(key);
  }

  static String _quantizeBounds(Rect bounds) {
    // ~1px buckets keep shader reuse high while strokes grow slowly.
    return '${bounds.left.round()},${bounds.top.round()},'
        '${bounds.width.round()},${bounds.height.round()}';
  }

  static String _stopsKey(List<Color> colors, List<double> offsets) {
    final b = StringBuffer();
    for (var i = 0; i < colors.length; i++) {
      if (i > 0) b.write(';');
      b
        ..write(colors[i].toARGB32().toRadixString(16))
        ..write('@')
        ..write(offsets[i].toStringAsFixed(3));
    }
    return b.toString();
  }
}
