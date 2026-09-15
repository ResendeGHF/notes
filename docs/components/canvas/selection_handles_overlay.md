# `lib/components/canvas/selection_handles_overlay.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Overlay of selection box handles (4 corners + 1 rotation) as widgets.
 Uses Container with BoxDecoration.circle so Flutter renders crisp circles
 at display resolution, avoiding the aliasing that occurs when drawing
 circles via Canvas inside scaled CustomPaint.

## Imports

- `dart:math`
- `package:flutter/material.dart`
- `package:saber/data/tools/select.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `SelectionHandlesOverlay`
- `build()`
- `rotate()`
- `snap()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
