# `editor.dart` and `editor_menu.dart`

## File structure

`lib/pages/editor/editor.dart` is a **large** `StatefulWidget` (`Editor` / `EditorState`). It uses **`part` files**:

| Part | Role |
|------|------|
| `editor_menu.dart` | `ModernEditorMenu` — hamburger / side sheet for page settings, export, layers, etc. |
| `editor_scrollbar.dart` | Scrollbar helpers |
| `editor_split_view.dart` | Split-view secondary editor |

`editor_menu.dart` **must not be imported alone** — it is `part of 'editor.dart';` and closes over private types and `EditorState` patterns via callbacks passed as constructor args.

---

## `EditorState` — core responsibilities

### Document model

- **`EditorCoreInfo coreInfo`** — pages, links, line height, file path, quill controllers, PDF state, etc.
- **`history: EditorHistory`** — undo/redo stacks (`EditorHistoryItem` typed: draw, erase, areaErase, move, quill, pages, …).
- **`currentTool`** — `Pen`, `Eraser`, `Select`, `ShapeTool`, `LaserPointer`, `Tool.textEditing`, etc.

### Gesture pipeline (drawing)

Wired from **`CanvasGestureDetector`** into **`EditorState`**:

| Phase | Typical actions |
|-------|------------------|
| **`onDrawStart`** | Determine page under focal point; tool-specific: `Pen.onDragStart`, eraser first apply, select lasso start, shape tool step, reset timers |
| **`onDrawUpdate`** | `Pen.onDragUpdate` with pressure/timestamp; eraser position + `_doEraserApply`; selection transforms; `previousPosition` / `moveOffset` |
| **`onRawPointerMoveForDraw`** | Higher-rate samples for **pen** only (when stroke active) — bypasses coarser scale-update rate |
| **`onDrawEnd`** | Finalize stroke → `page.insertStroke`, **spatial index insert**, **history.recordChange**; eraser `onDragEnd` + dispose purged fragments; selection commit; shape completion |

**Complexity:** Per event **O(1)** for tool logic + **O(log n)** spatial insert amortized; area eraser can be **O(strokes in radius × points)** per apply (see eraser doc).

### Area eraser throttling

- `Eraser.apply(..., areaTimeBudgetMs: …)` slices CPU per frame; **`_scheduleAreaEraserBackgroundDrain`** continues work post-frame.
- On gesture end, **`_syncFlushAreaEraserWork`** runs **unbounded** passes so history matches final geometry.
- UI chip when backlog (memory-safe queue messaging).

### Undo / redo

- **`undo` / `redo`** mutate pages (strokes/images/quill), spatial indices, links, selection; call **`Eraser.currentEraser.clearState()`** so internal eraser session maps don’t reference stale strokes.

**Complexity:** **O(1)** stack pop + **O(Δ)** applying that history item (variable).

### Autosave

- **`autosaveAfterDelay`**, **`saveToFile`**, lifecycle **paused** → flush; coordinates with **`_isDisposed`** to avoid use-after-dispose.

### Infinite canvas

- Fixed logical **`Editor.infinitePageSize`**; pan/zoom via **`TransformationController`**; helpers **`_fitInfiniteCanvasToContent`**, **`_trimInfiniteCanvasWhitespace`**, **`_applyInfiniteCanvasExpansionTransform`**.

### PDF

- Large subsystem: outlines, links, equation preview, decryption state, **`pdfrx`** controllers — search `Pdf` / `pdfrx` in `editor.dart` for entry points.

### Quill

- Per-page **`QuillStruct`**; **`listenToQuillChanges`** records **`EditorHistoryItemType.quillChange`** with **`DocChange`** payloads; focus routing via **`quillFocus`** notifiers consumed by toolbar.

---

## `ModernEditorMenu` (`editor_menu.dart`)

**Purpose:** Single **surface** for “document menu” actions without crowding the main toolbar.

### Navigation

**Enum `_MenuPage`:** `main` → `pageSettings` → `backgroundSettings` / `layers` (nested Material navigation or equivalent in widget tree — see implementation).

### Callback pattern

The menu is **purely presentational**; every action is a **`VoidCallback` / `ValueChanged` / `Future` fn** provided by `EditorState` when building the menu:

- Page: pattern, line height/thickness/color, orientation, margins, border, clear page/all.
- Background: pick image, import PDF, invert, fit.
- Insert: table, plot, matrix image from calculator.
- Export: SBA, PDF, PNG.
- Meta: delete note, properties, split view toggles, tags/links, calculator, custom thumbnail.

**Complexity:** **O(1)** per user action from menu perspective; heavy work delegated to `FileManager`, exporters, PDF importers.

### Presets

**`_pageColorPresets`**, **`_lineColorPresets`** — static `Color` arrays for quick picks in UI.

---

## Build method (high level)

`Editor.build` composes:

- **Toolbar** (`EnhancedToolbar`, split toolbar) with tool/color/undo/export/calculator hooks.
- **`CanvasGestureDetector`** wrapping scrollable **`InteractiveCanvasViewer`** + per-page **`Canvas`** widgets (`InnerCanvas` inside).
- **Overlays:** PDF equation preview, save indicator, area-eraser notice, dialogs.

**Repaint strategy:** `ValueNotifier` / `Listenable` for interaction repaints to avoid full `setState` on every pointer move where possible.

---

## Related documentation

- [canvas-inner-preview-painter.md](canvas-inner-preview-painter.md)
- [other-core-systems.md](other-core-systems.md) — eraser, history detail, exporter entry

---

## Reading tips for contributors

1. **Start from** `onDrawStart` / `onDrawUpdate` / `onDrawEnd` — they fan out to all tools.
2. **Search** `history.recordChange` for what becomes undoable.
3. **Menu:** search `ModernEditorMenu(` in `editor.dart` build path to see **exact callback wiring**.
