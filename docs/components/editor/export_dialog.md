# `lib/components/editor/export_dialog.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

JPEG export resolution as pixel ratio (DPI/72).

### Block 2

When running export in background, used for PDF generation and snackbar.

## Imports

- `dart:typed_data`
- `dart:ui`
- `package:archive/archive.dart`
- `package:flutter/material.dart`
- `package:saber/data/editor/editor_core_info.dart`
- `package:saber/data/editor/editor_exporter.dart`
- `package:saber/data/editor/link_export_expander.dart`
- `package:saber/data/file_manager/file_manager.dart`
- `package:saber/data/prefs.dart`
- `package:saber/i18n/strings.g.dart`
- `package:wakelock_plus/wakelock_plus.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `ExportFormat`
- `ExportPageRange`
- `ExportResolution`
- `ExportResolutionExt`
- `ExportDialog`
- `_ExportDialogState`
- `initState()`
- `dispose()`
- `build()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
