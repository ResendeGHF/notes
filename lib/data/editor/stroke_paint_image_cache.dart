// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:saber/data/editor/stroke_paint.dart';
import 'package:saber/data/editor/stroke_paint_shader_cache.dart';

/// Decodes and caches tiled textures for [StrokePaint] image/SVG modes.
class StrokePaintImageCache {
  StrokePaintImageCache._();
  static final StrokePaintImageCache instance = StrokePaintImageCache._();

  final Map<String, ui.Image> _images = {};
  final Set<String> _loading = {};
  final ValueNotifier<int> revision = ValueNotifier(0);

  ui.Image? getSync(StrokePaint paint) {
    if (!paint.usesTexture) return null;
    return _images[paint.cacheKey];
  }

  /// Starts decode if needed; returns cached image when ready.
  ui.Image? ensure(StrokePaint paint, {VoidCallback? onReady}) {
    if (!paint.usesTexture) return null;
    final key = paint.cacheKey;
    final hit = _images[key];
    if (hit != null) return hit;
    final bytes = paint.bytes;
    if (bytes == null || bytes.isEmpty) return null;
    if (_loading.contains(key)) return null;
    _loading.add(key);
    unawaited(() async {
      try {
        final img = paint.mode == StrokePaintMode.svg
            ? await _decodeSvg(bytes)
            : await _decodeRaster(bytes);
        if (img != null) {
          _images[key] = img;
          revision.value++;
          onReady?.call();
        }
      } finally {
        _loading.remove(key);
      }
    }());
    return null;
  }

  static Future<ui.Image?> _decodeRaster(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    const maxEdge = 1024;
    if (image.width <= maxEdge && image.height <= maxEdge) {
      return image;
    }
    final scale = maxEdge / math.max(image.width, image.height);
    final w = math.max(1, (image.width * scale).round());
    final h = math.max(1, (image.height * scale).round());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    paintImage(
      canvas: canvas,
      rect: Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      image: image,
      filterQuality: FilterQuality.medium,
      fit: BoxFit.fill,
    );
    final picture = recorder.endRecording();
    image.dispose();
    try {
      return await picture.toImage(w, h);
    } finally {
      picture.dispose();
    }
  }

  static Future<ui.Image?> _decodeSvg(Uint8List bytes) async {
    try {
      final pictureInfo = await vg.loadPicture(
        SvgBytesLoader(bytes),
        null,
      );
      final size = pictureInfo.size;
      // Stroke tiles are repeated at [StrokePaint.imageScale] (often ≪ 1).
      // Cap aggressively — 2048² tiles were a common OOM source.
      const maxEdge = 512;
      final w = size.width.isFinite && size.width > 0
          ? size.width.ceil().clamp(8, maxEdge)
          : 256;
      final h = size.height.isFinite && size.height > 0
          ? size.height.ceil().clamp(8, maxEdge)
          : 256;
      final image = await pictureInfo.picture.toImage(w, h);
      pictureInfo.picture.dispose();
      return image;
    } catch (e, st) {
      debugPrint('StrokePaintImageCache SVG decode failed: $e\n$st');
      return null;
    }
  }

  void clear() {
    for (final img in _images.values) {
      img.dispose();
    }
    _images.clear();
    _loading.clear();
    StrokePaintShaderCache.instance.clear();
  }
}
