# `lib/data/tools/shape_tool.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Modern shape drawing tool with multi-step construction and fixed-start behavior.
 Supports physics diagrams (pendulum, spring, vectors) and precise triangle editing.

### Block 2

Returns the shapes that should be visible in the Shape Tool menu

### Block 3

Retorna o stroke se finalizou, ou null se ainda está construindo

### Block 4

Cancel current construction and reset state

### Block 5

Maps a stored shape kind index (from JSON) to [ShapeKind]. Old indices for
 removed shapes (toroid, sineWave, cosineWave) are mapped to
 [ShapeKind.rectangle]. Index 20 is nabla and must persist.

### Block 6

ShapeConfig Robusta
 Estratégia:
 - Runtime: Usa coordenadas ABSOLUTAS para performance e precisão de edição.
 - Storage: Usa coordenadas NORMALIZADAS para evitar conflitos de escala (explosão) ao recarregar.

## Imports

- `dart:math`
- `package:flutter/material.dart`
- `package:saber/components/canvas/_shape_stroke.dart`
- `package:saber/data/editor/page.dart`
- `package:saber/data/tools/_tool.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `ShapeTool`
- `ShapeKind`
- `ShapeKindVisibility`
- `ShapeConfig`
- `onDragStart()`
- `onDragUpdate()`
- `cancel()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
