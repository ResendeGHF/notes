// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:defer_pointer/defer_pointer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:saber/data/editor/canvas_background_pattern.dart';
import 'package:saber/components/canvas/_canvas_background_painter.dart';
import 'package:saber/components/canvas/_canvas_painter.dart';
import 'package:saber/components/canvas/_shape_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/canvas_image.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/editor/quill_styles.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/components/canvas/selection_handles_overlay.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:flutter/rendering.dart';

class InnerCanvas extends StatefulWidget {
  const InnerCanvas({
    super.key,
    required this.pageIndex,
    this.redrawPageListenable,
    required this.width,
    required this.height,
    this.isPreview = false,
    this.isPrint = false,
    this.textEditing = false,
    required this.coreInfo,
    required this.currentStroke,
    required this.currentStrokeDetectedShape,
    required this.currentSelection,
    this.selectionPreview,
    this.setAsBackground,
    this.onRenderObjectChange,
    required this.currentToolIsSelect,
    this.interactionRepaintListenable,
    required this.currentScale,
    this.onNoteLinkTap,
    this.eraserPosition,
    this.eraserSize,
    this.eraserDeltaRemoved,
    this.eraserDeltaAdded,
    this.doneSelecting = false,
    this.lineHeight,
    this.lineThickness,
    this.lineColor,
    this.imageCropState,
    this.onCropRectChanged,
    this.overrideInvert,
  });

  final int? lineHeight;
  final int? lineThickness;
  final Color? lineColor;

  final ({EditorImage image, Rect normalizedCrop})? imageCropState;
  final void Function(Rect normalizedCrop)? onCropRectChanged;

  final int pageIndex;
  final Listenable? redrawPageListenable;
  final double width;
  final double height;

  final bool isPreview;
  final bool isPrint;

  final bool textEditing;
  final EditorCoreInfo coreInfo;
  final Stroke? currentStroke;
  final RecognizedUnistroke? currentStrokeDetectedShape;
  final SelectResult? currentSelection;
  final SelectionTransformPreview? selectionPreview;
  final void Function(EditorImage image)? setAsBackground;
  final ValueChanged<RenderObject>? onRenderObjectChange;

  final bool currentToolIsSelect;
  final ValueListenable<int>? interactionRepaintListenable;
  final void Function(NoteLink link)? onNoteLinkTap;

  final double currentScale;
  final Offset? eraserPosition;
  final double? eraserSize;
  final List<Stroke>? eraserDeltaRemoved;
  final List<Stroke>? eraserDeltaAdded;
  final bool doneSelecting;

  final bool? overrideInvert;

  static const defaultBackgroundColor = Color(0xFFFCFCFC);

  static Color getBackgroundColor(BuildContext context, Color? customColor) {
    return customColor ?? defaultBackgroundColor;
  }

  @override
  State<InnerCanvas> createState() => InnerCanvasState();
}

class InnerCanvasState extends State<InnerCanvas> {
  late final ValueNotifier<int> _layer2Repaint;

  bool _linkMarkersCollapsed = true;

  int _lastStrokeCount = 0;
  int _lastLayerOrderHash = 0;
  int _lastLaserStrokeCount = 0;

  Map<int, List<ui.Vertices>> _batchedMeshes = const {};
  Map<int, List<ui.Vertices>> _batchedMeshesExcludingSelection = const {};

  static const int _kMaxVerticesPerBatch = 65535;

  Timer? _shapePreviewTicker;
  final ValueNotifier<int> _shapePreviewRepaint = ValueNotifier(0);
  int _shapePreviewTick = 0;

  bool _isCapturingThumbnail = false;
  final GlobalKey _thumbnailCaptureKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _layer2Repaint = ValueNotifier(0);
    widget.redrawPageListenable?.addListener(_onPageChanged);

    if (widget.coreInfo.pages.isNotEmpty) {
      final page = widget.coreInfo.pages[_safePageIndex];
      _lastLayerOrderHash = _layerOrderHash(page);
      _lastLaserStrokeCount = page.laserStrokes.length;
      final strokes = page.allStrokesInDrawOrder.toList();
      _lastStrokeCount = strokes.length;
      if (widget.currentStroke == null && strokes.isNotEmpty) {
        _batchedMeshes = _buildBatchedMeshes(strokes);
      }
    }
    _syncShapePreviewTicker();
  }

  int _totalStrokesAcrossLayers(EditorPage page) {
    int n = 0;
    for (var i = 0; i < page.layerCount; i++) {
      n += page.layerAt(i).strokes.length;
    }
    return n;
  }

  int _layerOrderHash(EditorPage page) {
    var h = 0;
    for (final i in page.layerOrderIndices) {
      h = h * 31 + i;
    }
    return h;
  }

  int get _safePageIndex {
    final p = widget.coreInfo.pages;
    if (p.isEmpty) return 0;
    return widget.pageIndex.clamp(0, p.length - 1);
  }

  @override
  void didUpdateWidget(InnerCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.redrawPageListenable != oldWidget.redrawPageListenable) {
      oldWidget.redrawPageListenable?.removeListener(_onPageChanged);
      widget.redrawPageListenable?.addListener(_onPageChanged);
    }
    _syncShapePreviewTicker();

    final pages = widget.coreInfo.pages;
    if (pages.isEmpty) return;
    final safePageIndex = _safePageIndex;
    final oldPages = oldWidget.coreInfo.pages;
    final safeOldPageIndex = oldPages.isEmpty
        ? 0
        : oldWidget.pageIndex.clamp(0, oldPages.length - 1);

    final page = pages[safePageIndex];
    final bool strokeFinished =
        oldWidget.currentStroke != null && widget.currentStroke == null;
    final bool pageChanged = page != oldPages[safeOldPageIndex];
    final bool eraserFinished =
        oldWidget.eraserPosition != null && widget.eraserPosition == null;

    final bool selectionCleared =
        (oldWidget.currentSelection != null &&
            !oldWidget.currentSelection!.isEmpty) &&
        (widget.currentSelection == null || widget.currentSelection!.isEmpty);

    final int quickStrokeCount = _totalStrokesAcrossLayers(page);
    final int layerOrderHash = _layerOrderHash(page);
    final bool isEraserActive = widget.eraserPosition != null;

    if (!pageChanged &&
        !strokeFinished &&
        !eraserFinished &&
        !selectionCleared &&
        quickStrokeCount == _lastStrokeCount &&
        layerOrderHash == _lastLayerOrderHash &&
        page.laserStrokes.length == _lastLaserStrokeCount &&
        !isEraserActive &&
        oldWidget.currentSelection == widget.currentSelection &&
        oldWidget.selectionPreview == widget.selectionPreview &&
        oldWidget.currentStroke == widget.currentStroke &&
        oldWidget.currentStrokeDetectedShape == widget.currentStrokeDetectedShape &&
        oldWidget.currentScale == widget.currentScale &&
        oldWidget.width == widget.width &&
        oldWidget.height == widget.height &&
        oldWidget.imageCropState == widget.imageCropState &&
        oldWidget.doneSelecting == widget.doneSelecting &&
        oldWidget.lineHeight == widget.lineHeight &&
        oldWidget.lineThickness == widget.lineThickness &&
        oldWidget.lineColor == widget.lineColor &&
        oldWidget.overrideInvert == widget.overrideInvert &&
        oldWidget.textEditing == widget.textEditing &&
        oldWidget.isPreview == widget.isPreview &&
        oldWidget.isPrint == widget.isPrint &&
        identical(oldWidget.eraserDeltaRemoved, widget.eraserDeltaRemoved) &&
        identical(oldWidget.eraserDeltaAdded, widget.eraserDeltaAdded)) {
      return;
    }

    final currentStrokes = page.allStrokesInDrawOrder.toList();
    _lastLayerOrderHash = layerOrderHash;
    _lastLaserStrokeCount = page.laserStrokes.length;

    final bool contentChanged = currentStrokes.length != _lastStrokeCount;

    if (pageChanged) {
      _layer2Repaint.value++;
    } else if (isEraserActive) {
      _layer2Repaint.value++;
    } else if (eraserFinished) {
      _layer2Repaint.value++;
      if (widget.currentStroke == null && currentStrokes.isNotEmpty) {
        _disposeBatchedMeshes();
        _batchedMeshes = _buildBatchedMeshes(currentStrokes);
      } else if (currentStrokes.isEmpty) {
        _disposeBatchedMeshes();
        _batchedMeshes = const {};
      }
    } else if (strokeFinished || contentChanged || selectionCleared) {
      _layer2Repaint.value++;
    }

    _lastStrokeCount = currentStrokes.length;

    if (widget.currentStroke == null &&
        (strokeFinished || contentChanged || pageChanged || selectionCleared) &&
        currentStrokes.isNotEmpty) {
      _disposeBatchedMeshes();
      _batchedMeshes = _buildBatchedMeshes(currentStrokes);
    }

    if (widget.currentSelection != null &&
        widget.currentSelection!.strokes.isNotEmpty) {
      final excluded = widget.currentSelection!.strokes.toSet();
      final remaining = currentStrokes
          .where((s) => !excluded.contains(s))
          .toList();
      _disposeBatchedMeshesExcludingSelection();
      _batchedMeshesExcludingSelection = remaining.isEmpty
          ? const {}
          : _buildBatchedMeshes(remaining);
    } else {
      _disposeBatchedMeshesExcludingSelection();
      _batchedMeshesExcludingSelection = const {};
    }
  }

  void _disposeBatchedMeshes() {
    for (final list in _batchedMeshes.values) {
      for (final v in list) v.dispose();
    }
  }

  void _disposeBatchedMeshesExcludingSelection() {
    for (final list in _batchedMeshesExcludingSelection.values) {
      for (final v in list) v.dispose();
    }
  }

  @override
  void dispose() {
    _shapePreviewTicker?.cancel();
    _shapePreviewRepaint.dispose();
    _disposeBatchedMeshesExcludingSelection();
    widget.redrawPageListenable?.removeListener(_onPageChanged);
    _layer2Repaint.dispose();
    super.dispose();
  }

  bool get _shouldAnimateShapePreview =>
      widget.currentStroke != null && widget.currentStrokeDetectedShape != null;

  bool get _isEraserActive => widget.eraserPosition != null;

  void _syncShapePreviewTicker() {
    _shapePreviewTicker?.cancel();
    if (!_shouldAnimateShapePreview) return;
    _shapePreviewTicker = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!mounted || !_shouldAnimateShapePreview) return;
      _shapePreviewTick++;
      _shapePreviewRepaint.value++;
    });
  }

  void _onPageChanged() {
    if (widget.currentStroke == null && mounted) {
      final pages = widget.coreInfo.pages;
      if (pages.isEmpty) return;

      final page = pages[_safePageIndex];
      final strokes = page.allStrokesInDrawOrder.toList();
      _lastLayerOrderHash = _layerOrderHash(page);
      _lastLaserStrokeCount = page.laserStrokes.length;
      final countChanged = strokes.length != _lastStrokeCount;
      _lastStrokeCount = strokes.length;
      if (countChanged) {
        _disposeBatchedMeshes();
        _batchedMeshes = strokes.isEmpty
            ? const {}
            : _buildBatchedMeshes(strokes);
        setState(() {});
      } else {
        _layer2Repaint.value++;
      }
    }
  }

  Map<int, List<ui.Vertices>> _buildBatchedMeshes(List<Stroke> strokes) {
    final double scale = widget.currentScale.clamp(0.1, 5.0);
    for (final s in strokes) s.setLodScale(scale);

    final Map<int, List<Stroke>> groups = {};
    for (final s in strokes) {
      if (s.toolId == ToolId.highlighter ||
          s is ShapeStroke)
        continue;
      if (s.vertices == null) continue;
      groups.putIfAbsent(s.color.toARGB32(), () => []).add(s);
    }

    final Map<int, List<ui.Vertices>> batches = {};
    groups.forEach((colorValue, strokeList) {

      final List<List<Stroke>> chunks = [];
      List<Stroke> currentChunk = [];
      int currentVerts = 0;

      for (final s in strokeList) {
        final sPos = s.getRawPositions();
        final sIndices = s.getRawIndices();
        if (sPos.isEmpty || sIndices.isEmpty) continue;
        final int vertCount = sPos.length ~/ 2;
        if (currentVerts + vertCount > _kMaxVerticesPerBatch &&
            currentChunk.isNotEmpty) {
          chunks.add(List<Stroke>.from(currentChunk));
          currentChunk.clear();
          currentVerts = 0;
        }
        currentChunk.add(s);
        currentVerts += vertCount;
      }
      if (currentChunk.isNotEmpty) chunks.add(currentChunk);

      final List<ui.Vertices> listForColor = [];
      for (final chunk in chunks) {
        int totalPos = 0;
        int totalIndices = 0;
        for (final s in chunk) {
          final sPos = s.getRawPositions();
          final sIndices = s.getRawIndices();
          if (sPos.isEmpty || sIndices.isEmpty) continue;
          totalPos += sPos.length;
          final int stripLen = sIndices.length;
          totalIndices += stripLen >= 3 ? (stripLen - 2) * 3 : 0;
        }
        final positions = Float32List(totalPos);
        final indices = Uint16List(totalIndices);
        int posOffset = 0;
        int indexOffset = 0;
        for (final s in chunk) {
          final Float32List sPos = s.getRawPositions();
          final Uint16List sIndices = s.getRawIndices();
          if (sPos.isEmpty || sIndices.isEmpty) continue;
          positions.setAll(posOffset, sPos);
          final int vertexOffset = posOffset ~/ 2;
          for (int i = 0; i + 2 < sIndices.length; i++) {
            indices[indexOffset++] = vertexOffset + sIndices[i];
            indices[indexOffset++] = vertexOffset + sIndices[i + 1];
            indices[indexOffset++] = vertexOffset + sIndices[i + 2];
          }
          posOffset += sPos.length;
        }
        listForColor.add(
          ui.Vertices.raw(ui.VertexMode.triangles, positions, indices: indices),
        );
      }
      if (listForColor.isNotEmpty) batches[colorValue] = listForColor;
    });
    return batches;
  }

  Future<Uint8List?> captureThumbnail() async {
    if (!mounted) return null;

    setState(() {
      _isCapturingThumbnail = true;
    });

    final hasBackgroundImage =
        widget.coreInfo.pages.isNotEmpty &&
        widget.coreInfo.pages[_safePageIndex].backgroundImage != null;
    await Future.delayed(
      hasBackgroundImage
          ? const Duration(milliseconds: 400)
          : const Duration(milliseconds: 50),
    );

    try {
      final boundary =
          _thumbnailCaptureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;

      if (boundary != null) {

        final image = await boundary.toImage(pixelRatio: 0.7);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        return byteData?.buffer.asUint8List();
      }
    } catch (e) {
      debugPrint('Erro ao capturar thumbnail: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isCapturingThumbnail = false;
        });
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final brightness = theme.brightness;
    final invert =
        widget.overrideInvert ??
        (brightness == Brightness.dark
            ? getEffectiveNoteInvertInDarkModeForFile(widget.coreInfo.filePath)
            : false);

    if (widget.overrideInvert == null && brightness == Brightness.dark) {
      return ValueListenableBuilder<Map<String, int>>(
        valueListenable: stows.noteInvertInDarkModeOverrides,
        builder: (context, _, __) {
          final effectiveInvert = getEffectiveNoteInvertInDarkModeForFile(
            widget.coreInfo.filePath,
          );
          return _buildContent(
            context,
            theme,
            colorScheme,
            brightness,
            effectiveInvert,
          );
        },
      );
    }

    return _buildContent(context, theme, colorScheme, brightness, invert);
  }

  Widget _buildContent(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    Brightness brightness,
    bool invert,
  ) {
    final Color backgroundColor = InnerCanvas.getBackgroundColor(
      context,
      widget.coreInfo.backgroundColor,
    );

    if (widget.coreInfo.pages.isEmpty) {
      return SizedBox(width: widget.width, height: widget.height);
    }

    final page = widget.coreInfo.pages[_safePageIndex];

    final quillEditor = widget.coreInfo.pages.isNotEmpty
        ? QuillEditor(
            controller: widget.coreInfo.pages[_safePageIndex].quill.controller,
            config: QuillEditorConfig(
              customStyles: SaberQuillStyles.get(
                invert: invert,
                secondary: colorScheme.secondary,
                lineHeight: widget.coreInfo.lineHeight,
                appBodyTextStyle: theme.textTheme.bodyMedium,
              ),
              scrollable: false,
              autoFocus: false,
              expands: true,
              maxContentWidth:
                  widget.width -
                  widget.coreInfo.lineHeight,
              placeholder: widget.textEditing
                  ? t.editor.quill.typeSomething
                  : null,
              showCursor: true,
              keyboardAppearance: invert ? .dark : .light,
              padding: .only(
                top: widget.coreInfo.lineHeight * 1.2,
                left: widget.coreInfo.lineHeight * 0.5,
                right: widget.coreInfo.lineHeight * 0.5,
                bottom: widget.coreInfo.lineHeight * 0.5,
              ),
            ),
            scrollController: ScrollController(),
            focusNode: widget.coreInfo.pages[_safePageIndex].quill.focusNode,
          )
        : null;

    final Widget content = Stack(
      fit: StackFit.expand,
      children: [

        Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(

                key: ValueKey(
                  'bg_${widget.lineHeight}_${widget.lineThickness}_${widget.lineColor?.value}_${page.marginLeft}_${page.marginRight}_${page.marginTop}_${page.marginBottom}_${page.borderColor.value}',
                ),
                painter: CanvasBackgroundPainter(
                  invert: invert,
                  backgroundColor: () {
                    if (page.backgroundImage != null) {
                      return Colors.white;
                    } else {
                      return page.backgroundColor.value != 0xFFFFFFFF
                          ? page.backgroundColor
                          : backgroundColor;
                    }
                  }(),
                  backgroundPattern: () {
                    if (page.backgroundImage != null) {
                      return CanvasBackgroundPattern.none;
                    } else {
                      return page.backgroundPattern ??
                          widget.coreInfo.backgroundPattern;
                    }
                  }(),

                  lineHeight: widget.lineHeight ?? widget.coreInfo.lineHeight,
                  lineThickness:
                      widget.lineThickness ?? widget.coreInfo.lineThickness,

                  primaryColor:
                      widget.lineColor ??
                      (page.lineColor.value != 0xFF9E9E9E
                          ? page.lineColor
                          : colorScheme.primary),
                  secondaryColor:
                      (widget.lineColor ??
                              (page.lineColor.value != 0xFF9E9E9E
                                  ? page.lineColor
                                  : colorScheme.secondary))
                          .withValues(alpha: 0.5),
                  marginLeft: page.marginLeft,
                  marginRight: page.marginRight,
                  marginTop: page.marginTop,
                  marginBottom: page.marginBottom,
                  borderColor: page.hasLocalBorderColor || (page.marginLeft > 0 || page.marginRight > 0 || page.marginTop > 0 || page.marginBottom > 0)
                      ? page.borderColor
                      : null,
                ),
                size: Size(widget.width, widget.height),
              ),
            ),

            if (page.backgroundImage != null)
              CanvasImage(
                filePath: widget.coreInfo.filePath,
                image: page.backgroundImage!,
                pageSize: Size(widget.width, widget.height),
                setAsBackground: null,
                isBackground: true,
                readOnly: true,
              ),

            Positioned.fill(
              child: IgnorePointer(
                ignoring: widget.coreInfo.readOnly || !widget.textEditing,
                child: quillEditor,
              ),
            ),

            Positioned.fill(
              child: DeferredPointerHandler(
                child: Stack(
                  children: [
                    for (final image in page.allImagesInDrawOrder) ...[
                      CanvasImage(
                        filePath: widget.coreInfo.filePath,
                        image: image,
                        pageSize: Size(widget.width, widget.height),
                        setAsBackground: widget.setAsBackground,
                        readOnly:
                            widget.coreInfo.readOnly ||
                            !widget.currentToolIsSelect,
                        selected:
                            widget.currentSelection?.images.contains(image) ??
                            false,
                        previewRect:
                            (widget.currentSelection?.images.contains(image) ??
                                    false) &&
                                widget.selectionPreview != null
                            ? widget.selectionPreview!.transformRect(
                                image.dstRect,
                              )
                            : null,
                        previewRotationDeg:
                            (widget.currentSelection?.images.contains(image) ??
                                    false) &&
                                widget.selectionPreview != null
                            ? image.rotationDeg +
                                  widget.selectionPreview!.rotationDeltaDeg
                            : null,
                        canvasScale: widget.currentScale,
                        cropPreviewRect:
                            widget.imageCropState != null &&
                                identical(widget.imageCropState!.image, image)
                            ? widget.imageCropState!.normalizedCrop
                            : null,
                        onCropRectChanged: widget.onCropRectChanged,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (!widget.isPreview &&
                !widget.isPrint &&
                widget.onNoteLinkTap != null &&
                widget.coreInfo
                    .linksForPage(
                      widget.coreInfo.pages[_safePageIndex],
                      widget.pageIndex,
                    )
                    .isNotEmpty)
              Positioned(
                top: 10,
                right: 10,
                child: _LinksCard(
                  coreInfo: widget.coreInfo,
                  pageIndex: widget.pageIndex,
                  safePageIndex: _safePageIndex,
                  collapsed: _linkMarkersCollapsed,
                  onToggle: () {
                    setState(() {
                      _linkMarkersCollapsed = !_linkMarkersCollapsed;
                    });
                  },
                  onLinkTap: widget.onNoteLinkTap,
                  colorScheme: colorScheme,
                ),
              ),
          ],
        ),

        IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: CanvasPainter(
                repaint: _layer2Repaint,
                invert: invert,

                spatialGrid: null,
                quadTree: null,
                batchedStrokes: _isEraserActive
                    ? null
                    : (widget.currentSelection != null &&
                              widget.currentSelection!.strokes.isNotEmpty
                          ? (_batchedMeshesExcludingSelection.isNotEmpty
                                ? _batchedMeshesExcludingSelection
                                : null)
                          : (_batchedMeshes.isNotEmpty
                                ? _batchedMeshes
                                : null)),
                lineHeight: widget.lineHeight,
                lineThickness: widget.lineThickness?.toDouble(),
                lineColor: widget.lineColor,
                strokes: page.allStrokesInDrawOrder.toList(),
                laserStrokes: page.laserStrokes,
                currentStroke: null,
                currentSelection: null,
                selectionPreview: null,
                primaryColor: colorScheme.primary,
                page: page,
                showPageIndicator:
                    !widget.isPreview &&
                    (!widget.isPrint || stows.printPageIndicators.value) &&
                    !widget.coreInfo.isInfinite,
                pageIndex: widget.pageIndex,
                totalPages: widget.coreInfo.pages.length,
                currentScale: widget.currentScale,
                defaultTextStyle: theme.textTheme.bodyMedium!,
                eraserPosition: null,
                eraserSize: null,
                doneSelecting: true,
                excludedStrokes:
                    widget.currentSelection != null &&
                        widget.currentSelection!.strokes.isNotEmpty
                    ? widget.currentSelection!.strokes.toSet()
                    : null,
              ),
              size: Size(widget.width, widget.height),
            ),
          ),
        ),

        if (widget.currentStroke != null ||
            widget.currentSelection != null ||
            widget.eraserPosition != null ||
            !widget.doneSelecting)
          IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: CanvasPainter(

                  repaint: Listenable.merge([
                    if (widget.redrawPageListenable != null)
                      widget.redrawPageListenable!,
                    if (widget.interactionRepaintListenable != null)
                      widget.interactionRepaintListenable!,
                    _shapePreviewRepaint,
                  ]),

                  strokes:
                      widget.currentSelection != null &&
                          widget.currentSelection!.strokes.isNotEmpty
                      ? widget.currentSelection!.strokes
                      : const [],
                  spatialGrid: null,
                  laserStrokes: const [],
                  lineHeight: widget.lineHeight,
                  lineThickness: widget.lineThickness
                      ?.toDouble(),
                  lineColor: widget.lineColor,
                  currentStroke: widget.currentStroke,
                  currentStrokeDetectedShape: widget.currentStrokeDetectedShape,
                  shapePreviewPulse: (_shapePreviewTick % 120) / 120.0,
                  currentSelection: widget.currentSelection,
                  selectionPreview: widget.selectionPreview,
                  eraserPosition: widget.eraserPosition,
                  eraserSize: widget.eraserSize,
                  invert: invert,
                  primaryColor: colorScheme.primary,
                  page: page,
                  showPageIndicator: false,
                  pageIndex: widget.pageIndex,
                  totalPages: widget.coreInfo.pages.length,
                  currentScale: widget.currentScale,
                  defaultTextStyle: theme.textTheme.bodyMedium!,
                  doneSelecting: widget.doneSelecting,
                ),
                size: Size(widget.width, widget.height),
              ),
            ),
          ),

        if (widget.currentSelection != null &&
            widget.doneSelecting &&
            !widget.currentSelection!.isEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: widget.interactionRepaintListenable == null
                  ? SelectionHandlesOverlay(
                      selection: widget.currentSelection!,
                      selectionPreview: widget.selectionPreview,
                      primaryColor: colorScheme.primary,
                      invert: invert,
                      currentScale: widget.currentScale,
                    )
                  : ValueListenableBuilder<int>(
                      valueListenable: widget.interactionRepaintListenable!,
                      builder: (context, _, __) {
                        return SelectionHandlesOverlay(
                          selection: widget.currentSelection!,
                          selectionPreview: widget.selectionPreview,
                          primaryColor: colorScheme.primary,
                          invert: invert,
                          currentScale: widget.currentScale,
                        );
                      },
                    ),
            ),
          ),

      ],
    );

    if (_isCapturingThumbnail) {
      return RepaintBoundary(key: _thumbnailCaptureKey, child: content);
    }

    return content;
  }
}

class _LinksCard extends StatelessWidget {
  const _LinksCard({
    required this.coreInfo,
    required this.pageIndex,
    required this.safePageIndex,
    required this.collapsed,
    required this.onToggle,
    required this.onLinkTap,
    required this.colorScheme,
  });

  static const double _width = 280;

  final EditorCoreInfo coreInfo;
  final int pageIndex;
  final int safePageIndex;
  final bool collapsed;
  final VoidCallback onToggle;
  final void Function(NoteLink link)? onLinkTap;
  final ColorScheme colorScheme;

  static String _linkLabel(NoteLink link) {
    if (link.label?.isNotEmpty == true) return link.label!;
    final name = link.targetPath.split('/').last;
    if (link.isRange) {
      return 'p${link.targetPageIndex + 1}-${link.targetPageIndexEnd! + 1}: $name';
    }
    return 'p${link.targetPageIndex + 1}: $name';
  }

  @override
  Widget build(BuildContext context) {
    final links = coreInfo.linksForPage(
      coreInfo.pages[safePageIndex],
      pageIndex,
    );

    return SizedBox(
      width: _width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onToggle,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.92,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.25),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: collapsed ? 0 : 0.5,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      child: Icon(
                        Icons.expand_more,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        collapsed
                            ? 'Links (${links.length})'
                            : 'Hide links',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: collapsed
                ? const SizedBox.shrink()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      Material(
                        color: Colors.transparent,
                        child: Container(
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colorScheme.outline.withValues(alpha: 0.25),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.shadow.withValues(alpha: 0.06),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 0; i < links.length; i++) ...[
                                if (i > 0)
                                  Divider(
                                    height: 1,
                                    indent: 12,
                                    endIndent: 12,
                                    color: colorScheme.outline
                                        .withValues(alpha: 0.2),
                                  ),
                                InkWell(
                                  onTap: () => onLinkTap?.call(links[i]),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.link_rounded,
                                          size: 16,
                                          color: colorScheme.primary,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            _linkLabel(links[i]),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: colorScheme.onSurface,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
