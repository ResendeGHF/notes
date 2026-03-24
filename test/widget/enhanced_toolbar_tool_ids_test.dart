import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/laser_pointer.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/data/tools/shape_tool.dart';

/// Regression guard: toolbar rows expect these tool singletons / ids to exist.
void main() {
  group('Enhanced toolbar tool registry', () {
    test('core tool ids cover pens, shapes, eraser, select, laser, text', () {
      expect(ToolId.values, contains(ToolId.fountainPen));
      expect(ToolId.values, contains(ToolId.ballpointPen));
      expect(ToolId.values, contains(ToolId.calligraphyPen));
      expect(ToolId.values, contains(ToolId.shapePen));
      expect(ToolId.values, contains(ToolId.verticalSpacePen));
      expect(ToolId.values, contains(ToolId.horizontalSpacePen));
      expect(ToolId.values, contains(ToolId.advancedPen));
      expect(ToolId.values, contains(ToolId.highlighter));
      expect(ToolId.values, contains(ToolId.eraser));
      expect(ToolId.values, contains(ToolId.select));
      expect(ToolId.values, contains(ToolId.laserPointer));
      expect(ToolId.values, contains(ToolId.textEditing));
      expect(ToolId.values, contains(ToolId.shapeTool));
    });

    test('singleton tools expose stable toolId', () {
      expect(Eraser.currentEraser.toolId, ToolId.eraser);
      expect(LaserPointer.currentLaserPointer.toolId, ToolId.laserPointer);
      expect(ShapeTool.currentShapeTool.toolId, ToolId.shapeTool);
      expect(Select.currentSelect.toolId, ToolId.select);
    });
  });
}
