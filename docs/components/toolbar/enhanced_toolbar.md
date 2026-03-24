# `lib/components/toolbar/enhanced_toolbar.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Minimal toolbar with icons and popup card for pen selection

### Block 2

Index of the preset that matches current pen options, color, and easing ids; -1 if none.

### Block 3

Color picker for the toolbar: wheel only + editable hex field (no Primary/Accent).
 Hex field updates when wheel changes; wheel updates when user enters valid hex.

## Imports

- `dart:math`
- `dart:ui`
- `package:collection/collection.dart`
- `package:flex_color_picker/flex_color_picker.dart`
- `package:flutter/cupertino.dart`
- `package:flutter/material.dart`
- `package:flutter_quill/flutter_quill.dart`
- `package:font_awesome_flutter/font_awesome_flutter.dart`
- `package:material_symbols_icons/symbols.dart`
- `package:perfect_freehand/perfect_freehand.dart`
- `package:saber/components/theming/adaptive_alert_dialog.dart`
- `package:saber/components/toolbar/color_toolbar.dart`
- `package:saber/components/toolbar/size_picker.dart`
- `package:saber/data/editor/page.dart`
- `package:saber/data/extensions/color_extensions.dart`
- `package:saber/data/prefs.dart`
- `package:saber/data/tools/_tool.dart`
- `package:saber/data/tools/eraser.dart`
- `package:saber/data/tools/highlighter.dart`
- `package:saber/data/tools/laser_pointer.dart`
- `package:saber/data/tools/pen.dart`
- `package:saber/data/tools/select.dart`
- `package:saber/data/tools/shape_tool.dart`
- `package:saber/i18n/strings.g.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `EnhancedToolbar`
- `EnhancedToolbarState`
- `_ToolIconButton`
- `_PenSelectionCard`
- `_PenSelectionCardState`
- `_AdvancedPenOptionsPanel`
- `_AdvancedPenOptionsPanelState`
- `_HighlighterSelectionCard`
- `_HighlighterSelectionCardState`
- `_ChipOption`
- `_LaserOptionsCard`
- `_LaserOptionsCardState`
- `_ExportOptionTile`
- `_ShapeSelectionCard`
- `_ShapeSelectionCardState`
- `_EraserSelectionCard`
- `_EraserSelectionCardState`
- `_TextFormattingCard`
- `_PopoverOverlay`
- `_PopoverOverlayState`
- `_PopoverLayoutDelegate`
- `_ToolbarColorPickerContent`
- `_ToolbarColorPickerContentState`
- `_SmoothCirclePainter`
- `hideAllCards()`
- `didUpdateWidget()`
- `dispose()`
- `build()`
- `initState()`
- `Function()`
- `getPositionForChild()`
- `shouldRelayout()`
- `paint()`
- `shouldRepaint()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
