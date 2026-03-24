# `lib/pages/home/settings.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Widget for vault encryption toggle with migration logic.

## Imports

- `dart:convert`
- `dart:io`
- `dart:math`
- `dart:ui`
- `package:archive/archive_io.dart`
- `package:file_picker/file_picker.dart`
- `package:flex_color_picker/flex_color_picker.dart`
- `package:flutter/cupertino.dart`
- `package:flutter/foundation.dart`
- `package:flutter/material.dart`
- `package:flutter/services.dart`
- `package:font_awesome_flutter/font_awesome_flutter.dart`
- `package:go_router/go_router.dart`
- `package:intl/intl.dart`
- `package:path/path.dart`
- `package:path_provider/path_provider.dart`
- `package:permission_handler/permission_handler.dart`
- `package:saber/components/navbar/responsive_navbar.dart`
- `package:saber/components/settings/app_info.dart`
- `package:saber/components/settings/settings_button.dart`
- `package:saber/components/settings/settings_directory_selector.dart`
- `package:saber/components/settings/settings_dropdown.dart`
- `package:saber/components/settings/settings_selection.dart`
- `package:saber/components/settings/settings_switch.dart`
- `package:saber/components/settings/vault_pdf_load_settings.dart`
- `package:saber/components/theming/adaptive_alert_dialog.dart`
- `package:saber/components/theming/adaptive_toggle_buttons.dart`
- `package:saber/data/editor/canvas_background_pattern.dart`
- `package:saber/data/file_manager/file_manager.dart`
- `package:saber/data/locales.dart`
- `package:saber/data/prefs.dart`
- `package:saber/data/routes.dart`
- `package:saber/i18n/strings.g.dart`
- `package:saber/services/sba_encryption.dart`
- `package:saber/services/vault_adapter.dart`
- `package:share_plus/share_plus.dart`
- `package:stow/stow.dart`
- `package:wakelock_plus/wakelock_plus.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `SettingsPage`
- `_SettingsStows`
- `_SettingsPageState`
- `_VaultEncryptionSwitch`
- `_VaultEncryptionSwitchState`
- `_VaultCredentials`
- `_VaultCreationDialog`
- `_VaultCreationDialogState`
- `_VaultAdvancedOptions`
- `_VaultBackupTile`
- `_VaultBackupTileState`
- `_VaultPasswordDialog`
- `_VaultPasswordDialogState`
- `_VaultSecurityStatus`
- `_MigrationProgressDialog`
- `_PasswordDialog`
- `_PasswordDialogState`
- `initState()`
- `onChanged()`
- `build()`
- `buildSection()`
- `dispose()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
