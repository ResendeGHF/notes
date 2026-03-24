// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:saber/services/math_engine/format.dart';
import 'package:saber/services/math_engine/grid.dart';
import 'package:saber/services/math_engine/math_engine.dart';

enum ExtremaPointType { root, minimum, maximum, asymptote, saddle }

enum _MinMaxMode { minOnly, maxOnly }

class ExtremaPoint {
  const ExtremaPoint({required this.type, required this.x, this.y, this.z});

  final ExtremaPointType type;
  final double x;
  final double? y;
  final double? z;
}

class ExtremaPane extends StatefulWidget {
  const ExtremaPane({
    super.key,
    required this.colorScheme,
    required this.isDark,
    this.repaintBoundaryKey,
    this.onCaptureRequested,
    this.forCapture = false,
  });

  final ColorScheme colorScheme;
  final bool isDark;
  final GlobalKey? repaintBoundaryKey;
  final VoidCallback? onCaptureRequested;

  final bool forCapture;

  @override
  State<ExtremaPane> createState() => _ExtremaPaneState();
}

class _ExtremaPaneState extends State<ExtremaPane> {
  final _exprCtrl = TextEditingController(text: 'x^2 - 2*x - 3');
  final _xMinCtrl = TextEditingController(text: '-5');
  final _xMaxCtrl = TextEditingController(text: '5');
  final _yMinCtrl = TextEditingController(text: '-5');
  final _yMaxCtrl = TextEditingController(text: '5');

  int _dimension = 2;
  final List<ExtremaPoint> _points = [];
  String _message = '';
  bool _showLabels = true;
  bool _showGrid = true;

  double _offsetX = 0;
  double _offsetY = 0;
  double _zoom2D = 40.0;
  double _yaw3D = 45;
  double _pitch3D = -30;
  double _zoom3D = 1.0;

  static final _parser = ComplexParser();

  @override
  void initState() {
    super.initState();
    _exprCtrl.addListener(_clearPointsOnInputChange);
    _xMinCtrl.addListener(_clearPointsOnInputChange);
    _xMaxCtrl.addListener(_clearPointsOnInputChange);
    _yMinCtrl.addListener(_clearPointsOnInputChange);
    _yMaxCtrl.addListener(_clearPointsOnInputChange);
  }

  void _centerViewAtOrigin() {
    if (_dimension == 2) {
      _offsetX = 0;
      _offsetY = 0;
      _zoom2D = 40.0;
    } else {
      _yaw3D = 45;
      _pitch3D = -30;
      _zoom3D = 1.0;
    }
  }

  void _clearPointsOnInputChange() {
    if (_points.isNotEmpty || _message.isNotEmpty) {
      setState(() {
        _points.clear();
        _message = '';
      });
    }
  }

  @override
  void dispose() {
    _exprCtrl.removeListener(_clearPointsOnInputChange);
    _xMinCtrl.removeListener(_clearPointsOnInputChange);
    _xMaxCtrl.removeListener(_clearPointsOnInputChange);
    _yMinCtrl.removeListener(_clearPointsOnInputChange);
    _yMaxCtrl.removeListener(_clearPointsOnInputChange);
    _exprCtrl.dispose();
    _xMinCtrl.dispose();
    _xMaxCtrl.dispose();
    _yMinCtrl.dispose();
    _yMaxCtrl.dispose();
    super.dispose();
  }

  double _eval2D(double x) {
    final r = _parser.evaluate(
      _exprCtrl.text.replaceAll('×', '*').replaceAll('√', 'sqrt'),
      variables: {'x': Complex(x)},
    );
    return r.real;
  }

  double _eval3D(double x, double y) {
    final r = _parser.evaluate(
      _exprCtrl.text.replaceAll('×', '*').replaceAll('√', 'sqrt'),
      variables: {'x': Complex(x), 'y': Complex(y)},
    );
    return r.real;
  }

  double? _eval2DSafe(double x) {
    try {
      final r = _parser.evaluate(
        _exprCtrl.text.replaceAll('×', '*').replaceAll('√', 'sqrt'),
        variables: {'x': Complex(x)},
      );
      final y = r.real;
      return y.isFinite ? y : null;
    } catch (_) {
      return null;
    }
  }

  double? _eval3DSafe(double x, double y) {
    try {
      final r = _parser.evaluate(
        _exprCtrl.text.replaceAll('×', '*').replaceAll('√', 'sqrt'),
        variables: {'x': Complex(x), 'y': Complex(y)},
      );
      final z = r.real;
      return z.isFinite ? z : null;
    } catch (_) {
      return null;
    }
  }

  static double _h3D(double xRange, double yRange) =>
      math.max(xRange, yRange) * 1e-5 + 1e-10;

  double? _eval3D_fx(double x, double y, double h) {
    try {
      final fR = _eval3D(x + h, y);
      final fL = _eval3D(x - h, y);
      if (fR.isFinite && fL.isFinite) return (fR - fL) / (2 * h);
    } catch (_) {}
    return null;
  }

  double? _eval3D_fy(double x, double y, double h) {
    try {
      final fR = _eval3D(x, y + h);
      final fL = _eval3D(x, y - h);
      if (fR.isFinite && fL.isFinite) return (fR - fL) / (2 * h);
    } catch (_) {}
    return null;
  }

  double? _eval3D_hessianDet(double x, double y, double h) {
    try {
      final f = _eval3D(x, y);
      if (!f.isFinite) return null;
      final fxx = (_eval3D(x + h, y) - 2 * f + _eval3D(x - h, y)) / (h * h);
      final fyy = (_eval3D(x, y + h) - 2 * f + _eval3D(x, y - h)) / (h * h);
      final fxy =
          (_eval3D(x + h, y + h) -
              _eval3D(x + h, y - h) -
              _eval3D(x - h, y + h) +
              _eval3D(x - h, y - h)) /
          (4 * h * h);
      if (fxx.isFinite && fyy.isFinite && fxy.isFinite) {
        return fxx * fyy - fxy * fxy;
      }
    } catch (_) {}
    return null;
  }

  static const double _poleThreshold = 1e8;

  static const double _poleJumpThreshold = 1e4;

  void _findAsymptotes() {
    if (_dimension == 2) {
      _findAsymptotes2D();
    } else {
      _findAsymptotes3D();
    }
  }

  double _refinePole2D(
    double a,
    double b, [
    double poleThreshold = _poleThreshold,
  ]) {
    for (int iter = 0; iter < 50; iter++) {
      final mid = (a + b) / 2;
      final yMid = _eval2DSafe(mid);
      final midIsPole = yMid == null || yMid.abs() > poleThreshold;
      if (midIsPole) {
        b = mid;
      } else {
        a = mid;
      }
      if ((b - a).abs() < 1e-12) return (a + b) / 2;
    }
    return (a + b) / 2;
  }

  void _findAsymptotes2D() {
    final xMin = double.tryParse(_xMinCtrl.text) ?? -5;
    final xMax = double.tryParse(_xMaxCtrl.text) ?? 5;
    if (xMin >= xMax) {
      setState(() {
        _message = 'Invalid range';
        _points.removeWhere((p) => p.type == ExtremaPointType.asymptote);
      });
      return;
    }
    const n = 800;
    final step = (xMax - xMin) / n;
    final newPoints = <ExtremaPoint>[];
    void addPole(double poleX) {
      if (newPoints.every((p) => (p.x - poleX).abs() > 1e-6)) {
        newPoints.add(ExtremaPoint(type: ExtremaPointType.asymptote, x: poleX));
      }
    }

    bool isPoleLike(double? y, [double threshold = _poleThreshold]) =>
        y == null || !y.isFinite || y.abs() > threshold;
    bool isFiniteBounded(double? y, [double threshold = _poleThreshold]) =>
        y != null && y.isFinite && y.abs() <= threshold;

    for (int i = 0; i < n; i++) {
      final a = xMin + step * i;
      final b = xMin + step * (i + 1);
      final fa = _eval2DSafe(a);
      final fb = _eval2DSafe(b);
      if (isFiniteBounded(fa) && isPoleLike(fb)) {
        addPole(_refinePole2D(a, b));
      } else if (isPoleLike(fa) && isFiniteBounded(fb)) {
        addPole(_refinePole2D(b, a));
      } else if (fa != null &&
          fb != null &&
          fa.isFinite &&
          fb.isFinite &&
          fa * fb < 0 &&
          (fa.abs() > 100 || fb.abs() > 100)) {
        addPole(_refinePole2D(a, b, _poleJumpThreshold));
      }
    }
    setState(() {
      _points.removeWhere((p) => p.type == ExtremaPointType.asymptote);
      _points.addAll(newPoints);
      final parts = <String>[];
      final mins = _points
          .where((p) => p.type == ExtremaPointType.minimum)
          .toList();
      final maxs = _points
          .where((p) => p.type == ExtremaPointType.maximum)
          .toList();
      final roots = _points
          .where((p) => p.type == ExtremaPointType.root)
          .toList();
      final asym = _points
          .where((p) => p.type == ExtremaPointType.asymptote)
          .toList();
      if (mins.isNotEmpty)
        parts.add('Min: ${mins.map((p) => p.x.toStringAsFixed(3)).join(', ')}');
      if (maxs.isNotEmpty)
        parts.add('Max: ${maxs.map((p) => p.x.toStringAsFixed(3)).join(', ')}');
      if (roots.isNotEmpty)
        parts.add(
          'Roots: ${roots.map((p) => p.x.toStringAsFixed(3)).join(', ')}',
        );
      if (asym.isNotEmpty)
        parts.add(
          'Asymptotes x: ${asym.map((p) => p.x.toStringAsFixed(3)).join(', ')}',
        );
      _message = parts.isEmpty
          ? 'No vertical asymptotes found in range'
          : parts.join('  |  ');
    });
  }

  void _findAsymptotes3D() {
    final xMin = double.tryParse(_xMinCtrl.text) ?? -5;
    final xMax = double.tryParse(_xMaxCtrl.text) ?? 5;
    final yMin = double.tryParse(_yMinCtrl.text) ?? -5;
    final yMax = double.tryParse(_yMaxCtrl.text) ?? 5;
    if (xMin >= xMax || yMin >= yMax) {
      setState(() {
        _message = 'Invalid range';
        _points.removeWhere((p) => p.type == ExtremaPointType.asymptote);
      });
      return;
    }
    const n = 80;
    final dx = (xMax - xMin) / n;
    final dy = (yMax - yMin) / n;
    final newPoints = <ExtremaPoint>[];
    for (int i = 0; i <= n; i++) {
      for (int j = 0; j <= n; j++) {
        final x = xMin + dx * i;
        final y = yMin + dy * j;
        final z = _eval3DSafe(x, y);
        final isPole = z == null || z.abs() > _poleThreshold;
        if (!isPole) continue;
        if (newPoints.any(
          (p) => (p.x - x).abs() < dx * 1.5 && (p.y! - y).abs() < dy * 1.5,
        ))
          continue;
        newPoints.add(
          ExtremaPoint(
            type: ExtremaPointType.asymptote,
            x: x,
            y: y,
            z: double.nan,
          ),
        );
      }
    }
    setState(() {
      _points.removeWhere((p) => p.type == ExtremaPointType.asymptote);
      _points.addAll(newPoints);
      final asym = _points
          .where((p) => p.type == ExtremaPointType.asymptote)
          .toList();
      final parts = <String>[];
      final mins = _points
          .where((p) => p.type == ExtremaPointType.minimum)
          .toList();
      final maxs = _points
          .where((p) => p.type == ExtremaPointType.maximum)
          .toList();
      if (mins.isNotEmpty) parts.add('Min: ${mins.length} pt(s)');
      if (maxs.isNotEmpty) parts.add('Max: ${maxs.length} pt(s)');
      if (asym.isNotEmpty) parts.add('Asymptotes: ${asym.length} pole(s)');
      _message = parts.isEmpty
          ? 'No pole asymptotes found in range'
          : parts.join('  |  ');
    });
  }

  void _findRoots() {
    final xMin = double.tryParse(_xMinCtrl.text) ?? -5;
    final xMax = double.tryParse(_xMaxCtrl.text) ?? 5;
    if (xMin >= xMax) {
      setState(() {
        _message = 'Invalid range: xMin < xMax required';
        _points.clear();
      });
      return;
    }
    final roots = <ExtremaPoint>[];
    const n = 500;
    double? prevY;
    for (int i = 0; i <= n; i++) {
      final x = xMin + (xMax - xMin) * i / n;
      double y;
      try {
        y = _eval2D(x);
      } catch (_) {
        setState(() {
          _message = 'Function diverges or error in range';
          _points.clear();
        });
        return;
      }
      if (!y.isFinite) {
        setState(() {
          _message = 'Function diverges in range';
          _points.clear();
        });
        return;
      }
      if (prevY != null && (prevY < 0 != y < 0)) {
        final xRoot = _bisectRoot(x - (xMax - xMin) / n, x);
        if (xRoot != null)
          roots.add(ExtremaPoint(type: ExtremaPointType.root, x: xRoot));
      }
      prevY = y;
    }
    setState(() {
      _points.removeWhere((p) => p.type == ExtremaPointType.root);
      _points.addAll(roots);
      _message = roots.isEmpty
          ? 'No real root in range (or no sign change)'
          : 'Found ${roots.length} root(s)';
    });
  }

  double? _bisectRoot(double a, double b) {
    const maxIter = 60;
    for (int i = 0; i < maxIter; i++) {
      final mid = (a + b) / 2;
      final fMid = _eval2D(mid);
      if (fMid.abs() < 1e-10) return mid;
      if ((b - a).abs() < 1e-12) return mid;
      final fA = _eval2D(a);
      if (fA * fMid < 0)
        b = mid;
      else
        a = mid;
    }
    return (a + b) / 2;
  }

  void _findMinMax({required _MinMaxMode mode}) {
    if (_dimension == 2) {
      _findMinMax2D(mode: mode);
    } else {
      _findMinMax3D(mode: mode);
    }
  }

  static const double _goldenRatio = 0.618033988749895;

  double? _refineMin2D(double a, double c, double b) {
    const maxIter = 80;
    double lo = a, hi = b;
    double mid = c;
    double fMid = _eval2D(mid);
    for (int it = 0; it < maxIter && (hi - lo).abs() > 1e-12; it++) {
      if (hi - mid > mid - lo) {
        final x = mid + _goldenRatio * (hi - mid);
        final fX = _eval2D(x);
        if (!fX.isFinite) return null;
        if (fX < fMid) {
          lo = mid;
          mid = x;
          fMid = fX;
        } else {
          hi = x;
        }
      } else {
        final x = mid - _goldenRatio * (mid - lo);
        final fX = _eval2D(x);
        if (!fX.isFinite) return null;
        if (fX < fMid) {
          hi = mid;
          mid = x;
          fMid = fX;
        } else {
          lo = x;
        }
      }
    }
    return mid;
  }

  double? _refineMax2D(double a, double c, double b) {
    const maxIter = 80;
    double lo = a, hi = b;
    double mid = c;
    double fMid = _eval2D(mid);
    for (int it = 0; it < maxIter && (hi - lo).abs() > 1e-12; it++) {
      if (hi - mid > mid - lo) {
        final x = mid + _goldenRatio * (hi - mid);
        final fX = _eval2D(x);
        if (!fX.isFinite) return null;
        if (fX > fMid) {
          lo = mid;
          mid = x;
          fMid = fX;
        } else {
          hi = x;
        }
      } else {
        final x = mid - _goldenRatio * (mid - lo);
        final fX = _eval2D(x);
        if (!fX.isFinite) return null;
        if (fX > fMid) {
          hi = mid;
          mid = x;
          fMid = fX;
        } else {
          lo = x;
        }
      }
    }
    return mid;
  }

  void _findMinMax2D({required _MinMaxMode mode}) {
    final xMin = double.tryParse(_xMinCtrl.text) ?? -5;
    final xMax = double.tryParse(_xMaxCtrl.text) ?? 5;
    if (xMin >= xMax) {
      setState(() {
        _message = 'Invalid range';
        _points.removeWhere(
          (p) =>
              p.type == ExtremaPointType.minimum ||
              p.type == ExtremaPointType.maximum,
        );
      });
      return;
    }
    const n = 600;
    final step = (xMax - xMin) / n;
    final vals = <double?>[];
    for (int i = 0; i <= n; i++) {
      final x = xMin + step * i;
      try {
        final y = _eval2D(x);
        vals.add(y.isFinite ? y : null);
      } catch (_) {
        vals.add(null);
      }
    }
    final newPoints = <ExtremaPoint>[];
    for (int i = 1; i < n; i++) {
      if (vals[i] == null) continue;
      final v = vals[i]!;
      final left = vals[i - 1];
      final right = vals[i + 1];
      if (left != null && right != null) {
        if (mode != _MinMaxMode.maxOnly && v <= left && v <= right) {
          final xC = xMin + step * i;
          final refined = _refineMin2D(xC - step, xC, xC + step);
          if (refined != null) {
            try {
              final yRef = _eval2D(refined);
              if (yRef.isFinite) {
                newPoints.add(
                  ExtremaPoint(
                    type: ExtremaPointType.minimum,
                    x: refined,
                    y: yRef,
                  ),
                );
              }
            } catch (_) {}
          }
        }
        if (mode != _MinMaxMode.minOnly && v >= left && v >= right) {
          final xC = xMin + step * i;
          final refined = _refineMax2D(xC - step, xC, xC + step);
          if (refined != null) {
            try {
              final yRef = _eval2D(refined);
              if (yRef.isFinite) {
                newPoints.add(
                  ExtremaPoint(
                    type: ExtremaPointType.maximum,
                    x: refined,
                    y: yRef,
                  ),
                );
              }
            } catch (_) {}
          }
        }
      }
    }
    if (newPoints.isEmpty) {
      double? gMin, gMax;
      for (int i = 0; i <= n; i++) {
        if (vals[i] == null) continue;
        final y = vals[i]!;
        if (gMin == null || y < gMin) gMin = y;
        if (gMax == null || y > gMax) gMax = y;
      }
      final tol = 1e-10 * (1 + (gMin?.abs() ?? 0) + (gMax?.abs() ?? 0));
      if (mode != _MinMaxMode.maxOnly && gMin != null) {
        for (int i = 0; i <= n; i++) {
          if (vals[i] == null) continue;
          if ((vals[i]! - gMin).abs() <= tol) {
            final x = xMin + step * i;
            newPoints.add(
              ExtremaPoint(type: ExtremaPointType.minimum, x: x, y: gMin),
            );
          }
        }
      }
      if (mode != _MinMaxMode.minOnly && gMax != null) {
        for (int i = 0; i <= n; i++) {
          if (vals[i] == null) continue;
          if ((vals[i]! - gMax).abs() <= tol) {
            final x = xMin + step * i;
            newPoints.add(
              ExtremaPoint(type: ExtremaPointType.maximum, x: x, y: gMax),
            );
          }
        }
      }
    }
    setState(() {

      if (mode == _MinMaxMode.minOnly) {
        _points.removeWhere((p) => p.type == ExtremaPointType.minimum);
      } else {
        _points.removeWhere((p) => p.type == ExtremaPointType.maximum);
      }
      _points.addAll(newPoints);
      final mins = _points
          .where((p) => p.type == ExtremaPointType.minimum)
          .toList();
      final maxs = _points
          .where((p) => p.type == ExtremaPointType.maximum)
          .toList();
      final parts = <String>[];
      if (mins.isNotEmpty)
        parts.add(
          'Min: ${mins.map((p) => '${p.y?.toStringAsFixed(4)} at x=${p.x.toStringAsFixed(4)}').join('; ')}',
        );
      if (maxs.isNotEmpty)
        parts.add(
          'Max: ${maxs.map((p) => '${p.y?.toStringAsFixed(4)} at x=${p.x.toStringAsFixed(4)}').join('; ')}',
        );
      _message = parts.isEmpty
          ? (mode == _MinMaxMode.minOnly
                ? 'No minimum found'
                : 'No maximum found')
          : parts.join('  |  ');
    });
  }

  void _findMinMax3D({required _MinMaxMode mode}) {
    final xMin = double.tryParse(_xMinCtrl.text) ?? -5;
    final xMax = double.tryParse(_xMaxCtrl.text) ?? 5;
    final yMin = double.tryParse(_yMinCtrl.text) ?? -5;
    final yMax = double.tryParse(_yMaxCtrl.text) ?? 5;
    if (xMin >= xMax || yMin >= yMax) {
      setState(() {
        _message = 'Invalid range';
        _points.removeWhere(
          (p) =>
              p.type == ExtremaPointType.minimum ||
              p.type == ExtremaPointType.maximum,
        );
      });
      return;
    }
    const n = 60;
    final dx = (xMax - xMin) / n;
    final dy = (yMax - yMin) / n;
    final grid = List<List<double?>>.generate(
      n + 1,
      (_) => List.filled(n + 1, null),
    );
    for (int i = 0; i <= n; i++) {
      for (int j = 0; j <= n; j++) {
        final x = xMin + dx * i;
        final y = yMin + dy * j;
        try {
          final z = _eval3D(x, y);
          grid[i][j] = z.isFinite ? z : null;
        } catch (_) {
          grid[i][j] = null;
        }
      }
    }
    final newPoints = <ExtremaPoint>[];
    for (int i = 1; i < n; i++) {
      for (int j = 1; j < n; j++) {
        final z = grid[i][j];
        if (z == null) continue;
        bool isLocalMin = true, isLocalMax = true;
        for (int di = -1; di <= 1 && (isLocalMin || isLocalMax); di++) {
          for (int dj = -1; dj <= 1 && (isLocalMin || isLocalMax); dj++) {
            if (di == 0 && dj == 0) continue;
            final nz = grid[i + di][j + dj];
            if (nz != null) {
              if (nz < z) isLocalMin = false;
              if (nz > z) isLocalMax = false;
            }
          }
        }
        if (mode != _MinMaxMode.maxOnly && isLocalMin) {
          newPoints.add(
            ExtremaPoint(
              type: ExtremaPointType.minimum,
              x: xMin + dx * i,
              y: yMin + dy * j,
              z: z,
            ),
          );
        }
        if (mode != _MinMaxMode.minOnly && isLocalMax) {
          newPoints.add(
            ExtremaPoint(
              type: ExtremaPointType.maximum,
              x: xMin + dx * i,
              y: yMin + dy * j,
              z: z,
            ),
          );
        }
      }
    }
    if (newPoints.isEmpty) {
      double? gMin, gMax;
      for (int i = 0; i <= n; i++) {
        for (int j = 0; j <= n; j++) {
          final z = grid[i][j];
          if (z == null) continue;
          if (gMin == null || z < gMin) gMin = z;
          if (gMax == null || z > gMax) gMax = z;
        }
      }
      final tol = 1e-10 * (1 + (gMin?.abs() ?? 0) + (gMax?.abs() ?? 0));
      if (mode != _MinMaxMode.maxOnly && gMin != null) {
        for (int i = 0; i <= n; i++) {
          for (int j = 0; j <= n; j++) {
            final z = grid[i][j];
            if (z == null) continue;
            if ((z - gMin).abs() <= tol) {
              newPoints.add(
                ExtremaPoint(
                  type: ExtremaPointType.minimum,
                  x: xMin + dx * i,
                  y: yMin + dy * j,
                  z: gMin,
                ),
              );
            }
          }
        }
      }
      if (mode != _MinMaxMode.minOnly && gMax != null) {
        for (int i = 0; i <= n; i++) {
          for (int j = 0; j <= n; j++) {
            final z = grid[i][j];
            if (z == null) continue;
            if ((z - gMax).abs() <= tol) {
              newPoints.add(
                ExtremaPoint(
                  type: ExtremaPointType.maximum,
                  x: xMin + dx * i,
                  y: yMin + dy * j,
                  z: gMax,
                ),
              );
            }
          }
        }
      }
    }
    setState(() {

      if (mode == _MinMaxMode.minOnly) {
        _points.removeWhere((p) => p.type == ExtremaPointType.minimum);
      } else {
        _points.removeWhere((p) => p.type == ExtremaPointType.maximum);
      }
      _points.addAll(newPoints);
      final mins = _points
          .where((p) => p.type == ExtremaPointType.minimum)
          .toList();
      final maxs = _points
          .where((p) => p.type == ExtremaPointType.maximum)
          .toList();
      final parts = <String>[];
      if (mins.isNotEmpty) parts.add('Min: ${mins.length} point(s)');
      if (maxs.isNotEmpty) parts.add('Max: ${maxs.length} point(s)');
      _message = parts.isEmpty
          ? (mode == _MinMaxMode.minOnly
                ? 'No minimum found'
                : 'No maximum found')
          : parts.join('  |  ');
    });
  }

  void _findSaddles3D() {
    final xMin = double.tryParse(_xMinCtrl.text) ?? -5;
    final xMax = double.tryParse(_xMaxCtrl.text) ?? 5;
    final yMin = double.tryParse(_yMinCtrl.text) ?? -5;
    final yMax = double.tryParse(_yMaxCtrl.text) ?? 5;
    if (xMin >= xMax || yMin >= yMax) {
      setState(() {
        _message = 'Invalid range';
        _points.removeWhere((p) => p.type == ExtremaPointType.saddle);
      });
      return;
    }
    final xRange = (xMax - xMin).abs().clamp(0.1, 1e6);
    final yRange = (yMax - yMin).abs().clamp(0.1, 1e6);
    final h = _h3D(xRange, yRange);
    const n = 50;
    final dx = (xMax - xMin) / n;
    final dy = (yMax - yMin) / n;
    final scale = math.max(xRange, yRange).clamp(0.1, 1e6);
    final critTol =
        scale * 1e-3;
    final newPoints = <ExtremaPoint>[];
    for (int i = 1; i < n; i++) {
      for (int j = 1; j < n; j++) {
        final x = xMin + dx * i;
        final y = yMin + dy * j;
        final fx = _eval3D_fx(x, y, h);
        final fy = _eval3D_fy(x, y, h);
        if (fx == null || fy == null) continue;
        if (fx.abs() > critTol || fy.abs() > critTol) continue;
        final det = _eval3D_hessianDet(x, y, h);
        if (det == null || det >= 0) continue;
        if (newPoints.any(
          (p) =>
              (p.x - x).abs() < dx * 1.5 && ((p.y ?? 0) - y).abs() < dy * 1.5,
        )) {
          continue;
        }
        try {
          final z = _eval3D(x, y);
          if (z.isFinite) {
            newPoints.add(
              ExtremaPoint(type: ExtremaPointType.saddle, x: x, y: y, z: z),
            );
          }
        } catch (_) {}
      }
    }
    setState(() {
      _points.removeWhere((p) => p.type == ExtremaPointType.saddle);
      _points.addAll(newPoints);
      final saddles = _points
          .where((p) => p.type == ExtremaPointType.saddle)
          .toList();
      final parts = <String>[];
      final mins = _points
          .where((p) => p.type == ExtremaPointType.minimum)
          .toList();
      final maxs = _points
          .where((p) => p.type == ExtremaPointType.maximum)
          .toList();
      if (mins.isNotEmpty) parts.add('Min: ${mins.length} pt(s)');
      if (maxs.isNotEmpty) parts.add('Max: ${maxs.length} pt(s)');
      if (saddles.isNotEmpty) parts.add('Saddle: ${saddles.length} pt(s)');
      _message = parts.isEmpty
          ? 'No saddle points found in range'
          : parts.join('  |  ');
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useSideBySide = constraints.maxWidth > 800;

        final capturableContent = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: _dimension == 2 ? _build2DGraph() : _build3DGraph(),
            ),
            _buildLegendBar(),
          ],
        );

        final graphWithOverlay = Stack(
          clipBehavior: Clip.none,
          children: [
            if (widget.repaintBoundaryKey != null)
              RepaintBoundary(
                key: widget.repaintBoundaryKey,
                child: capturableContent,
              )
            else
              capturableContent,
            Positioned(
              top: 12,
              right: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.repaintBoundaryKey != null &&
                      widget.onCaptureRequested != null)
                    IconButton(
                      icon: const Icon(Icons.camera_alt),
                      tooltip: 'Save graph with legend',
                      onPressed: widget.onCaptureRequested,
                    ),
                  IconButton(
                    icon: Icon(_showLabels ? Icons.numbers : Icons.label_off),
                    tooltip: _showLabels ? 'Hide labels' : 'Show labels',
                    onPressed: () => setState(() => _showLabels = !_showLabels),
                  ),
                  IconButton(
                    icon: Icon(_showGrid ? Icons.grid_on : Icons.grid_off),
                    tooltip: _showGrid ? 'Hide grid' : 'Show grid',
                    onPressed: () => setState(() => _showGrid = !_showGrid),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'Zoom in',
                    onPressed: () => setState(() {
                      if (_dimension == 2)
                        _zoom2D *= 1.2;
                      else
                        _zoom3D *= 1.2;
                    }),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove),
                    tooltip: 'Zoom out',
                    onPressed: () => setState(() {
                      if (_dimension == 2)
                        _zoom2D /= 1.2;
                      else
                        _zoom3D /= 1.2;
                    }),
                  ),
                  IconButton(
                    icon: const Icon(Icons.center_focus_strong),
                    tooltip: 'Center view at origin',
                    onPressed: () => setState(_centerViewAtOrigin),
                  ),
                ],
              ),
            ),
          ],
        );

        final graphPart = Expanded(
          flex: useSideBySide ? 6 : 5,
          child: graphWithOverlay,
        );

        final panelPart = Expanded(
          flex: useSideBySide ? 4 : 5,
          child: Container(

            decoration: BoxDecoration(
              color: widget.colorScheme.surfaceContainerLow,
              border: Border(
                left: useSideBySide
                    ? BorderSide(
                        color: widget.colorScheme.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      )
                    : BorderSide.none,
                top: useSideBySide
                    ? BorderSide.none
                    : BorderSide(
                        color: widget.colorScheme.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 2, label: Text('2D f(x)')),
                      ButtonSegment(value: 3, label: Text('3D f(x,y)')),
                    ],
                    selected: {_dimension},
                    onSelectionChanged: (s) {
                      final next = s.first;
                      if (next != _dimension) {
                        setState(() {
                          _dimension = next;
                          _points.clear();
                          _message = '';
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _exprCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Function',
                      hintText: 'e.g. x^2 - 2*x - 3 or sin(x)*cos(y)',
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _xMinCtrl,
                          decoration: const InputDecoration(
                            labelText: 'xMin',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _xMaxCtrl,
                          decoration: const InputDecoration(
                            labelText: 'xMax',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_dimension == 3) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _yMinCtrl,
                            decoration: const InputDecoration(
                              labelText: 'yMin',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _yMaxCtrl,
                            decoration: const InputDecoration(
                              labelText: 'yMax',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_dimension == 2)
                        FilledButton.icon(
                          icon: const Icon(Icons.functions),
                          label: const Text('Find roots'),
                          onPressed: _findRoots,
                        ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.arrow_downward),
                        label: const Text('Find min'),
                        onPressed: () => _findMinMax(mode: _MinMaxMode.minOnly),
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.arrow_upward),
                        label: const Text('Find max'),
                        onPressed: () => _findMinMax(mode: _MinMaxMode.maxOnly),
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.aspect_ratio),
                        label: const Text('Show asymptotes'),
                        onPressed: _findAsymptotes,
                      ),
                      if (_dimension == 3)
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.gradient),
                          label: const Text('Find saddle'),
                          onPressed: _findSaddles3D,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_message.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: widget.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _message,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: widget.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  if (_points.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Marked points (${_points.length})',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    ..._points.map((p) {
                      final label = p.type == ExtremaPointType.root
                          ? 'Root x=${p.x.toStringAsFixed(4)}'
                          : p.type == ExtremaPointType.minimum
                          ? 'Min: ${p.z?.toStringAsFixed(4) ?? p.y?.toStringAsFixed(4)} at (${p.x.toStringAsFixed(3)}${p.y != null ? ", ${p.y!.toStringAsFixed(3)}" : ""})'
                          : p.type == ExtremaPointType.maximum
                          ? 'Max: ${p.z?.toStringAsFixed(4) ?? p.y?.toStringAsFixed(4)} at (${p.x.toStringAsFixed(3)}${p.y != null ? ", ${p.y!.toStringAsFixed(3)}" : ""})'
                          : p.type == ExtremaPointType.saddle
                          ? 'Saddle: ${p.z?.toStringAsFixed(4) ?? "—"} at (${p.x.toStringAsFixed(3)}, ${(p.y ?? 0).toStringAsFixed(3)})'
                          : _dimension == 2
                          ? 'Asymptote x=${p.x.toStringAsFixed(4)}'
                          : 'Asymptote (${p.x.toStringAsFixed(3)}, ${(p.y ?? 0).toStringAsFixed(3)})';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
        );

        if (useSideBySide) {
          return Row(

            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [graphPart, panelPart],
          );
        }
        return Column(

          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [graphPart, panelPart],
        );
      },
    );
  }

  Widget _build2DGraph() {
    final xMin = double.tryParse(_xMinCtrl.text) ?? -5;
    final xMax = double.tryParse(_xMaxCtrl.text) ?? 5;
    return CustomPaint(
      painter: _Extrema2DPainter(
        expression: _exprCtrl.text,
        xMin: xMin,
        xMax: xMax,
        points: _points,
        offsetX: _offsetX,
        offsetY: _offsetY,
        zoom2D: _zoom2D,
        isDarkMode: widget.isDark,
        showLabels: widget.forCapture ? false : _showLabels,
        showGrid: widget.forCapture ? false : _showGrid,
        accentColor: widget.colorScheme.primary,
      ),
      child: GestureDetector(
        onScaleUpdate: (d) {
          setState(() {
            if (d.scale != 1.0) _zoom2D = (_zoom2D * d.scale).clamp(5.0, 400.0);
            _offsetX += d.focalPointDelta.dx;
            _offsetY += d.focalPointDelta.dy;
          });
        },
      ),
    );
  }

  Widget _buildLegendBar() {
    final roots = _points
        .where((p) => p.type == ExtremaPointType.root)
        .toList();
    final mins = _points
        .where((p) => p.type == ExtremaPointType.minimum)
        .toList();
    final maxs = _points
        .where((p) => p.type == ExtremaPointType.maximum)
        .toList();
    final asym = _points
        .where((p) => p.type == ExtremaPointType.asymptote)
        .toList();
    final saddles = _points
        .where((p) => p.type == ExtremaPointType.saddle)
        .toList();
    if (roots.isEmpty &&
        mins.isEmpty &&
        maxs.isEmpty &&
        asym.isEmpty &&
        saddles.isEmpty) {
      return const SizedBox.shrink();
    }
    final parts = <String>[];
    if (roots.isNotEmpty) {
      parts.add(
        'Roots: ${roots.map((p) => p.x.toStringAsFixed(3)).join(', ')}',
      );
    }
    if (mins.isNotEmpty) {
      for (final p in mins) {
        if (_dimension == 2) {
          parts.add(
            'Min: ${p.y?.toStringAsFixed(3) ?? "—"} at x=${p.x.toStringAsFixed(3)}',
          );
        } else {
          parts.add(
            'Min: ${p.z?.toStringAsFixed(3) ?? "—"} at (${p.x.toStringAsFixed(2)}, ${p.y?.toStringAsFixed(2)})',
          );
        }
      }
    }
    if (maxs.isNotEmpty) {
      for (final p in maxs) {
        if (_dimension == 2) {
          parts.add(
            'Max: ${p.y?.toStringAsFixed(3) ?? "—"} at x=${p.x.toStringAsFixed(3)}',
          );
        } else {
          parts.add(
            'Max: ${p.z?.toStringAsFixed(3) ?? "—"} at (${p.x.toStringAsFixed(2)}, ${p.y?.toStringAsFixed(2)})',
          );
        }
      }
    }
    if (asym.isNotEmpty) {
      if (_dimension == 2) {
        parts.add(
          'Asymptotes: x=${asym.map((p) => p.x.toStringAsFixed(3)).join(', ')}',
        );
      } else {
        parts.add('Asymptotes: ${asym.length} pole(s)');
      }
    }
    if (saddles.isNotEmpty) {
      parts.add(
        'Saddle: ${saddles.map((p) => '(${p.x.toStringAsFixed(2)}, ${(p.y ?? 0).toStringAsFixed(2)})').join(', ')}',
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: widget.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: widget.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              parts.join('  |  '),
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: widget.colorScheme.onSurface,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _build3DGraph() {
    final xMin = double.tryParse(_xMinCtrl.text) ?? -5;
    final xMax = double.tryParse(_xMaxCtrl.text) ?? 5;
    final yMin = double.tryParse(_yMinCtrl.text) ?? -5;
    final yMax = double.tryParse(_yMaxCtrl.text) ?? 5;
    return CustomPaint(
      painter: _Extrema3DPainter(
        expression: _exprCtrl.text,
        xMin: xMin,
        xMax: xMax,
        yMin: yMin,
        yMax: yMax,
        points: _points,
        yaw: _yaw3D,
        pitch: _pitch3D,
        zoom: _zoom3D,
        isDarkMode: widget.isDark,
        showLabels: widget.forCapture ? false : _showLabels,
        showGrid: widget.forCapture ? false : _showGrid,
      ),
      child: GestureDetector(
        onScaleUpdate: (d) {
          setState(() {
            if (d.scale == 1.0) {
              _yaw3D -= d.focalPointDelta.dx * 0.5;
              _pitch3D += d.focalPointDelta.dy * 0.5;
            } else {
              _zoom3D = (_zoom3D * d.scale).clamp(0.3, 10.0);
            }
          });
        },
      ),
    );
  }
}

class _Extrema2DPainter extends CustomPainter {
  _Extrema2DPainter({
    required this.expression,
    required this.xMin,
    required this.xMax,
    required this.points,
    required this.offsetX,
    required this.offsetY,
    required this.zoom2D,
    required this.isDarkMode,
    required this.showLabels,
    required this.showGrid,
    required this.accentColor,
  });

  final String expression;
  final double xMin;
  final double xMax;
  final List<ExtremaPoint> points;
  final double offsetX;
  final double offsetY;
  final double zoom2D;
  final bool isDarkMode;
  final bool showLabels;
  final bool showGrid;
  final Color accentColor;

  static final _parser = ComplexParser();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2 + offsetX;
    final cy = size.height / 2 + offsetY;

    final bg = Paint()
      ..color = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bg);

    final gridPaint = Paint()
      ..color = isDarkMode
          ? Colors.white10
          : Colors.black.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = isDarkMode ? Colors.white38 : Colors.black38
      ..strokeWidth = 1.5;

    if (showGrid) {
      final stepUnit = MathGrid.calculateStepSize(80.0, zoom2D);
      final stepPx = stepUnit * zoom2D;
      final startXi = (-cx / stepPx).floor();
      final endXi = ((size.width - cx) / stepPx).ceil();
      for (int i = startXi; i <= endXi; i++) {
        final x = cx + i * stepPx;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      }
      final startYi = (-cy / stepPx).floor();
      final endYi = ((size.height - cy) / stepPx).ceil();
      for (int i = startYi; i <= endYi; i++) {
        final y = cy + i * stepPx;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
    }

    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), axisPaint);
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), axisPaint);

    if (showLabels) {
      final stepUnit = MathGrid.calculateStepSize(80.0, zoom2D);
      final stepPx = stepUnit * zoom2D;
      final textStyle = TextStyle(
        color: isDarkMode ? Colors.white54 : Colors.black54,
        fontSize: 10,
      );
      final startXi = (-cx / stepPx).floor();
      final endXi = ((size.width - cx) / stepPx).ceil();
      for (int i = startXi; i <= endXi; i++) {
        final x = cx + i * stepPx;
        final val = i * stepUnit;
        if (val != 0) {
          final tp = TextPainter(
            text: TextSpan(
              text: MathFormatter.formatAxisLabel(val, precision: 1),
              style: textStyle,
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(x - tp.width / 2, cy + 4));
        }
      }
      final startYi = (-cy / stepPx).floor();
      final endYi = ((size.height - cy) / stepPx).ceil();
      for (int i = startYi; i <= endYi; i++) {
        final y = cy + i * stepPx;
        final val = -i * stepUnit;
        if (val != 0) {
          final tp = TextPainter(
            text: TextSpan(
              text: MathFormatter.formatAxisLabel(val, precision: 1),
              style: textStyle,
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(cx - tp.width - 4, y - tp.height / 2));
        }
      }
      final tp0 = TextPainter(
        text: TextSpan(text: '0', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp0.paint(canvas, Offset(cx - tp0.width - 2, cy + 2));
    }

    final expr = expression.replaceAll('×', '*').replaceAll('√', 'sqrt');
    final path = Path();
    bool first = true;
    const step = 2.0;
    for (double xPx = 0; xPx <= size.width; xPx += step) {
      final xVal = (xPx - cx) / zoom2D;
      try {
        final r = _parser.evaluate(expr, variables: {'x': Complex(xVal)});
        final yVal = r.real;
        if (yVal.isFinite) {
          final yPx = cy - yVal * zoom2D;
          if (yPx >= -size.height * 2 && yPx <= size.height * 2) {
            if (first) {
              path.moveTo(xPx, yPx);
              first = false;
            } else {
              path.lineTo(xPx, yPx);
            }
          } else {
            first = true;
          }
        } else {
          first = true;
        }
      } catch (_) {
        first = true;
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = accentColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    final dashPaint = Paint()
      ..color = isDarkMode ? Colors.amberAccent : Colors.deepOrange
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final asymptotePaint = Paint()
      ..color = isDarkMode ? Colors.purpleAccent : Colors.purple
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final p in points) {
      final xPx = cx + p.x * zoom2D;
      if (xPx < 0 || xPx > size.width) continue;

      if (p.type == ExtremaPointType.asymptote) {
        _drawDashedVertical(canvas, xPx, size.height, asymptotePaint);
        continue;
      }

      _drawDashedVertical(canvas, xPx, size.height, dashPaint);

      if (p.y != null) {
        final yPx = cy - p.y! * zoom2D;
        if (yPx >= 0 && yPx <= size.height) {
          _drawDashedHorizontal(canvas, yPx, size.width, dashPaint);
          canvas.drawCircle(
            Offset(xPx, yPx),
            5,
            Paint()..color = dashPaint.color,
          );
        }
      } else {
        try {
          final r = _parser.evaluate(expr, variables: {'x': Complex(p.x)});
          final yPx = cy - r.real * zoom2D;
          if (yPx >= 0 && yPx <= size.height) {
            _drawDashedHorizontal(canvas, yPx, size.width, dashPaint);
            canvas.drawCircle(
              Offset(xPx, yPx),
              5,
              Paint()..color = dashPaint.color,
            );
          }
        } catch (_) {}
      }
    }
  }

  void _drawDashedVertical(
    Canvas canvas,
    double x,
    double height,
    Paint paint,
  ) {
    const dash = 6.0;
    double y = 0;
    while (y < height) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, (y + dash).clamp(0, height)),
        paint,
      );
      y += dash * 2;
    }
  }

  void _drawDashedHorizontal(
    Canvas canvas,
    double y,
    double width,
    Paint paint,
  ) {
    const dash = 6.0;
    double x = 0;
    while (x < width) {
      canvas.drawLine(
        Offset(x, y),
        Offset((x + dash).clamp(0, width), y),
        paint,
      );
      x += dash * 2;
    }
  }

  @override
  bool shouldRepaint(covariant _Extrema2DPainter old) =>
      old.expression != expression ||
      old.xMin != xMin ||
      old.xMax != xMax ||
      old.points != points ||
      old.offsetX != offsetX ||
      old.offsetY != offsetY ||
      old.zoom2D != zoom2D ||
      old.showLabels != showLabels ||
      old.showGrid != showGrid;
}

class _Extrema3DPainter extends CustomPainter {
  _Extrema3DPainter({
    required this.expression,
    required this.xMin,
    required this.xMax,
    required this.yMin,
    required this.yMax,
    required this.points,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.isDarkMode,
    required this.showLabels,
    required this.showGrid,
  });

  final String expression;
  final double xMin, xMax, yMin, yMax;
  final List<ExtremaPoint> points;
  final double yaw, pitch, zoom;
  final bool isDarkMode, showLabels, showGrid;

  static final _parser = ComplexParser();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final scale = 15.0 * zoom;
    final radYaw = yaw * math.pi / 180;
    final radPitch = (pitch - 90) * math.pi / 180;
    final cz = math.cos(radYaw);
    final sz = math.sin(radYaw);
    final cp = math.cos(radPitch);
    final sp = math.sin(radPitch);
    final r00 = cz;
    final r01 = -sz;
    final r10 = cp * sz;
    final r11 = cp * cz;
    final r12 = -sp;

    final bg = Paint()
      ..color = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bg);

    Offset proj(double x, double y, double z) {
      final rx = r00 * x + r01 * y;
      final ry = r10 * x + r11 * y + r12 * z;
      return Offset(cx + rx * scale, cy - ry * scale);
    }

    final axisPaint = Paint()..strokeWidth = 1.5;
    axisPaint.color = Colors.red.withValues(alpha: showGrid ? 0.7 : 0.5);
    canvas.drawLine(proj(xMin, 0, 0), proj(xMax, 0, 0), axisPaint);
    axisPaint.color = Colors.green.withValues(alpha: showGrid ? 0.7 : 0.5);
    canvas.drawLine(proj(0, yMin, 0), proj(0, yMax, 0), axisPaint);
    axisPaint.color = Colors.blue.withValues(alpha: showGrid ? 0.7 : 0.5);
    final zScale = (xMax - xMin).abs().clamp(1.0, 20.0);
    canvas.drawLine(proj(0, 0, -zScale), proj(0, 0, zScale), axisPaint);

    if (showGrid) {
      final gridPaint = Paint()
        ..color = isDarkMode ? Colors.white12 : Colors.black26
        ..strokeWidth = 1;
      const gridN = 8;
      for (int i = 1; i < gridN; i++) {
        final x = xMin + (xMax - xMin) * i / gridN;
        canvas.drawLine(proj(x, yMin, 0), proj(x, yMax, 0), gridPaint);
        final y = yMin + (yMax - yMin) * i / gridN;
        canvas.drawLine(proj(xMin, y, 0), proj(xMax, y, 0), gridPaint);
      }
    }

    if (showLabels) {
      final textStyle = TextStyle(
        color: isDarkMode ? Colors.white70 : Colors.black87,
        fontSize: 11,
      );
      void drawLabel(String text, double x, double y, double z) {
        final o = proj(x, y, z);
        if (o.dx < 0 || o.dx > size.width || o.dy < 0 || o.dy > size.height)
          return;
        final tp = TextPainter(
          text: TextSpan(text: text, style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(o.dx - tp.width / 2, o.dy - tp.height / 2));
      }

      drawLabel('X', xMax + (xMax - xMin) * 0.05, 0, 0);
      drawLabel('Y', 0, yMax + (yMax - yMin) * 0.05, 0);
      drawLabel('Z', 0, 0, zScale + 0.5);
      final stepX = (xMax - xMin) / 6;
      final stepY = (yMax - yMin) / 6;
      for (int i = 1; i < 6; i++) {
        drawLabel(
          MathFormatter.formatAxisLabel(xMin + stepX * i, precision: 1),
          xMin + stepX * i,
          0,
          0,
        );
        drawLabel(
          MathFormatter.formatAxisLabel(yMin + stepY * i, precision: 1),
          0,
          yMin + stepY * i,
          0,
        );
      }
    }

    final expr = expression.replaceAll('×', '*').replaceAll('√', 'sqrt');
    const gridN = 40;
    final dx = (xMax - xMin) / gridN;
    final dy = (yMax - yMin) / gridN;
    final pathColor = isDarkMode ? Colors.cyanAccent : Colors.blue;
    final pathPaint = Paint()
      ..color = pathColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < gridN; i++) {
      for (int j = 0; j < gridN; j++) {
        final x1 = xMin + i * dx;
        final y1 = yMin + j * dy;
        final x2 = xMin + (i + 1) * dx;
        final y2 = yMin + (j + 1) * dy;
        try {
          final z1 = _parser
              .evaluate(expr, variables: {'x': Complex(x1), 'y': Complex(y1)})
              .real;
          final z2 = _parser
              .evaluate(expr, variables: {'x': Complex(x2), 'y': Complex(y1)})
              .real;
          final z3 = _parser
              .evaluate(expr, variables: {'x': Complex(x2), 'y': Complex(y2)})
              .real;
          final z4 = _parser
              .evaluate(expr, variables: {'x': Complex(x1), 'y': Complex(y2)})
              .real;
          if (z1.isFinite && z2.isFinite && z3.isFinite && z4.isFinite) {
            canvas.drawLine(proj(x1, y1, z1), proj(x2, y1, z2), pathPaint);
            canvas.drawLine(proj(x2, y1, z2), proj(x2, y2, z3), pathPaint);
            canvas.drawLine(proj(x2, y2, z3), proj(x1, y2, z4), pathPaint);
            canvas.drawLine(proj(x1, y2, z4), proj(x1, y1, z1), pathPaint);
          }
        } catch (_) {}
      }
    }

    final dashColor = isDarkMode ? Colors.amberAccent : Colors.deepOrange;
    final dashPaint = Paint()
      ..color = dashColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final asymptoteColor = isDarkMode ? Colors.purpleAccent : Colors.purple;
    final asymptotePaint = Paint()
      ..color = asymptoteColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    void drawDashedLineWith(Offset a, Offset b, Paint paint) {
      const dash = 5.0;
      final dx = b.dx - a.dx;
      final dy = b.dy - a.dy;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 1) return;
      final n = (len / (dash * 2)).floor();
      final step = len / (n * 2 + 1);
      for (int i = 0; i <= n; i++) {
        final t = (i * 2) * step / len;
        final t2 = ((i * 2 + 1) * step / len).clamp(0.0, 1.0);
        canvas.drawLine(
          Offset(a.dx + dx * t, a.dy + dy * t),
          Offset(a.dx + dx * t2, a.dy + dy * t2),
          paint,
        );
      }
    }

    final saddleColor = isDarkMode ? Colors.tealAccent : Colors.teal;
    final saddlePaint = Paint()
      ..color = saddleColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final p in points) {
      if (p.type == ExtremaPointType.asymptote) {
        final px = p.x;
        final py = p.y ?? 0;
        if (!px.isFinite || !py.isFinite) continue;
        final ptBase = proj(px, py, 0);
        final zMax = zScale * 1.5;
        final ptTop = proj(px, py, zMax);
        drawDashedLineWith(ptBase, ptTop, asymptotePaint);
        canvas.drawCircle(ptBase, 5, Paint()..color = asymptoteColor);
        continue;
      }
      if (p.type == ExtremaPointType.saddle) {
        final px = p.x;
        final py = p.y ?? 0;
        final pz = p.z ?? 0;
        if (!px.isFinite || !py.isFinite || !pz.isFinite) continue;
        final ptTop = proj(px, py, pz);
        final ptBase = proj(px, py, 0);
        drawDashedLineWith(ptTop, ptBase, saddlePaint);
        canvas.drawCircle(ptTop, 6, Paint()..color = saddleColor);
        continue;
      }
      if (p.x.isFinite && (p.y ?? 0).isFinite && (p.z ?? 0).isFinite) {
        final px = p.x;
        final py = p.y ?? 0;
        final pz = p.z ?? 0;
        final ptTop = proj(px, py, pz);
        final ptBase = proj(px, py, 0);
        drawDashedLineWith(ptTop, ptBase, dashPaint);
        canvas.drawCircle(ptTop, 6, Paint()..color = dashColor);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Extrema3DPainter old) =>
      old.expression != expression ||
      old.points != points ||
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.zoom != zoom ||
      old.showLabels != showLabels ||
      old.showGrid != showGrid;
}
