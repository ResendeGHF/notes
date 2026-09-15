# `lib/data/tools/select.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

The minimum ratio of points inside a stroke or image
 for it to be selected.

### Block 2

Adds the indices of any [strokes] that are inside the selection area
 to [selectResult.indices].

### Block 3

The page index when the items were selected.

### Block 4

Get the bounding box of the selection

### Block 5

Check if a point is inside the selection (including rotation)

### Block 6

Get the centroid of all points in the selection

## Imports

- `dart:math`
- `package:flutter/material.dart`
- `package:saber/components/canvas/_stroke.dart`
- `package:saber/components/canvas/image/editor_image.dart`
- `package:saber/data/tools/_tool.dart`
- `package:vector_math/vector_math_64.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `Select`
- `SelectResult`
- `SelectionTransformPreview`
- `SelectionGuideLine`
- `unselect()`
- `onDragStart()`
- `onDragUpdate()`
- `onDragEnd()`
- `clearAlignmentGuides()`
- `getBounds()`
- `unrotateAroundSelection()`
- `contains()`
- `getCentroid()`
- `transformPoint()`
- `transformRect()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
