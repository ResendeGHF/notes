// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_shape_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

import 'package:saber/data/tools/_tool.dart';

enum EraserMode { stroke, area }

class EraserResult {
  EraserResult({
    required this.removed,
    required this.added,
    this.areaWorkRemaining = false,
  });
  final List<Stroke> removed;
  final List<Stroke> added;

  final bool areaWorkRemaining;
}

class _EraserLimits {
  static const int maxLocalSplitPoints = 4096;
}

class Eraser extends Tool {
  Eraser({double size = 5, this.mode = EraserMode.stroke})
      : size = size.clamp(sizeMin, 25.0) {
    _rebuildCached();
  }

  static Eraser currentEraser = Eraser();

  double size;
  EraserMode mode;

  void _rebuildCached() {}

  static const double sizeMin = 0.5;

  set updateSize(double newSize) {
    size = newSize.clamp(sizeMin, 25.0);
    _rebuildCached();
  }

  set updateMode(EraserMode newMode) {
    mode = newMode;
  }

  final Set<Stroke> _erased = {};
  final Set<Stroke> _added = {};

  final Set<Stroke> _toDispose = {};
  final List<Stroke> _candidateBuffer = [];
  Uint8List _splitMaskScratch = Uint8List(0);
  final List<_IndexRange> _rangeScratch = [];
  Offset? _lastAppliedPos;
  final Map<Stroke, _AreaSession> _areaSessions = {};
  final Map<Stroke, _AreaSession> _areaFragmentSessions = {};
  final Set<Stroke> _areaRemovedOriginals = {};

  static const double _minRadius = 1e-3;

  static const double _cutMargin = 0.0;

  static const double _areaStepFactor = 0.45;

  @override
  ToolId get toolId => ToolId.eraser;

  bool shouldApplyAt(Offset position) {
    if (mode != EraserMode.area) {
      _lastAppliedPos = position;
      return true;
    }
    final last = _lastAppliedPos;
    if (last == null) {
      _lastAppliedPos = position;
      return true;
    }
    final step = (size * _areaStepFactor).clamp(1.0, 24.0);
    final dx = position.dx - last.dx;
    final dy = position.dy - last.dy;
    if (dx * dx + dy * dy < step * step) return false;
    _lastAppliedPos = position;
    return true;
  }

  EraserResult apply(
    Offset eraserPos,
    List<Stroke> strokes, {
    QuadTree<Stroke>? spatialIndex,
    double? scale,

    int? areaTimeBudgetMs,
  }) {
    final removed = <Stroke>[];
    final added = <Stroke>[];

    final removedInThisApply = <Stroke>{};

    final double sizeInPage = size.clamp(_minRadius, 1e6);
    final searchRadius = sizeInPage + 30.0;
    final searchRect = Rect.fromCenter(
      center: eraserPos,
      width: searchRadius * 2,
      height: searchRadius * 2,
    );

    final List<Stroke> candidates;
    if (spatialIndex != null) {
      candidates = spatialIndex.query(searchRect, _candidateBuffer..clear());
    } else {
      candidates = strokes;
    }

    final hitTestEraserSize = mode == EraserMode.area
        ? sizeInPage + _cutMargin
        : sizeInPage;

    for (final stroke in candidates) {

      if (mode == EraserMode.stroke) {
        if (!_shouldStrokeBeErased(eraserPos, stroke, hitTestEraserSize))
          continue;
        removed.add(stroke);
        removedInThisApply.add(stroke);
        _markStrokeRemoved(stroke);
        continue;
      }
    }

    if (mode != EraserMode.area) {
      return EraserResult(removed: removed, added: added);
    }

    final Stopwatch? budget =
        areaTimeBudgetMs != null ? (Stopwatch()..start()) : null;
    var areaWorkRemaining = false;

    bool overBudget() {
      if (budget == null) return false;
      return budget.elapsedMilliseconds >= areaTimeBudgetMs!;
    }

    final processedSessions = <_AreaSession>{};
    for (final candidate in candidates) {
      if (removedInThisApply.contains(candidate)) continue;
      final existingSession =
          _areaSessions[candidate] ?? _areaFragmentSessions[candidate];
      if (existingSession != null) {
        if (!processedSessions.add(existingSession)) continue;
        if (overBudget()) {
          areaWorkRemaining = true;
          break;
        }
        final sessionDone = _applyAreaToSession(
          session: existingSession,
          eraserPos: eraserPos,
          sizeInPage: sizeInPage,
          removed: removed,
          removedInThisApply: removedInThisApply,
          added: added,
          isOverBudget: budget != null ? overBudget : null,
        );
        if (!sessionDone) {
          areaWorkRemaining = true;
          break;
        }
        continue;
      }
      if (_areaRemovedOriginals.contains(candidate)) continue;

      final strokeHalfWidth = candidate.options.size / 2.0;
      final hitRadius = (sizeInPage + strokeHalfWidth).clamp(_minRadius, 1e6);
      final hitRect = Rect.fromCircle(center: eraserPos, radius: hitRadius);
      if (!candidate.bounds.overlaps(hitRect)) continue;

      final points = candidate.pointsForEraser;
      if (points.isEmpty) {
        if (_shouldStrokeBeErased(
          eraserPos,
          candidate,
          sizeInPage + _cutMargin,
        )) {
          removed.add(candidate);
          removedInThisApply.add(candidate);
          _markStrokeRemoved(candidate);
        }
        continue;
      }

      if (overBudget()) {
        areaWorkRemaining = true;
        break;
      }

      final session = _AreaSession(
        original: candidate,
        originalPoints: points,
        currentSegments: [
          _AreaSegment(start: 0, end: points.length - 1, stroke: null),
        ],
      );
      _areaSessions[candidate] = session;
      processedSessions.add(session);
      final sessionDone = _applyAreaToSession(
        session: session,
        eraserPos: eraserPos,
        sizeInPage: sizeInPage,
        removed: removed,
        removedInThisApply: removedInThisApply,
        added: added,
        isOverBudget: budget != null ? overBudget : null,
      );
      if (!sessionDone) {
        areaWorkRemaining = true;
        break;
      }
    }

    return EraserResult(
      removed: removed,
      added: added,
      areaWorkRemaining: areaWorkRemaining,
    );
  }

  void _markStrokeRemoved(Stroke stroke) {
    if (_added.contains(stroke)) {
      _added.remove(stroke);
      _toDispose.add(stroke);
    } else {
      _erased.add(stroke);
    }
  }

  /// Returns false if [isOverBudget] fired mid-work; nothing is committed so
  /// the same session can be retried on the next queued chunk (avoids OOM/jank
  /// from huge polylines and keeps page/eraser state consistent).
  bool _applyAreaToSession({
    required _AreaSession session,
    required Offset eraserPos,
    required double sizeInPage,
    required List<Stroke> removed,
    required Set<Stroke> removedInThisApply,
    required List<Stroke> added,
    bool Function()? isOverBudget,
  }) {
    final points = session.originalPoints;
    if (points.isEmpty) return true;

    final strokeHalfWidth = session.original.options.size / 2.0;

    final hitRadius = (sizeInPage + strokeHalfWidth).clamp(_minRadius, 1e6);
    final hitRect = Rect.fromCircle(center: eraserPos, radius: hitRadius);
    final cutRadius = hitRadius + _cutMargin;
    final cutRadiusSqr = cutRadius * cutRadius;

    final source = session.original;
    final bool isShape =
        source is ShapeStroke ||
        source is CircleStroke ||
        source is RectangleStroke;
    final strokeWidth = source.options.size;
    final minKeepDistSq = (strokeWidth * 0.12) * (strokeWidth * 0.12);

    bool changed = false;
    final nextSegments = <_AreaSegment>[];
    final pendingFragmentRemovals = <Stroke>[];
    final pendingNewStrokes = <Stroke>[];
    var pendingOriginalRemoval = false;

    for (final segment in session.currentSegments) {
      if (isOverBudget != null && isOverBudget()) return false;

      final fragment = segment.stroke;
      if (fragment != null && !fragment.bounds.overlaps(hitRect)) {
        nextSegments.add(segment);
        continue;
      }
      final splitRanges = _splitRangeOutsideCircle(
        points: points,
        start: segment.start,
        end: segment.end,
        center: eraserPos,
        radiusSqr: cutRadiusSqr,
        isOverBudget: isOverBudget,
      );
      if (splitRanges == null) return false;

      final unchanged =
          splitRanges.length == 1 &&
          splitRanges.first.start == segment.start &&
          splitRanges.first.end == segment.end;
      if (unchanged) {
        nextSegments.add(segment);
        continue;
      }

      changed = true;
      if (!session.originalRemoved && !pendingOriginalRemoval) {
        pendingOriginalRemoval = true;
      }
      if (fragment != null) {
        pendingFragmentRemovals.add(fragment);
      }
      for (final range in splitRanges) {
        final segLength = range.end - range.start + 1;
        if (segLength < 2) continue;
        if (segLength == 2) {
          final first = points[range.start];
          final last = points[range.end];
          final dx = first.x - last.x;
          final dy = first.y - last.y;
          if (dx * dx + dy * dy < minKeepDistSq) continue;
        }

        final newStroke = isShape
            ? source.cloneForEraserFragment()
            : source.cloneForEraserFragment();
        newStroke.replacePointRangeFromEraser(points, range.start, range.end);
        if (source.toolId == ToolId.highlighter) {
          newStroke.color = Color(source.color.value);
        }
        nextSegments.add(
          _AreaSegment(start: range.start, end: range.end, stroke: newStroke),
        );
        pendingNewStrokes.add(newStroke);
      }
    }

    if (!changed) return true;

    if (pendingOriginalRemoval && !session.originalRemoved) {
      removed.add(session.original);
      removedInThisApply.add(session.original);
      _markStrokeRemoved(session.original);
      session.originalRemoved = true;
      _areaRemovedOriginals.add(session.original);
    }
    for (final f in pendingFragmentRemovals) {
      removed.add(f);
      removedInThisApply.add(f);
      _markStrokeRemoved(f);
      _areaFragmentSessions.remove(f);
    }
    for (final newStroke in pendingNewStrokes) {
      added.add(newStroke);
      _added.add(newStroke);
      _areaFragmentSessions[newStroke] = session;
    }

    session.currentSegments
      ..clear()
      ..addAll(nextSegments);

    if (session.currentSegments.isEmpty) {
      _dropAreaSession(session);
    }
    return true;
  }

  static double _distPointToSegmentSq({
    required double px,
    required double py,
    required double x1,
    required double y1,
    required double x2,
    required double y2,
  }) {
    final l2 = (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2);
    if (l2 == 0) {
      final dx = px - x1;
      final dy = py - y1;
      return dx * dx + dy * dy;
    }
    final t = ((px - x1) * (x2 - x1) + (py - y1) * (y2 - y1)) / l2;
    final tc = t.clamp(0.0, 1.0);
    final qx = x1 + tc * (x2 - x1);
    final qy = y1 + tc * (y2 - y1);
    final dx = px - qx;
    final dy = py - qy;
    return dx * dx + dy * dy;
  }

  /// [null] means time budget exceeded; retry later without mutating session.
  List<_IndexRange>? _splitRangeOutsideCircle({
    required List<PointVector> points,
    required int start,
    required int end,
    required Offset center,
    required double radiusSqr,
    bool Function()? isOverBudget,
  }) {
    if (end < start) return const [];
    final len = end - start + 1;
    if (_splitMaskScratch.length < len) {
      _splitMaskScratch = Uint8List(len);
    }
    final localMask = _splitMaskScratch;
    localMask.fillRange(0, len, 0);
    _rangeScratch.clear();
    final cx = center.dx;
    final cy = center.dy;

    final localStride = math.max(
      1,
      (len / _EraserLimits.maxLocalSplitPoints).ceil(),
    );
    var coarseI = 0;
    for (int i = start; i <= end; i += localStride) {
      if (isOverBudget != null &&
          (coarseI & 0x3FF) == 0 &&
          isOverBudget()) {
        return null;
      }
      coarseI++;
      final p = points[i];
      final dx = p.x - cx;
      final dy = p.y - cy;
      if ((dx * dx + dy * dy) <= radiusSqr) {
        localMask[i - start] = 1;
      }
    }
    if ((len - 1) % localStride != 0) {
      final p = points[end];
      final dx = p.x - cx;
      final dy = p.y - cy;
      if ((dx * dx + dy * dy) <= radiusSqr) {
        localMask[end - start] = 1;
      }
    }

    var refineSteps = 0;
    for (int i = start + 1; i <= end; i++) {
      if (isOverBudget != null &&
          (refineSteps & 0x3FF) == 0 &&
          isOverBudget()) {
        return null;
      }
      refineSteps++;
      final localI = i - start;
      final prevLocal = localI - 1;
      final p1 = points[i - 1];
      final p2 = points[i];
      if (_distPointToSegmentSq(
            px: cx,
            py: cy,
            x1: p1.x,
            y1: p1.y,
            x2: p2.x,
            y2: p2.y,
          ) >
          radiusSqr) {
        continue;
      }
      final p1In =
          (p1.x - cx) * (p1.x - cx) + (p1.y - cy) * (p1.y - cy) <= radiusSqr;
      final p2In =
          (p2.x - cx) * (p2.x - cx) + (p2.y - cy) * (p2.y - cy) <= radiusSqr;
      if (p1In) localMask[prevLocal] = 1;
      if (p2In) localMask[localI] = 1;
      if (!p1In && !p2In) {
        final d1 = (p1.x - cx) * (p1.x - cx) + (p1.y - cy) * (p1.y - cy);
        final d2 = (p2.x - cx) * (p2.x - cx) + (p2.y - cy) * (p2.y - cy);
        if (d1 <= d2) {
          localMask[prevLocal] = 1;
        } else {
          localMask[localI] = 1;
        }
      }
    }

    int? currentStart;
    var scanI = 0;
    for (int i = 0; i < len; i++) {
      if (isOverBudget != null &&
          (scanI & 0x3FF) == 0 &&
          isOverBudget()) {
        return null;
      }
      scanI++;
      if (localMask[i] == 0) {
        currentStart ??= start + i;
      } else if (currentStart != null) {
        _rangeScratch.add(_IndexRange(start: currentStart, end: start + i - 1));
        currentStart = null;
      }
    }
    if (currentStart != null) {
      _rangeScratch.add(_IndexRange(start: currentStart, end: end));
    }
    return _rangeScratch;
  }

  void _dropAreaSession(_AreaSession session) {
    _areaSessions.remove(session.original);
    for (final segment in session.currentSegments) {
      if (segment.stroke != null) {
        _areaFragmentSessions.remove(segment.stroke);
      }
    }
    session.currentSegments.clear();
  }

  static bool _shouldStrokeBeErased(
    Offset eraserPos,
    Stroke stroke,
    double eraserSize,
  ) {
    final effectiveRadius = (eraserSize + stroke.options.size / 2).clamp(
      _minRadius,
      1e6,
    );
    final hitRect = Rect.fromCircle(center: eraserPos, radius: effectiveRadius);

    if (!stroke.bounds.overlaps(hitRect)) return false;

    if (stroke is ShapeStroke ||
        stroke is CircleStroke ||
        stroke is RectangleStroke) {
      return stroke.isHitByCircle(eraserPos, eraserSize);
    }

    return stroke.isHitByCircle(eraserPos, eraserSize);
  }

  (List<Stroke> erased, List<Stroke> added, List<Stroke> toDispose) onDragEnd() {
    final erased = _erased.toList();
    final added = _added.toList();
    final toDispose = _toDispose.toList();
    _erased.clear();
    _added.clear();
    _toDispose.clear();
    _areaSessions.clear();
    _areaFragmentSessions.clear();
    _areaRemovedOriginals.clear();
    _lastAppliedPos = null;
    return (erased, added, toDispose);
  }

  void clearState() {
    _erased.clear();
    _added.clear();
    _toDispose.clear();
    _areaSessions.clear();
    _areaFragmentSessions.clear();
    _areaRemovedOriginals.clear();
    _lastAppliedPos = null;
  }
}

class _IndexRange {
  const _IndexRange({required this.start, required this.end});
  final int start;
  final int end;
}

class _AreaSegment {
  const _AreaSegment({
    required this.start,
    required this.end,
    required this.stroke,
  });

  final int start;
  final int end;
  final Stroke? stroke;
}

class _AreaSession {
  _AreaSession({
    required this.original,
    required this.originalPoints,
    required this.currentSegments,
  });
  final Stroke original;
  final List<PointVector> originalPoints;
  final List<_AreaSegment> currentSegments;
  bool originalRemoved = false;
}
