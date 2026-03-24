# `lib/components/canvas/_rectangle_stroke.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

A list of points that form the rectangle's perimeter.
 Each side has 24/N points.

### Block 2

Points along the rectangle perimeter for area-erase (split by eraser circle).

### Block 3

Returns a [Path] with four lines for each side of the rectangle.

## Imports

- `package:fixnum/fixnum.dart`
- `package:flutter/material.dart`
- `package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart`
- `package:perfect_freehand/perfect_freehand.dart`
- `package:saber/components/canvas/_stroke.dart`
- `package:saber/data/editor/binary_writer.dart`
- `package:saber/data/editor/page.dart`
- `package:saber/data/extensions/dynamic_extensions.dart`
- `package:saber/data/tools/_tool.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `RectangleStroke`
- `toBinary()`
- `getPath()`
- `addPoint()`
- `popFirstPoint()`
- `optimisePoints()`
- `toSvgPath()`
- `shift()`
- `isStraightLine()`
- `scale()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
