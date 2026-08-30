# `lib/data/tools/pen.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

The default stroke options.

 Note that these are different to the default options in [StrokeOptions]
 e.g. [StrokeOptions.defaultSize] for historical reasons
 (i.e. [StrokeOptions.toJson] does not include default values.)

### Block 2

Default options for [AdvancedPen]; full control is in the toolbar.

### Block 3

Pen with all stroke geometry options exposed; configurable via Advanced Pen panel and presets.

## Imports

- `package:flutter/material.dart`
- `package:font_awesome_flutter/font_awesome_flutter.dart`
- `package:saber/data/stroke_geometry/stroke_geometry.dart`
- `package:saber/components/canvas/_stroke.dart`
- `package:saber/data/editor/page.dart`
- `package:saber/data/prefs.dart`
- `package:saber/data/tools/_tool.dart`
- `package:saber/data/tools/highlighter.dart`
- `package:saber/i18n/strings.g.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `Pen`
- `AdvancedPen`
- `onDragStart()`
- `onDragUpdate()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
