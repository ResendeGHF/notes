# `lib/components/files/file_tree_skeleton.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Shimmer placeholder for a file tree row. Matches the exact layout of
 _FileTreeFolder (chevron + icon + label) and _FileTreeFile (icon + label).

### Block 2

Root-level skeleton: mimics real file tree shape with folders and files
 at correct indentation levels.

### Block 3

Skeleton for folder children loading (indented under expanded folder).
 Uses same indent formula as real _FileTreeFolder children.

### Block 4

Level of the parent folder (children are at parentLevel + 1)

## Imports

- `package:flutter/cupertino.dart`
- `package:flutter/material.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `FileTreeSkeletonRow`
- `_FileTreeSkeletonRowState`
- `FileTreeSkeleton`
- `FileTreeFolderSkeleton`
- `initState()`
- `dispose()`
- `build()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
