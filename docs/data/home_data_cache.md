# `lib/data/home_data_cache.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Shared cache for Home screen data (Recent, Search, Browse).
 Preloads data when Home mounts so tab switches show content instantly.

### Block 2

Preload all home data in parallel. Call when HomePage mounts.

### Block 3

Invalidate cache (e.g. on file change). Pages will refetch.

### Block 4

Returns browse root data. Use [browseRootCached] etc for sync check.

### Block 5

Cached browse root directory data.

## Imports

- `dart:convert`
- `package:saber/components/home/sort_button.dart`
- `package:saber/data/file_manager/file_manager.dart`
- `package:saber/data/tags_database.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `HomeDataCache`
- `BrowseRootData`
- `preload()`
- `invalidate()`
- `getBrowseRootOrLoad()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
