// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:saber/services/math_engine/math_engine.dart';
import 'package:vector_math/vector_math_64.dart' as vmath;

typedef _Complex = Complex;

class PlotLine3D {
  final String expression;
  final Color color;
  final double tMin;
  final double tMax;
  final int durationMs;

  const PlotLine3D({
    required this.expression,
    required this.color,
    this.tMin = 0,
    this.tMax = 0,
    this.durationMs = 0,
  });

  bool get hasAnimation => tMax > tMin && durationMs > 0;
}

class Plot3DWidget extends StatefulWidget {
  final List<PlotLine3D> functions;
  final double yaw;
  final double pitch;
  final double zoom;
  final double centerX;
  final double centerY;
  final double centerZ;
  final bool isDarkMode;
  final bool showLabels;
  final bool isComplex;
  final bool autoRotate;

  const Plot3DWidget({
    super.key,
    required this.functions,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.centerX,
    required this.centerY,
    required this.centerZ,
    required this.isDarkMode,
    required this.showLabels,
    required this.isComplex,
    this.autoRotate = false,
  });

  @override
  State<Plot3DWidget> createState() => _Plot3DWidgetState();
}

class _Plot3DWidgetState extends State<Plot3DWidget>
    with SingleTickerProviderStateMixin {
  final List<_ProcessedMesh> _meshes = [];
  bool _needsRecalc = true;

  late final Ticker _ticker;
  double _autoRotationOffset = 0.0;
  bool _isInteracting = false;
  double _animationClockMs = 0.0;
  int _lastTickMs = 0;

  final ComplexParser _parser = ComplexParser();

  static const int _gridSteps = 120;
  static const int _gridStepsComplexBase =
      160;
  static const int _gridStepsComplexMax =
      320;
  static const double _zClipLimit =
      8.0;

  int _effectiveGridSteps() => _gridStepsForZoom(widget.zoom);

  int _gridStepsForZoom(double z) {
    if (!widget.isComplex) {
      if (z < 0.6) return 70;
      if (z < 0.9) return 90;
      if (z > 1.8) return 140;
      return _gridSteps;
    }
    if (z < 0.45) return 90;
    if (z < 0.7) return 120;
    if (z < 1.0) return _gridStepsComplexBase;
    if (z < 1.4) return 200;
    if (z < 1.9) return 260;
    return _gridStepsComplexMax;
  }

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

      final hasAnimatedFunctions = widget.functions.any((f) => f.hasAnimation);
      final shouldAnimateFunction =
          hasAnimatedFunctions && (_isInteracting == false);

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
  void didUpdateWidget(covariant Plot3DWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.functions != oldWidget.functions ||
        widget.isComplex != oldWidget.isComplex) {
      _needsRecalc = true;
    }

    if (widget.isComplex &&
        _gridStepsForZoom(widget.zoom) != _gridStepsForZoom(oldWidget.zoom)) {
      _needsRecalc = true;
    }
  }

  vmath.Vector3 _calculateNormal(
    String expr,
    double x,
    double y,
    double z,
    Map<String, _Complex> vars,
  ) {
    const double eps = 0.001;
    vmath.Vector3 normal = vmath.Vector3(0, 0, 1);

    try {

      double getZ(double tx, double ty) {
        vars['x'] = _Complex(tx, 0);
        vars['y'] = _Complex(ty, 0);
        if (widget.isComplex) {
          vars['z'] = _Complex(tx, ty);
          return _parser.evaluate(expr, variables: vars).abs();
        } else {

          return _parser.evaluate(expr, variables: vars).real;
        }
      }

      double z1 = getZ(x + eps, y);
      double z2 = getZ(x - eps, y);
      double dx = (z1 - z2) / (2 * eps);

      double z3 = getZ(x, y + eps);
      double z4 = getZ(x, y - eps);
      double dy = (z3 - z4) / (2 * eps);

      normal = vmath.Vector3(-dx, -dy, 1.0)..normalize();
    } catch (_) {}

    return normal;
  }

  _Point3D _findBoundary(
    _Point3D valid,
    _Point3D invalid,
    String expr,
    Map<String, _Complex> vars,
  ) {
    double minT = 0.0;
    double maxT = 1.0;

    for (int i = 0; i < 14; i++) {
      double t = (minT + maxT) / 2;
      double ix = valid.x + (invalid.x - valid.x) * t;
      double iy = valid.y + (invalid.y - valid.y) * t;

      vars['x'] = _Complex(ix, 0);
      vars['y'] = _Complex(iy, 0);
      vars['z'] = _Complex(ix, iy);

      bool isValid = false;
      try {
        final res = _parser.evaluate(expr, variables: vars);
        if (widget.isComplex) {
          isValid = res.real.isFinite && res.imag.isFinite;
        } else {
          isValid = res.real.isFinite && res.imag.abs() < 1e-4;

          if (isValid) isValid = res.real.abs() <= _zClipLimit;
        }
      } catch (_) {}

      if (isValid)
        minT = t;
      else
        maxT = t;
    }

    double t = minT;
    double finalX = valid.x + (invalid.x - valid.x) * t;
    double finalY = valid.y + (invalid.y - valid.y) * t;

    vars['x'] = _Complex(finalX, 0);
    vars['y'] = _Complex(finalY, 0);
    vars['z'] = _Complex(finalX, finalY);

    final res = _parser.evaluate(expr, variables: vars);

    double zVal;
    double colorParam;

    if (widget.isComplex) {
      zVal = res.abs();
      if (zVal > _zClipLimit) zVal = _zClipLimit;
      colorParam = res.arg();
    } else {
      zVal = res.real;
      if (zVal > _zClipLimit) zVal = _zClipLimit;
      if (zVal < -_zClipLimit) zVal = -_zClipLimit;
      colorParam = res.imag;
    }

    final normal = _calculateNormal(expr, finalX, finalY, zVal, vars);
    return _Point3D(finalX, finalY, zVal, colorParam, normal);
  }

  void _calculateRawData() {
    _meshes.clear();

    const double range = 15.0;
    final int gridSteps = _effectiveGridSteps();
    final double stepSize = (range * 2) / gridSteps;

    final Map<String, _Complex> vars = {
      'x': const _Complex(0),
      'y': const _Complex(0),
      'z': const _Complex(0),
      't': const _Complex(0),
    };

    for (final func in widget.functions) {
      if (func.expression.trim().isEmpty) continue;
      final tValue = func.hasAnimation
          ? _computeAnimatedT(func.tMin, func.tMax, func.durationMs)
          : 0.0;
      vars['t'] = _Complex(tValue, 0);
      final String expr = func.expression
          .replaceAll('×', '*')
          .replaceAll('^', '^');
      final List<_Triangle> triangles = [];

      final List<List<_Point3D?>> grid = List.generate(
        gridSteps + 1,
        (_) => List.filled(gridSteps + 1, null),
      );

      for (int i = 0; i <= gridSteps; i++) {
        final double x = -range + (i * stepSize);
        for (int j = 0; j <= gridSteps; j++) {
          final double y = -range + (j * stepSize);

          vars['x'] = _Complex(x, 0);
          vars['y'] = _Complex(y, 0);
          vars['z'] = _Complex(x, y);

          try {
            final result = _parser.evaluate(expr, variables: vars);
            double zVal;
            double colorParam;
            bool isValid = true;

            if (widget.isComplex) {

              if (!result.real.isFinite || !result.imag.isFinite) {
                isValid = false;
                zVal = 0;
                colorParam = 0;
              } else {
                zVal = result.abs();
                colorParam = result.arg();

                if (zVal > _zClipLimit) zVal = _zClipLimit;
              }
            } else {

              zVal = result.real;
              colorParam = result.imag;

              if (result.imag.abs() > 1e-4 || !result.real.isFinite) {
                isValid = false;
              }

              if (isValid && zVal.abs() > _zClipLimit) {
                isValid = false;
              }
            }

            if (isValid) {
              final normal = _calculateNormal(expr, x, y, zVal, vars);
              grid[i][j] = _Point3D(x, y, zVal, colorParam, normal);
            }
          } catch (_) {}
        }
      }

      final Map<String, _Point3D> boundaryCache = {};
      final dummyNorm = vmath.Vector3(0, 0, 1);

      for (int i = 0; i < gridSteps; i++) {
        for (int j = 0; j < gridSteps; j++) {
          final p_bl = grid[i][j];
          final p_br = grid[i + 1][j];
          final p_tr = grid[i + 1][j + 1];
          final p_tl = grid[i][j + 1];

          final double x_l = -range + (i * stepSize);
          final double x_r = x_l + stepSize;
          final double y_b = -range + (j * stepSize);
          final double y_t = y_b + stepSize;

          int mask = 0;
          if (p_bl != null) mask |= 1;
          if (p_br != null) mask |= 2;
          if (p_tr != null) mask |= 4;
          if (p_tl != null) mask |= 8;

          if (mask == 0) continue;

          void addTri(_Point3D a, _Point3D b, _Point3D c) {
            triangles.add(_Triangle(a, b, c));
          }

          if (mask == 15) {
            addTri(p_bl!, p_br!, p_tr!);
            addTri(p_bl, p_tr, p_tl!);
            continue;
          }

          _Point3D edge(String side) {
            final String key = side == 'b'
                ? 'b_${i}_$j'
                : side == 'r'
                ? 'r_${i + 1}_$j'
                : side == 't'
                ? 'b_${i}_${j + 1}'
                : 'l_${i}_$j';
            return boundaryCache.putIfAbsent(key, () {
              _Point3D v, inv;
              if (side == 'b') {
                v = (p_bl != null) ? p_bl : p_br!;
                inv = (p_bl != null)
                    ? _Point3D(x_r, y_b, 0, 0, dummyNorm)
                    : _Point3D(x_l, y_b, 0, 0, dummyNorm);
              } else if (side == 'r') {
                v = (p_br != null) ? p_br : p_tr!;
                inv = (p_br != null)
                    ? _Point3D(x_r, y_t, 0, 0, dummyNorm)
                    : _Point3D(x_r, y_b, 0, 0, dummyNorm);
              } else if (side == 't') {
                v = (p_tr != null) ? p_tr : p_tl!;
                inv = (p_tr != null)
                    ? _Point3D(x_l, y_t, 0, 0, dummyNorm)
                    : _Point3D(x_r, y_t, 0, 0, dummyNorm);
              } else {
                v = (p_tl != null) ? p_tl : p_bl!;
                inv = (p_tl != null)
                    ? _Point3D(x_l, y_b, 0, 0, dummyNorm)
                    : _Point3D(x_l, y_t, 0, 0, dummyNorm);
              }
              return _findBoundary(v, inv, expr, vars);
            });
          }

          switch (mask) {
            case 1:
              addTri(p_bl!, edge('b'), edge('l'));
              break;
            case 2:
              addTri(p_br!, edge('r'), edge('b'));
              break;
            case 4:
              addTri(p_tr!, edge('t'), edge('r'));
              break;
            case 8:
              addTri(p_tl!, edge('l'), edge('t'));
              break;
            case 3:
              addTri(p_bl!, p_br!, edge('r'));
              addTri(p_bl, edge('r'), edge('l'));
              break;
            case 6:
              addTri(p_br!, p_tr!, edge('t'));
              addTri(p_br, edge('t'), edge('b'));
              break;
            case 9:
              addTri(p_bl!, edge('b'), edge('t'));
              addTri(p_bl, edge('t'), p_tl!);
              break;
            case 12:
              addTri(p_tr!, p_tl!, edge('l'));
              addTri(p_tr, edge('l'), edge('r'));
              break;
            case 7:
              addTri(p_bl!, p_br!, p_tr!);
              addTri(p_bl, p_tr, edge('t'));
              addTri(p_bl, edge('t'), edge('l'));
              break;
            case 11:
              addTri(p_bl!, p_br!, edge('r'));
              addTri(p_bl, edge('r'), edge('t'));
              addTri(p_bl, edge('t'), p_tl!);
              break;
            case 13:
              addTri(p_tl!, p_bl!, edge('b'));
              addTri(p_tl, edge('b'), edge('r'));
              addTri(p_tl, edge('r'), p_tr!);
              break;
            case 14:
              addTri(p_tr!, p_tl!, edge('l'));
              addTri(p_tr, edge('l'), edge('b'));
              addTri(p_tr, edge('b'), p_br!);
              break;
            case 5:
              addTri(p_bl!, edge('b'), edge('l'));
              addTri(p_tr!, edge('t'), edge('r'));
              break;
            case 10:
              addTri(p_br!, edge('r'), edge('b'));
              addTri(p_tl!, edge('l'), edge('t'));
              break;
          }
        }
      }

      _meshes.add(_ProcessedMesh(triangles: triangles, color: func.color));
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
      builder: (context, constraints) {
        if (_needsRecalc) {
          _calculateRawData();
        }

        return Listener(
          onPointerDown: (_) => _isInteracting = true,
          onPointerUp: (_) => _isInteracting = false,
          onPointerCancel: (_) => _isInteracting = false,
          child: CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _VertexMeshPainter(
              meshes: _meshes,
              yaw: widget.yaw + _autoRotationOffset,
              pitch: widget.pitch,
              zoom: widget.zoom,
              centerX: widget.centerX,
              centerY: widget.centerY,
              centerZ: widget.centerZ,
              isDarkMode: widget.isDarkMode,
              showLabels: widget.showLabels,
              isComplex: widget.isComplex,
            ),
          ),
        );
      },
    );
  }
}

class _Point3D {
  final double x, y, z;
  final double colorParam;
  final vmath.Vector3 normal;
  const _Point3D(this.x, this.y, this.z, this.colorParam, this.normal);
}

class _Triangle {
  final _Point3D p1, p2, p3;
  const _Triangle(this.p1, this.p2, this.p3);
}

class _ProcessedMesh {
  final List<_Triangle> triangles;
  final Color color;
  const _ProcessedMesh({required this.triangles, required this.color});
}

class _SortableTri {
  int index;
  double depth;
  _SortableTri(this.index, this.depth);
}

class _VertexMeshPainter extends CustomPainter {
  final List<_ProcessedMesh> meshes;
  final double yaw, pitch, zoom, centerX, centerY, centerZ;
  final bool isDarkMode, showLabels, isComplex;

  static Float32List _vertexBuffer = Float32List(0);
  static Int32List _colorBuffer = Int32List(0);
  static Float32List _sortedVertexBuffer = Float32List(0);
  static Int32List _sortedColorBuffer = Int32List(0);
  static List<_SortableTri> _sortBuffer = [];

  _VertexMeshPainter({
    required this.meshes,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.centerX,
    required this.centerY,
    required this.centerZ,
    required this.isDarkMode,
    required this.showLabels,
    required this.isComplex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final scale = 15.0 * zoom;

    final radYaw = vmath.radians(yaw);
    final radPitch = vmath.radians(pitch);

    final cz = math.cos(radYaw);
    final sz = math.sin(radYaw);
    final cx_rot = math.cos(radPitch - math.pi / 2);
    final sx_rot = math.sin(radPitch - math.pi / 2);

    final r00 = cz;
    final r01 = -sz;
    final r02 = 0.0;
    final r10 = cx_rot * sz;
    final r11 = cx_rot * cz;
    final r12 = -sx_rot;
    final r20 = sx_rot * sz;
    final r21 = sx_rot * cz;
    final r22 = cx_rot;

    final double lLen = math.sqrt(1.0 * 1.0 + 1.0 * 1.0 + 0.8 * 0.8);
    final double lx = 1.0 / lLen;
    final double ly = -1.0 / lLen;
    final double lz = 0.8 / lLen;

    int triCount = 0;
    for (final mesh in meshes) {
      triCount += mesh.triangles.length;
    }
    final vertexCount = triCount * 6;
    final colorCount = triCount * 3;

    if (_vertexBuffer.length != vertexCount) {
      _vertexBuffer = Float32List(vertexCount);
    }
    if (_colorBuffer.length != colorCount) {
      _colorBuffer = Int32List(colorCount);
    }
    if (_sortedVertexBuffer.length != vertexCount) {
      _sortedVertexBuffer = Float32List(vertexCount);
    }
    if (_sortedColorBuffer.length != colorCount) {
      _sortedColorBuffer = Int32List(colorCount);
    }
    if (_sortBuffer.length < triCount) {
      _sortBuffer = List.generate(triCount, (_) => _SortableTri(0, 0.0));
    }
    _sortBuffer.length = triCount;

    int triIndex = 0;
    int vertexIndex = 0;
    int colorIndex = 0;

    for (final mesh in meshes) {
      final HSLColor baseHsl = HSLColor.fromColor(mesh.color);

      for (final tri in mesh.triangles) {

        double x1 = tri.p1.x - centerX;
        double y1 = tri.p1.y - centerY;
        double z1 = tri.p1.z - centerZ;
        double rx1 = r00 * x1 + r01 * y1 + r02 * z1;
        double ry1 = r10 * x1 + r11 * y1 + r12 * z1;
        double rz1 = r20 * x1 + r21 * y1 + r22 * z1;

        double x2 = tri.p2.x - centerX;
        double y2 = tri.p2.y - centerY;
        double z2 = tri.p2.z - centerZ;
        double rx2 = r00 * x2 + r01 * y2 + r02 * z2;
        double ry2 = r10 * x2 + r11 * y2 + r12 * z2;
        double rz2 = r20 * x2 + r21 * y2 + r22 * z2;

        double x3 = tri.p3.x - centerX;
        double y3 = tri.p3.y - centerY;
        double z3 = tri.p3.z - centerZ;
        double rx3 = r00 * x3 + r01 * y3 + r02 * z3;
        double ry3 = r10 * x3 + r11 * y3 + r12 * z3;
        double rz3 = r20 * x3 + r21 * y3 + r22 * z3;

        int getColor(double nx, double ny, double nz, double param) {
          double rnx = r00 * nx + r01 * ny + r02 * nz;
          double rny = r10 * nx + r11 * ny + r12 * nz;
          double rnz = r20 * nx + r21 * ny + r22 * nz;

          double dot = (rnx * lx + rny * ly + rnz * lz).abs();
          double intensity = math.max(0.05, dot);
          double lightness = 0.2 + (0.7 * intensity);

          if (isComplex) {

            double hue = ((param * 180 / math.pi) + 360) % 360;

            return HSLColor.fromAHSL(
              1.0,
              hue,
              0.8,
              lightness.clamp(0.15, 0.85),
            ).toColor().toARGB32();
          } else {

            return HSLColor.fromAHSL(
              1.0,
              baseHsl.hue,
              baseHsl.saturation,
              lightness.clamp(0.15, 0.85),
            ).toColor().toARGB32();
          }
        }

        _colorBuffer[colorIndex++] = getColor(
          tri.p1.normal.x,
          tri.p1.normal.y,
          tri.p1.normal.z,
          tri.p1.colorParam,
        );
        _colorBuffer[colorIndex++] = getColor(
          tri.p2.normal.x,
          tri.p2.normal.y,
          tri.p2.normal.z,
          tri.p2.colorParam,
        );
        _colorBuffer[colorIndex++] = getColor(
          tri.p3.normal.x,
          tri.p3.normal.y,
          tri.p3.normal.z,
          tri.p3.colorParam,
        );

        _vertexBuffer[vertexIndex++] = cx + rx1 * scale;
        _vertexBuffer[vertexIndex++] = cy - ry1 * scale;
        _vertexBuffer[vertexIndex++] = cx + rx2 * scale;
        _vertexBuffer[vertexIndex++] = cy - ry2 * scale;
        _vertexBuffer[vertexIndex++] = cx + rx3 * scale;
        _vertexBuffer[vertexIndex++] = cy - ry3 * scale;

        final sortItem = _sortBuffer[triIndex];
        sortItem.index = triIndex;
        sortItem.depth = (rz1 + rz2 + rz3) / 3;
        triIndex++;
      }
    }

    _sortBuffer.sort((a, b) => a.depth.compareTo(b.depth));

    for (int i = 0; i < triCount; i++) {
      final int oldIdx = _sortBuffer[i].index * 6;
      final int oldColIdx = _sortBuffer[i].index * 3;
      final int newIdx = i * 6;
      final int newColIdx = i * 3;

      _sortedVertexBuffer[newIdx] = _vertexBuffer[oldIdx];
      _sortedVertexBuffer[newIdx + 1] = _vertexBuffer[oldIdx + 1];
      _sortedVertexBuffer[newIdx + 2] = _vertexBuffer[oldIdx + 2];
      _sortedVertexBuffer[newIdx + 3] = _vertexBuffer[oldIdx + 3];
      _sortedVertexBuffer[newIdx + 4] = _vertexBuffer[oldIdx + 4];
      _sortedVertexBuffer[newIdx + 5] = _vertexBuffer[oldIdx + 5];

      _sortedColorBuffer[newColIdx] = _colorBuffer[oldColIdx];
      _sortedColorBuffer[newColIdx + 1] = _colorBuffer[oldColIdx + 1];
      _sortedColorBuffer[newColIdx + 2] = _colorBuffer[oldColIdx + 2];
    }

    if (showLabels) {
      _drawGridAndLabels(
        canvas,
        size,
        r00,
        r01,
        r02,
        r10,
        r11,
        r12,
        r20,
        r21,
        r22,
        scale,
        cx,
        cy,
      );
    }

    final meshPaint = Paint()..style = PaintingStyle.fill;
    final vertObject = ui.Vertices.raw(
      ui.VertexMode.triangles,
      _sortedVertexBuffer,
      colors: _sortedColorBuffer,
    );
    canvas.drawVertices(vertObject, BlendMode.dst, meshPaint);
  }

  void _drawGridAndLabels(
    Canvas canvas,
    Size size,
    double r00,
    double r01,
    double r02,
    double r10,
    double r11,
    double r12,
    double r20,
    double r21,
    double r22,
    double scale,
    double cx,
    double cy,
  ) {
    final axisPaint = Paint()
      ..color = (isDarkMode ? Colors.white30 : Colors.black26).withValues(
        alpha: 0.3,
      )
      ..strokeWidth = 1;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final labelStyle = TextStyle(
      color: isDarkMode ? Colors.white70 : Colors.black87,
      fontSize: 10,
      backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
    );

    Offset proj(double x, double y, double z) {
      final double rx =
          r00 * (x - centerX) + r01 * (y - centerY) + r02 * (z - centerZ);
      final double ry =
          r10 * (x - centerX) + r11 * (y - centerY) + r12 * (z - centerZ);
      return Offset(cx + rx * scale, cy - ry * scale);
    }

    final double tickStep = MathGrid.calculateStepSize(80.0, scale);
    final double L = 1000.0;
    canvas.drawLine(
      proj(-L, 0, 0),
      proj(L, 0, 0),
      axisPaint..color = Colors.red.withValues(alpha: 0.5),
    );
    canvas.drawLine(
      proj(0, -L, 0),
      proj(0, L, 0),
      axisPaint..color = Colors.green.withValues(alpha: 0.5),
    );
    canvas.drawLine(
      proj(0, 0, -L),
      proj(0, 0, L),
      axisPaint..color = Colors.blue.withValues(alpha: 0.5),
    );

    final lenX = math.sqrt(r00 * r00 + r10 * r10);
    final lenY = math.sqrt(r01 * r01 + r11 * r11);
    final lenZ = math.sqrt(r02 * r02 + r12 * r12);
    final ax = lenX > 1e-6 ? Offset(r00 / lenX, -r10 / lenX) : Offset.zero;
    final ay = lenY > 1e-6 ? Offset(r01 / lenY, -r11 / lenY) : Offset.zero;
    final az = lenZ > 1e-6 ? Offset(r02 / lenZ, -r12 / lenZ) : Offset.zero;
    const labelOffset = 8.0;

    const int ticks = 6;
    void drawTicks(String axis) {
      final unit = axis == 'x' ? ax : (axis == 'y' ? ay : az);

      double centerVal = axis == 'x'
          ? centerX
          : (axis == 'y' ? centerY : centerZ);
      double start = (centerVal / tickStep).floor() * tickStep;

      for (int i = -ticks; i <= ticks; i++) {
        final double val = start + (i * tickStep);
        if (val.abs() < 1e-5) continue;

        double wx = 0, wy = 0, wz = 0;
        if (axis == 'x') {
          wx = val;
        } else if (axis == 'y') {
          wy = val;
        } else {
          wz = val;
        }

        final p = proj(wx, wy, wz);
        if (p.dx < -50 ||
            p.dx > size.width + 50 ||
            p.dy < -50 ||
            p.dy > size.height + 50) {
          continue;
        }
        canvas.drawCircle(
          p,
          2,
          axisPaint..color = (isDarkMode ? Colors.white : Colors.black),
        );
        textPainter.text = TextSpan(
          text: MathFormatter.formatAxisLabel(val, precision: 2),
          style: labelStyle,
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
    _drawGizmo(canvas, size, r00, r01, r02, r10, r11, r12);
  }

  void _drawGizmo(
    Canvas canvas,
    Size size,
    double r00,
    double r01,
    double r02,
    double r10,
    double r11,
    double r12,
  ) {
    final paint = Paint()..strokeWidth = 2.0;
    final origin = Offset(35, size.height - 35);
    const len = 20.0;
    const labelOffset = 10.0;

    Offset proj(double x, double y, double z) {
      final rx = r00 * x + r01 * y + r02 * z;
      final ry = r10 * x + r11 * y + r12 * z;
      return origin + Offset(rx, -ry);
    }

    canvas.drawLine(origin, proj(len, 0, 0), paint..color = Colors.red);
    canvas.drawLine(origin, proj(0, len, 0), paint..color = Colors.green);
    canvas.drawLine(origin, proj(0, 0, len), paint..color = Colors.blue);

    final tp = TextPainter(textDirection: TextDirection.ltr);
    void drawLabel(
      String text,
      Offset axisTip,
      double ux,
      double uy,
      Color color,
    ) {
      final labelPos = axisTip + Offset(ux * labelOffset, uy * labelOffset);
      tp.text = TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 9,
        ),
      );
      tp.layout();
      tp.paint(canvas, labelPos);
    }

    final lx = math.sqrt(r00 * r00 + r10 * r10);
    final ly = math.sqrt(r01 * r01 + r11 * r11);
    final lz = math.sqrt(r02 * r02 + r12 * r12);
    final ux = lx > 1e-6 ? Offset(r00 / lx, -r10 / lx) : Offset.zero;
    final uy = ly > 1e-6 ? Offset(r01 / ly, -r11 / ly) : Offset.zero;
    final uz = lz > 1e-6 ? Offset(r02 / lz, -r12 / lz) : Offset.zero;
    drawLabel('X', proj(len, 0, 0), ux.dx, ux.dy, Colors.red);
    drawLabel('Y', proj(0, len, 0), uy.dx, uy.dy, Colors.green);
    drawLabel('Z', proj(0, 0, len), uz.dx, uz.dy, Colors.blue);
  }

  @override
  bool shouldRepaint(covariant _VertexMeshPainter old) =>
      old.meshes != meshes ||
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.zoom != zoom ||
      old.centerX != centerX ||
      old.centerY != centerY ||
      old.centerZ != centerZ ||
      old.isDarkMode != isDarkMode ||
      old.showLabels != showLabels ||
      old.isComplex != isComplex;
}

