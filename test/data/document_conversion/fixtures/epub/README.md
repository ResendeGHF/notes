# EPUB conversion test corpus

Fixtures for the pure-Dart EPUB parser and PDF converter
(`lib/data/document_conversion/epub/`). They are hand-built by `generate.py`
and are deterministic: the same bytes are produced on every platform.

Regenerate with:

```sh
python3 test/data/document_conversion/fixtures/epub/generate.py
```

## Documents

| File | What it exercises |
| --- | --- |
| `book.epub` | EPUB 3: navigation document with a nested section, a nonexistent fragment (falls back to the chapter top), an external entry, a stylesheet with `@import`, a 4×3 PNG, internal same-document and cross-document links, a link to a non-spine resource, an external link, unusual characters, and a paragraph long enough to span many pages as one `RichText` |
| `ncx.epub` | EPUB 2: NCX table of contents, single chapter |

The fixtures carry no DRM, no remote resources and no fonts, so tests can parse
and convert them without network access. Real font rendering is exercised by
loading the app's bundled Atkinson Hyperlegible Next assets (see
`epub_test_utils.dart`).
