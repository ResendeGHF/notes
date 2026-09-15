// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/home/sort_button.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/recent_notes_index.dart';

NoteIndexEntry _note(String path, {required int m, int size = 1}) {
  return NoteIndexEntry(path: path, modifiedMillis: m, sizeBytes: size);
}

void main() {
  group('RecentNotesIndex', () {
    test('default sort is recently edited first', () {
      final index = RecentNotesIndex(
        notes: [_note('/old', m: 1), _note('/mid', m: 5), _note('/new', m: 9)],
      );
      expect(index.sortedPaths(), ['/new', '/mid', '/old']);
    });

    test('session alphabetical sort does not drop notes', () {
      final index = RecentNotesIndex(
        notes: [_note('/b', m: 2), _note('/a', m: 1)],
      );
      index.sort.functionIdx = 0;
      index.sort.increasing = true;
      expect(index.sortedPaths(), ['/a', '/b']);
      index.sort.resetToRecentDefault();
      expect(index.sortedPaths(), ['/b', '/a']);
    });

    test('mergeFromDisk never drops local notes unless dropMissing', () {
      final index = RecentNotesIndex(notes: [_note('/keep', m: 10)]);
      index.mergeFromDisk([_note('/other', m: 3)]);
      expect(index.contains('/keep'), isTrue);
      expect(index.contains('/other'), isTrue);

      index.mergeFromDisk([_note('/other', m: 4)], dropMissing: true);
      expect(index.contains('/keep'), isFalse);
      expect(index.contains('/other'), isTrue);
    });

    test('mergeFromDisk keeps the newer mtime', () {
      final index = RecentNotesIndex(notes: [_note('/a', m: 50, size: 8)]);
      index.mergeFromDisk([_note('/a', m: 20, size: 99)]);
      expect(index['/a']!.modifiedMillis, 50);
      expect(index['/a']!.sizeBytes, 99);
    });

    test('write after watcher delete of the same path keeps the note', () {
      final index = RecentNotesIndex(notes: [_note('/a', m: 1)]);
      final result = index.applyOperations(const [
        FileOperation(FileOperationType.delete, '/a'),
        FileOperation(FileOperationType.write, '/a.sbn2'),
      ], nowMillis: 100);
      expect(index.contains('/a'), isTrue);
      expect(index['/a']!.modifiedMillis, 100);
      expect(result.removed, isEmpty);
      expect(result.unverifiedDeletes, isEmpty);
      expect(result.written, {'/a'});
    });

    test('watcher delete alone does not remove the note', () {
      final index = RecentNotesIndex(notes: [_note('/a', m: 1)]);
      final result = index.applyOperations(const [
        FileOperation(FileOperationType.delete, '/a'),
      ]);
      expect(index.contains('/a'), isTrue);
      expect(result.unverifiedDeletes, {'/a'});
      expect(result.removed, isEmpty);
    });

    test('confirmed delete removes the note', () {
      final index = RecentNotesIndex(notes: [_note('/a', m: 1)]);
      final result = index.applyOperations(const [
        FileOperation(
          FileOperationType.delete,
          '/a',
          removal: FileRemovalCause.deleted,
        ),
      ]);
      expect(index.contains('/a'), isFalse);
      expect(result.removed, {'/a'});
    });

    test('rename removes old path and adds new path', () {
      final index = RecentNotesIndex(notes: [_note('/old', m: 1, size: 4)]);
      final result = index.applyOperations(const [
        FileOperation(
          FileOperationType.delete,
          '/old',
          removal: FileRemovalCause.renamed,
        ),
        FileOperation(FileOperationType.write, '/new.sbn2'),
      ], nowMillis: 40);
      expect(index.contains('/old'), isFalse);
      expect(index.contains('/new'), isTrue);
      expect(result.removed, {'/old'});
      expect(result.written, {'/new'});
    });

    test('thumbnail events are ignored', () {
      final index = RecentNotesIndex(notes: [_note('/a', m: 1)]);
      final result = index.applyOperations(const [
        FileOperation(
          FileOperationType.delete,
          '/a',
          removal: FileRemovalCause.deleted,
          isThumbnail: true,
        ),
      ]);
      expect(index.contains('/a'), isTrue);
      expect(result.removed, isEmpty);
    });

    test('size sort uses index bytes without decrypt', () {
      final index = RecentNotesIndex(
        notes: [_note('/small', m: 9, size: 2), _note('/big', m: 1, size: 90)],
      );
      index.sort.functionIdx = 2;
      index.sort.increasing = false;
      expect(index.sortedPaths(), ['/big', '/small']);
    });
  });
}
