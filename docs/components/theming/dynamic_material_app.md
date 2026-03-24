# `lib/components/theming/dynamic_material_app.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

A widget that adds a border around the app window when not in fullscreen.

### Block 2

Use KeyedSubtree to preserve child state when adding/removing border

## Imports

- `dart:io`
- `package:flutter/cupertino.dart`
- `package:flutter/material.dart`
- `package:flutter/services.dart`
- `package:flutter_localizations/flutter_localizations.dart`
- `package:flutter_quill/flutter_quill.dart`
- `package:go_router/go_router.dart`
- `package:hux/hux.dart`
- `package:saber/data/prefs.dart`
- `package:saber/i18n/extensions/redirecting_localization_delegate.dart`
- `package:saber/i18n/strings.g.dart`
- `package:window_manager/window_manager.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `DynamicMaterialApp`
- `DynamicMaterialAppState`
- `ExplicitlyThemedApp`
- `_BorderedWindow`
- `_BorderedWindowState`
- `_ColorSchemeContraster`
- `initState()`
- `onChanged()`
- `onWindowEnterFullScreen()`
- `onWindowLeaveFullScreen()`
- `build()`
- `dispose()`
- `didChangeDependencies()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
