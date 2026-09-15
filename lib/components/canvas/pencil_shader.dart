// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:saber/components/canvas/pencil_grain_atlas.dart';
import 'package:saber/data/editor/stroke_paint.dart';
import 'package:saber/data/stroke_geometry/point_vector.dart';

final _log = Logger('PencilShader');

/// Advanced Pencil grain via [FragmentProgram] (`shaders/pencil.frag`).
///
/// Path-oriented, page-anchored grain. Live and committed use the same
/// painter with zoom LOD. One [ui.FragmentShader] per page; stays off tiles.
/// Noise is sampled from [PencilGrainAtlas] (Skia image samplers).
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

  static double stampWidthFor(double size, double maxSizeRatio) =>
      size * maxSizeRatio.clamp(0.5, 3.0) * 1.35;

  static double stampMinSegLen(double size) => math.max(2.4, size * 0.32);

  static const double stampMinDirDot = 0.96;

  static void configureBase(
    ui.FragmentShader shader,
    Color color, {
    required StrokePaint cfg,
    Offset coordOffset = Offset.zero,
    double seed = 0,
    double quality = 1.0,
    bool castShadow = false,
  }) {
    final g = cfg.noiseGrainScale.clamp(0.01, 0.25);
    final freq = (0.06 / g).clamp(0.2, 3.0);
    final opacityMax = (1.0 - cfg.noiseThreshold.clamp(0.05, 0.95) * 0.35)
        .clamp(0.35, 0.9);
    final contrast = cfg.noiseContrast.clamp(0.35, 2.5);
    final fineMix = cfg.noiseFineMix.clamp(0.0, 1.0);
    final threshold = cfg.noiseThreshold.clamp(0.05, 0.92);

    shader
      ..setFloat(0, color.r)
      ..setFloat(1, color.g)
      ..setFloat(2, color.b)
      ..setFloat(3, freq)
      ..setFloat(4, opacityMax)
      ..setFloat(5, seed)
      ..setFloat(6, contrast)
      ..setFloat(7, fineMix)
      ..setFloat(8, threshold)
      ..setFloat(9, coordOffset.dx)
      ..setFloat(10, coordOffset.dy)
      ..setFloat(11, quality.clamp(0.0, 1.0))
      ..setFloat(12, castShadow ? 1.0 : 0.0);
    bindAtlas(shader);
  }

  static final Paint _stampPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = const Color(0xFFFFFFFF);

  static final Paint _shadowPaint = Paint()
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

  static void paintIsotropicStroke({
    required Canvas canvas,
    required ui.FragmentShader shader,
    required Color color,
    required StrokePaint cfg,
    required Path outline,
    ui.Vertices? mesh,
    required double stampWidth,
    bool configureBaseUniforms = true,
    Offset coordOffset = Offset.zero,
    double currentScale = 1.0,
    int visibleCount = 1,
    double? strokeSize,
  }) {
    final double quality = currentScale < 0.82 ? 0.0 : 1.0;

    if (configureBaseUniforms) {
      configureBase(
        shader,
        color,
        cfg: cfg,
        quality: quality,
        coordOffset: coordOffset,
        castShadow: cfg.pencilShadow,
      );
    }

    paintCastShadow(
      canvas: canvas,
      outline: outline,
      strokeColor: color,
      size: strokeSize ?? stampWidth / 1.35,
      currentScale: currentScale,
      visibleCount: visibleCount,
      quality: quality,
      lodTier: lodTierForScale(currentScale),
      enabled: cfg.pencilShadow,
    );

    if (mesh != null) {
      final bounds = outline.getBounds();
      if (bounds.isEmpty) return;

      // Infla a área para acomodar o anti-aliasing da malha
      final safeBounds = bounds.inflate(4.0);

      // Isola a camada para realizar o recorte perfeito (Masking)
      canvas.saveLayer(safeBounds, Paint());

      // 1. Pinta a malha em branco primeiro (a cor do vértice com Alpha multiplicará o branco)
      _stampPaint
        ..isAntiAlias = quality > 0.5
        ..shader = null
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.fill
        ..blendMode = BlendMode.srcOver;
      
      // BlendMode.modulate funde os Alpha dos Vértices na Tinta Branca
      canvas.drawVertices(mesh, BlendMode.modulate, _stampPaint);

      // 2. Preenche com o Shader de Ruído usando BlendMode.srcIn
      // Isso transfere a textura hiper-realista restritamente para as áreas opacas da malha desenhada acima.
      _stampPaint
        ..shader = shader
        ..blendMode = BlendMode.srcIn;
      canvas.drawRect(safeBounds, _stampPaint);

      canvas.restore();
      
      // Restaura os padrões de pintura para as próximas chamadas
      _stampPaint.shader = null;
      _stampPaint.blendMode = BlendMode.srcOver;
    } else {
      fillOutline(
        canvas: canvas,
        shader: shader,
        outline: outline,
        quality: quality,
      );
    }
  }

  static void fillOutline({
    required Canvas canvas,
    required ui.FragmentShader shader,
    required Path outline,
    required double quality,
  }) {
    _stampPaint
      ..isAntiAlias = quality > 0.5
      ..shader = shader
      ..style = PaintingStyle.fill;
    canvas.drawPath(outline, _stampPaint);
    _stampPaint.shader = null;
  }

  /// True when [color]/[cfg]/[quality] match the last [configure] inputs.
  static bool sameConfig({
    required Color color,
    required StrokePaint cfg,
    required double quality,
    required Color? lastColor,
    required StrokePaint? lastCfg,
    required double? lastQuality,
  }) {
    if (lastColor == null || lastCfg == null || lastQuality == null) {
      return false;
    }

    if (lastColor != color) return false;

    if ((lastQuality - quality).abs() > 0.01) return false;

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