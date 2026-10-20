// SPDX-License-Identifier: GPL-3.0-or-later
//
// On-device performance instrumentation, enabled with
// `--dart-define=saberDebugLogs=true` (release-mode performance, INFO logs).
// Emits per-second frame statistics (UI build / raster thread) plus
// timestamped MARK lines so an adb logcat capture can reconstruct the open
// and scroll timelines. Zero overhead when disabled.

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:logging/logging.dart';

class PerfProbe {
  PerfProbe._();

  static final Logger _log = Logger('PerfProbe');

  /// Mirrors the saberDebugLogs gate in main.dart. The probe only installs
  /// when INFO logs are enabled, so production builds carry no callbacks.
  static const bool enabled = bool.fromEnvironment('saberDebugLogs');

  static bool _installed = false;
  static final int _t0 = DateTime.now().millisecondsSinceEpoch;
  static final List<FrameTiming> _window = <FrameTiming>[];

  static void install() {
    if (!enabled || _installed) return;
    _installed = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    Timer.periodic(const Duration(seconds: 1), (_) => _report());
    _log.info('PROBE installed');
  }

  /// Timestamped event marker: `PROBE MARK <label> t=<ms since install>`.
  static void mark(String label) {
    if (!enabled) return;
    final t = DateTime.now().millisecondsSinceEpoch - _t0;
    _log.info('PROBE MARK $label t=${t}ms');
  }

  static void _onTimings(List<FrameTiming> timings) {
    _window.addAll(timings);
    // Safety cap: never let a paused window grow unbounded.
    if (_window.length > 4096) {
      _window.removeRange(0, _window.length - 4096);
    }
  }

  /// Per-second call counters. Call sites use these to attribute continuous
  /// repaints to the code path that schedules them: the report prints every
  /// non-zero counter, so a 91 fps idle shows exactly which builds/paints
  /// are running (and which chained-scheduling branch re-arms them).
  static final Map<String, int> _hits = <String, int>{};

  /// Counts one occurrence of [key] for the current second.
  static void hit(String key) {
    if (!enabled) return;
    _hits[key] = (_hits[key] ?? 0) + 1;
  }

  /// Marks [label] once per unique [key] (per process).
  static final Set<String> _marksOnce = <String>{};

  static void markOnce(String key, String label) {
    if (!enabled) return;
    if (!_marksOnce.add(key)) return;
    mark(label);
  }

  static void _report() {
    if (!enabled || _window.isEmpty) return;
    final n = _window.length;
    final build = List<int>.generate(
      n,
      (i) => _window[i].buildDuration.inMicroseconds,
    )..sort();
    final raster = List<int>.generate(
      n,
      (i) => _window[i].rasterDuration.inMicroseconds,
    )..sort();
    int sum(List<int> v) => v.fold<int>(0, (a, b) => a + b);
    int pct(List<int> v, double p) => v[(p * (v.length - 1)).round()];
    double ms(int us) => us / 1000.0;    final slowBuild = build.where((us) => us > 8333).length;
    final slowRaster = raster.where((us) => us > 8333).length;
    final hits = _hits.entries
        .where((e) => e.value > 0)
        .map((e) => '${e.key}=${e.value}')
        .join(' ');
    _hits.clear();
    _log.info(
      'PROBE 1s frames=$n '
      'buildAvg=${ms(sum(build) ~/ n).toStringAsFixed(1)} '
      'buildP90=${ms(pct(build, 0.90)).toStringAsFixed(1)} '
      'buildMax=${ms(build.last).toStringAsFixed(1)} '
      'rasterP90=${ms(pct(raster, 0.90)).toStringAsFixed(1)} '
      'rasterMax=${ms(raster.last).toStringAsFixed(1)} '
      'slowBuild=$slowBuild slowRaster=$slowRaster'
      '${hits.isEmpty ? '' : ' $hits'}',
    );
    _window.clear();
  }
}
