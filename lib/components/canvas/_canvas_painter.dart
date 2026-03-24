// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_shape_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
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
    this.eraserSize,
    this.doneSelecting = false,
    this.lineHeight,
    this.lineThickness,
    this.lineColor,
    this.excludedStrokes,
  });

  final bool invert;
  final List<Stroke> strokes;

  final SpatialGrid? spatialGrid;

  final QuadTree<int>? quadTree;

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
  final double? eraserSize;
  final bool doneSelecting;
  final int? lineHeight;
  final double? lineThickness;
  final Color? lineColor;

  final Set<Stroke>? excludedStrokes;

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

    const int linearScanThreshold = 999999;
    final hasSpatialIndex = quadTree != null || spatialGrid != null;
    if (previewingSelection) {
      visibleStrokes = strokes;
    } else if (hasSpatialIndex && strokes.length > linearScanThreshold) {
      final List<int> indices;
      if (quadTree != null) {
        indices = quadTree!.query(cullingRect);

        indices.sort();
      } else {

        indices = spatialGrid!.query(cullingRect);
      }
      _reusableQueryBuffer.clear();
      for (final i in indices) {
        if (i >= 0 && i < strokes.length) {
          _reusableQueryBuffer.add(strokes[i]);
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
              stroke.toolId == ToolId.calligraphyPen ||
              stroke is ShapeStroke;
          if ((overlaps || forceRecentSensitiveStroke) &&
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

    _drawHighlighterStrokes(canvas, visibleStrokes);

    if (batchedStrokes != null && batchedStrokes!.isNotEmpty) {

      final batchPaint = Paint()..isAntiAlias = true;
      for (final entry in batchedStrokes!.entries) {
        batchPaint.color = Color(entry.key).withInversion(invert);
        for (final vertices in entry.value) {
          canvas.drawVertices(vertices, BlendMode.srcOver, batchPaint);
        }
      }

      final unbatchable = visibleStrokes
          .where(
            (s) =>
                s is ShapeStroke ||
                s.vertices == null,
          )
          .toList();
      _drawNonHighlighterStrokes(canvas, unbatchable, cullingRect);
    } else {
      _drawNonHighlighterStrokes(canvas, visibleStrokes, cullingRect);
    }

    if (selectionPreview != null) {
      canvas.restore();
    }

    for (final stroke in laserStrokes) {

      if (cullingRect.overlaps(stroke.bounds)) {
        _drawLaserStroke(canvas, stroke);
      }
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
        doneSelecting != oldDelegate.doneSelecting ||

        lineHeight != oldDelegate.lineHeight ||
        lineThickness != oldDelegate.lineThickness ||
        lineColor != oldDelegate.lineColor ||

        spatialGrid != oldDelegate.spatialGrid ||
        quadTree != oldDelegate.quadTree ||
        excludedStrokes != oldDelegate.excludedStrokes;
  }

  void _drawHighlighterStrokes(Canvas canvas, List<Stroke> visibleStrokes) {

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..blendMode = invert ? BlendMode.plus : BlendMode.darken;

    for (final stroke in visibleStrokes) {
      if (stroke.toolId != ToolId.highlighter) continue;

      paint.color = stroke.color.withInversion(invert);

      if (stroke.vertices != null) {
        paint.isAntiAlias = true;

        canvas.drawVertices(stroke.vertices!, BlendMode.dst, paint);
      } else {
        canvas.drawPath(_selectPath(stroke), paint);
      }
    }
  }

  static final _sharedPaint = Paint();

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

    for (final stroke in visibleStrokes) {
      if (stroke.toolId == ToolId.highlighter) continue;

      var color = stroke.color.withInversion(invert);
      final isSelected = allVisibleStrokesAreSelected
          ? true
          : selectedStrokeSet?.contains(stroke) ??
                selectedStrokes?.contains(stroke) ??
                false;
      if (isSelected) {
        color = Color.lerp(color, primaryColor, 0.5)!;
      }

      _sharedPaint
        ..color = color
        ..shader = null
        ..maskFilter = null;

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

      if (stroke.vertices != null) {
        _sharedPaint.style = PaintingStyle.fill;
        _sharedPaint.isAntiAlias = true;
        canvas.drawVertices(stroke.vertices!, BlendMode.srcOver, _sharedPaint);
      } else {

        _sharedPaint.style = PaintingStyle.fill;
        canvas.drawPath(_selectPath(stroke), _sharedPaint);
      }
    }
  }

  void _drawCurrentStroke(Canvas canvas) {
    if (currentStroke == null) return;

    currentStroke!.setLodScale(currentScale);

    if (currentStroke! is LaserStroke) {
      return _drawLaserStroke(canvas, currentStroke as LaserStroke);
    }

    if (currentStroke is ShapeStroke) {
      final shape = currentStroke as ShapeStroke;
      final path = shape.shapePath;
      if (shape.fill) {
        final fillPaint = Paint()
          ..color = shape.fillColor.withInversion(invert)
          ..style = PaintingStyle.fill
          ..isAntiAlias = true;
        canvas.drawPath(path, fillPaint);
      }
      final strokePaint = Paint()
        ..color = shape.color.withInversion(invert)
        ..style = PaintingStyle.stroke
        ..strokeWidth = shape.options.size
        ..isAntiAlias = true
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(shape.strokeDrawPath, strokePaint);
      return;
    }

    final color = currentStroke!.color.withInversion(invert);
    final paint = Paint();

    paint.color = color;
    paint.shader = null;
    paint.maskFilter = null;

    if (currentStroke!.toolId == ToolId.highlighter) {
      paint
        ..style = PaintingStyle.fill
        ..blendMode = invert ? BlendMode.plus : BlendMode.darken
        ..isAntiAlias = true;
      if (currentStroke!.length == 1) {
        final p = currentStroke!.pointsForEraser.first;
        final baseSize =
            (currentStroke!.options.size / 2) *
            Stroke.highlighterStrokeScaleFactor;
        canvas.drawCircle(Offset(p.x, p.y), baseSize.clamp(0.5, 999.0), paint);
      } else if (currentStroke!.vertices != null) {
        canvas.drawVertices(currentStroke!.vertices!, BlendMode.dst, paint);
      } else {
        canvas.drawPath(_selectPath(currentStroke!), paint);
      }
      return;
    }

    // Visual parity: while drawing, [options.isComplete] is false until drag end.
    // Still draw the same triangle mesh as the committed stroke whenever [vertices]
    // is available (fountain, calligraphy, ballpoint mesh path, etc.). Using only
    // [highQualityPath] here regressed live preview into a simplified path vs final ink.
    if (currentStroke!.vertices != null) {
      paint.style = PaintingStyle.fill;
      paint.isAntiAlias = true;
      canvas.drawVertices(currentStroke!.vertices!, BlendMode.srcOver, paint);
      return;
    }

    if (currentStroke!.length == 1) {
      final p = currentStroke!.pointsForEraser.first;
      paint.style = PaintingStyle.fill;
      paint.isAntiAlias = true;
      canvas.drawCircle(
        Offset(p.x, p.y),
        (currentStroke!.options.size / 2).clamp(0.5, 999.0),
        paint,
      );
    } else {
      paint.style = PaintingStyle.fill;
      paint.isAntiAlias = true;
      canvas.drawPath(currentStroke!.highQualityPath, paint);
    }
  }

  void _drawDetectedShape(Canvas canvas) {
    final shape = currentStrokeDetectedShape;
    if (shape == null || currentStroke == null) return;

    final color = currentStroke!.color.withInversion(invert);
    final pulse = (0.55 + 0.35 * math.sin(shapePreviewPulse * 2 * math.pi))
        .clamp(0.2, 0.95);

    final shapePaint = Paint()
      ..color = Color.lerp(color, primaryColor, 0.5)!.withValues(alpha: pulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, currentStroke!.options.size * 1.05)
      ..isAntiAlias = true
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final dashedPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, shapePaint.strokeWidth * 0.7)
      ..isAntiAlias = true
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void drawPreviewPath(Path path) {
      canvas.drawPath(path, shapePaint);

      final dashLength = math.max(8.0, shapePaint.strokeWidth * 1.5);
      canvas.drawPath(
        dashPath(
          path,
          dashArray: CircularIntervalList([dashLength, dashLength]),
        ),
        dashedPaint,
      );
    }

    final path = buildDetectedShapePreviewPath(currentStroke!, shape);
    drawPreviewPath(path);
  }

  void _drawLaserStroke(Canvas canvas, LaserStroke stroke) {
    canvas.drawPath(
      _selectPath(stroke),
      Paint()
        ..color = stroke.color.withInversion(invert)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.solid,
          stroke.options.size * 0.4,
        ),
    );
    canvas.drawPath(stroke.innerPath, Paint()..color = const Color(0xDDffffff));
  }

  void _drawEraserIndicator(Canvas canvas) {
    if (eraserPosition == null || eraserSize == null) return;

    canvas.save();
    canvas.translate(eraserPosition!.dx, eraserPosition!.dy);
    canvas.scale(1.0 / currentScale, 1.0 / currentScale);

    const strokeWidth = 2.0;
    final radiusPx = eraserSize! * currentScale;

    final fillPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(Offset.zero, radiusPx, fillPaint);

    final strokePaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true;
    canvas.drawCircle(Offset.zero, radiusPx - strokeWidth / 2, strokePaint);

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

      canvas.drawPath(
        visualPath,
        Paint()..color = primaryColor.withValues(alpha: 0.15),
      );

      canvas.drawPath(
        dashPath(visualPath, dashArray: CircularIntervalList([6, 6])),
        Paint()
          ..color = primaryColor.withValues(alpha: 0.8)
          ..strokeWidth = 1.2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );

      return;
    }

    if (selection.alignmentGuides.isNotEmpty) {
      final guidePaint = Paint()
        ..color = primaryColor.withValues(alpha: 0.5)
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
        ..color = primaryColor.withValues(alpha: 0.04)
        ..style = PaintingStyle.fill,
    );

    canvas.drawRect(
      rect,
      Paint()
        ..color = primaryColor.withValues(alpha: 0.7)
        ..strokeWidth = 1.5 / currentScale
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke,
    );

    final topCenter = Offset(rect.center.dx, rect.top);
    final handleCenter = topCenter - Offset(0, 42.0 / currentScale);
    const double rotRadiusPx = 6.0;

    canvas.drawLine(
      topCenter,
      handleCenter + Offset(0, (rotRadiusPx + 1.0) / currentScale),
      Paint()
        ..color = primaryColor.withValues(alpha: 0.6)
        ..strokeWidth = 1.5 / currentScale
        ..isAntiAlias = true,
    );

    final displayRotationDeg =
        selectionPreview?.effectiveRotationDeg ?? selection.rotationDeg;
    final normalizedAngle = ((displayRotationDeg % 360) + 360) % 360;
    final angleText = '${normalizedAngle.toStringAsFixed(1)}°';
    final angleTextPainter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: angleText,
        style: TextStyle(
          color: primaryColor,
          fontSize: 10.0 / currentScale,
          fontWeight: FontWeight.w600,
        ),
      )
      ..layout();

    final double chipWidth = angleTextPainter.width + (12.0 / currentScale);
    final double chipHeight = 18.0 / currentScale;
    final double chipOffsetFromHandle =
        6.0 + (9.0 + 4.0) / currentScale;
    final chipCenter = handleCenter - Offset(0, chipOffsetFromHandle);

    final angleChipRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: chipCenter, width: chipWidth, height: chipHeight),
      Radius.circular(6.0 / currentScale),
    );

    canvas.drawRRect(
      angleChipRect,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.08)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.0 / currentScale)
        ..isAntiAlias = true,
    );

    canvas.drawRRect(
      angleChipRect,
      Paint()
        ..color = (invert ? const Color(0xFF1E1E1E) : Colors.white).withValues(
          alpha: 0.9,
        )
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );

    canvas.drawRRect(
      angleChipRect,
      Paint()
        ..color = primaryColor.withValues(alpha: 0.3)
        ..strokeWidth = 1.0 / currentScale
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true,
    );

    angleTextPainter.paint(
      canvas,
      chipCenter -
          Offset(angleTextPainter.width / 2, angleTextPainter.height / 2),
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

  Path _selectPath(Stroke stroke) => stroke.highQualityPath;
}
