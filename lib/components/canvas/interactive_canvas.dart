// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

// ignore_for_file: omit_obvious_property_types

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:saber/components/canvas/page_raster_cache.dart'
    show PageRasterCacheManager;
import 'package:saber/data/prefs.dart';
import 'package:saber/services/display_ink_feel.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, Quad, Vector3;

typedef InteractiveCanvasViewerWidgetBuilder =
    Widget Function(BuildContext context, Quad viewport);

@immutable
class InteractiveCanvasViewer extends StatefulWidget {
  static bool isAutoPanningEnabled = false;

  InteractiveCanvasViewer({
    super.key,
    this.clipBehavior = Clip.hardEdge,
    this.panAxis = PanAxis.free,
    this.boundaryMargin = .zero,
    this.constrained = true,

    this.maxScale = 2.5,
    this.minScale = 0.8,
    this.isDrawGesture,
    this.interactionEndFrictionCoefficient = kDrag,
    this.onInteractionStart,
    this.onInteractionEnd,
    this.onDrawEnd,
    this.onDrawStart,
    this.onDrawUpdate,
    this.panEnabled = true,
    this.scaleEnabled = true,
    this.scaleFactor = kDefaultMouseScrollToScaleFactor,
    this.transformationController,
    this.alignment,
    this.trackpadScrollCausesScale = false,
    this.shouldIgnorePanZoom,
    this.scrollPhysicsStopNotifier,
    required Widget this.child,
  }) : assert(minScale > 0),
       assert(interactionEndFrictionCoefficient > 0),
       assert(minScale.isFinite),
       assert(maxScale > 0),
       assert(!maxScale.isNaN),
       assert(maxScale >= minScale),

       assert(
         (boundaryMargin.horizontal.isInfinite &&
                 boundaryMargin.vertical.isInfinite) ||
             (boundaryMargin.top.isFinite &&
                 boundaryMargin.right.isFinite &&
                 boundaryMargin.bottom.isFinite &&
                 boundaryMargin.left.isFinite),
       ),
       builder = null;

  InteractiveCanvasViewer.builder({
    super.key,
    this.clipBehavior = Clip.hardEdge,
    this.panAxis = PanAxis.free,
    this.boundaryMargin = .zero,

    this.maxScale = 2.5,
    this.minScale = 0.8,
    this.isDrawGesture,
    this.interactionEndFrictionCoefficient = kDrag,
    this.onInteractionStart,
    this.onInteractionEnd,
    this.onDrawEnd,
    this.onDrawStart,
    this.onDrawUpdate,
    this.panEnabled = true,
    this.scaleEnabled = true,
    this.scaleFactor = 200.0,
    this.transformationController,
    this.alignment,
    this.trackpadScrollCausesScale = false,
    this.shouldIgnorePanZoom,
    this.scrollPhysicsStopNotifier,
    required InteractiveCanvasViewerWidgetBuilder this.builder,
  }) : assert(minScale > 0),
       assert(interactionEndFrictionCoefficient > 0),
       assert(minScale.isFinite),
       assert(maxScale > 0),
       assert(!maxScale.isNaN),
       assert(maxScale >= minScale),

       assert(
         (boundaryMargin.horizontal.isInfinite &&
                 boundaryMargin.vertical.isInfinite) ||
             (boundaryMargin.top.isFinite &&
                 boundaryMargin.right.isFinite &&
                 boundaryMargin.bottom.isFinite &&
                 boundaryMargin.left.isFinite),
       ),
       constrained = false,
       child = null;

  final Alignment? alignment;

  final Clip clipBehavior;

  final PanAxis panAxis;

  final EdgeInsets boundaryMargin;

  final InteractiveCanvasViewerWidgetBuilder? builder;

  final Widget? child;

  final bool constrained;

  final bool panEnabled;

  final bool scaleEnabled;

  final bool trackpadScrollCausesScale;

  final double scaleFactor;

  final double maxScale;

  final double minScale;

  final double interactionEndFrictionCoefficient;

  final GestureScaleEndCallback? onDrawEnd;

  final GestureScaleStartCallback? onDrawStart;

  final GestureScaleUpdateCallback? onDrawUpdate;

  final bool Function(ScaleStartDetails scaleDetails)? isDrawGesture;

  final bool Function(ScaleStartDetails scaleDetails)? shouldIgnorePanZoom;

  final ValueNotifier<int>? scrollPhysicsStopNotifier;

  final GestureScaleStartCallback? onInteractionStart;

  final GestureScaleEndCallback? onInteractionEnd;

  final TransformationController? transformationController;

  static const double kDrag = 0.0000135;

  @visibleForTesting
  static Vector3 getNearestPointOnLine(Vector3 point, Vector3 l1, Vector3 l2) {
    final double lengthSquared =
        math.pow(l2.x - l1.x, 2.0).toDouble() +
        math.pow(l2.y - l1.y, 2.0).toDouble();

    if (lengthSquared == 0) {
      return l1;
    }

    final Vector3 l1P = point - l1;
    final Vector3 l1L2 = l2 - l1;
    final double fraction = clampDouble(l1P.dot(l1L2) / lengthSquared, 0, 1);
    return l1 + l1L2 * fraction;
  }

  @visibleForTesting
  static Quad getAxisAlignedBoundingBox(Quad quad) {
    final double minX = math.min(
      quad.point0.x,
      math.min(quad.point1.x, math.min(quad.point2.x, quad.point3.x)),
    );
    final double minY = math.min(
      quad.point0.y,
      math.min(quad.point1.y, math.min(quad.point2.y, quad.point3.y)),
    );
    final double maxX = math.max(
      quad.point0.x,
      math.max(quad.point1.x, math.max(quad.point2.x, quad.point3.x)),
    );
    final double maxY = math.max(
      quad.point0.y,
      math.max(quad.point1.y, math.max(quad.point2.y, quad.point3.y)),
    );
    return Quad.points(
      Vector3(minX, minY, 0),
      Vector3(maxX, minY, 0),
      Vector3(maxX, maxY, 0),
      Vector3(minX, maxY, 0),
    );
  }

  @visibleForTesting
  static bool pointIsInside(Vector3 point, Quad quad) {
    final Vector3 aM = point - quad.point0;
    final Vector3 aB = quad.point1 - quad.point0;
    final Vector3 aD = quad.point3 - quad.point0;

    final double aMAB = aM.dot(aB);
    final double aBAB = aB.dot(aB);
    final double aMAD = aM.dot(aD);
    final double aDAD = aD.dot(aD);

    return 0 <= aMAB && aMAB <= aBAB && 0 <= aMAD && aMAD <= aDAD;
  }

  @visibleForTesting
  static Vector3 getNearestPointInside(Vector3 point, Quad quad) {
    if (pointIsInside(point, quad)) {
      return point;
    }

    final List<Vector3> closestPoints = <Vector3>[
      InteractiveCanvasViewer.getNearestPointOnLine(
        point,
        quad.point0,
        quad.point1,
      ),
      InteractiveCanvasViewer.getNearestPointOnLine(
        point,
        quad.point1,
        quad.point2,
      ),
      InteractiveCanvasViewer.getNearestPointOnLine(
        point,
        quad.point2,
        quad.point3,
      ),
      InteractiveCanvasViewer.getNearestPointOnLine(
        point,
        quad.point3,
        quad.point0,
      ),
    ];
    double minDistance = double.infinity;
    late Vector3 closestOverall;
    for (final Vector3 closePoint in closestPoints) {
      final double distance = math.sqrt(
        math.pow(point.x - closePoint.x, 2) +
            math.pow(point.y - closePoint.y, 2),
      );
      if (distance < minDistance) {
        minDistance = distance;
        closestOverall = closePoint;
      }
    }
    return closestOverall;
  }

  @override
  State<InteractiveCanvasViewer> createState() =>
      _InteractiveCanvasViewerState();
}

class _InteractiveCanvasViewerState extends State<InteractiveCanvasViewer>
    with TickerProviderStateMixin {
  late TransformationController _transformer =
      widget.transformationController ?? TransformationController();

  Offset _toScene(Matrix4 matrix, Offset point) {
    final Matrix4 inverse = matrix.clone()..invert();
    return PointerEvent.transformPosition(inverse, point);
  }

  final GlobalKey _childKey = GlobalKey();
  final GlobalKey _parentKey = GlobalKey();
  Animation<Offset>? _animation;
  Animation<double>? _scaleAnimation;
  late Offset _scaleAnimationFocalPoint;
  late AnimationController _controller;
  late AnimationController _scaleController;
  Axis? _currentAxis;
  Offset? _referenceFocalPoint;
  double? _scaleStart;
  double? _rotationStart = 0;
  double _currentRotation = 0;
  _GestureType? _gestureType;
  Timer? _wheelZoomSettleTimer;

  void _markWheelZoomActive() {
    PageRasterCacheManager.updateViewportMoving(true);
    _wheelZoomSettleTimer?.cancel();
    _wheelZoomSettleTimer = Timer(PageRasterCacheManager.viewportSettleDelay, () {
      _wheelZoomSettleTimer = null;
      PageRasterCacheManager.updateViewportMoving(false);
    });
  }

  final bool _rotateEnabled = false;

  Rect get _boundaryRect {
    assert(_childKey.currentContext != null);
    assert(!widget.boundaryMargin.left.isNaN);
    assert(!widget.boundaryMargin.right.isNaN);
    assert(!widget.boundaryMargin.top.isNaN);
    assert(!widget.boundaryMargin.bottom.isNaN);

    final RenderBox childRenderBox =
        _childKey.currentContext!.findRenderObject()! as RenderBox;
    final Size childSize = childRenderBox.size;
    final Rect boundaryRect = widget.boundaryMargin.inflateRect(
      Offset.zero & childSize,
    );
    assert(
      !boundaryRect.isEmpty,
      "InteractiveCanvasViewer's child must have nonzero dimensions.",
    );

    assert(
      boundaryRect.isFinite ||
          (boundaryRect.left.isInfinite &&
              boundaryRect.top.isInfinite &&
              boundaryRect.right.isInfinite &&
              boundaryRect.bottom.isInfinite),
      'boundaryRect must either be infinite in all directions or finite in all directions.',
    );
    return boundaryRect;
  }

  Rect get _viewport {
    assert(_parentKey.currentContext != null);
    final RenderBox parentRenderBox =
        _parentKey.currentContext!.findRenderObject()! as RenderBox;
    return Offset.zero & parentRenderBox.size;
  }

  Matrix4 _matrixTranslate(Matrix4 matrix, Offset translation) {
    if (translation == .zero) {
      return matrix.clone();
    }

    final Offset alignedTranslation;

    if (_currentAxis != null) {
      alignedTranslation = switch (widget.panAxis) {
        PanAxis.horizontal => _alignAxis(translation, Axis.horizontal),
        PanAxis.vertical => _alignAxis(translation, Axis.vertical),
        PanAxis.aligned => _alignAxis(translation, _currentAxis!),
        PanAxis.free => translation,
      };
    } else {
      alignedTranslation = translation;
    }

    final Matrix4 nextMatrix = matrix.clone()
      ..translateByDouble(alignedTranslation.dx, alignedTranslation.dy, 0, 1);

    final Quad nextViewport = _transformViewport(nextMatrix, _viewport);

    if (_boundaryRect.isInfinite) {
      return nextMatrix;
    }

    final Quad boundariesAabbQuad = _getAxisAlignedBoundingBoxWithRotation(
      _boundaryRect,
      _currentRotation,
    );

    final Offset offendingDistance = _exceedsBy(
      boundariesAabbQuad,
      nextViewport,
    );
    if (offendingDistance == .zero) {
      return nextMatrix;
    }

    final Offset nextTotalTranslation = _getMatrixTranslation(nextMatrix);
    final double currentScale = matrix.getMaxScaleOnAxis();
    final Offset correctedTotalTranslation = Offset(
      nextTotalTranslation.dx - offendingDistance.dx * currentScale,
      nextTotalTranslation.dy - offendingDistance.dy * currentScale,
    );

    final Matrix4 correctedMatrix = matrix.clone()
      ..setTranslation(
        Vector3(correctedTotalTranslation.dx, correctedTotalTranslation.dy, 0),
      );

    final Quad correctedViewport = _transformViewport(
      correctedMatrix,
      _viewport,
    );
    final Offset offendingCorrectedDistance = _exceedsBy(
      boundariesAabbQuad,
      correctedViewport,
    );
    if (offendingCorrectedDistance == .zero) {
      return correctedMatrix;
    }

    if (offendingCorrectedDistance.dx != 0.0 &&
        offendingCorrectedDistance.dy != 0.0) {
      return matrix.clone();
    }

    final Offset unidirectionalCorrectedTotalTranslation = Offset(
      offendingCorrectedDistance.dx == 0.0 ? correctedTotalTranslation.dx : 0.0,
      offendingCorrectedDistance.dy == 0.0 ? correctedTotalTranslation.dy : 0.0,
    );
    return matrix.clone()..setTranslation(
      Vector3(
        unidirectionalCorrectedTotalTranslation.dx,
        unidirectionalCorrectedTotalTranslation.dy,
        0,
      ),
    );
  }

  Matrix4 _matrixScale(Matrix4 matrix, double scale) {
    if (scale == 1.0) {
      return matrix.clone();
    }
    assert(scale != 0.0);

    final double currentScale = _transformer.value.getMaxScaleOnAxis();
    final double totalScale = math.max(
      currentScale * scale,

      math.max(
        _viewport.width / _boundaryRect.width,
        _viewport.height / _boundaryRect.height,
      ),
    );
    final double clampedTotalScale = clampDouble(
      totalScale,
      widget.minScale,
      widget.maxScale,
    );
    final double clampedScale = clampedTotalScale / currentScale;
    return matrix.clone()
      ..scaleByDouble(clampedScale, clampedScale, clampedScale, 1);
  }

  Matrix4 _matrixRotate(Matrix4 matrix, double rotation, Offset focalPoint) {
    if (rotation == 0) {
      return matrix.clone();
    }
    final Offset focalPointScene = _transformer.toScene(focalPoint);
    return matrix.clone()
      ..translateByDouble(focalPointScene.dx, focalPointScene.dy, 0, 1)
      ..rotateZ(-rotation)
      ..translateByDouble(-focalPointScene.dx, -focalPointScene.dy, 0, 1);
  }

  bool _gestureIsSupported(_GestureType? gestureType) {
    return switch (gestureType) {
      _GestureType.rotate => _rotateEnabled,
      _GestureType.scale => widget.scaleEnabled,
      _GestureType.pan || null => widget.panEnabled,
    };
  }

  _GestureType _getGestureType(ScaleUpdateDetails details) {
    final double scale = !widget.scaleEnabled ? 1.0 : details.scale;
    final double rotation = !_rotateEnabled ? 0.0 : details.rotation;
    if ((scale - 1).abs() > rotation.abs()) {
      return _GestureType.scale;
    } else if (rotation != 0.0) {
      return _GestureType.rotate;
    } else {
      return _GestureType.pan;
    }
  }

  bool isCurrentGestureADrawGesture = false;
  bool _ignoreThisPanZoomGesture = false;
  Offset _panVelocityScene = Offset.zero;
  Offset _appliedPanLead = Offset.zero;
  Duration? _lastPanStamp;
  var _viewportGestureActive = false;

  void _onScaleStart(ScaleStartDetails details) {
    _ignoreThisPanZoomGesture =
        widget.shouldIgnorePanZoom?.call(details) ?? false;
    _stopPhysics();
    _panVelocityScene = Offset.zero;
    _appliedPanLead = Offset.zero;
    _lastPanStamp = null;
    if (_controller.isAnimating) {
      _controller.stop();
      _controller.reset();
      _animation?.removeListener(_handleInertiaAnimation);
      _animation = null;
    }
    if (_scaleController.isAnimating) {
      _scaleController.stop();
      _scaleController.reset();
      _scaleAnimation?.removeListener(_handleScaleAnimation);
      _scaleAnimation = null;
    }

    _gestureType = null;
    _currentAxis = null;
    _scaleStart = _transformer.value.getMaxScaleOnAxis();
    _referenceFocalPoint = _transformer.toScene(details.localFocalPoint);
    _rotationStart = _currentRotation;

    if (widget.isDrawGesture?.call(details) ?? false) {
      isCurrentGestureADrawGesture = true;
      widget.onDrawStart?.call(details);
    } else if (!_ignoreThisPanZoomGesture) {
      _viewportGestureActive = true;
      PageRasterCacheManager.updateViewportMoving(true);
      widget.onInteractionStart?.call(details);
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_ignoreThisPanZoomGesture && !isCurrentGestureADrawGesture) return;
    _scaleAnimationFocalPoint = details.localFocalPoint;
    final Offset focalPointScene = _transformer.toScene(
      details.localFocalPoint,
    );

    if (_gestureType == _GestureType.pan) {
      _gestureType = _getGestureType(details);
    } else {
      _gestureType ??= _getGestureType(details);
    }
    if (!_gestureIsSupported(_gestureType) && !isCurrentGestureADrawGesture) {
      return;
    }

    switch (_gestureType!) {
      case _GestureType.scale:
        assert(_scaleStart != null);

        final Matrix4 nextMatrix = _transformer.value.clone();
        final double currentScale = nextMatrix.getMaxScaleOnAxis();

        final feel = DisplayInkFeel.instance;
        final double reportedScale = details.scale;
        final double gainedScale = feel.isLowRefresh
            ? 1.0 + (reportedScale - 1.0) * feel.zoomDeltaGain
            : reportedScale;
        final double desiredScale = _scaleStart! * gainedScale;
        final double scaleChange = desiredScale / currentScale;

        if (scaleChange != 1.0) {
          final double totalScale = math.max(
            currentScale * scaleChange,
            math.max(
              _viewport.width / _boundaryRect.width,
              _viewport.height / _boundaryRect.height,
            ),
          );
          final double clampedTotalScale = clampDouble(
            totalScale,
            widget.minScale,
            widget.maxScale,
          );
          final double clampedScaleChange = clampedTotalScale / currentScale;
          nextMatrix.scaleByDouble(
            clampedScaleChange,
            clampedScaleChange,
            clampedScaleChange,
            1,
          );
        }

        final Offset focalPointSceneScaled = _toScene(
          nextMatrix,
          details.localFocalPoint,
        );
        final Offset translationDelta =
            focalPointSceneScaled - _referenceFocalPoint!;

        final Matrix4 finalMatrix = _matrixTranslate(
          nextMatrix,
          translationDelta,
        );
        _transformer.value = finalMatrix;

        final Offset focalPointSceneCheck = _toScene(
          _transformer.value,
          details.localFocalPoint,
        );
        if (_round(_referenceFocalPoint!) != _round(focalPointSceneCheck)) {
          _referenceFocalPoint = focalPointSceneCheck;
        }

      case _GestureType.rotate:
        if (details.rotation == 0.0) {
          return;
        }
        final double desiredRotation = _rotationStart! + details.rotation;
        _transformer.value = _matrixRotate(
          _transformer.value,
          _currentRotation - desiredRotation,
          details.localFocalPoint,
        );
        _currentRotation = desiredRotation;

      case _GestureType.pan:
        assert(_referenceFocalPoint != null);

        if (details.scale != 1.0) {
          return;
        }

        if (isCurrentGestureADrawGesture) {
          _lastDrawDetails = details;
          widget.onDrawUpdate?.call(details);

          if (InteractiveCanvasViewer.isAutoPanningEnabled) {
            _updateAutoPanTarget(details.localFocalPoint);
          } else {
            _autoPanVelocity = null;
          }
        } else {
          _currentAxis ??= _getPanAxis(_referenceFocalPoint!, focalPointScene);

          Offset translationChange = focalPointScene - _referenceFocalPoint!;
          final feel = DisplayInkFeel.instance;
          if (feel.isLowRefresh && translationChange != Offset.zero) {
            final now = SchedulerBinding.instance.currentSystemFrameTimeStamp;
            final last = _lastPanStamp;
            if (last != null) {
              final dt = (now - last).inMicroseconds / 1e6;
              if (dt > 0.0005 && dt < 0.08) {
                final instant = translationChange / dt;
                _panVelocityScene = Offset.lerp(
                  _panVelocityScene,
                  instant,
                  0.45,
                )!;
              }
            }
            _lastPanStamp = now;
            // Constant-velocity lead stays fixed so we track 1:1 with the
            // finger while content sits ~one frame ahead (no cumulative drift).
            final newLead = _panVelocityScene * feel.panVelocityLeadSec;
            translationChange =
                translationChange * feel.panDeltaGain +
                (newLead - _appliedPanLead);
            _appliedPanLead = newLead;
          } else {
            _panVelocityScene = Offset.zero;
            _appliedPanLead = Offset.zero;
            _lastPanStamp = null;
          }
          _transformer.value = _matrixTranslate(
            _transformer.value,
            translationChange,
          );
          _referenceFocalPoint = _transformer.toScene(details.localFocalPoint);
        }
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_ignoreThisPanZoomGesture && !isCurrentGestureADrawGesture) {
      _ignoreThisPanZoomGesture = false;
      return;
    }
    widget.onInteractionEnd?.call(details);

    if (isCurrentGestureADrawGesture) {
      _stopPhysics();
      isCurrentGestureADrawGesture = false;
      return widget.onDrawEnd?.call(details);
    }

    _stopPhysics();
    _scaleStart = null;
    _rotationStart = null;
    _referenceFocalPoint = null;
    _panVelocityScene = Offset.zero;
    // Keep the last lead baked into the matrix (no snap-back on lift).
    _appliedPanLead = Offset.zero;
    _lastPanStamp = null;

    _animation?.removeListener(_handleInertiaAnimation);
    _scaleAnimation?.removeListener(_handleScaleAnimation);
    _controller.reset();
    _scaleController.reset();

    if (!_gestureIsSupported(_gestureType)) {
      _currentAxis = null;
      _finishViewportGesture();
      return;
    }

    switch (_gestureType) {
      case _GestureType.pan:
        if (details.velocity.pixelsPerSecond.distance < 150.0) {
          _currentAxis = null;
          _finishViewportGesture();
          return;
        }

        final double scale = _transformer.value.getMaxScaleOnAxis();

        _inertiaVelocity = (details.velocity.pixelsPerSecond / scale) * 0.7;
        // Keep viewportMoving true through fling so tiles stay on the cheap path.
        _startPhysics();

      case _GestureType.rotate:
      case _GestureType.scale:
      case null:
        _finishViewportGesture();
        break;
    }
  }

  void _finishViewportGesture() {
    if (!_viewportGestureActive) return;
    _viewportGestureActive = false;
    PageRasterCacheManager.updateViewportMoving(false);
  }

  void _receivedPointerSignal(PointerSignalEvent event) {
    final Offset local = event.localPosition;
    final Offset global = event.position;
    final double scaleChange;
    if (event is PointerScrollEvent) {
      if (!HardwareKeyboard.instance.isControlPressed &&
          !HardwareKeyboard.instance.isMetaPressed) {
        if (!_gestureIsSupported(_GestureType.pan)) return;

        final Offset localDelta = PointerEvent.transformDeltaViaPositions(
          untransformedEndPosition: global + event.scrollDelta,
          untransformedDelta: event.scrollDelta,
          transform: event.transform,
        );

        final Offset focalPointScene = _transformer.toScene(local);

        final Offset newFocalPointScene = _transformer.toScene(
          local - localDelta,
        );

        PageRasterCacheManager.updateViewportMoving(true);
        _transformer.value = _matrixTranslate(
          _transformer.value,
          newFocalPointScene - focalPointScene,
        );
        PageRasterCacheManager.updateViewportMoving(false);

        return;
      }

      if (event.scrollDelta.dy == 0.0) {
        return;
      }
      scaleChange = math.exp(-event.scrollDelta.dy / widget.scaleFactor);
    } else if (event is PointerScaleEvent) {
      scaleChange = event.scale;
    } else {
      return;
    }

    if (!_gestureIsSupported(_GestureType.scale)) return;

    _markWheelZoomActive();

    final Offset focalPointScene = _transformer.toScene(local);

    var nextMatrix = _matrixScale(_transformer.value, scaleChange);

    final Offset focalPointSceneScaled = _toScene(nextMatrix, local);
    nextMatrix = _matrixTranslate(
      nextMatrix,
      focalPointSceneScaled - focalPointScene,
    );
    _transformer.value = nextMatrix;
  }

  void _handleInertiaAnimation() {
    if (!_controller.isAnimating || _animation == null) {
      _currentAxis = null;
      _controller.removeListener(_handleInertiaAnimation);
      _animation = null;
      _controller.reset();
      return;
    }

    final Vector3 translationVector = _transformer.value.getTranslation();
    final Offset currentTranslation = Offset(
      translationVector.x,
      translationVector.y,
    );

    final Offset targetTranslation = _animation!.value;
    final Offset delta = targetTranslation - currentTranslation;

    final Matrix4 nextMatrix = _matrixTranslate(_transformer.value, delta);

    final Vector3 nextTranslationVector = nextMatrix.getTranslation();
    final Offset actualNewTranslation = Offset(
      nextTranslationVector.x,
      nextTranslationVector.y,
    );

    if ((actualNewTranslation - currentTranslation).distance < 0.01) {
      _controller.stop();
      return;
    }

    _transformer.value = nextMatrix;
  }

  void _handleScaleAnimation() {
    if (!_scaleController.isAnimating) {
      _currentAxis = null;
      _scaleAnimation?.removeListener(_handleScaleAnimation);
      _scaleAnimation = null;
      _scaleController.reset();
      return;
    }
    final double desiredScale = _scaleAnimation!.value;
    final double scaleChange =
        desiredScale / _transformer.value.getMaxScaleOnAxis();
    final Offset referenceFocalPoint = _transformer.toScene(
      _scaleAnimationFocalPoint,
    );
    var nextMatrix = _matrixScale(_transformer.value, scaleChange);

    final Offset focalPointSceneScaled = _toScene(
      nextMatrix,
      _scaleAnimationFocalPoint,
    );
    nextMatrix = _matrixTranslate(
      nextMatrix,
      focalPointSceneScaled - referenceFocalPoint,
    );
    _transformer.value = nextMatrix;
  }

  void _handleTransformation() {
    final scale = _transformer.value.getMaxScaleOnAxis();
    final lastPersisted = _lastPersistedCanvasScale;
    if (lastPersisted == null || (scale - lastPersisted).abs() >= 0.01) {
      _lastPersistedCanvasScale = scale;
      stows.lastCanvasScale = scale;
    }

    _scheduleViewportRebuildIfNeeded();
  }

  Ticker? _physicsTicker;
  Duration _lastTickTime = Duration.zero;
  Offset _inertiaVelocity = Offset.zero;
  Offset? _autoPanVelocity;
  ScaleUpdateDetails? _lastDrawDetails;
  bool _transformRebuildScheduled = false;
  double? _lastPersistedCanvasScale;
  Rect? _lastViewportBucket;
  Quad? _lastViewportQuad;
  Size? _lastViewportSize;

  static const double _viewportBucketSize = 360.0;

  Rect _bucketViewport(Rect viewport) {
    double bucket(double value) =>
        (value / _viewportBucketSize).floorToDouble() * _viewportBucketSize;
    return Rect.fromLTRB(
      bucket(viewport.left),
      bucket(viewport.top),
      bucket(viewport.right),
      bucket(viewport.bottom),
    );
  }

  void _syncViewportForBuild(Rect viewportRect) {
    final quad = _transformViewport(_transformer.value, viewportRect);
    _lastViewportQuad = quad;
    _lastViewportBucket = _bucketViewport(_quadAxisAlignedBounds(quad));
    _lastViewportSize = viewportRect.size;
  }

  void _scheduleViewportRebuildIfNeeded() {
    if (widget.builder == null || _parentKey.currentContext == null) return;
    final viewportRect = _viewport;
    final quad = _transformViewport(_transformer.value, viewportRect);
    final bucket = _bucketViewport(_quadAxisAlignedBounds(quad));
    if (_lastViewportBucket == bucket &&
        _lastViewportSize == viewportRect.size) {
      return;
    }
    _lastViewportBucket = bucket;
    _lastViewportQuad = quad;
    _lastViewportSize = viewportRect.size;

    if (_transformRebuildScheduled) return;
    _transformRebuildScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _transformRebuildScheduled = false;
      if (mounted) setState(() {});
    });
    SchedulerBinding.instance.ensureVisualUpdate();
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
    final wasTicking = _physicsTicker?.isTicking ?? false;
    _physicsTicker?.stop();
    _inertiaVelocity = Offset.zero;
    _autoPanVelocity = null;
    // Fling / edge-auto-pan ended: allow stroke tiles to leave the moving path.
    if (wasTicking && _viewportGestureActive && !isCurrentGestureADrawGesture) {
      _finishViewportGesture();
    }
  }

  void _updateAutoPanTarget(Offset localPosition) {
    const double edgeThreshold = 100.0;

    const double maxSpeedScreen = 1200.0;

    double dx = 0.0;
    double dy = 0.0;
    final Size viewportSize = _viewport.size;

    if (localPosition.dx < edgeThreshold) {
      dx =
          maxSpeedScreen *
          (1.0 - math.max(0.0, localPosition.dx) / edgeThreshold);
    } else if (localPosition.dx > viewportSize.width - edgeThreshold) {
      dx =
          -maxSpeedScreen *
          (1.0 -
              math.max(0.0, viewportSize.width - localPosition.dx) /
                  edgeThreshold);
    }

    if (localPosition.dy < edgeThreshold) {
      dy =
          maxSpeedScreen *
          (1.0 - math.max(0.0, localPosition.dy) / edgeThreshold);
    } else if (localPosition.dy > viewportSize.height - edgeThreshold) {
      dy =
          -maxSpeedScreen *
          (1.0 -
              math.max(0.0, viewportSize.height - localPosition.dy) /
                  edgeThreshold);
    }

    if (dx != 0 || dy != 0) {
      final double scale = _transformer.value.getMaxScaleOnAxis();
      _autoPanVelocity = Offset(dx / scale, dy / scale);
      _startPhysics();
    } else {
      _autoPanVelocity = null;
    }
  }

  void _onPhysicsTick(Duration elapsed) {
    if (_lastTickTime == Duration.zero) {
      _lastTickTime = elapsed;
      return;
    }
    final double dt = (elapsed - _lastTickTime).inMicroseconds / 1000000.0;
    _lastTickTime = elapsed;

    Offset delta = Offset.zero;

    if (_autoPanVelocity != null) {
      delta += _autoPanVelocity! * dt;
    }

    if (_inertiaVelocity.distance > 5.0) {
      delta += _inertiaVelocity * dt;

      _inertiaVelocity *= math.pow(0.15, dt).toDouble();
    } else {
      _inertiaVelocity = Offset.zero;
    }

    if (delta == Offset.zero) {
      _stopPhysics();
      return;
    }

    final Matrix4 nextMatrix = _matrixTranslate(_transformer.value, delta);

    final Offset actualDelta =
        _getMatrixTranslation(nextMatrix) -
        _getMatrixTranslation(_transformer.value);
    if (actualDelta.distance < delta.distance * 0.1) {
      _inertiaVelocity = Offset.zero;
    }

    _transformer.value = nextMatrix;

    if (isCurrentGestureADrawGesture &&
        _autoPanVelocity != null &&
        _lastDrawDetails != null) {
      widget.onDrawUpdate?.call(_lastDrawDetails!);
    }
  }

  VoidCallback? _scrollPhysicsStopListener;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _scaleController = AnimationController(vsync: this);
    _transformer.addListener(_handleTransformation);
    _scrollPhysicsStopListener = () => _stopPhysics();
    widget.scrollPhysicsStopNotifier?.addListener(_scrollPhysicsStopListener!);
  }

  @override
  void didUpdateWidget(InteractiveCanvasViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scrollPhysicsStopNotifier !=
        oldWidget.scrollPhysicsStopNotifier) {
      oldWidget.scrollPhysicsStopNotifier?.removeListener(
        _scrollPhysicsStopListener!,
      );
      widget.scrollPhysicsStopNotifier?.addListener(
        _scrollPhysicsStopListener!,
      );
    }
    final TransformationController? newController =
        widget.transformationController;
    if (newController == oldWidget.transformationController) {
      return;
    }
    _transformer.removeListener(_handleTransformation);
    if (oldWidget.transformationController == null) {
      _transformer.dispose();
    }
    _transformer = newController ?? TransformationController();
    _transformer.addListener(_handleTransformation);
  }

  @override
  void dispose() {
    _wheelZoomSettleTimer?.cancel();
    widget.scrollPhysicsStopNotifier?.removeListener(
      _scrollPhysicsStopListener!,
    );
    _physicsTicker?.dispose();
    _controller.dispose();
    _scaleController.dispose();
    _transformer.removeListener(_handleTransformation);
    if (widget.transformationController == null) {
      _transformer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (widget.child != null) {
      child = _InteractiveCanvasViewerBuilt(
        childKey: _childKey,
        clipBehavior: widget.clipBehavior,
        constrained: widget.constrained,
        transformer: _transformer,
        alignment: widget.alignment,
        child: widget.child!,
      );
    } else {
      assert(widget.builder != null);
      assert(!widget.constrained);
      child = LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final viewportRect = Offset.zero & constraints.biggest;
          if (_lastViewportQuad == null ||
              _lastViewportSize != viewportRect.size) {
            _syncViewportForBuild(viewportRect);
          }
          return _InteractiveCanvasViewerBuilt(
            childKey: _childKey,
            clipBehavior: widget.clipBehavior,
            constrained: widget.constrained,
            alignment: widget.alignment,
            transformer: _transformer,
            child: widget.builder!(context, _lastViewportQuad!),
          );
        },
      );
    }

    return Listener(
      key: _parentKey,
      onPointerSignal: _receivedPointerSignal,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          _ImmediateScaleGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                _ImmediateScaleGestureRecognizer
              >(
                () => _ImmediateScaleGestureRecognizer(
                  debugOwner: this,
                  isDrawGesture: (PointerDownEvent event) {
                    final details = ScaleStartDetails(
                      focalPoint: event.position,
                      localFocalPoint: event.localPosition,
                      pointerCount: 1,
                    );
                    return widget.isDrawGesture?.call(details) ?? false;
                  },
                ),
                (_ImmediateScaleGestureRecognizer instance) {
                  instance
                    ..onStart = _onScaleStart
                    ..onUpdate = _onScaleUpdate
                    ..onEnd = _onScaleEnd
                    // Milder slop at ~60 Hz so pan/zoom starts a frame sooner;
                    // draw still wins the arena immediately via isDrawGesture.
                    ..gestureSettings = DeviceGestureSettings(
                      touchSlop:
                          kTouchSlop * DisplayInkFeel.instance.panTouchSlopFactor,
                    )
                    ..trackpadScrollCausesScale =
                        widget.trackpadScrollCausesScale
                    ..trackpadScrollToScaleFactor = Offset(
                      0,
                      -1 / widget.scaleFactor,
                    );
                },
              ),
        },
        child: child,
      ),
    );
  }
}

class _InteractiveCanvasViewerBuilt extends StatelessWidget {
  const _InteractiveCanvasViewerBuilt({
    required this.child,
    required this.childKey,
    required this.clipBehavior,
    required this.constrained,
    required this.transformer,
    required this.alignment,
  });

  final Widget child;
  final GlobalKey childKey;
  final Clip clipBehavior;
  final bool constrained;
  final TransformationController transformer;
  final Alignment? alignment;

  @override
  Widget build(BuildContext context) {
    final transformedChild = KeyedSubtree(key: childKey, child: child);
    Widget result = AnimatedBuilder(
      animation: transformer,
      child: transformedChild,
      builder: (context, child) => Transform(
        transform: transformer.value,
        alignment: alignment,
        child: child,
      ),
    );

    if (!constrained) {
      result = OverflowBox(
        alignment: .topLeft,
        minWidth: 0,
        minHeight: 0,

        maxHeight: double.infinity,
        child: result,
      );
    }

    return ClipRect(clipBehavior: clipBehavior, child: result);
  }
}

enum _GestureType { pan, scale, rotate }

class _ImmediateScaleGestureRecognizer extends ScaleGestureRecognizer {
  _ImmediateScaleGestureRecognizer({
    super.debugOwner,
    required this.isDrawGesture,
  });

  final bool Function(PointerDownEvent) isDrawGesture;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    if (isDrawGesture(event)) {
      resolve(GestureDisposition.accepted);
    }
  }
}

Offset _getMatrixTranslation(Matrix4 matrix) {
  final Vector3 nextTranslation = matrix.getTranslation();
  return Offset(nextTranslation.x, nextTranslation.y);
}

Quad _transformViewport(Matrix4 matrix, Rect viewport) {
  final Matrix4 inverseMatrix = matrix.clone()..invert();
  return Quad.points(
    inverseMatrix.transform3(
      Vector3(viewport.topLeft.dx, viewport.topLeft.dy, 0),
    ),
    inverseMatrix.transform3(
      Vector3(viewport.topRight.dx, viewport.topRight.dy, 0),
    ),
    inverseMatrix.transform3(
      Vector3(viewport.bottomRight.dx, viewport.bottomRight.dy, 0),
    ),
    inverseMatrix.transform3(
      Vector3(viewport.bottomLeft.dx, viewport.bottomLeft.dy, 0),
    ),
  );
}

Rect _quadAxisAlignedBounds(Quad quad) {
  final points = [quad.point0, quad.point1, quad.point2, quad.point3];
  var left = points.first.x;
  var right = points.first.x;
  var top = points.first.y;
  var bottom = points.first.y;
  for (var i = 1; i < points.length; i++) {
    final point = points[i];
    left = math.min(left, point.x);
    right = math.max(right, point.x);
    top = math.min(top, point.y);
    bottom = math.max(bottom, point.y);
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

Quad _getAxisAlignedBoundingBoxWithRotation(Rect rect, double rotation) {
  final Matrix4 rotationMatrix = Matrix4.identity()
    ..translateByDouble(rect.size.width / 2, rect.size.height / 2, 0, 1)
    ..rotateZ(rotation)
    ..translateByDouble(-rect.size.width / 2, -rect.size.height / 2, 0, 1);
  final Quad boundariesRotated = Quad.points(
    rotationMatrix.transform3(Vector3(rect.left, rect.top, 0)),
    rotationMatrix.transform3(Vector3(rect.right, rect.top, 0)),
    rotationMatrix.transform3(Vector3(rect.right, rect.bottom, 0)),
    rotationMatrix.transform3(Vector3(rect.left, rect.bottom, 0)),
  );
  return InteractiveCanvasViewer.getAxisAlignedBoundingBox(boundariesRotated);
}

Offset _exceedsBy(Quad boundary, Quad viewport) {
  final List<Vector3> viewportPoints = <Vector3>[
    viewport.point0,
    viewport.point1,
    viewport.point2,
    viewport.point3,
  ];
  Offset largestExcess = .zero;
  for (final Vector3 point in viewportPoints) {
    final Vector3 pointInside = InteractiveCanvasViewer.getNearestPointInside(
      point,
      boundary,
    );
    final Offset excess = Offset(
      pointInside.x - point.x,
      pointInside.y - point.y,
    );
    if (excess.dx.abs() > largestExcess.dx.abs()) {
      largestExcess = Offset(excess.dx, largestExcess.dy);
    }
    if (excess.dy.abs() > largestExcess.dy.abs()) {
      largestExcess = Offset(largestExcess.dx, excess.dy);
    }
  }

  return _round(largestExcess);
}

Offset _round(Offset offset) {
  return Offset(
    double.parse(offset.dx.toStringAsFixed(9)),
    double.parse(offset.dy.toStringAsFixed(9)),
  );
}

Offset _alignAxis(Offset offset, Axis axis) {
  return switch (axis) {
    Axis.horizontal => Offset(offset.dx, 0),
    Axis.vertical => Offset(0, offset.dy),
  };
}

Axis? _getPanAxis(Offset point1, Offset point2) {
  if (point1 == point2) {
    return null;
  }
  final double x = point2.dx - point1.dx;
  final double y = point2.dy - point1.dy;
  return x.abs() > y.abs() ? Axis.horizontal : Axis.vertical;
}
