// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

// Pencil grain is painted as ONE union path fill (live and committed). These
// tests pin the two properties that design exists for:
//   * overlapping geometry shades each pixel exactly once - no additive
//     darkening at retraces, loops or chunk overlaps;
//   * the staged live render is pixel-identical to the committed render.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_canvas_painter.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/pencil_shader.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/editor/stroke_paint.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';
import 'package:saber/data/tools/_tool.dart';

const double _w = 500;
const double _h = 300;

Stroke _pencilStroke({required bool complete, double size = 12}) {
  return Stroke(
    color: Colors.black,
    pressureEnabled: false,
    options: StrokeOptions(
      size: size,
      simulatePressure: false,
      isComplete: complete,
    ),
    pageIndex: 0,
    page: const HasSize(EditorPage.defaultSize),
    toolId: ToolId.pencil,
  )..paint = StrokePaint.pencilNoiseDefault();
}

/// Retraces the same line twice (perfectly overlapping arms).
Stroke _retraceStroke() {
  final stroke = _pencilStroke(complete: true);
  for (var i = 0; i <= 60; i++) {
    stroke.addPoint(Offset(100 + i * 5, 150), 0.5);
  }
  for (var i = 1; i <= 60; i++) {
    stroke.addPoint(Offset(400 - i * 5, 150), 0.5);
  }
  stroke.finishLiveGeometry();
  return stroke;
}

/// Single pass over the same line with the same sample spacing.
Stroke _singlePassStroke() {
  final stroke = _pencilStroke(complete: true);
  for (var i = 0; i <= 60; i++) {
    stroke.addPoint(Offset(100 + i * 5, 150), 0.5);
  }
  stroke.finishLiveGeometry();
  return stroke;
}

/// Long wavy stroke; [complete] false keeps it open so live staging engages.
Stroke _wavyStroke({required bool complete, int samples = 520}) {
  final stroke = _pencilStroke(complete: complete);
  for (var i = 0; i < samples; i++) {
    final t = i * 0.16;
    stroke.addPoint(
      Offset(40 + i * 0.8, 150 + math.sin(t) * 60 + math.sin(t * 0.27) * 25),
      0.5 + (i % 4) * 0.05,
    );
  }
  if (complete) stroke.finishLiveGeometry();
  return stroke;
}

Future<Uint8List> _render(
  List<Stroke> strokes, {
  Stroke? current,
  bool opaqueBackground = false,
  double scale = 1.0,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, _w, _h));
  if (opaqueBackground) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _w, _h),
      Paint()..color = Colors.white,
    );
  }
  canvas.save();
  canvas.scale(scale);
  CanvasPainter(
    strokes: strokes,
    laserStrokes: const [],
    currentStroke: current,
    currentSelection: null,
    primaryColor: Colors.blue,
    page: EditorPage(),
    showPageIndicator: false,
    pageIndex: 0,
    totalPages: 1,
    currentScale: scale,
    defaultTextStyle: const TextStyle(),
  ).paint(canvas, Size(_w / scale, _h / scale));
  canvas.restore();
  final picture = recorder.endRecording();
  final image = await picture.toImage(_w.toInt(), _h.toInt());
  final bytes = (await image.toByteData())!.buffer.asUint8List();
  picture.dispose();
  image.dispose();
  return bytes;
}

int _alpha(Uint8List rgba, int x, int y) => rgba[(y * _w.toInt() + x) * 4 + 3];

void main() {
  setUpAll(() async {
    await PencilShader.init();
    expect(PencilShader.isReady, isTrue);
  });

  // Rendered onto a transparent canvas: the alpha channel is exactly the
  // grain the shader deposited (a white backdrop would saturate it to 255).
  test('retraced pencil ink shades once (no additive darkening)', () async {
    final single = await _render([_singlePassStroke()]);
    final retrace = await _render([_retraceStroke()]);

    // Interior band away from caps and the turnaround bulb: both strokes cover
    // the exact same pixels, with the same page-anchored grain.
    var checked = 0;
    var maxDelta = 0;
    for (var x = 150; x <= 380; x++) {
      for (var y = 146; y <= 154; y++) {
        final a = _alpha(single, x, y);
        final b = _alpha(retrace, x, y);
        if (a > 8) {
          checked++;
          final d = (a - b).abs();
          if (d > maxDelta) maxDelta = d;
        }
      }
    }
    expect(checked, greaterThan(1000));
    // A compositing double-draw would land near 1.5-2x the single-pass alpha;
    // a single union fill matches it within quantization noise.
    expect(maxDelta, lessThanOrEqualTo(3));
  });

  test('staged live pencil is pixel-identical to the committed stroke', () async {
    final live = _wavyStroke(complete: false);
    // Staging must actually be engaged, otherwise this proves nothing.
    expect(live.hasLiveStaging, isTrue);
    expect(live.debugLiveChunkCount, greaterThan(0));

    final livePixels = await _render(const [], current: live);

    // Pen-up on the SAME stroke: identical points, committed pipeline.
    live.finishLiveGeometry();
    expect(live.options.isComplete, isTrue);
    expect(live.hasLiveStaging, isFalse);
    final committedPixels = await _render([live]);

    var differing = 0;
    var maxDelta = 0;
    for (var i = 3; i < livePixels.length; i += 4) {
      final d = (livePixels[i] - committedPixels[i]).abs();
      if (d > 2) {
        differing++;
        if (d > maxDelta) maxDelta = d;
      }
    }
    // The grain field itself agrees exactly (a shifted field or a double
    // composite would light up thousands of pixels with large deltas). Outlines
    // can still differ by a fraction of a pixel at a handful of silhouette
    // pixels - the live union smooths a partial tail while the committed
    // polygon smooths the final point set - so allow a tiny budget there.
    expect(differing, lessThanOrEqualTo(12), reason: 'maxAlphaDelta=$maxDelta');
    expect(maxDelta, lessThanOrEqualTo(40), reason: '$differing px differ');
  });

  test('live and committed agree at a magnified zoom', () async {
    // The grain is page-anchored: zoom must not change the field, so live and
    // committed stay identical under magnification as well (this is the case
    // where a transform-derived sampling error would show up as a scale
    // mismatch between the two stages).
    const scale = 2.5;
    final live = _wavyStroke(complete: false, samples: 340);
    expect(live.hasLiveStaging, isTrue);

    final livePixels = await _render(const [], current: live, scale: scale);
    live.finishLiveGeometry();
    final committedPixels = await _render([live], scale: scale);

    var differing = 0;
    var coverage = 0;
    var maxDelta = 0;
    for (var i = 3; i < livePixels.length; i += 4) {
      if (livePixels[i] > 8 || committedPixels[i] > 8) coverage++;
      final d = (livePixels[i] - committedPixels[i]).abs();
      if (d > 2) {
        differing++;
        if (d > maxDelta) maxDelta = d;
      }
    }
    expect(coverage, greaterThan(5000));
    // Same sub-pixel outline budget as the flat-parity test above.
    expect(differing, lessThanOrEqualTo(12), reason: 'maxAlphaDelta=$maxDelta');
    expect(maxDelta, lessThanOrEqualTo(40), reason: '$differing px differ');
  });

  test('grain alpha stays inside the configured opacity band', () async {
    // A full-viewport union fill samples the whole page-anchored grain field,
    // so its peak is the darkest single shade the shader can deposit at this
    // zoom. Any stroke pixel is a subset of that field: overlapping geometry
    // that composited twice (or any geometry overlap bug) would push the
    // stroke's peak above it (a second srcOver of the same grain lands ~1.5x
    // higher, far outside the field's own range).
    final fieldPeak = _maxAlpha(await _renderFillRect());
    final bytes = await _render([_retraceStroke()]);
    final strokePeak = _maxAlpha(bytes);

    expect(fieldPeak, greaterThan(60));
    expect(
      strokePeak,
      lessThanOrEqualTo(fieldPeak),
      reason: 'stroke peak $strokePeak vs single-shade field peak $fieldPeak',
    );
  });
}

int _maxAlpha(Uint8List bytes) {
  var maxA = 0;
  for (var i = 3; i < bytes.length; i += 4) {
    if (bytes[i] > maxA) maxA = bytes[i];
  }
  return maxA;
}

/// One union-path fill of the whole viewport through the pencil kernel.
Future<Uint8List> _renderFillRect() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, _w, _h));
  final shader = PencilShader.create();
  expect(shader, isNotNull);
  PencilShader.paintGrainPath(
    canvas: canvas,
    shader: shader!,
    color: Colors.black,
    cfg: StrokePaint.pencilNoiseDefault(),
    outline: Path()..addRect(const Rect.fromLTWH(0, 0, _w, _h)),
    currentScale: 1.0,
    visibleCount: 1,
    strokeSize: 12,
  );
  shader.dispose();
  final picture = recorder.endRecording();
  final image = await picture.toImage(_w.toInt(), _h.toInt());
  final bytes = (await image.toByteData())!.buffer.asUint8List();
  picture.dispose();
  image.dispose();
  return bytes;
}
