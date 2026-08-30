// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/list_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/pen.dart';

class LaserPointer extends Tool {
  LaserPointer._();

  static final _currentLaserPointer = LaserPointer._();
  static LaserPointer get currentLaserPointer => _currentLaserPointer;

  @override
  ToolId get toolId => .laserPointer;

  final pressureEnabled = false;
  final options = StrokeOptions(smoothing: 0.52, streamline: 0.32);

  Color get color => stows.laserPointerColor.value;

  static const double maxSize = 10.0;
  double get size => (stows.laserPointerSize.value).clamp(4.0, maxSize);

  static var isDrawing = false;

  void onDragStart(Offset position, EditorPage page, int pageIndex) {
    isDrawing = true;
    Pen.currentStroke = LaserStroke(
      color: color,
      pressureEnabled: pressureEnabled,
      options: options.copyWith(size: size),
      pageIndex: pageIndex,
      page: page,
      toolId: toolId,
    );

    onDragUpdate(position);
  }

  void onDragUpdate(Offset position, {@visibleForTesting Duration? elapsed}) {
    isDrawing = true;
    Pen.currentStroke?.addPoint(position);
  }

  LaserStroke? onDragEnd(
    VoidCallback redrawPage,
    void Function(Stroke) deleteStroke,
  ) {
    isDrawing = false;

    final stroke = Pen.currentStroke;
    Pen.currentStroke = null;
    if (stroke is! LaserStroke) return null;

    stroke.clearLivePrediction();

    unawaited(
      fadeOutStroke(
        stroke: stroke,
        redrawPage: redrawPage,
        deleteStroke: deleteStroke,
      ),
    );

    return stroke
      ..options.isComplete = true
      ..markPolygonNeedsUpdating();
  }

  /// Brief hold at full opacity after stylus-up, then fade.
  @visibleForTesting
  static const fadeOutDelay = Duration(milliseconds: 200);

  /// Total fade length after the hold (~3s visible trail overall).
  @visibleForTesting
  static const fadeOutDuration = Duration(milliseconds: 2800);

  @visibleForTesting
  static Future<void> fadeOutStroke({
    required LaserStroke stroke,
    required VoidCallback redrawPage,
    required void Function(LaserStroke) deleteStroke,
    @visibleForTesting Future<void> Function(Duration) wait = Future.delayed,
  }) async {
    await wait(fadeOutDelay);

    // Pause while the user is drawing another laser stroke.
    if (isDrawing) {
      const waitTime = Duration(milliseconds: 50);
      while (isDrawing) {
        await wait(waitTime);
      }
      await wait(fadeOutDelay);
    }

    final completer = Completer<void>();
    late final Ticker ticker;
    ticker = Ticker((elapsed) {
      final t = (elapsed.inMilliseconds / fadeOutDuration.inMilliseconds)
          .clamp(0.0, 1.0);
      // Ease-out so it lingers brightly then softens away.
      final eased = Curves.easeOutCubic.transform(t);
      stroke.fadeOpacity = lerpDouble(1.0, 0.0, eased) ?? 0.0;
      redrawPage();
      if (t >= 1.0) {
        ticker.stop();
        ticker.dispose();
        if (!completer.isCompleted) completer.complete();
      }
    }, debugLabel: 'LaserFade');
    ticker.start();
    await completer.future;

    stroke.fadeOpacity = 0.0;
    deleteStroke(stroke);
    redrawPage();
  }
}

class LaserStroke extends Stroke {
  LaserStroke({
    required super.color,
    required super.pressureEnabled,
    required super.options,
    required super.pageIndex,
    required EditorPage super.page,
    required super.toolId,
  });
  @visibleForTesting
  LaserStroke.convertStroke(Stroke stroke)
    : super(
        color: stroke.color,
        pressureEnabled: stroke.pressureEnabled,
        options: stroke.options
          ..streamline = 0.32
          ..smoothing = 0.52,
        pageIndex: stroke.pageIndex,
        page: stroke.page,
        toolId: stroke.toolId,
      ) {
    points.addAll(stroke.points);
  }

  /// 1 = fully visible, 0 = fully faded (about to be removed).
  double fadeOpacity = 1.0;

  /// Neon white core: same ballpoint adaptive-spine + outline at ~40% size.
  @protected
  List<Offset> get innerPolygon =>
      _innerPolygon ??= Stroke.buildBallpointStylePolygon(
        points,
        size: options.size * 0.4,
      );
  List<Offset>? _innerPolygon;

  Path get innerPath =>
      _innerPath ??= Stroke.smoothPathFromPolygon(innerPolygon);
  Path? _innerPath;

  @override
  List<Offset> get lowQualityPolygon => highQualityPolygon;

  @override
  void shift(Offset offset) {
    _innerPolygon?.shift(offset);
    _innerPath?.shift(offset);
    super.shift(offset);
  }

  @override
  void markPolygonNeedsUpdating({bool preserveBounds = false}) {
    _innerPolygon = null;
    _innerPath = null;
    super.markPolygonNeedsUpdating(preserveBounds: preserveBounds);
  }
}
