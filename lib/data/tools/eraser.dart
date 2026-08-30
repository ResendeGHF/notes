// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui';

import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_shape_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';

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

/// One area-erase drag: originals map to their surviving fragments (xnotes
/// [EraseSession] shape). Re-cuts coalesce into the same entry.
class _AreaEraseEntry {
  _AreaEraseEntry(this.original);

  final Stroke original;
  final List<Stroke> fragments = [];
}

class Eraser extends Tool {
  Eraser({double size = 5, this.mode = EraserMode.stroke})
    : size = size.clamp(sizeMin, 25.0);

  static Eraser currentEraser = Eraser();

  /// True while an eraser pointer is down. Idle hydrate/prewarm and extra
  /// Picture-tile recording must bail, matching [Pen.currentStroke].
  static bool isDragging = false;

  double size;
  EraserMode mode;

  static const double sizeMin = 0.5;

  set updateSize(double newSize) {
    size = newSize.clamp(sizeMin, 25.0);
  }

  set updateMode(EraserMode newMode) {
    mode = newMode;
  }

  final Set<Stroke> _erased = {};
  final Set<Stroke> _added = {};
  final Set<Stroke> _toDispose = {};
  final List<Stroke> _candidateBuffer = [];
  Offset? _lastAppliedPos;

  /// Area-erase session: originals first touched this drag.
  final List<_AreaEraseEntry> _areaEntries = [];
  final Map<Stroke, _AreaEraseEntry> _areaByOriginal = {};
  final Map<Stroke, Stroke> _areaOriginOf = {};

  List<Stroke>? _orderDrawOrder;
  Map<Stroke, int>? _orderMap;
  int _orderMapRebuilds = 0;

  static const double _minRadius = 1e-3;
  static const double _areaStepFactor = 0.45;
  static const double _strokeStepFactor = 0.35;

  @override
  ToolId get toolId => ToolId.eraser;

  bool shouldApplyAt(Offset position) {
    final last = _lastAppliedPos;
    if (last == null) {
      _lastAppliedPos = position;
      return true;
    }
    final step =
        (size * (mode == EraserMode.area ? _areaStepFactor : _strokeStepFactor))
            .clamp(1.0, 24.0);
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
      candidates = _candidateBuffer
        ..clear()
        ..addAll(strokes);
    }
    _sortFrontToBack(candidates, strokes);

    if (mode == EraserMode.stroke) {
      for (final stroke in candidates) {
        if (!_shouldStrokeBeErased(eraserPos, stroke, sizeInPage)) continue;
        removed.add(stroke);
        _markStrokeRemoved(stroke);
        break;
      }
      return EraserResult(removed: removed, added: added);
    }

    // Area mode — xnotes EraseSession: every overlapping stroke under the
    // circle is eligible; soft time budget only yields, never caps hit count.
    final Stopwatch? budget = areaTimeBudgetMs != null
        ? (Stopwatch()..start())
        : null;
    var areaWorkRemaining = false;

    bool overBudget() {
      if (budget == null) return false;
      return budget.elapsedMilliseconds >= areaTimeBudgetMs!;
    }

    for (final candidate in candidates) {
      if (overBudget()) {
        areaWorkRemaining = true;
        break;
      }

      final strokeHalfWidth = candidate.options.size / 2.0;
      final hitRadius = (sizeInPage + strokeHalfWidth).clamp(_minRadius, 1e6);
      final hitRect = Rect.fromCircle(center: eraserPos, radius: hitRadius);
      if (!candidate.bounds.overlaps(hitRect)) continue;

      final fragmentsOrNull = _erasedByCircle(
        candidate,
        eraserPos,
        hitRadius,
      );
      if (fragmentsOrNull == null) continue;

      final fragments = fragmentsOrNull;
      removed.add(candidate);
      _markStrokeRemoved(candidate);
      for (final f in fragments) {
        added.add(f);
        _added.add(f);
      }
      _recordAreaCut(candidate, fragments);
    }

    return EraserResult(
      removed: removed,
      added: added,
      areaWorkRemaining: areaWorkRemaining,
    );
  }

  /// Surviving fragments after an eraser circle passes over [stroke].
  /// `null` = miss, empty = fully erased, otherwise replacement strokes.
  List<Stroke>? _erasedByCircle(
    Stroke stroke,
    Offset center,
    double radius,
  ) {
    final points = stroke.pointsForEraser;
    if (points.isEmpty) {
      return _shouldStrokeBeErased(center, stroke, size)
          ? const <Stroke>[]
          : null;
    }

    if (stroke is ShapeStroke ||
        stroke is CircleStroke ||
        stroke is RectangleStroke) {
      return stroke.isHitByCircle(center, size) ? const <Stroke>[] : null;
    }

    final radiusSqr = radius * radius;
    final cx = center.dx;
    final cy = center.dy;
    final n = points.length;
    var anyErased = false;
    var runStart = -1;
    final ranges = <(int, int)>[];

    for (var i = 0; i < n; i++) {
      final p = points[i];
      final dx = p.x - cx;
      final dy = p.y - cy;
      if (dx * dx + dy * dy <= radiusSqr) {
        anyErased = true;
        if (runStart >= 0) {
          ranges.add((runStart, i - 1));
          runStart = -1;
        }
      } else if (runStart < 0) {
        runStart = i;
      }
    }
    if (runStart >= 0) ranges.add((runStart, n - 1));
    if (!anyErased) return null;

    final strokeWidth = stroke.options.size;
    final minKeepDistSq = (strokeWidth * 0.12) * (strokeWidth * 0.12);
    final out = <Stroke>[];
    for (final (start, end) in ranges) {
      final segLength = end - start + 1;
      if (segLength < 2) continue;
      if (segLength == 2) {
        final first = points[start];
        final last = points[end];
        final dx = first.x - last.x;
        final dy = first.y - last.y;
        if (dx * dx + dy * dy < minKeepDistSq) continue;
      }
      final frag = stroke.cloneForEraserFragment();
      frag.replacePointRangeFromEraser(points, start, end);
      if (stroke.toolId == ToolId.highlighter) {
        frag.color = Color(stroke.color.value);
      }
      out.add(frag);
    }
    return out;
  }

  void _recordAreaCut(Stroke item, List<Stroke> fragments) {
    final original = _areaOriginOf[item];
    final entry = original != null ? _areaByOriginal[original] : null;
    if (entry == null) {
      final fresh = _AreaEraseEntry(item);
      fresh.fragments.addAll(fragments);
      _areaEntries.add(fresh);
      _areaByOriginal[item] = fresh;
      for (final f in fragments) {
        _areaOriginOf[f] = item;
      }
      return;
    }
    final slot = entry.fragments.indexWhere((e) => identical(e, item));
    if (slot >= 0) {
      entry.fragments.removeAt(slot);
      entry.fragments.insertAll(slot, fragments);
    }
    _areaOriginOf.remove(item);
    for (final f in fragments) {
      _areaOriginOf[f] = entry.original;
    }
  }

  /// Rebuilds only when [drawOrder] identity/length changes or a candidate
  /// is missing. Misses on a stable page must not scan every stroke again.
  void _sortFrontToBack(List<Stroke> candidates, List<Stroke> drawOrder) {
    if (candidates.length < 2) return;
    var order = _orderMap;
    var rebuild =
        !identical(_orderDrawOrder, drawOrder) ||
        order == null ||
        order.length != drawOrder.length;
    if (!rebuild) {
      for (final candidate in candidates) {
        if (!order!.containsKey(candidate)) {
          rebuild = true;
          break;
        }
      }
    }
    if (rebuild) {
      order = <Stroke, int>{};
      for (var i = 0; i < drawOrder.length; i++) {
        order[drawOrder[i]] = i;
      }
      _orderMap = order;
      _orderDrawOrder = drawOrder;
      _orderMapRebuilds++;
    }
    final ranks = order!;
    candidates.sort((a, b) => (ranks[b] ?? -1).compareTo(ranks[a] ?? -1));
  }

  int get debugOrderMapRebuildCount => _orderMapRebuilds;

  void _markStrokeRemoved(Stroke stroke) {
    if (_added.contains(stroke)) {
      _added.remove(stroke);
      _toDispose.add(stroke);
    } else {
      _erased.add(stroke);
    }
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

    return stroke.isHitByCircle(eraserPos, eraserSize);
  }

  (List<Stroke> erased, List<Stroke> added, List<Stroke> toDispose)
  onDragEnd() {
    final erased = _erased.toList();
    final added = _added.toList();
    final toDispose = _toDispose.toList();
    clearState();
    return (erased, added, toDispose);
  }

  void clearState() {
    _erased.clear();
    _added.clear();
    _toDispose.clear();
    _areaEntries.clear();
    _areaByOriginal.clear();
    _areaOriginOf.clear();
    _lastAppliedPos = null;
  }
}
