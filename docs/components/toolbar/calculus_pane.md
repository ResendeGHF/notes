# `lib/components/toolbar/calculus_pane.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Result of a numerical derivative or integral with an error estimate.

### Block 2

Derivative methods (professional-grade, robust).

### Block 3

Integration methods (professional-grade, robust).

### Block 4

Numerical calculus: derivative and quadrature with error estimates.

### Block 5

Context from the overlay that hosts the calculator; use for menus so they render on top.

### Block 6

∫_{xMin}^{xMax} f(x, yFixed) dx using Gauss-Kronrod.

### Block 7

Inline expandable selector to avoid z-index issues when calculator is in an overlay.

## Imports

- `dart:math`
- `package:flutter/material.dart`
- `package:saber/services/math_engine/math_engine.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `CalculusResult`
- `DerivativeMethod`
- `DerivativeMethodExt`
- `IntegrationMethod`
- `IntegrationMethodExt`
- `CalculusPane`
- `_CalculusPaneState`
- `dispose()`
- `build()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
