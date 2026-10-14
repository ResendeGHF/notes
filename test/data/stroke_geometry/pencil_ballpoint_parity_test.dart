// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/editor/stroke_paint.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/stroke_geometry/stroke_options.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/pen.dart';

/// The pencil is strictly a ballpoint pen with a graphite-grain shader:
/// identical samples must produce identical geometry, differing only in
/// paint (and tool id).
void main() {
  setUp(() {
    stows.strokeStabilization.value = false;
  });
  tearDown(() {
    stows.strokeStabilization.value = true;
  });

  Stroke strokeFor(ToolId id) => Stroke(
        color: Colors.black,
        pressureEnabled: false,
        options: StrokeOptions(size: 4, simulatePressure: false),
        pageIndex: 0,
        page: HasSize(EditorPage.defaultSize),
        toolId: id,
        brushOptions: null,
      );

  void drawSquiggle(Stroke stroke) {
    for (var i = 0; i <= 15; i++) {
      stroke.addPoint(
        Offset(i * 9.0, (i.isEven ? 1.0 : -1.0) * (i % 5) * 3.0),
        0.7,
        Duration(milliseconds: i * 8),
      );
    }
    stroke.finishLiveGeometry();
  }

  test('pencil polygon matches ballpoint polygon', () {
    final ballpoint = strokeFor(ToolId.ballpointPen);
    final pencil = strokeFor(ToolId.pencil);
    drawSquiggle(ballpoint);
    drawSquiggle(pencil);

    final a = ballpoint.highQualityPolygon;
    final b = pencil.highQualityPolygon;
    expect(b.length, a.length);
    for (var i = 0; i < a.length; i++) {
      expect(b[i].dx, closeTo(a[i].dx, 1e-9), reason: 'x[$i]');
      expect(b[i].dy, closeTo(a[i].dy, 1e-9), reason: 'y[$i]');
    }

    final ab = ballpoint.highQualityPath.getBounds();
    final pb = pencil.highQualityPath.getBounds();
    expect(pb.left, closeTo(ab.left, 1e-9));
    expect(pb.top, closeTo(ab.top, 1e-9));
    expect(pb.right, closeTo(ab.right, 1e-9));
    expect(pb.bottom, closeTo(ab.bottom, 1e-9));
  });

  test('pencil mesh matches ballpoint mesh (same caps)', () {
    final ballpoint = strokeFor(ToolId.ballpointPen);
    final pencil = strokeFor(ToolId.pencil);
    pencil.paint = StrokePaint.pencilNoiseDefault();
    drawSquiggle(ballpoint);
    drawSquiggle(pencil);

    final bp = ballpoint.getRawPositions();
    final pp = pencil.getRawPositions();
    expect(pp.length, bp.length);
    for (var i = 0; i < bp.length; i++) {
      expect(pp[i], closeTo(bp[i], 1e-9), reason: 'pos[$i]');
    }
    final bi = ballpoint.getRawIndices();
    final pi = pencil.getRawIndices();
    expect(pi.length, bi.length);
    for (var i = 0; i < bi.length; i++) {
      expect(pi[i], bi[i], reason: 'index[$i]');
    }
  });

  test('pencil differs from ballpoint only in paint and tool id', () {
    final pen = Pen.pencil();
    final ballpoint = Pen.ballpointPen();
    expect(pen.pressureEnabled, ballpoint.pressureEnabled);
    expect(pen.sizeMin, ballpoint.sizeMin);
    expect(pen.sizeMax, ballpoint.sizeMax);
    expect(pen.sizeStep, ballpoint.sizeStep);
    expect(pen.paint.usesPencilNoise, isTrue);
    expect(ballpoint.paint.isSolid, isTrue);
  });

  test('pencil stroke keeps noise paint through json', () {
    final stroke = strokeFor(ToolId.pencil);
    stroke.paint = StrokePaint.pencilNoiseDefault();
    drawSquiggle(stroke);
    final json = stroke.toJson();
    expect(json['ty'], ToolId.pencil.id);
    expect(json['spi'], isA<Map>());
    final restored = Stroke.fromJson(
      Map<String, dynamic>.from(
        json.map((k, v) => MapEntry(k.toString(), v)),
      ),
      fileVersion: 99,
      pageIndex: 0,
      page: HasSize(EditorPage.defaultSize),
    );
    expect(restored.toolId, ToolId.pencil);
    expect(restored.paint.usesPencilNoise, isTrue);
  });
}
