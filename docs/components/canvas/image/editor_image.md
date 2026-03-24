# `lib/components/canvas/image/editor_image.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

The data for an image in the editor.
 This is listenable for changes to the image's position ([dstRect]).

### Block 2

id for this image, unique within a note

### Block 3

The image's file extension, e.g. [".jpg"].
 This is used when "downloading" the image to the user's photo gallery.

### Block 4

Defines the aspect ratio of the image.

### Block 5

The size of the page this image is on,
 used to make sure the image isn't too big.

### Block 6

If the image is new, it will be [active] (draggable) when loaded

### Block 7

Whether this image is inverted if Prefs.editorAutoInvert.value

### Block 8

The BoxFit used if this is a page's background image

### Block 9

Rotation angle in degrees

### Block 10

Whether this image is locked (cannot be moved, rotated, or scaled)

### Block 11

Whether the point is inside the image's bounding box

### Block 12

Rotate the image around a center point by the given angle in radians

### Block 13

Uniformly scale the image around [center] by [factor].

### Block 14

Call this from subclass to write shared fields.

### Block 15

Images are loaded out after 5 seconds of not being visible.

 Set this to true to load out immediately.

 This is useful for tests that can't have pending timers.

### Block 16

Called when the image becomes visible,
 and often involves loading the image from disk.

 The [firstLoad] method is called the first time this is called.
 Subsequent calls will wait for the first load to complete.

 See also:
 * [loadOut], which unloads the image from memory
 * [precache], which adds the image to Flutter's image cache
 * [loadedIn], which is true after [loadIn] and false after [loadOut]

### Block 17

Free up resources when the image is no longer visible.

 See also:
 * [loadIn], which will be called again when the image is visible again.
 * [loadedIn], which is true after [loadIn] and false after [loadOut]

### Block 18

Adds the image to Flutter's image cache.

### Block 19

Resizes [before] to fit inside [max] while maintaining aspect ratio

## Imports

- `dart:async`
- `dart:io`
- `dart:isolate`
- `dart:math`
- `dart:ui`
- `package:fast_image_resizer/fast_image_resizer.dart`
- `package:flutter/foundation.dart`
- `package:flutter/material.dart`
- `package:flutter_svg/flutter_svg.dart`
- `package:logging/logging.dart`
- `package:meta/meta.dart`
- `package:pdfrx/pdfrx.dart`
- `package:saber/components/canvas/_asset_cache.dart`
- `package:saber/components/canvas/canvas_image.dart`
- `package:saber/components/canvas/invert_widget.dart`
- `package:saber/components/editor/pdf_link_detector.dart`
- `package:saber/data/editor/binary_writer.dart`
- `package:saber/data/file_manager/file_manager.dart`
- `package:saber/data/prefs.dart`
- `package:saber/i18n/strings.g.dart`
- `package:saber/pages/editor/editor.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `Function()`
- `contains()`
- `rotate()`
- `scale()`
- `writeBinary()`
- `toBinary()`
- `firstLoad()`
- `loadIn()`
- `loadOut()`
- `precache()`
- `buildImageWidget()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
