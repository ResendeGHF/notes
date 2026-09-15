# `lib/components/toolbar/extrema_pane.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

When true, graph is rendered without grid/labels for a clean saved image.

### Block 2

Returns f(x) or null if evaluation fails or result is non-finite (for pole detection).

### Block 3

Returns f(x,y) or null if evaluation fails or result is non-finite.

### Block 4

Numerical partial derivatives for 3D (uses same parser). h scaled by domain.

### Block 5

Hessian determinant f_xx*f_yy - f_xy^2. Returns null if any eval fails.

### Block 6

Lower threshold to detect pole between two finite samples (e.g. tan near π/2).

### Block 7

Refines interval [a, b] to find x where f has a pole. [poleThreshold] used to treat large |f| as pole.

## Imports

- `dart:math`
- `package:flutter/material.dart`
- `package:saber/services/math_engine/format.dart`
- `package:saber/services/math_engine/grid.dart`
- `package:saber/services/math_engine/math_engine.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `ExtremaPointType`
- `_MinMaxMode`
- `ExtremaPoint`
- `ExtremaPane`
- `_ExtremaPaneState`
- `_Extrema2DPainter`
- `_Extrema3DPainter`
- `initState()`
- `dispose()`
- `addPole()`
- `isPoleLike()`
- `isFiniteBounded()`
- `build()`
- `paint()`
- `shouldRepaint()`
- `proj()`
- `drawLabel()`
- `drawDashedLineWith()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
