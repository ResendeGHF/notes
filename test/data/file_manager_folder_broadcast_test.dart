// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/file_manager/file_manager.dart';

/// Regression: folder ops in disk mode (vault off) must emit folder-level
/// broadcasts. Previously only per-child-file events were emitted, so
/// deleting/moving/renaming an *empty* folder emitted nothing and
/// browse/graph stayed stale until app restart.
void main() {
  late Directory tmp;
  late List<FileOperation> events;
  late StreamSubscription<FileOperation> sub;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('saber_folder_broadcast_');
    FileManager.documentsDirectory = tmp.path;
    events = [];
    sub = FileManager.fileWriteStream.stream.listen(events.add);
  });

  tearDown(() async {
    await sub.cancel();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('deleteDirectory broadcasts the folder itself', () async {
    final dir = Directory('${tmp.path}/Work/Empty');
    dir.createSync(recursive: true);
    events.clear();

    await FileManager.deleteDirectory('/Work/Empty');
    // Broadcast stream delivery is async: flush before asserting.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      events.any(
        (e) =>
            e.type == FileOperationType.delete &&
            e.filePath == '/Work/Empty',
      ),
      isTrue,
      reason: 'expected folder-level delete event, got: '
          '${events.map((e) => '${e.type}:${e.filePath}').toList()}',
    );
  });

  test('moveDirectory broadcasts folder delete+write', () async {
    Directory('${tmp.path}/Work/Empty').createSync(recursive: true);
    Directory('${tmp.path}/Archive').createSync(recursive: true);
    events.clear();

    await FileManager.moveDirectory('/Work/Empty', '/Archive');
    // Broadcast stream delivery is async: flush before asserting.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final kinds = events
        .map((e) => '${e.type}:${e.filePath}')
        .toList();
    expect(
      kinds.any((k) => k == 'FileOperationType.delete:/Work/Empty'),
      isTrue,
      reason: 'missing folder delete, got: $kinds',
    );
    expect(
      kinds.any((k) => k.startsWith('FileOperationType.write:/Archive/')),
      isTrue,
      reason: 'missing folder write, got: $kinds',
    );
  });

  test('renameDirectory broadcasts folder delete+write', () async {
    Directory('${tmp.path}/Work/Empty').createSync(recursive: true);
    events.clear();

    await FileManager.renameDirectory('/Work/Empty', 'Full');
    // Broadcast stream delivery is async: flush before asserting.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final kinds = events
        .map((e) => '${e.type}:${e.filePath}')
        .toList();
    expect(
      kinds.any((k) => k == 'FileOperationType.delete:/Work/Empty'),
      isTrue,
      reason: 'missing folder delete, got: $kinds',
    );
    expect(
      kinds.any((k) => k == 'FileOperationType.write:/Work/Full'),
      isTrue,
      reason: 'missing folder write, got: $kinds',
    );
  });
}
