// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ditredi/ditredi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:saber/services/math_engine/math_engine.dart';
import 'package:vector_math/vector_math_64.dart' as vmath;

typedef _Complex = Complex;

enum CoordSystem3D { cartesian, cylindrical, spherical }

class PlotLine3D {
  final String expression;
  final Color color;
  final double tMin;
  final double tMax;
  final int durationMs;
  final double? xMin, xMax, yMin, yMax, zMin, zMax;
  final CoordSystem3D coordSystem;

  const PlotLine3D({
    required this.expression,
    required this.color,
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
  final CoordSystem3D gridCoordSystem;

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
    this.gridCoordSystem = CoordSystem3D.cartesian,
  });

  @override
  State<Plot3DWidget> createState() => _Plot3DWidgetState();
}

class _Plot3DWidgetState extends State<Plot3DWidget>
    with SingleTickerProviderStateMixin {
  final ComplexParser _parser = ComplexParser();
  final DiTreDiController _controller = DiTreDiController(
    rotationX: -35,
    rotationY: 45,
    userScale: 1,
    minUserScale: 0.2,
    maxUserScale: 20,
    ambientLightStrength: 0.22,
    lightStrength: 0.95,
  );

  late final Ticker _ticker;
  double _animationClockMs = 0;
  int _lastTickMs = 0;
  double _autoRotationOffset = 0;
  bool _needsRecalc = true;
  List<SurfaceTriangle3D> _surfaceTriangles = const [];

  static const double _zClipLimit = 24.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final elapsedMs = elapsed.inMilliseconds;
      final deltaMs = _lastTickMs == 0 ? 0 : (elapsedMs - _lastTickMs);
      _lastTickMs = elapsedMs;
      if (deltaMs > 0) _animationClockMs += deltaMs;
      if (widget.autoRotate) {
        _autoRotationOffset += 0.2;
        if (_autoRotationOffset >= 360) _autoRotationOffset -= 360;
      }
      if (widget.functions.any((f) => f.hasAnimation)) {
        setState(() => _needsRecalc = true);
      } else {
        setState(() {});
      }
    });
    _ticker.start();
  }

  @override
  void didUpdateWidget(covariant Plot3DWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.functions != oldWidget.functions ||
        widget.isComplex != oldWidget.isComplex ||
        widget.centerX != oldWidget.centerX ||
        widget.centerY != oldWidget.centerY ||
        widget.centerZ != oldWidget.centerZ ||
        widget.zoom != oldWidget.zoom) {
      _needsRecalc = true;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _controller.dispose();
    super.dispose();
  }

  int _gridSteps() {
    final range = _visibleHalfRange();
    final rangeScale = math.sqrt(range / 15.0).clamp(0.75, 1.9);
    final base = widget.isComplex ? 92 : 84;
    final zoomDetail = widget.zoom < 0.7
        ? 1.12
        : (widget.zoom > 1.6 ? 1.08 : 1.0);
    return (base * rangeScale * zoomDetail).round().clamp(64, 150);
  }

  double _visibleHalfRange() {
    final range = 15.0 / widget.zoom.clamp(0.001, 1000000.0);
    return range.clamp(0.01, 100000.0);
  }

  double _computeAnimatedT(PlotLine3D f) {
    if (!f.hasAnimation) return f.tMin;
    final duration = f.durationMs.toDouble();
    final progress = (_animationClockMs % duration) / duration;
    return f.tMin + ((f.tMax - f.tMin) * progress);
  }

  List<Model3D> _buildFigures() {
    final models = <Model3D>[];
    _surfaceTriangles = [];
    final vars = <String, _Complex>{
      'x': const _Complex(0),
      'y': const _Complex(0),
      'z': const _Complex(0),
      't': const _Complex(0),
      'theta': const _Complex(0),
      'phi': const _Complex(0),
      'r': const _Complex(0),
    };

    for (final f in widget.functions) {
      final expr = f.expression.trim();
      if (expr.isEmpty) continue;

      final isCart = f.coordSystem == CoordSystem3D.cartesian;
      final isCyl = f.coordSystem == CoordSystem3D.cylindrical;
      final isSph = f.coordSystem == CoordSystem3D.spherical;
      final halfRange = _visibleHalfRange();

      final uMin = f.xMin ?? (isCart ? widget.centerX - halfRange : 0.0);
      final uMax =
          f.xMax ?? (isCart ? widget.centerX + halfRange : 2 * math.pi);
      final vMin =
          f.yMin ??
          (isCart ? widget.centerY - halfRange : (isSph ? 0.0 : -math.pi));
      final vMax = f.yMax ?? (isCart ? widget.centerY + halfRange : math.pi);
      final zClipLimit = math.max(_zClipLimit, halfRange * 1.35);
      final steps = _gridSteps();
      final uStep = (uMax - uMin) / steps;
      final vStep = (vMax - vMin) / steps;

      vars['t'] = _Complex(_computeAnimatedT(f));

      final grid = List.generate(
        steps + 1,
        (_) => List<_SamplePoint?>.filled(steps + 1, null),
      );

      for (int i = 0; i <= steps; i++) {
        final u = uMin + (i * uStep);
        for (int j = 0; j <= steps; j++) {
          final v = vMin + (j * vStep);
          vars['x'] = _Complex(u);
          vars['y'] = _Complex(v);
          vars['z'] = _Complex(u, v);
          vars['theta'] = _Complex(u);
          vars['phi'] = _Complex(v);
          vars['r'] = _Complex(u);
          grid[i][j] = _samplePoint(
            expr: expr,
            vars: vars,
            f: f,
            u: u,
            v: v,
            isCart: isCart,
            isCyl: isCyl,
            zClipLimit: zClipLimit,
          );
        }
      }

      final faces = <Face3D>[];
      for (int i = 0; i < steps; i++) {
        for (int j = 0; j < steps; j++) {
          final u0 = uMin + (i * uStep);
          final u1 = uMin + ((i + 1) * uStep);
          final v0 = vMin + (j * vStep);
          final v1 = vMin + ((j + 1) * vStep);
          _addCellFaces(
            faces,
            f,
            [
              _GridCorner(u0, v0, grid[i][j]),
              _GridCorner(u1, v0, grid[i + 1][j]),
              _GridCorner(u1, v1, grid[i + 1][j + 1]),
              _GridCorner(u0, v1, grid[i][j + 1]),
            ],
            expr,
            vars,
            isCart,
            isCyl,
            zClipLimit,
          );
        }
      }
      if (faces.isNotEmpty) models.add(Mesh3D(faces));
    }
    return models;
  }

  _SamplePoint? _samplePoint({
    required String expr,
    required Map<String, _Complex> vars,
    required PlotLine3D f,
    required double u,
    required double v,
    required bool isCart,
    required bool isCyl,
    required double zClipLimit,
  }) {
    vars['x'] = _Complex(u);
    vars['y'] = _Complex(v);
    vars['z'] = _Complex(u, v);
    vars['theta'] = _Complex(u);
    vars['phi'] = _Complex(v);
    vars['r'] = _Complex(u);
    try {
      final result = _parser.evaluate(expr, variables: vars);
      final zVal = widget.isComplex ? result.abs() : result.real;
      if (!zVal.isFinite || (zVal - widget.centerZ).abs() > zClipLimit) {
        return null;
      }
      if (!widget.isComplex && result.imag.abs() > 1e-4) return null;
      if (f.zMin != null && zVal < f.zMin!) return null;
      if (f.zMax != null && zVal > f.zMax!) return null;

      late double x;
      late double y;
      late double z;
      if (isCart) {
        x = u;
        y = v;
        z = zVal;
      } else if (isCyl) {
        x = u * math.cos(v);
        y = u * math.sin(v);
        z = zVal;
      } else {
        x = zVal * math.sin(v) * math.cos(u);
        y = zVal * math.sin(v) * math.sin(u);
        z = zVal * math.cos(v);
      }

      return _SamplePoint(
        vmath.Vector3(
          x - widget.centerX,
          y - widget.centerY,
          z - widget.centerZ,
        ),
        widget.isComplex ? result.arg() : zVal,
      );
    } catch (_) {
      return null;
    }
  }

  void _addCellFaces(
    List<Face3D> faces,
    PlotLine3D f,
    List<_GridCorner> corners,
    String expr,
    Map<String, _Complex> vars,
    bool isCart,
    bool isCyl,
    double zClipLimit,
  ) {
    final valid = corners.where((corner) => corner.sample != null).toList();

    if (valid.length == 4) {
      _addDoubleSidedTriangle(
        faces,
        f,
        valid[0].sample!,
        valid[1].sample!,
        valid[2].sample!,
      );
      _addDoubleSidedTriangle(
        faces,
        f,
        valid[0].sample!,
        valid[2].sample!,
        valid[3].sample!,
      );
      return;
    }

    final polygon = <_SamplePoint>[];
    for (int i = 0; i < corners.length; i++) {
      final current = corners[i];
      final next = corners[(i + 1) % corners.length];
      if (current.sample != null) polygon.add(current.sample!);
      if ((current.sample == null) != (next.sample == null)) {
        final boundary = _interpolateBoundary(
          expr: expr,
          vars: vars,
          f: f,
          valid: current.sample != null ? current : next,
          invalid: current.sample == null ? current : next,
          isCart: isCart,
          isCyl: isCyl,
          zClipLimit: zClipLimit,
        );
        if (boundary != null) polygon.add(boundary);
      }
    }

    if (polygon.length < 3) return;
    for (int i = 1; i < polygon.length - 1; i++) {
      _addDoubleSidedTriangle(faces, f, polygon[0], polygon[i], polygon[i + 1]);
    }
  }

  _SamplePoint? _interpolateBoundary({
    required String expr,
    required Map<String, _Complex> vars,
    required PlotLine3D f,
    required _GridCorner valid,
    required _GridCorner invalid,
    required bool isCart,
    required bool isCyl,
    required double zClipLimit,
  }) {
    var goodU = valid.u;
    var goodV = valid.v;
    var badU = invalid.u;
    var badV = invalid.v;
    _SamplePoint? best = valid.sample;
    for (int i = 0; i < 10; i++) {
      final midU = (goodU + badU) / 2;
      final midV = (goodV + badV) / 2;
      final sample = _samplePoint(
        expr: expr,
        vars: vars,
        f: f,
        u: midU,
        v: midV,
        isCart: isCart,
        isCyl: isCyl,
        zClipLimit: zClipLimit,
      );
      if (sample == null) {
        badU = midU;
        badV = midV;
      } else {
        best = sample;
        goodU = midU;
        goodV = midV;
      }
    }
    return best;
  }

  void _addDoubleSidedTriangle(
    List<Face3D> faces,
    PlotLine3D f,
    _SamplePoint a,
    _SamplePoint b,
    _SamplePoint c,
  ) {
    final color = _faceColor(
      f,
      (a.colorParam + b.colorParam + c.colorParam) / 3,
    );
    _surfaceTriangles.add(
      SurfaceTriangle3D(a.position, b.position, c.position, color),
    );
    faces.add(
      Face3D.fromVertices(a.position, b.position, c.position, color: color),
    );
    faces.add(
      Face3D.fromVertices(c.position, b.position, a.position, color: color),
    );
  }

  Color _faceColor(PlotLine3D f, double param) {
    if (!widget.isComplex) {
      final hsl = HSLColor.fromColor(f.color);
      final light = (0.35 + (param / (_zClipLimit + 1e-9)).abs() * 0.35).clamp(
        0.18,
        0.82,
      );
      return hsl.withLightness(light).toColor();
    }
    final hue = ((param * 180 / math.pi) + 360) % 360;
    return HSLColor.fromAHSL(1, hue, 0.82, 0.52).toColor();
  }

  @override
  Widget build(BuildContext context) {
    _controller.update(
      viewScale: 15.0,
      rotationY: widget.yaw + _autoRotationOffset,
      rotationX: widget.pitch - 90,
      userScale: widget.zoom,
      minUserScale: 0.2,
      maxUserScale: 20,
    );
    if (_needsRecalc) {
      _buildFigures();
      _needsRecalc = false;
    }
    return Stack(
      children: [
        if (widget.showLabels)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: MainAxesLabelsPainter3D(
                  yawDeg: widget.yaw + _autoRotationOffset,
                  pitchDeg: widget.pitch,
                  isDarkMode: widget.isDarkMode,
                  zoom: widget.zoom,
                  centerX: widget.centerX,
                  centerY: widget.centerY,
                  centerZ: widget.centerZ,
                  halfRange: _visibleHalfRange(),
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
              triangles: _surfaceTriangles,
              yawDeg: widget.yaw + _autoRotationOffset,
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
                  yawDeg: widget.yaw + _autoRotationOffset,
                  pitchDeg: widget.pitch,
                  isDarkMode: widget.isDarkMode,
                  zoom: widget.zoom,
                  centerX: widget.centerX,
                  centerY: widget.centerY,
                  centerZ: widget.centerZ,
                  halfRange: _visibleHalfRange(),
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
                  yawDeg: widget.yaw + _autoRotationOffset,
                  pitchDeg: widget.pitch,
                  isDarkMode: widget.isDarkMode,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SamplePoint {
  final vmath.Vector3 position;
  final double colorParam;

  const _SamplePoint(this.position, this.colorParam);
}

class _GridCorner {
  const _GridCorner(this.u, this.v, this.sample);

  final double u;
  final double v;
  final _SamplePoint? sample;
}

class SurfaceTriangle3D {
  const SurfaceTriangle3D(this.a, this.b, this.c, this.color);

  final vmath.Vector3 a;
  final vmath.Vector3 b;
  final vmath.Vector3 c;
  final Color color;
}

class ProjectedTriangle3D {
  const ProjectedTriangle3D(this.points, this.depth, this.color);

  final List<Offset> points;
  final double depth;
  final Color color;
}

class SurfacePainter3D extends CustomPainter {
  const SurfacePainter3D({
    required this.triangles,
    required this.yawDeg,
    required this.pitchDeg,
    required this.zoom,
    required this.isDarkMode,
  });

  final List<SurfaceTriangle3D> triangles;
  final double yawDeg;
  final double pitchDeg;
  final double zoom;
  final bool isDarkMode;

  @override
  void paint(Canvas canvas, Size size) {
    if (triangles.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2);
    final rot =
        vmath.Matrix3.rotationX(vmath.radians(pitchDeg) - math.pi / 2) *
        vmath.Matrix3.rotationZ(vmath.radians(yawDeg));
    final scale = 15.0 * zoom;
    final light = vmath.Vector3(0.35, -0.55, 0.75)..normalize();
    final viewDirection = vmath.Vector3(0, 0, 1);

    (Offset, double) project(vmath.Vector3 v) {
      final rx = rot[0] * v.x + rot[3] * v.y + rot[6] * v.z;
      final ry = rot[1] * v.x + rot[4] * v.y + rot[7] * v.z;
      final rz = rot[2] * v.x + rot[5] * v.y + rot[8] * v.z;
      return (Offset(center.dx + rx * scale, center.dy - ry * scale), rz);
    }

    final projected = <ProjectedTriangle3D>[];
    for (final tri in triangles) {
      final pa = project(tri.a);
      final pb = project(tri.b);
      final pc = project(tri.c);
      final normal = (tri.b - tri.a).cross(tri.c - tri.a);
      if (normal.length2 < 1e-12) continue;
      normal.normalize();
      var viewNormal = rot.transformed(normal)..normalize();
      if (viewNormal.dot(viewDirection) < 0) {
        viewNormal = -viewNormal;
      }
      final mainDiffuse = math.max(0.0, viewNormal.dot(light));
      final fillDiffuse = math.max(
        0.0,
        viewNormal.dot(vmath.Vector3(-0.45, 0.3, 0.75)..normalize()),
      );
      final diffuse = (mainDiffuse * 0.78 + fillDiffuse * 0.22).clamp(0.0, 1.0);
      final specular = math
          .pow(
            math.max(0.0, viewNormal.dot((light + viewDirection)..normalize())),
            18,
          )
          .toDouble();
      final shaded = _shadeColor(tri.color, diffuse, specular);
      projected.add(
        ProjectedTriangle3D(
          [pa.$1, pb.$1, pc.$1],
          (pa.$2 + pb.$2 + pc.$2) / 3,
          shaded,
        ),
      );
    }
    projected.sort((a, b) => a.depth.compareTo(b.depth));
    final positions = Float32List(projected.length * 6);
    final colors = Int32List(projected.length * 3);
    for (int i = 0; i < projected.length; i++) {
      final tri = projected[i];
      final p = tri.points;
      final vertexBase = i * 6;
      final colorBase = i * 3;
      positions[vertexBase] = p[0].dx;
      positions[vertexBase + 1] = p[0].dy;
      positions[vertexBase + 2] = p[1].dx;
      positions[vertexBase + 3] = p[1].dy;
      positions[vertexBase + 4] = p[2].dx;
      positions[vertexBase + 5] = p[2].dy;
      final argb = tri.color.toARGB32();
      colors[colorBase] = argb;
      colors[colorBase + 1] = argb;
      colors[colorBase + 2] = argb;
    }
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      colors: colors,
    );
    canvas.drawVertices(
      vertices,
      BlendMode.srcOver,
      Paint()..isAntiAlias = true,
    );
    vertices.dispose();
  }

  Color _shadeColor(Color base, double diffuse, double specular) {
    final hsl = HSLColor.fromColor(base);
    final baseLightness = isDarkMode ? 0.43 : 0.48;
    final lightness = (baseLightness + diffuse * 0.26).clamp(
      isDarkMode ? 0.34 : 0.32,
      isDarkMode ? 0.72 : 0.76,
    );
    final saturation = (hsl.saturation * (1.12 + diffuse * 0.10)).clamp(
      0.0,
      1.0,
    );
    final lit = hsl
        .withLightness(lightness)
        .withSaturation(saturation)
        .toColor()
        .withValues(alpha: 1.0);
    return Color.lerp(lit, Colors.white, (specular * 0.05).clamp(0.0, 0.05))!;
  }

  @override
  bool shouldRepaint(covariant SurfacePainter3D oldDelegate) {
    return oldDelegate.triangles != triangles ||
        oldDelegate.yawDeg != yawDeg ||
        oldDelegate.pitchDeg != pitchDeg ||
        oldDelegate.zoom != zoom ||
        oldDelegate.isDarkMode != isDarkMode;
  }
}

class MainAxesLabelsPainter3D extends CustomPainter {
  const MainAxesLabelsPainter3D({
    required this.yawDeg,
    required this.pitchDeg,
    required this.isDarkMode,
    required this.zoom,
    required this.centerX,
    required this.centerY,
    required this.centerZ,
    required this.halfRange,
    this.gridCoordSystem = CoordSystem3D.cartesian,
    required this.showGrid,
    required this.showAxesAndLabels,
  });

  final double yawDeg;
  final double pitchDeg;
  final bool isDarkMode;
  final double zoom;
  final double centerX;
  final double centerY;
  final double centerZ;
  final double halfRange;
  final CoordSystem3D gridCoordSystem;
  final bool showGrid;
  final bool showAxesAndLabels;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rot =
        vmath.Matrix3.rotationX(vmath.radians(pitchDeg) - math.pi / 2) *
        vmath.Matrix3.rotationZ(vmath.radians(yawDeg));
    final scale = 15.0 * zoom;

    Offset project(double x, double y, double z) {
      final rx = rot[0] * x + rot[3] * y + rot[6] * z;
      final ry = rot[1] * x + rot[4] * y + rot[7] * z;
      return Offset(center.dx + rx * scale, center.dy - ry * scale);
    }

    final gridPaint = Paint()
      ..color = (isDarkMode ? Colors.white24 : Colors.black26)
      ..strokeWidth = 1.0;
    final axisPaint = Paint()..strokeWidth = 1.6;

    final step = MathGrid.calculateStepSize(80.0, scale);
    final start = (-(halfRange / step).floor()) * step;
    final end = ((halfRange / step).floor()) * step;

    void drawPolyline(List<vmath.Vector3> points, Paint paint) {
      for (int i = 1; i < points.length; i++) {
        canvas.drawLine(
          project(points[i - 1].x, points[i - 1].y, points[i - 1].z),
          project(points[i].x, points[i].y, points[i].z),
          paint,
        );
      }
    }

    if (showGrid) {
      switch (gridCoordSystem) {
        case CoordSystem3D.cartesian:
          for (double d = start; d <= end; d += step) {
            canvas.drawLine(
              project(-halfRange, d, 0),
              project(halfRange, d, 0),
              gridPaint,
            );
            canvas.drawLine(
              project(d, -halfRange, 0),
              project(d, halfRange, 0),
              gridPaint,
            );
          }
        case CoordSystem3D.cylindrical:
          const circleSegments = 96;
          for (double r = step; r <= halfRange; r += step) {
            drawPolyline([
              for (int i = 0; i <= circleSegments; i++)
                vmath.Vector3(
                  math.cos((i / circleSegments) * math.pi * 2) * r,
                  math.sin((i / circleSegments) * math.pi * 2) * r,
                  0,
                ),
            ], gridPaint);
          }
          for (int i = 0; i < 24; i++) {
            final a = (i / 24) * math.pi * 2;
            canvas.drawLine(
              project(-math.cos(a) * halfRange, -math.sin(a) * halfRange, 0),
              project(math.cos(a) * halfRange, math.sin(a) * halfRange, 0),
              gridPaint,
            );
          }
          for (double z = start; z <= end; z += step) {
            drawPolyline([
              for (int i = 0; i <= circleSegments; i++)
                vmath.Vector3(
                  math.cos((i / circleSegments) * math.pi * 2) * halfRange,
                  math.sin((i / circleSegments) * math.pi * 2) * halfRange,
                  z,
                ),
            ], gridPaint..color = gridPaint.color.withValues(alpha: 0.55));
            gridPaint.color = isDarkMode ? Colors.white24 : Colors.black26;
          }
        case CoordSystem3D.spherical:
          const circleSegments = 96;
          for (double r = step; r <= halfRange; r += step) {
            drawPolyline([
              for (int i = 0; i <= circleSegments; i++)
                vmath.Vector3(
                  math.cos((i / circleSegments) * math.pi * 2) * r,
                  math.sin((i / circleSegments) * math.pi * 2) * r,
                  0,
                ),
            ], gridPaint);
            drawPolyline([
              for (int i = 0; i <= circleSegments; i++)
                vmath.Vector3(
                  math.cos((i / circleSegments) * math.pi * 2) * r,
                  0,
                  math.sin((i / circleSegments) * math.pi * 2) * r,
                ),
            ], gridPaint);
            drawPolyline([
              for (int i = 0; i <= circleSegments; i++)
                vmath.Vector3(
                  0,
                  math.cos((i / circleSegments) * math.pi * 2) * r,
                  math.sin((i / circleSegments) * math.pi * 2) * r,
                ),
            ], gridPaint);
          }
          for (int i = 0; i < 12; i++) {
            final a = (i / 12) * math.pi * 2;
            canvas.drawLine(
              project(0, 0, 0),
              project(math.cos(a) * halfRange, math.sin(a) * halfRange, 0),
              gridPaint,
            );
            canvas.drawLine(
              project(0, 0, 0),
              project(math.cos(a) * halfRange, 0, math.sin(a) * halfRange),
              gridPaint,
            );
          }
      }
    }

    if (!showAxesAndLabels) return;

    canvas.drawLine(
      project(-halfRange, 0, 0),
      project(halfRange, 0, 0),
      axisPaint..color = Colors.redAccent.withValues(alpha: 0.75),
    );
    canvas.drawLine(
      project(0, -halfRange, 0),
      project(0, halfRange, 0),
      axisPaint..color = Colors.greenAccent.withValues(alpha: 0.75),
    );
    canvas.drawLine(
      project(0, 0, -halfRange),
      project(0, 0, halfRange),
      axisPaint..color = Colors.blueAccent.withValues(alpha: 0.75),
    );

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final labelColor = isDarkMode ? Colors.white70 : Colors.black87;
    void drawText(String txt, Offset at, {Color? color}) {
      textPainter.text = TextSpan(
        text: txt,
        style: TextStyle(
          fontSize: 10,
          color: color ?? labelColor,
          fontWeight: FontWeight.w600,
          backgroundColor: Colors.transparent,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, at);
    }

    final lx = math.sqrt(rot[0] * rot[0] + rot[1] * rot[1]);
    final ly = math.sqrt(rot[3] * rot[3] + rot[4] * rot[4]);
    final lz = math.sqrt(rot[6] * rot[6] + rot[7] * rot[7]);
    final ax = lx > 1e-6 ? Offset(rot[0] / lx, -rot[1] / lx) : Offset.zero;
    final ay = ly > 1e-6 ? Offset(rot[3] / ly, -rot[4] / ly) : Offset.zero;
    final az = lz > 1e-6 ? Offset(rot[6] / lz, -rot[7] / lz) : Offset.zero;
    const labelOffset = 8.0;

    void drawTicks(String axis) {
      final unit = axis == 'x' ? ax : (axis == 'y' ? ay : az);
      final centerValue = axis == 'x'
          ? centerX
          : (axis == 'y' ? centerY : centerZ);
      for (double d = start; d <= end; d += step) {
        if (d.abs() < 1e-8) continue;
        double x = 0, y = 0, z = 0;
        if (axis == 'x') x = d;
        if (axis == 'y') y = d;
        if (axis == 'z') z = d;
        final p = project(x, y, z);
        if (p.dx < -60 ||
            p.dx > size.width + 60 ||
            p.dy < -60 ||
            p.dy > size.height + 60) {
          continue;
        }
        drawText(
          MathFormatter.formatAxisLabel(centerValue + d, precision: 2),
          p + Offset(unit.dx * labelOffset, unit.dy * labelOffset),
        );
      }
    }

    drawTicks('x');
    drawTicks('y');
    drawTicks('z');
    drawText('X', project(end, 0, 0), color: Colors.redAccent);
    drawText('Y', project(0, end, 0), color: Colors.greenAccent);
    drawText('Z', project(0, 0, end), color: Colors.blueAccent);
  }

  @override
  bool shouldRepaint(covariant MainAxesLabelsPainter3D oldDelegate) {
    return oldDelegate.yawDeg != yawDeg ||
        oldDelegate.pitchDeg != pitchDeg ||
        oldDelegate.isDarkMode != isDarkMode ||
        oldDelegate.zoom != zoom ||
        oldDelegate.centerX != centerX ||
        oldDelegate.centerY != centerY ||
        oldDelegate.centerZ != centerZ ||
        oldDelegate.halfRange != halfRange ||
        oldDelegate.gridCoordSystem != gridCoordSystem ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.showAxesAndLabels != showAxesAndLabels;
  }
}

class AxisGizmoPainter3D extends CustomPainter {
  const AxisGizmoPainter3D({
    required this.yawDeg,
    required this.pitchDeg,
    required this.isDarkMode,
  });

  final double yawDeg;
  final double pitchDeg;
  final bool isDarkMode;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final rot = vmath.Matrix3.identity()
      ..multiply(vmath.Matrix3.rotationX(vmath.radians(pitchDeg) - math.pi / 2))
      ..multiply(vmath.Matrix3.rotationZ(vmath.radians(yawDeg)));

    Offset project(vmath.Vector3 v) {
      final p = rot.transformed(v);
      return center + Offset(p.x * 18, -p.y * 18);
    }

    final p = Paint()..strokeWidth = 2.2;
    final ox = project(vmath.Vector3(1, 0, 0));
    final oy = project(vmath.Vector3(0, 1, 0));
    final oz = project(vmath.Vector3(0, 0, 1));
    canvas.drawLine(center, ox, p..color = Colors.redAccent);
    canvas.drawLine(center, oy, p..color = Colors.greenAccent);
    canvas.drawLine(center, oz, p..color = Colors.blueAccent);

    final tp = TextPainter(textDirection: TextDirection.ltr);
    void drawLabel(String text, Offset pos, Color color) {
      tp.text = TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      );
      tp.layout();
      tp.paint(canvas, pos + const Offset(2, -2));
    }

    drawLabel('X', ox, Colors.redAccent);
    drawLabel('Y', oy, Colors.greenAccent);
    drawLabel('Z', oz, Colors.blueAccent);
  }

  @override
  bool shouldRepaint(covariant AxisGizmoPainter3D oldDelegate) {
    return oldDelegate.yawDeg != yawDeg ||
        oldDelegate.pitchDeg != pitchDeg ||
        oldDelegate.isDarkMode != isDarkMode;
  }
}
