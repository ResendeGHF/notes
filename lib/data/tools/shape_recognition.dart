// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart'
    show
        computeRoundness,
        DefaultUnistrokeNames,
        fitLineAndProjectExtent,
        isAngleBracketPreferred,
        isBracePreferred,
        isBracketPreferred,
        RecognizedUnistroke;
import 'package:perfect_freehand/perfect_freehand.dart' show StrokeEndOptions;
import 'package:saber/components/canvas/_shape_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
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

Stroke _shapeStrokeToRealStroke(ShapeStroke shapeStroke, Stroke rawStroke) {
  final opts = rawStroke.options;
  final stroke = Stroke(
    color: rawStroke.color,
    pressureEnabled: rawStroke.pressureEnabled,
    options: opts.copyWith(
      isComplete: true,
      start: StrokeEndOptions.start(
        taperEnabled: false,
        customTaper: opts.start.customTaper,
        cap: opts.start.cap,
        easing: opts.start.easing,
      ),
      end: StrokeEndOptions.end(
        taperEnabled: false,
        customTaper: opts.end.customTaper,
        cap: opts.end.cap,
        easing: opts.end.easing,
      ),
    ),
    pageIndex: rawStroke.pageIndex,
    page: rawStroke.page,
    toolId: rawStroke.toolId,
  );
  stroke.replacePointsFromEraser(shapeStroke.pointsForEraser);
  stroke.rotationDeg = shapeStroke.rotationDeg;
  return stroke;
}

Stroke convertStrokeToShapeStroke(
  Stroke rawStroke,
  RecognizedUnistroke detected,
) {
  final List<Offset> rawPoints = rawStroke.highQualityPolygon;

  if (rawPoints.length < 2) return rawStroke;

  final String name = detected.name?.toString().split('.').last ?? '';

  switch (detected.name) {
    case DefaultUnistrokeNames.line:
      final s = rawStroke.copy();
      final orig = detected.originalPoints;
      if (orig.length >= 2) {
        final len = (orig.last - orig.first).distance;
        if (len >= 2.0) {
          s.convertToLine();
          if (rawStroke.toolId == ToolId.highlighter) s.densifyStraightLine();
        }
      }
      return s;

    case DefaultUnistrokeNames.arrow:
      final sArrow = rawStroke.copy();
      final origArrow = detected.originalPoints;
      if (origArrow.length >= 2) {
        final len = (origArrow.last - origArrow.first).distance;
        if (len >= 2.0) {
          sArrow.convertToLine();
          if (rawStroke.toolId == ToolId.highlighter) sArrow.densifyStraightLine();
        }
      }
      return sArrow;

    case DefaultUnistrokeNames.rectangle:
      final orig = detected.originalPoints;
      final rect = detected.convertToRect();
      final aspect = rect.height > 0 ? rect.width / rect.height : 1.0;

      final extremeAspect = aspect > 5.0 || aspect < 0.2;
      final roundness = orig.length >= 4 ? computeRoundness(orig) : 0.5;
      final isEllipse = extremeAspect
          ? (roundness > 0.25)
          : (roundness > 0.55);
      if (orig.length >= 4 && isEllipse && rect.width > 0 && rect.height > 0) {
        final oriented = _computeOrientedEllipse(rawStroke, detected, orig);
        final isCircle = (oriented.bounds.width - oriented.bounds.height).abs() <=
            math.max(oriented.bounds.width, oriented.bounds.height) * 0.1;
        return _shapeStrokeToRealStroke(
          ShapeStroke(
            color: rawStroke.color,
            fillColor: rawStroke.color.withValues(alpha: 0.2),
            fill: false,
            pressureEnabled: false,
            options: rawStroke.options.copyWith(simulatePressure: false),
            pageIndex: rawStroke.pageIndex,
            page: rawStroke.page,
            toolId: rawStroke.toolId,
            config: ShapeConfig(
              kind: isCircle ? ShapeKind.circle : ShapeKind.ellipse,
              bounds: oriented.bounds,
              start: oriented.bounds.topLeft,
              end: oriented.bounds.bottomRight,
              rotationDeg: oriented.rotationDeg,
            ),
          ),
          rawStroke,
        );
      }
      final aspectRect = rect.height == 0 ? 1.0 : rect.width / rect.height;
      final rectBounds = (aspectRect > 0.9 && aspectRect < 1.1)
          ? Rect.fromCenter(
              center: rect.center,
              width: math.max(rect.width, rect.height),
              height: math.max(rect.width, rect.height),
            )
          : rect;
      return _shapeStrokeToRealStroke(
        ShapeStroke(
          color: rawStroke.color,
          fillColor: rawStroke.color.withValues(alpha: 0.2),
          fill: false,
          pressureEnabled: false,
          options: rawStroke.options.copyWith(simulatePressure: false),
          pageIndex: rawStroke.pageIndex,
          page: rawStroke.page,
          toolId: rawStroke.toolId,
          config: ShapeConfig(
            kind: ShapeKind.rectangle,
            bounds: rectBounds,
            start: rectBounds.topLeft,
            end: rectBounds.bottomRight,
          ),
        ),
        rawStroke,
      );

    case DefaultUnistrokeNames.circle:
      final orig = detected.originalPoints;
      final rect = detected.convertToRect();

      if (orig.length >= 4 && computeRoundness(orig) <= 0.55) {
        final aspect = rect.height > 0 ? rect.width / rect.height : 1.0;
        if (aspect > 2.0 || aspect < 0.5) {
          return _shapeStrokeToRealStroke(
            ShapeStroke(
              color: rawStroke.color,
              fillColor: rawStroke.color.withValues(alpha: 0.2),
              fill: false,
              pressureEnabled: false,
              options: rawStroke.options.copyWith(simulatePressure: false),
              pageIndex: rawStroke.pageIndex,
              page: rawStroke.page,
              toolId: rawStroke.toolId,
              config: ShapeConfig(
                kind: ShapeKind.rectangle,
                bounds: rect,
                start: rect.topLeft,
                end: rect.bottomRight,
              ),
            ),
            rawStroke,
          );
        }
      }
        final oriented = _computeOrientedEllipse(rawStroke, detected, orig);
      final isCircle = (oriented.bounds.width - oriented.bounds.height).abs() <=
          math.max(oriented.bounds.width, oriented.bounds.height) * 0.1;
      return _shapeStrokeToRealStroke(
        ShapeStroke(
          color: rawStroke.color,
          fillColor: rawStroke.color.withValues(alpha: 0.2),
          fill: false,
          pressureEnabled: false,
          options: rawStroke.options.copyWith(simulatePressure: false),
          pageIndex: rawStroke.pageIndex,
          page: rawStroke.page,
          toolId: rawStroke.toolId,
          config: ShapeConfig(
            kind: isCircle ? ShapeKind.circle : ShapeKind.ellipse,
            bounds: oriented.bounds,
            start: oriented.bounds.topLeft,
            end: oriented.bounds.bottomRight,
            rotationDeg: oriented.rotationDeg,
          ),
        ),
        rawStroke,
      );

    case DefaultUnistrokeNames.triangle:
      if (detected.originalPoints.length >= 3 &&
          isAngleBracketPreferred(detected.originalPoints)) {
        final pts = detected.originalPoints;
        final angleName = _angleBracketLeftRight(pts);
        return _shapeStrokeFromSymbol(rawStroke, detected, angleName);
      }
      return _shapeStrokeFromTriangle(rawStroke, detected);
    case DefaultUnistrokeNames.star:
      return _shapeStrokeFromStar(rawStroke, detected);
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
        return _shapeStrokeFromSymbol(rawStroke, detected, _disambiguateSymbolName(name, detected.originalPoints));
      }

      return rawStroke;
  }
}

Stroke _shapeStrokeFromTriangle(Stroke rawStroke, RecognizedUnistroke detected) {
  final bounds = _boundsOf(detected.originalPoints);
  if (bounds.width <= 0 || bounds.height <= 0) return rawStroke;
  final upward = _trianglePointsUpward(detected.originalPoints, bounds);

  final kind = upward ? ShapeKind.triangleIsosceles : ShapeKind.nabla;
  return _shapeStrokeToRealStroke(
    ShapeStroke(
      color: rawStroke.color,
      fillColor: rawStroke.color.withValues(alpha: 0.2),
      fill: false,
      pressureEnabled: false,
      options: rawStroke.options.copyWith(simulatePressure: false),
      pageIndex: rawStroke.pageIndex,
      page: rawStroke.page,
      toolId: rawStroke.toolId,
      config: ShapeConfig(
        kind: kind,
        bounds: bounds,
        start: bounds.topLeft,
        end: bounds.bottomRight,
        data: kind == ShapeKind.triangleIsosceles
            ? {'equilateral': true, 'upward': true}
            : {},
      ),
    ),
    rawStroke,
  );
}

bool _trianglePointsUpward(List<Offset> points, Rect bounds) {
  if (points.length < 3) return true;
  double sumY = 0;
  for (final p in points) sumY += p.dy;
  final centroidY = sumY / points.length;
  final centerY = bounds.center.dy;
  return centroidY > centerY;
}

Stroke _shapeStrokeFromSymbol(
  Stroke rawStroke,
  RecognizedUnistroke detected,
  String name,
) {
  final canonical = detected.convertToCanonicalPolygon();
  if (canonical.length < 2) return rawStroke;
  final bounds = _boundsOf(canonical);
  final kind = _symbolNameToShapeKind(name);
  if (kind == null) return rawStroke;
  return _shapeStrokeToRealStroke(
    ShapeStroke(
      color: rawStroke.color,
      fillColor: rawStroke.color.withValues(alpha: 0.2),
      fill: false,
      pressureEnabled: false,
      options: rawStroke.options.copyWith(simulatePressure: false),
      pageIndex: rawStroke.pageIndex,
      page: rawStroke.page,
      toolId: rawStroke.toolId,
      config: ShapeConfig(
        kind: kind,
        bounds: bounds,
        start: bounds.topLeft,
        end: bounds.bottomRight,
      ),
    ),
    rawStroke,
  );
}

bool _angleBracketDrawnBottomToTop(List<Offset> points) {
  if (points.length < 2) return false;
  return points.first.dy > points.last.dy;
}

String _angleBracketLeftRight(List<Offset> points) {
  final box = _boundsOf(points);
  final cx = box.center.dx;
  final leftCount = points.where((p) => p.dx < cx).length;
  final moreOnLeft = leftCount >= points.length / 2;
  final drawnBottomToTop = _angleBracketDrawnBottomToTop(points);

  final isLeft = drawnBottomToTop ? !moreOnLeft : moreOnLeft;
  return isLeft ? 'leftAngleBracket' : 'rightAngleBracket';
}

String _disambiguateSymbolName(String name, List<Offset> points) {
  final box = _boundsOf(points);
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

    if (rightCount > leftCount) {
      return 'rightBrace';
    }
    if (leftCount > rightCount) {
      return 'leftBrace';
    }
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

Stroke _shapeStrokeFromStar(Stroke rawStroke, RecognizedUnistroke detected) {
  final canonical = detected.convertToCanonicalPolygon();
  if (canonical.length < 2) return rawStroke;
  final bounds = _boundsOf(canonical);
  return _shapeStrokeToRealStroke(
    ShapeStroke(
      color: rawStroke.color,
      fillColor: rawStroke.color.withValues(alpha: 0.2),
      fill: false,
      pressureEnabled: false,
      options: rawStroke.options.copyWith(simulatePressure: false),
      pageIndex: rawStroke.pageIndex,
      page: rawStroke.page,
      toolId: rawStroke.toolId,
      config: ShapeConfig(
        kind: ShapeKind.star,
        bounds: bounds,
        start: bounds.topLeft,
        end: bounds.bottomRight,
      ),
    ),
    rawStroke,
  );
}

Rect _boundsOf(List<Offset> points) {
  if (points.isEmpty) return Rect.zero;
  final xs = points.map((p) => p.dx);
  final ys = points.map((p) => p.dy);
  return Rect.fromPoints(
    Offset(xs.reduce(math.min), ys.reduce(math.min)),
    Offset(xs.reduce(math.max), ys.reduce(math.max)),
  );
}

({Rect bounds, double rotationDeg}) _computeOrientedEllipse(
  Stroke rawStroke,
  RecognizedUnistroke detected,
  List<Offset> orig,
) {
  final fitPoints = rawStroke.highQualityPolygon.length >= 3
      ? rawStroke.highQualityPolygon
      : orig;
  final box = fitPoints.isEmpty ? Rect.zero : _boundsOf(fitPoints);
  final center = box.center;
  if (fitPoints.length < 3) {
    final rx = box.width > 0 ? box.width / 2 : 1.0;
    final ry = box.height > 0 ? box.height / 2 : 1.0;
    return (
      bounds: Rect.fromCenter(center: center, width: rx * 2, height: ry * 2),
      rotationDeg: 0,
    );
  }
  final (lineStart, lineEnd) = fitLineAndProjectExtent(fitPoints);
  final dir = lineEnd - lineStart;
  final len = dir.distance;
  if (len < 1e-10) {
    final rx = box.width > 0 ? box.width / 2 : 1.0;
    final ry = box.height > 0 ? box.height / 2 : 1.0;
    return (
      bounds: Rect.fromCenter(center: center, width: rx * 2, height: ry * 2),
      rotationDeg: 0,
    );
  }
  final vx = dir.dx / len;
  final vy = dir.dy / len;
  final perpX = -vy;
  final perpY = vx;
  var tMin = double.infinity, tMax = -double.infinity;
  var sMin = double.infinity, sMax = -double.infinity;
  for (final p in fitPoints) {
    final dx = p.dx - center.dx, dy = p.dy - center.dy;
    final t = dx * vx + dy * vy;
    final s = dx * perpX + dy * perpY;
    if (t < tMin) tMin = t;
    if (t > tMax) tMax = t;
    if (s < sMin) sMin = s;
    if (s > sMax) sMax = s;
  }
  final majorHalf = math.max((tMax - tMin) / 2, 2.0);
  final minorHalf = math.max((sMax - sMin) / 2, 2.0);
  final (w, h) = majorHalf >= minorHalf
      ? (majorHalf * 2, minorHalf * 2)
      : (minorHalf * 2, majorHalf * 2);
  final bounds = Rect.fromCenter(center: center, width: w, height: h);
  final rotationDeg = majorHalf >= minorHalf
      ? math.atan2(vy, vx) * 180 / math.pi
      : math.atan2(perpY, perpX) * 180 / math.pi;
  return (bounds: bounds, rotationDeg: rotationDeg);
}

Path buildDetectedShapePreviewPath(Stroke rawStroke, RecognizedUnistroke detected) {
  final generated = convertStrokeToShapeStroke(rawStroke.copy(), detected);
  return generated.highQualityPath;
}
