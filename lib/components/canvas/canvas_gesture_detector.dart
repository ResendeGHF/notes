// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:keybinder/keybinder.dart';
import 'package:saber/components/canvas/hud/canvas_hud.dart';
import 'package:saber/components/canvas/interactive_canvas.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/change_notifier_extensions.dart';
import 'package:saber/data/extensions/matrix4_extensions.dart';
import 'package:saber/data/prefs.dart';
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
    this.shouldInjectRawPointerSamplesForDraw,
    this.onRawPointerMoveForDraw,
    required this.onHovering,
    required this.onHoveringEnd,
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
    this.scrollPhysicsStopNotifier,
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

  final bool Function()? shouldInjectRawPointerSamplesForDraw;
  final void Function(PointerMoveEvent event)? onRawPointerMoveForDraw;

  final VoidCallback onHovering;
  final VoidCallback onHoveringEnd;
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

  final ValueNotifier<int>? scrollPhysicsStopNotifier;

  late final TransformationController _transformationController;

  final void Function(Offset globalPosition)? onTapDown;

  @override
  State<CanvasGestureDetector> createState() => CanvasGestureDetectorState();

  static const kMinScale = 0.3;
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

    transformation.leftTranslateByDouble(
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
    widget._transformationController.notifyListenersPlease();
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

    if (widget.pages != oldWidget.pages) {
      _recalculatePageOffsets();
    }

    if (oldWidget.initialPageIndex != widget.initialPageIndex ||
        oldWidget.filePath != widget.filePath) {
      setInitialTransform();
    }
    super.didUpdateWidget(oldWidget);
  }

  void _recalculatePageOffsets() {
    final screenWidth = MediaQuery.sizeOf(context).width;

    if (screenWidth == _lastCachedScreenWidth &&
        _pageVerticalOffsets.length == widget.pages.length &&
        _pageVerticalOffsets.isNotEmpty) {
      return;
    }

    _lastCachedScreenWidth = screenWidth;
    _pageVerticalOffsets.clear();
    double currentTop = 0;

    for (final page in widget.pages) {
      _pageVerticalOffsets.add(currentTop);

      final pageSize = page.size;

      final pageWidthFitted = min(pageSize.width, screenWidth);

      currentTop += 16;
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

  void onTransformChanged() {

    if (widget.skipTransformClampForExpansion?.value ?? false) {
      widget.skipTransformClampForExpansion!.value = false;
      return;
    }
    final scale = widget._transformationController.value.approxScale;
    final translation = widget._transformationController.value.getTranslation();

    double adjustmentX = 0;
    double adjustmentY = 0;

    _snapZoomTimer?.cancel();
    final diffFrom1 = (scale - 1).abs();

    if (diffFrom1 < 0.05 && diffFrom1 > 0.001)
      _snapZoomTimer = Timer(const Duration(milliseconds: 200), resetZoom);

    if (scale < 1) {

      final center = containerBounds.maxWidth * (1 - scale) / 2;
      adjustmentX = center - translation.x;
    } else {

      late final minX = containerBounds.maxWidth * (1 - scale);
      if (translation.x > 0) {
        adjustmentX = -translation.x;
      } else if (translation.x < minX) {
        adjustmentX = minX - translation.x;
      }

      if (translation.y > 0) {
        adjustmentY = -translation.y;
      }
    }

    if (adjustmentX.abs() > 0.1 || adjustmentY.abs() > 0.1) {
      widget._transformationController.value.leftTranslateByDouble(
        adjustmentX,
        adjustmentY,
        0,
        1,
      );
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
    if (event.kind != PointerDeviceKind.stylus) return;

    if (event.synthesized) {
      widget.onHoveringEnd();
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
          onPointerHover: _listenerPointerHoverEvent,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPressStart: (details) =>
                widget.onLongPress(details.globalPosition),
            onSecondaryTapDown: (details) =>
                widget.onSecondaryTapDown?.call(details.globalPosition),
            onTapDown: (details) =>
                widget.onTapDown?.call(details.globalPosition),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints containerBounds) {
                this.containerBounds = containerBounds;

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
                    return _PagesBuilder(
                      pages: widget.pages,
                      pageBuilder: widget.pageBuilder,
                      placeholderPageBuilder: widget.placeholderPageBuilder,
                      boundingBox: _axisAlignedBoundingBox(viewport),
                      containerWidth: containerBounds.maxWidth,
                      isInfinite: widget.isInfinite,
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
  });

  final List<EditorPage> pages;
  final Widget Function(BuildContext context, int pageIndex) pageBuilder;
  final Widget Function(BuildContext context, int pageIndex)
  placeholderPageBuilder;
  final Rect boundingBox;
  final double containerWidth;
  final bool isInfinite;

  @override
  State<_PagesBuilder> createState() => _PagesBuilderState();
}

class _PagesBuilderState extends State<_PagesBuilder> {

  final List<double> _pageOffsets = [];
  final List<double> _pageHeights = [];
  final List<double> _pageWidths = [];

  double? _cachedContainerWidth;
  int _cachedPagesLength = 0;
  double _totalHeight = 0;

  @override
  void didUpdateWidget(_PagesBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);

    bool pageSizesChanged = false;
    if (widget.pages.length == oldWidget.pages.length) {
      for (int i = 0; i < widget.pages.length; i++) {
        if (widget.pages[i].size != oldWidget.pages[i].size) {
          pageSizesChanged = true;
          break;
        }
      }
    } else {
      pageSizesChanged = true;
    }
    if (widget.containerWidth != _cachedContainerWidth ||
        widget.pages.length != _cachedPagesLength ||
        widget.pages != oldWidget.pages ||
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

      currentTop += pageHeight + (widget.isInfinite ? 0 : Editor.gapBetweenPages);
    }

    if (!widget.isInfinite) {
      currentTop += Editor.gapBetweenPages;
    }
    _totalHeight = currentTop;

    _cachedContainerWidth = widget.containerWidth;
    _cachedPagesLength = widget.pages.length;
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

    final renderZone = widget.boundingBox.inflate(3000);

    final startIndex = _findFirstVisiblePageIndex(renderZone.top);

    for (int i = startIndex; i < widget.pages.length; i++) {
      final offset = _pageOffsets[i];

      if (offset > renderZone.bottom) break;

      final height = _pageHeights[i];
      final width = _pageWidths[i];

      final double leftOffset = (widget.containerWidth - width) / 2;

      widget.pages[i].isRendered = true;

      visibleWidgets.add(
        Positioned(
          top: offset,
          left: leftOffset,
          width: width,
          height: height,

          child: RepaintBoundary(
            child: widget.pageBuilder(context, i),

          ),
        ),
      );
    }

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
