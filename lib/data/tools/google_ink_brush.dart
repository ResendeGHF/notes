// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

/// Dart-side model of the Google Ink brush stack
/// (https://github.com/google/ink + ink-stroke-modeler, exposed on Android
/// via androidx.ink `Brush` / `StockBrushes` / `InProgressStrokesView`).
///
/// The experimental pen never uses `perfect_freehand` (`getStroke`). Live ink
/// is modeled + rasterized natively on Android (120Hz MotionEvent, pressure /
/// tilt / orientation) and committed strokes are re-built here with a
/// sliding-window input model + family-specific tip, so committed ink flows
/// through the same tiled Picture + temporary-raster LOD path as every other
/// pen.

/// Stock brush families mirrored from `androidx.ink.brush.StockBrushes`.
/// Keep ids stable: they are persisted per-stroke and sent over the
/// `google_ink` MethodChannel to Kotlin.
enum GoogleInkBrushFamily {
  pressurePen('pressurePen'),
  marker('marker'),
  highlighter('highlighter'),
  brush('brush'),
  calligraphy('calligraphy'),
  dashedLine('dashedLine');

  final String id;
  const GoogleInkBrushFamily(this.id);

  static GoogleInkBrushFamily parse(String? id, {GoogleInkBrushFamily fallback = GoogleInkBrushFamily.pressurePen}) {
    if (id == null) return fallback;
    for (final v in values) {
      if (v.id == id) return v;
    }
    return fallback;
  }

  /// Human label for the pen modal test UI.
  String get label => switch (this) {
        GoogleInkBrushFamily.pressurePen => 'Pressure pen',
        GoogleInkBrushFamily.marker => 'Marker',
        GoogleInkBrushFamily.highlighter => 'Highlighter',
        GoogleInkBrushFamily.brush => 'Brush',
        GoogleInkBrushFamily.calligraphy => 'Calligraphy',
        GoogleInkBrushFamily.dashedLine => 'Dashed line',
      };

  /// Whether the tip width responds to pressure (native Brush behavior).
  bool get respondsToPressure => switch (this) {
        GoogleInkBrushFamily.marker => false,
        GoogleInkBrushFamily.dashedLine => false,
        GoogleInkBrushFamily.highlighter => false,
        _ => true,
      };

  /// Whether the tip is angle-driven (flat nib) instead of round.
  bool get isNib => this == GoogleInkBrushFamily.calligraphy;
}

/// Tunable Google Ink brush + input-model config.
///
/// Maps 1:1 to the native `Brush`:
/// - `family` -> `StockBrushes.*` BrushFamily
/// - `size` -> `Brush.size` (stroke units / logical px)
/// - `colorArgb` -> `Brush.createWithColorIntArgb`
/// - `epsilon` -> `Brush.epsilon` (geometry fidelity vs memory)
///
/// Plus the `BrushFamily.InputModel` / authoring knobs exposed for testing:
/// - `smoothingWindowMs` -> SlidingWindowModel averaging window
/// - `predictionEnabled` + `predictionAmount` -> MotionEventPredictor lead
/// - `pressureSensitivity`, `tiltResponse`, `velocityResponse`
final class GoogleInkBrushConfig {
  GoogleInkBrushConfig({
    this.family = GoogleInkBrushFamily.pressurePen,
    this.size = 4.0,
    this.colorArgb = 0xFF000000,
    this.epsilon = 0.1,
    this.smoothingWindowMs = 16.0,
    this.predictionEnabled = true,
    this.predictionAmount = 0.5,
    this.pressureSensitivity = 1.0,
    this.tiltResponse = 0.5,
    this.velocityResponse = 0.35,
    this.useNativeView = true,
    this.minSizeRatio = 0.08,
    this.maxSizeRatio = 1.0,
  });

  GoogleInkBrushFamily family;
  double size;
  int colorArgb;
  double epsilon;
  double smoothingWindowMs;
  bool predictionEnabled;
  double predictionAmount;
  double pressureSensitivity;
  double tiltResponse;
  double velocityResponse;
  bool useNativeView;
  double minSizeRatio;
  double maxSizeRatio;

  static const double minSize = 0.5;
  static const double maxSize = 48.0;
  static const double minEpsilon = 0.01;
  static const double maxEpsilon = 1.0;

  GoogleInkBrushConfig copy() => GoogleInkBrushConfig(
        family: family,
        size: size,
        colorArgb: colorArgb,
        epsilon: epsilon,
        smoothingWindowMs: smoothingWindowMs,
        predictionEnabled: predictionEnabled,
        predictionAmount: predictionAmount,
        pressureSensitivity: pressureSensitivity,
        tiltResponse: tiltResponse,
        velocityResponse: velocityResponse,
        useNativeView: useNativeView,
        minSizeRatio: minSizeRatio,
        maxSizeRatio: maxSizeRatio,
      );

  Map<String, dynamic> toJson() => {
        'family': family.id,
        'size': size,
        'colorArgb': colorArgb,
        'epsilon': epsilon,
        'smoothingWindowMs': smoothingWindowMs,
        'predictionEnabled': predictionEnabled,
        'predictionAmount': predictionAmount,
        'pressureSensitivity': pressureSensitivity,
        'tiltResponse': tiltResponse,
        'velocityResponse': velocityResponse,
        'useNativeView': useNativeView,
        'minSizeRatio': minSizeRatio,
        'maxSizeRatio': maxSizeRatio,
      };

  factory GoogleInkBrushConfig.fromJson(Map<String, dynamic> json) {
    double d(Object? v, double fb) =>
        v is num ? v.toDouble() : fb;
    return GoogleInkBrushConfig(
      family: GoogleInkBrushFamily.parse(json['family'] as String?),
      size: d(json['size'], 4.0).clamp(minSize, maxSize),
      colorArgb: json['colorArgb'] is int
          ? json['colorArgb'] as int
          : 0xFF000000,
      epsilon: d(json['epsilon'], 0.1).clamp(minEpsilon, maxEpsilon),
      smoothingWindowMs: d(json['smoothingWindowMs'], 16.0).clamp(0, 120),
      predictionEnabled: json['predictionEnabled'] as bool? ?? true,
      predictionAmount: d(json['predictionAmount'], 0.5).clamp(0, 1),
      pressureSensitivity: d(json['pressureSensitivity'], 1.0).clamp(0, 2),
      tiltResponse: d(json['tiltResponse'], 0.5).clamp(0, 1),
      velocityResponse: d(json['velocityResponse'], 0.35).clamp(0, 1),
      useNativeView: json['useNativeView'] as bool? ?? true,
      minSizeRatio: d(json['minSizeRatio'], 0.08).clamp(0.01, 1),
      maxSizeRatio: d(json['maxSizeRatio'], 1.0).clamp(0.2, 2),
    );
  }

  /// Payload sent to Kotlin over `com.resendeghf.notes/google_ink`.
  Map<String, dynamic> toNativeMap() => {
        'family': family.id,
        'size': size,
        'colorArgb': colorArgb,
        'epsilon': epsilon,
        'smoothingWindowMs': smoothingWindowMs,
        'predictionEnabled': predictionEnabled,
        'predictionAmount': predictionAmount,
        'pressureSensitivity': pressureSensitivity,
        'tiltResponse': tiltResponse,
        'velocityResponse': velocityResponse,
      };
}
