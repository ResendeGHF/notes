// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_shape_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/pencil_shader.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/editor/stroke_paint.dart';
import 'package:saber/data/editor/stroke_paint_image_cache.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/laser_pointer.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/data/tools/shape_recognition.dart';

/// One merged run of consecutive batchable same-color strokes, in temporal
/// draw order. Drawn in place (interleaved with individual strokes) so z-order
/// stays exact across color changes.
class MeshBatchRun {
  const MeshBatchRun({
    required this.first,
    required this.colorKey,
    required this.meshes,
  });

  /// First stroke of the run (identity anchor for the painter walk).
  final Stroke first;

  /// ARGB32 color key (resolved with inversion at draw time).
  final int colorKey;

  /// Merged triangle meshes (Uint16-safe chunks, already clipped if tiled).
  final List<ui.Vertices> meshes;
}

/// Pre-batched solid meshes with an identity index for the painter walk.
/// Every batchable member maps to its run, so culled subsets still trigger
/// (clip keeps offscreen parts cheap) and a per-paint drawn-set suppresses
/// replays.
class OrderedMeshBatches {
  const OrderedMeshBatches(this.runs, this.draw);

  final List<MeshBatchRun> runs;
  final Map<Stroke, MeshBatchRun?> draw;

  bool get isEmpty => runs.isEmpty;
  bool get isNotEmpty => runs.isNotEmpty;
}

/// Raster-drag for massive selections: above these sizes the per-frame vector
/// replay of a transform drag dominates, so the selection is snapshotted once
/// (see [CanvasPainter.captureSelectionRaster]) and blitted per frame.
/// Aligned with the painter's own culling threshold scale (hundreds).
class SelectionRasterTuning {
  SelectionRasterTuning._();

  static const int minStrokes = 150;
  static const int minPoints = 15000;

  /// Capture supersample (sharp under moderate scale-up while dragging).
  static const double pixelRatio = 2.0;

  /// Drop the raster past this gesture scale (recapture would thrash; vector
  /// is sharper that far out anyway).
  static const double maxGestureScale = 1.5;

  /// Absolute bitmap ceiling (~16MP @ 4B/px); beyond it stay vector.
  static const int maxBitmapSidePx = 4096;

  static bool shouldRasterize({required int strokeCount, required int pointCount}) {
    return strokeCount >= minStrokes || pointCount >= minPoints;
  }
}

class CanvasPainter extends CustomPainter {
  const CanvasPainter({
    super.repaint,
    this.invert = false,
    required this.strokes,
    this.spatialGrid,
    this.quadTree,
    this.orderedBatches,
    required this.laserStrokes,
    required this.currentStroke,
    this.currentStrokeDetectedShape,
    this.shapePreviewPulse = 0,
    required this.currentSelection,
    this.selectionPreview,
    required this.primaryColor,
    required this.page,
    required this.showPageIndicator,
    required this.pageIndex,
    required this.totalPages,
    required this.currentScale,
    required this.defaultTextStyle,
    this.eraserPosition,
    this.eraserPositionListenable,
    this.eraserSize,
    this.doneSelecting = false,
    this.lineHeight,
    this.lineThickness,
    this.lineColor,
    this.excludedStrokes,
    this.pendingStrokes,
    this.selectionRasterImage,
    this.selectionRasterBounds,
    this.paintSelectionChrome = true,
    this.preferPathFill = false,
    this.scaleAgnosticRepaint = false,
  });

  final bool invert;
  final List<Stroke> strokes;

  final SpatialGrid? spatialGrid;

  /// Paint-time spatial index over the [strokes] list (page QuadTree).
  final QuadTree<Stroke>? quadTree;

  /// Pre-batched solid meshes in temporal draw order. Consecutive batchable
  /// same-color strokes merge into one run; the painter draws each run in
  /// place (interleaved with individual strokes), so newer ink always ends on
  /// top regardless of color. Null = paint every stroke individually.
  final OrderedMeshBatches? orderedBatches;
  final List<LaserStroke> laserStrokes;
  final Stroke? currentStroke;
  final RecognizedUnistroke? currentStrokeDetectedShape;
  final double shapePreviewPulse;
  final SelectResult? currentSelection;
  final SelectionTransformPreview? selectionPreview;
  final Color primaryColor;
  final EditorPage page;
  final bool showPageIndicator;
  final int pageIndex;
  final int totalPages;
  final double currentScale;
  final TextStyle defaultTextStyle;
  final Offset? eraserPosition;
  final ValueListenable<Offset?>? eraserPositionListenable;
  final double? eraserSize;
  final bool doneSelecting;
  final int? lineHeight;
  final double? lineThickness;
  final Color? lineColor;

  final Set<Stroke>? excludedStrokes;

  /// Finished strokes waiting to bake into Picture tiles. Always drawn
  /// (no spatial cull) so pen-up cannot drop ink the live stroke just showed.
  final List<Stroke>? pendingStrokes;

  /// Rasterized selection drag (see [captureSelectionRaster]): when moving
  /// hundreds of strokes, one blit replaces the full vector replay per frame.
  /// Drawn under the preview transform like vector strokes. Null = vector.
  final ui.Image? selectionRasterImage;
  final Rect? selectionRasterBounds;

  /// Draw selection box/handles/guides. Off for raster capture (ink only —
  /// chrome keeps painting live per frame on top).
  final bool paintSelectionChrome;

  /// Draw authored paths and skip mesh/vertices so first paint cannot stall
  /// on triangulation.
  final bool preferPathFill;

  /// Skip repaints on canvas-scale changes only. The committed-highlighter
  /// overlay sets this: highlighter geometry is scale-independent
  /// ([Stroke.setLodScale] forces 1.0) and the compositor rescales the layer,
  /// so re-rasterizing full-page highlighter paths on every pinch frame is
  /// pure waste (the pinch lag on highlighter-heavy pages).
  final bool scaleAgnosticRepaint;

  static final _reusableQueryBuffer = <Stroke>[];

  /// Snapshots a selection into one bitmap for raster-drag: a single blit per
  /// frame replaces the full vector replay while transforming hundreds of
  /// strokes. Captured in page space (identity transform) with the same
  /// painter settings (including selection tint) minus chrome; the live
  /// overlay maps it through the preview matrix exactly like vectors.
  /// Returns null when rasterizing is pointless or impossible (empty/tiny
  /// bounds, over the bitmap ceiling, raster backend failure) — callers fall
  /// back to vectors. The caller owns the image (dispose on gesture end).
  static ({ui.Image image, Rect bounds})? captureSelectionRaster({
    required List<Stroke> strokes,
    required SelectResult? selectionForTint,
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
    if (strokes.isEmpty) return null;
    Rect? bounds;
    for (final s in strokes) {
      final b = s.bounds;
      if (!b.isFinite || b.isEmpty) continue;
      bounds = bounds == null ? b : bounds.expandToInclude(b);
    }
    if (bounds == null || bounds.isEmpty || !bounds.isFinite) return null;
    var pr = SelectionRasterTuning.pixelRatio;
    final longest = bounds.longestSide * pr;
    if (longest > SelectionRasterTuning.maxBitmapSidePx) {
      pr *= SelectionRasterTuning.maxBitmapSidePx / longest;
    }
    final wPx = (bounds.width * pr).ceil();
    final hPx = (bounds.height * pr).ceil();
    if (wPx < 1 || hPx < 1) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, wPx.toDouble(), hPx.toDouble()),
    );
    canvas.scale(pr);
    canvas.translate(-bounds.left, -bounds.top);
    CanvasPainter(
      invert: invert,
      strokes: strokes,
      laserStrokes: const [],
      currentStroke: null,
      currentSelection: selectionForTint,
      primaryColor: primaryColor,
      page: page,
      showPageIndicator: false,
      pageIndex: pageIndex,
      totalPages: totalPages,
      currentScale: currentScale,
      defaultTextStyle: defaultTextStyle,
      lineHeight: lineHeight,
      lineThickness: lineThickness,
      lineColor: lineColor,
      doneSelecting: true,
      paintSelectionChrome: false,
    ).paint(canvas, page.size);
    final picture = recorder.endRecording();
    try {
      final image = picture.toImageSync(wPx, hPx);
      picture.dispose();
      return (image: image, bounds: bounds);
    } catch (_) {
      picture.dispose();
      return null;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final canvasRect = Offset.zero & size;

    canvas.save();
    canvas.clipRect(canvasRect);

    final visibleRect = canvas.getLocalClipBounds();

    final cullingRect = visibleRect.inflate(120);

    _reusableQueryBuffer.clear();
    List<Stroke> visibleStrokes;
    final bool previewingSelection =
        selectionPreview != null &&
        currentSelection != null &&
        currentStroke == null &&
        identical(strokes, currentSelection!.strokes);

    const int linearScanThreshold = 250;
    final hasSpatialIndex = quadTree != null || spatialGrid != null;

    if (previewingSelection) {
      visibleStrokes = strokes;
    } else if (hasSpatialIndex && strokes.length > linearScanThreshold) {
      _reusableQueryBuffer.clear();
      
      // Get all bounding-box overlaps from the QuadTree (Fast but unordered)
      final List<Stroke> foundStrokes;
      if (quadTree != null) {
        foundStrokes = quadTree!.query(cullingRect);
      } else {
        foundStrokes = [];
        final indices = spatialGrid!.query(cullingRect);
        for (final i in indices) {
          if (i >= 0 && i < strokes.length) {
            foundStrokes.add(strokes[i]);
          }
        }
      }

      // The QuadTree queries strokes blindly across all layers. To prevent layers 
      // from vanishing and to enforce Z-Order, we simply sort the found strokes 
      // using their natural Z-Order. O(K log K) where K is strokes in view.
      if (foundStrokes.isNotEmpty) {
        foundStrokes.sort();
        _reusableQueryBuffer.addAll(foundStrokes);
      }
      visibleStrokes = _reusableQueryBuffer;
      
    } else {
      for (final s in strokes) {
        if (!s.bounds.isFinite || cullingRect.overlaps(s.bounds)) {
          _reusableQueryBuffer.add(s);
        }
      }
      visibleStrokes = _reusableQueryBuffer;
    }

    if (excludedStrokes != null && excludedStrokes!.isNotEmpty) {
      visibleStrokes = visibleStrokes
          .where((s) => !excludedStrokes!.contains(s))
          .toList(growable: false);
    }

    // One temporal pass. Highlighters are not pulled in front of later pens.
    const highlighters = <Stroke>[];
    final normalStrokes = visibleStrokes;

    if (selectionPreview != null) {
      canvas.save();
      canvas.transform(selectionPreview!.transformMatrix.storage);
    }

    final useSelectionRaster =
        selectionPreview != null &&
        selectionRasterImage != null &&
        selectionRasterBounds != null &&
        !selectionRasterBounds!.isEmpty;
    if (useSelectionRaster) {
      // One blit for the whole selection (raster-drag mode): the image was
      // captured in page space, so the preview transform above maps it
      // exactly like the vector strokes it replaces.
      final image = selectionRasterImage!;
      _rasterBlitPaint.filterQuality = FilterQuality.medium;
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(
          0,
          0,
          image.width.toDouble(),
          image.height.toDouble(),
        ),
        selectionRasterBounds!,
        _rasterBlitPaint,
      );
    } else {
      if (highlighters.isNotEmpty) {
        _drawHighlighters(canvas, highlighters);
      }

      _drawNonHighlighterStrokes(
        canvas,
        normalStrokes,
        cullingRect,
      );
    }

    if (selectionPreview != null) {
      canvas.restore();
    }

    for (final stroke in laserStrokes) {
      if (cullingRect.overlaps(stroke.bounds)) {
        _drawLaserStroke(canvas, stroke);
      }
    }

    final pending = pendingStrokes;
    if (pending != null && pending.isNotEmpty) {
      _drawNonHighlighterStrokes(
        canvas,
        pending,
        const Rect.fromLTRB(-1.0e9, -1.0e9, 1.0e9, 1.0e9),
      );
    }

    _drawCurrentStroke(canvas);
    _drawDetectedShape(canvas);

    canvas.restore();

    if (paintSelectionChrome) _drawSelection(canvas);
    _drawEraserIndicator(canvas);
    _drawPageIndicator(canvas, size);
  }

  @override
  bool shouldRepaint(CanvasPainter oldDelegate) {
    return false ||
        (currentStroke != null || oldDelegate.currentStroke != null) ||
        (!doneSelecting && currentSelection != null) ||
        (laserStrokes.isNotEmpty || oldDelegate.laserStrokes.isNotEmpty) ||
        invert != oldDelegate.invert ||
        strokes.length != oldDelegate.strokes.length ||
        currentStrokeDetectedShape != oldDelegate.currentStrokeDetectedShape ||
        shapePreviewPulse != oldDelegate.shapePreviewPulse ||
        currentSelection != oldDelegate.currentSelection ||
        selectionPreview != oldDelegate.selectionPreview ||
        primaryColor != oldDelegate.primaryColor ||
        page != oldDelegate.page ||
        showPageIndicator != oldDelegate.showPageIndicator ||
        pageIndex != oldDelegate.pageIndex ||
        totalPages != oldDelegate.totalPages ||
        (!scaleAgnosticRepaint &&
            !oldDelegate.scaleAgnosticRepaint &&
            currentScale != oldDelegate.currentScale) ||
        eraserPosition != oldDelegate.eraserPosition ||
        eraserPositionListenable != oldDelegate.eraserPositionListenable ||
        eraserSize != oldDelegate.eraserSize ||
        doneSelecting != oldDelegate.doneSelecting ||
        lineHeight != oldDelegate.lineHeight ||
        lineThickness != oldDelegate.lineThickness ||
        lineColor != oldDelegate.lineColor ||
        spatialGrid != oldDelegate.spatialGrid ||
        quadTree != oldDelegate.quadTree ||
        excludedStrokes != oldDelegate.excludedStrokes ||
        pendingStrokes != oldDelegate.pendingStrokes ||
        (pendingStrokes?.length ?? 0) !=
            (oldDelegate.pendingStrokes?.length ?? 0) ||
        selectionRasterImage != oldDelegate.selectionRasterImage ||
        selectionRasterBounds != oldDelegate.selectionRasterBounds ||
        paintSelectionChrome != oldDelegate.paintSelectionChrome ||
        preferPathFill != oldDelegate.preferPathFill ||
        scaleAgnosticRepaint != oldDelegate.scaleAgnosticRepaint;
  }

  static final _sharedPaint = Paint();

  /// Dedicated blit paint (never carries a color/shader from vector draws —
  /// those would tint the raster).
  static final _rasterBlitPaint = Paint();

  void _drawOrderedRun(
    Canvas canvas,
    MeshBatchRun run,
  ) {
    _sharedPaint
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..shader = null
      ..maskFilter = null
      ..colorFilter = null
      ..blendMode = BlendMode.srcOver
      ..color = Color(run.colorKey).withInversion(invert);

    for (final mesh in run.meshes) {
      canvas.drawVertices(mesh, BlendMode.srcOver, _sharedPaint);
    }
  }

  static BlendMode _meshBlendMode(ToolId toolId, {required bool invert}) {
    if (toolId == ToolId.highlighter) {
      return invert ? BlendMode.plus : BlendMode.darken;
    }
    return BlendMode.srcOver;
  }

  /// Tile-local geometry clipping for long strokes: bounds per-frame vector
  /// replay/retessellation to the visible rect (tile bounds during tile
  /// recording). Short strokes and unbounded rects take the legacy path.
  /// Only opaque solid fills are clipped (exact under overlap); translucent,
  /// additive and bounds-anchored paints keep full geometry.
  static bool _clipAppliesTo(Stroke stroke, Rect rect) {
    return rect.isFinite &&
        stroke.sampleCount > Stroke.kTileClipMinPoints;
  }

  /// Buckets a stroke's cached mesh triangles to [rect] (compacted temp
  /// Vertices), or null when clipping doesn't apply / nothing overlaps.
  ui.Vertices? _clipMeshFor(Stroke stroke, Rect rect) {
    if (!_clipAppliesTo(stroke, rect)) return null;
    final part = Stroke.clipMeshArrays(
      stroke.getRawPositions(),
      stroke.getRawIndices(),
      stroke.getRawColors(),
      rect,
    );
    if (part == null || part.positions.isEmpty || part.indices.isEmpty) {
      return null;
    }
    return ui.Vertices.raw(
      ui.VertexMode.triangles,
      part.positions,
      indices: part.indices,
      colors: part.colors,
    );
  }

  /// Draws an opaque solid outline clipped to [rect] (1px bleed so adjacent
  /// tiles join exactly), or null when clipping doesn't apply.
  /// Returns true when handled (drawn or fully outside).
  bool _drawClippedSolidPath(
    Canvas canvas,
    Stroke stroke,
    Color color,
    Rect rect,
  ) {
    if (!_clipAppliesTo(stroke, rect)) return false;
    if (stroke.hasNonSolidPaint || color.alpha != 0xFF) return false;
    if (stroke is ShapeStroke ||
        stroke is CircleStroke ||
        stroke is RectangleStroke) {
      return false;
    }
    final clipped = Stroke.clipPolygonToRect(
      stroke.highQualityPolygon,
      rect,
      bleed: 1.0,
    );
    if (clipped.isEmpty) return true;
    _sharedPaint
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..color = color
      ..blendMode = BlendMode.srcOver
      ..shader = null
      ..maskFilter = null
      ..colorFilter = null;
    final path = Path()
      ..fillType = PathFillType.nonZero
      ..addPolygon(clipped, true);
    canvas.drawPath(path, _sharedPaint);
    return true;
  }

  void _drawHighlighters(Canvas canvas, List<Stroke> highlighters) {
    final selectedStrokes = currentSelection?.strokes;
    final bool allVisibleStrokesAreSelected =
        selectedStrokes != null && identical(highlighters, selectedStrokes);
    final Set<Stroke>? selectedStrokeSet =
        allVisibleStrokesAreSelected || selectedStrokes == null
        ? null
        : selectedStrokes.length > 8
        ? selectedStrokes.toSet()
        : null;

    final Map<int, Path> colorPaths = {};

    // Group all strokes of the exact same color into a single complex non-zero path.
    // This prevents the alpha from overlapping/stacking at intersections.
    for (final stroke in highlighters) {
      stroke.setLodScale(currentScale);
      
      var color = stroke.color.withInversion(invert);
      final isSelected = allVisibleStrokesAreSelected
          ? true
          : selectedStrokeSet?.contains(stroke) ??
                selectedStrokes?.contains(stroke) ??
                false;
      if (isSelected) {
        color = Color.lerp(color, Colors.black.withInversion(invert), 0.5)!;
      }

      final colorVal = color.value;
      final path = _selectPath(stroke);

      if (colorPaths.containsKey(colorVal)) {
        colorPaths[colorVal]!.addPath(path, Offset.zero);
      } else {
        final newPath = Path();
        newPath.fillType = PathFillType.nonZero;
        newPath.addPath(path, Offset.zero);
        colorPaths[colorVal] = newPath;
      }
    }

    // Paint each distinct color group efficiently
    for (final entry in colorPaths.entries) {
      final color = Color(entry.key);
      _sharedPaint
        ..style = PaintingStyle.fill
        ..isAntiAlias = true
        ..blendMode = invert ? BlendMode.plus : BlendMode.darken
        ..color = color
        ..shader = null
        ..maskFilter = null
        ..colorFilter = null;

      canvas.drawPath(entry.value, _sharedPaint);
    }
  }

  void _drawNonHighlighterStrokes(
    Canvas canvas,
    List<Stroke> visibleStrokes,
    Rect cullingRect,
  ) {
    final selectedStrokes = currentSelection?.strokes;
    final bool allVisibleStrokesAreSelected =
        selectedStrokes != null && identical(visibleStrokes, selectedStrokes);
    final Set<Stroke>? selectedStrokeSet =
        allVisibleStrokesAreSelected || selectedStrokes == null
        ? null
        : selectedStrokes.length > 8
        ? selectedStrokes.toSet()
        : null;

    // Ordered mesh runs (null under preferPathFill): drawn in place so newer
    // ink ends on top across color changes; every member maps to its run so
    // culled subsets still trigger (clip keeps it cheap).
    final batches =
        (!preferPathFill && !allVisibleStrokesAreSelected) ? orderedBatches : null;
    final batchDraw = (batches != null && batches.isNotEmpty)
        ? batches.draw
        : null;
    final drawnRuns = batchDraw == null ? null : <MeshBatchRun>{};

    // Carve bites are punched inside a layer so only this stroke's pixels
    // disappear. The layer is closed on the next stroke, which keeps the
    // many early-continues below from leaking a saveLayer.
    Stroke? carvedOpen;
    void closeCarved() {
      if (carvedOpen == null) return;
      carvedOpen!.carveMask?.punch(canvas);
      canvas.restore();
      carvedOpen = null;
    }

    void openCarved(Stroke stroke) {
      closeCarved();
      if (!stroke.hasCarve) return;
      final mode = stroke.toolId == ToolId.highlighter
          ? (invert ? BlendMode.plus : BlendMode.darken)
          : BlendMode.srcOver;
      final bounds = stroke.bounds.inflate((stroke.carveMask?.maxRadius ?? 0) + 8);
      canvas.saveLayer(bounds, Paint()..blendMode = mode);
      carvedOpen = stroke;
    }

    Color? pencilLastColor;
    StrokePaint? pencilLastCfg;
    double? pencilLastQuality;
    var pencilVisibleCount = 0;
    for (final s in visibleStrokes) {
      if (s.toolId == ToolId.pencil || s.paint.usesPencilNoise) {
        pencilVisibleCount++;
      }
    }

    for (var i = 0; i < visibleStrokes.length; i++) {
      final stroke = visibleStrokes[i];
      openCarved(stroke);
      if (stroke.toolId == ToolId.highlighter && !stroke.hasCarve) {
        _drawHighlighters(canvas, [stroke]);
        continue;
      }
      if (stroke.toolId == ToolId.highlighter && stroke.hasCarve) {
        stroke.setLodScale(currentScale);
        var color = stroke.color.withInversion(invert);
        final selectedNow = allVisibleStrokesAreSelected
            ? true
            : selectedStrokeSet?.contains(stroke) ??
                  selectedStrokes?.contains(stroke) ??
                  false;
        if (selectedNow) {
          color = Color.lerp(color, Colors.black.withInversion(invert), 0.5)!;
        }
        _sharedPaint
          ..style = PaintingStyle.fill
          ..isAntiAlias = true
          ..blendMode = BlendMode.srcOver
          ..color = color
          ..shader = null
          ..maskFilter = null
          ..colorFilter = null;
        canvas.drawPath(_selectPath(stroke), _sharedPaint);
        continue;
      }
      if (batchDraw != null && drawnRuns != null) {
        // Every batchable member maps to its run; the first present member
        // draws it (culling may drop earlier members) and the per-paint
        // drawn-set suppresses replays. Temporal order holds because members
        // are visited back-to-front.
        final run = batchDraw[stroke];
        if (run != null) {
          if (drawnRuns.add(run)) _drawOrderedRun(canvas, run);
          continue;
        }
      }

      stroke.setLodScale(currentScale);

      var color = stroke.color.withInversion(invert);
      final isSelected = allVisibleStrokesAreSelected
          ? true
          : selectedStrokeSet?.contains(stroke) ??
                selectedStrokes?.contains(stroke) ??
                false;
      if (isSelected) {
        color = Color.lerp(color, Colors.black.withInversion(invert), 0.5)!;
      }

      _sharedPaint
        ..color = color
        ..blendMode = BlendMode.srcOver
        ..shader = null
        ..maskFilter = null
        ..colorFilter = null;

      if (stroke is ShapeStroke) {
        _sharedPaint.isAntiAlias = true;
        if (stroke.fill) {
          _sharedPaint.style = PaintingStyle.fill;
          _sharedPaint.color = stroke.fillColor.withInversion(invert);
          canvas.drawPath(stroke.shapePath, _sharedPaint);
        }
        _sharedPaint.color = color;
        _sharedPaint.style = PaintingStyle.stroke;
        _sharedPaint.strokeWidth = stroke.options.size;
        _sharedPaint.strokeCap = StrokeCap.round;
        _sharedPaint.strokeJoin = StrokeJoin.round;
        canvas.drawPath(stroke.strokeDrawPath, _sharedPaint);
        continue;
      }

      if (stroke is CircleStroke) {
        _sharedPaint.style = PaintingStyle.stroke;
        _sharedPaint.strokeWidth = stroke.options.size;
        _sharedPaint.isAntiAlias = true;
        _sharedPaint.strokeCap = StrokeCap.round;
        canvas.drawCircle(stroke.center, stroke.radius, _sharedPaint);
        continue;
      }

      if (stroke is RectangleStroke) {
        _sharedPaint.style = PaintingStyle.stroke;
        _sharedPaint.strokeWidth = stroke.options.size;
        _sharedPaint.strokeCap = StrokeCap.round;
        _sharedPaint.strokeJoin = StrokeJoin.round;
        canvas.drawRect(stroke.rect, _sharedPaint);
        continue;
      }

      if (stroke.neon && stroke.toolId == ToolId.ballpointPen) {
        _drawNeonInkStroke(canvas, stroke, color);
        continue;
      }

      if (stroke.toolId == ToolId.pencil ||
          stroke.paint.usesPencilNoise) {
        final applied = _drawPencilNoiseStroke(
          canvas,
          stroke,
          color,
          visibleCount: identical(stroke, currentStroke)
              ? 1
              : pencilVisibleCount,
          lastColor: pencilLastColor,
          lastCfg: pencilLastCfg,
          lastQuality: pencilLastQuality,
          clipBounds: cullingRect,
        );
        if (applied != null) {
          pencilLastColor = applied.$1;
          pencilLastCfg = applied.$2;
          pencilLastQuality = applied.$3;
        }
        continue;
      }

      final useTextured = stroke.hasNonSolidPaint && stroke is! ShapeStroke;
      if (useTextured) {
        final path = !preferPathFill && stroke.vertices != null
            ? (stroke.highQualityPath)
            : _selectPath(stroke);
        _drawTexturedStrokePath(
          canvas,
          stroke,
          path,
          color,
          isLive: preferPathFill,
          clipBounds: preferPathFill ? null : cullingRect,
        );
        continue;
      }

      if (preferPathFill) {
        _sharedPaint.style = PaintingStyle.fill;
        _sharedPaint.isAntiAlias = true;
        final path = _selectPath(stroke);
        canvas.drawPath(path, _sharedPaint);
        continue;
      }

      if (stroke.vertices != null) {
        _sharedPaint.style = PaintingStyle.fill;
        _sharedPaint.isAntiAlias = true;
        // Tile-local mesh: long strokes replay only local triangles.
        final clippedMesh = _clipMeshFor(stroke, cullingRect);
        final mesh = clippedMesh ?? stroke.vertices!;
        final mode = _meshBlendMode(stroke.toolId, invert: invert);
        canvas.drawVertices(mesh, mode, _sharedPaint);
      } else if (_drawClippedSolidPath(canvas, stroke, color, cullingRect)) {
        // Tile-local opaque fill drawn above (or fully outside the tile).
      } else {
        final picture = stroke.ensureSolidPathPicture(
          invert: invert,
          color: color,
        );
        if (picture != null) {
          canvas.drawPicture(picture);
        } else {
          final path = _selectPath(stroke);
          _sharedPaint.style = PaintingStyle.fill;
          _sharedPaint.isAntiAlias = true;
          canvas.drawPath(path, _sharedPaint);
        }
      }
    }
    closeCarved();
  }

  void _drawTexturedStrokePath(
    Canvas canvas,
    Stroke stroke,
    Path path,
    Color fallbackColor, {
    bool isLive = false,
    // Tile-local clip (committed layer only; null = legacy full geometry).
    // The paint stays anchored to the FULL path bounds so gradients and
    // image fills never shift; only the drawn geometry is trimmed.
    Rect? clipBounds,
  }) {
    if (!isLive) {
      final picture = stroke.ensureVectorFillPicture(
        invert: invert,
        fallbackColor: fallbackColor,
        currentScale: currentScale,
      );
      if (picture != null) {
        canvas.drawPicture(picture);
        return;
      }
    }
    final bounds = path.getBounds();
    if (bounds.isEmpty) return;
    // Tile-local trim; the paint below stays anchored to the full bounds.
    Path drawPath = path;
    if (clipBounds != null &&
        clipBounds.isFinite &&
        stroke.sampleCount > Stroke.kTileClipMinPoints) {
      final clipped = Stroke.clipPolygonToRect(
        stroke.highQualityPolygon,
        clipBounds,
      );
      if (clipped.isEmpty) return;
      drawPath = Path()
        ..fillType = PathFillType.nonZero
        ..addPolygon(clipped, true);
    }
    final paintCfg = stroke.paint;
    ui.Image? texture;
    if (paintCfg.usesTexture) {
      texture = StrokePaintImageCache.instance.ensure(paintCfg);
    }
    _sharedPaint
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..blendMode = BlendMode.srcOver
      ..filterQuality = currentScale < 0.7
          ? FilterQuality.low
          : FilterQuality.medium
      ..color = fallbackColor;

    // Vector path+shader (not a raster bake) so gradient/image stay sharp.
    paintCfg.applyTo(
      _sharedPaint,
      bounds,
      texture: texture,
      useShaderCache: true,
    );
    // If texture not ready yet, still draw solid so stroke is visible.
    if (paintCfg.usesTexture && _sharedPaint.shader == null) {
      _sharedPaint.color = fallbackColor;
    }
    // Path fill (not outline triangulation): stroke outlines self-intersect at
    // turns; ear-clip meshes punched holes and flattened caps.
    canvas.drawPath(drawPath, _sharedPaint);
    _sharedPaint
      ..shader = null
      ..colorFilter = null
      ..maskFilter = null;
  }

  /// Returns the config that was applied, for uniform batching across strokes.
  (Color, StrokePaint, double)? _drawPencilNoiseStroke(
    Canvas canvas,
    Stroke stroke,
    Color color, {
    int visibleCount = 1,
    Color? lastColor,
    StrokePaint? lastCfg,
    double? lastQuality,
    // Tile-local clip (committed layer only; null = legacy full geometry).
    // Grain is page-anchored so clipping never shifts it; the mask edge
    // hides in the noise.
    Rect? clipBounds,
  }) {
    final bool clip = clipBounds != null &&
        clipBounds.isFinite &&
        stroke.sampleCount > Stroke.kTileClipMinPoints;
    Path path;
    if (clip) {
      final clippedPoly = Stroke.clipPolygonToRect(
        stroke.highQualityPolygon,
        clipBounds,
      );
      if (clippedPoly.isEmpty) return null;
      path = Path()
        ..fillType = PathFillType.nonZero
        ..addPolygon(clippedPoly, true);
    } else {
      path = _selectPath(stroke);
      if (path.getBounds().isEmpty) return null;
    }

    final shader = page.tryPencilShader();
    final size = stroke.options.size;
    final quality = PencilShader.qualityForScale(currentScale);

    // One union-path fill, never a triangle mesh: self-overlap at curves and
    // joins then shades each pixel exactly once (no additive darkening) and
    // there are no mesh seams. Live uses the identical call with the staged
    // chunk union, so both stages agree pixel-for-pixel.
    if (shader == null) {
      PencilShader.paintGrainFallback(
        canvas: canvas,
        color: color,
        cfg: stroke.paint,
        outline: path,
        currentScale: currentScale,
        visibleCount: visibleCount,
        strokeSize: size,
      );
      return (color, stroke.paint, quality);
    }

    PencilShader.paintGrainPath(
      canvas: canvas,
      shader: shader,
      color: color,
      cfg: stroke.paint,
      outline: path,
      configureBaseUniforms: !PencilShader.sameConfig(
        color: color,
        cfg: stroke.paint,
        quality: quality,
        lastColor: lastColor,
        lastCfg: lastCfg,
        lastQuality: lastQuality, size: size, lastSize: null,
      ),
      currentScale: currentScale,
      visibleCount: visibleCount,
      strokeSize: size,
    );

    return (color, stroke.paint, quality);
  }

  void _drawCurrentStroke(Canvas canvas) {
    if (currentStroke == null) return;

    currentStroke!.setLodScale(currentScale);

    if (currentStroke! is LaserStroke) {
      return _drawLaserStroke(canvas, currentStroke as LaserStroke);
    }

    _sharedPaint.blendMode = BlendMode.srcOver;
    _sharedPaint.maskFilter = null;
    _sharedPaint.isAntiAlias = true;
    // A stale shader/colorFilter from an earlier textured/pencil draw would
    // tint the live stroke (e.g. semi-transparent grain); the branches below
    // set their own. Cheap insurance for the whole live path.
    _sharedPaint.shader = null;
    _sharedPaint.colorFilter = null;

    if (currentStroke is ShapeStroke) {
      final shape = currentStroke as ShapeStroke;

      final path = shape.shapePath;
      if (shape.fill) {
        _sharedPaint.color = shape.fillColor.withInversion(invert);
        _sharedPaint.style = PaintingStyle.fill;
        canvas.drawPath(path, _sharedPaint);
      }

      _sharedPaint.color = shape.color.withInversion(invert);
      _sharedPaint.style = PaintingStyle.stroke;
      _sharedPaint.strokeWidth = shape.options.size;
      _sharedPaint.strokeCap = StrokeCap.round;
      _sharedPaint.strokeJoin = StrokeJoin.round;
      canvas.drawPath(shape.strokeDrawPath, _sharedPaint);
      return;
    }

    if (currentStroke is CircleStroke) {
      final circle = currentStroke as CircleStroke;
      _sharedPaint.color = circle.color.withInversion(invert);
      _sharedPaint.style = PaintingStyle.stroke;
      _sharedPaint.strokeWidth = circle.options.size;
      _sharedPaint.strokeCap = StrokeCap.round;

      canvas.drawCircle(circle.center, circle.radius, _sharedPaint);
      return;
    }

    if (currentStroke is RectangleStroke) {
      final rectangle = currentStroke as RectangleStroke;
      _sharedPaint.color = rectangle.color.withInversion(invert);
      _sharedPaint.style = PaintingStyle.stroke;
      _sharedPaint.strokeWidth = rectangle.options.size;
      _sharedPaint.strokeCap = StrokeCap.round;
      _sharedPaint.strokeJoin = StrokeJoin.round;

      canvas.drawRect(rectangle.rect, _sharedPaint);
      return;
    }

    _sharedPaint.color = currentStroke!.color.withInversion(invert);
    _sharedPaint.style = PaintingStyle.fill;

    if (currentStroke!.neon && currentStroke!.toolId == ToolId.ballpointPen) {
      if (currentStroke!.hasLiveStaging) {
        _drawStagedNeonInkStroke(
          canvas,
          currentStroke!,
          currentStroke!.color.withInversion(invert),
        );
      } else {
        _drawNeonInkStroke(
          canvas,
          currentStroke!,
          currentStroke!.color.withInversion(invert),
        );
      }
      return;
    }

    if (currentStroke!.toolId == ToolId.pencil ||
        currentStroke!.paint.usesPencilNoise) {
      if (currentStroke!.hasLiveStaging) {
        _drawStagedPencilStroke(
          canvas,
          currentStroke!,
          currentStroke!.color.withInversion(invert),
        );
      } else {
        _drawPencilNoiseStroke(
          canvas,
          currentStroke!,
          currentStroke!.color.withInversion(invert),
          visibleCount: 1,
        );
      }
      return;
    }

    if (currentStroke!.hasNonSolidPaint) {
      // NOTE: no `vertices` access here on purpose. `vertices` tessellates
      // the full live stroke (O(n) spline+mesh per frame); the mesh is then
      // discarded below in favor of `highQualityPath`, so touching it would
      // burn a full mesh build every frame of every long textured stroke.
      // `vertices != null` is equivalent to a length check anyway: it is null
      // for path-only tools and for <2 points, and both sides below use
      // `highQualityPath` for length>=2.
      final path = currentStroke!.length == 1
          ? (Path()..addOval(
              Rect.fromCircle(
                center: Offset(
                  currentStroke!.pointsForEraser.first.x,
                  currentStroke!.pointsForEraser.first.y,
                ),
                radius: () {
                  final baseRadius = currentStroke!.options.size / 2;
                  final pressure = (currentStroke!.pointsForEraser.first.pressure ?? 0.5).clamp(0.0, 1.0);
                  if (currentStroke!.toolId == ToolId.fountainPen) {
                    return math.max(0.05, baseRadius * (0.25 + 0.9 * pressure * pressure));
                  } else if (currentStroke!.toolId == ToolId.ballpointPen || currentStroke!.toolId == ToolId.calligraphyPen) {
                    return baseRadius;
                  } else if (currentStroke!.toolId == ToolId.advancedPen) {
                    return math.max(0.05, currentStroke!.brushOptions.pressureCurve.apply(baseRadius * 2, pressure) / 2);
                  }
                  return math.max(0.1, baseRadius * (0.2 + 0.8 * pressure * 2));
                }().clamp(0.5, 999.0),
              ),
            ))
          : currentStroke!.highQualityPath;
      _drawTexturedStrokePath(
        canvas,
        currentStroke!,
        path,
        currentStroke!.color.withInversion(invert),
        isLive: true,
      );
      return;
    }

    if (currentStroke!.toolId == ToolId.highlighter) {
      _sharedPaint.blendMode = invert ? BlendMode.plus : BlendMode.darken;

      if (currentStroke!.length == 1) {
        final p = currentStroke!.pointsForEraser.first;
        final baseSize =
            (currentStroke!.options.size / 2) *
            Stroke.highlighterStrokeScaleFactor;
        if (currentStroke!.flatEdge) {
          // Flat tip: square blob matching eventual rectangular caps.
          final r = baseSize.clamp(0.5, 999.0);
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset(p.x, p.y),
              width: r * 2,
              height: r * 2,
            ),
            _sharedPaint,
          );
        } else {
          canvas.drawCircle(
            Offset(p.x, p.y),
            baseSize.clamp(0.5, 999.0),
            _sharedPaint,
          );
        }
      } else if (currentStroke!.hasLiveStaging) {
        // Frozen butt-jointed chunks + live tail: already-drawn regions are
        // replayed verbatim, never re-tessellated.
        for (final c in currentStroke!.liveStagedChunks) {
          final p = c.path;
          if (p == null) continue;
          canvas.drawPath(p, _sharedPaint);
        }
      } else if (currentStroke!.vertices != null) {
        _sharedPaint.isAntiAlias = true;
        final mode = _meshBlendMode(currentStroke!.toolId, invert: invert);
        canvas.drawVertices(currentStroke!.vertices!, mode, _sharedPaint);
        canvas.drawVertices(currentStroke!.vertices!, mode, _sharedPaint);
      } else {
        canvas.drawPath(_selectPath(currentStroke!), _sharedPaint);
      }

      _sharedPaint.blendMode = BlendMode.srcOver;
      return;
    }

    // Staging first: `vertices` tessellates the WHOLE live stroke (O(n)
    // spline+mesh per frame). For staged strokes that mesh is discarded two
    // branches below in favor of frozen chunks + bounded tail, so touching it
    // here burned a full mesh rebuild every frame of every long stroke —
    // growing with stroke length. `hasLiveStaging` is O(1).
    if (currentStroke!.hasLiveStaging) {
      // Mesh families draw their staged meshes; path-only pens (Advanced)
      // draw their staged butt-jointed outlines. Chunks carry one or the
      // other, never neither.
      _sharedPaint.isAntiAlias = true;
      for (final c in currentStroke!.liveStagedChunks) {
        final m = c.mesh;
        if (m != null) {
          final mode = _meshBlendMode(currentStroke!.toolId, invert: invert);
          canvas.drawVertices(m, mode, _sharedPaint);
        } else if (c.path != null) {
          canvas.drawPath(c.path!, _sharedPaint);
        }
      }
      return;
    }

    if (currentStroke!.vertices != null) {
      _sharedPaint.isAntiAlias = true;
      final mode = _meshBlendMode(currentStroke!.toolId, invert: invert);
      canvas.drawVertices(currentStroke!.vertices!, mode, _sharedPaint);
      return;
    }

    if (currentStroke!.length == 1) {
      final p = currentStroke!.pointsForEraser.first;
      final center = Offset(p.x, p.y);
      final baseRadius = currentStroke!.options.size / 2;
      final pressure = (p.pressure ?? 0.5).clamp(0.0, 1.0);
      double radius = baseRadius;
      if (currentStroke!.toolId == ToolId.fountainPen) {
        radius = math.max(0.05, baseRadius * (0.25 + 0.9 * pressure * pressure));
      } else if (currentStroke!.toolId == ToolId.advancedPen) {
        radius = math.max(0.05, currentStroke!.brushOptions.pressureCurve.apply(baseRadius * 2, pressure) / 2);
      } else if (currentStroke!.toolId != ToolId.ballpointPen && currentStroke!.toolId != ToolId.calligraphyPen) {
        radius = math.max(0.1, baseRadius * (0.2 + 0.8 * pressure * 2));
      }
      canvas.drawCircle(center, radius.clamp(0.5, 999.0), _sharedPaint);
    } else {
      canvas.drawPath(currentStroke!.highQualityPath, _sharedPaint);
    }
  }

  void _drawDetectedShape(Canvas canvas) {
    final shape = currentStrokeDetectedShape;
    if (shape == null || currentStroke == null) return;

    final color = currentStroke!.color.withInversion(invert);
    final pulse = (0.55 + 0.35 * math.sin(shapePreviewPulse * 2 * math.pi))
        .clamp(0.2, 0.95);

    _sharedPaint.color = Color.lerp(
      color,
      primaryColor,
      0.5,
    )!.withValues(alpha: pulse);
    _sharedPaint.style = PaintingStyle.stroke;
    _sharedPaint.strokeWidth = math.max(
      1.5,
      currentStroke!.options.size * 1.05,
    );
    _sharedPaint.isAntiAlias = true;
    _sharedPaint.strokeCap = StrokeCap.round;
    _sharedPaint.strokeJoin = StrokeJoin.round;
    _sharedPaint.maskFilter = null;

    final dashLength = math.max(8.0, _sharedPaint.strokeWidth * 1.5);
    final path = buildDetectedShapePreviewPath(currentStroke!, shape);

    canvas.drawPath(path, _sharedPaint);

    _sharedPaint.color = primaryColor.withValues(alpha: 0.9);
    _sharedPaint.strokeWidth = math.max(1.0, _sharedPaint.strokeWidth * 0.7);

    canvas.drawPath(
      dashPath(path, dashArray: CircularIntervalList([dashLength, dashLength])),
      _sharedPaint,
    );
  }

  void _drawLaserStroke(Canvas canvas, LaserStroke stroke) {
    // Impeller: MaskFilter.blur is expensive. Prefer a soft alpha halo via a
    // second filled path when zoomed out; only blur at close scales.
    final opacity = stroke.fadeOpacity.clamp(0.0, 1.0);
    if (opacity <= 0.001) return;

    final useBlur = currentScale >= 1.25;
    _sharedPaint.style = PaintingStyle.fill;
    _sharedPaint.shader = null;
    _sharedPaint.colorFilter = null;

    if (useBlur) {
      _sharedPaint.color = stroke.color
          .withInversion(invert)
          .withValues(alpha: opacity);
      _sharedPaint.maskFilter = MaskFilter.blur(
        BlurStyle.solid,
        stroke.options.size * 0.35,
      );
      canvas.drawPath(_selectPath(stroke), _sharedPaint);
    } else {
      _sharedPaint.maskFilter = null;
      _sharedPaint.color = stroke.color
          .withInversion(invert)
          .withValues(alpha: 0.35 * opacity);
      canvas.drawPath(_selectPath(stroke), _sharedPaint);
      _sharedPaint.color = stroke.color
          .withInversion(invert)
          .withValues(alpha: opacity);
      canvas.drawPath(stroke.innerPath, _sharedPaint);
    }

    _sharedPaint.color = Color.fromRGBO(255, 255, 255, 0.87 * opacity);
    _sharedPaint.maskFilter = null;
    canvas.drawPath(stroke.innerPath, _sharedPaint);
  }

  /// Permanent neon ink (ballpoint only).
  ///
  /// Glow is a translucent outer path (no MaskFilter — blur stays on laser only).
  /// Body uses the fast spine mesh; white core uses a cached inset path.
  void _drawNeonInkStroke(Canvas canvas, Stroke stroke, Color color) {
    _sharedPaint.style = PaintingStyle.fill;
    _sharedPaint.shader = null;
    _sharedPaint.colorFilter = null;
    _sharedPaint.blendMode = BlendMode.srcOver;
    _sharedPaint.isAntiAlias = true;
    _sharedPaint.maskFilter = null;

    final outer = _selectPath(stroke);
    final mesh = stroke.ensureMeshVertices();
    final onScreen = stroke.options.size * currentScale;

    // Soft halo without blur.
    _sharedPaint.color = color.withValues(alpha: 0.35);
    canvas.drawPath(outer, _sharedPaint);

    // Saturated body: GPU mesh when available (same quality as normal ballpoint).
    _sharedPaint.color = color;
    if (mesh != null) {
      _sharedPaint.isAntiAlias = false;
      canvas.drawVertices(mesh, BlendMode.srcOver, _sharedPaint);
      _sharedPaint.isAntiAlias = true;
      canvas.drawVertices(mesh, BlendMode.srcOver, _sharedPaint);
    } else {
      canvas.drawPath(stroke.neonInnerPath, _sharedPaint);
    }

    // White hotspot — skip when effectively sub-pixel on screen.
    if (onScreen >= 1.25) {
      _sharedPaint.color = const Color(0xDDffffff);
      canvas.drawPath(stroke.neonInnerPath, _sharedPaint);
    }
  }

  /// Staged neon ink: frozen butt-jointed chunks + live tail, same three
  /// draws per chunk as [_drawNeonInkStroke]. Falls back to the single
  /// build when staging produced nothing (degenerate).
  void _drawStagedNeonInkStroke(Canvas canvas, Stroke stroke, Color color) {
    final chunks = stroke.liveStagedChunks;
    if (chunks.isEmpty) {
      _drawNeonInkStroke(canvas, stroke, color);
      return;
    }
    _sharedPaint.style = PaintingStyle.fill;
    _sharedPaint.shader = null;
    _sharedPaint.colorFilter = null;
    _sharedPaint.blendMode = BlendMode.srcOver;
    _sharedPaint.isAntiAlias = true;
    _sharedPaint.maskFilter = null;

    final onScreen = stroke.options.size * currentScale;
    for (final c in chunks) {
      final outer = c.path;
      if (outer == null) continue;
      // Soft halo without blur.
      _sharedPaint.color = color.withValues(alpha: 0.35);
      canvas.drawPath(outer, _sharedPaint);

      // Saturated body: GPU mesh when available, else the white-core path.
      _sharedPaint.color = color;
      if (c.mesh != null) {
        _sharedPaint.isAntiAlias = false;
        canvas.drawVertices(c.mesh!, BlendMode.srcOver, _sharedPaint);
        _sharedPaint.isAntiAlias = true;
        canvas.drawVertices(c.mesh!, BlendMode.srcOver, _sharedPaint);
      } else if (c.auxPath != null) {
        canvas.drawPath(c.auxPath!, _sharedPaint);
      }

      // White hotspot — skip when effectively sub-pixel on screen.
      if (onScreen >= 1.25 && c.auxPath != null) {
        _sharedPaint.color = const Color(0xDDffffff);
        canvas.drawPath(c.auxPath!, _sharedPaint);
      }
    }
  }

  /// Staged pencil: ONE union fill over the frozen chunk outlines + live tail.
  ///
  /// Chunks overlap by a few points so butt joints can never open a hairline
  /// crack; because they are combined into a single non-zero fill before
  /// drawing, that overlap still shades every pixel exactly once. A per-chunk
  /// draw would band, and an exact butt cut would leave AA seams.
  void _drawStagedPencilStroke(Canvas canvas, Stroke stroke, Color color) {
    final chunks = stroke.liveStagedChunks;
    if (chunks.isEmpty) {
      _drawPencilNoiseStroke(canvas, stroke, color, visibleCount: 1);
      return;
    }
    final size = stroke.options.size;
    final union = Path()..fillType = PathFillType.nonZero;
    for (final c in chunks) {
      final outline = c.path;
      if (outline != null) union.addPath(outline, Offset.zero);
    }
    if (union.getBounds().isEmpty) return;

    final shader = page.tryPencilShader();

    if (shader == null) {
      PencilShader.paintGrainFallback(
        canvas: canvas,
        color: color,
        cfg: stroke.paint,
        outline: union,
        currentScale: currentScale,
        visibleCount: 1,
        strokeSize: size,
      );
      return;
    }

    PencilShader.paintGrainPath(
      canvas: canvas,
      shader: shader,
      color: color,
      cfg: stroke.paint,
      outline: union,
      currentScale: currentScale,
      visibleCount: 1,
      strokeSize: size,
    );
  }

  void _drawEraserIndicator(Canvas canvas) {
    final position = eraserPositionListenable?.value ?? eraserPosition;
    if (position == null || eraserSize == null) return;

    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.scale(1.0 / currentScale, 1.0 / currentScale);

    const strokeWidth = 2.0;
    final radiusPx = eraserSize! * currentScale;

    _sharedPaint.color = Colors.grey.withValues(alpha: 0.15);
    _sharedPaint.style = PaintingStyle.fill;
    _sharedPaint.isAntiAlias = true;
    _sharedPaint.maskFilter = null;

    canvas.drawCircle(Offset.zero, radiusPx, _sharedPaint);

    _sharedPaint.color = Colors.grey.withValues(alpha: 0.4);
    _sharedPaint.style = PaintingStyle.stroke;
    _sharedPaint.strokeWidth = strokeWidth;

    canvas.drawCircle(Offset.zero, radiusPx - strokeWidth / 2, _sharedPaint);

    canvas.restore();
  }

  void _drawSelection(Canvas canvas) {
    if (currentSelection == null) return;

    final selection = currentSelection!;
    final selectionPath = selection.path;
    final bounds = selection.getBounds();
    final lassoBounds = selectionPath.getBounds();

    final hasObjects = !selection.isEmpty;
    final hasLasso =
        !doneSelecting && (lassoBounds.width > 0 || lassoBounds.height > 0);

    if (!hasObjects && !hasLasso) return;

    if (!doneSelecting) {
      final visualPath = Path.from(selectionPath);
      if (visualPath.getBounds().width > 0 ||
          visualPath.getBounds().height > 0) {
        visualPath.close();
      }

      final selectionColor = primaryColor;

      canvas.drawPath(
        visualPath,
        Paint()..color = selectionColor.withValues(alpha: 0.15),
      );

      canvas.drawPath(
        dashPath(visualPath, dashArray: CircularIntervalList([6, 6])),
        Paint()
          ..color = selectionColor.withValues(alpha: 0.8)
          ..strokeWidth = 1.2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );

      return;
    }

    final selectionColor = primaryColor;

    if (selection.alignmentGuides.isNotEmpty) {
      final guidePaint = Paint()
        ..color = selectionColor.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      for (final guide in selection.alignmentGuides) {
        final path = Path()
          ..moveTo(guide.start.dx, guide.start.dy)
          ..lineTo(guide.end.dx, guide.end.dy);
        canvas.drawPath(
          dashPath(path, dashArray: CircularIntervalList([8, 6])),
          guidePaint,
        );
      }
    }

    final rotationRad =
        (selectionPreview?.effectiveRotationDeg ?? selection.rotationDeg) *
        math.pi /
        180.0;
    final visualBounds =
        selectionPreview?.visualBounds ?? selection.displayBounds ?? bounds;
    final centroid = visualBounds.center;

    canvas.save();

    canvas.translate(centroid.dx, centroid.dy);
    canvas.rotate(rotationRad);
    canvas.translate(-centroid.dx, -centroid.dy);

    final rect = visualBounds;

    canvas.drawRect(
      rect,
      Paint()
        ..color = selectionColor.withValues(alpha: 0.04)
        ..style = PaintingStyle.fill,
    );

    canvas.drawRect(
      rect,
      Paint()
        ..color = selectionColor.withValues(alpha: 0.7)
        ..strokeWidth = 1.5 / currentScale
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke,
    );

    canvas.restore();
  }

  static const double _pageIndicatorFontSize = 20;
  static const double _pageIndicatorPadding = 5;
  void _drawPageIndicator(Canvas canvas, Size pageSize) {
    if (!showPageIndicator) return;

    final style = ui.ParagraphStyle(
      textAlign: .end,
      textDirection: .ltr,
      maxLines: 1,
    );

    final builder = ui.ParagraphBuilder(style)
      ..pushStyle(
        ui.TextStyle(
          color: Colors.black.withInversion(invert).withValues(alpha: 0.5),
          fontSize: _pageIndicatorFontSize,
          fontFamily: defaultTextStyle.fontFamily,
          fontFamilyFallback: defaultTextStyle.fontFamilyFallback,
        ),
      )
      ..addText('${pageIndex + 1} / $totalPages');

    final paragraph = builder.build();
    paragraph.layout(
      ui.ParagraphConstraints(
        width: pageSize.width - 2 * _pageIndicatorPadding,
      ),
    );

    canvas.drawParagraph(
      paragraph,
      Offset(
        _pageIndicatorPadding,
        pageSize.height - _pageIndicatorPadding - _pageIndicatorFontSize * 1.2,
      ),
    );
  }

  Path _selectPath(Stroke stroke) {
    // First frames after open: cheap outline until HQ polygon is built.
    // If we are painting a small number of strokes (e.g., newly added ones over a raster during zoom),
    // we can afford to use the high quality path immediately to avoid the ugly fallback.
    if (stroke.hasCachedHighQualityPolygon || strokes.length < 100) return stroke.highQualityPath;
    return stroke.lowQualityPath;
  }
}
