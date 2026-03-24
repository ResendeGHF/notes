// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/list_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/pen.dart';

class LaserPointer extends Tool {
  LaserPointer._();

  static final _currentLaserPointer = LaserPointer._();
  static LaserPointer get currentLaserPointer => _currentLaserPointer;

  @override
  ToolId get toolId => .laserPointer;

  final pressureEnabled = false;
  final options = StrokeOptions(smoothing: 0.7, streamline: 0.7);

  Color get color => stows.laserPointerColor.value;

  static const double maxSize = 10.0;
  double get size => (stows.laserPointerSize.value).clamp(4.0, maxSize);

  List<Duration> strokePointDelays = [];

  final _stopwatch = Stopwatch();

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

    strokePointDelays = [];
    _stopwatch.reset();
    onDragUpdate(position);
    _stopwatch.start();
  }

  void onDragUpdate(Offset position, {@visibleForTesting Duration? elapsed}) {
    isDrawing = true;
    Pen.currentStroke?.addPoint(position);
    strokePointDelays.add(elapsed ?? _stopwatch.elapsed);
    _stopwatch.reset();
  }

  LaserStroke? onDragEnd(
    VoidCallback redrawPage,
    void Function(Stroke) deleteStroke,
  ) {
    isDrawing = false;

    final stroke = Pen.currentStroke;
    Pen.currentStroke = null;
    if (stroke is! LaserStroke) return null;

    unawaited(
      fadeOutStroke(
        stroke: stroke,
        strokePointDelays: strokePointDelays,
        redrawPage: redrawPage,
        deleteStroke: deleteStroke,
      ),
    );

    return stroke
      ..options.isComplete = true
      ..markPolygonNeedsUpdating();
  }

  @visibleForTesting
  static const fadeOutDelay = Duration(seconds: 2);
  @visibleForTesting
  static Future<void> fadeOutStroke({
    required LaserStroke stroke,
    required List<Duration> strokePointDelays,
    required VoidCallback redrawPage,
    required void Function(LaserStroke) deleteStroke,
    @visibleForTesting Future<void> Function(Duration) wait = Future.delayed,
  }) async {
    await wait(fadeOutDelay);

    for (final delay in strokePointDelays) {
      await wait(delay);

      if (stroke.length <= 1) break;

      stroke.popFirstPoint();
      redrawPage();

      if (isDrawing) {

        const waitTime = Duration(milliseconds: 100);
        while (isDrawing) await wait(waitTime);

        await wait(fadeOutDelay - waitTime);
      }
    }

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
          ..streamline = 0.7
          ..smoothing = 0.7,
        pageIndex: stroke.pageIndex,
        page: stroke.page,
        toolId: stroke.toolId,
      ) {
    points.addAll(stroke.points);
  }

  @protected
  List<Offset> get innerPolygon => _innerPolygon ??= getStroke(
    points,
    options: options.copyWith(size: options.size * 0.4),
  );
  List<Offset>? _innerPolygon;

  Path get innerPath =>
      _innerPath ??= Stroke.smoothPathFromPolygon(innerPolygon);
  Path? _innerPath;

  @override
  List<Offset> get highQualityPolygon => super.highQualityPolygon;

  @override
  List<Offset> get lowQualityPolygon => super.highQualityPolygon;

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
