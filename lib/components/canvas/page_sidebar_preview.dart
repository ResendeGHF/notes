// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:saber/components/canvas/_canvas_background_painter.dart';
import 'package:saber/components/canvas/canvas_image.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
import 'package:saber/data/editor/canvas_background_pattern.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/editor/quill_styles.dart';
import 'package:saber/data/prefs.dart';

/// Serializes sidebar preview bakes so opening the panel does not run many
/// sync raster passes on the UI isolate at once.
final class _SidebarPreviewBakeQueue {
  _SidebarPreviewBakeQueue._();

  static Future<void> _tail = Future<void>.value();

  static Future<T> run<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }
}

/// Docked pages-sidebar preview: background + baked stroke raster LOD +
/// optional images/quill scaled to [displaySize] (no full-page InnerCanvas).
class PageSidebarPreview extends StatefulWidget {
  const PageSidebarPreview({
    super.key,
    required this.pageIndex,
    required this.coreInfo,
    required this.displaySize,
  });

  final int pageIndex;
  final EditorCoreInfo coreInfo;
  final Size displaySize;

  @override
  State<PageSidebarPreview> createState() => _PageSidebarPreviewState();
}

class _PageSidebarPreviewState extends State<PageSidebarPreview> {
  ui.Image? _inkRaster;
  bool _baking = false;
  int _bakeGeneration = 0;
  int _lastObservedRevision = -1;
  late final ScrollController _quillScrollController = ScrollController();

  /// Page instance this state currently listens to. Tracked directly (instead
  /// of re-resolving by index) so listener removal never touches a shrunk
  /// page list during unmount after page deletions.
  EditorPage? _listenedPage;

  /// Null when [PageSidebarPreview.pageIndex] no longer addresses a page
  /// (e.g. pages were deleted while this preview was mounted). All readers
  /// must handle null instead of throwing a RangeError.
  EditorPage? get _page {
    final pages = widget.coreInfo.pages;
    final index = widget.pageIndex;
    if (index < 0 || index >= pages.length) return null;
    return pages[index];
  }

  void _attachPageListener() {
    final page = _page;
    if (identical(page, _listenedPage)) return;
    _detachPageListener();
    _listenedPage = page;
    page?.addListener(_onPageChanged);
    _lastObservedRevision = page?.saveBinaryRevision ?? -1;
  }

  void _detachPageListener() {
    _listenedPage?.removeListener(_onPageChanged);
    _listenedPage = null;
  }

  @override
  void initState() {
    super.initState();
    _attachPageListener();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleBake());
  }

  @override
  void didUpdateWidget(covariant PageSidebarPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageIndex != widget.pageIndex ||
        !identical(oldWidget.coreInfo, widget.coreInfo)) {
      _detachPageListener();
      _attachPageListener();
      // Keep the previous raster only when still showing the same instance.
      _inkRaster = null;
    }
    _scheduleBake();
  }

  @override
  void dispose() {
    _detachPageListener();
    _quillScrollController.dispose();
    super.dispose();
  }

  void _onPageChanged() {
    if (!mounted) return;
    final page = _listenedPage ?? _page;
    if (page == null) return;
    final revision = page.saveBinaryRevision;
    if (revision == _lastObservedRevision) return;
    _lastObservedRevision = revision;
    _scheduleBake(force: true);
  }

  void _scheduleBake({bool force = false}) {
    final displaySize = widget.displaySize;
    if (displaySize.width <= 0 || displaySize.height <= 0) return;
    final page = _page;
    if (page == null) {
      if (_inkRaster != null && mounted) setState(() => _inkRaster = null);
      return;
    }

    if (!force &&
        page.sidebarPreviewMatches(page.saveBinaryRevision, displaySize)) {
      final cached = page.sidebarPreviewImage;
      if (!identical(_inkRaster, cached)) {
        if (mounted) setState(() => _inkRaster = cached);
      }
      return;
    }

    if (_baking && !force) return;
    final generation = ++_bakeGeneration;
    _baking = true;
    if (mounted) setState(() {});
    unawaited(_runBake(displaySize, generation));
  }

  Future<void> _runBake(Size displaySize, int generation) async {
    await _SidebarPreviewBakeQueue.run(
      () => _bakeInkRaster(displaySize, generation),
    );
  }

  Future<void> _bakeInkRaster(Size displaySize, int generation) async {
    final page = _page;
    if (!mounted || page == null) {
      if (mounted && generation == _bakeGeneration) {
        setState(() => _baking = false);
      }
      return;
    }
    final strokes = page.allStrokesInDrawOrder.toList(growable: false);
    ui.Image? image;
    final previewScale = displaySize.width / page.size.width;

    if (strokes.isNotEmpty) {
      // Reuse editor tile rasters when the page was already painted in-canvas.
      image = page.strokePictureCache.composeSidebarPreviewIfReady(
        pageSize: page.size,
        previewScale: previewScale,
      );

      if (image == null) {
        final theme = Theme.of(context);
        final invert = _effectiveInvert(context);
        final cache = page.sidebarPreviewBakeCache;
        cache.invalidateAll();
        image = await cache.bakeSidebarPreviewRaster(
          pageSize: page.size,
          strokes: strokes,
          page: page,
          primaryColor: theme.colorScheme.primary,
          pageIndex: widget.pageIndex,
          totalPages: widget.coreInfo.pages.length,
          defaultTextStyle: theme.textTheme.bodyMedium ?? const TextStyle(),
          previewScale: previewScale,
          invert: invert,
          lineHeight: page.hasLocalLineHeight
              ? page.lineHeight
              : widget.coreInfo.lineHeight,
          lineThickness: (page.hasLocalLineThickness
                  ? page.lineThickness
                  : widget.coreInfo.lineThickness)
              .toDouble(),
          lineColor: page.lineColor.value != 0xFF9E9E9E
              ? page.lineColor
              : theme.colorScheme.primary,
        );
      }
    }

    if (!mounted || generation != _bakeGeneration) {
      image?.dispose();
      if (mounted && generation == _bakeGeneration) {
        setState(() => _baking = false);
      }
      return;
    }

    page.setSidebarPreviewRaster(
      image: image,
      revision: page.saveBinaryRevision,
      displaySize: displaySize,
    );
    _lastObservedRevision = page.saveBinaryRevision;
    setState(() {
      _inkRaster = image;
      _baking = false;
    });
  }

  bool _effectiveInvert(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    if (brightness != Brightness.dark) return false;
    return getEffectiveNoteInvertInDarkModeForFile(widget.coreInfo.filePath);
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    if (page == null) return const SizedBox.shrink();
    final pageSize = page.size;
    final displaySize = widget.displaySize;
    if (displaySize.width <= 0 || displaySize.height <= 0) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final invert = _effectiveInvert(context);
    final backgroundColor = InnerCanvas.getBackgroundColor(
      context,
      widget.coreInfo.backgroundColor,
    );
    final hasQuill = !page.quill.controller.document.isEmpty();
    final lineHeight = page.hasLocalLineHeight
        ? page.lineHeight
        : widget.coreInfo.lineHeight;
    final lineThickness = page.hasLocalLineThickness
        ? page.lineThickness
        : widget.coreInfo.lineThickness;
    final lineColor = page.lineColor.value != 0xFF9E9E9E
        ? page.lineColor
        : colorScheme.primary;

    Widget pageBackgroundLayer({required bool includePdfBackground}) {
      return FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(
          width: pageSize.width,
          height: pageSize.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                size: pageSize,
                painter: CanvasBackgroundPainter(
                  invert: invert,
                  backgroundColor: page.backgroundImage != null
                      ? Colors.white
                      : (page.backgroundColor.value != 0xFFFFFFFF
                            ? page.backgroundColor
                            : backgroundColor),
                  backgroundPattern: page.backgroundImage != null
                      ? CanvasBackgroundPattern.none
                      : (page.backgroundPattern ??
                            widget.coreInfo.backgroundPattern),
                  lineHeight: lineHeight,
                  lineThickness: lineThickness.toInt(),
                  primaryColor: lineColor,
                  secondaryColor: lineColor.withValues(alpha: 0.5),
                  preview: true,
                  marginLeft: page.marginLeft,
                  marginRight: page.marginRight,
                  marginTop: page.marginTop,
                  marginBottom: page.marginBottom,
                  borderColor:
                      page.hasLocalBorderColor ||
                          (page.marginLeft > 0 ||
                              page.marginRight > 0 ||
                              page.marginTop > 0 ||
                              page.marginBottom > 0)
                      ? page.borderColor
                      : null,
                ),
              ),
              if (includePdfBackground && page.backgroundImage != null)
                CanvasImage(
                  filePath: widget.coreInfo.filePath,
                  image: page.backgroundImage!,
                  pageSize: pageSize,
                  setAsBackground: null,
                  isBackground: true,
                  readOnly: true,
                ),
            ],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        pageBackgroundLayer(includePdfBackground: true),
        if (_inkRaster != null)
          RawImage(
            image: _inkRaster,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.medium,
          )
        else if (_baking && page.allStrokesInDrawOrder.isNotEmpty)
          ColoredBox(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.12),
          ),
        if (page.allImagesInDrawOrder.isNotEmpty)
          FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(
              width: pageSize.width,
              height: pageSize.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final image in page.allImagesInDrawOrder)
                    CanvasImage(
                      filePath: widget.coreInfo.filePath,
                      image: image,
                      pageSize: pageSize,
                      setAsBackground: null,
                      readOnly: true,
                    ),
                ],
              ),
            ),
          ),
        if (hasQuill)
          FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(
              width: pageSize.width,
              height: page.previewHeight(),
              child: IgnorePointer(
                child: QuillEditor(
                  controller: page.quill.controller,
                  focusNode: page.quill.focusNode,
                  scrollController: _quillScrollController,
                  config: QuillEditorConfig(
                    customStyles: SaberQuillStyles.get(
                      invert: invert,
                      secondary: colorScheme.secondary,
                      lineHeight: widget.coreInfo.lineHeight,
                      appBodyTextStyle: theme.textTheme.bodyMedium,
                    ),
                    scrollable: false,
                    expands: true,
                    showCursor: false,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
