// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui';

import 'package:saber/components/canvas/_stroke.dart';

/// Groups strokes into horizontal "lines" of writing for per-line recognition.
List<List<Stroke>> clusterStrokesIntoWritingLines(List<Stroke> strokes) {
  if (strokes.isEmpty) return [];

  final withBounds = <({Stroke s, Rect r})>[];
  for (final s in strokes) {
    final r = s.bounds;
    if (r.width >= 0 && r.height >= 0) {
      withBounds.add((s: s, r: r));
    }
  }
  if (withBounds.isEmpty) return [];

  withBounds.sort((a, b) {
    final c = a.r.top.compareTo(b.r.top);
    if (c != 0) return c;
    return a.r.left.compareTo(b.r.left);
  });

  final heights = withBounds.map((e) => e.r.height).toList()..sort();
  final medianH = heights[heights.length ~/ 2];
  final gap = (medianH * 0.45).clamp(12.0, 56.0);

  final lines = <List<Stroke>>[];
  List<Stroke> cur = [withBounds.first.s];
  var lineBottom = withBounds.first.r.bottom;

  for (var i = 1; i < withBounds.length; i++) {
    final item = withBounds[i];
    if (item.r.top > lineBottom + gap) {
      lines.add(cur);
      cur = [item.s];
      lineBottom = item.r.bottom;
    } else {
      cur.add(item.s);
      if (item.r.bottom > lineBottom) lineBottom = item.r.bottom;
    }
  }
  lines.add(cur);
  return lines;
}
