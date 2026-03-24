# `lib/data/tools/shape_recognition.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Handles the "Hold to recognize" delay logic for any pen.

### Block 2

Call this on every drag update. It resets the timer.
 If the pointer is held still for the duration in settings, [onRecognize] triggers.

### Block 3

Call this on pointer release/drag end to cancel the recognition hold.

### Block 4

Converts a parametric [ShapeStroke] into a regular [Stroke] with sampled
 points, as if the shape were drawn by the current pen. Used so recognition
 produces hand-drawn-style strokes instead of crisp parametric shapes.

### Block 5

Converts a raw stroke to a regular stroke with a recognized shape's outline
 when the stroke is recognized as a shape. Used when "Recognize Shapes" is
 enabled and the user holds briefly at the end of a stroke (with any pen).
 All recognized shapes (circle, rectangle, triangle, etc.) are converted
 into real strokes (as if drawn by the current pen), not parametric shapes.

 Returns [rawStroke] unchanged if conversion is not applicable or recognition
 score is below threshold.

### Block 6

Builds an equilateral triangle (up or down) with size and placement from the drawing.

### Block 7

Builds a real stroke for math symbols (summatory, productory, brackets, braces).

### Block 8

Angle bracket left/right: when drawn bottom-to-top, geometry is inverted.

### Block 9

Resolves left vs right for angle brackets, accounting for stroke direction.

### Block 10

Disambiguates brace vs angle bracket, productory/summatory vs bracket,
 and fixes left/right swaps for brackets and braces.

### Block 11

Builds a real stroke for a 5-point star from recognition.

### Block 12

Computes oriented ellipse parameters. Uses PCA for major/minor dimensions
 so rotated ellipses stay elliptical (not misclassified as circles); uses
 visible stroke polygon for placement.

## Imports

- `dart:async`
- `dart:math`
- `package:flutter/material.dart`
- `package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart`
- `package:perfect_freehand/perfect_freehand.dart`
- `package:saber/components/canvas/_shape_stroke.dart`
- `package:saber/components/canvas/_stroke.dart`
- `package:saber/data/prefs.dart`
- `package:saber/data/tools/_tool.dart`
- `package:saber/data/tools/shape_tool.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `ShapeRecognitionTimer`
- `update()`
- `cancel()`
- `buildDetectedShapePreviewPath()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
