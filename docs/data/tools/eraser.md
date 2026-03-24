# `lib/data/tools/eraser.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Area mode only: [apply] stopped early to cap CPU; caller should schedule another slice.

### Block 2

Limits for worst-case strokes so area splitting stays responsive.

### Block 3

Sets prevent accumulation of intermediary split strokes during a long drag
 (OOM fix: strokes created and re-erased in same drag are purged, not listed).

### Block 4

Strokes purged during this drag (fragments fully erased before drag end).
 Disposed by editor after recording; never stored in history.

### Block 5

Cut slightly outside hit radius (Zeno fix). Kept small so area eraser only removes what's under the cursor.

### Block 6

Butterfly-like spacing: only apply again after moving enough in area mode.
 This keeps work proportional to pointer travel instead of event rate.

### Block 7

Area mode: max milliseconds per call; when exceeded, returns [EraserResult.areaWorkRemaining].
 Null = process all candidates in one call (used to finish a gesture or flush).

### Block 8

Strokes already added to [removed] this apply; skip them in area loop to avoid re-processing fragments.

### Block 9

If the stroke was created during this drag, remove it from _added and
 schedule for disposal (purged fragment). Otherwise add to _erased for history.

### Block 10

Fast hit-test: bounds overlap then isHitByCircle. No full segment fallback
 to keep work bounded and avoid UI freeze.

### Block 11

Clears internal state so eraser works correctly after undo/redo (no stale stroke references).

## Imports

- `dart:math`
- `dart:typed_data`
- `dart:ui`
- `package:perfect_freehand/perfect_freehand.dart`
- `package:saber/components/canvas/_circle_stroke.dart`
- `package:saber/components/canvas/_rectangle_stroke.dart`
- `package:saber/components/canvas/_shape_stroke.dart`
- `package:saber/components/canvas/_stroke.dart`
- `package:saber/data/tools/_tool.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `EraserMode`
- `EraserResult`
- `_EraserLimits`
- `Eraser`
- `_IndexRange`
- `_AreaSegment`
- `_AreaSession`
- `shouldApplyAt()`
- `overBudget()`
- `clearState()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
