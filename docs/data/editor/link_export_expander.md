# `lib/data/editor/link_export_expander.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Resolves [targetPath] relative to [sourcePath].

### Block 2

Formats a link for PDF/static display, e.g. "p:5-25 V. Arnold - Mechanics".

### Block 3

Returns true if the link points to an external note (not self).

### Block 4

Formats a link for static display (e.g. PDF export).
 Returns strings like "p:5-25 V. Arnold - Mechanics" or "p:5 V. Arnold - Mechanics".
 For mutated links (targetPath empty), [label] already contains the full string.

### Block 5

Copies an [EditorImage] with remapped asset into [targetCache].

### Block 6

Deep-copies [source] page from [externalCoreInfo] into [targetCoreInfo],
 merging assets and remapping IDs.

### Block 7

Expands external links inline for export. When [shareLinks] is true:
 - Iterates pages in order
 - For each external link on a page, appends the linked pages as a block
 - Mutates links to point to local pages (targetPath = '')
 - Returns a new EditorCoreInfo ready for saveToSba with omitLinksForExport=false

## Imports

- `dart:typed_data`
- `package:flutter/material.dart`
- `package:flutter_quill/flutter_quill.dart`
- `package:path/path.dart`
- `package:saber/components/canvas/_asset_cache.dart`
- `package:saber/components/canvas/image/editor_image.dart`
- `package:saber/data/editor/editor_core_info.dart`
- `package:saber/data/editor/note_layer.dart`
- `package:saber/data/editor/page.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `formatLinkDisplayLabel()`
- `isExternalNoteLink()`
- `formatLinkLabelForPdf()`
- `expandLinksForShare()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
