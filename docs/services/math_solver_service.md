# `lib/services/math_solver_service.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Inicializa e tenta baixar o modelo de reconhecimento.
 Protegido contra falhas de rede (Offline safe).

### Block 2

Tenta reconhecer, resolver e gerar o stroke de resultado

### Block 3

Gera strokes usando definições vetoriais manuais de alta qualidade

## Imports

- `dart:math`
- `dart:ui`
- `package:flutter/material.dart`
- `package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart`
- `package:logging/logging.dart`
- `package:math_expressions/math_expressions.dart`
- `package:saber/data/stroke_geometry/stroke_geometry.dart`
- `package:saber/components/canvas/_stroke.dart`
- `package:saber/data/editor/page.dart`
- `package:saber/data/tools/_tool.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `MathSolverService`
- `init()`
- `dispose()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
