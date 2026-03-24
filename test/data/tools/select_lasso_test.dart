import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/select.dart';
import '../../helpers/test_stroke_factory.dart';

void main() {
  group('Select tool (lasso)', () {
    tearDown(() {
      Select.currentSelect.unselect();
    });

    test('onDragStart/onDragUpdate/onDragEnd closes path and marks done', () {
      final s = Select.currentSelect;
      s.onDragStart(Offset.zero, 0);
      s.onDragUpdate(const Offset(40, 0));
      s.onDragUpdate(const Offset(40, 40));
      s.onDragEnd(<Stroke>[], <EditorImage>[]);

      expect(s.doneSelecting, isTrue);
      expect(s.selectResult.pageIndex, 0);
    });

    test('getDominantStrokeColor weights by stroke length', () {
      final s = Select.currentSelect;
      final a = testPolylineStroke(
        toolId: ToolId.ballpointPen,
        y: 10,
        x0: 0,
        x1: 50,
        points: 10,
      );
      a.color = const Color(0xFFFF0000);
      final b = testPolylineStroke(
        toolId: ToolId.ballpointPen,
        y: 20,
        x0: 0,
        x1: 200,
        points: 40,
      );
      b.color = const Color(0xFF0000FF);

      s.selectResult = s.selectResult.copyWith(strokes: [a, b]);
      s.doneSelecting = true;

      expect(s.getDominantStrokeColor(), const Color(0xFF0000FF));
    });
  });
}
