# `lib/pages/home/search.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Mitigates a bug where files got imported starting with `null/` instead of `/`.

 This caused them to be written to `Documents/Sabernull/...` instead of `Documents/Saber/...`.

 See https://github.com/saber-notes/saber/issues/996
 and https://github.com/saber-notes/saber/pull/977.

## Imports

- `dart:async`
- `package:collapsible/collapsible.dart`
- `package:flutter/material.dart`
- `package:go_router/go_router.dart`
- `package:logging/logging.dart`
- `package:saber/components/home/delete_note_button.dart`
- `package:saber/components/home/export_note_button.dart`
- `package:saber/components/home/masonry_files.dart`
- `package:saber/components/home/move_note_button.dart`
- `package:saber/components/home/new_note_button.dart`
- `package:saber/components/home/rename_note_button.dart`
- `package:saber/components/home/select_all_button.dart`
- `package:saber/components/home/sort_button.dart`
- `package:saber/components/theming/saber_theme.dart`
- `package:saber/data/file_manager/file_manager.dart`
- `package:saber/data/home_data_cache.dart`
- `package:saber/data/prefs.dart`
- `package:saber/data/routes.dart`
- `package:saber/data/tags_database.dart`
- `package:saber/i18n/strings.g.dart`
- `package:saber/services/vault_adapter.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `SearchPage`
- `_SearchPageState`
- `moveIncorrectlyImportedFiles()`
- `initState()`
- `dispose()`
- `fileWriteListener()`
- `filterFiles()`
- `build()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
