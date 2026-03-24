# Saber / Notes — technical documentation

This folder describes **architecture and algorithms** for the heaviest and most security-sensitive parts of the app. It is aimed at contributors who need to change rendering, I/O, or the editor without reverse-engineering large Dart files.

## Index

| Document | Topics |
|----------|--------|
| [canvas-inner-preview-painter.md](canvas-inner-preview-painter.md) | `InnerCanvas`, `CanvasPreview`, `CanvasPainter`, spatial indexing, GPU batching, repaint strategy |
| [canvas-stroke-and-shape.md](canvas-stroke-and-shape.md) | `_stroke.dart` (`Stroke`), mesh generation, `perfect_freehand`, splines, `QuadTree` / `SpatialGrid`, `ShapeStroke` |
| [file-manager.md](file-manager.md) | `FileManager`: vault vs plain disk, paths, backups, exports, directory watching |
| [vault-adapter.md](vault-adapter.md) | `VaultAdapter`: SQLCipher index, encrypted blobs, caches, isolates |
| [editor-and-menu.md](editor-and-menu.md) | `editor.dart`, `editor_menu.dart` (`ModernEditorMenu`): gesture pipeline, tools, history, menu surface |
| [other-core-systems.md](other-core-systems.md) | Editor history, eraser, exporter, gesture detector, worth knowing |

## Source map (quick)

- Canvas stack: `lib/components/canvas/inner_canvas.dart`, `canvas_preview.dart`, `_canvas_painter.dart`, `_stroke.dart`, `_shape_stroke.dart`
- I/O: `lib/data/file_manager/file_manager.dart`, `lib/services/vault_adapter.dart`, `lib/services/sba_encryption.dart`
- Editor shell: `lib/pages/editor/editor.dart` (+ parts `editor_menu.dart`, `editor_scrollbar.dart`, `editor_split_view.dart`)

When in doubt, **grep** the symbol you need from `lib/` — these docs name the main entry points but do not list every helper.
