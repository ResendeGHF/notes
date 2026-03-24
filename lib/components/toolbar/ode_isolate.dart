// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'package:saber/services/math_engine/math_engine.dart';

Map<String, dynamic> runOdeStepsInIsolate(Map<String, dynamic> params) {
  final expressions = List<String>.from(params['expressions'] as List);
  final methodStr = params['method'] as String;
  final lastState = List<double>.from(params['lastState'] as List);
  final lastT = params['lastT'] as double;
  final h = (params['h'] as num).toDouble();
  final stepsPerTick = params['stepsPerTick'] as int;
  final tolerance = (params['tolerance'] as num).toDouble();
  var previousStableSteps = params['previousStableSteps'] as int;

  final newSamples = <Map<String, dynamic>>[];
  var currentState = List<double>.from(lastState);
  var currentT = lastT;
  var converged = false;

  final parser = ComplexParser();

  String normalize(String input) {
    return input
        .trim()
        .replaceAll('×', '*')
        .replaceAll('÷', '/')
        .replaceAll('π', 'pi')
        .replaceAll('√', 'sqrt')
        .toLowerCase()
        .replaceAll(' ', '');
  }

  List<double> evaluateDerivative(List<double> state, double t) {
    final vars = <String, Complex>{
      't': Complex(t),
      'x': Complex(state[0]),
      'x1': Complex(state[0]),
      'y': Complex(state.length > 1 ? state[1] : 0),
      'x2': Complex(state.length > 1 ? state[1] : 0),
      'z': Complex(state.length > 2 ? state[2] : 0),
      'x3': Complex(state.length > 2 ? state[2] : 0),
    };
    final derivatives = <double>[];
    for (final expr in expressions) {
      final parsed = parser.evaluate(normalize(expr), variables: vars);
      derivatives.add(parsed.real);
    }
    return derivatives;
  }

  List<double> vecAddScaled(List<double> a, List<double> b, double scale) {
    return List<double>.generate(a.length, (i) => a[i] + (b[i] * scale));
  }

  List<double> vecLinearCombination(
    List<double> a,
    List<double> b,
    List<double> c,
    List<double> d,
  ) {
    return List<double>.generate(
      a.length,
      (i) => a[i] + 2 * b[i] + 2 * c[i] + d[i],
    );
  }

  List<double> midpointStep(List<double> state, double t, double stepH) {
    final k1 = evaluateDerivative(state, t);
    final mid = vecAddScaled(state, k1, 0.5 * stepH);
    final k2 = evaluateDerivative(mid, t + 0.5 * stepH);
    return vecAddScaled(state, k2, stepH);
  }

  List<double> nextState(List<double> state, double t, double stepH) {
    switch (methodStr) {
      case 'euler':
        return vecAddScaled(
          state,
          evaluateDerivative(state, t),
          stepH,
        );
      case 'eulerCromer':
        final k1 = evaluateDerivative(state, t);
        final predictor = vecAddScaled(state, k1, stepH);
        final k2 = evaluateDerivative(predictor, t + stepH);
        return vecAddScaled(state, k2, stepH);
      case 'verlet':
        return midpointStep(state, t, stepH);
      case 'rungeKutta4':
        final k1 = evaluateDerivative(state, t);
        final k2 = evaluateDerivative(
          vecAddScaled(state, k1, 0.5 * stepH),
          t + 0.5 * stepH,
        );
        final k3 = evaluateDerivative(
          vecAddScaled(state, k2, 0.5 * stepH),
          t + 0.5 * stepH,
        );
        final k4 = evaluateDerivative(
          vecAddScaled(state, k3, stepH),
          t + stepH,
        );
        final weighted = vecLinearCombination(k1, k2, k3, k4);
        return vecAddScaled(state, weighted, stepH / 6.0);
      case 'forestRuth':
        final cbrt2 = math.pow(2.0, 1.0 / 3.0).toDouble();
        final w1 = 1.0 / (2.0 - cbrt2);
        final w0 = -cbrt2 / (2.0 - cbrt2);
        var tCursor = t;
        var s1 = midpointStep(state, tCursor, w1 * stepH);
        tCursor += w1 * stepH;
        s1 = midpointStep(s1, tCursor, w0 * stepH);
        tCursor += w0 * stepH;
        s1 = midpointStep(s1, tCursor, w1 * stepH);
        return s1;
      default:
        return midpointStep(state, t, stepH);
    }
  }

  double deltaNorm(List<double> next, List<double> prev) {
    double sum = 0;
    for (int i = 0; i < next.length; i++) {
      final d = next[i] - prev[i];
      sum += d * d;
    }
    return math.sqrt(sum);
  }

  bool stateIsFinite(List<double> state) {
    for (final v in state) {
      if (!v.isFinite) return false;
    }
    return true;
  }

  try {
    for (int step = 0; step < stepsPerTick; step++) {
      List<double> nextStateVal;
      nextStateVal = nextState(currentState, currentT, h);

      if (!stateIsFinite(nextStateVal)) {
        return {
          'success': false,
          'error': 'Diverged (non-finite values). Stopped.',
          'newSamples': newSamples,
          'converged': false,
          'stableSteps': 0,
        };
      }

      currentT += h;
      newSamples.add({'t': currentT, 'state': nextStateVal});

      final delta = deltaNorm(nextStateVal, currentState);
      if (delta < tolerance) {
        previousStableSteps++;
      } else {
        previousStableSteps = 0;
      }

      if (previousStableSteps >= 12) {
        converged = true;
        break;
      }

      currentState = nextStateVal;
    }

    return {
      'success': true,
      'error': null,
      'newSamples': newSamples,
      'converged': converged,
      'stableSteps': previousStableSteps,
    };
  } catch (_) {
    return {
      'success': false,
      'error': 'Solver error while evaluating equation',
      'newSamples': newSamples,
      'converged': false,
      'stableSteps': 0,
    };
  }
}
