# `lib/pages/home/graph.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

When true and _rootPath is null, show full graph. When false and _rootPath is null, show "Select root" only.

### Block 2

Max nodes to render at once to avoid lag; excess is truncated with a banner.

### Block 3

Filter notes by search query: match path (file name) or any tag.

### Block 4

All notes when "All notes" mode, or notes reachable from root; empty when "Select root" (no choice yet).

### Block 5

When tree view is on with a root, return all nodes reachable from root (BFS).

### Block 6

Spanning tree edges (parent, child) from root for tree layout.

## Imports

- `dart:async`
- `package:flutter/material.dart`
- `package:go_router/go_router.dart`
- `package:graphview/GraphView.dart`
- `package:saber/data/file_manager/file_manager.dart`
- `package:saber/data/home_data_cache.dart`
- `package:saber/data/note_links_database.dart`
- `package:saber/data/routes.dart`
- `package:saber/data/tags_database.dart`
- `package:saber/i18n/strings.g.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `GraphPage`
- `_GraphPageState`
- `initState()`
- `dispose()`
- `build()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
