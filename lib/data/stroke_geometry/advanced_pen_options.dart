// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Advanced pen brush options: Dart mirror of Rnote's brush configuration
// (crates/rnote-engine/src/pens/pensconfig/brushconfig.rs +
//  crates/rnote-compose/src/style/{mod,smooth} + builders/mod.rs) and of the
// smoothing parameters of flxzt/ink-stroke-modeler-rs (src/params.rs,
// itself a port of google/ink-stroke-modeler params.h).
//
// Why a Dart port instead of flutter_rust_bridge?
// The math is deterministic (wobble average, spring-mass Euler integration,
// linear upsampling, variable-width ribbon composer). A faithful port gives
// bit-equivalent strokes on every Flutter target — including web, where FFI
// is unavailable — with no native build, no codegen and no per-platform
// toolchain. See [AdvancedPenStrokeModeler] for the modeler port and
// [composeAdvancedOutline] for the ribbon composer port.

import 'dart:math' as math;

/// How raw input is turned into path elements, mirroring
/// `PenPathBuilderType` in Rnote (`rnote-compose/src/builders/mod.rs`).
enum AdvancedPenBuilderType {
  /// Raw input points become `LineTo` segments (no smoothing).
  simple('simple'),

  /// Catmull-Rom points become cubic segments, then flattened to lines.
  curved('curved'),

  /// Google ink-stroke-modeler smoothing (`PenPathModeledBuilder`).
  /// This is Rnote's default and the recommended setting.
  modeled('modeled');

  final String id;
  const AdvancedPenBuilderType(this.id);

  static AdvancedPenBuilderType fromId(String? id, {AdvancedPenBuilderType fallback = AdvancedPenBuilderType.modeled}) {
    for (final v in AdvancedPenBuilderType.values) {
      if (v.id == id) return v;
    }
    return fallback;
  }
}

/// Pressure-to-width mapping, mirroring `PressureCurve` in
/// `rnote-compose/src/style/mod.rs`.
enum AdvancedPenPressureCurve {
  /// Constant width (Rnote Marker style).
  constant('const'),

  /// width * pressure (Rnote Solid default).
  linear('linear'),

  /// width * sqrt(pressure).
  sqrt('sqrt'),

  /// width * cbrt(pressure).
  cbrt('cbrt'),

  /// width * pressure^2.
  pow2('pow2'),

  /// width * pressure^3.
  pow3('pow3');

  final String id;
  const AdvancedPenPressureCurve(this.id);

  static AdvancedPenPressureCurve fromId(String? id, {AdvancedPenPressureCurve fallback = AdvancedPenPressureCurve.linear}) {
    for (final v in AdvancedPenPressureCurve.values) {
      if (v.id == id) return v;
    }
    return fallback;
  }

  /// Port of `PressureCurve::apply(width, pressure)`.
  double apply(double width, double pressure) {
    final p = pressure.clamp(0.0, 1.0);
    return switch (this) {
      AdvancedPenPressureCurve.constant => width,
      AdvancedPenPressureCurve.linear => width * p,
      AdvancedPenPressureCurve.sqrt => width * math.sqrt(p),
      AdvancedPenPressureCurve.cbrt => width * _cbrt(p),
      AdvancedPenPressureCurve.pow2 => width * p * p,
      AdvancedPenPressureCurve.pow3 => width * p * p * p,
    };
  }

  static double _cbrt(double x) {
    if (x == 0) return 0;
    // Dart has no cbrt; pow(x, 1/3) is exact for x >= 0 here.
    return math.pow(x, 1.0 / 3.0).toDouble();
  }
}

/// Line caps, mirroring `LineCap` in Rnote smooth options.
enum AdvancedPenLineCap {
  straight('straight'),
  rounded('rounded');

  final String id;
  const AdvancedPenLineCap(this.id);

  static AdvancedPenLineCap fromId(String? id, {AdvancedPenLineCap fallback = AdvancedPenLineCap.rounded}) {
    for (final v in AdvancedPenLineCap.values) {
      if (v.id == id) return v;
    }
    return fallback;
  }
}

/// Smoothing parameters for [AdvancedPenStrokeModeler].
///
/// Field docs mirror `ModelerParams` in ink-stroke-modeler-rs `src/params.rs`.
/// Defaults mirror Rnote's `MODELER_PARAMS` in
/// `penpathmodeledbuilder.rs` (which overrides a subset of
/// `ModelerParams::suggested()`).
class AdvancedPenModelerParams {
  /// Window for the wobble moving average. Good starting point:
  /// 2.5 / input_rate. Must be > 0.
  final double wobbleTimeout;

  /// Speed range for wobble smoothing. At [wobbleSpeedFloor] maximum
  /// smoothing is applied; at [wobbleSpeedCeiling] none is. Good starting
  /// points are 2-3% of expected input speed. Must be > 0 and floor < ceiling.
  final double wobbleSpeedFloor;
  final double wobbleSpeedCeiling;

  /// Spring-mass constant of the tip model. Must be > 0.
  final double springMassConstant;

  /// Drag constant of the tip model. Must be > 0.
  final double dragConstant;

  /// Minimum modeled outputs per unit time (upsampling rate). Must be > 0.
  final double minOutputRate;

  /// End-of-stroke stop distance (~2-3 orders smaller than expected
  /// inter-point distance). Must be > 0.
  final double endOfStrokeStoppingDistance;

  /// Max end-of-stroke iterations. Must be > 0 and < 1000.
  final int endOfStrokeMaxIterations;

  /// Max outputs per update/predict call (guards against huge time gaps).
  /// Must be > 0.
  final int maxOutputsPerCall;

  /// Raw inputs kept for stylus (pressure) interpolation. Must be > 0.
  final int maxInputSamples;

  const AdvancedPenModelerParams({
    required this.wobbleTimeout,
    required this.wobbleSpeedFloor,
    required this.wobbleSpeedCeiling,
    required this.springMassConstant,
    required this.dragConstant,
    required this.minOutputRate,
    required this.endOfStrokeStoppingDistance,
    required this.endOfStrokeMaxIterations,
    required this.maxOutputsPerCall,
    required this.maxInputSamples,
  });

  /// `ModelerParams::suggested()` from ink-stroke-modeler-rs.
  static const suggested = AdvancedPenModelerParams(
    wobbleTimeout: 0.04,
    wobbleSpeedFloor: 1.31,
    wobbleSpeedCeiling: 1.44,
    springMassConstant: 11.0 / 32400.0,
    dragConstant: 72.0,
    minOutputRate: 180.0,
    endOfStrokeStoppingDistance: 0.001,
    endOfStrokeMaxIterations: 20,
    maxOutputsPerCall: 20,
    maxInputSamples: 10,
  );

  /// What Rnote actually uses (`MODELER_PARAMS` in
  /// `penpathmodeledbuilder.rs`): suggested params with a lower output rate
  /// (120 Hz), a looser stop distance (0.01), larger per-call budget (200)
  /// and a deeper stylus window (20).
  static const advancedDefaults = AdvancedPenModelerParams(
    wobbleTimeout: 0.04,
    wobbleSpeedFloor: 1.31,
    wobbleSpeedCeiling: 1.44,
    springMassConstant: 11.0 / 32400.0,
    dragConstant: 72.0,
    minOutputRate: 120.0,
    endOfStrokeStoppingDistance: 0.01,
    endOfStrokeMaxIterations: 20,
    maxOutputsPerCall: 200,
    maxInputSamples: 20,
  );

  AdvancedPenModelerParams copyWith({
    double? wobbleTimeout,
    double? wobbleSpeedFloor,
    double? wobbleSpeedCeiling,
    double? springMassConstant,
    double? dragConstant,
    double? minOutputRate,
    double? endOfStrokeStoppingDistance,
    int? endOfStrokeMaxIterations,
    int? maxOutputsPerCall,
    int? maxInputSamples,
  }) {
    return AdvancedPenModelerParams(
      wobbleTimeout: wobbleTimeout ?? this.wobbleTimeout,
      wobbleSpeedFloor: wobbleSpeedFloor ?? this.wobbleSpeedFloor,
      wobbleSpeedCeiling: wobbleSpeedCeiling ?? this.wobbleSpeedCeiling,
      springMassConstant: springMassConstant ?? this.springMassConstant,
      dragConstant: dragConstant ?? this.dragConstant,
      minOutputRate: minOutputRate ?? this.minOutputRate,
      endOfStrokeStoppingDistance: endOfStrokeStoppingDistance ?? this.endOfStrokeStoppingDistance,
      endOfStrokeMaxIterations: endOfStrokeMaxIterations ?? this.endOfStrokeMaxIterations,
      maxOutputsPerCall: maxOutputsPerCall ?? this.maxOutputsPerCall,
      maxInputSamples: maxInputSamples ?? this.maxInputSamples,
    );
  }

  /// Mirrors `ModelerParams::validate()`. Returns null when valid,
  /// otherwise a human-readable reason.
  String? validate() {
    final errors = <String>[];
    if (springMassConstant <= 0) errors.add('springMassConstant must be > 0');
    if (dragConstant <= 0) errors.add('dragConstant must be > 0');
    if (minOutputRate <= 0) errors.add('minOutputRate must be > 0');
    if (endOfStrokeStoppingDistance <= 0) errors.add('endOfStrokeStoppingDistance must be > 0');
    if (endOfStrokeMaxIterations <= 0) errors.add('endOfStrokeMaxIterations must be > 0');
    if (endOfStrokeMaxIterations >= 1000) errors.add('endOfStrokeMaxIterations must be < 1000');
    if (maxOutputsPerCall <= 0) errors.add('maxOutputsPerCall must be > 0');
    if (wobbleTimeout <= 0) errors.add('wobbleTimeout must be > 0');
    if (wobbleSpeedFloor <= 0) errors.add('wobbleSpeedFloor must be > 0');
    if (wobbleSpeedCeiling <= 0) errors.add('wobbleSpeedCeiling must be > 0');
    if (wobbleSpeedFloor >= wobbleSpeedCeiling) {
      errors.add('wobbleSpeedFloor must be < wobbleSpeedCeiling');
    }
    if (maxInputSamples <= 0) errors.add('maxInputSamples must be > 0');
    if (errors.isEmpty) return null;
    return errors.join('; ');
  }

  Map<String, dynamic> toJson() => {
        'wobbleTimeout': wobbleTimeout,
        'wobbleSpeedFloor': wobbleSpeedFloor,
        'wobbleSpeedCeiling': wobbleSpeedCeiling,
        'springMassConstant': springMassConstant,
        'dragConstant': dragConstant,
        'minOutputRate': minOutputRate,
        'endOfStrokeStoppingDistance': endOfStrokeStoppingDistance,
        'endOfStrokeMaxIterations': endOfStrokeMaxIterations,
        'maxOutputsPerCall': maxOutputsPerCall,
        'maxInputSamples': maxInputSamples,
      };

  factory AdvancedPenModelerParams.fromJson(Map<String, dynamic> json) {
    double d(String k, double fallback) => (json[k] as num?)?.toDouble() ?? fallback;
    int i(String k, int fallback) => (json[k] as num?)?.toInt() ?? fallback;
    return AdvancedPenModelerParams(
      wobbleTimeout: d('wobbleTimeout', advancedDefaults.wobbleTimeout),
      wobbleSpeedFloor: d('wobbleSpeedFloor', advancedDefaults.wobbleSpeedFloor),
      wobbleSpeedCeiling: d('wobbleSpeedCeiling', advancedDefaults.wobbleSpeedCeiling),
      springMassConstant: d('springMassConstant', advancedDefaults.springMassConstant),
      dragConstant: d('dragConstant', advancedDefaults.dragConstant),
      minOutputRate: d('minOutputRate', advancedDefaults.minOutputRate),
      endOfStrokeStoppingDistance:
          d('endOfStrokeStoppingDistance', advancedDefaults.endOfStrokeStoppingDistance),
      endOfStrokeMaxIterations:
          i('endOfStrokeMaxIterations', advancedDefaults.endOfStrokeMaxIterations),
      maxOutputsPerCall: i('maxOutputsPerCall', advancedDefaults.maxOutputsPerCall),
      maxInputSamples: i('maxInputSamples', advancedDefaults.maxInputSamples),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AdvancedPenModelerParams &&
        other.wobbleTimeout == wobbleTimeout &&
        other.wobbleSpeedFloor == wobbleSpeedFloor &&
        other.wobbleSpeedCeiling == wobbleSpeedCeiling &&
        other.springMassConstant == springMassConstant &&
        other.dragConstant == dragConstant &&
        other.minOutputRate == minOutputRate &&
        other.endOfStrokeStoppingDistance == endOfStrokeStoppingDistance &&
        other.endOfStrokeMaxIterations == endOfStrokeMaxIterations &&
        other.maxOutputsPerCall == maxOutputsPerCall &&
        other.maxInputSamples == maxInputSamples;
  }

  @override
  int get hashCode => Object.hash(
        wobbleTimeout,
        wobbleSpeedFloor,
        wobbleSpeedCeiling,
        springMassConstant,
        dragConstant,
        minOutputRate,
        endOfStrokeStoppingDistance,
        endOfStrokeMaxIterations,
        maxOutputsPerCall,
        maxInputSamples,
      );
}

/// Full Advanced pen brush configuration for one pen.
///
/// Width lives in `StrokeOptions.size` (shared pen slider + presets), exactly
/// like every other Saber pen — this keeps `SizePicker`, bounds, exports and
/// old notes working unchanged. `pressureCurve` + `lineCap` mirror Rnote's
/// `SmoothOptions`; `builderType` mirrors `PenPathBuilderType`;
/// [modeler] mirrors Rnote's `MODELER_PARAMS`.
class AdvancedPenOptions {
  AdvancedPenPressureCurve pressureCurve;
  AdvancedPenLineCap lineCap;
  AdvancedPenBuilderType builderType;
  AdvancedPenModelerParams modeler;
  
  double velocityThinning;
  double tipAngle;
  double tipRatio;
  bool useTilt;
  double dashLength;
  double dashGap;

  AdvancedPenOptions({
    required this.pressureCurve,
    required this.lineCap,
    required this.builderType,
    required this.modeler,
    this.velocityThinning = 0.0,
    this.tipAngle = 0.0,
    this.tipRatio = 1.0,
    this.useTilt = false,
    this.dashLength = 0.0,
    this.dashGap = 0.0,
  });

  /// Solid defaults (as in Rnote): linear pressure, rounded caps, modeled
  /// builder with Rnote's modeler params.
  factory AdvancedPenOptions.advancedDefaults() => AdvancedPenOptions(
        pressureCurve: AdvancedPenPressureCurve.linear,
        lineCap: AdvancedPenLineCap.rounded,
        builderType: AdvancedPenBuilderType.modeled,
        modeler: AdvancedPenModelerParams.advancedDefaults,
        velocityThinning: 0.0,
        tipAngle: 0.0,
        tipRatio: 1.0,
        useTilt: false,
        dashLength: 0.0,
        dashGap: 0.0,
      );

  /// Marker defaults (as in Rnote): constant pressure (fixed width),
  /// straight caps.
  factory AdvancedPenOptions.markerDefaults() => AdvancedPenOptions(
        pressureCurve: AdvancedPenPressureCurve.constant,
        lineCap: AdvancedPenLineCap.straight,
        builderType: AdvancedPenBuilderType.modeled,
        modeler: AdvancedPenModelerParams.advancedDefaults,
        velocityThinning: 0.0,
        tipAngle: 0.0,
        tipRatio: 1.0,
        useTilt: false,
        dashLength: 0.0,
        dashGap: 0.0,
      );

  AdvancedPenOptions copyWith({
    AdvancedPenPressureCurve? pressureCurve,
    AdvancedPenLineCap? lineCap,
    AdvancedPenBuilderType? builderType,
    AdvancedPenModelerParams? modeler,
    double? velocityThinning,
    double? tipAngle,
    double? tipRatio,
    bool? useTilt,
    double? dashLength,
    double? dashGap,
  }) {
    return AdvancedPenOptions(
      pressureCurve: pressureCurve ?? this.pressureCurve,
      lineCap: lineCap ?? this.lineCap,
      builderType: builderType ?? this.builderType,
      modeler: modeler ?? this.modeler,
      velocityThinning: velocityThinning ?? this.velocityThinning,
      tipAngle: tipAngle ?? this.tipAngle,
      tipRatio: tipRatio ?? this.tipRatio,
      useTilt: useTilt ?? this.useTilt,
      dashLength: dashLength ?? this.dashLength,
      dashGap: dashGap ?? this.dashGap,
    );
  }

  Map<String, dynamic> toJson() => {
        'pressureCurve': pressureCurve.id,
        'lineCap': lineCap.id,
        'builderType': builderType.id,
        'modeler': modeler.toJson(),
        'velocityThinning': velocityThinning,
        'tipAngle': tipAngle,
        'tipRatio': tipRatio,
        'useTilt': useTilt,
        'dashLength': dashLength,
        'dashGap': dashGap,
      };

  factory AdvancedPenOptions.fromJson(Map<String, dynamic> json) {
    final modelerRaw = json['modeler'];
    return AdvancedPenOptions(
      pressureCurve: AdvancedPenPressureCurve.fromId(json['pressureCurve'] as String?),
      lineCap: AdvancedPenLineCap.fromId(json['lineCap'] as String?),
      builderType: AdvancedPenBuilderType.fromId(json['builderType'] as String?),
      modeler: modelerRaw is Map
          ? AdvancedPenModelerParams.fromJson(Map<String, dynamic>.from(modelerRaw))
          : AdvancedPenModelerParams.advancedDefaults,
      velocityThinning: (json['velocityThinning'] as num?)?.toDouble() ?? 0.0,
      tipAngle: (json['tipAngle'] as num?)?.toDouble() ?? 0.0,
      tipRatio: (json['tipRatio'] as num?)?.toDouble() ?? 1.0,
      useTilt: json['useTilt'] as bool? ?? false,
      dashLength: (json['dashLength'] as num?)?.toDouble() ?? 0.0,
      dashGap: (json['dashGap'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AdvancedPenOptions &&
        other.pressureCurve == pressureCurve &&
        other.lineCap == lineCap &&
        other.builderType == builderType &&
        other.modeler == modeler &&
        other.velocityThinning == velocityThinning &&
        other.tipAngle == tipAngle &&
        other.tipRatio == tipRatio &&
        other.useTilt == useTilt &&
        other.dashLength == dashLength &&
        other.dashGap == dashGap;
  }

  @override
  int get hashCode => Object.hash(pressureCurve, lineCap, builderType, modeler, velocityThinning, tipAngle, tipRatio, useTilt, dashLength, dashGap);
}
