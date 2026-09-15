// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:worker_manager/worker_manager.dart';

/// Runs [fn] on the persistent [workerManager] pool when available, otherwise
/// falls back to [compute] so tests and early startup still work.
Future<R> vaultWorkerRun<R, A>(R Function(A arg) fn, A arg) async {
  try {
    return await workerManager.execute(() => fn(arg));
  } catch (_) {
    return compute(fn, arg);
  }
}

/// Same as [vaultWorkerRun] but for no-arg top-level/static work that already
/// closed over sendable state via a thunk.
Future<R> vaultWorkerExecute<R>(R Function() fn) async {
  try {
    return await workerManager.execute(fn);
  } catch (_) {
    return Future<R>(() => fn());
  }
}
