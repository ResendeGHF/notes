// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

// Parity check: Dart port vs actual Rust ink-stroke-modeler-rs output.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/stroke_geometry/advanced_pen_modeler.dart';
import 'package:saber/data/stroke_geometry/advanced_pen_options.dart';

void main() {
  test('Dart port matches Rust ink-stroke-modeler-rs', () {
    final expected = (jsonDecode(
      File('test/data/stroke_geometry/advanced_rust_expected.json').readAsStringSync(),
    ) as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final m = AdvancedPenStrokeModeler(AdvancedPenModelerParams.advancedDefaults);
    final inputs = [
      (AdvancedPenInputEventType.down, 0.0, 0.0, 0.0, 0.5),
      (AdvancedPenInputEventType.move, 10.0, 2.0, 1.0 / 60.0, 0.6),
      (AdvancedPenInputEventType.move, 20.0, 0.0, 2.0 / 60.0, 0.7),
      (AdvancedPenInputEventType.move, 30.0, 5.0, 3.0 / 60.0, 0.8),
    ];
    final actual = <Map<String, dynamic>>[];
    for (final (et, x, y, t, p) in inputs) {
      final res = m.update(
        AdvancedPenModelerInput(eventType: et, x: x, y: y, time: t, pressure: p),
      );
      for (final r in res) {
        actual.add({'x': r.x, 'y': r.y, 't': r.time, 'p': r.pressure});
      }
    }
    for (final r in m.predict()) {
      actual.add(
          {'x': r.x, 'y': r.y, 't': r.time, 'p': r.pressure, 'pred': true});
    }
    for (final r in m.update(
      const AdvancedPenModelerInput(
        eventType: AdvancedPenInputEventType.up,
        x: 30.0,
        y: 5.0,
        time: 4.0 / 60.0,
        pressure: 0.8,
      ),
    )) {
      actual.add(
          {'x': r.x, 'y': r.y, 't': r.time, 'p': r.pressure, 'up': true});
    }

    expect(actual.length, expected.length,
        reason: 'output count must match Rust');
    for (var i = 0; i < expected.length; i++) {
      final e = expected[i];
      final a = actual[i];
      expect(a['x'], closeTo(e['x'] as double, 1e-9), reason: 'x[$i]');
      expect(a['y'], closeTo(e['y'] as double, 1e-9), reason: 'y[$i]');
      expect(a['t'], closeTo(e['t'] as double, 1e-9), reason: 't[$i]');
      expect(a['p'], closeTo(e['p'] as double, 1e-9), reason: 'p[$i]');
    }
  });
}
