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

enum EraserMode { stroke, area, carve }

extension EraserModeX on EraserMode {
  /// Area and carve share the drag session. Stroke mode deletes whole strokes.
  bool get isAreaLike => this == EraserMode.area || this == EraserMode.carve;
}

class EraserResult {
  EraserResult({
    required this.removed,
    required this.added,
    this.replacementGroups = const [],
    this.areaWorkRemaining = false,
    this.contentMutated = false,
  });

  final List<Stroke> removed;
  final List<Stroke> added;

  /// Parallel to [removed]: each entry replaces that stroke in draw order.
  /// Empty means the stroke is gone. Missing groups are treated as empty.
  final List<List<Stroke>> replacementGroups;

  final bool areaWorkRemaining;

  /// True when a carve mask was extended in place (same stroke object).
  final bool contentMutated;
}

/// One area-erase original and the fragments currently standing in for it.
class _AreaEntry {
  _AreaEntry(this.original, this.points);

  final Stroke original;

  /// Full centerline, unchanged for the life of the drag.
  final List<PointVector> points;

  /// Surviving polylines. Null until the first cut (the original is intact).
  /// Every sample outside the eraser is copied through; only the bitten
  /// span is replaced by the two boundary points.
  List<List<PointVector>>? pieces;

  /// Objects currently in the page (the original, then its fragments).
  List<Stroke> live = [];
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

  /// Tip of the last sweep that was fully applied. The next call covers the
  /// whole capsule from here to the pointer, so the bite cannot trail the pen
  /// and fast flicks cannot leave a tunnel.
  Offset? _coveredPos;

  final List<_AreaEntry> _areaEntries = [];
  final Map<Stroke, _AreaEntry> _areaByOriginal = {};
  final Map<Stroke, Stroke> _areaOriginOf = {};

  /// Carve: page object currently wearing the mask for an original.
  final Map<Stroke, Stroke> _carveLive = {};
  final Map<Stroke, Stroke> _carveOriginOf = {};

  List<Stroke>? _orderDrawOrder;
  Map<Stroke, int>? _orderMap;
  int _orderMapRebuilds = 0;

  static const double _minRadius = 1e-3;

  @override
  ToolId get toolId => ToolId.eraser;

  bool shouldApplyAt(Offset position) {
    final last = _lastAppliedPos;
    if (last == null) {
      _lastAppliedPos = position;
      return true;
    }
    // Area/carve still gate on travel, but each accepted call covers the
    // whole capsule back to [_coveredPos], so the hole ends on the pen.
    final factor = mode == EraserMode.stroke ? 0.35 : 0.22;
    final step = (size * factor).clamp(1.0, 18.0);
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
    // A zero budget is the "yield before doing work" signal used by tests
    // and by a saturated frame. Callers with a real budget finish the capsule
    // in this call — partial cuts are what made deleted ink come back.
    if (areaTimeBudgetMs != null && areaTimeBudgetMs <= 0 && mode.isAreaLike) {
      return EraserResult(
        removed: const [],
        added: const [],
        areaWorkRemaining: true,
      );
    }

    final from = _coveredPos ?? eraserPos;
    final sizeInPage = size.clamp(_minRadius, 1e6);
    final reach = sizeInPage + 40.0;
    final minX = (from.dx < eraserPos.dx ? from.dx : eraserPos.dx) - reach;
    final minY = (from.dy < eraserPos.dy ? from.dy : eraserPos.dy) - reach;
    final maxX = (from.dx > eraserPos.dx ? from.dx : eraserPos.dx) + reach;
    final maxY = (from.dy > eraserPos.dy ? from.dy : eraserPos.dy) + reach;
    final searchRect = Rect.fromLTRB(minX, minY, maxX, maxY);

    final List<Stroke> working;
    if (spatialIndex != null) {
      working = spatialIndex.query(searchRect, _candidateBuffer..clear());
    } else {
      working = _candidateBuffer
        ..clear()
        ..addAll(strokes);
    }

    _sortFrontToBack(working, strokes);

    final removed = <Stroke>[];
    final added = <Stroke>[];
    final groups = <List<Stroke>>[];
    var mutated = false;

    if (mode == EraserMode.stroke) {
      for (final candidate in working) {
        if (!_capsuleHits(from, eraserPos, candidate, sizeInPage)) continue;
        removed.add(candidate);
        groups.add(const []);
        _markRemoved(candidate);
        break;
      }
    } else if (mode == EraserMode.carve) {
      mutated = _applyCarve(
        from,
        eraserPos,
        sizeInPage,
        working,
        removed,
        added,
        groups,
      );
    } else {
      _applyArea(from, eraserPos, sizeInPage, working, removed, added, groups);
    }

    _coveredPos = eraserPos;
    return EraserResult(
      removed: removed,
      added: added,
      replacementGroups: groups,
      contentMutated: mutated,
    );
  }

  bool _applyCarve(
    Offset from,
    Offset to,
    double radius,
    List<Stroke> working,
    List<Stroke> removed,
    List<Stroke> added,
    List<List<Stroke>> groups,
  ) {
    var mutated = false;
    final seen = <Stroke>{};
    for (final candidate in working) {
      final origin = _carveOriginOf[candidate] ?? candidate;
      if (!seen.add(origin)) continue;
      final live = _carveLive[origin] ?? candidate;
      if (!_capsuleHits(from, to, live, radius)) continue;

      // No shape special-case: shapes carve like freehand ink. The first
      // touch clones the same shape type (geometry, fill and existing bites
      // included) and later touches edit the clone in place, so the punch
      // stays a mask on a vector shape (never a flattened freehand copy).
      // Replacing the original keeps the drag undoable, and a fully bitten
      // shape can be dropped like any other stroke.
      if (identical(live, origin) && !_carveLive.containsKey(origin)) {
        final carved = origin.copy();
        carved.addCarveSweep(from, to, radius);
        if (carved.carveCoversAllInk(radius)) {
          removed.add(origin);
          groups.add(const []);
          _markRemoved(origin);
          carved.dispose();
          continue;
        }
        _carveLive[origin] = carved;
        _carveOriginOf[carved] = origin;
        _added.add(carved);
        removed.add(origin);
        added.add(carved);
        groups.add([carved]);
        _markRemoved(origin);
        continue;
      }

      live.addCarveSweep(from, to, radius);
      // Fully bitten ink is dropped instead of keeping an invisible shell:
      // the page loses the object and undo restores the pristine original.
      if (live.carveCoversAllInk(radius)) {
        removed.add(live);
        groups.add(const []);
        _markRemoved(live);
        _carveLive.remove(origin);
        _carveOriginOf.remove(live);
      } else {
        mutated = true;
      }
    }
    return mutated;
  }

  void _applyArea(
    Offset from,
    Offset to,
    double radius,
    List<Stroke> working,
    List<Stroke> removed,
    List<Stroke> added,
    List<List<Stroke>> groups,
  ) {
    final seen = <Stroke>{};
    // Resolve the candidates to their entries before cutting anything.
    // Cutting an entry replaces its live fragments, so candidates already
    // returned by the spatial index would otherwise be mistaken for new
    // strokes: the stale copy then creates a bogus entry and its cut drops
    // the entry's other fragments from the page (the end-side piece of a
    // middle cut vanished, leaving only the start side).
    final targets = <(_AreaEntry, bool)>[];
    for (final candidate in working) {
      final origin = _areaOriginOf[candidate] ?? candidate;
      if (!seen.add(origin)) continue;
      final isShape =
          origin is ShapeStroke ||
          origin is CircleStroke ||
          origin is RectangleStroke;
      if (isShape || origin.pointsForEraser.isEmpty) {
        if (!_capsuleHits(from, to, origin, radius)) continue;
        targets.add((_entryFor(origin), true));
        continue;
      }
      targets.add((_entryFor(origin), false));
    }

    for (final (entry, isShapeOrEmpty) in targets) {
      if (isShapeOrEmpty) {
        _emitReplacement(entry, const [], removed, added, groups);
        continue;
      }
      final origin = entry.original;
      final hitRadius = radius + origin.options.size / 2;
      final next = _subtractCapsule(entry, from, to, hitRadius);
      if (next == null) continue;

      entry.pieces = next;
      final fragments = _materialize(origin, next);
      _emitReplacement(entry, fragments, removed, added, groups);
    }
  }

  _AreaEntry _entryFor(Stroke origin) {
    final existing = _areaByOriginal[origin];
    if (existing != null) return existing;
    final entry = _AreaEntry(origin, List<PointVector>.of(origin.pointsForEraser));
    entry.live = [origin];
    _areaEntries.add(entry);
    _areaByOriginal[origin] = entry;
    return entry;
  }

  void _emitReplacement(
    _AreaEntry entry,
    List<Stroke> fragments,
    List<Stroke> removed,
    List<Stroke> added,
    List<List<Stroke>> groups,
  ) {
    final previous = List<Stroke>.of(entry.live);
    for (var i = 0; i < previous.length; i++) {
      final old = previous[i];
      removed.add(old);
      groups.add(i == 0 ? fragments : const <Stroke>[]);
      _markRemoved(old);
      // Keep the mapping for the life of the drag: a replaced fragment may
      // still be returned by the spatial index in a later candidate sweep,
      // and must resolve back to this entry instead of becoming a new one.
    }
    for (final frag in fragments) {
      _added.add(frag);
      added.add(frag);
      _areaOriginOf[frag] = entry.original;
    }
    entry.live = List<Stroke>.of(fragments);
  }

  /// Returns null on a clean miss. Otherwise every surviving polyline, which
  /// may be empty when the capsule covers the stroke.
  ///
  /// Samples outside the capsule are the original points. A segment that
  /// crosses the capsule is cut at the boundary, so a sparse stroke splits
  /// in two instead of disappearing when only one sample was inside.
  List<List<PointVector>>? _subtractCapsule(
    _AreaEntry entry,
    Offset from,
    Offset to,
    double radius,
  ) {
    if (entry.points.isEmpty) return const [];
    final source = entry.pieces ?? [entry.points];
    final out = <List<PointVector>>[];
    var anyHit = false;
    for (final piece in source) {
      final split = _splitPolyline(piece, from, to, radius);
      if (split == null) {
        out.add(piece);
      } else {
        anyHit = true;
        out.addAll(split);
      }
    }
    if (!anyHit) return null;
    return out;
  }

  List<List<PointVector>>? _splitPolyline(
    List<PointVector> pts,
    Offset from,
    Offset to,
    double radius,
  ) {
    if (pts.isEmpty) return const [];
    final r2 = radius * radius;
    final out = <List<PointVector>>[];
    List<PointVector>? cur;
    var anyHit = false;

    void flush() {
      final piece = cur;
      cur = null;
      // Keep single-point survivors as dots instead of dropping them:
      // dropping a 1-sample tail is what made the end-point side vanish
      // entirely on short/sparse strokes (only the start side remained).
      if (piece != null && piece.isNotEmpty) out.add(piece);
    }

    void addPt(PointVector p) {
      final list = cur ??= <PointVector>[];
      if (list.isNotEmpty) {
        final last = list.last;
        final dx = last.x - p.x;
        final dy = last.y - p.y;
        if (dx * dx + dy * dy < 1e-8) return;
      }
      list.add(p);
    }

    bool inside(PointVector p) => _distSqToSeg(p.x, p.y, from, to) <= r2;

    for (var i = 0; i < pts.length; i++) {
      final p = pts[i];
      final inn = inside(p);
      if (i == 0) {
        if (inn) {
          anyHit = true;
        } else {
          addPt(p);
        }
        continue;
      }
      final prev = pts[i - 1];
      final prevIn = inside(prev);
      if (!prevIn && !inn) {
        final cuts = _segmentCuts(prev, p, from, to, r2);
        if (cuts == null) {
          addPt(p);
        } else {
          anyHit = true;
          addPt(_lerpPoint(prev, p, cuts.$1));
          flush();
          addPt(_lerpPoint(prev, p, cuts.$2));
          addPt(p);
        }
      } else if (!prevIn && inn) {
        anyHit = true;
        addPt(_lerpPoint(prev, p, _lastOutsideT(prev, p, 0, 1, from, to, r2)));
        flush();
      } else if (prevIn && !inn) {
        anyHit = true;
        addPt(_lerpPoint(prev, p, _firstOutsideT(prev, p, 0, 1, from, to, r2)));
        addPt(p);
      } else {
        anyHit = true;
      }
    }
    flush();
    if (!anyHit) return null;
    return out;
  }

  /// Enter/exit parameters on [a]→[b] when both ends are outside the capsule
  /// but the segment still crosses it. Null when the segment misses.
  (double, double)? _segmentCuts(
    PointVector a,
    PointVector b,
    Offset from,
    Offset to,
    double r2,
  ) {
    var s = _closestT(a, b, from, to);
    var mid = _lerpPoint(a, b, s);
    if (_distSqToSeg(mid.x, mid.y, from, to) > r2) {
      // [_closestT] can return an outside endpoint for (near-)parallel
      // overlapping segments (it snaps to s=0). Sample for any inside
      // point to bracket the cut instead of missing a real crossing.
      double? insideT;
      const samples = [0.5, 0.25, 0.75, 0.125, 0.375, 0.625, 0.875];
      for (final t in samples) {
        final p = _lerpPoint(a, b, t);
        if (_distSqToSeg(p.x, p.y, from, to) <= r2) {
          insideT = t;
          break;
        }
      }
      if (insideT == null) return null;
      s = insideT;
      mid = _lerpPoint(a, b, s);
    }
    final enter = _lastOutsideT(a, b, 0, s, from, to, r2);
    final exit = _firstOutsideT(a, b, s, 1, from, to, r2);
    if (exit <= enter + 1e-4) return null;
    return (enter, exit);
  }

  /// Highest t in [lo, hi] that is still outside. [lo] is outside, [hi] inside.
  double _lastOutsideT(
    PointVector a,
    PointVector b,
    double lo,
    double hi,
    Offset from,
    Offset to,
    double r2,
  ) {
    var left = lo;
    var right = hi;
    for (var n = 0; n < 20; n++) {
      final mid = (left + right) * 0.5;
      final p = _lerpPoint(a, b, mid);
      if (_distSqToSeg(p.x, p.y, from, to) <= r2) {
        right = mid;
      } else {
        left = mid;
      }
    }
    return left;
  }

  /// Lowest t in [lo, hi] that is outside. [lo] is inside, [hi] outside.
  double _firstOutsideT(
    PointVector a,
    PointVector b,
    double lo,
    double hi,
    Offset from,
    Offset to,
    double r2,
  ) {
    var left = lo;
    var right = hi;
    for (var n = 0; n < 20; n++) {
      final mid = (left + right) * 0.5;
      final p = _lerpPoint(a, b, mid);
      if (_distSqToSeg(p.x, p.y, from, to) <= r2) {
        left = mid;
      } else {
        right = mid;
      }
    }
    return right;
  }

  PointVector _lerpPoint(PointVector a, PointVector b, double t) {
    return PointVector(
      a.x + (b.x - a.x) * t,
      a.y + (b.y - a.y) * t,
      Stroke.lerpPressure(a.pressure, b.pressure, t),
    );
  }

  /// Parameter on [a]→[b] of the point closest to the eraser segment.
  double _closestT(PointVector a, PointVector b, Offset c, Offset d) {
    final ux = b.x - a.x;
    final uy = b.y - a.y;
    final vx = d.dx - c.dx;
    final vy = d.dy - c.dy;
    final wx = a.x - c.dx;
    final wy = a.y - c.dy;
    final aa = ux * ux + uy * uy;
    final bb = ux * vx + uy * vy;
    final cc = vx * vx + vy * vy;
    const tiny = 1e-12;
    // Degenerate stroke segment (duplicate samples): every t is the same
    // point, so the closest is trivially the start.
    if (aa < tiny) return 0;
    // Point eraser (tap without drag): project the eraser point onto the
    // stroke segment. The generic segment-segment path below divides by
    // cc (≈0 here) and always returns 0, so sparse strokes whose samples
    // straddle a tap were never split (miss instead of two fragments).
    if (cc < tiny) {
      final t = ((c.dx - a.x) * ux + (c.dy - a.y) * uy) / aa;
      if (t < 0) return 0;
      if (t > 1) return 1;
      return t;
    }
    final dd = ux * wx + uy * wy;
    final ee = vx * wx + vy * wy;
    final denom = aa * cc - bb * bb;
    var sN = 0.0;
    var sD = denom;
    var tN = 0.0;
    var tD = denom;
    if (denom < tiny) {
      sN = 0;
      sD = 1;
      tN = ee;
      tD = cc;
    } else {
      sN = bb * ee - cc * dd;
      tN = aa * ee - bb * dd;
      if (sN < 0) {
        sN = 0;
        tN = ee;
        tD = cc;
      } else if (sN > sD) {
        sN = sD;
        tN = ee + bb;
        tD = cc;
      }
    }
    if (tN < 0) {
      tN = 0;
      if (-dd < 0) {
        sN = 0;
      } else if (-dd > aa) {
        sN = sD;
      } else {
        sN = -dd;
        sD = aa;
      }
    } else if (tN > tD) {
      tN = tD;
      if (-dd + bb < 0) {
        sN = 0;
      } else if (-dd + bb > aa) {
        sN = sD;
      } else {
        sN = -dd + bb;
        sD = aa;
      }
    }
    if (sD.abs() < tiny) return 0;
    final s = sN / sD;
    if (s < 0) return 0;
    if (s > 1) return 1;
    return s;
  }

  List<Stroke> _materialize(Stroke origin, List<List<PointVector>> pieces) {
    if (pieces.isEmpty) return const [];
    final anchor = origin.paintAnchorBounds ?? origin.bounds;
    final out = <Stroke>[];
    for (var piece in pieces) {
      if (piece.isEmpty) continue;
      // Single-sample survivor (tiny tip after a middle cut on a short or
      // sparse stroke): duplicate with a micro-offset so it stays valid
      // ink (>=2 samples, like Pen.onDragEnd dots) instead of vanishing
      // and taking the whole end-point side with it.
      if (piece.length == 1) {
        final p = piece.first;
        piece = [
          p,
          PointVector(p.x + 0.1, p.y + 0.1, p.pressure),
        ];
      }
      final frag = origin.cloneForEraserFragment();
      frag.replacePointsFromEraser(piece);
      if (origin.toolId == ToolId.highlighter) frag.color = origin.color;
      frag.paintAnchorBounds = anchor;
      out.add(frag);
    }
    return out;
  }

  bool _capsuleHits(Offset from, Offset to, Stroke stroke, double radius) {
    return stroke.isHitByCapsule(from, to, radius);
  }

  static double _distSqToSeg(double px, double py, Offset a, Offset b) {
    final abx = b.dx - a.dx;
    final aby = b.dy - a.dy;
    final ab2 = abx * abx + aby * aby;
    if (ab2 < 1e-8) {
      final dx = px - a.dx;
      final dy = py - a.dy;
      return dx * dx + dy * dy;
    }
    var t = ((px - a.dx) * abx + (py - a.dy) * aby) / ab2;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    final dx = px - (a.dx + abx * t);
    final dy = py - (a.dy + aby * t);
    return dx * dx + dy * dy;
  }

  void _sortFrontToBack(List<Stroke> candidates, List<Stroke> drawOrder) {
    if (candidates.length < 2) return;
    var order = _orderMap;
    var rebuild =
        !identical(_orderDrawOrder, drawOrder) ||
        order == null ||
        order.length != drawOrder.length;
    if (!rebuild) {
      for (final candidate in candidates) {
        if (!order.containsKey(candidate)) {
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

  void _markRemoved(Stroke stroke) {
    if (_added.contains(stroke)) {
      _added.remove(stroke);
      _toDispose.add(stroke);
    } else {
      _erased.add(stroke);
    }
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
    _carveLive.clear();
    _carveOriginOf.clear();
    _lastAppliedPos = null;
    _coveredPos = null;
  }
}
