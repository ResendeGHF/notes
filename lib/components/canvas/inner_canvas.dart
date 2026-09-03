// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:defer_pointer/defer_pointer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:saber/components/canvas/_canvas_background_painter.dart';
import 'package:saber/components/canvas/_canvas_painter.dart';
import 'package:saber/components/canvas/_shape_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/canvas_image.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/canvas/page_raster_cache.dart';
import 'package:saber/components/canvas/selection_handles_overlay.dart';
import 'package:saber/components/canvas/shape_control_points_overlay.dart';
import 'package:saber/data/editor/canvas_background_pattern.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/editor/quill_styles.dart';
import 'package:saber/data/editor/stroke_paint_image_cache.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/services/display_ink_feel.dart';

bool _strokeCanMergeSolidMesh(Stroke stroke) => stroke.canBatchSolidMesh;

double _canvasDevicePixelRatio() {
  final views = ui.PlatformDispatcher.instance.views;
  if (views.isEmpty) return 1.0;
  return views.first.devicePixelRatio.clamp(1.0, 4.0);
}

List<ui.Vertices> mergeStrokeMeshes(List<(Float32List, Uint16List)> chunks) {
  if (chunks.isEmpty) return const [];
  if (chunks.length == 1) {
    return [ui.Vertices.raw(ui.VertexMode.triangles, chunks.first.$1, indices: chunks.first.$2)];
  }
  final out = <ui.Vertices>[];
  var posCount = 0;
  var indCount = 0;
  for (final chunk in chunks) {
    posCount += chunk.$1.length;
    indCount += chunk.$2.length;
  }
  if (posCount <= 65535 * 2) {
    final pos = Float32List(posCount);
    final ind = Uint16List(indCount);
    var pOffset = 0;
    var iOffset = 0;
    var vertexOffset = 0;
    for (final chunk in chunks) {
      pos.setAll(pOffset, chunk.$1);
      for (var i = 0; i < chunk.$2.length; i++) {
        ind[iOffset + i] = chunk.$2[i] + vertexOffset;
      }
      pOffset += chunk.$1.length;
      iOffset += chunk.$2.length;
      vertexOffset += chunk.$1.length ~/ 2;
    }
    out.add(ui.Vertices.raw(ui.VertexMode.triangles, pos, indices: ind));
  } else {
    for (final chunk in chunks) {
      out.add(ui.Vertices.raw(ui.VertexMode.triangles, chunk.$1, indices: chunk.$2));
    }
  }
  return out;
}

Map<int, List<ui.Vertices>> _mergeSolidStrokeMeshesByColor(
  List<Stroke> strokes,
  double scale,
) {
  final clamped = scale.clamp(0.1, 5.0);
  final byColor = <int, List<(Float32List, Uint16List)>>{};
  for (final stroke in strokes) {
    stroke.setLodScale(clamped);
    if (!_strokeCanMergeSolidMesh(stroke)) continue;
    final chunks = stroke.solidMeshChunks;
    if (chunks.isEmpty) continue;
    byColor.putIfAbsent(stroke.color.toARGB32(), () => []).addAll(chunks);
  }
  final merged = <int, List<ui.Vertices>>{};
  for (final entry in byColor.entries) {
    final meshes = mergeStrokeMeshes(entry.value);
    if (meshes.isNotEmpty) merged[entry.key] = meshes;
  }
  return merged;
}

class InnerCanvas extends StatefulWidget {
  const InnerCanvas({
    super.key,
    required this.pageIndex,
    this.redrawPageListenable,
    required this.width,
    required this.height,
    this.isPreview = false,
    this.isPrint = false,
    this.textEditing = false,
    required this.coreInfo,
    required this.currentStroke,
    required this.currentStrokeDetectedShape,
    required this.currentSelection,
    this.selectionPreview,
    this.setAsBackground,
    this.onRenderObjectChange,
    required this.currentToolIsSelect,
    this.interactionRepaintListenable,
    required this.currentScale,
    this.onNoteLinkTap,
    this.eraserPosition,
    this.eraserPositionListenable,
    this.eraserSize,
    this.eraserDeltaRemoved,
    this.eraserDeltaAdded,
    this.doneSelecting = false,
    this.lineHeight,
    this.lineThickness,
    this.lineColor,
    this.imageCropState,
    this.onCropRectChanged,
    this.overrideInvert,
    this.pageRasterCache,
  });

  final int? lineHeight;
  final int? lineThickness;
  final Color? lineColor;

  final ({EditorImage image, Rect normalizedCrop})? imageCropState;
  final void Function(Rect normalizedCrop)? onCropRectChanged;

  final int pageIndex;
  final Listenable? redrawPageListenable;
  final double width;
  final double height;

  final bool isPreview;
  final bool isPrint;

  final bool textEditing;
  final EditorCoreInfo coreInfo;
  final Stroke? currentStroke;
  final RecognizedUnistroke? currentStrokeDetectedShape;
  final SelectResult? currentSelection;
  final SelectionTransformPreview? selectionPreview;
  final void Function(EditorImage image)? setAsBackground;
  final ValueChanged<RenderObject>? onRenderObjectChange;

  final bool currentToolIsSelect;
  final ValueListenable<int>? interactionRepaintListenable;
  final void Function(NoteLink link)? onNoteLinkTap;

  final double currentScale;
  final Offset? eraserPosition;
  final ValueListenable<Offset?>? eraserPositionListenable;
  final double? eraserSize;
  final List<Stroke>? eraserDeltaRemoved;
  final List<Stroke>? eraserDeltaAdded;
  final bool doneSelecting;

  final bool? overrideInvert;

  /// Per-editor page ink/background bitmap caches (xnotes-style LOD).
  final PageRasterCacheManager? pageRasterCache;

  static const defaultBackgroundColor = Color(0xFFFCFCFC);

  static Color getBackgroundColor(BuildContext context, Color? customColor) {
    return customColor ?? defaultBackgroundColor;
  }

  @override
  State<InnerCanvas> createState() => InnerCanvasState();
}

class InnerCanvasState extends State<InnerCanvas> {
  late final ValueNotifier<int> _layer2Repaint;

  bool _linkMarkersCollapsed = true;

  int _lastStrokeCount = 0;
  int _lastLayerOrderHash = 0;
  int _lastLaserStrokeCount = 0;
  int _lastObservedSaveBinaryRevision = -1;
  Rect? _eraserSessionDirty;
  bool _eraserNeedsFullInvalidate = false;

  TiledStrokePictureCache? _localStrokePictureCache;

  TiledStrokePictureCache get _strokePictureCache {
    if (widget.isPreview || widget.isPrint) {
      return _localStrokePictureCache ??= TiledStrokePictureCache();
    }
    final pages = widget.coreInfo.pages;
    if (pages.isEmpty) {
      return _localStrokePictureCache ??= TiledStrokePictureCache();
    }
    return pages[_safePageIndex].strokePictureCache;
  }

  void _invalidatePageRasterInk({Rect? dirty}) {
    widget.pageRasterCache?.invalidateInk(widget.pageIndex);
  }

  void _invalidatePageRasterBg() {
    widget.pageRasterCache?.invalidateBg(widget.pageIndex);
  }

  void _invalidateCommittedStrokeCache({
    Rect? dirty,
    bool eagerRefill = false,
    double padding = 0,
  }) {
    if (widget.pageRasterCache != null) {
      _invalidatePageRasterInk(dirty: dirty);
    }
    // We MUST invalidate the tiled cache since we disabled PageRasterCacheManager
    // for ink. Without this, new strokes won't bake into the tiles.
    if (dirty != null) {
      _strokePictureCache.invalidateRect(
        dirty,
        eagerRefill: eagerRefill,
        padding: padding,
      );
    } else {
      _strokePictureCache.invalidateAll(eagerRefill: eagerRefill);
    }
  }

  /// Flattened draw-order view of committed strokes; rebuilt only when page
  /// content version changes (not on every frame while [currentStroke] updates).
  List<Stroke>? _cachedCommittedStrokesFlat;
  EditorPage? _cachedFlatStrokesPage;
  int _cachedFlatSaveBinaryRevision = -1;
  int _cachedFlatStrokeCount = -1;
  int _cachedFlatLayerOrderHash = -1;
  Map<int, List<ui.Vertices>>? _cachedBatchedMeshes;
  double _cachedBatchScale = -1;
  int _cachedBatchStrokeCount = -1;

  final List<Stroke> _pendingInk = [];
  final Set<Stroke> _pendingInkSet = {};
  Timer? _pendingBakeTimer;
  final ValueNotifier<int> _pendingRepaint = ValueNotifier(0);
  int _pendingGeneration = 0;
  List<Stroke> _tiledStrokesSnapshot = const [];
  List<Stroke> _pageStrokeSnapshot = const [];
  final _LiveStrokeList _liveTiledStrokes = _LiveStrokeList();

  void _invalidateCommittedStrokesFlatCache() {
    _cachedCommittedStrokesFlat = null;
    _cachedFlatStrokesPage = null;
    _cachedFlatSaveBinaryRevision = -1;
    _cachedFlatStrokeCount = -1;
    _cachedFlatLayerOrderHash = -1;
    _cachedBatchedMeshes = null;
    _cachedBatchScale = -1;
    _cachedBatchStrokeCount = -1;
  }

  Map<int, List<ui.Vertices>> _buildBatchedMeshes(
    List<Stroke> strokes,
    double scale,
  ) {
    final clamped = scale.clamp(0.1, 5.0);
    if (_cachedBatchedMeshes != null &&
      _cachedBatchStrokeCount == strokes.length &&
      (_cachedBatchScale - clamped).abs() < 0.001) {
      return _cachedBatchedMeshes!;
      }
      final merged = _mergeSolidStrokeMeshesByColor(strokes, clamped);
    _cachedBatchedMeshes = merged;
    _cachedBatchScale = clamped;
    _cachedBatchStrokeCount = strokes.length;
    return merged;
  }

  List<Stroke> _reuseTiledSnapshot(List<Stroke> next) {
    final prev = _tiledStrokesSnapshot;
    if (prev.length == next.length) {
      var same = true;
      for (var i = 0; i < next.length; i++) {
        if (!identical(prev[i], next[i])) {
          same = false;
          break;
        }
      }
      if (same) return prev;
    }
    _tiledStrokesSnapshot = next;
    return next;
  }

  void _clearPendingInk() {
    _pendingBakeTimer?.cancel();
    _pendingBakeTimer = null;
    _pendingInk.clear();
    _pendingInkSet.clear();
    _pendingGeneration++;
  }

  void _bakePendingNow() {
    _pendingBakeTimer?.cancel();
    _pendingBakeTimer = null;
    if (_pendingInk.isEmpty) return;
    Rect? dirty;
    for (final stroke in _pendingInk) {
      final bounds = stroke.bounds;
      if (!bounds.isFinite || bounds.isEmpty) continue;
      dirty = dirty == null ? bounds : dirty.expandToInclude(bounds);
    }
    _pendingInk.clear();
    _pendingInkSet.clear();
    _pendingGeneration++;
    _invalidateCommittedStrokesFlatCache();
    _tiledStrokesSnapshot = const [];
    _invalidateCommittedStrokeCache(dirty: dirty, eagerRefill: dirty == null);
    _layer2Repaint.value++;
    _pendingRepaint.value++;
  }

  /// Keep Picture tiles in sync with page strokes. New ink is recorded into
  /// overlapping 512px tiles only (merged `drawVertices`), not deferred off
  /// the tiled layer — that path dropped strokes on pen-up.
  void _applyPageStrokeDelta(EditorPage page) {
    final previous = _pageStrokeSnapshot;
    final current = page.allStrokesInDrawOrder.toList(growable: false);
    final prevSet = previous.toSet();
    final currentSet = current.toSet();

    Rect? dirty;
    var changed = previous.length != current.length;
    for (final stroke in previous) {
      if (currentSet.contains(stroke)) continue;
      changed = true;
      if (_pendingInkSet.remove(stroke)) {
        _pendingInk.remove(stroke);
      }
      final bounds = stroke.bounds;
      if (bounds.isFinite && !bounds.isEmpty) {
        dirty = dirty == null ? bounds : dirty.expandToInclude(bounds);
      }
    }
    for (final stroke in current) {
      if (prevSet.contains(stroke)) continue;
      changed = true;
      final bounds = stroke.bounds;
      if (bounds.isFinite && !bounds.isEmpty) {
        dirty = dirty == null ? bounds : dirty.expandToInclude(bounds);
      }
    }
    _pageStrokeSnapshot = current;
    _liveTiledStrokes.strokes = current;
    if (!changed) return;

    _pendingBakeTimer?.cancel();
    _pendingBakeTimer = null;
    _pendingInk.clear();
    _pendingInkSet.clear();
    _pendingGeneration++;
    _invalidateCommittedStrokesFlatCache();
    _tiledStrokesSnapshot = current;
    _invalidateCommittedStrokeCache(dirty: dirty, eagerRefill: dirty == null);
    _layer2Repaint.value++;
    _pendingRepaint.value++;
  }

  Timer? _shapePreviewTicker;
  final ValueNotifier<int> _shapePreviewRepaint = ValueNotifier(0);
  int _shapePreviewTick = 0;
  late final ScrollController _quillScrollController;

  bool _isCapturingThumbnail = false;
  final GlobalKey _thumbnailCaptureKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _layer2Repaint = ValueNotifier(0);
    _quillScrollController = ScrollController();
    widget.redrawPageListenable?.addListener(_onPageChanged);

    if (widget.coreInfo.pages.isNotEmpty) {
      final page = widget.coreInfo.pages[_safePageIndex];
      _lastLayerOrderHash = _layerOrderHash(page);
      _lastLaserStrokeCount = page.laserStrokes.length;
      _lastStrokeCount = _totalStrokesAcrossLayers(page);
      _lastObservedSaveBinaryRevision = page.saveBinaryRevision;
      _pageStrokeSnapshot = page.allStrokesInDrawOrder.toList(growable: false);
      _liveTiledStrokes.strokes = _pageStrokeSnapshot;
    }
    _syncShapePreviewTicker();
    StrokePaintImageCache.instance.revision.addListener(
      _onStrokePaintImageReady,
    );
  }

  void _onStrokePaintImageReady() {
    if (!mounted) return;
    _invalidateCommittedStrokeCache(eagerRefill: true);
    _layer2Repaint.value++;
  }

  int _totalStrokesAcrossLayers(EditorPage page) {
    int n = 0;
    for (var i = 0; i < page.layerCount; i++) {
      n += page.layerAt(i).strokes.length;
    }
    return n;
  }

  int _layerOrderHash(EditorPage page) {
    var h = 0;
    for (final i in page.layerOrderIndices) {
      h = h * 31 + i;
    }
    return h;
  }

  int get _safePageIndex {
    final p = widget.coreInfo.pages;
    if (p.isEmpty) return 0;
    return widget.pageIndex.clamp(0, p.length - 1);
  }

  @override
  void didUpdateWidget(InnerCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.redrawPageListenable != oldWidget.redrawPageListenable) {
      oldWidget.redrawPageListenable?.removeListener(_onPageChanged);
      widget.redrawPageListenable?.addListener(_onPageChanged);
    }
    _syncShapePreviewTicker();

    if ((widget.currentScale - oldWidget.currentScale).abs() > 0.01 &&
      _pendingInk.length >= 4) {
      _bakePendingNow();
      }

      final selectingNow =
      widget.currentSelection != null && !widget.currentSelection!.isEmpty;
    final wasSelecting =
    oldWidget.currentSelection != null &&
    !oldWidget.currentSelection!.isEmpty;
    if (selectingNow && !wasSelecting && _pendingInk.isNotEmpty) {
      _bakePendingNow();
    }

    final pages = widget.coreInfo.pages;
    if (pages.isEmpty) return;
    final safePageIndex = _safePageIndex;
    final oldPages = oldWidget.coreInfo.pages;
    final safeOldPageIndex = oldPages.isEmpty
    ? 0
    : oldWidget.pageIndex.clamp(0, oldPages.length - 1);

    final page = pages[safePageIndex];
    final bool strokeFinished =
    oldWidget.currentStroke != null && widget.currentStroke == null;
    final bool pageChanged = page != oldPages[safeOldPageIndex];
    final bool eraserFinished =
    oldWidget.eraserPosition != null && widget.eraserPosition == null;

    final bool selectionCleared =
    (oldWidget.currentSelection != null &&
    !oldWidget.currentSelection!.isEmpty) &&
    (widget.currentSelection == null || widget.currentSelection!.isEmpty);

    final bool invertChanged = oldWidget.overrideInvert != widget.overrideInvert;

    final int quickStrokeCount = _totalStrokesAcrossLayers(page);
    final int layerOrderHash = _layerOrderHash(page);
    final bool isEraserActive = widget.eraserPosition != null;

    if (!pageChanged &&
      !strokeFinished &&
      !eraserFinished &&
      !selectionCleared &&
      !invertChanged &&
      quickStrokeCount == _lastStrokeCount &&
      layerOrderHash == _lastLayerOrderHash &&
      page.laserStrokes.isEmpty &&
      oldWidget.currentSelection == widget.currentSelection &&
      oldWidget.selectionPreview == widget.selectionPreview &&
      oldWidget.width == widget.width &&
      oldWidget.height == widget.height &&
      oldWidget.imageCropState == widget.imageCropState &&
      oldWidget.doneSelecting == widget.doneSelecting &&
      oldWidget.lineHeight == widget.lineHeight &&
      oldWidget.lineThickness == widget.lineThickness &&
      oldWidget.lineColor == widget.lineColor &&
      oldWidget.textEditing == widget.textEditing &&
      oldWidget.isPreview == widget.isPreview &&
      oldWidget.isPrint == widget.isPrint &&
      identical(oldWidget.eraserDeltaRemoved, widget.eraserDeltaRemoved) &&
      identical(oldWidget.eraserDeltaAdded, widget.eraserDeltaAdded)) {
      return;
      }

      final int prevLaserCount = _lastLaserStrokeCount;
      _lastLayerOrderHash = layerOrderHash;

      final bool contentChanged = quickStrokeCount != _lastStrokeCount;
      final bool revisionChanged =
      page.saveBinaryRevision != _lastObservedSaveBinaryRevision;

      if (pageChanged) {
        _clearPendingInk();
        _eraserSessionDirty = null;
        _eraserNeedsFullInvalidate = false;
        _pageStrokeSnapshot = page.allStrokesInDrawOrder.toList(growable: false);
        _tiledStrokesSnapshot = _pageStrokeSnapshot;
        _liveTiledStrokes.strokes = _pageStrokeSnapshot;
        _invalidateCommittedStrokesFlatCache();
        _invalidateCommittedStrokeCache();
        _layer2Repaint.value++;
      } else if (isEraserActive) {
        // Refill only the eraser's tiles so deleted ink disappears this frame.
        // Use the pointer circle for area splits (not the whole stroke bounds —
        // that flashed a huge rectangle and stalled the page).
        if (_pendingInk.isNotEmpty) {
          _bakePendingNow();
        }
        final dirtyBounds = _eraserLiveDirtyBounds(
          removed: widget.eraserDeltaRemoved,
          added: widget.eraserDeltaAdded,
        );
        if (dirtyBounds != null || contentChanged) {
          _invalidateCommittedStrokesFlatCache();
          _pageStrokeSnapshot = page.allStrokesInDrawOrder.toList(
            growable: false,
          );
          _tiledStrokesSnapshot = _pageStrokeSnapshot;
          _liveTiledStrokes.strokes = _pageStrokeSnapshot;
          if (dirtyBounds != null) {
            _eraserSessionDirty = _eraserSessionDirty == null
            ? dirtyBounds
            : _eraserSessionDirty!.expandToInclude(dirtyBounds);
            _invalidateCommittedStrokeCache(
              dirty: dirtyBounds,
              eagerRefill: true,
              padding: 48,
            );
          } else {
            _eraserNeedsFullInvalidate = true;
            _invalidateCommittedStrokeCache(eagerRefill: true);
          }
          _layer2Repaint.value++;
        }
      } else if (eraserFinished) {
        _bakePendingNow();
        _pageStrokeSnapshot = page.allStrokesInDrawOrder.toList(growable: false);
        _tiledStrokesSnapshot = _pageStrokeSnapshot;
        _liveTiledStrokes.strokes = _pageStrokeSnapshot;
        _invalidateCommittedStrokesFlatCache();
        final sessionDirty = _eraserSessionDirty;
        final needsFull = _eraserNeedsFullInvalidate;
        _eraserSessionDirty = null;
        _eraserNeedsFullInvalidate = false;
        if (needsFull) {
          _invalidateCommittedStrokeCache(eagerRefill: true);
        } else if (sessionDirty != null) {
          _invalidateCommittedStrokeCache(dirty: sessionDirty);
        }
        _layer2Repaint.value++;
      } else if (strokeFinished || contentChanged) {
        _applyPageStrokeDelta(page);
      } else if (selectionCleared) {
        _bakePendingNow();
        _pageStrokeSnapshot = page.allStrokesInDrawOrder.toList(growable: false);
        _tiledStrokesSnapshot = const [];
        _invalidateCommittedStrokesFlatCache();
        _invalidateCommittedStrokeCache(eagerRefill: true);
        _layer2Repaint.value++;
      } else if (revisionChanged && _lastObservedSaveBinaryRevision != -1) {
        // Same stroke count/order but committed content changed (e.g. color).
        _bakePendingNow();
        _pageStrokeSnapshot = page.allStrokesInDrawOrder.toList(growable: false);
        _tiledStrokesSnapshot = const [];
        _invalidateCommittedStrokesFlatCache();
        _invalidateCommittedStrokeCache(eagerRefill: true);
        _invalidatePageRasterBg();
        _layer2Repaint.value++;
      } else if (invertChanged) {
        _invalidateCommittedStrokesFlatCache();
        _invalidateCommittedStrokeCache(eagerRefill: true);
        _invalidatePageRasterBg();
        _layer2Repaint.value++;
      } else if (page.laserStrokes.isNotEmpty ||
        page.laserStrokes.length != prevLaserCount) {
        // Opacity fade keeps the same stroke count — still need a repaint.
        _layer2Repaint.value++;
        }

        _lastObservedSaveBinaryRevision = page.saveBinaryRevision;
      _lastLaserStrokeCount = page.laserStrokes.length;
      _lastStrokeCount = quickStrokeCount;
  }

  @override
  void dispose() {
    _pendingBakeTimer?.cancel();
    _pendingRepaint.dispose();
    _shapePreviewTicker?.cancel();
    _shapePreviewRepaint.dispose();
    _localStrokePictureCache?.dispose();
    _quillScrollController.dispose();
    widget.redrawPageListenable?.removeListener(_onPageChanged);
    StrokePaintImageCache.instance.revision.removeListener(
      _onStrokePaintImageReady,
    );
    _layer2Repaint.dispose();
    super.dispose();
  }

  bool get _shouldAnimateShapePreview =>
  widget.currentStroke != null && widget.currentStrokeDetectedShape != null;

  Rect? _eraserDeltaBounds({
    required List<Stroke>? removed,
    required List<Stroke>? added,
  }) {
    Rect? bounds;
    void addStrokeBounds(Stroke stroke) {
      final strokeBounds = stroke.bounds;
      if (!strokeBounds.isFinite || strokeBounds.isEmpty) return;
      bounds = bounds == null
      ? strokeBounds
      : bounds!.expandToInclude(strokeBounds);
    }

    removed?.forEach(addStrokeBounds);
    added?.forEach(addStrokeBounds);
    return bounds;
  }

  /// Tiles to rebuild while the eraser is down.
  /// Area splits change ink only under the pointer; whole-stroke delete uses
  /// the removed stroke bounds.
  Rect? _eraserLiveDirtyBounds({
    required List<Stroke>? removed,
    required List<Stroke>? added,
  }) {
    final pos = widget.eraserPosition;
    final radius = (widget.eraserSize ?? 16) + 8;
    final pointerRect = pos == null
    ? null
    : Rect.fromCircle(center: pos, radius: radius);

    // Fragments after a split: keep the dirty region on the pointer.
    if (added != null && added.isNotEmpty) {
      return pointerRect ?? _eraserDeltaBounds(removed: removed, added: added);
    }
    // Whole strokes removed (stroke-mode eraser): drop every tile they occupy.
    return _eraserDeltaBounds(removed: removed, added: added) ?? pointerRect;
  }

  void _syncShapePreviewTicker() {
    final want = _shouldAnimateShapePreview;
    if (want) {
      if (_shapePreviewTicker != null) return; // already running
      _shapePreviewTicker = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (!mounted || !_shouldAnimateShapePreview) return;
        _shapePreviewTick++;
        _shapePreviewRepaint.value++;
      });
    } else {
      _shapePreviewTicker?.cancel();
      _shapePreviewTicker = null;
    }
  }

  void _onPageChanged() {
    // Live ink paints on the overlay. Eraser hits still need a committed-tile
    // diff so deleted ink disappears without an Editor setState.
    if (widget.currentStroke != null || !mounted) return;
    final pages = widget.coreInfo.pages;
    if (pages.isEmpty) return;

    final page = pages[_safePageIndex];
    final eraserActive =
    Eraser.isDragging ||
    widget.eraserPositionListenable?.value != null ||
    widget.eraserPosition != null;
    final strokeCount = _totalStrokesAcrossLayers(page);
    final laserCount = page.laserStrokes.length;
    final laserCountChanged = laserCount != _lastLaserStrokeCount;
    _lastLayerOrderHash = _layerOrderHash(page);
    _lastLaserStrokeCount = laserCount;
    if (eraserActive) {
      _applyPageStrokeDelta(page);
      _lastStrokeCount = strokeCount;
      return;
    }
    final countChanged = strokeCount != _lastStrokeCount;
    _lastStrokeCount = strokeCount;
    if (countChanged) {
      _applyPageStrokeDelta(page);
    } else if (laserCountChanged) {
      setState(() {});
    } else if (page.laserStrokes.isNotEmpty) {
      // Opacity fade ticks — repaint without rebuilding the tree.
      _layer2Repaint.value++;
    }
  }

  Future<Uint8List?> captureThumbnail() async {
    if (!mounted) return null;

    _bakePendingNow();
    setState(() {
      _isCapturingThumbnail = true;
    });

    final hasBackgroundImage =
    widget.coreInfo.pages.isNotEmpty &&
    widget.coreInfo.pages[_safePageIndex].backgroundImage != null;
    await Future.delayed(
      hasBackgroundImage
      ? const Duration(milliseconds: 400)
      : const Duration(milliseconds: 50),
    );

    try {
      final boundary =
      _thumbnailCaptureKey.currentContext?.findRenderObject()
      as RenderRepaintBoundary?;

      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 0.7);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        return byteData?.buffer.asUint8List();
      }
    } catch (e) {
      debugPrint('Erro ao capturar thumbnail: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isCapturingThumbnail = false;
        });
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final brightness = theme.brightness;

    final overrides = stows.noteInvertInDarkModeOverrides.value;
    final invert =
    widget.overrideInvert ??
    (brightness == Brightness.dark
    ? (overrides[widget.coreInfo.filePath] == 1)
    : false);

    if (widget.overrideInvert == null && brightness == Brightness.dark) {
      return ValueListenableBuilder<Map<String, int>>(
        valueListenable: stows.noteInvertInDarkModeOverrides,
        builder: (context, overridesMap, _) {
          final effectiveInvert = overridesMap[widget.coreInfo.filePath] == 1;
          return _buildContent(
            context,
            theme,
            colorScheme,
            brightness,
            effectiveInvert,
          );
        },
      );
    }

    return _buildContent(context, theme, colorScheme, brightness, invert);
  }

  Widget _buildContent(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    Brightness brightness,
    bool invert,
  ) {
    final Color backgroundColor = InnerCanvas.getBackgroundColor(
      context,
      widget.coreInfo.backgroundColor,
    );

    if (widget.coreInfo.pages.isEmpty) {
      return SizedBox(width: widget.width, height: widget.height);
    }

    final page = widget.coreInfo.pages[_safePageIndex];
    final strokeCount = _totalStrokesAcrossLayers(page);
    final layerOrderHash = _layerOrderHash(page);
    final bool canReuseCommittedFlat =
    _cachedCommittedStrokesFlat != null &&
    identical(page, _cachedFlatStrokesPage) &&
    page.saveBinaryRevision == _cachedFlatSaveBinaryRevision &&
    strokeCount == _cachedFlatStrokeCount &&
    layerOrderHash == _cachedFlatLayerOrderHash;
    final freezeCommittedLayer =
    _cachedCommittedStrokesFlat != null && widget.currentStroke != null;

    late final List<Stroke> committedStrokes;
    if (freezeCommittedLayer || canReuseCommittedFlat) {
      committedStrokes = _cachedCommittedStrokesFlat!;
    } else {
      final allStrokes = page.allStrokesInDrawOrder.toList();
      // Força os Highlighters para o início do array para serem desenhados primeiro (atrás).
      committedStrokes = [
        ...allStrokes.where((s) => s.toolId == ToolId.highlighter),
        ...allStrokes.where((s) => s.toolId != ToolId.highlighter),
      ];
      _cachedCommittedStrokesFlat = committedStrokes;
      _cachedFlatStrokesPage = page;
      _cachedFlatSaveBinaryRevision = page.saveBinaryRevision;
      _cachedFlatStrokeCount = strokeCount;
      _cachedFlatLayerOrderHash = layerOrderHash;
    }

    final tiledStrokes = _reuseTiledSnapshot(committedStrokes);
    _liveTiledStrokes.strokes = tiledStrokes;

    final useCachedStrokeLayer =
    !widget.isPrint &&
    (widget.currentSelection == null || widget.currentSelection!.isEmpty);

    final usePageRasterCacheBg =
    widget.pageRasterCache != null &&
    !widget.isPreview &&
    !widget.isPrint;
    
    final committedInkStrokes = committedStrokes
        .where((s) => s.toolId != ToolId.highlighter)
        .toList(growable: false);
    final committedHighlighterStrokes = committedStrokes
        .where((s) => s.toolId == ToolId.highlighter)
        .toList(growable: false);

    final pageRasterRepaint = widget.pageRasterCache == null
    ? null
    : Listenable.merge([
      widget.pageRasterCache!.repaintEpoch,
      PageRasterCacheManager.lodEpoch,
    ]);
    final devicePixelRatio = _canvasDevicePixelRatio();

    final paintQuadTree = page.strokeSpatialIndex;

    final quillEditor = widget.coreInfo.pages.isNotEmpty
    ? QuillEditor(
      controller: widget.coreInfo.pages[_safePageIndex].quill.controller,
      config: QuillEditorConfig(
        customStyles: SaberQuillStyles.get(
          invert: invert,
          secondary: colorScheme.secondary,
          lineHeight: widget.coreInfo.lineHeight,
          appBodyTextStyle: theme.textTheme.bodyMedium,
        ),
        scrollable: false,
        autoFocus: false,
        expands: true,
        maxContentWidth: widget.width - widget.coreInfo.lineHeight,
        placeholder: widget.textEditing
        ? t.editor.quill.typeSomething
        : null,
        showCursor: true,
        keyboardAppearance: invert ? .dark : .light,
        padding: .only(
          top: widget.coreInfo.lineHeight * 1.2,
          left: widget.coreInfo.lineHeight * 0.5,
          right: widget.coreInfo.lineHeight * 0.5,
          bottom: widget.coreInfo.lineHeight * 0.5,
        ),
      ),
      scrollController: _quillScrollController,
      focusNode: widget.coreInfo.pages[_safePageIndex].quill.focusNode,
    )
    : null;

    final Widget content = Stack(
      fit: StackFit.expand,
      children: [
        Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                isComplex: true,
                key: ValueKey(
                  'bg_${invert}_${page.backgroundPattern?.index}_${page.backgroundColor.toARGB32()}_${widget.lineHeight}_${widget.lineThickness}_${widget.lineColor?.toARGB32()}_${page.marginLeft}_${page.marginRight}_${page.marginTop}_${page.marginBottom}_${page.borderColor.toARGB32()}',
                ),
                painter: usePageRasterCacheBg && page.backgroundImage == null
                ? _PageRasterBgLayerPainter(
                  repaint: pageRasterRepaint,
                  manager: widget.pageRasterCache!,
                  pageIndex: widget.pageIndex,
                  pageSize: Size(widget.width, widget.height),
                  currentScale: widget.currentScale,
                  fallback: CanvasBackgroundPainter(
                    invert: invert,
                    backgroundColor: () {
                      if (page.backgroundImage != null) {
                        return Colors.white;
                      } else {
                        return page.backgroundColor.toARGB32() != 0xFFFFFFFF
                        ? page.backgroundColor
                        : backgroundColor;
                      }
                    }(),
                    backgroundPattern: () {
                      if (page.backgroundImage != null) {
                        return CanvasBackgroundPattern.none;
                      } else {
                        return page.backgroundPattern ??
                        widget.coreInfo.backgroundPattern;
                      }
                    }(),
                    lineHeight:
                    widget.lineHeight ?? widget.coreInfo.lineHeight,
                    lineThickness:
                    widget.lineThickness ??
                    widget.coreInfo.lineThickness,
                    primaryColor:
                    widget.lineColor ??
                    (page.lineColor.toARGB32() != 0xFF9E9E9E
                    ? page.lineColor
                    : colorScheme.primary),
                    secondaryColor:
                    (widget.lineColor ??
                    (page.lineColor.toARGB32() != 0xFF9E9E9E
                    ? page.lineColor
                    : colorScheme.secondary))
                    .withValues(alpha: 0.5),
                    marginLeft: page.marginLeft,
                    marginRight: page.marginRight,
                    marginTop: page.marginTop,
                    marginBottom: page.marginBottom,
                    borderColor:
                    page.hasLocalBorderColor ||
                    (page.marginLeft > 0 ||
                    page.marginRight > 0 ||
                    page.marginTop > 0 ||
                    page.marginBottom > 0)
                    ? page.borderColor
                    : null,
                  ),
                  bgParams: pageRasterBgParamsFor(
                    page: page,
                    coreInfo: widget.coreInfo,
                    invert: invert,
                    primaryColor: colorScheme.primary,
                    secondaryColor: colorScheme.secondary,
                    defaultLineHeight: widget.coreInfo.lineHeight,
                      defaultLineThickness:
                        widget.coreInfo.lineThickness.toDouble(),
                        defaultPattern: widget.coreInfo.backgroundPattern,
                          defaultBackgroundColor: backgroundColor,
                  ),
                  devicePixelRatio: devicePixelRatio,
                )
                : CanvasBackgroundPainter(
                  invert: invert,
                  backgroundColor: () {
                    if (page.backgroundImage != null) {
                      return Colors.white;
                    } else {
                      return page.backgroundColor.toARGB32() != 0xFFFFFFFF
                      ? page.backgroundColor
                      : backgroundColor;
                    }
                  }(),
                  backgroundPattern: () {
                    if (page.backgroundImage != null) {
                      return CanvasBackgroundPattern.none;
                    } else {
                      return page.backgroundPattern ??
                      widget.coreInfo.backgroundPattern;
                    }
                  }(),

                  lineHeight: widget.lineHeight ?? widget.coreInfo.lineHeight,
                  lineThickness:
                  widget.lineThickness ?? widget.coreInfo.lineThickness,

                  primaryColor:
                  widget.lineColor ??
                  (page.lineColor.toARGB32() != 0xFF9E9E9E
                  ? page.lineColor
                  : colorScheme.primary),
                  secondaryColor:
                  (widget.lineColor ??
                  (page.lineColor.toARGB32() != 0xFF9E9E9E
                  ? page.lineColor
                  : colorScheme.secondary))
                  .withValues(alpha: 0.5),
                  marginLeft: page.marginLeft,
                  marginRight: page.marginRight,
                  marginTop: page.marginTop,
                  marginBottom: page.marginBottom,
                  borderColor:
                  page.hasLocalBorderColor ||
                  (page.marginLeft > 0 ||
                  page.marginRight > 0 ||
                  page.marginTop > 0 ||
                  page.marginBottom > 0)
                  ? page.borderColor
                  : null,
                ),
                size: Size(widget.width, widget.height),
              ),
            ),

            if (page.backgroundImage != null)
              CanvasImage(
                filePath: widget.coreInfo.filePath,
                image: page.backgroundImage!,
                pageSize: Size(widget.width, widget.height),
                setAsBackground: null,
                isBackground: true,
                readOnly: true,
              ),

              Positioned.fill(
                child: IgnorePointer(
                  ignoring: widget.coreInfo.readOnly || !widget.textEditing,
                  child: quillEditor,
                ),
              ),

              Positioned.fill(
                child: DeferredPointerHandler(
                  child: Stack(
                    children: [
                      for (final image in page.allImagesInDrawOrder) ...[
                        CanvasImage(
                          filePath: widget.coreInfo.filePath,
                          image: image,
                          pageSize: Size(widget.width, widget.height),
                          setAsBackground: widget.setAsBackground,
                          readOnly:
                          widget.coreInfo.readOnly ||
                          !widget.currentToolIsSelect,
                          selected:
                          widget.currentSelection?.images.contains(image) ??
                          false,
                          previewRect:
                          (widget.currentSelection?.images.contains(image) ??
                          false) &&
                          widget.selectionPreview != null
                          ? widget.selectionPreview!.transformRect(
                            image.dstRect,
                          )
                          : null,
                          previewRotationDeg:
                          (widget.currentSelection?.images.contains(image) ??
                          false) &&
                          widget.selectionPreview != null
                          ? image.rotationDeg +
                          widget.selectionPreview!.rotationDeltaDeg
                          : null,
                          canvasScale: widget.currentScale,
                          cropPreviewRect:
                          widget.imageCropState != null &&
                          identical(widget.imageCropState!.image, image)
                          ? widget.imageCropState!.normalizedCrop
                          : null,
                          onCropRectChanged: widget.onCropRectChanged,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (!widget.isPreview &&
                !widget.isPrint &&
                widget.onNoteLinkTap != null &&
                widget.coreInfo
                .linksForPage(
                  widget.coreInfo.pages[_safePageIndex],
                  widget.pageIndex,
                )
                .isNotEmpty)
                Positioned(
                  top: 10,
                  right: 10,
                  child: _LinksCard(
                    coreInfo: widget.coreInfo,
                    pageIndex: widget.pageIndex,
                    safePageIndex: _safePageIndex,
                    collapsed: _linkMarkersCollapsed,
                    onToggle: () {
                      setState(() {
                        _linkMarkersCollapsed = !_linkMarkersCollapsed;
                      });
                    },
                    onLinkTap: widget.onNoteLinkTap,
                    colorScheme: colorScheme,
                  ),
                ),
          ],
        ),

// 1º PINTA O HIGHLIGHTER NO FUNDO (CASHED)
        if (committedHighlighterStrokes.isNotEmpty)
          IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: CanvasPainter(
                  repaint: _layer2Repaint,
                  invert: invert,
                  strokes: committedHighlighterStrokes,
                  quadTree: paintQuadTree,
                  laserStrokes: const [],
                  currentStroke: null,
                  currentSelection: null,
                  primaryColor: colorScheme.primary,
                  page: page,
                  showPageIndicator: false,
                  pageIndex: widget.pageIndex,
                  totalPages: widget.coreInfo.pages.length,
                  currentScale: widget.currentScale,
                  defaultTextStyle: theme.textTheme.bodyMedium!,
                  lineHeight: widget.lineHeight,
                  lineThickness: widget.lineThickness?.toDouble(),
                  lineColor: widget.lineColor,
                  doneSelecting: true,
                  preferPathFill: true,
                ),
                size: Size(widget.width, widget.height),
              ),
            ),
          ),

          // 2º PINTA A TINTA E CANETAS NORMAIS NA FRENTE
          IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                isComplex: true,
                painter: _PageRasterInkLayerPainter(
                  repaint: Listenable.merge([
                    _layer2Repaint,
                    _pendingRepaint,
                    if (pageRasterRepaint != null) pageRasterRepaint,
                    _strokePictureCache.recordGeneration,
                    TiledStrokePictureCache.lodEpoch,
                  ]),
                  manager: widget.pageRasterCache!,
                  invert: invert,
                  quadTree: paintQuadTree,
                  committedStrokes: committedInkStrokes,
                  pendingStrokes: _pendingInk,
                  pendingGeneration: _pendingGeneration,
                  page: page,
                  primaryColor: colorScheme.primary,
                  pageIndex: widget.pageIndex,
                  totalPages: widget.coreInfo.pages.length,
                  currentScale: widget.currentScale,
                  devicePixelRatio: devicePixelRatio,
                  defaultTextStyle: theme.textTheme.bodyMedium!,
                  lineHeight: widget.lineHeight,
                  lineThickness: widget.lineThickness?.toDouble(),
                  lineColor: widget.lineColor,
                  showPageIndicator:
                      !widget.isPreview &&
                      (!widget.isPrint || stows.printPageIndicators.value) &&
                      !widget.coreInfo.isInfinite,
                  tiledCache: _strokePictureCache,
                  liveStrokes: _liveTiledStrokes,
                ),
                size: Size(widget.width, widget.height),
              ),
            ),
          ),

          if (widget.currentStroke != null ||
            page.laserStrokes.isNotEmpty ||
            widget.currentSelection != null ||
            widget.eraserPosition != null ||
            (widget.eraserDeltaRemoved?.isNotEmpty ?? false) ||
            (widget.eraserDeltaAdded?.isNotEmpty ?? false) ||
            !widget.doneSelecting)
            IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  willChange: true,
                  painter: CanvasPainter(
                    repaint: Listenable.merge([
                      if (widget.redrawPageListenable != null)
                        widget.redrawPageListenable!,
                        if (widget.interactionRepaintListenable != null)
                          widget.interactionRepaintListenable!,
                          if (widget.eraserPositionListenable != null)
                            widget.eraserPositionListenable!,
                            _shapePreviewRepaint,
                            _pendingRepaint,
                            if (widget.currentSelection != null ||
                              widget.eraserPosition != null ||
                              page.laserStrokes.isNotEmpty)
                              _layer2Repaint,
                              StrokePaintImageCache.instance.revision,
                    ]),

                    strokes:
                    widget.currentSelection != null &&
                    widget.currentSelection!.strokes.isNotEmpty
                    ? widget.currentSelection!.strokes
                    : const [],
                    spatialGrid: null,
                    // Selection/live strokes are not in the page QuadTree.
                    quadTree: null,
                    // Lasers live here (not in the tiled cache) so opacity fade
                    // can repaint every tick after stylus-up.
                    laserStrokes: page.laserStrokes,
                    lineHeight: widget.lineHeight,
                    lineThickness: widget.lineThickness?.toDouble(),
                    lineColor: widget.lineColor,
                    currentStroke: widget.currentStroke,
                    currentStrokeDetectedShape: widget.currentStrokeDetectedShape,
                    shapePreviewPulse: (_shapePreviewTick % 120) / 120.0,
                    currentSelection: widget.currentSelection,
                    selectionPreview: widget.selectionPreview,
                    eraserPosition: widget.eraserPosition,
                    eraserPositionListenable: widget.eraserPositionListenable,
                    eraserSize: widget.eraserSize,
                    invert: invert,
                    primaryColor: colorScheme.primary,
                    page: page,
                    showPageIndicator: false,
                    pageIndex: widget.pageIndex,
                    totalPages: widget.coreInfo.pages.length,
                    currentScale: widget.currentScale,
                    defaultTextStyle: theme.textTheme.bodyMedium!,
                      doneSelecting: widget.doneSelecting,
                  ),
                  size: Size(widget.width, widget.height),
                ),
              ),
            ),

            if (widget.currentSelection != null &&
              widget.doneSelecting &&
              !widget.currentSelection!.isEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: widget.interactionRepaintListenable == null
                  ? SelectionHandlesOverlay(
                    selection: widget.currentSelection!,
                    selectionPreview: widget.selectionPreview,
                    primaryColor: colorScheme.primary,
                    invert: invert,
                    currentScale: widget.currentScale,
                  )
                  : ValueListenableBuilder<int>(
                    valueListenable: widget.interactionRepaintListenable!,
                    builder: (context, _, _) {
                      return SelectionHandlesOverlay(
                        selection: widget.currentSelection!,
                        selectionPreview: widget.selectionPreview,
                        primaryColor: colorScheme.primary,
                        invert: invert,
                        currentScale: widget.currentScale,
                      );
                    },
                  ),
                ),
              ),
              if (widget.currentSelection != null &&
                widget.doneSelecting &&
                !widget.currentSelection!.isEmpty &&
                widget.currentSelection!.images.isEmpty &&
                widget.currentSelection!.strokes.length == 1 &&
                widget.currentSelection!.strokes.first is ShapeStroke &&
                (widget.currentSelection!.strokes.first as ShapeStroke)
                .isVertexEditable)
                Positioned.fill(
                  child: IgnorePointer(
                    child: widget.interactionRepaintListenable == null
                    ? ShapeControlPointsOverlay(
                      shape:
                      widget.currentSelection!.strokes.first as ShapeStroke,
                      primaryColor: colorScheme.primary,
                      invert: invert,
                      currentScale: widget.currentScale,
                      selectionPreview: widget.selectionPreview,
                    )
                    : ValueListenableBuilder<int>(
                      valueListenable: widget.interactionRepaintListenable!,
                      builder: (context, _, _) {
                        return ShapeControlPointsOverlay(
                          shape:
                          widget.currentSelection!.strokes.first
                          as ShapeStroke,
                          primaryColor: colorScheme.primary,
                          invert: invert,
                          currentScale: widget.currentScale,
                          selectionPreview: widget.selectionPreview,
                        );
                      },
                    ),
                  ),
                ),
      ],
    );

    if (_isCapturingThumbnail) {
      return RepaintBoundary(key: _thumbnailCaptureKey, child: content);
    }

    return content;
  }
}

class _LiveStrokeList {
  List<Stroke> strokes = const [];
}

class _PageRasterBgLayerPainter extends CustomPainter {
  _PageRasterBgLayerPainter({
    super.repaint,
    required this.manager,
    required this.pageIndex,
    required this.pageSize,
    required this.currentScale,
    required this.devicePixelRatio,
    required this.fallback,
    required this.bgParams,
  });

  final PageRasterCacheManager manager;
  final int pageIndex;
  final Size pageSize;
  final double currentScale;
  final double devicePixelRatio;
  final CanvasBackgroundPainter fallback;
  final PageRasterBgParams bgParams;

  @override
  void paint(Canvas canvas, Size size) {
    final idealRes = currentScale * devicePixelRatio;
    final entry = manager.backgroundForOrSchedule(
      pageIndex: pageIndex,
      pageSize: pageSize,
      scale: currentScale,
      devicePixelRatio: devicePixelRatio,
      params: bgParams,
      hasFullBleedBackground: false,
    );
    if (entry != null) {
      final cacheSharp = pageRasterCacheResCoversTarget(entry.res, idealRes);
      // Use !viewportSettled to keep the lightweight raster until the settle delay finishes!
      if (cacheSharp || !PageRasterCacheManager.viewportSettled) {
        paintPageCacheImage(
          canvas,
          size,
          entry,
          targetRes: idealRes,
          lowQualityFilter: !PageRasterCacheManager.viewportSettled,
        );
      } else {
        fallback.paint(canvas, size);
      }
      return;
    }
    fallback.paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _PageRasterBgLayerPainter oldDelegate) {
    return oldDelegate.manager != manager ||
    oldDelegate.pageIndex != pageIndex ||
    oldDelegate.pageSize != pageSize ||
    oldDelegate.currentScale != currentScale ||
    oldDelegate.devicePixelRatio != devicePixelRatio ||
    oldDelegate.fallback != fallback ||
    oldDelegate.bgParams.invert != bgParams.invert ||
    oldDelegate.bgParams.backgroundColor != bgParams.backgroundColor ||
    oldDelegate.bgParams.backgroundPattern != bgParams.backgroundPattern ||
    oldDelegate.bgParams.lineHeight != bgParams.lineHeight ||
    oldDelegate.bgParams.lineThickness != bgParams.lineThickness ||
    oldDelegate.bgParams.primaryColor != bgParams.primaryColor ||
    oldDelegate.bgParams.secondaryColor != bgParams.secondaryColor ||
    oldDelegate.bgParams.marginLeft != bgParams.marginLeft ||
    oldDelegate.bgParams.marginRight != bgParams.marginRight ||
    oldDelegate.bgParams.marginTop != bgParams.marginTop ||
    oldDelegate.bgParams.marginBottom != bgParams.marginBottom ||
    oldDelegate.bgParams.borderColor != bgParams.borderColor;
  }
}

class _PageRasterInkLayerPainter extends CustomPainter {
  _PageRasterInkLayerPainter({
    super.repaint,
    required this.manager,
    required this.invert,
    required this.quadTree,
    required this.committedStrokes,
    required this.pendingStrokes,
    required this.pendingGeneration,
    required this.page,
    required this.primaryColor,
    required this.pageIndex,
    required this.totalPages,
    required this.currentScale,
    required this.devicePixelRatio,
    required this.defaultTextStyle,
    required this.showPageIndicator,
    this.lineHeight,
    this.lineThickness,
    this.lineColor,
    required this.tiledCache,
    required this.liveStrokes,
  });

  final PageRasterCacheManager manager;
  final bool invert;
  final QuadTree<Stroke>? quadTree;
  final List<Stroke> committedStrokes;
  final List<Stroke> pendingStrokes;
  final int pendingGeneration;
  final EditorPage page;
  final Color primaryColor;
  final int pageIndex;
  final int totalPages;
  final double currentScale;
  final double devicePixelRatio;
  final TextStyle defaultTextStyle;
  final bool showPageIndicator;
  final int? lineHeight;
  final double? lineThickness;
  final Color? lineColor;
  final TiledStrokePictureCache tiledCache;
  final _LiveStrokeList liveStrokes;

  @override
  void paint(Canvas canvas, Size size) {
    final idealRes = currentScale * devicePixelRatio;
    final inkParams = PageRasterInkParams(
      invert: invert,
      strokes: committedStrokes,
      page: page,
      primaryColor: primaryColor,
      pageIndex: pageIndex,
      totalPages: totalPages,
      currentScale: currentScale,
      defaultTextStyle: defaultTextStyle,
      lineHeight: lineHeight,
      lineThickness: lineThickness,
      lineColor: lineColor,
    );
    final entry = manager.inkForOrSchedule(
      pageIndex: pageIndex,
      pageSize: size,
      scale: currentScale,
      devicePixelRatio: devicePixelRatio,
      params: inkParams,
    );

    final isDrawing = pendingStrokes.isNotEmpty || Pen.currentStroke != null;
    bool useVectorFallback = isDrawing || entry == null;
    if (entry != null && !useVectorFallback) {
      if (entry.strokeCount > committedStrokes.length) {
        useVectorFallback = true;
      } else if (!pageRasterCacheResCoversTarget(entry.res, idealRes) && PageRasterCacheManager.viewportSettled) {
        useVectorFallback = true;
      }
    }

    if (useVectorFallback) {
      final isInitialLoad = tiledCache.shouldDeferMeshWarmup;
      final idleFill = Pen.currentStroke == null && !Eraser.isDragging && !TiledStrokePictureCache.viewportMoving;
      final budget = isInitialLoad ? 48 : (idleFill ? TiledStrokePictureCache.idleTileBudgetMs : 8);

      tiledCache.paint(
        canvas: canvas,
        size: size,
        invert: invert,
        strokes: liveStrokes.strokes,
        page: page,
        primaryColor: primaryColor,
        pageIndex: pageIndex,
        totalPages: totalPages,
        currentScale: currentScale,
        enableRasterLod: true,
        followLiveViewportScale: true,
        defaultTextStyle: defaultTextStyle,
        lineHeight: lineHeight,
        lineThickness: lineThickness,
        lineColor: lineColor,
        deferRaster: Eraser.isDragging || Pen.currentStroke != null,
        tileRecordBudgetMs: budget,
        maxNewTilesPerPaint: isInitialLoad ? 64 : (idleFill ? 8 : 2),
      );
    } else {
      paintPageCacheImage(
        canvas,
        size,
        entry!,
        targetRes: idealRes,
        lowQualityFilter: !PageRasterCacheManager.viewportSettled,
      );
      
      if (entry.strokeCount < committedStrokes.length) {
        CanvasPainter(
          invert: invert,
          strokes: committedStrokes.sublist(entry.strokeCount),
          quadTree: null, 
          laserStrokes: const [],
          currentStroke: null,
          currentSelection: null,
          primaryColor: primaryColor,
          page: page,
          showPageIndicator: false,
          pageIndex: pageIndex,
          totalPages: totalPages,
          currentScale: currentScale,
          defaultTextStyle: defaultTextStyle,
          lineHeight: lineHeight,
          lineThickness: lineThickness?.toDouble(),
          lineColor: lineColor,
          doneSelecting: true,
          preferPathFill: false,
        ).paint(canvas, size);
      }
    }

    if (pendingStrokes.isNotEmpty) {
      CanvasPainter(
        invert: invert,
        strokes: const [],
        pendingStrokes: pendingStrokes,
        laserStrokes: const [],
        currentStroke: null,
        currentSelection: null,
        primaryColor: primaryColor,
        page: page,
        showPageIndicator: false,
        pageIndex: pageIndex,
        totalPages: totalPages,
        currentScale: currentScale,
        defaultTextStyle: defaultTextStyle,
        lineHeight: lineHeight,
        lineThickness: lineThickness?.toDouble(),
        lineColor: lineColor,
        doneSelecting: true,
      ).paint(canvas, size);
    }

    if (showPageIndicator) {
      CanvasPainter(
        invert: invert,
        strokes: const [],
        laserStrokes: const [],
        currentStroke: null,
        currentSelection: null,
        primaryColor: primaryColor,
        page: page,
        showPageIndicator: true,
        pageIndex: pageIndex,
        totalPages: totalPages,
        currentScale: currentScale,
        defaultTextStyle: defaultTextStyle,
        lineHeight: lineHeight,
        lineThickness: lineThickness?.toDouble(),
        lineColor: lineColor,
        doneSelecting: true,
      ).paint(canvas, size);
    }
  }

  @override
  bool shouldRepaint(covariant _PageRasterInkLayerPainter oldDelegate) {
    return oldDelegate.manager != manager ||
    oldDelegate.invert != invert ||
    oldDelegate.committedStrokes.length != committedStrokes.length ||
    oldDelegate.page != page ||
    oldDelegate.primaryColor != primaryColor ||
    oldDelegate.pageIndex != pageIndex ||
    oldDelegate.totalPages != totalPages ||
    oldDelegate.defaultTextStyle != defaultTextStyle ||
    oldDelegate.showPageIndicator != showPageIndicator ||
    oldDelegate.lineHeight != lineHeight ||
    oldDelegate.lineThickness != lineThickness ||
    oldDelegate.lineColor != lineColor ||
    oldDelegate.currentScale != currentScale ||
    oldDelegate.devicePixelRatio != devicePixelRatio ||
    oldDelegate.pendingGeneration != pendingGeneration ||
    oldDelegate.pendingStrokes.length != pendingStrokes.length ||
    oldDelegate.tiledCache != tiledCache ||
    oldDelegate.liveStrokes != liveStrokes;
  }
}

class _PendingRasterJob {
  const _PendingRasterJob({
    required this.tileRect,
    required this.bakeScale,
    required this.dpr,
    required this.fineInk,
    required this.strokeCount,
  });

  final Rect tileRect;
  final double bakeScale;
  final double dpr;
  final bool fineInk;
  final int strokeCount;
}

/// Tweaks for the temporary raster LOD (the bitmap tiles you see while
/// committed ink is not drawn as live vectors).
///
/// Edit these constants in
/// `lib/components/canvas/inner_canvas.dart` → [RasterLodTuning].
///
/// - Zoom curve: [vectorLodMinScale] and the body of
///   [TiledStrokePictureCache.rasterQuality] / [TiledStrokePictureCache.maxRasterEdgePxForScale].
/// - Stroke-count curve: [sparseStrokeCount] / [mediumStrokeCount] /
///   [denseStrokeCount] and the matching `*QualityMul` values.
/// - Ballpoint / fountain / calligraphy only: [fineInkQualityBoost] and
///   [fineInkCapMul]. Other tools keep the zoom+density curve without this
///   extra sharpness.
abstract final class RasterLodTuning {
  /// Above this canvas scale, tiles stay as vectors (no bitmap LOD).
  static const vectorLodMinScale = 1.5;

  /// Page stroke-count breakpoints. [mediumQualityMul] is 1.0 so a typical
  /// page matches the previous zoom-only curve.
  static const sparseStrokeCount = 28;
  static const mediumStrokeCount = 90;
  static const denseStrokeCount = 200;
  static const sparseQualityMul = 1.18;
  static const mediumQualityMul = 1.08;
  static const denseQualityMul = 0.95;

  /// Extra pixels-per-logical-pixel for tiles that contain ballpoint,
  /// fountain, or calligraphy ink. 2.0 ≈ twice the samples on each edge.
  static const fineInkQualityBoost = 1.5;

  /// Raises the per-tile bitmap cap for those same pens so the boost is
  /// not immediately clipped (e.g. 1280 → 2240 at 1×).
  static const fineInkCapMul = 1.80;

  /// Static docked page-sidebar previews — sharper than live pan/zoom LOD.
  static const sidebarPreviewQualityMul = 1.35;

  static bool isFineInkTool(ToolId id) {
    return id == ToolId.ballpointPen ||
    id == ToolId.fountainPen ||
    id == ToolId.calligraphyPen;
  }
}

class TiledStrokePictureCache {
  static const tileSize = 512.0;
  static const _cullPadding = 128.0;
  static const idleTileBudgetMs = 12;
  static const idleRasterBudgetMs = 16;

  /// Absolute ceiling for a single tile bitmap.
  static const maxRasterEdgePx = 4096;
  static const maxConcurrentRasters = 1;
  static const vectorLodMinScale = RasterLodTuning.vectorLodMinScale;

  /// True while the page list is scrolling/flinging or the canvas is
  /// panning/zooming. Mesh upgrades wait until this is false.
  static bool get viewportMoving => PageRasterCacheManager.viewportMoving;
  static set viewportMoving(bool value) {
    PageRasterCacheManager.updateViewportMoving(value);
  }

  /// True while a sidebar/split resize is animating. Used to ignore pan-idle
  /// signals from bounding-box jitter without blocking raster LOD bakes.
  static bool get layoutResizeSession =>
  PageRasterCacheManager.layoutResizeSession;

  static bool get layoutOccluded => PageRasterCacheManager.layoutOccluded;

  static void pushLayoutOcclusion() =>
  PageRasterCacheManager.pushLayoutOcclusion();

  static void popLayoutOcclusion() => PageRasterCacheManager.popLayoutOcclusion();

  /// False between a pan/zoom and [viewportSettleDelay]. Used to delay
  /// expensive path-only mesh upgrades, not raster LOD (that follows zoom).
  static bool get viewportSettled => PageRasterCacheManager.viewportSettled;
  static set viewportSettled(bool value) =>
  PageRasterCacheManager.viewportSettled = value;

  /// Delay before treating the viewport as settled after motion stops.
  static Duration get viewportSettleDelay =>
  DisplayInkFeel.instance.viewportSettleDelay;

  /// False while the quantized zoom LOD is still changing. After it has
  /// been still for [viewportSettleDelay], visible tiles bake once at that
  /// LOD — even if the viewport is still coasting from inertia — so later
  /// pan/fling samples those bitmaps instead of retessellating vectors.
  static bool zoomLodSettled = true;

  /// Bumped when motion starts (switch to textures) and when zoom has been
  /// still long enough to bake a raster LOD for that rest scale.
  static ValueNotifier<int> get lodEpoch => PageRasterCacheManager.lodEpoch;

  static Timer? _tileZoomSettleTimer;
  static double _tileZoomLod = 0;
  static double? _tileLiveViewportScale;

  /// Tests bake with [ui.Picture.toImageSync] so a paint can finish in-frame.
  @visibleForTesting
  static bool get debugForceSyncRaster => PageRasterCacheManager.debugForceSyncRaster; // ignore: invalid_use_of_visible_for_testing_member
  @visibleForTesting
  static set debugForceSyncRaster(bool value) {
    PageRasterCacheManager.debugForceSyncRaster = value; // ignore: invalid_use_of_visible_for_testing_member
  }

  /// Drive Samsung-style temporal LOD from pan/zoom motion.
  static void updateViewportMoving(bool moving) =>
  PageRasterCacheManager.updateViewportMoving(moving);

  /// After outline / page-list jumps: clear the moving flag so idle BSON
  /// hydrate is not stuck waiting for a finger-up that never comes.
  static void endProgrammaticViewportJump() =>
  PageRasterCacheManager.endProgrammaticViewportJump();

  static void beginLayoutResizeSession() =>
  PageRasterCacheManager.beginLayoutResizeSession();

  static void endLayoutResizeSession() =>
  PageRasterCacheManager.endLayoutResizeSession();

  /// Live InteractiveViewer scale. Call on every pan/zoom frame so LOD does
  /// not wait for a widget rebuild (which often only happens after drawing).
  static void setViewportScale(double scale) {
    _tileLiveViewportScale = scale;
    _observeTileZoomScale(scale);
    PageRasterCacheManager.setViewportScale(scale);
  }

  static double effectiveScale(double fallback) =>
  _tileLiveViewportScale ?? fallback;

  static bool usesVectorStrokes(double scale) => scale >= vectorLodMinScale;

  static void _observeTileZoomScale(double scale) {
    if (usesVectorStrokes(scale)) {
      _tileZoomSettleTimer?.cancel();
      _tileZoomSettleTimer = null;
      final crossedIntoVector =
      _tileZoomLod > 0 && _tileZoomLod < vectorLodMinScale;
      _tileZoomLod = rasterLodScale(scale);
      zoomLodSettled = true;
      if (crossedIntoVector) lodEpoch.value++;
      return;
    }
    final lod = rasterLodScale(scale);
    if (_tileZoomLod <= 0) {
      _tileZoomLod = lod;
      zoomLodSettled = true;
      return;
    }
    if ((lod - _tileZoomLod).abs() <= 1e-6) return;
    _tileZoomLod = lod;
    zoomLodSettled = false;
    _tileZoomSettleTimer?.cancel();
    _tileZoomSettleTimer = Timer(viewportSettleDelay, () {
      _tileZoomSettleTimer = null;
      zoomLodSettled = true;
      lodEpoch.value++;
      SchedulerBinding.instance.ensureVisualUpdate();
    });
  }

  @visibleForTesting
  static void debugResetViewportLod() {
    PageRasterCacheManager.debugResetViewportLod(); // ignore: invalid_use_of_visible_for_testing_member
    _tileZoomSettleTimer?.cancel();
    _tileZoomSettleTimer = null;
    zoomLodSettled = true;
    _tileZoomLod = 0;
    _tileLiveViewportScale = null;
    debugForceSyncRaster = false;
  }

  final Map<int, ui.Picture> _pictures = {};
  final Map<int, ui.Image> _rasters = {};
  final Map<int, double> _rasterScales = {};
  final Set<int> _pathOnlyKeys = {};
  final Set<int> _fineInkKeys = {};
  final Set<int> _bakingKeys = {};
  int _rasterBakeEpoch = 0;
  final Map<int, _PendingRasterJob> _pendingRasterJobs = {};
  final List<int> _pendingRasterOrder = [];
  bool _bakeScheduled = false;
  SpatialGrid? _grid;
  bool _gridDirty = true;
  int _indexedStrokeCount = -1;
  int _visualSignature = 0;
  bool _disposed = false;
  bool _moreTilesScheduled = false;
  bool _eagerRefillVisibleTiles = false;
  bool _visibleTilesCaughtUp = false;
  int _livePaintedTileCount = 0;
  int _visibleStrokeCount = RasterLodTuning.mediumStrokeCount;

  /// Bumped when a paint left unrecorded visible tiles so the next frame
  /// can record one more without blocking the current frame.
  final recordGeneration = ValueNotifier<int>(0);

  int get recordedTileCount => _pictures.length;

  int get debugLivePaintedTileCount => _livePaintedTileCount;

  int get debugPathOnlyTileCount => _pathOnlyKeys.length;

  int get debugRasterCount => _rasters.length;

  int get debugBakingKeyCount => _bakingKeys.length;

  double? get debugAnyRasterScale =>
  _rasterScales.isEmpty ? null : _rasterScales.values.first;

  Iterable<double> get debugRasterScales => _rasterScales.values;

  ui.Image? get debugFirstRaster =>
  _rasters.isEmpty ? null : _rasters.values.first;

  double? debugRasterScaleFor(int tileKey) => _rasterScales[tileKey];

  bool get isDisposed => _disposed;

  bool get willEagerRefillVisibleTiles => _eagerRefillVisibleTiles;

  /// Mesh triangulation waits until every visible tile has a Picture
  /// (path-only is enough). That keeps the first seconds after open on
  /// cheap `drawPicture` instead of fighting the UI isolate.
  bool get shouldDeferMeshWarmup => !_visibleTilesCaughtUp;

  void dispose() {
    _disposed = true;
    _rasterBakeEpoch++;
    for (final picture in _pictures.values) {
      picture.dispose();
    }
    _pictures.clear();
    _disposeAllRasters();
    _clearPendingRasters();
    _bakingKeys.clear();
    _pathOnlyKeys.clear();
    _fineInkKeys.clear();
    _visibleTilesCaughtUp = false;
    recordGeneration.dispose();
  }

  void _abandonInFlightRasters() {
    _rasterBakeEpoch++;
    _bakingKeys.clear();
    _clearPendingRasters();
  }

  void invalidateAll({bool eagerRefill = false}) {
    _abandonInFlightRasters();
    for (final picture in _pictures.values) {
      picture.dispose();
    }
    _pictures.clear();
    _disposeAllRasters();
    _pathOnlyKeys.clear();
    _fineInkKeys.clear();
    _gridDirty = true;
    _visibleTilesCaughtUp = false;
    _eagerRefillVisibleTiles = eagerRefill;
  }

  void invalidateRect(Rect rect, {bool eagerRefill = true, double? padding}) {
    if (!rect.isFinite) {
      invalidateAll(eagerRefill: true);
      return;
    }
    // Do not bump [_rasterBakeEpoch] / cancel every in-flight bake. Eraser
    // hits only dirty a few tiles; killing unrelated rasters is the FPS dip
    // when ink is actually deleted.
    final inflated = rect.inflate(padding ?? _cullPadding);
    final startX = (inflated.left / tileSize).floor();
    final endX = (inflated.right / tileSize).floor();
    final startY = (inflated.top / tileSize).floor();
    final endY = (inflated.bottom / tileSize).floor();
    for (var tx = startX; tx <= endX; tx++) {
      for (var ty = startY; ty <= endY; ty++) {
        _discardTile(_tileKey(tx, ty));
      }
    }
    _gridDirty = true;
    _visibleTilesCaughtUp = false;
    _eagerRefillVisibleTiles = eagerRefill;
  }

  void _discardTile(int key) {
    _pictures.remove(key)?.dispose();
    _disposeRaster(key);
    _pathOnlyKeys.remove(key);
    _fineInkKeys.remove(key);
    _pendingRasterJobs.remove(key);
    _pendingRasterOrder.remove(key);
  }

  void paint({
    required Canvas canvas,
    required Size size,
    required bool invert,
    required List<Stroke> strokes,
    required EditorPage page,
    required Color primaryColor,
    required int pageIndex,
    required int totalPages,
    required double currentScale,
    bool enableRasterLod = true,
    bool followLiveViewportScale = true,
    required TextStyle defaultTextStyle,
    int? lineHeight,
    double? lineThickness,
    Color? lineColor,
    int maxNewTilesPerPaint = 1,
    int? tileRecordBudgetMs,
    bool liveMissingTiles = false,
    bool deferRaster = false,
  }) {
    if (strokes.isEmpty) {
      return;
    }
    _livePaintedTileCount = 0;
    _ensureVisualSignature(
      size: size,
      page: page,
      invert: invert,
      currentScale: currentScale,
      lineHeight: lineHeight,
      lineThickness: lineThickness,
      lineColor: lineColor,
    );

    final pageRect = Offset.zero & size;
    final visible = canvas.getLocalClipBounds().intersect(pageRect);
    if (visible.isEmpty) return;

    _visibleStrokeCount = _countVisibleStrokes(visible, strokes, page);
    if (_visibleStrokeCount <= 0) {
      _visibleStrokeCount = strokes.length;
    }

    final startX = (visible.left / tileSize).floor();
    final endX = (visible.right / tileSize).floor();
    final startY = (visible.top / tileSize).floor();
    final endY = (visible.bottom / tileSize).floor();

    var recordedThisPaint = 0;
    var missingTiles = false;
    var staleRasters = false;
    final forbidRecord = liveMissingTiles;
    // First visible pass and eraser/dirty refill record every clip tile as a
    // Picture (path-only if meshes are cold). Do not live-fill the rest —
    // that is what made pan/zoom/scroll scale with stroke count.
    // Cap refill only while drawing a new stroke. Eraser must refill every
    // discarded tile this frame so deleted ink is gone immediately.
    final capLiveRefill = deferRaster && Pen.currentStroke != null;
    // ALWAYS respect the time budget to avoid UI thread freezes!
    final useTimeBudget =
        !forbidRecord &&
        tileRecordBudgetMs != null &&
        tileRecordBudgetMs > 0;
    
    final tileBudget = capLiveRefill
        ? 2
        : (useTimeBudget
            ? 0x7fffffff
            : maxNewTilesPerPaint);
    final Stopwatch? budgetWatch = useTimeBudget
    ? (Stopwatch()..start())
    : null;
    final dpr = _devicePixelRatio();
    final scale = followLiveViewportScale
    ? effectiveScale(currentScale)
    : currentScale;
    if (enableRasterLod && followLiveViewportScale) {
      _observeTileZoomScale(scale);
      PageRasterCacheManager.setViewportScale(scale);
    }
    final bakeScale = rasterLodScale(scale);
    if (!debugForceSyncRaster) {
      _prunePendingRasters(bakeScale);
    }
    final useVectorLod = usesVectorStrokes(scale);
    final allowRaster =
    enableRasterLod &&
    zoomLodSettled &&
    !viewportMoving &&
    !forbidRecord &&
    !useVectorLod &&
    !deferRaster;
    final rasterBudgetWatch = (allowRaster && debugForceSyncRaster)
    ? (Stopwatch()..start())
    : null;
    final visibleKeys = <int>{};

    void drawTile(int key, Rect tileRect, ui.Picture picture) {
      if (useVectorLod) {
        // Prefer a cheap stale blit while moving; fall back to the recorded
        // Picture so ink never blinks off when rasters are missing.
        if (viewportMoving) {
          final movingRaster = _rasters[key];
          if (movingRaster != null) {
            canvas.drawImageRect(
              movingRaster,
              Rect.fromLTWH(
                0,
                0,
                movingRaster.width.toDouble(),
                movingRaster.height.toDouble(),
              ),
              tileRect,
              Paint()
              ..filterQuality =
              DisplayInkFeel.instance.movingBlitFilterQuality,
            );
            return;
          }
        }
        canvas.drawPicture(picture);
        return;
      }
      final raster = _rasters[key];
      // Blit a zoom LOD raster when we have one — settled, moving, and while
      // the user is drawing a new stroke on the live overlay.
      if (raster != null) {
        final stale = _rasterScaleStale(_rasterScales[key] ?? 0, scale);
        canvas.drawImageRect(
          raster,
          Rect.fromLTWH(
            0,
            0,
            raster.width.toDouble(),
            raster.height.toDouble(),
          ),
          tileRect,
          Paint()
          ..filterQuality = viewportMoving
          ? DisplayInkFeel.instance.movingBlitFilterQuality
          : (stale ? FilterQuality.low : FilterQuality.medium),
        );
        return;
      }
      // No raster yet (cold tile, mid-zoom before bake, eviction): keep drawing
      // the Picture so strokes do not blink off during pan/zoom. Recording new
      // tiles is still forbidden while viewportMoving (tileBudget == 0).
      canvas.drawPicture(picture);
    }

    bool rasterOverTime() =>
    rasterBudgetWatch != null &&
    rasterBudgetWatch.elapsedMilliseconds >= idleRasterBudgetMs;

    bool tryRasterize(int key, Rect tileRect, ui.Picture picture) {
      if (!allowRaster) return false;
      if (!_rasterNeedsBake(key, tileRect, scale, dpr)) {
        return false;
      }
      if (_bakingKeys.contains(key) || _pendingRasterJobs.containsKey(key)) {
        return true;
      }
      if (debugForceSyncRaster) {
        if (rasterOverTime()) return false;
        final image = _rasterizePicture(
          picture,
          tileRect,
          scale,
          dpr,
          fineInk: _fineInkKeys.contains(key),
          strokeCount: _visibleStrokeCount,
        );
        if (image == null) {
          _rasterScales[key] = bakeScale;
          return true;
        }
        _disposeRaster(key);
        _rasters[key] = image;
        _rasterScales[key] = bakeScale;
        return true;
      }
      // Enqueue only — never tessellate or toImage on this paint frame.
      // The current raster stays on screen until the idle bake finishes.
      _enqueueBackgroundRaster(key, tileRect, bakeScale, dpr);
      return true;
    }

    for (var ty = startY; ty <= endY; ty++) {
      for (var tx = startX; tx <= endX; tx++) {
        final tileRect = _tileRect(tx, ty).intersect(pageRect);
        if (tileRect.isEmpty) continue;
        final key = _tileKey(tx, ty);
        visibleKeys.add(key);
        final existing = _pictures[key];
        final budgetMs = tileRecordBudgetMs;
        final overTime =
        budgetWatch != null &&
        budgetMs != null &&
        budgetWatch.elapsedMilliseconds >= budgetMs;
        if (existing != null) {
          if (_pathOnlyKeys.contains(key) &&
            !forbidRecord &&
            viewportSettled &&
            !viewportMoving &&
            Pen.currentStroke == null &&
            !_rasterScaleStale(_rasterScales[key] ?? 0, scale) &&
            _visibleTilesCaughtUp &&
            recordedThisPaint < tileBudget &&
            !overTime) {
            final upgradeStrokes = _strokesForTile(tileRect, strokes, page);
          if (upgradeStrokes.isNotEmpty &&
            !_tileNeedsMeshBuild(upgradeStrokes)) {
            existing.dispose();
          final upgraded = _recordTile(
            tileRect: tileRect,
            tileStrokes: upgradeStrokes,
            page: page,
            invert: invert,
            primaryColor: primaryColor,
            pageIndex: pageIndex,
            totalPages: totalPages,
            currentScale: scale,
            defaultTextStyle: defaultTextStyle,
              lineHeight: lineHeight,
              lineThickness: lineThickness,
              lineColor: lineColor,
          );
          _pictures[key] = upgraded;
          _pathOnlyKeys.remove(key);
          _markFineInk(key, upgradeStrokes);
          _disposeRaster(key);
          recordedThisPaint++;
          tryRasterize(key, tileRect, upgraded);
          drawTile(key, tileRect, upgraded);
          continue;
            }
            }
            final needsRaster =
            allowRaster && _rasterNeedsBake(key, tileRect, scale, dpr);
            if (needsRaster && !tryRasterize(key, tileRect, existing)) {
              staleRasters = true;
            }
            drawTile(key, tileRect, existing);
            continue;
        }
        final tileStrokes = _strokesForTile(tileRect, strokes, page);
        if (tileStrokes.isEmpty) continue;
        final needsMesh = _tileNeedsMeshBuild(tileStrokes);
        final canRecord =
        !forbidRecord && recordedThisPaint < tileBudget && !overTime;
        if (!canRecord) {
          missingTiles = true;
          continue;
        }
        final pathOnly = needsMesh;
        final picture = _recordTile(
          tileRect: tileRect,
          tileStrokes: tileStrokes,
          page: page,
          invert: invert,
          primaryColor: primaryColor,
          pageIndex: pageIndex,
          totalPages: totalPages,
          currentScale: scale,
          defaultTextStyle: defaultTextStyle,
            lineHeight: lineHeight,
            lineThickness: lineThickness,
            lineColor: lineColor,
        );
        _pictures[key] = picture;
        _markFineInk(key, tileStrokes);
        if (pathOnly) {
          _pathOnlyKeys.add(key);
        } else {
          _pathOnlyKeys.remove(key);
        }
        recordedThisPaint++;
        if (!tryRasterize(key, tileRect, picture)) {
          staleRasters = true;
        }
        drawTile(key, tileRect, picture);
      }
    }
    _evictOffscreenRasters(visibleKeys);
    if (missingTiles) {
      _visibleTilesCaughtUp = false;
      _scheduleMoreTiles();
    } else {
      _visibleTilesCaughtUp = true;
      _eagerRefillVisibleTiles = false;
      if (allowRaster && staleRasters) {
        _scheduleMoreTiles();
      }
    }
    if (allowRaster &&
      _pendingRasterOrder.isNotEmpty &&
      !debugForceSyncRaster) {
      _scheduleBackgroundBake();
      }
  }

  void _scheduleMoreTiles() {
    if (_moreTilesScheduled || _disposed) return;
    _moreTilesScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _moreTilesScheduled = false;
      if (!_disposed) {
        recordGeneration.value++;
      }
    });
  }

  void _clearPendingRasters() {
    _pendingRasterJobs.clear();
    _pendingRasterOrder.clear();
  }

  void _prunePendingRasters(double bakeScale) {
    if (_pendingRasterJobs.isEmpty) return;
    _pendingRasterJobs.removeWhere(
      (key, job) => (job.bakeScale - bakeScale).abs() > 1e-6,
    );
    _pendingRasterOrder.removeWhere((k) => !_pendingRasterJobs.containsKey(k));
  }

  void _enqueueBackgroundRaster(
    int key,
    Rect tileRect,
    double bakeScale,
    double dpr,
  ) {
    if (_pendingRasterJobs.containsKey(key)) return;
    _pendingRasterJobs[key] = _PendingRasterJob(
      tileRect: tileRect,
      bakeScale: bakeScale,
      dpr: dpr,
      fineInk: _fineInkKeys.contains(key),
      strokeCount: _visibleStrokeCount,
    );
    _pendingRasterOrder.add(key);
    _scheduleBackgroundBake();
  }

  void _scheduleBackgroundBake() {
    if (_bakeScheduled || _disposed || debugForceSyncRaster) return;
    if (viewportMoving) return;
    if (_pendingRasterOrder.isEmpty && _bakingKeys.isEmpty) return;
    _bakeScheduled = true;
    // Do not use Priority.idle: Flutter skips idle tasks while any ticker
    // is running and will not resume them, so zoom LOD bakes stalled until
    // the next widget rebuild (usually drawing a stroke).
    Future<void>.delayed(Duration.zero, () {
      _bakeScheduled = false;
      if (_disposed) return;
      _pumpOneBackgroundRaster();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _pumpOneBackgroundRaster() {
    if (_disposed) return;
    if (viewportMoving) return;
    if (Pen.currentStroke != null || Eraser.isDragging) return;
    if (_bakingKeys.length >= maxConcurrentRasters) return;
    while (_pendingRasterOrder.isNotEmpty) {
      final key = _pendingRasterOrder.removeAt(0);
      final job = _pendingRasterJobs.remove(key);
      if (job == null) continue;
      final picture = _pictures[key];
      if (picture == null) continue;
      if (usesVectorStrokes(effectiveScale(job.bakeScale))) continue;
      if (!_rasterNeedsBake(
        key,
        job.tileRect,
        effectiveScale(job.bakeScale),
        job.dpr,
        fineInk: job.fineInk,
        strokeCount: job.strokeCount,
      ) &&
      _rasters.containsKey(key)) {
        continue;
      }
      _startAsyncRaster(key, job);
      break;
    }
    if (_pendingRasterOrder.isNotEmpty) {
      _scheduleBackgroundBake();
    }
  }

  void _startAsyncRaster(int key, _PendingRasterJob job) {
    final tileRect = job.tileRect;
    final bakeScale = job.bakeScale;
    final dpr = job.dpr;
    if (tileRect.width < 1e-3 || tileRect.height < 1e-3) return;
    final epoch = _rasterBakeEpoch;
    _bakingKeys.add(key);
    () async {
      ui.Picture? mapped;
      try {
        // Yield so the settle callback returns before tessellation.
        await Future<void>.delayed(Duration.zero);
        if (_disposed || epoch != _rasterBakeEpoch) return;
        final picture = _pictures[key];
        if (picture == null) return;
        final pixelScale = effectiveScale(bakeScale);
        final w = _rasterEdgePx(
          tileRect.width,
          pixelScale,
          dpr,
          fineInk: job.fineInk,
          strokeCount: job.strokeCount,
        );
        final h = _rasterEdgePx(
          tileRect.height,
          pixelScale,
          dpr,
          fineInk: job.fineInk,
          strokeCount: job.strokeCount,
        );
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(
          recorder,
          Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        );
        canvas.scale(w / tileRect.width, h / tileRect.height);
        canvas.translate(-tileRect.left, -tileRect.top);
        canvas.drawPicture(picture);
        mapped = recorder.endRecording();
        final image = await mapped.toImage(w, h);
        if (_disposed ||
          epoch != _rasterBakeEpoch ||
          !_pictures.containsKey(key)) {
          image.dispose();
        return;
          }
          final current = effectiveScale(bakeScale);
          if (usesVectorStrokes(current) ||
            (rasterLodScale(current) - bakeScale).abs() > 1e-6) {
            image.dispose();
          return;
            }
            _disposeRaster(key);
            _rasters[key] = image;
            _rasterScales[key] = bakeScale;
            if (!_disposed) {
              recordGeneration.value++;
            }
      } catch (_) {
        // Keep the previous raster (if any). A later paint can enqueue again.
      } finally {
        mapped?.dispose();
        if (epoch == _rasterBakeEpoch) {
          _bakingKeys.remove(key);
          _scheduleBackgroundBake();
        }
      }
    }();
  }

  void _disposeRaster(int key) {
    _rasters.remove(key)?.dispose();
    _rasterScales.remove(key);
  }

  void _disposeAllRasters() {
    for (final image in _rasters.values) {
      image.dispose();
    }
    _rasters.clear();
    _rasterScales.clear();
  }

  void _evictOffscreenRasters(Set<int> visibleKeys) {
    final scale = _tileLiveViewportScale ?? 1.0;
    final extra = scale >= 2.5
    ? 3
    : scale >= 1.5
    ? 5
    : 8;
    final keep = visibleKeys.length + extra;
    if (_rasters.length <= keep) return;
    final stale = _rasters.keys.where((k) => !visibleKeys.contains(k)).toList();
    for (final key in stale) {
      if (_rasters.length <= keep) break;
      _disposeRaster(key);
    }
  }

  /// Fraction of on-screen tile pixels to bake.
  /// ~1× stays at 88% (many medium tiles). Below 1× tiles shrink on screen
  /// so we spend the budget on sharpness — 0.3–0.7 was too soft.
  ///
  /// [strokeCount] defaults to a typical page so existing zoom-only callers
  /// keep the previous curve. [fineInk] is ballpoint / fountain / calligraphy
  /// only. Tweaks: [RasterLodTuning].
  static double rasterQuality(
    double scale, {
      int strokeCount = RasterLodTuning.mediumStrokeCount,
      bool fineInk = false,
    }) {
    final s = scale.clamp(0.25, vectorLodMinScale);
    final double zoom;
    if (s < 1.0) {
      zoom = 1.08 + (s - 0.25) / 0.75 * (0.88 - 1.08);
    } else if (s >= 2.0) {
      zoom = 1.0;
    } else {
      zoom = 0.88 + (s - 1.0) * 0.12;
    }
    var q = zoom * densityQualityMul(strokeCount);
    if (fineInk) q *= RasterLodTuning.fineInkQualityBoost;
    return q;
    }

    /// Linear blend of [RasterLodTuning] sparse → medium → dense multipliers.
    static double densityQualityMul(int strokeCount) {
      const sparse = RasterLodTuning.sparseStrokeCount;
      const medium = RasterLodTuning.mediumStrokeCount;
      const dense = RasterLodTuning.denseStrokeCount;
      if (strokeCount <= sparse) return RasterLodTuning.sparseQualityMul;
      if (strokeCount >= dense) return RasterLodTuning.denseQualityMul;
      if (strokeCount <= medium) {
        final t = (strokeCount - sparse) / (medium - sparse);
        return RasterLodTuning.sparseQualityMul +
        (RasterLodTuning.mediumQualityMul -
        RasterLodTuning.sparseQualityMul) *
        t;
      }
      final t = (strokeCount - medium) / (dense - medium);
      return RasterLodTuning.mediumQualityMul +
      (RasterLodTuning.denseQualityMul - RasterLodTuning.mediumQualityMul) *
      t;
    }

    /// Per-tile bitmap cap. Grows with zoom because visible tile count falls
    /// roughly with scale — 1.5–4× can afford much sharper rasters than 1×.
    static int maxRasterEdgePxForScale(double scale, {bool fineInk = false}) {
      final s = scale.clamp(0.25, vectorLodMinScale);
      final int base;
      if (s <= 1.0) {
        base = 1280;
      } else if (s >= 3.5) {
        base = 4096;
      } else if (s <= 1.5) {
        base = (1280 + (s - 1.0) / 0.5 * (2048 - 1280)).round();
      } else if (s <= 2.0) {
        base = (2048 + (s - 1.5) / 0.5 * (2560 - 2048)).round();
      } else if (s <= 3.0) {
        base = (2560 + (s - 2.0) / 1.0 * (3584 - 2560)).round();
      } else {
        base = (3584 + (s - 3.0) / 0.5 * (4096 - 3584)).round();
      }
      if (!fineInk) return base;
      return (base * RasterLodTuning.fineInkCapMul).round().clamp(
        32,
        maxRasterEdgePx,
      );
    }

    /// Quarter-stop zoom buckets so a rest at 2.9–3.1 shares one raster LOD.
    /// Pan/fling at that zoom keeps sampling the same bitmaps.
    static double rasterLodScale(double scale) {
      final s = scale.clamp(0.25, 8.0);
      return (s * 4).round() / 4;
    }

    static bool _rasterScaleStale(double baked, double current) {
      if (baked <= 1e-6) return true;
      return (baked - rasterLodScale(current)).abs() > 1e-6;
    }

    bool _rasterNeedsBake(
      int key,
      Rect tileRect,
      double scale,
      double dpr, {
        bool? fineInk,
        int? strokeCount,
      }) {
      if (_rasterScaleStale(_rasterScales[key] ?? 0, scale)) return true;
      final raster = _rasters[key];
      if (raster == null) return true;
      final want = _rasterEdgePx(
        tileRect.width,
        scale,
        dpr,
        fineInk: fineInk ?? _fineInkKeys.contains(key),
        strokeCount: strokeCount ?? _visibleStrokeCount,
      );
      return raster.width < (want * 0.88).round();
      }

      static double _devicePixelRatio() {
        return ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1.0;
      }

      static int _rasterEdgePx(
        double logical,
        double scale,
        double dpr, {
          bool fineInk = false,
          int strokeCount = RasterLodTuning.mediumStrokeCount,
        }) {
        final px =
        (logical *
        scale *
        dpr *
        rasterQuality(
          scale,
          strokeCount: strokeCount,
          fineInk: fineInk,
        ))
        .round();
        final cap = maxRasterEdgePxForScale(
          scale,
          fineInk: fineInk,
        ).clamp(32, maxRasterEdgePx);
        return px.clamp(32, cap);
        }

        ui.Image? _rasterizePicture(
          ui.Picture picture,
          Rect tileRect,
          double scale,
          double dpr, {
            bool fineInk = false,
            int strokeCount = RasterLodTuning.mediumStrokeCount,
          }) {
          if (tileRect.width < 1e-3 || tileRect.height < 1e-3) return null;
          final w = _rasterEdgePx(
            tileRect.width,
            scale,
            dpr,
            fineInk: fineInk,
            strokeCount: strokeCount,
          );
          final h = _rasterEdgePx(
            tileRect.height,
            scale,
            dpr,
            fineInk: fineInk,
            strokeCount: strokeCount,
          );
          // Picture commands are in page space (the tile may not start at 0,0).
          // Map tileRect → the bitmap so drawImageRect(tileRect) matches the live
          // overlay. toImageSync(w,h) alone is 1:1 from the picture origin and
          // would shift/scale ink after pen-up.
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(
            recorder,
            Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          );
          canvas.scale(w / tileRect.width, h / tileRect.height);
          canvas.translate(-tileRect.left, -tileRect.top);
          canvas.drawPicture(picture);
          final mapped = recorder.endRecording();
          try {
            return mapped.toImageSync(w, h);
          } catch (_) {
            return null;
          } finally {
            mapped.dispose();
          }
          }

          void _ensureGrid(List<Stroke> strokes) {
            if (!_gridDirty && _indexedStrokeCount == strokes.length) return;
            final grid = SpatialGrid(cellSize: tileSize / 2);
            for (var i = 0; i < strokes.length; i++) {
              final bounds = strokes[i].bounds;
              if (bounds.isFinite && !bounds.isEmpty) {
                grid.insert(i, bounds);
              }
            }
            _grid = grid;
            _indexedStrokeCount = strokes.length;
            _gridDirty = false;
          }

          void _ensureVisualSignature({
    required Size size,
    required EditorPage page,
    required bool invert,
    required double currentScale,
    required int? lineHeight,
    required double? lineThickness,
    required Color? lineColor,
  }) {
    final signature = Object.hash(
      size.width,
      size.height,
      page,
      invert,
      lineHeight,
      lineThickness,
      lineColor?.toARGB32(),
    );
    if (_visualSignature == signature) return;
    if (_pictures.isNotEmpty) {
      invalidateAll(eagerRefill: true);
    }
    _visualSignature = signature;
  }

  ui.Picture _recordTile({
    required Rect tileRect,
    required List<Stroke> tileStrokes,
    required EditorPage page,
    required bool invert,
    required Color primaryColor,
    required int pageIndex,
    required int totalPages,
    required double currentScale,
    required TextStyle defaultTextStyle,
    int? lineHeight,
    double? lineThickness,
    Color? lineColor,
  }) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, tileRect);
    canvas.save();
    canvas.clipRect(tileRect);
    _paintTileContents(
      canvas: canvas,
      tileStrokes: tileStrokes,
      page: page,
      invert: invert,
      primaryColor: primaryColor,
      pageIndex: pageIndex,
      totalPages: totalPages,
      currentScale: currentScale,
      defaultTextStyle: defaultTextStyle,
      lineHeight: lineHeight,
      lineThickness: lineThickness,
      lineColor: lineColor,
    );
    canvas.restore();
    return recorder.endRecording();
  }

  void _paintTileContents({
    required Canvas canvas,
    required List<Stroke> tileStrokes,
    required EditorPage page,
    required bool invert,
    required Color primaryColor,
    required int pageIndex,
    required int totalPages,
    required double currentScale,
    required TextStyle defaultTextStyle,
    int? lineHeight,
    double? lineThickness,
    Color? lineColor,
  }) {
    final mergedMeshes = _mergeSolidStrokeMeshesByColor(
      tileStrokes,
      currentScale,
    );

    CanvasPainter(
      invert: invert,
      strokes: tileStrokes,
      laserStrokes: const [],
      currentStroke: null,
      currentSelection: null,
      primaryColor: primaryColor,
      page: page,
      showPageIndicator: false,
      pageIndex: pageIndex,
      totalPages: totalPages,
      currentScale: currentScale,
      defaultTextStyle: defaultTextStyle,
      lineHeight: lineHeight,
      lineThickness: lineThickness?.toDouble(),
      lineColor: lineColor,
      doneSelecting: true,
      batchedStrokes: mergedMeshes.isEmpty ? null : mergedMeshes,
      preferPathFill: false,
    ).paint(canvas, page.size);
  }

  void _markFineInk(int key, List<Stroke> strokes) {
    var fine = false;
    for (final stroke in strokes) {
      if (RasterLodTuning.isFineInkTool(stroke.toolId)) {
        fine = true;
        break;
      }
    }
    if (fine) {
      _fineInkKeys.add(key);
    } else {
      _fineInkKeys.remove(key);
    }
  }

  int _countVisibleStrokes(Rect visible, List<Stroke> strokes, EditorPage page) {
            if (strokes.isEmpty) return 0;
            final query = visible.inflate(_cullPadding);
            _ensureGrid(strokes);
            final grid = _grid;
            if (grid == null) return strokes.length;
            var n = 0;
            for (final index in grid.query(query)) {
              if (index >= 0 &&
                index < strokes.length &&
                strokes[index].bounds.overlaps(query)) {
                n++;
              }
            }
            return n;
          }

          List<Stroke> _strokesForTile(Rect tileRect, List<Stroke> strokes, EditorPage page) {
            final queryRect = tileRect.inflate(_cullPadding);
            _ensureGrid(strokes);
            final candidateIndices = _grid?.query(queryRect) ?? const <int>[];
            final tileStrokes = <Stroke>[];
            for (final index in candidateIndices) {
              if (index >= 0 && index < strokes.length) {
                final stroke = strokes[index];
                if (stroke.bounds.overlaps(queryRect)) {
                  tileStrokes.add(stroke);
                }
              }
            }
            return tileStrokes;
          }

          static bool _tileNeedsMeshBuild(List<Stroke> tileStrokes) {
            for (final stroke in tileStrokes) {
              if (stroke.needsTileMeshWarmup) return true;
            }
            return false;
          }

          static Rect _tileRect(int tx, int ty) {
            return Rect.fromLTWH(tx * tileSize, ty * tileSize, tileSize, tileSize);
          }

          static int _tileKey(int tx, int ty) {
            return (tx + 0x3fffffff) ^ ((ty + 0x3fffffff) << 32);
          }

          ui.Image? composeSidebarPreviewIfReady({
            required Size pageSize,
            required double previewScale,
            double? devicePixelRatio,
          }) {
            if (!_sidebarPreviewTilesReady(pageSize)) return null;
            return _composeSidebarPreviewImage(
              pageSize: pageSize,
              previewScale: previewScale,
              dpr: devicePixelRatio ?? _devicePixelRatio(),
            );
          }

          /// Headless high-quality raster for docked page-sidebar previews.
          Future<ui.Image?> bakeSidebarPreviewRaster({
            required Size pageSize,
            required List<Stroke> strokes,
            required EditorPage page,
            required Color primaryColor,
            required int pageIndex,
            required int totalPages,
            required TextStyle defaultTextStyle,
            required double previewScale,
            double? devicePixelRatio,
            bool invert = false,
            int? lineHeight,
            double? lineThickness,
            Color? lineColor,
          }) async {
            if (strokes.isEmpty || pageSize.width <= 0 || pageSize.height <= 0) {
              return null;
            }
            final dpr = devicePixelRatio ?? _devicePixelRatio();
            final wasSync = debugForceSyncRaster;
            final wasMoving = viewportMoving;
            final wasSettled = viewportSettled;
            final wasZoomSettled = zoomLodSettled;
            viewportMoving = false;
            viewportSettled = true;
            zoomLodSettled = true;
            debugForceSyncRaster = true;
            try {
              for (var pass = 0; pass < 16; pass++) {
                final recorder = ui.PictureRecorder();
                final canvas = Canvas(recorder, Offset.zero & pageSize);
                paint(
                  canvas: canvas,
                  size: pageSize,
                  invert: invert,
                  strokes: strokes,
                  page: page,
                  primaryColor: primaryColor,
                  pageIndex: pageIndex,
                  totalPages: totalPages,
                  currentScale: previewScale,
                  enableRasterLod: true,
                  followLiveViewportScale: false,
                  defaultTextStyle: defaultTextStyle,
                    lineHeight: lineHeight,
                    lineThickness: lineThickness,
                    lineColor: lineColor,
                    maxNewTilesPerPaint: 64,
                );
                recorder.endRecording().dispose();
                if (_sidebarPreviewTilesReady(pageSize)) break;
                if (_rasters.isNotEmpty && pass >= 2) break;
                await Future<void>.delayed(Duration.zero);
              }
              return _composeSidebarPreviewImage(
                pageSize: pageSize,
                previewScale: previewScale,
                dpr: dpr,
              );
            } finally {
              debugForceSyncRaster = wasSync;
              viewportMoving = wasMoving;
              viewportSettled = wasSettled;
              zoomLodSettled = wasZoomSettled;
            }
          }

          bool _sidebarPreviewTilesReady(Size pageSize) {
            if (_pictures.isEmpty) return false;
            final pageRect = Offset.zero & pageSize;
            final endX = (pageSize.width / tileSize).floor();
            final endY = (pageSize.height / tileSize).floor();
            var pictured = 0;
            for (var ty = 0; ty <= endY; ty++) {
              for (var tx = 0; tx <= endX; tx++) {
                final tileRect = _tileRect(tx, ty).intersect(pageRect);
                if (tileRect.isEmpty) continue;
                final key = _tileKey(tx, ty);
                if (!_pictures.containsKey(key)) continue;
                pictured++;
                if (!_rasters.containsKey(key)) return false;
              }
            }
            return pictured > 0;
          }

          ui.Image? _composeSidebarPreviewImage({
            required Size pageSize,
            required double previewScale,
            required double dpr,
          }) {
            if (_rasters.isEmpty) return null;
            final outW = _sidebarPreviewEdgePx(pageSize.width, previewScale, dpr);
            final outH = _sidebarPreviewEdgePx(pageSize.height, previewScale, dpr);
            if (outW <= 0 || outH <= 0) return null;

            final recorder = ui.PictureRecorder();
            final canvas = Canvas(
              recorder,
              Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
            );
            final scaleX = outW / pageSize.width;
            final scaleY = outH / pageSize.height;
            final pageRect = Offset.zero & pageSize;
            final startX = 0;
            final endX = (pageSize.width / tileSize).floor();
            final startY = 0;
            final endY = (pageSize.height / tileSize).floor();
            final paint = Paint()..filterQuality = FilterQuality.medium;

            for (var ty = startY; ty <= endY; ty++) {
              for (var tx = startX; tx <= endX; tx++) {
                final tileRect = _tileRect(tx, ty).intersect(pageRect);
                if (tileRect.isEmpty) continue;
                final raster = _rasters[_tileKey(tx, ty)];
                if (raster == null) continue;
                canvas.drawImageRect(
                  raster,
                  Rect.fromLTWH(
                    0,
                    0,
                    raster.width.toDouble(),
                    raster.height.toDouble(),
                  ),
                  Rect.fromLTWH(
                    tileRect.left * scaleX,
                    tileRect.top * scaleY,
                    tileRect.width * scaleX,
                    tileRect.height * scaleY,
                  ),
                  paint,
                );
              }
            }

            final picture = recorder.endRecording();
            try {
              return picture.toImageSync(outW, outH);
            } catch (_) {
              return null;
            } finally {
              picture.dispose();
            }
          }

          static int _sidebarPreviewEdgePx(
          double logical,
          double previewScale,
          double dpr,
        ) {
          final px =
          (logical *
          previewScale *
          dpr *
          rasterQuality(previewScale) *
          RasterLodTuning.sidebarPreviewQualityMul)
          .round();
          return px.clamp(32, maxRasterEdgePx);
        }
}

class _LinksCard extends StatelessWidget {
  const _LinksCard({
    required this.coreInfo,
    required this.pageIndex,
    required this.safePageIndex,
    required this.collapsed,
    required this.onToggle,
    required this.onLinkTap,
    required this.colorScheme,
  });

  static const _width = 280.0;

  final EditorCoreInfo coreInfo;
  final int pageIndex;
  final int safePageIndex;
  final bool collapsed;
  final VoidCallback onToggle;
  final void Function(NoteLink link)? onLinkTap;
  final ColorScheme colorScheme;

  static String _linkLabel(NoteLink link) {
    if (link.label?.isNotEmpty ?? false) return link.label!;
    final name = link.targetPath.split('/').last;
    if (link.isRange) {
      return 'p${link.targetPageIndex + 1}-${link.targetPageIndexEnd! + 1}: $name';
    }
    return 'p${link.targetPageIndex + 1}: $name';
  }

  @override
  Widget build(BuildContext context) {
    final links = coreInfo.linksForPage(
      coreInfo.pages[safePageIndex],
      pageIndex,
    );

    return SizedBox(
      width: _width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onToggle,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.92,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.25),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: collapsed ? 0 : 0.5,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      child: Icon(
                        Icons.expand_more,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        collapsed ? 'Links (${links.length})' : 'Hide links',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: collapsed
            ? const SizedBox.shrink()
            : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.outline.withValues(
                          alpha: 0.25,
                        ),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.shadow.withValues(
                            alpha: 0.06,
                          ),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < links.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              indent: 12,
                              endIndent: 12,
                              color: colorScheme.outline.withValues(
                                alpha: 0.2,
                              ),
                            ),
                            InkWell(
                              onTap: () => onLinkTap?.call(links[i]),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.link_rounded,
                                      size: 16,
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _linkLabel(links[i]),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colorScheme.onSurface,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}