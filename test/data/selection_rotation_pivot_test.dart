import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/stroke_geometry/point_vector.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/select.dart';

import '../helpers/test_stroke_factory.dart';

Offset rotateAround(Offset p, Offset c, double rad) {
  final dx = p.dx - c.dx;
  final dy = p.dy - c.dy;
  final cosTheta = math.cos(rad);
  final sinTheta = math.sin(rad);
  return Offset(
    c.dx + dx * cosTheta - dy * sinTheta,
    c.dy + dx * sinTheta + dy * cosTheta,
  );
}

double maxPointDrift(List<List<Offset>> a, List<List<Offset>> b) {
  var max = 0.0;
  for (var i = 0; i < a.length; i++) {
    for (var j = 0; j < a[i].length; j++) {
      max = math.max(max, (a[i][j] - b[i][j]).distance);
    }
  }
  return max;
}

/// Builds asymmetric ink (long horizontal + short vertical leg) so the
/// point-average centroid differs from the bounding-box center.
List<Stroke> asymmetricStrokes() {
  final horizontal = testPolylineStroke(
    toolId: ToolId.fountainPen,
    y: 100,
    x0: 0,
    x1: 200,
    points: 21,
  );
  final vertical = testPolylineStroke(toolId: ToolId.fountainPen);
  vertical.points.clear();
  vertical.points.addAll([
    PointVector(0, 100, 0.5),
    PointVector(0, 200, 0.5),
  ]);
  vertical.markPolygonNeedsUpdating();
  return [horizontal, vertical];
}

void main() {
  test('rotation pivot stays fixed across commits (no translation)', () {
    final strokes = asymmetricStrokes();
    final selection = SelectResult(
      pageIndex: 0,
      pageIndexStart: 0,
      strokes: strokes,
      images: const [],
      path: Path(),
    );

    List<List<Offset>> snapshotGeometry() => [
      for (final s in selection.strokes) List<Offset>.of(s.highQualityPolygon),
    ];

    const step = 30 * math.pi / 180;
    selection.displayBounds = null;
    final before = snapshotGeometry();

    // First rotation commit, mimicking _commitSelectionPreview.
    var preview = SelectionTransformPreview.fromSelection(selection);
    final pivot1 = preview.pivot;
    for (final s in selection.strokes) {
      s.rotate(step, pivot1);
    }
    selection.rotationDeg = (selection.rotationDeg + 30) % 360.0;
    selection.displayBounds = null;
    selection.recomputeBoundsAround(pivot1);

    // Second rotation commit around the freshly computed pivot.
    preview = SelectionTransformPreview.fromSelection(selection);
    final pivot2 = preview.pivot;
    for (final s in selection.strokes) {
      s.rotate(-step, pivot2);
    }
    selection.rotationDeg = (selection.rotationDeg - 30) % 360.0;
    selection.displayBounds = null;
    selection.recomputeBoundsAround(pivot2);

    final after = snapshotGeometry();

    // The pivot must not wander between commits...
    expect(
      (pivot2 - pivot1).distance,
      lessThan(1e-6),
      reason: 'rotation pivot drifted between commits',
    );
    // ...and a +30/-30 round trip must restore the geometry exactly.
    expect(
      maxPointDrift(before, after),
      lessThan(1e-6),
      reason: 'rotation round trip translated the strokes',
    );
  });

  test('overlay box tracks rotated content extents', () {
    final strokes = asymmetricStrokes();
    final selection = SelectResult(
      pageIndex: 0,
      pageIndexStart: 0,
      strokes: strokes,
      images: const [],
      path: Path(),
    );
    selection.displayBounds = null;

    const step = 45 * math.pi / 180;
    final preview = SelectionTransformPreview.fromSelection(selection);
    final rotated = preview.copyWith(rotationDeltaDeg: 45.0);

    // Commit the same rotation the preview shows.
    for (final s in selection.strokes) {
      s.rotate(step, preview.pivot);
    }
    selection.rotationDeg = (selection.rotationDeg + 45) % 360.0;
    selection.displayBounds = null;
    selection.recomputeBoundsAround(preview.pivot);

    // The overlay box (unrotated base box rotated by the effective angle)
    // must match the committed geometry frame.
    final box = rotated.visualBounds;
    final boxCorners = {
      rotateAround(box.topLeft, box.center, step),
      rotateAround(box.topRight, box.center, step),
      rotateAround(box.bottomRight, box.center, step),
      rotateAround(box.bottomLeft, box.center, step),
    };
    final committedBox = selection.displayBounds!;
    final committedCorners = {
      rotateAround(committedBox.topLeft, committedBox.center, step),
      rotateAround(
        committedBox.topRight,
        committedBox.center,
        step,
      ),
      rotateAround(
        committedBox.bottomRight,
        committedBox.center,
        step,
      ),
      rotateAround(
        committedBox.bottomLeft,
        committedBox.center,
        step,
      ),
    };
    double cornerDrift = 0.0;
    for (final a in boxCorners) {
      var best = double.infinity;
      for (final b in committedCorners) {
        best = math.min(best, (a - b).distance);
      }
      cornerDrift = math.max(cornerDrift, best);
    }
    expect(
      cornerDrift,
      lessThan(1e-6),
      reason: 'overlay box detached from rotated content',
    );
  });

  test('undo restores exact geometry via stored pivot', () {
    final strokes = asymmetricStrokes();
    final selection = SelectResult(
      pageIndex: 0,
      pageIndexStart: 0,
      strokes: strokes,
      images: const [],
      path: Path(),
    );
    selection.displayBounds = null;
    List<Offset> snapshotGeometry() => [
      for (final s in selection.strokes) ...s.highQualityPolygon,
    ];
    final before = snapshotGeometry();

    const step = 30 * math.pi / 180;
    final preview = SelectionTransformPreview.fromSelection(selection);
    final pivot = preview.pivot;
    for (final s in selection.strokes) {
      s.rotate(step, pivot);
    }
    selection.rotationDeg = (selection.rotationDeg + 30) % 360.0;
    selection.displayBounds = null;
    selection.recomputeBoundsAround(pivot);

    // Undo: inverse rotation around the stored history centroid.
    final storedCentroid = pivot;
    for (final s in selection.strokes) {
      s.rotate(-step, storedCentroid);
    }
    selection.rotationDeg = (selection.rotationDeg - 30) % 360.0;
    selection.displayBounds = null;
    selection.recomputeBoundsAround(storedCentroid);

    final after = snapshotGeometry();
    var maxDrift = 0.0;
    for (var i = 0; i < before.length; i++) {
      maxDrift = math.max(maxDrift, (before[i] - after[i]).distance);
    }
    expect(maxDrift, lessThan(1e-6));
    expect(
      (selection.displayBounds!.center - pivot).distance,
      lessThan(1e-6),
    );
  });
}
