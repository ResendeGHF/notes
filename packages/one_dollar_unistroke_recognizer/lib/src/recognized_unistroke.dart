import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:one_dollar_unistroke_recognizer/src/default_unistrokes.dart';
import 'package:one_dollar_unistroke_recognizer/src/unistroke.dart';
import 'package:one_dollar_unistroke_recognizer/src/utils.dart';
import 'package:vector_math/vector_math.dart';

/// A recognized unistroke.
///
/// This is the output of [recognizeUnistroke].
///
/// See also [RecognizedCustomUnistroke], which is the same as this class
/// but with a custom key type.
typedef RecognizedUnistroke = RecognizedCustomUnistroke<DefaultUnistrokeNames>;

/// A recognized unistroke, with a custom key type.
///
/// This is the output of [recognizeCustomUnistroke].
class RecognizedCustomUnistroke<K> {
  /// Creates a [RecognizedCustomUnistroke].
  const RecognizedCustomUnistroke(
    this.name,
    this.score, {
    required this.originalPoints,
    required this.referenceUnistrokes,
  });

  /// The recognized unistroke name.
  final K? name;

  /// The score of the recognized unistroke.
  ///
  /// The score is a value between 0.0 and 1.0, where 1.0 is a perfect match.
  final double score;

  /// The original [inputPoints] parameter that was provided to
  /// [recognizeUnistroke].
  final List<Offset> originalPoints;

  /// The list of reference unistrokes
  /// that were used in [recognizeUnistroke].
  final List<Unistroke<K>> referenceUnistrokes;

  /// Gets the canonical polygon of the recognized unistroke,
  /// and transforms it to the size and position of the original unistroke.
  ///
  /// This function assumes that the recognized unistroke is a polygon.
  /// If it's a circle, use [convertToCircle] instead.
  List<Offset> convertToCanonicalPolygon({
    double Function(double) roundIndicativeAngle =
        RecognizedUnistroke.roundIndicativeAngle,
  }) {
    final unscaledCanonicalPolygon = findUnscaledCanonicalPolygon();

    if (unscaledCanonicalPolygon.isALineExactly) {
      final (start, end) = convertToLine();
      return [start, end];
    }

    // Shapes that should remain perfectly upright (no rotation)
    final isUprightShape = name == DefaultUnistrokeNames.summatory ||
        name == DefaultUnistrokeNames.productory ||
        name == DefaultUnistrokeNames.leftBracket ||
        name == DefaultUnistrokeNames.rightBracket ||
        name == DefaultUnistrokeNames.leftAngleBracket ||
        name == DefaultUnistrokeNames.rightAngleBracket ||
        name == DefaultUnistrokeNames.leftBrace ||
        name == DefaultUnistrokeNames.rightBrace ||
        name == DefaultUnistrokeNames.star ||
        name == DefaultUnistrokeNames.infinity;

    // Use pure unrotated input points for upright shapes
    final List<Offset> sourcePoints = isUprightShape
        ? unscaledCanonicalPolygon.inputPoints
        : unscaledCanonicalPolygon.pointsBeforeResampling;

    final originalBoundingBox = boundingBox(originalPoints);
    final canonicalBoundingBox = boundingBox(sourcePoints);

    final originalCenter = originalBoundingBox.center;
    final canonicalCenter = canonicalBoundingBox.center;

    double angleToApply = 0.0;
    if (!isUprightShape) {
      angleToApply = roundIndicativeAngle(indicativeAngle(originalPoints));
    }

    final transform = Matrix4.identity()
      ..translateByDouble(originalCenter.dx, originalCenter.dy, 0, 1)
      ..scaleByDouble(
        originalBoundingBox.width / canonicalBoundingBox.width,
        originalBoundingBox.height / canonicalBoundingBox.height,
        1,
        1,
      )
      ..rotateZ(angleToApply)
      ..translateByDouble(-canonicalCenter.dx, -canonicalCenter.dy, 0, 1);

    return sourcePoints
        .map((point) => transform.transform3(Vector3(point.dx, point.dy, 0)))
        .map((point) => Offset(point.x, point.y))
        .toList();
  }

  /// Gets the canonical line of the recognized unistroke.
  ///
  /// This function just returns the first and last input points.
  (Offset start, Offset end) convertToLine() {
    return (originalPoints.first, originalPoints.last);
  }

  /// Gets the canonical circle of the recognized unistroke.
  ///
  /// This function assumes that the recognized unistroke is a circle.
  /// If it isn't, it will return the closest approximation.
  ///
  /// Also see [convertToOval]
  (Offset center, double radius) convertToCircle() {
    final rect = boundingBox(originalPoints);
    final radius = (rect.width + rect.height) / 4;
    return (rect.center, radius);
  }

  /// Gets the canonical oval of the recognized unistroke.
  ///
  /// Unlike [convertToCircle], this function does not take the
  /// average of the width and height of the bounding box.
  (Offset center, double radiusX, double radiusY) convertToOval() {
    final rect = boundingBox(originalPoints);
    return (rect.center, rect.width / 2, rect.height / 2);
  }

  /// Gets the bounding box of the recognized unistroke.
  ///
  /// This function is useful for recognized squares/rectangles.
  Rect convertToRect() => boundingBox(originalPoints);

  /// Gets the canonical form of this unistroke.
  @visibleForTesting
  Unistroke findUnscaledCanonicalPolygon() {
    final choices = referenceUnistrokes
        .where((ref) => ref.name == name)
        .toList();
    assert(choices.isNotEmpty, 'No reference unistrokes with name "$name"');
    return choices.firstWhere(
      (ref) => ref.isCanonical,
      orElse: () => choices.first,
    );
  }

  /// Rounds [angle] to the nearest 5 degrees.
  static double roundIndicativeAngle(double angle) {
    const precision = 5 * pi / 180;
    return (angle / precision).roundToDouble() * precision;
  }
}
