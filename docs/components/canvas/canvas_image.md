# `lib/components/canvas/canvas_image.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

The path to the note that this image is in.

### Block 2

When non-null, this image is in crop mode: show overlay and drag handles.
 Normalized rect in [0, 1] for left, top, right, bottom.

### Block 3

When notified, all [CanvasImages] will have their [active] property set to false.

### Block 4

The minimum size of the interactive area for the image.

### Block 5

The minimum size of the image itself, inside of the interactive area.

### Block 6

Whether this image can be dragged

### Block 7

Painter for selection frame around images

### Block 8

Rotation handle widget for images

### Block 9

Overlay with 8 crop handles. Dragging updates the normalized crop rect.

## Imports

- `dart:async`
- `dart:math`
- `package:defer_pointer/defer_pointer.dart`
- `package:flutter/material.dart`
- `package:saber/components/canvas/canvas_image_dialog.dart`
- `package:saber/components/canvas/image/editor_image.dart`
- `package:saber/components/theming/adaptive_alert_dialog.dart`
- `package:saber/components/toolbar/plot_animation_metadata.dart`
- `package:saber/data/extensions/change_notifier_extensions.dart`
- `package:saber/data/prefs.dart`
- `package:saber/data/tools/select.dart`
- `package:saber/i18n/strings.g.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `CanvasImage`
- `_CanvasImageState`
- `_CanvasImageResizeHandle`
- `_SelectionFramePainter`
- `_RotationHandle`
- `_CropHandlesOverlay`
- `_CropHandlesOverlayState`
- `initState()`
- `disableActive()`
- `imageListener()`
- `didUpdateWidget()`
- `build()`
- `dispose()`
- `showModal()`
- `paint()`
- `shouldRepaint()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
