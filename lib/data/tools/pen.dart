// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/editor/stroke_paint.dart';
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
      sizeMax = 50.0,
      sizeStep = 0.5,
      icon = fountainPenIcon,
      options = stows.lastFountainPenOptions.value,
      pressureEnabled = true,
      color = Color(stows.lastFountainPenColor.value),
      toolId = .fountainPen;

  Pen.ballpointPen()
    : name = t.editor.pens.ballpointPen,
      sizeMin = 0.5,
      sizeMax = 50.0,
      sizeStep = 0.5,
      icon = ballpointPenIcon,
      options = stows.lastBallpointPenOptions.value,
      pressureEnabled = false,
      color = Color(stows.lastBallpointPenColor.value),
      toolId = .ballpointPen;

  Pen.calligraphyPen()
    : name = t.editor.pens.calligraphyPen,
      sizeMin = 0.5,
      sizeMax = 50.0,
      sizeStep = 0.5,
      icon = calligraphyPenIcon,
      options = stows.lastCalligraphyPenOptions.value,
      pressureEnabled = true,
      color = Color(stows.lastCalligraphyPenColor.value),
      toolId = .calligraphyPen;

  Pen.advancedPen()
    : name = t.editor.pens.advancedPen,
      sizeMin = 0.5,
      sizeMax = 50.0,
      sizeStep = 0.5,
      icon = advancedPenIcon,
      options = stows.lastAdvancedPenOptions.value,
      pressureEnabled = true,
      color = Color(stows.lastAdvancedPenColor.value),
      toolId = .advancedPen {
    paint = const StrokePaint();
    brushOptions = stows.lastAdvancedPenBrushOptions.value.copyWith();
  }

  /// Simple pencil (official Saber style): exactly a ballpoint pen with a
  /// fixed graphite-grain shader. No tuning UI.
  Pen.pencil()
    : name = t.editor.pens.pencil,
      sizeMin = 0.5,
      sizeMax = 50.0,
      sizeStep = 0.5,
      icon = pencilIcon,
      options = stows.lastPencilOptions.value,
      pressureEnabled = false,
      color = Color(stows.lastPencilColor.value),
      toolId = .pencil {
    paint = StrokePaint.pencilNoiseDefault();
  }

  final String name;
  final double sizeMin, sizeMax, sizeStep;
  late final int sizeStepsBetweenMinAndMax = ((sizeMax - sizeMin) / sizeStep)
      .round();
  final FaIconData icon;

  @override
  final ToolId toolId;

  static const FaIconData fountainPenIcon = FontAwesomeIcons.penFancy;
  static const FaIconData ballpointPenIcon = FontAwesomeIcons.pen;
  static const FaIconData calligraphyPenIcon = FontAwesomeIcons.penNib;
  static const FaIconData advancedPenIcon = FontAwesomeIcons.brush;
  static const FaIconData pencilIcon = FontAwesomeIcons.pencil;

  static Stroke? currentStroke;
  Color color;
  bool pressureEnabled;
  StrokeOptions options;
  StrokePaint paint = const StrokePaint();

  /// Brush configuration of the Advanced pen (live prefs-backed copy).
  /// Only meaningful when [toolId] is [ToolId.advancedPen]; otherwise it
  /// holds defaults.
  AdvancedPenOptions brushOptions = AdvancedPenOptions.advancedDefaults();

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
      brushOptions:
          toolId == ToolId.advancedPen ? brushOptions.copyWith() : null,
    );
    if (this is Highlighter) {
      currentStroke?.flatEdge = stows.highlighterFlatEdge.value;
    }
    currentStroke?.neon = neonEnabledForTool(toolId);
    if (toolId == ToolId.pencil) {
      // Fixed graphite grain (no prefs: the pencil has no tuning UI).
      currentStroke?.paint = StrokePaint.pencilNoiseDefault();
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

    stroke.finishLiveGeometry();
    return stroke;
  }

  static final defaultOptions = StrokeOptions(
    size: 2,
    smoothing: 0.5,
    streamline: 0.5,
    simulatePressure: false,
  );

  /// Apple-Notes-style fountain pen: lively pressure response with hairline
  /// lows, short elegant tapers (no long needle tails) and smooth tips.
  static StrokeOptions get fountainPenOptions => defaultOptions.copyWith(
    size: 2,

    smoothing: 0.42,
    streamline: 0.18,
    thinning: 0.55,
    minSizeRatio: 0.07,
    simulatePressure: true,
    start: StrokeEndOptions.start(
      taperEnabled: true,
      customTaper: 6,
      cap: false,
    ),
    end: StrokeEndOptions.end(taperEnabled: true, customTaper: 6, cap: false),
  );

  static StrokeOptions get ballpointPenOptions => defaultOptions.copyWith(
    smoothing: 0.18,
    streamline: 0.0,
    size: 2,

    thinning: 0.0,
    simulatePressure: false,

    start: StrokeEndOptions.start(taperEnabled: false, cap: true),
    end: StrokeEndOptions.end(taperEnabled: false, cap: true),
  );

  /// Ballpoint-width defaults; look comes from stamped grain mesh.

  static StrokeOptions get calligraphyPenOptions => defaultOptions.copyWith(
    smoothing: 0.48,
    streamline: 0.22,
    thinning: 0.0,
    simulatePressure: true,

    start: StrokeEndOptions.start(
      taperEnabled: true,
      customTaper: 8,
      cap: false,
    ),
    end: StrokeEndOptions.end(taperEnabled: true, customTaper: 8, cap: false),
  );

  /// Whether neon ink is enabled for this pen tool (ballpoint only).
  static bool neonEnabledForTool(ToolId id) {
    return id == ToolId.ballpointPen && stows.lastBallpointPenNeon.value;
  }

  static void setNeonEnabledForTool(ToolId id, bool enabled) {
    if (id == ToolId.ballpointPen) {
      stows.lastBallpointPenNeon.value = enabled;
    }
  }

  static StrokeOptions get shapePenOptions =>
      defaultOptions.copyWith(smoothing: 0, streamline: 0);
  static StrokeOptions get highlighterOptions =>
      defaultOptions.copyWith(size: 20, thinning: 0);

  /// Defaults for the Advanced pen brush (user-tunable via modal + presets).
  static AdvancedPenOptions get advancedBrushDefaults =>
      AdvancedPenOptions.advancedDefaults();

  /// Freehand ink tools that can be applied to an existing selection.
  static const List<ToolId> convertibleInkToolIds = [
    ToolId.fountainPen,
    ToolId.ballpointPen,
    ToolId.calligraphyPen,
    ToolId.advancedPen,
    ToolId.pencil,
    ToolId.highlighter,
  ];

  static bool isConvertibleInkTool(ToolId id) =>
      convertibleInkToolIds.contains(id);

  /// Current prefs-backed pen for [id], or null if not a convertible ink tool.
  static Pen? inkPenForTool(ToolId id) {
    return switch (id) {
      ToolId.fountainPen => Pen.fountainPen(),
      ToolId.ballpointPen => Pen.ballpointPen(),
      ToolId.calligraphyPen => Pen.calligraphyPen(),
      ToolId.advancedPen => Pen.advancedPen(),
      ToolId.pencil => Pen.pencil(),
      ToolId.highlighter => Highlighter.currentHighlighter,
      _ => null,
    };
  }

  static String displayNameForTool(ToolId id) {
    return switch (id) {
      ToolId.fountainPen => t.editor.pens.fountainPen,
      ToolId.ballpointPen => t.editor.pens.ballpointPen,
      ToolId.calligraphyPen => t.editor.pens.calligraphyPen,
      ToolId.advancedPen => t.editor.pens.advancedPen,
      ToolId.pencil => t.editor.pens.pencil,
      ToolId.highlighter => t.editor.pens.highlighter,
      _ => id.id,
    };
  }

  static FaIconData iconForTool(ToolId id) {
    return switch (id) {
      ToolId.fountainPen => fountainPenIcon,
      ToolId.ballpointPen => ballpointPenIcon,
      ToolId.calligraphyPen => calligraphyPenIcon,
      ToolId.advancedPen => advancedPenIcon,
      ToolId.pencil => pencilIcon,
      ToolId.highlighter => Highlighter.highlighterIcon,
      _ => FontAwesomeIcons.pen,
    };
  }

  /// Built-in Advanced pen preset payload.
  static Map<String, dynamic> defaultAdvancedPenPresetPayload({
    String name = 'Default',
    int? colorArgb,
  }) {
    final pen = Pen.advancedPen();
    return {
      'name': name,
      'options': pen.options.toJson(),
      'colorArgb': colorArgb ?? pen.color.toARGB32(),
      'brush': pen.brushOptions.toJson(),
    };
  }

  /// Rebuilds [stroke] as [newToolId], keeping samples and color.
  /// Size is preserved; options / paint / neon follow the target pen prefs.
  static Stroke convertStroke(Stroke stroke, ToolId newToolId) {
    if (!stroke.canConvertStrokeType) {
      throw StateError(
        'Stroke cannot convert tool type: ${stroke.runtimeType} / ${stroke.toolId}',
      );
    }
    if (!isConvertibleInkTool(newToolId)) {
      throw ArgumentError.value(
        newToolId,
        'newToolId',
        'not a convertible ink tool',
      );
    }
    if (newToolId == stroke.toolId) return stroke.copy();

    final template = inkPenForTool(newToolId);
    if (template == null) {
      throw ArgumentError.value(newToolId, 'newToolId');
    }

    var paint = template.paint;
    if (newToolId == ToolId.pencil && !paint.usesPencilNoise) {
      paint = paint.copyWith(mode: StrokePaintMode.pencilNoise);
    } else if (newToolId != ToolId.pencil) {
      paint = const StrokePaint();
    }

    final rebuilt = stroke.rebuildWithTool(
      toolId: newToolId,
      pressureEnabled: template.pressureEnabled,
      options: template.options.copyWith(
        size: stroke.options.size,
        isComplete: true,
      ),
      paint: paint,
      neon: neonEnabledForTool(newToolId),
      flatEdge: newToolId == ToolId.highlighter
          ? (stroke.flatEdge || stows.highlighterFlatEdge.value)
          : false,
      brushOptions: newToolId == ToolId.advancedPen
          ? template.brushOptions.copyWith()
          : null,
    );
    return rebuilt;
  }
}
