// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';
import 'package:saber/components/navbar/responsive_navbar.dart';
import 'package:saber/data/editor/canvas_background_pattern.dart';
import 'package:saber/data/editor/stroke_paint.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/pen_stroke_preset_scaling.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:stow/stow.dart';
import 'package:stow_codecs/stow_codecs.dart';
import 'package:stow_plain/stow_plain.dart';

var _isOnMainIsolate = false;

final stows = Stows();

class Stows {
  Stows() {
    recentColorsLength.addListener(() {
      while (recentColorsLength.value < recentColorsPositioned.value.length) {
        final removed = recentColorsChronological.value.removeAt(0);
        recentColorsPositioned.value.remove(removed);
      }
    });
  }

  final backupFilePath = PlainStow('/backupFilePath', '');
  final backupPassword = PlainStow('/backupPassword', '');
  final defaultExportPath = PlainStow('/defaultExportPath', '');
  final autoBackupIntervalMinutes = PlainStow('/autoBackupIntervalMinutes', 0);

  static void markAsOnMainIsolate() {
    _isOnMainIsolate = true;
  }

  final log = Logger('Stows');

  final customDataDir = PlainStow<String?>(
    'customDataDir',
    null,
    volatile: !_isOnMainIsolate,
  );

  final appAccentColor = PlainStow(
    'appAccentColor',
    0xFF673AB7, // Colors.deepPurple (Cor Padrão M3)
    volatile: !_isOnMainIsolate,
  );

  final appTheme = PlainStow(
    'appTheme',
    ThemeMode.system,
    codec: const EnumCodec(ThemeMode.values),
    volatile: !_isOnMainIsolate,
  );

  final layoutSize = PlainStow(
    'layoutSize',
    LayoutSize.auto,
    codec: LayoutSize.codec,
    volatile: !_isOnMainIsolate,
  );

  final hyperlegibleFont = PlainStow(
    'hyperlegibleFont',
    false,
    volatile: !_isOnMainIsolate,
  );

  final editorToolbarAlignment = PlainStow(
    'editorToolbarAlignment',
    AxisDirection.left,
    codec: const EnumCodec(AxisDirection.values),
    volatile: !_isOnMainIsolate,
  );

  final editorAutoInvert = PlainStow(
    'editorAutoInvert',
    true,
    volatile: !_isOnMainIsolate,
  );
  final editorAutoInvertBackground = PlainStow(
    'editorAutoInvertBackground',
    true,
    volatile: !_isOnMainIsolate,
  );

  final enableFingerDrawing = PlainStow(
    'enableFingerDrawing',
    false,
    volatile: !_isOnMainIsolate,
  );
  final preferGreyscale = PlainStow(
    'preferGreyscale',
    false,
    volatile: !_isOnMainIsolate,
  );
  final editorPromptRename = PlainStow(
    'editorPromptRename',
    true,
    volatile: !_isOnMainIsolate,
  );
  final shapeRecognitionDelay = PlainStow(
    'shapeRecognitionDelay',
    850,
    volatile: !_isOnMainIsolate,
  );
  final autoStraightenLines = PlainStow(
    'autoStraightenLines',
    true,
    volatile: !_isOnMainIsolate,
  );

  final autosaveDelay = PlainStow<int>(
    'autosaveDelay',
    300,
    volatile: !_isOnMainIsolate,
  );

  final highlighterAutoStraightenLines = PlainStow(
    'highlighterAutoStraightenLines',
    false,
    volatile: !_isOnMainIsolate,
  );

  final highlighterFlatEdge = PlainStow(
    'highlighterFlatEdge',
    false,
    volatile: !_isOnMainIsolate,
  );

  final highlighterOpacity = PlainStow(
    'highlighterOpacity',
    0.7,
    volatile: !_isOnMainIsolate,
  );

  final strokeStabilization = PlainStow(
    'strokeStabilization',
    true,
    volatile: !_isOnMainIsolate,
  );

  final strokeStabilizationAmount = PlainStow(
    'strokeStabilizationAmount',
    0.15,
    volatile: !_isOnMainIsolate,
  );

  final strokePrediction = PlainStow(
    'strokePrediction',
    true,
    volatile: !_isOnMainIsolate,
  );

  final strokePredictionAmount = PlainStow(
    'strokePredictionAmount',
    0.45,
    volatile: !_isOnMainIsolate,
  );

  final enableMathSolver = PlainStow(
    'enableMathSolver',
    false,
    volatile: !_isOnMainIsolate,
  );

  final printPageIndicators = PlainStow(
    'printPageIndicators',
    false,
    volatile: !_isOnMainIsolate,
  );

  final maxImageSize = PlainStow(
    'maxImageSize',
    1000.0,
    volatile: !_isOnMainIsolate,
  );

  final disableEraserAfterUse = PlainStow(
    'disableEraserAfterUse',
    true,
    volatile: !_isOnMainIsolate,
  );

  final eraserOnStylusButtonPressAndRelease = PlainStow(
    'eraserOnStylusButtonPressAndRelease',
    true,
    volatile: !_isOnMainIsolate,
  );

  final recentColorsChronological = PlainStow(
    'recentColorsChronological',
    <String>[],
    volatile: !_isOnMainIsolate,
  );
  final recentColorsPositioned = PlainStow(
    'recentColorsPositioned',
    <String>[],
    volatile: !_isOnMainIsolate,
  );
  final pinnedColors = PlainStow(
    'pinnedColors',
    <String>[],
    volatile: !_isOnMainIsolate,
  );
  final recentColorsDontSavePresets = PlainStow(
    'dontSavePresetColors',
    false,
    volatile: !_isOnMainIsolate,
  );
  final recentColorsLength = PlainStow(
    'recentColorsLength',
    5,
    volatile: !_isOnMainIsolate,
  );
  final toolbarColorSlotsCount = PlainStow(
    'toolbarColorSlotsCount',
    10,
    volatile: !_isOnMainIsolate,
  );

  static const _defaultToolbarColorSlotsArgb = [
    0xFF374151,
    0xFF1E3A5F,
    0xFF1F2937,
    0xFF134E4A,
    0xFF15803D,
    0xFF7F1D1D,
    0xFF422006,
    0xFF312E81,
    0xFF607D8B,
    0xFF0F172A,
  ];
  final toolbarColorSlots = PlainStow(
    'toolbarColorSlots',
    _defaultToolbarColorSlotsArgb.map((c) => c.toString()).toList(),
    volatile: !_isOnMainIsolate,
  );

  final inkPresetLibraryJson = PlainStow(
    'inkPresetLibraryJsonV1',
    '',
    volatile: !_isOnMainIsolate,
  );

  final activeInkPresetId = PlainStow(
    'activeInkPresetIdV1',
    'studio_default',
    volatile: !_isOnMainIsolate,
  );

  final defaultNotePageOrientationIndex = PlainStow(
    'defaultNotePageOrientation',
    0,
    volatile: !_isOnMainIsolate,
  );

  final penSizePresetCount = PlainStow(
    'penSizePresetCount',
    5,
    volatile: !_isOnMainIsolate,
  );

  static List<String> _defaultPenSizePresetSizeStrings(int count) {
    const defaults = <double>[1.0, 2.0, 3.0, 4.0, 5.0];
    return List<String>.generate(
      count,
      (i) => PenStrokePresetScaling.snapInternal(
        defaults[i.clamp(0, defaults.length - 1)],
      ).toString(),
    );
  }

  final penSizePresetSizes = PlainStow(
    'penSizePresetSizes',
    _defaultPenSizePresetSizeStrings(5),
    volatile: !_isOnMainIsolate,
  );

  void normalizePenSizePresetList() {
    var n = penSizePresetCount.value;
    if (n < 3) n = 3;
    if (n > 7) n = 7;
    if (n != penSizePresetCount.value) {
      penSizePresetCount.value = n;
    }
    final raw = List<String>.from(penSizePresetSizes.value);
    for (var i = 0; i < raw.length; i++) {
      raw[i] = PenStrokePresetScaling.snapInternal(
        PenStrokePresetScaling.parseStored(raw[i]),
      ).toString();
    }
    const fillSeq = <double>[1.0, 2.0, 2.5, 3.0, 4.0, 4.5, 5.0];
    while (raw.length < n) {
      final pick = fillSeq[(raw.length).clamp(0, fillSeq.length - 1)];
      raw.add(PenStrokePresetScaling.snapInternal(pick).toString());
    }
    while (raw.length > n) {
      raw.removeLast();
    }
    penSizePresetSizes.value = raw;
  }

  List<double> penSizePresetSizesAsDoubles() {
    normalizePenSizePresetList();
    return penSizePresetSizes.value
        .map((s) => double.tryParse(s) ?? 2.0)
        .toList();
  }

  final lastTool = PlainStow(
    'lastTool',
    ToolId.ballpointPen,
    codec: ToolId.prefCodec,
    volatile: !_isOnMainIsolate,
  );
  final lastPenType = PlainStow(
    'lastPenType',
    ToolId.ballpointPen,
    codec: ToolId.prefCodec,
    volatile: !_isOnMainIsolate,
  );
  static StrokeOptions _strokeOptionsFromJson(Object json) =>
      StrokeOptions.fromJson(json as Map<String, dynamic>);
  final lastFountainPenOptions = PlainStow.json(
        'lastFountainPenProperties',
        Pen.fountainPenOptions,
        fromJson: _strokeOptionsFromJson,
        volatile: !_isOnMainIsolate,
      ),
      lastBallpointPenOptions = PlainStow.json(
        'lastBallpointPenProperties',
        Pen.ballpointPenOptions,
        fromJson: _strokeOptionsFromJson,
        volatile: !_isOnMainIsolate,
      ),
      lastCalligraphyPenOptions = PlainStow.json(
        'lastCalligraphyPenProperties',
        Pen.calligraphyPenOptions,
        fromJson: _strokeOptionsFromJson,
        volatile: !_isOnMainIsolate,
      ),
      lastHighlighterOptions = PlainStow.json(
        'lastHighlighterProperties',
        Pen.highlighterOptions,
        fromJson: _strokeOptionsFromJson,
        volatile: !_isOnMainIsolate,
      ),
      lastShapePenOptions = PlainStow.json(
        'lastShapePenProperties',
        Pen.shapePenOptions,
        fromJson: _strokeOptionsFromJson,
        volatile: !_isOnMainIsolate,
      ),
      lastAdvancedPenOptions = PlainStow.json(
        'lastAdvancedPenProperties',
        Pen.defaultOptions.copyWith(
          size: 5,
          thinning: 0.45,
          smoothing: 0.55,
          streamline: 0.45,
          simulatePressure: false,
          pressureSensitivity: 1.0,
          velocityThinning: 1.0,
          minSizeRatio: 0.12,
          maxSizeRatio: 1.0,
          start: StrokeEndOptions.start(
            taperEnabled: false,
            customTaper: 0,
            cap: true,
          ),
          end: StrokeEndOptions.end(
            taperEnabled: false,
            customTaper: 0,
            cap: true,
          ),
        ),
        fromJson: _strokeOptionsFromJson,
        volatile: !_isOnMainIsolate,
      ),
      lastAdvancedPencilOptions = PlainStow.json(
        'lastAdvancedPencilProperties',
        Pen.defaultOptions.copyWith(
          size: 2,
          thinning: 0.45,
          smoothing: 0.55,
          streamline: 0.45,
          simulatePressure: true,
          pressureSensitivity: 1.0,
          velocityThinning: 0.15,
          minSizeRatio: 0.12,
          maxSizeRatio: 1.0,
          start: StrokeEndOptions.start(
            taperEnabled: true,
            customTaper: 10,
            cap: true,
          ),
          end: StrokeEndOptions.end(
            taperEnabled: true,
            customTaper: 10,
            cap: true,
          ),
        ),
        fromJson: _strokeOptionsFromJson,
        volatile: !_isOnMainIsolate,
      );
  final lastFountainPenColor = PlainStow('lastFountainPenColor', Colors.black.toARGB32(), volatile: !_isOnMainIsolate), lastBallpointPenColor = PlainStow('lastBallpointPenColor', Colors.black.toARGB32(), volatile: !_isOnMainIsolate), lastCalligraphyPenColor = PlainStow('lastCalligraphyPenColor', Colors.black.toARGB32(), volatile: !_isOnMainIsolate), lastHighlighterColor = PlainStow(
    'lastHighlighterColor',
    Colors.yellow.withValues(alpha: 0.4).toARGB32(),
    volatile: !_isOnMainIsolate,
  ), lastShapePenColor = PlainStow(
    'lastShapePenColor',
    const Color(0xFF5B7C99).toARGB32(),
    volatile: !_isOnMainIsolate,
  ), lastAdvancedPenColor = PlainStow('lastAdvancedPenColor', Colors.black.toARGB32(), volatile: !_isOnMainIsolate), lastAdvancedPencilColor = PlainStow('lastAdvancedPencilColor', 0xFF374151, volatile: !_isOnMainIsolate), lastAdvancedPenMainEasingId = PlainStow('lastAdvancedPenMainEasingId', 'identity', volatile: !_isOnMainIsolate), lastAdvancedPenStartEasingId = PlainStow('lastAdvancedPenStartEasingId', 'easeInOut', volatile: !_isOnMainIsolate), lastAdvancedPenEndEasingId = PlainStow('lastAdvancedPenEndEasingId', 'easeOutCubic', volatile: !_isOnMainIsolate), lastAdvancedPencilMainEasingId = PlainStow('lastAdvancedPencilMainEasingId', 'identity', volatile: !_isOnMainIsolate), lastAdvancedPencilStartEasingId = PlainStow('lastAdvancedPencilStartEasingId', 'easeInOut', volatile: !_isOnMainIsolate), lastAdvancedPencilEndEasingId = PlainStow('lastAdvancedPencilEndEasingId', 'easeOutCubic', volatile: !_isOnMainIsolate), lastAdvancedPenPaint = PlainStow.json('lastAdvancedPenPaint', <String, dynamic>{'m': 0}, volatile: !_isOnMainIsolate), lastAdvancedPencilPaint = PlainStow.json(
    'lastAdvancedPencilPaint',
    StrokePaint.pencilNoiseDefault().toJson(embedBytes: false),
    volatile: !_isOnMainIsolate,
  );

  final lastBallpointPenNeon = PlainStow(
        'lastBallpointPenNeon',
        false,
        volatile: !_isOnMainIsolate,
      ),
      lastFountainPenNeon = PlainStow(
        'lastFountainPenNeon',
        false,
        volatile: !_isOnMainIsolate,
      ),
      lastCalligraphyPenNeon = PlainStow(
        'lastCalligraphyPenNeon',
        false,
        volatile: !_isOnMainIsolate,
      ),
      lastAdvancedPenNeon = PlainStow(
        'lastAdvancedPenNeon',
        false,
        volatile: !_isOnMainIsolate,
      );

  final laserPointerColor = PlainStow(
    'laserPointerColor',
    Colors.red,
    codec: const ColorCodec(),
    volatile: !_isOnMainIsolate,
  );
  final laserPointerSize = PlainStow<double>(
    'laserPointerSize',
    12.0,
    volatile: !_isOnMainIsolate,
  );

  static Map<String, List<int>> get _defaultPenFavoriteColors {
    const modernPalette = <int>[
      0xFF000000,
      0xFF374151,
      0xFF1F2937,
      0xFF1E3A5F,
      0xFF14532D,
      0xFF7F1D1D,
      0xFF422006,
      0xFF134E4A,
      0xFF312E81,
      0xFF1E293B,
    ];
    const laserPalette = <int>[
      0xFFDC2626,
      0xFFB91C1C,
      0xFFEA580C,
      0xFFCA8A04,
      0xFF16A34A,
      0xFF2563EB,
      0xFF7C3AED,
      0xFFDB2777,
      0xFFFFFFFF,
      0xFF000000,
    ];
    const highlighterPalette = <int>[
      0xFFFDE047,
      0xFF86EFAC,
      0xFF93C5FD,
      0xFFF9A8D4,
      0xFFFDBA74,
      0xFFA5B4FC,
      0xFF67E8F9,
      0xFFBEF264,
    ];
    return {
      ToolId.ballpointPen.id: List<int>.from(modernPalette),
      ToolId.calligraphyPen.id: List<int>.from(modernPalette),
      ToolId.fountainPen.id: List<int>.from(modernPalette),
      ToolId.advancedPen.id: List<int>.from(modernPalette),
      ToolId.advancedPencil.id: List<int>.from(modernPalette),
      ToolId.shapePen.id: List<int>.from(modernPalette),
      ToolId.highlighter.id: List<int>.from(highlighterPalette),
      ToolId.laserPointer.id: List<int>.from(laserPalette),
    };
  }

  static const int _penFavoritesCount = 10;

  static const _inkFavoriteToolIds = [
    ToolId.ballpointPen,
    ToolId.calligraphyPen,
    ToolId.fountainPen,
    ToolId.shapePen,
    ToolId.advancedPen,
    ToolId.advancedPencil,
  ];

  static Map<String, List<int>> _penFavoriteColorsFromJson(Object? json) {
    final defaults = _defaultPenFavoriteColors;
    if (json is! Map<String, dynamic>) return defaults;
    final result = <String, List<int>>{};

    List<int>? parseList(dynamic raw, List<int> fallback) {
      if (raw is! List) return null;
      final list = raw
          .map((e) => (e is num) ? e.toInt() : 0xFF000000)
          .take(_penFavoritesCount)
          .toList();
      return list.length >= _penFavoritesCount
          ? list
          : list + fallback.sublist(list.length, _penFavoritesCount);
    }

    for (final entry in defaults.entries) {
      final parsed = parseList(json[entry.key], entry.value);
      if (parsed != null) {
        result[entry.key] = parsed;
      }
    }
    // Older palettes omitted Advanced Pen/Pencil. Inherit the ink row
    // (ballpoint) so suggestions follow the selected color preset.
    final inkFallback =
        result[ToolId.ballpointPen.id] ??
        defaults[ToolId.ballpointPen.id]!;
    for (final tid in _inkFavoriteToolIds) {
      result[tid.id] ??= List<int>.from(inkFallback);
    }
    for (final entry in defaults.entries) {
      result[entry.key] ??= List<int>.from(entry.value);
    }
    return result;
  }

  final penFavoriteColors = PlainStow.json(
    'penFavoriteColors',
    _defaultPenFavoriteColors,
    fromJson: _penFavoriteColorsFromJson,
    volatile: !_isOnMainIsolate,
  );

  static List<Map<String, dynamic>> _advancedPenPresetsFromJson(Object? json) {
    if (json is! List) return [];
    return json
        .map(
          (e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{},
        )
        .toList();
  }

  final advancedPenPresets = PlainStow.json(
    'advancedPenPresets',
    <Map<String, dynamic>>[],
    fromJson: _advancedPenPresetsFromJson,
    volatile: !_isOnMainIsolate,
  );

  final advancedPencilPresets = PlainStow.json(
    'advancedPencilPresets',
    <Map<String, dynamic>>[],
    fromJson: _advancedPenPresetsFromJson,
    volatile: !_isOnMainIsolate,
  );

  final lastBackgroundPattern = PlainStow(
    'lastBackgroundPattern',
    CanvasBackgroundPattern.none,
    codec: CanvasBackgroundPattern.codec,
    volatile: !_isOnMainIsolate,
  );
  static const defaultLineHeight = 40;
  static const defaultLineThickness = 3;
  final lastLineHeight = PlainStow(
    'lastLineHeight',
    defaultLineHeight,
    volatile: !_isOnMainIsolate,
  );
  final lastLineThickness = PlainStow(
    'lastLineThickness',
    defaultLineThickness,
    volatile: !_isOnMainIsolate,
  );

  final defaultPageColor = PlainStow(
    'defaultPageColor',
    0xFFEFEFEF,
    volatile: !_isOnMainIsolate,
  );

  final defaultLineColor = PlainStow(
    'defaultLineColor',
    0xFF9E9E9E,
    volatile: !_isOnMainIsolate,
  );

  final defaultMarginLeft = PlainStow(
    'defaultMarginLeft',
    0.0,
    volatile: !_isOnMainIsolate,
  );
  final defaultMarginRight = PlainStow(
    'defaultMarginRight',
    0.0,
    volatile: !_isOnMainIsolate,
  );
  final defaultMarginTop = PlainStow(
    'defaultMarginTop',
    0.0,
    volatile: !_isOnMainIsolate,
  );
  final defaultMarginBottom = PlainStow(
    'defaultMarginBottom',
    0.0,
    volatile: !_isOnMainIsolate,
  );

  final defaultMarginColor = PlainStow(
    'defaultMarginColor',
    0xFFFFFFFF,
    volatile: !_isOnMainIsolate,
  );

  final lastZoomLock = PlainStow(
        'lastZoomLock',
        false,
        volatile: !_isOnMainIsolate,
      ),
      lastSingleFingerPanLock = PlainStow(
        'lastSingleFingerPanLock',
        false,
        volatile: !_isOnMainIsolate,
      ),
      lastAxisAlignedPanLock = PlainStow(
        'lastAxisAlignedPanLock',
        false,
        volatile: !_isOnMainIsolate,
      );

  double lastCanvasScale = 1.0;
  final recentFiles = PlainStow(
    'recentFiles',
    <String>[],
    volatile: !_isOnMainIsolate,
  );

  final shouldCheckForUpdates = PlainStow(
    'shouldCheckForUpdates',
    FlavorConfig.shouldCheckForUpdatesByDefault && !Platform.isLinux,
    volatile: !_isOnMainIsolate,
  );
  final shouldAlwaysAlertForUpdates = PlainStow(
    'shouldAlwaysAlertForUpdates',
    kDebugMode ? true : false,
    volatile: !_isOnMainIsolate,
  );

  final homeListMode = PlainStow(
    'homeListMode',
    false,
    volatile: !_isOnMainIsolate,
  );

  final homeBrowseTreeView = PlainStow(
    'homeBrowseTreeView',
    false,
    volatile: !_isOnMainIsolate,
  );

  final sortFunctionIdx = PlainStow(
    'sortFunctionIdx',
    0,
    volatile: !_isOnMainIsolate,
  );

  final isSortIncreasing = PlainStow(
    'isSortIncreasing',
    true,
    volatile: !_isOnMainIsolate,
  );

  final browseSortFunctionIdx = PlainStow(
    'browseSortFunctionIdx',
    0,
    volatile: !_isOnMainIsolate,
  );

  final browseIsSortIncreasing = PlainStow(
    'browseIsSortIncreasing',
    true,
    volatile: !_isOnMainIsolate,
  );

  final recentSortFunctionIdx = PlainStow(
    'recentSortFunctionIdx',
    1,
    volatile: !_isOnMainIsolate,
  );

  final recentIsSortIncreasing = PlainStow(
    'recentIsSortIncreasing',
    false,
    volatile: !_isOnMainIsolate,
  );

  final locale = PlainStow('locale', '', volatile: !_isOnMainIsolate);

  final folderColors = PlainStow(
    'folderColors',
    <String, int>{},
    codec: const _MapStringIntCodec(),
    volatile: !_isOnMainIsolate,
  );

  final noteInvertInDarkModeOverrides = PlainStow<Map<String, int>>(
    'noteInvertInDarkModeOverrides',
    {},
    codec: const _MapStringIntCodec(),
    volatile: !_isOnMainIsolate,
  );

  final noteInvertBackgroundOverrides = PlainStow<Map<String, int>>(
    'noteInvertBackgroundOverrides',
    {},
    codec: const _MapStringIntCodec(),
    volatile: !_isOnMainIsolate,
  );

  final localEncryptionEnabled = PlainStow(
    'localEncryptionEnabled',
    false,
    volatile: !_isOnMainIsolate,
  );

  final backupDirectoryPath = PlainStow(
    '/backupDirectoryPath',
    '',
    volatile: !_isOnMainIsolate,
  );
  final autoBackupIntervalHours = PlainStow(
    '/autoBackupIntervalHours',
    0,
    volatile: !_isOnMainIsolate,
  );
  final lastBackupTimestamp = PlainStow(
    '/lastBackupTimestamp',
    0,
    volatile: !_isOnMainIsolate,
  );

  final vaultSecureDelete = PlainStow(
    'vaultSecureDelete',
    false,
    volatile: !_isOnMainIsolate,
  );

  final vaultPdfLoadMode = PlainStow(
    'vaultPdfLoadMode',
    'ram_only',
    volatile: !_isOnMainIsolate,
  );

  final vaultPdfAllowLargeRam = PlainStow(
    'vaultPdfAllowLargeRam',
    false,
    volatile: !_isOnMainIsolate,
  );

  final vaultPdfLoadOverrides = PlainStow<Map<String, String>>(
    'vaultPdfLoadOverrides',
    {},
    codec: const _MapStringStringCodec(),
    volatile: !_isOnMainIsolate,
  );

  final thumbnailOnAutosave = PlainStow(
    'thumbnailOnAutosave',
    true,
    volatile: !_isOnMainIsolate,
  );

  @pragma('vm:platform-const')
  static final isDesktop =
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;
}

class TransformedStow<T_in, T_out> extends Stow<dynamic, T_out, dynamic> {
  final Stow<dynamic, T_in, dynamic> parent;
  final T_out Function(T_in) transform;
  final T_in Function(T_out) reverseTransform;

  @override
  T_out get value => transform(parent.value);

  @override
  set value(T_out value) => parent.value = reverseTransform(value);

  TransformedStow(this.parent, this.transform, this.reverseTransform)
    : super(parent.key, transform(parent.defaultValue), volatile: true) {
    parent.addListener(notifyListeners);
  }

  @override
  Future<dynamic> protectedRead() async => null;

  @override
  Future<void> protectedWrite(dynamic value) async {}

  @override
  String toString() {
    return 'TransformedPref<$T_in, $T_out>(from ${parent.key}, $value)';
  }

  @override
  void dispose() {
    parent.removeListener(notifyListeners);
    super.dispose();
  }
}

class _MapStringIntCodec extends Codec<Map<String, int>, Object?> {
  const _MapStringIntCodec();

  @override
  Converter<Map<String, int>, Object?> get encoder =>
      const _MapStringIntEncoder();

  @override
  Converter<Object?, Map<String, int>> get decoder =>
      const _MapStringIntDecoder();
}

class _MapStringIntEncoder extends Converter<Map<String, int>, Object?> {
  const _MapStringIntEncoder();

  @override
  Object? convert(Map<String, int> input) {
    return jsonEncode(input);
  }
}

class _MapStringIntDecoder extends Converter<Object?, Map<String, int>> {
  const _MapStringIntDecoder();

  @override
  Map<String, int> convert(Object? input) {
    if (input == null) return {};

    if (input is Map) {
      try {
        return input.map((key, val) => MapEntry(key.toString(), val as int));
      } catch (e) {
        return {};
      }
    }

    if (input is String) {
      if (input.isEmpty) return {};
      try {
        final Map<String, dynamic> decoded = jsonDecode(input);

        return decoded.map((key, value) => MapEntry(key, value as int));
      } catch (e) {
        return {};
      }
    }

    return {};
  }
}

class _MapStringStringCodec extends Codec<Map<String, String>, Object?> {
  const _MapStringStringCodec();

  @override
  Converter<Map<String, String>, Object?> get encoder =>
      const _MapStringStringEncoder();

  @override
  Converter<Object?, Map<String, String>> get decoder =>
      const _MapStringStringDecoder();
}

class _MapStringStringEncoder extends Converter<Map<String, String>, Object?> {
  const _MapStringStringEncoder();

  @override
  Object? convert(Map<String, String> input) => jsonEncode(input);
}

class _MapStringStringDecoder extends Converter<Object?, Map<String, String>> {
  const _MapStringStringDecoder();

  @override
  Map<String, String> convert(Object? input) {
    if (input == null) return {};
    if (input is Map) {
      try {
        return input.map(
          (key, val) => MapEntry(key.toString(), val.toString()),
        );
      } catch (_) {
        return {};
      }
    }
    if (input is String && input.isNotEmpty) {
      try {
        final decoded = jsonDecode(input) as Map<dynamic, dynamic>;
        return decoded.map(
          (key, value) =>
              MapEntry(key.toString(), value?.toString() ?? 'default'),
        );
      } catch (_) {
        return {};
      }
    }
    return {};
  }
}

String _normalizePathForOverride(String path) {
  return path.replaceAll('\\', '/').replaceFirst(RegExp(r'^/'), '').trim();
}

String getEffectiveVaultPdfLoadMode(String filePath) {
  final norm = _normalizePathForOverride(filePath);
  final overrides = stows.vaultPdfLoadOverrides.value;

  final exact = overrides[norm];
  if (exact != null && exact != 'default') return exact;

  String? bestMatch;
  int bestLen = 0;
  for (final entry in overrides.entries) {
    if (entry.value == 'default') continue;
    final key = entry.key;
    if (norm.startsWith('$key.') || norm == key) {
      if (key.length > bestLen) {
        bestLen = key.length;
        bestMatch = entry.value;
      }
    }
  }
  if (bestMatch != null) return bestMatch;

  return stows.vaultPdfLoadMode.value;
}

/// True when vault plaintext may be written to a short-lived temp file for this
/// path (effective mode is `temp_file` via global setting or per-note override).
///
/// Scoped to note **assets** (`*.sbn2.<n>`): Secure PDF loading never authorizes
/// plaintext temps for the note body itself. When false (RAM-only), decrypted
/// bytes must stay in memory only — never disk.
bool vaultPathAllowsDiskBackedDecrypt(String filePath) {
  if (getEffectiveVaultPdfLoadMode(filePath) != 'temp_file') return false;
  final norm = _normalizePathForOverride(filePath);
  return RegExp(r'\.sbn2\.\d+$').hasMatch(norm);
}

/// Note PDF/image assets stored as `*.sbn2.<n>` in the vault. When the user
/// chose RAM-only PDF loading, plaintext must not be written to disk.
bool vaultPdfAssetRequiresRamOnlyDecrypt(String filePath) {
  final norm = _normalizePathForOverride(filePath);
  if (!RegExp(r'\.sbn2\.\d+$').hasMatch(norm)) return false;
  return !vaultPathAllowsDiskBackedDecrypt(filePath);
}

String getStoredVaultPdfLoadOverrideForPath(String path) {
  final norm = _normalizePathForOverride(path);
  return stows.vaultPdfLoadOverrides.value[norm] ?? 'default';
}

void setVaultPdfLoadOverrideForFile(String filePath, String? mode) {
  final norm = _normalizePathForOverride(filePath);
  final current = Map<String, String>.from(stows.vaultPdfLoadOverrides.value);
  if (mode == null || mode == 'default') {
    current.remove(norm);
  } else {
    current[norm] = mode;
  }
  stows.vaultPdfLoadOverrides.value = current;
}

/// Keep per-note Secure PDF overrides across rename/move of the note body path.
void remapVaultPdfLoadOverride(String fromFilePath, String toFilePath) {
  final fromNorm = _normalizePathForOverride(fromFilePath);
  final toNorm = _normalizePathForOverride(toFilePath);
  if (fromNorm.isEmpty || toNorm.isEmpty || fromNorm == toNorm) return;
  final current = Map<String, String>.from(stows.vaultPdfLoadOverrides.value);
  final mode = current.remove(fromNorm);
  if (mode == null) return;
  current[toNorm] = mode;
  stows.vaultPdfLoadOverrides.value = current;
}

bool getEffectiveNoteInvertInDarkModeForFile(String filePath) {
  final overrides = stows.noteInvertInDarkModeOverrides.value;
  final override = overrides[filePath];
  if (override == null) {
    return stows.editorAutoInvert.value;
  }
  return override != 0;
}

void setNoteInvertInDarkModeOverrideForFile(String filePath, bool invert) {
  final base = stows.editorAutoInvert.value;
  final current = Map<String, int>.from(
    stows.noteInvertInDarkModeOverrides.value,
  );

  if (invert == base) {
    if (current.remove(filePath) != null) {
      stows.noteInvertInDarkModeOverrides.value = current;
    }
  } else {
    current[filePath] = invert ? 1 : 0;
    stows.noteInvertInDarkModeOverrides.value = current;
  }
}

bool getEffectiveNoteInvertBackgroundForFile(String filePath) {
  final overrides = stows.noteInvertBackgroundOverrides.value;
  final override = overrides[filePath];
  if (override == null) {
    return stows.editorAutoInvertBackground.value;
  }
  return override != 0;
}

void setNoteInvertBackgroundOverrideForFile(String filePath, bool invert) {
  final base = stows.editorAutoInvertBackground.value;
  final current = Map<String, int>.from(
    stows.noteInvertBackgroundOverrides.value,
  );

  if (invert == base) {
    if (current.remove(filePath) != null) {
      stows.noteInvertBackgroundOverrides.value = current;
    }
  } else {
    current[filePath] = invert ? 1 : 0;
    stows.noteInvertBackgroundOverrides.value = current;
  }
}
