# `lib/components/canvas/canvas_gesture_detector.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Called when the pressure of the stylus changes

### Block 2

When true, [onRawPointerMoveForDraw] is called for each [PointerMoveEvent]
 during an active pen stroke (supplements sparse [ScaleUpdateDetails]).

### Block 3

When true (infinite canvas), pan/zoom gestures starting outside the page
 are ignored to prevent view glitches.

### Block 4

When set to true, the next onTransformChanged will skip edge clamping.
 Used when programmatically adjusting transform for infinite canvas expansion
 so the user stays at the same place.

### Block 5

When incremented, signals all scroll physics (canvas and scrollbar) to stop.
 Used so tapping canvas stops scrollbar inertia and vice versa.

### Block 6

Returns the cached top offset for a given page index.
 Complexity: O(1)

### Block 7

Returns the index of the page currently visible at scrollY.
 Complexity: O(log N) using Binary Search on cached offsets.

### Block 8

Cached vertical offsets for each page to enable O(1) lookups and O(log N) searching.

### Block 9

If zooming is locked, this is the zoom level.
 Otherwise, this is null.

### Block 10

Whether single-finger panning is locked.
 Two-finger panning is always enabled.

### Block 11

Whether panning is locked to being horizontal or vertical.
 Otherwise, panning can be done in any (i.e. diagonal) direction.

### Block 12

When the widget is created, we still have an empty coreInfo.
 Wait for note to be loaded before setting the initial transform.

### Block 13

Sets the initial transform so that we're scrolled to the correct page.
 Has no effect if note hasn't yet loaded or if the user has already scrolled.

### Block 14

Corrects the transform if it's out of bounds.
 If the scale is less than 1, centers the pages horizontally.
 Otherwise, prevents the user from scrolling past the edges.

### Block 15

Resets the zoom level to 1.0x

### Block 16

Returns the axis aligned bounding box for the given Quad,
 which might not be axis aligned.
 From https://api.flutter.dev/flutter/widgets/InteractiveViewer/builder.html

### Block 17

Busca Binária para encontrar o índice da primeira página
 potencialmente visível dada a posição Y (viewport top).
 Complexidade: O(log P)

## Imports

- `dart:async`
- `dart:collection`
- `dart:math`
- `dart:ui`
- `package:flutter/gestures.dart`
- `package:flutter/material.dart`
- `package:flutter/services.dart`
- `package:keybinder/keybinder.dart`
- `package:saber/components/canvas/hud/canvas_hud.dart`
- `package:saber/components/canvas/interactive_canvas.dart`
- `package:saber/data/editor/page.dart`
- `package:saber/data/extensions/change_notifier_extensions.dart`
- `package:saber/data/extensions/matrix4_extensions.dart`
- `package:saber/data/prefs.dart`
- `package:saber/pages/editor/editor.dart`
- `package:vector_math/vector_math_64.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `CanvasGestureDetector`
- `CanvasGestureDetectorState`
- `_PagesBuilder`
- `_PagesBuilderState`
- `CanvasTransformCache`
- `zoomIn()`
- `zoomOut()`
- `arrowKeyPan()`
- `initState()`
- `didChangeDependencies()`
- `didUpdateWidget()`
- `setInitialTransform()`
- `onTransformChanged()`
- `resetZoom()`
- `build()`
- `dispose()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
