# `VaultAdapter` (`lib/services/vault_adapter.dart`)

## Architecture: “FBA” (file-backed archive pattern)

The vault splits concerns into two layers:

1. **Index — SQLCipher database** (`saber_index.db` under the vault root)  
   - Metadata: logical path → **storage id**, **IV**, size, timestamps, folder counts, config.  
   - Stores **`file_master_key`** (base64) used for **content** encryption (separate from SQLCipher’s page password).

2. **Storage — opaque files on disk** (`data/xx/<uuid>.enc` style)  
   - **AES-256-CBC** ciphertext of file bytes using master key + per-file IV.  
   - Filenames do **not** reveal user paths (privacy + tamper resistance).

**User password** → **Scrypt** (N, r, p from config sidecar) → **hex key** passed to SQLCipher **`openDatabase(..., password: x'…')`**.

---

## Unlock flow (`unlock`)

1. **`_setupPaths`** — resolve index path and storage root.
2. Read **vault config** sidecar (KDF iterations, cipher page size, salt, scrypt params).
3. **`_deriveKeyHexAsync`** — Scrypt on password + salt (may run off UI isolate for responsiveness).
4. **`openDatabase`** with SQLCipher pragmas:
   - `cipher_page_size`, `kdf_iter`, HMAC.
   - **`journal_mode = WAL`**, **`synchronous = NORMAL`**, **`wal_autocheckpoint`** — balance durability vs UI jank (same rationale as comments in code: long saves during drawing caused “square” strokes).
5. **`_ensureSchema`** — tables for files, folders, config.
6. **`PRAGMA secure_delete`** optionally ON from **`stows.vaultSecureDelete`**.
7. **`_initFileEncryption`** — load or create `file_master_key`, build **`enc.Encrypter(AES-CBC)`**.

**Complexity:** **O(1)** DB ops aside from **Scrypt** — **O(N·r·p · |password|)** work, intentionally expensive.

---

## Create vault (`create`)

Wipes storage root, writes config, opens DB **`onCreate`**: `_createTables`, inserts new random **`file_master_key`**, initial counts.

---

## Read / write file content

**Typical read:**

1. Normalize logical path → lookup **storage_id + iv** in DB (with **`_metaCache` LRU**).
2. Read bytes from **`data/...`** file.
3. **Decrypt** in memory (optionally via **isolate** for large files — see `readFileBytes` variants in source).
4. **`_readCache`:** LRU by path capped by **entry count** and **~128MB** bytes — hot reopen of same note avoids repeated decrypt+I/O.

**Typical write:**

1. Encrypt plaintext → write blob to new storage location if needed.
2. **Queue DB row update** in **`_pendingDbUpdates`**; **`Timer` debounce** (`_dbCommitDebounce`, ~2s) batches commits to reduce fsync pressure.

**Complexity per read (cache miss):** **O(file size)** crypto + I/O.  
**Per write:** **O(file size)** + amortized DB flush.

---

## Deletes and secure delete

- Index rows updated/deleted on remove.
- **Blob files:** may be **overwritten** or **secure-deleted** via **isolate** helpers (`isolateSecureDeletePaths`) when secure delete is enabled — **O(file size)** per file.

---

## Folder counts

**`_folderCountCache`** avoids repeated SQL for browse UI; invalidated on mutations (see methods touching folder metadata).

---

## Backup inside vault context

**`_isolateVaultBackupTask`** (top of file): packages vault-related data for backup export — runs in **isolate** to keep UI responsive; interacts with paths passed from main isolate only.

---

## Concurrency and safety

- **`preventLock`:** temporary flag (e.g. thumbnail/custom flows) to avoid re-entrant lock.
- **`unlockState` `ValueNotifier`** for UI.
- **`_isFlushing`** guards re-entrancy on DB batch flush.

---

## What unit tests cannot easily cover

- **SQLCipher** native library on host CI.
- **Platform secure storage** differences.

Use **integration tests** with a **temporary vault directory** and in-memory or test passwords for end-to-end checks.

---

## Related

- [file-manager.md](file-manager.md) — when `_shouldUseVault` routes here.
- `lib/services/sba_encryption.dart` — different format (SBA encrypted export), not the vault blob format.
