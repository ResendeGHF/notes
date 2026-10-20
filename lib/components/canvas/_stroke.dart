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
import 'package:saber/data/editor/stroke_paint.dart';
import 'package:saber/data/editor/stroke_paint_image_cache.dart';
import 'package:saber/data/extensions/dynamic_extensions.dart';
import 'package:saber/data/extensions/list_extensions.dart';
import 'package:saber/data/extensions/point_extensions.dart';
import 'package:saber/data/extensions/svg_path_formatting.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';
import 'package:saber/data/stroke_geometry/motion_event_predictor.dart'
    show MotionEventPredictor;
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
        case StrokeBinaryKeys.googleInkFamily:
          // Defensive: snapshot lives pre-options, but drain it here too so
          // a misplaced key can never desync the stream.
          reader.readStringNoKey();
        case StrokeBinaryKeys.googleInkEpsilon:
        case StrokeBinaryKeys.googleInkSmoothingMs:
          reader.readFloat();
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

/// Pixel bites taken out of one stroke by the carve eraser.
///
/// The stroke geometry, pressure and paint anchor stay intact. Rendering
/// punches these discs and round strokes out of the ink, the way a real
/// eraser lifts pigment without splitting the mark or growing new caps.
class StrokeCarveMask {
  StrokeCarveMask();

  final List<double> _radii = [];
  final List<Float32List> _xy = [];
  final List<int> _lengths = [];
  final List<Float32List> _bounds = [];
  final Float32List _totalBounds = Float32List.fromList([
    double.infinity,
    double.infinity,
    double.negativeInfinity,
    double.negativeInfinity
  ]);

  bool get isEmpty => _radii.isEmpty;
  int get runCount => _radii.length;

  double get maxRadius {
    var m = 0.0;
    for (final r in _radii) {
      if (r > m) m = r;
    }
    return m;
  }

  int get fingerprint {
    if (_radii.isEmpty) return 0;
    final last = _xy.last;
    final len = _lengths.last;
    return Object.hash(
      _radii.length,
      len,
      _radii.last.toInt(),
      len == 0 ? 0 : last[0].toInt(),
      len < 2 ? 0 : last[1].toInt(),
    );
  }

  StrokeCarveMask clone() {
    final copy = StrokeCarveMask();
    copy._radii.addAll(_radii);
    for (var i = 0; i < _xy.length; i++) {
      final run = _xy[i];
      final len = _lengths[i];
      final clonedRun = Float32List(run.length);
      clonedRun.setRange(0, len, run);
      copy._xy.add(clonedRun);
      copy._lengths.add(len);
    }
    for (final b in _bounds) {
      copy._bounds.add(Float32List.fromList(b));
    }
    copy._totalBounds.setRange(0, 4, _totalBounds);
    return copy;
  }

  void _updateTotalBounds(double x, double y) {
    if (x < _totalBounds[0]) _totalBounds[0] = x;
    if (y < _totalBounds[1]) _totalBounds[1] = y;
    if (x > _totalBounds[2]) _totalBounds[2] = x;
    if (y > _totalBounds[3]) _totalBounds[3] = y;
  }

  void addSweep(Offset from, Offset to, double radius) {
    if (radius <= 0 || !from.dx.isFinite || !to.dx.isFinite) return;
    if (_continuesLast(from, radius)) {
      _appendPoint(_xy.length - 1, to);
      return;
    }
    if ((from - to).distance < 0.4) {
      _radii.add(radius);
      final run = Float32List(16);
      run[0] = from.dx;
      run[1] = from.dy;
      _xy.add(run);
      _lengths.add(2);
      _bounds.add(Float32List.fromList([from.dx, from.dy, from.dx, from.dy]));
      _updateTotalBounds(from.dx, from.dy);
      return;
    }
    final run = Float32List(16);
    run[0] = from.dx;
    run[1] = from.dy;
    run[2] = to.dx;
    run[3] = to.dy;
    _radii.add(radius);
    _xy.add(run);
    _lengths.add(4);
    
    final b = Float32List(4);
    b[0] = math.min(from.dx, to.dx);
    b[1] = math.min(from.dy, to.dy);
    b[2] = math.max(from.dx, to.dx);
    b[3] = math.max(from.dy, to.dy);
    _bounds.add(b);

    _updateTotalBounds(from.dx, from.dy);
    _updateTotalBounds(to.dx, to.dy);
  }

  bool _continuesLast(Offset from, double radius) {
    if (_radii.isEmpty || (_radii.last - radius).abs() > 0.05) return false;
    final run = _xy.last;
    final len = _lengths.last;
    if (len < 2) return false;
    final dx = from.dx - run[len - 2];
    final dy = from.dy - run[len - 1];
    return dx * dx + dy * dy <= 1.0;
  }

  void _appendPoint(int runIndex, Offset p) {
    final run = _xy[runIndex];
    final len = _lengths[runIndex];
    if (len >= 2) {
      final lx = run[len - 2];
      final ly = run[len - 1];
      final dx = p.dx - lx;
      final dy = p.dy - ly;
      if (dx * dx + dy * dy < 0.36) return;
    }
    if (len >= 16000) return;
    
    if (len + 2 > run.length) {
      final next = Float32List(run.length * 2);
      next.setRange(0, len, run);
      _xy[runIndex] = next;
    }
    
    _xy[runIndex][len] = p.dx;
    _xy[runIndex][len + 1] = p.dy;
    _lengths[runIndex] += 2;
    
    final b = _bounds[runIndex];
    if (p.dx < b[0]) b[0] = p.dx;
    if (p.dy < b[1]) b[1] = p.dy;
    if (p.dx > b[2]) b[2] = p.dx;
    if (p.dy > b[3]) b[3] = p.dy;

    _updateTotalBounds(p.dx, p.dy);
  }

  void translate(Offset delta) {
    if (delta == Offset.zero) return;
    for (var r = 0; r < _xy.length; r++) {
      final run = _xy[r];
      final len = _lengths[r];
      for (var i = 0; i < len; i += 2) {
        run[i] += delta.dx;
        run[i + 1] += delta.dy;
      }
    }
    for (final b in _bounds) {
      b[0] += delta.dx;
      b[1] += delta.dy;
      b[2] += delta.dx;
      b[3] += delta.dy;
    }
    _totalBounds[0] += delta.dx;
    _totalBounds[1] += delta.dy;
    _totalBounds[2] += delta.dx;
    _totalBounds[3] += delta.dy;
  }

  void rotate(double angleRad, Offset center) {
    if (angleRad == 0) return;
    final cos = math.cos(angleRad);
    final sin = math.sin(angleRad);
    _totalBounds[0] = double.infinity;
    _totalBounds[1] = double.infinity;
    _totalBounds[2] = double.negativeInfinity;
    _totalBounds[3] = double.negativeInfinity;

    for (int r = 0; r < _xy.length; r++) {
      final run = _xy[r];
      final len = _lengths[r];
      double minX = double.infinity, minY = double.infinity, maxX = double.negativeInfinity, maxY = double.negativeInfinity;
      for (var i = 0; i < len; i += 2) {
        final dx = run[i] - center.dx;
        final dy = run[i + 1] - center.dy;
        run[i] = center.dx + dx * cos - dy * sin;
        run[i + 1] = center.dy + dx * sin + dy * cos;
        if (run[i] < minX) minX = run[i];
        if (run[i] > maxX) maxX = run[i];
        if (run[i+1] < minY) minY = run[i+1];
        if (run[i+1] > maxY) maxY = run[i+1];
      }
      final b = _bounds[r];
      b[0] = minX; b[1] = minY; b[2] = maxX; b[3] = maxY;

      _updateTotalBounds(minX, minY);
      _updateTotalBounds(maxX, maxY);
    }
  }

  void scale(double factor, Offset center) {
    if (factor == 1) return;
    _totalBounds[0] = double.infinity;
    _totalBounds[1] = double.infinity;
    _totalBounds[2] = double.negativeInfinity;
    _totalBounds[3] = double.negativeInfinity;

    for (var r = 0; r < _radii.length; r++) {
      _radii[r] *= factor;
    }
    for (int r = 0; r < _xy.length; r++) {
      final run = _xy[r];
      final len = _lengths[r];
      double minX = double.infinity, minY = double.infinity, maxX = double.negativeInfinity, maxY = double.negativeInfinity;
      for (var i = 0; i < len; i += 2) {
        run[i] = center.dx + (run[i] - center.dx) * factor;
        run[i + 1] = center.dy + (run[i + 1] - center.dy) * factor;
        if (run[i] < minX) minX = run[i];
        if (run[i] > maxX) maxX = run[i];
        if (run[i+1] < minY) minY = run[i+1];
        if (run[i+1] > maxY) maxY = run[i+1];
      }
      final b = _bounds[r];
      b[0] = minX; b[1] = minY; b[2] = maxX; b[3] = maxY;

      _updateTotalBounds(minX, minY);
      _updateTotalBounds(maxX, maxY);
    }
  }

  double distanceSq(double x, double y) {
    var best = double.infinity;
    for (int r = 0; r < _xy.length; r++) {
      final run = _xy[r];
      final len = _lengths[r];
      if (len < 2) continue;
      
      final b = _bounds[r];
      final margin = _radii[r];
      if (x < b[0] - margin || x > b[2] + margin || y < b[1] - margin || y > b[3] + margin) {
        continue;
      }

      if (len == 2) {
        final dx = x - run[0];
        final dy = y - run[1];
        final d = dx * dx + dy * dy;
        if (d < best) best = d;
        continue;
      }
      for (var i = 0; i + 3 < len; i += 2) {
        final d = _distSqToSeg(x, y, run[i], run[i + 1], run[i + 2], run[i + 3]);
        if (d < best) best = d;
      }
    }
    return best;
  }
  
  static double _distSqToSeg(
    double px,
    double py,
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    final abx = bx - ax;
    final aby = by - ay;
    final ab2 = abx * abx + aby * aby;
    if (ab2 < 1e-12) {
      final dx = px - ax;
      final dy = py - ay;
      return dx * dx + dy * dy;
    }
    var t = ((px - ax) * abx + (py - ay) * aby) / ab2;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    final dx = px - (ax + abx * t);
    final dy = py - (ay + aby * t);
    return dx * dx + dy * dy;
  }

  void punch(Canvas canvas) {
    final clear = Paint()
      ..blendMode = BlendMode.clear
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..blendMode = BlendMode.clear
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = 0; i < _radii.length; i++) {
      final radius = _radii[i];
      final run = _xy[i];
      final len = _lengths[i];
      if (len < 2 || radius <= 0) continue;
      if (len == 2) {
        canvas.drawCircle(Offset(run[0], run[1]), radius, clear);
        continue;
      }
      final path = Path()..moveTo(run[0], run[1]);
      for (var k = 2; k + 1 < len; k += 2) {
        path.lineTo(run[k], run[k + 1]);
      }
      strokePaint.strokeWidth = radius * 2;
      canvas.drawPath(path, strokePaint);
    }
  }

  void writeBinary(BinaryWriter writer) {
    writer.writeInt(StrokeBinaryKeys.carveMask, _radii.length);
    for (var i = 0; i < _radii.length; i++) {
      writer.writeScaledFloatNoKey(_radii[i]);
      final run = _xy[i];
      final len = _lengths[i];
      final n = len ~/ 2;
      writer.writeIntNoKey(n);
      for (var k = 0; k < len; k++) {
        writer.writeScaledFloatNoKey(run[k]);
      }
    }
  }

  static StrokeCarveMask readBinary(BinaryReader reader, int runCount) {
    final mask = StrokeCarveMask();
    final safeRuns = runCount.clamp(0, 4096);
    for (var i = 0; i < safeRuns; i++) {
      final radius = reader.readScaledFloat();
      final n = reader.readIntNoKey().clamp(0, 8000);
      final len = n * 2;
      final run = Float32List(len);
      double minX = double.infinity, minY = double.infinity, maxX = double.negativeInfinity, maxY = double.negativeInfinity;
      for (var k = 0; k < len; k++) {
        run[k] = reader.readScaledFloat();
        if (k % 2 == 0) {
          if (run[k] < minX) minX = run[k];
          if (run[k] > maxX) maxX = run[k];
        } else {
          if (run[k] < minY) minY = run[k];
          if (run[k] > maxY) maxY = run[k];
        }
      }
      if (radius > 0 && n > 0) {
        mask._radii.add(radius);
        mask._xy.add(run);
        mask._lengths.add(len);
        mask._bounds.add(Float32List.fromList([minX, minY, maxX, maxY]));
        mask._updateTotalBounds(minX, minY);
        mask._updateTotalBounds(maxX, maxY);
      }
    }
    return mask;
  }

  List<List<double>> toJsonLists() {
    final out = <List<double>>[];
    for (var i = 0; i < _radii.length; i++) {
      final run = _xy[i];
      final len = _lengths[i];
      final row = <double>[ _radii[i] ];
      for (var k = 0; k < len; k++) {
        row.add(run[k]);
      }
      out.add(row);
    }
    return out;
  }

  static StrokeCarveMask? fromJsonLists(Object? raw) {
    if (raw is! List || raw.isEmpty) return null;
    final mask = StrokeCarveMask();
    for (final row in raw) {
      if (row is! List || row.length < 3) continue;
      final radius = (row[0] as num).toDouble();
      final n = (row.length - 1) ~/ 2;
      if (radius <= 0 || n <= 0) continue;
      final len = n * 2;
      final run = Float32List(len);
      double minX = double.infinity, minY = double.infinity, maxX = double.negativeInfinity, maxY = double.negativeInfinity;
      for (var k = 0; k < len; k++) {
        run[k] = (row[k + 1] as num).toDouble();
        if (k % 2 == 0) {
          if (run[k] < minX) minX = run[k];
          if (run[k] > maxX) maxX = run[k];
        } else {
          if (run[k] < minY) minY = run[k];
          if (run[k] > maxY) maxY = run[k];
        }
      }
      mask._radii.add(radius);
      mask._xy.add(run);
      mask._lengths.add(len);
      mask._bounds.add(Float32List.fromList([minX, minY, maxX, maxY]));
      mask._updateTotalBounds(minX, minY);
      mask._updateTotalBounds(maxX, maxY);
    }
    return mask.isEmpty ? null : mask;
  }
}

class Stroke implements HasBounds, Comparable<Stroke> {
  static final log = Logger('Stroke');

  int zIndex = 0;

  @visibleForTesting
  @protected
  final List<PointVector> points = [];

  int get sampleCount => points.length;

  /// Live input decimation: while drawing, samples closer than this to the
  /// last committed sample carry no visible ink (sub-pixel at any zoom) but
  /// each one forces a full geometry rebuild. Absorbing them keeps per-frame
  /// work bounded as the stroke grows — the same reason rnote smooths raw
  /// input through its modeler and the Ink API coalesces MotionEvents.
  static const kLiveMinSampleDistPx = 1.0;

  /// In-place samples are still kept when pressure actually moves (pressing
  /// harder without moving must widen fountain/brush nibs).
  static const kLiveMinPressureDelta = 0.08;

  /// Live render staging ("ink in stone"): while drawing, the committed
  /// prefix is baked once into frozen butt-jointed chunks and only this many
  /// trailing raw points are re-tessellated per frame. Frozen chunks never
  /// rebuild, so already-drawn regions cannot dance, and per-frame UI
  /// work stays constant no matter how long the stroke gets.
  static const kLiveStageTailPoints = 192;

  /// Scan-back window when choosing a freeze boundary: prefer a straight
  /// run so butt joints join invisibly under any blend mode.
  static const kLiveStageGateScan = 64;

  /// Maximum tail overrun while no straight boundary is found (continuous
  /// scribble through corners): freeze at the straightest point anyway so
  /// per-frame work stays bounded.
  static const kLiveStageTailOverrun = 256;

  /// Minimum raw points per frozen chunk (degenerate ranges are deferred).
  static const kLiveStageMinChunk = 3;

  /// Minimum frozen span per extension: without this the freeze target
  /// tracks the tip and every sample would seal a micro-chunk (hundreds of
  /// draw calls). With it, extensions happen about every window/±, chunks
  /// stay ~128+ points and per-frame draw calls stay in the dozens.
  static const kLiveStageMinFreeze = 128;

  /// Joint sagitta budget: sin(turn/2) * halfWidth below this reads as a
  /// perfect joint. Scales the gate angle to the pen width.
  static const kLiveStageGateSagittaPx = 0.75;

  /// Hard cap: a single stroke never holds more raw samples than this.
  /// Reached only by pathological input (minutes-long scribbles at 240 Hz);
  /// enforced by visually-lossless RDP thinning so one user stroke stays one
  /// object instead of OOMing the tessellator/file.
  static const kMaxStrokeSamples = 6000;

  /// Tessellation input cap for the spine mesh. Committed strokes beyond this
  /// (e.g. loaded from old files) are stride-sampled with endpoints kept, so
  /// vertex/index buffers — and the Uint16 index range below — stay bounded.
  static const kMaxMeshSpinePoints = 4096;

  /// `ui.Vertices.raw` takes Uint16 indices: never emit more than this many
  /// vertices in one mesh (long strokes used to wrap indices → garbage/crash).
  static const kMaxMeshVertices = 60000;

  /// Spline upsampler output cap (total points). Prevents a single teleport
  /// gap from exploding into hundreds of interpolated samples per segment.
  static const kMaxSplineOutputPoints = 8192;

  /// Minimum raw points before tile-local clipping engages. Short strokes
  /// take the exact legacy full-geometry path (zero behavior change).
  static const kTileClipMinPoints = 512;

  /// Sutherland–Hodgman clip of a closed outline loop to [rect] (with
  /// optional outward [bleed]). Exact for opaque fills; safe for idempotent
  /// darken blending under overlap. Never use for translucent/additive
  /// blends (bands) or bounds-anchored paints (gradient shift — clip the
  /// geometry but keep the original bounds for the paint instead).
  static List<Offset> clipPolygonToRect(
    List<Offset> poly,
    Rect rect, {
    double bleed = 0,
  }) {
    if (poly.isEmpty) return const [];
    final r = bleed > 0 ? rect.inflate(bleed) : rect;
    var minX = double.infinity,
        minY = double.infinity,
        maxX = double.negativeInfinity,
        maxY = double.negativeInfinity;
    for (final p in poly) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    if (maxX < r.left || minX > r.right || maxY < r.top || minY > r.bottom) {
      return const [];
    }
    if (minX >= r.left &&
        maxX <= r.right &&
        minY >= r.top &&
        maxY <= r.bottom) {
      return poly;
    }
    // Closed loop: drop a duplicated trailing joint for the clip; the
    // caller re-closes with addPolygon(..., true).
    var src = poly;
    if (src.length > 1 && src.first == src.last) {
      src = src.sublist(0, src.length - 1);
    }
    List<Offset> clipEdge(
      List<Offset> input,
      bool Function(Offset p) inside,
      Offset Function(Offset a, Offset b) intersect,
    ) {
      if (input.isEmpty) return const [];
      final out = <Offset>[];
      var s = input.last;
      var sIn = inside(s);
      for (final e in input) {
        final eIn = inside(e);
        if (eIn) {
          if (!sIn) out.add(intersect(s, e));
          out.add(e);
        } else if (sIn) {
          out.add(intersect(s, e));
        }
        s = e;
        sIn = eIn;
      }
      return out;
    }

    Offset intersectX(Offset a, Offset b, double x) {
      final dx = b.dx - a.dx;
      if (dx.abs() < 1e-9) return Offset(x, a.dy);
      final t = (x - a.dx) / dx;
      return Offset(x, a.dy + t * (b.dy - a.dy));
    }

    Offset intersectY(Offset a, Offset b, double y) {
      final dy = b.dy - a.dy;
      if (dy.abs() < 1e-9) return Offset(a.dx, y);
      final t = (y - a.dy) / dy;
      return Offset(a.dx + t * (b.dx - a.dx), y);
    }

    var out = src;
    out = clipEdge(out, (p) => p.dx >= r.left, (a, b) => intersectX(a, b, r.left));
    if (out.isEmpty) return const [];
    out = clipEdge(out, (p) => p.dx <= r.right, (a, b) => intersectX(a, b, r.right));
    if (out.isEmpty) return const [];
    out = clipEdge(out, (p) => p.dy >= r.top, (a, b) => intersectY(a, b, r.top));
    if (out.isEmpty) return const [];
    out = clipEdge(out, (p) => p.dy <= r.bottom, (a, b) => intersectY(a, b, r.bottom));
    return out;
  }

  /// Buckets mesh triangles to [clip] (with [bleed] pad), compacting to the
  /// referenced vertices. Returns null when nothing overlaps, or the
  /// original arrays (no copy) when everything overlaps.
  static ({Float32List positions, Uint16List indices, Int32List? colors})?
  clipMeshArrays(
    Float32List positions,
    Uint16List indices,
    Int32List? colors,
    Rect clip, {
    double bleed = 1.5,
  }) {
    if (positions.isEmpty || indices.isEmpty) return null;
    final r = clip.inflate(bleed);
    final triCount = indices.length ~/ 3;
    var inside = 0;
    for (var t = 0; t < triCount; t++) {
      final o = t * 3;
      var minX = double.infinity,
          minY = double.infinity,
          maxX = double.negativeInfinity,
          maxY = double.negativeInfinity;
      var ok = true;
      for (var k = 0; k < 3; k++) {
        final v = indices[o + k] * 2;
        if (v + 1 >= positions.length) {
          ok = false;
          break;
        }
        final x = positions[v], y = positions[v + 1];
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
      if (ok &&
          maxX >= r.left &&
          minX <= r.right &&
          maxY >= r.top &&
          minY <= r.bottom) {
        inside++;
      }
    }
    if (inside == 0) return null;
    // Empty color buffers mean "no per-vertex colors" (solid ink): preserve
    // null so clipped Vertices keep using the paint color. Forwarding an
    // empty (but non-null) buffer would allocate zero-filled colors below,
    // rendering transparent.
    final bool hasColors = colors != null && colors.isNotEmpty;
    if (inside == triCount) {
      return (positions: positions, indices: indices, colors: hasColors ? colors : null);
    }
    final remap = <int, int>{};
    final newPos = <double>[];
    final newIdx = Uint16List(inside * 3);
    final newCol = hasColors ? Int32List(inside * 2) : null;
    var w = 0;
    for (var t = 0; t < triCount; t++) {
      final o = t * 3;
      var minX = double.infinity,
          minY = double.infinity,
          maxX = double.negativeInfinity,
          maxY = double.negativeInfinity;
      var ok = true;
      for (var k = 0; k < 3; k++) {
        final v = indices[o + k] * 2;
        if (v + 1 >= positions.length) {
          ok = false;
          break;
        }
        final x = positions[v], y = positions[v + 1];
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
      if (!ok ||
          maxX < r.left ||
          minX > r.right ||
          maxY < r.top ||
          minY > r.bottom) {
        continue;
      }
      for (var k = 0; k < 3; k++) {
        final old = indices[o + k];
        var mapped = remap[old];
        if (mapped == null) {
          mapped = newPos.length ~/ 2;
          remap[old] = mapped;
          newPos.add(positions[old * 2]);
          newPos.add(positions[old * 2 + 1]);
          if (newCol != null && hasColors && old * 2 + 1 < colors!.length) {
            newCol[mapped * 2] = colors[old * 2];
            newCol[mapped * 2 + 1] = colors[old * 2 + 1];
          }
        }
        newIdx[w++] = mapped;
      }
    }
    if (w == 0) return null;
    return (
      positions: Float32List.fromList(newPos),
      indices: Uint16List.sublistView(newIdx, 0, w),
      colors: newCol != null
          ? Int32List.sublistView(newCol, 0, (w ~/ 3) * 2)
          : null,
    );
  }

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
    int end, {
    double startT = 0.0,
    double endT = 1.0,
  }) {
    // Fractional trims (carve mode): exact circle-boundary points interpolated
    // in the neighboring segments instead of the last-surviving sample (which
    // leaves up to a full sample spacing of serration/gap). startT in (0,1)
    // trims the head into segment [start-1 → start]; endT in (0,1) trims the
    // tail into segment [end → end+1]. Defaults reproduce the legacy
    // whole-sample behavior bit-for-bit.
    points.clear();
    if (startT > 0.0 && startT < 1.0 && start - 1 >= 0) {
      final a = source[start - 1];
      final b = source[start];
      points.add(PointVector(
        a.x + (b.x - a.x) * startT,
        a.y + (b.y - a.y) * startT,
        lerpPressure(a.pressure, b.pressure, startT),
      ));
    }
    for (int i = start; i <= end && i < source.length; i++) {
      if (i >= 0) points.add(source[i]);
    }
    if (endT > 0.0 && endT < 1.0 && end + 1 < source.length) {
      final a = source[end];
      final b = source[end + 1];
      points.add(PointVector(
        a.x + (b.x - a.x) * endT,
        a.y + (b.y - a.y) * endT,
        lerpPressure(a.pressure, b.pressure, endT),
      ));
    }
    _cachedBounds = null;
    _packedPoints = null;
    _cachedAveragePressure = null;
    markPolygonNeedsUpdating();
  }

  /// Pressure lerp for synthesized boundary points (carve/erase): null-safe,
  /// clamped. Public for the eraser, which interpolates cut boundaries.
  static double? lerpPressure(double? a, double? b, double t) {
    if (a == null && b == null) return null;
    return ((a ?? 0.5) + ((b ?? 0.5) - (a ?? 0.5)) * t).clamp(0.0, 1.0);
  }

  /// Paint anchor for area-erase fragments: bounds-anchored paints (gradients,
  /// textures) keep the ORIGINAL stroke bounds so the shading phase does not
  /// jump when a stroke is cut. Transient (never serialized): reloads
  /// re-anchor, an accepted rare-case tradeoff that keeps the binary format
  /// untouched.
  Rect? paintAnchorBounds;

  /// Carve-eraser bites. Null until the first carve. Geometry is unchanged.
  StrokeCarveMask? carveMask;

  bool get hasCarve => carveMask != null && !carveMask!.isEmpty;

  /// Ensures a mask exists and records one eraser sweep through this stroke.
  void addCarveSweep(Offset from, Offset to, double radius) {
    final mask = carveMask ??= StrokeCarveMask();
    mask.addSweep(from, to, radius);
    _invalidateVectorFillPicture();
  }

  /// True when every sample's full width sits inside the carve bites, so the
  /// stroke can be dropped instead of keeping an empty shell.
  bool carveCoversAllInk(double eraserRadius) {
    final mask = carveMask;
    if (mask == null || mask.isEmpty) return false;
    final need = eraserRadius - options.size / 2;
    if (need <= 0) return false;
    final pts = points;
    if (pts.isEmpty) return false;

    final sBounds = bounds;
    final mBounds = mask._totalBounds;
    if (sBounds.left < mBounds[0] - eraserRadius ||
        sBounds.top < mBounds[1] - eraserRadius ||
        sBounds.right > mBounds[2] + eraserRadius ||
        sBounds.bottom > mBounds[3] + eraserRadius) {
      return false;
    }

    final needSq = need * need;
    final stride = pts.length > 512 ? (pts.length / 512).ceil() : 1;
    for (var i = 0; i < pts.length; i += stride) {
      if (mask.distanceSq(pts[i].x, pts[i].y) > needSq) return false;
    }
    final last = pts.last;
    return mask.distanceSq(last.x, last.y) <= needSq;
  }

  /// Applies butt (flat, full-width) caps on carved ends, keeping natural caps
  /// where the fragment touches the original stroke ends. Cut ends must not
  /// inherit round caps (they would bulge past the cut) nor tapers (they
  /// would pinch a mid-stroke cut). [options] itself is final, so this swaps
  /// the per-end option objects for owned copies; natural ends keep sharing
  /// the original's (the original is discarded on carve, so no aliasing).
  void applyCarvedCaps({required bool cutStart, required bool cutEnd}) {
    if (!cutStart && !cutEnd) return;
    if (cutStart) {
      final s = options.start;
      // customTaper: null (not s.customTaper): the ctor derives
      // taperEnabled from a non-null customTaper, which would resurrect the
      // taper we just disabled. A butt cut has no taper by definition.
      options.start = s.copyWith(
        cap: false,
        taperEnabled: false,
        customTaper: null,
        easing: s.easing,
      );
    }
    if (cutEnd) {
      final e = options.end;
      options.end = e.copyWith(
        cap: false,
        taperEnabled: false,
        customTaper: null,
        easing: e.easing,
      );
    }
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

  List<PointVector>? _liveRenderScratch;

  void dispose() {
    _cachedVertices = null;
    _cachedVerticesHash = null;
    _rawPositions = null;
    _rawIndices = null;
    _rawColors = null;
    _cachedPath = null;
    _cachedPathValid = false;
    _invalidateVectorFillPicture();
  }
  
  bool pressureEnabled;
  final StrokeOptions options;

  /// Advanced brush style. Only interpreted when [toolId] is
  /// [ToolId.advancedPen]; always present so copies/serialization stay total.
  AdvancedPenOptions brushOptions;

  /// Transient brush smoothing state (never serialized). Points stored in
  /// [points] are already modeled outputs, mirroring Rnote's
  /// `PenPathModeledBuilder` buffer.
  AdvancedPenStrokeModeler? _brushModeler;
  double? _brushStartTimeSec;
  double? _brushLastTimeSec;
  bool _brushHasOpenStroke = false;

  /// Last raw (unmodeled) sample. The Up event is fed to the modeler at the
  /// lift position — like Rnote's `PenEvent::Up` element — so the committed
  /// stroke ends where the stylus lifted, not at the lagging spring tip.
  double _brushRawX = 0;
  double _brushRawY = 0;
  double _brushRawP = 0.5;
  double _brushRawT = 0;
  bool _brushHasRaw = false;
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
      // Ink Pooling mutates the tail pressure in place without adding a
      // point; without this term the cached live mesh would never rebuild
      // and the bleed would stay invisible.
      last.pressure ?? -1.0,
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

  /// True once the fallback paint path can draw this stroke without building
  /// outline geometry (the low- or high-quality polygon is already cached).
  bool get hasCachedFallbackGeometry =>
      _lowQualityPolygon != null || _highQualityPolygon != null;
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
  Path get lowQualityPath {
    return _lowQualityPath ??= getPath(lowQualityPolygon, smooth: true);
  }

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
        toolId == ToolId.pencil ||
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
        toolId == ToolId.pencil ||
        toolId == ToolId.highlighter ||
        toolId == ToolId.ballpointPen) {
      _cachedPath!.fillType = PathFillType.nonZero;
    }

    _cachedPathValid = true;
    return _cachedPath!;
  }

  void shift(Offset offset) {
    if (offset == Offset.zero) return;

    _clearLiveStaging();
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

    if (_cachedBounds != null) {
      _cachedBounds = _cachedBounds!.shift(offset);
    }

    _mapMeshPositions((x, y) => (x + offset.dx, y + offset.dy));
    carveMask?.translate(offset);
    _rebuildCachedVerticesFromCommitted();
    _refreshSpineMeshAfterTransform();
    _invalidateVectorFillPicture();
  }

  void rotate(double angleRad, Offset center) {
    if (angleRad == 0.0) return;

    _clearLiveStaging();
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

    rotationDeg = (rotationDeg + angleRad * 180.0 / math.pi) % 360.0;

    _lowQualityPath = null;
    _cachedPath = null;
    _cachedPathValid = false;
    _invalidateVectorFillPicture();
    _neonInnerPath = null;
    carveMask?.rotate(angleRad, center);
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
    _clearLiveStaging();
    _clearRawLiveTip();
    _dropBrushPredictionCache();
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
    _invalidateVectorFillPicture();
    if (!preserveBounds) {
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
    carveMask?.scale(factor, center);
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
      colors: _rawColors,
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

  bool isHitByCapsule(Offset from, Offset to, double radius) {
    if (isEmpty) return false;

    final effectiveRadius = radius + (options.size / 2);
    final effectiveRadiusSq = effectiveRadius * effectiveRadius;

    final rect = Rect.fromLTRB(
      math.min(from.dx, to.dx) - effectiveRadius,
      math.min(from.dy, to.dy) - effectiveRadius,
      math.max(from.dx, to.dx) + effectiveRadius,
      math.max(from.dy, to.dy) + effectiveRadius,
    );

    if (!bounds.overlaps(rect)) return false;

    final points = this.points;
    final int len = points.length;
    if (len < 2) {
      if (len == 1) {
        final p = points.first;
        return _distToSegmentSq(Offset(p.x, p.y), from, to) <= effectiveRadiusSq;
      }
      return false;
    }

    final eraserLeft = rect.left;
    final eraserRight = rect.right;
    final eraserTop = rect.top;
    final eraserBottom = rect.bottom;

    for (int i = 0; i < len - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      
      final minX = p1.x < p2.x ? p1.x : p2.x;
      final maxX = p1.x > p2.x ? p1.x : p2.x;
      if (minX > eraserRight || maxX < eraserLeft) continue;
      
      final minY = p1.y < p2.y ? p1.y : p2.y;
      final maxY = p1.y > p2.y ? p1.y : p2.y;
      if (minY > eraserBottom || maxY < eraserTop) continue;

      if (_segmentIntersectsCapsuleSq(Offset(p1.x, p1.y), Offset(p2.x, p2.y), from, to) <= effectiveRadiusSq) {
        return true;
      }
    }
    return false;
  }

  static double _segmentIntersectsCapsuleSq(Offset a, Offset b, Offset c, Offset d) {
    final ux = b.dx - a.dx;
    final uy = b.dy - a.dy;
    final vx = d.dx - c.dx;
    final vy = d.dy - c.dy;
    final wx = a.dx - c.dx;
    final wy = a.dy - c.dy;

    final a00 = ux * ux + uy * uy;
    final a01 = -(ux * vx + uy * vy);
    final a11 = vx * vx + vy * vy;
    final b0 = ux * wx + uy * wy;
    final b1 = -(vx * wx + vy * wy);

    final det = a00 * a11 - a01 * a01;
    double s = 0.0, t = 0.0;

    if (det > 1e-6) {
      s = (a01 * b1 - a11 * b0) / det;
      t = (a01 * b0 - a00 * b1) / det;
    } else {
      s = 0.0;
      t = (a01 > 0 ? -b0 / a01 : 0.0);
    }

    if (s < 0.0) s = 0.0; else if (s > 1.0) s = 1.0;
    if (t < 0.0) t = 0.0; else if (t > 1.0) t = 1.0;

    double bestDistSq = double.infinity;
    if (s > 0.0 && s < 1.0 && t > 0.0 && t < 1.0) {
      final px = a.dx + ux * s;
      final py = a.dy + uy * s;
      final qx = c.dx + vx * t;
      final qy = c.dy + vy * t;
      return (px - qx) * (px - qx) + (py - qy) * (py - qy);
    }

    bestDistSq = math.min(bestDistSq, _distToSegmentSq(a, c, d));
    bestDistSq = math.min(bestDistSq, _distToSegmentSq(b, c, d));
    bestDistSq = math.min(bestDistSq, _distToSegmentSq(c, a, b));
    bestDistSq = math.min(bestDistSq, _distToSegmentSq(d, a, b));

    return bestDistSq;
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
    AdvancedPenOptions? brushOptions,
  }) : brushOptions = brushOptions ?? AdvancedPenOptions.advancedDefaults() {
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

    final stroke = Stroke(
      color: color,
      pressureEnabled: pressureEnabled,
      options: options,
      pageIndex: pageIndex,
      page: page,
      toolId: toolId,
      brushOptions: _brushOptionsFromJson(json),
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
      ..paint = _strokePaintFromJson(json)
      ..carveMask = StrokeCarveMask.fromJsonLists(json['carve']);
    // Removed Google Ink snapshot keys (giF/giE/giS) are ignored so old
    // notes keep loading; their strokes arrive as fountain pen (see
    // ToolId.parsePenType).
    return stroke;
  }
  /// Reads the Advanced brush style, accepting the current `'brush'` key
  /// and the legacy `'rnote'` key (unreleased builds).
  static AdvancedPenOptions? _brushOptionsFromJson(
    Map<String, dynamic> json,
  ) {
    final raw = json['brush'] ?? json['rnote'];
    if (raw is! Map) return null;
    try {
      return AdvancedPenOptions.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      return null;
    }
  }

  /// Reads the stroke paint. Written under `'spi'`; the legacy `'sp'` key
  /// is also accepted when it holds a Map (before the options
  /// `simulatePressure` collision was fixed, `'sp'` could only survive when
  /// `simulatePressure` kept its default).
  static StrokePaint _strokePaintFromJson(Map<String, dynamic> json) {
    final raw = json['spi'] ?? json['sp'];
    if (raw is Map) {
      try {
        return StrokePaint.fromJson(Map<String, dynamic>.from(raw));
      } catch (_) {
        return const StrokePaint();
      }
    }
    return const StrokePaint();
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
      // NB: not 'sp' — that key belongs to options.simulatePressure and
      // would overwrite the paint via addAll below.
      if (!paint.isSolid) 'spi': paint.toJson(),
      if (toolId == ToolId.advancedPen) 'brush': brushOptions.toJson(),
      if (hasCarve) 'carve': carveMask!.toJsonLists(),
    }..addAll(options.toJson());
  }

  /// Encoded brush JSON of the last serialized brush config. Hundreds of
  /// strokes share the same pen prefs (insertion groups them), and
  /// `toJson()+jsonEncode` rebuilds ~1KB of transient maps/strings per stroke
  /// per save — the single hottest allocation in dense saves. Value-keyed, so
  /// in-place edits can never serve stale bytes.
  static AdvancedPenOptions? _lastBrushJsonOptions;
  static String? _lastBrushJson;

  static String _brushJsonFor(AdvancedPenOptions options) {
    final cachedOptions = _lastBrushJsonOptions;
    final cachedJson = _lastBrushJson;
    if (cachedOptions != null &&
        cachedJson != null &&
        cachedOptions == options) {
      return cachedJson;
    }
    final json = jsonEncode(options.toJson());
    _lastBrushJsonOptions = options;
    _lastBrushJson = json;
    return json;
  }

  void toBinary(BinaryWriter writer) {
    if (toolId == ToolId.highlighter) {
      options.start.cap = !flatEdge;
      options.end.cap = !flatEdge;
    }

    bool isFinitePoint(PointVector point) =>
        point.x.isFinite &&
        point.y.isFinite &&
        (!pressureEnabled ||
            point.pressure == null ||
            point.pressure!.isFinite);
    // Two passes, zero temporaries: the old `.where().toList()` cloned the
    // whole point list per stroke per save (1000+ lists on dense pages) just
    // to print the count header. Same bytes out.
    var finiteCount = 0;
    for (var i = 0; i < points.length; i++) {
      if (isFinitePoint(points[i])) finiteCount++;
    }

    writer.writeString(StrokeBinaryKeys.shape, '');
    writer.writeInt(StrokeBinaryKeys.pointCount, finiteCount);
    writer.writeBool(StrokeBinaryKeys.pressureEnabled, pressureEnabled);
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      if (!isFinitePoint(point)) continue;
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
    if (toolId == ToolId.advancedPen) {
      writer.writeString(
        StrokeBinaryKeys.advancedBrushOptions,
        _brushJsonFor(brushOptions),
      );
    }
    if (hasCarve) {
      carveMask!.writeBinary(writer);
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

    // Track bounds inline while points are hot: grid builds and culling then
    // skip the O(points) first-bounds pass per stroke on dense pages. Only
    // finite points count (mirrors the filter applied below).
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    if (pressureEnabled) {
      for (int i = 0; i < pointCount; i++) {
        double x = data.getInt32(offset, Endian.little) / 1000.0;
        offset += 4;
        double y = data.getInt32(offset, Endian.little) / 1000.0;
        offset += 4;
        double pressure = data.getInt32(offset, Endian.little) / 1000.0;
        offset += 4;
        points[i] = PointVector(x, y, pressure);
        if (x.isFinite && y.isFinite && pressure.isFinite) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    } else {
      for (int i = 0; i < pointCount; i++) {
        double x = data.getInt32(offset, Endian.little) / 1000.0;
        offset += 4;
        double y = data.getInt32(offset, Endian.little) / 1000.0;
        offset += 4;
        points[i] = PointVector(x, y);
        if (x.isFinite && y.isFinite) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    reader.offset = offset;
    final bool hasFinitePoints = minX != double.infinity;

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
    AdvancedPenOptions? brushOptions;
    if (key == StrokeBinaryKeys.advancedBrushOptions) {
      final packed = reader.readStringNoKey();
      try {
        final map = jsonDecode(packed);
        if (map is Map) {
          brushOptions =
              AdvancedPenOptions.fromJson(Map<String, dynamic>.from(map));
        }
      } catch (_) {}
      key = reader.readKey();
    }
    // Removed Google Ink snapshot keys sit between paint and options in old
    // files. Drain (and discard) them so any subset / order stays readable.
    var giGuard = 0;
    while ((key == StrokeBinaryKeys.googleInkFamily ||
            key == StrokeBinaryKeys.googleInkEpsilon ||
            key == StrokeBinaryKeys.googleInkSmoothingMs) &&
        giGuard++ < 4) {
      if (key == StrokeBinaryKeys.googleInkFamily) {
        reader.readStringNoKey();
      } else if (key == StrokeBinaryKeys.googleInkEpsilon) {
        reader.readFloat();
      } else {
        reader.readFloat();
      }
      key = reader.readKey();
    }
    StrokeCarveMask? carveMask;
    if (key == StrokeBinaryKeys.carveMask) {
      carveMask = StrokeCarveMask.readBinary(reader, reader.readIntNoKey());
      key = reader.readKey();
    }
    final options = BinaryOptions().optionsFromBinary(reader, initialKey: key);

    // Bounds were tracked inline during the packed-points loop above using
    // the same finite-point rule as the filter below, with the same margin
    // as the lazy [bounds] getter. Pre-seeding avoids an O(points) pass per
    // stroke on the first grid build / cull of dense pages.
    final double boundsMargin = options.size / 2;
    final Rect parsedBounds = hasFinitePoints
        ? Rect.fromLTRB(
            minX - boundsMargin,
            minY - boundsMargin,
            maxX + boundsMargin,
            maxY + boundsMargin,
          )
        : Rect.zero;

    return Stroke(
        color: color,
        pressureEnabled: pressureEnabled,
        options: options,
        pageIndex: pageIndex,
        page: page,
        toolId: ToolId.parsePenType(penType, fallback: ToolId.fountainPen),
        brushOptions: brushOptions,
      )
      ..flatEdge = !options.start.cap
      ..neon = neon
      ..paint = paint
      ..carveMask = carveMask
      .._cachedBounds = parsedBounds
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
    // Points are a packed run of scaled int32s (x, y, optional pressure).
    // Jump the run in one seek — walking each float is what made indexing a
    // dense note stall the UI isolate.
    final stride = pressureEnabled ? 12 : 8;
    final pointBytes = pointCount * stride;
    if (pointCount < 0 ||
        pointBytes < 0 ||
        reader.offset + pointBytes > reader.data.lengthInBytes) {
      throw Exception(
        'Stroke.skipFromBinary point payload exceeds buffer '
        '(count=$pointCount pressure=$pressureEnabled)',
      );
    }
    reader.offset += pointBytes;

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
    if (key == StrokeBinaryKeys.advancedBrushOptions) {
      reader.readStringNoKey();
      key = reader.readKey();
    }
    if (key == StrokeBinaryKeys.carveMask) {
      final runs = reader.readIntNoKey();
      StrokeCarveMask.readBinary(reader, runs);
      key = reader.readKey();
    }
    var giGuard = 0;
    while ((key == StrokeBinaryKeys.googleInkFamily ||
            key == StrokeBinaryKeys.googleInkEpsilon ||
            key == StrokeBinaryKeys.googleInkSmoothingMs) &&
        giGuard++ < 4) {
      if (key == StrokeBinaryKeys.googleInkFamily) {
        reader.readStringNoKey();
      } else {
        reader.readFloat();
      }
      key = reader.readKey();
    }
    BinaryOptions().optionsFromBinary(reader, initialKey: key);
  }

  double? _drawSampleTimeSec;

  List<PointVector>? _predictedTail;

  /// Latest RAW input position in page coordinates (pre-stabilization).
  ///
  /// Committed samples trail it by the 1€ filter lag (tens of ms at low
  /// speed / deceleration), while the Kalman lookahead collapses exactly
  /// when stopping or turning — so the live tip would visibly lag the pen at
  /// every stroke end. The live render therefore draws a short connector to
  /// this truth position (see [_liveRawTipPoint]); pen-up commits it when
  /// nothing else covers it (see [finishLiveGeometry]). Never serialized;
  /// purely transient like [_predictedTail].
  double _rawLiveTipX = double.nan;
  double _rawLiveTipY = double.nan;
  double? _rawLiveTipPressure;
  Duration? _rawLiveTipTime;

  bool get _hasRawLiveTip =>
      _rawLiveTipX.isFinite && _rawLiveTipY.isFinite;

  /// Live-tip predictor: faithful Dart port of the `EventMotionPredictor`
  /// used with Google Ink (`androidx.input.motionprediction` Kalman stack).
  /// Fed with every raw input sample; its transient tip is appended to live
  /// renders only — never committed, replaced by the next real sample.
  /// Replaces the former EMA velocity/acceleration kinematics.
  final MotionEventPredictor _motionPredictor = MotionEventPredictor();

  /// Tool accuracy for the predictor's confidence ranges (stylus predicts at
  /// full speed factor; finger ramps over 0–2 dp/ms). Written per sample by
  /// [recordPredictionSample]; defaults to stylus.
  bool predictionAccurateTool = true;

  /// Stroke stabilization applies only to these ink tools. Brush,
  /// highlighter and laser keep their raw input feel.
  bool get _allowsStrokeStabilizationAndPrediction =>
      toolId == ToolId.ballpointPen ||
      toolId == ToolId.calligraphyPen ||
      toolId == ToolId.fountainPen ||
      toolId == ToolId.advancedPen ||
      toolId == ToolId.pencil;

  /// Motion prediction (EventMotionPredictor) applies to every freehand ink
  /// pen. Highlighter with straight-line assist opts out per stroke (a tip
  /// would drag the end chord off the snapped line).
  bool get _allowsMotionPrediction =>
      toolId == ToolId.ballpointPen ||
      toolId == ToolId.calligraphyPen ||
      toolId == ToolId.fountainPen ||
      toolId == ToolId.highlighter ||
      toolId == ToolId.advancedPen ||
      toolId == ToolId.pencil;

  /// Aplica a física de superfície, inércia de cerdas e sangramento em O(1)
  /// por amostra de entrada, garantindo que o preview em tempo real (Mesh)
  /// e o traço finalizado (Polygon Outline) recebam os exatos mesmos dados.
  (Offset, double) _stepAdvancedInputPhysics(
    Offset pt,
    double rawPressure,
    double eventTimeSec,
  ) {
    final dt = _lastPhysicsTimeSec == null
        ? (1.0 / 120.0)
        : (eventTimeSec - _lastPhysicsTimeSec!).clamp(0.001, 0.25);
    _lastPhysicsTimeSec = eventTimeSec;

    final dist = _lastPhysicsPoint == null
        ? 0.0
        : (pt - _lastPhysicsPoint!).distance;
    _lastPhysicsPoint = pt;

    // Velocidade instantânea suavizada por EMA (px/segundo)
    final instSpeed = dist / dt;
    _smoothedSpeedPxPerSec = _smoothedSpeedPxPerSec * 0.65 + instSpeed * 0.35;

    // 1. Bristle Stiffness
    double p = rawPressure.clamp(0.0, 1.0);
    if (brushOptions.pressureInertia > 0.0) {
      final prevP = _lastInertPressure ?? p;
      final isReleasing = p < prevP;
      final inertia = isReleasing
          ? brushOptions.pressureInertia
          : brushOptions.pressureInertia * 0.45;
      final tau = 0.005 + inertia * 0.175;
      final alpha = dt / (tau + dt);
      p = prevP + (p - prevP) * alpha;
      _lastInertPressure = p;
    } else {
      _lastInertPressure = p;
    }

    // 2. Ink Bleeding (Pooling): Inversely proportional to velocity.
    if (brushOptions.inkPooling > 0.0) {
      final speed = math.max(1.0, _smoothedSpeedPxPerSec);
      
      // Target bleed is inversely proportional to speed.
      // Slower speed -> higher target. Faster speed -> approaches 0.
      final targetBleed = (brushOptions.inkPooling * 3.0) / (1.0 + speed * 0.04);
      
      // Smoothly interpolate current _inkPoolAccum to targetBleed.
      // Drain faster when moving to leave a trailing edge, grow slower when resting.
      final approachRate = targetBleed > _inkPoolAccum ? 2.5 : (4.0 + speed * 0.02);
      
      _inkPoolAccum += (targetBleed - _inkPoolAccum) * (1.0 - math.exp(-dt * approachRate));
      
      p = p + _inkPoolAccum;
    }

    // Surface friction is mapped strictly to visual width variations and transverse 
    // geometry shifts during rendering instead of coordinate jitter, preventing 
    // spline breaks and NaN/Infinity layout bounds errors on long strokes.
    return (pt, p);
  }

  void addPoint(Offset point, [double? pressure, Duration? timestamp]) {
    final double eventTimeSec = timestamp != null
        ? timestamp.inMicroseconds / 1e6
        : (_drawSampleTimeSec ?? 0.0) + 1.0 / 60.0;

    Offset effectivePoint = point;

    if (toolId == ToolId.advancedPen && brushOptions.ropePull  > 0.0) {
      if (_ropeAnchor == null) {
        _ropeAnchor = effectivePoint;
      } else {
        final dist = (effectivePoint - _ropeAnchor!).distance;
        if (dist > brushOptions.ropePull) {
          final dir = (effectivePoint - _ropeAnchor!) / dist;
          _ropeAnchor = effectivePoint - dir * brushOptions.ropePull;
        } else if (points.isNotEmpty && brushOptions.inkPooling <= 0.0) {
          // Mantém a ponta ancorada enquanto o cursor está dentro do raio morto.
          if (!options.isComplete) {
            noteRawLiveTip(
              _ropeAnchor!,
              _lastInertPressure ?? (pressureEnabled ? pressure : null),
              timestamp,
            );
          }
          return;
        }
      }
      effectivePoint = _ropeAnchor!;
    }

    double p = pressureEnabled ? (pressure ?? 0.5) : 0.5;
    if (toolId == ToolId.advancedPen) {
      final stepped = _stepAdvancedInputPhysics(effectivePoint, p, eventTimeSec);
      effectivePoint = stepped.$1;
      p = stepped.$2;
    }

    if (!options.isComplete) {
      noteRawLiveTip(
        effectivePoint,
        pressureEnabled ? p : null,
        timestamp,
      );
    }

    // Advanced pen with the modeled builder runs its own smoothing pipeline
    if (toolId == ToolId.advancedPen &&
        brushOptions.builderType == AdvancedPenBuilderType.modeled) {
      _addBrushModeledPoint(effectivePoint, p, timestamp, eventTimeSec);
      return;
    }

    if (!pressureEnabled) {
      pressure = null;
    } else {
      pressure = p;
      options.simulatePressure = false;
    }

    final Offset samplePoint = _allowsStrokeStabilizationAndPrediction
        ? _applyStabilization(effectivePoint, timestamp)
        : effectivePoint;

    if (toolId == ToolId.highlighter && Highlighter.straightLine.value) {
      if (points.isEmpty) {
        _commitStabilizedSample(samplePoint, pressure, eventTimeSec);
      } else {
        final first = points.first;
        final current = PointVector(samplePoint.dx, samplePoint.dy, pressure);
        final snapped = snapLine(first, current);
        points.clear();
        _packedPoints = null;
        // Straight-line assist rewrites the point list: staged indices reset.
        _clearLiveStaging();
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

  /// Feeds one raw pointer sample to the brush modeler, mirroring Rnote's
  /// `PenPathModeledBuilder::update_modeler_w_element` (Down on the first
  /// sample, Move afterwards). Modeled outputs are appended to [points];
  /// on modeler errors the raw sample is kept so ink never vanishes.
  void _addBrushModeledPoint(
    Offset point,
    double? pressure,
    Duration? timestamp, [
    double? precomputedNowSec,
  ]) {
    final double effectiveP = pressureEnabled ? (pressure ?? 0.5) : 0.5;
    final double modelerP = effectiveP.clamp(0.0, 1.0);
    // Sobrepressão de Ink Pooling (> 1.0) preservada para engordar a poça
    final double poolBoost = math.max(0.0, effectiveP - modelerP);

    final double nowSec = precomputedNowSec ??
        (timestamp != null
            ? timestamp.inMicroseconds / 1e6
            : (_brushLastTimeSec ?? 0.0) + 1.0 / 60.0);
    _brushStartTimeSec ??= nowSec;
    final double t = math.max(0.0, nowSec - _brushStartTimeSec!);

    _brushModeler ??= AdvancedPenStrokeModeler(brushOptions.modeler);
    final modeler = _brushModeler!;
    _brushRawX = point.dx;
    _brushRawY = point.dy;
    _brushRawP = effectiveP;
    _brushRawT = t;
    _brushHasRaw = true;

    // Se o usuário está segurando a caneta parada com Ink Pooling ativo,
    // atualiza a pressão dos pontos finais de repouso in-place para a poça crescer suavemente!
    if (_inkPoolAccum > 0.01 && points.isNotEmpty) {
      final last = points.last;
      final dSq = (point.dx - last.x) * (point.dx - last.x) +
          (point.dy - last.y) * (point.dy - last.y);
      if (dSq < 4.0) {
        points[points.length - 1] = PointVector(
          last.x,
          last.y,
          math.max(last.pressure ?? 0.5, effectiveP),
        );
      }
    }

    try {
      final List<AdvancedPenModelerResult> results;
      if (!_brushHasOpenStroke) {
        results = modeler.update(
          AdvancedPenModelerInput(
            eventType: AdvancedPenInputEventType.down,
            x: point.dx,
            y: point.dy,
            time: t,
            pressure: modelerP,
          ),
        );
        _brushHasOpenStroke = true;
      } else {
        var tt = t;
        if (tt <= (_brushLastTimeSec ?? -1.0)) {
          tt = _brushLastTimeSec! + 1e-4;
        }
        results = modeler.update(
          AdvancedPenModelerInput(
            eventType: AdvancedPenInputEventType.move,
            x: point.dx,
            y: point.dy,
            time: tt,
            pressure: modelerP,
          ),
        );
      }
      _brushLastTimeSec = t;
      for (final r in results) {
        // Usa effectiveP (que já tem Bristle Stiffness + Ink Pooling)
        final outP = brushOptions.pressureInertia > 0.0 || poolBoost > 0.0
            ? effectiveP
            : (r.pressure.clamp(0.0, 1.0) + poolBoost);
        points.add(PointVector(r.x, r.y, outP));
      }
      _drawSampleTimeSec = nowSec;
      _packedPoints = null;
      _cachedAveragePressure = null;
      _markLiveTailAppended(nullBounds: true);
      _enforceSampleBudget();
      _extendLiveStaging();
    } catch (_) {
      _brushModeler = AdvancedPenStrokeModeler(brushOptions.modeler);
      _brushStartTimeSec = nowSec;
      _brushLastTimeSec = 0.0;
      _brushHasOpenStroke = false;
      try {
        final results = _brushModeler!.update(
          AdvancedPenModelerInput(
            eventType: AdvancedPenInputEventType.down,
            x: point.dx,
            y: point.dy,
            time: 0.0,
            pressure: modelerP,
          ),
        );
        _brushHasOpenStroke = true;
        for (final r in results) {
          points.add(PointVector(r.x, r.y, effectiveP));
        }
      } catch (_) {
        points.add(PointVector(point.dx, point.dy, effectiveP));
      }
      _drawSampleTimeSec = nowSec;
      _packedPoints = null;
      _cachedAveragePressure = null;
      _markLiveTailAppended(nullBounds: true);
      _enforceSampleBudget();
      _extendLiveStaging();
    }
  }

  /// Feeds the Up event to the brush modeler so the spring catches up to
  /// the lift position (`model_end_of_stroke`), mirroring Rnote's
  /// `BuilderProgress::Finished` path. No-op unless a modeled stroke is open.
  void _finishBrushModeledStroke() {
    final modeler = _brushModeler;
    if (toolId != ToolId.advancedPen ||
        brushOptions.builderType != AdvancedPenBuilderType.modeled ||
        modeler == null ||
        !_brushHasOpenStroke ||
        !_brushHasRaw ||
        points.isEmpty) {
      return;
    }
    // End at the lift position (last raw sample), like Rnote's Up element.
    final double t = _brushRawT + 1.0 / 240.0;
    try {
      final results = modeler.update(
        AdvancedPenModelerInput(
          eventType: AdvancedPenInputEventType.up,
          x: _brushRawX,
          y: _brushRawY,
          time: t,
          pressure: _brushRawP.clamp(0.0, 1.0),
        ),
      );
      for (final r in results) {
        points.add(PointVector(r.x, r.y, r.pressure.clamp(0.0, 1.0)));
      }
    } catch (_) {
      // Keep existing modeled points; the stroke is still valid ink.
    }
    _brushHasOpenStroke = false;
    _packedPoints = null;
    _cachedAveragePressure = null;
    _dropBrushPredictionCache();
  }

  /// Live brush prediction tail (`StrokeModeler::predict`), shown under the
  /// tip while drawing. Never committed; replaced by the next real sample
  /// or dropped on pen-up — same contract as Rnote's `prediction_buffer`.
  ///
  /// Memoized per modeler state: paint queries it up to 3x per frame (tail
  /// presence, tail bake, full polygon) and `predict()` re-runs the model
  /// each call. The cache is dropped on every modeler mutation (see
  /// [_dropBrushPredictionCache]), so sharing the instance is exact — callers
  /// only spread it into new lists, never mutate it.
  List<PointVector> _brushPredictionTail() {
    if (_brushPredCache != null) return _brushPredCache!;
    final tail = _computeBrushPredictionTail();
    _brushPredCache = tail;
    return tail;
  }

  List<PointVector>? _brushPredCache;

  void _dropBrushPredictionCache() {
    _brushPredCache = null;
  }

  List<PointVector> _computeBrushPredictionTail() {
    final modeler = _brushModeler;
    if (toolId != ToolId.advancedPen ||
        brushOptions.builderType != AdvancedPenBuilderType.modeled ||
        options.isComplete ||
        modeler == null ||
        !_brushHasOpenStroke) {
      return const [];
    }
    try {
      final results = modeler.predict();
      if (results.isEmpty) return const [];
      final inertP = _lastInertPressure;
      final useInert = inertP != null &&
          (brushOptions.pressureInertia > 0.0 || _inkPoolAccum > 0.0);
      return [
        for (final r in results)
          PointVector(
            r.x,
            r.y,
            useInert
                ? (inertP + _inkPoolAccum).clamp(0.0, 2.5)
                : r.pressure.clamp(0.0, 1.0),
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Feeds one raw pointer sample to the live-tip predictor, mirroring
  /// upstream `record(event)` for every received MotionEvent.
  ///
  /// Call ONLY with raw (uncoalesced) pointer positions in page-local
  /// coordinates — never with gesture-arena focal points, gap-fill
  /// midpoints or committed geometry. Mixing coalesced samples into the
  /// stream fabricates teleports that the filter turns into flying tangent
  /// tips. The editor calls this from the raw-move path (plus one seed on
  /// pen-down); [addPoint] never records.
  void recordPredictionSample(
    Offset pageLocal,
    double? pressure,
    Duration timestamp, {
    required bool accurateTool,
  }) {
    if (!_allowsMotionPrediction) return;
    if (!stows.strokePrediction.value) return;
    predictionAccurateTool = accurateTool;
    _motionPredictor.record(
      pageLocal.dx,
      pageLocal.dy,
      pressure ?? 0.5,
      timestamp.inMicroseconds / 1000.0,
    );
  }

  /// True when a live sample adds no visible ink over the last committed one:
  /// sub-[kLiveMinSampleDistPx] movement without a meaningful pressure change.
  /// Shape-defining samples (first samples, corners, press-in-place) are kept.
  bool _shouldAbsorbLiveSample(Offset samplePoint, double? pressure) {
    if (points.isEmpty) return false;
    final last = points.last;
    final dx = samplePoint.dx - last.x;
    final dy = samplePoint.dy - last.y;
    final double lastPressure = last.pressure ?? 0.5;
    final double newPressure = pressure ?? lastPressure;
    // Se a caneta está parada mas o Ink Pooling está expandindo a poça,
    // atualiza a pressão do último ponto in-place sem criar vértices duplicados!
    if (dx * dx + dy * dy < kLiveMinSampleDistPx * kLiveMinSampleDistPx) {
      if (toolId == ToolId.advancedPen &&
          brushOptions.inkPooling > 0.0 &&
          newPressure > lastPressure + 0.005) {
        points[points.length - 1] = PointVector(last.x, last.y, newPressure);
        _packedPoints = null;
        _markLiveTailAppended();
      }
      return (newPressure - lastPressure).abs() < kLiveMinPressureDelta;
    }
    return false;
  }

  /// Enforces [kMaxStrokeSamples]: thins intermediate samples with a tight
  /// RDP pass (endpoints always kept, so caps/joins stay put). Runs rarely —
  /// it thins down to 3/4 of the cap — so amortized cost is negligible, while
  /// unbounded growth (tessellator OOM, multi-MB saves) becomes impossible.
  void _enforceSampleBudget() {
    if (points.length <= kMaxStrokeSamples) return;
    final int target = kMaxStrokeSamples * 3 ~/ 4;
    double epsilon = 0.75;
    List<PointVector> thinned = points;
    for (var i = 0; i < 8 && thinned.length > target; i++) {
      final next = _ramerDouglasPeucker(thinned, epsilon: epsilon);
      if (next.length >= thinned.length) {
        epsilon *= 2;
        continue;
      }
      thinned = next;
      epsilon *= 2;
    }
    if (thinned.length >= points.length) return;
    points
      ..clear()
      ..addAll(thinned);
    _packedPoints = null;
    _cachedAveragePressure = null;
    _cachedBounds = null;
    markPolygonNeedsUpdating(preserveBounds: true);
    _invalidateSpatialData();
  }

  /// Live render staging ("ink in stone").
  ///
  /// While a freehand stroke is being drawn, its committed prefix is baked
  /// ONCE into frozen butt-jointed chunks; only the trailing tail is rebuilt
  /// per frame. Frozen chunks never rebuild, so already-drawn regions cannot
  /// reshape ("dance") no matter how long the stroke gets, and per-frame UI
  /// work stays constant. Chunks use the exact committed pipeline settings
  /// (full smoothing, true start/end caps only at true ends), so pen-up
  /// changes nothing visible.
  ///
  /// Ranges share their joint point ([startPoint] of one chunk is [endPoint]
  /// of the previous). Interior ends are butt-cut; freeze boundaries sit on
  /// straight runs (see [_chooseStageBoundary]) so joints join invisibly
  /// under any blend mode.
  int _liveStagedEnd = -1;
  final List<_LiveStageChunk> _liveFrozen = [];
  _LiveStageChunk? _liveTail;
  int _liveTailN = -1;
  double _liveTailTipX = double.nan;
  double _liveTailTipY = double.nan;
  double _liveTailTipP = double.nan;
  double _liveTailPredX = double.nan;
  double _liveTailPredY = double.nan;
  int _liveTailBrushN = -1;

  /// True once a prefix has been frozen (painter then draws staged chunks).
  /// Short strokes never stage: they use the exact legacy single-build path.
  bool get hasLiveStaging => _liveFrozen.isNotEmpty;

  /// Freehand ink families whose live rendering is staged. Textured fills
  /// (bounds-anchored gradients/images), lasers and shapes keep the global
  /// rebuild: deterministic like everything else post-fix, just unbounded.
  bool get _stagesLiveGeometry {
    if (options.isComplete) return false;
    switch (toolId) {
      case ToolId.ballpointPen:
      case ToolId.fountainPen:
      case ToolId.calligraphyPen:
      case ToolId.pencil:
      case ToolId.advancedPen:
      case ToolId.highlighter:
        break;
      default:
        return false;
    }
    if (hasNonSolidPaint && !paint.usesPencilNoise) return false;
    return true;
  }

  void _clearLiveStaging() {
    // Paths/Vertices are GC'd (Pictures deliberately avoided: no dispose).
    _liveFrozen.clear();
    _liveStagedEnd = -1;
    _dropLiveTailCache();
  }

  void _dropLiveTailCache() {
    _liveTail = null;
    _liveTailN = -1;
  }

  /// Live append bookkeeping: committed caches are dropped (rebuilt lazily
  /// post-commit, never during the gesture); the frozen prefix survives
  /// untouched; only tail caches drop.
  void _markLiveTailAppended({bool nullBounds = false}) {
    if (options.isComplete) {
      markPolygonNeedsUpdating(preserveBounds: true);
      return;
    }
    _dropBrushPredictionCache();
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
    _invalidateVectorFillPicture();
    if (nullBounds) _invalidateSpatialData();
    _dropLiveTailCache();
  }

  /// Per-tool live staging windows. The Advanced brush composes outlines with
  /// heavyweight round joins/caps per joint (up to 44 cap segments with
  /// trig), so its full-rebuild cost per frame dwarfs mesh pens at the same
  /// point count (measured ~20x ballpoint on real notes). It stages earlier
  /// with smaller chunks at IDENTICAL pipeline/settings — and, unlike mesh
  /// strips (explicit triangles, no winding risk), its path chunks overlap by
  /// [_liveStageOverlap] points (see [_bakeLiveChunk]): butt-cutting a curvy
  /// ribbon with a straight chord can self-intersect the chunk outline, and
  /// nonZero winding then cancels into holes that vanish on commit. Overlap
  /// keeps every cut buried inside a neighbor's body, so cuts can never show
  /// seams or holes — opaque overdraw is pixel-identical. Typical handwriting
  /// letters (<100 pts) still take the exact legacy single-build path.
  int get _liveStageTailPoints => kLiveStageTailPoints;
  int get _liveStageMinFreeze => kLiveStageMinFreeze;
  int get _liveStageTailOverrun => kLiveStageTailOverrun;

  /// Overlap (in raw points) between adjacent live chunks. For opaque solid
  /// ink (alpha 255): translucent overdraw would double-darken the band.
  /// Pencil opts in even at lower alpha because its grain is drawn as one
  /// union path fill, where overlap shades once.
  static const int _liveStageOverlap = 8;

  bool get _liveStageOverlaps {
    if (toolId == ToolId.highlighter) return false;
    if (paint.usesPencilNoise) return true;
    return (color.a * 255.0).round() == 255 && paint.isSolid;
  }

  /// Freeze another prefix chunk once the tail outgrows its window.
  void _extendLiveStaging() {
    if (!_stagesLiveGeometry) return;
    final n = points.length;
    final tailWindow = _liveStageTailPoints;
    final tailCount = n - 1 - _liveStagedEnd;
    if (tailCount <= tailWindow) return;
    var ideal = n - 1 - tailWindow;
    ideal = ideal.clamp(_liveStagedEnd + 1, n - 2);
    if (ideal - _liveStagedEnd < _liveStageMinFreeze) return;
    final force = tailCount > tailWindow + _liveStageTailOverrun;
    final f = _chooseStageBoundary(ideal, force: force);
    if (f <= _liveStagedEnd) return;
    if (f - _liveStagedEnd < kLiveStageMinChunk) return;
    final chunk = _bakeLiveChunk(_liveStagedEnd, f, isTip: false);
    if (chunk == null) return;
    _liveFrozen.add(chunk);
    _liveStagedEnd = f;
    _dropLiveTailCache();
  }

  /// Picks a freeze boundary near [ideal] on the straightest run behind the
  /// tip, so butt joints join invisibly. Returns -1 to defer (no straight
  /// run in the scan window) unless [force] (tail overrun bound).
  int _chooseStageBoundary(int ideal, {required bool force}) {
    final n = points.length;
    const k = 8;
    if (n < k * 2 + 2) return force ? ideal : -1;
    ideal = ideal.clamp(k, n - 1 - k);
    final halfW = math.max(options.size / 2, 0.5);
    var minDot = 1.0 - 2.0 * math.pow(kLiveStageGateSagittaPx / halfW, 2);
    minDot = minDot.clamp(0.7, 0.995);
    final start = math.max(_liveStagedEnd + 1, ideal - kLiveStageGateScan);
    var best = -1;
    var bestDot = -2.0;
    for (var f = ideal; f >= start; f--) {
      final bx = points[f].x - points[f - k].x;
      final by = points[f].y - points[f - k].y;
      final dx = points[f + k].x - points[f].x;
      final dy = points[f + k].y - points[f].y;
      final bl = math.sqrt(bx * bx + by * by);
      final dl = math.sqrt(dx * dx + dy * dy);
      if (bl < 1e-6 || dl < 1e-6) continue;
      final dot = (bx * dx + by * dy) / (bl * dl);
      if (dot > bestDot) {
        bestDot = dot;
        best = f;
      }
      if (dot >= minDot) return f;
    }
    return force ? best : -1;
  }

  /// Builds one staged chunk over raw points [s]..[e] (inclusive, shared
  /// joints). Interior ends are butt-cut; true start/end caps only when the
  /// chunk touches the true stroke ends ([isTip] keeps the live end cap).
  /// Returns null for degenerate ranges (caller defers).
  _LiveStageChunk? _bakeLiveChunk(int s, int e, {required bool isTip}) {
    final start = math.max(0, s);
    if (e - start + 1 < 2 || e >= points.length) return null;
    final sub = points.sublist(start, e + 1);
    // Overlapping geometry range (Advanced opaque only): bake [lo..hi]
    // widened by [_liveStageOverlap] on interior sides so every butt cut is
    // buried inside a neighbor chunk's body. Without this, cutting a curvy
    // ribbon with a straight chord self-intersects the chunk outline and
    // nonZero winding cancels into holes that vanish on commit (live/ink
    // mismatch). Opaque overdraw is pixel-identical; bookkeeping below still
    // uses the exact committed [start..e] range. The live tip truth point
    // rides on top of the widened range when it extends past it.
    final int overlap = _liveStageOverlaps ? _liveStageOverlap : 0;
    final int glo = start > 0 ? math.max(0, start - overlap) : start;
    final int ghi = e < points.length - 1
        ? math.min(points.length - 1, e + overlap)
        : e;
    final List<PointVector> geoSub =
        (overlap == 0 || (glo == start && ghi == e))
        ? sub
        : points.sublist(glo, ghi + 1);
    // Live tip truth shared by mesh and path tip chunks (see [_liveRawTipPoint]):
    // computed once against committed points; mesh rides it after Kalman,
    // path chunks append it after their sub-range. Null unless the raw truth
    // strictly extends the live end.
    final PointVector? tipRawPt = isTip ? _liveRawTipPoint(points) : null;
    final List<PointVector> tipSub;
    if (isTip) {
      tipSub = tipRawPt == null ? geoSub : [...geoSub, tipRawPt];
    } else {
      tipSub = geoSub;
    }
    final startIsTrue = start <= 0;
    final bool isMeshFamily =
        toolId == ToolId.ballpointPen ||
        toolId == ToolId.fountainPen ||
        toolId == ToolId.calligraphyPen ||
        toolId == ToolId.advancedPen;
    // Pencil is path-only: its grain is one union fill, so live chunks never
    // build a spine mesh (the outline polygon below is the whole geometry).
    final bool isPencil = toolId == ToolId.pencil;
    final bool isNeon = neon && toolId == ToolId.ballpointPen;

    ui.Vertices? mesh;
    Path? path;
    Path? auxPath;
    Rect? bounds;

    double chunkDashOffset = 0.0;
    if (toolId == ToolId.advancedPen) {
       for (int i = 1; i <= glo; i++) {
           double dx = points[i].x - points[i-1].x;
           double dy = points[i].y - points[i-1].y;
           chunkDashOffset += math.sqrt(dx*dx + dy*dy);
       }
    }

    if (isMeshFamily || isNeon) {
      final arrays = _buildMeshRange(
        geoSub, // Usa a array com a sobreposição de segurança (overlap)
        openStart: !startIsTrue,
        openEnd: !isTip,
        withPrediction: isTip,
        startTaper: startIsTrue && options.start.taperEnabled,
        endTaper: isTip && options.end.taperEnabled,
        liveRawTip: tipRawPt,
        pathLengthOffset: chunkDashOffset,
      );
      if (arrays != null) {
        mesh = ui.Vertices.raw(
          ui.VertexMode.triangles,
          arrays.positions,
          indices: arrays.indices,
          colors: arrays.colors,
        );
        final pos = arrays.positions;
        var minX = double.infinity,
            minY = double.infinity,
            maxX = double.negativeInfinity,
            maxY = double.negativeInfinity;
        for (var i = 0; i + 1 < pos.length; i += 2) {
          final x = pos[i], y = pos[i + 1];
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
        if (minX <= maxX) {
          bounds = Rect.fromLTRB(minX, minY, maxX, maxY);
        }
      }
    }

    if (toolId == ToolId.highlighter) {
      final poly = _buildHighlighterRangePoly(
        tipSub,
        startCap: startIsTrue,
        endCap: isTip,
      );
      path = _stagedPathFor(poly);
      bounds = path.getBounds();
    } else if (isPencil || isNeon) {
      final poly = _buildBallpointRangePoly(
        tipSub,
        startCap: startIsTrue,
        endCap: isTip,
        // True neighbors of the range: smoothed as context so the cut ends
        // follow the committed spine exactly (no hair sticking out at cuts).
        leadContext: glo > 0 ? points[glo - 1] : null,
        tailContext: ghi + 1 < points.length ? points[ghi + 1] : null,
      );
      path = _stagedPathFor(poly);
      if (isNeon) {
        final inner = buildBallpointStylePolygon(
          tipSub,
          size: options.size * 0.4,
          targetScale: 1.0,
          startCap: startIsTrue,
          endCap: isTip,
        );
        auxPath = _stagedPathFor(inner);
      }
      final b = path.getBounds();
      if (bounds == null) {
        bounds = b;
      } else if (!b.isEmpty) {
        bounds = bounds.expandToInclude(b);
      }
    }

    if (mesh == null && (path == null || path.getBounds().isEmpty)) {
      return null;
    }
    return _LiveStageChunk(
      startPoint: start,
      endPoint: e,
      firstX: sub.first.x,
      firstY: sub.first.y,
      lastX: sub.last.x,
      lastY: sub.last.y,
      mesh: mesh,
      path: path,
      auxPath: auxPath,
      bounds: bounds,
    );
  }

  /// Mesh triangulation over an explicit raw-point range (live staging).
  /// Mirrors [_generateSpineMeshLOD] inputs with full committed settings.
  ///
  /// [liveRawTip] (from [_liveRawTipPoint]) rides at the END of the Kalman
  /// tail — the same [..., kalman..., raw] order as the polygon live path, so
  /// mesh and path renders agree exactly and no hook can form (the helper
  /// only returns a tip strictly beyond the Kalman end).
  ({Float32List positions, Uint16List indices, Int32List? colors})?
  _buildMeshRange(
    List<PointVector> sub, {
    required bool openStart,
    required bool openEnd,
    required bool withPrediction,
    required bool startTaper,
    required bool endTaper,
    PointVector? liveRawTip,
    double pathLengthOffset = 0.0,
  }) {
    if (sub.length < 2) return null;
    final packed = Float32List(sub.length * 3);
    for (var i = 0; i < sub.length; i++) {
      packed[i * 3] = sub[i].x;
      packed[i * 3 + 1] = sub[i].y;
      packed[i * 3 + 2] = sub[i].pressure ?? 0.5;
    }
    Float32List? tail;
    final bool useAdvancedPred = toolId == ToolId.advancedPen && brushOptions.builderType == AdvancedPenBuilderType.modeled;
    final List<PointVector> predList = useAdvancedPred ? _brushPredictionTail() : (_predictedTail ?? const []);

    if (withPrediction && _usesLiveCheapSpineMesh && predList.isNotEmpty) {
      final extra = liveRawTip == null ? 0 : 1;
      tail = Float32List((predList.length + extra) * 3);
      for (var i = 0; i < predList.length; i++) {
        tail[i * 3] = predList[i].x;
        tail[i * 3 + 1] = predList[i].y;
        tail[i * 3 + 2] = predList[i].pressure ?? 0.5;
      }
      if (liveRawTip != null) {
        final o = predList.length * 3;
        tail[o] = liveRawTip.x;
        tail[o + 1] = liveRawTip.y;
        tail[o + 2] = liveRawTip.pressure ?? 0.5;
      }
    } else if (withPrediction &&
        _usesLiveCheapSpineMesh &&
        liveRawTip != null) {
      tail = Float32List(3);
      tail[0] = liveRawTip.x;
      tail[1] = liveRawTip.y;
      tail[2] = liveRawTip.pressure ?? 0.5;
    }
    return Stroke.buildSpineMeshArrays(
      packedBase: packed,
      predictedTail: tail,
      toolId: toolId,
      flatEdge: flatEdge,
      size: options.size,
      smoothing: options.smoothing,
      simulatePressure: options.simulatePressure,
      isComplete: false,
      startCap: options.start.cap,
      startTaper: startTaper,
      startCustomTaper: options.start.customTaper,
      endCap: options.end.cap,
      endTaper: endTaper,
      endCustomTaper: options.end.customTaper,
      openStart: openStart,
      openEnd: openEnd,
      pressureMapsToCoverage: paint.pressureMapsToCoverage,
      pressureEnabled: pressureEnabled,
      targetScale: 1.0,
      brushOptions: brushOptions,
      pathLengthOffset: pathLengthOffset,
    );
  }

  /// Highlighter outline over an explicit raw-point range (live staging).
  /// Mirrors the [getPolygon] highlighter branch exactly for full ranges.
  List<Offset> _buildHighlighterRangePoly(
    List<PointVector> sub, {
    required bool startCap,
    required bool endCap,
  }) {
    final List<PointVector> source;
    if (sub.length >= 3) {
      final radius = (options.size / 2) * highlighterStrokeScaleFactor;
      final decimated = decimateStrokeSpine(
        sub,
        minDistance: math.max(1.5, radius * 1.5),
      );
      source = decimated.length >= 3 ? _getSmoothSpine(decimated) : decimated;
    } else {
      source = sub;
    }
    var strokePoints = source;
    if (strokePoints.length == 1) {
      strokePoints = [strokePoints.first, strokePoints.first];
    }
    return _buildHighlighterOutline(
      strokePoints,
      radius: (options.size / 2) * highlighterStrokeScaleFactor,
      roundCaps: !flatEdge,
      startCap: startCap,
      endCap: endCap,
    );
  }

  /// Ballpoint-style outline over an explicit raw-point range (pencil grain
  /// outline + neon glow, live staging). Mirrors the [getPolygon] ballpoint
  /// branch exactly for full ranges.
  ///
  /// [leadContext]/[tailContext] are the raw points immediately outside the
  /// rendered range. They are smoothed (so every rendered segment sees the
  /// same Catmull-Rom neighbors as the committed build) but never drawn:
  /// without them the spline's extrapolated end segments bend a hair away
  /// from the committed outline, and a frozen chunk's cut would stick out of
  /// the union by that hair.
  List<Offset> _buildBallpointRangePoly(
    List<PointVector> sub, {
    required bool startCap,
    required bool endCap,
    PointVector? leadContext,
    PointVector? tailContext,
  }) {
    final int leadCount = leadContext == null ? 0 : 1;
    final int tailCount = tailContext == null ? 0 : 1;
    if (sub.length + leadCount + tailCount < 3) {
      return buildBallpointStyleOutline(
        sub,
        size: options.size,
        startCap: startCap,
        endCap: endCap,
      );
    }
    final packed = Float32List((sub.length + leadCount + tailCount) * 3);
    var o = 0;
    void put(PointVector p) {
      packed[o++] = p.x;
      packed[o++] = p.y;
      packed[o++] = p.pressure ?? 0.5;
    }

    if (leadContext != null) put(leadContext);
    for (var i = 0; i < sub.length; i++) {
      put(sub[i]);
    }
    if (tailContext != null) put(tailContext);
    const toleranceSq = (0.12 * 1.0) * (0.12 * 1.0);
    final smooth = _getAdaptiveSpineFast(
      packed,
      toleranceSq,
      segStepPx: 1.25,
      smoothing: options.smoothing,
      trimLeadPoints: leadCount,
      trimTailPoints: tailCount,
    );
    final n = smooth.length ~/ 3;
    final sourcePoints = List.generate(
      n,
      (i) => PointVector(smooth[i * 3], smooth[i * 3 + 1], smooth[i * 3 + 2]),
    );
    return buildBallpointStyleOutline(
      sourcePoints,
      size: options.size,
      startCap: startCap,
      endCap: endCap,
    );
  }

  /// Closed fill path from an outline polygon, mirroring [highQualityPath]
  /// for authored outlines (dedup + nonZero, no smoothing).
  Path _stagedPathFor(List<Offset> poly) {
    final path = Path()..fillType = PathFillType.nonZero;
    if (poly.isEmpty) return path;
    const epsilon = 1e-6;
    final List<Offset> reduced = [poly[0]];
    for (var i = 1; i < poly.length; i++) {
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
    if (reduced.isEmpty) return path;
    path.addPolygon(reduced, true);
    return path;
  }

  /// Rebuilds the live tail chunk when the tip moved. Frozen chunks are
  /// never touched here.
  void _ensureLiveTail() {
    if (!_stagesLiveGeometry || points.length < 2) {
      _liveTail = null;
      return;
    }
    final s = math.max(0, _liveStagedEnd);
    final n = points.length;
    final tip = points.last;
    final tipP = tip.pressure ?? -1.0;
    final pred = _predictedTail != null && _predictedTail!.isNotEmpty
        ? _predictedTail!.last
        : null;
    final brushN =
        toolId == ToolId.advancedPen &&
            brushOptions.builderType == AdvancedPenBuilderType.modeled
        ? _brushPredictionTail().length
        : 0;
    final tail = _liveTail;
    if (tail != null &&
        _liveTailN == n &&
        tail.startPoint == s &&
        _liveTailTipX == tip.x &&
        _liveTailTipY == tip.y &&
        _liveTailTipP == tipP &&
        (_liveTailPredX.isNaN
            ? pred == null
            : pred != null &&
                  _liveTailPredX == pred.x &&
                  _liveTailPredY == pred.y) &&
        _liveTailBrushN == brushN) {
      return;
    }
    _liveTail = _bakeLiveChunk(_liveStagedEnd, n - 1, isTip: true);
    _liveTailN = n;
    _liveTailTipX = tip.x;
    _liveTailTipY = tip.y;
    _liveTailTipP = tipP;
    if (pred == null) {
      _liveTailPredX = double.nan;
      _liveTailPredY = double.nan;
    } else {
      _liveTailPredX = pred.x;
      _liveTailPredY = pred.y;
    }
    _liveTailBrushN = brushN;
  }

  /// Frozen staged meshes (mesh families, pencil grain mask, neon core).
  List<ui.Vertices> get liveFrozenMeshes => [
    for (final c in _liveFrozen)
      if (c.mesh != null) c.mesh!,
  ];

  /// Live tail mesh, built on demand (bounded window).
  ui.Vertices? get liveTailMesh {
    _ensureLiveTail();
    return _liveTail?.mesh;
  }

  /// Frozen staged outline paths (advanced, highlighter, pencil, neon glow).
  List<Path> get liveFrozenPaths => [
    for (final c in _liveFrozen)
      if (c.path != null) c.path!,
  ];

  /// Live tail outline path, built on demand (bounded window).
  Path? get liveTailPath {
    _ensureLiveTail();
    return _liveTail?.path;
  }

  /// Frozen neon inner cores.
  List<Path> get liveFrozenAuxPaths => [
    for (final c in _liveFrozen)
      if (c.auxPath != null) c.auxPath!,
  ];

  /// Live tail neon inner core.
  Path? get liveTailAuxPath {
    _ensureLiveTail();
    return _liveTail?.auxPath;
  }

  /// Frozen chunk bounds (painter culls off-screen chunks when zoomed in).
  List<Rect> get liveFrozenBounds => [
    for (final c in _liveFrozen)
      if (c.bounds != null) c.bounds!,
  ];

  /// Painter-facing staged chunks: frozen prefix + live tail (when built).
  /// Empty unless a prefix has been frozen.
  List<LiveStagedChunkView> get liveStagedChunks {
    if (_liveFrozen.isEmpty) return const [];
    _ensureLiveTail();
    final out = <LiveStagedChunkView>[
      for (final c in _liveFrozen)
        LiveStagedChunkView(
          mesh: c.mesh,
          path: c.path,
          auxPath: c.auxPath,
          bounds: c.bounds,
        ),
    ];
    final tail = _liveTail;
    if (tail != null &&
        (tail.mesh != null ||
            tail.path != null ||
            tail.auxPath != null)) {
      out.add(
        LiveStagedChunkView(
          mesh: tail.mesh,
          path: tail.path,
          auxPath: tail.auxPath,
          bounds: tail.bounds,
        ),
      );
    }
    return out;
  }

  @visibleForTesting
  int get debugLiveFrozenEnd => _liveStagedEnd;

  @visibleForTesting
  int get debugLiveChunkCount => _liveFrozen.length;

  @visibleForTesting
  int get debugLiveTailStart => math.max(0, _liveStagedEnd);

  void _commitStabilizedSampleWithGapFill(
    Offset stabilizedPoint,
    double? pressure,
    double timeSec,
  ) {
    if (points.isEmpty) {
      _commitStabilizedSample(stabilizedPoint, pressure, timeSec);
      return;
    }

    // Live input decimation: absorb sub-pixel jitter samples. They add
    // vertices (and a full rebuild) but no visible ink; without this a long
    // cursive/diagram stroke accumulates thousands of samples and every new
    // sample re-tessellates all of them — the progressive jank behind this
    // issue. Time bookkeeping still advances so later timestamps stay sane.
    if (!options.isComplete &&
        _shouldAbsorbLiveSample(stabilizedPoint, pressure)) {
      _drawSampleTimeSec = timeSec;
      return;
    }

    // DO NOT insert linear gap-fill points here.
    // Injecting linear points forced the Catmull-Rom spline (_getAdaptiveSpineFast)
    // to rigidly follow a straight line across dropped frames, causing the
    // "square-ish" polygonal corners during input lag (e.g. multiple tabs open).
    // By passing only the true stabilized samples, the adaptive spline natively
    // mathematically reconstructs a perfectly smooth curve across the gap.
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
      _recomputePredictionTail();
      final tail = _predictedTail;
      if (tail != null && _cachedBounds != null) {
        for (final pt in tail) {
          final px = pt.x;
          final py = pt.y;
          _cachedBounds = Rect.fromLTRB(
            math.min(_cachedBounds!.left, px - r),
            math.min(_cachedBounds!.top, py - r),
            math.max(_cachedBounds!.right, px + r),
            math.max(_cachedBounds!.bottom, py + r),
          );
        }
      }
    }

    _markLiveTailAppended();
    _enforceSampleBudget();
    _extendLiveStaging();
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

    // Relax the upper dt clamp to 1.0s. Aggressive clamping falsely inflated 
    // the calculated velocity during lag jumps, triggering the filter to bypass 
    // smoothing completely (alpha -> 1.0) exactly when we needed it the most.
    final dt = (nowSeconds - _lastTimestampSeconds!).clamp(0.001, 1.0);
    _lastTimestampSeconds = nowSeconds;

    final velocity = (point - _filteredPoint!) / dt;
    final alphaD = _alpha(dCutoff, dt);
    _filteredVelocity = _lowPass(velocity, _filteredVelocity, alphaD);
    
    // Clamp the raw speed so extreme teleportation jumps from input starvation
    // don't force alpha to 1.0, preserving the filter's positional inertia.
    final speed = _filteredVelocity!.distance.clamp(0.0, 4000.0);

    final cutoff = minCutoff + beta * speed;
    final alphaPos = _alpha(cutoff, dt);

    _filteredPoint = _lowPass(point, _filteredPoint, alphaPos);

    return _filteredPoint!;
  }

  Offset? _ropeAnchor;
  double? _lastInertPressure;
  double? _lastPhysicsTimeSec;
  Offset? _lastPhysicsPoint;
  double _smoothedSpeedPxPerSec = 0.0;
  double _inkPoolAccum = 0.0;

  /// True when time-based brush physics keeps consuming samples while the tip
  /// is stationary (ink pooling, bristle stiffness). Input decimation must
  /// keep forwarding sub-threshold moves for these brushes, otherwise a held
  /// stylus never advances the physics.
  bool get wantsRestingSamples =>
      toolId == ToolId.advancedPen &&
      (brushOptions.inkPooling > 0.0 || brushOptions.pressureInertia > 0.0);

  void resetStabilization() {
    _filteredPoint = null;
    _filteredVelocity = null;
    _lastTimestampSeconds = null;
    _drawSampleTimeSec = null;
    _predictedTail = null;
    _clearRawLiveTip();
    _dropBrushPredictionCache();
    _motionPredictor.reset();
    predictionAccurateTool = true;
    _brushModeler = null;
    _brushStartTimeSec = null;
    _brushLastTimeSec = null;
    _brushHasOpenStroke = false;
    _brushHasRaw = false;
    _ropeAnchor = null;
    _lastInertPressure = null;
    _lastPhysicsTimeSec = null;
    _lastPhysicsPoint = null;
    _smoothedSpeedPxPerSec = 0.0;
    _inkPoolAccum = 0.0;
  }

  void clearLivePrediction() {
    _predictedTail = null;
  }

  /// Test-only: injects a live prediction tip, mirroring the Kalman tail that
  /// [recordPredictionSample] + [_recomputePredictionTail] produce on device.
  @visibleForTesting
  void debugSetLivePrediction(Offset tip) {
    _predictedTail = [
      PointVector(
        tip.dx,
        tip.dy,
        points.isEmpty ? 0.5 : (points.last.pressure ?? 0.5),
      ),
    ];
  }

  /// Notes the latest raw input position for the live tip connector.
  ///
  /// Call with EVERY pointer event (even sub-threshold ones that add no ink):
  /// slow end-of-stroke creep must still move the displayed tip. Only
  /// bookkeeping here (a few field writes + tail/path dirty flags when the
  /// tip actually moved); tessellation stays lazy in paint, so this is safe
  /// at 240 Hz. Stale (older-clock) events never regress the tip: the raw
  /// Listener path runs ahead of the gesture-arena focal path for the same
  /// motion.
  void noteRawLiveTip(Offset raw, double? pressure, [Duration? timestamp]) {
    if (options.isComplete) return;
    if (timestamp != null) {
      final prevTime = _rawLiveTipTime;
      if (prevTime != null && timestamp < prevTime) return;
      _rawLiveTipTime = timestamp;
    }
    final rx = raw.dx, ry = raw.dy;
    if (_hasRawLiveTip && _rawLiveTipX == rx && _rawLiveTipY == ry) return;
    _rawLiveTipX = rx;
    _rawLiveTipY = ry;
    _rawLiveTipPressure = pressure;
    // The connector below rides in the live tail / live path / live mesh:
    // drop those caches so the next paint rebuilds them (bounded tail work
    // only). The full mesh cache must go too — otherwise sub-threshold creep
    // (absorbed samples add no points) would keep painting a stale tip.
    _dropLiveTailCache();
    _cachedPathValid = false;
    _cachedVertices = null;
    _cachedVerticesHash = null;
  }

  /// Shared turn gate for every live-tip extension (Kalman lookahead and raw
  /// connector alike): while committed travel already turned away from filter
  /// velocity, extending spikes a kink across the bend. Threshold stays at
  /// 60deg (cos<0.5), covered by `turning tip drops the lead`.
  bool _leadGatePasses() {
    if (points.length < 3) return true;
    final vel = _motionPredictor.velocity;
    final vl = vel.distance;
    if (vl <= 1e-6) return true;
    final a = points[points.length - 3];
    final b = points.last;
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final l = math.sqrt(dx * dx + dy * dy);
    if (l <= 1e-6) return true;
    return (dx * vel.dx + dy * vel.dy) / (l * vl) >= 0.5;
  }

  /// Raw-tip connector point for live renders, or null when nothing beyond
  /// committed ink should be drawn. Supplements (never duplicates) the
  /// Kalman tail: it is appended only when the raw truth sits beyond the
  /// current live end (committed tip when the tail is empty, tail end
  /// otherwise) — appending behind an overshooting lookahead would hook.
  /// Gated exactly like prediction (straight-line snap, modeled brush and
  /// turns keep pristine geometry), so existing lead tests are unaffected.
  PointVector? _liveRawTipPoint(List<PointVector> source) {
    if (options.isComplete || source.isEmpty) return null;
    if (!_allowsMotionPrediction) return null;
    if (toolId == ToolId.highlighter && Highlighter.straightLine.value) {
      return null;
    }
    if (toolId == ToolId.advancedPen &&
        brushOptions.builderType == AdvancedPenBuilderType.modeled) {
      return null;
    }
    if (!_hasRawLiveTip) return null;
    final last = source.last;
    final dx = _rawLiveTipX - last.x;
    final dy = _rawLiveTipY - last.y;
    // Sub-pixel truth adds no visible ink; skip to keep caches valid.
    if (dx * dx + dy * dy <= 0.75 * 0.75) return null;
    // Wild filter state (sharp turn) abstains exactly like prediction: the
    // direction gate alone cannot tell a stop from a turn (both align with
    // travel), but jank can. Calm flight and rests extend to the pen.
    if (!_motionPredictor.allowsShortLead(
      accurateTool: predictionAccurateTool,
    )) {
      return null;
    }
    if (!_leadGatePasses()) return null;
    if (stows.strokePrediction.value &&
        _predictedTail != null &&
        _predictedTail!.isNotEmpty) {
      final t = _predictedTail!.last;
      final tdx = t.x - last.x;
      final tdy = t.y - last.y;
      // Kalman already reaches past the raw truth: appending would hook back.
      if (dx * dx + dy * dy <=
          tdx * tdx + tdy * tdy + 0.25 * 0.25) {
        return null;
      }
    }
    return PointVector(
      _rawLiveTipX,
      _rawLiveTipY,
      _rawLiveTipPressure ?? last.pressure,
    );
  }

  void _recomputePredictionTail() {
    _predictedTail = null;
    if (!_allowsMotionPrediction) return;
    if (options.isComplete || !stows.strokePrediction.value) return;
    if (points.length < 2) return;
    // Straight-line assist snaps to committed samples only: a predicted tip
    // would drag the end chord (and its cap) off the snapped line.
    if (toolId == ToolId.highlighter && Highlighter.straightLine.value) {
      return;
    }
    if (!_leadGatePasses()) return;

    // Horizon mirrors upstream's PredictionEstimator: the predicted samples
    // land when the next frame renders — one display frame, scaled by the
    // user amount. Short by design: the tip cancels pipeline latency under
    // the stylus instead of overshooting past it as a tangent ruler.
    // (Deliberately NOT lengthened: the raw truth connector above already
    // covers stabilization lag exactly; a longer estimate would only
    // overshoot further into turns. Bounded by the `lead stays short` /
    // `committed tip stays bounded` tests.)
    final amount = stows.strokePredictionAmount.value.clamp(0.0, 1.0);
    if (amount <= 0.01) return;
    final refreshHz = DisplayInkFeel.instance.refreshHz;
    final frameMs = refreshHz > 1 ? 1000.0 / refreshHz : 16.7;
    final targetMs = (frameMs * amount).clamp(
      0.0,
      MotionEventPredictor.maxPredictionMs,
    );
    if (targetMs <= 0.5) return;

    final tips = _motionPredictor.predictPolyline(
      predictionTargetMs: targetMs,
      accurateTool: predictionAccurateTool,
    );
    if (tips.isEmpty) return;
    final anchor = _motionPredictor.lastRecordedPosition;
    if (anchor == null) return;

    // Anchor the Kalman displacement onto the COMMITTED tip: the tail
    // extends the visible ink C0-continuously instead of hanging a
    // separately-fitted raw tip off a stabilized (lagging) base, which
    // kinks at the junction and reads as a tangent ruler. Direction and
    // length still come from the filter; only the origin is re-based.
    final base = points.last;
    _predictedTail = [
      for (final tip in tips)
        PointVector(
          base.x + (tip.x - anchor.dx),
          base.y + (tip.y - anchor.dy),
          tip.pressure.isFinite ? tip.pressure : base.pressure,
        ),
    ];
    if (_cachedBounds != null) {
      final double r = options.size / 2;
      var bounds = _cachedBounds!;
      for (final tip in tips) {
        bounds = Rect.fromLTRB(
          math.min(bounds.left, tip.x - r),
          math.min(bounds.top, tip.y - r),
          math.max(bounds.right, tip.x + r),
          math.max(bounds.bottom, tip.y + r),
        );
      }
      _cachedBounds = bounds;
    }
  }

  List<PointVector> _pointsForLiveRender(
    List<PointVector> source, {
    bool reuseBuffer = false,
  }) {
    if (options.isComplete || source.isEmpty) return source;
    final bool useKalman =
        _allowsMotionPrediction &&
        !options.isComplete &&
        stows.strokePrediction.value &&
        _predictedTail != null &&
        _predictedTail!.isNotEmpty;
    // Raw truth connector (end-of-stroke anti-lag): appended only when it
    // extends past the current live end (see [_liveRawTipPoint]).
    final rawTip = _liveRawTipPoint(source);
    if (!useKalman && rawTip == null) return source;

    if (!reuseBuffer) {
      return [
        ...source,
        if (useKalman) ..._predictedTail!,
        if (rawTip != null) rawTip,
      ];
    }
    final scratch = _liveRenderScratch ??= <PointVector>[];
    scratch
      ..clear()
      ..addAll(source);
    if (useKalman) scratch.addAll(_predictedTail!);
    if (rawTip != null) scratch.add(rawTip);
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
    // Advanced pen: points are already modeled outputs (same contract as
    // Rnote's PenPathModeledBuilder buffer). Compose the variable-width
    // ribbon directly — no Saber streamline/spline on top.
    if (toolId == ToolId.advancedPen) {
      return _getBrushPolygon();
    }

    // 1. Get points WITH the prediction tip appended FIRST.
    // Live and committed tessellation use the same inputs and settings, so
    // already-drawn regions never reshape ("ink in stone"). Per-frame cost
    // is bounded separately by live render staging (frozen chunks + tail).
    // Live reuses a scratch buffer (no `[...a, ...b]` alloc per frame);
    // committed keeps the exact legacy copy path.
    final List<PointVector> basePoints = _pointsForLiveRender(
      points,
      reuseBuffer: !options.isComplete,
    );

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
        final radius = (options.size / 2) * highlighterStrokeScaleFactor;
        final decimated = decimateStrokeSpine(
          basePoints,
          minDistance: math.max(1.5, radius * 1.5), 
        );
        sourcePoints = decimated.length >= 3
            ? _getSmoothSpine(decimated)
            : decimated;
      } else {
        sourcePoints = basePoints;
      }
    } else if (toolId == ToolId.calligraphyPen ||
        toolId == ToolId.fountainPen ||
        toolId == ToolId.ballpointPen ||
        toolId == ToolId.pencil ||
        toolId == ToolId.laserPointer) {
      if (basePoints.length >= 3 && packedBase != null) {
        final scale = _targetScale.clamp(0.1, 5.0);
        const double toleranceMultiplier = 1.0;
        final toleranceSq =
            (0.12 * toleranceMultiplier / scale) *
            (0.12 * toleranceMultiplier / scale);
        final smooth = _getAdaptiveSpineFast(
          packedBase, 
          toleranceSq,
          segStepPx: 1.25,
          smoothing: options.smoothing,
        );
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
        final smooth = _getAdaptiveSpineFast(
          packedBase, 
          toleranceSq,
          segStepPx: 1.25,
          smoothing: options.smoothing,
        );
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
      if (strokePoints.length == 1) {
        strokePoints = [strokePoints.first, strokePoints.first];
      }
      // Tap/dot: coincident samples have no travel — collapse to one point
      // so the outline builds a true circle instead of a sliver.
      if (strokePoints.length == 2) {
        final dx = strokePoints[1].x - strokePoints[0].x;
        final dy = strokePoints[1].y - strokePoints[0].y;
        if (dx * dx + dy * dy <= 1.0) strokePoints = [strokePoints.first];
      }
      // Mature the width profile (pressure jitter only, never positions).
      strokePoints = _smoothPressureProfile(strokePoints);

      final minChord = math.max(3.0, options.size * 0.4);
      (double, double)? startTravel;
      if (strokePoints.length >= 2) {
        final a = strokePoints.first;
        // Skip micro-jitter points at pen down to get a stable chord direction
        double dx = 0, dy = 0, len = 0;
        for (int i = 1; i < strokePoints.length; i++) {
          final b = strokePoints[i];
          dx = b.x - a.x;
          dy = b.y - a.y;
          len = math.sqrt(dx * dx + dy * dy);
          if (len >= minChord) break;
        }
        if (len > 1e-6) startTravel = (dx / len, dy / len);
      }

      (double, double)? endTravel;
      if (strokePoints.length >= 2) {
        final b = strokePoints.last;
        // Skip micro-jitter points at pen up to get a stable chord direction
        double dx = 0, dy = 0, len = 0;
        for (int i = strokePoints.length - 2; i >= 0; i--) {
          final a = strokePoints[i];
          dx = b.x - a.x;
          dy = b.y - a.y;
          len = math.sqrt(dx * dx + dy * dy);
          if (len >= minChord) break;
        }
        if (len > 1e-6) endTravel = (dx / len, dy / len);
      }

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
        // Tapered nib ends keep their look, but ride jitter-stable chord
        // tangents with blended tip radii — first/last-segment tangents
        // swing with every jitter sample and misalign the nib.
        preserveLegacyTips: false,
        startTravelTangent: startTravel,
        endTravelTangent: endTravel,
      );
    }

    if (toolId == ToolId.highlighter) {
      var strokePoints = sourcePoints;
      if (strokePoints.length == 1) {
        strokePoints = [strokePoints.first, strokePoints.first];
      }
      // Single closed outline (not a triangle mesh) so translucent ink does
      // not show darker overlap artifacts. Flat vs rounded via [flatEdge].
      return _buildHighlighterOutline(
        strokePoints,
        radius: (options.size / 2) * highlighterStrokeScaleFactor,
        roundCaps: !flatEdge,
      );
    }

    if (toolId == ToolId.ballpointPen ||
        toolId == ToolId.pencil ||
        toolId == ToolId.laserPointer) {
      // Spine already smoothed above; outline only (shared with laser neon).
      return buildBallpointStyleOutline(sourcePoints, size: options.size);
    }

    final useFullOptions = quality == StrokeQuality.high;
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

  /// Advanced outline: variable-width ribbon composer over (already modeled)
  /// centerline points, with the live prediction tail appended while
  /// drawing. Mirrors Rnote's `PenPath::draw_composed` for `SmoothOptions`.
  List<Offset> _getBrushPolygon() {
    // Raw tip truth (end-of-stroke anti-lag), mirroring [_pointsForLiveRender]
    // for the brush path: appended only when it strictly extends the live end
    // (null for modeled brushes, snapped highlighter work never reaches here,
    // turns and Kalman-covered runs) and only when the brush model emitted
    // nothing past it (never hook back behind a predicted tip). Keeps live ==
    // committed on pen-up.
    final brushTail = _brushPredictionTail();
    final rawTip = options.isComplete ? null : _liveRawTipPoint(points);
    final List<PointVector> spine = [
      ...points,
      ...brushTail,
      if (rawTip != null && brushTail.isEmpty) rawTip,
    ];
    if (spine.isEmpty) return const [];
    List<PointVector> shaped = spine;
    if (brushOptions.builderType == AdvancedPenBuilderType.curved &&
        shaped.length >= 4) {
      shaped = sampleCatmullRom(shaped);
    }
    _highQualitySpine = shaped;
    try {
      return composeAdvancedOutline(
        shaped,
        strokeWidth: options.size,
        brushOptions: brushOptions,
        roundedCaps: brushOptions.lineCap == AdvancedPenLineCap.rounded,
      );
    } catch (e, st) {
      log.warning('composeAdvancedOutline crashed in getPolygon: $e', e, st);
      return shaped.map((p) => Offset(p.x, p.y)).toList();
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
        if (tanDx * tanDx + tanDy * tanDy < 1e-6) {
          // Short/jittered stroke: the scan above found nothing stable.
          // Fall back to the jitter-stable arc chord (never a raw
          // micro-segment or a bare +x default that would lay the cap
          // sideways).
          final chord = localOpeningChordTangent(
            strokePoints,
            baseSize: size / 2,
          );
          tanDx = chord.$1;
          tanDy = chord.$2;
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
        if (tanDx * tanDx + tanDy * tanDy < 1e-6) {
          final chord = localClosingChordTangent(
            strokePoints,
            baseSize: size / 2,
          );
          tanDx = chord.$1;
          tanDy = chord.$2;
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

      final double rx = size * 0.55 * pressureScale;
      final double ry = size * 0.25 * pressureScale;
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

    const int baseEllipseSegments = 6;
    // Nib caps stay circular at broad sizes instead of faceting.
    final int ellipseSegments =
        (baseEllipseSegments + (size / 2).round()).clamp(6, 20);
    final List<Offset> result = [];

    // Tip pressure blended toward its neighbor so a landing/lift spike
    // can't balloon or pinch the cap radii (the cap mouths ride these).
    double stableTipPressure(int tipIndex) {
      final p =
          (strokePoints[tipIndex].pressure ?? 0.5).clamp(0.0, 1.0);
      if (strokePoints.length < 3) return p;
      final j = tipIndex == 0 ? 1 : strokePoints.length - 2;
      final q = (strokePoints[j].pressure ?? 0.5).clamp(0.0, 1.0);
      return (p * 0.35 + q * 0.65).clamp(0.0, 1.0);
    }

    void addEllipticalCap(
      double cx,
      double cy,
      double dirX,
      double dirY,
      double pressure,
      bool isStart,
    ) {
      final dist = math.sqrt(dirX * dirX + dirY * dirY);
      if (dist < 0.001) return;
      final tx = dirX / dist;
      final ty = dirY / dist;
      final nx = -ty; 
      final ny = tx;

      final double pScale = 0.5 + pressure * 0.5;
      final double width = size * 0.5 * pScale;
      
      for (int k = 0; k <= ellipseSegments; k++) {
        final double t = k / ellipseSegments;
        
        double circleNx, circleNy;
        if (isStart) {
          // Start cap: from Left (-nx) to Right (nx), bulging backward (-tx)
          circleNx = -nx * math.cos(math.pi * t) - tx * math.sin(math.pi * t);
          circleNy = -ny * math.cos(math.pi * t) - ty * math.sin(math.pi * t);
        } else {
          // End cap: from Right (nx) to Left (-nx), bulging forward (tx)
          circleNx = nx * math.cos(math.pi * t) + tx * math.sin(math.pi * t);
          circleNy = ny * math.cos(math.pi * t) + ty * math.sin(math.pi * t);
        }
        
        // Apply Calligraphy squash
        double localNx = circleNx * cosTheta + circleNy * sinTheta;
        double localNy = -circleNx * sinTheta + circleNy * cosTheta;
        
        double rxNorm = 1.1;
        double ryNorm = 0.5;
        double scl = 1.0 / math.sqrt(rxNorm * rxNorm * localNx * localNx + ryNorm * ryNorm * localNy * localNy);
        
        double localVx = rxNorm * rxNorm * localNx * scl;
        double localVy = ryNorm * ryNorm * localNy * scl;
        
        double vx = (localVx * cosTheta - localVy * sinTheta);
        double vy = (localVx * sinTheta + localVy * cosTheta);
        
        result.add(Offset(cx + vx * width, cy + vy * width));
      }
    }

    if (len >= 2) {
      final p0 = strokePoints[0];
      final pressure0 = stableTipPressure(0);
      addEllipticalCap(p0.x, p0.y, startDirX, startDirY, pressure0, true);

      for (int i = 1; i < len; i++) result.add(rightSide[i]);

      final pLast = strokePoints[len - 1];
      final pressureN = stableTipPressure(len - 1);
      addEllipticalCap(pLast.x, pLast.y, endDirX, endDirY, pressureN, false);

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
        toolId != ToolId.pencil &&
        toolId != ToolId.advancedPen &&
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
    // Open ribbon ends for staged chunks (default closed = current look).
    bool? startCap,
    bool? endCap,
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
        // Round both sides of hairpin returns into tip bulbs; the legacy
        // single-sided bevel reads square-ish at sharp U-turns.
        dualSidedReturnJoins: true,
        startCap: startCap,
        endCap: endCap,
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
    // Open ribbon ends for staged chunks (default closed = current look).
    bool? startCap,
    bool? endCap,
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
      final smooth = _getAdaptiveSpineFast(
        packed, 
        toleranceSq,
        smoothing: 0.52,
      );
      final n = smooth.length ~/ 3;
      strokePoints = List.generate(
        n,
        (i) => PointVector(smooth[i * 3], smooth[i * 3 + 1], smooth[i * 3 + 2]),
      );
    }
    return buildBallpointStyleOutline(
      strokePoints,
      size: size,
      startCap: startCap,
      endCap: endCap,
    );
  }

  double get maxY {
    return points.isEmpty ? 0 : points.map((point) => point.y).reduce(math.max);
  }

  List<Offset> _shapeRecognitionCenterline({int maxInputPoints = 96}) {
    // The $1 recognizer resamples to 64 points internally regardless, so 96
    // input points keep full accuracy at a fraction of the resample/insert
    // cost (was 192 — pure oversampling, same scores).
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

  /// Angle-bracket reference templates, filtered once (not per recognition).
  static final List<Unistroke<DefaultUnistrokeNames>> _angleBracketTemplates =
      default$1Unistrokes
          .where(
            (u) =>
                u.name == DefaultUnistrokeNames.leftAngleBracket ||
                u.name == DefaultUnistrokeNames.rightAngleBracket,
          )
          .toList(growable: false);

  /// Line reference templates, filtered once (not per recognition).
  static final List<Unistroke<DefaultUnistrokeNames>> _lineTemplates =
      default$1Unistrokes
          .where((unistroke) => unistroke.name == DefaultUnistrokeNames.line)
          .toList(growable: false);

  RecognizedUnistroke? detectShape() {
    if (points.length < 2) return null;
    final centerline = _shapeRecognitionCenterline();

    if (centerline.length < 25 && isAngleBracketPreferred(centerline)) {
      final angleOnly = _angleBracketTemplates;
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
      overrideReferenceUnistrokes: _lineTemplates,
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
          brushOptions: brushOptions.copyWith(),
        )
        ..points.addAll(points)
        ..rotationDeg = rotationDeg
        ..flatEdge = flatEdge
        ..neon = neon
        ..paint = paint
        ..carveMask = carveMask?.clone();

  /// Freehand ink that can be rewritten as another pen (not shapes).
  bool get canConvertStrokeType =>
      this is! ShapeStroke &&
      this is! CircleStroke &&
      this is! RectangleStroke &&
      (toolId == ToolId.fountainPen ||
          toolId == ToolId.ballpointPen ||
          toolId == ToolId.calligraphyPen ||
          toolId == ToolId.advancedPen ||
          toolId == ToolId.pencil ||
          toolId == ToolId.highlighter);

  /// Same path samples/color/page, with a new tool identity and style.
  Stroke rebuildWithTool({
    required ToolId toolId,
    required bool pressureEnabled,
    required StrokeOptions options,
    required StrokePaint paint,
    required bool neon,
    required bool flatEdge,
    AdvancedPenOptions? brushOptions,
  }) {
    final rebuilt =
        Stroke(
            color: color,
            pressureEnabled: pressureEnabled,
            options: options,
            pageIndex: pageIndex,
            page: page,
            toolId: toolId,
            brushOptions:
                brushOptions ?? this.brushOptions.copyWith(),
          )
          ..points.addAll(points)
          ..rotationDeg = rotationDeg
          ..flatEdge = flatEdge
          ..neon = neon
          ..paint = paint
          ..carveMask = carveMask?.clone();
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
          brushOptions: brushOptions.copyWith(),
        )
        ..rotationDeg = rotationDeg
        ..flatEdge = flatEdge
        ..neon = neon
        ..paint = paint
        // Fragments keep the page-space carve bites, so trimming a carved
        // stroke with the area eraser does not resurrect the erased ink.
        ..carveMask = carveMask?.clone();

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
    if (toolId == ToolId.highlighter) {
      if (_targetScale != 1.0) {
        _targetScale = 1.0;
        if (options.isComplete) {
          markPolygonNeedsUpdating(preserveBounds: true);
        }
      }
      return;
    }

    if (options.isComplete) return;
    _targetScale = 1.0;
  }

  int get _predictionLiveFingerprint {
    // If the stroke is complete, we must use the last valid prediction to ensure
    // the visual fingerprint remains stable until the final geometry is fully cached.
    if (options.isComplete && _predictedTail == null) return 0;
    
    if (!options.isComplete && !stows.strokePrediction.value) return 0;
    final tail = _predictedTail;
    if (tail == null || tail.isEmpty) return 0;
    final tip = tail.last;
    return Object.hash((tip.x * 128).round(), (tip.y * 128).round());
  }

  int get visualFingerprint {
    // Cheap-pen live mesh and path tools both append the prediction tip.
    final inkUsesPredictionInPath = _allowsMotionPrediction;
    return Object.hash(
      geometricFingerprint,
      toolId == ToolId.highlighter ? flatEdge : null,
      neon,
      inkUsesPredictionInPath ? _predictionLiveFingerprint : 0,
      paint.pressureMapsToCoverage,
      carveMask?.fingerprint ?? 0,
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
  /// The Advanced pen is path-fill only (variable-width ribbon outline),
  /// like the highlighter.
  bool get canBatchSolidMesh {
    if (hasCarve) return false;
    if (toolId == ToolId.highlighter) return false;
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
      hasNonSolidPaint && !paint.usesPencilNoise;

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
  /// Replaying one baked picture per frame is far cheaper than
  /// re-rasterizing paths during scroll/zoom.
  ui.Picture? ensureSolidPathPicture({
    required bool invert,
    required Color color,
  }) {
    // Solid ink pens only (extended beyond advancedPen for the same
    // replay saving); neon renders through its own glow path.
    final isSolidInkPen =
        !neon &&
        paint.isSolid &&
        (toolId == ToolId.ballpointPen ||
            toolId == ToolId.fountainPen ||
            toolId == ToolId.calligraphyPen ||
            toolId == ToolId.advancedPen);
    if (!isSolidInkPen) return null;
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
    final anchor = paintAnchorBounds;
    final hash = Object.hash(
      visualFingerprint,
      invert,
      fallbackColor.toARGB32(),
      paint.cacheKey,
      qualityBucket,
      anchor,
    );
    if (_vectorFillPicture != null && _vectorFillPictureHash == hash) {
      return _vectorFillPicture;
    }
    final path = highQualityPath;
    // Bounds-anchored paints (gradients/textures) keep the pre-cut phase via
    // the carve anchor so shading does not jump when a stroke is split.
    final bounds = anchor ?? path.getBounds();
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

  /// Gentle 3-tap smoothing of sample pressures (positions untouched).
  /// Stylus pressure jitters sample-to-sample; without this the nib edge
  /// wobbles and looks handmade in the bad sense. Caps, tangents and the
  /// centerline are unaffected — only the width profile matures.
  /// Deterministic: identical live and committed.
  List<PointVector> _smoothPressureProfile(List<PointVector> spine) {
    if (spine.length < 3) return spine;
    final out = List<PointVector>.of(spine);
    for (var i = 1; i < spine.length - 1; i++) {
      final p0 = spine[i - 1].pressure ?? 0.5;
      final p1 = spine[i].pressure ?? 0.5;
      final p2 = spine[i + 1].pressure ?? 0.5;
      out[i] = PointVector(
        spine[i].x,
        spine[i].y,
        (p0 * 0.25 + p1 * 0.5 + p2 * 0.25).clamp(0.0, 1.0),
      );
    }
    return out;
  }


  /// Live and committed outlines use identical settings: what the user sees
  /// while drawing is exactly what stays after pen-up ("ink in stone").
  /// (Live smoothing used to be reduced here, which morphed every stroke on
  /// commit.)
  StrokeOptions _outlineOptionsForCurrentPhase(StrokeOptions base) {
    var opts = base;
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
          toolId == ToolId.pencil ||
          toolId == ToolId.fountainPen ||
          toolId == ToolId.calligraphyPen ||
          toolId == ToolId.advancedPen);

  List<ui.Vertices>? get liveIncrementalMeshes => null;

  Path? get liveTipPathFallback => null;

  /// Commit live geometry on pen-up. The live tip included the motion
  /// prediction lookahead, so it is committed as real points first: what the
  /// user saw is what stays ("ink in stone", no tip snap-back).
  void finishLiveGeometry() {
    _finishBrushModeledStroke();
    final bool isModeledBrush =
        toolId == ToolId.advancedPen &&
        brushOptions.builderType == AdvancedPenBuilderType.modeled;
    final bool isStraightLineAssist =
        toolId == ToolId.highlighter && Highlighter.straightLine.value;
    // Commit the raw lift truth when nothing else covers it: at rest the
    // Kalman tail is empty and committed samples trail the 1€ filter, so the
    // live connector (see [_liveRawTipPoint]) showed ink the point list lacks
    // — without this the stroke end would snap back by the filter lag.
    // Skipped exactly where the connector is skipped (snap assist, modeled
    // brush); those paths already end truthfully by construction.
    if (!isModeledBrush &&
        !isStraightLineAssist &&
        (_predictedTail == null || _predictedTail!.isEmpty) &&
        points.isNotEmpty &&
        _hasRawLiveTip) {
      final last = points.last;
      final dx = _rawLiveTipX - last.x;
      final dy = _rawLiveTipY - last.y;
      if (dx * dx + dy * dy > 0.5 * 0.5) {
        points.add(
          PointVector(
            _rawLiveTipX,
            _rawLiveTipY,
            _rawLiveTipPressure ?? last.pressure,
          ),
        );
        _packedPoints = null;
        _cachedAveragePressure = null;
      }
    }
    if (_predictedTail != null &&
        _predictedTail!.isNotEmpty &&
        points.isNotEmpty) {
      points.addAll(_predictedTail!);
      _predictedTail = null;
      _packedPoints = null;
      _cachedAveragePressure = null;
    }
    _clearRawLiveTip();
    options.isComplete = true;
    _clearLiveStaging();
    markPolygonNeedsUpdating();
    _enforceSampleBudget();
  }

  /// Drops the transient raw-tip anchor (stroke ended or transformed).
  void _clearRawLiveTip() {
    _rawLiveTipX = double.nan;
    _rawLiveTipY = double.nan;
    _rawLiveTipPressure = null;
    _rawLiveTipTime = null;
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

    // Path-filled tools. Pencil builds the same spine mesh as ballpoint;
    // only the paint differs (graphite grain). Neon ballpoint still builds
    // a mesh via [ensureMeshVertices] for the core.
    if ((neon && toolId == ToolId.ballpointPen) ||
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

  /// Attaches mesh arrays triangulated by the background mesh worker. The
  /// worker runs the same geometry ([solidMeshChunks]) on equivalent inputs,
  /// so attached arrays are identical to UI-built ones. A structural guard
  /// (point count, endpoints, color) rejects results for strokes edited or
  /// moved while the worker ran, instead of mispainting. Returns true when
  /// attached. Must run on the UI isolate ([ui.Vertices] construction).
  bool adoptBackgroundMesh({
    required Float32List positions,
    required Uint16List indices,
    Int32List? colors,
    required int pointCount,
    required double firstX,
    required double firstY,
    required double lastX,
    required double lastY,
  }) {
    if (points.length != pointCount || points.isEmpty) return false;
    final first = points.first;
    final last = points.last;
    if (first.x != firstX ||
        first.y != firstY ||
        last.x != lastX ||
        last.y != lastY) {
      return false;
    }
    _rawPositions = positions;
    _rawIndices = indices;
    _rawColors = colors;
    _cachedVertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      indices: indices,
      colors: colors,
    );
    final int currentHash = visualFingerprint;
    _cachedVerticesHash = currentHash;
    if (options.isComplete) {
      while (_globalVertexCache.length >= _kMaxVertexCacheSize &&
          _vertexCacheLru.isNotEmpty) {
        final evictKey = _vertexCacheLru.removeAt(0);
        _globalVertexCache.remove(evictKey);
        // Do not dispose: other strokes may still reference this mesh.
      }
      _globalVertexCache[currentHash] = _StrokeMeshData(
        _cachedVertices!,
        positions,
        indices,
        colors,
      );
      _vertexCacheLru.add(currentHash);
    }
    return true;
  }

  static void _bumpVertexCacheLru(int key) {
    _vertexCacheLru.remove(key);
    _vertexCacheLru.add(key);
  }

  static const _capSegments = 10;

  static List<Offset> _buildHighlighterOutline(
    List<PointVector> points, {
    required double radius,
    required bool roundCaps,
    // Open ribbon ends for staged chunks: butt-cut instead of caps so
    // consecutive chunks join invisibly under any blend mode.
    bool startCap = true,
    bool endCap = true,
  }) {
    if (points.length < 2) return [];

    final packed = Float32List(points.length * 3);
    for (int i = 0; i < points.length; i++) {
      packed[i * 3] = points[i].x;
      packed[i * 3 + 1] = points[i].y;
      packed[i * 3 + 2] = points[i].pressure ?? 0.5;
    }

    final startChord = _localOpeningChordTangent(packed, points.length, radius);
    final tx0 = startChord.$1;
    final ty0 = startChord.$2;
    final nx0 = -ty0;
    final ny0 = tx0;

    final endChord = _localClosingChordTangent(packed, points.length, radius);
    final txLast = endChord.$1;
    final tyLast = endChord.$2;
    final nxLast = -tyLast;
    final nyLast = txLast;

    final leftSide = <Offset>[];
    final rightSide = <Offset>[];

    for (int i = 0; i < points.length; i++) {
      double nx, ny;
      double miterLength = 1.0;

      if (i == 0) {
        nx = nx0;
        ny = ny0;
      } else if (i == points.length - 1) {
        nx = nxLast;
        ny = nyLast;
      } else {
        final dx1 = points[i].x - points[i - 1].x;
        final dy1 = points[i].y - points[i - 1].y;
        final len1 = math.sqrt(dx1 * dx1 + dy1 * dy1);
        final dx2 = points[i + 1].x - points[i].x;
        final dy2 = points[i + 1].y - points[i].y;
        final len2 = math.sqrt(dx2 * dx2 + dy2 * dy2);

        double t1x = 0, t1y = 0, t2x = 0, t2y = 0;
        if (len1 > 0) { t1x = dx1 / len1; t1y = dy1 / len1; }
        if (len2 > 0) { t2x = dx2 / len2; t2y = dy2 / len2; }

        if (len1 > 0 && len2 > 0) {
          final tx = t1x + t2x;
          final ty = t1y + t2y;
          final tLen = math.sqrt(tx * tx + ty * ty);
          if (tLen > 0) {
            nx = -ty / tLen;
            ny = tx / tLen;
          } else {
            nx = -t1y; ny = t1x;
          }

          final dot = t1x * t2x + t1y * t2y;
          if (dot > -0.9) {
            miterLength = 1.0 / math.sqrt((1.0 + dot) / 2.0);
            miterLength = miterLength.clamp(1.0, 4.0);
          }
        } else if (len1 > 0) {
          nx = -t1y; ny = t1x;
        } else {
          nx = -t2y; ny = t2x;
        }
      }

      leftSide.add(Offset(
        points[i].x + nx * radius * miterLength,
        points[i].y + ny * radius * miterLength,
      ));
      rightSide.add(Offset(
        points[i].x - nx * radius * miterLength,
        points[i].y - ny * radius * miterLength,
      ));
    }

    final result = <Offset>[];
    
    final p0 = points.first;
    if (!startCap) {
      // Butt joint: plain cross-section, no cap arc or flat-tip extension.
      result.add(leftSide.first);
    } else if (roundCaps) {
      const segments = 12;
      for (int i = 0; i <= segments; i++) {
        final angle = math.pi * (i / segments);
        final vx = math.cos(angle) * nx0 + math.sin(angle) * (-tx0);
        final vy = math.cos(angle) * ny0 + math.sin(angle) * (-ty0);
        result.add(Offset(p0.x + radius * vx, p0.y + radius * vy));
      }
    } else {
      final extendDist = radius * 0.3;
      final cornerRadius = radius * 0.2;
      
      result.add(leftSide.first);
      result.add(Offset(
        leftSide.first.dx - tx0 * (extendDist - cornerRadius),
        leftSide.first.dy - ty0 * (extendDist - cornerRadius),
      ));
      result.add(Offset(
        p0.x + nx0 * (radius - cornerRadius) - tx0 * extendDist,
        p0.y + ny0 * (radius - cornerRadius) - ty0 * extendDist,
      ));
      result.add(Offset(
        p0.x - nx0 * (radius - cornerRadius) - tx0 * extendDist,
        p0.y - ny0 * (radius - cornerRadius) - ty0 * extendDist,
      ));
      result.add(Offset(
        rightSide.first.dx - tx0 * (extendDist - cornerRadius),
        rightSide.first.dy - ty0 * (extendDist - cornerRadius),
      ));
      result.add(rightSide.first);
    }

    result.addAll(rightSide);

    final pLast = points.last;
    // Butt joint: rightSide.last is already the edge; leftSide.reversed
    // below closes it. No cap arc or flat-tip extension.
    if (endCap && roundCaps) {
      const segments = 12;
      for (int i = 0; i <= segments; i++) {
        final angle = math.pi * (i / segments);
        final vx = math.cos(angle) * (-nxLast) + math.sin(angle) * txLast;
        final vy = math.cos(angle) * (-nyLast) + math.sin(angle) * tyLast;
        result.add(Offset(pLast.x + radius * vx, pLast.y + radius * vy));
      }
    } else if (endCap) {
      final extendDist = radius * 0.3;
      final cornerRadius = radius * 0.2;
      
      result.add(rightSide.last);
      result.add(Offset(
        rightSide.last.dx + txLast * (extendDist - cornerRadius),
        rightSide.last.dy + tyLast * (extendDist - cornerRadius),
      ));
      result.add(Offset(
        pLast.x - nxLast * (radius - cornerRadius) + txLast * extendDist,
        pLast.y - nyLast * (radius - cornerRadius) + tyLast * extendDist,
      ));
      result.add(Offset(
        pLast.x + nxLast * (radius - cornerRadius) + txLast * extendDist,
        pLast.y + nyLast * (radius - cornerRadius) + tyLast * extendDist,
      ));
      result.add(Offset(
        leftSide.last.dx + txLast * (extendDist - cornerRadius),
        leftSide.last.dy + tyLast * (extendDist - cornerRadius),
      ));
      result.add(leftSide.last);
    }

    result.addAll(leftSide.reversed);

    return result;
  }

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
    final double targetArc = math.min(math.max(baseSize * 0.65, 1.0), 3.2);
    double wx = 0.0, wy = 0.0, acc = 0.0;
    double? refTx, refTy;

    for (var i = 0; i < count - 1; i++) {
      final int o0 = i * 3;
      final int o1 = (i + 1) * 3;
      final double sx = pts[o1] - pts[o0];
      final double sy = pts[o1 + 1] - pts[o0 + 1];
      final double segLen = math.sqrt(sx * sx + sy * sy);
      if (segLen <= 1e-5) continue;
      final double ux = sx / segLen;
      final double uy = sy / segLen;
      if (refTx == null) {
        refTx = ux;
        refTy = uy;
      } else if (ux * refTx + uy * refTy! < 0.88) {
        break;
      }
      final double weight = segLen / (1.0 + acc);
      wx += ux * weight;
      wy += uy * weight;
      acc += segLen;
      if (acc >= targetArc) break;
    }

    final double wLen = math.sqrt(wx * wx + wy * wy);
    if (wLen > 1e-6) return (wx / wLen, wy / wLen);

    final double ax = pts[0], ay = pts[1];
    for (var k = 1; k < count; k++) {
      final int ok = k * 3;
      final double tx = pts[ok] - ax;
      final double ty = pts[ok + 1] - ay;
      final double len = math.sqrt(tx * tx + ty * ty);
      if (len > 1e-4) return (tx / len, ty / len);
    }
    return (1.0, 0.0);
  }

  /// Distance-weighted differential tangent at the closing tip. Rejects
  /// sub-pixel lift-off wobble while stopping before earlier turns so curved
  /// stroke ends keep caps strictly collinear with the final tangent.
  static (double, double) _localClosingChordTangent(
    Float32List pts,
    int count,
    double baseSize,
  ) {
    if (count < 2) return (1.0, 0.0);
    final int lastI = count - 1;
    final double targetArc = math.min(math.max(baseSize * 0.65, 1.0), 3.2);
    double wx = 0.0, wy = 0.0, acc = 0.0;
    double? refTx, refTy;

    for (var i = lastI; i > 0; i--) {
      final int o1 = i * 3;
      final int o0 = (i - 1) * 3;
      final double sx = pts[o1] - pts[o0];
      final double sy = pts[o1 + 1] - pts[o0 + 1];
      final double segLen = math.sqrt(sx * sx + sy * sy);
      if (segLen <= 1e-5) continue;
      final double ux = sx / segLen;
      final double uy = sy / segLen;
      if (refTx == null) {
        refTx = ux;
        refTy = uy;
      } else if (ux * refTx + uy * refTy! < 0.88) {
        break;
      }
      final double weight = segLen / (1.0 + acc);
      wx += ux * weight;
      wy += uy * weight;
      acc += segLen;
      if (acc >= targetArc) break;
    }

    final double wLen = math.sqrt(wx * wx + wy * wy);
    if (wLen > 1e-6) return (wx / wLen, wy / wLen);

    final double lx = pts[lastI * 3], ly = pts[lastI * 3 + 1];
    for (var k = lastI - 1; k >= 0; k--) {
      final int ok = k * 3;
      final double tx = lx - pts[ok];
      final double ty = ly - pts[ok + 1];
      final double len = math.sqrt(tx * tx + ty * ty);
      if (len > 1e-4) return (tx / len, ty / len);
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
    ToolId toolId, {
    bool stabilizeStart = true,
    bool stabilizeEnd = true,
  }) {
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
    if (n0 > 0 && stabilizeStart) {
      final ref = s0 / n0;
      p[0] = (p[0] * startRawW + ref * (1 - startRawW)).clamp(0.05, 1.0);
    }
    if (n1 > 0 && stabilizeEnd) {
      final ref = s1 / n1;
      p[count - 1] = (p[count - 1] * endRawW + ref * (1 - endRawW)).clamp(
        0.05,
        1.0,
      );
    }
  }

  /// Pure spine-mesh triangulation (isolate-safe): same math the UI path
  /// uses, but operating only on explicit inputs with no instance state, no
  /// singletons and no GPU objects. Shared by [_generateSpineMeshLOD] (UI)
  /// and the background mesh worker — single source of truth, so worker
  /// output is byte-identical. Returns raw arrays; callers wrap Vertices.
  static ({Float32List positions, Uint16List indices, Int32List? colors})?
  buildSpineMeshArrays({
    required Float32List packedBase,
    required Float32List? predictedTail,
    required ToolId toolId,
    required bool flatEdge,
    required double size,
    required double smoothing,
    required bool simulatePressure,
    required bool isComplete,
    required bool startCap,
    required bool startTaper,
    required double? startCustomTaper,
    required bool endCap,
    required bool endTaper,
    required double? endCustomTaper,
    required bool pressureMapsToCoverage,
    required bool pressureEnabled,
    required double targetScale,
    bool openStart = false,
    bool openEnd = false,
    AdvancedPenOptions? brushOptions,
    double pathLengthOffset = 0.0,
  }) {
    final double scale = targetScale;
    final int targetCapSegments = scale < 0.35
        ? math.max(4, (_capSegments * 0.6).round())
        : _capSegments;

    const double toleranceMultiplier = 1.0;
    const double effectiveTolerance = toleranceMultiplier;
    final double splineErrorSq =
        (0.22 * effectiveTolerance / scale) *
        (0.22 * effectiveTolerance / scale);

    Float32List packed = packedBase;
    final bool liveCheapSpineMesh =
        !isComplete &&
        (toolId == ToolId.ballpointPen ||
            toolId == ToolId.pencil ||
            toolId == ToolId.fountainPen ||
            toolId == ToolId.calligraphyPen ||
            toolId == ToolId.advancedPen);
    if (liveCheapSpineMesh && predictedTail != null) {
      final src = packedBase;
      packed = Float32List(src.length + predictedTail.length);
      packed.setAll(0, src);
      packed.setAll(src.length, predictedTail);
    }

    final Float32List rawSmooth = _getAdaptiveSpineFast(
      packed,
      splineErrorSq,
      flattenTipSegments: false,
      flattenEndSegments: 0,
      segStepPx: 0.85,
      smoothing: smoothing,
    );
    final int rawCount = rawSmooth.length ~/ 3;
    if (rawCount < 2) return null;

    final bool isHighlighter = toolId == ToolId.highlighter;
    final bool isBallpoint =
        toolId == ToolId.ballpointPen || toolId == ToolId.pencil;
    final bool isCalligraphy = toolId == ToolId.calligraphyPen;
    final bool isFountain = toolId == ToolId.fountainPen;
    final bool isAdvanced = toolId == ToolId.advancedPen;

    final double baseSize = isHighlighter
        ? (size / 2.0) * highlighterStrokeScaleFactor
        : size / 2.0;

    final double minTipDist = math.min(0.75, math.max(0.2, baseSize * 0.22));
    final double minTipDistSq = minTipDist * minTipDist;

    final _Float32Builder dedupe = _Float32Builder(estimatedSize: rawCount * 3);
    double lastX = rawSmooth[0], lastY = rawSmooth[1];
    dedupe.add(lastX, lastY, rawSmooth[2]);
    for (int i = 1; i < rawCount; i++) {
      final int o = i * 3;
      final double x = rawSmooth[o],
          y = rawSmooth[o + 1],
          p = rawSmooth[o + 2];
      final double dx = x - lastX, dy = y - lastY;
      final double d2 = dx * dx + dy * dy;
      if (i == rawCount - 1) {
        if (d2 < minTipDistSq && dedupe._count >= 6) {
          dedupe._buffer[dedupe._count - 3] = x;
          dedupe._buffer[dedupe._count - 2] = y;
          dedupe._buffer[dedupe._count - 1] = p;
        } else if (d2 > 1e-6 || dedupe._count < 6) {
          dedupe.add(x, y, p);
        }
      } else if (d2 > 0.0025) {
        dedupe.add(x, y, p);
        lastX = x;
        lastY = y;
      }
    }
    Float32List smoothPoints = dedupe.finish();
    int count = smoothPoints.length ~/ 3;

    if (count > kMaxMeshSpinePoints) {
      final int stride = (count / kMaxMeshSpinePoints).ceil();
      final kept = _Float32Builder(estimatedSize: kMaxMeshSpinePoints * 3 + 3);
      for (int i = 0; i < count - 1; i += stride) {
        final int o = i * 3;
        kept.add(smoothPoints[o], smoothPoints[o + 1], smoothPoints[o + 2]);
      }
      final int o = (count - 1) * 3;
      kept.add(smoothPoints[o], smoothPoints[o + 1], smoothPoints[o + 2]);
      smoothPoints = kept.finish();
      count = smoothPoints.length ~/ 3;
    }

    if (count == 1) {
      final _Float32Builder two = _Float32Builder(estimatedSize: 6);
      two.add(smoothPoints[0], smoothPoints[1], smoothPoints[2]);
      two.add(smoothPoints[0] + 0.1, smoothPoints[1], smoothPoints[2]);
      smoothPoints = two.finish();
      count = 2;
    }
    if (count < 2) return null;

    final bool canTaper = !isCalligraphy && !isBallpoint;
    final bool highlighterWantsCaps = isHighlighter && !flatEdge;

    final double advVelThinning =
        isAdvanced && brushOptions != null ? brushOptions.velocityThinning : 0.0;
    final double advTipAngle =
        isAdvanced && brushOptions != null ? brushOptions.tipAngle : 0.0;
    final double advTipRatio =
        isAdvanced && brushOptions != null ? brushOptions.tipRatio : 1.0;
    final bool advUseTilt =
        isAdvanced && brushOptions != null ? brushOptions.useTilt : false;
    final double advDashLength =
        isAdvanced && brushOptions != null ? brushOptions.dashLength : 0.0;
    final double advDashGap =
        isAdvanced && brushOptions != null ? brushOptions.dashGap : 0.0;
    final double advAngleLag =
        isAdvanced && brushOptions != null ? brushOptions.angleLag : 0.0;
    final double advInkPooling =
        isAdvanced && brushOptions != null ? brushOptions.inkPooling : 0.0;

    final bool hasEllipticalTip =
        isCalligraphy || (isAdvanced && advTipRatio < 1.0);

    final bool advancedWantsRounded = isAdvanced &&
        brushOptions != null &&
        brushOptions.lineCap == AdvancedPenLineCap.rounded;

    final bool roundCapOverridesTaper =
        isFountain || isBallpoint || advancedWantsRounded;

    final bool generateStartCap =
        !openStart &&
        targetCapSegments > 0 &&
        (isHighlighter
            ? highlighterWantsCaps
            : isAdvanced
                ? advancedWantsRounded
                : (startCap || isBallpoint || isCalligraphy || isFountain)) &&
        (!startTaper || !canTaper || roundCapOverridesTaper);

    final bool generateEndCap =
        !openEnd &&
        targetCapSegments > 0 &&
        (isHighlighter
            ? highlighterWantsCaps
            : isAdvanced
                ? advancedWantsRounded
                : (endCap || isBallpoint || isCalligraphy || isFountain)) &&
        (!endTaper || !canTaper || roundCapOverridesTaper);

    final bool useCoverage = toolId == ToolId.pencil && pressureMapsToCoverage;

    final Float32List smoothedSpeeds = Float32List(count);
    final Float32List smoothedDistances = Float32List(count);

    final rawSpeeds = Float32List(packed.length ~/ 3);
    final rawDistances = Float32List(packed.length ~/ 3);

    double accRawDist = pathLengthOffset;
    rawDistances[0] = accRawDist;
    for (int i = 1; i < rawSpeeds.length; i++) {
      final double dx = packed[i * 3] - packed[i * 3 - 3];
      final double dy = packed[i * 3 + 1] - packed[i * 3 - 2];
      final double dist = math.sqrt(dx * dx + dy * dy);
      rawSpeeds[i] = dist;
      accRawDist += dist;
      rawDistances[i] = accRawDist;
    }
    rawSpeeds[0] = rawSpeeds.length > 1 ? rawSpeeds[1] : 0.0;

    int rawIdx = 0;
    for (int i = 0; i < count; i++) {
      final double px = smoothPoints[i * 3];
      final double py = smoothPoints[i * 3 + 1];
      double bestD = double.infinity;
      int bestIdx = rawIdx;
      for (int j = rawIdx; j < math.min(rawIdx + 15, rawSpeeds.length); j++) {
        final double dx = px - packed[j * 3];
        final double dy = py - packed[j * 3 + 1];
        final double d = dx * dx + dy * dy;
        if (d < bestD) {
          bestD = d;
          bestIdx = j;
        }
      }
      rawIdx = bestIdx;
      smoothedSpeeds[i] = math.min(1.0, rawSpeeds[rawIdx] / 12.0);

      double t = 0.0;
      if (rawIdx < rawSpeeds.length - 1) {
        double r1x = packed[rawIdx * 3];
        double r1y = packed[rawIdx * 3 + 1];
        double r2x = packed[rawIdx * 3 + 3];
        double r2y = packed[rawIdx * 3 + 4];
        double segDx = r2x - r1x;
        double segDy = r2y - r1y;
        double segLen2 = segDx * segDx + segDy * segDy;
        if (segLen2 > 1e-6) {
           t = ((px - r1x) * segDx + (py - r1y) * segDy) / segLen2;
           t = t.clamp(0.0, 1.0);
        }
      }
      smoothedDistances[i] = rawDistances[rawIdx] + t * (rawIdx + 1 < rawSpeeds.length ? rawSpeeds[rawIdx + 1] : 0.0);
    }
    
    double s = smoothedSpeeds[0];
    for (int i = 0; i < count; i++) {
      s = s * 0.7 + smoothedSpeeds[i] * 0.3;
      smoothedSpeeds[i] = s;
    }

    final bool usePressure = (simulatePressure || pressureEnabled) && toolId != ToolId.ballpointPen && toolId != ToolId.highlighter;
    final Float32List smoothedPressures = Float32List(count);
    if (usePressure && count > 0) {
      smoothedPressures[0] = smoothPoints[2];
      smoothedPressures[count - 1] = smoothPoints[(count - 1) * 3 + 2];
      for (int i = 1; i < count - 1; i++) {
        smoothedPressures[i] = smoothPoints[(i - 1) * 3 + 2] * 0.25 +
            smoothPoints[i * 3 + 2] * 0.5 +
            smoothPoints[(i + 1) * 3 + 2] * 0.25;
      }
      if (!isAdvanced) {
        _stabilizeMeshEndpointPressures(
          smoothedPressures,
          count,
          toolId,
          stabilizeStart: !openStart,
          stabilizeEnd: !openEnd,
        );
      }
    }

    var taperLenStartMesh = startCustomTaper != null ? math.max(1, (startCustomTaper / 1.25).round()) : 6;
    var taperLenEndMesh = endCustomTaper != null ? math.max(1, (endCustomTaper / 1.25).round()) : 6;
    if (toolId == ToolId.fountainPen) {
      taperLenStartMesh = 0;
      taperLenEndMesh = 0;
    }

    final Float32List finalWidths = Float32List(count);

    for (int i = 0; i < count; i++) {
      final double pressure = usePressure ? smoothedPressures[i] : 0.5;
      final double speedNorm = advVelThinning != 0.0 || advInkPooling > 0.0 ? smoothedSpeeds[i] : 0.0;

      final double clampedP = pressure.clamp(0.0, 1.0);
      final double poolOverdrive = math.max(0.0, pressure - 1.0);

      double w = baseSize;
      if (isFountain) {
        w = math.max(0.05, baseSize * (0.25 + 0.9 * clampedP * clampedP));
      } else if (isAdvanced && brushOptions != null) {
        w = math.max(0.05, brushOptions.pressureCurve.apply(baseSize * 2, clampedP) / 2);
        if (poolOverdrive > 0.0) {
          w *= 1.0 + poolOverdrive;
        }
      } else {
        w = math.max(0.1, baseSize * (0.2 + 0.8 * clampedP * 2));
      }

      if (advVelThinning != 0.0) {
        w *= (1.0 - advVelThinning * speedNorm).clamp(0.1, 4.0);
      }

      if (canTaper) {
        if (startTaper && i < taperLenStartMesh && !generateStartCap) {
          final double t = i / taperLenStartMesh;
          w *= (t * (2 - t));
        } else if (endTaper && i > count - (taperLenEndMesh + 1) && !generateEndCap) {
          final double t = (count - 1 - i) / taperLenEndMesh;
          w *= (t * (2 - t));
        }
      }

      finalWidths[i] = math.max(0.01, w);
    }

    final bool isStamped = isAdvanced && brushOptions != null && brushOptions.builderType == AdvancedPenBuilderType.stamped;
    
    if (isStamped) {
      final int maxVerts = count * 40 + 128;
      final int maxInds = count * 120 + 256;
      final Float32List positions = Float32List(maxVerts * 2);
      final Uint16List indices = Uint16List(maxInds);
      final Int32List? colorsArray = useCoverage ? Int32List(maxVerts) : null;
      int vIndex = 0, iIndex = 0;

      for (int i = 0; i < count; i++) {
        final double px = smoothPoints[i * 3];
        final double py = smoothPoints[i * 3 + 1];
        final double w = finalWidths[i];
        final double pp = usePressure ? smoothedPressures[i] : 0.5;

        final int segs = math.max(12, (w * 1.5).round().clamp(12, 32));
        final int centerIdx = vIndex ~/ 2;
        
        positions[vIndex++] = px;
        positions[vIndex++] = py;
        if (useCoverage) {
          final int c = ((0.25 + 0.75 * pp.clamp(0.0, 1.0)) * 255).toInt().clamp(0, 255) << 24 | 0x00FFFFFF;
          colorsArray![centerIdx] = c;
        }
        
        final int startIdx = vIndex ~/ 2;
        for (int j = 0; j < segs; j++) {
          final double angle = (math.pi * 2 * j) / segs;
          positions[vIndex++] = px + math.cos(angle) * w;
          positions[vIndex++] = py + math.sin(angle) * w;
          if (useCoverage) {
            final int c = ((0.25 + 0.75 * pp.clamp(0.0, 1.0)) * 255).toInt().clamp(0, 255) << 24 | 0x00FFFFFF;
            colorsArray![startIdx + j] = c;
          }
          if (j > 0) {
            indices[iIndex++] = centerIdx;
            indices[iIndex++] = startIdx + j - 1;
            indices[iIndex++] = startIdx + j;
          }
        }
        indices[iIndex++] = centerIdx;
        indices[iIndex++] = startIdx + segs - 1;
        indices[iIndex++] = startIdx;

        if (i > 0) {
           final double prevPx = smoothPoints[(i-1) * 3];
           final double prevPy = smoothPoints[(i-1) * 3 + 1];
           final double prevW = finalWidths[i-1];
           final double prevPp = usePressure ? smoothedPressures[i-1] : 0.5;
           
           final double dx = px - prevPx;
           final double dy = py - prevPy;
           final double len = math.sqrt(dx*dx + dy*dy);
           if (len > 1e-4) {
             final double angle = math.atan2(dy, dx);
             double ratio = (prevW - w) / len;
             ratio = ratio.clamp(-0.9999, 0.9999);
             final double gamma = math.asin(ratio);

             final double alphaL = angle - math.pi / 2 - gamma;
             final double alphaR = angle + math.pi / 2 + gamma;

             final double l0x = prevPx + prevW * math.cos(alphaL);
             final double l0y = prevPy + prevW * math.sin(alphaL);
             final double r0x = prevPx + prevW * math.cos(alphaR);
             final double r0y = prevPy + prevW * math.sin(alphaR);
             final double l1x = px + w * math.cos(alphaL);
             final double l1y = py + w * math.sin(alphaL);
             final double r1x = px + w * math.cos(alphaR);
             final double r1y = py + w * math.sin(alphaR);
             
             final int idx = vIndex ~/ 2;
             positions[vIndex++] = l0x; positions[vIndex++] = l0y;
             positions[vIndex++] = r0x; positions[vIndex++] = r0y;
             positions[vIndex++] = l1x; positions[vIndex++] = l1y;
             positions[vIndex++] = r1x; positions[vIndex++] = r1y;
             
             if (useCoverage) {
               final int cPrev = ((0.25 + 0.75 * prevPp.clamp(0.0, 1.0)) * 255).toInt().clamp(0, 255) << 24 | 0x00FFFFFF;
               final int cCur = ((0.25 + 0.75 * pp.clamp(0.0, 1.0)) * 255).toInt().clamp(0, 255) << 24 | 0x00FFFFFF;
               colorsArray![idx] = cPrev; colorsArray[idx+1] = cPrev;
               colorsArray[idx+2] = cCur; colorsArray[idx+3] = cCur;
             }
             
             indices[iIndex++] = idx; indices[iIndex++] = idx+1; indices[iIndex++] = idx+2;
             indices[iIndex++] = idx+1; indices[iIndex++] = idx+3; indices[iIndex++] = idx+2;
           }
        }
      }
      final Float32List finalPositions = Float32List.sublistView(positions, 0, vIndex);
      final Uint16List finalIndices = Uint16List.sublistView(indices, 0, iIndex);
      final Int32List? finalColors = useCoverage ? Int32List.sublistView(colorsArray!, 0, vIndex~/2) : null;
      return (positions: finalPositions, indices: finalIndices, colors: finalColors);
    }

    final int maxPairs = count * 2 + targetCapSegments * 8 + 64;
    final Float32List positions = Float32List(maxPairs * 4);
    final Uint16List indices = Uint16List(maxPairs * 6);
    final Int32List? colorsArray = useCoverage ? Int32List(maxPairs * 2) : null;
    int vIndex = 0, iIndex = 0, pairCount = 0;

    final Float32List smoothedAngles = Float32List(count);
    double currentAngle = advTipAngle;
    if (isAdvanced && advUseTilt && count > 0) {
      for (int i = 0; i < count; i++) {
        double tdx = 0, tdy = 0;
        if (i < count - 1) {
          tdx = smoothPoints[i * 3 + 3] - smoothPoints[i * 3];
          tdy = smoothPoints[i * 3 + 4] - smoothPoints[i * 3 + 1];
        } else if (i > 0) {
          tdx = smoothPoints[i * 3] - smoothPoints[i * 3 - 3];
          tdy = smoothPoints[i * 3 + 1] - smoothPoints[i * 3 - 2];
        }
        double targetAngle = currentAngle;
        if (tdx * tdx + tdy * tdy > 1e-6) {
          targetAngle = math.atan2(tdy, tdx);
        }
        if (i == 0) currentAngle = targetAngle;

        if (advAngleLag > 0.0) {
          double diff = targetAngle - currentAngle;
          while (diff > math.pi) diff -= 2 * math.pi;
          while (diff < -math.pi) diff += 2 * math.pi;
          final double lerpFactor = (1.0 - advAngleLag * 0.9).clamp(0.01, 1.0);
          currentAngle += diff * lerpFactor;
        } else {
          currentAngle = targetAngle;
        }
        smoothedAngles[i] = currentAngle;
      }
    } else {
      for (int i = 0; i < count; i++) {
        smoothedAngles[i] = advTipAngle;
      }
    }

    (double, double) transformTip(double dx, double dy, double angle) {
      if (!hasEllipticalTip) return (dx, dy);
      double rxNorm = 1.0, ryNorm = 1.0, cosA = 1.0, sinA = 0.0;

      if (isCalligraphy) {
        rxNorm = 1.1;
        ryNorm = 0.5;
        cosA = math.cos(-40 * math.pi / 180);
        sinA = math.sin(-40 * math.pi / 180);
      } else {
        rxNorm = 1.0;
        ryNorm = advTipRatio.clamp(0.01, 1.0);
        cosA = math.cos(angle);
        sinA = math.sin(angle);
      }

      final double len = math.sqrt(dx * dx + dy * dy);
      if (len < 0.0001) return (0.0, 0.0);
      final double dirX = dx / len, dirY = dy / len;
      final double localNx = dirX * cosA + dirY * sinA;
      final double localNy = -dirX * sinA + dirY * cosA;
      final double scl = 1.0 /
          math.sqrt(
            rxNorm * rxNorm * localNx * localNx +
                ryNorm * ryNorm * localNy * localNy,
          );
      final double localVx = rxNorm * rxNorm * localNx * scl;
      final double localVy = ryNorm * ryNorm * localNy * scl;
      return (
        (localVx * cosA - localVy * sinA) * len,
        (localVx * sinA + localVy * cosA) * len,
      );
    }

    final List<bool> pairActive = List.filled(maxPairs, true);
    bool inDash = true;

    void addVertexPair(
      double px,
      double py,
      double nx,
      double ny,
      double w,
      double pressure,
      double angle,
    ) {
      if (pairCount >= maxPairs) return;
      double vx = nx, vy = ny;
      if (hasEllipticalTip) {
        final t = transformTip(nx, ny, angle);
        vx = t.$1;
        vy = t.$2;
      }

      pairActive[pairCount] = inDash;

      positions[vIndex++] = px + vx * w;
      positions[vIndex++] = py + vy * w;
      positions[vIndex++] = px - vx * w;
      positions[vIndex++] = py - vy * w;

      if (useCoverage) {
        final double cov = 0.25 + 0.75 * pressure.clamp(0.0, 1.0);
        final int alpha = (cov * 255).clamp(0, 255).toInt();
        final int c = (alpha << 24) | 0x00FFFFFF;
        colorsArray![pairCount * 2] = c;
        colorsArray[pairCount * 2 + 1] = c;
      }

      pairCount++;
    }

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
      final double outwardDx = -startTx;
      final double outwardDy = -startTy;
      final double nx = -startTy, ny = startTx;

      final double width = finalWidths[0];

      double cOutX = outwardDx;
      double cOutY = outwardDy;
      if (hasEllipticalTip) {
        final tOut = transformTip(outwardDx, outwardDy, smoothedAngles[0]);
        cOutX = tOut.$1;
        cOutY = tOut.$2;
      } else if (isFountain) {
        cOutX *= 2.2;
        cOutY *= 2.2;
      }

      final int steps = isBallpoint ? targetCapSegments * 2 : targetCapSegments;
      for (int i = steps; i > 0; i--) {
        final double angleStep = (math.pi / 2) * (i / steps);
        addVertexPair(
          p0x + cOutX * (math.sin(angleStep) * width),
          p0y + cOutY * (math.sin(angleStep) * width),
          nx,
          ny,
          math.cos(angleStep) * width,
          p0p,
          smoothedAngles[0],
        );
      }
    }

    for (int i = 0; i < count; i++) {
      if (advDashLength > 0.0 || advDashGap > 0.0) {
        final double cycle = advDashLength + advDashGap;
        if (cycle > 0) {
          inDash = (smoothedDistances[i] % cycle) <= advDashLength;
        }
      }
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
        final double segLen = math.sqrt(fdx * fdx + fdy * fdy);
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
        final double segLen = math.sqrt(bdx * bdx + bdy * bdy);
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

      final double dx = fdx * 0.5 + bdx * 0.5, dy = fdy * 0.5 + bdy * 0.5;
      final double lenM = math.sqrt(dx * dx + dy * dy);
      double nx = 0, ny = 0;
      if (lenM > 0.0001) {
        nx = -dy / lenM;
        ny = dx / lenM;
      } else {
        nx = nBx;
        ny = nBy;
      }

      final double width = finalWidths[i];

      final double dotMiter = (lenB > 0.0001 && lenF > 0.0001)
          ? (bdx * fdx + bdy * fdy) / (lenB * lenF)
          : 1.0;

      double miterLength =
          1.0 / math.sqrt(math.max(0.01, (1.0 + dotMiter) / 2.0));
      miterLength = miterLength.clamp(1.0, 2.5);

      if (dotMiter < 0.85 &&
          targetCapSegments > 0 &&
          lenB > 0.01 &&
          lenF > 0.01) {
        int segments = (targetCapSegments * (1.2 - dotMiter)).ceil().clamp(
          2,
          _capSegments,
        );
        final int endReserve = generateEndCap
            ? (isBallpoint ? targetCapSegments * 2 : targetCapSegments) + 1
            : 1;
        final int pointsLeft = count - 1 - i;
        final int remaining =
            maxPairs - pairCount - endReserve - pointsLeft;
        if (remaining <= 1) {
          addVertexPair(
            px,
            py,
            nx * miterLength,
            ny * miterLength,
            width,
            pp,
            smoothedAngles[i],
          );
        } else {
          if (segments > remaining - 1) segments = remaining - 1;
          final double angleB = math.atan2(nBy, nBx);
          final double angleF = math.atan2(nFy, nFx);
          double diff = angleF - angleB;
          while (diff > math.pi) diff -= 2 * math.pi;
          while (diff < -math.pi) diff += 2 * math.pi;

          for (int step = 0; step <= segments; step++) {
            final double t = step / segments;
            final double a = angleB + diff * t;
            addVertexPair(
              px,
              py,
              math.cos(a),
              math.sin(a),
              width,
              pp,
              smoothedAngles[i],
            );
          }
        }
      } else {
        addVertexPair(
          px,
          py,
          nx * miterLength,
          ny * miterLength,
          width,
          pp,
          smoothedAngles[i],
        );
      }
    }

    if (generateEndCap) {
      final int lastO = (count - 1) * 3;
      final double pLx = smoothPoints[lastO], pLy = smoothPoints[lastO + 1];
      final double pLp = usePressure ? smoothedPressures[count - 1] : 0.5;
      final double endDx = endTx;
      final double endDy = endTy;
      final double nx = -endDy, ny = endDx;

      final double width = finalWidths[count - 1];

      double cEndX = endDx;
      double cEndY = endDy;
      if (hasEllipticalTip) {
        final tEnd = transformTip(endDx, endDy, smoothedAngles[count - 1]);
        cEndX = tEnd.$1;
        cEndY = tEnd.$2;
      } else if (isFountain) {
        cEndX *= 2.2;
        cEndY *= 2.2;
      }

      final int steps = isBallpoint ? targetCapSegments * 2 : targetCapSegments;
      for (int i = 1; i <= steps; i++) {
        final double angleStep = (math.pi / 2) * (i / steps);
        addVertexPair(
          pLx + cEndX * (math.sin(angleStep) * width),
          pLy + cEndY * (math.sin(angleStep) * width),
          nx,
          ny,
          math.cos(angleStep) * width,
          pLp,
          smoothedAngles[count - 1],
        );
      }
    }

    for (int q = 0; q < pairCount - 1; q++) {
      if (pairActive[q] && pairActive[q + 1]) {
        final int A = q * 2, B = (q + 1) * 2;
        indices[iIndex++] = A + 0;
        indices[iIndex++] = A + 1;
        indices[iIndex++] = B + 0;
        indices[iIndex++] = A + 1;
        indices[iIndex++] = B + 1;
        indices[iIndex++] = B + 0;
      }
    }

    final Float32List finalPositions = Float32List.sublistView(
      positions,
      0,
      vIndex,
    );
    final Uint16List finalIndices = Uint16List.sublistView(indices, 0, iIndex);
    assert(
      pairCount * 2 <= kMaxMeshVertices,
      'mesh vertex overflow: ${pairCount * 2} > $kMaxMeshVertices',
    );
    final Int32List? finalColors = useCoverage
        ? Int32List.sublistView(colorsArray!, 0, pairCount * 2)
        : null;
    return (
      positions: finalPositions,
      indices: finalIndices,
      colors: finalColors,
    );
  }

  _StrokeMeshData? _generateSpineMeshLOD() {
    if (points.length < 2) return null;
    _ensurePackedPoints();
    if (_packedPoints == null || _packedPoints!.length < 6) return null;
    Float32List? tail;
    // Live tip truth (end-of-stroke anti-lag): rides at the END of the Kalman
    // tail — same [..., kalman..., raw] order as the polygon live path, so
    // mesh and path renders agree exactly. [_liveRawTipPoint] returns null
    // unless the raw truth strictly extends the live end (no hooks), and for
    // committed strokes (or when Kalman already covers) nothing changes.
    PointVector? liveRawTip;
    if (_usesLiveCheapSpineMesh) {
      liveRawTip = _liveRawTipPoint(points);
    }
    final bool useAdvancedPred = toolId == ToolId.advancedPen && brushOptions.builderType == AdvancedPenBuilderType.modeled;
    final List<PointVector> predList = useAdvancedPred ? _brushPredictionTail() : (_predictedTail ?? const []);

    if (_usesLiveCheapSpineMesh && predList.isNotEmpty) {
      final extra = liveRawTip == null ? 0 : 1;
      tail = Float32List((predList.length + extra) * 3);
      for (int i = 0; i < predList.length; i++) {
        tail[i * 3] = predList[i].x;
        tail[i * 3 + 1] = predList[i].y;
        tail[i * 3 + 2] = predList[i].pressure ?? 0.5;
      }
      if (liveRawTip != null) {
        final o = predList.length * 3;
        tail[o] = liveRawTip.x;
        tail[o + 1] = liveRawTip.y;
        tail[o + 2] = liveRawTip.pressure ?? 0.5;
      }
    } else if (_usesLiveCheapSpineMesh && liveRawTip != null) {
      tail = Float32List(3);
      tail[0] = liveRawTip.x;
      tail[1] = liveRawTip.y;
      tail[2] = liveRawTip.pressure ?? 0.5;
    }
    final arrays = Stroke.buildSpineMeshArrays(
      packedBase: _packedPoints!,
      predictedTail: tail,
      toolId: toolId,
      flatEdge: flatEdge,
      size: options.size,
      smoothing: options.smoothing,
      simulatePressure: options.simulatePressure,
      isComplete: options.isComplete,
      startCap: options.start.cap,
      startTaper: options.start.taperEnabled,
      startCustomTaper: options.start.customTaper,
      endCap: options.end.cap,
      endTaper: options.end.taperEnabled,
      endCustomTaper: options.end.customTaper,
      pressureMapsToCoverage: paint.pressureMapsToCoverage,
      pressureEnabled: pressureEnabled,
      targetScale: _targetScale,
      brushOptions: brushOptions,
    );
    if (arrays == null) return null;
    final ui.Vertices verts = ui.Vertices.raw(
      ui.VertexMode.triangles,
      arrays.positions,
      indices: arrays.indices,
      colors: arrays.colors,
    );
    return _StrokeMeshData(
      verts,
      arrays.positions,
      arrays.indices,
      arrays.colors,
    );
  }


  static Float32List _getAdaptiveSpineFast(
    Float32List input,
    double toleranceSq, {
    bool flattenTipSegments = false,
    int flattenEndSegments = 2,
    double segStepPx = 2.5,
    double smoothing = 0.0,
    int maxOutputPoints = kMaxSplineOutputPoints,
    int trimLeadPoints = 0,
    int trimTailPoints = 0,
  }) {
    final int rawN = input.length ~/ 3;
    if (rawN < 3) return input;
    // Live staging context: smooth [trimLeadPoints] input samples before and
    // [trimTailPoints] after the emitted range so the Catmull-Rom window sees
    // the same neighbors as the committed all-points build. The spline
    // extrapolates phantom endpoints for its first/last segment, so a range
    // without context bends by a hair at its ends; staging feeds every chunk
    // cut its true neighbors, which makes the rendered range identical to the
    // committed outline (no sliver sticking out of a cut).
    final int keepFrom = trimLeadPoints.clamp(0, rawN - 1);
    final int keepTo = (rawN - 1 - trimTailPoints).clamp(keepFrom, rawN - 1);
    final bool hasTailContext = keepTo < rawN - 1;

    // Filter out sub-pixel sensor duplicates and lift-off micro-wiggles
    // without shrinking loops or pulling penultimate points off the curve.
    final _Float32Builder cleanBuilder = _Float32Builder(estimatedSize: input.length);
    // Input index of each kept sample (parallel to cleanBuilder); used to skip
    // the context samples when emitting. Only tracked when context exists.
    final bool needKeptIdx = trimLeadPoints > 0 || trimTailPoints > 0;
    final List<int>? keptIdx = needKeptIdx ? [0] : null;
    double prevX = input[0], prevY = input[1];
    cleanBuilder.add(prevX, prevY, input[2]);
    for (int i = 1; i < rawN; i++) {
      final int o = i * 3;
      final double x = input[o], y = input[o + 1], p = input[o + 2];
      final double dx = x - prevX, dy = y - prevY;
      final double d2 = dx * dx + dy * dy;
      if (i == rawN - 1 && !hasTailContext) {
        if (d2 < 0.25 && cleanBuilder._count >= 6) {
          cleanBuilder._buffer[cleanBuilder._count - 3] = x;
          cleanBuilder._buffer[cleanBuilder._count - 2] = y;
          cleanBuilder._buffer[cleanBuilder._count - 1] = p;
          if (keptIdx != null) keptIdx[keptIdx.length - 1] = i;
        } else if (d2 > 1e-6 || cleanBuilder._count < 6) {
          cleanBuilder.add(x, y, p);
          keptIdx?.add(i);
        }
      } else if (d2 >= 0.04) {
        cleanBuilder.add(x, y, p);
        keptIdx?.add(i);
        prevX = x;
        prevY = y;
      }
    }

    final Float32List pts = cleanBuilder.finish();
    final int n = pts.length ~/ 3;
    if (n < 3) return pts;

    // Emission window over the cleaned list: context samples are smoothed (so
    // the real segments see their true neighbors) but never emitted.
    int firstKept = 0;
    int lastKept = n - 1;
    if (keptIdx != null) {
      while (firstKept < n - 1 && keptIdx[firstKept] < keepFrom) {
        firstKept++;
      }
      while (lastKept > firstKept && keptIdx[lastKept] > keepTo) {
        lastKept--;
      }
      if (firstKept >= lastKept) {
        firstKept = 0;
        lastKept = n - 1;
      }
    }

    final _Float32Builder out = _Float32Builder(estimatedSize: n * 12);
    out.add(pts[firstKept * 3], pts[firstKept * 3 + 1], pts[firstKept * 3 + 2]);
    final double stepPx = segStepPx.clamp(0.6, 8.0);
    final int endFlatten = flattenEndSegments.clamp(1, 8);

    for (int i = firstKept; i < lastKept; i++) {
      final int i1 = i * 3;
      final int i2 = (i + 1) * 3;

      final double p1x = pts[i1], p1y = pts[i1 + 1], p1p = pts[i1 + 2];
      final double p2x = pts[i2], p2y = pts[i2 + 1], p2p = pts[i2 + 2];

      // Extrapolate phantom endpoints collinearly so the first/last segments
      // never suffer an S-curve inflection at the cap.
      final double p0x = i > 0 ? pts[(i - 1) * 3] : (2 * p1x - p2x);
      final double p0y = i > 0 ? pts[(i - 1) * 3 + 1] : (2 * p1y - p2y);
      final double p3x = i + 2 < n ? pts[(i + 2) * 3] : (2 * p2x - p1x);
      final double p3y = i + 2 < n ? pts[(i + 2) * 3 + 1] : (2 * p2y - p1y);

      final double dx = p2x - p1x;
      final double dy = p2y - p1y;
      final double segDist = math.sqrt(dx * dx + dy * dy);

      final bool flattenThis =
          flattenTipSegments && (i == 0 || i >= n - 1 - endFlatten);

      // Output budget: a teleport gap (dropped frames during lag) must not
      // explode into hundreds of interpolated samples — link raw samples
      // directly once exhausted. The adaptive spline still reconstructs the
      // curve across the gap from the true samples.
      if (out._count ~/ 3 >= maxOutputPoints) {
        out.add(p2x, p2y, p2p);
        continue;
      }

      final int steps = flattenThis
          ? 1
          : (segDist / stepPx).ceil().clamp(2, 512);

      if (steps > 1 && segDist > 1e-5) {
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

  /// Evaluates a Centripetal Catmull-Rom (alpha = 0.5) Hermite point at [t].
  /// Mathematically prevents overshoots, cusps, and backward hooks when
  /// stylus sample spacing decelerates rapidly at stroke ends.
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
    final double d01 = math.sqrt(
      (p1x - p0x) * (p1x - p0x) + (p1y - p0y) * (p1y - p0y),
    );
    final double d12 = math.sqrt(
      (p2x - p1x) * (p2x - p1x) + (p2y - p1y) * (p2y - p1y),
    );
    final double d23 = math.sqrt(
      (p3x - p2x) * (p3x - p2x) + (p3y - p2y) * (p3y - p2y),
    );

    final double dt0 = math.max(1e-3, math.sqrt(d01));
    final double dt1 = math.max(1e-3, math.sqrt(d12));
    final double dt2 = math.max(1e-3, math.sqrt(d23));

    final double vx01 = (p1x - p0x) / dt0;
    final double vy01 = (p1y - p0y) / dt0;
    final double vx12 = (p2x - p1x) / dt1;
    final double vy12 = (p2y - p1y) / dt1;
    final double vx23 = (p3x - p2x) / dt2;
    final double vy23 = (p3y - p2y) / dt2;

    double m1x = dt1 * ((dt1 * vx01 + dt0 * vx12) / (dt0 + dt1));
    double m1y = dt1 * ((dt1 * vy01 + dt0 * vy12) / (dt0 + dt1));
    double m2x = dt1 * ((dt2 * vx12 + dt1 * vx23) / (dt1 + dt2));
    double m2y = dt1 * ((dt2 * vy12 + dt1 * vy23) / (dt1 + dt2));

    final double maxLen = d12 * 2.5;
    final double len1 = math.sqrt(m1x * m1x + m1y * m1y);
    if (len1 > maxLen && len1 > 1e-9) {
      final double s = maxLen / len1;
      m1x *= s;
      m1y *= s;
    }
    final double len2 = math.sqrt(m2x * m2x + m2y * m2y);
    if (len2 > maxLen && len2 > 1e-9) {
      final double s = maxLen / len2;
      m2x *= s;
      m2y *= s;
    }

    final double t2 = t * t;
    final double t3 = t2 * t;
    final double h00 = 2 * t3 - 3 * t2 + 1;
    final double h10 = t3 - 2 * t2 + t;
    final double h01 = -2 * t3 + 3 * t2;
    final double h11 = t3 - t2;

    final double x = h00 * p1x + h10 * m1x + h01 * p2x + h11 * m2x;
    final double y = h00 * p1y + h10 * m1y + h01 * p2y + h11 * m2y;
    final double pressure = p1p + (p2p - p1p) * t;
    out.add(x, y, pressure);
  }

  List<PointVector> _getSmoothSpine(List<PointVector> inputPoints) {
    if (inputPoints.length < 3) return inputPoints;
    return sampleCatmullRom(inputPoints, samplesPerSegment: 6);
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
  _StrokeMeshData(this.vertices, this.positions, this.indices, [this.colors]);
}

/// One baked live-staging chunk: geometry over raw points
/// [startPoint]..[endPoint] (inclusive, joints shared with neighbors),
/// built once with committed pipeline settings and never rebuilt.
/// [mesh] serves mesh families, pencil grain mask and neon core;
/// [path] serves advanced/highlighter/pencil/neon-glow outlines;
/// [auxPath] serves the neon white core.
class _LiveStageChunk {
  _LiveStageChunk({
    required this.startPoint,
    required this.endPoint,
    required this.firstX,
    required this.firstY,
    required this.lastX,
    required this.lastY,
    this.mesh,
    this.path,
    this.auxPath,
    this.bounds,
  });

  final int startPoint;
  final int endPoint;
  final double firstX;
  final double firstY;
  final double lastX;
  final double lastY;
  ui.Vertices? mesh;
  Path? path;
  Path? auxPath;
  Rect? bounds;
}

/// Painter-facing view of one staged chunk (frozen or live tail).
class LiveStagedChunkView {
  const LiveStagedChunkView({this.mesh, this.path, this.auxPath, this.bounds});

  final ui.Vertices? mesh;
  final Path? path;
  final Path? auxPath;
  final Rect? bounds;
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
  final int maxDepth;
  final int depth;
  final List<T> items = [];
  final Rect Function(T item) _getBounds;

  bool divided = false;
  QuadTree<T>? northeast;
  QuadTree<T>? northwest;
  QuadTree<T>? southeast;
  QuadTree<T>? southwest;

  QuadTree(
    this.boundary, {
    this.capacity = 10,
    this.maxDepth = 7,
    this.depth = 0,
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
    return _insert(item, _getBounds(item));
  }

  bool _fitsIn(Rect nodeRect, Rect itemBounds) {
    return nodeRect.left <= itemBounds.left &&
           nodeRect.right >= itemBounds.right &&
           nodeRect.top <= itemBounds.top &&
           nodeRect.bottom >= itemBounds.bottom;
  }

  bool _insert(T item, Rect itemBounds) {
    if (!boundary.overlaps(itemBounds)) return false;

    if (divided) {
      if (_fitsIn(northeast!.boundary, itemBounds)) return northeast!._insert(item, itemBounds);
      if (_fitsIn(northwest!.boundary, itemBounds)) return northwest!._insert(item, itemBounds);
      if (_fitsIn(southeast!.boundary, itemBounds)) return southeast!._insert(item, itemBounds);
      if (_fitsIn(southwest!.boundary, itemBounds)) return southwest!._insert(item, itemBounds);
      
      // Does not fit completely in any child, so it straddles boundaries. Store it here.
      items.add(item);
      return true;
    }

    items.add(item);

    if (items.length > capacity && depth < maxDepth) {
      subdivide();
      final oldItems = List<T>.of(items);
      items.clear();
      for (final oldItem in oldItems) {
        final ob = _getBounds(oldItem);
        // Re-insert triggers the fitsIn logic above
        _insert(oldItem, ob);
      }
    }
    return true;
  }

  void subdivide() {
    final x = boundary.left;
    final y = boundary.top;
    final w = boundary.width / 2;
    final h = boundary.height / 2;

    northeast = QuadTree(Rect.fromLTWH(x + w, y, w, h), capacity: capacity, maxDepth: maxDepth, depth: depth + 1, getBounds: _getBounds);
    northwest = QuadTree(Rect.fromLTWH(x, y, w, h), capacity: capacity, maxDepth: maxDepth, depth: depth + 1, getBounds: _getBounds);
    southeast = QuadTree(Rect.fromLTWH(x + w, y + h, w, h), capacity: capacity, maxDepth: maxDepth, depth: depth + 1, getBounds: _getBounds);
    southwest = QuadTree(Rect.fromLTWH(x, y + h, w, h), capacity: capacity, maxDepth: maxDepth, depth: depth + 1, getBounds: _getBounds);
    divided = true;
  }

  List<T> query(Rect range, [List<T>? found]) {
    found ??= [];

    if (!boundary.overlaps(range)) return found;

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      if (range.overlaps(_getBounds(item))) {
        found.add(item);
      }
    }

    if (divided) {
      northeast!.query(range, found);
      northwest!.query(range, found);
      southeast!.query(range, found);
      southwest!.query(range, found);
    }

    return found;
  }

  bool remove(T item) {
    return _remove(item, _getBounds(item));
  }

  bool _remove(T item, Rect itemBounds) {
    if (!boundary.overlaps(itemBounds)) return false;

    if (items.remove(item)) return true;

    if (divided) {
      if (_fitsIn(northeast!.boundary, itemBounds)) return northeast!._remove(item, itemBounds);
      if (_fitsIn(northwest!.boundary, itemBounds)) return northwest!._remove(item, itemBounds);
      if (_fitsIn(southeast!.boundary, itemBounds)) return southeast!._remove(item, itemBounds);
      if (_fitsIn(southwest!.boundary, itemBounds)) return southwest!._remove(item, itemBounds);
    }

    return false;
  }
}

class SpatialGrid {
  SpatialGrid({this.cellSize = 100.0});

  final double cellSize;
  final _grid = <int, List<int>>{};
  static final _queryBuffer = <int>[];
  static final _seenBuffer = <int>{};

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
