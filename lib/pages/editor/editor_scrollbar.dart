// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

part of 'editor.dart';

class _AdaptiveScrollbar extends StatefulWidget {
  final TransformationController controller;
  final List<EditorPage> pages;
  final double screenHeight;
  final double screenWidth;
  final Axis direction;
  final bool isInfinite;
  final ValueNotifier<int>? scrollPhysicsStopNotifier;

  const _AdaptiveScrollbar({
    required this.controller,
    required this.pages,
    required this.screenHeight,
    required this.screenWidth,
    this.direction = Axis.vertical,
    this.isInfinite = false,
    this.scrollPhysicsStopNotifier,
  });

  @override
  State<_AdaptiveScrollbar> createState() => _AdaptiveScrollbarState();
}

class _AdaptiveScrollbarState extends State<_AdaptiveScrollbar>
    with TickerProviderStateMixin {
  bool _isHovering = false;
  bool _isDragging = false;

  Ticker? _physicsTicker;
  double _inertiaVelocity = 0.0;
  Duration _lastTickTime = Duration.zero;
  VoidCallback? _scrollPhysicsStopListener;

  @override
  void initState() {
    super.initState();
    _scrollPhysicsStopListener = stopPhysics;
    widget.scrollPhysicsStopNotifier?.addListener(_scrollPhysicsStopListener!);
  }

  @override
  void didUpdateWidget(_AdaptiveScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scrollPhysicsStopNotifier !=
        oldWidget.scrollPhysicsStopNotifier) {
      oldWidget.scrollPhysicsStopNotifier
          ?.removeListener(_scrollPhysicsStopListener!);
      widget.scrollPhysicsStopNotifier
          ?.addListener(_scrollPhysicsStopListener!);
    }
  }

  @override
  void dispose() {
    widget.scrollPhysicsStopNotifier?.removeListener(_scrollPhysicsStopListener!);
    _physicsTicker?.dispose();
    super.dispose();
  }

  void stopPhysics() {
    _stopPhysics();
  }

  void _startPhysics() {
    if (_physicsTicker == null) {
      _physicsTicker = createTicker(_onPhysicsTick);
    }
    if (!_physicsTicker!.isTicking) {
      _lastTickTime = Duration.zero;
      _physicsTicker!.start();
    }
  }

  void _stopPhysics() {
    _physicsTicker?.stop();
    _inertiaVelocity = 0.0;
  }

  void _onPhysicsTick(Duration elapsed) {
    if (_lastTickTime == Duration.zero) {
      _lastTickTime = elapsed;
      return;
    }
    final double dt = (elapsed - _lastTickTime).inMicroseconds / 1000000.0;
    _lastTickTime = elapsed;

    if (_inertiaVelocity.abs() > 5.0) {
      final double delta = _inertiaVelocity * dt;
      _inertiaVelocity *= math
          .pow(0.40, dt)
          .toDouble();
      _applyScrollDelta(delta);
    } else {
      _stopPhysics();
    }
  }

  void _applyScrollDelta(double delta) {
    final matrix = widget.controller.value;
    final scale = matrix.getMaxScaleOnAxis();
    final bool isVertical = widget.direction == Axis.vertical;

    final contentSize = _contentSize(scale: scale, isVertical: isVertical);

    final double viewportSize = isVertical
        ? widget.screenHeight
        : widget.screenWidth;
    final double currentTranslate = isVertical
        ? matrix.getTranslation().y
        : matrix.getTranslation().x;

    double thumbSize = (viewportSize / contentSize) * viewportSize;
    thumbSize = math.max(thumbSize, 48.0);
    final double trackSize = viewportSize - thumbSize;
    final double maxScrollExtent = contentSize - viewportSize;

    if (trackSize <= 0) return;

    final double relativeDelta = delta / trackSize;
    final double scrollDelta = relativeDelta * maxScrollExtent;
    final double unclampedTranslate = currentTranslate - scrollDelta;
    final double newTranslate = unclampedTranslate.clamp(
      -maxScrollExtent,
      0.0,
    );

    if (newTranslate != unclampedTranslate) {
      _inertiaVelocity = 0.0;
    }

    final newMatrix = matrix.clone();
    if (isVertical) {
      newMatrix.setTranslationRaw(
        matrix.getTranslation().x,
        newTranslate,
        matrix.getTranslation().z,
      );
    } else {
      newMatrix.setTranslationRaw(
        newTranslate,
        matrix.getTranslation().y,
        matrix.getTranslation().z,
      );
    }
    widget.controller.value = newMatrix;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Matrix4>(
      valueListenable: widget.controller,
      builder: (context, matrix, child) {
        final scale = matrix.getMaxScaleOnAxis();
        final isVertical = widget.direction == Axis.vertical;

        final contentSize = _contentSize(scale: scale, isVertical: isVertical);

        final viewportSize = isVertical
            ? widget.screenHeight
            : widget.screenWidth;

        if (contentSize <= viewportSize) {
          return const SizedBox.shrink();
        }

        final currentTranslate = isVertical
            ? matrix.getTranslation().y
            : matrix.getTranslation().x;

        double thumbSize = (viewportSize / contentSize) * viewportSize;
        thumbSize = math.max(thumbSize, 48.0);

        final double trackSize = viewportSize - thumbSize;
        final double maxScrollExtent = contentSize - viewportSize;

        if (maxScrollExtent <= 0) return const SizedBox.shrink();

        final double progress = (-currentTranslate / maxScrollExtent).clamp(
          0.0,
          1.0,
        );
        final double thumbPosition = progress * trackSize;
        final double currentThickness = (_isHovering || _isDragging)
            ? 16.0
            : 6.0;

        final thumbVisual = AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: isVertical ? currentThickness : thumbSize,
          height: isVertical ? thumbSize : currentThickness,
          decoration: BoxDecoration(
            color: (_isHovering || _isDragging)
                ? Colors.grey.withValues(alpha: 0.8)
                : Colors.grey.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(currentThickness / 2),
          ),
        );

        final hitArea = Container(
          width: isVertical ? 12.0 : thumbSize,
          height: isVertical ? thumbSize : 12.0,
          color: Colors.transparent,
        );

        return Stack(
          children: [
            Positioned(
              right: isVertical ? 2 : null,
              top: isVertical ? thumbPosition : null,
              bottom: isVertical ? null : 2,
              left: isVertical ? null : thumbPosition,
              child: MouseRegion(
                onEnter: (_) => setState(() => _isHovering = true),
                onExit: (_) => setState(() => _isHovering = false),
                hitTestBehavior: HitTestBehavior.translucent,
                child: GestureDetector(
                  onPanStart: (_) {
                    if (widget.scrollPhysicsStopNotifier != null) {
                      widget.scrollPhysicsStopNotifier!.value++;
                    }
                    _stopPhysics();
                    setState(() => _isDragging = true);
                  },
                  onPanEnd: (details) {
                    setState(() => _isDragging = false);

                    final double velocity = isVertical
                        ? details.velocity.pixelsPerSecond.dy
                        : details.velocity.pixelsPerSecond.dx;

                    if (velocity.abs() > 10.0) {
                      _inertiaVelocity = velocity;
                      _startPhysics();
                    }
                  },
                  onPanCancel: () {
                    setState(() => _isDragging = false);
                  },
                  onPanUpdate: (details) {
                    if (trackSize <= 0) return;
                    final double delta = isVertical
                        ? details.delta.dy
                        : details.delta.dx;
                    _applyScrollDelta(delta);
                  },
                  child: isVertical
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [hitArea, thumbVisual],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [hitArea, thumbVisual],
                        ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  double _contentSize({required double scale, required bool isVertical}) {
    if (widget.pages.isEmpty) return 0;

    if (widget.isInfinite) {
      final page = widget.pages.first;
      final fittedWidth = math.min(page.size.width, widget.screenWidth);
      final fittedHeight = page.size.height * (fittedWidth / page.size.width);
      if (isVertical) {
        return fittedHeight * scale;
      }
      return fittedWidth * scale;
    }

    double contentSize = 0;
    if (isVertical) {
      for (final page in widget.pages) {
        contentSize += page.size.height;
      }
      if (widget.pages.isNotEmpty) {
        contentSize += (widget.pages.length - 1) * Editor.gapBetweenPages;
      }
      return contentSize * scale;
    }

    double maxWidth = widget.screenWidth;
    for (final page in widget.pages) {
      if (page.size.width > maxWidth) maxWidth = page.size.width;
    }
    return maxWidth * scale;
  }
}
