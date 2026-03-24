import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/editor/editor_history.dart';

void main() {
  group('EditorHistory (undo / redo)', () {
    test('recordChange then undo / redo', () {
      final h = EditorHistory();
      final item = EditorHistoryItem(
        type: EditorHistoryItemType.draw,
        pageIndex: 0,
        strokes: <Stroke>[],
        images: <EditorImage>[],
      );
      h.recordChange(item);
      expect(h.canUndo, isTrue);
      expect(h.canRedo, isFalse);

      final undone = h.undo();
      expect(undone.type, EditorHistoryItemType.draw);
      expect(h.canUndo, isFalse);
      // Editor sets [canRedo] after undo so redo is offered.
      expect(h.canRedo, isFalse);
      h.canRedo = true;
      expect(h.canRedo, isTrue);
      final redone = h.redo();
      expect(redone.type, EditorHistoryItemType.draw);
      expect(h.canUndo, isTrue);
    });

    test('maxHistoryLength trims oldest', () {
      final h = EditorHistory();
      for (var i = 0; i < EditorHistory.maxHistoryLength + 5; i++) {
        h.recordChange(
          EditorHistoryItem(
            type: EditorHistoryItemType.draw,
            pageIndex: 0,
            strokes: <Stroke>[],
            images: <EditorImage>[],
          ),
        );
      }
      var undos = 0;
      while (h.canUndo) {
        h.undo();
        undos++;
      }
      expect(undos, EditorHistory.maxHistoryLength);
    });

    test('undo throws when empty', () {
      final h = EditorHistory();
      expect(() => h.undo(), throwsException);
    });
  });
}
