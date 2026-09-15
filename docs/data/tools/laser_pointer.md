# `lib/data/tools/laser_pointer.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Current color from prefs (used when creating new strokes).

### Block 2

Current size from prefs (used when creating new strokes). Capped at 10.

### Block 3

List of timings that correspond to the delay between each point
 in the stroke. The first point has a delay of 0.

 This is used to fade out each point in the stroke one by one.

### Block 4

Stopwatch used to find the time elapsed since the last point.

### Block 5

Whether the user is currently drawing with the laser.
 This is used to prevent strokes fading out until the user
 has finished drawing.

### Block 6

The inner part of the stroke which is thinner and white
 to create a glowing effect.

### Block 7

The outer thicker part of the stroke which is colored with [color].

### Block 8

The outer thicker part of the stroke which is colored with [color].

 Note that LODs are disabled so that the outer path matches the inner path.

## Imports

- `dart:async`
- `package:flutter/material.dart`
- `package:saber/data/stroke_geometry/stroke_geometry.dart`
- `package:saber/components/canvas/_stroke.dart`
- `package:saber/data/editor/page.dart`
- `package:saber/data/extensions/list_extensions.dart`
- `package:saber/data/prefs.dart`
- `package:saber/data/tools/_tool.dart`
- `package:saber/data/tools/pen.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `LaserPointer`
- `LaserStroke`
- `onDragStart()`
- `onDragUpdate()`
- `Function()`
- `shift()`
- `markPolygonNeedsUpdating()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
