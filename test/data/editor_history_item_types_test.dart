import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/editor/editor_history.dart';

/// Documents history item kinds used by the editor (draw, erase, quill, etc.).
void main() {
  group('EditorHistoryItemType', () {
    test('draw and erase items construct', () {
      final draw = EditorHistoryItem(
        type: EditorHistoryItemType.draw,
        pageIndex: 0,
        strokes: <Stroke>[],
        images: <EditorImage>[],
      );
      expect(draw.type, EditorHistoryItemType.draw);

      final erase = EditorHistoryItem(
        type: EditorHistoryItemType.erase,
        pageIndex: 0,
        strokes: <Stroke>[],
        images: <EditorImage>[],
      );
      expect(erase.type, EditorHistoryItemType.erase);
    });

    test('areaErase requires strokesAdded', () {
      expect(
        () => EditorHistoryItem(
          type: EditorHistoryItemType.areaErase,
          pageIndex: 0,
          strokes: <Stroke>[],
          images: <EditorImage>[],
        ),
        throwsAssertionError,
      );
    });
  });
}
