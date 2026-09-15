# `lib/data/tags_database.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Database-backed storage for note tags. Tags are keyed by note path
 so search and editor can read/write without opening note files.

### Block 2

Ensures the database is open. Uses [FileManager.documentsDirectory]
 so tags live next to the user's data (including custom data dir).

### Block 3

Normalizes path to the same form used elsewhere (e.g. leading slash, forward slashes).
 Exposed so callers (e.g. Search) can look up tags by normalized path.

### Block 4

Returns all tags for a single note path.

### Block 5

Replaces all tags for a note. Pass empty list to clear.

### Block 6

SQLite limits bound parameters; chunk to stay under limit.

### Block 7

Batch: returns map of normalized note_path -> set of tags for many paths.
 Use [normalizePath] for lookups. Paths not in the DB get an empty set.

### Block 8

Merges tags from a note file (legacy) into the DB, then returns current tags for that path.
 Call once when loading an old note that had tags in its file.

### Block 9

Removes all tags for a note. Call when a note is deleted.

### Block 10

Closes the database (e.g. for tests or when switching data dir).

## Imports

- `dart:io`
- `package:path/path.dart`
- `package:saber/data/file_manager/file_manager.dart`
- `package:sqflite_sqlcipher/sqflite.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `TagDatabase`
- `setTagsForPath()`
- `removePath()`
- `close()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
