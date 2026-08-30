// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:saber/data/editor/stroke_paint_shader_cache.dart';

/// Butterfly-style stroke surface: solid, tiled image/SVG, gradient, or
/// procedural pencil noise (Advanced Pencil).
enum StrokePaintMode {
  solid,
  image,
  svg,
  linearGradient,
  radialGradient,
  pencilNoise,
}

class StrokePaintStop {
  const StrokePaintStop({required this.offset, required this.color});

  final double offset;
  final Color color;

  Map<String, dynamic> toJson() => {
    'o': offset,
    'c': color.toARGB32(),
  };

  factory StrokePaintStop.fromJson(Map<String, dynamic> json) {
    return StrokePaintStop(
      offset: (json['o'] as num?)?.toDouble() ?? 0,
      color: Color((json['c'] as num?)?.toInt() ?? 0xFF000000),
    );
  }
}

/// Default Advanced Pencil grain (cellular speckles, world-anchored).
class PencilNoiseDefaults {
  /// Smaller = finer grains.
  static const double grainScale = 0.05;
  /// Higher = more paper gaps / sparser graphite.
  static const double threshold = 0.40;
  /// Higher = harder grain edges.
  static const double contrast = 1.25;
  /// Higher = more fine salt-and-pepper grit.
  static const double fineMix = 0.55;
}

/// Fill/paint description for freehand strokes (advanced pen / pencil).
class StrokePaint {
  const StrokePaint({
    this.mode = StrokePaintMode.solid,
    this.tint = const Color(0xFFFFFFFF),
    this.blur = 0,
    this.imageScale = 0.25,
    this.assetId,
    this.bytes,
    this.gradientStart = Offset.zero,
    this.gradientEnd = const Offset(1, 0),
    this.gradientCenter = const Offset(0.5, 0.5),
    this.gradientRadius = 0.5,
    this.stops = const [
      StrokePaintStop(offset: 0, color: Color(0xFF374151)),
      StrokePaintStop(offset: 1, color: Color(0xFFE5E7EB)),
    ],
    this.noiseGrainScale = PencilNoiseDefaults.grainScale,
    this.noiseThreshold = PencilNoiseDefaults.threshold,
    this.noiseContrast = PencilNoiseDefaults.contrast,
    this.noiseFineMix = PencilNoiseDefaults.fineMix,
    this.pressureMapsToCoverage = false,
    this.pencilShadow = false,
  });

  factory StrokePaint.solid({Color tint = const Color(0xFFFFFFFF)}) =>
      StrokePaint(mode: StrokePaintMode.solid, tint: tint);

  /// Efficient default pencil grain for Advanced Pencil.
  factory StrokePaint.pencilNoiseDefault() => const StrokePaint(
    mode: StrokePaintMode.pencilNoise,
    noiseGrainScale: PencilNoiseDefaults.grainScale,
    noiseThreshold: PencilNoiseDefaults.threshold,
    noiseContrast: PencilNoiseDefaults.contrast,
    noiseFineMix: PencilNoiseDefaults.fineMix,
  );

  final StrokePaintMode mode;
  final Color tint;
  final double blur;
  final double imageScale;

  /// Note asset index when texture is stored in [AssetCacheAll].
  final int? assetId;

  /// Raw PNG/JPEG/SVG bytes (prefs / live paint / fallback embed).
  final Uint8List? bytes;

  final Offset gradientStart;
  final Offset gradientEnd;
  final Offset gradientCenter;
  final double gradientRadius;
  final List<StrokePaintStop> stops;

  /// Procedural pencil noise (Advanced Pencil shader uniforms).
  final double noiseGrainScale;
  final double noiseThreshold;
  final double noiseContrast;
  final double noiseFineMix;

  /// When true, stylus pressure changes grain coverage instead of stroke width.
  final bool pressureMapsToCoverage;

  /// Cheap page-space contact shadow under Advanced Pencil grain.
  final bool pencilShadow;

  bool get isSolid => mode == StrokePaintMode.solid;

  bool get usesTexture =>
      mode == StrokePaintMode.image || mode == StrokePaintMode.svg;

  bool get usesGradient =>
      mode == StrokePaintMode.linearGradient ||
      mode == StrokePaintMode.radialGradient;

  bool get usesPencilNoise => mode == StrokePaintMode.pencilNoise;

  Color get gradientColorA =>
      stops.isNotEmpty ? stops.first.color : const Color(0xFF374151);

  Color get gradientColorB =>
      stops.length > 1 ? stops[1].color : const Color(0xFFE5E7EB);

  String get cacheKey {
    if (bytes != null && bytes!.isNotEmpty) {
      final b = bytes!;
      var h = b.length;
      final step = math.max(1, b.length ~/ 32);
      for (var i = 0; i < b.length; i += step) {
        h = 0x1fffffff & (h * 31 + b[i]);
      }
      return '${mode.name}:$h:${b.length}';
    }
    return '${mode.name}:a${assetId ?? -1}';
  }

  StrokePaint copyWith({
    StrokePaintMode? mode,
    Color? tint,
    double? blur,
    double? imageScale,
    int? assetId,
    Uint8List? bytes,
    bool clearBytes = false,
    bool clearAssetId = false,
    Offset? gradientStart,
    Offset? gradientEnd,
    Offset? gradientCenter,
    double? gradientRadius,
    List<StrokePaintStop>? stops,
    double? noiseGrainScale,
    double? noiseThreshold,
    double? noiseContrast,
    double? noiseFineMix,
    bool? pressureMapsToCoverage,
    bool? pencilShadow,
  }) {
    return StrokePaint(
      mode: mode ?? this.mode,
      tint: tint ?? this.tint,
      blur: blur ?? this.blur,
      imageScale: imageScale ?? this.imageScale,
      assetId: clearAssetId ? null : (assetId ?? this.assetId),
      bytes: clearBytes ? null : (bytes ?? this.bytes),
      gradientStart: gradientStart ?? this.gradientStart,
      gradientEnd: gradientEnd ?? this.gradientEnd,
      gradientCenter: gradientCenter ?? this.gradientCenter,
      gradientRadius: gradientRadius ?? this.gradientRadius,
      stops: stops ?? this.stops,
      noiseGrainScale: noiseGrainScale ?? this.noiseGrainScale,
      noiseThreshold: noiseThreshold ?? this.noiseThreshold,
      noiseContrast: noiseContrast ?? this.noiseContrast,
      noiseFineMix: noiseFineMix ?? this.noiseFineMix,
      pressureMapsToCoverage:
          pressureMapsToCoverage ?? this.pressureMapsToCoverage,
      pencilShadow: pencilShadow ?? this.pencilShadow,
    );
  }

  StrokePaint withGradientColors(Color a, Color b) {
    return copyWith(
      stops: [
        StrokePaintStop(offset: 0, color: a),
        StrokePaintStop(offset: 1, color: b),
      ],
    );
  }

  Map<String, dynamic> toJson({bool embedBytes = true}) {
    return {
      'm': mode.index,
      't': tint.toARGB32(),
      'b': blur,
      'is': imageScale,
      if (assetId != null) 'aid': assetId,
      if (embedBytes && bytes != null && bytes!.isNotEmpty && assetId == null)
        'bytes': base64Encode(bytes!),
      'gs': {'x': gradientStart.dx, 'y': gradientStart.dy},
      'ge': {'x': gradientEnd.dx, 'y': gradientEnd.dy},
      'gc': {'x': gradientCenter.dx, 'y': gradientCenter.dy},
      'gr': gradientRadius,
      'st': stops.map((s) => s.toJson()).toList(),
      'ngs': noiseGrainScale,
      'nth': noiseThreshold,
      'nct': noiseContrast,
      'nfm': noiseFineMix,
      'pmc': pressureMapsToCoverage,
      'psh': pencilShadow,
    };
  }

  factory StrokePaint.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const StrokePaint();
    final modeIdx = (json['m'] as num?)?.toInt() ?? 0;
    final mode = (modeIdx >= 0 && modeIdx < StrokePaintMode.values.length)
        ? StrokePaintMode.values[modeIdx]
        : StrokePaintMode.solid;
    Uint8List? bytes;
    final raw = json['bytes'];
    if (raw is String && raw.isNotEmpty) {
      try {
        bytes = Uint8List.fromList(base64Decode(raw));
      } catch (_) {}
    }
    Offset o(dynamic v, Offset fallback) {
      if (v is! Map) return fallback;
      return Offset(
        (v['x'] as num?)?.toDouble() ?? fallback.dx,
        (v['y'] as num?)?.toDouble() ?? fallback.dy,
      );
    }

    final stopList = <StrokePaintStop>[];
    final st = json['st'];
    if (st is List) {
      for (final e in st) {
        if (e is Map<String, dynamic>) {
          stopList.add(StrokePaintStop.fromJson(e));
        } else if (e is Map) {
          stopList.add(StrokePaintStop.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return StrokePaint(
      mode: mode,
      tint: Color((json['t'] as num?)?.toInt() ?? 0xFFFFFFFF),
      blur: (json['b'] as num?)?.toDouble() ?? 0,
      imageScale: (json['is'] as num?)?.toDouble() ?? 0.25,
      assetId: (json['aid'] as num?)?.toInt(),
      bytes: bytes,
      gradientStart: o(json['gs'], Offset.zero),
      gradientEnd: o(json['ge'], const Offset(1, 0)),
      gradientCenter: o(json['gc'], const Offset(0.5, 0.5)),
      gradientRadius: (json['gr'] as num?)?.toDouble() ?? 0.5,
      stops: stopList.isEmpty
          ? const [
              StrokePaintStop(offset: 0, color: Color(0xFF374151)),
              StrokePaintStop(offset: 1, color: Color(0xFFE5E7EB)),
            ]
          : stopList,
      noiseGrainScale:
          (json['ngs'] as num?)?.toDouble() ?? PencilNoiseDefaults.grainScale,
      noiseThreshold:
          (json['nth'] as num?)?.toDouble() ?? PencilNoiseDefaults.threshold,
      noiseContrast:
          (json['nct'] as num?)?.toDouble() ?? PencilNoiseDefaults.contrast,
      noiseFineMix:
          (json['nfm'] as num?)?.toDouble() ?? PencilNoiseDefaults.fineMix,
      pressureMapsToCoverage: json['pmc'] == true,
      pencilShadow: json['psh'] == true,
    );
  }

  /// Configures [paint] for textured/gradient fill over [bounds].
  /// Pencil grain uses upstream-Saber [FragmentShader] via [PencilShader].
  ///
  /// [useShaderCache] reuses ImageShader/Gradient objects across frames.
  void applyTo(
    Paint paint,
    Rect bounds, {
    ui.Image? texture,
    bool useShaderCache = true,
  }) {
    paint.maskFilter = blur > 0
        ? ui.MaskFilter.blur(ui.BlurStyle.normal, blur)
        : null;
    paint.colorFilter = null;
    paint.shader = null;

    switch (mode) {
      case StrokePaintMode.solid:
      case StrokePaintMode.pencilNoise:
        return;
      case StrokePaintMode.image:
      case StrokePaintMode.svg:
        if (texture == null) return;
        final shader = useShaderCache
            ? StrokePaintShaderCache.instance.imageShader(texture, imageScale)
            : ui.ImageShader(
                texture,
                TileMode.repeated,
                TileMode.repeated,
                Matrix4.diagonal3Values(
                  imageScale.clamp(0.02, 8.0),
                  imageScale.clamp(0.02, 8.0),
                  1,
                ).storage,
              );
        paint
          ..shader = shader
          ..colorFilter = ColorFilter.mode(tint, BlendMode.modulate);
        return;
      case StrokePaintMode.linearGradient:
        if (useShaderCache) {
          paint.shader =
              StrokePaintShaderCache.instance.linearGradient(this, bounds);
        } else {
          final colors = stops.map((s) => s.color).toList();
          final offsets = stops.map((s) => s.offset.clamp(0.0, 1.0)).toList();
          if (colors.length < 2) return;
          final start = Offset(
            bounds.left + gradientStart.dx * bounds.width,
            bounds.top + gradientStart.dy * bounds.height,
          );
          final end = Offset(
            bounds.left + gradientEnd.dx * bounds.width,
            bounds.top + gradientEnd.dy * bounds.height,
          );
          paint.shader = ui.Gradient.linear(start, end, colors, offsets);
        }
        return;
      case StrokePaintMode.radialGradient:
        if (useShaderCache) {
          paint.shader =
              StrokePaintShaderCache.instance.radialGradient(this, bounds);
        } else {
          final colors = stops.map((s) => s.color).toList();
          final offsets = stops.map((s) => s.offset.clamp(0.0, 1.0)).toList();
          if (colors.length < 2) return;
          final diag =
              math.sqrt(
                bounds.width * bounds.width + bounds.height * bounds.height,
              ) /
              2;
          paint.shader = ui.Gradient.radial(
            Offset(
              bounds.left + gradientCenter.dx * bounds.width,
              bounds.top + gradientCenter.dy * bounds.height,
            ),
            (gradientRadius.clamp(0.01, 2.0)) * diag,
            colors,
            offsets,
          );
        }
        return;
    }
  }
}
