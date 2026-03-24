// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

class PerfTiming {
  static const bool _enabledByDefine = bool.fromEnvironment(
    'SABER_TIMING_PROFILER',
    defaultValue: false,
  );

  static bool get enabled => kDebugMode && _enabledByDefine;
  static final Logger _log = Logger('PerfTiming');

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
