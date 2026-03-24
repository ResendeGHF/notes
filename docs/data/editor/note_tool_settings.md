# `lib/data/editor/note_tool_settings.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Per-note tool settings persisted in the note file.
 When a note is loaded, these override global preferences for that session.

### Block 2

Captures current tool state from stows and tool singletons.
 Prefers live tool state (Pen.currentPen, Highlighter.currentHighlighter,
 Eraser.currentEraser) when available so we capture unsaved edits.

### Block 3

Applies note tool settings to stows and tool singletons.

## Imports

- `dart:convert`
- `package:perfect_freehand/perfect_freehand.dart`
- `package:saber/data/prefs.dart`
- `package:saber/data/tools/_tool.dart`
- `package:saber/data/tools/eraser.dart`
- `package:saber/data/tools/highlighter.dart`
- `package:saber/data/tools/pen.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `NoteToolSettings`
- `toJsonString()`
- `applyNoteToolSettings()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
