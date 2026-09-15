# `lib/data/tools/_tool.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

An identifier for the tool,
 used to save the last-used tool in [stows.lastTool].

### Block 2

An enum of all available tools.
 Note that the pens must be ordered in z-axis order,
 e.g. so that the highlighter is always below the rest.

### Block 3

Codec that maps legacy 'pencilPen' to ballpointPen for prefs migration.

### Block 4

Before using this enum, we used the (runtimeType).toString()
 as the identifier for pens.
 This function converts those old identifiers to the new [ToolId]s.

### Block 5

Codec for prefs that maps legacy 'pencilPen' to ballpointPen.

## Imports

- `package:flutter/foundation.dart`
- `package:logging/logging.dart`
- `package:saber/data/prefs.dart`
- `package:stow_codecs/stow_codecs.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `Tool`
- `_TextEditingTool`
- `ToolId`
- `_ToolIdPrefCodec`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
