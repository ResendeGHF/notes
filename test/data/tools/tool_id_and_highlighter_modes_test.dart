import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/highlighter.dart';

void main() {
  group('ToolId.parsePenType (prefs / file compatibility)', () {
    test('parses known pen ids', () {
      expect(ToolId.parsePenType('fountainPen', fallback: ToolId.ballpointPen),
          ToolId.fountainPen);
      expect(ToolId.parsePenType('ballpointPen', fallback: ToolId.fountainPen),
          ToolId.ballpointPen);
      expect(ToolId.parsePenType('advancedPen', fallback: ToolId.ballpointPen),
          ToolId.advancedPen);
      expect(ToolId.parsePenType('Highlighter', fallback: ToolId.ballpointPen),
          ToolId.highlighter);
    });

    test('legacy pencil maps to ballpoint', () {
      expect(ToolId.parsePenType('pencilPen', fallback: ToolId.fountainPen),
          ToolId.ballpointPen);
      expect(ToolId.parsePenType('Pencil', fallback: ToolId.fountainPen),
          ToolId.ballpointPen);
    });

    test('null uses fallback', () {
      expect(ToolId.parsePenType(null, fallback: ToolId.calligraphyPen),
          ToolId.calligraphyPen);
    });
  });

  group('Highlighter modes (toolbar card toggles)', () {
    tearDown(() {
      Highlighter.straightLine.value = false;
    });

    test('straightLine notifier toggles', () {
      expect(Highlighter.straightLine.value, isFalse);
      Highlighter.straightLine.value = true;
      expect(Highlighter.straightLine.value, isTrue);
      Highlighter.straightLine.value = false;
      expect(Highlighter.straightLine.value, isFalse);
    });

    test('alpha is fixed at 1 for color pipeline', () {
      expect(Highlighter.alpha, 1.0);
    });
  });
}
