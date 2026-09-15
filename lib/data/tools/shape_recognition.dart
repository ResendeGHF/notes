// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart'
    show
        computeRoundness,
        DefaultUnistrokeNames,
        isAngleBracketPreferred,
        isBracePreferred,
        isBracketPreferred,
        RecognizedUnistroke;
import 'package:saber/data/stroke_geometry/stroke_geometry.dart'
    show StrokeEndOptions;
import 'package:saber/components/canvas/_shape_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/shape_geometry.dart';
import 'package:saber/data/tools/shape_tool.dart';

class ShapeRecognitionTimer {
  Timer? _timer;

  void update(void Function() onRecognize) {
    final delay = stows.shapeRecognitionDelay.value;

    if (delay < 0) {
      cancel();
      return;
    }

    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: delay), onRecognize);
  }

  void cancel() {
    _timer?.cancel();
  }
}

/// Highlighter blend modes need ink strokes; straighten to a dense line.
Stroke _highlighterLineInk(Stroke rawStroke) {
  final s = rawStroke.copy();
  s.convertToLine();
  s.densifyStraightLine();
  return s;
}

ShapeStroke _shapeFromConfig(Stroke rawStroke, ShapeConfig config) {
  return ShapeStroke(
    color: rawStroke.color,
    fillColor: rawStroke.color.withValues(alpha: 0.2),
    fill: false,
    pressureEnabled: false,
    options: rawStroke.options.copyWith(
      simulatePressure: false,
      isComplete: true,
      start: StrokeEndOptions.start(
        taperEnabled: false,
        customTaper: rawStroke.options.start.customTaper,
        cap: rawStroke.options.start.cap,
        easing: rawStroke.options.start.easing,
      ),
      end: StrokeEndOptions.end(
        taperEnabled: false,
        customTaper: rawStroke.options.end.customTaper,
        cap: rawStroke.options.end.cap,
        easing: rawStroke.options.end.easing,
      ),
    ),
    pageIndex: rawStroke.pageIndex,
    page: rawStroke.page,
    toolId: ToolId.shapeTool,
    config: config.ensuredControlPoints(),
  );
}

List<Offset> _fitPoints(Stroke rawStroke, RecognizedUnistroke detected) {
  // Prefer the drawn centerline. highQualityPolygon is a thickened outline and
  // inflates size / invents sharp corners that break ellipse vs rect decisions.
  final orig = detected.originalPoints;
  if (orig.length >= 2) return orig;
  final hq = rawStroke.highQualityPolygon;
  if (hq.length >= 3) return hq;
  return const <Offset>[];
}

/// Classify with `$1`, then fit a parametric [ShapeStroke] (or ink for highlighter lines).
Stroke convertStrokeToShapeStroke(
  Stroke rawStroke,
  RecognizedUnistroke detected,
) {
  final points = _fitPoints(rawStroke, detected);
  if (points.length < 2) return rawStroke;

  final String name = detected.name?.toString().split('.').last ?? '';
  final isHighlighter = rawStroke.toolId == ToolId.highlighter;

  switch (detected.name) {
    case DefaultUnistrokeNames.line:
      if (isHighlighter) return _highlighterLineInk(rawStroke);
      final cfg = ShapeGeometry.fitLine(points);
      return cfg != null ? _shapeFromConfig(rawStroke, cfg) : rawStroke;

    case DefaultUnistrokeNames.arrow:
      if (isHighlighter) return _highlighterLineInk(rawStroke);
      final cfg = ShapeGeometry.fitLine(points, kind: ShapeKind.arrow);
      return cfg != null ? _shapeFromConfig(rawStroke, cfg) : rawStroke;

    case DefaultUnistrokeNames.rectangle:
      final roundness = points.length >= 4 ? computeRoundness(points) : 0.5;
      final oriented = ShapeGeometry.fitOrientedRect(points);
      final aspect = oriented == null
          ? 1.0
          : oriented.width / math.max(oriented.height, 1e-6);
      final extremeAspect = aspect > 1.75 || aspect < 1 / 1.75;

      // `$1` often labels elongated ellipses as rectangles (aspect destroyed by
      // square-normalization). Decide with comparable residuals + roundness.
      // Clearly angular → keep rectangle.
      var asEllipse = false;
      if (roundness <= 0.15) {
        asEllipse = false;
      } else {
        final ellipseFit = points.length >= 5
            ? ShapeGeometry.fitEllipseAlgebraic(points)
            : null;
        if (ellipseFit != null && oriented != null) {
          final eErr = ShapeGeometry.ellipseFitError(
            points,
            center: ellipseFit.center,
            rx: ellipseFit.rx,
            ry: ellipseFit.ry,
            angleRad: ellipseFit.angleRad,
          );
          final rErr = ShapeGeometry.orientedRectFitError(
            points,
            center: oriented.center,
            width: oriented.width,
            height: oriented.height,
            angleRad: oriented.angleRad,
          );
          if (eErr < rErr * 0.95) {
            asEllipse = true;
          } else if (extremeAspect && eErr <= rErr * 1.2 && roundness >= 0.4) {
            asEllipse = true;
          } else if (roundness >= 0.7 && eErr <= rErr * 1.1) {
            asEllipse = true;
          }
        } else if (roundness >= 0.65) {
          asEllipse = true;
        }
      }
      if (asEllipse) {
        final cfg = ShapeGeometry.fitEllipse(points);
        return cfg != null ? _shapeFromConfig(rawStroke, cfg) : rawStroke;
      }
      final cfg = ShapeGeometry.fitRectangle(points);
      return cfg != null ? _shapeFromConfig(rawStroke, cfg) : rawStroke;

    case DefaultUnistrokeNames.circle:
      // `$1` has a circle template, not an ellipse — ovals land here too.
      // A circle is just an ellipse with equal axes, so always fit an ellipse.
      final roundness = points.length >= 4 ? computeRoundness(points) : 0.7;
      // Only demote to square when the stroke is clearly angular.
      if (roundness <= 0.15) {
        final cfg = ShapeGeometry.fitRectangle(points);
        return cfg != null ? _shapeFromConfig(rawStroke, cfg) : rawStroke;
      }
      // Residual tie-break: freehand squares sometimes score as circles in `$1`.
      if (roundness < 0.45 && points.length >= 5) {
        final oriented = ShapeGeometry.fitOrientedRect(points);
        final ellipseFit = ShapeGeometry.fitEllipseAlgebraic(points);
        if (oriented != null && ellipseFit != null) {
          final eErr = ShapeGeometry.ellipseFitError(
            points,
            center: ellipseFit.center,
            rx: ellipseFit.rx,
            ry: ellipseFit.ry,
            angleRad: ellipseFit.angleRad,
          );
          final rErr = ShapeGeometry.orientedRectFitError(
            points,
            center: oriented.center,
            width: oriented.width,
            height: oriented.height,
            angleRad: oriented.angleRad,
          );
          if (rErr < eErr * 0.75) {
            final cfg = ShapeGeometry.fitRectangle(points);
            return cfg != null ? _shapeFromConfig(rawStroke, cfg) : rawStroke;
          }
        }
      }
      final cfg = ShapeGeometry.fitEllipse(points);
      return cfg != null ? _shapeFromConfig(rawStroke, cfg) : rawStroke;

    case DefaultUnistrokeNames.triangle:
      final orig = detected.originalPoints;
      final box = ShapeGeometry.boundsOf(orig);
      final closed =
          orig.length >= 3 &&
          (orig.first - orig.last).distance <=
              math.max(8.0, box.shortestSide * 0.25);
      if (!closed &&
          orig.length >= 3 &&
          isAngleBracketPreferred(orig)) {
        final angleName = _angleBracketLeftRight(orig);
        return _shapeStrokeFromSymbol(rawStroke, detected, angleName);
      }
      final cfg = ShapeGeometry.fitTriangle(points);
      return cfg != null ? _shapeFromConfig(rawStroke, cfg) : rawStroke;

    case DefaultUnistrokeNames.star:
      final cfg = ShapeGeometry.fitStar(points);
      return cfg != null ? _shapeFromConfig(rawStroke, cfg) : rawStroke;

    case DefaultUnistrokeNames.infinity:
      return _shapeStrokeFromSymbol(rawStroke, detected, 'infinity');

    default:
      if (const {
        'summatory',
        'productory',
        'leftBracket',
        'rightBracket',
        'leftAngleBracket',
        'rightAngleBracket',
        'leftBrace',
        'rightBrace',
        'infinity',
      }.contains(name)) {
        return _shapeStrokeFromSymbol(
          rawStroke,
          detected,
          _disambiguateSymbolName(name, detected.originalPoints),
        );
      }
      return rawStroke;
  }
}

Stroke _shapeStrokeFromSymbol(
  Stroke rawStroke,
  RecognizedUnistroke detected,
  String name,
) {
  final canonical = detected.convertToCanonicalPolygon();
  if (canonical.length < 2) return rawStroke;
  final bounds = ShapeGeometry.boundsOf(canonical);
  final kind = _symbolNameToShapeKind(name);
  if (kind == null) return rawStroke;
  return _shapeFromConfig(
    rawStroke,
    ShapeConfig(
      kind: kind,
      bounds: bounds,
      start: bounds.topLeft,
      end: bounds.bottomRight,
    ),
  );
}

bool _angleBracketDrawnBottomToTop(List<Offset> points) {
  if (points.length < 2) return false;
  return points.first.dy > points.last.dy;
}

String _angleBracketLeftRight(List<Offset> points) {
  final box = ShapeGeometry.boundsOf(points);
  final cx = box.center.dx;
  final leftCount = points.where((p) => p.dx < cx).length;
  final moreOnLeft = leftCount >= points.length / 2;
  final drawnBottomToTop = _angleBracketDrawnBottomToTop(points);
  final isLeft = drawnBottomToTop ? !moreOnLeft : moreOnLeft;
  return isLeft ? 'leftAngleBracket' : 'rightAngleBracket';
}

String _disambiguateSymbolName(String name, List<Offset> points) {
  final box = ShapeGeometry.boundsOf(points);
  final cx = box.center.dx;
  var leftCount = 0;
  for (final p in points) {
    if (p.dx < cx) leftCount++;
  }
  final rightCount = points.length - leftCount;

  if (name == 'leftAngleBracket' || name == 'rightAngleBracket') {
    if (isBracePreferred(points)) {
      return rightCount > leftCount ? 'leftBrace' : 'rightBrace';
    }
  }

  if (name == 'leftBracket' || name == 'rightBracket') {
    if (isAngleBracketPreferred(points)) {
      return _angleBracketLeftRight(points);
    }
  }

  if (name == 'leftBrace' || name == 'rightBrace') {
    if (isAngleBracketPreferred(points)) {
      return _angleBracketLeftRight(points);
    }
    if (rightCount > leftCount) return 'rightBrace';
    if (leftCount > rightCount) return 'leftBrace';
  }

  if (name == 'productory' || name == 'summatory') {
    if (isBracketPreferred(points)) {
      return leftCount >= points.length / 2 ? 'rightBracket' : 'leftBracket';
    }
  }

  if (name == 'leftBracket' || name == 'rightBracket') {
    if (isAngleBracketPreferred(points)) {
      return _angleBracketLeftRight(points);
    }
    return leftCount >= points.length / 2 ? 'rightBracket' : 'leftBracket';
  }
  return name;
}

ShapeKind? _symbolNameToShapeKind(String name) {
  switch (name) {
    case 'summatory':
      return ShapeKind.summatory;
    case 'productory':
      return ShapeKind.productory;
    case 'leftBracket':
      return ShapeKind.leftBracket;
    case 'rightBracket':
      return ShapeKind.rightBracket;
    case 'leftAngleBracket':
      return ShapeKind.leftAngleBracket;
    case 'rightAngleBracket':
      return ShapeKind.rightAngleBracket;
    case 'leftBrace':
      return ShapeKind.leftBrace;
    case 'rightBrace':
      return ShapeKind.rightBrace;
    case 'infinity':
      return ShapeKind.infinity;
    default:
      return null;
  }
}

Path? _cachedShapePreviewPath;
RecognizedUnistroke? _cachedShapePreviewDetected;
int _cachedShapePreviewStrokeLen = -1;
int _cachedShapePreviewStrokeId = 0;

/// Clears the cached dashed preview path (call when hold preview ends).
void clearDetectedShapePreviewCache() {
  _cachedShapePreviewPath = null;
  _cachedShapePreviewDetected = null;
  _cachedShapePreviewStrokeLen = -1;
  _cachedShapePreviewStrokeId = 0;
}

Path buildDetectedShapePreviewPath(
  Stroke rawStroke,
  RecognizedUnistroke detected,
) {
  // Rebuilding ShapeStroke (~2k samples) every 33ms pulse was a major lag/crash
  // source while a suggestion was visible. Cache until the detection changes.
  final strokeId = identityHashCode(rawStroke);
  if (identical(_cachedShapePreviewDetected, detected) &&
      _cachedShapePreviewStrokeId == strokeId &&
      _cachedShapePreviewStrokeLen == rawStroke.length &&
      _cachedShapePreviewPath != null) {
    return _cachedShapePreviewPath!;
  }

  final generated = convertStrokeToShapeStroke(rawStroke.copy(), detected);
  final path = generated is ShapeStroke
      ? generated.shapePath
      : generated.highQualityPath;
  _cachedShapePreviewPath = path;
  _cachedShapePreviewDetected = detected;
  _cachedShapePreviewStrokeLen = rawStroke.length;
  _cachedShapePreviewStrokeId = strokeId;
  return path;
}
