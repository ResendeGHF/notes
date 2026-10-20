// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

// Pencil grain coordinate contract and tip-size scaling.
//
// The graphite shader evaluates FlutterFragCoord() (local to the drawing
// command - page space for every pencil draw path) and carries no canvas
// transform: the field is anchored to the page, so panning, zooming, cached
// pictures, tile rasters and page bakes must all evaluate the identical grain.
// These tests render the same stroke through every one of those paths and
// compare pixel values, which is exactly how the pan-swim / live-vs-committed
// opacity bugs escaped before. Tip size must shape the deposit structure
// without pushing grain below the page pixel grid (sub-page-pixel content
// shimmers when the canvas shifts or when a cache is resampled).

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

const _w = 512;
const _h = 384;

Stroke _line({
  double size = 24,
  double y = 150,
  double x0 = 60,
  double x1 = 440,
  int samples = 80,
  bool complete = true,
}) {
  final stroke = Stroke(
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
  for (var i = 0; i <= samples; i++) {
    final t = i / samples;
    stroke.addPoint(Offset(x0 + (x1 - x0) * t, y), 0.5);
  }
  if (complete) stroke.finishLiveGeometry();
  return stroke;
}

CanvasPainter _painter(
  List<Stroke> strokes,
  double scale, {
  Stroke? current,
}) =>
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
    );

Future<Uint8List> _toBytes(ui.Image image) async =>
    (await image.toByteData())!.buffer.asUint8List();

/// Direct draw: uniforms and fragments are recorded and rasterized under the
/// same CTM (the live overlay path).
Future<Uint8List> _renderDirect(
  List<Stroke> strokes, {
  double scale = 1.0,
  double zoom = 1.0,
  Offset pan = Offset.zero,
  Stroke? current,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas =
      Canvas(recorder, const Rect.fromLTWH(0, 0, _w + 0.0, _h + 0.0));
  canvas.scale(zoom);
  canvas.translate(-pan.dx, -pan.dy);
  _painter(strokes, scale, current: current)
      .paint(canvas, const Size(_w + 0.0, _h + 0.0));
  final picture = recorder.endRecording();
  final image =
      await picture.toImage((_w * zoom).round(), (_h * zoom).round());
  final bytes = await _toBytes(image);
  picture.dispose();
  image.dispose();
  return bytes;
}

/// Records the painter at the page origin (identity CTM) and rasterizes the
/// picture under a new transform: this is how tile pictures are replayed
/// (pan) and how a device pixel ratio / bake resolution wraps a picture.
Future<Uint8List> _renderWrapped(
  List<Stroke> strokes, {
  double wrapScale = 1.0,
  Offset pan = Offset.zero,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas =
      Canvas(recorder, const Rect.fromLTWH(0, 0, _w + 0.0, _h + 0.0));
  _painter(strokes, 1.0).paint(canvas, const Size(_w + 0.0, _h + 0.0));
  final picture = recorder.endRecording();

  final recorder2 = ui.PictureRecorder();
  final canvas2 = Canvas(
    recorder2,
    Rect.fromLTWH(0, 0, _w * wrapScale, _h * wrapScale),
  );
  canvas2.scale(wrapScale);
  canvas2.translate(-pan.dx, -pan.dy);
  canvas2.drawPicture(picture);
  final wrapped = recorder2.endRecording();
  final image = await wrapped.toImage(
    (_w * wrapScale).round(),
    (_h * wrapScale).round(),
  );
  final bytes = await _toBytes(image);
  picture.dispose();
  wrapped.dispose();
  image.dispose();
  return bytes;
}

/// Tile pipeline: picture recorded in page coords with a tile clip, rasterized
/// at [rasterScale] through a scale+translate wrapper, then blitted back onto
/// the tile rect.
Future<Uint8List> _renderTileRaster(
  List<Stroke> strokes,
  Rect tileRect, {
  double rasterScale = 2.0,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, tileRect);
  canvas.clipRect(tileRect);
  _painter(strokes, 1.0).paint(canvas, const Size(_w + 0.0, _h + 0.0));
  final picture = recorder.endRecording();

  final rw = (tileRect.width * rasterScale).round();
  final rh = (tileRect.height * rasterScale).round();
  final recorder2 = ui.PictureRecorder();
  final canvas2 =
      Canvas(recorder2, Rect.fromLTWH(0, 0, rw.toDouble(), rh.toDouble()));
  canvas2.scale(rw / tileRect.width, rh / tileRect.height);
  canvas2.translate(-tileRect.left, -tileRect.top);
  canvas2.drawPicture(picture);
  final mapped = recorder2.endRecording();
  final raster = await mapped.toImage(rw, rh);

  final recorder3 = ui.PictureRecorder();
  final canvas3 =
      Canvas(recorder3, const Rect.fromLTWH(0, 0, _w + 0.0, _h + 0.0));
  canvas3.drawImageRect(
    raster,
    Rect.fromLTWH(0, 0, raster.width.toDouble(), raster.height.toDouble()),
    tileRect,
    Paint()..filterQuality = FilterQuality.medium,
  );
  final out = recorder3.endRecording();
  final image = await out.toImage(_w, _h);
  final bytes = await _toBytes(image);
  picture.dispose();
  mapped.dispose();
  raster.dispose();
  out.dispose();
  image.dispose();
  return bytes;
}

/// Page raster pipeline: bake at [res] through the painter (its uniforms bake
/// with the same logical scale), then blit at 1:1.
Future<Uint8List> _renderPageBake(List<Stroke> strokes, double res) async {
  final recorder = ui.PictureRecorder();
  final canvas =
      Canvas(recorder, Rect.fromLTWH(0, 0, _w * res, _h * res));
  canvas.scale(res);
  _painter(strokes, 1.0).paint(canvas, const Size(_w + 0.0, _h + 0.0));
  final picture = recorder.endRecording();
  final raster = await picture.toImage((_w * res).round(), (_h * res).round());

  final recorder2 = ui.PictureRecorder();
  final canvas2 =
      Canvas(recorder2, const Rect.fromLTWH(0, 0, _w + 0.0, _h + 0.0));
  canvas2.drawImageRect(
    raster,
    Rect.fromLTWH(0, 0, raster.width.toDouble(), raster.height.toDouble()),
    const Rect.fromLTWH(0, 0, _w + 0.0, _h + 0.0),
    Paint()..filterQuality = FilterQuality.medium,
  );
  final out = recorder2.endRecording();
  final image = await out.toImage(_w, _h);
  final bytes = await _toBytes(image);
  picture.dispose();
  raster.dispose();
  out.dispose();
  image.dispose();
  return bytes;
}

int _alphaAt(Uint8List rgba, int w, int x, int y) => rgba[(y * w + x) * 4 + 3];

/// Differences over [r] (page coordinates). [b] was drawn with the canvas
/// translated by -[pan] and scaled by [zoom].
({double mean, int differing, int maxDelta}) _diff(
  Uint8List a,
  Uint8List b,
  Rect r, {
  Offset pan = Offset.zero,
  double zoom = 1.0,
}) {
  final aWidth = (_w * zoom).round();
  final bWidth = (_w * zoom).round();
  final bHeight = (_h * zoom).round();
  var sum = 0.0;
  var n = 0;
  var differing = 0;
  var maxDelta = 0;
  for (var py = (r.top * zoom).round(); py < (r.bottom * zoom).round(); py++) {
    for (var px = (r.left * zoom).round();
        px < (r.right * zoom).round();
        px++) {
      final bx = (((px / zoom) - pan.dx) * zoom).round();
      final by = (((py / zoom) - pan.dy) * zoom).round();
      if (bx < 0 || by < 0 || bx >= bWidth || by >= bHeight) continue;
      final d = (_alphaAt(a, aWidth, px, py) - _alphaAt(b, bWidth, bx, by))
          .abs();
      sum += d;
      n++;
      if (d > 2) differing++;
      if (d > maxDelta) maxDelta = d;
    }
  }
  return (mean: sum / math.max(n, 1), differing: differing, maxDelta: maxDelta);
}

/// Downscales a 2x render to 1x with a 2x2 box filter (DPR emulation).
Uint8List _downsample2(Uint8List b) {
  final out = Uint8List(_w * _h * 4);
  for (var y = 0; y < _h; y++) {
    for (var x = 0; x < _w; x++) {
      var sum = 0;
      for (var dy = 0; dy < 2; dy++) {
        for (var dx = 0; dx < 2; dx++) {
          sum += b[(((y * 2 + dy) * _w * 2) + (x * 2 + dx)) * 4 + 3];
        }
      }
      final v = (sum / 4).round();
      final i = (y * _w + x) * 4;
      out[i] = v;
      out[i + 1] = v;
      out[i + 2] = v;
      out[i + 3] = v;
    }
  }
  return out;
}

/// Mean alpha profile along the stroke and its autocorrelation at [lag]:
/// thin tips must stay uncorrelated (fine speckle), broad tips keep the tonal
/// drift.
double _acfAlong(List<double> profile, int lag) {
  var mean = 0.0;
  for (final v in profile) {
    mean += v;
  }
  mean /= profile.length;
  var num = 0.0;
  var den = 0.0;
  for (var i = 0; i < profile.length; i++) {
    den += (profile[i] - mean) * (profile[i] - mean);
    if (i < profile.length - lag) {
      num += (profile[i] - mean) * (profile[i + lag] - mean);
    }
  }
  return num / den;
}

void main() {
  setUpAll(() async {
    await PencilShader.init();
    expect(PencilShader.isReady, isTrue);
  });

  test('tip size shapes deposit structure, not the sampling frequency',
      () {
    // The default config must sample the atlas 1:1 (1 texel per page pixel):
    // finer sampling would put grain below the device grid and shimmer on
    // fractional pan / cache resampling.
    expect(
      PencilShader.grainTilePagePxFor(StrokePaint.pencilNoiseDefault()),
      closeTo(256.0, 1e-6),
    );
    expect(PencilShader.tipMixFor(10), 0.0);
    expect(PencilShader.tipMixFor(12), 0.0);
    expect(PencilShader.tipMixFor(100), 1.0);
    expect(PencilShader.tipMixFor(72), 1.0);
    expect(PencilShader.tipMixFor(30), greaterThan(0.0));
    expect(PencilShader.tipMixFor(30), lessThan(1.0));
  });

  test('panning does not move the grain', () async {
    const rect = Rect.fromLTWH(70, 138, 180, 24);
    final a = await _renderDirect([_line()]);
    final b = await _renderDirect([_line()], pan: const Offset(40, 25));
    final d = _diff(a, b, rect, pan: const Offset(40, 25));
    expect(d.differing, 0, reason: 'maxDelta=${d.maxDelta}');
  });

  test('magnified views stay anchored', () async {
    const zoom = 2.5;
    const rect = Rect.fromLTWH(70, 138, 180, 24);
    final a = await _renderDirect([_line()], zoom: zoom);
    // Integral device-pixel offset at 2.5x: the identical sampling grid, so
    // the grain must match exactly (a transform-dependent mapping shifts it).
    final b = await _renderDirect(
      [_line()],
      zoom: zoom,
      pan: const Offset(40, 24),
    );
    final d = _diff(a, b, rect, pan: const Offset(40, 24), zoom: zoom);
    expect(d.differing, 0, reason: 'maxDelta=${d.maxDelta}');
  });

  test('picture replay under a new transform matches direct draws', () async {
    const rect = Rect.fromLTWH(70, 138, 180, 24);
    final a = await _renderDirect([_line()]);
    final b = await _renderWrapped([_line()], pan: const Offset(40, 25));
    final d = _diff(a, b, rect, pan: const Offset(40, 25));
    expect(d.differing, 0, reason: 'maxDelta=${d.maxDelta}');
  });

  test('tile rasters at another resolution match direct draws', () async {
    const tileRect = Rect.fromLTWH(0, 64, 256, 192);
    const rect = Rect.fromLTWH(70, 138, 170, 24);
    final a = await _renderDirect([_line()]);
    final b = await _renderTileRaster([_line()], tileRect);
    final d = _diff(a, b, rect);
    expect(d.mean, lessThan(1.0), reason: 'maxDelta=${d.maxDelta}');
    expect(d.maxDelta, lessThanOrEqualTo(12));
  });

  test('page raster bakes match direct draws', () async {
    const rect = Rect.fromLTWH(70, 138, 180, 24);
    final a = await _renderDirect([_line()]);
    final b = await _renderPageBake([_line()], 2.0);
    final d = _diff(a, b, rect);
    expect(d.mean, lessThan(1.0), reason: 'maxDelta=${d.maxDelta}');
    expect(d.maxDelta, lessThanOrEqualTo(12));
  });

  test('device pixel ratio resampling matches direct draws', () async {
    const rect = Rect.fromLTWH(70, 138, 180, 24);
    final a = await _renderDirect([_line()]);
    final b = await _renderWrapped([_line()], wrapScale: 2.0);
    final d = _diff(a, _downsample2(b), rect);
    expect(d.mean, lessThan(1.0), reason: 'maxDelta=${d.maxDelta}');
    expect(d.maxDelta, lessThanOrEqualTo(12));
  });

  test('live staged ink matches the committed stroke under a pan', () async {
    const rect = Rect.fromLTWH(40, 120, 440, 60);
    final live = _line(samples: 300, complete: false);
    expect(live.hasLiveStaging, isTrue);
    const pan = Offset(37, 21);

    final livePixels = await _renderDirect(const [], current: live, pan: pan);
    live.finishLiveGeometry();
    final committedPixels = await _renderDirect([live], pan: pan);
    // Both renders are panned identically: compare at the same pixels.
    final d = _diff(livePixels, committedPixels, rect);
    // Same budget as the flat parity test: outlines may differ by a fraction
    // of a pixel at isolated silhouette pixels; the field must not.
    expect(d.differing, lessThanOrEqualTo(12), reason: 'maxDelta=${d.maxDelta}');
    expect(d.maxDelta, lessThanOrEqualTo(40));
  });

  test('grain structure scales with the selected tip size', () async {
    Future<List<double>> profileFor(double size) async {
      final bytes = await _renderDirect([_line(size: size, y: 150)]);
      return [
        for (var x = 80; x < 420; x++)
          () {
            var sum = 0.0;
            var n = 0;
            for (var y = (150 - size * 0.3).round();
                y < (150 + size * 0.3).round();
                y++) {
              sum += _alphaAt(bytes, _w, x, y);
              n++;
            }
            return sum / n;
          }(),
      ];
    }

    final thin = await profileFor(10);
    final broad = await profileFor(100);

    double meanOf(List<double> p) => p.reduce((a, b) => a + b) / p.length;

    // Tone stays in the same graphite band regardless of size.
    for (final p in [thin, broad]) {
      expect(meanOf(p), inInclusiveRange(85.0, 125.0));
    }

    // A 10 px tip must read as fine speckle: no tonal drift at a 4 px scale.
    // A 100 px tip keeps the lumpy paper/contact drift.
    final thinAcf = _acfAlong(thin, 4);
    final broadAcf = _acfAlong(broad, 4);
    expect(thinAcf, lessThan(0.20), reason: 'thin acf4=$thinAcf');
    expect(broadAcf, greaterThan(0.30), reason: 'broad acf4=$broadAcf');
    expect(
      broadAcf - thinAcf,
      greaterThan(0.20),
      reason: 'thin=$thinAcf broad=$broadAcf',
    );
  });
}
