import 'dart:math';
import 'dart:ui' show Offset, Rect;

import 'package:one_dollar_unistroke_recognizer/src/line_detection.dart';
import 'package:one_dollar_unistroke_recognizer/src/unistroke.dart';

const _circlePoints = 32;
const _square = Rect.fromLTWH(0, 0, 50, 50);
const _rectangle = Rect.fromLTWH(0, 0, 100, 50);

/// The default unistroke templates provided by this package.
final default$1Unistrokes = List<Unistroke<DefaultUnistrokeNames>>.unmodifiable(
  [
    // --- Lines ---
    Unistroke(DefaultUnistrokeNames.line, [
      _square.topLeft,
      _square.topRight,
    ], isCanonical: true),
    Unistroke(DefaultUnistrokeNames.line, [_square.topRight, _square.topLeft]),
    Unistroke(DefaultUnistrokeNames.line, [
      _square.topCenter,
      _square.bottomCenter,
    ]),
    Unistroke(DefaultUnistrokeNames.line, [
      _square.bottomCenter,
      _square.topCenter,
    ]),

    // --- Circles & Ellipses ---
    // CCW from right
    Unistroke(DefaultUnistrokeNames.circle, [
      for (var i = 0; i <= _circlePoints; i++)
        Offset(
          cos(2 * pi * i / _circlePoints),
          sin(2 * pi * i / _circlePoints),
        ),
    ], isCanonical: true),
    // CW from right
    Unistroke(DefaultUnistrokeNames.circle, [
      for (var i = 0; i <= _circlePoints; i++)
        Offset(
          cos(-2 * pi * i / _circlePoints),
          sin(-2 * pi * i / _circlePoints),
        ),
    ]),
    // CCW from top
    Unistroke(DefaultUnistrokeNames.circle, [
      for (var i = 0; i <= _circlePoints; i++)
        Offset(
          sin(2 * pi * i / _circlePoints),
          -cos(2 * pi * i / _circlePoints),
        ),
    ]),
    // CW from top
    Unistroke(DefaultUnistrokeNames.circle, [
      for (var i = 0; i <= _circlePoints; i++)
        Offset(
          -sin(2 * pi * i / _circlePoints),
          -cos(2 * pi * i / _circlePoints),
        ),
    ]),
    // Stretched Ellipses (Absorbs thin ellipses so they don't match rectangles)
    // Use more aspect ratios (1.3, 1.5, 2, 3, 4, 8) to better capture ellipses
    for (final stretch in const [1.3, 1.5, 2, 3, 4, 8]) ...[
      // Wide Ellipse CCW
      Unistroke(DefaultUnistrokeNames.circle, [
        for (var i = 0; i <= _circlePoints; i++)
          Offset(
            cos(2 * pi * i / _circlePoints) * stretch,
            sin(2 * pi * i / _circlePoints),
          ),
      ]),
      // Wide Ellipse CW
      Unistroke(DefaultUnistrokeNames.circle, [
        for (var i = 0; i <= _circlePoints; i++)
          Offset(
            cos(-2 * pi * i / _circlePoints) * stretch,
            sin(-2 * pi * i / _circlePoints),
          ),
      ]),
      // Tall Ellipse CCW
      Unistroke(DefaultUnistrokeNames.circle, [
        for (var i = 0; i <= _circlePoints; i++)
          Offset(
            cos(2 * pi * i / _circlePoints),
            sin(2 * pi * i / _circlePoints) * stretch,
          ),
      ]),
      // Tall Ellipse CW
      Unistroke(DefaultUnistrokeNames.circle, [
        for (var i = 0; i <= _circlePoints; i++)
          Offset(
            cos(-2 * pi * i / _circlePoints),
            sin(-2 * pi * i / _circlePoints) * stretch,
          ),
      ]),
    ],

    // --- Rectangles ---
    for (final rect in const [_square, _rectangle]) ...[
      // TL CW
      Unistroke(DefaultUnistrokeNames.rectangle, [
        rect.topLeft,
        rect.topRight,
        rect.bottomRight,
        rect.bottomLeft,
        rect.topLeft,
      ], isCanonical: rect == _square),
      // TL CCW
      Unistroke(DefaultUnistrokeNames.rectangle, [
        rect.topLeft,
        rect.bottomLeft,
        rect.bottomRight,
        rect.topRight,
        rect.topLeft,
      ]),
      // TR CW
      Unistroke(DefaultUnistrokeNames.rectangle, [
        rect.topRight,
        rect.bottomRight,
        rect.bottomLeft,
        rect.topLeft,
        rect.topRight,
      ]),
      // TR CCW
      Unistroke(DefaultUnistrokeNames.rectangle, [
        rect.topRight,
        rect.topLeft,
        rect.bottomLeft,
        rect.bottomRight,
        rect.topRight,
      ]),
      // BR CW
      Unistroke(DefaultUnistrokeNames.rectangle, [
        rect.bottomRight,
        rect.bottomLeft,
        rect.topLeft,
        rect.topRight,
        rect.bottomRight,
      ]),
      // BR CCW
      Unistroke(DefaultUnistrokeNames.rectangle, [
        rect.bottomRight,
        rect.topRight,
        rect.topLeft,
        rect.bottomLeft,
        rect.bottomRight,
      ]),
      // BL CW
      Unistroke(DefaultUnistrokeNames.rectangle, [
        rect.bottomLeft,
        rect.topLeft,
        rect.topRight,
        rect.bottomRight,
        rect.bottomLeft,
      ]),
      // BL CCW
      Unistroke(DefaultUnistrokeNames.rectangle, [
        rect.bottomLeft,
        rect.bottomRight,
        rect.topRight,
        rect.topLeft,
        rect.bottomLeft,
      ]),
    ],

    // --- Triangles ---
    // Top CW
    Unistroke(DefaultUnistrokeNames.triangle, [
      _square.topCenter,
      _square.bottomRight,
      _square.bottomLeft,
      _square.topCenter,
    ], isCanonical: true),
    // Top CCW
    Unistroke(DefaultUnistrokeNames.triangle, [
      _square.topCenter,
      _square.bottomLeft,
      _square.bottomRight,
      _square.topCenter,
    ]),

    // --- Stars ---
    // Standard
    Unistroke(DefaultUnistrokeNames.star, [
      for (final theta in const [90, 234, 18, 162, 306, 90])
        Offset(cos(theta * pi / 180), -sin(theta * pi / 180)),
    ], isCanonical: true),
    // Reverse Trace
    Unistroke(DefaultUnistrokeNames.star, [
      for (final theta in const [90, 306, 162, 18, 234, 90])
        Offset(cos(theta * pi / 180), -sin(theta * pi / 180)),
    ]),

    // --- Arrows ---
    // L -> R
    Unistroke(DefaultUnistrokeNames.arrow, const [
      Offset(0, 25),
      Offset(40, 25),
      Offset(35, 18),
      Offset(50, 25),
      Offset(35, 32),
      Offset(40, 25),
    ], isCanonical: true),
    // R -> L
    Unistroke(DefaultUnistrokeNames.arrow, const [
      Offset(50, 25),
      Offset(10, 25),
      Offset(15, 18),
      Offset(0, 25),
      Offset(15, 32),
      Offset(10, 25),
    ]),
    // T -> B
    Unistroke(DefaultUnistrokeNames.arrow, const [
      Offset(25, 0),
      Offset(25, 40),
      Offset(18, 35),
      Offset(25, 50),
      Offset(32, 35),
      Offset(25, 40),
    ]),
    // B -> T
    Unistroke(DefaultUnistrokeNames.arrow, const [
      Offset(25, 50),
      Offset(25, 10),
      Offset(18, 15),
      Offset(25, 0),
      Offset(32, 15),
      Offset(25, 10),
    ]),

    // --- Complex Math Symbols ---
    Unistroke(DefaultUnistrokeNames.summatory, const [
      Offset(50, 0),
      Offset(0, 0),
      Offset(25, 25),
      Offset(0, 50),
      Offset(50, 50),
    ], isCanonical: true),
    Unistroke(DefaultUnistrokeNames.summatory, const [
      Offset(50, 50),
      Offset(0, 50),
      Offset(25, 25),
      Offset(0, 0),
      Offset(50, 0),
    ]),
    Unistroke(DefaultUnistrokeNames.productory, const [
      Offset(0, 50),
      Offset(0, 0),
      Offset(50, 0),
      Offset(50, 50),
    ], isCanonical: true),
    Unistroke(DefaultUnistrokeNames.productory, const [
      Offset(50, 50),
      Offset(50, 0),
      Offset(0, 0),
      Offset(0, 50),
    ]),

    // --- Square Brackets [ ] ---
    Unistroke(DefaultUnistrokeNames.leftBracket, const [
      Offset(50, 0),
      Offset(0, 0),
      Offset(0, 50),
      Offset(50, 50),
    ], isCanonical: true),
    Unistroke(DefaultUnistrokeNames.leftBracket, const [
      Offset(50, 50),
      Offset(0, 50),
      Offset(0, 0),
      Offset(50, 0),
    ]),
    Unistroke(DefaultUnistrokeNames.rightBracket, const [
      Offset(0, 0),
      Offset(50, 0),
      Offset(50, 50),
      Offset(0, 50),
    ], isCanonical: true),
    Unistroke(DefaultUnistrokeNames.rightBracket, const [
      Offset(0, 50),
      Offset(50, 50),
      Offset(50, 0),
      Offset(0, 0),
    ]),

    // --- Angle Brackets < > (before braces so templates are evaluated) ---
    Unistroke(DefaultUnistrokeNames.leftAngleBracket, const [
      Offset(50, 0),
      Offset(0, 25),
      Offset(50, 50),
    ], isCanonical: true),
    Unistroke(DefaultUnistrokeNames.leftAngleBracket, const [
      Offset(50, 50),
      Offset(0, 25),
      Offset(50, 0),
    ]),
    Unistroke(DefaultUnistrokeNames.leftAngleBracket, const [
      Offset(40, 0),
      Offset(10, 25),
      Offset(40, 50),
    ]),
    Unistroke(DefaultUnistrokeNames.rightAngleBracket, const [
      Offset(0, 0),
      Offset(50, 25),
      Offset(0, 50),
    ], isCanonical: true),
    Unistroke(DefaultUnistrokeNames.rightAngleBracket, const [
      Offset(0, 50),
      Offset(50, 25),
      Offset(0, 0),
    ]),
    Unistroke(DefaultUnistrokeNames.rightAngleBracket, const [
      Offset(10, 0),
      Offset(40, 25),
      Offset(10, 50),
    ]),

    // --- Curly Braces { } ---
    Unistroke(DefaultUnistrokeNames.leftBrace, const [
      Offset(40, 0),
      Offset(15, 10),
      Offset(15, 20),
      Offset(0, 22),
      Offset(0, 28),
      Offset(15, 30),
      Offset(15, 40),
      Offset(40, 50),
    ], isCanonical: true),
    Unistroke(DefaultUnistrokeNames.leftBrace, const [
      Offset(40, 50),
      Offset(15, 40),
      Offset(15, 30),
      Offset(0, 28),
      Offset(0, 22),
      Offset(15, 20),
      Offset(15, 10),
      Offset(40, 0),
    ]),
    Unistroke(DefaultUnistrokeNames.rightBrace, const [
      Offset(10, 0),
      Offset(35, 10),
      Offset(35, 20),
      Offset(50, 22),
      Offset(50, 28),
      Offset(35, 30),
      Offset(35, 40),
      Offset(10, 50),
    ], isCanonical: true),
    Unistroke(DefaultUnistrokeNames.rightBrace, const [
      Offset(10, 50),
      Offset(35, 40),
      Offset(35, 30),
      Offset(50, 28),
      Offset(50, 22),
      Offset(35, 20),
      Offset(35, 10),
      Offset(10, 0),
    ]),

    // --- Infinity ∞ ---
    Unistroke(DefaultUnistrokeNames.infinity, const [
      Offset(25, 25),
      Offset(35, 15),
      Offset(45, 25),
      Offset(35, 35),
      Offset(25, 25),
      Offset(15, 15),
      Offset(5, 25),
      Offset(15, 35),
      Offset(25, 25),
    ], isCanonical: true),
    Unistroke(DefaultUnistrokeNames.infinity, const [
      Offset(15, 15),
      Offset(5, 25),
      Offset(15, 35),
      Offset(25, 25),
      Offset(35, 15),
      Offset(45, 25),
      Offset(35, 35),
      Offset(25, 25),
      Offset(15, 15),
    ]),
    Unistroke(DefaultUnistrokeNames.infinity, const [
      Offset(25, 25),
      Offset(15, 15),
      Offset(5, 25),
      Offset(15, 35),
      Offset(25, 25),
      Offset(35, 15),
      Offset(45, 25),
      Offset(35, 35),
      Offset(25, 25),
    ]),
  ],
);

/// The enum of the names of the default unistrokes.
// If you add a new unistroke name, you should also add it to the README.
enum DefaultUnistrokeNames {
  /// A line.
  ///
  /// Note that the line unistroke in default$1Unistrokes is just for
  /// completeness,
  /// but we use a different algorithm to recognize straight lines:
  /// see [meanAbsoluteError].
  line,

  /// A circle
  circle,

  /// A rectangle
  rectangle,

  /// A triangle
  triangle,

  /// A star
  star,

  /// An arrow (single head)
  arrow,

  // Complex Math Symbols
  /// @deprecated No template - nabla-shaped strokes match triangle instead.
  nabla,
  summatory,
  productory,
  leftBracket,
  rightBracket,
  leftAngleBracket,
  rightAngleBracket,
  leftBrace,
  rightBrace,
  infinity,
}
