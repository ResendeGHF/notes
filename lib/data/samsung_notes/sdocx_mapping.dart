// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:saber/data/editor/canvas_background_pattern.dart';
import 'package:saber/data/tools/_tool.dart';

/// Map a Samsung pen name to the closest Saber tool.
///
/// Samsung preload names (prefix `…pen.preload.` already stripped):
/// ballpoint pens (`InkPen`, `InkPen2`, …) → [ToolId.ballpointPen],
/// `FountainPen` family → [ToolId.fountainPen], calligraphy nibs
/// (`MontblancCalligraphyPen`, `ChineseBrush`, `ObliquePen`) →
/// [ToolId.calligraphyPen], pencils → [ToolId.pencil], markers →
/// [ToolId.highlighter]. Brushes ("bush") and anything unrecognized fall back
/// to [ToolId.ballpointPen] per requirements; translucent unknown ink still
/// behaves like a highlighter.
ToolId samsungPenToToolId(String? penName, {int? colorArgb}) {
  final short = (penName ?? '').trim();
  switch (short) {
    case 'FountainPen':
    case 'MontblancFountainPen':
      return ToolId.fountainPen;
    case 'MontblancCalligraphyPen':
    case 'ChineseBrush':
    case 'ObliquePen':
      return ToolId.calligraphyPen;
    case 'Pencil':
    case 'Pencil2':
    case 'Pencil3':
    case 'ColoredPencil':
      return ToolId.pencil;
    case 'Marker':
    case 'Marker2':
    case 'Marker3':
    case 'Marker4':
    case 'StraightMarker':
    case 'StraightHighlighter':
      return ToolId.highlighter;
    case 'InkPen':
    case 'InkPen2':
    case 'StraightInkPen2':
    case 'DefaultPen':
      return ToolId.ballpointPen;
    default:
      final alpha = colorArgb == null ? 255 : ((colorArgb >> 24) & 0xFF);
      if (alpha < 200) return ToolId.highlighter;
      return ToolId.ballpointPen;
  }
}

/// Map a Samsung page template to Saber's equivalent background pattern.
///
/// Keyword matching on the template URI comes first (most descriptive);
/// otherwise built-in numeric ids apply: 1..3 ruled, 4..6 grid, 7..9
/// dots (each narrow/normal/big, which Saber renders as one pattern),
/// 0/absent/unknown means blank ([CanvasBackgroundPattern.none]).
CanvasBackgroundPattern samsungTemplateToPattern({
  int? templateType,
  String? templateUri,
}) {
  final uri = (templateUri ?? '').toLowerCase();
  if (uri.isNotEmpty) {
    if (uri.contains('grid')) return CanvasBackgroundPattern.grid;
    if (uri.contains('dot')) return CanvasBackgroundPattern.dots;
    if (uri.contains('line') ||
        uri.contains('ruled') ||
        uri.contains('lined') ||
        uri.contains('college')) {
      return CanvasBackgroundPattern.lined;
    }
    if (uri.contains('blank') ||
        uri.contains('none') ||
        uri.contains('plain')) {
      return CanvasBackgroundPattern.none;
    }
    if (uri.contains('staff') || uri.contains('music')) {
      return CanvasBackgroundPattern.staffs;
    }
    if (uri.contains('cornell')) return CanvasBackgroundPattern.cornell;
    if (uri.contains('calligraphy')) {
      return CanvasBackgroundPattern.calligraphy;
    }
    if (uri.contains('tab')) return CanvasBackgroundPattern.tablature;
  }
  switch (templateType) {
    case 1:
    case 2:
    case 3:
      return CanvasBackgroundPattern.lined;
    case 4:
    case 5:
    case 6:
      return CanvasBackgroundPattern.grid;
    case 7:
    case 8:
    case 9:
      return CanvasBackgroundPattern.dots;
    default:
      return CanvasBackgroundPattern.none;
  }
}
