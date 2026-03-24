# `lib/components/editor/sba_export_dialog.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Result of [showSbaExportModeDialog].

### Block 2

Shows a dialog to choose export mode (encrypted vs unencrypted)
 and optionally collects a shared password.

 When [hasExternalLinks] is true, shows a "Share Links" switch to embed
 linked pages in the export.

 Returns:
 - `ok: true` with `password: String` if user chose encrypted and entered password
 - `ok: true` with `password: null` if user chose unencrypted
 - `ok: false` if user cancelled
 - `shareLinks: true` if user enabled Share Links (only when hasExternalLinks)
 - `includeExportMetadata: bool` for SBA: when false, `saveToSba` omits dates, time spent, location, and first-page hash (PDF flow always omits this flag in the archive path)

### Block 3

Result of the SBA export mode dialog.

### Block 4

When false (e.g. PDF export), encryption options are hidden since PDFs cannot be encrypted.

## Imports

- `dart:ui`
- `package:flutter/cupertino.dart`
- `package:flutter/material.dart`
- `package:saber/i18n/strings.g.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `SbaExportModeResult`
- `showSbaExportModeDialog()`
- `showSbaImportPasswordDialog()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
