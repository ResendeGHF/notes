// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_shape_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';

/// Warm high-quality outlines on the current isolate.
///
/// Must not construct [Stroke] or touch [stows] in a new isolate — [Stroke]'s
/// field initializers read prefs and crash off the main isolate.
Future<void> prepareExportStrokePolygons(Iterable<EditorPage> pages) async {
  var computed = 0;
  for (final page in pages) {
    for (final stroke in page.allStrokesInDrawOrder) {
      if (stroke is CircleStroke ||
          stroke is RectangleStroke ||
          stroke is ShapeStroke) {
        continue;
      }
      if (stroke.cachedExportPolygon != null) continue;
      if (stroke.hasCachedHighQualityPolygon) continue;
      try {
        // Existing instance only — Stroke construction reads [stows].
        stroke.highQualityPolygon;
      } catch (_) {
        continue;
      }
      computed++;
      if (computed % 24 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
  }
}
