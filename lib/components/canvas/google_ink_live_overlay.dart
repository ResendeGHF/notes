// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:saber/data/tools/google_ink_brush.dart';
import 'package:saber/services/google_ink_channel.dart';

/// Transparent native live-ink layer for the experimental pen.
///
/// Android only: an `InProgressStrokesView` PlatformView
/// (`GoogleInkViews.kt`) sits above the page and renders the low-latency
/// shader mesh for STYLUS pointers (native-rate pressure / tilt /
/// orientation, 120Hz+). Fingers, mouse, rubber and the inverted-stylus
/// eraser end are never consumed natively — they fall through to Flutter, so
/// pan/scroll/zoom, the app eraser and finger-draw keep working while the
/// experimental pen is selected (consuming the first DOWN would starve
/// Flutter's gesture arena and kill pinch-zoom). Finished stylus strokes are
/// pushed to Dart (dp coordinates) and committed as persistent `Stroke`s,
/// which then flow through the standard tiled Picture + temporary-raster LOD
/// pipeline (`InnerCanvas` / `PageRasterCacheManager`) — the native view
/// never owns committed ink, so pan/zoom LOD keeps working unchanged.
///
/// Off Android (iOS / desktop / tests) this builds an empty box: the Dart
/// stroke-modeler fallback (`google_ink_geometry.dart`) draws live +
/// committed ink with the same brush config, so the test bench works
/// everywhere.
class GoogleInkLiveOverlay extends StatelessWidget {
  const GoogleInkLiveOverlay({
    super.key,
    required this.brush,
    required this.enabled,
    this.onNativeFirstFrame,
  });

  final GoogleInkBrushConfig brush;
  final bool enabled;
  final VoidCallback? onNativeFirstFrame;

  @override
  Widget build(BuildContext context) {
    if (!enabled ||
        !brush.useNativeView ||
        !GoogleInkNative.isNativeSupported) {
      return const SizedBox.expand();
    }
    // Hybrid composition keeps the native SurfaceView transparent above
    // Flutter tiles; input stays in Flutter's gesture arena (which owns
    // pan/zoom + LOD), the native view only renders the live stroke.
    return const _GoogleInkAndroidView();
  }
}

class _GoogleInkAndroidView extends StatelessWidget {
  const _GoogleInkAndroidView();

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const SizedBox.expand();
    }
    return AndroidView(
      viewType: GoogleInkNative.viewType,
      layoutDirection: TextDirection.ltr,
      creationParams: const <String, dynamic>{},
      creationParamsCodec: const StandardMessageCodec(),
      // Transparent overlay: no gesture competition with the canvas arena.
      gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
    );
  }
}
