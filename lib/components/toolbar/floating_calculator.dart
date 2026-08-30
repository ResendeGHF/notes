// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';

import 'package:saber/components/toolbar/2Dplot.dart';
import 'package:saber/components/toolbar/3Dplot.dart';
import 'package:saber/components/toolbar/3Dscalar.dart';
import 'package:saber/components/toolbar/3Dvector.dart';
import 'package:saber/components/toolbar/calculus_pane.dart';
import 'package:saber/components/toolbar/extrema_pane.dart';
import 'package:saber/components/toolbar/ode_isolate.dart';
import 'package:saber/components/toolbar/ode_visualizer.dart';
import 'package:saber/components/toolbar/plot_animation_metadata.dart';
import 'package:saber/components/toolbar/plot_input_parser.dart';
import 'package:saber/components/toolbar/unit_converter.dart';
import 'package:saber/services/math_engine/math_engine.dart';

typedef OnInsertImage =
    void Function(
      Uint8List imageBytes, {
      String? assetFileInfo,
      bool invertible,
    });

class FunctionDef {
  TextEditingController controller;
  Color color;
  bool enabled;
  bool fillArea;
  TextEditingController tMinCtrl;
  TextEditingController tMaxCtrl;
  TextEditingController tDurationCtrl;
  TextEditingController dMinXCtrl;
  TextEditingController dMaxXCtrl;
  TextEditingController dMinYCtrl;
  TextEditingController dMaxYCtrl;
  TextEditingController dMinZCtrl;
  TextEditingController dMaxZCtrl;
  CoordSystem2D coord2D;
  CoordSystem3D coord3D;

  FunctionDef({
    this.coord2D = CoordSystem2D.cartesian,
    this.coord3D = CoordSystem3D.cartesian,
    required String initialText,
    required this.color,
    this.enabled = true,
    this.fillArea = false,
    String tMin = '',
    String tMax = '',
    String durationMs = '6000',
    String dMinX = '',
    String dMaxX = '',
    String dMinY = '',
    String dMaxY = '',
    String dMinZ = '',
    String dMaxZ = '',
  }) : controller = TextEditingController(text: initialText),
       tMinCtrl = TextEditingController(text: tMin),
       tMaxCtrl = TextEditingController(text: tMax),
       tDurationCtrl = TextEditingController(text: durationMs),
       dMinXCtrl = TextEditingController(text: dMinX),
       dMaxXCtrl = TextEditingController(text: dMaxX),
       dMinYCtrl = TextEditingController(text: dMinY),
       dMaxYCtrl = TextEditingController(text: dMaxY),
       dMinZCtrl = TextEditingController(text: dMinZ),
       dMaxZCtrl = TextEditingController(text: dMaxZ);

  bool get hasTimeAnimation {
    final parser = ComplexParser();
    final tMin = parsePlotRealExpression(parser, tMinCtrl.text);
    final tMax = parsePlotRealExpression(parser, tMaxCtrl.text);
    final duration = int.tryParse(tDurationCtrl.text);
    return tMin != null && tMax != null && tMax > tMin && (duration ?? 0) > 0;
  }

  void dispose() {
    controller.dispose();
    tMinCtrl.dispose();
    tMaxCtrl.dispose();
    tDurationCtrl.dispose();
    dMinXCtrl.dispose();
    dMaxXCtrl.dispose();
    dMinYCtrl.dispose();
    dMaxYCtrl.dispose();
    dMinZCtrl.dispose();
    dMaxZCtrl.dispose();
  }
}

class ScalarFuncDef {
  TextEditingController xCtrl, yCtrl, zCtrl, fCtrl;
  TextEditingController tMinCtrl, tMaxCtrl, tDurationCtrl;
  TextEditingController dMinXCtrl, dMaxXCtrl;
  TextEditingController dMinYCtrl, dMaxYCtrl;
  TextEditingController dMinZCtrl, dMaxZCtrl;
  bool enabled;
  CoordSystem3D coord3D;

  ScalarFuncDef({
    this.coord3D = CoordSystem3D.cartesian,
    this.enabled = true,
    String x = '',
    String y = '',
    String z = '',
    String f = '',
    String tMin = '',
    String tMax = '',
    String durationMs = '6000',
    String dMinX = '',
    String dMaxX = '',
    String dMinY = '',
    String dMaxY = '',
    String dMinZ = '',
    String dMaxZ = '',
  }) : xCtrl = TextEditingController(text: x),
       yCtrl = TextEditingController(text: y),
       zCtrl = TextEditingController(text: z),
       fCtrl = TextEditingController(text: f),
       tMinCtrl = TextEditingController(text: tMin),
       tMaxCtrl = TextEditingController(text: tMax),
       tDurationCtrl = TextEditingController(text: durationMs),
       dMinXCtrl = TextEditingController(text: dMinX),
       dMaxXCtrl = TextEditingController(text: dMaxX),
       dMinYCtrl = TextEditingController(text: dMinY),
       dMaxYCtrl = TextEditingController(text: dMaxY),
       dMinZCtrl = TextEditingController(text: dMinZ),
       dMaxZCtrl = TextEditingController(text: dMaxZ);

  void dispose() {
    xCtrl.dispose();
    yCtrl.dispose();
    zCtrl.dispose();
    fCtrl.dispose();
    tMinCtrl.dispose();
    tMaxCtrl.dispose();
    tDurationCtrl.dispose();
    dMinXCtrl.dispose();
    dMaxXCtrl.dispose();
    dMinYCtrl.dispose();
    dMaxYCtrl.dispose();
    dMinZCtrl.dispose();
    dMaxZCtrl.dispose();
  }

  bool get hasTimeAnimation {
    final parser = ComplexParser();
    final tMin = parsePlotRealExpression(parser, tMinCtrl.text);
    final tMax = parsePlotRealExpression(parser, tMaxCtrl.text);
    final duration = int.tryParse(tDurationCtrl.text);
    return tMin != null && tMax != null && tMax > tMin && (duration ?? 0) > 0;
  }
}

class VectorFuncDef {
  TextEditingController xCtrl, yCtrl, zCtrl;
  TextEditingController pCtrl, qCtrl, rCtrl;
  TextEditingController tMinCtrl, tMaxCtrl, tDurationCtrl;
  TextEditingController dMinXCtrl, dMaxXCtrl;
  TextEditingController dMinYCtrl, dMaxYCtrl;
  TextEditingController dMinZCtrl, dMaxZCtrl;
  bool enabled;
  CoordSystem3D coord3D;

  VectorFuncDef({
    this.coord3D = CoordSystem3D.cartesian,
    this.enabled = true,
    String x = '',
    String y = '',
    String z = '',
    String p = '',
    String q = '',
    String r = '',
    String tMin = '',
    String tMax = '',
    String durationMs = '6000',
    String dMinX = '',
    String dMaxX = '',
    String dMinY = '',
    String dMaxY = '',
    String dMinZ = '',
    String dMaxZ = '',
  }) : xCtrl = TextEditingController(text: x),
       yCtrl = TextEditingController(text: y),
       zCtrl = TextEditingController(text: z),
       pCtrl = TextEditingController(text: p),
       qCtrl = TextEditingController(text: q),
       rCtrl = TextEditingController(text: r),
       tMinCtrl = TextEditingController(text: tMin),
       tMaxCtrl = TextEditingController(text: tMax),
       tDurationCtrl = TextEditingController(text: durationMs),
       dMinXCtrl = TextEditingController(text: dMinX),
       dMaxXCtrl = TextEditingController(text: dMaxX),
       dMinYCtrl = TextEditingController(text: dMinY),
       dMaxYCtrl = TextEditingController(text: dMaxY),
       dMinZCtrl = TextEditingController(text: dMinZ),
       dMaxZCtrl = TextEditingController(text: dMaxZ);

  void dispose() {
    xCtrl.dispose();
    yCtrl.dispose();
    zCtrl.dispose();
    pCtrl.dispose();
    qCtrl.dispose();
    rCtrl.dispose();
    tMinCtrl.dispose();
    tMaxCtrl.dispose();
    tDurationCtrl.dispose();
    dMinXCtrl.dispose();
    dMaxXCtrl.dispose();
    dMinYCtrl.dispose();
    dMaxYCtrl.dispose();
    dMinZCtrl.dispose();
    dMaxZCtrl.dispose();
  }

  bool get hasTimeAnimation {
    final parser = ComplexParser();
    final tMin = parsePlotRealExpression(parser, tMinCtrl.text);
    final tMax = parsePlotRealExpression(parser, tMaxCtrl.text);
    final duration = int.tryParse(tDurationCtrl.text);
    return tMin != null && tMax != null && tMax > tMin && (duration ?? 0) > 0;
  }
}

enum OdeIntegrationMethod {
  euler,
  eulerCromer,
  verlet,
  rungeKutta4,
  forestRuth,
}

extension OdeIntegrationMethodLabel on OdeIntegrationMethod {
  String get label {
    switch (this) {
      case OdeIntegrationMethod.euler:
        return 'Euler';
      case OdeIntegrationMethod.eulerCromer:
        return 'Euler-Cromer';
      case OdeIntegrationMethod.verlet:
        return 'Verlet';
      case OdeIntegrationMethod.rungeKutta4:
        return 'Runge-Kutta 4';
      case OdeIntegrationMethod.forestRuth:
        return 'Forest-Ruth';
    }
  }
}

class OdePresetConfig {
  const OdePresetConfig({
    required this.id,
    required this.label,
    required this.dimension,
    required this.method,
    required this.dx,
    required this.dy,
    required this.dz,
    required this.x0,
    required this.y0,
    required this.z0,
    required this.t0,
    required this.step,
    required this.tolerance,
  });

  final String id;
  final String label;
  final int dimension;
  final OdeIntegrationMethod method;
  final String dx;
  final String dy;
  final String dz;
  final String x0;
  final String y0;
  final String z0;
  final String t0;
  final String step;
  final String tolerance;
}

class _CalcCache {
  static BuildContext? sessionContext;
  static String expression = '';
  static String result = '';
  static Complex? lastAnswer;

  static List<FunctionDef>? plotFunctions2D;
  static List<FunctionDef>? plotFunctions3D;
  static List<ScalarFuncDef>? scalarFunctions;
  static List<VectorFuncDef>? vectorFunctions;

  static void reset() {
    plotFunctions2D?.forEach((f) => f.dispose());
    plotFunctions3D?.forEach((f) => f.dispose());
    scalarFunctions?.forEach((f) => f.dispose());
    vectorFunctions?.forEach((f) => f.dispose());

    plotFunctions2D = null;
    plotFunctions3D = null;
    scalarFunctions = null;
    vectorFunctions = null;

    expression = '';
    result = '';
    lastAnswer = null;
  }
}

class FloatingCalculator extends StatefulWidget {
  const FloatingCalculator({
    super.key,
    required this.onClose,
    required this.onDrag,
    required this.onInsertImage,
    this.visualizerMetadata,
    this.readOnlyVisualizer = false,
    this.initialWorkspaceMetadata,
    this.onWorkspaceMetadataChanged,
    this.menuOverlayContext,
  });

  final VoidCallback onClose;
  final void Function(DragUpdateDetails) onDrag;
  final OnInsertImage onInsertImage;
  final PlotAnimationMetadata? visualizerMetadata;
  final bool readOnlyVisualizer;
  final String? initialWorkspaceMetadata;
  final ValueChanged<String?>? onWorkspaceMetadataChanged;

  final BuildContext? menuOverlayContext;

  @override
  State<FloatingCalculator> createState() => _FloatingCalculatorState();
}

class _FloatingCalculatorState extends State<FloatingCalculator>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _showConverter = false;

  late TextEditingController _expressionCtrl;
  String _result = '';

  Complex? _lastAnswer;
  bool _shouldClear = false;

  bool _isShifted = false;
  bool _isRad = true;
  bool _isComplexMode = false;
  bool _autoRotate3D = false;

  bool _showLabels = true;

  bool _showFunctionMenu = false;

  late List<FunctionDef> _plotFunctions2D;
  late List<FunctionDef> _plotFunctions3D;
  late List<ScalarFuncDef> _scalarFunctions;
  late List<VectorFuncDef> _vectorFunctions;

  var _yaw = 45.0;
  var _pitch = 30.0;
  var _zoom3D = 1.0;
  var _baseZoom3D = 1.0;

  var _center3DX = 0.0;
  var _center3DY = 0.0;
  var _center3DZ = 0.0;

  late TextEditingController _cXCtrl;
  late TextEditingController _cYCtrl;
  late TextEditingController _cZCtrl;

  var _offsetX = 0.0;
  var _offsetY = 0.0;
  var _zoom2D = 40.0;

  final _complexParser = ComplexParser();

  var _odeMethod = OdeIntegrationMethod.verlet;
  var _odeDimension = 2;
  late TextEditingController _odeDxCtrl;
  late TextEditingController _odeDyCtrl;
  late TextEditingController _odeDzCtrl;
  late TextEditingController _odeX0Ctrl;
  late TextEditingController _odeY0Ctrl;
  late TextEditingController _odeZ0Ctrl;
  late TextEditingController _odeT0Ctrl;
  late TextEditingController _odeStepCtrl;
  late TextEditingController _odeToleranceCtrl;
  Timer? _odeTimer;
  Ticker? _odeTicker;
  var _odeComputeInFlight = false;
  final List<OdeSample> _odeSamples = [];
  var _odeRunning = false;
  var _odeConverged = false;
  var _odeStableSteps = 0;
  var _showOdeGrid = true;
  var _odeSelectedPresetId = 'harmonic';
  var _odeStatus = 'Configure equation and press Start';
  static const int _odeStepsPerTick = 2;
  static const int _odeMaxStoredSamples = 8000;
  static const List<OdePresetConfig> _odePresets = [
    OdePresetConfig(
      id: 'harmonic',
      label: 'Harmonic',
      dimension: 2,
      method: OdeIntegrationMethod.verlet,
      dx: 'y',
      dy: '-x',
      dz: '0',
      x0: '1',
      y0: '0',
      z0: '0',
      t0: '0',
      step: '0.02',
      tolerance: '1e-6',
    ),
    OdePresetConfig(
      id: 'lorenz',
      label: 'Lorenz',
      dimension: 3,
      method: OdeIntegrationMethod.rungeKutta4,
      dx: '10*(y-x)',
      dy: 'x*(28-z)-y',
      dz: 'x*y-(8/3)*z',
      x0: '0.1',
      y0: '0',
      z0: '0',
      t0: '0',
      step: '0.005',
      tolerance: '1e-7',
    ),
    OdePresetConfig(
      id: 'lotka_volterra',
      label: 'Lotka-Volterra',
      dimension: 2,
      method: OdeIntegrationMethod.rungeKutta4,
      dx: '1.5*x-1*x*y',
      dy: '-3*y+1*x*y',
      dz: '0',
      x0: '3',
      y0: '2',
      z0: '0',
      t0: '0',
      step: '0.01',
      tolerance: '1e-6',
    ),
    OdePresetConfig(
      id: 'van_der_pol',
      label: 'Van der Pol',
      dimension: 2,
      method: OdeIntegrationMethod.rungeKutta4,
      dx: 'y',
      dy: '1*(1-x^2)*y-x',
      dz: '0',
      x0: '1',
      y0: '0',
      z0: '0',
      t0: '0',
      step: '0.01',
      tolerance: '1e-6',
    ),
  ];

  final GlobalKey _plot3dKey = GlobalKey();
  final GlobalKey _scalarKey = GlobalKey();
  final GlobalKey _vectorKey = GlobalKey();
  final GlobalKey _graphKey = GlobalKey();
  final GlobalKey _odeKey = GlobalKey();
  final GlobalKey _extremaKey = GlobalKey();
  bool _extremaCaptureMode = false;
  final OdeVisualizerController _odeVizController = OdeVisualizerController();
  bool get _isReadOnlyVisualizer => widget.readOnlyVisualizer;
  bool _restoringWorkspaceMetadata = false;
  Map<String, dynamic> _calculusMetadata = const {};
  int _calculusResetNonce = 0;

  @override
  void initState() {
    super.initState();

    if (_CalcCache.sessionContext != widget.menuOverlayContext) {
      _CalcCache.reset();
      _CalcCache.sessionContext = widget.menuOverlayContext;
    }

    _expressionCtrl = TextEditingController(text: _CalcCache.expression);
    _expressionCtrl.addListener(() {
      _CalcCache.expression = _expressionCtrl.text;
    });

    _result = _CalcCache.result;
    _lastAnswer = _CalcCache.lastAnswer;

    if (_CalcCache.plotFunctions2D == null) {
      _CalcCache.plotFunctions2D = [];
      _CalcCache.plotFunctions3D = [];
      _CalcCache.scalarFunctions = [];
      _CalcCache.vectorFunctions = [];
    }

    _plotFunctions2D = _CalcCache.plotFunctions2D!;
    _plotFunctions3D = _CalcCache.plotFunctions3D!;
    _scalarFunctions = _CalcCache.scalarFunctions!;
    _vectorFunctions = _CalcCache.vectorFunctions!;

    _cXCtrl = TextEditingController(text: '0');
    _cYCtrl = TextEditingController(text: '0');
    _cZCtrl = TextEditingController(text: '0');

    _odeDxCtrl = TextEditingController();
    _odeDyCtrl = TextEditingController();
    _odeDzCtrl = TextEditingController();
    _odeX0Ctrl = TextEditingController();
    _odeY0Ctrl = TextEditingController();
    _odeZ0Ctrl = TextEditingController();
    _odeT0Ctrl = TextEditingController();
    _odeStepCtrl = TextEditingController();
    _odeToleranceCtrl = TextEditingController();

    _tabController = TabController(length: 8, vsync: this);
    _tabController.addListener(_onCalculatorTabChanged);
    _loadWorkspaceMetadata(widget.initialWorkspaceMetadata);
    _loadVisualizerMetadata();
  }

  void _onCalculatorTabChanged() {
    if (!mounted) return;
    if (_tabController.index != 5 && _odeRunning) {
      _stopOdeSolver(reason: 'Stopped (switched pane)');

      _odeSamples.clear();
    }
    _markWorkspaceChanged();
  }

  void _closeCalculator() {
    _saveWorkspaceMetadataNow();
    widget.onClose();
  }

  @override
  void dispose() {
    _cXCtrl.dispose();
    _cYCtrl.dispose();
    _cZCtrl.dispose();
    _odeTimer?.cancel();
    _odeTicker?.dispose();
    _odeDxCtrl.dispose();
    _odeDyCtrl.dispose();
    _odeDzCtrl.dispose();
    _odeX0Ctrl.dispose();
    _odeY0Ctrl.dispose();
    _odeZ0Ctrl.dispose();
    _odeT0Ctrl.dispose();
    _odeStepCtrl.dispose();
    _odeToleranceCtrl.dispose();
    _expressionCtrl.dispose();

    _tabController.removeListener(_onCalculatorTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _loadVisualizerMetadata() {
    final metadata = widget.visualizerMetadata;
    if (metadata == null) return;

    _plotFunctions2D.clear();
    _plotFunctions3D.clear();
    _scalarFunctions.clear();
    _vectorFunctions.clear();
    _odeSamples.clear();

    switch (metadata.kind) {
      case PlotAnimationKind.plot2d:
        for (final item in metadata.items) {
          _plotFunctions2D.add(
            FunctionDef(
              initialText: item.expressions['expression'] ?? '',
              color: colorFromArgbOrDefault(item.colorArgb, _randomColor()),
              tMin: item.hasAnimation ? item.tMin.toString() : '',
              tMax: item.hasAnimation ? item.tMax.toString() : '',
              durationMs: item.durationMs.toString(),
            ),
          );
        }
        _tabController.index = 1;
        _isComplexMode = metadata.isComplex;
      case PlotAnimationKind.surface3d:
        for (final item in metadata.items) {
          _plotFunctions3D.add(
            FunctionDef(
              initialText: item.expressions['expression'] ?? '',
              color: colorFromArgbOrDefault(item.colorArgb, _randomColor()),
              tMin: item.hasAnimation ? item.tMin.toString() : '',
              tMax: item.hasAnimation ? item.tMax.toString() : '',
              durationMs: item.durationMs.toString(),
            ),
          );
        }
        _tabController.index = 2;
        _isComplexMode = metadata.isComplex;
      case PlotAnimationKind.scalar3d:
        for (final item in metadata.items) {
          _scalarFunctions.add(
            ScalarFuncDef(
              x: item.expressions['x'] ?? 'u',
              y: item.expressions['y'] ?? 'v',
              z: item.expressions['z'] ?? '0',
              f: item.expressions['f'] ?? 'z',
              tMin: item.hasAnimation ? item.tMin.toString() : '',
              tMax: item.hasAnimation ? item.tMax.toString() : '',
              durationMs: item.durationMs.toString(),
            ),
          );
        }
        _tabController.index = 3;
      case PlotAnimationKind.vector3d:
        for (final item in metadata.items) {
          _vectorFunctions.add(
            VectorFuncDef(
              x: item.expressions['x'] ?? 'u',
              y: item.expressions['y'] ?? 'v',
              z: item.expressions['z'] ?? '0',
              p: item.expressions['p'] ?? '1',
              q: item.expressions['q'] ?? '0',
              r: item.expressions['r'] ?? '0',
              tMin: item.hasAnimation ? item.tMin.toString() : '',
              tMax: item.hasAnimation ? item.tMax.toString() : '',
              durationMs: item.durationMs.toString(),
            ),
          );
        }
        _tabController.index = 4;
      case PlotAnimationKind.ode:
        if (metadata.items.isNotEmpty) {
          final expr = metadata.items.first.expressions;
          final dim = int.tryParse(expr['dimension'] ?? '2') ?? 2;
          _odeDimension = dim.clamp(2, 3);
          final methodName =
              expr['method'] ?? OdeIntegrationMethod.rungeKutta4.name;
          _odeMethod = OdeIntegrationMethod.values.firstWhere(
            (m) => m.name == methodName,
            orElse: () => OdeIntegrationMethod.rungeKutta4,
          );
          _odeDxCtrl.text = expr['dx'] ?? _odeDxCtrl.text;
          _odeDyCtrl.text = expr['dy'] ?? _odeDyCtrl.text;
          _odeDzCtrl.text = expr['dz'] ?? _odeDzCtrl.text;
          _odeX0Ctrl.text = expr['x0'] ?? _odeX0Ctrl.text;
          _odeY0Ctrl.text = expr['y0'] ?? _odeY0Ctrl.text;
          _odeZ0Ctrl.text = expr['z0'] ?? _odeZ0Ctrl.text;
          _odeT0Ctrl.text = expr['t0'] ?? _odeT0Ctrl.text;
          _odeStepCtrl.text = expr['step'] ?? _odeStepCtrl.text;
          _odeToleranceCtrl.text = expr['tol'] ?? _odeToleranceCtrl.text;
          _odeSelectedPresetId = expr['preset'] ?? _odeSelectedPresetId;
          _odeStatus = 'Visualizer mode: press Play to run.';
        }
        _tabController.index = 5;
    }
  }

  void _loadWorkspaceMetadata(String? encoded) {
    if (encoded == null || encoded.isEmpty || _isReadOnlyVisualizer) return;
    try {
      final raw = jsonDecode(encoded);
      if (raw is! Map) return;
      final data = raw.map((key, value) => MapEntry(key.toString(), value));
      _restoringWorkspaceMetadata = true;

      _replaceFunctionList(
        _plotFunctions2D,
        _readList(
          data['plot2d'],
        ).map((item) => _functionDefFromMetadata(item, is3D: false)).toList(),
      );
      _replaceFunctionList(
        _plotFunctions3D,
        _readList(
          data['plot3d'],
        ).map((item) => _functionDefFromMetadata(item, is3D: true)).toList(),
      );
      _replaceFunctionList(
        _scalarFunctions,
        _readList(data['scalar']).map(_scalarDefFromMetadata).toList(),
      );
      _replaceFunctionList(
        _vectorFunctions,
        _readList(data['vector']).map(_vectorDefFromMetadata).toList(),
      );

      final ode = _readMap(data['ode']);
      if (ode.isNotEmpty) {
        _odeDimension = (ode['dimension'] as num?)?.toInt().clamp(2, 3) ?? 2;
        _odeMethod = OdeIntegrationMethod.values.firstWhere(
          (m) => m.name == ode['method'],
          orElse: () => OdeIntegrationMethod.verlet,
        );
        _odeSelectedPresetId = ode['preset']?.toString() ?? '';
        _odeDxCtrl.text = ode['dx']?.toString() ?? '';
        _odeDyCtrl.text = ode['dy']?.toString() ?? '';
        _odeDzCtrl.text = ode['dz']?.toString() ?? '';
        _odeX0Ctrl.text = ode['x0']?.toString() ?? '';
        _odeY0Ctrl.text = ode['y0']?.toString() ?? '';
        _odeZ0Ctrl.text = ode['z0']?.toString() ?? '';
        _odeT0Ctrl.text = ode['t0']?.toString() ?? '';
        _odeStepCtrl.text = ode['step']?.toString() ?? '';
        _odeToleranceCtrl.text = ode['tol']?.toString() ?? '';
        _showOdeGrid = ode['showGrid'] != false;
      }
      _calculusMetadata = _readMap(data['calculus']);

      _isComplexMode = data['complex'] == true;
      _showLabels = data['showLabels'] != false;
      _autoRotate3D = data['autoRotate3D'] == true;
      _center3DX = (data['centerX'] as num?)?.toDouble() ?? _center3DX;
      _center3DY = (data['centerY'] as num?)?.toDouble() ?? _center3DY;
      _center3DZ = (data['centerZ'] as num?)?.toDouble() ?? _center3DZ;
      _cXCtrl.text = _center3DX.toString();
      _cYCtrl.text = _center3DY.toString();
      _cZCtrl.text = _center3DZ.toString();
      _yaw = (data['yaw'] as num?)?.toDouble() ?? _yaw;
      _pitch = (data['pitch'] as num?)?.toDouble() ?? _pitch;
      _zoom3D = (data['zoom3D'] as num?)?.toDouble() ?? _zoom3D;
      _offsetX = (data['offsetX'] as num?)?.toDouble() ?? _offsetX;
      _offsetY = (data['offsetY'] as num?)?.toDouble() ?? _offsetY;
      _zoom2D = (data['zoom2D'] as num?)?.toDouble() ?? _zoom2D;
      final activeTab = (data['activeTab'] as num?)?.toInt();
      if (activeTab != null &&
          activeTab >= 0 &&
          activeTab < _tabController.length) {
        _tabController.index = activeTab;
      }
    } catch (_) {
      // Ignore malformed note metadata from older or manually edited files.
    } finally {
      _restoringWorkspaceMetadata = false;
    }
  }

  List<Map<String, dynamic>> _readList(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList();
  }

  Map<String, dynamic> _readMap(Object? value) {
    if (value is! Map) return const {};
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  void _replaceFunctionList<T>(List<T> target, List<T> replacement) {
    for (final item in target) {
      if (item is FunctionDef) item.dispose();
      if (item is ScalarFuncDef) item.dispose();
      if (item is VectorFuncDef) item.dispose();
    }
    target
      ..clear()
      ..addAll(replacement);
  }

  FunctionDef _functionDefFromMetadata(
    Map<String, dynamic> item, {
    required bool is3D,
  }) {
    return FunctionDef(
      initialText: item['expression']?.toString() ?? '',
      color: colorFromArgbOrDefault(
        (item['color'] as num?)?.toInt(),
        _randomColor(),
      ),
      enabled: item['enabled'] != false,
      fillArea: item['fill'] == true,
      tMin: item['tMin']?.toString() ?? '',
      tMax: item['tMax']?.toString() ?? '',
      durationMs: item['duration']?.toString() ?? '6000',
      dMinX: item['xMin']?.toString() ?? '',
      dMaxX: item['xMax']?.toString() ?? '',
      dMinY: item['yMin']?.toString() ?? '',
      dMaxY: item['yMax']?.toString() ?? '',
      dMinZ: item['zMin']?.toString() ?? '',
      dMaxZ: item['zMax']?.toString() ?? '',
      coord2D: CoordSystem2D.values.firstWhere(
        (c) => c.name == item['coord2D'],
        orElse: () => CoordSystem2D.cartesian,
      ),
      coord3D: CoordSystem3D.values.firstWhere(
        (c) => c.name == item['coord3D'],
        orElse: () => CoordSystem3D.cartesian,
      ),
    );
  }

  ScalarFuncDef _scalarDefFromMetadata(Map<String, dynamic> item) {
    return ScalarFuncDef(
      x: item['x']?.toString() ?? '',
      y: item['y']?.toString() ?? '',
      z: item['z']?.toString() ?? '',
      f: item['f']?.toString() ?? '',
      enabled: item['enabled'] != false,
      tMin: item['tMin']?.toString() ?? '',
      tMax: item['tMax']?.toString() ?? '',
      durationMs: item['duration']?.toString() ?? '6000',
      dMinX: item['xMin']?.toString() ?? '',
      dMaxX: item['xMax']?.toString() ?? '',
      dMinY: item['yMin']?.toString() ?? '',
      dMaxY: item['yMax']?.toString() ?? '',
      dMinZ: item['zMin']?.toString() ?? '',
      dMaxZ: item['zMax']?.toString() ?? '',
      coord3D: CoordSystem3D.values.firstWhere(
        (c) => c.name == item['coord3D'],
        orElse: () => CoordSystem3D.cartesian,
      ),
    );
  }

  VectorFuncDef _vectorDefFromMetadata(Map<String, dynamic> item) {
    return VectorFuncDef(
      x: item['x']?.toString() ?? '',
      y: item['y']?.toString() ?? '',
      z: item['z']?.toString() ?? '',
      p: item['p']?.toString() ?? '',
      q: item['q']?.toString() ?? '',
      r: item['r']?.toString() ?? '',
      enabled: item['enabled'] != false,
      tMin: item['tMin']?.toString() ?? '',
      tMax: item['tMax']?.toString() ?? '',
      durationMs: item['duration']?.toString() ?? '6000',
      dMinX: item['xMin']?.toString() ?? '',
      dMaxX: item['xMax']?.toString() ?? '',
      dMinY: item['yMin']?.toString() ?? '',
      dMaxY: item['yMax']?.toString() ?? '',
      dMinZ: item['zMin']?.toString() ?? '',
      dMaxZ: item['zMax']?.toString() ?? '',
      coord3D: CoordSystem3D.values.firstWhere(
        (c) => c.name == item['coord3D'],
        orElse: () => CoordSystem3D.cartesian,
      ),
    );
  }

  String _buildWorkspaceMetadataJson() {
    final data = <String, dynamic>{
      'v': 1,
      'activeTab': _tabController.index,
      'complex': _isComplexMode,
      'showLabels': _showLabels,
      'autoRotate3D': _autoRotate3D,
      'yaw': _yaw,
      'pitch': _pitch,
      'zoom3D': _zoom3D,
      'centerX': _center3DX,
      'centerY': _center3DY,
      'centerZ': _center3DZ,
      'offsetX': _offsetX,
      'offsetY': _offsetY,
      'zoom2D': _zoom2D,
      'plot2d': _plotFunctions2D.map(_functionDefToMetadata).toList(),
      'plot3d': _plotFunctions3D.map(_functionDefToMetadata).toList(),
      'scalar': _scalarFunctions.map(_scalarDefToMetadata).toList(),
      'vector': _vectorFunctions.map(_vectorDefToMetadata).toList(),
      'ode': _odeMetadata(),
      'calculus': _calculusMetadata,
    };
    return jsonEncode(data);
  }

  Map<String, dynamic> _functionDefToMetadata(FunctionDef f) => {
    'expression': f.controller.text,
    'color': f.color.toARGB32(),
    'enabled': f.enabled,
    'fill': f.fillArea,
    'coord2D': f.coord2D.name,
    'coord3D': f.coord3D.name,
    'tMin': f.tMinCtrl.text,
    'tMax': f.tMaxCtrl.text,
    'duration': f.tDurationCtrl.text,
    'xMin': f.dMinXCtrl.text,
    'xMax': f.dMaxXCtrl.text,
    'yMin': f.dMinYCtrl.text,
    'yMax': f.dMaxYCtrl.text,
    'zMin': f.dMinZCtrl.text,
    'zMax': f.dMaxZCtrl.text,
  };

  Map<String, dynamic> _scalarDefToMetadata(ScalarFuncDef f) => {
    'x': f.xCtrl.text,
    'y': f.yCtrl.text,
    'z': f.zCtrl.text,
    'f': f.fCtrl.text,
    'enabled': f.enabled,
    'coord3D': f.coord3D.name,
    'tMin': f.tMinCtrl.text,
    'tMax': f.tMaxCtrl.text,
    'duration': f.tDurationCtrl.text,
    'xMin': f.dMinXCtrl.text,
    'xMax': f.dMaxXCtrl.text,
    'yMin': f.dMinYCtrl.text,
    'yMax': f.dMaxYCtrl.text,
    'zMin': f.dMinZCtrl.text,
    'zMax': f.dMaxZCtrl.text,
  };

  Map<String, dynamic> _vectorDefToMetadata(VectorFuncDef f) => {
    'x': f.xCtrl.text,
    'y': f.yCtrl.text,
    'z': f.zCtrl.text,
    'p': f.pCtrl.text,
    'q': f.qCtrl.text,
    'r': f.rCtrl.text,
    'enabled': f.enabled,
    'coord3D': f.coord3D.name,
    'tMin': f.tMinCtrl.text,
    'tMax': f.tMaxCtrl.text,
    'duration': f.tDurationCtrl.text,
    'xMin': f.dMinXCtrl.text,
    'xMax': f.dMaxXCtrl.text,
    'yMin': f.dMinYCtrl.text,
    'yMax': f.dMaxYCtrl.text,
    'zMin': f.dMinZCtrl.text,
    'zMax': f.dMaxZCtrl.text,
  };

  Map<String, dynamic> _odeMetadata() => {
    'dimension': _odeDimension,
    'method': _odeMethod.name,
    'preset': _odeSelectedPresetId,
    'dx': _odeDxCtrl.text,
    'dy': _odeDyCtrl.text,
    'dz': _odeDzCtrl.text,
    'x0': _odeX0Ctrl.text,
    'y0': _odeY0Ctrl.text,
    'z0': _odeZ0Ctrl.text,
    't0': _odeT0Ctrl.text,
    'step': _odeStepCtrl.text,
    'tol': _odeToleranceCtrl.text,
    'showGrid': _showOdeGrid,
  };

  void _saveWorkspaceMetadataNow() {
    if (_restoringWorkspaceMetadata || _isReadOnlyVisualizer) return;
    widget.onWorkspaceMetadataChanged?.call(_buildWorkspaceMetadataJson());
  }

  void _markWorkspaceChanged() {
    if (_restoringWorkspaceMetadata || _isReadOnlyVisualizer) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _saveWorkspaceMetadataNow();
    });
  }

  void _updateWorkspaceState(VoidCallback update) {
    setState(update);
    _markWorkspaceChanged();
  }

  List<FunctionDef> _enabledPlotFunctions(bool is3D) {
    return (is3D ? _plotFunctions3D : _plotFunctions2D)
        .where((f) => f.enabled)
        .toList();
  }

  List<ScalarFuncDef> get _enabledScalarFunctions {
    return _scalarFunctions.where((f) => f.enabled).toList();
  }

  List<VectorFuncDef> get _enabledVectorFunctions {
    return _vectorFunctions.where((f) => f.enabled).toList();
  }

  CoordSystem2D _activeCoordSystem2D(List<FunctionDef> enabled) {
    return enabled.any((f) => f.coord2D == CoordSystem2D.polar)
        ? CoordSystem2D.polar
        : CoordSystem2D.cartesian;
  }

  CoordSystem3D _activeCoordSystem3DFromFunctions(List<FunctionDef> enabled) {
    if (enabled.any((f) => f.coord3D == CoordSystem3D.spherical)) {
      return CoordSystem3D.spherical;
    }
    if (enabled.any((f) => f.coord3D == CoordSystem3D.cylindrical)) {
      return CoordSystem3D.cylindrical;
    }
    return CoordSystem3D.cartesian;
  }

  CoordSystem3D _activeCoordSystem3DFromScalar(List<ScalarFuncDef> enabled) {
    if (enabled.any((f) => f.coord3D == CoordSystem3D.spherical)) {
      return CoordSystem3D.spherical;
    }
    if (enabled.any((f) => f.coord3D == CoordSystem3D.cylindrical)) {
      return CoordSystem3D.cylindrical;
    }
    return CoordSystem3D.cartesian;
  }

  CoordSystem3D _activeCoordSystem3DFromVector(List<VectorFuncDef> enabled) {
    if (enabled.any((f) => f.coord3D == CoordSystem3D.spherical)) {
      return CoordSystem3D.spherical;
    }
    if (enabled.any((f) => f.coord3D == CoordSystem3D.cylindrical)) {
      return CoordSystem3D.cylindrical;
    }
    return CoordSystem3D.cartesian;
  }

  void _resetPane(int index) {
    _updateWorkspaceState(() {
      switch (index) {
        case 1:
          _plotFunctions2D.forEach((f) => f.dispose());
          _plotFunctions2D.clear();
          break;
        case 2:
          _plotFunctions3D.forEach((f) => f.dispose());
          _plotFunctions3D.clear();
          break;
        case 3:
          _scalarFunctions.forEach((f) => f.dispose());
          _scalarFunctions.clear();
          break;
        case 4:
          _vectorFunctions.forEach((f) => f.dispose());
          _vectorFunctions.clear();
          break;
        case 5:
          _stopOdeSolver(reason: 'Reset');
          _odeSamples.clear();
          _odeDimension = 2;
          _odeMethod = OdeIntegrationMethod.verlet;
          _odeSelectedPresetId = '';
          _odeDxCtrl.clear();
          _odeDyCtrl.clear();
          _odeDzCtrl.clear();
          _odeX0Ctrl.clear();
          _odeY0Ctrl.clear();
          _odeZ0Ctrl.clear();
          _odeT0Ctrl.clear();
          _odeStepCtrl.clear();
          _odeToleranceCtrl.clear();
          _odeStatus = 'Configure equation and press Start';
          break;
        case 6:
          _calculusMetadata = const {};
          _calculusResetNonce++;
          break;
        default:
          break;
      }
    });
  }

  Color _randomColor() {
    final colors = [
      Colors.blue,
      Colors.red,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
      Colors.amber,
      Colors.cyan,
    ];
    return colors[math.Random().nextInt(colors.length)];
  }

  void _onKeyTap(String label, {String? insertValue}) {
    HapticFeedback.selectionClick();
    final val = insertValue ?? label;

    if (label == 'AC') {
      _expressionCtrl.clear();
      setState(() {
        _result = '';
        _shouldClear = false;
      });
      return;
    }
    if (label == '=') {
      _calculate();
      _shouldClear = true;
      return;
    }
    if (label == '⌫') {
      _shouldClear = false;
      final text = _expressionCtrl.text;
      if (text.isNotEmpty) {
        _expressionCtrl.text = text.characters.skipLast(1).toString();
      }
      return;
    }

    if (_shouldClear) {
      final isOperator = ['+', '-', '*', '/', '^'].contains(val);
      if (!isOperator) {
        _expressionCtrl.clear();
      }
      _shouldClear = false;
    }

    String toInsert = val;
    int cursorOffset = val.length;

    if ([
      'sin',
      'cos',
      'tan',
      'sinh',
      'cosh',
      'tanh',
      'asinh',
      'acosh',
      'atanh',
      'asin',
      'acos',
      'atan',
      'log',
      'ln',
      'abs',
      'sqrt',
      'nCr',
      'nPr',
      'nrt',
    ].contains(val)) {
      toInsert = '$val(';
      cursorOffset = toInsert.length;
    } else if (val == 'log10') {
      toInsert = 'log10(';
      cursorOffset = toInsert.length;
    }

    final text = _expressionCtrl.text;
    final start = _expressionCtrl.selection.start;
    final end = _expressionCtrl.selection.end;

    final newText = text.replaceRange(start, end, toInsert);
    _expressionCtrl.text = newText;
    _expressionCtrl.selection = TextSelection.fromPosition(
      TextPosition(offset: start + cursorOffset),
    );
  }

  void _calculate() {
    String input = _expressionCtrl.text.trim();
    if (input.isEmpty) return;

    input = input
        .replaceAll('×', '*')
        .replaceAll('÷', '/')
        .replaceAll('π', 'pi')
        .replaceAll('√', 'sqrt')
        .replaceAll('e', 'e')
        .replaceAll('ln(', 'log(')
        .replaceAll('log10(', 'log(');

    try {
      final result = _complexParser.evaluate(
        input,
        isRad: _isRad,
        ans: _lastAnswer,
      );

      setState(() {
        _result = result.toString(precision: 10);
        _lastAnswer = result;
        _CalcCache.result = _result;
        _CalcCache.lastAnswer = _lastAnswer;
      });
    } catch (e) {
      setState(() => _result = 'Error');
    }
  }

  void _toggleConverter() {
    setState(() {
      _showConverter = !_showConverter;
    });
  }

  Future<void> _captureGraph({
    String? assetFileInfo,
    String? customSuccessMessage,
  }) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final idx = _tabController.index;

      if (idx == 6) {
        if (!mounted) return;
        setState(() => _extremaCaptureMode = true);
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final boundary =
              _extremaKey.currentContext?.findRenderObject()
                  as RenderRepaintBoundary?;
          if (boundary == null) {
            if (mounted) setState(() => _extremaCaptureMode = false);
            return;
          }
          final img = await boundary.toImage(pixelRatio: 3.0);
          if (mounted) setState(() => _extremaCaptureMode = false);

          final recorder = ui.PictureRecorder();
          final w = img.width.toDouble();
          final h = img.height.toDouble();
          final canvas = ui.Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
          final isDark = Theme.of(context).brightness == Brightness.dark;

          canvas.drawRect(
            Rect.fromLTWH(0, 0, w, h),
            Paint()..color = Colors.white,
          );

          final paint = Paint();
          if (isDark) {
            paint.colorFilter = const ColorFilter.matrix(<double>[
              0.5740000009536743,
              -1.4299999475479126,
              -0.14399999380111694,
              0,
              255,
              -0.4259999990463257,
              -0.4299999475479126,
              -0.14399999380111694,
              0,
              255,
              -0.4259999990463257,
              -1.4299999475479126,
              0.8560000061988831,
              0,
              255,
              0,
              0,
              0,
              1,
              0,
            ]);
          }

          canvas.drawImage(img, Offset.zero, paint);
          final compositeImg = await recorder.endRecording().toImage(
            w.toInt(),
            h.toInt(),
          );

          final byteData = await compositeImg.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (byteData == null) return;
          widget.onInsertImage(byteData.buffer.asUint8List(), invertible: true);
          if (mounted) {
            scaffoldMessenger.showSnackBar(
              const SnackBar(
                content: Text('Calculus graph with legend saved!'),
                duration: Duration(milliseconds: 800),
              ),
            );
          }
        });
        return;
      }

      GlobalKey targetKey;
      if (idx == 1) {
        targetKey = _graphKey;
      } else if (idx == 2) {
        targetKey = _plot3dKey;
      } else if (idx == 3) {
        targetKey = _scalarKey;
      } else if (idx == 4) {
        targetKey = _vectorKey;
      } else {
        targetKey = _odeKey;
      }

      final boundary =
          targetKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;

      final img = await boundary.toImage(pixelRatio: 3.0);

      final List<({String text, Color color})> legendItems = [];
      if (idx == 1) {
        for (var f in _plotFunctions2D.where((f) => f.enabled)) {
          legendItems.add((text: 'y = ${f.controller.text}', color: f.color));
        }
      } else if (idx == 2) {
        for (var f in _plotFunctions3D.where((f) => f.enabled)) {
          legendItems.add((text: 'z = ${f.controller.text}', color: f.color));
        }
      } else if (idx == 3) {
        for (var f in _scalarFunctions.where((f) => f.enabled)) {
          legendItems.add((
            text:
                'Surface: r(u,v) = <${f.xCtrl.text}, ${f.yCtrl.text}, ${f.zCtrl.text}>\nScalar Field: f(x,y,z) = ${f.fCtrl.text}',
            color: Colors.blueGrey,
          ));
        }
      } else if (idx == 4) {
        for (var f in _vectorFunctions.where((f) => f.enabled)) {
          legendItems.add((
            text:
                'Surface: r(u,v) = <${f.xCtrl.text}, ${f.yCtrl.text}, ${f.zCtrl.text}>\nVector Field: F(x,y,z) = <${f.pCtrl.text}, ${f.qCtrl.text}, ${f.rCtrl.text}>',
            color: Colors.blueGrey,
          ));
        }
      }

      const double pixelRatio = 3.0;
      final w = img.width.toDouble();
      final baseH = img.height.toDouble();
      final double legendPadding = 24.0 * pixelRatio;

      final isDark = Theme.of(context).brightness == Brightness.dark;

      final textStyle = ui.TextStyle(
        color: isDark ? Colors.white : const Color(0xFF1E1E1E),
        fontSize: 32 * pixelRatio,
        fontFamily: 'monospace',
        fontWeight: ui.FontWeight.w600,
        height: 1.3,
      );

      final paragraphs = <ui.Paragraph>[];
      double legendContentHeight = 0;
      for (var item in legendItems) {
        final builder =
            ui.ParagraphBuilder(
                ui.ParagraphStyle(
                  textDirection: TextDirection.ltr,
                  maxLines: 10,
                ),
              )
              ..pushStyle(textStyle)
              ..addText(item.text);
        final p = builder.build();
        p.layout(
          ui.ParagraphConstraints(
            width: w - legendPadding * 4 - 40 * pixelRatio,
          ),
        );
        paragraphs.add(p);
        legendContentHeight += p.height + 28 * pixelRatio;
      }

      final double legendHeight = legendItems.isEmpty
          ? 0
          : (legendPadding * 2 + legendContentHeight);
      final h = baseH + legendHeight;

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder, Rect.fromLTWH(0, 0, w, h));

      final paint = Paint();
      if (isDark) {
        paint.colorFilter = const ColorFilter.matrix(<double>[
          0.5740000009536743,
          -1.4299999475479126,
          -0.14399999380111694,
          0,
          255,
          -0.4259999990463257,
          -0.4299999475479126,
          -0.14399999380111694,
          0,
          255,
          -0.4259999990463257,
          -1.4299999475479126,
          0.8560000061988831,
          0,
          255,
          0,
          0,
          0,
          1,
          0,
        ]);

        canvas.saveLayer(Rect.fromLTWH(0, 0, w, h), paint);
      }

      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h),
        Paint()..color = isDark ? const Color(0xFF1E1E1E) : Colors.white,
      );

      canvas.drawImage(img, Offset.zero, Paint());

      if (legendItems.isNotEmpty) {
        final legendRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            legendPadding,
            baseH + legendPadding / 2,
            w - legendPadding * 2,
            legendHeight - legendPadding,
          ),
          Radius.circular(24 * pixelRatio),
        );

        canvas.drawRRect(
          legendRect,
          Paint()
            ..color = isDark
                ? const Color(0xFF2C2C2E)
                : const Color(0xFFF8F9FA),
        );
        canvas.drawRRect(
          legendRect,
          Paint()
            ..color = isDark ? Colors.white24 : const Color(0x1A000000)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0 * pixelRatio,
        );

        double currentY = baseH + legendPadding;
        for (int i = 0; i < legendItems.length; i++) {
          var item = legendItems[i];
          var paragraph = paragraphs[i];

          canvas.drawCircle(
            Offset(legendPadding * 2, currentY + paragraph.height / 2),
            12 * pixelRatio,
            Paint()..color = item.color,
          );

          canvas.drawParagraph(
            paragraph,
            Offset(legendPadding * 2 + 40 * pixelRatio, currentY),
          );
          currentY += paragraph.height + 28 * pixelRatio;
        }
      }

      if (isDark) {
        canvas.restore();
      }

      final compositeImg = await recorder.endRecording().toImage(
        w.toInt(),
        h.toInt(),
      );
      final byteData = await compositeImg.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData != null) {
        widget.onInsertImage(
          byteData.buffer.asUint8List(),
          assetFileInfo: assetFileInfo,
          invertible: true,
        );
        if (mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(
                customSuccessMessage ?? 'High Quality Plot inserted!',
              ),
              duration: const Duration(milliseconds: 800),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Capture error: $e');
    }
  }

  bool _hasTimedAnimationForCurrentTab() {
    final idx = _tabController.index;
    if (idx == 1)
      return _plotFunctions2D.any((f) => f.enabled && f.hasTimeAnimation);
    if (idx == 2)
      return _plotFunctions3D.any((f) => f.enabled && f.hasTimeAnimation);
    if (idx == 3)
      return _scalarFunctions.any((f) => f.enabled && f.hasTimeAnimation);
    if (idx == 4)
      return _vectorFunctions.any((f) => f.enabled && f.hasTimeAnimation);
    if (idx == 5) return true;
    return false;
  }

  PlotAnimationMetadata? _buildCurrentAnimationMetadata() {
    final idx = _tabController.index;
    if (idx == 1) {
      final items = _plotFunctions2D.where((f) => f.enabled).map((f) {
        final tMin = parsePlotRealExpressionOrFallback(
          _complexParser,
          f.tMinCtrl.text,
          0,
        );
        final tMax = parsePlotRealExpressionOrFallback(
          _complexParser,
          f.tMaxCtrl.text,
          0,
        );
        final duration = int.tryParse(f.tDurationCtrl.text) ?? 0;
        return PlotAnimationItemMetadata(
          expressions: {'expression': f.controller.text},
          tMin: tMin,
          tMax: tMax,
          durationMs: duration,
          colorArgb: f.color.toARGB32(),
        );
      }).toList();
      final meta = PlotAnimationMetadata(
        kind: PlotAnimationKind.plot2d,
        items: items,
        isComplex: _isComplexMode,
      );
      return meta.hasAnimation ? meta : null;
    }
    if (idx == 2) {
      final items = _plotFunctions3D.where((f) => f.enabled).map((f) {
        final tMin = parsePlotRealExpressionOrFallback(
          _complexParser,
          f.tMinCtrl.text,
          0,
        );
        final tMax = parsePlotRealExpressionOrFallback(
          _complexParser,
          f.tMaxCtrl.text,
          0,
        );
        final duration = int.tryParse(f.tDurationCtrl.text) ?? 0;
        return PlotAnimationItemMetadata(
          expressions: {'expression': f.controller.text},
          tMin: tMin,
          tMax: tMax,
          durationMs: duration,
          colorArgb: f.color.toARGB32(),
        );
      }).toList();
      final meta = PlotAnimationMetadata(
        kind: PlotAnimationKind.surface3d,
        items: items,
        isComplex: _isComplexMode,
      );
      return meta.hasAnimation ? meta : null;
    }
    if (idx == 3) {
      final items = _scalarFunctions.where((f) => f.enabled).map((f) {
        final tMin = parsePlotRealExpressionOrFallback(
          _complexParser,
          f.tMinCtrl.text,
          0,
        );
        final tMax = parsePlotRealExpressionOrFallback(
          _complexParser,
          f.tMaxCtrl.text,
          0,
        );
        final duration = int.tryParse(f.tDurationCtrl.text) ?? 0;
        return PlotAnimationItemMetadata(
          expressions: {
            'x': f.xCtrl.text,
            'y': f.yCtrl.text,
            'z': f.zCtrl.text,
            'f': f.fCtrl.text,
          },
          tMin: tMin,
          tMax: tMax,
          durationMs: duration,
        );
      }).toList();
      final meta = PlotAnimationMetadata(
        kind: PlotAnimationKind.scalar3d,
        items: items,
      );
      return meta.hasAnimation ? meta : null;
    }
    if (idx == 4) {
      final items = _vectorFunctions.where((f) => f.enabled).map((f) {
        final tMin = parsePlotRealExpressionOrFallback(
          _complexParser,
          f.tMinCtrl.text,
          0,
        );
        final tMax = parsePlotRealExpressionOrFallback(
          _complexParser,
          f.tMaxCtrl.text,
          0,
        );
        final duration = int.tryParse(f.tDurationCtrl.text) ?? 0;
        return PlotAnimationItemMetadata(
          expressions: {
            'x': f.xCtrl.text,
            'y': f.yCtrl.text,
            'z': f.zCtrl.text,
            'p': f.pCtrl.text,
            'q': f.qCtrl.text,
            'r': f.rCtrl.text,
          },
          tMin: tMin,
          tMax: tMax,
          durationMs: duration,
        );
      }).toList();
      final meta = PlotAnimationMetadata(
        kind: PlotAnimationKind.vector3d,
        items: items,
      );
      return meta.hasAnimation ? meta : null;
    }
    if (idx == 5) {
      final item = PlotAnimationItemMetadata(
        expressions: {
          'dimension': _odeDimension.toString(),
          'method': _odeMethod.name,
          'dx': _odeDxCtrl.text,
          'dy': _odeDyCtrl.text,
          'dz': _odeDzCtrl.text,
          'x0': _odeX0Ctrl.text,
          'y0': _odeY0Ctrl.text,
          'z0': _odeZ0Ctrl.text,
          't0': _odeT0Ctrl.text,
          'step': _odeStepCtrl.text,
          'tol': _odeToleranceCtrl.text,
          'preset': _odeSelectedPresetId,
        },

        tMin: 0,
        tMax: 1,
        durationMs: 1,
      );
      return PlotAnimationMetadata(kind: PlotAnimationKind.ode, items: [item]);
    }
    return null;
  }

  Future<void> _captureAnimatedGraphWithMetadata() async {
    final metadata = _buildCurrentAnimationMetadata();
    if (metadata == null) return;
    await _captureGraph(
      assetFileInfo: metadata.encodeForAssetInfo(),
      customSuccessMessage: 'Animated plot saved with metadata!',
    );
  }

  void _zoomIn() {
    _updateWorkspaceState(() {
      if (_tabController.index >= 2) {
        _zoom3D = (_zoom3D * 1.2).clamp(0.001, 1000000.0);
      } else {
        _zoom2D *= 1.2;
      }
    });
  }

  void _zoomOut() {
    _updateWorkspaceState(() {
      if (_tabController.index >= 2) {
        _zoom3D = (_zoom3D / 1.2).clamp(0.001, 1000000.0);
      } else {
        _zoom2D /= 1.2;
      }
    });
  }

  void _resetView(String type) {
    _updateWorkspaceState(() {
      _zoom3D = 1.0;

      switch (type) {
        case 'XY':
          _yaw = 0;
          _pitch = 90;
        case 'XZ':
          _yaw = 0;
          _pitch = 0;
        case 'YZ':
          _yaw = 90;
          _pitch = 0;
        case 'ISO':
          _yaw = 45;
          _pitch = 30;
      }
    });
  }

  String _normalizeMathInput(String input) {
    return normalizePlotMathInput(input);
  }

  double _readDouble(TextEditingController controller, double fallback) {
    return parsePlotRealExpressionOrFallback(
      _complexParser,
      controller.text,
      fallback,
    );
  }

  List<double> _evaluateOdeDerivative(List<double> state, double t) {
    final vars = <String, Complex>{
      't': Complex(t),
      'x': Complex(state[0]),
      'x1': Complex(state[0]),
      'y': Complex(state.length > 1 ? state[1] : 0),
      'x2': Complex(state.length > 1 ? state[1] : 0),
      'z': Complex(state.length > 2 ? state[2] : 0),
      'x3': Complex(state.length > 2 ? state[2] : 0),
    };

    final derivatives = <double>[];
    final expressions = <String>[
      _odeDxCtrl.text,
      if (_odeDimension >= 2) _odeDyCtrl.text,
      if (_odeDimension >= 3) _odeDzCtrl.text,
    ];

    for (final expr in expressions) {
      final parsed = _complexParser.evaluate(
        _normalizeMathInput(expr),
        variables: vars,
      );
      derivatives.add(parsed.real);
    }
    return derivatives;
  }

  bool _stateIsFinite(List<double> state) {
    for (final v in state) {
      if (!v.isFinite) return false;
    }
    return true;
  }

  void _stopOdeSolver({String? reason}) {
    _odeTimer?.cancel();
    _odeTimer = null;
    _odeTicker?.dispose();
    _odeTicker = null;
    _odeComputeInFlight = false;
    if (!mounted) return;
    _updateWorkspaceState(() {
      _odeRunning = false;
      if (reason != null && reason.isNotEmpty) {
        _odeStatus = reason;
      }
    });
  }

  void _tickOdeSolver() {
    if (!_odeRunning || _odeSamples.isEmpty || _odeComputeInFlight) return;
    final h = _readDouble(_odeStepCtrl, 0.02).abs();
    final tol = _readDouble(_odeToleranceCtrl, 1e-5).abs();
    if (h <= 0) {
      _stopOdeSolver(reason: 'Step size must be > 0');
      return;
    }

    final last = _odeSamples.last;
    final expressions = <String>[
      _odeDxCtrl.text,
      if (_odeDimension >= 2) _odeDyCtrl.text,
      if (_odeDimension >= 3) _odeDzCtrl.text,
    ];
    final methodStr = _odeMethod.name;

    final params = <String, dynamic>{
      'expressions': expressions,
      'method': methodStr,
      'lastState': last.state,
      'lastT': last.t,
      'h': h,
      'stepsPerTick': _odeStepsPerTick,
      'tolerance': tol,
      'previousStableSteps': _odeStableSteps,
    };

    _odeComputeInFlight = true;
    compute(runOdeStepsInIsolate, params).then((result) {
      _odeComputeInFlight = false;
      if (!mounted || !_odeRunning) return;

      final success = result['success'] as bool;
      if (!success) {
        _stopOdeSolver(reason: result['error'] as String?);
        return;
      }

      final newSamplesRaw = result['newSamples'] as List;
      final converged = result['converged'] as bool;
      final stableSteps = result['stableSteps'] as int;

      for (final m in newSamplesRaw) {
        final map = m as Map<String, dynamic>;
        final sample = OdeSample(
          t: (map['t'] as num).toDouble(),
          state: List<double>.from(map['state'] as List),
        );
        _odeSamples.add(sample);
        if (_odeSamples.length > _odeMaxStoredSamples) {
          _odeSamples.removeAt(0);
        }
      }

      _odeStableSteps = stableSteps;

      if (converged && newSamplesRaw.isNotEmpty) {
        final lastSample = newSamplesRaw.last as Map<String, dynamic>;
        final tVal = (lastSample['t'] as num).toDouble();
        _odeConverged = true;
        _stopOdeSolver(
          reason: 'Converged automatically at t=${tVal.toStringAsFixed(4)}',
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        final lastSample = _odeSamples.last;
        final coords = lastSample.state
            .map((v) => v.toStringAsFixed(4))
            .join(_odeDimension >= 2 ? ', ' : '');
        _odeStatus =
            'Running t=${lastSample.t.toStringAsFixed(4)}  state=[$coords]  points=${_odeSamples.length}';
      });
    });
  }

  void _startOdeSolver() {
    final h = _readDouble(_odeStepCtrl, 0.02).abs();
    final t0 = _readDouble(_odeT0Ctrl, 0);
    final x0 = _readDouble(_odeX0Ctrl, 0);
    final y0 = _readDouble(_odeY0Ctrl, 0);
    final z0 = _readDouble(_odeZ0Ctrl, 0);
    if (h <= 0) {
      setState(() => _odeStatus = 'Step size must be > 0');
      return;
    }

    final initial = <double>[
      x0,
      if (_odeDimension >= 2) y0,
      if (_odeDimension >= 3) z0,
    ];
    try {
      final test = _evaluateOdeDerivative(initial, t0);
      if (!_stateIsFinite(test)) {
        setState(() => _odeStatus = 'Equation produced non-finite derivative');
        return;
      }
    } catch (_) {
      setState(() => _odeStatus = 'Invalid differential equation');
      return;
    }

    _odeTimer?.cancel();
    setState(() {
      _odeConverged = false;
      _odeStableSteps = 0;

      _odeSamples
        ..clear()
        ..add(OdeSample(t: t0, state: initial));
      _odeRunning = true;
      _odeStatus = 'Running...';
    });
    _odeTicker = createTicker((_) {
      _tickOdeSolver();
    });
    _odeTicker!.start();
  }

  void _clearOdeSolver() {
    _odeTimer?.cancel();
    _odeTicker?.dispose();
    _odeTicker = null;
    _odeComputeInFlight = false;
    setState(() {
      _odeRunning = false;
      _odeConverged = false;
      _odeStableSteps = 0;
      _odeSamples.clear();
      _odeStatus = 'Cleared. Configure equation and press Start';
    });
  }

  void _applyOdePreset(OdePresetConfig preset) {
    _odeTimer?.cancel();
    _odeTicker?.dispose();
    _odeTicker = null;
    _odeComputeInFlight = false;
    _updateWorkspaceState(() {
      _odeSelectedPresetId = preset.id;
      _odeDimension = preset.dimension;
      _odeMethod = preset.method;
      _odeDxCtrl.text = preset.dx;
      _odeDyCtrl.text = preset.dy;
      _odeDzCtrl.text = preset.dz;
      _odeX0Ctrl.text = preset.x0;
      _odeY0Ctrl.text = preset.y0;
      _odeZ0Ctrl.text = preset.z0;
      _odeT0Ctrl.text = preset.t0;
      _odeStepCtrl.text = preset.step;
      _odeToleranceCtrl.text = preset.tolerance;
      _odeSamples.clear();
      _odeRunning = false;
      _odeConverged = false;
      _odeStableSteps = 0;
      _odeStatus = 'Preset loaded: ${preset.label}. Press Start to run.';
    });
  }

  Future<void> _copyOdeValues() async {
    if (_odeSamples.isEmpty) {
      setState(() => _odeStatus = 'No solution values to copy yet');
      return;
    }
    final buffer = StringBuffer();
    if (_odeDimension == 2) {
      buffer.writeln('t,x,y');
    } else {
      buffer.writeln('t,x,y,z');
    }
    for (final s in _odeSamples) {
      buffer.write(s.t);
      for (final v in s.state) {
        buffer.write(',$v');
      }
      buffer.writeln();
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    setState(() {
      _odeStatus = 'Copied ${_odeSamples.length} solution rows to clipboard';
    });
  }

  Widget PointerInterceptor({required Widget child}) {
    return Align(alignment: Alignment.topLeft, child: child);
  }

  Widget _buildScalarItem(ScalarFuncDef f, int i, List list) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Saved scalar surface ${i + 1}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            const Spacer(),
            Tooltip(
              message: f.enabled ? 'Hide from plot' : 'Show in plot',
              child: Switch(
                value: f.enabled,
                onChanged: _isReadOnlyVisualizer
                    ? null
                    : (value) => _updateWorkspaceState(() => f.enabled = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Surface position r(u, v)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: _miniField(f.xCtrl, 'x')),
            const SizedBox(width: 8),
            Expanded(child: _miniField(f.yCtrl, 'y')),
            const SizedBox(width: 8),
            Expanded(child: _miniField(f.zCtrl, 'z')),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Scalar value sampled at that position',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: _miniField(f.fCtrl, 'f')),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: _isReadOnlyVisualizer
                  ? null
                  : () => _updateWorkspaceState(() => list.removeAt(i)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Time parameter t (optional):',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: _miniField(f.tMinCtrl, 't min')),
            const SizedBox(width: 8),
            Expanded(child: _miniField(f.tMaxCtrl, 't max')),
            const SizedBox(width: 8),
            Expanded(child: _miniField(f.tDurationCtrl, 'duration ms')),
          ],
        ),
        const SizedBox(height: 8),
        _coordinateChoice3D(
          value: f.coord3D,
          onChanged: (value) => _updateWorkspaceState(() => f.coord3D = value),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(width: 140, child: _miniField(f.dMinXCtrl, 'x min')),
            SizedBox(width: 140, child: _miniField(f.dMaxXCtrl, 'x max')),
            SizedBox(width: 140, child: _miniField(f.dMinYCtrl, 'y min')),
            SizedBox(width: 140, child: _miniField(f.dMaxYCtrl, 'y max')),
            SizedBox(width: 140, child: _miniField(f.dMinZCtrl, 'z min')),
            SizedBox(width: 140, child: _miniField(f.dMaxZCtrl, 'z max')),
          ],
        ),
      ],
    );
  }

  Widget _buildVectorItem(VectorFuncDef f, int i, List list) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Saved vector field ${i + 1}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            const Spacer(),
            Tooltip(
              message: f.enabled ? 'Hide from plot' : 'Show in plot',
              child: Switch(
                value: f.enabled,
                onChanged: _isReadOnlyVisualizer
                    ? null
                    : (value) => _updateWorkspaceState(() => f.enabled = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Surface position r(u, v)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: _miniField(f.xCtrl, 'x')),
            const SizedBox(width: 8),
            Expanded(child: _miniField(f.yCtrl, 'y')),
            const SizedBox(width: 8),
            Expanded(child: _miniField(f.zCtrl, 'z')),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Vector components sampled at that position',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: _miniField(f.pCtrl, 'P')),
            const SizedBox(width: 8),
            Expanded(child: _miniField(f.qCtrl, 'Q')),
            const SizedBox(width: 8),
            Expanded(child: _miniField(f.rCtrl, 'R')),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: _isReadOnlyVisualizer
                  ? null
                  : () => _updateWorkspaceState(() => list.removeAt(i)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Time parameter t (optional):',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: _miniField(f.tMinCtrl, 't min')),
            const SizedBox(width: 8),
            Expanded(child: _miniField(f.tMaxCtrl, 't max')),
            const SizedBox(width: 8),
            Expanded(child: _miniField(f.tDurationCtrl, 'duration ms')),
          ],
        ),
        const SizedBox(height: 8),
        _coordinateChoice3D(
          value: f.coord3D,
          onChanged: (value) => _updateWorkspaceState(() => f.coord3D = value),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(width: 140, child: _miniField(f.dMinXCtrl, 'x min')),
            SizedBox(width: 140, child: _miniField(f.dMaxXCtrl, 'x max')),
            SizedBox(width: 140, child: _miniField(f.dMinYCtrl, 'y min')),
            SizedBox(width: 140, child: _miniField(f.dMaxYCtrl, 'y max')),
            SizedBox(width: 140, child: _miniField(f.dMinZCtrl, 'z min')),
            SizedBox(width: 140, child: _miniField(f.dMaxZCtrl, 'z max')),
          ],
        ),
      ],
    );
  }

  Widget _coordinateChoice3D({
    required CoordSystem3D value,
    required ValueChanged<CoordSystem3D> onChanged,
  }) {
    const options = [
      (value: CoordSystem3D.cartesian, label: 'Cartesian', hint: 'x, y, z'),
      (value: CoordSystem3D.cylindrical, label: 'Cylindrical', hint: 'r, θ, z'),
      (value: CoordSystem3D.spherical, label: 'Spherical', hint: 'ρ, θ, φ'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Coordinate system',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              ChoiceChip(
                label: Text('${option.label} (${option.hint})'),
                selected: value == option.value,
                onSelected: _isReadOnlyVisualizer
                    ? null
                    : (_) => onChanged(option.value),
              ),
          ],
        ),
      ],
    );
  }

  Widget _coordinateChoice2D({
    required CoordSystem2D value,
    required ValueChanged<CoordSystem2D> onChanged,
  }) {
    const options = [
      (value: CoordSystem2D.cartesian, label: 'Cartesian', hint: 'x, y'),
      (value: CoordSystem2D.polar, label: 'Polar', hint: 'r, θ'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Coordinate system',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              ChoiceChip(
                label: Text('${option.label} (${option.hint})'),
                selected: value == option.value,
                onSelected: _isReadOnlyVisualizer
                    ? null
                    : (_) => onChanged(option.value),
              ),
          ],
        ),
      ],
    );
  }

  Widget _miniField(TextEditingController c, String hint) {
    return SizedBox(
      height: 36,
      child: TextField(
        controller: c,
        readOnly: _isReadOnlyVisualizer,
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          filled: true,
          fillColor: Colors.white10,
        ),
        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
        onChanged: (_) {
          setState(() {});
          _markWorkspaceChanged();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final size = MediaQuery.of(context).size;
    final double kWidth = size.width < 1050 ? size.width * 0.95 : 1000.0;
    final double kHeight = size.height < 750 ? size.height * 0.85 : 700.0;

    return Container(
      width: kWidth,
      height: kHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1C1C1E).withValues(alpha: 0.65)
                  : colorScheme.surface.withValues(alpha: 0.75),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.5),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(32),
            ),
            clipBehavior: Clip.antiAlias,
            child: _showConverter
                ? UnitConverter(
                    initialValue:
                        _lastAnswer?.real ?? double.tryParse(_result) ?? 0.0,
                    onBack: _toggleConverter,
                    onDrag: widget.onDrag,
                    onClose: _closeCalculator,
                  )
                : Column(
                    children: [
                      _buildHeader(colorScheme),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _buildCalculatorUI(colorScheme),
                            _buildGraphUI(
                              colorScheme,
                              is3D: false,
                              isDark: isDark,
                            ),
                            _buildGraphUI(
                              colorScheme,
                              is3D: true,
                              isDark: isDark,
                            ),
                            _buildScalarUI(colorScheme, isDark: isDark),
                            _buildVectorUI(colorScheme, isDark: isDark),
                            _buildOdeUI(colorScheme, isDark: isDark),
                            _buildExtremaUI(colorScheme, isDark: isDark),
                            _buildCalculusUI(
                              colorScheme,
                              isDark: isDark,
                              overlayContext:
                                  widget.menuOverlayContext ?? context,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildScalarUI(ColorScheme colors, {required bool isDark}) {
    final enabledFunctions = _enabledScalarFunctions;
    return Stack(
      children: [
        GestureDetector(
          onScaleStart: (d) => _baseZoom3D = _zoom3D,
          onScaleUpdate: (d) => setState(() {
            if (d.scale == 1.0) {
              _yaw += d.focalPointDelta.dx * 0.5;
              _pitch -= d.focalPointDelta.dy * 0.5;
            } else {
              _zoom3D = _baseZoom3D * d.scale;
            }
          }),
          child: Container(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            width: double.infinity,
            height: double.infinity,
            child: RepaintBoundary(
              key: _scalarKey,
              child: Scalar3DWidget(
                surfaces: enabledFunctions
                    .map(
                      (f) => ScalarSurfaceDef(
                        exprX: f.xCtrl.text,
                        exprY: f.yCtrl.text,
                        exprZ: f.zCtrl.text,
                        scalarField: f.fCtrl.text,
                        tMin: parsePlotRealExpressionOrFallback(
                          _complexParser,
                          f.tMinCtrl.text,
                          0,
                        ),
                        tMax: parsePlotRealExpressionOrFallback(
                          _complexParser,
                          f.tMaxCtrl.text,
                          0,
                        ),
                        durationMs: int.tryParse(f.tDurationCtrl.text) ?? 0,
                        xMin: parsePlotOptionalBound(
                          _complexParser,
                          f.dMinXCtrl.text,
                        ),
                        xMax: parsePlotOptionalBound(
                          _complexParser,
                          f.dMaxXCtrl.text,
                        ),
                        yMin: parsePlotOptionalBound(
                          _complexParser,
                          f.dMinYCtrl.text,
                        ),
                        yMax: parsePlotOptionalBound(
                          _complexParser,
                          f.dMaxYCtrl.text,
                        ),
                        zMin: parsePlotOptionalBound(
                          _complexParser,
                          f.dMinZCtrl.text,
                        ),
                        zMax: parsePlotOptionalBound(
                          _complexParser,
                          f.dMaxZCtrl.text,
                        ),
                        coordSystem: f.coord3D,
                      ),
                    )
                    .toList(),
                gridCoordSystem: _activeCoordSystem3DFromScalar(
                  enabledFunctions,
                ),
                yaw: _yaw,
                pitch: _pitch,
                zoom: _zoom3D,
                centerX: _center3DX,
                centerY: _center3DY,
                centerZ: _center3DZ,
                isDarkMode: isDark,
                showLabels: _showLabels,
                autoRotate: _autoRotate3D,
              ),
            ),
          ),
        ),

        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    'f(x,y,z)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colors.onPrimaryContainer,
                      fontFamily: 'monospace',
                      fontSize: 16,
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: _isReadOnlyVisualizer
                        ? null
                        : () => setState(() => _showFunctionMenu = true),
                    child: Container(
                      color: Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.centerLeft,
                      height: 40,
                      child: Text(
                        _scalarFunctions.isEmpty
                            ? 'Tap to add surfaces...'
                            : '${_scalarFunctions.length} surface(s)',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 18,
                          color: colors.onSurface.withValues(alpha: 0.7),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: 'Edit surfaces',
                  onPressed: _isReadOnlyVisualizer
                      ? null
                      : () => setState(() => _showFunctionMenu = true),
                ),
              ],
            ),
          ),
        ),

        Positioned(
          bottom: 80,
          left: 24,
          child: PointerInterceptor(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.surfaceContainer.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.center_focus_strong, size: 16),
                  const SizedBox(width: 8),
                  _buildCoordInput(
                    "X",
                    _cXCtrl,
                    (v) => setState(() => _center3DX = v),
                  ),
                  const SizedBox(width: 8),
                  _buildCoordInput(
                    "Y",
                    _cYCtrl,
                    (v) => setState(() => _center3DY = v),
                  ),
                  const SizedBox(width: 8),
                  _buildCoordInput(
                    "Z",
                    _cZCtrl,
                    (v) => setState(() => _center3DZ = v),
                  ),
                ],
              ),
            ),
          ),
        ),

        Positioned(
          bottom: 24,
          right: 24,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_isReadOnlyVisualizer && _hasTimedAnimationForCurrentTab())
                _buildFab(
                  Icons.movie_creation_outlined,
                  _captureAnimatedGraphWithMetadata,
                  colors,
                  small: true,
                ),
              if (!_isReadOnlyVisualizer && _hasTimedAnimationForCurrentTab())
                const SizedBox(width: 10),
              if (!_isReadOnlyVisualizer)
                _buildFab(Icons.camera_alt, _captureGraph, colors),
            ],
          ),
        ),
        _buildStandard3DControls(colors),

        if (_showFunctionMenu && _tabController.index == 3)
          Stack(
            children: [
              GestureDetector(
                onTap: () => setState(() => _showFunctionMenu = false),
                child: Container(color: Colors.black.withValues(alpha: 0.4)),
              ),
              Center(
                child: Material(
                  elevation: 12,
                  borderRadius: BorderRadius.circular(24),
                  color: colors.surfaceContainer,
                  child: Container(
                    width: (MediaQuery.sizeOf(context).width * 0.92).clamp(
                      520.0,
                      980.0,
                    ),
                    height: (MediaQuery.sizeOf(context).height * 0.8).clamp(
                      460.0,
                      760.0,
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Scalar Fields',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: colors.onSurface,
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: _isReadOnlyVisualizer
                                  ? null
                                  : () => _resetPane(3),
                              icon: const Icon(Icons.restart_alt),
                              label: const Text('Reset pane'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  setState(() => _showFunctionMenu = false),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: ListView.separated(
                            itemCount: _scalarFunctions.length,
                            separatorBuilder: (c, i) =>
                                const Divider(height: 16),
                            itemBuilder: (ctx, i) => _buildScalarItem(
                              _scalarFunctions[i],
                              i,
                              _scalarFunctions,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            icon: const Icon(Icons.add),
                            label: const Text('Add New Surface'),
                            onPressed: _isReadOnlyVisualizer
                                ? null
                                : () => _updateWorkspaceState(
                                    () => _scalarFunctions.add(ScalarFuncDef()),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildVectorUI(ColorScheme colors, {required bool isDark}) {
    final enabledFunctions = _enabledVectorFunctions;
    return Stack(
      children: [
        GestureDetector(
          onScaleStart: (d) => _baseZoom3D = _zoom3D,
          onScaleUpdate: (d) => setState(() {
            if (d.scale == 1.0) {
              _yaw += d.focalPointDelta.dx * 0.5;
              _pitch -= d.focalPointDelta.dy * 0.5;
            } else {
              _zoom3D = _baseZoom3D * d.scale;
            }
          }),
          child: Container(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            width: double.infinity,
            height: double.infinity,
            child: RepaintBoundary(
              key: _vectorKey,
              child: Vector3DWidget(
                fields: enabledFunctions
                    .map(
                      (f) => VectorFieldDef(
                        exprX: f.xCtrl.text,
                        exprY: f.yCtrl.text,
                        exprZ: f.zCtrl.text,
                        funcP: f.pCtrl.text,
                        funcQ: f.qCtrl.text,
                        funcR: f.rCtrl.text,
                        tMin: parsePlotRealExpressionOrFallback(
                          _complexParser,
                          f.tMinCtrl.text,
                          0,
                        ),
                        tMax: parsePlotRealExpressionOrFallback(
                          _complexParser,
                          f.tMaxCtrl.text,
                          0,
                        ),
                        durationMs: int.tryParse(f.tDurationCtrl.text) ?? 0,
                        xMin: parsePlotOptionalBound(
                          _complexParser,
                          f.dMinXCtrl.text,
                        ),
                        xMax: parsePlotOptionalBound(
                          _complexParser,
                          f.dMaxXCtrl.text,
                        ),
                        yMin: parsePlotOptionalBound(
                          _complexParser,
                          f.dMinYCtrl.text,
                        ),
                        yMax: parsePlotOptionalBound(
                          _complexParser,
                          f.dMaxYCtrl.text,
                        ),
                        zMin: parsePlotOptionalBound(
                          _complexParser,
                          f.dMinZCtrl.text,
                        ),
                        zMax: parsePlotOptionalBound(
                          _complexParser,
                          f.dMaxZCtrl.text,
                        ),
                        coordSystem: f.coord3D,
                      ),
                    )
                    .toList(),
                gridCoordSystem: _activeCoordSystem3DFromVector(
                  enabledFunctions,
                ),
                yaw: _yaw,
                pitch: _pitch,
                zoom: _zoom3D,
                centerX: _center3DX,
                centerY: _center3DY,
                centerZ: _center3DZ,
                isDarkMode: isDark,
                showLabels: _showLabels,
                autoRotate: _autoRotate3D,
              ),
            ),
          ),
        ),

        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    '<P,Q,R>',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colors.onPrimaryContainer,
                      fontFamily: 'monospace',
                      fontSize: 16,
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: _isReadOnlyVisualizer
                        ? null
                        : () => setState(() => _showFunctionMenu = true),
                    child: Container(
                      color: Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.centerLeft,
                      height: 40,
                      child: Text(
                        _vectorFunctions.isEmpty
                            ? 'Tap to add fields...'
                            : '${_vectorFunctions.length} field(s)',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 18,
                          color: colors.onSurface.withValues(alpha: 0.7),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: 'Edit fields',
                  onPressed: _isReadOnlyVisualizer
                      ? null
                      : () => setState(() => _showFunctionMenu = true),
                ),
              ],
            ),
          ),
        ),

        Positioned(
          bottom: 80,
          left: 24,
          child: PointerInterceptor(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.surfaceContainer.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.center_focus_strong, size: 16),
                  const SizedBox(width: 8),
                  _buildCoordInput(
                    "X",
                    _cXCtrl,
                    (v) => setState(() => _center3DX = v),
                  ),
                  const SizedBox(width: 8),
                  _buildCoordInput(
                    "Y",
                    _cYCtrl,
                    (v) => setState(() => _center3DY = v),
                  ),
                  const SizedBox(width: 8),
                  _buildCoordInput(
                    "Z",
                    _cZCtrl,
                    (v) => setState(() => _center3DZ = v),
                  ),
                ],
              ),
            ),
          ),
        ),

        Positioned(
          bottom: 24,
          right: 24,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_isReadOnlyVisualizer && _hasTimedAnimationForCurrentTab())
                _buildFab(
                  Icons.movie_creation_outlined,
                  _captureAnimatedGraphWithMetadata,
                  colors,
                  small: true,
                ),
              if (!_isReadOnlyVisualizer && _hasTimedAnimationForCurrentTab())
                const SizedBox(width: 10),
              if (!_isReadOnlyVisualizer)
                _buildFab(Icons.camera_alt, _captureGraph, colors),
            ],
          ),
        ),
        _buildStandard3DControls(colors),

        if (_showFunctionMenu && _tabController.index == 4)
          Stack(
            children: [
              GestureDetector(
                onTap: () => setState(() => _showFunctionMenu = false),
                child: Container(color: Colors.black.withValues(alpha: 0.4)),
              ),
              Center(
                child: Material(
                  elevation: 12,
                  borderRadius: BorderRadius.circular(24),
                  color: colors.surfaceContainer,
                  child: Container(
                    width: (MediaQuery.sizeOf(context).width * 0.92).clamp(
                      520.0,
                      980.0,
                    ),
                    height: (MediaQuery.sizeOf(context).height * 0.8).clamp(
                      460.0,
                      760.0,
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Vector Fields',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: colors.onSurface,
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: _isReadOnlyVisualizer
                                  ? null
                                  : () => _resetPane(4),
                              icon: const Icon(Icons.restart_alt),
                              label: const Text('Reset pane'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  setState(() => _showFunctionMenu = false),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: ListView.separated(
                            itemCount: _vectorFunctions.length,
                            separatorBuilder: (c, i) =>
                                const Divider(height: 16),
                            itemBuilder: (ctx, i) => _buildVectorItem(
                              _vectorFunctions[i],
                              i,
                              _vectorFunctions,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            icon: const Icon(Icons.add),
                            label: const Text('Add New Field'),
                            onPressed: _isReadOnlyVisualizer
                                ? null
                                : () => _updateWorkspaceState(
                                    () => _vectorFunctions.add(VectorFuncDef()),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildStandard3DControls(ColorScheme colors) {
    return Stack(
      children: [
        Positioned(
          bottom: 24,
          left: 24,
          right: 90,
          child: Center(
            child: Container(
              height: 48,
              width: 380,
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(24),
              ),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                children: [
                  _buildViewChip('XY', 'Top', colors),
                  _buildViewChip('XZ', 'Front', colors),
                  _buildViewChip('YZ', 'Side', colors),
                  _buildViewChip('ISO', 'ISO', colors),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: 90,
          right: 16,
          child: Column(
            children: [
              _buildFab(Icons.add, _zoomIn, colors, small: true),
              const SizedBox(height: 12),
              _buildFab(Icons.remove, _zoomOut, colors, small: true),
              const SizedBox(height: 12),

              _buildFab(
                _showLabels ? Icons.numbers : Icons.grid_off,
                () => _updateWorkspaceState(() => _showLabels = !_showLabels),
                colors,
                small: true,
              ),
              const SizedBox(height: 12),
              _buildFab(
                _autoRotate3D ? Icons.pause_circle : Icons.play_circle,
                () =>
                    _updateWorkspaceState(() => _autoRotate3D = !_autoRotate3D),
                colors,
                small: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ColorScheme colors) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onPanUpdate: widget.onDrag,
      behavior: HitTestBehavior.translucent,
      child: Container(
        padding: const EdgeInsets.only(top: 16, bottom: 8, left: 24, right: 24),
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.science_outlined, size: 20, color: colors.onSurface),
                const SizedBox(width: 12),
                Text(
                  _isReadOnlyVisualizer
                      ? 'Plot Visualizer'
                      : 'Scientific Suite',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: colors.onSurface,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                if (!_isReadOnlyVisualizer)
                  IconButton(
                    icon: const Icon(Icons.sync_alt, size: 20),
                    tooltip: 'Unit Converter',
                    onPressed: _toggleConverter,
                    style: IconButton.styleFrom(
                      backgroundColor: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : colors.surfaceContainerHighest,
                      foregroundColor: colors.onSurface,
                    ),
                  ),
                if (!_isReadOnlyVisualizer) const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: _closeCalculator,
                  style: IconButton.styleFrom(
                    backgroundColor: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : colors.surfaceContainerHighest,
                    foregroundColor: colors.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: IgnorePointer(
                ignoring: _isReadOnlyVisualizer,
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : colors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : colors.outlineVariant.withValues(alpha: 0.3),
                    ),
                    boxShadow: isDark
                        ? []
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: colors.onSurface,
                  unselectedLabelColor: colors.onSurfaceVariant,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  dividerColor: Colors.transparent,
                  padding: const EdgeInsets.all(4),
                  isScrollable: true,
                  tabs: const [
                    Tab(text: 'CALC'),
                    Tab(text: '2D'),
                    Tab(text: '3D'),
                    Tab(text: 'SCALAR'),
                    Tab(text: 'VECTOR'),
                    Tab(text: 'ODE'),
                    Tab(text: 'CALCULUS'),
                    Tab(text: 'DER/QUAD'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildCalculatorUI(ColorScheme colors) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            color: Colors.transparent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: TextField(
                      controller: _expressionCtrl,
                      textAlign: TextAlign.end,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      style: TextStyle(
                        fontSize: 24,
                        fontFamily: 'monospace',
                        color: colors.onSurfaceVariant,
                      ),
                      readOnly: true,
                      showCursor: true,
                      maxLines: 2,
                    ),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SelectableText(
                    _result.isEmpty ? '0' : _result,
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: colors.onSurface,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: colors.outlineVariant.withValues(alpha: 0.3),
        ),
        Expanded(
          flex: 7,
          child: Container(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : colors.surfaceContainerLow.withValues(alpha: 0.5),
            padding: const EdgeInsets.all(8),
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bool isPortrait =
                    constraints.maxHeight > constraints.maxWidth ||
                    constraints.maxWidth < 500;
                return _buildKeypad(colors, isPortrait: isPortrait);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOdeUI(ColorScheme colors, {required bool isDark}) {
    final canRun = !_odeRunning;
    final canEdit = !_isReadOnlyVisualizer;
    final odeExpressions = <Widget>[
      _odeEquationField('dx/dt =', _odeDxCtrl, colors),
      if (_odeDimension >= 2) _odeEquationField('dy/dt =', _odeDyCtrl, colors),
      if (_odeDimension >= 3) _odeEquationField('dz/dt =', _odeDzCtrl, colors),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final useSideBySide = constraints.maxWidth > 900;
        final visualizer = Expanded(
          flex: useSideBySide ? 7 : 6,
          child: Container(
            width: double.infinity,
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: RepaintBoundary(
                    key: _odeKey,
                    child: OdeTrajectoryVisualizer(
                      samples: List<OdeSample>.from(_odeSamples),
                      dimension: _odeDimension,
                      isDarkMode: isDark,
                      showLabels: _showLabels,
                      showGrid: _showOdeGrid,
                      controller: _odeVizController,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _odeStatus,
                          style: TextStyle(
                            color: colors.onSurface,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton.filled(
                        icon: const Icon(Icons.remove),
                        onPressed: () => _odeVizController.zoomOut?.call(),
                        tooltip: 'Zoom out',
                      ),
                      const SizedBox(width: 4),
                      IconButton.filled(
                        icon: const Icon(Icons.add),
                        onPressed: () => _odeVizController.zoomIn?.call(),
                        tooltip: 'Zoom in',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

        final controls = Expanded(
          flex: useSideBySide ? 5 : 4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              border: Border(
                left: useSideBySide
                    ? BorderSide(
                        color: colors.outlineVariant.withValues(alpha: 0.5),
                      )
                    : BorderSide.none,
                top: useSideBySide
                    ? BorderSide.none
                    : BorderSide(
                        color: colors.outlineVariant.withValues(alpha: 0.5),
                      ),
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'System dimension',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 2, label: Text('2D system (x, y)')),
                      ButtonSegment(
                        value: 3,
                        label: Text('3D system (x, y, z)'),
                      ),
                    ],
                    selected: {_odeDimension},
                    onSelectionChanged: canEdit
                        ? (value) => _updateWorkspaceState(
                            () => _odeDimension = value.first,
                          )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Method',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: OdeIntegrationMethod.values
                        .map(
                          (method) => ChoiceChip(
                            label: Text(method.label),
                            selected: _odeMethod == method,
                            onSelected: canEdit
                                ? (_) => _updateWorkspaceState(
                                    () => _odeMethod = method,
                                  )
                                : null,
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Presets',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _odePresets
                        .map(
                          (preset) => ChoiceChip(
                            label: Text(preset.label),
                            selected: _odeSelectedPresetId == preset.id,
                            onSelected: canEdit
                                ? (_) => _applyOdePreset(preset)
                                : null,
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  ...odeExpressions,
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _miniField(_odeX0Ctrl, 'x0')),
                      if (_odeDimension >= 2) ...[
                        const SizedBox(width: 8),
                        Expanded(child: _miniField(_odeY0Ctrl, 'y0')),
                      ],
                      if (_odeDimension >= 3) ...[
                        const SizedBox(width: 8),
                        Expanded(child: _miniField(_odeZ0Ctrl, 'z0')),
                      ],
                      const SizedBox(width: 8),
                      Expanded(child: _miniField(_odeT0Ctrl, 't0')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _miniField(_odeStepCtrl, 'step h')),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _miniField(_odeToleranceCtrl, 'convergence tol'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _showLabels ? Icons.numbers : Icons.label_off,
                        ),
                        tooltip: _showLabels ? 'Hide labels' : 'Show labels',
                        onPressed: () => _updateWorkspaceState(
                          () => _showLabels = !_showLabels,
                        ),
                      ),
                      Text(
                        _showLabels ? 'Labels on' : 'Labels off',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: Icon(
                          _showOdeGrid ? Icons.grid_on : Icons.grid_off,
                        ),
                        tooltip: _showOdeGrid ? 'Hide grid' : 'Show grid',
                        onPressed: () => _updateWorkspaceState(
                          () => _showOdeGrid = !_showOdeGrid,
                        ),
                      ),
                      Text(
                        _showOdeGrid ? 'Grid on' : 'Grid off',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: canRun ? _startOdeSolver : null,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Play'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: !_odeRunning
                            ? null
                            : () => _stopOdeSolver(reason: 'Stopped by user'),
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: canEdit ? _clearOdeSolver : null,
                        icon: const Icon(Icons.clear_all),
                        label: const Text('Clear'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: canEdit ? () => _resetPane(5) : null,
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Reset pane'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _copyOdeValues,
                        icon: const Icon(Icons.copy_all),
                        label: const Text('Copy values'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!_isReadOnlyVisualizer)
                        FilledButton.tonalIcon(
                          onPressed: _captureGraph,
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Save image'),
                        ),
                      if (!_isReadOnlyVisualizer)
                        FilledButton.tonalIcon(
                          onPressed: _captureAnimatedGraphWithMetadata,
                          icon: const Icon(Icons.movie_creation_outlined),
                          label: const Text('Save image + metadata'),
                        ),
                    ],
                  ),
                  if (_odeConverged)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Converged: animation stopped automatically.',
                        style: TextStyle(
                          color: colors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );

        if (useSideBySide) {
          return Row(children: [visualizer, controls]);
        }

        return Column(children: [visualizer, controls]);
      },
    );
  }

  Widget _buildExtremaUI(ColorScheme colors, {required bool isDark}) {
    return ExtremaPane(
      colorScheme: colors,
      isDark: isDark,
      repaintBoundaryKey: _extremaKey,
      onCaptureRequested: () => _captureGraph(),
      forCapture: _extremaCaptureMode,
    );
  }

  Widget _buildCalculusUI(
    ColorScheme colors, {
    required bool isDark,
    BuildContext? overlayContext,
  }) {
    return CalculusPane(
      key: ValueKey('calculus-$_calculusResetNonce'),
      colorScheme: colors,
      isDark: isDark,
      overlayContext: overlayContext,
      initialMetadata: _calculusMetadata,
      onMetadataChanged: (metadata) {
        _calculusMetadata = metadata;
        _markWorkspaceChanged();
      },
    );
  }

  Widget _odeEquationField(
    String label,
    TextEditingController controller,
    ColorScheme colors,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        readOnly: _isReadOnlyVisualizer,
        onChanged: (_) {
          setState(() {});
          _markWorkspaceChanged();
        },
        decoration: InputDecoration(
          labelText: label,
          hintText: 'Use x,y,z,t and functions like sin(), exp()...',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          isDense: true,
        ),
        style: TextStyle(fontFamily: 'monospace', color: colors.onSurface),
      ),
    );
  }

  Widget _buildKeypad(ColorScheme colors, {required bool isPortrait}) {
    List<_Key> keys;

    if (isPortrait) {
      keys = [
        _Key(
          'SHIFT',
          type: _KeyType.func,
          action: () => setState(() => _isShifted = !_isShifted),
          isActive: _isShifted,
        ),
        _Key(
          'RAD',
          type: _KeyType.func,
          label: _isRad ? 'RAD' : 'DEG',
          action: () => setState(() => _isRad = !_isRad),
        ),
        _Key('(', type: _KeyType.func),
        _Key(')', type: _KeyType.func),
        _Key('AC', type: _KeyType.danger),

        _Key(_isShifted ? 'asin' : 'sin', type: _KeyType.func),
        _Key(_isShifted ? 'acos' : 'cos', type: _KeyType.func),
        _Key(_isShifted ? 'atan' : 'tan', type: _KeyType.func),
        _Key('^', type: _KeyType.func),
        _Key('√', value: 'sqrt', type: _KeyType.func),

        _Key('7'),
        _Key('8'),
        _Key('9'),
        _Key('DEL', label: '⌫', type: _KeyType.danger),
        _Key('÷', value: '/', type: _KeyType.op),
        _Key('4'),
        _Key('5'),
        _Key('6'),
        _Key('×', value: '*', type: _KeyType.op),
        _Key('log', value: 'log10', type: _KeyType.func),
        _Key('1'),
        _Key('2'),
        _Key('3'),
        _Key('-', type: _KeyType.op),
        _Key('ln', value: 'ln', type: _KeyType.func),
        _Key('0'),
        _Key('.'),
        _Key('ANS', value: 'ANS', type: _KeyType.primary),
        _Key('=', type: _KeyType.primary),
        _Key('+', type: _KeyType.op),
      ];
    } else {
      keys = [
        _Key(
          'SHIFT',
          type: _KeyType.func,
          action: () => setState(() => _isShifted = !_isShifted),
          isActive: _isShifted,
        ),
        _Key(
          'RAD',
          type: _KeyType.func,
          label: _isRad ? 'RAD' : 'DEG',
          action: () => setState(() => _isRad = !_isRad),
        ),
        _Key('(', type: _KeyType.func),
        _Key(')', type: _KeyType.func),
        _Key('AC', type: _KeyType.danger),

        _Key(_isShifted ? 'asin' : 'sin', type: _KeyType.func),
        _Key(_isShifted ? 'acos' : 'cos', type: _KeyType.func),
        _Key(_isShifted ? 'atan' : 'tan', type: _KeyType.func),
        _Key('log', value: 'log10', type: _KeyType.func),
        _Key('ln', value: 'ln', type: _KeyType.func),

        _Key(_isShifted ? 'asinh' : 'sinh', type: _KeyType.func),
        _Key(_isShifted ? 'acosh' : 'cosh', type: _KeyType.func),
        _Key(_isShifted ? 'atanh' : 'tanh', type: _KeyType.func),
        _Key('abs', type: _KeyType.func),
        _Key('^', type: _KeyType.func),

        _Key('√', value: 'sqrt', type: _KeyType.func),
        _Key('i', type: _KeyType.func),
        _Key('nCr', type: _KeyType.func),
        _Key('nPr', type: _KeyType.func),
        _Key(',', type: _KeyType.func),

        _Key('7'),
        _Key('8'),
        _Key('9'),
        _Key('DEL', label: '⌫', type: _KeyType.danger),
        _Key('÷', value: '/', type: _KeyType.op),
        _Key('4'),
        _Key('5'),
        _Key('6'),
        _Key('×', value: '*', type: _KeyType.op),
        _Key('π', value: 'pi', type: _KeyType.func),
        _Key('1'),
        _Key('2'),
        _Key('3'),
        _Key('-', type: _KeyType.op),
        _Key('e', type: _KeyType.func),
        _Key('0'),
        _Key('.'),
        _Key('ANS', value: 'ANS', type: _KeyType.primary),
        _Key('=', type: _KeyType.primary),
        _Key('+', type: _KeyType.op),
      ];
    }

    const int cols = 5;
    final int rows = (keys.length / cols).ceil();

    return Column(
      children: List.generate(rows, (rowIndex) {
        return Expanded(
          child: Row(
            children: List.generate(cols, (colIndex) {
              final index = rowIndex * cols + colIndex;
              if (index >= keys.length) return const Spacer();

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: _buildButton(keys[index], colors),
                ),
              );
            }),
          ),
        );
      }),
    );
  }

  Widget _buildButton(_Key key, ColorScheme colors) {
    Color bg;
    Color fg;

    switch (key.type) {
      case _KeyType.num:
        bg = colors.surfaceContainerHighest.withValues(alpha: 0.3);
        fg = colors.onSurface;
        break;
      case _KeyType.op:
        bg = colors.tertiaryContainer;
        fg = colors.onTertiaryContainer;
        break;
      case _KeyType.func:
        bg = key.isActive ? colors.primary : colors.surface;
        if (!key.isActive) bg = Colors.transparent;
        fg = key.isActive ? colors.onPrimary : colors.primary;
        break;
      case _KeyType.danger:
        bg = colors.errorContainer;
        fg = colors.onErrorContainer;
        break;
      case _KeyType.primary:
        bg = colors.primaryContainer;
        fg = colors.onPrimaryContainer;
        break;
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(24),
      elevation: key.isActive ? 4 : 0,
      clipBehavior: Clip.antiAlias,
      type: MaterialType.canvas,
      child: InkWell(
        onTap:
            key.action ?? () => _onKeyTap(key.label!, insertValue: key.value),
        splashColor: fg.withValues(alpha: 0.1),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: Text(
                key.label ?? key.value ?? '',
                style: TextStyle(
                  fontSize: key.label!.length > 3 ? 18 : 22,
                  fontWeight: key.type == _KeyType.num
                      ? FontWeight.w400
                      : FontWeight.bold,
                  color: fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGraphUI(
    ColorScheme colors, {
    required bool is3D,
    required bool isDark,
  }) {
    final activeList = _enabledPlotFunctions(is3D);

    return Stack(
      children: [
        if (is3D)
          GestureDetector(
            onScaleStart: (details) {
              _baseZoom3D = _zoom3D;
            },
            onScaleUpdate: (details) {
              setState(() {
                if (details.scale == 1.0) {
                  _yaw += details.focalPointDelta.dx * 0.5;
                  _pitch -= details.focalPointDelta.dy * 0.5;
                } else {
                  _zoom3D = _baseZoom3D * details.scale;
                }
              });
            },
            child: Container(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              width: double.infinity,
              height: double.infinity,
              child: RepaintBoundary(
                key: _plot3dKey,
                child: Plot3DWidget(
                  key: ValueKey(
                    'plot3d-center:${_center3DX}_${_center3DY}_${_center3DZ}',
                  ),
                  functions: activeList
                      .map(
                        (f) => PlotLine3D(
                          expression: f.controller.text,
                          color: f.color,
                          tMin: parsePlotRealExpressionOrFallback(
                            _complexParser,
                            f.tMinCtrl.text,
                            0,
                          ),
                          tMax: parsePlotRealExpressionOrFallback(
                            _complexParser,
                            f.tMaxCtrl.text,
                            0,
                          ),
                          durationMs: int.tryParse(f.tDurationCtrl.text) ?? 0,
                          xMin: parsePlotOptionalBound(
                            _complexParser,
                            f.dMinXCtrl.text,
                          ),
                          xMax: parsePlotOptionalBound(
                            _complexParser,
                            f.dMaxXCtrl.text,
                          ),
                          yMin: parsePlotOptionalBound(
                            _complexParser,
                            f.dMinYCtrl.text,
                          ),
                          yMax: parsePlotOptionalBound(
                            _complexParser,
                            f.dMaxYCtrl.text,
                          ),
                          zMin: parsePlotOptionalBound(
                            _complexParser,
                            f.dMinZCtrl.text,
                          ),
                          zMax: parsePlotOptionalBound(
                            _complexParser,
                            f.dMaxZCtrl.text,
                          ),
                          coordSystem: f.coord3D,
                        ),
                      )
                      .toList(),
                  gridCoordSystem: _activeCoordSystem3DFromFunctions(
                    activeList,
                  ),
                  isDarkMode: isDark,
                  yaw: _yaw,
                  pitch: _pitch,
                  zoom: _zoom3D,
                  centerX: _center3DX,
                  centerY: _center3DY,
                  centerZ: _center3DZ,
                  showLabels: _showLabels,
                  isComplex: _isComplexMode,
                  autoRotate: _autoRotate3D,
                ),
              ),
            ),
          )
        else
          GestureDetector(
            onScaleUpdate: (details) {
              setState(() {
                if (details.scale != 1.0) {
                  const sensitivity = 0.25;
                  final adjustedScale =
                      1.0 + (details.scale - 1.0) * sensitivity;
                  _zoom2D = (_zoom2D * adjustedScale).clamp(5.0, 400.0);
                }
                _offsetX += details.focalPointDelta.dx;
                _offsetY += details.focalPointDelta.dy;
              });
            },
            child: Container(
              width: double.infinity,
              height: double.infinity,
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              child: RepaintBoundary(
                key: _graphKey,
                child: ClipRect(
                  child: Plot2DWidget(
                    functions: activeList
                        .map(
                          (f) => PlotLine2D(
                            expression: f.controller.text,
                            color: f.color,
                            fillArea: f.fillArea,
                            tMin: parsePlotRealExpressionOrFallback(
                              _complexParser,
                              f.tMinCtrl.text,
                              0,
                            ),
                            tMax: parsePlotRealExpressionOrFallback(
                              _complexParser,
                              f.tMaxCtrl.text,
                              0,
                            ),
                            durationMs: int.tryParse(f.tDurationCtrl.text) ?? 0,
                            xMin: parsePlotOptionalBound(
                              _complexParser,
                              f.dMinXCtrl.text,
                            ),
                            xMax: parsePlotOptionalBound(
                              _complexParser,
                              f.dMaxXCtrl.text,
                            ),
                            yMin: parsePlotOptionalBound(
                              _complexParser,
                              f.dMinYCtrl.text,
                            ),
                            yMax: parsePlotOptionalBound(
                              _complexParser,
                              f.dMaxYCtrl.text,
                            ),
                            coordSystem: f.coord2D,
                          ),
                        )
                        .toList(),
                    gridCoordSystem: _activeCoordSystem2D(activeList),
                    offsetX: _offsetX,
                    offsetY: _offsetY,
                    zoom2D: _zoom2D,
                    isDarkMode: isDark,
                    accentColor: colors.primary,
                    isComplex: _isComplexMode,
                    showAxisLabels: _showLabels,
                  ),
                ),
              ),
            ),
          ),

        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    is3D ? 'z =' : 'f(x)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colors.onPrimaryContainer,
                      fontFamily: 'monospace',
                      fontSize: 16,
                    ),
                  ),
                ),

                Expanded(
                  child: GestureDetector(
                    onTap: _isReadOnlyVisualizer
                        ? null
                        : () => setState(() => _showFunctionMenu = true),
                    child: Container(
                      color: Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.centerLeft,
                      height: 40,
                      child: Text(
                        (is3D ? _plotFunctions3D : _plotFunctions2D).isEmpty
                            ? 'Tap to add functions...'
                            : activeList.isEmpty
                            ? '${(is3D ? _plotFunctions3D : _plotFunctions2D).length} saved, none visible'
                            : activeList.length == 1
                            ? activeList.first.controller.text
                            : '${activeList.length} visible / ${(is3D ? _plotFunctions3D : _plotFunctions2D).length} saved',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 18,
                          color: colors.onSurface.withValues(alpha: 0.7),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),

                IconButton(
                  icon: Icon(
                    _showLabels ? Icons.numbers : Icons.grid_off,
                    color: colors.primary,
                  ),
                  tooltip: _showLabels ? 'Hide Labels' : 'Show Labels',
                  onPressed: () =>
                      _updateWorkspaceState(() => _showLabels = !_showLabels),
                ),
                if (is3D)
                  IconButton(
                    icon: Icon(
                      _autoRotate3D ? Icons.pause_circle : Icons.play_circle,
                      color: colors.primary,
                    ),
                    tooltip: _autoRotate3D ? 'Stop Rotation' : 'Start Rotation',
                    onPressed: _isReadOnlyVisualizer
                        ? null
                        : () => _updateWorkspaceState(
                            () => _autoRotate3D = !_autoRotate3D,
                          ),
                  ),
                IconButton(
                  icon: Icon(
                    _isComplexMode ? Icons.hub : Icons.show_chart,
                    color: colors.primary,
                  ),
                  tooltip: _isComplexMode ? 'Complex Mode On' : 'Real Mode',
                  onPressed: _isReadOnlyVisualizer
                      ? null
                      : () => _updateWorkspaceState(
                          () => _isComplexMode = !_isComplexMode,
                        ),
                ),
                const SizedBox(width: 4),
                IconButton.filled(
                  icon: const Icon(Icons.play_arrow),
                  onPressed: _isReadOnlyVisualizer
                      ? null
                      : () => setState(() {}),
                  tooltip: 'Plot',
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),

        if (is3D)
          Positioned(
            bottom: 80,
            left: 24,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.surfaceContainer.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.center_focus_strong, size: 16),
                  const SizedBox(width: 8),
                  _buildCoordInput(
                    "X",
                    _cXCtrl,
                    (v) => setState(() => _center3DX = v),
                  ),
                  const SizedBox(width: 8),
                  _buildCoordInput(
                    "Y",
                    _cYCtrl,
                    (v) => setState(() => _center3DY = v),
                  ),
                  const SizedBox(width: 8),
                  _buildCoordInput(
                    "Z",
                    _cZCtrl,
                    (v) => setState(() => _center3DZ = v),
                  ),
                ],
              ),
            ),
          ),
        if (is3D)
          Positioned(
            bottom: 24,
            left: 24,
            right: 90,
            child: Center(
              child: Container(
                height: 48,
                width: 380,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  children: [
                    _buildViewChip("XY", "Top", colors),
                    _buildViewChip("XZ", "Front", colors),
                    _buildViewChip("YZ", "Side", colors),
                    _buildViewChip("ISO", "ISO", colors),
                  ],
                ),
              ),
            ),
          ),

        Positioned(
          top: 90,
          right: 16,
          child: Column(
            children: [
              _buildFab(Icons.add, _zoomIn, colors, small: true),
              const SizedBox(height: 12),
              _buildFab(Icons.remove, _zoomOut, colors, small: true),
            ],
          ),
        ),

        Positioned(
          bottom: 24,
          right: 24,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_isReadOnlyVisualizer && _hasTimedAnimationForCurrentTab())
                _buildFab(
                  Icons.movie_creation_outlined,
                  _captureAnimatedGraphWithMetadata,
                  colors,
                  small: true,
                ),
              if (!_isReadOnlyVisualizer && _hasTimedAnimationForCurrentTab())
                const SizedBox(width: 10),
              if (!_isReadOnlyVisualizer)
                _buildFab(Icons.camera_alt, _captureGraph, colors),
            ],
          ),
        ),

        if (!is3D)
          Positioned(
            bottom: 24,
            left: 24,
            child: _buildFab(
              Icons.center_focus_strong,
              () => setState(() {
                _offsetX = 0;
                _offsetY = 0;
                _zoom2D = 40.0;
              }),
              colors,
              small: true,
              secondary: true,
            ),
          ),

        if (_showFunctionMenu)
          Stack(
            children: [
              GestureDetector(
                onTap: () => setState(() => _showFunctionMenu = false),
                child: Container(color: Colors.black.withValues(alpha: 0.4)),
              ),
              Center(
                child: Material(
                  elevation: 12,
                  borderRadius: BorderRadius.circular(24),
                  color: colors.surfaceContainer,
                  child: Container(
                    width: (MediaQuery.sizeOf(context).width * 0.92).clamp(
                      520.0,
                      980.0,
                    ),
                    height: (MediaQuery.sizeOf(context).height * 0.78).clamp(
                      460.0,
                      740.0,
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              is3D ? "3D Surfaces" : "2D Functions",
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: colors.onSurface,
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: _isReadOnlyVisualizer
                                  ? null
                                  : () => _resetPane(is3D ? 2 : 1),
                              icon: const Icon(Icons.restart_alt),
                              label: const Text('Reset pane'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  setState(() => _showFunctionMenu = false),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: ListView.separated(
                            itemCount:
                                (is3D ? _plotFunctions3D : _plotFunctions2D)
                                    .length,
                            separatorBuilder: (c, i) =>
                                const Divider(height: 16),
                            itemBuilder: (ctx, i) {
                              final list = is3D
                                  ? _plotFunctions3D
                                  : _plotFunctions2D;
                              final func = list[i];
                              return Column(
                                children: [
                                  Row(
                                    children: [
                                      GestureDetector(
                                        onTap: _isReadOnlyVisualizer
                                            ? null
                                            : () => _updateWorkspaceState(
                                                () =>
                                                    func.color = _randomColor(),
                                              ),
                                        child: CircleAvatar(
                                          backgroundColor: func.color,
                                          radius: 14,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Tooltip(
                                        message: func.enabled
                                            ? 'Hide from plot'
                                            : 'Show in plot',
                                        child: IconButton(
                                          icon: Icon(
                                            func.enabled
                                                ? Icons.visibility
                                                : Icons.visibility_off,
                                          ),
                                          onPressed: _isReadOnlyVisualizer
                                              ? null
                                              : () => _updateWorkspaceState(
                                                  () => func.enabled =
                                                      !func.enabled,
                                                ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: TextField(
                                          controller: func.controller,
                                          readOnly: _isReadOnlyVisualizer,
                                          decoration: InputDecoration(
                                            isDense: true,
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 12,
                                                ),
                                            hintText: is3D
                                                ? 'z = f(x,y). Series: sum(n,a,b)(expr), product(n,a,b)(expr)'
                                                : 'y = f(x). Series: sum(n,a,b)(expr), product(n,a,b)(expr)',
                                          ),
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 16,
                                          ),
                                          onChanged: (_) {
                                            setState(() {});
                                            _markWorkspaceChanged();
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      if (!is3D)
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Text(
                                              "Fill",
                                              style: TextStyle(fontSize: 10),
                                            ),
                                            SizedBox(
                                              height: 24,
                                              width: 24,
                                              child: Checkbox(
                                                value: func.fillArea,
                                                onChanged: _isReadOnlyVisualizer
                                                    ? null
                                                    : (v) =>
                                                          _updateWorkspaceState(
                                                            () =>
                                                                func.fillArea =
                                                                    v ?? false,
                                                          ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.grey,
                                        ),
                                        onPressed: _isReadOnlyVisualizer
                                            ? null
                                            : () => _updateWorkspaceState(
                                                () => list.removeAt(i),
                                              ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _miniField(
                                          func.tMinCtrl,
                                          't min',
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: _miniField(
                                          func.tMaxCtrl,
                                          't max',
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: _miniField(
                                          func.tDurationCtrl,
                                          'duration ms',
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (!is3D)
                                    _coordinateChoice2D(
                                      value: func.coord2D,
                                      onChanged: (value) =>
                                          _updateWorkspaceState(
                                            () => func.coord2D = value,
                                          ),
                                    )
                                  else
                                    _coordinateChoice3D(
                                      value: func.coord3D,
                                      onChanged: (value) =>
                                          _updateWorkspaceState(
                                            () => func.coord3D = value,
                                          ),
                                    ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      SizedBox(
                                        width: 140,
                                        child: _miniField(
                                          func.dMinXCtrl,
                                          'x min',
                                        ),
                                      ),
                                      SizedBox(
                                        width: 140,
                                        child: _miniField(
                                          func.dMaxXCtrl,
                                          'x max',
                                        ),
                                      ),
                                      SizedBox(
                                        width: 140,
                                        child: _miniField(
                                          func.dMinYCtrl,
                                          'y min',
                                        ),
                                      ),
                                      SizedBox(
                                        width: 140,
                                        child: _miniField(
                                          func.dMaxYCtrl,
                                          'y max',
                                        ),
                                      ),
                                      if (is3D)
                                        SizedBox(
                                          width: 140,
                                          child: _miniField(
                                            func.dMinZCtrl,
                                            'z min',
                                          ),
                                        ),
                                      if (is3D)
                                        SizedBox(
                                          width: 140,
                                          child: _miniField(
                                            func.dMaxZCtrl,
                                            'z max',
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            icon: const Icon(Icons.add),
                            label: const Text('Add function'),
                            onPressed: _isReadOnlyVisualizer
                                ? null
                                : () {
                                    _updateWorkspaceState(() {
                                      (is3D
                                              ? _plotFunctions3D
                                              : _plotFunctions2D)
                                          .add(
                                            FunctionDef(
                                              initialText: '',
                                              color: _randomColor(),
                                            ),
                                          );
                                    });
                                  },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildViewChip(String code, String label, ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ActionChip(
        label: Text(label),
        avatar: CircleAvatar(
          backgroundColor: colors.primary.withValues(alpha: 0.2),
          child: Text(
            code[0],
            style: TextStyle(fontSize: 10, color: colors.primary),
          ),
        ),
        backgroundColor: Colors.transparent,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        onPressed: () => _resetView(code),
      ),
    );
  }

  Widget _buildFab(
    IconData icon,
    VoidCallback onTap,
    ColorScheme colors, {
    bool small = false,
    bool secondary = false,
  }) {
    return Container(
      width: small ? 40 : 56,
      height: small ? 40 : 56,
      decoration: BoxDecoration(
        color: secondary
            ? colors.surfaceContainerHigh
            : colors.primaryContainer,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(
            icon,
            color: secondary ? colors.onSurface : colors.onPrimaryContainer,
            size: small ? 20 : 24,
          ),
        ),
      ),
    );
  }

  Widget _buildCoordInput(
    String label,
    TextEditingController ctrl,
    Function(double) onChanged,
  ) {
    return SizedBox(
      width: 60,
      height: 30,
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
        decoration: InputDecoration(
          prefixText: '$label: ',
          prefixStyle: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: Colors.grey[600],
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 0,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.grey.withValues(alpha: 0.1),
        ),
        onSubmitted: (val) {
          final d = parsePlotRealExpression(_complexParser, val);
          if (d != null) {
            onChanged(d);
            _markWorkspaceChanged();
          }
        },
        onChanged: (val) {
          final d = parsePlotRealExpression(_complexParser, val);
          if (d != null) {
            onChanged(d);
            _markWorkspaceChanged();
          }
        },
      ),
    );
  }
}

enum _KeyType { num, op, func, danger, primary }

class _Key {
  final String? label;
  final String? value;
  final _KeyType type;
  final VoidCallback? action;
  final bool isActive;

  _Key(
    String val, {
    String? label,
    String? value,
    this.type = _KeyType.num,
    this.action,
    this.isActive = false,
  }) : label = label ?? val,
       value = value ?? val;
}
