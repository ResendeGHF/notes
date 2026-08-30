// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:logging/logging.dart';

class PerfTiming {
  static const bool _enabledByDefine = bool.fromEnvironment(
    'SABER_TIMING_PROFILER',
    defaultValue: false,
  );

  static bool get enabled => kDebugMode && _enabledByDefine;
  static final Logger _log = Logger('PerfTiming');

  static int _vaultAutosaveWindows = 0;
  static int _vaultAutosaveDroppedFrames = 0;
  static int _vaultAutosaveSlowFrames = 0;
  static bool _frameCallbackRegistered = false;

  static PerfSpan? start(
    String name, {
    Map<String, Object?>? fields,
  }) {
    if (!enabled) return null;
    return PerfSpan._(name, fields ?? const {});
  }

  static String formatFields(Map<String, Object?> fields) {
    if (fields.isEmpty) return '';
    return fields.entries.map((e) => '${e.key}=${e.value}').join(' ');
  }

  static void logLine(String message) {
    if (!enabled) return;
    _log.info(message);
  }

  /// Begin capturing [FrameTiming] while a vault autosave is in flight.
  /// Always cheap; logs only when [enabled] or when frames are dropped.
  static void beginVaultAutosaveWindow() {
    _ensureFrameCallback();
    _vaultAutosaveWindows++;
  }

  static void endVaultAutosaveWindow() {
    if (_vaultAutosaveWindows > 0) _vaultAutosaveWindows--;
    if (_vaultAutosaveWindows == 0 &&
        (_vaultAutosaveDroppedFrames > 0 || _vaultAutosaveSlowFrames > 0)) {
      final msg =
          '[PERF][VaultAutosave.frames] dropped=$_vaultAutosaveDroppedFrames '
          'slow=$_vaultAutosaveSlowFrames';
      if (enabled || _vaultAutosaveDroppedFrames > 0) {
        _log.info(msg);
      }
      _vaultAutosaveDroppedFrames = 0;
      _vaultAutosaveSlowFrames = 0;
    }
  }

  static void _ensureFrameCallback() {
    if (_frameCallbackRegistered) return;
    _frameCallbackRegistered = true;
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
  }

  static void _onFrameTimings(List<FrameTiming> timings) {
    if (_vaultAutosaveWindows <= 0) return;
    for (final t in timings) {
      final totalUs = t.totalSpan.inMicroseconds;
      // ~1 frame at 120Hz is 8333µs; count as dropped if build+raster > 16.6ms.
      if (totalUs > 16667) {
        _vaultAutosaveDroppedFrames++;
      } else if (totalUs > 10000) {
        _vaultAutosaveSlowFrames++;
      }
    }
  }
}

class PerfSpan {
  PerfSpan._(this.name, this._baseFields) {
    PerfTiming.logLine(
      '[perf:start] $name ${PerfTiming.formatFields(_baseFields)}',
    );
  }

  final String name;
  final Map<String, Object?> _baseFields;
  final Stopwatch _sw = Stopwatch()..start();

  void checkpoint(
    String label, {
    Map<String, Object?>? fields,
  }) {
    final merged = <String, Object?>{
      ..._baseFields,
      if (fields != null) ...fields,
    };
    PerfTiming.logLine(
      '[perf:checkpoint] $name::$label ${_sw.elapsedMilliseconds}ms ${PerfTiming.formatFields(merged)}',
    );
  }

  void end({
    Map<String, Object?>? fields,
  }) {
    final merged = <String, Object?>{
      ..._baseFields,
      if (fields != null) ...fields,
    };
    PerfTiming.logLine(
      '[perf:end] $name ${_sw.elapsedMilliseconds}ms ${PerfTiming.formatFields(merged)}',
    );
  }
}
