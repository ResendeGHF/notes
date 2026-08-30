# `lib/components/editor/pdf_outline_navigator.dart`

Outline list for notes that have PDF bookmarks/outlines.

## Role

- Exposes [`PdfOutlineListView`](../../../lib/components/editor/pdf_outline_navigator.dart): a scrollable flat outline tree.
- Used as the **Outlines** tab inside [`EditorPageManager`](../toolbar/editor_page_manager.md).
- The old standalone toolbar **Outlines** `IconButton` / dialog was removed; navigation lives under the Pages side panel.

## Behavior

- Flattens `List<PdfOutlineItem>` via `flattenPdfOutlineTree(expandedKeys: …)`.
- **Collapsed by default**: only root-level sections are listed; chevron expands Section → SubSection → SubSubSection.
- Chevron toggles expand/collapse; tapping the title/page badge navigates (`onPageSelected`).
- Empty tree shows a localized placeholder (`t.editor.navigation.noPdfOutlineEntries`).
