# Other important systems (brief technical notes)

These modules are not fully duplicated in dedicated docs but are **high impact** for correctness and performance.

---

## `CanvasGestureDetector` (`lib/components/canvas/canvas_gesture_detector.dart`)

Bridges **Flutter gestures** (`ScaleStart/Update/End`, hover, long-press) to editor callbacks.

- Handles **multi-touch** vs **stylus priority** (see editor’s `isDrawGesture` coordination).
- May **inject** high-frequency `PointerMoveEvent` samples into the editor when pen drawing (configurable).

**Complexity:** **O(1)** per event; listener count affects notification cost.

---

## `EditorHistory` / `EditorHistoryItem` (`lib/data/editor/editor_history.dart`)

- **`_past` / `_future` stacks**, max length **100** (oldest dropped).
- **`canRedo`** requires both **`_isRedoPossible`** and non-empty `_future` — editor sets `canRedo = true` after `undo()` so redo appears (see tests).
- **Types:** `draw`, `erase`, `areaErase` (requires `strokesAdded`), `move`, `quillChange`, page insert/delete, `changeColor`, etc.

**Complexity:** **O(1)** push/pop; applying an item is domain-specific.

---

## `Eraser` (`lib/data/tools/eraser.dart`)

### Stroke mode

Whole-stroke removal when **circle hit-test** succeeds (`bounds` then `isHitByCircle`).

### Area mode

- Maintains **`_AreaSession`** per original stroke: segments as index ranges over **original** `pointsForEraser`.
- **`_splitRangeOutsideCircle`:** builds a **boolean mask** along the polyline (point-in-circle + segment–circle distance) → **ranges** of surviving indices.
- New **`Stroke`** fragments via **`replacePointRangeFromEraser`**.
- **`shouldApplyAt`** in area mode **throttles** by distance (`size * 0.45` clamped) to limit work vs event rate.
- Optional **`areaTimeBudgetMs`** returns **`areaWorkRemaining`** when the candidate loop must continue next slice.

**Complexity (one apply):** **O(C · P)** worst where C = candidates in search rect, P = points per stroke segment processed; large strokes use **stride** in mask fill (`maxLocalSplitPoints`) to cap work.

---

## `EditorExporter` (`lib/data/editor/editor_exporter.dart`)

- **`generatePdf`:** builds `pdf` package `Document`; vector path for many strokes; **raster fallback** when page has images/PDF background (screenshot path).
- **`expandLinksForShare`** when exporting with linked notes.

**Complexity:** **O(pages × objects)**; screenshot path dominates when backgrounds are complex.

---

## `LinkExportExpander` / note links (`lib/data/editor/link_export_expander.dart`, `note_links_database.dart`)

Resolves **cross-note links** for export and navigation — graph-style expansion with cycle guards.

---

## `EditorCoreInfo` + `EditorPage`

- **Layers** (base + overlays) with max layer count.
- **`allStrokesInDrawOrder`**, **`redrawStrokes()`** invalidates canvas listenables.
- **Deferred spatial index build** for very large page lists (`_buildDeferredSpatialIndices` in editor).

---

## `stows` / `prefs.dart` (Stow-backed preferences)

Global **reactive preferences** (colors, dirs, encryption, stabilization, toolbar, …).  

**Side effect:** Many types read `stows` at construction (e.g. `Stroke.flatEdge`) — tests need **`flutter_test_config.dart`**-style initialization (see `test/flutter_test_config.dart`).

---

## `RecognitionService` / shape recognition (`lib/data/tools/shape_recognition.dart`, pen hold timer in editor)

Uses **`one_dollar_unistroke_recognizer`** after dwell time to propose **line/arrow/…** replacement for pen strokes.

---

## Thumbnails (`ThumbnailCache`, page `CanvasPreview`)

Preview uses **`InnerCanvas`** with low LOD scale — see [canvas-inner-preview-painter.md](canvas-inner-preview-painter.md).

---

## When to add a new dedicated doc

Add a new `.md` under `docs/` when:

- A subsystem exceeds ~500 lines **and** has a **non-obvious invariant** (security, ordering, numerical stability), or
- Onboarding repeatedly hits the same **3+ file** cluster.
