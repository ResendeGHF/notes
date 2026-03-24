# Tests

Run all tests from the repo root:

```bash
flutter test test/
```

## Layout

| Path | Focus |
|------|--------|
| `flutter_test_config.dart` | Shared binding + `FlavorConfig` + mocked `SharedPreferences` (needed for `Stroke` / `stows`). |
| `helpers/` | Factories for canvas types used in multiple tests. |
| `services/` | Crypto, math engine (calculator), backup encryption (`SbaEncryption`). |
| `data/` | File manager paths & backup ZIP detection, editor history, pens, eraser, select, highlighter, export constants. |
| `widget/` | Lightweight widget smoke tests and toolbar tool-id registry checks. |
| `vault/` | Placeholder / skipped test documenting that real vault tests need SQLCipher + `integration_test/`. |

## Coverage notes

- **Vault (`VaultAdapter`)**: Unlock, SQLCipher index, and encrypted blobs require native SQLCipher and a writable vault directory. Use `integration_test/` with a temporary vault path for end-to-end checks.
- **Full `EnhancedToolbar`**: Depends on many prefs, i18n, and popovers; `enhanced_toolbar_tool_ids_test.dart` guards `ToolId` / singleton coverage instead of pumping the entire bar.
- **Quill**: History types `quillChange` / `quillUndoneChange` are tied to `flutter_quill` `DocChange`; extend with a small harness if you add a headless Quill document in tests.
- **PDF export**: `EditorExporter.generatePdf` needs a real `BuildContext` and often `ScreenshotController`; only static export constants are asserted here.
