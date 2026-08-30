// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:saber/data/stroke_geometry/stroke_geometry.dart';

import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';

class NoteToolSettings {
  NoteToolSettings({
    this.toolbarColorSlots,
    this.toolbarColorSlotsCount,
    this.penSizePresetSizes,
    this.lastTool,
    this.lastPenType,

    this.fountainPenOptions,
    this.fountainPenColor,
    this.ballpointPenOptions,
    this.ballpointPenColor,
    this.calligraphyPenOptions,
    this.calligraphyPenColor,
    this.highlighterOptions,
    this.highlighterColor,
    this.highlighterOpacity,
    this.highlighterAutoStraightenLines,
    this.highlighterFlatEdge,
    this.shapePenOptions,
    this.shapePenColor,
    this.advancedPenOptions,
    this.advancedPenColor,
    this.advancedPenMainEasingId,
    this.advancedPenStartEasingId,
    this.advancedPenEndEasingId,

    this.laserPointerSize,

    this.eraserSize,
    this.eraserMode,
  });

  final List<String>? toolbarColorSlots;
  final int? toolbarColorSlotsCount;
  final List<double>? penSizePresetSizes;
  final String? lastTool;
  final String? lastPenType;

  final Map<String, dynamic>? fountainPenOptions;
  final int? fountainPenColor;
  final Map<String, dynamic>? ballpointPenOptions;
  final int? ballpointPenColor;
  final Map<String, dynamic>? calligraphyPenOptions;
  final int? calligraphyPenColor;
  final Map<String, dynamic>? highlighterOptions;
  final int? highlighterColor;
  final double? highlighterOpacity;
  final bool? highlighterAutoStraightenLines;
  final bool? highlighterFlatEdge;
  final Map<String, dynamic>? shapePenOptions;
  final int? shapePenColor;
  final Map<String, dynamic>? advancedPenOptions;
  final int? advancedPenColor;
  final String? advancedPenMainEasingId;
  final String? advancedPenStartEasingId;
  final String? advancedPenEndEasingId;

  final double? laserPointerSize;

  final double? eraserSize;
  final int? eraserMode;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (toolbarColorSlots != null) 'cs': toolbarColorSlots,
      if (toolbarColorSlotsCount != null) 'csc': toolbarColorSlotsCount,
      if (penSizePresetSizes != null) 'psp': penSizePresetSizes,
      if (lastTool != null) 'lt': lastTool,
      if (lastPenType != null) 'lpt': lastPenType,
      if (fountainPenOptions != null) 'fpo': fountainPenOptions,
      if (fountainPenColor != null) 'fpc': fountainPenColor,
      if (ballpointPenOptions != null) 'bpo': ballpointPenOptions,
      if (ballpointPenColor != null) 'bpc': ballpointPenColor,
      if (calligraphyPenOptions != null) 'cpo': calligraphyPenOptions,
      if (calligraphyPenColor != null) 'cpc': calligraphyPenColor,
      if (highlighterOptions != null) 'ho': highlighterOptions,
      if (highlighterColor != null) 'hc': highlighterColor,
      if (highlighterOpacity != null) 'hop': highlighterOpacity,
      if (highlighterAutoStraightenLines != null)
        'has': highlighterAutoStraightenLines,
      if (highlighterFlatEdge != null) 'hfe': highlighterFlatEdge,
      if (shapePenOptions != null) 'spo': shapePenOptions,
      if (shapePenColor != null) 'spc': shapePenColor,
      if (advancedPenOptions != null) 'apo': advancedPenOptions,
      if (advancedPenColor != null) 'apc': advancedPenColor,
      if (advancedPenMainEasingId != null) 'ame': advancedPenMainEasingId,
      if (advancedPenStartEasingId != null) 'ase': advancedPenStartEasingId,
      if (advancedPenEndEasingId != null) 'aee': advancedPenEndEasingId,
      if (laserPointerSize != null) 'lps': laserPointerSize,
      if (eraserSize != null) 'es': eraserSize,
      if (eraserMode != null) 'em': eraserMode,
    };
  }

  factory NoteToolSettings.fromJson(Map<String, dynamic> json) {
    return NoteToolSettings(
      toolbarColorSlots: (json['cs'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      toolbarColorSlotsCount: (json['csc'] as num?)?.toInt(),
      penSizePresetSizes: (json['psp'] as List<dynamic>?)
          ?.map((e) => (e as num).toDouble())
          .toList(),
      lastTool: json['lt'] as String?,
      lastPenType: json['lpt'] as String?,
      fountainPenOptions: json['fpo'] == null
          ? null
          : Map<String, dynamic>.from(json['fpo']),
      fountainPenColor: (json['fpc'] as num?)?.toInt(),
      ballpointPenOptions: json['bpo'] == null
          ? null
          : Map<String, dynamic>.from(json['bpo']),
      ballpointPenColor: (json['bpc'] as num?)?.toInt(),
      calligraphyPenOptions: json['cpo'] == null
          ? null
          : Map<String, dynamic>.from(json['cpo']),
      calligraphyPenColor: (json['cpc'] as num?)?.toInt(),
      highlighterOptions: json['ho'] == null
          ? null
          : Map<String, dynamic>.from(json['ho']),
      highlighterColor: (json['hc'] as num?)?.toInt(),
      highlighterOpacity: (json['hop'] as num?)?.toDouble(),
      highlighterAutoStraightenLines: json['has'] as bool?,
      highlighterFlatEdge: json['hfe'] as bool?,
      shapePenOptions: json['spo'] == null
          ? null
          : Map<String, dynamic>.from(json['spo']),
      shapePenColor: (json['spc'] as num?)?.toInt(),
      advancedPenOptions: json['apo'] == null
          ? null
          : Map<String, dynamic>.from(json['apo']),
      advancedPenColor: (json['apc'] as num?)?.toInt(),
      advancedPenMainEasingId: json['ame'] as String?,
      advancedPenStartEasingId: json['ase'] as String?,
      advancedPenEndEasingId: json['aee'] as String?,
      laserPointerSize: (json['lps'] as num?)?.toDouble(),
      eraserSize: (json['es'] as num?)?.toDouble(),
      eraserMode: (json['em'] as num?)?.toInt(),
    );
  }

  String toJsonString() => jsonEncode(toJson());
  static NoteToolSettings? fromJsonString(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      final map = jsonDecode(s) as Map<String, dynamic>?;
      return map != null ? NoteToolSettings.fromJson(map) : null;
    } catch (_) {
      return null;
    }
  }
}

NoteToolSettings captureNoteToolSettings({
  required ToolId lastToolId,
  required ToolId lastPenTypeId,
}) {

  StrokeOptions fountainOpts = stows.lastFountainPenOptions.value;
  int fountainColor = stows.lastFountainPenColor.value;
  StrokeOptions ballpointOpts = stows.lastBallpointPenOptions.value;
  int ballpointColor = stows.lastBallpointPenColor.value;
  StrokeOptions calligraphyOpts = stows.lastCalligraphyPenOptions.value;
  int calligraphyColor = stows.lastCalligraphyPenColor.value;
  StrokeOptions highlighterOpts = stows.lastHighlighterOptions.value;
  int highlighterColor = stows.lastHighlighterColor.value;
  StrokeOptions advancedOpts = stows.lastAdvancedPenOptions.value;
  int advancedColor = stows.lastAdvancedPenColor.value;

  final cp = Pen.currentPen;
  final ch = Highlighter.currentHighlighter;
  if (cp.toolId == ToolId.fountainPen) {
    fountainOpts = cp.options;
    fountainColor = cp.color.value;
  } else if (cp.toolId == ToolId.ballpointPen) {
    ballpointOpts = cp.options;
    ballpointColor = cp.color.value;
  } else if (cp.toolId == ToolId.calligraphyPen) {
    calligraphyOpts = cp.options;
    calligraphyColor = cp.color.value;
  } else if (cp.toolId == ToolId.advancedPen ||
      cp.toolId == ToolId.experimentalPen) {
    advancedOpts = cp.options;
    advancedColor = cp.color.value;
  }

  highlighterOpts = ch.options;
  highlighterColor = ch.color.value;

  return NoteToolSettings(
    toolbarColorSlots: List<String>.from(stows.toolbarColorSlots.value),
    toolbarColorSlotsCount: stows.toolbarColorSlotsCount.value,
    penSizePresetSizes: stows.penSizePresetSizesAsDoubles(),
    lastTool: lastToolId.id,
    lastPenType: lastPenTypeId.id,
    fountainPenOptions: fountainOpts.toJson(),
    fountainPenColor: fountainColor,
    ballpointPenOptions: ballpointOpts.toJson(),
    ballpointPenColor: ballpointColor,
    calligraphyPenOptions: calligraphyOpts.toJson(),
    calligraphyPenColor: calligraphyColor,
    highlighterOptions: highlighterOpts.toJson(),
    highlighterColor: highlighterColor,
    highlighterOpacity: stows.highlighterOpacity.value,
    highlighterAutoStraightenLines: stows.highlighterAutoStraightenLines.value,
    highlighterFlatEdge: stows.highlighterFlatEdge.value,
    shapePenOptions: stows.lastShapePenOptions.value.toJson(),
    shapePenColor: stows.lastShapePenColor.value,
    advancedPenOptions: advancedOpts.toJson(),
    advancedPenColor: advancedColor,
    advancedPenMainEasingId: stows.lastAdvancedPenMainEasingId.value,
    advancedPenStartEasingId: stows.lastAdvancedPenStartEasingId.value,
    advancedPenEndEasingId: stows.lastAdvancedPenEndEasingId.value,
    laserPointerSize: stows.laserPointerSize.value,
    eraserSize: Eraser.currentEraser.size,
    eraserMode: Eraser.currentEraser.mode.index,
  );
}

void applyNoteToolSettings(NoteToolSettings settings) {
  if (settings.toolbarColorSlots != null) {
    stows.toolbarColorSlots.value = List<String>.from(
      settings.toolbarColorSlots!,
    );
  }
  if (settings.toolbarColorSlotsCount != null) {
    stows.toolbarColorSlotsCount.value = settings.toolbarColorSlotsCount!;
  }
  if (settings.penSizePresetSizes != null) {
    stows.normalizePenSizePresetList();
    final n = stows.penSizePresetCount.value;
    final incoming = settings.penSizePresetSizes!;
    final merged = List<String>.generate(
      n,
      (i) => i < incoming.length
          ? incoming[i].toString()
          : stows.penSizePresetSizes.value.length > i
          ? stows.penSizePresetSizes.value[i]
          : '${2 + i}',
    );
    stows.penSizePresetSizes.value = merged;
    stows.normalizePenSizePresetList();
  }
  if (settings.lastTool != null) {
    stows.lastTool.value = ToolId.parsePenType(
      settings.lastTool,
      fallback: ToolId.ballpointPen,
    );
  }
  if (settings.lastPenType != null) {
    stows.lastPenType.value = ToolId.parsePenType(
      settings.lastPenType,
      fallback: ToolId.ballpointPen,
    );
  }

  if (settings.fountainPenOptions != null) {
    stows.lastFountainPenOptions.value = StrokeOptions.fromJson(
      settings.fountainPenOptions!,
    );
  }
  if (settings.fountainPenColor != null) {
    stows.lastFountainPenColor.value = settings.fountainPenColor!;
  }
  if (settings.ballpointPenOptions != null) {
    stows.lastBallpointPenOptions.value = StrokeOptions.fromJson(
      settings.ballpointPenOptions!,
    );
  }
  if (settings.ballpointPenColor != null) {
    stows.lastBallpointPenColor.value = settings.ballpointPenColor!;
  }
  if (settings.calligraphyPenOptions != null) {
    stows.lastCalligraphyPenOptions.value = StrokeOptions.fromJson(
      settings.calligraphyPenOptions!,
    );
  }
  if (settings.calligraphyPenColor != null) {
    stows.lastCalligraphyPenColor.value = settings.calligraphyPenColor!;
  }
  if (settings.highlighterOptions != null) {
    stows.lastHighlighterOptions.value = StrokeOptions.fromJson(
      settings.highlighterOptions!,
    );
  }
  if (settings.highlighterColor != null) {
    stows.lastHighlighterColor.value = settings.highlighterColor!;
  }
  if (settings.highlighterOpacity != null) {
    stows.highlighterOpacity.value = settings.highlighterOpacity!;
  }
  if (settings.highlighterAutoStraightenLines != null) {
    stows.highlighterAutoStraightenLines.value =
        settings.highlighterAutoStraightenLines!;
  }
  if (settings.highlighterFlatEdge != null) {
    stows.highlighterFlatEdge.value = settings.highlighterFlatEdge!;
  }
  if (settings.shapePenOptions != null) {
    stows.lastShapePenOptions.value = StrokeOptions.fromJson(
      settings.shapePenOptions!,
    );
  }
  if (settings.shapePenColor != null) {
    stows.lastShapePenColor.value = settings.shapePenColor!;
  }
  if (settings.advancedPenOptions != null) {
    stows.lastAdvancedPenOptions.value = StrokeOptions.fromJson(
      settings.advancedPenOptions!,
    );
  }
  if (settings.advancedPenColor != null) {
    stows.lastAdvancedPenColor.value = settings.advancedPenColor!;
  }
  if (settings.advancedPenMainEasingId != null) {
    stows.lastAdvancedPenMainEasingId.value = settings.advancedPenMainEasingId!;
  }
  if (settings.advancedPenStartEasingId != null) {
    stows.lastAdvancedPenStartEasingId.value =
        settings.advancedPenStartEasingId!;
  }
  if (settings.advancedPenEndEasingId != null) {
    stows.lastAdvancedPenEndEasingId.value = settings.advancedPenEndEasingId!;
  }

  if (settings.laserPointerSize != null) {
    stows.laserPointerSize.value =
        settings.laserPointerSize!.clamp(4.0, 10.0);
  }

  if (settings.eraserSize != null) {
    Eraser.currentEraser.updateSize = settings.eraserSize!;
  }
  if (settings.eraserMode != null &&
      settings.eraserMode! >= 0 &&
      settings.eraserMode! < EraserMode.values.length) {
    Eraser.currentEraser.updateMode = EraserMode.values[settings.eraserMode!];
  }

  Pen.currentPen = _penFromType(stows.lastPenType.value);
  Highlighter.currentHighlighter =
      Highlighter();
}

Pen _penFromType(ToolId id) {
  switch (id) {
    case ToolId.fountainPen:
      return Pen.fountainPen();
    case ToolId.ballpointPen:
      return Pen.ballpointPen();
    case ToolId.calligraphyPen:
      return Pen.calligraphyPen();
    case ToolId.shapePen:
      return Pen.ballpointPen();
    case ToolId.advancedPen:
      return Pen.advancedPen();
    case ToolId.experimentalPen:
      return Pen.advancedPen();
    default:
      return Pen.ballpointPen();
  }
}
