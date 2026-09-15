# `lib/services/thumbnail_cache.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

In-memory LRU cache for note thumbnails. Speeds up Home/Browse/Search
 when switching tabs - thumbnails load instantly from cache.

### Block 2

Get cached thumbnail bytes, or null if not cached.

## Imports

- `dart:collection`
- `dart:typed_data`
- `package:saber/pages/editor/editor.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `ThumbnailCache`
- `_CacheEntry`
- `put()`
- `invalidate()`
- `clear()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
