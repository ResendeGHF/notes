# `lib/components/canvas/_canvas_background_painter.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Color for the border area (outside pattern when margins > 0). When null, uses [backgroundColor].

### Block 2

The pattern to use for the background. See [CanvasBackgroundPatterns].

### Block 3

The height between each line in the background pattern

### Block 4

Whether to draw the background pattern in a preview mode (more opaque).

### Block 5

Margins inset from page edges (pattern drawn only within this inner rect).

## Imports

- `package:flutter/foundation.dart`
- `package:flutter/material.dart`
- `package:saber/data/editor/canvas_background_pattern.dart`
- `package:saber/data/extensions/color_extensions.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `CanvasBackgroundPainter`
- `PatternElement`
- `paint()`
- `shouldRepaint()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
