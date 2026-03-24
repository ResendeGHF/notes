# `lib/data/extensions/change_notifier_extensions.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

This is a hack to allow us to call [notifyListeners]
 which is usually protected.

 In my (@adil192) opinion, [notifyListeners] should be public. See
 - https://github.com/flutter/flutter/issues/135478
 - https://github.com/flutter/flutter/issues/27448
 - https://github.com/flutter/flutter/issues/29958
 - etc.

## Imports

- `package:flutter/material.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `ChangeNotifierExtensions`
- `notifyListenersPlease()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
