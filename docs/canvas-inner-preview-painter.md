# Inner canvas, canvas preview, and canvas painter

## Overview

The visible “page” in the editor is built from layers:

1. **Background** (solid, pattern, PDF, image) — `CanvasBackgroundPainter` / page assets.
2. **Committed strokes** — mostly drawn via **batched `ui.Vertices`** (GPU triangle meshes) for standard pens; highlighter, some path-only tools, and shapes use different paths.
3. **Live interaction** — current stroke, eraser, selection, laser, shape-recognition preview — `CanvasPainter` on a separate `CustomPaint` / `RepaintBoundary`.

`InnerCanvas` is the **StatefulWidget** that owns **spatial indices**, **vertex batching**, **Quill** embedding, thumbnails, and delegates painting to `CanvasPainter`.

`CanvasPreview` is a **thin wrapper**: same `InnerCanvas` with `isPreview: true` and no live tool state — used for thumbnails and list previews.

---

## `CanvasPreview` (`lib/components/canvas/canvas_preview.dart`)

**Role:** `PreferredSizeWidget` that sizes itself to a page (or default size) and builds:

```text
InnerCanvas(
  isPreview: true,
  currentStroke: null,
  currentSelection: null,
  currentToolIsSelect: false,
  currentScale: highQuality ? double.maxFinite : double.minPositive,
  …
)
```

**`currentScale` semantics:**

- **High quality:** passes `double.maxFinite` into `InnerCanvas` → after `clamp(0.1, 5.0)` in batching code this becomes **5.0** (maximum LOD detail for stroke meshes).
- **Low quality (thumbnails):** `double.minPositive` → clamps to **0.1** (coarser spline tolerance / cheaper geometry).

**Complexity:** **O(1)** widget build; real cost is downstream `InnerCanvas` + `CanvasPainter` for the stroke count on that page.

---

## `InnerCanvas` (`lib/components/canvas/inner_canvas.dart`)

### Responsibilities

| Concern | Mechanism |
|---------|-----------|
| Rebuild when page data changes | `redrawPageListenable` → `_onPageChanged` |
| **Spatial index** for paint-time culling | `SpatialGrid` or `QuadTree<int>` (indices into stroke list) |
| **GPU batching** | `_buildBatchedMeshes` → `Map<colorARGB32, List<ui.Vertices>>` |
| Selection | Duplicate batch **excluding** selected strokes so base layer can hide selection; overlay draws selection |
| Eraser | While eraser active: lighter repaint path; on eraser end: rebuild index + batches |
| Shape recognition preview | `Timer.periodic(~33ms)` → `ValueNotifier` drives pulse on `CanvasPainter` |
| Thumbnail capture | `RepaintBoundary` + `toImage` |

### Spatial index: when grid vs quadtree

In `_rebuildSpatialIndex()`:

- **`strokes.length ≤ 2000`** → **`SpatialGrid`** with `cellSize = 100` logical px. Each stroke index is inserted into every grid cell its **axis-aligned bounds** touch.
- **`strokes.length > 2000`** → **`QuadTree<int>`** over the page rect, `capacity = 10`, `getBounds: (i) => strokes[i].bounds`.

**Incremental update (`_updateSpatialIndex`):**

- If only **append** at end (same first stroke, longer list, still on grid path): **insert new indices only** into the grid — **O(k)** for k new strokes × cells covered.
- Otherwise: **full rebuild** — **O(n log n)** typical for quadtree construction (depends on distribution), **O(n · C)** for grid where C = average cells per stroke.

### `SpatialGrid` (defined in `_stroke.dart`)

- **Insert:** For each cell `(cx, cy)` overlapped by `Rect bounds`, append stroke index to a hash-bucket list: **O((Δx+1)(Δy+1))** per stroke where Δ* = number of cells spanned.
- **Query:** Iterate cells overlapped by query rect, union indices into a `Set`, sort — **O(cells · average_list_length log n)** for the sort; query cell count is **O(area of query in cells)**.

### Batched meshes (`_buildBatchedMeshes`)

**Goal:** Fewer `drawVertices` calls than “one per stroke” for fill-rate bound GPUs.

**Algorithm:**

1. Set each stroke’s LOD: `stroke.setLodScale(currentScale.clamped)`.
2. **Group** strokes by **`color.toARGB32()`**.
3. **Exclude** highlighter and `ShapeStroke` (different rendering path).
4. **Require** `stroke.vertices != null` (mesh-capable strokes).
5. For each color group, **greedily pack** strokes into chunks where total **vertex count** (from `getRawPositions().length / 2`) **≤ 65535** (`_kMaxVerticesPerBatch` — index buffer limit for `Uint16` indices in practice).
6. For each chunk, concatenate `Float32List` positions and expand **triangle strip indices** into **triangle list indices** for `Vertices.raw(VertexMode.triangles, …)`.

**Complexity:**

- **Grouping:** **O(n)**.
- **Packing + memcpy:** **O(total vertices)** across all strokes.
- **Memory:** one `ui.Vertices` per chunk per color; disposed on rebuild.

### `didUpdateWidget` logic (simplified)

Triggers **full mesh rebuild** when:

- Stroke finished (`currentStroke` went non-null → null),
- Stroke count changed,
- Page reference changed,
- Selection cleared (spatial index may need reset),
- Eraser gesture ended (rebuild index + batches).

While **eraser is down** (`eraserPosition != null`), batches may be **stale** on purpose; repaints use lighter invalidation.

---

## `CanvasPainter` (`lib/components/canvas/_canvas_painter.dart`)

### Visible stroke set (culling)

1. Compute **`cullingRect`** = local clip bounds **inflated by 120** px (draw slightly outside viewport).
2. If **previewing selection** (special identical-list case): use full `strokes` list.
3. Else if **spatial index exists** and `strokes.length > linearScanThreshold` (effectively **always** for huge lists when index present — threshold is `999999`):

   - **Quadtree:** `indices = quadTree.query(cullingRect)`, sorted.
   - **Grid:** `indices = spatialGrid.query(cullingRect)` (already sorted).
   - Map indices → `Stroke` into reusable buffer.

4. **Heuristic:** For the **last up to 20** strokes, if bounds overlap culling rect **or** tool is highlighter / advanced pen / calligraphy / `ShapeStroke`, **force-include** (avoids rare misses when bounds are tight or geometry is sensitive).

5. **Fallback:** If query returns empty but page has strokes, filter by `bounds.overlap`; if still empty, draw **all** (safety).

6. Without spatial structure: **linear scan** **O(n)** bounds tests.

**Complexity per frame:** **O(k)** for k visible strokes with a good index; worst case **O(n)**.

### Draw order (conceptual)

1. Highlighter strokes (special blend / fill rules).
2. If `batchedStrokes` provided: `drawVertices` per color batch; then **unbatchable** strokes (shape, `vertices == null`) via path / other branches.
3. Else: draw all non-highlighter via path/mesh logic.
4. Laser, current stroke, eraser indicator, page chrome, etc.

---

## Design trade-offs

| Choice | Benefit | Cost |
|--------|---------|------|
| Two structures (grid vs tree) | Grid is simple and fast for “normal” notes; tree scales to huge pages | Two code paths to maintain |
| 65535 vertex chunks | Works with 16-bit index paths on all backends | More draw calls when many fat strokes share a color |
| Inflate culling rect | Fewer pop-in artifacts | Slightly more overdraw |

---

## Related files

- `lib/components/canvas/_stroke.dart` — `Stroke`, `QuadTree`, `SpatialGrid`, mesh generation (see [canvas-stroke-and-shape.md](canvas-stroke-and-shape.md)).
- `lib/components/canvas/canvas_gesture_detector.dart` — feeds editor; not detailed here.
- `lib/data/editor/page.dart` — `allStrokesInDrawOrder`, layers, `redrawStrokes()`.
