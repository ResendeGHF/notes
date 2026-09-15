# `lib/data/editor/editor_exporter.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

The primary color used in exports.
 This is independent to the user's color theme,
 so that the export will look the same when
 exported from different devices.
 See also [secondaryColor].

### Block 2

The secondary color used in exports.
 See also [primaryColor].

### Block 3

Most* strokes can be drawn to the PDF canvas as vector graphics.
 This function returns true if [stroke] is one of those strokes.

 Strokes that can't be drawn as vector graphics include:
 - Highlighter strokes, because PDFs don't support transparency
 - (Pencil tool was removed)

### Block 4

Returns a screenshot of the page at [pageIndex] in [coreInfo].

 When [fullPage] is false: screenshots do not include most* strokes
 because they're added separately to the PDF as vector graphics.
 See [_shouldRasterizeStroke] for more details.

 When [fullPage] is true: captures the complete page including backgrounds,
 images, PDF pages, and all strokes. Used for PDF export when pages have
 complex content (e.g. Share Links with appended PDF pages).

## Imports

- `dart:typed_data`
- `dart:ui`
- `package:flutter/material.dart`
- `package:flutter_localizations/flutter_localizations.dart`
- `package:path_drawing/path_drawing.dart`
- `package:pdf/pdf.dart`
- `package:pdf/widgets.dart`
- `package:saber/components/canvas/_circle_stroke.dart`
- `package:saber/components/canvas/_rectangle_stroke.dart`
- `package:saber/components/canvas/_shape_stroke.dart`
- `package:saber/components/canvas/_stroke.dart`
- `package:saber/components/canvas/inner_canvas.dart`
- `package:saber/data/editor/editor_core_info.dart`
- `package:saber/data/editor/link_export_expander.dart`
- `package:saber/data/extensions/color_extensions.dart`
- `package:screenshot/screenshot.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `EditorExporter`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
