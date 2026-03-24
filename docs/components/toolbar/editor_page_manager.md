# `lib/components/toolbar/editor_page_manager.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Fixed height for each card. Enables O(1) extent calculation so scrolling to
 page 530 does not require building items 0..529. Without this, variable-sized
 list would lay out hundreds of CanvasPreviews before showing the panel.

### Block 2

Defers heavy CanvasPreview rendering until after the first frame.
 Panel opens instantly with placeholders; previews load asynchronously.

## Imports

- `dart:math`
- `package:flutter/cupertino.dart`
- `package:flutter/material.dart`
- `package:saber/components/canvas/canvas_gesture_detector.dart`
- `package:saber/components/canvas/canvas_preview.dart`
- `package:saber/components/theming/adaptive_icon.dart`
- `package:saber/components/theming/saber_theme.dart`
- `package:saber/data/editor/editor_core_info.dart`
- `package:saber/i18n/strings.g.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `EditorPageManager`
- `_LazyPagePreview`
- `_LazyPagePreviewState`
- `_EditorPageManagerState`
- `initState()`
- `build()`
- `dispose()`
- `scrollToPage()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
