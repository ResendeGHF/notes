// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Pure-Dart port of flxzt/ink-stroke-modeler-rs (itself a port of
// google/ink-stroke-modeler): wobble smoothing, linear resampling,
// spring-mass position modeling, end-of-stroke catch-up, nearest-segment
// stylus (pressure) interpolation and stroke-end prediction.
//
// Source mapping (ink-stroke-modeler-rs `src/`):
// - `WobbleSample`, `StrokeModeler::{update,predict,wobble_update,reset}`
//   <- `engine.rs`
// - `PositionModeler::{update,update_along_linear_path,model_end_of_stroke}`
//   <- `position_modeler.rs`
// - `StateModeler::{update,query}` <- `state_modeler.rs`
// - `normalize01_64`, `interp`, `nearest_point_on_segment`, `dist`, `dot`
//   <- `utils.rs`
// - `ModelerInput{,EventType}`, `ModelerResult` <- `input.rs`, `results.rs`
//
// Numerical behavior matches the Rust originals (same formulas, same edge
// cases: first-event passthrough, `ceil(dt * minOutputRate)` upsampling,
// halving `dt` on overshoot, state save/restore in `modelEndOfStroke`).
// Time and space units are agnostic, exactly as upstream: Saber feeds
// seconds (from [Duration]) and page-local pixels.

import 'dart:collection';
import 'dart:math' as math;

import 'package:saber/data/stroke_geometry/advanced_pen_options.dart';

/// Raw input event type, mirroring `ModelerInputEventType`.
enum AdvancedPenInputEventType { down, move, up }

/// Raw input sample, mirroring `ModelerInput` (tilt/orientation are
/// intentionally absent upstream and here).
class AdvancedPenModelerInput {
  final AdvancedPenInputEventType eventType;
  final double x;
  final double y;
  final double time;
  final double pressure;

  const AdvancedPenModelerInput({
    required this.eventType,
    required this.x,
    required this.y,
    required this.time,
    required this.pressure,
  });

  @override
  bool operator ==(Object other) {
    return other is AdvancedPenModelerInput &&
        other.eventType == eventType &&
        other.x == x &&
        other.y == y &&
        other.time == time &&
        other.pressure == pressure;
  }

  @override
  int get hashCode => Object.hash(eventType, x, y, time, pressure);
}

/// Modeled output sample, mirroring `ModelerResult`.
class AdvancedPenModelerResult {
  final double x;
  final double y;
  final double vx;
  final double vy;
  final double ax;
  final double ay;
  final double time;
  final double pressure;

  const AdvancedPenModelerResult({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.ax,
    required this.ay,
    required this.time,
    required this.pressure,
  });
}

/// Failure modes, mirroring `ModelerError` / `ElementError`.
enum AdvancedPenModelerError {
  unexpectedDown,
  unexpectedMove,
  unexpectedUp,
  negativeTimeDelta,
  duplicate,
  tooFarApart,
  emptyPrediction,
}

class AdvancedPenModelerException implements Exception {
  final AdvancedPenModelerError error;
  const AdvancedPenModelerException(this.error);
  @override
  String toString() => 'AdvancedPenModelerException($error)';
}

class _WobbleSample {
  final double x;
  final double y;
  final double weightedX;
  final double weightedY;
  final double distance;
  final double duration;
  final double time;

  const _WobbleSample({
    required this.x,
    required this.y,
    required this.weightedX,
    required this.weightedY,
    required this.distance,
    required this.duration,
    required this.time,
  });
}

class _Partial {
  double x, y, vx, vy, ax, ay, time;
  _Partial({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.ax,
    required this.ay,
    required this.time,
  });

  _Partial clone() => _Partial(
        x: x,
        y: y,
        vx: vx,
        vy: vy,
        ax: ax,
        ay: ay,
        time: time,
      );
}

double _normalize01(double start, double end, double value) {
  if (start == end) return value > start ? 1.0 : 0.0;
  return ((value - start) / (end - start)).clamp(0.0, 1.0);
}

double _interp(double start, double end, double amount) {
  final t = amount.clamp(0.0, 1.0);
  return start + (end - start) * t;
}

double _dot(double ax, double ay, double bx, double by) => ax * bx + ay * by;

double _dist(double ax, double ay, double bx, double by) {
  final dx = ax - bx;
  final dy = ay - by;
  return math.sqrt(dx * dx + dy * dy);
}

double _nearestPointOnSegment(
  double sx,
  double sy,
  double ex,
  double ey,
  double px,
  double py,
) {
  if (sx == ex && sy == ey) return 0.0;
  final segX = ex - sx;
  final segY = ey - sy;
  final projX = px - sx;
  final projY = py - sy;
  return (_dot(projX, projY, segX, segY) / _dot(segX, segY, segX, segY))
      .clamp(0.0, 1.0);
}

/// Spring-mass tip model. Port of `PositionModeler` in `position_modeler.rs`.
class _PositionModeler {
  final double springMassConstant;
  final double dragConstant;
  final _Partial state;

  _PositionModeler({
    required this.springMassConstant,
    required this.dragConstant,
    required double startX,
    required double startY,
    required double startTime,
  }) : state = _Partial(
          x: startX,
          y: startY,
          vx: 0,
          vy: 0,
          ax: 0,
          ay: 0,
          time: startTime,
        );

  _Partial update(double anchorX, double anchorY, double time) {
    final dt = time - state.time;
    state.ax = (anchorX - state.x) / springMassConstant - dragConstant * state.vx;
    state.ay = (anchorY - state.y) / springMassConstant - dragConstant * state.vy;
    state.vx = state.vx + dt * state.ax;
    state.vy = state.vy + dt * state.ay;
    state.x = state.x + dt * state.vx;
    state.y = state.y + dt * state.vy;
    state.time = time;
    return state.clone();
  }

  /// Port of `update_along_linear_path`: linearly interpolate the anchor
  /// from ([startX],[startY],[startTime]) to ([endX],[endY],[endTime]) in
  /// [nSteps] and feed each interpolated anchor through [update].
  List<_Partial> updateAlongLinearPath(
    double startX,
    double startY,
    double startTime,
    double endX,
    double endY,
    double endTime,
    int nSteps,
  ) {
    final out = <_Partial>[];
    for (var i = 1; i <= nSteps; i++) {
      final frac = i / nSteps;
      final ax = startX + frac * (endX - startX);
      final ay = startY + frac * (endY - startY);
      final t = startTime + frac * (endTime - startTime);
      out.add(update(ax, ay, t));
    }
    return out;
  }

  /// Port of `model_end_of_stroke`: iterate the spring towards [anchorX/Y]
  /// without mutating the model (state is saved and restored). Stops when a
  /// step moves less than [stopDistance], when the candidate reaches the
  /// anchor, or after [maxIterations]. Overshooting candidates halve `dt`
  /// and are retried.
  List<_Partial> modelEndOfStroke(
    double anchorX,
    double anchorY,
    double deltaTime,
    int maxIterations,
    double stopDistance,
  ) {
    final initial = state.clone();
    var dt = deltaTime;
    final out = <_Partial>[];
    for (var k = 0; k < maxIterations; k++) {
      final previous = state.clone();
      final candidate = update(anchorX, anchorY, previous.time + dt);
      if (_dist(previous.x, previous.y, candidate.x, candidate.y) < stopDistance) {
        state
          ..x = initial.x
          ..y = initial.y
          ..vx = initial.vx
          ..vy = initial.vy
          ..ax = initial.ax
          ..ay = initial.ay
          ..time = initial.time;
        return out;
      }
      if (_nearestPointOnSegment(
            previous.x,
            previous.y,
            candidate.x,
            candidate.y,
            anchorX,
            anchorY,
          ) <
          1.0) {
        dt *= 0.5;
        state
          ..x = previous.x
          ..y = previous.y
          ..vx = previous.vx
          ..vy = previous.vy
          ..ax = previous.ax
          ..ay = previous.ay
          ..time = previous.time;
        continue;
      } else {
        out.add(candidate.clone());
      }
      if (_dist(candidate.x, candidate.y, anchorX, anchorY) < stopDistance) {
        state
          ..x = initial.x
          ..y = initial.y
          ..vx = initial.vx
          ..vy = initial.vy
          ..ax = initial.ax
          ..ay = initial.ay
          ..time = initial.time;
        return out;
      }
    }
    state
      ..x = initial.x
      ..y = initial.y
      ..vx = initial.vx
      ..vy = initial.vy
      ..ax = initial.ax
      ..ay = initial.ay
      ..time = initial.time;
    return out;
  }
}

/// Pressure lookup over recent raw inputs. Port of `StateModeler::query`.
class _StateModeler {
  int maxSamples;
  final ListQueue<AdvancedPenModelerInput> _recent = ListQueue();

  _StateModeler(this.maxSamples);

  void reset(int max) {
    _recent.clear();
    maxSamples = max <= 0 ? 1 : max;
  }

  void update(AdvancedPenModelerInput input) {
    _recent.addLast(input);
    while (_recent.length > (maxSamples <= 0 ? 1 : maxSamples)) {
      _recent.removeFirst();
    }
  }

  double query(double x, double y) {
    if (_recent.isEmpty) return 1.0;
    if (_recent.length == 1) return _recent.first.pressure;
    var best = double.infinity;
    var r = 0.0;
    var startP = 1.0;
    var endP = 1.0;
    for (var i = 0; i < _recent.length - 1; i++) {
      final s = _recent.elementAt(i);
      final e = _recent.elementAt(i + 1);
      final rc = _nearestPointOnSegment(s.x, s.y, e.x, e.y, x, y);
      final cx = _interp(s.x, e.x, rc);
      final cy = _interp(s.y, e.y, rc);
      final d = _dist(x, y, cx, cy);
      if (d < best) {
        best = d;
        r = rc;
        startP = s.pressure;
        endP = e.pressure;
      }
    }
    return _interp(startP, endP, r);
  }
}

/// Dart port of `StrokeModeler` (`engine.rs`).
///
/// Feed raw pointer samples in order: one [AdvancedPenInputEventType.down],
/// zero or more [AdvancedPenInputEventType.move], then one
/// [AdvancedPenInputEventType.up]. Each [update] returns the newly modeled
/// results (at least one on success); [predict] returns the stroke-end
/// catch-up tail without mutating the model.
class AdvancedPenStrokeModeler {
  AdvancedPenModelerParams params;

  final ListQueue<_WobbleSample> _wobble = ListQueue();
  double _wobbleSumX = 0;
  double _wobbleSumY = 0;
  double _wobbleDurationSum = 0;
  double _wobbleDistanceSum = 0;

  _PositionModeler? _position;
  AdvancedPenModelerInput? _lastEvent;
  (double, double)? _lastCorrected;
  late _StateModeler _state;

  AdvancedPenStrokeModeler([AdvancedPenModelerParams? params])
      : params = params ?? AdvancedPenModelerParams.advancedDefaults {
    _state = _StateModeler(this.params.maxInputSamples);
  }

  void reset() {
    _wobble.clear();
    _wobbleSumX = 0;
    _wobbleSumY = 0;
    _wobbleDurationSum = 0;
    _wobbleDistanceSum = 0;
    _position = null;
    _lastEvent = null;
    _lastCorrected = null;
    _state.reset(params.maxInputSamples);
  }

  void resetWithParams(AdvancedPenModelerParams next) {
    final err = next.validate();
    if (err != null) throw ArgumentError('Invalid AdvancedPenModelerParams: $err');
    params = next;
    reset();
  }

  List<AdvancedPenModelerResult> update(AdvancedPenModelerInput input) {
    switch (input.eventType) {
      case AdvancedPenInputEventType.down:
        if (_lastEvent != null) {
          throw const AdvancedPenModelerException(AdvancedPenModelerError.unexpectedDown);
        }
        _wobbleUpdate(input);
        _position = _PositionModeler(
          springMassConstant: params.springMassConstant,
          dragConstant: params.dragConstant,
          startX: input.x,
          startY: input.y,
          startTime: input.time,
        );
        _lastEvent = input;
        _lastCorrected = (input.x, input.y);
        _state.reset(params.maxInputSamples);
        _state.update(input);
        return [
          AdvancedPenModelerResult(
            x: input.x,
            y: input.y,
            vx: 0,
            vy: 0,
            ax: 0,
            ay: 0,
            time: input.time,
            pressure: input.pressure,
          ),
        ];
      case AdvancedPenInputEventType.move:
        final last = _lastEvent;
        if (last == null) {
          throw const AdvancedPenModelerException(AdvancedPenModelerError.unexpectedMove);
        }
        if (input.time - last.time < 0.0) {
          throw const AdvancedPenModelerException(AdvancedPenModelerError.negativeTimeDelta);
        }
        if (input == last) {
          throw const AdvancedPenModelerException(AdvancedPenModelerError.duplicate);
        }
        _state.update(input);
        final nSteps =
            ((input.time - last.time) * params.minOutputRate).ceil();
        if (nSteps > params.maxOutputsPerCall) {
          throw const AdvancedPenModelerException(AdvancedPenModelerError.tooFarApart);
        }
        final start = _lastCorrected!;
        final end = _wobbleUpdate(input);
        final out = _position!
            .updateAlongLinearPath(
              start.$1,
              start.$2,
              last.time,
              end.$1,
              end.$2,
              input.time,
              nSteps,
            )
            .map(
              (p) => AdvancedPenModelerResult(
                x: p.x,
                y: p.y,
                vx: p.vx,
                vy: p.vy,
                ax: p.ax,
                ay: p.ay,
                time: p.time,
                pressure: _state.query(p.x, p.y),
              ),
            )
            .toList();
        _lastEvent = input;
        _lastCorrected = end;
        return out;
      case AdvancedPenInputEventType.up:
        final last = _lastEvent;
        if (last == null) {
          throw const AdvancedPenModelerException(AdvancedPenModelerError.unexpectedUp);
        }
        if (input.time - last.time < 0.0) {
          throw const AdvancedPenModelerException(AdvancedPenModelerError.negativeTimeDelta);
        }
        if (input == last) {
          throw const AdvancedPenModelerException(AdvancedPenModelerError.duplicate);
        }
        final start = _lastCorrected!;
        final moved = _dist(input.x, input.y, last.x, last.y) > 1e-6;
        final out = <AdvancedPenModelerResult>[];
        late final (double, double) end;
        if (moved) {
          _state.update(input);
          final nSteps =
              ((input.time - last.time) * params.minOutputRate).ceil();
          if (nSteps > params.maxOutputsPerCall) {
            throw const AdvancedPenModelerException(AdvancedPenModelerError.tooFarApart);
          }
          end = _wobbleUpdate(input);
          if (nSteps > 0) {
            out.addAll(
              _position!
                  .updateAlongLinearPath(
                    start.$1,
                    start.$2,
                    last.time,
                    end.$1,
                    end.$2,
                    input.time,
                    nSteps,
                  )
                  .map(
                    (p) => AdvancedPenModelerResult(
                      x: p.x,
                      y: p.y,
                      vx: p.vx,
                      vy: p.vy,
                      ax: p.ax,
                      ay: p.ay,
                      time: p.time,
                      pressure: _state.query(p.x, p.y),
                    ),
                  ),
            );
          }
        } else {
          end = start;
        }
        // Settle the spring toward the wobble-corrected anchor so the tail
        // never hooks sideways toward raw lift-off noise.
        out.addAll(
          _position!
              .modelEndOfStroke(
                end.$1,
                end.$2,
                1.0 / params.minOutputRate,
                params.endOfStrokeMaxIterations,
                params.endOfStrokeStoppingDistance,
              )
              .map(
                (p) => AdvancedPenModelerResult(
                  x: p.x,
                  y: p.y,
                  vx: p.vx,
                  vy: p.vy,
                  ax: p.ax,
                  ay: p.ay,
                  time: p.time,
                  pressure: _state.query(p.x, p.y),
                ),
              ),
        );
        if (out.isEmpty) {
          final s = _position!.state;
          out.add(
            AdvancedPenModelerResult(
              x: s.x,
              y: s.y,
              vx: s.vx,
              vy: s.vy,
              ax: s.ax,
              ay: s.ay,
              time: s.time + 1.0 / params.minOutputRate,
              pressure: _state.query(s.x, s.y),
            ),
          );
        }
        _lastEvent = null;
        return out;
    }
  }

  /// Stroke-end prediction: what [update] would append if the last input
  /// had been [AdvancedPenInputEventType.up]. Does not mutate the model.
  List<AdvancedPenModelerResult> predict() {
    final last = _lastEvent;
    final pos = _position;
    if (last == null || pos == null) {
      throw const AdvancedPenModelerException(AdvancedPenModelerError.emptyPrediction);
    }
    final anchor = _lastCorrected ?? (last.x, last.y);
    return pos
        .modelEndOfStroke(
          anchor.$1,
          anchor.$2,
          1.0 / params.minOutputRate,
          params.endOfStrokeMaxIterations,
          params.endOfStrokeStoppingDistance,
        )
        .map(
          (p) => AdvancedPenModelerResult(
            x: p.x,
            y: p.y,
            vx: p.vx,
            vy: p.vy,
            ax: p.ax,
            ay: p.ay,
            time: p.time,
            pressure: _state.query(p.x, p.y),
          ),
        )
        .toList();
  }

  /// Wobble smoother port (`engine.rs::wobble_update`): time-weighted moving
  /// average of position, interpolated towards the raw position by the
  /// average speed mapped through [AdvancedPenModelerParams.wobbleSpeedFloor] /
  /// ceiling. Slow movement is smoothed; fast movement passes through.
  (double, double) _wobbleUpdate(AdvancedPenModelerInput event) {
    if (_wobble.isEmpty) {
      _wobble.addLast(
        _WobbleSample(
          x: event.x,
          y: event.y,
          weightedX: 0,
          weightedY: 0,
          distance: 0,
          duration: 0,
          time: event.time,
        ),
      );
      return (event.x, event.y);
    }
    final prev = _wobble.last;
    final duration = event.time - prev.time;
    final wx = event.x * duration;
    final wy = event.y * duration;
    final distance = _dist(event.x, event.y, prev.x, prev.y);
    _wobble.addLast(
      _WobbleSample(
        x: event.x,
        y: event.y,
        weightedX: wx,
        weightedY: wy,
        distance: distance,
        duration: duration,
        time: event.time,
      ),
    );
    _wobbleSumX += wx;
    _wobbleSumY += wy;
    _wobbleDistanceSum += distance;
    _wobbleDurationSum += duration;

    while (_wobble.isNotEmpty &&
        _wobble.first.time < event.time - params.wobbleTimeout) {
      final front = _wobble.removeFirst();
      _wobbleSumX -= front.weightedX;
      _wobbleSumY -= front.weightedY;
      _wobbleDistanceSum -= front.distance;
      _wobbleDurationSum -= front.duration;
    }

    if (_wobbleDurationSum < 1e-12) return (event.x, event.y);

    final avgX = _wobbleSumX / _wobbleDurationSum;
    final avgY = _wobbleSumY / _wobbleDurationSum;
    final avgSpeed = _wobbleDistanceSum / _wobbleDurationSum;
    final t = _normalize01(
      params.wobbleSpeedFloor,
      params.wobbleSpeedCeiling,
      avgSpeed,
    );
    return (_interp(avgX, event.x, t), _interp(avgY, event.y, t));
  }
}
