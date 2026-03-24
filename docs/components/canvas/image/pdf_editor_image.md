# `lib/components/canvas/image/pdf_editor_image.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

index of asset assigned to this pdf file

### Block 2

If the pdf needs to be loaded from disk, this is the File
 that the pdf will be loaded from.

### Block 3

Callback called when user taps on the PDF.
 Parameters: (localPosition in widget coordinates, pdfDocument, pdfPage index, pdfFile)
 Note: pdfFile parameter is kept for compatibility but not used anymore (pdfrx handles links natively)

### Block 4

Minimal placeholder while PDF loads; progress is shown in the editor app bar.

## Imports

_None (part file or exports only)._

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `PdfEditorImage`
- `_PdfLoadingPlaceholder`
- `_PdfPageRenderer`
- `_PdfPageRendererState`
- `_LinkHighlightPainter`
- `writeBinary()`
- `firstLoad()`
- `loadIn()`
- `loadOut()`
- `precache()`
- `buildImageWidget()`
- `build()`
- `initState()`
- `didUpdateWidget()`
- `paint()`
- `shouldRepaint()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
