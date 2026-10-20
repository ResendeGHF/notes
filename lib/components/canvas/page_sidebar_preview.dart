// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:pdfrx/pdfrx.dart' show PdfDocument;
import 'package:saber/components/canvas/_canvas_background_painter.dart';
import 'package:saber/components/canvas/canvas_image.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/services/display_ink_feel.dart';
import 'package:saber/services/pdf_native_texture.dart';
import 'package:saber/services/pdf_page_thumbnail_cache.dart';
import 'package:saber/services/vault_adapter.dart';
import 'package:saber/data/editor/canvas_background_pattern.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
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

/// Serializes sidebar hydrate requests so scrolling the pages panel through
/// dozens of lazy shells does not run many synchronous BSON parses in the
/// same frame. Small slices parse instantly; dense slices hydrate chunked
/// (see [EditorCoreInfo.tryHydratePageSmart]) with UI yields between batches.
final class _SidebarHydrateQueue {
  _SidebarHydrateQueue._();

  static Future<void> _tail = Future<void>.value();

  static Future<T> run<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }
}

/// Docked pages-sidebar preview: background + baked stroke raster LOD +
/// optional images/quill scaled to [displaySize] (no full-page InnerCanvas).
///
/// Far pages may still be lazy BSON shells ([EditorPage.isLazyShell]) when the
/// panel opens (only the landing window hydrates eagerly). This widget
/// hydrates its own page on demand through [tryHydratePage] (or directly via
/// [EditorCoreInfo.tryHydratePageSmart]) so any scrolled-into-view card
/// converges to a real preview without blocking the UI. Hydrates and bakes
/// are serialized globally and cancelled by generation when scrolled away.
class PageSidebarPreview extends StatefulWidget {
  const PageSidebarPreview({
    super.key,
    required this.pageIndex,
    required this.coreInfo,
    required this.displaySize,
    this.tryHydratePage,
    this.onPageHydrated,
  });

  final int pageIndex;
  final EditorCoreInfo coreInfo;
  final Size displaySize;

  /// Hydrates page [pageIndex] if it is still a lazy shell. Returns true when
  /// the page is ready, newly hydrated synchronously, or an async hydrate
  /// started (completion rebuilds via [onPageHydrated] / state). When null,
  /// the preview falls back to [EditorCoreInfo.tryHydratePageSmart] directly.
  final bool Function(int pageIndex)? tryHydratePage;

  /// Fired when an async (chunked) hydrate for [pageIndex] completes, so the
  /// editor can wire image/quill callbacks and prime assets. The preview
  /// already rebuilds itself; this is only for editor-side wiring.
  final void Function(int pageIndex, EditorPage page)? onPageHydrated;

  @override
  State<PageSidebarPreview> createState() => _PageSidebarPreviewState();
}

class _PageSidebarPreviewState extends State<PageSidebarPreview> {
  ui.Image? _inkRaster;
  bool _baking = false;
  int _bakeGeneration = 0;

  /// True while a hydrate was requested for the current shell instance.
  /// Reset whenever the page instance changes so a new shell re-requests.
  EditorPage? _hydrateRequestedFor;
  bool _hydrateInFlight = false;

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
  }

  void _detachPageListener() {
    _listenedPage?.removeListener(_onPageChanged);
    _listenedPage = null;
  }

  @override
  void initState() {
    super.initState();
    _attachPageListener();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncPageInstance();
    });
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
      _hydrateRequestedFor = null;
      _hydrateInFlight = false;
      // A hydrate elsewhere (main canvas idle, outline jump) replaces
      // pages[index] without changing widget config; the sync below picks
      // up the new instance. Defer so build finishes first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncPageInstance();
        if (mounted) setState(() {});
      });
    } else {
      // Same widget config but the underlying page instance may have been
      // swapped by a lazy hydrate. Detect without waiting for a page
      // notification (the old shell never notifies about its replacement).
      _syncPageInstance();
    }
  }

  @override
  void dispose() {
    _detachPageListener();
    super.dispose();
  }

  void _onPageChanged() {
    if (!mounted) return;
    // The listened instance may have been replaced by a hydrate (shells
    // never notify about their own replacement). Re-sync first.
    _syncPageInstance();
    final page = _listenedPage ?? _page;
    if (page == null) return;
    setState(() {});
  }

  bool _isShell(EditorPage page) {
    if (page.isLazyShell) return true;
    final index = widget.pageIndex;
    if (index < 0 || index >= widget.coreInfo.pages.length) return false;
    return widget.coreInfo.isLazyShellPage(index);
  }

  /// Re-attaches when pages[index] was swapped (lazy hydrate, undo/redo,
  /// delete/insert) without a widget config change. Returns true when the
  /// instance changed and a rebuild/bake was scheduled.
  bool _syncPageInstance() {
    final page = _page;
    if (identical(page, _listenedPage)) return false;
    _detachPageListener();
    _attachPageListener();
    _hydrateRequestedFor = null;
    _hydrateInFlight = false;
    // A new instance means a new revision namespace: drop the stale raster
    // so a shell (or a cleared page) never shows the previous page's ink.
    if (_inkRaster != null) {
      _inkRaster = null;
      if (mounted) setState(() {});
    } else if (mounted) {
      // Still rebuild: background/images/quill come from the new instance.
      setState(() {});
    }
    return true;
  }

  /// Requests a lazy-shell hydrate for the visible preview. Serialized so a
  /// fast sidebar fling does not parse many pages in one frame. Sync slices
  /// finish immediately; dense slices complete chunked-async and rebuild here
  /// (direct path) or via the editor's setState (owned [tryHydratePage] path,
  /// which rebuilds this card through [didUpdateWidget]).
  void _ensureHydrated() {
    if (!mounted) return;
    final index = widget.pageIndex;
    if (index < 0 || index >= widget.coreInfo.pages.length) return;
    if (!widget.coreInfo.isLazyShellPage(index)) {
      // Instance may still be flagged while indices already cleared (race);
      // sync again so the fresh page paints.
      final page = _page;
      if (page != null && !identical(page, _listenedPage)) _syncPageInstance();
      return;
    }
    final shell = _page;
    if (identical(shell, _hydrateRequestedFor) || _hydrateInFlight) return;
    _hydrateRequestedFor = shell;
    _hydrateInFlight = true;
    unawaited(
      _SidebarHydrateQueue.run(() async {
        // Yield so the sidebar frame that mounted this card finishes first.
        await Future<void>.delayed(Duration.zero);
        if (!mounted) return;
        if (index != widget.pageIndex) return;
        if (index < 0 || index >= widget.coreInfo.pages.length) return;
        if (!widget.coreInfo.isLazyShellPage(index)) return;
        final hydrate = widget.tryHydratePage;
        if (hydrate != null) {
          final accepted = hydrate(index);
          if (!accepted) return;
          // Sync path replaces the instance inline and the editor wires it.
          // Async (dense) path completes via the editor's own callback which
          // rebuilds the panel; this card then re-syncs in [didUpdateWidget]
          // / [build]. No polling: one timer per card for dozens of shells
          // would keep hundreds of delayed futures alive on every fling.
          return;
        }
        final wasShell = widget.coreInfo.isLazyShellPage(index);
        if (!wasShell) return;
        final accepted = widget.coreInfo.tryHydratePageSmart(
          index,
          onAsyncHydrated: (page) => _onAsyncHydrated(index, page),
        );
        if (!accepted) return;
        // Sync hydrate done inline; async hydrate notifies via callback.
      }).then((_) {
        _hydrateInFlight = false;
        if (!mounted) return;
        if (index != widget.pageIndex) return;
        final changed = _syncPageInstance();
        _ensureHydratedRetryIfStillShell();
        if (!changed && mounted) setState(() {});
      }),
    );
  }

  void _ensureHydratedRetryIfStillShell() {
    if (!mounted) return;
    final index = widget.pageIndex;
    if (index < 0 || index >= widget.coreInfo.pages.length) return;
    if (!widget.coreInfo.isLazyShellPage(index)) return;
    // Dense async hydrate still in flight (or skipped while scrolling fast):
    // allow one re-request per new frame instead of spamming per build.
    _hydrateRequestedFor = null;
  }

  void _onAsyncHydrated(int index, EditorPage page) {
    if (!mounted) return;
    if (index != widget.pageIndex) return;
    if (index < 0 || index >= widget.coreInfo.pages.length) return;
    if (!identical(widget.coreInfo.pages[index], page)) return;
    widget.onPageHydrated?.call(index, page);
    _hydrateInFlight = false;
    _hydrateRequestedFor = null;
    _syncPageInstance();
    if (mounted) setState(() {});
  }

  void _scheduleBake({bool force = false}) {
    final displaySize = widget.displaySize;
    if (displaySize.width <= 0 || displaySize.height <= 0) return;
    // Instance may have been swapped by a hydrate without a widget update.
    _syncPageInstance();
    final page = _page;
    if (page == null) {
      if (_inkRaster != null && mounted) setState(() => _inkRaster = null);
      return;
    }
    if (_isShell(page)) {
      // Blank paper is not a valid preview for a shell: hydrate first, bake
      // after the real strokes exist.
      _ensureHydrated();
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
    if (_isShell(page)) {
      // Hydrate won the race after _scheduleBake: request it and stop.
      if (mounted && generation == _bakeGeneration) {
        setState(() => _baking = false);
      }
      _ensureHydrated();
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
          lineColor: page.lineColor,
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
    // A hydrate elsewhere swaps pages[index] without a widget update. Never
    // touch listeners synchronously in build; schedule the re-sync.
    if (!identical(_listenedPage, _page)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncPageInstance();
        if (mounted) setState(() {});
      });
    }
    final page = _page;
    if (page == null) return const SizedBox.shrink();
    final isShell = _isShell(page);
    // Parse the shell so its ink can be sketched. This does not mount a PDF
    // texture: the card draws a cached JPEG and polylines only.
    if (isShell) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureHydrated();
      });
    }
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
    final lineColor = page.lineColor;

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
                  lineThickness: lineThickness.toDouble(),
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
              if (includePdfBackground &&
                  page.backgroundImage is PdfEditorImage)
                _SidebarPdfThumb(image: page.backgroundImage! as PdfEditorImage, invert: invert)
              else if (includePdfBackground && page.backgroundImage != null)
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

    // Stroke layer: cached raster blit when available (one draw call while
    // scrolling), sketch polylines only as the first-frame placeholder while
    // the bake runs. The bake is serialized globally and cancelled by
    // generation when the card scrolls away.
    final hasStrokes = !isShell && page.strokeCountInDrawOrder > 0;
    final rasterReady =
        hasStrokes &&
        _inkRaster != null &&
        page.sidebarPreviewMatches(page.saveBinaryRevision, displaySize);
    if (hasStrokes && !rasterReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scheduleBake();
      });
    }
    final strokeRevision = page.saveBinaryRevision;
    final strokeCount = page.strokeCountInDrawOrder;

    return Stack(
      fit: StackFit.expand,
      children: [
        pageBackgroundLayer(includePdfBackground: true),
        if (isShell)
          ColoredBox(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
            child: Center(
              child: Text(
                '${widget.pageIndex + 1}',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        if (rasterReady)
          RepaintBoundary(
            child: RawImage(
              image: _inkRaster,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.low,
            ),
          )
        else if (hasStrokes)
          RepaintBoundary(
            child: CustomPaint(
              painter: _SidebarStrokeSketchPainter(
                strokes: page.allStrokesInDrawOrder.toList(growable: false),
                pageSize: pageSize,
                invert: invert,
                revision: strokeRevision,
                strokeCount: strokeCount,
              ),
              child: const SizedBox.expand(),
            ),
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
                    if (image is PdfEditorImage)
                      Positioned(
                        left: image.dstRect.left,
                        top: image.dstRect.top,
                        width: image.dstRect.width,
                        height: image.dstRect.height,
                        child: _SidebarPdfThumb(image: image, invert: invert),
                      )
                    else
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
          Padding(
            padding: const EdgeInsets.all(6),
            child: Text(
              page.quill.controller.document.toPlainText(),
              maxLines: 6,
              overflow: TextOverflow.fade,
              style: theme.textTheme.labelSmall?.copyWith(
                color: invert ? Colors.white : colorScheme.onSurface,
              ),
            ),
          ),
      ],
    );
  }
}

/// Low-detail ink for the pages sidebar. Draws subsampled polylines in the
/// card's own coordinate space. No mesh build, no tile bake, no toImage.
class _SidebarStrokeSketchPainter extends CustomPainter {
  _SidebarStrokeSketchPainter({
    required this.strokes,
    required this.pageSize,
    required this.invert,
    required this.revision,
    required this.strokeCount,
  });

  final List<Stroke> strokes;
  final Size pageSize;
  final bool invert;
  final int revision;
  final int strokeCount;
  
  // Zero-copy shared buffer
  static Float32List _sharedBuffer = Float32List(32768);

  @override
  void paint(Canvas canvas, Size size) {
    if (pageSize.width <= 0 || pageSize.height <= 0 || size.isEmpty) return;
    final sx = size.width / pageSize.width;
    final sy = size.height / pageSize.height;
    final scale = (sx + sy) / 2.0;
    
    canvas.save();
    canvas.scale(sx, sy);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = false;

    // True zero-allocation rendering using a static buffer and sublistView
    for (final stroke in strokes) {
      final pts = stroke.pointsForEraser;
      if (pts.isEmpty) continue;
      
      final step = pts.length > 50 ? (pts.length / 25).ceil() : 1;
      int count = 0;
      for (int i = 0; i < pts.length; i += step) count++;
      if ((pts.length - 1) % step != 0) count++;
      
      final neededSize = count * 2;
      if (neededSize > _sharedBuffer.length) {
        _sharedBuffer = Float32List(neededSize * 2);
      }
      
      int idx = 0;
      for (int i = 0; i < pts.length; i += step) {
        _sharedBuffer[idx++] = pts[i].x;
        _sharedBuffer[idx++] = pts[i].y;
      }
      if ((pts.length - 1) % step != 0) {
        _sharedBuffer[idx++] = pts.last.x;
        _sharedBuffer[idx++] = pts.last.y;
      }
      
      final view = Float32List.sublistView(_sharedBuffer, 0, idx);
      
      paint.color = invert ? Colors.white : stroke.color;
      final widthOnScreen = (stroke.options.size * scale).clamp(0.4, 3.0);
      paint.strokeWidth = widthOnScreen / scale;
      
      if (idx == 2) {
        paint.style = PaintingStyle.fill;
        canvas.drawCircle(
          Offset(view[0], view[1]), 
          paint.strokeWidth / 2, 
          paint
        );
        paint.style = PaintingStyle.stroke; // Restore for next strokes
      } else {
        canvas.drawRawPoints(ui.PointMode.polygon, view, paint);
      }
    }
    
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SidebarStrokeSketchPainter oldDelegate) {
    // The build creates a fresh stroke list every time: never compare list
    // identity (it always differs and forced a repaint on every scroll
    // frame). Repaint only when content actually changed.
    return oldDelegate.revision != revision ||
        oldDelegate.strokeCount != strokeCount ||
        oldDelegate.pageSize != pageSize ||
        oldDelegate.invert != invert;
  }
}

/// Cached JPEG of a PDF page. Never mounts a full-page native texture.
///
/// Probe order (all synchronous, zero PDFium on first paint):
/// 1. Memory LRU, 2. disk file.
///
/// On a miss the thumb is filled asynchronously and the card rebuilds:
/// 1. Native PdfRenderer bytes (Kotlin, file path only — no pdfrx document,
///    no worker contention with the main canvas), stored in the shared
///    tile cache so the main canvas reuses the same pixels;
/// 2. pdfrx `getOrRender` through the already-open (or opening) shared
///    document as fallback (non-Android, vault, encrypted).
///
/// The cache key uses the live preview policy width, so sidebar tiles and
/// main-canvas placeholder tiles are the SAME file (previous hardcoded
/// 240px keys never hit the 360/720/1080px tiles the canvas writes, which
/// is why every far page stayed blank).
class _SidebarPdfThumb extends StatefulWidget {
  const _SidebarPdfThumb({required this.image, this.invert = false});

  final PdfEditorImage image;
  final bool invert;

  @override
  State<_SidebarPdfThumb> createState() => _SidebarPdfThumbState();
}

class _SidebarPdfThumbState extends State<_SidebarPdfThumb> {
  File? _file;
  Uint8List? _memory;
  int _gen = 0;
  static int _activeNativeFills = 0;

  @override
  void initState() {
    super.initState();
    _probeAndFill();
  }

  @override
  void didUpdateWidget(covariant _SidebarPdfThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.pdfPage != widget.image.pdfPage ||
        oldWidget.image.assetId != widget.image.assetId ||
        oldWidget.image.pdfFile?.path != widget.image.pdfFile?.path) {
      _probeAndFill();
    }
  }

  int get _policyWidth {
    try {
      return DisplayInkFeel.instance.pdfPreviewWidthPx;
    } catch (_) {
      return PdfPageThumbnailCache.defaultThumbWidthPx;
    }
  }

  void _probeAndFill() {
    _gen++;
    final gen = _gen;
    _file = null;
    _memory = null;
    
    // Defer the disk IO and hashing to the next event loop cycle so the sidebar
    // open animation can play smoothly at 60/120fps without blocking the UI thread.
    Future<void>.delayed(Duration.zero, () async {
      if (!mounted || gen != _gen) return;

      final path = widget.image.assetCacheAll.getResolvedPdfPath(
            widget.image.assetId,
          ) ??
          widget.image.pdfFile?.path;
      if (path == null || path.isEmpty) {
        if (mounted) setState(() {});
        return;
      }
      
      final cache = widget.image.assetCacheAll;
      
      // Yield strongly to keep scrolling at 120fps
      await Future<void>.delayed(const Duration(milliseconds: 2));
      if (!mounted || gen != _gen) return;

      // These cache queries can hit the disk synchronously (e.g. file size)
      final fileSize = cache.getAssetFileSize(widget.image.assetId);
      final hash = cache.getAssetPreviewHash(widget.image.assetId);
      
      final key = PdfPageThumbnailCache.keyForPage(
        fileSize: fileSize,
        identityHash: hash,
        filePath: path,
        pageIndex: widget.image.pdfPage,
        targetWidth: _policyWidth,
      );
      
      if (key == null) {
        if (mounted) setState(() {});
        return;
      }
      
      final mem = PdfPageThumbnailCache.tryGetMemory(key);
      if (mem != null && mem.isNotEmpty) {
        if (mounted && gen == _gen) {
          setState(() {
            _memory = mem;
          });
        }
        return;
      }
      
      // Yield once more before hitting the disk sync check just in case we are 
      // processing dozens of thumbnails in the same frame.
      await Future<void>.delayed(Duration.zero);
      if (!mounted || gen != _gen) return;

      final f = PdfPageThumbnailCache.tryGetDiskFileSync(key);
      if (f != null) {
        if (mounted && gen == _gen) {
          setState(() {
            _file = f;
          });
        }
        return;
      }
      
      // Miss: fill in the background, show the page-number placeholder meanwhile.
      if (mounted) setState(() {});
      unawaited(_fillMiss(gen, key, path));
    });
  }

  Future<void> _fillMiss(int gen, String key, String path) async {
    if (!mounted || gen != _gen) return;
    // Yield so the sidebar frame that mounted this card finishes first.
    await Future<void>.delayed(Duration.zero);
    if (!mounted || gen != _gen) return;
    final sw = Stopwatch()..start();
    // 1. Native fast path: no pdfrx document needed, no worker contention.
    while (_activeNativeFills >= 2) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      if (!mounted || gen != _gen) return;
    }
    _activeNativeFills++;
    try {
      final bytes = await PdfNativeTexture.renderThumbnailBytes(
        filePath: path,
        pageIndex: widget.image.pdfPage,
        widthPx: _policyWidth,
        vaultUnlocked: VaultAdapter.isUnlocked,
      );
      Logger('PDFTIMING').info(
        'PDFTIMING sidebar.native page=${widget.image.pdfPage} '
        'bytes=${bytes?.length ?? -1} ms=${sw.elapsedMilliseconds}',
      );
      if (bytes != null && bytes.isNotEmpty) {
        await PdfPageThumbnailCache.putBytes(key, bytes);
        if (!mounted || gen != _gen) return;
        final mem = PdfPageThumbnailCache.tryGetMemory(key);
        setState(() {
          _memory = (mem != null && mem.isNotEmpty) ? mem : bytes;
          _file = null;
        });
        return;
      }
    } catch (_) {
      // Fall through to the pdfrx path.
    } finally {
      _activeNativeFills--;
    }
    if (!mounted || gen != _gen) return;
    // 2. pdfrx fallback through the shared document (opens it if needed).
    try {
      final notifier = widget.image.assetCacheAll.getPdfNotifier(
        widget.image.assetId,
      );
      Future<void> renderWithDoc(PdfDocument? doc) async {
        if (doc == null) return;
        if (!mounted || gen != _gen) return;
        final pageIndex = widget.image.pdfPage;
        try {
          await PdfPageThumbnailCache.getOrRender(
            doc: doc,
            pageIndex: pageIndex,
            cacheKey: key,
            targetWidth: _policyWidth,
            // Scrolled away while parsing/rendering: skip the JPEG encode +
            // disk write instead of blocking the worker for a dead card.
            stillNeeded: () =>
                mounted &&
                gen == _gen &&
                widget.image.pdfPage == pageIndex,
          );
        } catch (_) {}
        if (!mounted || gen != _gen) return;
        final mem = PdfPageThumbnailCache.tryGetMemory(key);
        Logger('PDFTIMING').info(
          'PDFTIMING sidebar.pdfrxDone page=$pageIndex mem=${mem != null} '
          'ms=${sw.elapsedMilliseconds}',
        );
        if (mem != null && mem.isNotEmpty) {
          setState(() {
            _memory = mem;
            _file = null;
          });
          return;
        }
        final f = PdfPageThumbnailCache.tryGetDiskFileSync(key);
        if (f != null && mounted && gen == _gen) {
          setState(() {
            _file = f;
          });
        }
      }

      final doc = notifier.value;
      if (doc != null) {
        await renderWithDoc(doc);
      } else {
        // Wait for the shared open (started above) without blocking the UI.
        for (var i = 0; i < 40; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          if (!mounted || gen != _gen) return;
          final d = notifier.value;
          if (d != null) {
            await renderWithDoc(d);
            return;
          }
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    Widget applyInvert(Widget child) {
      if (!widget.invert) return child;
      return ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          -1, 0, 0, 0, 255,
          0, -1, 0, 0, 255,
          0, 0, -1, 0, 255,
          0, 0, 0, 1, 0,
        ]),
        child: child,
      );
    }

    final mem = _memory;
    if (mem != null) {
      return RepaintBoundary(
        child: applyInvert(
          Image.memory(
            mem,
            fit: BoxFit.fill,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
          ),
        ),
      );
    }
    final file = _file;
    if (file != null) {
      return RepaintBoundary(
        child: applyInvert(
          Image.file(
            file,
            fit: BoxFit.fill,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, _, _) => const SizedBox.expand(),
          ),
        ),
      );
    }
    // Loading placeholder: page number, never a white flash.
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: const SizedBox.expand(),
    );
  }
}
