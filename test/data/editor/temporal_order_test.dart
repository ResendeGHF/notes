// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

// Temporal z-order: newer strokes append on top regardless of pen/color,
// batches preserve order across colors, and undo/redo restore positions.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/inner_canvas.dart'
    show buildOrderedMeshBatches;
import 'package:saber/data/editor/editor_history.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/_tool.dart';

import '../../helpers/test_stroke_factory.dart';

Stroke _ink(Color color, ToolId tool) {
  final s = testPolylineStroke(toolId: tool);
  s.color = color;
  return s;
}

void main() {
  group('temporal insert', () {
    test('insertion appends regardless of pen and color', () {
      final page = EditorPage();
      final red = _ink(const Color(0xFFFF0000), ToolId.ballpointPen);
      final blue = _ink(const Color(0xFF0000FF), ToolId.fountainPen);
      final red2 = _ink(const Color(0xFFFF0000), ToolId.ballpointPen);
      page.insertStroke(red);
      page.insertStroke(blue);
      page.insertStroke(red2);
      final order = page.allStrokesInDrawOrder.toList();
      expect(order, [red, blue, red2]);
    });

    test('insertStrokeAt restores exact slots', () {
      final page = EditorPage();
      final a = _ink(Colors.black, ToolId.ballpointPen);
      final b = _ink(Colors.black, ToolId.ballpointPen);
      final c = _ink(Colors.black, ToolId.ballpointPen);
      page.insertStroke(a);
      page.insertStroke(b);
      page.insertStroke(c);
      page.removeStrokeFromAnyLayer(b);
      expect(page.allStrokesInDrawOrder.toList(), [a, c]);
      page.layerAt(0).insertStrokeAt(b, 1);
      expect(page.allStrokesInDrawOrder.toList(), [a, b, c]);
    });

    test('restoreStrokesAt reproduces multi-remove exactly', () {
      final page = EditorPage();
      final strokes = [
        for (var i = 0; i < 6; i++)
          _ink(Colors.black, ToolId.ballpointPen),
      ];
      for (final s in strokes) {
        page.insertStroke(s);
      }
      final spots = [
        for (final s in [strokes[1], strokes[3], strokes[4]])
          page.drawOrderSpotOf(s)!,
      ];
      expect(spots, [(0, 1), (0, 3), (0, 4)]);
      page.removeStrokeFromAnyLayer(strokes[1]);
      page.removeStrokeFromAnyLayer(strokes[3]);
      page.removeStrokeFromAnyLayer(strokes[4]);
      expect(page.allStrokesInDrawOrder.length, 3);
      page.restoreStrokesAt([strokes[1], strokes[3], strokes[4]], spots);
      expect(page.allStrokesInDrawOrder.toList(), strokes);
    });
  });

  group('ordered mesh batches', () {
    test('alternating colors split into ordered runs', () {
      final red1 = _ink(const Color(0xFFFF0000), ToolId.ballpointPen);
      final blue1 = _ink(const Color(0xFF0000FF), ToolId.ballpointPen);
      final red2 = _ink(const Color(0xFFFF0000), ToolId.ballpointPen);
      final ordered =
          buildOrderedMeshBatches([red1, blue1, red2], 1.0)!;
      expect(ordered.runs, hasLength(3));
      expect(ordered.runs[0].first, same(red1));
      expect(ordered.runs[1].first, same(blue1));
      expect(ordered.runs[2].first, same(red2));
      // Every member resolves to its run (culled subsets still trigger).
      expect(ordered.draw[red1], same(ordered.runs[0]));
      expect(ordered.draw[blue1], same(ordered.runs[1]));
      expect(ordered.draw[red2], same(ordered.runs[2]));
    });

    test('consecutive same-color strokes merge into one run', () {
      final red1 = _ink(const Color(0xFFFF0000), ToolId.ballpointPen);
      final red2 = _ink(const Color(0xFFFF0000), ToolId.ballpointPen);
      final blue = _ink(const Color(0xFF0000FF), ToolId.ballpointPen);
      final ordered = buildOrderedMeshBatches([red1, red2, blue], 1.0)!;
      expect(ordered.runs, hasLength(2));
      expect(ordered.runs[0].first, same(red1));
      expect(ordered.draw[red2], same(ordered.runs[0]));
      expect(ordered.runs[1].first, same(blue));
    });

    test('no batchable strokes yields null (individual paint)', () {
      final shape = _ink(Colors.black, ToolId.ballpointPen);
      // Force non-batchable via highlighter tool id semantics.
      final hi = testPolylineStroke(toolId: ToolId.highlighter);
      expect(buildOrderedMeshBatches([hi], 1.0), isNull);
      expect(shape.canBatchSolidMesh, isTrue);
    });
  });

  group('history spots', () {
    test('erase item round-trips positions', () {
      final item = EditorHistoryItem(
        type: EditorHistoryItemType.erase,
        pageIndex: 0,
        strokes: [],
        images: const [],
        strokeSpots: const [(0, 2), (1, 0)],
      );
      expect(item.strokeSpots, [(0, 2), (1, 0)]);
      final moved = item.copyWith(pageIndex: 1);
      expect(moved.strokeSpots, [(0, 2), (1, 0)]);
      expect(moved.pageIndex, 1);
    });

    test('undo-erase simulation restores exact order', () {
      final page = EditorPage();
      final strokes = [
        for (var i = 0; i < 5; i++)
          _ink(Colors.black, ToolId.ballpointPen),
      ];
      for (final s in strokes) {
        page.insertStroke(s);
      }
      // Erase middle two (as the eraser would), capturing spots first.
      final erased = [strokes[1], strokes[3]];
      final spots = [
        for (final s in erased) page.drawOrderSpotOf(s)!,
      ];
      expect(spots, [(0, 1), (0, 3)]);
      page.removeStrokeFromAnyLayer(strokes[1]);
      page.removeStrokeFromAnyLayer(strokes[3]);
      expect(page.allStrokesInDrawOrder.toList(),
          [strokes[0], strokes[2], strokes[4]]);
      // Undo: restore at recorded spots.
      page.restoreStrokesAt(erased, spots);
      expect(page.allStrokesInDrawOrder.toList(), strokes);
    });

    test('changeStrokeType-style replace keeps order', () {
      final page = EditorPage();
      final a = _ink(Colors.black, ToolId.ballpointPen);
      final b = _ink(Colors.black, ToolId.fountainPen);
      final c = _ink(Colors.black, ToolId.ballpointPen);
      page.insertStroke(a);
      page.insertStroke(b);
      page.insertStroke(c);
      final replacement = _ink(Colors.black, ToolId.ballpointPen);
      page.replaceStroke(b, replacement);
      expect(page.allStrokesInDrawOrder.toList(), [a, replacement, c]);
      page.replaceStroke(replacement, b);
      expect(page.allStrokesInDrawOrder.toList(), [a, b, c]);
    });
  });
}
