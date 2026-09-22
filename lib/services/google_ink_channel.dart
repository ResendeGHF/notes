// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:saber/data/tools/google_ink_brush.dart';

/// Finished stroke pushed by Kotlin: screen-space samples + brush snapshot.
final class GoogleInkFinishedStroke {
  GoogleInkFinishedStroke({required this.samples, required this.brush});

  final List<GoogleInkSample> samples;
  final GoogleInkBrushConfig brush;

  static GoogleInkFinishedStroke? parse(Object? raw) {
    if (raw is! Map) return null;
    final list = raw['samples'];
    if (list is! List || list.isEmpty) return null;
    final samples = <GoogleInkSample>[];
    for (final e in list) {
      if (e is! Map) continue;
      double d(Object? v) => v is num ? v.toDouble() : 0.0;
      samples.add(GoogleInkSample(
        x: d(e['x']),
        y: d(e['y']),
        pressure: (e['pressure'] is num ? (e['pressure'] as num).toDouble() : 0.5)
            .clamp(0.0, 1.0),
        tiltDeg: d(e['tilt']),
        timeMs: d(e['time']),
      ));
    }
    if (samples.isEmpty) return null;
    GoogleInkBrushConfig brush = GoogleInkBrushConfig();
    final b = raw['brush'];
    if (b is Map) {
      double d(Object? v, double fb) => v is num ? v.toDouble() : fb;
      brush = GoogleInkBrushConfig(
        family: GoogleInkBrushFamily.parse(b['family'] as String?),
        size: d(b['size'], brush.size).clamp(
            GoogleInkBrushConfig.minSize, GoogleInkBrushConfig.maxSize),
        colorArgb: b['colorArgb'] is num
            ? (b['colorArgb'] as num).toInt()
            : brush.colorArgb,
        epsilon: d(b['epsilon'], brush.epsilon).clamp(
            GoogleInkBrushConfig.minEpsilon, GoogleInkBrushConfig.maxEpsilon),
      );
    }
    return GoogleInkFinishedStroke(samples: samples, brush: brush);
  }
}

final class GoogleInkSample {
  GoogleInkSample({
    required this.x,
    required this.y,
    required this.pressure,
    required this.tiltDeg,
    required this.timeMs,
  });

  final double x;
  final double y;
  final double pressure;
  final double tiltDeg;
  final double timeMs;
}

/// Bridge to the native Google Ink engine (Android only).
///
/// Native side (`GoogleInkViews.kt`):
/// - owns an `androidx.ink.authoring.InProgressStrokesView` PlatformView
///   (`viewType = google_ink_view`) that captures stylus MotionEvents at
///   native rate (pressure / tilt / orientation / 120Hz+) and renders the
///   shader mesh with `CanvasStrokeRenderer` / low-latency authoring;
/// - exposes `Brush` construction from [GoogleInkBrushConfig] via
///   `StockBrushes.*` + `Brush.createWithColorIntArgb`;
/// - returns finished-stroke input batches so Dart can commit a persistent
///   [Stroke] that flows through the tiled + temporary-raster LOD pipeline.
///
/// On non-Android platforms (iOS / desktop / tests) every call is a no-op and
/// [isNativeSupported] is false, so the Dart stroke-modeler fallback in
/// `google_ink_geometry.dart` renders committed ink instead. The test modal
/// always works; only the live low-latency layer requires Android.
final class GoogleInkNative {
  GoogleInkNative._();

  static const String viewType = 'com.resendeghf.notes/google_ink_view';
  static const MethodChannel channel =
      MethodChannel('com.resendeghf.notes/google_ink');

  /// True only where the Kotlin PlatformView is registered (Android).
  static bool get isNativeSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android;
  }

  static bool _warnedUnavailable = false;

  static Future<void> setBrush(GoogleInkBrushConfig config) async {
    if (!isNativeSupported) return;
    try {
      await channel.invokeMethod('setBrush', config.toNativeMap());
    } on MissingPluginException {
      _logOnce('google_ink native plugin missing (setBrush)');
    } catch (_) {
      // Test bench must never crash the editor for a native miss.
    }
  }

  static Future<void> setPrediction(bool enabled, double amount) async {
    if (!isNativeSupported) return;
    try {
      await channel.invokeMethod('setPrediction', {
        'enabled': enabled,
        'amount': amount,
      });
    } on MissingPluginException {
      _logOnce('google_ink native plugin missing (setPrediction)');
    } catch (_) {}
  }

  static Future<void> clearLive() async {
    if (!isNativeSupported) return;
    try {
      await channel.invokeMethod('clearLive');
    } on MissingPluginException {
      _logOnce('google_ink native plugin missing (clearLive)');
    } catch (_) {}
  }

  /// Native -> Dart push for finished strokes (screen-space batch + brush
  /// snapshot). Registered once by the editor; the handler converts
  /// screen -> world with the live canvas transform and commits a normal
  /// `Stroke(toolId: experimentalPen)` so tiled + temporary-raster LOD apply.
  static void setFinishedStrokeHandler(
    FutureOr<void> Function(GoogleInkFinishedStroke stroke)? handler,
  ) {
    if (handler == null) {
      channel.setMethodCallHandler(null);
      return;
    }
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onGoogleInkStrokeFinished') {
        final parsed = GoogleInkFinishedStroke.parse(call.arguments);
        if (parsed != null) {
          await handler(parsed);
        }
        return;
      }
    });
  }

  /// Last finished-stroke input batch delivered by Kotlin
  /// (`onStrokesFinished`), decoded as `[{x,y,pressure,tilt,orientation,time}]`.
  /// Null when nothing finished yet or native is unavailable.
  static Future<List<Map<String, double>>?> drainFinishedInputs() async {
    if (!isNativeSupported) return null;
    try {
      final raw = await channel.invokeMethod('drainFinishedInputs');
      if (raw is! List) return null;
      final out = <Map<String, double>>[];
      for (final e in raw) {
        if (e is! Map) continue;
        double d(Object? v) => v is num ? v.toDouble() : 0.0;
        out.add({
          'x': d(e['x']),
          'y': d(e['y']),
          'pressure': d(e['pressure']),
          'tilt': d(e['tilt']),
          'time': d(e['time']),
        });
      }
      return out.isEmpty ? null : out;
    } on MissingPluginException {
      _logOnce('google_ink native plugin missing (drainFinishedInputs)');
      return null;
    } catch (_) {
      return null;
    }
  }

  static void _logOnce(String msg) {
    if (_warnedUnavailable) return;
    _warnedUnavailable = true;
    debugPrint('[GoogleInk] $msg — using Dart fallback renderer.');
  }
}
