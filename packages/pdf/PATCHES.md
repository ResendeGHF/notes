# Vendored `pdf` package

This is `pdf` **3.13.0** from [pub.dev](https://pub.dev/packages/pdf),
vendored so Saber can carry a small performance patch. It is wired up through
`dependency_overrides` in the repository root `pubspec.yaml`.

## Patch: `PdfStream` grows geometrically

**File:** `lib/src/pdf/format/stream.dart` (`PdfStream._ensureCapacity`)

Upstream grows the output buffer by a fixed 64 KiB step and copies the entire
buffer into the new allocation on every growth. For large documents that makes
`Document.save()` quadratic: writing a ~64 MiB PDF (an 862-page scanned EPUB)
copies tens of gigabytes in total and takes ~15 s on a fast desktop.

The patch keeps the upstream "+64 KiB" step but doubles the buffer size when
that is larger, so the total copy work stays linear. The same conversion then
takes well under a second. Output bytes are identical to upstream.

```diff
-    final newSize = _offset + size + _grow;
+    var newSize = _offset + size + _grow;
+    final doubled = _stream.length * 2;
+    if (doubled > newSize) {
+      newSize = doubled;
+    }
     final newBuffer = Uint8List(newSize);
     newBuffer.setAll(0, _stream);
     _stream = newBuffer;
```

This applies to every PDF Saber writes through the widget layer (EPUB import,
note export, ...), not only to imports.

## Updating to a newer `pdf`

1. Replace `lib/` with the new release's `lib/` (and `pubspec.yaml`, keeping
   the version field exactly as upstream publishes it).
2. Re-apply the patch above.
3. Update this file and the override in the root `pubspec.yaml` if the version
   changed.
4. Check whether upstream fixed the buffer growth; if so, drop the patch,
   delete this directory and the override.

Upstream source: <https://github.com/DavBfr/dart_pdf> (Apache-2.0, see
`LICENSE`).
