# `lib/data/editor/editor_history.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

A stack of the changes that have been made in the editor.
 The last element is used when undoing.

 See also: [_future]

### Block 2

A stack of the changes that have been undone in the editor.
 The last element is used when redoing.

 See also: [_past]

### Block 3

The last saved state in the history.
 This is used to determine whether an autosave is needed.

### Block 4

True if redo is possible.
 We don't directly clear [_future] because we sometimes need to
 reject strokes (i.e. accidental strokes when zooming).

### Block 5

Removes an element from the [_past] stack,
 adds it to the [_future] stack, and returns it.

 Please check [canUndo] first: this method will
 throw an exception if there is nothing to undo.

### Block 6

Removes an element from the [_future] stack,
 adds it to the [_past] stack, and returns it.

 Please check [canRedo] first: this method will
 throw an exception if there is nothing to redo.

### Block 7

Allows you to see the last item in the [_past] stack
 without removing it.

 Please check [canUndo] first: this method will
 throw an exception if there is nothing to undo.

### Block 8

Allows you to see the last item in the [_future] stack
 without removing it.

 Please check [canRedo] first: this method will
 throw an exception if there is nothing to redo.

### Block 9

Adds an item to the [_past] stack.

### Block 10

Marks the last change as saved to disk.
 This does not modify the history stacks, but allows us to know
 whether the current state is saved or not.

### Block 11

Whether the current state is saved to disk.

 Note that this explicitly checks the last change in the history,
 not whether _past is empty. This is because _past items can be discarded
 if the history exceeds [maxHistoryLength].

### Block 12

Removes the last history item due to a rejected stroke.
 This does essentially the opposite of [recordChange].

### Block 13

Returns true if there is something to undo.

### Block 14

Returns true if there is something to redo.

### Block 15

Original page of selected items before being moved to another one.

 This can be the same as [pageIndex]
 if the items were moved within the same page.

 See also: [SelectResult.pageIndexStart]

### Block 16

Strokes created by area erase (split segments). Used when [type] is [EditorHistoryItemType.areaErase].

### Block 17

Area erase: [strokes] = removed originals, [strokesAdded] = new split segments. One undo restores both.

## Imports

- `package:flutter/material.dart`
- `package:flutter_quill/flutter_quill.dart`
- `package:saber/components/canvas/_stroke.dart`
- `package:saber/components/canvas/image/editor_image.dart`
- `package:saber/data/editor/_color_change.dart`
- `package:saber/data/editor/page.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `EditorHistory`
- `EditorHistoryItem`
- `EditorHistoryItemType`
- `recordChange()`
- `markLastChangeAsSaved()`
- `clearRedo()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
