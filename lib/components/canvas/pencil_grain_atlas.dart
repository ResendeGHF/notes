// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Seamless graphite / paper-tooth noise atlases for the pencil shader.
///
/// Two 256×256 tiles, each packing three independent noise fields in RGB, so
/// one hardware texture fetch serves a whole octave band [1]. The fields are
/// built on a wrapped value-noise lattice (periods divide the texture size),
/// which makes [ui.Image] samplers with plain `fract()` sampling tile without
/// seams. GPU-side the pencil shader then only mixes a handful of fetches —
/// the same "BitmapShader" hardware path as Android ink effects — instead of
/// hashing a lattice per pixel.
///
/// - `paper`: R = coarse paper lumps (6–64 px features), G = medium tooth,
///   B = fine grit. This is the paper height field graphite catches on.
/// - `bristles`: R/G = directional fibre streaks (graphite smears along the
///   travel of the grain), B = mid-frequency grit used to modulate streak
///   contrast.
///
/// [1] All fields are computed on the CPU once at startup (~1.2 M lattice
/// evaluations) and uploaded as raw RGBA; no raster-thread picture work.
class PencilGrainAtlas {
  PencilGrainAtlas._();
  static final PencilGrainAtlas instance = PencilGrainAtlas._();

  /// Texture edge length. Must stay a power of two (noise periods divide it).
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
      // Heavy synchronous math: keep it off the first frame's critical path.
      await Future<void>.delayed(Duration.zero);
      final paperBytes = _buildPaper();
      final bristleBytes = _buildBristles();
      _paper = await _upload(paperBytes);
      _bristles = await _upload(bristleBytes);
    } finally {
      _loading = null;
    }
  }

  Future<ui.Image> _upload(Uint8List rgba) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: size,
      height: size,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }

  // ---------------------------------------------------------------------
  // Noise synthesis
  // ---------------------------------------------------------------------

  static double _hash(int x, int y, int seed) {
    var h = x * 0x27d4eb2d + y * 0x165667b1 + seed * 0x9e3779b1;
    h ^= h >> 15;
    h *= 0x85ebca6b;
    h ^= h >> 13;
    h *= 0xc2b2ae35;
    h ^= h >> 16;
    return (h & 0xFFFFFF) / 0xFFFFFF;
  }

  /// Value noise evaluated at texel coordinates [x],[y] with a square lattice
  /// of [period] cells across the texture. Wraps at [period], so the field is
  /// seamless on the torus.
  static double _vnoise(double x, double y, int period, int seed) {
    final xi = x.floor();
    final yi = y.floor();
    final xf = x - xi;
    final yf = y - yi;
    final u = xf * xf * (3.0 - 2.0 * xf);
    final v = yf * yf * (3.0 - 2.0 * yf);
    final a = _hash(xi & (period - 1), yi & (period - 1), seed);
    final b = _hash((xi + 1) & (period - 1), yi & (period - 1), seed);
    final c = _hash(xi & (period - 1), (yi + 1) & (period - 1), seed);
    final d = _hash((xi + 1) & (period - 1), (yi + 1) & (period - 1), seed);
    final top = a + (b - a) * u;
    final bottom = c + (d - c) * u;
    return top + (bottom - top) * v;
  }

  /// Fractal sum of [periods] octaves (each must divide [size]). Returns
  /// roughly [0, 1] centred near 0.5.
  static Float32List _fbm(int seed, List<int> periods) {
    final out = Float32List(size * size);
    final count = periods.length;
    double ampSum = 0;
    for (var o = 0; o < count; o++) {
      ampSum += math.pow(0.5, o).toDouble();
    }
    final inv = 1.0 / ampSum;
    for (var o = 0; o < count; o++) {
      final period = periods[o];
      final amp = math.pow(0.5, o).toDouble() * inv;
      final scale = period / size;
      final octaveSeed = seed + o * 7919;
      for (var y = 0; y < size; y++) {
        final row = y * size;
        final ny = y * scale;
        for (var x = 0; x < size; x++) {
          out[row + x] +=
              amp * _vnoise(x * scale, ny, period, octaveSeed);
        }
      }
    }
    return out;
  }

  /// Wrapped integer-step box blur: streaks along ([dx],[dy]) (texels).
  static Float32List _streak(Float32List src, int dx, int dy, int radius) {
    final out = Float32List(size * size);
    final taps = radius * 2 + 1;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        double sum = 0;
        for (var k = -radius; k <= radius; k++) {
          final sx = (x + k * dx) & (size - 1);
          final sy = (y + k * dy) & (size - 1);
          sum += src[sy * size + sx];
        }
        out[y * size + x] = sum / taps;
      }
    }
    return out;
  }

  /// Recentres a field on 0.5 and rescales its spread to [targetStd].
  static void _normalise(Float32List a, {double targetStd = 0.16}) {
    double mean = 0;
    for (var i = 0; i < a.length; i++) {
      mean += a[i];
    }
    mean /= a.length;
    double varSum = 0;
    for (var i = 0; i < a.length; i++) {
      final d = a[i] - mean;
      varSum += d * d;
    }
    final std = math.sqrt(varSum / a.length);
    final k = std < 1e-6 ? 0.0 : targetStd / std;
    for (var i = 0; i < a.length; i++) {
      a[i] = (0.5 + (a[i] - mean) * k).clamp(0.0, 1.0);
    }
  }

  static void _writeChannel(
    Uint8List rgba,
    Float32List channel,
    int offset,
  ) {
    for (var i = 0, j = offset; i < channel.length; i++, j += 4) {
      rgba[j] = (channel[i] * 255.0).round().clamp(0, 255);
    }
  }

  static Uint8List _newRgba() {
    final bytes = Uint8List(size * size * 4);
    for (var i = 3; i < bytes.length; i += 4) {
      bytes[i] = 255;
    }
    return bytes;
  }

  // ---------------------------------------------------------------------
  // Field layouts
  // ---------------------------------------------------------------------

  /// R coarse lumps / G medium tooth / B fine grit.
  static Uint8List _buildPaper() {
    final rgba = _newRgba();
    _writeChannel(rgba, _fbm(0x5EED01, const [4, 8, 16]), 0);
    _writeChannel(rgba, _fbm(0x5EED02, const [16, 32, 64]), 1);
    final grit = _fbm(0x5EED03, const [64, 128, 256]);
    // A whisper of per-texel sparkle reads as graphite dust under magnification.
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final i = y * size + x;
        grit[i] = (grit[i] * 0.82 + _hash(x, y, 0x5EED04) * 0.18)
            .clamp(0.0, 1.0);
      }
    }
    _writeChannel(rgba, grit, 2);
    return rgba;
  }

  /// R/G directional fibre streaks (different angles) / B streak grit.
  static Uint8List _buildBristles() {
    final rgba = _newRgba();
    final streakA = _streak(_fbm(0x5EED11, const [8, 16, 32]), 4, 1, 9);
    _normalise(streakA, targetStd: 0.17);
    _writeChannel(rgba, streakA, 0);
    final streakB = _streak(_fbm(0x5EED12, const [8, 16, 32]), -1, 3, 9);
    _normalise(streakB, targetStd: 0.17);
    _writeChannel(rgba, streakB, 1);
    _writeChannel(rgba, _fbm(0x5EED13, const [32, 64, 128]), 2);
    return rgba;
  }
}
