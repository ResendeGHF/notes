// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';

class NoteLayer extends ChangeNotifier {
  NoteLayer({this.name, List<Stroke>? strokes, List<EditorImage>? images})
      : _strokes = strokes ?? [],
        _images = images ?? [];

  final String? name;
  final List<Stroke> _strokes;
  final List<EditorImage> _images;

  List<Stroke> get strokes => _strokes;
  List<EditorImage> get images => _images;

  /// Backing lists for [EditorPage] incremental-save dirty tracking (see
  /// [_SaveDirtyDelegatingList]).
  List<Stroke> get backingStrokes => _strokes;
  List<EditorImage> get backingImages => _images;

  bool get isEmpty => _strokes.isEmpty && _images.isEmpty;

  void insertStroke(Stroke stroke) {
    // Temporal z-order: newer strokes append on top, painted back-to-front so
    // the newest ends on top regardless of pen or color. (An old revision
    // grouped by pen type here; that broke temporal layering, top-first
    // erasing and undo positioning. File order on load is preserved as-is,
    // so already-saved notes render exactly as before.)
    _strokes.add(stroke);
    notifyListeners();
  }

  /// Positional insert for undo/redo restore (exact draw-order slot, clamped).
  /// Does not group or sort: the caller owns positions.
  void insertStrokeAt(Stroke stroke, int index) {
    if (index < 0 || index >= _strokes.length) {
      _strokes.add(stroke);
    } else {
      _strokes.insert(index, stroke);
    }
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
