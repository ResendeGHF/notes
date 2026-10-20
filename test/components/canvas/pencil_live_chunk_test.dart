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
    page: const HasSize(EditorPage.defaultSize),
    toolId: ToolId.pencil,
  )..paint = StrokePaint.pencilNoiseDefault();
}

void _drawWave(Stroke stroke, int from, int to) {
  for (var i = from; i < to; i++) {
    stroke.addPoint(
      Offset(20.0 + i * 1.7, 120.0 + math.sin(i * 0.18) * 45.0),
      0.5,
    );
  }
}

void main() {
  test('live pencil stages path-only chunks', () {
    final stroke = _livePencil();
    _drawWave(stroke, 0, 520);

    expect(stroke.hasLiveStaging, isTrue);
    expect(stroke.debugLiveChunkCount, greaterThan(0));

    final chunks = stroke.liveStagedChunks;
    expect(chunks, isNotEmpty);
    for (final chunk in chunks) {
      // The grain is drawn as one union path fill: outlines are all the
      // renderer needs, so chunks never bake a spine mesh.
      expect(chunk.path, isNotNull);
      expect(chunk.mesh, isNull);
      expect(chunk.bounds, isNotNull);
      expect(chunk.bounds!.isEmpty, isFalse);
    }

    // Adjacent chunks overlap (union fill shades the overlap once) so a butt
    // joint can never open a hairline crack mid-stroke.
    for (var i = 0; i + 1 < chunks.length; i++) {
      expect(chunks[i].bounds!.overlaps(chunks[i + 1].bounds!), isTrue);
    }
  });

  test('already-frozen pencil chunks do not reorient or change coverage', () {
    final stroke = _livePencil();
    _drawWave(stroke, 0, 520);
    expect(stroke.debugLiveChunkCount, greaterThan(0));

    final frozen = stroke.liveStagedChunks.first;
    final frozenPath = frozen.path;
    final frozenBounds = frozen.bounds;

    _drawWave(stroke, 520, 1040);

    final after = stroke.liveStagedChunks.first;
    // Same Path instance: frozen chunks are never rebuilt, so ink already on
    // screen cannot move or remap its grain.
    expect(identical(after.path, frozenPath), isTrue);
    expect(after.bounds, frozenBounds);
    expect(stroke.debugLiveChunkCount, greaterThan(1));
  });

  test('pen-up clears staging and rebuilds one committed outline', () {
    final stroke = _livePencil();
    _drawWave(stroke, 0, 420);
    expect(stroke.hasLiveStaging, isTrue);

    stroke.finishLiveGeometry();

    expect(stroke.options.isComplete, isTrue);
    expect(stroke.hasLiveStaging, isFalse);
    expect(stroke.debugLiveChunkCount, 0);
    final bounds = stroke.highQualityPath.getBounds();
    expect(bounds.isEmpty, isFalse);
    expect(bounds.left, lessThan(30));
    expect(bounds.right, greaterThan(20.0 + 419 * 1.7 - 30));
  });

  test('mid-stroke frozen pencil chunks keep non-empty coverage', () {
    final stroke = _livePencil();
    stroke.setLodScale(0.5);
    _drawWave(stroke, 0, 600);

    final chunks = stroke.liveStagedChunks;
    expect(chunks.length, greaterThan(1));

    // Open joins keep non-empty coverage along the stroke; a tapered mid
    // chunk would collapse toward a near-empty bounds at the seam.
    for (final chunk in chunks) {
      final b = chunk.path!.getBounds();
      expect(b.width * b.height, greaterThan(4.0));
    }
  });
}
