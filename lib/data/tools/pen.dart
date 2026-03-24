// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/i18n/strings.g.dart';

class Pen extends Tool {
  @protected
  @visibleForTesting
  Pen({
    required this.name,
    required this.sizeMin,
    required this.sizeMax,
    required this.sizeStep,
    required this.icon,
    required this.options,
    required this.pressureEnabled,
    required this.color,
    required this.toolId,
  });

  Pen.fountainPen()
    : name = t.editor.pens.fountainPen,
      sizeMin = 0.5,
      sizeMax = 5.0,
      sizeStep = 0.5,
      icon = fountainPenIcon,
      options = stows.lastFountainPenOptions.value,
      pressureEnabled = true,
      color = Color(stows.lastFountainPenColor.value),
      toolId = .fountainPen;

  Pen.ballpointPen()
    : name = t.editor.pens.ballpointPen,
      sizeMin = 0.5,
      sizeMax = 5.0,
      sizeStep = 0.5,
      icon = ballpointPenIcon,
      options = stows.lastBallpointPenOptions.value,
      pressureEnabled = false,
      color = Color(stows.lastBallpointPenColor.value),
      toolId = .ballpointPen;

  Pen.calligraphyPen()
    : name = t.editor.pens.calligraphyPen,
      sizeMin = 0.5,
      sizeMax = 5.0,
      sizeStep = 0.5,
      icon = calligraphyPenIcon,
      options = stows.lastCalligraphyPenOptions.value,
      pressureEnabled = true,
      color = Color(stows.lastCalligraphyPenColor.value),
      toolId = .calligraphyPen;

  Pen.verticalSpacePen()
    : name = 'Vertical Space',
      sizeMin = 0.5,
      sizeMax = 5.0,
      sizeStep = 0.5,
      icon = verticalSpacePenIcon,
      options = insertPenOptions,
      pressureEnabled = false,
      color = Colors.blueAccent,
      toolId = .verticalSpacePen;

  Pen.horizontalSpacePen()
    : name = 'Horizontal Space',
      sizeMin = 0.5,
      sizeMax = 5.0,
      sizeStep = 0.5,
      icon = horizontalSpacePenIcon,
      options = insertPenOptions,
      pressureEnabled = false,
      color = Colors.blueAccent,
      toolId = .horizontalSpacePen;

  final String name;
  final double sizeMin, sizeMax, sizeStep;
  late final int sizeStepsBetweenMinAndMax = ((sizeMax - sizeMin) / sizeStep)
      .round();
  final IconData icon;

  @override
  final ToolId toolId;

  static const IconData fountainPenIcon = FontAwesomeIcons.penFancy;
  static const IconData ballpointPenIcon = FontAwesomeIcons.pen;
  static const IconData calligraphyPenIcon = FontAwesomeIcons.penNib;
  static const IconData verticalSpacePenIcon = FontAwesomeIcons.arrowsUpDown;
  static const IconData horizontalSpacePenIcon =
      FontAwesomeIcons.arrowsLeftRight;

  static Stroke? currentStroke;
  Color color;
  bool pressureEnabled;
  StrokeOptions options;

  static var _currentPen = Pen.ballpointPen();
  static Pen get currentPen => _currentPen;
  static set currentPen(Pen currentPen) {
    assert(
      currentPen is! Highlighter,
      'Use Highlighter.currentHighlighter instead',
    );
    _currentPen = currentPen;
  }

  void onDragStart(
    Offset position,
    EditorPage page,
    int pageIndex,
    double? pressure,
    Duration timestamp,
  ) {
    currentStroke = Stroke(
      color: color,
      pressureEnabled: pressureEnabled,
      options: options.copyWith(isComplete: false),
      pageIndex: pageIndex,
      page: page,
      toolId: toolId,
    );
    if (this is Highlighter) {
      currentStroke?.flatEdge = stows.highlighterFlatEdge.value;
    }
    currentStroke?.resetStabilization();
    onDragUpdate(position, pressure, timestamp);
  }

  void onDragUpdate(Offset position, double? pressure, Duration timestamp) {
    currentStroke?.addPoint(position, pressure, timestamp);
  }

  Stroke? onDragEnd() {
    final stroke = currentStroke;
    currentStroke = null;
    if (stroke == null) return null;

    stroke.options.isComplete = true;
    stroke.clearLivePrediction();

    if (this is Highlighter &&
        Highlighter.straightLine.value &&
        stroke.length == 2) {
      stroke.densifyStraightLine();
    }

    if (stroke.length < 2) {

      final lastPoint = stroke.points.lastOrNull;
      if (lastPoint != null) {

        stroke.addPoint(
          Offset(lastPoint.x + 0.1, lastPoint.y + 0.1),
          lastPoint.pressure,
          null,
        );
      }
    }

    return stroke..markPolygonNeedsUpdating();
  }

  static final defaultOptions = StrokeOptions(
    size: 2,
    smoothing: 0.5,
    streamline: 0.5,
    simulatePressure:
        false,
  );

  static StrokeOptions get fountainPenOptions => defaultOptions.copyWith(
    size: 2,

    smoothing: 0.95,
    streamline: 0.88,
    thinning: 0.35,
    simulatePressure: true,
    start: StrokeEndOptions.start(
      taperEnabled: true,
      customTaper: 12,
      cap: false,
    ),
    end: StrokeEndOptions.end(taperEnabled: true, customTaper: 12, cap: false),
  );

  static StrokeOptions get ballpointPenOptions => defaultOptions.copyWith(

    smoothing: 0.3,
    streamline: 0.0,
    size: 2,

    thinning: 0.0,
    simulatePressure: false,

    start: StrokeEndOptions.start(taperEnabled: false, cap: true),
    end: StrokeEndOptions.end(taperEnabled: false, cap: true),
  );

  static StrokeOptions get calligraphyPenOptions => defaultOptions.copyWith(

    smoothing: 0.85,
    streamline: 0.7,
    thinning: 0.0,
    simulatePressure: true,

    start: StrokeEndOptions.start(taperEnabled: true, customTaper: 8, cap: false),
    end: StrokeEndOptions.end(taperEnabled: true, customTaper: 8, cap: false),
  );
  static StrokeOptions get shapePenOptions =>
      defaultOptions.copyWith(smoothing: 0, streamline: 0);
  static StrokeOptions get insertPenOptions => defaultOptions.copyWith(
    size: 2,
    smoothing: 0,
    streamline: 0,
    thinning: 0,
    simulatePressure: false,
  );
  static StrokeOptions get highlighterOptions => defaultOptions.copyWith(
    size: 20,
    thinning: 0,
  );

  static StrokeOptions get advancedPenOptions => defaultOptions.copyWith(
    size: 2,
    thinning: 0.5,
    smoothing: 0.5,
    streamline: 0.5,
    simulatePressure: false,
    start: StrokeEndOptions.start(
      taperEnabled: true,
      customTaper: 10,
      cap: true,
    ),
    end: StrokeEndOptions.end(taperEnabled: true, customTaper: 10, cap: true),
  );
}

class AdvancedPen extends Pen {
  AdvancedPen()
    : super(
        name: 'Advanced Pen',
        sizeMin: 0.5,
        sizeMax: 5.0,
        sizeStep: 0.5,
        icon: AdvancedPen.advancedPenIcon,
        options: AdvancedPen._optionsWithPersistedEasing(),
        pressureEnabled: true,
        color: Color(stows.lastAdvancedPenColor.value),
        toolId: ToolId.advancedPen,
      );

  static const IconData advancedPenIcon = FontAwesomeIcons.sliders;

  static StrokeOptions _optionsWithPersistedEasing() {
    final opts = stows.lastAdvancedPenOptions.value;
    final mainE = _easingFromId(stows.lastAdvancedPenMainEasingId.value);
    final startE = _easingFromId(stows.lastAdvancedPenStartEasingId.value);
    final endE = _easingFromId(stows.lastAdvancedPenEndEasingId.value);
    opts.easing = mainE;
    opts.start = StrokeEndOptions.start(
      taperEnabled: opts.start.taperEnabled,
      customTaper: opts.start.customTaper,
      cap: opts.start.cap,
      easing: startE,
    );
    opts.end = StrokeEndOptions.end(
      taperEnabled: opts.end.taperEnabled,
      customTaper: opts.end.customTaper,
      cap: opts.end.cap,
      easing: endE,
    );
    return opts;
  }

  static double Function(double) _easingFromId(String id) {
    switch (id) {
      case 'easeInOut':
        return StrokeEasings.easeInOut;
      case 'easeOutCubic':
        return StrokeEasings.easeOutCubic;
      default:
        return StrokeEasings.identity;
    }
  }
}
