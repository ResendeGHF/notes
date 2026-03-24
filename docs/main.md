# `lib/main.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

To set the flavor config e.g. for the Play Store, use:
 flutter build \
   --dart-define=FLAVOR="Google Play" \
   --dart-define=APP_STORE="Google Play" \
   --dart-define=UPDATE_CHECK="false"

## Imports

- `dart:async`
- `dart:io`
- `package:args/args.dart`
- `package:flutter/foundation.dart`
- `package:flutter/material.dart`
- `package:flutter/services.dart`
- `package:go_router/go_router.dart`
- `package:logging/logging.dart`
- `package:path_to_regexp/path_to_regexp.dart`
- `package:pdfrx/pdfrx.dart`
- `package:printing/printing.dart`
- `package:receive_sharing_intent/receive_sharing_intent.dart`
- `package:saber/components/editor/sba_export_dialog.dart`
- `package:saber/components/theming/dynamic_material_app.dart`
- `package:saber/data/file_manager/file_manager.dart`
- `package:saber/data/flavor_config.dart`
- `package:saber/data/prefs.dart`
- `package:saber/data/routes.dart`
- `package:saber/data/tools/stroke_properties.dart`
- `package:saber/i18n/strings.g.dart`
- `package:saber/pages/editor/editor.dart`
- `package:saber/pages/home/home.dart`
- `package:saber/pages/home/vault_pdf_load_overrides_page.dart`
- `package:saber/pages/logs.dart`
- `package:saber/pages/vault_login.dart`
- `package:saber/services/vault_adapter.dart`
- `package:window_manager/window_manager.dart`
- `package:worker_manager/worker_manager.dart`
- `package:workmanager/workmanager.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `App`
- `_AppState`
- `callbackDispatcher()`
- `main()`
- `appRunner()`
- `setLocale()`
- `initState()`
- `didChangeAppLifecycleState()`
- `setupSharingIntent()`
- `build()`
- `dispose()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
