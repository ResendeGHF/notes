// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:saber/components/canvas/_asset_cache.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/binary_writer.dart';
import 'package:saber/data/editor/canvas_background_pattern.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
import 'package:saber/data/editor/note_layer.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/laser_pointer.dart';

typedef CanvasKey = GlobalKey<State<InnerCanvas>>;

const int _kMaxLayers = 4;

enum PageOrientation {
  portrait,
  landscape,
}

extension PageOrientationExtension on PageOrientation {

  Size get defaultSize => switch (this) {
        PageOrientation.portrait => EditorPage.defaultSize,
        PageOrientation.landscape => Size(
            EditorPage.defaultHeight,
            EditorPage.defaultWidth,
          ),
      };
}

class HasSize {
  const HasSize(this.size);
  final Size size;
}

class EditorPage extends ChangeNotifier implements HasSize {
  static const double defaultWidth = 1000;
  static const double defaultHeight = defaultWidth * 1.4;
  static const Size defaultSize = Size(defaultWidth, defaultHeight);

  int? id;

  QuadTree<Stroke>? strokeSpatialIndex;

  void buildSpatialIndex() {
    final s = size;
    strokeSpatialIndex = QuadTree<Stroke>(
      Rect.fromLTWH(0, 0, s.width, s.height),
      capacity: 10,
    );
    for (final stroke in allStrokesInDrawOrder) {
      strokeSpatialIndex!.insert(stroke);
    }
  }

  bool hasLocalPattern = false;
  bool hasLocalBackgroundColor = false;
  bool hasLocalLineColor = false;
  bool hasLocalLineHeight = false;
  bool hasLocalLineThickness = false;
  bool hasLocalMargins = false;
  bool hasLocalBorderColor = false;

  double marginLeft = 0;
  double marginRight = 0;
  double marginTop = 0;
  double marginBottom = 0;

  int? _borderColor;
  Color get borderColor => _borderColor != null ? Color(_borderColor!) : backgroundColor;
  set borderColor(Color value) {
    if (_borderColor == value.value) return;
    _borderColor = value.value;
    notifyListeners();
  }

  int lineHeight = 40;
  double lineThickness = 1.0;

  final Size _baseSize;

  @override
  Size get size => _sizeOverride ?? _baseSize;

  Size? _sizeOverride;

  late final CanvasKey innerCanvasKey = CanvasKey();
  RenderBox? _renderBox;
  RenderBox? get renderBox {
    if (_renderBox != null && _renderBox!.attached) {
      return _renderBox;
    }
    _renderBox =
        innerCanvasKey.currentState?.context.findRenderObject() as RenderBox?;
    return _renderBox;
  }

  bool _isRendered = false;
  bool get isRendered => _isRendered;
  set isRendered(bool isRendered) {
    if (isRendered == _isRendered) return;
    _isRendered = isRendered;

    _renderBox = null;
  }

  final List<NoteLayer> _layers;
  final List<LaserStroke> laserStrokes;
  final QuillStruct quill;

  List<int> _layerOrder;

  int _activeLayerIndex = 0;

  int get activeLayerIndex => _activeLayerIndex;
  set activeLayerIndex(int v) {
    if (_activeLayerIndex == v) return;
    _activeLayerIndex = v.clamp(0, _layers.length - 1);
    notifyListeners();
  }

  int get layerCount => _layers.length;

  List<Stroke> get strokes => _layers[_activeLayerIndex].strokes;

  List<EditorImage> get images => _layers[_activeLayerIndex].images;

  Iterable<Stroke> get allStrokesInDrawOrder =>
      _layerOrder.expand((i) => _layers[i].strokes);

  Iterable<EditorImage> get allImagesInDrawOrder =>
      _layerOrder.expand((i) => _layers[i].images);

  bool addLayer() {
    if (_layers.length >= _kMaxLayers) return false;
    _layers.add(NoteLayer(name: 'Layer ${_layers.length + 1}'));
    _layerOrder.add(_layers.length - 1);
    notifyListeners();
    return true;
  }

  void removeLayer(int index) {
    if (index <= 0 || index >= _layers.length) return;
    final layer = _layers[index];
    for (final s in layer.strokes) _layers[0].insertStroke(s);
    for (final img in layer.images) _layers[0].addImage(img);
    _layers.removeAt(index);
    _layerOrder.removeWhere((i) => i == index);
    _layerOrder = _layerOrder.map((i) => i > index ? i - 1 : i).toList();
    if (_activeLayerIndex >= _layers.length) _activeLayerIndex = _layers.length - 1;
    if (_activeLayerIndex > index) _activeLayerIndex--;
    notifyListeners();
  }

  void moveLayerUp(int orderIndex) {
    if (orderIndex <= 0 || orderIndex >= _layerOrder.length) return;
    final t = _layerOrder[orderIndex];
    _layerOrder[orderIndex] = _layerOrder[orderIndex - 1];
    _layerOrder[orderIndex - 1] = t;
    notifyListeners();
  }

  void moveLayerDown(int orderIndex) {
    if (orderIndex < 0 || orderIndex >= _layerOrder.length - 1) return;
    final t = _layerOrder[orderIndex];
    _layerOrder[orderIndex] = _layerOrder[orderIndex + 1];
    _layerOrder[orderIndex + 1] = t;
    notifyListeners();
  }

  NoteLayer layerAt(int index) => _layers[index];

  List<int> get layerOrderIndices => List.unmodifiable(_layerOrder);

  void replaceLayersFromBinary(List<NoteLayer> layers, List<int> order) {
    _layers.clear();
    _layers.addAll(layers);
    _layerOrder.clear();
    _layerOrder.addAll(order);
    _activeLayerIndex = _activeLayerIndex.clamp(0, _layers.length - 1);
    notifyListeners();
  }

  void removeStrokeFromAnyLayer(Stroke stroke) {
    for (final layer in _layers) {
      if (layer.strokes.remove(stroke)) {
        notifyListeners();
        return;
      }
    }
  }

  void removeImageFromAnyLayer(EditorImage image) {
    for (final layer in _layers) {
      if (layer.images.remove(image)) {
        notifyListeners();
        return;
      }
    }
  }

  CanvasBackgroundPattern? backgroundPattern;
  EditorImage? backgroundImage;

  int _lineColor = 0xFF9E9E9E;
  Color get lineColor => Color(_lineColor);
  set lineColor(Color value) {
    if (_lineColor == value.value) return;
    _lineColor = value.value;
    notifyListeners();
  }

  int _backgroundColor = 0xFFFFFFFF;
  Color get backgroundColor => Color(_backgroundColor);
  set backgroundColor(Color value) {
    if (_backgroundColor == value.value) return;
    _backgroundColor = value.value;
    notifyListeners();
  }

  bool get isEmpty =>
      _layers.every((l) => l.isEmpty) &&
      quill.controller.document.isEmpty() &&
      backgroundImage == null &&
      backgroundPattern == null;
  bool get isNotEmpty => !isEmpty;

  double previewHeight() {

    assert(size.height != 0);
    assert(size.width != 0);
    if (size.height == 0 || size.width == 0) {
      return 0;
    }

    if (backgroundImage != null) {
      return size.height;
    }

    double maxY = 0;
    for (final stroke in allStrokesInDrawOrder) {
      maxY = math.max(maxY, stroke.maxY);
    }
    for (final image in allImagesInDrawOrder) {
      maxY = math.max(maxY, image.dstRect.bottom);
    }
    if (!quill.controller.document.isEmpty()) {

      int linesOfText = quill.controller.document
          .toPlainText()
          .split('\n')
          .length;
      maxY = math.max(maxY, linesOfText * lineHeight * 1.5);
    }

    final fullHeight = size.height;

    final croppedHeight = math.min(fullHeight, math.max(maxY, 0) + (0.1 * fullHeight));

    return croppedHeight;
  }

  Rect getContentBounds() {
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final stroke in allStrokesInDrawOrder) {
      final b = stroke.bounds;
      minX = math.min(minX, b.left);
      minY = math.min(minY, b.top);
      maxX = math.max(maxX, b.right);
      maxY = math.max(maxY, b.bottom);
    }
    for (final image in allImagesInDrawOrder) {
      final r = image.dstRect;
      minX = math.min(minX, r.left);
      minY = math.min(minY, r.top);
      maxX = math.max(maxX, r.right);
      maxY = math.max(maxY, r.bottom);
    }
    if (backgroundImage != null) {
      final r = backgroundImage!.dstRect;
      minX = math.min(minX, r.left);
      minY = math.min(minY, r.top);
      maxX = math.max(maxX, r.right);
      maxY = math.max(maxY, r.bottom);
    }
    if (!quill.controller.document.isEmpty()) {
      final lines = quill.controller.document.toPlainText().split('\n').length;
      final textHeight = lines * lineHeight * 1.5;
      minX = math.min(minX, 0);
      minY = math.min(minY, 0);
      maxX = math.max(maxX, size.width);
      maxY = math.max(maxY, textHeight);
    }
    if (minX == double.infinity) return Rect.zero;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  void ensureMinimumSize(Size minSize) {
    final s = size;
    if (s.width >= minSize.width && s.height >= minSize.height) return;
    resizeInfiniteCanvas(Size(math.max(s.width, minSize.width), math.max(s.height, minSize.height)));
    buildSpatialIndex();
  }

  void resizeInfiniteCanvas(Size newSize, {Offset contentOffset = Offset.zero}) {
    if (contentOffset != Offset.zero) {
      for (final layer in _layers) {
        for (final stroke in layer.strokes) {
          stroke.shift(contentOffset);
        }
        for (final img in layer.images) {
          img.dstRect = img.dstRect.shift(contentOffset);
        }
      }
      if (backgroundImage != null) {
        backgroundImage!.dstRect = backgroundImage!.dstRect.shift(contentOffset);
      }
    }
    _sizeOverride = newSize;
    strokeSpatialIndex = null;
    notifyListeners();
  }

  void trimWhitespace({double buffer = 50}) {
    final bounds = getContentBounds();
    if (bounds == Rect.zero || bounds.isEmpty) return;
    final s = size;
    double newLeft = bounds.left - buffer;
    double newTop = bounds.top - buffer;
    double newRight = bounds.right + buffer;
    double newBottom = bounds.bottom + buffer;
    newLeft = math.max(0, newLeft);
    newTop = math.max(0, newTop);
    newRight = math.min(s.width, newRight);
    newBottom = math.min(s.height, newBottom);
    double newWidth = newRight - newLeft;
    double newHeight = newBottom - newTop;

    const minW = 1600.0;
    const minH = 900.0;
    newWidth = math.max(newWidth, minW);
    newHeight = math.max(newHeight, minH);
    if ((newWidth - s.width).abs() < 1 && (newHeight - s.height).abs() < 1) {
      return;
    }
    resizeInfiniteCanvas(
      Size(newWidth, newHeight),
      contentOffset: Offset(-newLeft, -newTop),
    );
    buildSpatialIndex();
  }

  EditorPage({
    Size? size,
    double? width,
    double? height,
    this.id,
    List<Stroke>? strokes,
    List<EditorImage>? images,
    QuillStruct? quill,
    this.backgroundImage,
    this.backgroundPattern,
    Color? lineColor,
    Color? backgroundColor,
    int? lineHeight,
    double? lineThickness,
    this.hasLocalPattern = false,
    this.hasLocalBackgroundColor = false,
    this.hasLocalLineColor = false,
    this.hasLocalLineHeight = false,
    this.hasLocalLineThickness = false,
    this.hasLocalMargins = false,
    this.hasLocalBorderColor = false,
    Color? borderColor,
    double? marginLeft,
    double? marginRight,
    double? marginTop,
    double? marginBottom,
  }) : assert(
         (size == null) || (width == null && height == null),
         "size and width/height shouldn't both be specified",
       ),
       _baseSize = size ?? Size(width ?? defaultWidth, height ?? defaultHeight),
       laserStrokes = [],
       _layers = [
         NoteLayer(
           name: 'Base',
           strokes: strokes ?? [],
           images: images ?? [],
         )
       ],
       _layerOrder = [0],
       quill =
           quill ??
           QuillStruct(
             controller: QuillController.basic(),
             focusNode: FocusNode(debugLabel: 'Quill Focus Node'),
           ) {
    if (lineColor != null) _lineColor = lineColor.value;
    if (backgroundColor != null) _backgroundColor = backgroundColor.value;
    if (lineHeight != null) this.lineHeight = lineHeight;
    if (lineThickness != null) this.lineThickness = lineThickness;
    if (marginLeft != null) this.marginLeft = marginLeft;
    if (marginRight != null) this.marginRight = marginRight;
    if (marginTop != null) this.marginTop = marginTop;
    if (marginBottom != null) this.marginBottom = marginBottom;
    if (borderColor != null) _borderColor = borderColor.value;
  }

  factory EditorPage.fromJson(
    Map<String, dynamic> json, {
    required List<Uint8List>? inlineAssets,
    required bool readOnly,
    required int fileVersion,
    required String sbnPath,
    required AssetCacheAll assetCacheAll,
  }) {
    final size = Size(json['w'] ?? defaultWidth, json['h'] ?? defaultHeight);
    final id = (json['id'] as num?)?.toInt();
    final hasLayers = json['ly'] != null && (json['ly'] as List).isNotEmpty;
    if (hasLayers) {
      final layersJson = json['ly'] as List;
      final layers = layersJson
          .map((ly) {
            final m = ly as Map<String, dynamic>;
            return NoteLayer(
              name: m['n'] as String?,
              strokes: parseStrokesJson(
                m['s'] as List?,
                page: HasSize(size),
                onlyFirstPage: false,
                fileVersion: fileVersion,
              ),
              images: parseImagesJson(
                m['i'] as List?,
                inlineAssets: inlineAssets,
                isThumbnail: readOnly,
                onlyFirstPage: false,
                sbnPath: sbnPath,
                assetCacheAll: assetCacheAll,
              ),
            );
          })
          .toList();
      final layerOrder = (json['lo'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          List.generate(layers.length, (i) => i);
      final page = EditorPage(
        size: size,
        id: id,
        quill: QuillStruct(
          controller: json['q'] != null
              ? QuillController(
                  document: Document.fromJson(json['q'] as List),
                  selection: const TextSelection.collapsed(offset: 0),
                )
              : QuillController.basic(),
          focusNode: FocusNode(debugLabel: 'Quill Focus Node'),
        ),
        backgroundImage: json['b'] != null
            ? parseImageJson(
                json['b'],
                inlineAssets: inlineAssets,
                isThumbnail: false,
                sbnPath: sbnPath,
                assetCacheAll: assetCacheAll,
              )
            : null,
        backgroundPattern: json['bp'] != null
            ? CanvasBackgroundPattern.values[json['bp']]
            : null,
        lineColor: json['lc'] != null ? Color(json['lc'] as int) : null,
        backgroundColor: json['bc'] != null ? Color(json['bc'] as int) : null,
        lineHeight: json['lh'] ?? 40,
        lineThickness: (json['lt'] ?? 1.0).toDouble(),
        hasLocalPattern: json['hl_bp'] ?? false,
        hasLocalBackgroundColor: json['hl_bc'] ?? false,
        hasLocalLineColor: json['hl_lc'] ?? false,
        hasLocalLineHeight: json['hl_lh'] ?? false,
        hasLocalLineThickness: json['hl_lt'] ?? false,
        hasLocalMargins: json['hl_m'] ?? false,
        hasLocalBorderColor: json['hl_brc'] ?? false,
        borderColor: (json['brc'] as num?) != null ? Color((json['brc'] as num).toInt()) : null,
        marginLeft: (json['ml'] as num?)?.toDouble(),
        marginRight: (json['mr'] as num?)?.toDouble(),
        marginTop: (json['mt'] as num?)?.toDouble(),
        marginBottom: (json['mb'] as num?)?.toDouble(),
      );
      page._layers.clear();
      page._layers.addAll(layers);
      page._layerOrder.clear();
      page._layerOrder.addAll(layerOrder);
      final savedActive = (json['la'] as num?)?.toInt();
      if (savedActive != null && savedActive >= 0 && savedActive < layers.length) {
        page.activeLayerIndex = savedActive;
      }
      return page;
    }
    return EditorPage(
      size: size,
      id: id,
      strokes: parseStrokesJson(
        json['s'] as List?,
        page: HasSize(size),
        onlyFirstPage: false,
        fileVersion: fileVersion,
      ),
      images: parseImagesJson(
        json['i'] as List?,
        inlineAssets: inlineAssets,
        isThumbnail: readOnly,
        onlyFirstPage: false,
        sbnPath: sbnPath,
        assetCacheAll: assetCacheAll,
      ),
      quill: QuillStruct(
        controller: json['q'] != null
            ? QuillController(
                document: Document.fromJson(json['q'] as List),
                selection: const TextSelection.collapsed(offset: 0),
              )
            : QuillController.basic(),
        focusNode: FocusNode(debugLabel: 'Quill Focus Node'),
      ),
      backgroundImage: json['b'] != null
          ? parseImageJson(
              json['b'],
              inlineAssets: inlineAssets,
              isThumbnail: false,
              sbnPath: sbnPath,
              assetCacheAll: assetCacheAll,
            )
          : null,
      backgroundPattern: json['bp'] != null
          ? CanvasBackgroundPattern.values[json['bp']]
          : null,
      lineColor: json['lc'] != null ? Color(json['lc'] as int) : null,
      backgroundColor: json['bc'] != null ? Color(json['bc'] as int) : null,
      lineHeight: json['lh'] ?? 40,
      lineThickness: (json['lt'] ?? 1.0).toDouble(),
      hasLocalPattern: json['hl_bp'] ?? false,
      hasLocalBackgroundColor: json['hl_bc'] ?? false,
      hasLocalLineColor: json['hl_lc'] ?? false,
      hasLocalLineHeight: json['hl_lh'] ?? false,
      hasLocalLineThickness: json['hl_lt'] ?? false,
      hasLocalBorderColor: json['hl_brc'] ?? false,
      borderColor: (json['brc'] as num?) != null ? Color((json['brc'] as num).toInt()) : null,
      hasLocalMargins: json['hl_m'] ?? false,
      marginLeft: (json['ml'] as num?)?.toDouble(),
      marginRight: (json['mr'] as num?)?.toDouble(),
      marginTop: (json['mt'] as num?)?.toDouble(),
      marginBottom: (json['mb'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    final flatStrokes = _layerOrder.expand((i) => _layers[i].strokes).toList();
    final flatImages = _layerOrder.expand((i) => _layers[i].images).toList();
    return {
      'w': size.width,
      'h': size.height,
      if (id != null) 'id': id,
      if (_layers.length == 1) ...{
        if (flatStrokes.isNotEmpty)
          's': flatStrokes.map((stroke) => stroke.toJson()).toList(),
        if (flatImages.isNotEmpty)
          'i': flatImages.map((image) => image.toJson()).toList(),
      } else ...{
        'ly': _layers.map((l) => {
              if (l.name != null) 'n': l.name,
              if (l.strokes.isNotEmpty)
                's': l.strokes.map((s) => s.toJson()).toList(),
              if (l.images.isNotEmpty)
                'i': l.images.map((i) => i.toJson()).toList(),
            }).toList(),
        'lo': _layerOrder,
      },
    if (!quill.controller.document.isEmpty())
      'q': quill.controller.document.toDelta().toJson(),
    if (backgroundImage != null) 'b': backgroundImage?.toJson(),

    'bp': backgroundPattern?.index,
    'lc': _lineColor,
    'bc': _backgroundColor,

    'lh': lineHeight,
    'lt': lineThickness,

    'hl_bp': hasLocalPattern,
    'hl_bc': hasLocalBackgroundColor,
    'hl_lc': hasLocalLineColor,
    'hl_lh': hasLocalLineHeight,
    'hl_lt': hasLocalLineThickness,
    'hl_m': hasLocalMargins,
    'hl_brc': hasLocalBorderColor,
    if (hasLocalMargins) 'ml': marginLeft,
    if (hasLocalMargins) 'mr': marginRight,
    if (hasLocalMargins) 'mt': marginTop,
    if (hasLocalMargins) 'mb': marginBottom,
    if (hasLocalBorderColor && _borderColor != null) 'brc': _borderColor,
    if (_layers.length > 1) 'la': _activeLayerIndex,
    };
  }

  void toBinary(BinaryWriter writer) {
    writer.writeInt(PageBinaryKeys.version, 1);
    if (id != null) {
      writer.writeKey(PageBinaryKeys.pageId);
      writer.writeIntNoKey(id!);
    }
    writer.writeScaledFloat(PageBinaryKeys.width, size.width);
    writer.writeScaledFloat(PageBinaryKeys.height, size.height);

    if (_layers.length > 1) {
      writer.writeKey(PageBinaryKeys.layers);
      writer.writeIntNoKey(_layers.length);
      for (final layer in _layers) {
        writer.writeIntNoKey(layer.strokes.length);
        for (final stroke in layer.strokes) {
          stroke.toBinary(writer);
        }
        writer.writeIntNoKey(layer.images.length);
        for (final image in layer.images) {
          image.toBinary(writer);
        }
      }
      writer.writeIntNoKey(_layerOrder.length);
      for (final i in _layerOrder) {
        writer.writeIntNoKey(i);
      }
    } else {
      final flatStrokes = _layers[0].strokes;
      final flatImages = _layers[0].images;
      if (flatStrokes.isNotEmpty) {
        writer.writeKey(PageBinaryKeys.strokes);
        writer.writeIntNoKey(flatStrokes.length);
        for (final stroke in flatStrokes) {
          stroke.toBinary(writer);
        }
      }
      if (flatImages.isNotEmpty) {
        writer.writeKey(PageBinaryKeys.images);
        writer.writeIntNoKey(flatImages.length);
        for (final image in flatImages) {
          image.toBinary(writer);
        }
      }
    }

    if (!quill.controller.document.isEmpty()) {
      writer.writeKey(PageBinaryKeys.quill);
      writer.writeStringNoKey(
        jsonEncode(quill.controller.document.toDelta().toJson()),
      );
    }

    if (backgroundImage != null) {
      writer.writeKey(PageBinaryKeys.backgroundImage);
      backgroundImage!.toBinary(writer);
    }

    if (backgroundPattern != null) {
      writer.writeKey(PageBinaryKeys.backgroundPattern);
      writer.writeIntNoKey(backgroundPattern!.index);
    }
    writer.writeKey(PageBinaryKeys.lineColor);
    writer.writeIntNoKey(_lineColor);
    writer.writeKey(PageBinaryKeys.backgroundColor);
    writer.writeIntNoKey(_backgroundColor);

    writer.writeKey(PageBinaryKeys.lineHeight);
    writer.writeIntNoKey(lineHeight);

    writer.writeKey(PageBinaryKeys.lineThickness);
    writer.writeFloatNoKey(lineThickness);

    if (_layers.length > 1) {
      writer.writeKey(PageBinaryKeys.activeLayer);
      writer.writeIntNoKey(_activeLayerIndex);
    }

    int flags = 0;
    if (hasLocalPattern) flags |= 1;
    if (hasLocalBackgroundColor) flags |= 2;
    if (hasLocalLineColor) flags |= 4;
    if (hasLocalLineHeight) flags |= 8;
    if (hasLocalLineThickness) flags |= 16;
    if (hasLocalMargins) flags |= 32;
    if (hasLocalBorderColor) flags |= 64;

    writer.writeKey(PageBinaryKeys.localFlags);
    writer.writeIntNoKey(flags);

    if (hasLocalMargins) {
      writer.writeKey(PageBinaryKeys.marginLeft);
      writer.writeScaledFloatNoKey(marginLeft);
      writer.writeKey(PageBinaryKeys.marginRight);
      writer.writeScaledFloatNoKey(marginRight);
      writer.writeKey(PageBinaryKeys.marginTop);
      writer.writeScaledFloatNoKey(marginTop);
      writer.writeKey(PageBinaryKeys.marginBottom);
      writer.writeScaledFloatNoKey(marginBottom);
    }
    if (hasLocalBorderColor && _borderColor != null) {
      writer.writeKey(PageBinaryKeys.borderColor);
      writer.writeIntNoKey(_borderColor!);
    }
  }

  factory EditorPage.fromBinary(
    BinaryReader reader, {
    required bool readOnly,
    required int fileVersion,
    required String sbnPath,
    required AssetCacheAll assetCacheAll,
  }) {
    int key;
    int? pageIdRead;

    if (reader.isEOF) {
      throw Exception('Page.fromBinary: EOF before reading version');
    }
    key = reader.readKey();
    if (key != PageBinaryKeys.version) {
      throw Exception(
        'Page.fromBinary: version not set, got key: $key (expected ${PageBinaryKeys.version})',
      );
    }
    reader.readIntNoKey();

    final keyAfterVersion = reader.peekKey();
    if (keyAfterVersion == PageBinaryKeys.pageId) {
      reader.readKey();
      pageIdRead = reader.readIntNoKey();
    }

    key = reader.readKey();
    if (key != PageBinaryKeys.width) {
      throw Exception('Page.fromBinary: width not set');
    }
    final double width = reader.readScaledFloat();

    key = reader.readKey();
    if (key != PageBinaryKeys.height) {
      throw Exception('Page.fromBinary: height not set');
    }
    final double height = reader.readScaledFloat();
    final Size size = Size(width, height);

    final strokes = <Stroke>[];
    final images = <EditorImage>[];
    List<NoteLayer>? layersRead;
    List<int>? layerOrderRead;
    int? activeLayerRead;
    QuillStruct? quill;
    EditorImage? backgroundImage;
    CanvasBackgroundPattern? backgroundPattern;
    int? lineColor;
    int? backgroundColor;
    int? lineHeight;
    double? lineThickness;
    bool hasLocalPattern = false;
    bool hasLocalBackgroundColor = false;
    bool hasLocalLineColor = false;
    bool hasLocalLineHeight = false;
    bool hasLocalLineThickness = false;
    bool hasLocalMargins = false;
    bool hasLocalBorderColor = false;
    int? borderColorRead;
    double marginLeftRead = 0;
    double marginRightRead = 0;
    double marginTopRead = 0;
    double marginBottomRead = 0;

    while (!reader.isEOF) {

      final nextKey = reader.peekKey();

      if (nextKey == -1) {
        break;
      }

      if (nextKey == PageBinaryKeys.strokes ||
          nextKey == PageBinaryKeys.images ||
          nextKey == PageBinaryKeys.layers ||
          nextKey == PageBinaryKeys.quill ||
          nextKey == PageBinaryKeys.backgroundImage ||
          nextKey == PageBinaryKeys.backgroundPattern ||
          nextKey == PageBinaryKeys.lineColor ||
          nextKey == PageBinaryKeys.backgroundColor ||
      nextKey == PageBinaryKeys.lineHeight ||
      nextKey == PageBinaryKeys.lineThickness ||
      nextKey == PageBinaryKeys.localFlags ||
      nextKey == PageBinaryKeys.pageId ||
      nextKey == PageBinaryKeys.activeLayer ||
      nextKey == PageBinaryKeys.marginLeft ||
      nextKey == PageBinaryKeys.marginRight ||
      nextKey == PageBinaryKeys.marginTop ||
      nextKey == PageBinaryKeys.marginBottom ||
      nextKey == PageBinaryKeys.borderColor) {

        key = reader.readKey();

        switch (key) {
          case PageBinaryKeys.strokes:
            final count = reader.readIntNoKey();
            for (int i = 0; i < count; i++) {
              strokes.add(
                Stroke.fromBinary(
                  reader,
                  fileVersion: fileVersion,
                  page: HasSize(size),
                ),
              );
            }
            break;
          case PageBinaryKeys.images:
            final count = reader.readIntNoKey();
            for (int i = 0; i < count; i++) {
              final imageInfo = EditorImage.readBinary(reader);
              images.add(
                EditorImage.fromBinary(
                  reader,
                  imageInfo: imageInfo,
                  inlineAssets: null,
                  isThumbnail: readOnly,
                  sbnPath: sbnPath,
                  assetCacheAll: assetCacheAll,
                ),
              );
            }
            break;
          case PageBinaryKeys.layers:
            final layerCount = reader.readIntNoKey();
            final readLayers = <NoteLayer>[];
            for (int li = 0; li < layerCount; li++) {
              final strokeCount = reader.readIntNoKey();
              final layerStrokes = <Stroke>[];
              for (int i = 0; i < strokeCount; i++) {
                layerStrokes.add(
                  Stroke.fromBinary(
                    reader,
                    fileVersion: fileVersion,
                    page: HasSize(size),
                  ),
                );
              }
              final imageCount = reader.readIntNoKey();
              final layerImages = <EditorImage>[];
              for (int i = 0; i < imageCount; i++) {
                final imageInfo = EditorImage.readBinary(reader);
                layerImages.add(
                  EditorImage.fromBinary(
                    reader,
                    imageInfo: imageInfo,
                    inlineAssets: null,
                    isThumbnail: readOnly,
                    sbnPath: sbnPath,
                    assetCacheAll: assetCacheAll,
                  ),
                );
              }
              readLayers.add(NoteLayer(
                name: li == 0 ? 'Base' : 'Layer ${li + 1}',
                strokes: layerStrokes,
                images: layerImages,
              ));
            }
            final orderCount = reader.readIntNoKey();
            layerOrderRead = <int>[];
            for (int i = 0; i < orderCount; i++) {
              layerOrderRead.add(reader.readIntNoKey());
            }
            layersRead = readLayers;
            break;
          case PageBinaryKeys.quill:
            final deltaJson = jsonDecode(reader.readStringNoKey());
            quill = QuillStruct(
              controller: QuillController(
                document: Document.fromJson(deltaJson as List),
                selection: const TextSelection.collapsed(offset: 0),
              ),
              focusNode: FocusNode(debugLabel: 'Quill Focus Node'),
            );
            break;
          case PageBinaryKeys.backgroundImage:
            final imageInfo = EditorImage.readBinary(reader);
            backgroundImage = EditorImage.fromBinary(
              reader,
              imageInfo: imageInfo,
              inlineAssets: null,
              isThumbnail: false,
              sbnPath: sbnPath,
              assetCacheAll: assetCacheAll,
            );
            break;
          case PageBinaryKeys.backgroundPattern:
            final patternIndex = reader.readIntNoKey();
            if (patternIndex >= 0 &&
                patternIndex < CanvasBackgroundPattern.values.length) {
              backgroundPattern = CanvasBackgroundPattern.values[patternIndex];
            }
            break;
          case PageBinaryKeys.lineColor:
            lineColor = reader.readIntNoKey();
            break;
          case PageBinaryKeys.backgroundColor:
            backgroundColor = reader.readIntNoKey();
            break;
          case PageBinaryKeys.lineHeight:
            lineHeight = reader.readIntNoKey();
            break;
          case PageBinaryKeys.lineThickness:
            lineThickness = reader.readFloatNoKey();
            break;
          case PageBinaryKeys.localFlags:
            int flags = reader.readIntNoKey();
            hasLocalPattern = (flags & 1) != 0;
            hasLocalBackgroundColor = (flags & 2) != 0;
            hasLocalLineColor = (flags & 4) != 0;
            hasLocalLineHeight = (flags & 8) != 0;
            hasLocalLineThickness = (flags & 16) != 0;
            hasLocalMargins = (flags & 32) != 0;
            hasLocalBorderColor = (flags & 64) != 0;
            break;
          case PageBinaryKeys.marginLeft:
            marginLeftRead = reader.readScaledFloat();
            break;
          case PageBinaryKeys.marginRight:
            marginRightRead = reader.readScaledFloat();
            break;
          case PageBinaryKeys.marginTop:
            marginTopRead = reader.readScaledFloat();
            break;
          case PageBinaryKeys.marginBottom:
            marginBottomRead = reader.readScaledFloat();
            break;
          case PageBinaryKeys.borderColor:
            borderColorRead = reader.readIntNoKey();
            break;
          case PageBinaryKeys.activeLayer:
            activeLayerRead = reader.readIntNoKey();
            break;
        }
      } else if (nextKey == PageBinaryKeys.version) {

        break;
      } else {

        break;
      }
    }

    final page = EditorPage(
      size: size,
      id: pageIdRead,
      strokes: layersRead != null ? [] : strokes,
      images: layersRead != null ? [] : images,
      quill:
          quill ??
          QuillStruct(
            controller: QuillController.basic(),
            focusNode: FocusNode(debugLabel: 'Quill Focus Node'),
          ),
      backgroundImage: backgroundImage,
      backgroundPattern: backgroundPattern,
      lineColor: lineColor != null ? Color(lineColor) : null,
      backgroundColor: backgroundColor != null ? Color(backgroundColor) : null,
      lineHeight: lineHeight,
      lineThickness: lineThickness,
      hasLocalPattern: hasLocalPattern,
      hasLocalBackgroundColor: hasLocalBackgroundColor,
      hasLocalLineColor: hasLocalLineColor,
      hasLocalLineHeight: hasLocalLineHeight,
      hasLocalLineThickness: hasLocalLineThickness,
      hasLocalMargins: hasLocalMargins,
      marginLeft: hasLocalMargins ? marginLeftRead : null,
      marginRight: hasLocalMargins ? marginRightRead : null,
      marginTop: hasLocalMargins ? marginTopRead : null,
      marginBottom: hasLocalMargins ? marginBottomRead : null,
      hasLocalBorderColor: hasLocalBorderColor,
      borderColor: borderColorRead != null ? Color(borderColorRead) : null,
    );
    if (layersRead != null && layerOrderRead != null) {
      page.replaceLayersFromBinary(layersRead, layerOrderRead);
      if (activeLayerRead != null &&
          activeLayerRead >= 0 &&
          activeLayerRead < layersRead.length) {
        page.activeLayerIndex = activeLayerRead;
      }
    }
    return page;
  }

  void insertStroke(Stroke newStroke) {
    _layers[_activeLayerIndex].insertStroke(newStroke);
    notifyListeners();
  }

  void sortStrokes() {
    _layers[_activeLayerIndex].strokes.sort((Stroke a, Stroke b) {
      int penTypeComparison = a.penType.compareTo(b.penType);
      if (penTypeComparison != 0) return penTypeComparison;
      if (a.penType != (Highlighter).toString()) return 0;
      return a.color.toARGB32().compareTo(b.color.toARGB32());
    });
    notifyListeners();
  }

  static List<Stroke> parseStrokesJson(
    List<dynamic>? strokes, {
    required HasSize page,
    required bool onlyFirstPage,
    required int fileVersion,
  }) => (strokes ?? [])
      .map((dynamic stroke) {
        final map = stroke as Map<String, dynamic>;
        final pageIndex = map['i'] ?? 0;
        if (onlyFirstPage && pageIndex > 0) return null;
        return Stroke.fromJson(
          map,
          fileVersion: fileVersion,
          pageIndex: pageIndex,
          page: page,
        );
      })
      .where((element) => element != null)
      .cast<Stroke>()
      .toList();

  static List<EditorImage> parseImagesJson(
    List<dynamic>? images, {
    required List<Uint8List>? inlineAssets,
    required bool isThumbnail,
    required bool onlyFirstPage,
    required String sbnPath,
    required AssetCacheAll assetCacheAll,
  }) =>
      images
          ?.cast<Map<String, dynamic>>()
          .map((Map<String, dynamic> image) {
            if (onlyFirstPage && image['i'] > 0) return null;
            return parseImageJson(
              image,
              inlineAssets: inlineAssets,
              isThumbnail: isThumbnail,
              sbnPath: sbnPath,
              assetCacheAll: assetCacheAll,
            );
          })
          .where((element) => element != null)
          .cast<EditorImage>()
          .toList() ??
      [];

  static EditorImage parseImageJson(
    Map<String, dynamic> json, {
    required List<Uint8List>? inlineAssets,
    required bool isThumbnail,
    required String sbnPath,
    required AssetCacheAll assetCacheAll,
  }) => EditorImage.fromJson(
    json,
    inlineAssets: inlineAssets,
    isThumbnail: isThumbnail,
    sbnPath: sbnPath,
    assetCacheAll: assetCacheAll,
  );

  void redrawStrokes() {
    notifyListeners();
  }

  @override
  void dispose() {
    quill.dispose();
    isRendered = false;
    backgroundImage?.dispose();
    super.dispose();
  }

  EditorPage copyWith({
    Size? size,
    int? id,
    List<Stroke>? strokes,
    List<EditorImage>? images,
    QuillStruct? quill,
    EditorImage? backgroundImage,
    CanvasBackgroundPattern? backgroundPattern,
    Color? lineColor,
    Color? backgroundColor,
  }) => EditorPage(
    size: size ?? this.size,
    id: id ?? this.id,
    strokes: strokes ?? this.strokes,
    images: images ?? this.images,
    quill: quill ?? this.quill,
    backgroundImage: backgroundImage ?? this.backgroundImage,
    backgroundPattern: backgroundPattern ?? this.backgroundPattern,
    lineColor: lineColor ?? this.lineColor,
    backgroundColor: backgroundColor ?? this.backgroundColor,
  );
}

class QuillStruct {
  final QuillController controller;
  late final FocusNode focusNode;
  StreamSubscription? changeSubscription;

  QuillStruct({required this.controller, required this.focusNode});

  void dispose() {
    changeSubscription?.cancel();
    focusNode.dispose();
    controller.dispose();
  }
}
