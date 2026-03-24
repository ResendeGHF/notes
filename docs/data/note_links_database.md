# `lib/data/note_links_database.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Database-backed storage for note-to-note links keyed by source note path.
 This allows graph views to read links without opening note files.

### Block 2

Closes the database (e.g. for restore or when switching data dir).

## Imports

- `dart:io`
- `package:path/path.dart`
- `package:saber/data/editor/editor_core_info.dart`
- `package:sqflite_sqlcipher/sqflite.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `NoteLinksDatabase`
- `setLinksForPath()`
- `remapPath()`
- `removePath()`
- `close()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
