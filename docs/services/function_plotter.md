# `lib/services/function_plotter.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Pure Dart function plotter that renders to PNG bytes (2D and 3D).

### Block 2

Polar plot: function r = f(theta). Theta uses x variable (radians).

### Block 3

Simple top-down 3D surface plot rendered as a heatmap.

### Block 4

Spherical surface plot: r = f(theta, phi)
 theta in [0, pi], phi in [0, 2pi]. Renders a top-down heatmap of z.

### Block 5

2D vector field quiver plot. fx, fy are expressions in x,y.

### Block 6

3D vector field projected on XY plane at z = z0; color encodes magnitude.

### Block 7

Expression evaluator supporting common math functions and variables x,y.

## Imports

- `dart:math`
- `dart:typed_data`
- `dart:ui`
- `package:flutter/foundation.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `FunctionPlotter`
- `ExpressionEvaluator`
- `_Tokenizer`
- `_Token`
- `_TokenType`
- `Function()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
