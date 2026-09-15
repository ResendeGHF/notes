# `lib/components/home/move_note_button.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

The original file names of the notes.

### Block 2

The original parent folders of the notes,
 including the trailing slash.

### Block 3

Whether each file uses [Editor.extensionOldJson].
 This is populated in [findOldExtensions].

### Block 4

The current folder browsed to in the dialog.
 Always ends with '/' except for root which is '/'.

### Block 5

The children of [currentFolder].

### Block 6

The file names that the notes will be moved to.

 These will be the same as in [fileNames], unless
 a file needs to be renamed to avoid a name conflict.
 Such a file will also be in [changedFileNames].

### Block 7

The new names of the files that needed to be renamed.

## Imports

- `package:flutter/cupertino.dart`
- `package:flutter/material.dart`
- `package:path/path.dart`
- `package:saber/components/theming/adaptive_alert_dialog.dart`
- `package:saber/data/file_manager/file_manager.dart`
- `package:saber/i18n/strings.g.dart`
- `package:saber/pages/editor/editor.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `MoveNoteButton`
- `MoveNoteDialog`
- `_MoveNoteDialogState`
- `build()`
- `findOldExtensions()`
- `createFolder()`
- `initState()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
