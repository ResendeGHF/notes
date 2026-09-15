// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

bool _remoteProcessLikelyAlive(int processId) {
  if (processId <= 0) return false;
  if (Platform.isAndroid || Platform.isLinux) {
    try {
      return Directory('/proc/$processId').existsSync();
    } catch (_) {
      return true;
    }
  }
  if (Platform.isMacOS || Platform.isIOS) {
    try {
      final r = Process.runSync('kill', ['-0', '$processId']);
      return r.exitCode == 0;
    } catch (_) {
      return true;
    }
  }
  if (Platform.isWindows) {
    try {
      final r = Process.runSync('tasklist', ['/FI', 'PID eq $processId', '/NH']);
      if (r.exitCode != 0) return false;
      final out = (r.stdout as String).toString().trim();
      return out.isNotEmpty && !out.toLowerCase().contains('no tasks');
    } catch (_) {
      return true;
    }
  }
  return true;
}

/// Cross-isolate / cross-entry-point serialization for heavy background work
/// using an **exclusive lock file** (atomic `create(exclusive: true)`), so the
/// UI isolate, worker isolates, and the Workmanager callback cannot run import,
/// export, or backup bodies concurrently.
///
/// [flock]/[RandomAccessFile.lock] is often **per-process** on POSIX; a second
/// Dart isolate in the same VM would not block. A dedicated lock **path** with
/// exclusive create works across all callers that share the data directory.
class BackgroundOperationLock {
  BackgroundOperationLock._();

  static final _log = Logger('BackgroundOperationLock');
  static const _lockFileName = '.saber_background_ops.lock';

  /// If a lock file survives a hard kill, it could block forever. After this
  /// age we allow one cooperative break-and-retry (tune for very long exports).
  static const _staleLockMaxAge = Duration(hours: 24);

  static String? _lockPath;

  static void configure(String documentsDirectory) {
    _lockPath = p.join(documentsDirectory, _lockFileName);
  }

  /// Clears a leftover lock from a crashed or killed process so import/export
  /// are not stuck forever (see [runSerialized] wait loop).
  static Future<void> recoverOrphanAtStartup() async {
    if (kIsWeb) return;
    try {
      final token = File(_requirePath());
      if (!await token.exists()) return;
      if (await _tryBreakOrphanLock(token)) {
        _log.info('Removed orphan background lock at startup');
        return;
      }
      if (await _tryRemoveStaleLock(token)) {
        _log.info('Removed stale background lock at startup');
      }
    } on StateError {
      // configure not done yet
    } on FileSystemException catch (e, st) {
      _log.fine('Startup lock recovery skipped: $e', e, st);
    }
  }

  static String _requirePath() {
    final path = _lockPath;
    if (path == null || path.isEmpty) {
      throw StateError(
        'BackgroundOperationLock.configure(documentsDirectory) must run after '
        'FileManager.init',
      );
    }
    return path;
  }

  static Future<T> runSerialized<T>(Future<T> Function() operation) async {
    if (kIsWeb) {
      return operation();
    }

    final token = File(_requirePath());
    try {
      await token.parent.create(recursive: true);
    } on FileSystemException catch (e, st) {
      _log.severe('Could not create lock parent dir: $e', e, st);
      rethrow;
    }

    while (true) {
      try {
        await token.create(exclusive: true);
        await token.writeAsString(
          '${pid}\n${DateTime.now().millisecondsSinceEpoch}\n',
        );
        break;
      } on FileSystemException catch (e) {
        _log.fine('Lock file busy or error: $e');
        if (await _tryBreakOrphanLock(token)) {
          continue;
        }
        if (await _tryRemoveStaleLock(token)) {
          continue;
        }
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    }

    try {
      return await operation();
    } finally {
      try {
        if (token.existsSync()) {
          await token.delete();
        }
      } on FileSystemException catch (e) {
        _log.fine('Lock delete: $e');
      }
    }
  }

  static Future<bool> _tryBreakOrphanLock(File token) async {
    try {
      if (!await token.exists()) return false;
      final content = await token.readAsString();
      final firstLine = content.split('\n').first.trim();
      final lockPid = int.tryParse(firstLine);
      if (lockPid == null) {
        _log.warning('Removing corrupt background lock (unreadable PID)');
        await token.delete();
        return true;
      }
      if (lockPid == pid) {
        return false;
      }
      if (!_remoteProcessLikelyAlive(lockPid)) {
        _log.warning(
          'Removing orphan background lock (holder PID $lockPid is gone)',
        );
        await token.delete();
        return true;
      }
      return false;
    } on FileSystemException catch (e) {
      _log.fine('Orphan lock probe: $e');
      return false;
    }
  }

  static Future<bool> _tryRemoveStaleLock(File token) async {
    try {
      if (!await token.exists()) return false;
      final modified = (await token.stat()).modified;
      if (DateTime.now().difference(modified) <= _staleLockMaxAge) {
        return false;
      }
      _log.warning(
        'Removing stale background lock (>${_staleLockMaxAge.inHours}h old). '
        'If a task is still running, stop it from settings.',
      );
      await token.delete();
      return true;
    } on FileSystemException catch (e) {
      _log.fine('Stale lock check: $e');
      return false;
    }
  }
}
