# `lib/data/editor/page.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Max user-addable layers (base + 3 = 4 total).

### Block 2

Page orientation. Landscape = same dimensions as portrait but width and height swapped (90°).

### Block 3

Default size for this orientation (portrait: 1000×1400, landscape: 1400×1000).

### Block 4

Stable page id: links and other references use this so they stay with the
 page when pages are reordered or deleted. Assigned on creation or during
 load migration; never changes for the lifetime of the page.

### Block 5

Constrói o índice espacial do zero. Deve ser chamado ao carregar a página.

### Block 6

Border color (area outside pattern when margins > 0). When null, uses [backgroundColor].

### Block 7

Base size (from constructor or load). For infinite canvas, [size] may be
 overridden by [_sizeOverride] when the canvas has been expanded/shrunk.

### Block 8

When non-null, overrides [size] for infinite canvas (supports grow/shrink).

### Block 9

Draw order: indices into _layers. First = bottom, last = top.

### Block 10

Index of the layer currently being drawn/edited (0 to layerCount-1).

### Block 11

Active layer's strokes (for drawing, select, add).

### Block 12

Active layer's images (for placement, select).

### Block 13

All strokes in draw order (bottom to top). O(1) per layer.

### Block 14

All images in draw order.

### Block 15

Add a user layer. Returns true if added (max 4).

### Block 16

Remove layer at index. Content is moved to base layer. Cannot remove base (0).

### Block 17

Move layer up (higher z-order). index into _layerOrder.

### Block 18

Move layer down (lower z-order).

### Block 19

Indices of layers in draw order (first=bottom, last=top).

### Block 20

Replaces layers and order (used when loading from binary).

### Block 21

Remove stroke from whichever layer contains it (for undo).

### Block 22

Remove image from whichever layer contains it.

### Block 23

The height of the canvas cropped to the content.

### Block 24

The maximum y value of any stroke, image, or text.

### Block 25

The uncropped height of the page.
 In lots of cases, this is [Editor.defaultHeight].

### Block 26

The height of the canvas (cropped),
 adjusted to be between 10% and 100% of the full height.

### Block 27

Bounding box of all content (strokes, images, text). Used for infinite
 canvas expansion/shrink and whitespace trimming.

### Block 28

Ensures size is at least [minSize]. Used for infinite canvas (never smaller than 16:9).

### Block 29

For infinite canvas: resize and shift content when expanding left/top.
 [newSize] is the desired page size. [contentOffset] shifts all strokes and
 images (used when expanding left/top to keep content in place).

### Block 30

For infinite canvas: trim unused whitespace before save.
 Keeps a [buffer] margin around content. Shifts content if trimming left/top.
 Never shrinks below [_baseSize] (initial 16:9 for infinite notes).

### Block 31

Inserts a stroke into the active layer, keeping strokes sorted by pen type and color.

### Block 32

Sorts the active layer's strokes by pen type and color.

### Block 33

Triggers a redraw of the strokes. If you need to redraw images,
 call [setState] instead.

## Imports

- `dart:async`
- `dart:convert`
- `dart:math`
- `dart:typed_data`
- `package:flutter/material.dart`
- `package:flutter_quill/flutter_quill.dart`
- `package:saber/components/canvas/_asset_cache.dart`
- `package:saber/components/canvas/_stroke.dart`
- `package:saber/components/canvas/image/editor_image.dart`
- `package:saber/components/canvas/inner_canvas.dart`
- `package:saber/data/editor/binary_writer.dart`
- `package:saber/data/editor/canvas_background_pattern.dart`
- `package:saber/data/editor/note_layer.dart`
- `package:saber/data/tools/highlighter.dart`
- `package:saber/data/tools/laser_pointer.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `CanvasKey`
- `PageOrientation`
- `PageOrientationExtension`
- `HasSize`
- `EditorPage`
- `QuillStruct`
- `buildSpatialIndex()`
- `addLayer()`
- `removeLayer()`
- `moveLayerUp()`
- `moveLayerDown()`
- `replaceLayersFromBinary()`
- `removeStrokeFromAnyLayer()`
- `removeImageFromAnyLayer()`
- `previewHeight()`
- `getContentBounds()`
- `ensureMinimumSize()`
- `resizeInfiniteCanvas()`
- `trimWhitespace()`
- `toBinary()`
- `insertStroke()`
- `sortStrokes()`
- `redrawStrokes()`
- `dispose()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
