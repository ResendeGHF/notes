# `lib/components/editor/note_properties_dialog.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Dialog content that shows coreInfo metadata immediately and loads file size
 and base path asynchronously (avoids blocking when note is saving/loading).

### Block 2

PDF loading mode row for vault notes. Shown only when vault is enabled.

### Block 3

Local state for immediate visual feedback on tap (optimistic update).

## Imports

- `dart:ui`
- `package:flutter/material.dart`
- `package:intl/intl.dart`
- `package:saber/data/editor/editor_core_info.dart`
- `package:saber/data/file_manager/file_manager.dart`
- `package:saber/data/prefs.dart`
- `package:saber/pages/editor/editor.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `_NotePropertiesDialogContent`
- `_NotePropertiesDialogContentState`
- `_PropRow`
- `_PdfLoadModeRow`
- `_PdfLoadModeRowState`
- `showPropertiesForFile()`
- `showNotePropertiesDialog()`
- `initState()`
- `build()`
- `dispose()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
