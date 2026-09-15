# `lib/components/toolbar/ode_isolate.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Runs ODE solver steps in a separate isolate to avoid blocking the main UI thread.
 Complex equations or high steps-per-tick would otherwise cause UI jank.

 [params] must contain:
 - expressions: List<String> [dx, dy?, dz?]
 - method: String ('euler'|'eulerCromer'|'verlet'|'rungeKutta4'|'forestRuth')
 - lastState: List<double>
 - lastT: double
 - h: double
 - stepsPerTick: int
 - tolerance: double
 - previousStableSteps: int

 Returns Map with:
 - success: bool
 - error: String? (if !success)
 - newSamples: List<Map> [{'t': double, 'state': List<double>}]
 - converged: bool
 - stableSteps: int

## Imports

- `dart:math`
- `package:saber/services/math_engine/math_engine.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `normalize()`
- `deltaNorm()`
- `stateIsFinite()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
