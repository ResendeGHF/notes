# Inner canvas, canvas preview, and canvas painter

## Overview

The visible “page” in the editor is built from layers:

1. **Background** (solid, pattern, PDF, image) — `CanvasBackgroundPainter` / page assets.
2. **Committed strokes** — usually a **tiled `ui.Picture` cache** (`_TiledStrokePictureCache`, 512px tiles) replayed each frame; falls back to `CanvasPainter` when a selection is active.
3. **Live interaction** — current stroke, eraser, selection, laser, shape-recognition preview — `CanvasPainter` on a separate `CustomPaint` / `RepaintBoundary` with `willChange: true`.

`InnerCanvas` owns the tiled Picture cache, a flattened committed-stroke list cache, optional color mesh batches for the non-cache path, and wires the page `QuadTree<Stroke>` into paint-time culling.

`CanvasPreview` is a thin wrapper: same `InnerCanvas` with `isPreview: true`.

---

## Paint path (current)

| Layer | Mechanism | Hints |
|-------|-----------|-------|
| Background | `RepaintBoundary` + `CanvasBackgroundPainter` | `isComplex: true` |
| Committed strokes | Tiled Picture cache **or** `CanvasPainter` | `isComplex: true` |
| Live tools | `CanvasPainter` | `willChange: true` |

### Tiled Picture cache

- 512px tiles, 128px cull padding
- Per-tile `SpatialGrid` for which strokes belong in a tile
- Visible tiles only (`canvas.getLocalClipBounds()`)
- Invalidation: full (`invalidateAll`) or dirty-rect (eraser mid-stroke; finished stroke when bounds are finite)

### Paint-time spatial culling

- Page builds `QuadTree<Stroke>` via `EditorPage.buildSpatialIndex` (also used by the eraser)
- `InnerCanvas` passes `page.strokeSpatialIndex` into `CanvasPainter.quadTree` on the committed fallback path (selection / no tile cache)
- Culling activates when `strokes.length > 250`

### Mesh batching

- `_buildBatchedMeshes` groups committed pen meshes by `color.toARGB32()`
- Used on the non-cache `CanvasPainter` path (`batchedStrokes`)
- Highlighter / shapes stay on the per-stroke path

---

## Impeller / ABI

- Flutter Android uses Impeller by default (no project opt-out)
- Release packaging is **arm64-v8a only** (`ndk.abiFilters` in `android/app/build.gradle.kts`)

---

## Profiling notes

Profile on-device for: dense-page pan/zoom, fast inking, laser blur (`MaskFilter.blur` is a known Impeller cost). Prefer measuring before adding a native ink surface.
