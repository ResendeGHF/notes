// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_shape_stroke.dart';
import 'package:saber/data/editor/binary_writer.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/components/canvas/pencil_shader.dart';
import 'package:saber/data/editor/stroke_paint.dart';
import 'package:saber/data/editor/stroke_paint_image_cache.dart';
import 'package:saber/data/extensions/dynamic_extensions.dart';
import 'package:saber/data/extensions/list_extensions.dart';
import 'package:saber/data/extensions/point_extensions.dart';
import 'package:saber/data/extensions/svg_path_formatting.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/services/display_ink_feel.dart';

class BinaryOptions {
  void optionsToBinary(BinaryWriter writer, StrokeOptions options) {
    if (options.size != StrokeOptions.defaultSize) {
      writer.writeFloat(StrokeBinaryKeys.size, options.size);
    }
    if (options.thinning != StrokeOptions.defaultThinning) {
      writer.writeFloat(StrokeBinaryKeys.thinning, options.thinning);
    }
    if (options.smoothing != StrokeOptions.defaultSmoothing) {
      writer.writeFloat(StrokeBinaryKeys.smoothing, options.smoothing);
    }
    if (options.streamline != StrokeOptions.defaultStreamline) {
      writer.writeFloat(StrokeBinaryKeys.streamline, options.streamline);
    }
    if (options.simulatePressure != StrokeOptions.defaultSimulatePressure) {
      writer.writeBool(
        StrokeBinaryKeys.simulatePressure,
        options.simulatePressure,
      );
    }
    if (options.isComplete != StrokeOptions.defaultIsComplete) {
      writer.writeBool(StrokeBinaryKeys.isComplete, options.isComplete);
    }
    if (options.pressureSensitivity !=
        StrokeOptions.defaultPressureSensitivity) {
      writer.writeFloat(
        StrokeBinaryKeys.pressureSensitivity,
        options.pressureSensitivity,
      );
    }
    if (options.velocityThinning != StrokeOptions.defaultVelocityThinning) {
      writer.writeFloat(
        StrokeBinaryKeys.velocityThinning,
        options.velocityThinning,
      );
    }
    if (options.minSizeRatio != StrokeOptions.defaultMinSizeRatio) {
      writer.writeFloat(StrokeBinaryKeys.minSizeRatio, options.minSizeRatio);
    }
    if (options.maxSizeRatio != StrokeOptions.defaultMaxSizeRatio) {
      writer.writeFloat(StrokeBinaryKeys.maxSizeRatio, options.maxSizeRatio);
    }
    if (options.start.taperEnabled) {
      writer.writeBool(
        StrokeBinaryKeys.startTaperEnabled,
        options.start.taperEnabled,
      );
      if (options.start.customTaper != null) {
        writer.writeFloat(
          StrokeBinaryKeys.startCustomTaper,
          options.start.customTaper!,
        );
      }
    } else {
      writer.writeBool(
        StrokeBinaryKeys.startTaperEnabled,
        options.start.taperEnabled,
      );
    }
    if (options.start.cap != StrokeEndOptions.defaultCap) {
      writer.writeBool(
        StrokeBinaryKeys.endTaperEnabled,
        options.end.taperEnabled,
      );
      writer.writeBool(StrokeBinaryKeys.startCap, options.start.cap);
    }
    if (options.end.taperEnabled) {
      writer.writeBool(
        StrokeBinaryKeys.endTaperEnabled,
        options.end.taperEnabled,
      );
      if (options.end.customTaper != null) {
        writer.writeFloat(
          StrokeBinaryKeys.endCustomTaper,
          options.end.customTaper!,
        );
      }
    } else {
      writer.writeBool(StrokeBinaryKeys.endTaperEnabled, false);
    }
    if (options.end.cap != StrokeEndOptions.defaultCap) {
      writer.writeBool(StrokeBinaryKeys.endCap, options.end.cap);
    }
    writer.writeKey(StrokeBinaryKeys.endOptions);
  }

  StrokeOptions optionsFromBinary(BinaryReader reader, {int? initialKey}) {
    int key;
    var size = StrokeOptions.defaultSize;
    var thinning = StrokeOptions.defaultThinning;
    var smoothing = StrokeOptions.defaultSmoothing;
    var streamLine = StrokeOptions.defaultStreamline;
    var simulatePressure = StrokeOptions.defaultSimulatePressure;
    var isComplete = StrokeOptions.defaultIsComplete;
    var pressureSensitivity = StrokeOptions.defaultPressureSensitivity;
    var velocityThinning = StrokeOptions.defaultVelocityThinning;
    var minSizeRatio = StrokeOptions.defaultMinSizeRatio;
    var maxSizeRatio = StrokeOptions.defaultMaxSizeRatio;
    double? startCustomTaper;
    double? endCustomTaper;
    bool startCap = StrokeEndOptions.defaultCap;
    bool endCap = StrokeEndOptions.defaultCap;
    bool startTaperEnabled = false;
    bool endTaperEnabled = false;
    key = initialKey ?? reader.readKey();
    while (key != StrokeBinaryKeys.endOptions) {
      switch (key) {
        case StrokeBinaryKeys.size:
          size = reader.readFloat();
        case StrokeBinaryKeys.thinning:
          thinning = reader.readFloat();
        case StrokeBinaryKeys.smoothing:
          smoothing = reader.readFloat();
        case StrokeBinaryKeys.streamline:
          streamLine = reader.readFloat();
        case StrokeBinaryKeys.simulatePressure:
          simulatePressure = reader.readBoolNoKey();
        case StrokeBinaryKeys.isComplete:
          isComplete = reader.readBoolNoKey();
        case StrokeBinaryKeys.pressureSensitivity:
          pressureSensitivity = reader.readFloat();
        case StrokeBinaryKeys.velocityThinning:
          velocityThinning = reader.readFloat();
        case StrokeBinaryKeys.minSizeRatio:
          minSizeRatio = reader.readFloat();
        case StrokeBinaryKeys.maxSizeRatio:
          maxSizeRatio = reader.readFloat();
        case StrokeBinaryKeys.startTaperEnabled:
          startTaperEnabled = reader.readBoolNoKey();
        case StrokeBinaryKeys.startCustomTaper:
          startCustomTaper = reader.readFloat();
        case StrokeBinaryKeys.startCap:
          startCap = reader.readBoolNoKey();
        case StrokeBinaryKeys.endTaperEnabled:
          endTaperEnabled = reader.readBoolNoKey();
        case StrokeBinaryKeys.endCustomTaper:
          endCustomTaper = reader.readFloat();
        case StrokeBinaryKeys.endCap:
          endCap = reader.readBoolNoKey();
      }
      key = reader.readKey();
    }

    final start = StrokeEndOptions.start(
      customTaper: startCustomTaper,
      taperEnabled: startTaperEnabled,
      cap: startCap,
      easing: StrokeOptions.defaultEasing,
    );
    final end = StrokeEndOptions.end(
      customTaper: endCustomTaper,
      taperEnabled: endTaperEnabled,
      cap: endCap,
      easing: StrokeOptions.defaultEasing,
    );
    return StrokeOptions(
      size: size,
      thinning: thinning,
      smoothing: smoothing,
      streamline: streamLine,
      easing: StrokeOptions.defaultEasing,
      simulatePressure: simulatePressure,
      start: start,
      end: end,
      isComplete: isComplete,
      pressureSensitivity: pressureSensitivity,
      velocityThinning: velocityThinning,
      minSizeRatio: minSizeRatio,
      maxSizeRatio: maxSizeRatio,
    );
  }
}

class Stroke implements HasBounds, Comparable<Stroke> {
  static final log = Logger('Stroke');

  int zIndex = 0;

  @visibleForTesting
  @protected
  final List<PointVector> points = [];

  int get sampleCount => points.length;

  Float32List packExportXyz() {
    final packed = Float32List(points.length * 3);
    for (var i = 0; i < points.length; i++) {
      packed[i * 3] = points[i].x;
      packed[i * 3 + 1] = points[i].y;
      packed[i * 3 + 2] = points[i].pressure ?? 0.5;
    }
    return packed;
  }

  void loadExportPackedXyz(Float32List packed) {
    points.clear();
    final n = packed.length ~/ 3;
    for (var i = 0; i < n; i++) {
      points.add(
        PointVector(packed[i * 3], packed[i * 3 + 1], packed[i * 3 + 2]),
      );
    }
    _packedPoints = null;
    markPolygonNeedsUpdating();
  }

  Float32List? _packedPoints;

  void _ensurePackedPoints() {
    // Vertices mesh must not include stroke-prediction tail: that extra vertex
    // moves the tip, end tangent, and cap while drawing but vanishes on commit,
    // so preview caps would never match finalized ink.
    final List<PointVector> src = points;
    final int len = src.length;
    if (_packedPoints != null && _packedPoints!.length == len * 3) return;
    _packedPoints = Float32List(len * 3);
    for (int i = 0; i < len; i++) {
      final p = src[i];
      final int o = i * 3;
      _packedPoints![o] = p.x;
      _packedPoints![o + 1] = p.y;
      _packedPoints![o + 2] = p.pressure ?? 0.5;
    }
  }

  List<PointVector> get pointsForEraser => points;

  /// Returns points including the live prediction tip, ensuring
  /// custom segmented drawing methods don't lag behind the stylus.
  List<PointVector> get livePoints => _pointsForLiveRender(points);

  void replacePointsFromEraser(List<PointVector> newPoints) {
    points
      ..clear()
      ..addAll(newPoints);
    _cachedBounds = null;
    _packedPoints = null;
    _cachedAveragePressure = null;
    markPolygonNeedsUpdating();
  }

  void replacePointRangeFromEraser(
    List<PointVector> source,
    int start,
    int end,
  ) {
    points.clear();
    for (int i = start; i <= end; i++) {
      points.add(source[i]);
    }
    _cachedBounds = null;
    _packedPoints = null;
    _cachedAveragePressure = null;
    markPolygonNeedsUpdating();
  }

  bool get isEmpty => points.isEmpty;

  @override
  int compareTo(Stroke other) => zIndex.compareTo(other.zIndex);
  int get length => points.length;

  int pageIndex;
  HasSize page;
  final ToolId toolId;

  String get penType => toolId.id;

  static const defaultColor = Colors.black;
  static const defaultPressureEnabled = true;

  Color color;

  /// Butterfly-style fill: solid (default), image, SVG, or gradient.
  StrokePaint paint = const StrokePaint();

  bool get hasNonSolidPaint => !paint.isSolid;

  /// FragmentShader pencil stays off Picture tiles. Fills are vector-in-tiles.
  bool get isExpensivePaintStroke => paint.usesPencilNoise;

  PencilOrientedPlan? _pencilPlan;
  final List<PointVector> _lockedPencilSpine = [];
  final List<PencilDrawChunk> _liveFrozenPencilChunks = [];
  int _pencilLockedPointCount = 0;
  PencilDrawChunk? _livePencilTip;
  List<PencilDrawChunk>? _livePencilTipChunks;
  int _livePencilTipHash = 0;
  List<PencilDrawChunk>? _committedPencilChunks;

  /// Frozen interior ribbon for live ballpoint / fountain / calligraphy.
  /// Tip quads and the end cap rebuild each sample; commit uses one mesh.
  Float32List? _liveCheapFrozenPositions;
  int _liveCheapFrozenSpineCount = 0;
  Float32List? _liveCheapFrozenSmoothPrefix;
  List<PointVector>? _liveRenderScratch;

  /// Cached direction-run plan for committed pencil. Live strokes only
  /// extend [_lockedPencilSpine] — already-placed grain samples stay put.
  PencilOrientedPlan orientedPencilPlan(
    double currentScale, {
    int visibleCount = 1,
  }) {
    final lod = PencilShader.lodFor(
      currentScale: currentScale,
      size: options.size,
      visibleCount: visibleCount,
    );
    if (options.isComplete &&
        _pencilPlan != null &&
        _pencilPlan!.tier == lod.tier) {
      return _pencilPlan!;
    }
    if (!options.isComplete && points.isNotEmpty) {
      if (_lockedPencilSpine.isEmpty) {
        PencilShader.extendLockedSpine(
          locked: _lockedPencilSpine,
          tip: points.first,
          minSegLen: lod.minSegLen,
        );
      }
      final live = _pointsForLiveRender(points);
      PencilShader.extendLockedSpine(
        locked: _lockedPencilSpine,
        tip: live.isNotEmpty ? live.last : points.last,
        minSegLen: lod.minSegLen,
      );
    } else {
      final spine = shaderSpine;
      if (spine.isNotEmpty) {
        if (_lockedPencilSpine.isEmpty) {
          PencilShader.extendLockedSpine(
            locked: _lockedPencilSpine,
            tip: spine.first,
            minSegLen: lod.minSegLen,
          );
        }
        PencilShader.extendLockedSpine(
          locked: _lockedPencilSpine,
          tip: spine.last,
          minSegLen: lod.minSegLen,
        );
      }
    }
    final useLocked = _lockedPencilSpine.length >= 2;
    final plan = PencilShader.buildOrientedPlan(
      spine: useLocked ? _lockedPencilSpine : shaderSpine,
      lod: lod,
      alreadyDecimated: useLocked,
    );
    if (options.isComplete) {
      _pencilPlan = plan;
    }
    return plan;
  }

  void _invalidatePencilPlan() {
    _pencilPlan = null;
  }

  void _clearLivePencilChunks() {
    _liveFrozenPencilChunks.clear();
    _pencilLockedPointCount = 0;
    _livePencilTip = null;
    _livePencilTipChunks = null;
    _livePencilTipHash = 0;
    _committedPencilChunks = null;
  }

  bool get _usesLivePencilChunks =>
      toolId == ToolId.advancedPencil || paint.usesPencilNoise;

  @visibleForTesting
  int get debugFrozenAdvancedMeshCount => 0;

  @visibleForTesting
  int get debugLiveLockedPointCount => _liveCheapFrozenSpineCount;

  @visibleForTesting
  List<Float32List> get debugFrozenAdvancedPositions => const [];

  @visibleForTesting
  void debugSetLivePrediction(Offset tip, [double? pressure]) {
    _predictionTip = tip;
    _predictionPressure = pressure ?? 0.5;
  }

  @visibleForTesting
  int get debugFrozenPencilChunkCount => _liveFrozenPencilChunks.length;

  @visibleForTesting
  List<double> get debugFirstFrozenPencilSpineXY =>
      _liveFrozenPencilChunks.isEmpty
      ? const []
      : List<double>.from(_liveFrozenPencilChunks.first.plan.spineXY);

  @visibleForTesting
  List<double> get debugFirstFrozenPencilPressure =>
      _liveFrozenPencilChunks.isEmpty
      ? const []
      : List<double>.from(_liveFrozenPencilChunks.first.plan.spinePressure);

  /// Frozen + tip pencil chunks. Already-drawn pieces keep their outline,
  /// grain tangent, and pressure coverage until the stylus is lifted.
  List<PencilDrawChunk>? get pencilDrawChunks {
    final committed = _committedPencilChunks;
    if (committed != null && committed.isNotEmpty) return committed;
    if (options.isComplete || !_usesLivePencilChunks) return null;
    if (points.length < 2) return null;
    return _ensureLivePencilChunks();
  }

  List<PencilDrawChunk> _ensureLivePencilChunks() {
    if (points.length - _pencilLockedPointCount >=
        _pencilLockBehind + _pencilLockMinChunk) {
      final newLock = points.length - _pencilLockBehind;
      final from = math.max(0, _pencilLockedPointCount - _pencilLockOverlap);
      // Mid-stroke freezes must not taper/cap the join — that pinched the
      // ribbon to a point and looked like missing segments (worse at low zoom
      // where adaptive spine reshape + grain coverage amplify the gap).
      _liveFrozenPencilChunks.addAll(
        _buildPencilChunks(
          points.sublist(from, newLock),
          isStrokeStart: from == 0 && _liveFrozenPencilChunks.isEmpty,
          isStrokeEnd: false,
        ),
      );
      _pencilLockedPointCount = newLock;
      _livePencilTip = null;
      _livePencilTipChunks = null;
      _livePencilTipHash = 0;
    }

    final tipStart = math.max(0, _pencilLockedPointCount - _pencilLockOverlap);
    final tipPoints = _pointsForLiveRender(points.sublist(tipStart));
    final tipHash = Object.hash(
      visualFingerprint,
      tipStart,
      tipPoints.length,
    );
    if (_livePencilTip == null || _livePencilTipHash != tipHash) {
      final built = _buildPencilChunks(
        tipPoints,
        isStrokeStart: tipStart == 0 && _liveFrozenPencilChunks.isEmpty,
        isStrokeEnd: true,
      );
      // Tip may split into several shader chunks; keep all of them live.
      _livePencilTipChunks = built;
      _livePencilTip = built.isEmpty ? null : built.last;
      _livePencilTipHash = tipHash;
    }

    return [
      ..._liveFrozenPencilChunks,
      ...?_livePencilTipChunks,
    ];
  }

  List<PencilDrawChunk> _buildPencilChunks(
    List<PointVector> basePoints, {
    bool isStrokeStart = true,
    bool isStrokeEnd = true,
  }) {
    if (basePoints.length < 2) return const [];
    final spine = _prepareAdvancedSpine(
      basePoints,
      stabilizeStart: isStrokeStart,
      stabilizeEnd: isStrokeEnd,
      flattenEnds: isStrokeStart || isStrokeEnd,
    );
    if (spine.length < 2) return const [];
    return _chunksFromPreparedSpine(
      spine,
      isStrokeStart: isStrokeStart,
      isStrokeEnd: isStrokeEnd,
    );
  }

  List<PencilDrawChunk> _chunksFromPreparedSpine(
    List<PointVector> spine, {
    required bool isStrokeStart,
    required bool isStrokeEnd,
  }) {
    if (spine.length < 2) return const [];
    if (spine.length <= PencilShader.maxSpinePts) {
      final chunk = _chunkFromPreparedSpine(
        spine,
        includeStart: isStrokeStart,
        includeEnd: isStrokeEnd,
      );
      return chunk == null ? const [] : [chunk];
    }
    final out = <PencilDrawChunk>[];
    // Generous overlap so open joins between shader uploads stay covered.
    final overlap = math.max(8, (options.size * 1.25).round().clamp(8, 16));
    var start = 0;
    while (start < spine.length - 1) {
      final end = math.min(start + PencilShader.maxSpinePts, spine.length);
      final isFirst = start == 0;
      final isLast = end >= spine.length;
      final chunk = _chunkFromPreparedSpine(
        spine.sublist(start, end),
        includeStart: isStrokeStart && isFirst,
        includeEnd: isStrokeEnd && isLast,
      );
      if (chunk != null) out.add(chunk);
      if (isLast) break;
      start = end - overlap;
    }
    return out;
  }

  PencilDrawChunk? _chunkFromPreparedSpine(
    List<PointVector> spine, {
    bool includeStart = true,
    bool includeEnd = true,
  }) {
    if (spine.length < 2) return null;
    final outline = _advancedOutlineFromSpine(
      spine,
      includeStart: includeStart,
      includeEnd: includeEnd,
    );
    if (outline.length < 3) return null;
    return PencilDrawChunk(
      outline: getPath(outline, smooth: false),
      plan: PencilShader.buildOrientedPlan(
        spine: spine,
        lod: _livePencilLod,
        alreadyDecimated: true,
      ),
    );
  }

  PencilLod get _livePencilLod => PencilShader.lodFor(
    currentScale: _targetScale <= 0 ? 1.0 : _targetScale,
    size: options.size,
    visibleCount: 1,
  );

  static const int _pencilLockBehind = 12;
  static const int _pencilLockMinChunk = 8;
  /// Overlap between frozen ribbon and live tip (raw samples). Large enough
  /// that open mid-joins stay covered after independent streamlining.
  static const int _pencilLockOverlap = 14;

  void _shiftLockedPencilSpine(Offset offset) {
    if (offset == Offset.zero || _lockedPencilSpine.isEmpty) return;
    for (var i = 0; i < _lockedPencilSpine.length; i++) {
      final p = _lockedPencilSpine[i];
      _lockedPencilSpine[i] = PointVector(
        p.dx + offset.dx,
        p.dy + offset.dy,
        p.pressure,
      );
    }
  }

  bool pressureEnabled;
  final StrokeOptions options;
  double? _cachedAveragePressure;

  double rotationDeg = 0.0;

  bool flatEdge = stows.highlighterFlatEdge.value;

  /// Permanent neon glow (laser-like). Ballpoint only in the UI; older notes
  /// may still carry the flag on other tools and are drawn without neon.
  bool neon = false;

  Path? _neonInnerPath;

  /// Bright neon core (ballpoint-style inset).
  Path get neonInnerPath {
    if (_neonInnerPath != null) return _neonInnerPath!;
    final poly = Stroke.buildBallpointStylePolygon(
      points,
      size: options.size * 0.4,
      targetScale: _targetScale,
    );
    return _neonInnerPath = Path()
      ..fillType = PathFillType.nonZero
      ..addPolygon(poly, true);
  }

  double get averagePressure {
    if (_cachedAveragePressure != null) return _cachedAveragePressure!;
    if (points.isEmpty) return _cachedAveragePressure = 0.5;
    double sum = 0;
    int count = 0;
    for (final point in points) {
      sum += point.pressure ?? 0.5;
      count++;
    }
    return _cachedAveragePressure = count == 0 ? 0.5 : (sum / count);
  }

  Rect? _cachedBounds;

  @override
  Rect get bounds {
    if (_cachedBounds != null) return _cachedBounds!;

    if (this is ShapeStroke) {
      final shapeBounds = (this as ShapeStroke).shapePath.getBounds();
      final double margin = options.size / 2;
      return _cachedBounds = shapeBounds.inflate(margin);
    }

    if (points.isEmpty) return _cachedBounds = Rect.zero;

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    final double margin = options.size / 2;

    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }

    _cachedBounds = Rect.fromLTRB(
      minX - margin,
      minY - margin,
      maxX + margin,
      maxY + margin,
    );

    return _cachedBounds!;
  }

  int get geometricFingerprint {
    if (points.isEmpty) {
      return Object.hash(
        color,
        options.size,
        toolId.index,
        0,
        options.isComplete,
      );
    }
    final first = points.first;
    final last = points.last;
    return Object.hash(
      first.x.toInt(),
      first.y.toInt(),
      last.x.toInt(),
      last.y.toInt(),
      points.length,
      color.toARGB32(),
      (options.size * 1000).round(),
      toolId.index,
      options.isComplete,
    );
  }

  void _invalidateSpatialData() {
    _cachedBounds = null;
  }

  List<Offset>? _lowQualityPolygon, _highQualityPolygon;
  List<Offset>? _exportPolygon;
  List<PointVector>? _highQualitySpine;
  List<Offset> get lowQualityPolygon =>
      _lowQualityPolygon ??= getPolygon(quality: StrokeQuality.low);
  List<Offset> get highQualityPolygon =>
      _highQualityPolygon ??= getPolygon(quality: StrokeQuality.high);

  bool get hasCachedHighQualityPolygon => _highQualityPolygon != null;
  List<Offset>? get cachedExportPolygon => _exportPolygon;

  void cacheExportPolygon(List<Offset> poly) => _exportPolygon = poly;

  /// Used when export vectorization ran in an isolate (same geometry as
  /// [highQualityPolygon] on this isolate).
  void adoptHighQualityPolygon(List<Offset> poly) {
    _highQualityPolygon = poly;
    _exportPolygon = null;
    _highQualitySpine = null;
  }

  /// Smoothed centerline used by [getPolygon] (high). Pencil grain follows this
  /// tangent, not the raw input samples.
  List<PointVector> get shaderSpine {
    if (_highQualitySpine != null) return _highQualitySpine!;
    highQualityPolygon;
    return _highQualitySpine ?? points;
  }

  Path? _lowQualityPath;
  Path get lowQualityPath =>
      _lowQualityPath ??= getPath(lowQualityPolygon, smooth: true);

  Path get highQualityPath {
    if (_cachedPath != null && _cachedPathValid) return _cachedPath!;

    _cachedPath ??= Path();
    _cachedPath!.reset();

    final poly = getPolygon(quality: StrokeQuality.high);
    if (poly.isEmpty) return _cachedPath!;

    const epsilon = 1e-6;
    final List<Offset> reduced = [poly[0]];
    for (int i = 1; i < poly.length; i++) {
      final prev = reduced.last;
      final p = poly[i];
      if ((p.dx - prev.dx).abs() > epsilon ||
          (p.dy - prev.dy).abs() > epsilon) {
        reduced.add(p);
      }
    }

    if (reduced.length >= 2) {
      final first = reduced.first;
      final last = reduced.last;
      if ((last.dx - first.dx).abs() <= epsilon &&
          (last.dy - first.dy).abs() <= epsilon) {
        reduced.removeLast();
      }
    }
    if (reduced.isEmpty) return _cachedPath!;

    final pathPoints = reduced;

    // Path-outline pens already include round joins/caps. Midpoint smoothing of
    // the outline polygon creates self-intersections near returns and chipped caps.
    // Fountain keeps the previous smoothed-path look (mesh tips are separate).
    final bool preserveAuthoredOutline =
        toolId == ToolId.highlighter ||
        toolId == ToolId.advancedPen ||
        toolId == ToolId.advancedPencil ||
        toolId == ToolId.ballpointPen ||
        toolId == ToolId.laserPointer;

    if (toolId == ToolId.calligraphyPen &&
        options.isComplete &&
        pathPoints.length >= 3) {
      _cachedPath!.moveTo(pathPoints[0].dx, pathPoints[0].dy);
      for (int i = 1; i < pathPoints.length - 1; i++) {
        final p1 = pathPoints[i];
        final p2 = pathPoints[i + 1];
        final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        _cachedPath!.quadraticBezierTo(p1.dx, p1.dy, mid.dx, mid.dy);
      }
      _cachedPath!.lineTo(pathPoints.last.dx, pathPoints.last.dy);
      _cachedPath!.close();
    } else if (pathPoints.length >= 3 && !preserveAuthoredOutline) {
      _cachedPath!.addPath(smoothPathFromPolygon(pathPoints), Offset.zero);
    } else {
      _cachedPath!.addPolygon(pathPoints, true);
    }

    if (toolId == ToolId.calligraphyPen ||
        toolId == ToolId.advancedPen ||
        toolId == ToolId.advancedPencil ||
        toolId == ToolId.experimentalPen ||
        toolId == ToolId.highlighter ||
        toolId == ToolId.ballpointPen) {
      _cachedPath!.fillType = PathFillType.nonZero;
    }

    _cachedPathValid = true;
    return _cachedPath!;
  }

  void shift(Offset offset) {
    if (offset == Offset.zero) return;

    _detachMeshFromGlobalCache();
    points.shift(offset);
    _packedPoints = null;
    _lowQualityPolygon?.shift(offset);
    _highQualityPolygon?.shift(offset);
    _exportPolygon = null;
    _highQualitySpine = null;
    _lowQualityPath = _lowQualityPath?.shift(offset);

    _cachedPath = _cachedPath?.shift(offset);
    _neonInnerPath = _neonInnerPath?.shift(offset);
    _pencilPlan?.shift(offset);
    _shiftLockedPencilSpine(offset);
    for (final chunk in _liveFrozenPencilChunks) {
      chunk.shift(offset);
    }
    final tipChunks = _livePencilTipChunks;
    if (tipChunks != null) {
      for (final chunk in tipChunks) {
        chunk.shift(offset);
      }
    } else {
      _livePencilTip?.shift(offset);
    }
    final committed = _committedPencilChunks;
    if (committed != null) {
      for (final chunk in committed) {
        chunk.shift(offset);
      }
    }

    if (_cachedBounds != null) {
      _cachedBounds = _cachedBounds!.shift(offset);
    }

    _mapMeshPositions((x, y) => (x + offset.dx, y + offset.dy));
    _rebuildCachedVerticesFromCommitted();
    _refreshSpineMeshAfterTransform();
    _invalidateVectorFillPicture();
  }

  void rotate(double angleRad, Offset center) {
    if (angleRad == 0.0) return;

    _detachMeshFromGlobalCache();
    final cos = math.cos(angleRad);
    final sin = math.sin(angleRad);

    for (int i = 0; i < points.length; i++) {
      final point = points[i];
      final dx = point.x - center.dx;
      final dy = point.y - center.dy;
      final newX = center.dx + dx * cos - dy * sin;
      final newY = center.dy + dx * sin + dy * cos;
      points[i] = PointVector(newX, newY, point.pressure);
    }
    _packedPoints = null;

    void rotatePolygon(List<Offset>? polygon) {
      if (polygon == null) return;
      for (int i = 0; i < polygon.length; i++) {
        final p = polygon[i];
        final dx = p.dx - center.dx;
        final dy = p.dy - center.dy;
        polygon[i] = Offset(
          center.dx + dx * cos - dy * sin,
          center.dy + dx * sin + dy * cos,
        );
      }
    }

    rotatePolygon(_lowQualityPolygon);
    rotatePolygon(_highQualityPolygon);
    _exportPolygon = null;
    _highQualitySpine = null;
    for (var i = 0; i < _lockedPencilSpine.length; i++) {
      final p = _lockedPencilSpine[i];
      final dx = p.dx - center.dx;
      final dy = p.dy - center.dy;
      _lockedPencilSpine[i] = PointVector(
        center.dx + dx * cos - dy * sin,
        center.dy + dx * sin + dy * cos,
        p.pressure,
      );
    }

    rotationDeg = (rotationDeg + angleRad * 180.0 / math.pi) % 360.0;

    _lowQualityPath = null;
    _cachedPath = null;
    _cachedPathValid = false;
    _invalidateVectorFillPicture();
    _neonInnerPath = null;
    _invalidatePencilPlan();
    _clearLivePencilChunks();
    _mapMeshPositions((x, y) {
      final dx = x - center.dx;
      final dy = y - center.dy;
      return (
        center.dx + dx * cos - dy * sin,
        center.dy + dx * sin + dy * cos,
      );
    });
    _rebuildCachedVerticesFromCommitted();
    _refreshSpineMeshAfterTransform();
    _invalidateSpatialData();
  }

  void markPolygonNeedsUpdating({bool preserveBounds = false}) {
    _lowQualityPolygon = null;
    _highQualityPolygon = null;
    _exportPolygon = null;
    _highQualitySpine = null;
    _lowQualityPath = null;
    _cachedPathValid = false;
    _cachedVertices = null;
    _cachedVerticesHash = null;
    _packedPoints = null;
    _neonInnerPath = null;
    _invalidatePencilPlan();
    _invalidateVectorFillPicture();
    if (!preserveBounds) {
      _clearLiveCheapSpineFreeze();
      _clearLivePencilChunks();
      _invalidateSpatialData();
    }
  }

  void scale(double factor, Offset center) {
    if (factor == 1.0) return;
    _detachMeshFromGlobalCache();
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final dx = p.x - center.dx;
      final dy = p.y - center.dy;
      points[i] = PointVector(
        center.dx + dx * factor,
        center.dy + dy * factor,
        p.pressure,
      );
    }
    options.size *= factor;
    for (var i = 0; i < _lockedPencilSpine.length; i++) {
      final p = _lockedPencilSpine[i];
      final dx = p.dx - center.dx;
      final dy = p.dy - center.dy;
      _lockedPencilSpine[i] = PointVector(
        center.dx + dx * factor,
        center.dy + dy * factor,
        p.pressure,
      );
    }
    markPolygonNeedsUpdating(preserveBounds: true);
    _mapMeshPositions((x, y) {
      return (
        center.dx + (x - center.dx) * factor,
        center.dy + (y - center.dy) * factor,
      );
    });
    _rebuildCachedVerticesFromCommitted();
    _refreshSpineMeshAfterTransform();
    _invalidateSpatialData();
  }

  /// Drop this stroke's mesh from the process-wide cache before mutating
  /// positions in place. Otherwise later strokes with the same pre-transform
  /// fingerprint reuse a translated/rotated buffer (misplaced caps).
  void _detachMeshFromGlobalCache() {
    final fp = visualFingerprint;
    final keys = <int>{
      if (_cachedVerticesHash != null) _cachedVerticesHash!,
      fp,
      Object.hash(fp, 0x0b11),
    };
    for (final key in keys) {
      _globalVertexCache.remove(key);
      _vertexCacheLru.remove(key);
    }
  }

  /// Spine-mesh pens keep a single [_rawPositions] buffer. Rebuild [Vertices]
  /// after an in-place transform.
  void _refreshSpineMeshAfterTransform() {
    final pos = _rawPositions;
    final ind = _rawIndices;
    if (pos == null || ind == null || pos.isEmpty || ind.isEmpty) return;
    _cachedVertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      pos,
      indices: ind,
    );
    _cachedVerticesHash = visualFingerprint;
  }

  void _mapMeshPositions((double, double) Function(double x, double y) map) {
    final pos = _rawPositions;
    if (pos == null) return;
    for (var i = 0; i + 1 < pos.length; i += 2) {
      final mapped = map(pos[i], pos[i + 1]);
      pos[i] = mapped.$1;
      pos[i + 1] = mapped.$2;
    }
  }

  void _rebuildCachedVerticesFromCommitted() {
    _refreshSpineMeshAfterTransform();
  }

  bool contains(Offset position) {
    if (isEmpty) return false;

    final double tolerance = math.max(10, options.size);
    if (!bounds.inflate(tolerance).contains(position)) return false;

    final double toleranceSq = tolerance * tolerance;
    for (final p in points) {
      final double dx = p.x - position.dx;
      final double dy = p.y - position.dy;
      if ((dx * dx + dy * dy) < toleranceSq) return true;
    }
    return false;
  }

  bool isHitByCircle(Offset center, double radius) {
    if (isEmpty) return false;

    final effectiveRadius = radius + (options.size / 2);
    final hitRect = Rect.fromCircle(center: center, radius: effectiveRadius);
    if (!bounds.inflate(options.size / 2).overlaps(hitRect)) return false;

    final points = this.points;
    if (points.length < 2) {
      if (points.length == 1) {
        final p = points.first;
        final dx = p.x - center.dx;
        final dy = p.y - center.dy;
        return (dx * dx + dy * dy) <= (effectiveRadius * effectiveRadius);
      }
      return false;
    }

    final effectiveRadiusSq = effectiveRadius * effectiveRadius;
    final eraserLeft = center.dx - effectiveRadius;
    final eraserRight = center.dx + effectiveRadius;
    final eraserTop = center.dy - effectiveRadius;
    final eraserBottom = center.dy + effectiveRadius;

    final int stride = points.length <= 8 ? 1 : 5;
    final double looseRadiusSq = (effectiveRadius * 4) * (effectiveRadius * 4);
    bool possibleHit = false;
    for (int i = 0; i < points.length; i += stride) {
      final p = points[i];
      final dx = p.x - center.dx;
      final dy = p.y - center.dy;
      if (dx * dx + dy * dy <= looseRadiusSq) {
        possibleHit = true;
        break;
      }
    }
    if (!possibleHit) return false;

    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      final minX = math.min(p1.x, p2.x);
      final maxX = math.max(p1.x, p2.x);
      if (minX > eraserRight || maxX < eraserLeft) continue;
      final minY = math.min(p1.y, p2.y);
      final maxY = math.max(p1.y, p2.y);
      if (minY > eraserBottom || maxY < eraserTop) continue;

      if (_distToSegmentSq(center, Offset(p1.x, p1.y), Offset(p2.x, p2.y)) <=
          effectiveRadiusSq) {
        return true;
      }
    }
    return false;
  }

  static double _distToSegmentSq(Offset p, Offset v, Offset w) {
    final dx = w.dx - v.dx;
    final dy = w.dy - v.dy;
    final magSq = dx * dx + dy * dy;

    if (magSq == 0.0) {
      final px = p.dx - v.dx;
      final py = p.dy - v.dy;
      return px * px + py * py;
    }

    final u = ((p.dx - v.dx) * dx + (p.dy - v.dy) * dy) / magSq;
    final tClamped = u.clamp(0.0, 1.0);

    final projX = v.dx + tClamped * dx;
    final projY = v.dy + tClamped * dy;

    final diffX = p.dx - projX;
    final diffY = p.dy - projY;
    return diffX * diffX + diffY * diffY;
  }

  Stroke({
    required this.color,
    required this.pressureEnabled,
    required this.options,
    required this.pageIndex,
    required this.page,
    required this.toolId,
  }) {
    resetStabilization();
  }

  factory Stroke.fromJson(
    Map<String, dynamic> json, {
    required int fileVersion,
    required int pageIndex,
    required HasSize page,
  }) {
    assert(json['i'] == pageIndex || json['i'] == null);

    if (json['type'] == 'ShapeStroke') {
      return ShapeStroke.fromJson(
        json,
        fileVersion: fileVersion,
        pageIndex: pageIndex,
        page: page,
      );
    }

    switch (json['shape'] as String?) {
      case null:
        break;
      case 'circle':
        return CircleStroke.fromJson(
          json,
          fileVersion: fileVersion,
          pageIndex: pageIndex,
          page: page,
        );
      case 'rect':
        return RectangleStroke.fromJson(
          json,
          fileVersion: fileVersion,
          pageIndex: pageIndex,
          page: page,
        );
      case 'shapeCustom':
        return ShapeStroke.fromJson(
          json,
          fileVersion: fileVersion,
          pageIndex: pageIndex,
          page: page,
        );
      default:
        log.severe("Unknown shape: ${json['shape']}");
    }

    final ToolId toolId = ToolId.parsePenType(
      json['ty'],
      fallback: ToolId.fountainPen,
    );
    final options = StrokeOptions.fromJson(json);
    final bool flatEdge = json['fe'] ?? !options.start.cap;
    final pressureEnabled = json['pe'] ?? defaultPressureEnabled;

    if (toolId == ToolId.shapePen) {
      options.smoothing = 0;
      options.streamline = 0;
    }

    final Color color;
    switch (json['c']) {
      case (final int value):
        color = Color(value);
      case (final Int64 value):
        color = Color(value.toInt());
      case null:
        color = defaultColor;
      default:
        throw Exception(
          "Invalid color value: (${json['c'].runtimeType}) ${json['c']}",
        );
    }

    final offset = Offset(
      toDoubleSafe(json['ox']) ?? 0,
      toDoubleSafe(json['oy']) ?? 0,
    );
    final pointsJson = json['p'] as List<dynamic>;
    final Iterable<PointVector> points;
    if (fileVersion >= 13) {
      points = pointsJson.map(
        (point) => PointExtensions.fromBsonBinary(json: point, offset: offset),
      );
    } else {
      points = pointsJson.map(
        (point) => PointExtensions.fromJson(
          json: Map<String, dynamic>.from(point),
          offset: offset,
        ),
      );
    }

    return Stroke(
        color: color,
        pressureEnabled: pressureEnabled,
        options: options,
        pageIndex: pageIndex,
        page: page,
        toolId: toolId,
      )
      ..points.addAll(
        points.where(
          (point) =>
              point.x.isFinite &&
              point.y.isFinite &&
              (point.pressure == null || point.pressure!.isFinite),
        ),
      )
      ..rotationDeg = toDoubleSafe(json['rot']) ?? 0
      ..flatEdge = flatEdge
      ..neon = json['n'] as bool? ?? false
      ..paint = json['sp'] is Map
          ? StrokePaint.fromJson(Map<String, dynamic>.from(json['sp'] as Map))
          : const StrokePaint();
  }
  Map<String, dynamic> toJson() {
    if (toolId == ToolId.highlighter) {
      options.start.cap = !flatEdge;
      options.end.cap = !flatEdge;
    }

    return {
      'shape': null,
      'p': points
          .where((point) => point.isFinite)
          .map((PointVector point) => point.toBsonBinary())
          .toList(),
      'i': pageIndex,
      'ty': toolId.id,
      'fe': flatEdge,
      'pe': pressureEnabled,
      'c': color.toARGB32(),
      'rot': rotationDeg,
      if (neon) 'n': true,
      if (!paint.isSolid) 'sp': paint.toJson(),
    }..addAll(options.toJson());
  }

  void toBinary(BinaryWriter writer) {
    if (toolId == ToolId.highlighter) {
      options.start.cap = !flatEdge;
      options.end.cap = !flatEdge;
    }

    final finitePoints = points
        .where(
          (point) =>
              point.x.isFinite &&
              point.y.isFinite &&
              (!pressureEnabled ||
                  point.pressure == null ||
                  point.pressure!.isFinite),
        )
        .toList(growable: false);

    writer.writeString(StrokeBinaryKeys.shape, '');
    writer.writeInt(StrokeBinaryKeys.pointCount, finitePoints.length);
    writer.writeBool(StrokeBinaryKeys.pressureEnabled, pressureEnabled);
    for (final point in finitePoints) {
      writer.writeScaledFloatNoKey(point.x);
      writer.writeScaledFloatNoKey(point.y);
      if (pressureEnabled) {
        writer.writeScaledFloatNoKey(point.pressure ?? 0.5);
      }
    }

    writer.writeInt(StrokeBinaryKeys.pageIndex, pageIndex);
    writer.writeString(StrokeBinaryKeys.penType, penType);
    writer.writeInt(StrokeBinaryKeys.color, color.toARGB32());
    if (neon) {
      writer.writeBool(StrokeBinaryKeys.neon, true);
    }
    if (!paint.isSolid) {
      writer.writeString(
        StrokeBinaryKeys.strokePaint,
        jsonEncode(paint.toJson()),
      );
    }

    BinaryOptions().optionsToBinary(writer, options);
  }

  factory Stroke.fromBinary(
    BinaryReader reader, {
    int offset = 0,
    required int fileVersion,
    required HasSize page,
  }) {
    int key;
    final int pointCount;

    key = reader.readKey();
    if (key != StrokeBinaryKeys.shape) {
      throw Exception('StrokefromBinary no shape');
    }
    final shape = reader.readStringNoKey();
    switch (shape) {
      case '':
        break;
      case 'circle':
        return CircleStroke.fromBinary(reader, page: page);
      case 'rect':
        return RectangleStroke.fromBinary(reader, page: page);
      case 'shapeCustom':
        return ShapeStroke.fromBinary(reader, page: page);
      default:
        log.severe('StrokeFromBinary Unknown shape: $shape');
    }

    key = reader.readKey();
    if (key != StrokeBinaryKeys.pointCount) {
      throw Exception('StrokefromBinary no pointCount');
    }
    pointCount = reader.readIntNoKey();

    final bool pressureEnabled;
    key = reader.readKey();
    if (key != StrokeBinaryKeys.pressureEnabled) {
      throw Exception('StrokefromBinary no pressureEnabled');
    }
    pressureEnabled = reader.readBoolNoKey();
    
    // Alocação linear super rápida de ponteiros contínuos em memória, evita Garbage Collection overhead.
    final points = List<PointVector>.filled(pointCount, PointVector(0, 0), growable: true);
    final data = reader.data;
    int offset = reader.offset;

    if (pressureEnabled) {
      for (int i = 0; i < pointCount; i++) {
        double x = data.getInt32(offset, Endian.little) / 1000.0;
        offset += 4;
        double y = data.getInt32(offset, Endian.little) / 1000.0;
        offset += 4;
        double pressure = data.getInt32(offset, Endian.little) / 1000.0;
        offset += 4;
        points[i] = PointVector(x, y, pressure);
      }
    } else {
      for (int i = 0; i < pointCount; i++) {
        double x = data.getInt32(offset, Endian.little) / 1000.0;
        offset += 4;
        double y = data.getInt32(offset, Endian.little) / 1000.0;
        offset += 4;
        points[i] = PointVector(x, y);
      }
    }
    reader.offset = offset;

    final int pageIndex;
    key = reader.readKey();
    if (key != StrokeBinaryKeys.pageIndex) {
      throw Exception('StrokefromBinary no pageIndex');
    }
    pageIndex = reader.readIntNoKey();

    final String penType;
    key = reader.readKey();
    if (key != StrokeBinaryKeys.penType) {
      throw Exception('StrokefromBinary no penType');
    }
    penType = reader.readStringNoKey();

    final Color color;
    key = reader.readKey();
    if (key != StrokeBinaryKeys.color) {
      throw Exception('StrokefromBinary no color');
    }
    color = reader.readColor();

    key = reader.readKey();
    if (key == StrokeBinaryKeys.pencilTextureIndex) {
      reader.readIntNoKey();
      key = reader.readKey();
    }
    var neon = false;
    if (key == StrokeBinaryKeys.neon) {
      neon = reader.readBoolNoKey();
      key = reader.readKey();
    }
    StrokePaint paint = const StrokePaint();
    if (key == StrokeBinaryKeys.strokePaint) {
      final packed = reader.readStringNoKey();
      try {
        final map = jsonDecode(packed);
        if (map is Map) {
          paint = StrokePaint.fromJson(Map<String, dynamic>.from(map));
        }
      } catch (_) {}
      key = reader.readKey();
    }
    final options = BinaryOptions().optionsFromBinary(reader, initialKey: key);

    return Stroke(
        color: color,
        pressureEnabled: pressureEnabled,
        options: options,
        pageIndex: pageIndex,
        page: page,
        toolId: ToolId.parsePenType(penType, fallback: ToolId.fountainPen),
      )
      ..flatEdge = !options.start.cap
      ..neon = neon
      ..paint = paint
      ..points.addAll(
        points.where(
          (point) =>
              point.x.isFinite &&
              point.y.isFinite &&
              (point.pressure == null || point.pressure!.isFinite),
        ),
      );
  }

  static void skipFromBinary(BinaryReader reader) {
    int key = reader.readKey();
    if (key != StrokeBinaryKeys.shape) {
      throw Exception('Stroke.skipFromBinary no shape');
    }
    final shape = reader.readStringNoKey();
    switch (shape) {
      case '':
        break;
      case 'circle':
        CircleStroke.skipFromBinary(reader);
        return;
      case 'rect':
        RectangleStroke.skipFromBinary(reader);
        return;
      case 'shapeCustom':
        ShapeStroke.skipFromBinary(reader);
        return;
      default:
        log.severe('Stroke.skipFromBinary Unknown shape: $shape');
        break;
    }

    key = reader.readKey();
    if (key != StrokeBinaryKeys.pointCount) {
      throw Exception('Stroke.skipFromBinary no pointCount');
    }
    final pointCount = reader.readIntNoKey();

    key = reader.readKey();
    if (key != StrokeBinaryKeys.pressureEnabled) {
      throw Exception('Stroke.skipFromBinary no pressureEnabled');
    }
    final pressureEnabled = reader.readBoolNoKey();
    for (int i = 0; i < pointCount; i++) {
      reader.readScaledFloat();
      reader.readScaledFloat();
      if (pressureEnabled) {
        reader.readScaledFloat();
      }
    }

    key = reader.readKey();
    if (key != StrokeBinaryKeys.pageIndex) {
      throw Exception('Stroke.skipFromBinary no pageIndex');
    }
    reader.readIntNoKey();

    key = reader.readKey();
    if (key != StrokeBinaryKeys.penType) {
      throw Exception('Stroke.skipFromBinary no penType');
    }
    reader.readStringNoKey();

    key = reader.readKey();
    if (key != StrokeBinaryKeys.color) {
      throw Exception('Stroke.skipFromBinary no color');
    }
    reader.readColor();

    key = reader.readKey();
    if (key == StrokeBinaryKeys.pencilTextureIndex) {
      reader.readIntNoKey();
      key = reader.readKey();
    }
    if (key == StrokeBinaryKeys.neon) {
      reader.readBoolNoKey();
      key = reader.readKey();
    }
    if (key == StrokeBinaryKeys.strokePaint) {
      reader.readStringNoKey();
      key = reader.readKey();
    }
    BinaryOptions().optionsFromBinary(reader, initialKey: key);
  }

  double? _drawSampleTimeSec;
  double? _prevDrawSampleTimeSec;

  Offset? _predictionTip;
  double? _predictionPressure;

  /// Raw pointer kinematics for live stroke prediction (not affected by stabilization).
  Offset? _predPrevRawPos;
  double? _predPrevRawTimeSec;
  Offset? _predEmaVelocity;
  Offset? _predInstantVelPrev;
  Offset? _predInstantVelLast;

  /// Stroke stabilization / prediction apply only to these ink tools.
  bool get _allowsStrokeStabilizationAndPrediction =>
      toolId == ToolId.ballpointPen ||
      toolId == ToolId.calligraphyPen ||
      toolId == ToolId.fountainPen ||
      toolId == ToolId.advancedPen ||
      toolId == ToolId.advancedPencil;

  void addPoint(Offset point, [double? pressure, Duration? timestamp]) {
    if (!pressureEnabled) {
      pressure = null;
    } else if (pressure != null) {
      options.simulatePressure = false;
    }

    final Offset samplePoint = _allowsStrokeStabilizationAndPrediction
        ? _applyStabilization(point, timestamp)
        : point;

    final double eventTimeSec = timestamp != null
        ? timestamp.inMicroseconds / 1e6
        : (_drawSampleTimeSec ?? 0.0) + 1.0 / 60.0;

    if (_allowsStrokeStabilizationAndPrediction) {
      _updateRawPredictionKinematics(point, eventTimeSec);
    }

    if (toolId == ToolId.highlighter && Highlighter.straightLine.value) {
      if (points.isEmpty) {
        _commitStabilizedSample(samplePoint, pressure, eventTimeSec);
      } else {
        final first = points.first;
        final current = PointVector(samplePoint.dx, samplePoint.dy, pressure);
        final snapped = snapLine(first, current);
        points.clear();
        _packedPoints = null;
        _commitStabilizedSample(
          Offset(first.x, first.y),
          first.pressure,
          eventTimeSec,
        );
        _commitStabilizedSample(
          Offset(snapped.$2.x, snapped.$2.y),
          snapped.$2.pressure,
          eventTimeSec,
        );
      }
    } else if (points.isEmpty) {
      _commitStabilizedSample(samplePoint, pressure, eventTimeSec);
    } else {
      _commitStabilizedSampleWithGapFill(samplePoint, pressure, eventTimeSec);
    }
  }

  void _commitStabilizedSampleWithGapFill(
    Offset stabilizedPoint,
    double? pressure,
    double timeSec,
  ) {
    if (points.isEmpty) {
      _commitStabilizedSample(stabilizedPoint, pressure, timeSec);
      return;
    }

    final previous = points.last;
    final previousPoint = Offset(previous.x, previous.y);
    final delta = stabilizedPoint - previousPoint;
    final distance = delta.distance;
    // Sparse midpoints: dense gap-fill makes the live spline feel heavy even
    // when FPS is high (the tip is pulled toward extra interpolated samples).
    final maxStep = math.max(3.2, options.size * 1.05);
    final feelMax = DisplayInkFeel.instance.maxGapFills;
    var maxFills = _usesLiveCheapSpineMesh
        ? math.min(2, feelMax)
        : feelMax;
    // After an input stall the stylus can jump far; fill more midpoints so the
    // recovered segment does not read as a single square-ish chord.
    if (distance > maxStep * 3) {
      maxFills = math.max(maxFills, DisplayInkFeel.instance.isLowRefresh ? 4 : 5);
    }
    final gapFillCount = (distance / maxStep).floor().clamp(0, maxFills);

    if (gapFillCount > 1) {
      final previousTime = _drawSampleTimeSec ?? timeSec;
      for (var i = 1; i < gapFillCount; i++) {
        final t = i / gapFillCount;
        final interpolatedPressure =
            previous.pressure == null || pressure == null
            ? pressure ?? previous.pressure
            : previous.pressure! + (pressure - previous.pressure!) * t;
        _commitStabilizedSample(
          Offset(
            previousPoint.dx + delta.dx * t,
            previousPoint.dy + delta.dy * t,
          ),
          interpolatedPressure,
          previousTime + (timeSec - previousTime) * t,
          recomputePrediction: false,
        );
      }
    }

    _commitStabilizedSample(
      stabilizedPoint,
      pressure,
      timeSec,
      recomputePrediction: true,
    );
  }

  void _commitStabilizedSample(
    Offset stabilizedPoint,
    double? pressure,
    double timeSec, {
    bool recomputePrediction = true,
  }) {
    _prevDrawSampleTimeSec = _drawSampleTimeSec;
    _drawSampleTimeSec = timeSec;

    points.add(PointVector(stabilizedPoint.dx, stabilizedPoint.dy, pressure));
    _packedPoints = null;
    _cachedAveragePressure = null;

    final double r = options.size / 2;
    final double x = stabilizedPoint.dx;
    final double y = stabilizedPoint.dy;
    if (_cachedBounds != null) {
      _cachedBounds = Rect.fromLTRB(
        math.min(_cachedBounds!.left, x - r),
        math.min(_cachedBounds!.top, y - r),
        math.max(_cachedBounds!.right, x + r),
        math.max(_cachedBounds!.bottom, y + r),
      );
    }

    if (recomputePrediction) {
      _recomputePredictionTip();
      if (_predictionTip != null && _cachedBounds != null) {
        final px = _predictionTip!.dx;
        final py = _predictionTip!.dy;
        _cachedBounds = Rect.fromLTRB(
          math.min(_cachedBounds!.left, px - r),
          math.min(_cachedBounds!.top, py - r),
          math.max(_cachedBounds!.right, px + r),
          math.max(_cachedBounds!.bottom, py + r),
        );
      }
    }

    markPolygonNeedsUpdating(preserveBounds: true);
  }

  void _updateRawPredictionKinematics(Offset rawPosition, double timeSec) {
    if (_predPrevRawPos != null && _predPrevRawTimeSec != null) {
      final dt = (timeSec - _predPrevRawTimeSec!).clamp(1e-4, 0.25);
      final ix = (rawPosition.dx - _predPrevRawPos!.dx) / dt;
      final iy = (rawPosition.dy - _predPrevRawPos!.dy) / dt;
      final instant = Offset(ix, iy);
      // At ~60 Hz samples arrive near 16 ms; use a faster EMA so direction
      // changes reach the tip lead within one frame.
      final lowHz = DisplayInkFeel.instance.isLowRefresh;
      final beta = lowHz
          ? (dt < 0.020 ? 0.74 : 0.62)
          : (dt < 0.011 ? 0.68 : 0.56);
      _predEmaVelocity = _predEmaVelocity == null
          ? instant
          : Offset(
              _predEmaVelocity!.dx * (1 - beta) + instant.dx * beta,
              _predEmaVelocity!.dy * (1 - beta) + instant.dy * beta,
            );
      _predInstantVelPrev = _predInstantVelLast;
      _predInstantVelLast = instant;
    }
    _predPrevRawPos = rawPosition;
    _predPrevRawTimeSec = timeSec;
  }

  Offset? _filteredPoint;
  Offset? _filteredVelocity;
  double? _lastTimestampSeconds;

  double _alpha(double cutoff, double dt) {
    final tau = 1.0 / (2 * math.pi * cutoff);
    return 1.0 / (1.0 + tau / dt);
  }

  Offset _lowPass(Offset current, Offset? prev, double alpha) {
    if (prev == null) return current;
    return Offset(
      prev.dx + alpha * (current.dx - prev.dx),
      prev.dy + alpha * (current.dy - prev.dy),
    );
  }

  Offset _applyStabilization(Offset point, Duration? timestamp) {
    if (!_allowsStrokeStabilizationAndPrediction ||
        !stows.strokeStabilization.value ||
        stows.strokeStabilizationAmount.value <= 0) {
      return point;
    }

    // At ~60 Hz, heavy 1€ filtering reads as rubber-banding; ease it so the
    // committed tip stays closer to the stylus while prediction covers the rest.
    final amount = (stows.strokeStabilizationAmount.value *
            DisplayInkFeel.instance.stabilizationScale)
        .clamp(0.0, 1.0);
    if (amount <= 0.001) return point;

    final minCutoff = 10.0 * math.pow(0.05, amount);
    final beta = 0.1 * math.pow(0.01, amount);
    const dCutoff = 1.0;

    final double now =
        timestamp?.inMicroseconds.toDouble() ??
        (_lastTimestampSeconds == null
            ? 0.0
            : _lastTimestampSeconds! + 16666.0);
    final double nowSeconds = now / 1000000.0;

    if (_lastTimestampSeconds == null) {
      _lastTimestampSeconds = nowSeconds;
      _filteredPoint = point;
      _filteredVelocity = Offset.zero;
      return point;
    }

    final dt = (nowSeconds - _lastTimestampSeconds!).clamp(0.001, 0.1);
    _lastTimestampSeconds = nowSeconds;

    final velocity = (point - _filteredPoint!) / dt;
    final alphaD = _alpha(dCutoff, dt);
    _filteredVelocity = _lowPass(velocity, _filteredVelocity, alphaD);
    final speed = _filteredVelocity!.distance;

    final cutoff = minCutoff + beta * speed;
    final alphaPos = _alpha(cutoff, dt);

    _filteredPoint = _lowPass(point, _filteredPoint, alphaPos);

    return _filteredPoint!;
  }

  void resetStabilization() {
    _filteredPoint = null;
    _filteredVelocity = null;
    _lastTimestampSeconds = null;
    _drawSampleTimeSec = null;
    _prevDrawSampleTimeSec = null;
    _predictionTip = null;
    _predictionPressure = null;
    _predPrevRawPos = null;
    _predPrevRawTimeSec = null;
    _predEmaVelocity = null;
    _predInstantVelPrev = null;
    _predInstantVelLast = null;
  }

  void clearLivePrediction() {
    _predictionTip = null;
    _predictionPressure = null;
  }

  void _recomputePredictionTip() {
    _predictionTip = null;
    _predictionPressure = null;
    if (!_allowsStrokeStabilizationAndPrediction) return;
    if (options.isComplete || !stows.strokePrediction.value) return;
    if (points.length < 2) return;

    Offset v;
    if (_predEmaVelocity != null && _predEmaVelocity!.distance > 1e-3) {
      v = _predEmaVelocity!;
    } else if (_drawSampleTimeSec != null && _prevDrawSampleTimeSec != null) {
      final dt = (_drawSampleTimeSec! - _prevDrawSampleTimeSec!).clamp(
        1.2e-3,
        0.12,
      );
      final prev = points[points.length - 2];
      final last = points.last;
      v = Offset((last.x - prev.x) / dt, (last.y - prev.y) / dt);
    } else {
      return;
    }

    // At low refresh the 1€ velocity lags the stylus; prefer raw EMA so tip
    // lead does not re-inject the filter lag we just eased.
    if (stows.strokeStabilization.value &&
        _filteredVelocity != null &&
        _filteredVelocity!.distance > 18 &&
        !DisplayInkFeel.instance.isLowRefresh) {
      final f = _filteredVelocity!;
      v = Offset(v.dx * 0.52 + f.dx * 0.48, v.dy * 0.52 + f.dy * 0.48);
    }

    final speed = v.distance;
    if (speed < 2.5) return;

    final amount = stows.strokePredictionAmount.value.clamp(0.0, 1.0);

    var turnFactor = 1.0;
    if (_predInstantVelPrev != null && _predInstantVelLast != null) {
      final a = _predInstantVelPrev!;
      final b = _predInstantVelLast!;
      final la = a.distance;
      final lb = b.distance;
      if (la > 2.0 && lb > 2.0) {
        final cos = (a.dx * b.dx + a.dy * b.dy) / (la * lb);
        turnFactor = (0.22 + 0.78 * ((cos + 1) * 0.5)).clamp(0.18, 1.0);
      }
    } else if (points.length >= 3) {
      final p0 = points[points.length - 3];
      final prev = points[points.length - 2];
      final last = points.last;
      final v0dx = prev.x - p0.x;
      final v0dy = prev.y - p0.y;
      final v1dx = last.x - prev.x;
      final v1dy = last.y - prev.y;
      final len0 = math.sqrt(v0dx * v0dx + v0dy * v0dy);
      final len1 = math.sqrt(v1dx * v1dx + v1dy * v1dy);
      if (len0 > 1e-4 && len1 > 1e-4) {
        final cos = (v0dx * v1dx + v0dy * v1dy) / (len0 * len1);
        if (cos < 0.2) {
          turnFactor = 0.26;
        } else if (cos < 0.5) {
          turnFactor = 0.5;
        } else if (cos < 0.72) {
          turnFactor = 0.76;
        }
      }
    }

    final speedNorm = (speed / (speed + 88.0)).clamp(0.0, 1.0);
    final feel = DisplayInkFeel.instance;
    final lookaheadSec =
        (0.016 + 0.08 * amount + feel.predictionLookaheadBoostSec) *
        turnFactor *
        speedNorm;

    var dx = v.dx * lookaheadSec;
    var dy = v.dy * lookaheadSec;
    var dist = math.sqrt(dx * dx + dy * dy);
    final maxDist =
        (options.size * (2.6 + 3.6 * amount) * feel.predictionDistanceScale)
            .clamp(6.0, 72.0);
    if (dist > maxDist && dist > 0) {
      final s = maxDist / dist;
      dx *= s;
      dy *= s;
      dist = maxDist;
    }
    if (dist < 0.28) return;

    final last = points.last;
    // At low refresh, lean the tip origin toward the raw stylus so filter lag
    // does not leave a visible gap between pen and ink.
    final raw = _predPrevRawPos;
    final blend = feel.rawTipBlend;
    final originX = raw == null || blend <= 0
        ? last.x
        : last.x * (1.0 - blend) + raw.dx * blend;
    final originY = raw == null || blend <= 0
        ? last.y
        : last.y * (1.0 - blend) + raw.dy * blend;
    _predictionTip = Offset(originX + dx, originY + dy);
    _predictionPressure = last.pressure;
  }

  List<PointVector> _pointsForLiveRender(
    List<PointVector> source, {
    bool reuseBuffer = false,
  }) {
    if (!_allowsStrokeStabilizationAndPrediction ||
        options.isComplete ||
        !stows.strokePrediction.value ||
        _predictionTip == null) {
      return source;
    }
    if (source.isEmpty) return source;

    final p = _predictionPressure ?? source.last.pressure;
    final tip = PointVector(_predictionTip!.dx, _predictionTip!.dy, p);
    if (!reuseBuffer) {
      return [...source, tip];
    }
    final scratch = _liveRenderScratch ??= <PointVector>[];
    scratch
      ..clear()
      ..addAll(source)
      ..add(tip);
    return scratch;
  }

  void addPoints(List<Offset> points) {
    for (final point in points) {
      addPoint(point);
    }
  }

  void popFirstPoint() {
    points.removeAt(0);
    _cachedAveragePressure = null;
    markPolygonNeedsUpdating();
  }

  static const _optimisePointsThreshold = 0.1;

  void optimisePoints({double thresholdMultiplier = _optimisePointsThreshold}) {
    if (points.length <= 3) return;

    final minDistance = options.size * thresholdMultiplier;

    points.removeWhere((point) => point.pressure == null);

    for (int i = 1; i < points.length - 1; i++) {
      final point = points[i];
      final prev = points[i - 1];
      final next = points[i + 1];

      if (prev.distanceSquaredTo(point) < minDistance * minDistance &&
          point.distanceSquaredTo(next) < minDistance * minDistance) {
        points.removeAt(i);
        i--;
      }
    }
    _packedPoints = null;
  }

  @protected
  List<Offset> getPolygon({required StrokeQuality quality}) {
    if (!pressureEnabled) {
      options.simulatePressure = false;
    }

    // 1. Get points WITH the prediction tip appended FIRST
    final List<PointVector> basePoints = _pointsForLiveRender(points);

    // 2. Create a temporary packed array including the prediction tip
    Float32List? packedBase;
    if (basePoints.length >= 2) {
      packedBase = Float32List(basePoints.length * 3);
      for (int i = 0; i < basePoints.length; i++) {
        packedBase[i * 3] = basePoints[i].x;
        packedBase[i * 3 + 1] = basePoints[i].y;
        packedBase[i * 3 + 2] = basePoints[i].pressure ?? 0.5;
      }
    }

    final List<PointVector> sourcePoints;
    if (toolId == ToolId.highlighter) {
      if (basePoints.length >= 3) {
        // Dense slow samples make Catmull-Rom + offset normals unstable.
        // Decimate relative to brush radius before smoothing.
        final radius = (options.size / 2) * highlighterStrokeScaleFactor;
        final decimated = decimateStrokeSpine(
          basePoints,
          minDistance: math.max(0.75, radius * 0.35),
        );
        sourcePoints = decimated.length >= 3
            ? _getSmoothSpine(decimated)
            : decimated;
      } else {
        sourcePoints = basePoints;
      }
    } else if (toolId == ToolId.advancedPen ||
        toolId == ToolId.advancedPencil) {
      sourcePoints = _prepareAdvancedSpine(basePoints);
    } else if (toolId == ToolId.calligraphyPen ||
        toolId == ToolId.fountainPen ||
        toolId == ToolId.ballpointPen ||
        toolId == ToolId.laserPointer ||
        toolId == ToolId.experimentalPen) {
      if (basePoints.length >= 3 && packedBase != null) {
        final scale = _targetScale.clamp(0.1, 5.0);
        double toleranceMultiplier = 1.0;
        if (toolId == ToolId.experimentalPen) {
          // options.smoothing is [0.0, 1.0]
          // default 0.5 -> multiplier ~ 1.0
          // 0.0 -> multiplier ~ 0.1 (less tolerance, more points)
          // 1.0 -> multiplier ~ 3.0 (more tolerance, smoother/simpler)
          toleranceMultiplier = math.max(0.1, options.smoothing * 3.0);
        }
        final toleranceSq =
            (0.12 * toleranceMultiplier / scale) *
            (0.12 * toleranceMultiplier / scale);
        final smooth = _getAdaptiveSpineFast(packedBase, toleranceSq);
        final n = smooth.length ~/ 3;
        sourcePoints = List.generate(
          n,
          (i) =>
              PointVector(smooth[i * 3], smooth[i * 3 + 1], smooth[i * 3 + 2]),
        );
      } else {
        sourcePoints = basePoints;
      }
    } else {
      if (quality == StrokeQuality.high &&
          basePoints.length >= 3 &&
          packedBase != null) {
        final scale = _targetScale.clamp(0.1, 5.0);
        final toleranceSq = (0.14 / scale) * (0.14 / scale);
        final smooth = _getAdaptiveSpineFast(packedBase, toleranceSq);
        final n = smooth.length ~/ 3;
        sourcePoints = List.generate(
          n,
          (i) =>
              PointVector(smooth[i * 3], smooth[i * 3 + 1], smooth[i * 3 + 2]),
        );
      } else {
        sourcePoints = quality == StrokeQuality.high
            ? basePoints
            : _ramerDouglasPeucker(basePoints, epsilon: 0.05 * options.size);
      }
    }

    if (quality == StrokeQuality.high) {
      _highQualitySpine = sourcePoints;
    }

    // 3. Render the specific tool using our splined sourcePoints
    if (toolId == ToolId.calligraphyPen) {
      var strokePoints = sourcePoints;
      if (strokePoints.length == 1)
        strokePoints = [strokePoints.first, strokePoints.first];
      if (strokePoints.length < 2) return [];
      return _getCalligraphyPolygon(strokePoints, quality: quality);
    }

    if (toolId == ToolId.fountainPen) {
      var strokePoints = sourcePoints;
      if (strokePoints.length == 1)
        strokePoints = [strokePoints.first, strokePoints.first];
      return getStroke(
        strokePoints,
        options: _outlineOptionsForCurrentPhase(
          options.copyWith(
            thinning: options.thinning,
            smoothing: options.smoothing,
            streamline: options.streamline,
            simulatePressure: options.simulatePressure,
            start: options.start,
            end: options.end,
          ),
        ),
        rememberSimulatedPressure: false,
      );
    }

    if (toolId == ToolId.highlighter) {
      var strokePoints = sourcePoints;
      if (strokePoints.length == 1) {
        strokePoints = [strokePoints.first, strokePoints.first];
      }
      // Single closed outline (not a triangle mesh) so translucent ink does
      // not show darker overlap artifacts. Flat vs rounded via [flatEdge].
      return buildConstantWidthOutline(
        strokePoints,
        radius: (options.size / 2) * highlighterStrokeScaleFactor,
        roundCaps: !flatEdge,
      );
    }

    if (toolId == ToolId.ballpointPen || toolId == ToolId.laserPointer) {
      // Spine already smoothed above; outline only (shared with laser neon).
      return buildBallpointStyleOutline(sourcePoints, size: options.size);
    }

    if (toolId == ToolId.advancedPen || toolId == ToolId.advancedPencil) {
      return _advancedOutlineFromSpine(sourcePoints);
    }

    final useFullOptions =
        quality == StrokeQuality.high || toolId != ToolId.experimentalPen;
    StrokeOptions effectiveOptions = useFullOptions
        ? options
        : options.copyWith(
            simulatePressure: false,
            smoothing: 0.35,
            streamline: 0.15,
          );

    try {
      return getStroke(
        sourcePoints,
        options: _outlineOptionsForCurrentPhase(effectiveOptions),
        rememberSimulatedPressure: false,
      );
    } catch (e, st) {
      log.warning('getStroke crashed in getPolygon: $e', e, st);
      return sourcePoints.map((p) => Offset(p.x, p.y)).toList();
    }
  }

  List<Offset> _getCalligraphyPolygon(
    List<PointVector> strokePoints, {
    required StrokeQuality quality,
  }) {
    final int len = strokePoints.length;
    if (len < 2) return [];

    const double nibAngle = -40 * math.pi / 180;
    final double size = options.size;

    final double cosTheta = math.cos(nibAngle);
    final double sinTheta = math.sin(nibAngle);

    final double minDistSq = math.max(400.0, (size * 2.0) * (size * 2.0));

    final List<Offset> leftSide = List<Offset>.filled(len, Offset.zero);
    final List<Offset> rightSide = List<Offset>.filled(len, Offset.zero);

    double prevVx = 0.0;
    double prevVy = 0.0;
    double startDirX = 0.0;
    double startDirY = 0.0;
    double endDirX = 0.0;
    double endDirY = 0.0;

    for (int i = 0; i < len; i++) {
      final p = strokePoints[i];
      final double px = p.x;
      final double py = p.y;

      final double pressure = (p.pressure ?? 0.5).clamp(0.0, 1.0);
      double pressureScale = 0.5 + pressure * 0.5;

      double tanDx = 0.0;
      double tanDy = 0.0;
      if (i == 0) {
        for (int step = 1; step < len; step++) {
          tanDx = strokePoints[step].x - px;
          tanDy = strokePoints[step].y - py;
          if (tanDx * tanDx + tanDy * tanDy > minDistSq) break;
        }
        if (tanDx == 0 && tanDy == 0 && len > 1) {
          tanDx = strokePoints[1].x - px;
          tanDy = strokePoints[1].y - py;
        }
        startDirX = tanDx;
        startDirY = tanDy;
      } else if (i == len - 1) {
        for (int step = 1; step < len; step++) {
          tanDx = px - strokePoints[len - 1 - step].x;
          tanDy = py - strokePoints[len - 1 - step].y;
          if (tanDx * tanDx + tanDy * tanDy > minDistSq) break;
        }
        if (tanDx == 0 && tanDy == 0 && len > 1) {
          tanDx = px - strokePoints[len - 2].x;
          tanDy = py - strokePoints[len - 2].y;
        }
        endDirX = tanDx;
        endDirY = tanDy;
      } else {
        double pPrevX = strokePoints[i - 1].x;
        double pPrevY = strokePoints[i - 1].y;
        for (int step = 1; step <= i; step++) {
          pPrevX = strokePoints[i - step].x;
          pPrevY = strokePoints[i - step].y;
          if ((px - pPrevX) * (px - pPrevX) + (py - pPrevY) * (py - pPrevY) >
              minDistSq)
            break;
        }
        double pNextX = strokePoints[i + 1].x;
        double pNextY = strokePoints[i + 1].y;
        for (int step = 1; step < len - i; step++) {
          pNextX = strokePoints[i + step].x;
          pNextY = strokePoints[i + step].y;
          if ((pNextX - px) * (pNextX - px) + (pNextY - py) * (pNextY - py) >
              minDistSq)
            break;
        }
        tanDx = pNextX - pPrevX;
        tanDy = pNextY - pPrevY;
      }

      double distSq = tanDx * tanDx + tanDy * tanDy;
      if (distSq < 0.000001) {
        tanDx = 1.0;
        tanDy = 0.0;
        distSq = 1.0;
      }
      final double invLen = 1.0 / math.sqrt(distSq);
      double nxNorm = -tanDy * invLen;
      double nyNorm = tanDx * invLen;

      final double rx = size * 0.65 * pressureScale;
      final double ry = size * 0.12 * pressureScale;
      final double rx2 = rx * rx;
      final double ry2 = ry * ry;

      final double localNx = nxNorm * cosTheta + nyNorm * sinTheta;
      final double localNy = -nxNorm * sinTheta + nyNorm * cosTheta;

      final double scale =
          1.0 / math.sqrt(rx2 * localNx * localNx + ry2 * localNy * localNy);
      final double localVx = rx2 * localNx * scale;
      final double localVy = ry2 * localNy * scale;

      double vx = localVx * cosTheta - localVy * sinTheta;
      double vy = localVx * sinTheta + localVy * cosTheta;

      if (i > 0 && (vx * prevVx + vy * prevVy) < 0) {
        vx = -vx;
        vy = -vy;
      }
      prevVx = vx;
      prevVy = vy;

      leftSide[i] = Offset(px - vx, py - vy);
      rightSide[i] = Offset(px + vx, py + vy);
    }

    if (len >= 3) {
      for (int pass = 0; pass < 2; pass++) {
        final prevL = List<Offset>.from(leftSide);
        final prevR = List<Offset>.from(rightSide);
        for (int i = 1; i < len - 1; i++) {
          leftSide[i] = Offset(
            prevL[i - 1].dx * 0.25 + prevL[i].dx * 0.5 + prevL[i + 1].dx * 0.25,
            prevL[i - 1].dy * 0.25 + prevL[i].dy * 0.5 + prevL[i + 1].dy * 0.25,
          );
          rightSide[i] = Offset(
            prevR[i - 1].dx * 0.25 + prevR[i].dx * 0.5 + prevR[i + 1].dx * 0.25,
            prevR[i - 1].dy * 0.25 + prevR[i].dy * 0.5 + prevR[i + 1].dy * 0.25,
          );
        }
      }
    }

    const int ellipseSegments = 6;
    final List<Offset> result = [];

    void addEllipticalCap(
      double cx,
      double cy,
      double dirX,
      double dirY,
      double rxVal,
      double ryVal,
      bool towardStroke,
    ) {
      final dist = math.sqrt(dirX * dirX + dirY * dirY);
      if (dist < 0.001) return;
      final tx = dirX / dist;
      final ty = dirY / dist;
      final nx = -ty;
      final ny = tx;

      final sign = towardStroke ? 1.0 : -1.0;
      for (int k = 0; k <= ellipseSegments; k++) {
        final angle = sign * (math.pi * (k / ellipseSegments) - math.pi / 2);
        final ex =
            cx + rxVal * tx * math.cos(angle) + ryVal * nx * math.sin(angle);
        final ey =
            cy + rxVal * ty * math.cos(angle) + ryVal * ny * math.sin(angle);
        result.add(Offset(ex, ey));
      }
    }

    if (len >= 2) {
      final p0 = strokePoints[0];
      final pressure0 = (p0.pressure ?? 0.5).clamp(0.0, 1.0);
      final r0 = size * 0.65 * (0.5 + pressure0 * 0.5);
      final r0y = size * 0.12 * (0.5 + pressure0 * 0.5);
      addEllipticalCap(p0.x, p0.y, startDirX, startDirY, r0, r0y, true);

      for (int i = 1; i < len; i++) result.add(rightSide[i]);

      final pLast = strokePoints[len - 1];
      final pressureN = (pLast.pressure ?? 0.5).clamp(0.0, 1.0);
      final rN = size * 0.65 * (0.5 + pressureN * 0.5);
      final rNy = size * 0.12 * (0.5 + pressureN * 0.5);
      addEllipticalCap(pLast.x, pLast.y, endDirX, endDirY, rN, rNy, false);

      for (int i = len - 2; i >= 0; i--) result.add(leftSide[i]);
    }

    return result;
  }

  @protected
  Path getPath(List<Offset> polygon, {bool smooth = true}) {
    if (toolId == ToolId.calligraphyPen && polygon.isNotEmpty) {
      if (smooth && options.isComplete) {
        return smoothPathFromPolygon(polygon)..fillType = PathFillType.nonZero;
      }
      return Path()
        ..fillType = PathFillType.nonZero
        ..addPolygon(polygon, true);
    }

    // Keep authored stroke outlines as-is (see [highQualityPath]).
    // Fountain is excluded so completed paths keep their prior smoothed look.
    final bool maySmooth =
        smooth &&
        options.isComplete &&
        toolId != ToolId.highlighter &&
        toolId != ToolId.advancedPen &&
        toolId != ToolId.advancedPencil &&
        toolId != ToolId.ballpointPen &&
        toolId != ToolId.laserPointer;

    if (maySmooth) {
      return smoothPathFromPolygon(polygon)..fillType = PathFillType.nonZero;
    }

    return Path()
      ..fillType = PathFillType.nonZero
      ..addPolygon(polygon, true);
  }

  static List<PointVector> skipPoints(List<PointVector> points, int N) {
    if (N <= 1) return points;

    final divided = points.length / N;
    const minDivided = 8;
    if (divided < minDivided) {
      N = (N * divided / minDivided).floor();
      if (N <= 1) return points;
    }

    return [
      for (int i = 0; i < points.length - 1; i += N) points[i],
      points.last,
    ];
  }

  static Path smoothPathFromPolygon(List<Offset> polygon) {
    if (polygon.length < 2) return Path();
    final path = Path();
    path.moveTo(polygon.first.dx, polygon.first.dy);
    if (polygon.length == 2) {
      path.lineTo(polygon.last.dx, polygon.last.dy);
      return path..close();
    }

    for (int i = 1; i < polygon.length; i++) {
      final p1 = polygon[i];
      final p2 = polygon[(i + 1) % polygon.length];
      final mid = (p1 + p2) / 2;
      path.quadraticBezierTo(p1.dx, p1.dy, mid.dx, mid.dy);
    }
    return path..close();
  }

  String toSvgPath() {
    String toSvgPoint(Offset point) {
      return '${formatSvgPathDouble(point.dx)} '
          '${formatSvgPathDouble(page.size.height - point.dy)}';
    }

    final svgPoints = highQualityPolygon
        .where((offset) => offset.isFinite)
        .map(toSvgPoint);

    return svgPoints.isNotEmpty ? 'M${svgPoints.join('L')}' : '';
  }

  /// Ballpoint / laser outline from an already-splined centerline.
  static List<Offset> buildBallpointStyleOutline(
    List<PointVector> strokePoints, {
    required double size,
  }) {
    var pts = strokePoints;
    if (pts.isEmpty) return const <Offset>[];
    if (pts.length == 1) {
      pts = [pts.first, pts.first];
    }
    try {
      return getStroke(
        pts,
        options: StrokeOptions(
          size: size.abs(),
          thinning: 0,
          smoothing: 0.52,
          streamline: 0.32,
          simulatePressure: false,
          isComplete: true,
          start: StrokeEndOptions.start(
            taperEnabled: false,
            cap: true,
            easing: StrokeOptions.defaultEasing,
          ),
          end: StrokeEndOptions.end(
            taperEnabled: false,
            cap: true,
            easing: StrokeOptions.defaultEasing,
          ),
        ),
      );
    } catch (e, st) {
      log.warning('getStroke crashed in buildBallpointStyleOutline: $e', e, st);
      return pts.map((p) => Offset(p.x, p.y)).toList();
    }
  }

  /// Full ballpoint / laser neon pipeline: adaptive spine then constant-width outline.
  static List<Offset> buildBallpointStylePolygon(
    List<PointVector> points, {
    required double size,
    double targetScale = 1.0,
  }) {
    if (points.isEmpty) return const <Offset>[];
    var strokePoints = List<PointVector>.from(points);
    if (strokePoints.length == 1) {
      strokePoints = [strokePoints.first, strokePoints.first];
    }
    if (strokePoints.length >= 3) {
      final packed = Float32List(strokePoints.length * 3);
      for (var i = 0; i < strokePoints.length; i++) {
        packed[i * 3] = strokePoints[i].x;
        packed[i * 3 + 1] = strokePoints[i].y;
        packed[i * 3 + 2] = strokePoints[i].pressure ?? 0.5;
      }
      final scale = targetScale.clamp(0.1, 5.0);
      final toleranceSq = (0.12 / scale) * (0.12 / scale);
      final smooth = _getAdaptiveSpineFast(packed, toleranceSq);
      final n = smooth.length ~/ 3;
      strokePoints = List.generate(
        n,
        (i) => PointVector(smooth[i * 3], smooth[i * 3 + 1], smooth[i * 3 + 2]),
      );
    }
    return buildBallpointStyleOutline(strokePoints, size: size);
  }

  double get maxY {
    return points.isEmpty ? 0 : points.map((point) => point.y).reduce(math.max);
  }

  List<Offset> _shapeRecognitionCenterline({int maxInputPoints = 192}) {
    if (points.length <= maxInputPoints) {
      return points.map((p) => Offset(p.x, p.y)).toList(growable: false);
    }

    final sampled = <Offset>[];
    final lastIndex = points.length - 1;
    for (var i = 0; i < maxInputPoints; i++) {
      final sourceIndex = (i * lastIndex / (maxInputPoints - 1)).round();
      final point = points[sourceIndex];
      sampled.add(Offset(point.x, point.y));
    }
    return sampled;
  }

  RecognizedUnistroke? detectShape() {
    if (points.length < 2) return null;
    final centerline = _shapeRecognitionCenterline();

    if (centerline.length < 25 && isAngleBracketPreferred(centerline)) {
      final angleOnly = default$1Unistrokes
          .where(
            (u) =>
                u.name == DefaultUnistrokeNames.leftAngleBracket ||
                u.name == DefaultUnistrokeNames.rightAngleBracket,
          )
          .toList();
      if (angleOnly.isNotEmpty) {
        final angleResult = recognizeUnistroke(
          centerline,
          overrideReferenceUnistrokes: angleOnly,
        );
        if (angleResult != null && angleResult.score >= 0.5) {
          return angleResult;
        }
      }
    }
    return recognizeUnistroke(centerline);
  }

  bool isStraightLine([int minLength = 5]) {
    if (points.length < 3) return false;

    final sqrLength = points.first.distanceSquaredTo(points.last);
    final sqrMinLength = minLength * minLength * options.size * options.size;
    if (sqrLength < sqrMinLength) return false;

    final recognized = recognizeUnistroke(
      points,
      overrideReferenceUnistrokes: default$1Unistrokes
          .where((unistroke) => unistroke.name == DefaultUnistrokeNames.line)
          .toList(),
    );
    if (recognized == null) return false;
    assert(recognized.name == DefaultUnistrokeNames.line);
    return recognized.score >= 0.7;
  }

  void densifyStraightLine() {
    if (points.length < 2) return;
    final first = points.first;
    final last = points.last;
    final pressure = points.map((p) => p.pressure ?? 0.5).average;
    final dx = last.x - first.x;
    final dy = last.y - first.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) return;

    final stepPx = 8.0;
    final n = math.max(24, (len / stepPx).ceil() + 1).clamp(24, 512);

    final result = <PointVector>[];
    for (var i = 0; i <= n; i++) {
      final t = i / n;
      result.add(PointVector(first.x + t * dx, first.y + t * dy, pressure));
    }
    points.clear();
    points.addAll(result);
    _cachedBounds = null;
    _packedPoints = null;
    _cachedPath = null;
    _cachedPathValid = false;
    markPolygonNeedsUpdating();
  }

  void convertToLine() {
    assert(points.length >= 2);

    final offsets = points.map((p) => Offset(p.x, p.y)).toList();
    final (start, end) = fitLineAndProjectExtent(
      offsets,
      useChordDirection: true,
    );

    final pressure = points.map((point) => point.pressure ?? 0.5).average;
    var firstPoint = PointVector.fromOffset(offset: start, pressure: pressure);
    var lastPoint = PointVector.fromOffset(offset: end, pressure: pressure);

    (firstPoint, lastPoint) = snapLine(firstPoint, lastPoint);

    final midPoint = PointVector(
      (firstPoint.dx + lastPoint.dx) / 2,
      (firstPoint.dy + lastPoint.dy) / 2,
      pressure,
    );

    points.clear();
    points.add(firstPoint);
    points.add(midPoint);
    points.add(lastPoint);

    options.isComplete = true;
    options.start.taperEnabled = false;
    options.end.taperEnabled = false;

    _cachedBounds = null;
    _cachedVertices = null;
    _cachedPath = null;
    _cachedPathValid = false;
    markPolygonNeedsUpdating();
  }

  static (PointVector firstPoint, PointVector lastPoint) snapLine(
    PointVector firstPoint,
    PointVector lastPoint,
  ) {
    final dx = lastPoint.dx - firstPoint.dx;
    final dy = lastPoint.dy - firstPoint.dy;
    final angle = math.atan2(dy, dx);

    final snapAngle = 15 * math.pi / 180;
    final step = math.pi / 4;

    final closestStep = (angle / step).round() * step;
    if ((angle - closestStep).abs() < snapAngle) {
      final dist = math.sqrt(dx * dx + dy * dy);
      return (
        firstPoint,
        PointVector(
          firstPoint.x + dist * math.cos(closestStep),
          firstPoint.y + dist * math.sin(closestStep),
          lastPoint.pressure,
        ),
      );
    }

    return (firstPoint, lastPoint);
  }

  Stroke copy() =>
      Stroke(
          color: color,
          pressureEnabled: pressureEnabled,
          options: options.copyWith(),
          pageIndex: pageIndex,
          page: page,
          toolId: toolId,
        )
        ..points.addAll(points)
        ..rotationDeg = rotationDeg
        ..flatEdge = flatEdge
        ..neon = neon
        ..paint = paint
        .._lockedPencilSpine.addAll(_lockedPencilSpine);

  /// Freehand ink that can be rewritten as another pen (not shapes).
  bool get canConvertStrokeType =>
      this is! ShapeStroke &&
      this is! CircleStroke &&
      this is! RectangleStroke &&
      (toolId == ToolId.fountainPen ||
          toolId == ToolId.ballpointPen ||
          toolId == ToolId.calligraphyPen ||
          toolId == ToolId.advancedPen ||
          toolId == ToolId.advancedPencil ||
          toolId == ToolId.highlighter);

  /// Same path samples/color/page, with a new tool identity and style.
  Stroke rebuildWithTool({
    required ToolId toolId,
    required bool pressureEnabled,
    required StrokeOptions options,
    required StrokePaint paint,
    required bool neon,
    required bool flatEdge,
  }) {
    final rebuilt =
        Stroke(
            color: color,
            pressureEnabled: pressureEnabled,
            options: options,
            pageIndex: pageIndex,
            page: page,
            toolId: toolId,
          )
          ..points.addAll(points)
          ..rotationDeg = rotationDeg
          ..flatEdge = flatEdge
          ..neon = neon
          ..paint = paint;
    rebuilt.markPolygonNeedsUpdating();
    return rebuilt;
  }

  Stroke cloneForEraserFragment() =>
      Stroke(
          color: color,
          pressureEnabled: pressureEnabled,
          options: options.copyWith(),
          pageIndex: pageIndex,
          page: page,
          toolId: toolId,
        )
        ..rotationDeg = rotationDeg
        ..flatEdge = flatEdge
        ..neon = neon
        ..paint = paint;

  static List<PointVector> _ramerDouglasPeucker(
    List<PointVector> points, {
    required double epsilon,
  }) {
    if (points.length < 3) return points;

    final epsilonSq = epsilon * epsilon;
    final len = points.length;

    final Uint8List keep = Uint8List(len);
    keep[0] = 1;
    keep[len - 1] = 1;

    final List<int> stack = [0, len - 1];

    while (stack.isNotEmpty) {
      final end = stack.removeLast();
      final start = stack.removeLast();

      if (end - start < 2) continue;

      double maxDistSq = 0.0;
      int index = start;

      final pStart = points[start];
      final pEnd = points[end];

      for (int i = start + 1; i < end; i++) {
        final double distSq = _perpendicularDistanceSq(points[i], pStart, pEnd);
        if (distSq > maxDistSq) {
          maxDistSq = distSq;
          index = i;
        }
      }

      if (maxDistSq > epsilonSq) {
        keep[index] = 1;

        stack.add(index);
        stack.add(end);

        stack.add(start);
        stack.add(index);
      }
    }

    final List<PointVector> result = [];
    for (int i = 0; i < len; i++) {
      if (keep[i] == 1) result.add(points[i]);
    }

    return result;
  }

  static double _perpendicularDistanceSq(
    PointVector point,
    PointVector lineStart,
    PointVector lineEnd,
  ) {
    final dx = lineEnd.x - lineStart.x;
    final dy = lineEnd.y - lineStart.y;
    final magSq = dx * dx + dy * dy;

    if (magSq == 0.0) {
      return point.distanceSquaredTo(lineStart);
    }

    final u =
        ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / magSq;

    final double closestX, closestY;
    if (u < 0) {
      closestX = lineStart.x;
      closestY = lineStart.y;
    } else if (u > 1) {
      closestX = lineEnd.x;
      closestY = lineEnd.y;
    } else {
      closestX = lineStart.x + u * dx;
      closestY = lineStart.y + u * dy;
    }

    final diffX = point.x - closestX;
    final diffY = point.y - closestY;
    return diffX * diffX + diffY * diffY;
  }

  ui.Vertices? _cachedVertices;
  Path? _cachedPath;
  bool _cachedPathValid = false;

  Int32List? _rawColors;

  double _targetScale = 1.0;

  /// LOD scale used by adaptive spine (export isolates must match).
  double get exportTargetScale => _targetScale;

  void setLodScale(double scale) {
    // Committed ink is GPU-scaled (backup). Updating LOD here rebuilt spines
    // during zoom and dropped 90Hz notes to 60fps.
    if (options.isComplete) return;
    
    // LIVE strokes always use 1.0x tolerance to prevent severe Catmull-Rom 
    // flickering and shape-shifting when drawing at high/low zoom levels.
    _targetScale = 1.0;
  }

  int get _predictionLiveFingerprint {
    // If the stroke is complete, we must use the last valid prediction to ensure
    // the visual fingerprint remains stable until the final geometry is fully cached.
    if (options.isComplete && _predictionTip == null) return 0;
    
    if (!options.isComplete && !stows.strokePrediction.value) return 0;
    final tip = _predictionTip;
    if (tip == null) return 0;
    return Object.hash((tip.dx * 128).round(), (tip.dy * 128).round());
  }

  int get visualFingerprint {
    // Cheap-pen live mesh and path tools both append [_predictionTip].
    final inkUsesPredictionInPath = _allowsStrokeStabilizationAndPrediction;
    return Object.hash(
      geometricFingerprint,
      toolId == ToolId.highlighter ? flatEdge : null,
      neon,
      inkUsesPredictionInPath ? _predictionLiveFingerprint : 0,
    );
  }

  static const highlighterStrokeScaleFactor = 1.0;

  Float32List? _rawPositions;
  Uint16List? _rawIndices;

  int? _cachedVerticesHash;

  static final Map<int, _StrokeMeshData> _globalVertexCache = {};
  static const _kMaxVertexCacheSize =
      8192; // Increased to prevent cache thrashing on dense pages
  static final List<int> _vertexCacheLru = [];

  Float32List getRawPositions() {
    if (_rawPositions == null) vertices;
    return _rawPositions ?? Float32List(0);
  }

  Uint16List getRawIndices() {
    if (_rawIndices == null) vertices;
    return _rawIndices ?? Uint16List(0);
  }

  Int32List getRawColors() {
    if (_rawPositions == null) vertices;
    return _rawColors ?? Int32List(0);
  }

  /// Advanced Pen is path-fill only (local getStroke). Cheap pens use a
  /// spine mesh. Kept so tests can assert the outline-mesh path is off.
  bool get usesSolidOutlineMesh => false;

  /// True when [vertices] / tile merge will not triangulate this stroke.
  bool get hasCachedMesh => _cachedVertices != null;

  /// Spine-mesh pens (ballpoint / fountain / calligraphy) record
  /// `drawVertices` immediately. Advanced Pen is path-only.
  bool get needsTileMeshWarmup => false;

  /// Solid opaque mesh that page/tile batching can `drawVertices`.
  bool get canBatchSolidMesh {
    if (toolId == ToolId.highlighter) return false;
    if (toolId == ToolId.advancedPen) return false;
    if (hasNonSolidPaint) return false;
    if (this is ShapeStroke ||
        this is CircleStroke ||
        this is RectangleStroke) {
      return false;
    }
    if (vertices == null) return false;
    return getRawPositions().isNotEmpty && getRawIndices().isNotEmpty;
  }

  bool get usesVectorFillPicture =>
      hasNonSolidPaint &&
      toolId != ToolId.advancedPencil &&
      !paint.usesPencilNoise;

  ui.Picture? _vectorFillPicture;
  int? _vectorFillPictureHash;
  ui.Picture? _solidPathPicture;
  int? _solidPathPictureHash;

  void _invalidateVectorFillPicture() {
    _vectorFillPicture?.dispose();
    _vectorFillPicture = null;
    _vectorFillPictureHash = null;
    _solidPathPicture?.dispose();
    _solidPathPicture = null;
    _solidPathPictureHash = null;
  }

  /// Records a solid `drawPath` once when the outline mesh is unavailable
  /// (failed ear-clip, or translucent ink that cannot use `drawVertices`).
  ui.Picture? ensureSolidPathPicture({
    required bool invert,
    required Color color,
  }) {
    if (toolId != ToolId.advancedPen || !paint.isSolid || neon) return null;
    final hash = Object.hash(visualFingerprint, invert, color.toARGB32());
    if (_solidPathPicture != null && _solidPathPictureHash == hash) {
      return _solidPathPicture;
    }
    final path = highQualityPath;
    final bounds = path.getBounds();
    if (bounds.isEmpty) return null;
    _solidPathPicture?.dispose();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, bounds.inflate(4));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..isAntiAlias = true
        ..color = color,
    );
    _solidPathPicture = recorder.endRecording();
    _solidPathPictureHash = hash;
    return _solidPathPicture;
  }

  /// Records the textured/gradient fill once (vector path+shader, not a raster).
  ui.Picture? ensureVectorFillPicture({
    required bool invert,
    required Color fallbackColor,
    required double currentScale,
  }) {
    if (!usesVectorFillPicture) return null;
    final qualityBucket = currentScale < 0.7 ? 0 : 1;
    final hash = Object.hash(
      visualFingerprint,
      invert,
      fallbackColor.toARGB32(),
      paint.cacheKey,
      qualityBucket,
    );
    if (_vectorFillPicture != null && _vectorFillPictureHash == hash) {
      return _vectorFillPicture;
    }
    final path = highQualityPath;
    final bounds = path.getBounds();
    if (bounds.isEmpty) return null;
    ui.Image? texture;
    if (paint.usesTexture) {
      texture = StrokePaintImageCache.instance.ensure(paint);
      if (texture == null) return null;
    }
    _invalidateVectorFillPicture();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, bounds.inflate(4));
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..filterQuality = qualityBucket == 0
          ? FilterQuality.low
          : FilterQuality.medium
      ..color = fallbackColor;
    paint.applyTo(fill, bounds, texture: texture, useShaderCache: true);
    canvas.drawPath(path, fill);
    _vectorFillPicture = recorder.endRecording();
    _vectorFillPictureHash = hash;
    return _vectorFillPicture;
  }

  List<PointVector> _prepareAdvancedSpine(
    List<PointVector> basePoints, {
    bool stabilizeStart = true,
    bool stabilizeEnd = true,
    bool flattenEnds = true,
  }) {
    if (basePoints.isEmpty) return basePoints;
    var advanced = streamlinePoints(
      basePoints,
      streamline: options.isComplete
          ? options.streamline
          : options.streamline * 0.28,
    );
    advanced = decimateStrokeSpine(
      advanced,
      minDistance: math.max(0.55, options.size * 0.22),
    );
    if (advanced.length >= 3) {
      final packed = Float32List(advanced.length * 3);
      for (var i = 0; i < advanced.length; i++) {
        packed[i * 3] = advanced[i].x;
        packed[i * 3 + 1] = advanced[i].y;
        packed[i * 3 + 2] = advanced[i].pressure ?? 0.5;
      }
      final scale = _targetScale.clamp(0.1, 5.0);
      final tolMul = math.max(0.15, options.smoothing * 2.5);
      final toleranceSq = (0.12 * tolMul / scale) * (0.12 * tolMul / scale);
      // Mid-stroke pencil chunks keep open joins: flattening only the true
      // stroke ends avoids pinching the ribbon where chunks meet.
      final smooth = _getAdaptiveSpineFast(
        packed,
        toleranceSq,
        flattenTipSegments: flattenEnds,
        flattenEndSegments: !flattenEnds
            ? 1
            : (options.isComplete ? 2 : 5),
        segStepPx: options.isComplete ? 2.5 : 4.8,
      );
      final n = smooth.length ~/ 3;
      advanced = List.generate(
        n,
        (i) => PointVector(smooth[i * 3], smooth[i * 3 + 1], smooth[i * 3 + 2]),
      );
    }
    if (options.simulatePressure && !pressureEnabled) {
      advanced = bakeSimulatedPressure(
        advanced,
        sensitivity: options.pressureSensitivity,
        stabilizeStart: stabilizeStart,
        stabilizeEnd: stabilizeEnd,
      );
    } else {
      advanced = stabilizeAdvancedTipPressures(
        advanced,
        stabilizeStart: stabilizeStart,
        stabilizeEnd: stabilizeEnd,
      );
    }
    return advanced;
  }

  List<Offset> _advancedOutlineFromSpine(
    List<PointVector> spine, {
    bool includeStart = true,
    bool includeEnd = true,
  }) {
    var strokePoints = spine;
    if (strokePoints.length == 1) {
      strokePoints = [strokePoints.first, strokePoints.first];
    }
    final outlineOptions =
        toolId == ToolId.advancedPencil && paint.pressureMapsToCoverage
        ? options.copyWith(thinning: 0)
        : options;
    final isAdvanced = toolId == ToolId.advancedPen;
    // Advanced Pen fills a closed getStroke outline (path), not a spine mesh.
    // Round caps use circular semicircle arcs (_capArc) centered on the tip —
    // not mesh-style hemisphere strips. Those strips read as a sideways
    // "tic tac" during live drawing because _alignTipEdgeToChord shears the
    // last spine edge while the bulb stays full-radius along travel.
    // Start/end travel follow the first/last authored segment so each circle
    // sits on the tip (not a long opening/closing chord that leans the
    // diameter off-axis relative to the adjacent stem).
    // U-turn joins stay Advanced-only via [dualSidedReturnJoins].
    (double, double)? startTravel;
    if (isAdvanced &&
        includeStart &&
        outlineOptions.start.cap &&
        strokePoints.length >= 2) {
      final a = strokePoints.first;
      final b = strokePoints[1];
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len > 1e-6) startTravel = (dx / len, dy / len);
    }
    (double, double)? endTravel;
    if (isAdvanced &&
        includeEnd &&
        outlineOptions.end.cap &&
        strokePoints.length >= 2) {
      final a = strokePoints[strokePoints.length - 2];
      final b = strokePoints.last;
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len > 1e-6) endTravel = (dx / len, dy / len);
    }
    
    try {
      return getStroke(
        strokePoints,
        options: _outlineOptionsForCurrentPhase(outlineOptions),
        startCap: includeStart && outlineOptions.start.cap,
        endCap: includeEnd && outlineOptions.end.cap,
        applyStartTaper: includeStart,
        applyEndTaper: includeEnd,
        capChordOnlyAtCappedEnds: isAdvanced,
        dualSidedReturnJoins: isAdvanced,
        preferStemCapTangents: false,
        meshStyleCaps: false,
        startTravelTangent: startTravel,
        endTravelTangent: endTravel,
      );
    } catch (e, st) {
      log.warning('getStroke crashed in _advancedOutlineFromSpine: $e', e, st);
      return strokePoints.map((p) => Offset(p.x, p.y)).toList();
    }
  }

  void _clearLiveCheapSpineFreeze() {
    _liveCheapFrozenPositions = null;
    _liveCheapFrozenSpineCount = 0;
    _liveCheapFrozenSmoothPrefix = null;
  }

  static bool _cheapSmoothPrefixMatches(
    Float32List prefix,
    Float32List smooth,
    int count,
  ) {
    final n = count * 3;
    if (prefix.length < n || smooth.length < n) return false;
    for (var i = 0; i < n; i += 3) {
      if ((prefix[i] - smooth[i]).abs() > 0.4) return false;
      if ((prefix[i + 1] - smooth[i + 1]).abs() > 0.4) return false;
    }
    return true;
  }

  /// Live getStroke / perfect-freehand should track the stylus, not settle
  /// into the committed outline. Committed geometry keeps full smoothing.
  StrokeOptions _outlineOptionsForCurrentPhase(StrokeOptions base) {
    var opts = base;
    if (!options.isComplete) {
      opts = opts.copyWith(
        smoothing: base.smoothing * 0.42,
        streamline: base.streamline * 0.28,
      );
    }
    
    // Safeguard: Impede crashes do double.clamp no buildVariableWidthOutline
    if (opts.minSizeRatio > opts.maxSizeRatio) {
      opts = opts.copyWith(
        minSizeRatio: opts.maxSizeRatio,
        maxSizeRatio: opts.minSizeRatio,
      );
    }
    if (opts.size < 0) {
      opts = opts.copyWith(size: opts.size.abs());
    }
    return opts;
  }

  bool get _usesLiveCheapSpineMesh =>
      !options.isComplete &&
      (toolId == ToolId.ballpointPen ||
          toolId == ToolId.fountainPen ||
          toolId == ToolId.calligraphyPen);

  List<ui.Vertices>? get liveIncrementalMeshes => null;

  Path? get liveTipPathFallback => null;

  /// Commit live geometry on pen-up. Cheap pens keep the last live mesh
  /// until [visualFingerprint] changes (prediction is cleared here so the
  /// committed rebuild drops the lookahead tail).
  void finishLiveGeometry() {
    options.isComplete = true;
    // Do NOT clear prediction here for tools that use path-based rendering (Ballpoint).
    // Clearing it before the final path is cached causes a one-frame flickering cap.
    if (_usesLivePencilChunks) {
      clearLivePrediction();
    }
    if (_usesLivePencilChunks && points.length >= 2) {
      // One continuous prepare on pen-up so mid-stroke open joins / freeze
      // seams cannot leave permanent gaps in the committed ribbon.
      _committedPencilChunks = _buildPencilChunks(
        points,
        isStrokeStart: true,
        isStrokeEnd: true,
      );
      if (_committedPencilChunks!.isNotEmpty) {
        _liveFrozenPencilChunks.clear();
        _pencilLockedPointCount = 0;
        _livePencilTip = null;
        _livePencilTipChunks = null;
        _livePencilTipHash = 0;
        return;
      }
    }
    markPolygonNeedsUpdating();
  }

  /// Solid mesh chunks for tile batching (spine-mesh pens only).
  Iterable<(Float32List, Uint16List)> get solidMeshChunks {
    if (canBatchSolidMesh) {
      return [(getRawPositions(), getRawIndices())];
    }
    return const [];
  }

  List<ui.Vertices> get drawableSolidMeshes => const [];

  ui.Vertices? get vertices {
    if (points.length < 2) return null;

    // Path-filled tools. Neon ballpoint still builds a mesh via
    // [ensureMeshVertices] for the core.
    if ((neon && toolId == ToolId.ballpointPen) ||
        toolId == ToolId.advancedPen ||
        toolId == ToolId.advancedPencil ||
        toolId == ToolId.highlighter ||
        toolId == ToolId.laserPointer) {
      return null;
    }
    return _ensureVertices();
  }

  /// Mesh for neon ballpoint core (bypasses [vertices] nulling neon).
  ui.Vertices? ensureMeshVertices() {
    if (points.length < 2) return null;
    return _ensureVertices();
  }

  ui.Vertices? _ensureVertices() {
    final int currentHash = visualFingerprint;
    if (_cachedVertices != null && _cachedVerticesHash == currentHash) {
      return _cachedVertices;
    }
    if (options.isComplete) {
      final _StrokeMeshData? cached = _globalVertexCache[currentHash];
      if (cached != null) {
        _cachedVertices = cached.vertices;
        _cachedVerticesHash = currentHash;
        _rawPositions = cached.positions;
        _rawIndices = cached.indices;
        _rawColors = cached.colors;
        _bumpVertexCacheLru(currentHash);
        return _cachedVertices;
      }
    }

    final _StrokeMeshData? meshData = _generateSpineMeshLOD();

    if (meshData == null) return null;
    _cachedVertices = meshData.vertices;
    _cachedVerticesHash = currentHash;
    _rawPositions = meshData.positions;
    _rawIndices = meshData.indices;
    _rawColors = meshData.colors;
    if (!options.isComplete) {
      return _cachedVertices;
    }
    while (_globalVertexCache.length >= _kMaxVertexCacheSize &&
        _vertexCacheLru.isNotEmpty) {
      final evictKey = _vertexCacheLru.removeAt(0);
      _globalVertexCache.remove(evictKey);
      // Do not dispose: other strokes may still reference this mesh.
    }
    _globalVertexCache[currentHash] = meshData;
    _vertexCacheLru.add(currentHash);
    return _cachedVertices;
  }

  static void _bumpVertexCacheLru(int key) {
    _vertexCacheLru.remove(key);
    _vertexCacheLru.add(key);
  }

  void dispose() {
    _cachedVertices = null;
    _cachedVerticesHash = null;
    _rawPositions = null;
    _rawIndices = null;
    _rawColors = null;
    _cachedPath = null;
    _cachedPathValid = false;
    _invalidatePencilPlan();
    _invalidateVectorFillPicture();
    _clearLiveCheapSpineFreeze();
  }

  static const _capSegments = 10;

  /// Chord direction from spine start across only the first few edges — avoids
  /// far-down-the-spine chords that swing as more ink is added.
  /// Ballpoint mesh caps use this. Advanced Pen outline caps pass the first
  /// authored segment via [startTravelTangent] instead (mirrors end).
  static (double, double) _localOpeningChordTangent(
    Float32List pts,
    int count,
    double baseSize,
  ) {
    if (count < 2) return (1.0, 0.0);
    final ax = pts[0], ay = pts[1];
    if (count == 2) {
      final tx = pts[3] - ax, ty = pts[4] - ay;
      final len = math.sqrt(tx * tx + ty * ty);
      return len > 1e-6 ? (tx / len, ty / len) : (1.0, 0.0);
    }
    const maxEdges = 8;
    final maxArc = math.min(math.max(baseSize * 2.25, 5.5), 16.5);
    var j = 0;
    double acc = 0;
    for (var e = 0; e < maxEdges && j + 1 < count; e++) {
      final o0 = j * 3;
      final o1 = (j + 1) * 3;
      final sx = pts[o1] - pts[o0];
      final sy = pts[o1 + 1] - pts[o0 + 1];
      acc += math.sqrt(sx * sx + sy * sy);
      j++;
      if (acc >= maxArc) break;
    }
    if (j < 1) j = 1;
    if (j >= count) j = count - 1;
    final oj = j * 3;
    var tx = pts[oj] - ax;
    var ty = pts[oj + 1] - ay;
    var len = math.sqrt(tx * tx + ty * ty);
    if (len > 1e-6) return (tx / len, ty / len);
    for (var k = 1; k < count; k++) {
      final ok = k * 3;
      tx = pts[ok] - ax;
      ty = pts[ok + 1] - ay;
      final l2 = tx * tx + ty * ty;
      if (l2 > 1e-8) {
        len = math.sqrt(l2);
        return (tx / len, ty / len);
      }
    }
    return (1.0, 0.0);
  }

  /// Chord from a short trailing run ending at the tip ([_localOpeningChordTangent]
  /// mirrored). Tall arc lookahead at the end lets later curvature shear the tip
  /// normal relative to the last ribbon slice and reads as one flat hemisphere face.
  static (double, double) _localClosingChordTangent(
    Float32List pts,
    int count,
    double baseSize,
  ) {
    if (count < 2) return (1.0, 0.0);
    final lastI = count - 1;
    final lx = pts[lastI * 3], ly = pts[lastI * 3 + 1];
    if (count == 2) {
      final tx = lx - pts[0], ty = ly - pts[1];
      final len = math.sqrt(tx * tx + ty * ty);
      return len > 1e-6 ? (tx / len, ty / len) : (1.0, 0.0);
    }
    const maxEdges = 8;
    final maxArc = math.min(math.max(baseSize * 2.25, 5.5), 16.5);
    var anchor = lastI;
    double acc = 0;
    for (var e = 0; e < maxEdges && anchor > 0; e++) {
      final o0 = (anchor - 1) * 3;
      final o1 = anchor * 3;
      final sx = pts[o1] - pts[o0];
      final sy = pts[o1 + 1] - pts[o0 + 1];
      acc += math.sqrt(sx * sx + sy * sy);
      anchor--;
      if (acc >= maxArc) break;
    }
    if (anchor >= lastI) anchor = math.max(0, lastI - 1);
    final oa = anchor * 3;
    var tx = lx - pts[oa];
    var ty = ly - pts[oa + 1];
    var len = math.sqrt(tx * tx + ty * ty);
    if (len > 1e-6) return (tx / len, ty / len);
    for (var k = lastI - 1; k >= 0; k--) {
      final ok = k * 3;
      tx = lx - pts[ok];
      ty = ly - pts[ok + 1];
      final l2 = tx * tx + ty * ty;
      if (l2 > 1e-8) {
        len = math.sqrt(l2);
        return (tx / len, ty / len);
      }
    }
    return (1.0, 0.0);
  }

  /// Pulls endpoint pressure toward a short interior average so caps / tapered
  /// tips don't balloon or pinch when pressure spikes at lift-off.
  /// [FountainPen] uses a slightly stronger pull — small lift-off wiggles read
  /// as cap artifacts with the chisel taper alone.
  static void _stabilizeMeshEndpointPressures(
    Float32List p,
    int count,
    ToolId toolId,
  ) {
    if (count < 3) return;
    const w = 4;
    final startRawW = toolId == ToolId.fountainPen ? 0.28 : 0.4;
    final endRawW = toolId == ToolId.fountainPen ? 0.28 : 0.4;
    var n0 = 0;
    var s0 = 0.0;
    for (var i = 1; i < count && i <= w; i++) {
      s0 += p[i];
      n0++;
    }
    var n1 = 0;
    var s1 = 0.0;
    for (var i = count - 2; i >= 0 && n1 < w; i--) {
      s1 += p[i];
      n1++;
    }
    if (n0 > 0) {
      final ref = s0 / n0;
      p[0] = (p[0] * startRawW + ref * (1 - startRawW)).clamp(0.05, 1.0);
    }
    if (n1 > 0) {
      final ref = s1 / n1;
      p[count - 1] = (p[count - 1] * endRawW + ref * (1 - endRawW)).clamp(
        0.05,
        1.0,
      );
    }
  }

  _StrokeMeshData? _generateSpineMeshLOD() {
    if (points.length < 2) return null;
    _ensurePackedPoints();
    if (_packedPoints == null || _packedPoints!.length < 6) return null;

    final double scale = _targetScale;
    // Mild overview LOD for hemisphere tessellation only — writing zoom unchanged.
    final int targetCapSegments = scale < 0.35
        ? math.max(4, (_capSegments * 0.6).round())
        : _capSegments;

    double toleranceMultiplier = 1.0;
    if (toolId == ToolId.experimentalPen) {
      toleranceMultiplier = math.max(0.1, options.smoothing * 3.0);
    }

    // Same spine simplification live and committed — divergent tolerances popped
    // the mesh (especially caps / tips) between preview and finalized ink.
    // Optimize tolerance during live drawing to reduce mesh complexity
    final double effectiveTolerance = toleranceMultiplier;
    final double splineErrorSq =
        (0.22 * effectiveTolerance / scale) *
        (0.22 * effectiveTolerance / scale);

    // Packed samples stay prediction-free so commit can rebuild without a
    // phantom tail. Live cheap-pen mesh appends the tip so the cap tracks
    // the stylus (path tools already did this in getPolygon).
    Float32List packed = _packedPoints!;
    if (_usesLiveCheapSpineMesh && _predictionTip != null) {
      final src = _packedPoints!;
      packed = Float32List(src.length + 3);
      packed.setAll(0, src);
      packed[src.length] = _predictionTip!.dx;
      packed[src.length + 1] = _predictionTip!.dy;
      packed[src.length + 2] = _predictionPressure ?? 0.5;
    }

    Float32List rawSmooth = _getAdaptiveSpineFast(
      packed,
      splineErrorSq,
      flattenTipSegments: true,
      flattenEndSegments: 2,
      segStepPx: 3.4,
    );
    final int rawCount = rawSmooth.length ~/ 3;
    if (rawCount < 2) return null;

    final _Float32Builder dedupe = _Float32Builder(estimatedSize: rawCount * 3);
    double lastX = rawSmooth[0], lastY = rawSmooth[1];
    dedupe.add(lastX, lastY, rawSmooth[2]);
    for (int i = 1; i < rawCount; i++) {
      final int o = i * 3;
      final double x = rawSmooth[o],
          y = rawSmooth[o + 1],
          p = rawSmooth[o + 2];
      final double dx = x - lastX, dy = y - lastY;
      if ((dx * dx + dy * dy) > 0.0001) {
        dedupe.add(x, y, p);
        lastX = x;
        lastY = y;
      }
    }
    Float32List smoothPoints = dedupe.finish();
    int count = smoothPoints.length ~/ 3;

    if (count == 1) {
      final _Float32Builder two = _Float32Builder(estimatedSize: 6);
      two.add(smoothPoints[0], smoothPoints[1], smoothPoints[2]);
      two.add(smoothPoints[0] + 0.1, smoothPoints[1], smoothPoints[2]);
      smoothPoints = two.finish();
      count = 2;
    }
    if (count < 2) return null;

    var startSpine = 0;
    var reuseStartCap = false;
    if (_usesLiveCheapSpineMesh) {
      final frozen = _liveCheapFrozenSpineCount;
      final frozenPos = _liveCheapFrozenPositions;
      final prefix = _liveCheapFrozenSmoothPrefix;
      if (frozen > 2 &&
          frozenPos != null &&
          prefix != null &&
          count > frozen + 2 &&
          _cheapSmoothPrefixMatches(prefix, smoothPoints, frozen)) {
        startSpine = frozen;
        reuseStartCap = true;
      } else {
        _clearLiveCheapSpineFreeze();
      }
    }

    final bool isHighlighter = toolId == ToolId.highlighter;
    final bool isBallpoint = toolId == ToolId.ballpointPen;
    final bool isCalligraphy = toolId == ToolId.calligraphyPen;

    final double baseSize = isHighlighter
        ? (options.size / 2.0) * highlighterStrokeScaleFactor
        : options.size / 2.0;
    final bool canTaper = !isCalligraphy;
    final double calliCos = isCalligraphy ? math.cos(-40 * math.pi / 180) : 1.0;
    final double calliSin = isCalligraphy ? math.sin(-40 * math.pi / 180) : 0.0;
    final bool highlighterWantsCaps = isHighlighter && !flatEdge;

    /// Round mesh caps: ballpoint always; advanced/experimental when [cap] is on
    /// (even with taper — round bulb instead of jittery chisel tips).
    final bool roundCapOverridesTaper =
        toolId == ToolId.advancedPen ||
        toolId == ToolId.advancedPencil ||
        toolId == ToolId.experimentalPen;

    var generateStartCap =
        targetCapSegments > 0 &&
        (isHighlighter
            ? highlighterWantsCaps
            : (isCalligraphy ? false : (options.start.cap || isBallpoint))) &&
        (!options.start.taperEnabled || !canTaper || roundCapOverridesTaper);
    final bool generateEndCap =
        targetCapSegments > 0 &&
        (isHighlighter
            ? highlighterWantsCaps
            : (isCalligraphy ? false : (options.end.cap || isBallpoint))) &&
        (!options.end.taperEnabled || !canTaper || roundCapOverridesTaper);
    if (reuseStartCap) generateStartCap = false;

    // Spine points can emit >1 quad pair when miter subdivisions activate.
    final int maxPairs =
        count * (targetCapSegments + _capSegments + 8) +
        targetCapSegments * 8 +
        48;
    final Float32List positions = Float32List(maxPairs * 4);
    final Uint16List indices = Uint16List(maxPairs * 6);

    int vIndex = 0, iIndex = 0, pairCount = 0;
    final frozenPos = _liveCheapFrozenPositions;
    if (reuseStartCap && frozenPos != null) {
      positions.setRange(0, frozenPos.length, frozenPos);
      vIndex = frozenPos.length;
      pairCount = vIndex >> 2;
    }

    void addVertexPair(double px, double py, double nx, double ny, double w) {
      double vx = nx, vy = ny;
      if (isCalligraphy) {
        double rxNorm = 1.3;
        double ryNorm = 0.24;
        double len = math.sqrt(nx * nx + ny * ny);
        if (len > 0.0001) {
          double dirX = nx / len, dirY = ny / len;
          double localNx = dirX * calliCos + dirY * calliSin;
          double localNy = -dirX * calliSin + dirY * calliCos;
          double scl =
              1.0 /
              math.sqrt(
                rxNorm * rxNorm * localNx * localNx +
                    ryNorm * ryNorm * localNy * localNy,
              );
          double localVx = rxNorm * rxNorm * localNx * scl;
          double localVy = ryNorm * ryNorm * localNy * scl;
          vx = (localVx * calliCos - localVy * calliSin);
          vy = (localVx * calliSin + localVy * calliCos);
        }
      }

      positions[vIndex++] = px + vx * w;
      positions[vIndex++] = py + vy * w;
      positions[vIndex++] = px - vx * w;
      positions[vIndex++] = py - vy * w;
      pairCount++;
    }

    final bool usePressure =
        (options.simulatePressure || pressureEnabled) &&
        toolId != ToolId.ballpointPen &&
        toolId != ToolId.highlighter;

    final Float32List smoothedPressures = Float32List(count);
    if (usePressure && count > 0) {
      if (toolId == ToolId.advancedPen || toolId == ToolId.advancedPencil) {
        for (int i = 0; i < count; i++)
          smoothedPressures[i] = smoothPoints[i * 3 + 2];
      } else {
        double p = smoothPoints[2];
        for (int i = 0; i < count; i++) {
          p = p * 0.75 + smoothPoints[i * 3 + 2] * 0.25;
          smoothedPressures[i] = p;
        }
        p = smoothedPressures[count - 1];
        for (int i = count - 1; i >= 0; i--) {
          p = p * 0.75 + smoothedPressures[i] * 0.25;
          smoothedPressures[i] = p;
        }
      }
      if (usePressure) {
        _stabilizeMeshEndpointPressures(smoothedPressures, count, toolId);
      }
    }

    // Stable tip tangents for every mesh pen (including fountain) — same idea
    // as the older backup: orient caps/tips from local edges, not raw jitter.
    final computedStart = _localOpeningChordTangent(
      smoothPoints,
      count,
      baseSize,
    );
    final double startTx = computedStart.$1;
    final double startTy = computedStart.$2;
    final computedEnd = _localClosingChordTangent(
      smoothPoints,
      count,
      baseSize,
    );
    final double endTx = computedEnd.$1;
    final double endTy = computedEnd.$2;

    if (generateStartCap) {
      final double p0x = smoothPoints[0], p0y = smoothPoints[1];
      final double p0p = usePressure ? smoothedPressures[0] : 0.5;
      // Same hemisphere as the end tip: sample along outward = -travel, then
      // emit tip→stem so the mesh strip opens at the bulb.
      final double outwardDx = -startTx;
      final double outwardDy = -startTy;
      final nx = -startTy, ny = startTx;

      // Taper+cap couldn't both be true historically; Advanced/Experimental
      // allow both — do not multiply pressure away or the hemisphere is ~minimal
      // while the stem stays thick (strip blows up / gaps / pinhole lifts).
      double hemisP0 = usePressure ? p0p : 0.5;
      if (roundCapOverridesTaper && usePressure && count >= 4) {
        double sum = 0;
        var n = 0;
        for (var k = 1; k <= math.min(count - 1, 6); k++) {
          sum += smoothedPressures[k];
          n++;
        }
        if (n > 0) {
          hemisP0 = math.max(hemisP0, (sum / n) * 0.93);
        }
      }

      final double width = (isBallpoint || isHighlighter || isCalligraphy)
          ? baseSize
          : math.max(0.1, baseSize * (0.2 + 0.8 * hemisP0 * 2));

      // Angle must stay in [0, π/2]: use phase = i/steps where i≤steps only.
      // Ballpoint doubles `steps`; using i/targetCapSegments made angle reach π so
      // cos(angle) flipped the rim and chipped the circular cap visually.
      final int steps = isBallpoint ? targetCapSegments * 2 : targetCapSegments;
      for (int i = steps; i > 0; i--) {
        final double angle = (math.pi / 2) * (i / steps);
        addVertexPair(
          p0x + outwardDx * (math.sin(angle) * width),
          p0y + outwardDy * (math.sin(angle) * width),
          nx,
          ny,
          math.cos(angle) * width,
        );
      }
    }

    var taperLenStartMesh = 6;
    var taperLenEndMesh = 6;
    if (toolId == ToolId.fountainPen) {
      taperLenStartMesh = (options.start.customTaper ?? 12).round().clamp(
        4,
        64,
      );
      taperLenEndMesh = (options.end.customTaper ?? 12).round().clamp(4, 64);
    } else if (toolId == ToolId.advancedPen ||
        toolId == ToolId.advancedPencil ||
        toolId == ToolId.experimentalPen) {
      taperLenStartMesh = (options.start.customTaper ?? 10).round().clamp(
        4,
        64,
      );
      taperLenEndMesh = (options.end.customTaper ?? 10).round().clamp(4, 64);
    }

    final spinePairStart = Int32List(count);
    for (int i = startSpine; i < count; i++) {
      spinePairStart[i] = pairCount;
      final int o = i * 3;
      final double px = smoothPoints[o], py = smoothPoints[o + 1];
      final double pp = usePressure ? smoothedPressures[i] : 0.5;

      double bdx = 0, bdy = 0;
      if (i > 0) {
        bdx = px - smoothPoints[o - 3];
        bdy = py - smoothPoints[o - 2];
      }
      double fdx = 0, fdy = 0;
      if (i < count - 1) {
        fdx = smoothPoints[o + 3] - px;
        fdy = smoothPoints[o + 4] - py;
      }

      if (i == 0) {
        final segLen = math.sqrt(fdx * fdx + fdy * fdy);
        if (segLen > 1e-6) {
          bdx = startTx * segLen;
          bdy = startTy * segLen;
          fdx = bdx;
          fdy = bdy;
        } else {
          bdx = fdx;
          bdy = fdy;
        }
      } else if (i == count - 1) {
        final segLen = math.sqrt(bdx * bdx + bdy * bdy);
        if (segLen > 1e-6) {
          fdx = endTx * segLen;
          fdy = endTy * segLen;
          bdx = fdx;
          bdy = fdy;
        } else {
          fdx = bdx;
          fdy = bdy;
        }
      }

      double lenB = math.sqrt(bdx * bdx + bdy * bdy),
          lenF = math.sqrt(fdx * fdx + fdy * fdy);
      double nBx = 0, nBy = 0;
      if (lenB > 0.0001) {
        nBx = -bdy / lenB;
        nBy = bdx / lenB;
      }
      double nFx = 0, nFy = 0;
      if (lenF > 0.0001) {
        nFx = -fdy / lenF;
        nFy = fdx / lenF;
      }

      if (lenB <= 0.0001 && lenF > 0.0001) {
        nBx = nFx;
        nBy = nFy;
        lenB = lenF;
        bdx = fdx;
        bdy = fdy;
      }
      if (lenF <= 0.0001 && lenB > 0.0001) {
        nFx = nBx;
        nFy = nBy;
        lenF = lenB;
        fdx = bdx;
        fdy = bdy;
      }

      final dx = fdx * 0.5 + bdx * 0.5, dy = fdy * 0.5 + bdy * 0.5;
      final lenM = math.sqrt(dx * dx + dy * dy);
      double nx = 0, ny = 0;
      if (lenM > 0.0001) {
        nx = -dy / lenM;
        ny = dx / lenM;
      } else {
        nx = nBx;
        ny = nBy;
      }

      double pressure = usePressure ? pp : 0.5;
      if (canTaper) {
        if (options.start.taperEnabled &&
            i < taperLenStartMesh &&
            !generateStartCap) {
          final double t = i / taperLenStartMesh;
          pressure *= (t * (2 - t));
        } else if (options.end.taperEnabled &&
            i > count - (taperLenEndMesh + 1) &&
            !generateEndCap) {
          final double t = (count - 1 - i) / taperLenEndMesh;
          pressure *= (t * (2 - t));
        }
      }
      final double width = (isBallpoint || isHighlighter || isCalligraphy)
          ? baseSize
          : math.max(0.1, baseSize * (0.2 + 0.8 * pressure * 2));

      final double dotMiter = (lenB > 0.0001 && lenF > 0.0001)
          ? (bdx * fdx + bdy * fdy) / (lenB * lenF)
          : 1.0;

      if (dotMiter < 0.5 &&
          targetCapSegments > 0 &&
          lenB > 0.01 &&
          lenF > 0.01) {
        int segments = (targetCapSegments * (1.0 - dotMiter)).ceil().clamp(
          1,
          _capSegments,
        );
        double angleB = math.atan2(nBy, nBx);
        double angleF = math.atan2(nFy, nFx);
        double diff = angleF - angleB;
        while (diff > math.pi) diff -= 2 * math.pi;
        while (diff < -math.pi) diff += 2 * math.pi;

        for (int step = 0; step <= segments; step++) {
          double t = step / segments;
          double a = angleB + diff * t;
          addVertexPair(px, py, math.cos(a), math.sin(a), width);
        }
      } else {
        double miterLength =
            1.0 / math.sqrt(math.max(0.01, (1.0 + dotMiter) / 2.0));
        miterLength = miterLength.clamp(1.0, 2.5);
        addVertexPair(px, py, nx * miterLength, ny * miterLength, width);
      }
    }

    if (_usesLiveCheapSpineMesh && count > 24) {
      // Freeze earlier at ~60 Hz so tip remesh stays inside one vsync budget.
      // Lowering 'tipKeep' on battery saver cuts down the vertices calculated per frame, saving CPU.
      final tipKeep = DisplayInkFeel.instance.isLowRefresh ? 6 : 16;
      final lockAt = count - tipKeep;
      if (lockAt > _liveCheapFrozenSpineCount &&
          lockAt > startSpine &&
          lockAt < count) {
        final pairAt = spinePairStart[lockAt];
        if (pairAt > 0 && pairAt * 4 <= vIndex) {
          _liveCheapFrozenPositions = Float32List.fromList(
            positions.sublist(0, pairAt * 4),
          );
          _liveCheapFrozenSpineCount = lockAt;
          final prefix = Float32List(lockAt * 3);
          prefix.setRange(0, prefix.length, smoothPoints);
          _liveCheapFrozenSmoothPrefix = prefix;
        }
      }
    }

    if (generateEndCap) {
      final int lastO = (count - 1) * 3;
      final double pLx = smoothPoints[lastO], pLy = smoothPoints[lastO + 1];
      final double pLp = usePressure ? smoothedPressures[count - 1] : 0.5;
      final double endDx = endTx;
      final double endDy = endTy;
      final nx = -endDy, ny = endDx;

      double hemisP = usePressure ? pLp : 0.5;
      if (roundCapOverridesTaper && usePressure && count >= 4) {
        double sum = 0;
        var n = 0;
        for (var k = math.max(0, count - 6); k <= count - 2; k++) {
          sum += smoothedPressures[k];
          n++;
        }
        if (n > 0) {
          hemisP = math.max(hemisP, (sum / n) * 0.93);
        }
      }

      final double width = (isBallpoint || isHighlighter || isCalligraphy)
          ? baseSize
          : math.max(0.1, baseSize * (0.2 + 0.8 * hemisP * 2));

      final int steps = isBallpoint ? targetCapSegments * 2 : targetCapSegments;
      for (int i = 1; i <= steps; i++) {
        final double angle = (math.pi / 2) * (i / steps);
        addVertexPair(
          pLx + endDx * (math.sin(angle) * width),
          pLy + endDy * (math.sin(angle) * width),
          nx,
          ny,
          math.cos(angle) * width,
        );
      }
    }

    for (int q = 0; q < pairCount - 1; q++) {
      int A = q * 2, B = (q + 1) * 2;
      indices[iIndex++] = A + 0;
      indices[iIndex++] = A + 1;
      indices[iIndex++] = B + 0;
      indices[iIndex++] = A + 1;
      indices[iIndex++] = B + 1;
      indices[iIndex++] = B + 0;
    }

    final Float32List finalPositions = Float32List.sublistView(
      positions,
      0,
      vIndex,
    );
    final Uint16List finalIndices = Uint16List.sublistView(indices, 0, iIndex);

    final ui.Vertices verts = ui.Vertices.raw(
      ui.VertexMode.triangles,
      finalPositions,
      indices: finalIndices,
    );
    return _StrokeMeshData(verts, finalPositions, finalIndices);
  }

  static Float32List _getAdaptiveSpineFast(
    Float32List input,
    double toleranceSq, {
    bool flattenTipSegments = false,
    int flattenEndSegments = 2,
    double segStepPx = 2.5,
  }) {
    final int n = input.length ~/ 3;
    if (n < 3) return input;
    final _Float32Builder out = _Float32Builder(estimatedSize: n * 8);
    out.add(input[0], input[1], input[2]);
    final double stepPx = segStepPx.clamp(1.2, 8.0);
    final int endFlatten = flattenEndSegments.clamp(1, 8);

    for (int i = 0; i < n - 1; i++) {
      final int i0 = math.max(0, i - 1) * 3;
      final int i1 = i * 3;
      final int i2 = (i + 1) * 3;
      final int i3 = math.min(n - 1, i + 2) * 3;

      final double p0x = input[i0], p0y = input[i0 + 1];
      final double p1x = input[i1], p1y = input[i1 + 1], p1p = input[i1 + 2];
      final double p2x = input[i2], p2y = input[i2 + 1], p2p = input[i2 + 2];
      final double p3x = input[i3], p3y = input[i3 + 1];

      // Calculate the actual distance of this line segment
      final double dx = p2x - p1x;
      final double dy = p2y - p1y;
      final double segDist = math.sqrt(dx * dx + dy * dy);

      // Keep the first/last authored edges linear so round caps sit on the
      // stem. Catmull on those edges pulls the hemisphere toward later chords.
      final flattenThis =
          flattenTipSegments && (i == 0 || i >= n - 1 - endFlatten);

      // Dynamically add a spline point every ~stepPx to guarantee smoothness
      final int steps = flattenThis
          ? 1
          : (segDist / stepPx).ceil().clamp(1, 64);

      if (steps > 1) {
        for (int j = 1; j < steps; j++) {
          _addSplinePointFast(
            out,
            p0x,
            p0y,
            p1x,
            p1y,
            p1p,
            p2x,
            p2y,
            p2p,
            p3x,
            p3y,
            j / steps,
          );
        }
      }
      out.add(p2x, p2y, p2p);
    }
    return out.finish();
  }

  static void _addSplinePointFast(
    _Float32Builder out,
    double p0x,
    double p0y,
    double p1x,
    double p1y,
    double p1p,
    double p2x,
    double p2y,
    double p2p,
    double p3x,
    double p3y,
    double t,
  ) {
    final double t2 = t * t;
    final double t3 = t2 * t;
    final double x =
        0.5 *
        ((2 * p1x) +
            (-p0x + p2x) * t +
            (2 * p0x - 5 * p1x + 4 * p2x - p3x) * t2 +
            (-p0x + 3 * p1x - 3 * p2x + p3x) * t3);
    final double y =
        0.5 *
        ((2 * p1y) +
            (-p0y + p2y) * t +
            (2 * p0y - 5 * p1y + 4 * p2y - p3y) * t2 +
            (-p0y + 3 * p1y - 3 * p2y + p3y) * t3);
    final double pressure = p1p + (p2p - p1p) * t;
    out.add(x, y, pressure);
  }

  List<PointVector> _getSmoothSpine(List<PointVector> inputPoints) {
    if (inputPoints.length < 3) return inputPoints;

    final List<PointVector> result = [];
    result.add(inputPoints.first);

    for (int i = 0; i < inputPoints.length - 1; i++) {
      final p0 = inputPoints[math.max(0, i - 1)];
      final p1 = inputPoints[i];
      final p2 = inputPoints[i + 1];
      final p3 = inputPoints[math.min(inputPoints.length - 1, i + 2)];

      final dist = math.sqrt(
        math.pow(p2.x - p1.x, 2) + math.pow(p2.y - p1.y, 2),
      );

      double segFactor = dist / 4.0;
      if (i > 0 && i < inputPoints.length - 2) {
        final ax = p1.x - inputPoints[i - 1].x;
        final ay = p1.y - inputPoints[i - 1].y;
        final bx = inputPoints[i + 2].x - p2.x;
        final by = inputPoints[i + 2].y - p2.y;
        final amag = math.sqrt(ax * ax + ay * ay);
        final bmag = math.sqrt(bx * bx + by * by);
        if (amag > 0.001 && bmag > 0.001) {
          final cosTheta = (ax * bx + ay * by) / (amag * bmag).clamp(-1.0, 1.0);
          final curvature = 1.0 - cosTheta;
          if (curvature > 0.3) segFactor *= (1.0 + curvature * 0.4);
        }
      }
      // Keep at least 3 Catmull samples so tip/return tangents stay stable
      // (1-sample early-out over-densifies bends and shears end caps).
      final int segments = segFactor.ceil().clamp(3, 16);

      for (int t = 1; t <= segments; t++) {
        final double tNorm = t / segments.toDouble();

        final double t2 = tNorm * tNorm;
        final double t3 = t2 * tNorm;

        final double x =
            0.5 *
            ((2 * p1.x) +
                (-p0.x + p2.x) * tNorm +
                (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 +
                (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3);

        final double y =
            0.5 *
            ((2 * p1.y) +
                (-p0.y + p2.y) * tNorm +
                (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 +
                (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3);

        double pressure = 0.5;
        if (p1.pressure != null && p2.pressure != null) {
          pressure = p1.pressure! + (p2.pressure! - p1.pressure!) * tNorm;
        }

        result.add(PointVector(x, y, pressure));
      }
    }

    return result;
  }
}

class _Float32Builder {
  Float32List _buffer;
  int _count = 0;

  _Float32Builder({int estimatedSize = 32})
    : _buffer = Float32List(estimatedSize);

  void add(double x, double y, double p) {
    if (_count + 3 > _buffer.length) {
      final next = Float32List(_buffer.length * 2);
      next.setRange(0, _count, _buffer);
      _buffer = next;
    }
    _buffer[_count++] = x;
    _buffer[_count++] = y;
    _buffer[_count++] = p;
  }

  Float32List finish() {
    if (_count == 0) return Float32List(0);
    return Float32List.view(_buffer.buffer, _buffer.offsetInBytes, _count);
  }
}

class _StrokeMeshData {
  final ui.Vertices vertices;
  final Float32List positions;
  final Uint16List indices;
  final Int32List? colors;
  _StrokeMeshData(this.vertices, this.positions, this.indices, {this.colors});
}

enum StrokeQuality {
  low(4),
  high(1);

  const StrokeQuality(this.N);

  final int N;
}

abstract class HasBounds {
  Rect get bounds;
}

extension PointVectorBounds on PointVector {
  Rect get bounds => Rect.fromLTWH(x, y, 0.001, 0.001);
}

class QuadTree<T> {
  final Rect boundary;
  final int capacity;
  final List<T> items = [];
  final Rect Function(T item) _getBounds;

  bool divided = false;
  QuadTree<T>? northeast;
  QuadTree<T>? northwest;
  QuadTree<T>? southeast;
  QuadTree<T>? southwest;

  static final List<QuadTree<dynamic>> _insertStack = [];
  static final List<QuadTree<dynamic>> _queryStack = [];
  static final List<QuadTree<dynamic>> _removeStack = [];
  static final Set<dynamic> _querySeen = {};

  QuadTree(
    this.boundary, {
    this.capacity = 10,
    Rect Function(T item)? getBounds,
  }) : _getBounds =
           getBounds ??
           ((item) {
             if (item is HasBounds) return item.bounds;
             if (item is PointVector) return (item as PointVector).bounds;
             if (item is Stroke) return item.bounds;
             throw UnimplementedError(
               'Item must implement HasBounds or provide getBounds',
             );
           });

  bool insert(T item) {
    final itemBounds = _getBounds(item);
    if (!boundary.overlaps(itemBounds)) return false;

    final stack = _insertStack;
    stack.clear();
    stack.add(this as QuadTree<dynamic>);
    bool inserted = false;

    while (stack.isNotEmpty) {
      final node = stack.removeLast() as QuadTree<T>;
      if (!node.boundary.overlaps(itemBounds)) continue;

      if (node.items.length < node.capacity && !node.divided) {
        node.items.add(item);
        inserted = true;
        continue;
      }

      if (!node.divided) {
        node.subdivide();
      }

      stack.add(node.northeast! as QuadTree<dynamic>);
      stack.add(node.northwest! as QuadTree<dynamic>);
      stack.add(node.southeast! as QuadTree<dynamic>);
      stack.add(node.southwest! as QuadTree<dynamic>);
    }

    return inserted;
  }

  void subdivide() {
    final x = boundary.left;
    final y = boundary.top;
    final w = boundary.width / 2;
    final h = boundary.height / 2;

    northeast = QuadTree(
      Rect.fromLTWH(x + w, y, w, h),
      capacity: capacity,
      getBounds: _getBounds,
    );
    northwest = QuadTree(
      Rect.fromLTWH(x, y, w, h),
      capacity: capacity,
      getBounds: _getBounds,
    );
    southeast = QuadTree(
      Rect.fromLTWH(x + w, y + h, w, h),
      capacity: capacity,
      getBounds: _getBounds,
    );
    southwest = QuadTree(
      Rect.fromLTWH(x, y + h, w, h),
      capacity: capacity,
      getBounds: _getBounds,
    );
    divided = true;
  }

  List<T> query(Rect range, [List<T>? found]) {
    found ??= [];
    _querySeen.clear();

    final stack = _queryStack;
    stack.clear();
    stack.add(this as QuadTree<dynamic>);

    while (stack.isNotEmpty) {
      final node = stack.removeLast() as QuadTree<T>;
      if (!node.boundary.overlaps(range)) continue;

      for (int i = 0; i < node.items.length; i++) {
        final item = node.items[i];
        if (range.overlaps(_getBounds(item)) && _querySeen.add(item)) {
          found.add(item);
        }
      }

      if (node.divided) {
        stack.add(node.northeast! as QuadTree<dynamic>);
        stack.add(node.northwest! as QuadTree<dynamic>);
        stack.add(node.southeast! as QuadTree<dynamic>);
        stack.add(node.southwest! as QuadTree<dynamic>);
      }
    }
    
    // Clear the set reference so it doesn't hold memory
    _querySeen.clear();
    return found;
  }

  bool remove(T item) {
    final itemBounds = _getBounds(item);
    if (!boundary.overlaps(itemBounds)) return false;

    final stack = _removeStack;
    stack.clear();
    stack.add(this as QuadTree<dynamic>);
    bool removed = false;

    while (stack.isNotEmpty) {
      final node = stack.removeLast() as QuadTree<T>;
      if (!node.boundary.overlaps(itemBounds)) continue;

      if (node.items.remove(item)) {
        removed = true;
      }

      if (node.divided) {
        stack.add(node.northeast! as QuadTree<dynamic>);
        stack.add(node.northwest! as QuadTree<dynamic>);
        stack.add(node.southeast! as QuadTree<dynamic>);
        stack.add(node.southwest! as QuadTree<dynamic>);
      }
    }

    return removed;
  }
}

class SpatialGrid {
  SpatialGrid({this.cellSize = 100.0});

  final double cellSize;
  final Map<int, List<int>> _grid = {};

  static final List<int> _queryBuffer = [];
  static final Set<int> _seenBuffer = {};

  int _cellHash(int cx, int cy) {
    return (cx * 73856093) ^ (cy * 19349663);
  }

  void clear() {
    _grid.clear();
  }

  void insert(int strokeIndex, Rect bounds) {
    final startX = (bounds.left / cellSize).floor();
    final endX = (bounds.right / cellSize).floor();
    final startY = (bounds.top / cellSize).floor();
    final endY = (bounds.bottom / cellSize).floor();

    for (var cx = startX; cx <= endX; cx++) {
      for (var cy = startY; cy <= endY; cy++) {
        final h = _cellHash(cx, cy);
        _grid.putIfAbsent(h, () => []).add(strokeIndex);
      }
    }
  }

  List<int> query(Rect rect) {
    final startX = (rect.left / cellSize).floor();
    final endX = (rect.right / cellSize).floor();
    final startY = (rect.top / cellSize).floor();
    final endY = (rect.bottom / cellSize).floor();

    _queryBuffer.clear();
    _seenBuffer.clear();

    for (var cx = startX; cx <= endX; cx++) {
      for (var cy = startY; cy <= endY; cy++) {
        final list = _grid[_cellHash(cx, cy)];
        if (list != null) {
          for (final i in list) {
            if (_seenBuffer.add(i)) {
              _queryBuffer.add(i);
            }
          }
        }
      }
    }
    
    // Clear the set reference so it doesn't hold memory
    _seenBuffer.clear();
    _queryBuffer.sort();
    return _queryBuffer;
  }
}
