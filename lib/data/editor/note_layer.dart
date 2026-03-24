// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/tools/highlighter.dart';

class NoteLayer extends ChangeNotifier {
  NoteLayer({this.name, List<Stroke>? strokes, List<EditorImage>? images})
      : _strokes = strokes ?? [],
        _images = images ?? [];

  final String? name;
  final List<Stroke> _strokes;
  final List<EditorImage> _images;

  List<Stroke> get strokes => _strokes;
  List<EditorImage> get images => _images;

  bool get isEmpty => _strokes.isEmpty && _images.isEmpty;

  void insertStroke(Stroke stroke) {
    int newStrokeColor = stroke.color.toARGB32();
    int index = 0;
    for (final Stroke s in _strokes) {
      final penCmp = s.penType.compareTo(stroke.penType);
      final color = s.color.toARGB32();
      if (penCmp > 0) break;
      if (s.penType == (Highlighter).toString() &&
          penCmp == 0 &&
          color > newStrokeColor) break;
      index++;
    }
    _strokes.insert(index, stroke);
    notifyListeners();
  }

  void removeStroke(Stroke stroke) {
    _strokes.remove(stroke);
    notifyListeners();
  }

  void addImage(EditorImage image) {
    _images.add(image);
    notifyListeners();
  }

  void removeImage(EditorImage image) {
    _images.remove(image);
    notifyListeners();
  }

  void redrawStrokes() => notifyListeners();
}
