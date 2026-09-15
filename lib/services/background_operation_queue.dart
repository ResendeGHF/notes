// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:saber/services/background_operation_lock.dart';

enum BackgroundOperationKind { importFile, exportFile, backup, restoreBackup }

class BackgroundOperationUiState {
  const BackgroundOperationUiState({
    this.kind,
    this.headline = '',
    this.detail = '',
    this.progress = 0.0,
    this.indeterminate = false,
  });

  final BackgroundOperationKind? kind;
  final String headline;
  final String detail;
  final double progress;
  final bool indeterminate;

  bool get isActive => kind != null;

  static const idle = BackgroundOperationUiState();
}

typedef BackgroundProgressCallback =
    void Function(double progress, String message, {bool indeterminate});

class BackgroundOperationQueue {
  BackgroundOperationQueue._();
  static final instance = BackgroundOperationQueue._();

  static final _log = Logger('BackgroundOperationQueue');

  static final ValueNotifier<BackgroundOperationUiState> uiState =
      ValueNotifier(BackgroundOperationUiState.idle);

  final Queue<Future<void> Function()> _pending = Queue();
  bool _draining = false;

  /// Run [work] after all previously enqueued tasks complete. Progress and
  /// headlines are published to [uiState] for the status strip / navbar.
  Future<T> enqueue<T>({
    required BackgroundOperationKind kind,
    required String headline,
    required String initialDetail,
    required Future<T> Function(BackgroundProgressCallback onProgress) work,
  }) async {
    final completer = Completer<T>();
    _pending.add(() async {
      try {
        await BackgroundOperationLock.runSerialized(() async {
          void onProgress(
            double progress,
            String message, {
            bool indeterminate = false,
          }) {
            uiState.value = BackgroundOperationUiState(
              kind: kind,
              headline: headline,
              detail: message,
              progress: progress,
              indeterminate: indeterminate,
            );
          }

          onProgress(0, initialDetail, indeterminate: true);
          try {
            final result = await work(onProgress);
            if (!completer.isCompleted) {
              completer.complete(result);
            }
          } catch (e, st) {
            if (!completer.isCompleted) {
              completer.completeError(e, st);
            }
          }
        });
      } catch (e, st) {
        _log.severe('Background operation aborted before start: $e', e, st);
        if (!completer.isCompleted) {
          completer.completeError(e, st);
        }
      }
    });
    unawaited(_drain());
    return completer.future;
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_pending.isNotEmpty) {
        try {
          await _pending.removeFirst().call();
        } catch (e, st) {
          _log.severe('Queued background task failed: $e', e, st);
        }
        uiState.value = BackgroundOperationUiState.idle;
      }
    } finally {
      _draining = false;
    }
  }
}
