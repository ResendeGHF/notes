// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/editor/stroke_paint.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';
import 'package:saber/data/tools/_tool.dart';

Stroke _livePencil() {
  return Stroke(
    color: Colors.black,
    pressureEnabled: true,
    options: StrokeOptions(
      size: 8,
      thinning: 0.45,
      smoothing: 0.55,
      streamline: 0.45,
      simulatePressure: false,
      isComplete: false,
    ),
    pageIndex: 0,
    page: HasSize(EditorPage.defaultSize),
    toolId: ToolId.advancedPencil,
  )..paint = StrokePaint.pencilNoiseDefault().copyWith(
    pressureMapsToCoverage: true,
  );
}

void main() {
  test('already-drawn pencil grain does not reorient or change coverage', () {
    final stroke = _livePencil();

    for (var i = 0; i < 80; i++) {
      stroke.addPoint(
        Offset(20.0 + i * 4.0, 90.0 + (i % 5) * 0.3),
        0.35,
      );
    }

    final chunks = stroke.pencilDrawChunks;
    expect(chunks, isNotNull);
    expect(chunks, isNotEmpty);
    expect(stroke.debugFrozenPencilChunkCount, greaterThan(0));

    final frozenXY = stroke.debugFirstFrozenPencilSpineXY;
    final frozenPr = stroke.debugFirstFrozenPencilPressure;
    expect(frozenXY, isNotEmpty);
    expect(frozenPr, isNotEmpty);

    for (var i = 80; i < 160; i++) {
      stroke.addPoint(
        Offset(20.0 + i * 4.0, 40.0 + (i % 9) * 1.2),
        0.95,
      );
    }

    expect(stroke.pencilDrawChunks, isNotEmpty);
    expect(stroke.debugFirstFrozenPencilSpineXY, frozenXY);
    expect(stroke.debugFirstFrozenPencilPressure, frozenPr);
  });

  test('pen-up rebuilds a continuous committed pencil ribbon', () {
    final stroke = _livePencil();
    for (var i = 0; i < 90; i++) {
      stroke.addPoint(Offset(16.0 + i * 3.5, 70.0), 0.4 + (i % 4) * 0.1);
    }
    expect(stroke.pencilDrawChunks, isNotEmpty);
    expect(stroke.debugFrozenPencilChunkCount, greaterThan(0));

    stroke.finishLiveGeometry();
    expect(stroke.options.isComplete, isTrue);
    expect(stroke.pencilDrawChunks, isNotEmpty);
    expect(stroke.debugFrozenPencilChunkCount, 0);
  });

  test('mid-stroke frozen pencil chunks do not taper open joins', () {
    final stroke = _livePencil();
    stroke.setLodScale(0.5);
    for (var i = 0; i < 120; i++) {
      stroke.addPoint(
        Offset(10.0 + i * 3.0, 80.0 + math.sin(i * 0.2) * 12.0),
        0.45 + (i % 5) * 0.08,
      );
    }
    final chunks = stroke.pencilDrawChunks;
    expect(chunks, isNotNull);
    expect(chunks!.length, greaterThan(1));

    // Open joins keep non-empty coverage along the stroke; a tapered mid
    // chunk would collapse toward a near-empty bounds at the seam.
    for (final chunk in chunks) {
      final b = chunk.outline.getBounds();
      expect(b.width * b.height, greaterThan(4.0));
    }
  });
}
