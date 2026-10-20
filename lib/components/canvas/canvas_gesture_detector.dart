// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:keybinder/keybinder.dart';
import 'package:saber/components/canvas/canvas_context_menu_feel.dart';
import 'package:saber/components/canvas/canvas_transform_cache.dart';
import 'package:saber/components/canvas/hud/canvas_hud.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
import 'package:saber/components/canvas/interactive_canvas.dart';
import 'package:saber/components/canvas/page_raster_cache.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/change_notifier_extensions.dart';
import 'package:saber/data/extensions/matrix4_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:saber/services/perf_probe.dart';
import 'package:vector_math/vector_math_64.dart';

class CanvasGestureDetector extends StatefulWidget {
  CanvasGestureDetector({
    super.key,
    required this.filePath,
    required this.isDrawGesture,
    this.onInteractionEnd,
    required this.onDrawStart,
    required this.onDrawUpdate,
    required this.onDrawEnd,
    required this.updatePointerData,
    this.onPointerDown,
    this.onPointerUpOrCancel,
    this.shouldInjectRawPointerSamplesForDraw,
    this.onRawPointerMoveForDraw,
    required this.onHovering,
    required this.onHoveringEnd,
    this.onEraserHover,
    required this.onStylusButtonChanged,
    required this.onLongPress,
    this.onSecondaryTapDown,
    this.onTapDown,
    required this.undo,
    required this.redo,
    required this.pages,
    required this.initialPageIndex,
    required this.pageBuilder,
    required this.placeholderPageBuilder,
    required this.isTextEditing,
    this.isInfinite = false,
    this.skipTransformClampForExpansion,
    this.suppressTransformClamp,
    this.onContainerBoundsChanged,
    this.pageLayoutWidthOverride,
    this.scrollPhysicsStopNotifier,
    this.tryHydratePage,
    this.onMaintainPageRasterBand,
    this.onPrefetchNearbyPages,
    TransformationController? transformationController, this.onAddPageAbove, this.onAddPageBelow,
  }) : _transformationController =
           transformationController ?? TransformationController();

  final String filePath;

  final bool Function(ScaleStartDetails scaleDetails) isDrawGesture;
  final ValueChanged<ScaleEndDetails>? onInteractionEnd;
  final ValueChanged<ScaleStartDetails> onDrawStart;
  final ValueChanged<ScaleUpdateDetails> onDrawUpdate;
  final ValueChanged<ScaleEndDetails> onDrawEnd;

  final void Function(
    PointerDeviceKind kind,
    double? pressure,
    Duration timestamp,
  )
  updatePointerData;
  final ValueChanged<PointerEvent>? onPointerDown;
  final ValueChanged<PointerEvent>? onPointerUpOrCancel;

  final bool Function()? shouldInjectRawPointerSamplesForDraw;
  final void Function(PointerMoveEvent event)? onRawPointerMoveForDraw;

  final VoidCallback onHovering;
  final VoidCallback onHoveringEnd;
  // Fired when the stylus eraser end approaches (invertedStylus hover).
  // Used to settle viewport inertia before the first erase touch lands.
  final VoidCallback? onEraserHover;
  final ValueChanged<bool> onStylusButtonChanged;
  final void Function(Offset globalPosition) onLongPress;
  final void Function(Offset globalPosition)? onSecondaryTapDown;

  final VoidCallback undo;
  final VoidCallback redo;

  final List<EditorPage> pages;
  final int? initialPageIndex;
  final Widget Function(BuildContext context, int pageIndex) pageBuilder;
  final Widget Function(BuildContext context, int pageIndex)
  placeholderPageBuilder;

  final bool Function() isTextEditing;

  final bool isInfinite;

  final ValueNotifier<bool>? skipTransformClampForExpansion;

  /// When true, skip pan/zoom clamping until cleared (viewport resize sessions).
  final ValueNotifier<bool>? suppressTransformClamp;

  /// Fired when the interactive canvas layout size changes.
  final ValueChanged<Size>? onContainerBoundsChanged;

  /// When set, page geometry (fitted width/height/offsets) uses this width
  /// instead of the live viewport width. Used while a sidebar/split resize is
  /// animating so pages do not reflow every frame (avoids a "scrolling" look).
  /// The HUD stays outside the transform and is unaffected.
  final double? pageLayoutWidthOverride;

  final ValueNotifier<int>? scrollPhysicsStopNotifier;

  /// Idle-path BSON hydrate. Must not run inside [pageBuilder] / `build`.
  /// Returns true when this call replaced a shell.
  final bool Function(int pageIndex)? tryHydratePage;

  /// Prefetch/evict page raster caches for the visible band ± neighbors.
  final void Function(int visibleStart, int visibleEnd)?
  onMaintainPageRasterBand;

  /// Idle pre-tessellation hook: the editor records tile Pictures for pages
  /// near the viewport so a pan scrolls into already-drawn content.
  /// Returns the number of tiles recorded (progress for the warmer loop).
  final int Function(int bandStart, int bandEnd)? onPrefetchNearbyPages;

  final VoidCallback? onAddPageAbove;
  final VoidCallback? onAddPageBelow;

  late final TransformationController _transformationController;

  final void Function(Offset globalPosition)? onTapDown;

  @override
  State<CanvasGestureDetector> createState() => CanvasGestureDetectorState();

  static const kMinScale = 0.6;
  static const kMaxScale = 10.0;

  static double getTopOfPage({
    required int pageIndex,
    required List<double> pageOffsets,
  }) {
    if (pageIndex <= 0 || pageOffsets.isEmpty) return 0;
    if (pageIndex >= pageOffsets.length) return pageOffsets.last;
    return pageOffsets[pageIndex];
  }

  static void scrollToPage({
    required int pageIndex,
    required List<double> pageOffsets,
    required TransformationController transformationController,
  }) {
    final topOfPage = -CanvasGestureDetector.getTopOfPage(
      pageIndex: pageIndex,
      pageOffsets: pageOffsets,
    );
    transformationController.value = Matrix4.translationValues(
      0,
      topOfPage + 50,
      0,
    );
    // Programmatic jumps are not finger gestures — clear moving so idle
    // BSON hydrate is not stuck waiting for _finishViewportGesture.
    PageRasterCacheManager.endProgrammaticViewportJump();
  }

  static int getPageIndex({
    required double scrollY,
    required List<double> pageOffsets,
  }) {
    if (pageOffsets.isEmpty || scrollY <= 0) return 0;

    int min = 0;
    int max = pageOffsets.length - 1;

    while (min <= max) {
      final mid = min + ((max - min) >> 1);
      final midOffset = pageOffsets[mid];

      if (midOffset == scrollY) {
        return mid;
      } else if (midOffset < scrollY) {
        min = mid + 1;
      } else {
        max = mid - 1;
      }
    }

    return max >= 0 ? max : 0;
  }
}

class CanvasGestureDetectorState extends State<CanvasGestureDetector> {
  late var containerBounds = const BoxConstraints();

  final List<double> _pageVerticalOffsets = [];
  double? _lastCachedScreenWidth;

  late double? zoomLockedValue = stows.lastZoomLock.value
      ? widget._transformationController.value.approxScale
      : null;

  late bool singleFingerPanLock = stows.lastSingleFingerPanLock.value;

  late bool axisAlignedPanLock = stows.lastAxisAlignedPanLock.value;

  void zoomIn() => widget._transformationController.value =
      setZoom(
        scaleDelta: 0.1,
        transformation: widget._transformationController.value,
        containerBounds: containerBounds,
      ) ??
      widget._transformationController.value;
  void zoomOut() => widget._transformationController.value =
      setZoom(
        scaleDelta: -0.1,
        transformation: widget._transformationController.value,
        containerBounds: containerBounds,
      ) ??
      widget._transformationController.value;
  @visibleForTesting
  static Matrix4? setZoom({
    required double scaleDelta,
    required Matrix4 transformation,
    required BoxConstraints containerBounds,
  }) {
    final oldScale = transformation.approxScale;
    final newScale = oldScale + scaleDelta;

    if (newScale < CanvasGestureDetector.kMinScale) return null;
    if (newScale > CanvasGestureDetector.kMaxScale) return null;

    final center = Vector3(
      containerBounds.maxWidth / 2,
      containerBounds.maxHeight / 2,
      0,
    );
    final translation =
        (transformation.getTranslation() - center) * (newScale / oldScale) +
        center;

    return Matrix4.translation(translation)
      ..scaleByDouble(newScale, newScale, newScale, 1);
  }

  final Map<AxisDirection, Timer> _arrowKeyPanTimers = {};
  void arrowKeyPan(AxisDirection direction, bool pressed) {
    _arrowKeyPanTimers.remove(direction)?.cancel();
    if (!pressed) return;

    if (widget.isTextEditing()) return;

    _arrowKeyPanNow(direction);

    const ms100 = Duration(milliseconds: 100);
    const ms200 = Duration(milliseconds: 200);
    _arrowKeyPanTimers[direction] = Timer(ms200, () {
      _arrowKeyPanTimers[direction] = Timer.periodic(ms100, (_) {
        _arrowKeyPanNow(direction);
      });
    });
  }

  void _arrowKeyPanNow(AxisDirection direction) {
    final transformation = widget._transformationController.value;
    const panAmount = 50.0;

    final next = Matrix4.copy(transformation);
    next.leftTranslateByDouble(
      switch (direction) {
        AxisDirection.left => panAmount,
        AxisDirection.right => -panAmount,
        AxisDirection.up => 0.0,
        AxisDirection.down => 0.0,
      },
      switch (direction) {
        AxisDirection.left => 0.0,
        AxisDirection.right => 0.0,
        AxisDirection.up => panAmount,
        AxisDirection.down => -panAmount,
      },
      0,
      1,
    );

    widget._transformationController.value = next;
    // Central debounce owns the settle; the transform listener refreshes it.
    PageRasterCacheManager.notifyViewportMotion(
      scale: next.getMaxScaleOnAxis(),
    );
  }

  var _setupKeybindings = false;
  late Keybinding _ctrlPlus, _ctrlEquals, _ctrlMinus;
  late Keybinding _leftKey, _rightKey, _upKey, _downKey;
  void _assignKeybindings() {
    _ctrlPlus = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.add),
    ], inclusive: true);
    _ctrlEquals = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.equal),
    ], inclusive: true);
    _ctrlMinus = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.minus),
    ], inclusive: true);
    Keybinder.bind(_ctrlPlus, zoomIn);
    Keybinder.bind(_ctrlEquals, zoomIn);
    Keybinder.bind(_ctrlMinus, zoomOut);

    _leftKey = Keybinding([
      KeyCode.from(LogicalKeyboardKey.arrowLeft),
    ], inclusive: true);
    _rightKey = Keybinding([
      KeyCode.from(LogicalKeyboardKey.arrowRight),
    ], inclusive: true);
    _upKey = Keybinding([
      KeyCode.from(LogicalKeyboardKey.arrowUp),
    ], inclusive: true);
    _downKey = Keybinding([
      KeyCode.from(LogicalKeyboardKey.arrowDown),
    ], inclusive: true);
    Keybinder.bind(
      _leftKey,
      (bool pressed) => arrowKeyPan(AxisDirection.left, pressed),
    );
    Keybinder.bind(
      _rightKey,
      (bool pressed) => arrowKeyPan(AxisDirection.right, pressed),
    );
    Keybinder.bind(
      _upKey,
      (bool pressed) => arrowKeyPan(AxisDirection.up, pressed),
    );
    Keybinder.bind(
      _downKey,
      (bool pressed) => arrowKeyPan(AxisDirection.down, pressed),
    );

    _setupKeybindings = true;
  }

  void _removeKeybindings() {
    if (!_setupKeybindings) return;
    _setupKeybindings = false;

    Keybinder.remove(_ctrlPlus);
    Keybinder.remove(_ctrlEquals);
    Keybinder.remove(_ctrlMinus);

    Keybinder.remove(_leftKey);
    Keybinder.remove(_rightKey);
    Keybinder.remove(_upKey);
    Keybinder.remove(_downKey);
    _arrowKeyPanTimers.forEach((_, timer) => timer.cancel());
  }

  @override
  void initState() {
    // Seed the initial viewport BEFORE first layout: otherwise the first
    // frame builds at scroll 0 (mounting full PDF renderers for pages 0-2,
    // each queueing parses+renders on the single pdfrx worker) and only
    // then jumps to the saved page. Starting placed saves ~seconds on deep
    // notes. The post-frame re-assert covers late prop arrival (no-op once
    // placed, guarded by the identity check in setInitialTransform).
    _recalculatePageOffsets();
    setInitialTransform();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _recalculatePageOffsets();
        setInitialTransform();
      }
    });

    widget._transformationController.addListener(onTransformChanged);
    _assignKeybindings();
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _recalculatePageOffsets();
  }

  @override
  void didUpdateWidget(CanvasGestureDetector oldWidget) {
    if (widget.pages != oldWidget.pages ||
        widget.pageLayoutWidthOverride != oldWidget.pageLayoutWidthOverride) {
      _recalculatePageOffsets();
    }

    if (oldWidget.initialPageIndex != widget.initialPageIndex ||
        oldWidget.filePath != widget.filePath) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setInitialTransform();
      });
    }
    super.didUpdateWidget(oldWidget);
  }

  void _recalculatePageOffsets({double? widthOverride}) {
    final screenWidth =
        widthOverride ??
        widget.pageLayoutWidthOverride ??
        (containerBounds.maxWidth > 0
            ? containerBounds.maxWidth
            : MediaQuery.sizeOf(context).width);

    if (screenWidth == _lastCachedScreenWidth &&
        _pageVerticalOffsets.length == widget.pages.length &&
        _pageVerticalOffsets.isNotEmpty) {
      return;
    }

    _lastCachedScreenWidth = screenWidth;
    _pageVerticalOffsets.clear();
    // Keep in sync with Editor._generatePageOffsets / _PagesBuilder.
    double currentTop = widget.isInfinite ? 0 : Editor.gapBetweenPages * 2;

    for (final page in widget.pages) {
      _pageVerticalOffsets.add(currentTop);

      final pageSize = page.size;
      final pageWidthFitted = min(pageSize.width, screenWidth);
      currentTop += widget.isInfinite ? 0 : Editor.gapBetweenPages;
      currentTop += pageSize.height * (pageWidthFitted / pageSize.width);
    }
  }

  void setInitialTransform() {
    if (widget.filePath.isEmpty) return;

    if (_pageVerticalOffsets.isEmpty) _recalculatePageOffsets();

    if (!widget._transformationController.value.isIdentity()) return;

    // ignore: invalid_use_of_visible_for_testing_member
    final transformCacheItem = CanvasTransformCache.get(widget.filePath);

    if (transformCacheItem != null) {
      widget._transformationController.value = transformCacheItem.transform;
      if (zoomLockedValue != null) {
        zoomLockedValue = transformCacheItem.transform.approxScale;
      }
    } else if (widget.initialPageIndex != null) {
      CanvasGestureDetector.scrollToPage(
        pageIndex: widget.initialPageIndex!,
        pageOffsets: _pageVerticalOffsets,
        transformationController: widget._transformationController,
      );
    }
  }

  Timer? _snapZoomTimer;

  bool _isClamping = false;

  /// Live viewport page range (±1 page margin) refreshed on every transform
  /// change. The page list below rebuilds on a bucket-throttled viewport, so
  /// without this a page edge crossing inside one bucket would leave the
  /// entering page unbuilt until the next throttle window (dark gap flash).
  /// [_PagesBuilder] unions this live range with its own render zone, and
  /// rebuilds here only fire when the range actually changes.
  int? _liveRangeStart;
  int? _liveRangeEnd;

  void onTransformChanged() {
    if (_isClamping) return;

    // Async fail-safe: kick hydration for every on-screen lazy shell (plus
    // one page beyond each edge, so an entering page is already parsing
    // before its pixels scroll in). This listener must NEVER parse page
    // bytes synchronously — a single dense page parse blocks the frame for
    // 10-25ms, which is exactly the freeze felt when transitioning pages.
    // The lazy loader time-slices the parse and defers under load; the
    // hydrated page rebuilds through its completion callback. Cost here is
    // a handful of page-state lookups per transform frame.
    if (Pen.currentStroke == null &&
        !(Eraser.isDragging ?? false) &&
        _pageVerticalOffsets.isNotEmpty &&
        containerBounds.maxHeight > 0 &&
        widget.pages.isNotEmpty) {
      final transform = widget._transformationController.value;
      final scale = transform.approxScale;
      if (scale > 0) {
        final translateY = transform.getTranslation().y;
        final contentTop = -translateY / scale;
        final contentBottom =
            (-translateY + containerBounds.maxHeight) / scale;
        final first = CanvasGestureDetector.getPageIndex(
          scrollY: contentTop,
          pageOffsets: _pageVerticalOffsets,
        );
        final last = CanvasGestureDetector.getPageIndex(
          scrollY: contentBottom,
          pageOffsets: _pageVerticalOffsets,
        );
        final hydrateStart = (first - 1).clamp(0, widget.pages.length - 1);
        final hydrateEnd = (last + 1).clamp(0, widget.pages.length - 1);

        var hydratedSync = false;
        for (var i = hydrateStart; i <= hydrateEnd; i++) {
          if (widget.pages[i].isLazyShell &&
              widget.tryHydratePage != null) {
            widget.tryHydratePage!(i);
            // A synchronous replacement (tiny slice) still shows the
            // placeholder until the page list rebuilds; request one below.
            if (!widget.pages[i].isLazyShell) hydratedSync = true;
          }
        }

        // Prebuild one page beyond each viewport edge so the entering page
        // widget (and its first paint) exists before its pixels scroll in.
        if (hydratedSync ||
            _liveRangeStart != hydrateStart ||
            _liveRangeEnd != hydrateEnd) {
          _liveRangeStart = hydrateStart;
          _liveRangeEnd = hydrateEnd;
          if (mounted) setState(() {});
        }
      }
    }

    // Transform updates every pan/zoom frame via AnimatedBuilder, but the
    // page builder is bucket-throttled. Observe the scale here for zoom LOD
    // rasters; motion itself is driven once by InteractiveCanvasViewer so
    // each frame restarts the settle timer exactly once.
    PageRasterCacheManager.setViewportScale(
      widget._transformationController.value.approxScale,
    );
    if (widget.suppressTransformClamp?.value ?? false) {
      return;
    }
    if (widget.skipTransformClampForExpansion?.value ?? false) {
      widget.skipTransformClampForExpansion!.value = false;
      return;
    }
    _clampTransform();
  }

  /// Re-run pan bounds clamping (e.g. after a viewport resize session ends).
  void reclampTransform() {
    if (!mounted) return;
    _clampTransform();
  }

  void _clampTransform() {
    final scale = widget._transformationController.value.approxScale;
    final translation = widget._transformationController.value.getTranslation();

    double adjustmentX = 0;
    double adjustmentY = 0;

    _snapZoomTimer?.cancel();
    final diffFrom1 = (scale - 1).abs();

    if (diffFrom1 < 0.05 && diffFrom1 > 0.001) {
      _snapZoomTimer = Timer(const Duration(milliseconds: 200), resetZoom);
    }

    if (scale < 1) {
      final center = containerBounds.maxWidth * (1 - scale) / 2;
      adjustmentX = center - translation.x;
    } else {
      if (widget.isInfinite) {
        late final minX = containerBounds.maxWidth * (1 - scale);
        if (translation.x > 0) {
          adjustmentX = -translation.x;
        } else if (translation.x < minX) {
          adjustmentX = minX - translation.x;
        }
      } else {
        final cWidth = containerBounds.maxWidth;
        final leftOffset = widget.pages.isEmpty ? 0.0 : (cWidth - min(widget.pages.first.size.width, cWidth)) / 2.0;
        final pageWidth = cWidth - 2 * leftOffset;

        final scaledPageWidth = pageWidth * scale;
        
        if (scaledPageWidth <= cWidth) {
          final center = cWidth * (1 - scale) / 2;
          adjustmentX = center - translation.x;
        } else {
          const allowedMargin = 0.0;

          final maxX = allowedMargin - leftOffset * scale;
          final minX = cWidth - allowedMargin - leftOffset * scale - scaledPageWidth;

          if (translation.x > maxX) {
            adjustmentX = maxX - translation.x;
          } else if (translation.x < minX) {
            adjustmentX = minX - translation.x;
          }
        }
      }
    }

    if (translation.y > 0) {
      adjustmentY = -translation.y;
    }

    if (adjustmentX.abs() > 0.001 || adjustmentY.abs() > 0.001) {
      _isClamping = true;
      // Assign a new matrix so TransformationController notifies listeners.
      // In-place leftTranslateByDouble does not, which left the canvas visually
      // uncentered after sidebar/split resize until the user panned.
      final next = Matrix4.copy(widget._transformationController.value);
      next.leftTranslateByDouble(adjustmentX, adjustmentY, 0, 1);
      widget._transformationController.value = next;
      _isClamping = false;
    }
  }

  void resetZoom() {
    final transformation = widget._transformationController.value;
    final scale = transformation.approxScale;
    if (scale == 1) return;

    widget._transformationController.value =
        setZoom(
          scaleDelta: 1 - scale,
          transformation: transformation,
          containerBounds: containerBounds,
        ) ??
        transformation;
  }

  void _listenerPointerEvent(PointerEvent event) {
    if (event is PointerDownEvent) {
      widget.onPointerDown?.call(event);
    }

    final isStylus =
        event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;

    final double? pressure;
    if (isStylus) {
      if (event.pressureMin != event.pressureMax) {
        pressure = event.pressure;
      } else {
        pressure = null;
      }

      final buttonPressed = (event.buttons & kPrimaryStylusButton) != 0;
      if (stylusButtonWasPressed != buttonPressed) {
        stylusButtonWasPressed = buttonPressed;
        widget.onStylusButtonChanged(buttonPressed);
      }
    } else {
      pressure = null;
    }
    widget.updatePointerData(event.kind, pressure, event.timeStamp);

    if (event is PointerMoveEvent &&
        widget.shouldInjectRawPointerSamplesForDraw?.call() == true) {
      widget.onRawPointerMoveForDraw?.call(event);
    }
  }

  var stylusButtonWasPressed = false;

  void _listenerPointerHoverEvent(PointerEvent event) {
    final isEraserHover = event.kind == PointerDeviceKind.invertedStylus;
    if (event.kind != PointerDeviceKind.stylus && !isEraserHover) return;

    if (event.synthesized) {
      widget.onHoveringEnd();
    } else if (isEraserHover) {
      widget.onEraserHover?.call();
    } else {
      widget.onHovering();
      final barrelPressed = (event.buttons & kPrimaryStylusButton) != 0;
      if (stylusButtonWasPressed != barrelPressed) {
        stylusButtonWasPressed = barrelPressed;
        widget.onStylusButtonChanged(stylusButtonWasPressed);
      }
    }
  }

  void _listenerPointerUpEvent(PointerEvent event) {
    widget.updatePointerData(event.kind, null, event.timeStamp);
    widget.onPointerUpOrCancel?.call(event);
    stylusButtonWasPressed = false;
    widget.onStylusButtonChanged(false);
  }

  @override
  Widget build(BuildContext context) {
    PerfProbe.hit('gdet.build');
    final Size screenSize = MediaQuery.sizeOf(context);

    return Stack(
      children: [
        Listener(
          onPointerDown: _listenerPointerEvent,
          onPointerMove: _listenerPointerEvent,
          onPointerUp: _listenerPointerUpEvent,
          onPointerCancel: _listenerPointerUpEvent,
          onPointerHover: _listenerPointerHoverEvent,
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: <Type, GestureRecognizerFactory>{
              LongPressGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    LongPressGestureRecognizer
                  >(
                    () => LongPressGestureRecognizer(
                      duration: CanvasContextMenuFeel.longPressDuration,
                    ),
                    (LongPressGestureRecognizer instance) {
                      instance.onLongPressStart = (details) {
                        widget.onLongPress(details.globalPosition);
                      };
                    },
                  ),
              TapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                    () => TapGestureRecognizer(),
                    (TapGestureRecognizer instance) {
                      instance
                        ..onSecondaryTapDown = (details) {
                          widget.onSecondaryTapDown?.call(details.globalPosition);
                        }
                        ..onTapDown = (details) {
                          widget.onTapDown?.call(details.globalPosition);
                        };
                    },
                  ),
            },
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints containerBounds) {
                final previous = this.containerBounds;
                this.containerBounds = containerBounds;
                final pageLayoutWidth =
                    widget.pageLayoutWidthOverride ?? containerBounds.maxWidth;
                final lastWidth = _lastCachedScreenWidth;
                if (pageLayoutWidth > 0 &&
                    (lastWidth == null ||
                        (pageLayoutWidth - lastWidth).abs() > 0.5)) {
                  _recalculatePageOffsets(widthOverride: pageLayoutWidth);
                }

                final sizeChanged =
                    (previous.maxWidth - containerBounds.maxWidth).abs() >
                        0.5 ||
                    (previous.maxHeight - containerBounds.maxHeight).abs() >
                        0.5;
                if (sizeChanged &&
                    containerBounds.maxWidth > 0 &&
                    containerBounds.maxHeight > 0) {
                  final size = Size(
                    containerBounds.maxWidth,
                    containerBounds.maxHeight,
                  );
                  // Synchronous: update scroll anchors before this frame paints
                  // so sidebar/split resize does not flash a wrong transform.
                  widget.onContainerBoundsChanged?.call(size);
                }

                return InteractiveCanvasViewer.builder(
                  minScale: zoomLockedValue ?? CanvasGestureDetector.kMinScale,
                  maxScale: zoomLockedValue ?? CanvasGestureDetector.kMaxScale,
                  panEnabled: !singleFingerPanLock,
                  panAxis: axisAlignedPanLock ? PanAxis.aligned : PanAxis.free,

                  interactionEndFrictionCoefficient:
                      InteractiveCanvasViewer.kDrag,

                  boundaryMargin: widget.isInfinite && widget.pages.isNotEmpty
                      ? const EdgeInsets.symmetric(
                          horizontal: double.infinity,
                          vertical: double.infinity,
                        )
                      : EdgeInsets.symmetric(
                          vertical: 0,
                          horizontal: screenSize.width * 2,
                        ),

                  transformationController: widget._transformationController,
                  scrollPhysicsStopNotifier: widget.scrollPhysicsStopNotifier,

                  isDrawGesture: widget.isDrawGesture,

                  shouldIgnorePanZoom: widget.isInfinite ? null : null,
                  onInteractionEnd: widget.onInteractionEnd,
                  onDrawStart: widget.onDrawStart,
                  onDrawUpdate: widget.onDrawUpdate,
                  onDrawEnd: widget.onDrawEnd,

                  builder: (BuildContext context, Quad viewport) {
                    PageRasterCacheManager.setViewportScale(
                      widget._transformationController.value.approxScale,
                    );
                    // Exact on-screen content rect from the live transform.
                    // [viewport] is bucket-floored and rebuild-throttled, so
                    // it can include a sliver of the page above (or miss the
                    // bottom of the page below); the open-instant band clamp
                    // needs the pages that are really on screen.
                    double? liveContentTop;
                    double? liveContentBottom;
                    if (containerBounds.maxHeight > 0) {
                      final transform =
                          widget._transformationController.value;
                      final scale = transform.approxScale;
                      if (scale > 0) {
                        final translateY = transform.getTranslation().y;
                        liveContentTop = -translateY / scale;
                        liveContentBottom =
                            (-translateY + containerBounds.maxHeight) / scale;
                      }
                    }
                    return _PagesBuilder(
                      pages: widget.pages,
                      pageBuilder: widget.pageBuilder,
                      placeholderPageBuilder: widget.placeholderPageBuilder,
                      boundingBox: _axisAlignedBoundingBox(viewport),
                      containerWidth: pageLayoutWidth,
                      isInfinite: widget.isInfinite,
                      tryHydratePage: widget.tryHydratePage,
                      onMaintainPageRasterBand:
                          widget.onMaintainPageRasterBand,
                      onPrefetchNearbyPages: widget.onPrefetchNearbyPages,
                      forcedStartPage: _liveRangeStart,
                      forcedEndPage: _liveRangeEnd,
                      liveContentTop: liveContentTop,
                      liveContentBottom: liveContentBottom,
                    );
                  },
                );
              },
            ),
          ),
        ),
        Positioned.fill(
          child: CanvasHud(
            transformationController: widget._transformationController,
            zoomLock: zoomLockedValue != null,
            setZoomLock: (bool zoomLock) => setState(() {
              zoomLockedValue = zoomLock
                  ? widget._transformationController.value.approxScale
                  : null;
              stows.lastZoomLock.value = zoomLock;
            }),
            resetZoom: zoomLockedValue != null ? null : resetZoom,
            singleFingerPanLock: singleFingerPanLock,
            setSingleFingerPanLock: (bool singleFingerPanLock) => setState(() {
              this.singleFingerPanLock = singleFingerPanLock;
              stows.lastSingleFingerPanLock.value = singleFingerPanLock;
            }),
            axisAlignedPanLock: axisAlignedPanLock,
            setAxisAlignedPanLock: (bool axisAlignedPanLock) => setState(() {
              this.axisAlignedPanLock = axisAlignedPanLock;
              stows.lastAxisAlignedPanLock.value = axisAlignedPanLock;
            }),
            onAddPageAbove: widget.onAddPageAbove,
            onAddPageBelow: widget.onAddPageBelow,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    // Compute the page range the saved transform actually shows (the same
    // math [onTransformChanged] uses, without the prebuild margins): the
    // loader parses these pages up front so the first painted frame after a
    // reopen is real content, not a blank lazy-shell placeholder.
    final transform = widget._transformationController.value;
    final scale = transform.approxScale;
    final offsets = _pageVerticalOffsets;
    int? landingStart;
    int? landingEnd;
    if (scale > 0 && offsets.isNotEmpty && containerBounds.maxHeight > 0) {
      final translateY = transform.getTranslation().y;
      final contentTop = -translateY / scale;
      final contentBottom = (-translateY + containerBounds.maxHeight) / scale;
      landingStart = CanvasGestureDetector.getPageIndex(
        scrollY: contentTop,
        pageOffsets: offsets,
      );
      landingEnd = CanvasGestureDetector.getPageIndex(
        scrollY: contentBottom,
        pageOffsets: offsets,
      );
    }
    // ignore: invalid_use_of_visible_for_testing_member
    CanvasTransformCache.add(
      widget.filePath,
      transform,
      pageIndex: landingStart,
      pageIndexEnd: landingEnd,
    );
    widget._transformationController.removeListener(onTransformChanged);
    widget._transformationController.dispose();
    _removeKeybindings();
    super.dispose();
  }

  static Rect _axisAlignedBoundingBox(Quad quad) {
    final List<Vector3> points = [
      quad.point0,
      quad.point1,
      quad.point2,
      quad.point3,
    ];

    final left = points.map((point) => point.x).reduce(min);
    final right = points.map((point) => point.x).reduce(max);
    final top = points.map((point) => point.y).reduce(min);
    final bottom = points.map((point) => point.y).reduce(max);

    return Rect.fromLTRB(left, top, right, bottom);
  }
}

class _PagesBuilder extends StatefulWidget {
  const _PagesBuilder({
    required this.pages,
    required this.pageBuilder,
    required this.placeholderPageBuilder,
    required this.boundingBox,
    required this.containerWidth,
    this.isInfinite = false,
    this.tryHydratePage,
    this.onMaintainPageRasterBand,
    this.onPrefetchNearbyPages,
    this.forcedStartPage,
    this.forcedEndPage,
    this.liveContentTop,
    this.liveContentBottom,
  });

  final List<EditorPage> pages;
  final Widget Function(BuildContext context, int pageIndex) pageBuilder;
  final Widget Function(BuildContext context, int pageIndex)
  placeholderPageBuilder;
  final Rect boundingBox;
  final double containerWidth;
  final bool isInfinite;
  final bool Function(int pageIndex)? tryHydratePage;
  final void Function(int visibleStart, int visibleEnd)?
  onMaintainPageRasterBand;
  final int Function(int bandStart, int bandEnd)? onPrefetchNearbyPages;

  /// Live viewport page range from the transform listener. Unioned with the
  /// render zone below so an entering page is built before its pixels scroll
  /// into view, even though the [boundingBox] viewport itself is
  /// bucket-throttled.
  final int? forcedStartPage;
  final int? forcedEndPage;

  /// Exact content-space viewport rect from the live transform (unlike
  /// [boundingBox], which is bucket-floored). Only used by the open-instant
  /// band clamp.
  final double? liveContentTop;
  final double? liveContentBottom;

  @override
  State<_PagesBuilder> createState() => _PagesBuilderState();
}

class _PagesBuilderState extends State<_PagesBuilder> with WidgetsBindingObserver {
  static const _renderCacheExtent = 500.0;
  // PDF notes prebuild ~one page ahead. Two mechanical reasons this must
  // exceed one page:
  // 1. [boundingBox] is bucket-floored (360px leaves) and rebuilt at most
  //    every 180ms during motion, so the live viewport can run up to
  //    ~360px + sprint past the render zone before a rebuild catches up —
  //    a page entering that gap has NO widget at all (bare canvas = the
  //    white band while panning).
  // 2. The entering page's load chain (tile probe/fill, native texture
  //    open) starts at widget mount; without look-ahead, that chain starts
  //    when the page is already visible, i.e. seconds of blank.
  // Widgets are cheap to build; big surfaces are still owned by the retile
  // logic inside the PDF page renderer.
  static const _pdfRenderCacheExtent = 1000.0;
  static const _minHydrateRadius = 1;
  // Max new shell parses started per warm-up pass while the viewport is
  // settled. The loader's concurrency cap keeps the total bounded.
  static const _maxShellsPerWarmPass = 3;
  // Parse-ahead horizon for the aggressive warmer: scrolls land inside it.
  static const _warmHydrateRadius = 5;
  // Lead pages hydrated beyond the warm band in the direction of travel
  // while the viewport is moving, so arrivals land on painted content.
  static const _motionLeadPages = 6;

  // Background warm-up pacing. The pump is Timer-driven so hydration keeps
  // converging while the app is idle; frame-chained sweeps only advanced
  // while frames were being produced, so pages ahead were still blank
  // shells when a later fling or jump reached them. During the open grace
  // the cadence halves: the first fling comes within the first moment and
  // must land on warmed pages.
  //
  // A pass is already frame-bounded (~8 ms of tile recording), so the timer
  // only has to leave room for the gesture/paint frames between passes.
  // While the user is driving the viewport it backs off further: gesture
  // frames get the isolate, and warming resumes the moment input stops.
  static const _warmupPumpPeriod = Duration(milliseconds: 32);
  static const _warmupPumpGracePeriod = Duration(milliseconds: 16);
  static const _warmupPumpInputPeriod = Duration(milliseconds: 48);

  final _pageOffsets = <double>[];
  final _pageHeights = <double>[];
  final _pageWidths = <double>[];

  double? _cachedContainerWidth;
  var _cachedPagesLength = 0;
  var _totalHeight = 0.0;
  var _idleWorkScheduled = false;
  var _hasPdfBackedPages = false;
  // Persistent whole-note warmer. Build kicks run an immediate pass so
  // scrolls warm in realtime; the pump guarantees progress when the app is
  // idle and no frames are being produced.
  Timer? _warmupPumpTimer;
  var _lastVisibleStart = 0;
  var _lastVisibleEnd = 0;
  var _lastPassVisibleStart = -1;
  var _travelDirection = 0;
  final _probeShellPages = <int>{};

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _warmupPumpTimer?.cancel();
    _warmupPumpTimer = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(_PagesBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);

    bool pageSizesChanged = false;
    if (widget.pages.length == oldWidget.pages.length) {
      for (int i = 0; i < widget.pages.length; i++) {
        if (widget.pages[i].size != oldWidget.pages[i].size) {
          pageSizesChanged = true;
        }
      }
    } else {
      pageSizesChanged = true;
    }
    if (widget.containerWidth != _cachedContainerWidth ||
        widget.pages.length != _cachedPagesLength ||
        pageSizesChanged) {
      _recalculateLayout();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recalculateLayout();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The pump sleeps while backgrounded; restart it on resume — there may
    // be no other rebuild (scroll/edit/theme) to kick it.
    if (state == AppLifecycleState.resumed) {
      _scheduleIdlePageWork(_lastVisibleStart, _lastVisibleEnd);
    }
  }

  void _recalculateLayout() {
    _pageOffsets.clear();
    _pageHeights.clear();
    _pageWidths.clear();

    double currentTop = widget.isInfinite ? 0 : Editor.gapBetweenPages * 2;

    for (final page in widget.pages) {
      final pageWidth = min(page.size.width, widget.containerWidth);
      final pageHeight = (pageWidth / page.size.width) * page.size.height;

      _pageOffsets.add(currentTop);
      _pageHeights.add(pageHeight);
      _pageWidths.add(pageWidth);

      currentTop +=
          pageHeight + (widget.isInfinite ? 0 : Editor.gapBetweenPages);
    }

    if (!widget.isInfinite) {
      currentTop += Editor.gapBetweenPages;
    }
    _totalHeight = currentTop;

    _cachedContainerWidth = widget.containerWidth;
    _cachedPagesLength = widget.pages.length;
    _hasPdfBackedPages = widget.pages
        .take(24)
        .any((page) => page.backgroundImage?.extension == '.pdf');
  }

  /// Do not cache the built page subtree: caching the same [Widget] instance
  /// makes [Element.updateChild] skip updating descendants (`child.widget ==
  /// newWidget`), so [Canvas] stays frozen with stale `currentStroke` and the
  /// live-stroke overlay never mounts. Rebuilding here is cheap relative to
  /// paint work; [RepaintBoundary] still contains ink invalidations per page.
  Widget _pageChild(BuildContext context, int pageIndex) {
    final page = widget.pages[pageIndex];
    // Never blank a mounted PDF page on zoom/scroll/pan: the GPU texture
    // glides with the page at zero CPU cost, and [_PdfPageRendererState]
    // gates NEW renders on [viewportMoving] internally — so keeping the
    // widget mounted never opens a bitmap per page during a fling. Swapping
    // to the placeholder here is exactly the "pages turn white while
    // moving" flash: the placeholder is a bare colored rect with no PDF
    // content. Only lazy BSON shells (no content parsed yet) use it.
    final child = page.isLazyShell
        ? widget.placeholderPageBuilder(context, pageIndex)
        : widget.pageBuilder(context, pageIndex);
    if (PerfProbe.enabled) {
      if (page.isLazyShell) {
        if (_probeShellPages.add(pageIndex)) {
          PerfProbe.mark('shell.enter i=$pageIndex');
        }
      } else if (_probeShellPages.remove(pageIndex)) {
        PerfProbe.mark('shell.exit i=$pageIndex');
      }
    }
    return RepaintBoundary(child: child);
  }

  void _scheduleIdlePageWork(int startIndex, int endIndex) {
    if (widget.pages.isEmpty) return;
    PerfProbe.hit('idle.sched');
    _lastVisibleStart = startIndex.clamp(0, widget.pages.length - 1);
    _lastVisibleEnd = endIndex.clamp(0, widget.pages.length - 1);
    _ensureWarmupPump();
    if (_idleWorkScheduled) return;
    _idleWorkScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _idleWorkScheduled = false;
      if (!mounted) return;
      // Use the latest visible range, not the one captured at kick time:
      // flings move several pages between kick and callback.
      _runWarmupPass();
    });
  }

  /// Frame-independent warm-up pump: a Timer-driven pass while lazy shells
  /// remain. The old frame-chained sweep could only advance while frames
  /// were being produced — an idle app (no scroll, no animation) stopped
  /// warming entirely, so a page reached later by a fling or jump was still
  /// a blank shell and had to parse on arrival. The pump keeps hydration
  /// converging in the background; build kicks still run an immediate pass
  /// so scrolls warm in realtime.
  void _ensureWarmupPump() {
    if (_warmupPumpTimer != null || !mounted || widget.pages.isEmpty) return;
    // Open grace: the viewport is where the user will start panning within
    // the first moment, so the band must be warm before they touch it. Run
    // the pump at ~2x cadence while the grace lasts (each pass is bounded by
    // the editor's per-frame warm budget, so frames stay inside ~one frame);
    // once the grace ends or the user takes over, the normal idle cadence
    // resumes. Without this the first fling entered pages the 48 ms pump
    // period had not reached yet and paid the cold-page geometry build.
    final grace = PageRasterCacheManager.openGraceUntil;
    final fastGrace =
        grace != null &&
        DateTime.now().isBefore(grace) &&
        !PageRasterCacheManager.userInputRecent;
    final period = fastGrace
        ? _warmupPumpGracePeriod
        : PageRasterCacheManager.userInputRecent
            ? _warmupPumpInputPeriod
            : _warmupPumpPeriod;
    _warmupPumpTimer = Timer(period, () {
      _warmupPumpTimer = null;
      if (!mounted) return;
      if (_runWarmupPass()) _ensureWarmupPump();
    });
  }

  bool _hasLazyShells() {
    for (final page in widget.pages) {
      if (page.isLazyShell) return true;
    }
    return false;
  }

  /// One warm-up pass: maintain the raster keep-band, prewarm tiles/meshes
  /// near the viewport, and start bounded lazy-page parses.
  ///
  /// Hydration order is nearest-first from the viewport center across the
  /// whole note when settled (so pages are materialized before a fling
  /// reaches them); while moving it stays in the warm band plus a lead of
  /// [_motionLeadPages] pages in the travel direction, so arrivals land on
  /// painted content without queuing parses for pages the pan will never
  /// reach. Parse slices are bounded (a couple of ms, capped at a small
  /// number of concurrent parses), so background warmth never becomes a
  /// freeze.
  ///
  /// Returns true when lazy shells remain and another pass should run.
  bool _runWarmupPass() {
    PerfProbe.hit('warm.pass');
    if (Pen.currentStroke != null || Eraser.isDragging) {
      // Drawing has priority; the pump retries on its next tick.
      return true;
    }
    final lifecycle = SchedulerBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      // Backgrounded: stop burning CPU; the observer restarts the pump on
      // resume (there may be no other rebuild to kick it).
      return false;
    }
    final pageCount = widget.pages.length;
    if (pageCount == 0) return false;
    final visibleStart = _lastVisibleStart.clamp(0, pageCount - 1);
    final visibleEnd = _lastVisibleEnd.clamp(0, pageCount - 1);

    // Travel direction for lead-biased hydration while scrolling.
    if (visibleStart != _lastPassVisibleStart) {
      if (PageRasterCacheManager.viewportMoving &&
          _lastPassVisibleStart >= 0) {
        _travelDirection = visibleStart > _lastPassVisibleStart ? 1 : -1;
      }
      _lastPassVisibleStart = visibleStart;
    }

    final moving = PageRasterCacheManager.viewportMoving;
    final visibleCount = (visibleEnd - visibleStart + 1).clamp(1, 64);
    // Raster keep-set stays tight (GPU bitmaps): ±N where N ≈ number of
    // visible pages (min 2).
    final radius = max(_minHydrateRadius, visibleCount);
    final start = (visibleStart - radius).clamp(0, pageCount - 1);
    final end = (visibleEnd + radius).clamp(0, pageCount - 1);
    widget.onMaintainPageRasterBand?.call(start, end);
    // Warm horizon is wider (parse + tiles are CPU-cheap to keep ahead).
    final warmStart =
        (visibleStart - _warmHydrateRadius).clamp(0, pageCount - 1);
    final warmEnd = (visibleEnd + _warmHydrateRadius).clamp(0, pageCount - 1);
    // Prewarm runs even during the post-open bake-defer window: recording a
    // page's tile pictures up front (in budgeted slices) is far cheaper than
    // re-recording the same dense strokes as fallback vectors on every paint
    // until the tiles exist — measured at 55-133 ms for the first paint of a
    // dense page whose tiles were skipped. Raster bakes (toImage) stay
    // deferred by PageRasterCacheManager.
    final geomBefore = TiledStrokePictureCache.geometryWarmEpoch;
    final warmRecorded =
        widget.onPrefetchNearbyPages?.call(warmStart, warmEnd) ?? 0;
    final geometryWarmed =
        TiledStrokePictureCache.geometryWarmEpoch != geomBefore;
    final center = ((visibleStart + visibleEnd) / 2).round().clamp(
      0,
      pageCount - 1,
    );

    var started = 0;
    var hydratedSync = 0;
    if (widget.tryHydratePage != null) {
      var hydrateStart = moving ? warmStart : 0;
      var hydrateEnd = moving ? warmEnd : pageCount - 1;
      if (moving && _travelDirection > 0) {
        hydrateEnd = min(pageCount - 1, hydrateEnd + _motionLeadPages);
      } else if (moving && _travelDirection < 0) {
        hydrateStart = max(0, hydrateStart - _motionLeadPages);
      }
      // Slow reading pans may start two parses per pass (parses are
      // unthrottled there); fast flings start one so gesture frames keep
      // the lion's share of the UI isolate.
      final maxPerCall = !moving
          ? _maxShellsPerWarmPass
          : (PageRasterCacheManager.viewportSlowMotion ? 2 : 1);
      final maxDist = max(center - hydrateStart, hydrateEnd - center);
      hydrate:
      for (var dist = 0; dist <= maxDist; dist++) {
        for (final i in <int>{center - dist, if (dist > 0) center + dist}) {
          if (i < hydrateStart || i > hydrateEnd) continue;
          if (!widget.pages[i].isLazyShell) continue;
          if (widget.tryHydratePage!(i)) {
            if (widget.pages[i].isLazyShell) {
              started++;
            } else {
              hydratedSync++;
            }
            if (started + hydratedSync >= maxPerCall) break hydrate;
          }
        }
      }
    }
    if (hydratedSync > 0 && mounted) setState(() {});
    if (!mounted) return false;
    // Keep the pump alive while the band still has tiles to record, not only
    // while shells remain: otherwise the pump stopped ~1.3 s after open (all
    // pages parsed) and a fling at 2 s entered pages the 48 ms cadence had
    // not reached yet. A pass that records nothing means the band is warm.
    return _hasLazyShells() || warmRecorded > 0 || geometryWarmed;
  }

  int _findFirstVisiblePageIndex(double viewportTop) {
    if (_pageOffsets.isEmpty) return 0;

    int min = 0;
    int max = _pageOffsets.length - 1;

    if (viewportTop <= _pageOffsets.first) return 0;

    if (viewportTop >= _pageOffsets.last + _pageHeights.last) return max;

    while (min <= max) {
      final mid = min + ((max - min) >> 1);
      final offset = _pageOffsets[mid];
      final height = _pageHeights[mid];

      if (offset + height < viewportTop) {
        min = mid + 1;
      } else if (offset > viewportTop) {
        max = mid - 1;
      } else {
        return mid;
      }
    }

    return max >= 0 ? max : 0;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pages.isEmpty) return const SizedBox();
    PerfProbe.hit('pages.build');

    final visibleWidgets = <Widget>[];

    final renderCacheExtent = _hasPdfBackedPages
        ? _pdfRenderCacheExtent
        : _renderCacheExtent;
    final renderZone = widget.boundingBox.inflate(renderCacheExtent);

    var startIndex = _findFirstVisiblePageIndex(renderZone.top);
    var endIndex = startIndex;

    for (int i = startIndex; i < widget.pages.length; i++) {
      final offset = _pageOffsets[i];

      if (offset > renderZone.bottom) break;
      endIndex = i;
    }

    // Open instant: keep only the pages actually on screen mounted for the
    // short window right after a note opens. A cold dense page's first paint
    // records the whole page (~60-130 ms), so mounting the ±1 look-ahead band
    // on top of the landing page turned the open into several heavy frames in
    // a row. The warm-up pump records the neighbors' tiles in budgeted slices
    // meanwhile, so they blit — not re-record — when they mount (the band
    // returns once the grace expires or their pixels enter the viewport).
    //
    // The clamp only describes the landing placement, which is programmatic.
    // As soon as the user drives the viewport (first pointer down) the normal
    // look-ahead band takes over again: panning needs the pages on both sides
    // mounted ahead of the finger, and each cold first paint is now bounded
    // to ~one frame by the paint budgets.
    final graceStamp = PageRasterCacheManager.openGraceUntil;
    final openGrace =
        graceStamp != null &&
        DateTime.now().isBefore(graceStamp) &&
        !PageRasterCacheManager.userInputRecent;
    var clampedStart = -1;
    var clampedEnd = -1;
    final liveTop = widget.liveContentTop;
    final liveBottom = widget.liveContentBottom;
    if (openGrace &&
        !widget.isInfinite &&
        // PDF pages start their texture chain at widget mount; keep their
        // look-ahead band mounted (they are not the dense-stroke case this
        // clamp targets).
        !_hasPdfBackedPages &&
        liveTop != null &&
        liveBottom != null) {
      // Pages intersecting the exact on-screen rect (skip the page above
      // when the viewport top sits in the inter-page gap, and pages that
      // start at/below the viewport bottom). The landing placement lands a
      // frame or two after the first build (programmatic jump), so this is
      // recomputed from the live transform on every build: pages mount as
      // their pixels enter the viewport, never one whole look-ahead band
      // early (whose cold first paints were the open hitch).
      var visStart = _findFirstVisiblePageIndex(liveTop);
      while (visStart < widget.pages.length - 1 &&
          _pageOffsets[visStart] + _pageHeights[visStart] <= liveTop) {
        visStart++;
      }
      var visEnd = visStart;
      for (int i = visStart; i < widget.pages.length; i++) {
        if (_pageOffsets[i] >= liveBottom) break;
        visEnd = i;
      }
      clampedStart = visStart;
      clampedEnd = visEnd;
      PerfProbe.hit('band.clamp');
      PerfProbe.markOnce(
        'band.clamp.$graceStamp.$visStart-$visEnd',
        'band.clamp pages=$visStart..$visEnd '
            'top=${liveTop.toStringAsFixed(0)} '
            'bottom=${liveBottom.toStringAsFixed(0)}',
      );
    }
    if (clampedStart >= 0) {
      startIndex = clampedStart;
      endIndex = clampedEnd < clampedStart ? clampedStart : clampedEnd;
    } else {
      // Union with the live transform range: the render zone above is derived
      // from a bucket-throttled viewport, so without this an entering page
      // would stay unbuilt (dark gap) until the next throttle window, even
      // though its edge is already on screen.
      final forcedStart = widget.forcedStartPage;
      final forcedEnd = widget.forcedEndPage;
      if (forcedStart != null &&
          forcedEnd != null &&
          widget.pages.isNotEmpty) {
        startIndex = min(
          startIndex,
          forcedStart.clamp(0, widget.pages.length - 1),
        );
        endIndex = max(
          endIndex,
          forcedEnd.clamp(0, widget.pages.length - 1),
        );
      }
    }

    // Build order follows distance to the visible middle (not page
    // order): the current page's PDF parse+render jobs hit pdfrx's single
    // worker first, so visible content paints ~seconds earlier on deep
    // notes instead of waiting behind neighbor pages. Layout is unaffected
    // (absolute Positioned offsets); paint order of non-overlapping pages
    // is irrelevant.
    final mid = (startIndex + endIndex) ~/ 2;
    final buildOrder = <int>[];
    for (int i = startIndex; i <= endIndex && i < widget.pages.length; i++) {
      buildOrder.add(i);
    }
    buildOrder.sort((a, b) {
      final da = (a - mid).abs();
      final db = (b - mid).abs();
      if (da != db) return da.compareTo(db);
      return a.compareTo(b);
    });
    for (final i in buildOrder) {
      final offset = _pageOffsets[i];
      final height = _pageHeights[i];
      final width = _pageWidths[i];

      final double leftOffset = (widget.containerWidth - width) / 2;

      widget.pages[i].isRendered = true;

      visibleWidgets.add(
        Positioned(
          key: ValueKey('page_pos_$i'),
          top: offset,
          left: leftOffset,
          width: width,
          height: height,

          child: _pageChild(context, i),
        ),
      );
    }
    _scheduleIdlePageWork(startIndex, endIndex);

    final content = SizedBox(
      height: _totalHeight,
      width: widget.containerWidth,
      child: Stack(clipBehavior: Clip.none, children: visibleWidgets),
    );

    if (widget.isInfinite) {
      return AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topLeft,
        child: content,
      );
    }
    return content;
  }
}
