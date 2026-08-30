# `_stroke.dart` (`Stroke`) and `_shape_stroke.dart` (`ShapeStroke`)

## `Stroke` — data model

A `Stroke` is the **authoritative** representation of ink on a page:

- **`points`** — `List<PointVector>` (from `lib/data/stroke_geometry`): x, y, optional pressure.
- **`StrokeOptions`** — size, thinning, smoothing, streamline, tapers, caps (`stroke_geometry` types).
- **`toolId`** — fountain, ballpoint, highlighter, calligraphy, advanced, etc.
- **Caches:** polygon/path/vertices invalidated via `markPolygonNeedsUpdating()`.

**Bounds:** Incrementally expanded on `addPoint` when possible; otherwise recomputed from geometry — used everywhere for **hit tests**, **culling**, **spatial indices**.

---

## Input pipeline: sampling and stabilization

### `addPoint`

1. Optional **pressure** normalization (if disabled, pressure ignored).
2. **One Euro–style filter** (`_applyStabilization`) when user prefs enable stabilization: adaptive low-pass on position from timestamps — **O(1)** per point with small state.
3. **Linear interpolation** along the chord when gap **> threshold** (`~2.5px`) with step **`~1.15px`**: prevents huge gaps on fast strokes — **O(k)** inserted points for gap length.
4. Highlighter **straight-line mode:** keeps **two points** only (start + moving end).
5. Invalidates packed points / polygon caches.

**Complexity per event:** **O(1)** amortized except interpolation which adds **O(distance)** points.

---

## Spine smoothing (Catmull-Rom family)

### `_getSmoothSpine`

Classic **Catmull-Rom** spline between consecutive control points, with **per-segment subdivision count** derived from Euclidean length and optional curvature boost at corners — **segments ∈ [3, 16]**.

**Use:** Highlighter polylines, ballpoint when sparse, other tools as documented in `getPolygon`.

**Complexity:** **O(n · S)** for n segments and average S subdivisions (bounded).

### `_getAdaptiveSpineFast`

**Purpose:** Densify polyline with **adaptive** extra samples only where the midpoint of the Catmull-Rom segment **deviates** from the chord beyond **`toleranceSq`** (scale-dependent: `(ε/scale)²`).

Iterates segments; if deviation large, inserts points at **t = 0.33, 0.66** (recursive refinement pattern in flat form).

**Complexity:** **O(n)** in best case (few subdivisions); worst **O(n log L)**-style for pathological polylines (many refinements); bounded by input size in practice.

---

## Polygon and path for rendering

### `getPolygon({StrokeQuality quality})`

**Branches by `toolId`:**

| Tool | Strategy |
|------|----------|
| Highlighter | Smooth spine for ≥3 points → `buildConstantWidthOutline` (flat or round caps via `flatEdge`). |
| Advanced pen | High quality: smooth spine; low quality: decimate with `skipPoints`. |
| Calligraphy / Fountain | Adaptive spine from packed floats, then calligraphy ribbon or `getStroke` (`stroke_geometry`). |
| Ballpoint | Adaptive spine (same family as fountain) for smooth output. |
| Default | High quality + adaptive spine when needed; low quality may use **Ramer–Douglas–Peucker** (`_ramerDouglasPeucker`) with ε ∝ `options.size`. |

**RDP complexity:** **O(n)** typical implementation per decimation pass.

### `stroke_geometry.getStroke` / `buildConstantWidthOutline`

Produces a **single closed polygon** outline around the polyline — used for **filled translucent ink** (highlighter) without triangle-mesh overlap artifacts. Options control size, end caps, and (for pressure pens) thinning/tapers.

**Complexity:** **O(m)** in spine points m.

---

## Triangle mesh path (`vertices`, `_generateSpineMeshLOD`)

**Used for:** Most pens **except** advanced pen + highlighter (those use path fill in painter for uniform behavior).

**Pipeline:**

1. **`_getAdaptiveSpineFast`** on packed `[x,y,p]` → smooth spine.
2. **Dedupe** near-duplicate points.
3. Walk spine: compute **left/right offset** along **averaged normals** (blend forward/backward tangents); **miter-like joins** with optional **fan of segments** at sharp corners (`dot < 0.5`) to avoid bow-ties.
4. **Caps:** LUT-based circular-ish caps (`_capSegments`).
5. **Calligraphy:** Elliptical nib in rotated frame; **highlighter / ballpoint:** constant width.
6. Output **`ui.Vertices`** triangle strip / indexed triangles + **raw positions/indices** for batching.

**LOD:** `setLodScale` feeds tolerance for spline and visual fingerprint for **global vertex cache** (`_globalVertexCache`) — same geometry + LOD bucket → **reuse** `Vertices` (flyweight).

**Complexity per stroke:** **O(n)** in spine length n for mesh build; **cache hit** → **O(1)** lookup.

---

## `highQualityPath`

For **path-based** drawing (live stroke, export paths): builds `Path` from polygon with **`smoothPathFromPolygon`** (quadratic smoothing) or tool-specific quadratic midpoints for calligraphy when complete.

**Deduplication** of polygon vertices avoids degenerate segments.

---

## `QuadTree<T>` (in `_stroke.dart`)

**Classic point-region quadtree** storing **items** (strokes, or **indices** in `InnerCanvas`) with **axis-aligned bounds**.

- **Insert (iterative stack):** While node full and undivided → **subdivide** into 4 children; push children. **O(log n)** average well-distributed; **O(depth)** worst.
- **Query:** DFS/stack; collect items whose bounds overlap range. **O(visited nodes + output size)**.
- **Remove:** Stack walk, remove from any node containing item. **O(nodes touched)**.

**Shared stacks** `_insertStack`, `_queryStack`, `_removeStack` reduce allocations during hot paths.

---

## `SpatialGrid`

Uniform **100px** cells (configurable). Hash **(cx, cy)** into bucket lists of stroke **indices**.

**Good for:** Moderate n, simpler than tree, predictable memory.

**Bad for:** Very non-uniform stroke density (many in one cell → long lists).

---

## `ShapeStroke` (`lib/components/canvas/_shape_stroke.dart`)

**Extends `Stroke`:** represents **parametric shapes** from the shape tool (line, arrow, rectangle, …).

### Construction

- Takes `ShapeConfig` (kind, geometry, stroke width).
- Forces `smoothing/streamline/simulatePressure/thinning` **off** for predictable vector look.
- **`_regeneratePoints`:** Builds `Path` from config, samples **`PathMetric`** along length with step **`max(1, length/2048)`** → fills `points` so eraser / selection / serialization see a **polyline**.

**Complexity:** **O(length / step)** samples; bounded by ~2048 steps per contour.

### `shapePath` / rotation / JSON

- Caches `Path`; supports rotation, fill, custom vertices for some shapes (e.g. triangle handles).
- Serialization includes `ShapeConfig` + vertices where needed.

### Area eraser

Uses same `pointsForEraser` as base stroke; shapes that need perimeter sampling (circle/rect) override in sibling files (`_circle_stroke`, `_rectangle_stroke`).

---

## Summary complexity cheat sheet

| Operation | Typical |
|-----------|---------|
| `addPoint` | O(1) + O(gap) interpolation |
| Full polygon for stroke | O(n) to O(n · S) |
| Mesh build | O(n) |
| Quadtree query (editor paint) | O(log n + k) informal average |
| Spatial grid query | O(cells + hits) |
| ShapeStroke sample path | O(2048) cap per metric |

---

## Related

- [canvas-inner-preview-painter.md](canvas-inner-preview-painter.md) — how indices/meshes are consumed.
- `lib/data/tools/eraser.dart` — splits `points` ranges using masks (see [other-core-systems.md](other-core-systems.md)).
