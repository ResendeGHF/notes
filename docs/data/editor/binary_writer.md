# `lib/data/editor/binary_writer.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Returns the accumulated binary data as a Uint8List

### Block 2

Peeks at the next key without consuming it

### Block 3

Reads color stored as ARGB int

### Block 4

Note-level "Replace default" and page defaults (persist per note).

### Block 5

Per-note tool settings (color bar, pens, highlighter, eraser).

### Block 6

Infinite canvas note (single page that grows/shrinks).

### Block 7

Infinite thumbnail: 'j' = jdenticon (default), 'c' = user-set cover.

## Imports

- `dart:convert`
- `dart:typed_data`
- `package:flutter/painting.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `BinaryWriter`
- `BinaryReader`
- `SBNBinaryKeys`
- `PageBinaryKeys`
- `ImageBinaryKeys`
- `StrokeBinaryKeys`
- `clear()`
- `writeKey()`
- `writeInt()`
- `writeFloat()`
- `writeScaledFloat()`
- `writeDouble()`
- `writeBool()`
- `writeColor()`
- `writeString()`
- `writeEnum()`
- `writeFloatNoKey()`
- `writeScaledFloatNoKey()`
- `writeDoubleNoKey()`
- `writeIntNoKey()`
- `writeBoolNoKey()`
- `writeStringNoKey()`
- `writeBytes()`
- `toBytes()`
- `readKey()`
- `peekKey()`
- `readInt()`
- `readFloat()`
- `readScaledFloat()`
- `readBool()`
- `readString()`
- `readIntNoKey()`
- `readFloatNoKey()`
- `readDoubleNoKey()`
- `readBoolNoKey()`
- `readStringNoKey()`
- `readColor()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
