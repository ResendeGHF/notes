// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Dart port of the `EventMotionPredictor` stack used with Google Ink
/// (`androidx.input.motionprediction`: `MotionEventPredictor` /
/// `KalmanMotionEventPredictor` / `SinglePointerPredictor` /
/// `PointerKalmanFilter` / `KalmanFilter`, Apache-2.0, (c) AOSP).
///
/// Why a port instead of the native API: prediction runs per input sample
/// (60–120 Hz) inside [Stroke.addPoint]; a MethodChannel round-trip per
/// sample is out of the question, and a pure-Dart model works identically on
/// Android, iOS, desktop and tests.
///
/// Faithfulness notes (verified against androidx-main):
/// - One 4-state Kalman filter per axis (position, velocity, acceleration,
///   jank), tuned with normalized dt = 1, process noise 0.01, measurement
///   noise 1.0. The report rate (ms/sample, averaged over the first 20
///   samples) converts the millisecond horizon into sample steps at predict
///   time — the filter itself never sees wall-clock dt.
/// - Duplicate-position samples within 20 ms are ignored (ARC++ multi-pointer
///   artefact guard); prediction needs >= 4 filter iterations.
/// - Projection applies jank * 0.1 into acceleration, acceleration * 0.5 into
///   velocity, velocity * 1.0 into position per sample step.
/// - Lead distance is confidence-gated: stylus ("accurate tool") predicts at
///   full speed factor whenever moving and scales down with jank in
///   [0.1, 0.2]; finger ramps speed over [0, 2] dp/ms with jank in
///   [0.02, 0.2]. Stationary input predicts nothing (null).
/// - Default strategy is balanced; aggressive forces full confidence, safe
///   forces at least one sample step.
///
/// Intentional deviations (documented, no behavior change in practice):
/// - Zero/negative report rate returns null instead of dividing by zero
///   (upstream sensors never produce it; synthetic callers might).
/// - Orientation/tilt are not tracked: only the (x, y, pressure) tip is
///   consumed by live ink.
/// - The multi-pointer dispatcher is omitted: each [Stroke] owns one
///   single-pointer predictor fed with its own samples, which is exactly the
///   topology upstream ends up with per active pointer.
final class MotionEventPredictor {
  MotionEventPredictor({
    this.strategy = PredictionStrategy.balanced,
    this.predictLift = false,
  });

  // Influence of jank during each prediction sample.
  static const double _jankInfluence = 0.1;

  // Influence of acceleration during each prediction sample.
  static const double _accelerationInfluence = 0.5;

  // Influence of velocity during each prediction sample.
  static const double _velocityInfluence = 1.0;

  // Range of jank values to expect.
  // Low value uses maximum prediction, high value uses no prediction.
  static const double _lowJank = 0.02;
  static const double _highJank = 0.2;
  static const double _accurateLowJank = 0.1;
  static const double _accurateHighJank = 0.2;

  // Range of pen speed to expect (in dp / ms).
  // Low value will not use prediction, high value will use full prediction.
  static const double _lowSpeed = 0.0;
  static const double _highSpeed = 2.0;
  static const double _accurateLowSpeed = 0.0;
  static const double _accurateHighSpeed = 0.0;

  static const double _eventTimeIgnoredThresholdMs = 20;

  // Minimum number of Kalman filter samples needed for predicting.
  static const int _minKalmanFilterIterations = 4;

  // Cap mirroring PredictionEstimator.MAX_PREDICTION_MS: the filter provides
  // solid prediction up to ~25 ms; beyond that errors dominate.
  static const double maxPredictionMs = 32;

  final int strategy;
  final bool predictLift;

  final _PointerKalmanFilter _kalman = _PointerKalmanFilter(0.01, 1.0);

  final _Vec2 _lastPosition = _Vec2.zero();
  bool _hasSample = false;
  double _lastSeenEventTimeMs = 0;  double _lastPredictEventTimeMs = 0;
  final List<double> _reportRates = <double>[];
  double _reportRateMs = 0;

  void reset() {
    _kalman.reset();
    _lastPosition.set(0, 0);
    _hasSample = false;
    _lastSeenEventTimeMs = 0;
    _lastPredictEventTimeMs = 0;
    _reportRates.clear();
    _reportRateMs = 0;
  }

  /// Feeds one input sample. Times are wall-clock milliseconds (any
  /// monotonic base); only deltas feed the report-rate estimate.
  void record(double x, double y, double pressure, double timeMs) {
    if (x == _lastPosition.x &&
        y == _lastPosition.y &&
        (timeMs <= (_lastSeenEventTimeMs + _eventTimeIgnoredThresholdMs))) {
      // Reduce Kalman filter jank by ignoring input events with (near-)
      // identical coordinates and event time as the previous input event.
      return;
    }

    _kalman.update(x, y, pressure);
    _lastPosition.set(x, y);
    _hasSample = true;

    // Average report rate over the first 20 samples. Most sensors do not
    // report at an even interval, so this is only an estimate.
    if (_reportRates.length < 20) {
      if (_lastSeenEventTimeMs > 0) {
        final dt = timeMs - _lastSeenEventTimeMs;
        _reportRates.add(dt);
        var sum = 0.0;
        for (final rate in _reportRates) {
          sum += rate;
        }
        _reportRateMs = sum / _reportRates.length;
      }
    }
    _lastSeenEventTimeMs = timeMs;
  }

  /// Last recorded (fitted) sample position, null until the first record.
  /// Lets callers anchor the projected polyline onto their own tip.
  Offset? get lastRecordedPosition =>
      _hasSample ? Offset(_lastPosition.x, _lastPosition.y) : null;

  /// Current Kalman velocity estimate, in position units per sample.
  /// Lets callers compare predicted travel against committed travel
  /// (turn-aware gating) without running a full projection.
  Offset get velocity => Offset(_kalman.velocityX, _kalman.velocityY);

  /// Projects the pointer [predictionTargetMs] milliseconds into the future.
  ///
  /// Returns the projected sample polyline — one tip per sample step, like
  /// the history batches of upstream's predicted `MotionEvent`. Empty when
  /// no trustworthy prediction exists (cold filter, stationary or lifting
  /// pointer): the caller renders committed samples only. The polyline is
  /// transient: never committed, replaced by the next real sample.
  ///
  /// Returning every step (instead of just the endpoint) matters for
  /// rendering: the live outline follows the Kalman curve instead of
  /// stretching a single ruler-straight chord to a far tip.
  List<PredictedTip> predictPolyline({
    required double predictionTargetMs,
    bool accurateTool = true,
  }) {
    if (_reportRateMs <= 0) return const [];
    if (_kalman.numIterations < _minKalmanFilterIterations) {
      return const [];
    }

    var px = _lastPosition.x;
    var py = _lastPosition.y;
    var vx = _kalman.velocityX;
    var vy = _kalman.velocityY;
    var ax = _kalman.accelerationX;
    var ay = _kalman.accelerationY;
    final jx = _kalman.jankX;
    final jy = _kalman.jankY;

    var pressure = _kalman.pressure;
    final pressureChange = _kalman.pressureChange;

    // Adjust prediction distance by filter confidence and movement speed.
    final speedAbs =
        math.sqrt(vx * vx + vy * vy) / _reportRateMs;
    final double lowSpeed, highSpeed, lowJank, highJank;
    if (accurateTool) {
      lowSpeed = _accurateLowSpeed;
      highSpeed = _accurateHighSpeed;
      lowJank = _accurateLowJank;
      highJank = _accurateHighJank;
    } else {
      lowSpeed = _lowSpeed;
      highSpeed = _highSpeed;
      lowJank = _lowJank;
      highJank = _highJank;
    }
    final speedFactor = _normalizeRangeCapped(speedAbs, lowSpeed, highSpeed);
    final jankAbs = math.sqrt(jx * jx + jy * jy);
    final jankFactor = 1.0 - _normalizeRange(jankAbs, lowJank, highJank);
    var confidenceFactor = speedFactor * jankFactor;

    if (strategy == PredictionStrategy.aggressive) {
      // Very confident.
      confidenceFactor = 1;
    }

    // Project physical state of the pen into the future, one sample step
    // per iteration (the filter is tuned with normalized dt = 1).
    var predictionTargetInSamples =
        (predictionTargetMs / _reportRateMs * confidenceFactor).ceil();

    if (strategy == PredictionStrategy.safe) {
      // A single prediction step is very accurate.
      predictionTargetInSamples =
          math.max(predictionTargetInSamples, 1);
    }

    var predictedEventTimeMs = _lastSeenEventTimeMs;
    var nextPredictedEventTimeMs = _lastSeenEventTimeMs + _reportRateMs;
    final tips = <PredictedTip>[];
    for (var i = 0;
        i < predictionTargetInSamples ||
            (nextPredictedEventTimeMs <= _lastPredictEventTimeMs);
        i++) {
      ax += jx * _jankInfluence;
      ay += jy * _jankInfluence;
      vx += ax * _accelerationInfluence;
      vy += ay * _accelerationInfluence;
      px += vx * _velocityInfluence;
      py += vy * _velocityInfluence;
      pressure += pressureChange;

      // Keep pressure in the valid range.
      pressure = pressure.clamp(0.0, 1.0);

      // Abort prediction if the pen is to be lifted.
      if (predictLift &&
          pressure < 0.1 &&
          nextPredictedEventTimeMs > _lastPredictEventTimeMs) {
        break;
      }

      tips.add(PredictedTip(x: px, y: py, pressure: pressure));
      // Keep track of the last predicted time.
      predictedEventTimeMs = nextPredictedEventTimeMs;

      // Prepare for next iteration.
      nextPredictedEventTimeMs += _reportRateMs;
    }
    // Store the last predicted time (even when nothing was produced).
    _lastPredictEventTimeMs = predictedEventTimeMs;

    return tips;
  }

  /// [x] clamped into [0, 1] over [min, max]; replicates the upstream
  /// 0/0-range semantics: any motion predicts fully, rest predicts nothing.
  static double _normalizeRangeCapped(double x, double min, double max) {
    if ((max - min).abs() < 1e-12) {
      return x > 0 ? 1.0 : 0.0;
    }
    return _normalizeRange(x, min, max);
  }

  static double _normalizeRange(double x, double min, double max) {
    final normalized = (x - min) / (max - min);
    return math.min(1.0, math.max(normalized, 0.0));
  }

  /// Filter internals for tests/diagnostics.
  @visibleForTesting
  Map<String, double> debugInternals() {
    final vx = _kalman.velocityX;
    final vy = _kalman.velocityY;
    final jx = _kalman.jankX;
    final jy = _kalman.jankY;
    final speedAbs = _reportRateMs > 0
        ? math.sqrt(vx * vx + vy * vy) / _reportRateMs
        : double.nan;
    final jankAbs = math.sqrt(jx * jx + jy * jy);
    return {
      'iterations': _kalman.numIterations.toDouble(),
      'reportRateMs': _reportRateMs,
      'vx': vx,
      'vy': vy,
      'ax': _kalman.accelerationX,
      'ay': _kalman.accelerationY,
      'jx': jx,
      'jy': jy,
      'speedAbs': speedAbs,
      'jankAbs': jankAbs,
    };
  }
}

  /// Prediction strategy, mirroring `Configuration.STRATEGY_*` upstream.
abstract final class PredictionStrategy {
  static const int balanced = 0;
  static const int safe = 1;
  static const int aggressive = 2;
}

/// Transient predicted tip: rendered live, never committed.
final class PredictedTip {
  const PredictedTip({
    required this.x,
    required this.y,
    required this.pressure,
  });

  final double x;
  final double y;
  final double pressure;

  Offset get offset => Offset(x, y);
}

final class _Vec2 {
  _Vec2(this.x, this.y);
  _Vec2.zero() : x = 0, y = 0;

  double x;
  double y;

  void set(double nx, double ny) {
    x = nx;
    y = ny;
  }
}

/// One 4-state Kalman filter per axis (position, velocity, acceleration,
/// jank), following http://filterpy.readthedocs.io/en/latest/.
///
/// State transition (normalized dt = 1, from basic physics):
///   new_x = x + v + a/2 + jank*0.16
///   new_v = v + a + jank/2
///   new_a = a + jank
///   new_jank = jank
/// System noise is modeled as a noisy force on the pointer.
final class _PointerKalmanFilter {
  _PointerKalmanFilter(this.sigmaProcess, this.sigmaMeasurement)
      : _x = _AxisKalmanFilter(sigmaProcess, sigmaMeasurement),
        _y = _AxisKalmanFilter(sigmaProcess, sigmaMeasurement),
        _p = _AxisKalmanFilter(sigmaProcess, sigmaMeasurement);

  final double sigmaProcess;
  final double sigmaMeasurement;

  final _AxisKalmanFilter _x;
  final _AxisKalmanFilter _y;
  final _AxisKalmanFilter _p;

  int _numIterations = 0;
  int get numIterations => _numIterations;

  double get velocityX => _x.state[1];
  double get velocityY => _y.state[1];
  double get accelerationX => _x.state[2];
  double get accelerationY => _y.state[2];
  double get jankX => _x.state[3];
  double get jankY => _y.state[3];
  double get pressure => _p.state[0];
  double get pressureChange => _p.state[1];

  void reset() {
    _x.reset();
    _y.reset();
    _p.reset();
    _numIterations = 0;
  }

  void update(double x, double y, double pressure) {
    if (_numIterations == 0) {
      _x.seed(x);
      _y.seed(y);
      _p.seed(pressure);
    } else {
      _x.step(x);
      _y.step(y);
      _p.step(pressure);
    }
    _numIterations += 1;
  }
}

final class _AxisKalmanFilter {
  _AxisKalmanFilter(double sigmaProcess, double sigmaMeasurement)
      : _sigmaProcess = sigmaProcess,
        _sigmaMeasurement = sigmaMeasurement,
        state = List<double>.filled(4, 0),
        _cov = _Matrix.identity(4) {
    // State transition matrix F (row-major, dt = 1).
    _f = _Matrix(4, 4)
      ..setValues(const [
        1.0, 1.0, 0.5, 0.16,
        0.0, 1.0, 1.0, 0.5,
        0.0, 0.0, 1.0, 1.0,
        0.0, 0.0, 0.0, 1.0,
      ]);
    // Process noise Q = (g * gT) * sigmaProcess, g = [0.16, 0.5, 1, 1].
    const g = [0.16, 0.5, 1.0, 1.0];
    _q = _Matrix(4, 4);
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 4; j++) {
        _q.set(i, j, g[i] * g[j] * sigmaProcess);
      }
    }
  }

  final double _sigmaProcess;
  final double _sigmaMeasurement;

  /// Current state estimate [position, velocity, acceleration, jank].
  final List<double> state;
  final _Matrix _cov;
  late final _Matrix _f;
  late final _Matrix _q;

  void reset() {
    state.fillRange(0, 4, 0);
    _cov.setIdentity();
  }

  void seed(double value) {
    state[0] = value;
  }

  /// One predict + update cycle for measurement [z].
  void step(double z) {
    // Predict: x = F * x; P = F * P * F^T + Q.
    final px = _matVec(_f, state);
    final fp = _Matrix.multiply(_f, _cov);
    final fpft = _Matrix.multiplyTransposeRight(fp, _f);
    for (var i = 0; i < 4; i++) {
      state[i] = px[i];
      for (var j = 0; j < 4; j++) {
        _cov.set(i, j, fpft.get(i, j) + _q.get(i, j));
      }
    }
    // Update with 1-D measurement: y = z - x[0].
    final y = z - state[0];
    // S = P[0][0] + R (H = [1,0,0,0] collapses the products to scalars).
    final s = _cov.get(0, 0) + _sigmaMeasurement;
    if (s.abs() < 1e-12) return;
    // K[i] = P[i][0] / S, snapshot before mutating P (upstream resolves
    // K*H*P into a separate buffer first; reading the live row 0 here
    // would reuse already-updated entries for rows 1..3).
    final gain = List<double>.generate(4, (i) => _cov.get(i, 0) / s);
    final row0 = List<double>.generate(4, (j) => _cov.get(0, j));
    for (var i = 0; i < 4; i++) {
      state[i] += gain[i] * y;
    }
    // P -= K * H * P  <=>  P[i][j] -= K[i] * P[0][j].
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 4; j++) {
        _cov.set(i, j, _cov.get(i, j) - gain[i] * row0[j]);
      }
    }
  }

  static List<double> _matVec(_Matrix m, List<double> v) {
    final out = List<double>.filled(4, 0);
    for (var i = 0; i < 4; i++) {
      var s = 0.0;
      for (var k = 0; k < 4; k++) {
        s += m.get(i, k) * v[k];
      }
      out[i] = s;
    }
    return out;
  }
}

/// Minimal row-major matrix for the fixed 4-D filter math above.
///
/// The generic update path of [KalmanFilter] upstream inverts only the 1x1
/// innovation covariance here, so [inverse] is unnecessary: [step] works the
/// scalar 1-D-measurement equations directly (identical arithmetic, no
/// per-sample allocation beyond small fixed lists).
final class _Matrix {
  _Matrix(this.rows, this.cols) : _m = List<double>.filled(rows * cols, 0);

  final int rows;
  final int cols;
  final List<double> _m;

  factory _Matrix.identity(int size) {
    final m = _Matrix(size, size);
    m.setIdentity();
    return m;
  }

  double get(int i, int j) => _m[i * cols + j];
  void set(int i, int j, double v) {
    _m[i * cols + j] = v;
  }

  void setValues(List<double> values) {
    for (var i = 0; i < values.length && i < _m.length; i++) {
      _m[i] = values[i];
    }
  }

  void setIdentity() {
    _m.fillRange(0, _m.length, 0);
    final n = math.min(rows, cols);
    for (var i = 0; i < n; i++) {
      set(i, i, 1);
    }
  }

  /// C = A * B (fresh result).
  static _Matrix multiply(_Matrix a, _Matrix b) {
    assert(a.cols == b.rows);
    final c = _Matrix(a.rows, b.cols);
    for (var i = 0; i < a.rows; i++) {
      for (var j = 0; j < b.cols; j++) {
        var s = 0.0;
        for (var k = 0; k < a.cols; k++) {
          s += a.get(i, k) * b.get(k, j);
        }
        c.set(i, j, s);
      }
    }
    return c;
  }

  /// C = A * B^T (fresh result).
  static _Matrix multiplyTransposeRight(_Matrix a, _Matrix b) {
    assert(a.cols == b.cols);
    final c = _Matrix(a.rows, b.rows);
    for (var i = 0; i < a.rows; i++) {
      for (var j = 0; j < b.rows; j++) {
        var s = 0.0;
        for (var k = 0; k < a.cols; k++) {
          s += a.get(i, k) * b.get(j, k);
        }
        c.set(i, j, s);
      }
    }
    return c;
  }
}
