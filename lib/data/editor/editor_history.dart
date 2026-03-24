// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/editor/_color_change.dart';
import 'package:saber/data/editor/page.dart';

class EditorHistory {
  static const maxHistoryLength = 100;

  final List<EditorHistoryItem> _past = [];

  final List<EditorHistoryItem> _future = [];

  EditorHistoryItem? _lastSaved;

  var _isRedoPossible = false;

  EditorHistoryItem undo() {
    if (_past.isEmpty) throw Exception('Nothing to undo');
    final item = _past.removeLast();
    _future.add(item);
    return item;
  }

  EditorHistoryItem redo() {
    if (_future.isEmpty) throw Exception('Nothing to redo');
    final item = _future.removeLast();
    _past.add(item);
    return item;
  }

  EditorHistoryItem peekUndo() {
    if (_past.isEmpty) throw Exception('Nothing to undo');
    return _past.last;
  }

  EditorHistoryItem peekRedo() {
    if (_future.isEmpty) throw Exception('Nothing to redo');
    return _future.last;
  }

  void recordChange(EditorHistoryItem item) {
    assert(
      item.type != .quillUndoneChange,
      'EditorHistoryItemType.quillUndoneChange is just a hack to make undoing quill changes easier. It should just be recorded as a quill change.',
    );

    _past.add(item);
    if (_past.length > maxHistoryLength) _past.removeAt(0);
    _isRedoPossible = false;
  }

  void markLastChangeAsSaved() {
    _lastSaved = _past.lastOrNull;
  }

  bool get isCurrentStateSaved {
    return _past.lastOrNull == _lastSaved;
  }

  EditorHistoryItem? removeAccidentalStroke() {
    _isRedoPossible = true;
    if (_past.isEmpty) return null;
    assert(_past.last.type == .draw, 'Accidental stroke is not a draw');
    assert(
      _past.last.strokes.length == 1,
      'Accidental strokes should be single-stroke',
    );
    assert(
      _past.last.images.isEmpty,
      'Accidental strokes should not contain images',
    );
    return _past.removeLast();
  }

  bool get canUndo {
    return _past.isNotEmpty;
  }

  bool get canRedo {
    return _isRedoPossible && _future.isNotEmpty;
  }

  set canRedo(bool isRedoPossible) {
    _isRedoPossible = isRedoPossible;
  }

  void clearRedo() {
    _future.clear();
  }
}

class EditorHistoryItem {
  EditorHistoryItem({
    required this.type,
    required this.pageIndex,
    this.pageIndexStart,
    required this.strokes,
    required this.images,
    this.strokesAdded,
    this.offset,
    this.rotation,
    this.scale,
    this.centroid,
    this.page,
    this.pages,
    this.quillChange,
    this.colorChange,
  }) : assert(
         type != .move || (offset != null || rotation != null || scale != null),
         'Offset, rotation, or scale must be provided for move',
       ),
       assert(
         type != .move || pageIndexStart != null,
         'pageIndexStart must be provided for move',
       ),
       assert(
         (type != .deletePage && type != .insertPage) ||
             (page != null || pages != null),
         'Page or pages must be provided for deletePage/insertPage',
       ),
       assert(
         type != .quillChange || quillChange != null,
         'Quill change must be provided for quillChange',
       ),
       assert(
         type != .quillUndoneChange || quillChange != null,
         'Quill change must be provided for quillUndoneChange',
       ),
       assert(
         type != .changeColor || colorChange?.length == strokes.length,
         'colorChange must be provided and contain each of strokes',
       ),
       assert(
         type != .areaErase || strokesAdded != null,
         'strokesAdded must be provided for areaErase',
       );

  final EditorHistoryItemType type;
  final int pageIndex;

  final int? pageIndexStart;
  final List<Stroke> strokes;
  final List<EditorImage> images;

  final List<Stroke>? strokesAdded;
  final Rect? offset;
  final double? rotation;
  final double? scale;
  final Offset? centroid;
  final EditorPage? page;
  final List<EditorPage>? pages;
  final DocChange? quillChange;
  final Map<Stroke, ColorChange>? colorChange;

  EditorHistoryItem copyWith({
    EditorHistoryItemType? type,
    int? pageIndex,
    int? pageIndexStart,
    List<Stroke>? strokes,
    List<EditorImage>? images,
    List<Stroke>? strokesAdded,
    Rect? offset,
    double? rotation,
    double? scale,
    Offset? centroid,
    EditorPage? page,
    List<EditorPage>? pages,
    DocChange? quillChange,
    Map<Stroke, ColorChange>? colorChange,
  }) {
    return EditorHistoryItem(
      type: type ?? this.type,
      pageIndex: pageIndex ?? this.pageIndex,
      pageIndexStart: pageIndexStart ?? this.pageIndexStart,
      strokes: strokes ?? this.strokes,
      images: images ?? this.images,
      strokesAdded: strokesAdded ?? this.strokesAdded,
      offset: offset ?? this.offset,
      rotation: rotation ?? this.rotation,
      scale: scale ?? this.scale,
      centroid: centroid ?? this.centroid,
      page: page ?? this.page,
      pages: pages ?? this.pages,
      quillChange: quillChange ?? this.quillChange,
      colorChange: colorChange ?? this.colorChange,
    );
  }
}

enum EditorHistoryItemType {
  draw,
  erase,

  areaErase,
  deletePage,
  insertPage,
  move,
  quillChange,
  quillUndoneChange,
  changeColor,
}
