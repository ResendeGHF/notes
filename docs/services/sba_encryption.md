# `lib/services/sba_encryption.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Encrypts/decrypts SBA (Saber Archive) files with a shared password
 for cross-user sharing. Uses AES-256-CBC with Scrypt key derivation.

### Block 2

Returns true if [bytes] start with the encrypted SBA magic.

### Block 3

Encrypts [plainBytes] (raw SBA zip) with [password].
 Output format: magic | salt | iv | ciphertext

### Block 4

Decrypts [encryptedBytes] with [password]. Throws on wrong password.

## Imports

- `dart:convert`
- `dart:typed_data`
- `package:encrypt/encrypt.dart`
- `package:pointycastle/export.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `SbaEncryption`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
