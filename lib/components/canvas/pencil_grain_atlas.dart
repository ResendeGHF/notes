// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Tiling graphite / paper-tooth atlases for Advanced Pencil.
///
/// Skia/Impeller sample these as [ui.Image] samplers (the same hardware path
/// as Android `BitmapShader`): bilinear fetch instead of hashing 4 lattice
/// corners per pixel. The fragment shader still mixes, thresholds, and rotates
/// bristles in world space so the silhouette and grain character stay the same.
class PencilGrainAtlas {
  PencilGrainAtlas._();
  static final PencilGrainAtlas instance = PencilGrainAtlas._();

  /// Must match `kAtlasSize` in `shaders/pencil.frag`.
  static const int size = 256;

  ui.Image? _paper;
  ui.Image? _bristles;
  Future<void>? _loading;

  bool get isReady => _paper != null && _bristles != null;

  ui.Image get paper => _paper!;
  ui.Image get bristles => _bristles!;

  Future<void> ensure() {
    if (isReady) return Future.value();
    return _loading ??= _build();
  }

  Future<void> _build() async {
    try {
      _paper = await _encode(_raster(seedX: 0, seedY: 0));
      _bristles = await _encode(_raster(seedX: 19.1, seedY: 7.3));
    } finally {
      _loading = null;
    }
  }

  static Uint8List _raster({required double seedX, required double seedY}) {
    final bytes = Uint8List(size * size * 4);
    final period = size.toDouble();
    var i = 0;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final n = _valueNoise(
          x.toDouble(),
          y.toDouble(),
          period,
          seedX,
          seedY,
        ).clamp(0.0, 1.0);
        final v = (n * 255.0).round().clamp(0, 255);
        bytes[i++] = v;
        bytes[i++] = v;
        bytes[i++] = v;
        bytes[i++] = 255;
      }
    }
    return bytes;
  }

  static Future<ui.Image> _encode(Uint8List pixels) {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      size,
      size,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }

  static double _fract(double x) => x - x.floorToDouble();

  static double _mod(double a, double period) {
    var m = a % period;
    if (m < 0) m += period;
    return m;
  }

  /// Same hash as `pencil.frag` (Iq-style hash21).
  static double _hash21(double x, double y) {
    var p3x = _fract(x * 0.1031);
    var p3y = _fract(y * 0.1031);
    var p3z = _fract(x * 0.1031);
    final d =
        p3x * (p3y + 33.33) + p3y * (p3z + 33.33) + p3z * (p3x + 33.33);
    p3x += d;
    p3y += d;
    p3z += d;
    return _fract((p3x + p3y) * p3z);
  }

  static double _valueNoise(
    double x,
    double y,
    double period,
    double seedX,
    double seedY,
  ) {
    final px = x + seedX;
    final py = y + seedY;
    var ix = px.floorToDouble();
    var iy = py.floorToDouble();
    final fx = px - ix;
    final fy = py - iy;
    ix = _mod(ix, period);
    iy = _mod(iy, period);
    final fadeX = fx * fx * fx * (fx * (fx * 6.0 - 15.0) + 10.0);
    final fadeY = fy * fy * fy * (fy * (fy * 6.0 - 15.0) + 10.0);
    final a = _hash21(ix, iy);
    final b = _hash21(_mod(ix + 1, period), iy);
    final c = _hash21(ix, _mod(iy + 1, period));
    final d = _hash21(_mod(ix + 1, period), _mod(iy + 1, period));
    final u = a + (b - a) * fadeX;
    final v = c + (d - c) * fadeX;
    return u + (v - u) * fadeY;
  }
}
