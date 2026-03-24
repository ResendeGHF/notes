# `lib/data/prefs.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

If false, all stows are stuck at their default values.

### Block 2

Call this before [runApp] to set [_isOnMainIsolate] to true.

### Block 3

Ephemeral ink tip ahead of the stylus while drawing (not persisted in strokes).

### Block 4

0 = minimal lookahead, 1 = stronger extrapolation (still clamped for stability).

### Block 5

Modern minimalist default palette for toolbar color bar (used when pref is unset or reset).

### Block 6

Default 10 favorite colors per pen (minimal, modern palette) until user sets their own.

### Block 7

Saved Advanced Pen presets: list of {name, options (Map), colorArgb (int), easingId?, startEasingId?, endEasingId?}.

### Block 8

Default margins for new pages (left, right, top, bottom). All 0 = no margins.

### Block 9

Default margin/border color when any default margin is not 0. Uses defaultPageColor when null.

### Block 10

When true, browse page shows the full file tree; when false, shows graph (folders + notes in current path).

### Block 11

Sort preferences for the Browse screen (alphabetical by default).

### Block 12

Sort preferences for the Recent Notes screen (last modified by default).

### Block 13

Per-note overrides for "Invert notes in dark mode".
 Key: note file path, Value: 0 = force off, 1 = force on.

### Block 14

Per-note overrides for "Invert background images in dark mode".
 Key: note file path, Value: 0 = force off, 1 = force on.

### Block 15

Whether local encryption (vault) is enabled.

### Block 16

When true, vault overwrites deleted data with zeros (slower I/O).
 When false, deletes are fast; take effect after next vault unlock.

### Block 17

PDF/asset loading mode when vault is enabled.
 "ram_only" = decrypt to RAM only, no temp file (slower, most secure).
 "temp_file" = decrypt to temp file for faster loading (temp is secure-deleted).

### Block 18

When false (default), PDFs >100MB never load into RAM (prevents OOM).
 When true, user can try loading large PDFs in RAM mode at their own risk.

### Block 19

Per-file overrides for PDF loading: path -> "ram_only" | "temp_allowed" | "default".
 "default" = use global vaultPdfLoadMode.

### Block 20

When true, autosave updates the note thumbnail. When false, only manual save does.

### Block 21

An [Stow] that transforms the value of another [Stow].

### Block 22

Codec for Map<String, int> that serializes to/from JSON.

### Block 23

Codec for Map<String, String> that serializes to/from JSON.

### Block 24

Normalizes path for override lookup (matches vault internal format).

### Block 25

Returns the effective PDF load mode for a vault file path.
 "ram_only" = use RAM only (no temp file). "temp_file" = allow temp file.
 Supports exact match and prefix match (e.g. override for "storage/note.sbn2"
 applies to "storage/note.sbn2.0").

### Block 26

Returns the stored per-file override for PDF loading mode, or 'default' if none.
 Use for UI display (e.g. note properties dialog) so path normalization is consistent.

### Block 27

Sets or clears the per-file override for PDF loading mode.

### Block 28

Returns the effective "invert notes in dark mode" flag for a given note.
 If there is no per-note override, falls back to the global [editorAutoInvert] flag.

### Block 29

Sets or clears the per-note override for "invert notes in dark mode".
 When [invert] matches the global setting, the override is removed.

### Block 30

Returns the effective "invert background images in dark mode" flag for a given note.

### Block 31

Sets or clears the per-note override for "invert background images in dark mode".

## Imports

- `dart:async`
- `dart:convert`
- `dart:io`
- `package:flutter/foundation.dart`
- `package:flutter/material.dart`
- `package:logging/logging.dart`
- `package:perfect_freehand/perfect_freehand.dart`
- `package:saber/components/navbar/responsive_navbar.dart`
- `package:saber/data/editor/canvas_background_pattern.dart`
- `package:saber/data/flavor_config.dart`
- `package:saber/data/tools/_tool.dart`
- `package:saber/data/tools/pen.dart`
- `package:stow/stow.dart`
- `package:stow_codecs/stow_codecs.dart`
- `package:stow_plain/stow_plain.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `Stows`
- `TransformedStow`
- `_MapStringIntCodec`
- `_MapStringIntEncoder`
- `_MapStringIntDecoder`
- `_MapStringStringCodec`
- `_MapStringStringEncoder`
- `_MapStringStringDecoder`
- `protectedRead()`
- `protectedWrite()`
- `toString()`
- `dispose()`
- `getEffectiveVaultPdfLoadMode()`
- `getStoredVaultPdfLoadOverrideForPath()`
- `setVaultPdfLoadOverrideForFile()`
- `getEffectiveNoteInvertInDarkModeForFile()`
- `setNoteInvertInDarkModeOverrideForFile()`
- `getEffectiveNoteInvertBackgroundForFile()`
- `setNoteInvertBackgroundOverrideForFile()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
