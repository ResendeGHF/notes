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

/// Zoom / on-screen size tier. Live and committed use the same rules so
/// the stroke does not pop on pen-up.
class PencilLod {
  const PencilLod({
    required this.tier,
    required this.quality,
    required this.minSegLen,
    required this.minDirDot,
    required this.stamps,
    this.spinePts = 32,
  });

  /// 0 = overview fill, 1 = zoomed-out fill, 2 = writing quality.
  final int tier;
  final double quality;
  final double minSegLen;
  final double minDirDot;
  final bool stamps;

  /// Decimated polyline uploaded to the shader (local tangent per segment).
  final int spinePts;
}

/// One frozen (or live-tip) pencil draw unit: silhouette + grain spine.
///
/// Already-drawn chunks keep the same [outline] and [plan] so orientation
/// and pressure coverage cannot change while the stylus is still down.
class PencilDrawChunk {
  PencilDrawChunk({required this.outline, required this.plan});

  Path outline;
  PencilOrientedPlan plan;

  void shift(Offset offset) {
    if (offset == Offset.zero) return;
    outline = outline.shift(offset);
    plan.shift(offset);
  }
}

/// Cached direction-run geometry for one LOD tier.
///
/// Committed strokes rebuild this only when geometry or zoom tier changes.
/// Pan/zoom within a tier just replays the cached paths.
class PencilOrientedPlan {
  PencilOrientedPlan({
    required this.tier,
    required this.quality,
    required this.stamps,
    required this.meanDir,
    required this.batches,
    required this.spineXY,
    required this.spineCount,
    Float32List? spinePressure,
  }) : spinePressure = spinePressure ?? Float32List(0);

  final int tier;
  final double quality;
  final bool stamps;
  Offset meanDir;
  final List<(Offset dir, Path path)> batches;

  /// Interleaved page-space polyline (x,y) for per-pixel tangent lookup.
  final Float32List spineXY;
  final int spineCount;
  final Float32List spinePressure;

  void shift(Offset offset) {
    if (offset == Offset.zero) return;
    for (var i = 0; i < spineCount; i++) {
      spineXY[i * 2] += offset.dx;
      spineXY[i * 2 + 1] += offset.dy;
    }
    for (var i = 0; i < batches.length; i++) {
      final (dir, path) = batches[i];
      batches[i] = (dir, path.shift(offset));
    }
  }
}

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

  static const int maxSpinePts = 32;

  /// Append-only grain spine: freeze interior samples, only the tip may move.
  /// Once a sample is locked its tangent must not be resampled.
  static void extendLockedSpine({
    required List<PointVector> locked,
    required PointVector tip,
    required double minSegLen,
    int maxPts = maxSpinePts,
  }) {
    if (locked.isEmpty) {
      locked.add(tip);
      return;
    }
    if (locked.length == 1) {
      final dx = tip.dx - locked[0].dx;
      final dy = tip.dy - locked[0].dy;
      if (dx * dx + dy * dy > 1e-8) locked.add(tip);
      return;
    }

    final last = locked.length - 1;
    final live = locked[last];
    final frozen = locked[last - 1];
    final traveledX = live.dx - frozen.dx;
    final traveledY = live.dy - frozen.dy;
    final traveledSq = traveledX * traveledX + traveledY * traveledY;
    final minSegSq = minSegLen * minSegLen;
    var freeze = locked.length < maxPts && traveledSq >= minSegSq;
    if (!freeze && locked.length < maxPts) {
      final outX = tip.dx - live.dx;
      final outY = tip.dy - live.dy;
      final outSq = outX * outX + outY * outY;
      if (traveledSq > 1e-4 && outSq > 1e-4) {
        final inLen = math.sqrt(traveledSq);
        final outLen = math.sqrt(outSq);
        final dot = (traveledX * outX + traveledY * outY) / (inLen * outLen);
        if (dot < 0.35) freeze = true;
      }
    }
    if (freeze) {
      locked.add(tip);
    } else {
      locked[last] = tip;
    }
  }

  /// Stamp / batch knobs shared by live and committed draws.
  static double stampWidthFor(double size, double maxSizeRatio) =>
      size * maxSizeRatio.clamp(0.5, 3.0) * 1.35;

  static double stampMinSegLen(double size) => math.max(2.4, size * 0.32);

  static const double stampMinDirDot = 0.96;

  /// LOD for oriented grain: same rules for live and committed at a given zoom.
  ///
  /// Writing-sized strokes keep full grain. Spine point count is the orientation
  /// LOD (more points = closer to a true per-element tangent).
  static PencilLod lodFor({
    required double currentScale,
    required double size,
    int visibleCount = 1,
  }) {
    final scale = currentScale;
    final onScreen = size * scale;
    final writingSized = scale >= 0.82 && onScreen >= 2.35;

    if (!writingSized && (scale < 0.42 || onScreen < 1.15)) {
      return PencilLod(
        tier: 0,
        quality: 0.0,
        minSegLen: math.max(7.0, size * 1.05),
        minDirDot: 0.82,
        stamps: false,
        spinePts: 10,
      );
    }
    if (writingSized) {
      return PencilLod(
        tier: 2,
        quality: 1.0,
        minSegLen: math.max(2.8, size * 0.38),
        minDirDot: 0.90,
        stamps: false,
        spinePts: visibleCount > 80 ? 20 : 32,
      );
    }
    return PencilLod(
      tier: 1,
      quality: 1.0,
      minSegLen: math.max(4.2, size * 0.62),
      minDirDot: 0.88,
      stamps: false,
      spinePts: 16,
    );
  }

  static Offset spineTangent(List<PointVector> spine) {
    if (spine.length < 2) return const Offset(1.0, 0.0);
    var accDx = 0.0;
    var accDy = 0.0;
    for (var i = 1; i < spine.length; i++) {
      accDx += spine[i].dx - spine[i - 1].dx;
      accDy += spine[i].dy - spine[i - 1].dy;
    }
    final len = math.sqrt(accDx * accDx + accDy * accDy);
    if (len < 1e-4) return const Offset(1.0, 0.0);
    return Offset(accDx / len, accDy / len);
  }

  /// Decimate [spine], pick the longest tangent run, and (when the stroke
  /// never hairpins) optionally keep per-run polylines for oriented grain.
  static PencilOrientedPlan buildOrientedPlan({
    required List<PointVector> spine,
    required PencilLod lod,
    bool alreadyDecimated = false,
  }) {
    if (spine.length < 2) {
      return PencilOrientedPlan(
        tier: lod.tier,
        quality: lod.quality,
        stamps: false,
        meanDir: const Offset(1.0, 0.0),
        batches: const [],
        spineXY: Float32List(0),
        spineCount: 0,
      );
    }

    _px
      ..clear()
      ..add(spine.first.dx);
    _py
      ..clear()
      ..add(spine.first.dy);
    _pp
      ..clear()
      ..add(spine.first.pressure ?? 0.5);
    if (alreadyDecimated) {
      for (var i = 1; i < spine.length; i++) {
        _px.add(spine[i].dx);
        _py.add(spine[i].dy);
        _pp.add(spine[i].pressure ?? 0.5);
      }
    } else {
      final minSegSq = lod.minSegLen * lod.minSegLen;
      var lastX = spine.first.dx;
      var lastY = spine.first.dy;
      for (var i = 1; i < spine.length; i++) {
        final x = spine[i].dx;
        final y = spine[i].dy;
        final dx = x - lastX;
        final dy = y - lastY;
        final isLast = i == spine.length - 1;
        var keep = isLast || dx * dx + dy * dy >= minSegSq;
        // Keep hairpin apexes — skipping them chords across the return and
        // stamps a square-ish face into the outline.
        if (!keep && i + 1 < spine.length) {
          final ndx = spine[i + 1].dx - x;
          final ndy = spine[i + 1].dy - y;
          final inLen = math.sqrt(dx * dx + dy * dy);
          final outLen = math.sqrt(ndx * ndx + ndy * ndy);
          if (inLen > 1e-4 && outLen > 1e-4) {
            final dot = (dx * ndx + dy * ndy) / (inLen * outLen);
            if (dot < 0.35) keep = true;
          }
        }
        if (!keep) continue;
        _px.add(x);
        _py.add(y);
        _pp.add(spine[i].pressure ?? 0.5);
        lastX = x;
        lastY = y;
      }
    }

    final n = _px.length;
    if (n < 2) {
      return PencilOrientedPlan(
        tier: lod.tier,
        quality: lod.quality,
        stamps: false,
        meanDir: const Offset(1.0, 0.0),
        batches: const [],
        spineXY: Float32List(0),
        spineCount: 0,
      );
    }

    var accDx = 0.0;
    var accDy = 0.0;
    var refDx = 1.0;
    var refDy = 0.0;
    var haveRef = false;
    var bestLen = 0.0;
    var bestDx = 1.0;
    var bestDy = 0.0;
    var runLen = 0.0;
    var runDx = 0.0;
    var runDy = 0.0;
    var runHas = false;

    void closeRun() {
      if (!runHas || runLen <= bestLen) return;
      final l = math.sqrt(runDx * runDx + runDy * runDy);
      if (l < 1e-4) return;
      bestLen = runLen;
      bestDx = runDx / l;
      bestDy = runDy / l;
    }

    for (var i = 1; i < n; i++) {
      final dx = _px[i] - _px[i - 1];
      final dy = _py[i] - _py[i - 1];
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 1e-4) continue;
      accDx += dx;
      accDy += dy;
      final ndx = dx / len;
      final ndy = dy / len;
      if (!haveRef) {
        refDx = ndx;
        refDy = ndy;
        haveRef = true;
        runDx = dx;
        runDy = dy;
        runLen = len;
        runHas = true;
      } else {
        final runNorm = math.sqrt(runDx * runDx + runDy * runDy);
        final runDot = runNorm < 1e-4
            ? 1.0
            : (ndx * runDx + ndy * runDy) / runNorm;
        if (runDot >= lod.minDirDot) {
          runDx += dx;
          runDy += dy;
          runLen += len;
        } else {
          closeRun();
          runDx = dx;
          runDy = dy;
          runLen = len;
          runHas = true;
        }
      }
    }
    closeRun();
    if (!haveRef) {
      bestDx = 1.0;
      bestDy = 0.0;
    } else if (bestLen <= 0) {
      final runL = math.sqrt(accDx * accDx + accDy * accDy);
      if (runL > 1e-4) {
        bestDx = accDx / runL;
        bestDy = accDy / runL;
      } else {
        bestDx = refDx;
        bestDy = refDy;
      }
    }

    final meanDir = Offset(bestDx, bestDy);
    final packed = _packDecimatedSpine(
      n,
      alreadyDecimated ? maxSpinePts : lod.spinePts,
    );
    return PencilOrientedPlan(
      tier: lod.tier,
      quality: lod.quality,
      stamps: false,
      meanDir: meanDir,
      batches: const [],
      spineXY: packed.$1,
      spineCount: packed.$1.length ~/ 2,
      spinePressure: packed.$2,
    );
  }

  static (Float32List, Float32List) _packDecimatedSpine(int n, int maxPts) {
    final cap = maxPts.clamp(2, maxSpinePts);
    if (n <= 0) return (Float32List(0), Float32List(0));
    if (n == 1) {
      return (
        Float32List(2)
          ..[0] = _px[0]
          ..[1] = _py[0],
        Float32List(1)..[0] = _pp.isEmpty ? 0.5 : _pp[0],
      );
    }
    final outN = n <= cap ? n : cap;
    final xy = Float32List(outN * 2);
    final pr = Float32List(outN);
    if (n <= cap) {
      for (var i = 0; i < n; i++) {
        xy[i * 2] = _px[i];
        xy[i * 2 + 1] = _py[i];
        pr[i] = i < _pp.length ? _pp[i] : 0.5;
      }
      return (xy, pr);
    }
    // Prefix-stable: never move earlier samples. Only the live tip updates.
    final lastLocked = outN - 1;
    for (var i = 0; i < lastLocked; i++) {
      xy[i * 2] = _px[i];
      xy[i * 2 + 1] = _py[i];
      pr[i] = i < _pp.length ? _pp[i] : 0.5;
    }
    xy[lastLocked * 2] = _px[n - 1];
    xy[lastLocked * 2 + 1] = _py[n - 1];
    pr[lastLocked] = (n - 1) < _pp.length ? _pp[n - 1] : 0.5;
    return (xy, pr);
  }

  /// Correct silhouette: fill the perfect-freehand outline (not fat stamps).
  /// Live preview uses this so the in-progress stroke is not square-ish.
  static void paintOutlineFill({
    required Canvas canvas,
    required ui.FragmentShader shader,
    required Color color,
    required StrokePaint cfg,
    required double quality,
    required Path outline,
    required List<PointVector> spine,
    bool configureBaseUniforms = true,
    Offset coordOffset = Offset.zero,
    double pressureSensitivity = 1.0,
  }) {
    if (configureBaseUniforms) {
      configureBase(
        shader,
        color,
        cfg: cfg,
        quality: quality,
        coordOffset: coordOffset,
      );
    }
    _px
      ..clear()
      ..addAll(spine.map((p) => p.dx));
    _py
      ..clear()
      ..addAll(spine.map((p) => p.dy));
    _pp
      ..clear()
      ..addAll(spine.map((p) => p.pressure ?? 0.5));
    final packed = _packDecimatedSpine(spine.length, maxSpinePts);
    configureSpine(
      shader,
      PencilOrientedPlan(
        tier: 2,
        quality: quality,
        stamps: false,
        meanDir: spineTangent(spine),
        batches: const [],
        spineXY: packed.$1,
        spineCount: packed.$1.length ~/ 2,
        spinePressure: packed.$2,
      ),
      pressureToCoverage: cfg.pressureMapsToCoverage,
      pressureSensitivity: pressureSensitivity,
      castShadow: cfg.pencilShadow,
    );
    fillOutline(
      canvas: canvas,
      shader: shader,
      outline: outline,
      quality: quality,
    );
  }

  static void configure(
    ui.FragmentShader shader,
    Color color, {
    required StrokePaint cfg,
    Offset coordOffset = Offset.zero,
    double seed = 0,
    double quality = 1.0,
    Offset direction = const Offset(1.0, 0.0),
  }) {
    configureBase(
      shader,
      color,
      cfg: cfg,
      coordOffset: coordOffset,
      seed: seed,
      quality: quality,
    );
    configureDirection(shader, direction);
  }

  /// Uniform layout must match `shaders/pencil.frag`:
  /// 0–2 `uColor`, 3 `uFreq`, 4 `uOpacityMax`, 5 `uSeed`, 6 `uContrast`,
  /// 7 `uFineMix`, 8 `uThreshold`, 9–10 `uOffset`, 11 `uQuality`,
  /// 12–13 `uDir` fallback, 14 `uSpineCount`, 15–78 spine `x,y`,
  /// 79–80 pressure-coverage, 81–112 packed pressures, 113 `uCastShadow`.
  static void configureBase(
    ui.FragmentShader shader,
    Color color, {
    required StrokePaint cfg,
    Offset coordOffset = Offset.zero,
    double seed = 0,
    double quality = 1.0,
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
      ..setFloat(11, quality.clamp(0.0, 1.0));
    bindAtlas(shader);
  }

  static void configureDirection(ui.FragmentShader shader, Offset direction) {
    var dx = direction.dx;
    var dy = direction.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-4) {
      dx = 1.0;
      dy = 0.0;
    } else {
      dx /= len;
      dy /= len;
    }
    shader
      ..setFloat(12, dx)
      ..setFloat(13, dy);
  }

  static void configureSpine(
    ui.FragmentShader shader,
    PencilOrientedPlan plan, {
    bool pressureToCoverage = false,
    double pressureSensitivity = 1.0,
    bool castShadow = false,
  }) {
    configureDirection(shader, plan.meanDir);
    var n = plan.spineCount;
    if (n > maxSpinePts) n = maxSpinePts;
    shader.setFloat(14, n.toDouble());
    final xy = plan.spineXY;
    for (var i = 0; i < maxSpinePts; i++) {
      final o = i * 2;
      final x = i < n ? xy[o] : 0.0;
      final y = i < n ? xy[o + 1] : 0.0;
      shader
        ..setFloat(15 + o, x)
        ..setFloat(16 + o, y);
    }
    shader
      ..setFloat(79, pressureToCoverage ? 1.0 : 0.0)
      ..setFloat(80, pressureSensitivity.clamp(0.0, 2.0));
    final pr = plan.spinePressure;
    for (var i = 0; i < maxSpinePts; i++) {
      final p = i < pr.length ? pr[i].clamp(0.0, 1.0) : 0.5;
      shader.setFloat(81 + i, p);
    }
    shader.setFloat(113, castShadow ? 1.0 : 0.0);
  }

  static final _px = <double>[];
  static final _py = <double>[];
  static final _pp = <double>[];
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

  /// Oriented grain inside [outline]. Uses [plan] when provided so committed
  /// strokes skip spine walks and Path rebuilds on pan.
  static void paintOrientedStroke({
    required Canvas canvas,
    required ui.FragmentShader shader,
    required Color color,
    required StrokePaint cfg,
    required Path outline,
    required List<PointVector> spine,
    required double stampWidth,
    PencilLod? lod,
    PencilOrientedPlan? plan,
    bool configureBaseUniforms = true,
    Offset coordOffset = Offset.zero,
    double pressureSensitivity = 1.0,
  }) {
    final resolved =
        plan ??
        buildOrientedPlan(
          spine: spine,
          lod:
              lod ??
              const PencilLod(
                tier: 2,
                quality: 1.0,
                minSegLen: 2.4,
                minDirDot: stampMinDirDot,
                stamps: true,
              ),
        );
    paintPlan(
      canvas: canvas,
      shader: shader,
      color: color,
      cfg: cfg,
      outline: outline,
      plan: resolved,
      stampWidth: stampWidth,
      configureBaseUniforms: configureBaseUniforms,
      coordOffset: coordOffset,
      pressureSensitivity: pressureSensitivity,
    );
  }

  static void paintPlan({
    required Canvas canvas,
    required ui.FragmentShader shader,
    required Color color,
    required StrokePaint cfg,
    required Path outline,
    required PencilOrientedPlan plan,
    required double stampWidth,
    bool configureBaseUniforms = true,
    Offset coordOffset = Offset.zero,
    double pressureSensitivity = 1.0,
    double currentScale = 1.0,
    int visibleCount = 1,
    double? strokeSize,
  }) {
    if (configureBaseUniforms) {
      configureBase(
        shader,
        color,
        cfg: cfg,
        quality: plan.quality,
        coordOffset: coordOffset,
      );
    }
    configureSpine(
      shader,
      plan,
      pressureToCoverage: cfg.pressureMapsToCoverage,
      pressureSensitivity: pressureSensitivity,
      castShadow: cfg.pencilShadow,
    );
    paintCastShadow(
      canvas: canvas,
      outline: outline,
      strokeColor: color,
      size: strokeSize ?? stampWidth / 1.35,
      currentScale: currentScale,
      visibleCount: visibleCount,
      quality: plan.quality,
      lodTier: plan.tier,
      enabled: cfg.pencilShadow,
    );
    fillOutline(
      canvas: canvas,
      shader: shader,
      outline: outline,
      quality: plan.quality,
    );
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
