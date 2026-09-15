# `FileManager` (`lib/data/file_manager/file_manager.dart`)

## Role

`FileManager` is the **central I/O façade** for user documents:

- Resolves **logical paths** (vault-relative or filesystem-relative).
- **Reads/writes** note files (`.sbn2` BSON, legacy JSON), assets, thumbnails.
- **Backups** (encrypted zip via `SbaEncryption`, manifest `_backup_manifest.json`).
- **Exports** (SBA, PDF pipeline hooks, PNG, folder archives).
- **Directory operations** (create/rename/move/delete folder, note counts).
- **Coordinates with `VaultAdapter`** when `stows.localEncryptionEnabled` is on.

It is **`static`** — single process-wide `documentsDirectory` and streams.

---

## Vault vs plain disk

```text
_shouldUseVault := stows.localEncryptionEnabled.value
```

When **true**:

- Logical reads/writes go through **`VaultAdapter`** (encrypted blobs + SQL index).
- **Disk watcher** (`watchRootDirectory`) is **disabled** — raw paths are opaque UUID blobs, not user paths.

When **false**:

- Direct `File` / `Directory` under `documentsDirectory`.
- **Recursive `watch`** on root for external changes.

---

## Path model

### `toRelativePath(String path)`

Normalizes slashes, strips `documentsDirectory` prefix if present, ensures leading `/`.

**Used by:** Vault index keys, archive entry names, link normalization.

**Complexity:** **O(length of path)**.

### `fixFileNameDelimiters`

Normalizes `\` → `/` for cross-platform consistency.

### `isCountableFile`

Filters **hidden**, **`.p` thumbnails**, **`.sbn2.N` asset sidecars**, internal `data/` and `file_picker/` paths — for **folder statistics UI**.

---

## Initialization (`init`)

1. Sets **`documentsDirectory`** from `stows.customDataDir` or `path_provider`.
2. Optionally starts **`watchRootDirectory`** (non-vault).
3. **`_cleanupVaultTempFiles`** — deletes `vault_*.tmp` in system temp (crash recovery).

---

## Backups (data archive)

**Isolate tasks** (see top of file):

- **`_isolateDataBackupTask`:** Walks `docsDir`, builds **zip** with manifest `type: data, version: 2`, embeds `_preferences.json`, optional **password encryption** via `SbaEncryption.encrypt`.
- **`_isolateDataRestoreTask`:** Decrypt if needed, validate manifest, extract to temp staging.

**`isDataBackupArchive(path)`:** Opens zip, finds `_backup_manifest.json`, checks `type == 'data'`.

**Complexity:** **O(total bytes)** for backup/restore dominated by disk + zip + optional scrypt/AES in `SbaEncryption`.

---

## Folder archives

**`createFolderArchive` / `encodeFolderArchive`:**

- Walks children via **`getChildrenOfDirectory`** (respects vault vs disk).
- **`FolderArchiveFormat.zip`:** `ZipEncoder`.
- **`FolderArchiveFormat.tarXz`:** `TarEncoder` + `XZEncoder`.
- Skips certain dirs/files (`_shouldSkipFolderArchiveDirectory`, `_shouldSkipFolderArchiveFile`).
- Resolves **symlink-like folder links** with cycle detection (`skippedCyclicLinks`).

**Complexity:** **O(files + total bytes)**.

---

## Note I/O highlights

- **`readFile` / `writeFile`:** Vault or raw; may use **temp files** for external editors.
- **`writeFilesBulk`:** Batches for performance.
- **`exportFile`:** User-facing export pipeline (share, gallery saver, etc.) — platform channels involved.
- **`newFilePath` / `suffixFilePathToMakeItUnique`:** Collision-safe naming.

---

## Streams

**`fileWriteStream`:** `StreamController<FileOperation>.broadcast()` — UI or index layers can react to writes/deletes without polling.

---

## Error handling & edge cases

- **Permissions** (photos, storage) wrapped around export-to-gallery paths.
- **PDF import** — `createNoteFromPdf` coordinates `pdfrx`, page splitting, asset extraction (large surface area; read method docs in source).

---

## Related

- [vault-adapter.md](vault-adapter.md) — encryption layer.
- `lib/services/sba_encryption.dart` — backup/share encryption format.
- `lib/data/editor/editor_exporter.dart` — PDF/SVG export from editor data.
