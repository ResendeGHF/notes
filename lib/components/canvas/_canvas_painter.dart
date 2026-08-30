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

class CanvasPainter extends CustomPainter {
  const CanvasPainter({
    super.repaint,
    this.invert = false,
    required this.strokes,
    this.spatialGrid,
    this.quadTree,
    this.batchedStrokes,
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
    this.preferPathFill = false,
  });

  final bool invert;
  final List<Stroke> strokes;

  final SpatialGrid? spatialGrid;

  /// Paint-time spatial index over the [strokes] list (page QuadTree).
  final QuadTree<Stroke>? quadTree;

  /// Pre-batched meshes keyed by ARGB32 color. When non-null, drawn first.
  final Map<int, List<ui.Vertices>>? batchedStrokes;
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

  /// Draw authored paths and skip mesh/vertices so first paint cannot stall
  /// on triangulation.
  final bool preferPathFill;

  static final _reusableQueryBuffer = <Stroke>[];

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

    // Activates QuadTree/Spatial culling when there are more than 250 strokes.
    // Extremely vital for maintaining 120fps on large documents.
    const int linearScanThreshold = 250;
    final hasSpatialIndex = quadTree != null || spatialGrid != null;
    if (previewingSelection) {
      visibleStrokes = strokes;
    } else if (hasSpatialIndex && strokes.length > linearScanThreshold) {
      _reusableQueryBuffer.clear();
      if (quadTree != null) {
        final found = quadTree!.query(cullingRect);
        final strokeSet = strokes.length > 64 ? strokes.toSet() : null;
        for (final s in found) {
          if (strokeSet != null ? strokeSet.contains(s) : strokes.contains(s)) {
            _reusableQueryBuffer.add(s);
          }
        }
      } else {
        final indices = spatialGrid!.query(cullingRect);
        for (final i in indices) {
          if (i >= 0 && i < strokes.length) {
            _reusableQueryBuffer.add(strokes[i]);
          }
        }
      }
      visibleStrokes = _reusableQueryBuffer;

      if (strokes.isNotEmpty) {
        final int totalStrokes = strokes.length;
        final int checkRange = math.min(20, totalStrokes);
        final seenStrokes = <Stroke>{...visibleStrokes};
        for (int i = 0; i < checkRange; i++) {
          final stroke = strokes[totalStrokes - 1 - i];
          final bounds = stroke.bounds;
          final boundsFinite =
              bounds.left.isFinite &&
              bounds.top.isFinite &&
              bounds.right.isFinite &&
              bounds.bottom.isFinite;
          final overlaps = boundsFinite && cullingRect.overlaps(bounds);

          final forceRecentSensitiveStroke =
              stroke.toolId == ToolId.highlighter ||
              stroke.toolId == ToolId.advancedPen ||
              stroke.toolId == ToolId.advancedPencil ||
              stroke.toolId == ToolId.experimentalPen ||
              stroke.toolId == ToolId.calligraphyPen ||
              stroke is ShapeStroke;
          if ((overlaps || (!boundsFinite && forceRecentSensitiveStroke)) &&
              seenStrokes.add(stroke)) {
            visibleStrokes.add(stroke);
          }
        }
      }

      if (visibleStrokes.isEmpty && strokes.isNotEmpty) {
        visibleStrokes = strokes
            .where((s) => cullingRect.overlaps(s.bounds))
            .toList();
        if (visibleStrokes.isEmpty) {
          visibleStrokes = List<Stroke>.from(strokes);
        }
      }
    } else {
      for (final s in strokes) {
        if (cullingRect.overlaps(s.bounds)) {
          _reusableQueryBuffer.add(s);
        }
      }
      visibleStrokes = _reusableQueryBuffer;
    }

    if (excludedStrokes != null && excludedStrokes!.isNotEmpty) {
      visibleStrokes = visibleStrokes
          .where((s) => !excludedStrokes!.contains(s))
          .toList();
    }

    if (selectionPreview != null) {
      canvas.save();
      canvas.transform(selectionPreview!.transformMatrix.storage);
    }

    if (batchedStrokes != null &&
        batchedStrokes!.isNotEmpty &&
        !preferPathFill) {
      _drawBatchedMeshes(canvas);
    }
    _drawNonHighlighterStrokes(
      canvas,
      visibleStrokes,
      cullingRect,
      skipBatched:
          !preferPathFill &&
          batchedStrokes != null &&
          batchedStrokes!.isNotEmpty,
    );

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

    _drawSelection(canvas);
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
        currentScale != oldDelegate.currentScale ||
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
        preferPathFill != oldDelegate.preferPathFill;
  }

  static final _sharedPaint = Paint();

  void _drawBatchedMeshes(Canvas canvas) {
    final batches = batchedStrokes;
    if (batches == null || batches.isEmpty) return;
    _sharedPaint
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..shader = null
      ..maskFilter = null
      ..colorFilter = null
      ..blendMode = BlendMode.srcOver;

    for (final entry in batches.entries) {
      final color = Color(entry.key).withInversion(invert);
      _sharedPaint.color = color;
      for (final mesh in entry.value) {
        canvas.drawVertices(mesh, BlendMode.srcOver, _sharedPaint);
      }
    }
  }

  static BlendMode _meshBlendMode(ToolId toolId, {required bool invert}) {
    if (toolId == ToolId.highlighter) {
      return invert ? BlendMode.plus : BlendMode.darken;
    }
    return BlendMode.srcOver;
  }

  void _drawNonHighlighterStrokes(
    Canvas canvas,
    List<Stroke> visibleStrokes,
    Rect cullingRect, {
    bool skipBatched = false,
  }) {
    final selectedStrokes = currentSelection?.strokes;
    final bool allVisibleStrokesAreSelected =
        selectedStrokes != null && identical(visibleStrokes, selectedStrokes);
    final Set<Stroke>? selectedStrokeSet =
        allVisibleStrokesAreSelected || selectedStrokes == null
        ? null
        : selectedStrokes.length > 8
        ? selectedStrokes.toSet()
        : null;

    Color? pencilLastColor;
    StrokePaint? pencilLastCfg;
    double? pencilLastQuality;
    var pencilVisibleCount = 0;
    for (final s in visibleStrokes) {
      if (s.toolId == ToolId.advancedPencil || s.paint.usesPencilNoise) {
        pencilVisibleCount++;
      }
    }

    for (var i = 0; i < visibleStrokes.length; i++) {
      final stroke = visibleStrokes[i];
      if (!preferPathFill && skipBatched && stroke.canBatchSolidMesh) continue;

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
        ..blendMode = stroke.toolId == ToolId.highlighter
            ? (invert ? BlendMode.plus : BlendMode.darken)
            : BlendMode.srcOver
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

      if (stroke.toolId == ToolId.advancedPencil ||
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
        );
        continue;
      }

      if (preferPathFill) {
        _sharedPaint.style = PaintingStyle.fill;
        _sharedPaint.isAntiAlias = true;
        canvas.drawPath(_selectPath(stroke), _sharedPaint);
        continue;
      }

      if (stroke.vertices != null) {
        _sharedPaint.style = PaintingStyle.fill;
        _sharedPaint.isAntiAlias = true;
        canvas.drawVertices(
          stroke.vertices!,
          _meshBlendMode(stroke.toolId, invert: invert),
          _sharedPaint,
        );
      } else {
        final picture = stroke.ensureSolidPathPicture(
          invert: invert,
          color: color,
        );
        if (picture != null) {
          canvas.drawPicture(picture);
        } else {
          _sharedPaint.style = PaintingStyle.fill;
          canvas.drawPath(_selectPath(stroke), _sharedPaint);
        }
      }
    }
  }

  void _drawTexturedStrokePath(
    Canvas canvas,
    Stroke stroke,
    Path path,
    Color fallbackColor, {
    bool isLive = false,
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
    canvas.drawPath(path, _sharedPaint);
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
  }) {
    final chunks = stroke.pencilDrawChunks;
    final path = chunks == null || chunks.isEmpty
        ? _selectPath(stroke)
        : null;
    if (path != null && path.getBounds().isEmpty) return null;
    if (chunks != null &&
        chunks.isNotEmpty &&
        chunks.every((c) => c.outline.getBounds().isEmpty)) {
      return null;
    }

    final shader = page.tryPencilShader();
    if (shader == null) {
      final outlines = chunks != null && chunks.isNotEmpty
          ? [for (final chunk in chunks) chunk.outline]
          : [path!];
      for (final outline in outlines) {
        if (outline.getBounds().isEmpty) continue;
        PencilShader.paintCastShadow(
          canvas: canvas,
          outline: outline,
          strokeColor: color,
          size: stroke.options.size,
          currentScale: currentScale,
          visibleCount: visibleCount,
          quality: 1.0,
          lodTier: PencilShader.lodTierForScale(currentScale),
          enabled: stroke.paint.pencilShadow,
        );
        _sharedPaint
          ..style = PaintingStyle.fill
          ..isAntiAlias = true
          ..shader = null
          ..colorFilter = null
          ..maskFilter = null
          ..color = color.withValues(alpha: 0.55);
        canvas.drawPath(outline, _sharedPaint);
      }
      return null;
    }

    final size = stroke.options.size;
    if (chunks != null && chunks.isNotEmpty) {
      var configured = false;
      double quality = 1.0;
      for (final chunk in chunks) {
        if (chunk.outline.getBounds().isEmpty) continue;
        quality = chunk.plan.quality;
        PencilShader.paintPlan(
          canvas: canvas,
          shader: shader,
          color: color,
          cfg: stroke.paint,
          outline: chunk.outline,
          plan: chunk.plan,
          stampWidth: PencilShader.stampWidthFor(
            size,
            stroke.options.maxSizeRatio,
          ),
          configureBaseUniforms:
              !configured ||
              !PencilShader.sameConfig(
                color: color,
                cfg: stroke.paint,
                quality: chunk.plan.quality,
                lastColor: lastColor,
                lastCfg: lastCfg,
                lastQuality: lastQuality,
              ),
          pressureSensitivity: stroke.options.pressureSensitivity,
          currentScale: currentScale,
          visibleCount: visibleCount,
          strokeSize: size,
        );
        configured = true;
      }
      return (color, stroke.paint, quality);
    }

    // The in-progress stroke stays at writing quality; committed strokes
    // cheapen stamps (not grain) when the viewport is crowded.
    final plan = stroke.orientedPencilPlan(
      currentScale,
      visibleCount: identical(stroke, currentStroke) ? 1 : visibleCount,
    );
    PencilShader.paintPlan(
      canvas: canvas,
      shader: shader,
      color: color,
      cfg: stroke.paint,
      outline: path!,
      plan: plan,
      stampWidth: PencilShader.stampWidthFor(size, stroke.options.maxSizeRatio),
      configureBaseUniforms: !PencilShader.sameConfig(
        color: color,
        cfg: stroke.paint,
        quality: plan.quality,
        lastColor: lastColor,
        lastCfg: lastCfg,
        lastQuality: lastQuality,
      ),
      pressureSensitivity: stroke.options.pressureSensitivity,
      currentScale: currentScale,
      visibleCount: visibleCount,
      strokeSize: size,
    );
    return (color, stroke.paint, plan.quality);
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
      _drawNeonInkStroke(
        canvas,
        currentStroke!,
        currentStroke!.color.withInversion(invert),
      );
      return;
    }

    if (currentStroke!.toolId == ToolId.advancedPencil ||
        currentStroke!.paint.usesPencilNoise) {
      _drawPencilNoiseStroke(
        canvas,
        currentStroke!,
        currentStroke!.color.withInversion(invert),
        visibleCount: 1,
      );
      return;
    }

    if (currentStroke!.hasNonSolidPaint) {
      final path = currentStroke!.vertices != null
          ? currentStroke!.highQualityPath
          : (currentStroke!.length == 1
                ? (Path()..addOval(
                    Rect.fromCircle(
                      center: Offset(
                        currentStroke!.pointsForEraser.first.x,
                        currentStroke!.pointsForEraser.first.y,
                      ),
                      radius: (currentStroke!.options.size / 2).clamp(
                        0.5,
                        999.0,
                      ),
                    ),
                  ))
                : currentStroke!.highQualityPath);
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
      } else if (currentStroke!.vertices != null) {
        canvas.drawVertices(
          currentStroke!.vertices!,
          _meshBlendMode(currentStroke!.toolId, invert: invert),
          _sharedPaint,
        );
      } else {
        canvas.drawPath(_selectPath(currentStroke!), _sharedPaint);
      }

      _sharedPaint.blendMode = BlendMode.srcOver;
      return;
    }

    if (currentStroke!.vertices != null) {
      canvas.drawVertices(
        currentStroke!.vertices!,
        _meshBlendMode(currentStroke!.toolId, invert: invert),
        _sharedPaint,
      );
      return;
    }

    if (currentStroke!.length == 1) {
      final p = currentStroke!.pointsForEraser.first;
      canvas.drawCircle(
        Offset(p.x, p.y),
        (currentStroke!.options.size / 2).clamp(0.5, 999.0),
        _sharedPaint,
      );
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

      final selectionColor = Colors.black.withInversion(invert);

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

    final selectionColor = Colors.black.withInversion(invert);

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
    if (stroke.hasCachedHighQualityPolygon) return stroke.highQualityPath;
    return stroke.lowQualityPath;
  }
}
