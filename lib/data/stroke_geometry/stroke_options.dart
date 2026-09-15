// SPDX-FileCopyrightText: 2021 Stephen Ruiz
// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Adapted from perfect_freehand (MIT).

import 'package:saber/data/stroke_geometry/easings.dart';

/// Stroke outline options for pens (including Advanced pen).
class StrokeOptions {
  static double defaultSize = 16;
  static double defaultThinning = 0.5;
  static double defaultSmoothing = 0.5;
  static double defaultStreamline = 0.5;
  static double Function(double) defaultEasing = StrokeEasings.identity;
  static bool defaultSimulatePressure = true;
  static bool defaultIsComplete = false;
  static double defaultPressureSensitivity = 1.0;
  static double defaultVelocityThinning = 0.0;
  static double defaultMinSizeRatio = 0.12;
  static double defaultMaxSizeRatio = 1.0;

  double size;
  double thinning;
  double smoothing;
  double streamline;
  double Function(double) easing;
  bool simulatePressure;
  StrokeEndOptions start;
  StrokeEndOptions end;
  bool isComplete;

  /// Scales how strongly [thinning] reacts to pressure (Advanced pen).
  double pressureSensitivity;

  /// Extra width reduction from stroke speed (0–1).
  double velocityThinning;

  /// Floor / ceiling of local radius as a fraction of [size]/2.
  double minSizeRatio;
  double maxSizeRatio;

  StrokeOptions({
    double? size,
    double? thinning,
    double? smoothing,
    double? streamline,
    double Function(double)? easing,
    bool? simulatePressure,
    StrokeEndOptions? start,
    StrokeEndOptions? end,
    bool? isComplete,
    double? pressureSensitivity,
    double? velocityThinning,
    double? minSizeRatio,
    double? maxSizeRatio,
  }) : size = size ?? defaultSize,
       thinning = thinning ?? defaultThinning,
       smoothing = smoothing ?? defaultSmoothing,
       streamline = streamline ?? defaultStreamline,
       easing = easing ?? defaultEasing,
       simulatePressure = simulatePressure ?? defaultSimulatePressure,
       start = start ?? StrokeEndOptions.start(),
       end = end ?? StrokeEndOptions.end(),
       isComplete = isComplete ?? defaultIsComplete,
       pressureSensitivity =
           pressureSensitivity ?? defaultPressureSensitivity,
       velocityThinning = velocityThinning ?? defaultVelocityThinning,
       minSizeRatio = minSizeRatio ?? defaultMinSizeRatio,
       maxSizeRatio = maxSizeRatio ?? defaultMaxSizeRatio;

  StrokeOptions.fromJson(
    Map<String, dynamic> json, {
    double Function(double)? easing,
    double Function(double)? startEasing,
    double Function(double)? endEasing,
  }) : size = (json['s'] as num?)?.toDouble() ?? StrokeOptions.defaultSize,
       thinning =
           (json['t'] as num?)?.toDouble() ?? StrokeOptions.defaultThinning,
       smoothing =
           (json['sm'] as num?)?.toDouble() ?? StrokeOptions.defaultSmoothing,
       streamline =
           (json['sl'] as num?)?.toDouble() ?? StrokeOptions.defaultStreamline,
       easing = easing ?? defaultEasing,
       simulatePressure =
           json['sp'] as bool? ?? StrokeOptions.defaultSimulatePressure,
       start = StrokeEndOptions.start(
         customTaper: (json['ts'] as num?)?.toDouble(),
         cap: json['cs'] as bool? ?? StrokeEndOptions.defaultCap,
         easing: startEasing,
       ),
       end = StrokeEndOptions.end(
         customTaper: (json['te'] as num?)?.toDouble(),
         cap: json['ce'] as bool? ?? StrokeEndOptions.defaultCap,
         easing: endEasing,
       ),
       isComplete = json['f'] as bool? ?? true,
       pressureSensitivity =
           (json['ps'] as num?)?.toDouble() ??
           StrokeOptions.defaultPressureSensitivity,
       velocityThinning =
           (json['vt'] as num?)?.toDouble() ??
           StrokeOptions.defaultVelocityThinning,
       minSizeRatio =
           (json['msr'] as num?)?.toDouble() ??
           StrokeOptions.defaultMinSizeRatio,
       maxSizeRatio =
           (json['xsr'] as num?)?.toDouble() ??
           StrokeOptions.defaultMaxSizeRatio;

  Map<String, dynamic> toJson() => {
    if (size != StrokeOptions.defaultSize) 's': size,
    if (thinning != StrokeOptions.defaultThinning) 't': thinning,
    if (smoothing != StrokeOptions.defaultSmoothing) 'sm': smoothing,
    if (streamline != StrokeOptions.defaultStreamline) 'sl': streamline,
    if (start.taperEnabled) 'ts': start.customTaper ?? -1.0,
    if (end.taperEnabled) 'te': end.customTaper ?? -1.0,
    if (start.cap != StrokeEndOptions.defaultCap) 'cs': start.cap,
    if (end.cap != StrokeEndOptions.defaultCap) 'ce': end.cap,
    if (simulatePressure != StrokeOptions.defaultSimulatePressure)
      'sp': simulatePressure,
    if (isComplete != true) 'f': isComplete,
    if (pressureSensitivity != StrokeOptions.defaultPressureSensitivity)
      'ps': pressureSensitivity,
    if (velocityThinning != StrokeOptions.defaultVelocityThinning)
      'vt': velocityThinning,
    if (minSizeRatio != StrokeOptions.defaultMinSizeRatio) 'msr': minSizeRatio,
    if (maxSizeRatio != StrokeOptions.defaultMaxSizeRatio) 'xsr': maxSizeRatio,
  };

  StrokeOptions copyWith({
    double? size,
    double? thinning,
    double? smoothing,
    double? streamline,
    double Function(double)? easing,
    bool? simulatePressure,
    StrokeEndOptions? start,
    StrokeEndOptions? end,
    bool? isComplete,
    double? pressureSensitivity,
    double? velocityThinning,
    double? minSizeRatio,
    double? maxSizeRatio,
  }) => StrokeOptions(
    size: size ?? this.size,
    thinning: thinning ?? this.thinning,
    smoothing: smoothing ?? this.smoothing,
    streamline: streamline ?? this.streamline,
    easing: easing ?? this.easing,
    simulatePressure: simulatePressure ?? this.simulatePressure,
    start: start ?? this.start,
    end: end ?? this.end,
    isComplete: isComplete ?? this.isComplete,
    pressureSensitivity: pressureSensitivity ?? this.pressureSensitivity,
    velocityThinning: velocityThinning ?? this.velocityThinning,
    minSizeRatio: minSizeRatio ?? this.minSizeRatio,
    maxSizeRatio: maxSizeRatio ?? this.maxSizeRatio,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StrokeOptions &&
        other.size == size &&
        other.thinning == thinning &&
        other.smoothing == smoothing &&
        other.streamline == streamline &&
        other.easing == easing &&
        other.simulatePressure == simulatePressure &&
        other.start == start &&
        other.end == end &&
        other.isComplete == isComplete &&
        other.pressureSensitivity == pressureSensitivity &&
        other.velocityThinning == velocityThinning &&
        other.minSizeRatio == minSizeRatio &&
        other.maxSizeRatio == maxSizeRatio;
  }

  @override
  int get hashCode => Object.hashAll([
    size,
    thinning,
    smoothing,
    streamline,
    easing,
    simulatePressure,
    start,
    end,
    isComplete,
    pressureSensitivity,
    velocityThinning,
    minSizeRatio,
    maxSizeRatio,
  ]);
}

class StrokeEndOptions {
  static bool defaultCap = true;
  static bool defaultTaperEnabled = false;

  bool cap;
  bool taperEnabled;
  double? customTaper;
  double Function(double) easing;

  StrokeEndOptions._({
    required this.cap,
    required this.taperEnabled,
    this.customTaper,
    required this.easing,
  }) {
    if (customTaper != null) {
      taperEnabled = customTaper != 0;
      if (customTaper == -1) customTaper = null;
    }
  }

  StrokeEndOptions.start({
    bool? cap,
    bool? taperEnabled,
    double? customTaper,
    double Function(double)? easing,
  }) : this._(
         cap: cap ?? defaultCap,
         taperEnabled: taperEnabled ?? defaultTaperEnabled,
         customTaper: customTaper,
         easing: easing ?? StrokeEasings.easeInOut,
       );

  StrokeEndOptions.end({
    bool? cap,
    bool? taperEnabled,
    double? customTaper,
    double Function(double)? easing,
  }) : this._(
         cap: cap ?? defaultCap,
         taperEnabled: taperEnabled ?? defaultTaperEnabled,
         customTaper: customTaper,
         easing: easing ?? StrokeEasings.easeOutCubic,
       );

  StrokeEndOptions copyWith({
    bool? cap,
    bool? taperEnabled,
    required double? customTaper,
    double Function(double)? easing,
  }) => StrokeEndOptions._(
    cap: cap ?? this.cap,
    taperEnabled: taperEnabled ?? this.taperEnabled,
    customTaper: customTaper,
    easing: easing ?? this.easing,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StrokeEndOptions &&
        other.cap == cap &&
        other.taperEnabled == taperEnabled &&
        other.customTaper == customTaper &&
        other.easing == easing;
  }

  @override
  int get hashCode => Object.hashAll([cap, taperEnabled, customTaper, easing]);
}
