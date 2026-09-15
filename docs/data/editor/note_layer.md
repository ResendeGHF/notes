# `lib/data/editor/note_layer.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

A single drawing layer on a page. Holds strokes and images.
 Each layer is independent - editing one does not touch others (O(1) for non-active layers).

## Imports

- `package:flutter/material.dart`
- `package:saber/components/canvas/_stroke.dart`
- `package:saber/components/canvas/image/editor_image.dart`
- `package:saber/data/tools/highlighter.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `NoteLayer`
- `insertStroke()`
- `removeStroke()`
- `addImage()`
- `removeImage()`
- `redrawStrokes()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
