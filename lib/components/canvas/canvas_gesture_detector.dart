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
import 'package:saber/components/canvas/hud/canvas_hud.dart';
import 'package:saber/components/canvas/canvas_context_menu_feel.dart';
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
    TransformationController? transformationController,
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

    // Synchronous fail-safe: hydrate any on-screen lazy shell right here, in
    // the transform listener, before the frame builds. The idle hydrate loop
    // lags a frame behind, so without this a fast pan could render a shell
    // placeholder for one frame. Cheap: binary search over page offsets.
    if (Pen.currentStroke == null &&
        Eraser.isDragging == false &&
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
        final firstClamped =
            first.clamp(0, widget.pages.length - 1);
        final lastClamped =
            last.clamp(0, widget.pages.length - 1);
        var hydratedSync = false;
        for (var i = firstClamped; i <= lastClamped; i++) {
          if (widget.pages[i].isLazyShell &&
              widget.tryHydratePage != null) {
            widget.tryHydratePage!(i);
            // A synchronous replacement still shows the placeholder until
            // the page list rebuilds, so request one below.
            if (!widget.pages[i].isLazyShell) hydratedSync = true;
          }
        }
        // Prebuild one page beyond each viewport edge so the entering page
        // widget (and its first paint) exists before its pixels scroll in.
        final liveStart = (firstClamped - 1).clamp(0, widget.pages.length - 1);
        final liveEnd = (lastClamped + 1).clamp(0, widget.pages.length - 1);
        if (hydratedSync ||
            _liveRangeStart != liveStart ||
            _liveRangeEnd != liveEnd) {
          _liveRangeStart = liveStart;
          _liveRangeEnd = liveEnd;
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
          final double allowedMargin = 0.0;

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
                      ? EdgeInsets.symmetric(
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
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    CanvasTransformCache.add(
      widget.filePath,
      widget._transformationController.value,
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

  @override
  State<_PagesBuilder> createState() => _PagesBuilderState();
}

class _PagesBuilderState extends State<_PagesBuilder> {
  static const double _renderCacheExtent = 500;
  // Same prebuild margin as stroke notes: the viewport driving the render
  // zone is bucket-throttled, so a smaller PDF margin routinely left the
  // entering page unbuilt (dark flash). Building the widget early is cheap;
  // bitmap budgets are still owned by the raster band logic.
  static const double _pdfRenderCacheExtent = 500;
  static const int _minHydrateRadius = 2;
  static const int _maxShellsPerIdleFrame = 3;
  // Parse-ahead horizon for the aggressive warmer: scrolls land inside it.
  static const int _warmHydrateRadius = 6;
  // Far-horizon pacing: one slice per tick, no vsync storm while waiting.
  // Fast enough that a freshly opened note converges in about a second;
  // each tick still yields, so opening stays interactive.
  static const int _trickleIntervalMs = 150;

  final List<double> _pageOffsets = [];
  final List<double> _pageHeights = [];
  final List<double> _pageWidths = [];

  double? _cachedContainerWidth;
  int _cachedPagesLength = 0;
  double _totalHeight = 0;
  bool _idleWorkScheduled = false;
  bool _hasPdfBackedPages = false;
  int _viewportMovingBlockedFrames = 0;
  // Persistent whole-note warmer: the aggressive loop chains frame callbacks
  // while making progress (nearest-first), then sleeps; any build kick
  // (scroll/edit/theme) wakes it. A slow trickle covers pages beyond the
  // aggressive horizon so waiting really warms everything over time.
  bool _warming = false;
  int _lastVisibleStart = 0;
  int _lastVisibleEnd = 0;
  Timer? _trickleTimer;

  @override
  void dispose() {
    _trickleTimer?.cancel();
    _trickleTimer = null;
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
    _recalculateLayout();
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
    final child = page.isLazyShell
        ? widget.placeholderPageBuilder(context, pageIndex)
        : widget.pageBuilder(context, pageIndex);
    return RepaintBoundary(child: child);
  }

  void _scheduleIdlePageWork(int startIndex, int endIndex) {
    if (widget.pages.isEmpty) return;
    _lastVisibleStart = startIndex.clamp(0, widget.pages.length - 1);
    _lastVisibleEnd = endIndex.clamp(0, widget.pages.length - 1);
    _kickTrickle();
    if (_warming || _idleWorkScheduled) return;
    _warming = true;
    _idleWorkScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _idleWorkScheduled = false;
      if (!mounted) {
        _warming = false;
        return;
      }
      // Use the latest visible range, not the one captured at kick time:
      // flings move several pages between kick and callback.
      _runIdlePageWork(_lastVisibleStart, _lastVisibleEnd);
    });
  }

  /// Slow far-horizon sweep (one slice per tick): warms pages beyond the
  /// aggressive band so waiting on any page eventually warms the whole note.
  /// Progress-tracked; stops when done. Skipped while drawing/moving/hidden.
  void _kickTrickle() {
    if (_trickleTimer != null || !mounted || widget.pages.isEmpty) return;
    if (_warming) return;
    _trickleTimer = Timer(const Duration(milliseconds: _trickleIntervalMs), () {
      _trickleTimer = null;
      if (!mounted || _warming) return;
      _runTrickle();
    });
  }

  void _runTrickle() {
    if (!mounted || _warming) return;
    if (Pen.currentStroke != null || Eraser.isDragging) return;
    // Fast flings pause the far-horizon sweep (paint fallback keeps those
    // pages visible); slow pans and settled frames keep converging.
    if (PageRasterCacheManager.viewportMoving &&
        !PageRasterCacheManager.viewportSlowMotion) {
      _kickTrickle();
      return;
    }
    if (SchedulerBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final pageCount = widget.pages.length;
    if (pageCount == 0) return;
    final center = ((_lastVisibleStart + _lastVisibleEnd) / 2)
        .round()
        .clamp(0, pageCount - 1);
    var hydrated = 0;
    if (widget.tryHydratePage != null) {
      // Nearest shells anywhere in the note (beyond the aggressive band),
      // up to two per tick so a fresh open converges quickly. Dense slices
      // hydrate chunked-async with UI yields, so this stays interactive.
      for (var n = 0; n < 2; n++) {
        var nearest = -1;
        var bestDist = pageCount + 1;
        for (var i = 0; i < pageCount; i++) {
          if (!widget.pages[i].isLazyShell) continue;
          final dist = (i - center).abs();
          if (dist < bestDist) {
            bestDist = dist;
            nearest = i;
          }
        }
        if (nearest < 0) break;
        if (widget.tryHydratePage!(nearest)) {
          hydrated++;
        } else {
          break;
        }
      }
    }
    // Whole-note tile trickle; the editor orders outward from the viewport.
    final prewarmed =
        widget.onPrefetchNearbyPages?.call(0, pageCount - 1) ?? 0;
    if (hydrated > 0 && mounted) setState(() {});
    if (hydrated > 0 || prewarmed > 0) {
      _kickTrickle();
    }
    // Else fully warm: sleep until the next build kick.
  }

  void _runIdlePageWork(int visibleStart, int visibleEnd) {
    if (Pen.currentStroke != null || Eraser.isDragging) {
      // Drawing has priority; the loop sleeps and the next build kick
      // (pen-up always rebuilds) resumes it.
      _warming = false;
      _trickleTimer?.cancel();
      _trickleTimer = null;
      return;
    }
    // Hydrate near shells even mid-motion (at a reduced pace) so a live pan
    // rarely exposes an empty page. No hard 6-frame gate: the sync hydrate in
    // the transform listener already guarantees on-screen shells, this loop
    // just keeps a wider band ready. Safety net: if the moving flag ever gets
    // stuck (programmatic jump without settle), force-clear it so tiles and
    // bakes resume instead of staying blit-only forever.
    final moving = PageRasterCacheManager.viewportMoving;
    if (moving) {
      _viewportMovingBlockedFrames++;
      if (_viewportMovingBlockedFrames >= 6) {
        PageRasterCacheManager.endProgrammaticViewportJump();
        _viewportMovingBlockedFrames = 0;
      }
    } else {
      _viewportMovingBlockedFrames = 0;
    }

    final pageCount = widget.pages.length;
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
    final prewarmed =
        widget.onPrefetchNearbyPages?.call(warmStart, warmEnd) ?? 0;
    final center = ((visibleStart + visibleEnd) / 2).round().clamp(
      0,
      pageCount - 1,
    );

    var hydrated = 0;
    if (widget.tryHydratePage != null) {
      // Nearest-first: walk by distance from viewport center. While moving,
      // hydrate at most one shell per frame so gesture frames stay bounded.
      final maxPerCall = moving ? 1 : _maxShellsPerIdleFrame;
      final maxDist = max(center - warmStart, warmEnd - center);
      for (var dist = 0; dist <= maxDist; dist++) {
        for (final i in <int>{center - dist, if (dist > 0) center + dist}) {
          if (i < warmStart || i > warmEnd) continue;
          if (!widget.pages[i].isLazyShell) continue;
          if (widget.tryHydratePage!(i)) {
            hydrated++;
            if (hydrated >= maxPerCall) {
              if (mounted) setState(() {});
              _scheduleIdlePageWork(visibleStart, visibleEnd);
              return;
            }
          }
        }
      }
    }
    if (hydrated > 0 && mounted) setState(() {});
    // Persistent loop: chain while making progress anywhere in the horizon;
    // sleep when fully warm (any build kick wakes us). The trickle covers
    // pages beyond the horizon.
    if (mounted && (hydrated > 0 || prewarmed > 0)) {
      _scheduleIdlePageWork(visibleStart, visibleEnd);
    } else {
      _warming = false;
      _kickTrickle();
    }
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

    for (int i = startIndex; i <= endIndex && i < widget.pages.length; i++) {
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

@visibleForTesting
class CanvasTransformCache {
  static const _maxCacheSize = 5;
  static final _cache = LinkedList<CanvasTransformCacheItem>();

  CanvasTransformCache._();

  static void add(String filePath, Matrix4 transform) {
    for (final entry in _cache) {
      if (entry.filePath != filePath) continue;
      entry.unlink();
      break;
    }
    _cache.add(CanvasTransformCacheItem(filePath, transform));

    if (_cache.length > _maxCacheSize) {
      _cache.first.unlink();
    }
  }

  static CanvasTransformCacheItem? get(String filePath) {
    try {
      return _cache.firstWhere((item) => item.filePath == filePath);
    } on StateError {
      return null;
    }
  }

  @visibleForTesting
  static void clear() {
    _cache.clear();
  }
}

@visibleForTesting
base class CanvasTransformCacheItem
    extends LinkedListEntry<CanvasTransformCacheItem> {
  final String filePath;
  final Matrix4 transform;

  CanvasTransformCacheItem(this.filePath, this.transform);
}
