// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

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

  Pen.advancedPen()
    : name = t.editor.pens.advancedPen,
      sizeMin = 0.5,
      sizeMax = 5.0,
      sizeStep = 0.5,
      icon = advancedPenIcon,
      options = _advancedOptionsFromPrefs(),
      pressureEnabled = true,
      color = Color(stows.lastAdvancedPenColor.value),
      toolId = .advancedPen {
    paint = const StrokePaint();
  }

  Pen.advancedPencil()
    : name = t.editor.pens.advancedPencil,
      sizeMin = 0.5,
      sizeMax = 5.0,
      sizeStep = 0.5,
      icon = advancedPencilIcon,
      options = _advancedPencilOptionsFromPrefs(),
      pressureEnabled = true,
      color = Color(stows.lastAdvancedPencilColor.value),
      toolId = .advancedPencil {
    final loaded = StrokePaint.fromJson(
      Map<String, dynamic>.from(stows.lastAdvancedPencilPaint.value),
    );
    paint = loaded.usesPencilNoise
        ? loaded
        : loaded.copyWith(mode: StrokePaintMode.pencilNoise);
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
  static const FaIconData advancedPenIcon = FontAwesomeIcons.sliders;
  static const FaIconData advancedPencilIcon = FontAwesomeIcons.pencil;

  static Stroke? currentStroke;
  Color color;
  bool pressureEnabled;
  StrokeOptions options;
  StrokePaint paint = const StrokePaint();

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
    currentStroke?.neon = neonEnabledForTool(toolId);
    if (toolId == ToolId.advancedPencil) {
      currentStroke?.paint = paint.usesPencilNoise
          ? paint
          : paint.copyWith(mode: StrokePaintMode.pencilNoise);
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

  static StrokeOptions get fountainPenOptions => defaultOptions.copyWith(
    size: 2,

    smoothing: 0.42,
    streamline: 0.18,
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

  /// Defaults for Advanced pen (user-tunable via modal + presets).
  static StrokeOptions get advancedPenOptions => defaultOptions.copyWith(
    size: 2,
    thinning: 0.45,
    smoothing: 0.38,
    streamline: 0.22,
    simulatePressure: true,
    pressureSensitivity: 1.0,
    velocityThinning: 0.15,
    minSizeRatio: 0.12,
    maxSizeRatio: 1.0,
    start: StrokeEndOptions.start(
      taperEnabled: true,
      customTaper: 10,
      cap: true,
      easing: StrokeEasingCatalog.byId(stows.lastAdvancedPenStartEasingId.value),
    ),
    end: StrokeEndOptions.end(
      taperEnabled: true,
      customTaper: 10,
      cap: true,
      easing: StrokeEasingCatalog.byId(stows.lastAdvancedPenEndEasingId.value),
    ),
    easing: StrokeEasingCatalog.byId(stows.lastAdvancedPenMainEasingId.value),
  );

  /// Defaults for Advanced Pencil (geometry matches Advanced Pen; noise separate).
  static StrokeOptions get advancedPencilOptions => defaultOptions.copyWith(
    size: 2,
    thinning: 0.45,
    smoothing: 0.38,
    streamline: 0.22,
    simulatePressure: true,
    pressureSensitivity: 1.0,
    velocityThinning: 0.15,
    minSizeRatio: 0.12,
    maxSizeRatio: 1.0,
    start: StrokeEndOptions.start(
      taperEnabled: true,
      customTaper: 10,
      cap: true,
      easing: StrokeEasingCatalog.byId(
        stows.lastAdvancedPencilStartEasingId.value,
      ),
    ),
    end: StrokeEndOptions.end(
      taperEnabled: true,
      customTaper: 10,
      cap: true,
      easing: StrokeEasingCatalog.byId(
        stows.lastAdvancedPencilEndEasingId.value,
      ),
    ),
    easing: StrokeEasingCatalog.byId(
      stows.lastAdvancedPencilMainEasingId.value,
    ),
  );

  static StrokeOptions _advancedOptionsFromPrefs() {
    final base = stows.lastAdvancedPenOptions.value;
    return base.copyWith(
      easing: StrokeEasingCatalog.byId(stows.lastAdvancedPenMainEasingId.value),
      start: base.start.copyWith(
        customTaper: base.start.customTaper,
        easing: StrokeEasingCatalog.byId(
          stows.lastAdvancedPenStartEasingId.value,
        ),
      ),
      end: base.end.copyWith(
        customTaper: base.end.customTaper,
        easing: StrokeEasingCatalog.byId(
          stows.lastAdvancedPenEndEasingId.value,
        ),
      ),
    );
  }

  static StrokeOptions _advancedPencilOptionsFromPrefs() {
    final base = stows.lastAdvancedPencilOptions.value;
    return base.copyWith(
      easing: StrokeEasingCatalog.byId(
        stows.lastAdvancedPencilMainEasingId.value,
      ),
      start: base.start.copyWith(
        customTaper: base.start.customTaper,
        easing: StrokeEasingCatalog.byId(
          stows.lastAdvancedPencilStartEasingId.value,
        ),
      ),
      end: base.end.copyWith(
        customTaper: base.end.customTaper,
        easing: StrokeEasingCatalog.byId(
          stows.lastAdvancedPencilEndEasingId.value,
        ),
      ),
    );
  }

  /// Built-in fast noise preset (not shared with Advanced Pen presets).
  static Map<String, dynamic> defaultAdvancedPencilPresetPayload() {
    final opts = advancedPencilOptions;
    final paint = StrokePaint.pencilNoiseDefault();
    return {
      'name': 'Default',
      'options': opts.toJson(),
      'colorArgb': 0xFF374151,
      'easingId': StrokeEasingCatalog.identity,
      'startEasingId': StrokeEasingCatalog.easeInOut,
      'endEasingId': StrokeEasingCatalog.easeOutCubic,
      'paint': paint.toJson(embedBytes: false),
    };
  }

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

  /// Freehand ink tools that can be applied to an existing selection.
  static const List<ToolId> convertibleInkToolIds = [
    ToolId.fountainPen,
    ToolId.ballpointPen,
    ToolId.calligraphyPen,
    ToolId.advancedPen,
    ToolId.advancedPencil,
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
      ToolId.advancedPencil => Pen.advancedPencil(),
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
      ToolId.advancedPencil => t.editor.pens.advancedPencil,
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
      ToolId.advancedPencil => advancedPencilIcon,
      ToolId.highlighter => Highlighter.highlighterIcon,
      _ => FontAwesomeIcons.pen,
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
    if (newToolId == ToolId.advancedPencil && !paint.usesPencilNoise) {
      paint = paint.copyWith(mode: StrokePaintMode.pencilNoise);
    } else if (newToolId != ToolId.advancedPencil) {
      paint = const StrokePaint();
    }

    return stroke.rebuildWithTool(
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
    );
  }
}
