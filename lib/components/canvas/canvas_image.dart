// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:async';

import 'package:defer_pointer/defer_pointer.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/canvas/canvas_context_menu_feel.dart';
import 'package:saber/components/canvas/canvas_image_dialog.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
import 'package:saber/components/toolbar/plot_animation_metadata.dart';
import 'package:saber/data/extensions/change_notifier_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/i18n/strings.g.dart';

class CanvasImage extends StatefulWidget {
  CanvasImage({
    required this.filePath,
    required this.image,
    this.overrideBoxFit,
    required this.pageSize,
    required this.setAsBackground,
    this.isBackground = false,
    this.readOnly = false,
    this.selected = false,
    this.previewRect,
    this.previewRotationDeg,
    this.canvasScale = 1.0,
    this.cropPreviewRect,
    this.onCropRectChanged,
  }) : super(key: Key('CanvasImage$filePath/${image.id}'));

  final String filePath;
  final EditorImage image;
  final BoxFit? overrideBoxFit;
  final Size pageSize;
  final void Function(EditorImage image)? setAsBackground;
  final bool isBackground;
  final bool readOnly;
  final bool selected;
  final Rect? previewRect;
  final double? previewRotationDeg;
  final double canvasScale;

  final Rect? cropPreviewRect;
  final void Function(Rect normalizedCrop)? onCropRectChanged;

  static var activeListener = ChangeNotifier();

  static double minInteractiveSize = 50;

  static double minImageSize = 10;

  @override
  State<CanvasImage> createState() => _CanvasImageState();
}

class _CanvasImageState extends State<CanvasImage> {
  var _active = false;

  double _renderScale = 1.0;
  Timer? _debounceScaleTimer;

  bool get active => _active;
  set active(bool value) {
    if (active == value) return;

    if (value) {
      CanvasImage.activeListener
          .notifyListenersPlease();
    }

    _active = value;

    if (mounted) {
      try {
        setState(() {});
      } catch (e) {

      }
    }
  }

  Brightness imageBrightness = .light;

  Rect panStartRect = .zero;
  Offset panStartPosition = .zero;
  double? _rotationPointerStart;
  double? _rotationStartAngle;

  bool get _isAnimationPreviewImage {
    if (widget.isBackground || widget.image is! PngEditorImage) return false;
    final image = widget.image as PngEditorImage;
    final fileInfo = image.assetCacheAll.getAssetFileInfo(image.assetId);
    final metadata = PlotAnimationMetadata.tryDecodeFromAssetInfo(fileInfo);
    return metadata?.hasAnimation == true;
  }

  @override
  void initState() {
    _renderScale = widget.canvasScale;
    widget.image.loadIn();

    if (widget.image.newImage) {

      active = true;
      widget.image.newImage = false;
    }

    widget.image.addListener(imageListener);
    CanvasImage.activeListener.addListener(disableActive);

    super.initState();
  }

  void disableActive() {
    active = false;
  }

  void imageListener() {
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant CanvasImage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if ((widget.canvasScale - oldWidget.canvasScale).abs() > 0.05) {
      _onScaleChanged();
    }

    if (widget.readOnly && active) {
      active = false;
    }
    if (widget.image != oldWidget.image) {
      oldWidget.image.removeListener(imageListener);
      widget.image.addListener(imageListener);
    }
    super.didUpdateWidget(oldWidget);
  }

  void _onScaleChanged() {

    _debounceScaleTimer?.cancel();

    _debounceScaleTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {

          _renderScale = widget.canvasScale.clamp(0.5, 4.0);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    final isSelectedBySelectTool =
        Select.currentSelect.doneSelecting &&
        Select.currentSelect.selectResult.images.contains(widget.image);

    final currentBrightness = widget.image.invertible
        ? Theme.brightnessOf(context)
        : Brightness.light;

    final shouldInvertInDarkMode =
        getEffectiveNoteInvertInDarkModeForFile(widget.filePath);

    if (shouldInvertInDarkMode) {
      if (currentBrightness != imageBrightness) {
        imageBrightness = currentBrightness;
      }
    } else if (imageBrightness != Brightness.light) {
      imageBrightness = Brightness.light;
    }

    final isCropMode = widget.cropPreviewRect != null && widget.onCropRectChanged != null;
    final effectiveRect = widget.previewRect ?? widget.image.dstRect;
    final effectiveRotationDeg =
        widget.previewRotationDeg ?? widget.image.rotationDeg;
    final effectiveSrcRect = isCropMode
        ? Rect.fromLTWH(
            widget.cropPreviewRect!.left * widget.image.naturalSize.width,
            widget.cropPreviewRect!.top * widget.image.naturalSize.height,
            widget.cropPreviewRect!.width * widget.image.naturalSize.width,
            widget.cropPreviewRect!.height * widget.image.naturalSize.height,
          )
        : widget.image.srcRect;

    final boxW = widget.isBackground
        ? widget.pageSize.width
        : math.max(
            effectiveRect.width,
            CanvasImage.minImageSize,
          );
    final boxH = widget.isBackground
        ? widget.pageSize.height
        : math.max(
            effectiveRect.height,
            CanvasImage.minImageSize,
          );

    final Widget unpositioned = IgnorePointer(
      ignoring: isCropMode
          ? false
          : (widget.readOnly ||
              isSelectedBySelectTool ||
              (!widget.isBackground && !widget.readOnly)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          MouseRegion(
            cursor: (active || widget.selected) && !isCropMode
                ? SystemMouseCursors.grab
                : MouseCursor.defer,
            child: RawGestureDetector(
              behavior: HitTestBehavior.translucent,
              gestures:
                  (widget.isBackground &&
                      (active || widget.selected) &&
                      !isCropMode)
                  ? <Type, GestureRecognizerFactory>{
                      LongPressGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                            LongPressGestureRecognizer
                          >(
                            () => LongPressGestureRecognizer(
                              duration: CanvasContextMenuFeel.longPressDuration,
                            ),
                            (LongPressGestureRecognizer instance) {
                              instance.onLongPress = showModal;
                            },
                          ),
                    }
                  : const <Type, GestureRecognizerFactory>{},
              child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.isBackground && !isCropMode
                  ? () {
                      active = !active;
                    }
                  : null,
              onSecondaryTap:
                  (widget.isBackground && (active || widget.selected) && !isCropMode)
                  ? showModal
                  : null,
              onPanStart: (widget.isBackground && (active || widget.selected) && !isCropMode)
                  ? (details) {
                      panStartRect = widget.image.dstRect;
                    }
                  : null,
              onPanUpdate: (widget.isBackground && (active || widget.selected) && !isCropMode)
                  ? (details) {
                      setState(() {
                        final fivePercent = math.min(
                          widget.pageSize.width * 0.05,
                          widget.pageSize.height * 0.05,
                        );
                        widget.image.dstRect = .fromLTWH(
                          (widget.image.dstRect.left + details.delta.dx)
                              .clamp(
                                fivePercent - widget.image.dstRect.width,
                                widget.pageSize.width - fivePercent,
                              )
                              .toDouble(),
                          (widget.image.dstRect.top + details.delta.dy)
                              .clamp(
                                fivePercent - widget.image.dstRect.height,
                                widget.pageSize.height - fivePercent,
                              )
                              .toDouble(),
                          widget.image.dstRect.width,
                          widget.image.dstRect.height,
                        );
                      });
                    }
                  : null,
              onPanEnd: (widget.isBackground && (active || widget.selected) && !isCropMode)
                  ? (details) {
                      if (panStartRect == widget.image.dstRect) return;
                      widget.image.onMoveImage?.call(
                        widget.image,
                        .fromLTRB(
                          widget.image.dstRect.left - panStartRect.left,
                          widget.image.dstRect.top - panStartRect.top,
                          widget.image.dstRect.right - panStartRect.right,
                          widget.image.dstRect.bottom - panStartRect.bottom,
                        ),
                      );
                      panStartRect = .zero;
                    }
                  : null,
              child: Transform.rotate(
                angle: effectiveRotationDeg * math.pi / 180.0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color:
                          (widget.isBackground && (active || widget.selected) && !isCropMode)
                          ? colorScheme.onSurface
                          : isCropMode
                              ? colorScheme.primary
                              : Colors.transparent,
                      width: isCropMode ? 2.5 : 2,
                    ),
                  ),
                  child: Center(
                    child: ClipRect(
                      child: SizedBox(
                        width: boxW,
                        height: boxH,
                        child: Stack(
                          fit: StackFit.expand,
                          clipBehavior: Clip.hardEdge,
                          children: [
                          SizedOverflowBox(
                            size: effectiveSrcRect.size,
                            child: Transform.translate(
                              offset: -effectiveSrcRect.topLeft,
                              child: widget.image.buildImageWidget(
                                context: context,
                                overrideBoxFit: widget.overrideBoxFit,
                                isBackground: widget.isBackground,
                                invert: imageBrightness == .dark,
                                renderScale: _renderScale,
                              ),
                            ),
                          ),
                          if (isCropMode && widget.cropPreviewRect != null && widget.onCropRectChanged != null)
                            _CropHandlesOverlay(
                              normalizedCrop: widget.cropPreviewRect!,
                              boxWidth: boxW,
                              boxHeight: boxH,
                              onCropRectChanged: widget.onCropRectChanged!,
                              colorScheme: colorScheme,
                            ),
                          if (_isAnimationPreviewImage)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.transparent,
                                      width: 0,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (_isAnimationPreviewImage)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: IgnorePointer(
                                child: ClipOval(
                                  clipBehavior: Clip.antiAlias,
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: colorScheme.primary,
                                      boxShadow: [
                                        BoxShadow(
                                          color: colorScheme.primary.withValues(
                                            alpha: 0.35,
                                          ),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      Icons.play_arrow_rounded,
                                      size: 18,
                                      color: colorScheme.onPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ),
          ),
        ),
          if (widget.isBackground &&
              !widget.readOnly &&
              (active || widget.selected) &&
              !Select.currentSelect.doneSelecting &&
              !isCropMode)
            Center(
              child: Transform.rotate(
                angle: effectiveRotationDeg * math.pi / 180,
                child: SizedBox(
                  width: effectiveRect.width,
                  height: effectiveRect.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _SelectionFramePainter(
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                      Positioned(
                        top: -30,
                        left: effectiveRect.width / 2 - 9,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (details) {
                            final center = Offset(
                              effectiveRect.width / 2,
                              effectiveRect.height / 2,
                            );
                            _rotationPointerStart = math.atan2(
                              details.localPosition.dy + 30 - center.dy,
                              details.localPosition.dx - center.dx,
                            );
                            _rotationStartAngle = widget.image.rotationDeg;
                          },
                          onPanUpdate: (details) {
                            final center = Offset(
                              effectiveRect.width / 2,
                              effectiveRect.height / 2,
                            );
                            final current = math.atan2(
                              details.localPosition.dy + 30 - center.dy,
                              details.localPosition.dx - center.dx,
                            );
                            if (_rotationPointerStart != null &&
                                _rotationStartAngle != null) {
                              final delta = current - _rotationPointerStart!;
                              setState(() {
                                widget.image.rotationDeg =
                                    (_rotationStartAngle! +
                                        delta * 180 / math.pi) %
                                    360;
                              });
                            }
                          },
                          child: _RotationHandle(color: colorScheme.primary),
                        ),
                      ),
                      for (final offset in const [
                        Offset(-1, -1),
                        Offset(1, -1),
                        Offset(1, 1),
                        Offset(-1, 1),
                      ])
                        _CanvasImageResizeHandle(
                          active: active || widget.selected,
                          position: offset * 20,
                          image: widget.image,
                          parent: this,
                          afterDrag: () => setState(() {}),
                          minimal: true,
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (widget.isBackground) {
      return AnimatedPositioned(
        duration: const Duration(milliseconds: 300),
        curve: Curves.fastLinearToSlowEaseIn,
        left: 0,
        top: 0,
        right: 0,
        bottom: 0,
        child: unpositioned,
      );
    }
    // Keep a minimum hit target, but pad equally around [dstRect] so the
    // painted image stays inside the selection box when the image is small.
    final hitW = math.max(effectiveRect.width, CanvasImage.minInteractiveSize);
    final hitH = math.max(effectiveRect.height, CanvasImage.minInteractiveSize);
    final padX = (hitW - effectiveRect.width) / 2;
    final padY = (hitH - effectiveRect.height) / 2;
    return AnimatedPositioned(
      duration: (panStartRect != .zero || widget.selected)
          ? Duration.zero
          : const Duration(milliseconds: 300),
      curve: Curves.fastLinearToSlowEaseIn,
      left: effectiveRect.left - padX,
      top: effectiveRect.top - padY,
      width: hitW,
      height: hitH,
      child: unpositioned,
    );
  }

  @override
  void dispose() {
    _debounceScaleTimer?.cancel();
    widget.image.loadOut();
    widget.image.removeListener(imageListener);
    CanvasImage.activeListener.removeListener(disableActive);
    super.dispose();
  }

  void showModal() {
    final isToolbarBottom =
        stows.editorToolbarAlignment.value == AxisDirection.down;

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.transparent,
      transitionDuration: CanvasContextMenuFeel.openDuration,
      pageBuilder: (context, animation, secondaryAnimation) {
        final dialog = AdaptiveAlertDialog(
          title: Text(t.editor.imageOptions.title),
          content: CanvasImageDialog(
            filePath: widget.filePath,
            image: widget.image,
            redrawImage: () => setState(() {}),
            isBackground: false,
            toggleAsBackground: () {
              widget.setAsBackground?.call(widget.image);
            },
          ),
          actions: const [],
        );

        if (isToolbarBottom) {
          final mediaQuery = MediaQuery.of(context);
          final safeAreaBottom = mediaQuery.padding.bottom;

          const estimatedToolbarHeight = 100.0;
          final bottomPadding = safeAreaBottom + estimatedToolbarHeight + 20;

          return Dialog(
            insetPadding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: bottomPadding,
            ),
            child: dialog,
          );
        }

        return dialog;
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return CanvasContextMenuFeel.buildOpenTransition(
          animation: animation,
          child: child,
        );
      },
    );
  }
}

class _CanvasImageResizeHandle extends StatelessWidget {
  const _CanvasImageResizeHandle({
    required this.active,
    required this.position,
    required this.image,
    required this.parent,
    required this.afterDrag,
    this.minimal = false,
  });

  final bool active;
  final Offset position;
  final EditorImage image;
  final _CanvasImageState parent;
  final void Function() afterDrag;
  final bool minimal;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Positioned(
      left: (position.dx.sign + 1) / 2 * image.dstRect.width - 20,
      top: (position.dy.sign + 1) / 2 * image.dstRect.height - 20,
      child: DeferPointer(
        paintOnTop: true,
        child: MouseRegion(
          cursor: () {
            if (!active) return MouseCursor.defer;

            if (position.dx == 0 && position.dy < 0)
              return SystemMouseCursors.resizeUp;
            if (position.dx == 0 && position.dy > 0)
              return SystemMouseCursors.resizeDown;
            if (position.dx < 0 && position.dy == 0)
              return SystemMouseCursors.resizeLeft;
            if (position.dx > 0 && position.dy == 0)
              return SystemMouseCursors.resizeRight;

            if (position.dx < 0 && position.dy < 0)
              return SystemMouseCursors.resizeUpLeft;
            if (position.dx < 0 && position.dy > 0)
              return SystemMouseCursors.resizeDownLeft;
            if (position.dx > 0 && position.dy < 0)
              return SystemMouseCursors.resizeUpRight;
            if (position.dx > 0 && position.dy > 0)
              return SystemMouseCursors.resizeDownRight;

            return MouseCursor.defer;
          }(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: active
                ? (details) {
                    parent.panStartRect = parent.widget.image.dstRect;
                    parent.panStartPosition = details.localPosition;
                  }
                : null,
            onPanUpdate: active
                ? (details) {
                    final Offset delta =
                        details.localPosition - parent.panStartPosition;

                    double newWidth;
                    if (position.dx < 0) {
                      newWidth = parent.panStartRect.width - delta.dx;
                    } else if (position.dx > 0) {
                      newWidth = parent.panStartRect.width + delta.dx;
                    } else {
                      newWidth = parent.panStartRect.width;
                    }

                    double newHeight;
                    if (position.dy < 0) {
                      newHeight = parent.panStartRect.height - delta.dy;
                    } else if (position.dy > 0) {
                      newHeight = parent.panStartRect.height + delta.dy;
                    } else {
                      newHeight = parent.panStartRect.height;
                    }

                    if (newWidth <= 0 || newHeight <= 0) return;

                    if (position.dx != 0 && position.dy != 0) {

                      final aspectRatio =
                          image.dstRect.width / image.dstRect.height;
                      if (newWidth / newHeight > aspectRatio) {
                        newHeight = newWidth / aspectRatio;
                      } else {
                        newWidth = newHeight * aspectRatio;
                      }
                    }

                    double left = image.dstRect.left, top = image.dstRect.top;
                    if (position.dx < 0) {
                      left = image.dstRect.right - newWidth;
                    }
                    if (position.dy < 0) {
                      top = image.dstRect.bottom - newHeight;
                    }

                    image.dstRect = .fromLTWH(left, top, newWidth, newHeight);
                    afterDrag();
                  }
                : null,
            onPanEnd: active
                ? (details) {
                    if (parent.panStartRect == image.dstRect) return;
                    image.onMoveImage?.call(
                      image,
                      .fromLTRB(
                        image.dstRect.left - parent.panStartRect.left,
                        image.dstRect.top - parent.panStartRect.top,
                        image.dstRect.right - parent.panStartRect.right,
                        image.dstRect.bottom - parent.panStartRect.bottom,
                      ),
                    );
                    parent.panStartRect = .zero;
                  }
                : null,
            child: AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: const Duration(milliseconds: 100),
              child: ClipOval(
                clipBehavior: Clip.antiAlias,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface,
                    border: Border.all(color: colorScheme.surface, width: 2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionFramePainter extends CustomPainter {
  const _SelectionFramePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_SelectionFramePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _RotationHandle extends StatelessWidget {
  const _RotationHandle({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: Colors.white, width: 2),
        ),
      ),
    );
  }
}

const double _cropMinSpan = 0.05;
const double _cropHandleSize = 28.0;

class _CropHandlesOverlay extends StatefulWidget {
  const _CropHandlesOverlay({
    required this.normalizedCrop,
    required this.boxWidth,
    required this.boxHeight,
    required this.onCropRectChanged,
    required this.colorScheme,
  });

  final Rect normalizedCrop;
  final double boxWidth;
  final double boxHeight;
  final void Function(Rect) onCropRectChanged;
  final ColorScheme colorScheme;

  @override
  State<_CropHandlesOverlay> createState() => _CropHandlesOverlayState();
}

class _CropHandlesOverlayState extends State<_CropHandlesOverlay> {
  Rect? _dragStartRect;
  Offset? _dragStartLocal;
  String? _draggingHandle;

  void _onPanStart(String handle, Offset local) {
    setState(() {
      _draggingHandle = handle;
      _dragStartRect = widget.normalizedCrop;
      _dragStartLocal = local;
    });
  }

  void _onPanUpdate(Offset local) {
    if (_dragStartRect == null || _dragStartLocal == null || _draggingHandle == null) return;
    final dx = (local.dx - _dragStartLocal!.dx) / widget.boxWidth;
    final dy = (local.dy - _dragStartLocal!.dy) / widget.boxHeight;
    double left = _dragStartRect!.left;
    double top = _dragStartRect!.top;
    double right = _dragStartRect!.right;
    double bottom = _dragStartRect!.bottom;

    switch (_draggingHandle!) {
      case 'left':
        left = (left + dx).clamp(0.0, right - _cropMinSpan);
        break;
      case 'right':
        right = (right + dx).clamp(left + _cropMinSpan, 1.0);
        break;
      case 'top':
        top = (top + dy).clamp(0.0, bottom - _cropMinSpan);
        break;
      case 'bottom':
        bottom = (bottom + dy).clamp(top + _cropMinSpan, 1.0);
        break;
      case 'topLeft':
        left = (left + dx).clamp(0.0, right - _cropMinSpan);
        top = (top + dy).clamp(0.0, bottom - _cropMinSpan);
        break;
      case 'topRight':
        right = (right + dx).clamp(left + _cropMinSpan, 1.0);
        top = (top + dy).clamp(0.0, bottom - _cropMinSpan);
        break;
      case 'bottomRight':
        right = (right + dx).clamp(left + _cropMinSpan, 1.0);
        bottom = (bottom + dy).clamp(top + _cropMinSpan, 1.0);
        break;
      case 'bottomLeft':
        left = (left + dx).clamp(0.0, right - _cropMinSpan);
        bottom = (bottom + dy).clamp(top + _cropMinSpan, 1.0);
        break;
    }
    widget.onCropRectChanged(Rect.fromLTRB(left, top, right, bottom));
  }

  void _onPanEnd() {
    setState(() {
      _draggingHandle = null;
      _dragStartRect = null;
      _dragStartLocal = null;
    });
  }

  Widget _buildHandle(String handle, double x, double y, [MouseCursor cursor = SystemMouseCursors.resizeUpLeft]) {
    final half = _cropHandleSize / 2;
    return Positioned(
      left: x - half,
      top: y - half,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _onPanStart(handle, d.localPosition),
          onPanUpdate: (d) => _onPanUpdate(d.localPosition),
          onPanEnd: (_) => _onPanEnd(),
          child: ClipOval(
            clipBehavior: Clip.antiAlias,
            child: Container(
              width: _cropHandleSize,
              height: _cropHandleSize,
              decoration: BoxDecoration(
                color: widget.colorScheme.surface,
                border: Border.all(color: widget.colorScheme.primary, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.normalizedCrop;
    final w = widget.boxWidth;
    final h = widget.boxHeight;
    final left = r.left * w;
    final top = r.top * h;
    final right = r.right * w;
    final bottom = r.bottom * h;
    final cx = (left + right) / 2;
    final cy = (top + bottom) / 2;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        _buildHandle('left', left, cy, SystemMouseCursors.resizeLeft),
        _buildHandle('right', right, cy, SystemMouseCursors.resizeRight),
        _buildHandle('top', cx, top, SystemMouseCursors.resizeUp),
        _buildHandle('bottom', cx, bottom, SystemMouseCursors.resizeDown),
        _buildHandle('topLeft', left, top, SystemMouseCursors.resizeUpLeft),
        _buildHandle('topRight', right, top, SystemMouseCursors.resizeUpRight),
        _buildHandle('bottomRight', right, bottom, SystemMouseCursors.resizeDownRight),
        _buildHandle('bottomLeft', left, bottom, SystemMouseCursors.resizeDownLeft),
      ],
    );
  }
}
