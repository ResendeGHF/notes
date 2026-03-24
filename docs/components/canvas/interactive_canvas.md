# `lib/components/canvas/interactive_canvas.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Global flag to enable/disable edge scrolling. Managed by EditorState.

### Block 2

Create an InteractiveCanvasViewer.

### Block 3

Creates an InteractiveCanvasViewer for a child that is created on demand.

 Can be used to render a child that changes in response to the current
 transformation.

 See the [builder] attribute docs for an example of using it to optimize a
 large child.

### Block 4

The alignment of the child's origin, relative to the size of the box.

### Block 5

If set to [Clip.none], the child may extend beyond the size of the InteractiveCanvasViewer,
 but it will not receive gestures in these areas.
 Be sure that the InteractiveCanvasViewer is the desired size when using [Clip.none].

 Defaults to [Clip.hardEdge].

### Block 6

When set to [PanAxis.aligned], panning is only allowed in the horizontal
 axis or the vertical axis, diagonal panning is not allowed.

 When set to [PanAxis.vertical] or [PanAxis.horizontal] panning is only
 allowed in the specified axis. For example, if set to [PanAxis.vertical],
 panning will only be allowed in the vertical axis. And if set to [PanAxis.horizontal],
 panning will only be allowed in the horizontal axis.

 When set to [PanAxis.free] panning is allowed in all directions.

 Defaults to [PanAxis.free].

### Block 7

A margin for the visible boundaries of the child.

 Any transformation that results in the viewport being able to view outside
 of the boundaries will be stopped at the boundary. The boundaries do not
 rotate with the rest of the scene, so they are always aligned with the
 viewport.

 To produce no boundaries at all, pass infinite [EdgeInsets], such as
 `EdgeInsets.all(double.infinity)`.

 No edge can be NaN.

 Defaults to [EdgeInsets.zero], which results in boundaries that are the
 exact same size and position as the [child].

### Block 8

Builds the child of this widget.

 Passed with the [InteractiveCanvasViewer.builder] constructor. Otherwise, the
 [child] parameter must be passed directly, and this is null.

 {@tool dartpad}
 This example shows how to use builder to create a [Table] whose cell
 contents are only built when they are visible. Built and remove cells are
 logged in the console for illustration.

 ** See code in examples/api/lib/widgets/interactive_viewer/interactive_viewer.builder.0.dart **
 {@end-tool}

 See also:

   * [ListView.builder], which follows a similar pattern.

### Block 9

The child [Widget] that is transformed by InteractiveCanvasViewer.

 If the [InteractiveCanvasViewer.builder] constructor is used, then this will be
 null, otherwise it is required.

### Block 10

Whether the normal size constraints at this point in the widget tree are
 applied to the child.

 If set to false, then the child will be given infinite constraints. This
 is often useful when a child should be bigger than the InteractiveCanvasViewer.

 For example, for a child which is bigger than the viewport but can be
 panned to reveal parts that were initially offscreen, [constrained] must
 be set to false to allow it to size itself properly. If [constrained] is
 true and the child can only size itself to the viewport, then areas
 initially outside of the viewport will not be able to receive user
 interaction events. If experiencing regions of the child that are not
 receptive to user gestures, make sure [constrained] is false and the child
 is sized properly.

 Defaults to true.

 {@tool dartpad}
 This example shows how to create a pannable table. Because the table is
 larger than the entire screen, setting [constrained] to false is necessary
 to allow it to be drawn to its full size. The parts of the table that
 exceed the screen size can then be panned into view.

 ** See code in examples/api/lib/widgets/interactive_viewer/interactive_viewer.constrained.0.dart **
 {@end-tool}

### Block 11

If false, the user will be prevented from panning.

 Defaults to true.

 See also:

   * [scaleEnabled], which is similar but for scale.

### Block 12

If false, the user will be prevented from scaling.

 Defaults to true.

 See also:

   * [panEnabled], which is similar but for panning.

### Block 13

{@macro flutter.gestures.scale.trackpadScrollCausesScale}

### Block 14

Determines the amount of scale to be performed per pointer scroll.

 Defaults to [kDefaultMouseScrollToScaleFactor].

 Increasing this value above the default causes scaling to feel slower,
 while decreasing it causes scaling to feel faster.

 The amount of scale is calculated as the exponential function of the
 [PointerScrollEvent.scrollDelta] to [scaleFactor] ratio. In the Flutter
 engine, the mousewheel [PointerScrollEvent.scrollDelta] is hardcoded to 20
 per scroll, while a trackpad scroll can be any amount.

 Affects only pointer device scrolling, not pinch to zoom.

### Block 15

The maximum allowed scale.

 The scale will be clamped between this and [minScale] inclusively.

 Defaults to 2.5.

 Must be greater than zero and greater than [minScale].

### Block 16

The minimum allowed scale.

 The scale will be clamped between this and [maxScale] inclusively.

 Scale is also affected by [boundaryMargin]. If the scale would result in
 viewing beyond the boundary, then it will not be allowed. By default,
 boundaryMargin is .zero, so scaling below 1.0 will not be
 allowed in most cases without first increasing the boundaryMargin.

 Defaults to 0.8.

 Must be a finite number greater than zero and less than [maxScale].

### Block 17

Changes the deceleration behavior after a gesture.

 Defaults to 0.0000135.

 Must be a finite number greater than zero.

### Block 18

Called when the user ends a pan or scale gesture on the widget.

 At the time this is called, the [TransformationController] will have
 already been updated to reflect the change caused by the interaction,
 though a pan may cause an inertia animation after this is called as well.

 {@template flutter.widgets.InteractiveCanvasViewer.onInteractionEnd}
 Will be called even if the interaction is disabled with [panEnabled] or
 [scaleEnabled] for both touch gestures and mouse interactions.

 A [GestureDetector] wrapping the InteractiveCanvasViewer will not respond to
 [GestureDetector.onScaleStart], [GestureDetector.onScaleUpdate], and
 [GestureDetector.onScaleEnd]. Use [onDrawStart],
 [onDrawUpdate], and [onDrawEnd] to respond to those
 gestures.
 {@endtemplate}

 See also:

  * [onDrawStart], which handles the start of the same interaction.
  * [onDrawUpdate], which handles an update to the same interaction.

### Block 19

Called when the user begins a pan or scale gesture on the widget.

 At the time this is called, the [TransformationController] will not have
 changed due to this interaction.

 {@macro flutter.widgets.InteractiveCanvasViewer.onInteractionEnd}

 The coordinates provided in the details' `focalPoint` and
 `localFocalPoint` are normal Flutter event coordinates, not
 InteractiveCanvasViewer scene coordinates. See
 [TransformationController.toScene] for how to convert these coordinates to
 scene coordinates relative to the child.

 See also:

  * [onDrawUpdate], which handles an update to the same interaction.
  * [onDrawEnd], which handles the end of the same interaction.

### Block 20

Called when the user updates a pan or scale gesture on the widget.

 At the time this is called, the [TransformationController] will have
 already been updated to reflect the change caused by the interaction, if
 the interaction caused the matrix to change.

 {@macro flutter.widgets.InteractiveCanvasViewer.onInteractionEnd}

 The coordinates provided in the details' `focalPoint` and
 `localFocalPoint` are normal Flutter event coordinates, not
 InteractiveCanvasViewer scene coordinates. See
 [TransformationController.toScene] for how to convert these coordinates to
 scene coordinates relative to the child.

 See also:

  * [onDrawStart], which handles the start of the same interaction.
  * [onDrawEnd], which handles the end of the same interaction.

### Block 21

A function to distinguish a draw gesture and a pan/zoom gesture.

### Block 22

When non-null, if this returns true at gesture start, pan/zoom is ignored
 for that gesture (e.g. when touch starts outside the canvas).

### Block 23

When non-null, listener will stop scroll physics when this notifier's value
 changes. Used to coordinate stopping inertia across canvas and scrollbar.

### Block 24

Called when any gesture ends.

### Block 25

A [TransformationController] for the transformation performed on the
 child.

 Whenever the child is transformed, the [Matrix4] value is updated and all
 listeners are notified. If the value is set, InteractiveCanvasViewer will update
 to respect the new value.

 {@tool dartpad}
 This example shows how transformationController can be used to animate the
 transformation back to its starting position.

 ** See code in examples/api/lib/widgets/interactive_viewer/interactive_viewer.transformation_controller.0.dart **
 {@end-tool}

 See also:

  * [ValueNotifier], the parent class of TransformationController.
  * [TextEditingController] for an example of another similar pattern.

### Block 26

Returns the closest point to the given point on the given line segment.

### Block 27

Given a quad, return its axis aligned bounding box.

### Block 28

Returns true iff the point is inside the rectangle given by the Quad,
 inclusively.
 Algorithm from https://math.stackexchange.com/a/190373.

### Block 29

Get the point inside (inclusively) the given Quad that is nearest to the
 given Vector3.

### Block 30

A custom [ScaleGestureRecognizer] that can win the arena immediately for stylus input

## Imports

- `dart:math`
- `package:flutter/foundation.dart`
- `package:flutter/gestures.dart`
- `package:flutter/material.dart`
- `package:flutter/scheduler.dart`
- `package:flutter/services.dart`
- `package:saber/data/prefs.dart`
- `package:vector_math/vector_math_64.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `InteractiveCanvasViewerWidgetBuilder`
- `InteractiveCanvasViewer`
- `_InteractiveCanvasViewerState`
- `_InteractiveCanvasViewerBuilt`
- `_GestureType`
- `_ImmediateScaleGestureRecognizer`
- `Function()`
- `initState()`
- `didUpdateWidget()`
- `dispose()`
- `build()`
- `addAllowedPointer()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
