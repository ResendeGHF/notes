# `lib/i18n/extensions/redirecting_localization_delegate.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

{@template RedirectingLocalizationDelegate}
 A localization delegate that adds support for Esperanto.

 Flutter's built-in translations do not include Esperanto,
 so we have to redirect it to use English as a fallback to avoid
 breaking the whole app.
 {@endtemplate}

### Block 2

{@macro RedirectingLocalizationDelegate}

## Imports

- `package:flutter/material.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `RedirectingLocalizationDelegate`
- `isSupported()`
- `load()`
- `shouldReload()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
