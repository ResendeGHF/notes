// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:saber/components/canvas/pencil_grain_atlas.dart';
import 'package:saber/data/editor/stroke_paint.dart';

final _log = Logger('PencilShader');

/// Graphite grain via [FragmentProgram] (`shaders/pencil.frag`).
///
/// The grain is painted by filling ONE union path per stroke — live and
/// committed alike. A path fill shades every covered pixel exactly once, so
/// self-overlap at curves/joins can never double-darken and there are no mesh
/// triangle seams to hide. Geometry (spine outlines) and uniforms are shared
/// with the committed render, so the live stroke and the committed stroke
/// evaluate the identical page-anchored field.
///
/// One [ui.FragmentShader] per page; stays off tiles. Noise is sampled from
/// [PencilGrainAtlas] (two packed 256×256 tiles, hardware-sampled).
class PencilShader {
  PencilShader._();

  static ui.FragmentProgram? _program;
  static Future<void>? _loading;

  static Future<void> init() async {
    if (_program != null && PencilGrainAtlas.instance.isReady) return;
    final existing = _loading;
    if (existing != null) {
      await existing;
      return;
    }
    _loading = () async {
      try {
        await Future.wait([
          ui.FragmentProgram.fromAsset('shaders/pencil.frag').then((p) {
            _program = p;
          }),
          PencilGrainAtlas.instance.ensure(),
        ]);
      } catch (e, st) {
        _log.warning('Failed to load pencil.frag: $e', e, st);
        _program = null;
      }
    }();
    await _loading;
    _loading = null;
  }

  static Future<void> preload() => init();

  static bool get isReady =>
      _program != null && PencilGrainAtlas.instance.isReady;

  /// Creates a new [ui.FragmentShader] instance.
  ///
  /// **Memory Warning:** Ensure you call `.dispose()` on the returned shader
  /// when the `Paint` object or `Picture` using it is discarded, to prevent
  /// engine memory spikes during fast handwriting.
  static ui.FragmentShader? create() {
    final program = _program;
    if (program == null || !PencilGrainAtlas.instance.isReady) return null;
    final shader = program.fragmentShader();
    bindAtlas(shader);
    return shader;
  }

  static void bindAtlas(ui.FragmentShader shader) {
    final atlas = PencilGrainAtlas.instance;
    if (!atlas.isReady) return;
    shader
      ..setImageSampler(0, atlas.paper)
      ..setImageSampler(1, atlas.bristles);
  }

  /// Scale-only LOD bucket for layer [shouldRepaint] (not per-stroke size).
  static int lodTierForScale(double currentScale) {
    if (currentScale < 0.42) return 0;
    if (currentScale < 0.82) return 1;
    return 2;
  }

  /// Page pixels covered by one noise tile for [cfg].
  ///
  /// The default grain scale maps the atlas 1:1: 256 page px per tile, 1 atlas
  /// texel = 1 page pixel. Grain is never sampled *finer* than that here:
  /// sub-page-pixel content shimmers when the canvas shifts by a fraction of a
  /// pixel (pan) or when a cached picture is resampled, so tip size shapes the
  /// deposit structure instead of the frequency (see [tipMixFor]).
  /// [StrokePaint.noiseGrainScale] multiplies the tile size on top - styles
  /// that ask for finer grain trade that stability for crispness.
  static double grainTilePagePxFor(StrokePaint cfg) {
    final g = cfg.noiseGrainScale.clamp(0.01, 0.25);
    return (_grainTilePagePx * (g / PencilNoiseDefaults.grainScale))
        .clamp(64.0, 640.0);
  }

  /// Deposit-structure blend for a tip of [size] page px: 0 = fine tip (fine
  /// speckle, no broad blotches), 1 = broad tip (full lump/tooth drift, the
  /// reference look at size >= ~72).
  static double tipMixFor(double size) =>
      ((size - 12.0) / 60.0).clamp(0.0, 1.0);

  /// Page pixels covered by one noise tile at the default grain scale, at
  /// which 1 atlas texel maps to 1 page pixel (no minification aliasing).
  static const _grainTilePagePx = 256.0;

  /// Shader LOD: 0 while the grain is sub-pixel (cheap fetch path), fading to
  /// 1 as soon as one page pixel maps to one screen pixel (full grain), so the
  /// level of detail never steps visibly while zooming.
  static double qualityForScale(double currentScale) =>
      ((currentScale - 0.70) / 0.35).clamp(0.0, 1.0);

  /// Darkest deposit alpha (and fallback mean alpha scale) for [cfg].
  static double opacityMaxFor(StrokePaint cfg) {
    final threshold = cfg.noiseThreshold.clamp(0.05, 0.92);
    return (0.96 - 0.62 * threshold).clamp(0.30, 0.90);
  }

  /// Uploads the per-draw uniforms.
  ///
  /// No canvas transform is involved on purpose: the shader evaluates
  /// FlutterFragCoord() (local to the drawing command - page space for every
  /// pencil draw path), so the grain stays page-anchored no matter how the
  /// canvas is panned, zoomed, rasterized or replayed from a cached picture.
  static void configureBase(
    ui.FragmentShader shader,
    Color color, {
    required StrokePaint cfg,
    required double size,
    double seed = 0,
    double quality = 1.0,
    bool castShadow = false,
  }) {
    final freq = 1.0 / grainTilePagePxFor(cfg);
    final threshold = cfg.noiseThreshold.clamp(0.05, 0.92);
    final contrast = cfg.noiseContrast.clamp(0.35, 2.5);
    final fineMix = cfg.noiseFineMix.clamp(0.0, 1.0);

    shader
      ..setFloat(0, color.r)
      ..setFloat(1, color.g)
      ..setFloat(2, color.b)
      ..setFloat(3, freq)
      ..setFloat(4, opacityMaxFor(cfg))
      ..setFloat(5, seed)
      ..setFloat(6, contrast)
      ..setFloat(7, fineMix)
      ..setFloat(8, threshold)
      ..setFloat(9, quality.clamp(0.0, 1.0))
      ..setFloat(10, castShadow ? 1.0 : 0.0)
      ..setFloat(11, tipMixFor(size));
    bindAtlas(shader);
  }

  static final _grainPaint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true
    ..blendMode = BlendMode.srcOver;

  static final _shadowPaint = Paint()
    ..style = PaintingStyle.fill
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..blendMode = BlendMode.srcOver;

  /// Page-space light: shadow falls down-right (illustration convention).
  static const _shadowDirX = 0.55;
  static const _shadowDirY = 0.82;

  static double _shadowLift(double size) =>
      (0.62 + size * 0.038).clamp(0.72, 2.05);

  /// Contact shadow: reuse the grain outline, no blur / saveLayer / extra shader.
  ///
  /// Zoomed-out or crowded views keep a single umbra fill. Writing zoom adds a
  /// cheap penumbra (second fill + hairline) so the crescent is not a hard cut.
  static void paintCastShadow({
    required Canvas canvas,
    required Path outline,
    required Color strokeColor,
    required double size,
    required double currentScale,
    required int visibleCount,
    required double quality,
    required int lodTier,
    required bool enabled,
  }) {
    if (!enabled || lodTier <= 0) return;
    final lift = _shadowLift(size);
    if (lift * currentScale < 0.42) return;

    final dirLen = math.sqrt(
      _shadowDirX * _shadowDirX + _shadowDirY * _shadowDirY,
    );
    final ox = _shadowDirX / dirLen * lift;
    final oy = _shadowDirY / dirLen * lift;
    final umbra = Color.lerp(
      const Color(0xFF1C1612),
      strokeColor,
      0.16,
    )!.withValues(alpha: 0.18);
    final soft = quality > 0.5 && currentScale >= 0.82 && visibleCount <= 48;

    _shadowPaint
      ..shader = null
      ..maskFilter = null
      ..colorFilter = null
      ..style = PaintingStyle.fill
      ..isAntiAlias = quality > 0.5
      ..blendMode = BlendMode.srcOver;

    if (soft) {
      canvas.save();
      canvas.translate(ox * 0.4, oy * 0.4);
      _shadowPaint.color = umbra.withValues(alpha: 0.07);
      canvas.drawPath(outline, _shadowPaint);
      canvas.restore();
    }

    canvas.save();
    canvas.translate(ox, oy);
    _shadowPaint.color = umbra;
    canvas.drawPath(outline, _shadowPaint);
    if (soft) {
      _shadowPaint
        ..style = PaintingStyle.stroke
        ..strokeWidth = (0.8 + lift * 0.32).clamp(0.75, 1.85)
        ..color = umbra.withValues(alpha: 0.08);
      canvas.drawPath(outline, _shadowPaint);
      _shadowPaint.style = PaintingStyle.fill;
    }
    canvas.restore();
  }

  /// Graphite kernel: optional contact shadow, then ONE union-path fill.
  ///
  /// [outline] must be the full stroke outline as a single non-zero fill path
  /// (or the exact union of staged chunks), never a triangle mesh: a fill
  /// shades each pixel once, which is what makes overlap-safe translucent
  /// grain possible.
  static void paintGrainPath({
    required Canvas canvas,
    required ui.FragmentShader shader,
    required Color color,
    required StrokePaint cfg,
    required Path outline,
    required double currentScale,
    required int visibleCount,
    required double? strokeSize,
    bool configureBaseUniforms = true,
    // Interior staged chunks skip the contact shadow: a butt joint would
    // otherwise cast a hairline across the stroke interior.
    bool includeShadow = true,
  }) {
    final quality = qualityForScale(currentScale);
    final size = strokeSize ?? 4.0;

    if (configureBaseUniforms) {
      configureBase(
        shader,
        color,
        cfg: cfg,
        size: size,
        quality: quality,
        castShadow: cfg.pencilShadow,
      );
    }

    paintCastShadow(
      canvas: canvas,
      outline: outline,
      strokeColor: color,
      size: size,
      currentScale: currentScale,
      visibleCount: visibleCount,
      quality: quality,
      lodTier: lodTierForScale(currentScale),
      enabled: includeShadow && cfg.pencilShadow,
    );

    _grainPaint
      ..shader = shader
      ..colorFilter = null
      ..maskFilter = null
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..blendMode = BlendMode.srcOver;
    canvas.drawPath(outline, _grainPaint);
    _grainPaint.shader = null;
  }

  /// Shader-less fallback: one flat translucent fill of the same union path
  /// (mean graphite alpha), so live and committed still agree pixel-for-pixel
  /// on machines where the program failed to load.
  static void paintGrainFallback({
    required Canvas canvas,
    required Color color,
    required StrokePaint cfg,
    required Path outline,
    required double currentScale,
    required int visibleCount,
    required double? strokeSize,
    bool includeShadow = true,
  }) {
    final quality = qualityForScale(currentScale);

    paintCastShadow(
      canvas: canvas,
      outline: outline,
      strokeColor: color,
      size: strokeSize ?? 4.0,
      currentScale: currentScale,
      visibleCount: visibleCount,
      quality: quality,
      lodTier: lodTierForScale(currentScale),
      enabled: includeShadow && cfg.pencilShadow,
    );

    final alpha = (opacityMaxFor(cfg) * 0.6).clamp(0.05, 0.9);
    _grainPaint
      ..shader = null
      ..colorFilter = null
      ..maskFilter = null
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..blendMode = BlendMode.srcOver
      ..color = color.withValues(alpha: alpha);
    canvas.drawPath(outline, _grainPaint);
  }

  /// True when [color]/[cfg]/[quality]/[size] match the last [configure]
  /// inputs. Tip size participates because it scales the grain field.
  static bool sameConfig({
    required Color color,
    required StrokePaint cfg,
    required double quality,
    required double size,
    required Color? lastColor,
    required StrokePaint? lastCfg,
    required double? lastQuality,
    required double? lastSize,
  }) {
    if (lastColor == null ||
        lastCfg == null ||
        lastQuality == null ||
        lastSize == null) {
      return false;
    }

    if (lastColor != color) return false;

    if ((lastQuality - quality).abs() > 0.01) return false;

    if ((lastSize - size).abs() > 0.01) return false;

    if (identical(lastCfg, cfg)) return true;

    return lastCfg.mode == cfg.mode &&
        lastCfg.noiseGrainScale == cfg.noiseGrainScale &&
        lastCfg.noiseThreshold == cfg.noiseThreshold &&
        lastCfg.noiseContrast == cfg.noiseContrast &&
        lastCfg.noiseFineMix == cfg.noiseFineMix &&
        lastCfg.pressureMapsToCoverage == cfg.pressureMapsToCoverage &&
        lastCfg.pencilShadow == cfg.pencilShadow;
  }
}

class PencilShaderController {
  PencilShaderController._();
  static final instance = PencilShaderController._();

  Future<void> preload() => PencilShader.init();
  bool get isReady => PencilShader.isReady;
}
