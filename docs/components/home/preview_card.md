# `lib/components/home/preview_card.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Loads thumbnail with retry logic to handle race conditions.
 Uses ThumbnailCache for instant display when switching tabs.

### Block 2

Use context.push instead of OpenContainer to prevent layout shift:
 OpenContainer reparents the closed widget during its transition, causing
 the masonry grid to recalculate and items below to shift position.

## Imports

- `dart:async`
- `dart:ui`
- `package:flutter/cupertino.dart`
- `package:flutter/material.dart`
- `package:go_router/go_router.dart`
- `package:saber/components/canvas/_stroke.dart`
- `package:saber/components/canvas/inner_canvas.dart`
- `package:saber/components/canvas/invert_widget.dart`
- `package:saber/components/editor/export_dialog.dart`
- `package:saber/components/home/move_note_button.dart`
- `package:saber/components/home/rename_note_button.dart`
- `package:saber/components/theming/adaptive_alert_dialog.dart`
- `package:saber/components/theming/saber_theme.dart`
- `package:saber/data/editor/editor_core_info.dart`
- `package:saber/data/file_manager/file_manager.dart`
- `package:saber/data/routes.dart`
- `package:saber/i18n/strings.g.dart`
- `package:saber/pages/editor/editor.dart`
- `package:saber/services/thumbnail_cache.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `PreviewCard`
- `_PreviewCardState`
- `_FallbackThumbnail`
- `_ThumbnailState`
- `initState()`
- `didChangeDependencies()`
- `didUpdateWidget()`
- `fileWriteListener()`
- `build()`
- `buildCardContent()`
- `openAction()`
- `dispose()`
- `markAsChanged()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
