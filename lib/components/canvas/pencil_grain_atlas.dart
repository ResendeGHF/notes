// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;
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
      _paper = await _createNoiseImage(42, bristles: false);
      _bristles = await _createNoiseImage(1337, bristles: true);
    } finally {
      _loading = null;
    }
  }

  Future<ui.Image> _createNoiseImage(int seed, {required bool bristles}) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()));
    final rand = math.Random(seed);
    
    // Transparent background
    canvas.drawColor(const ui.Color(0x00000000), ui.BlendMode.src);
    final paint = ui.Paint()..style = ui.PaintingStyle.fill;
      
    final numGrains = bristles ? 12000 : 40000;
    for (int i = 0; i < numGrains; i++) {
      final cx = rand.nextDouble() * size;
      final cy = rand.nextDouble() * size;
      final radius = bristles ? (0.8 + rand.nextDouble() * 1.5) : (0.5 + rand.nextDouble() * 1.2);
      final alpha = (50 + rand.nextDouble() * 205).toInt();
      paint.color = ui.Color.fromARGB(alpha, 255, 255, 255);
      
      // Draw 3x3 wrap-around pattern for perfectly seamless edge tiling
      for (int dx = -1; dx <= 1; dx++) {
        for (int dy = -1; dy <= 1; dy++) {
          final x = cx + dx * size;
          final y = cy + dy * size;
          if (x >= -radius && x <= size + radius && y >= -radius && y <= size + radius) {
            canvas.drawCircle(ui.Offset(x, y), radius, paint);
          }
        }
      }
    }
    
    final picture = recorder.endRecording();
    return await picture.toImage(size, size);
  }
}
