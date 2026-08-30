// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/editor/binary_writer.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/editor_recovery_journal.dart';

void main() {
  test('new notes get a noteId; legacy binary notes gain one on ensureNoteId', () async {
    final fresh = EditorCoreInfo(filePath: '/tmp/fresh', readOnly: false);
    expect(fresh.noteId, isNotEmpty);

    final legacy = EditorCoreInfo(filePath: '/tmp/legacy', readOnly: false);
    // Simulate a loaded legacy note with no stored id.
    legacy.noteId = '';
    legacy.noteIdWasAssigned = false;
    expect(legacy.ensureNoteId(), isTrue);
    expect(legacy.noteId, isNotEmpty);
    expect(legacy.noteIdWasAssigned, isTrue);

    final bytes = legacy.saveToBinary(currentPageIndex: 0);
    final reloaded = EditorCoreInfo.fromBinary(
      buffer: bytes,
      filePath: '/tmp/legacy',
      readOnly: false,
      onlyFirstPage: false,
    );
    expect(reloaded.noteId, legacy.noteId);
  });

  test('JSON notes persist nid and migrate when missing', () {
    final withId = EditorCoreInfo.fromJson(
      {
        'v': EditorCoreInfo.sbnVersion,
        'ni': 0,
        'p': 'none',
        'l': 40,
        'lt': 3,
        'z': <dynamic>[],
        'nid': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      },
      filePath: '/tmp/json',
      readOnly: false,
      onlyFirstPage: false,
    );
    expect(withId.noteId, 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
    expect(withId.toJson()['nid'], withId.noteId);

    final withoutId = EditorCoreInfo.fromJson(
      {
        'v': EditorCoreInfo.sbnVersion,
        'ni': 0,
        'p': 'none',
        'l': 40,
        'lt': 3,
        'z': <dynamic>[],
      },
      filePath: '/tmp/json2',
      readOnly: false,
      onlyFirstPage: false,
    );
    expect(withoutId.noteId, isEmpty);
    expect(withoutId.ensureNoteId(), isTrue);
    expect(withoutId.noteId, isNotEmpty);
  });

  test('recovery journals keyed by noteId do not collide on same path', () async {
    const path = '/notes/26-08-14 Untitled';
    final first = EditorRecoveryJournal(path, noteId: 'note-one');
    final second = EditorRecoveryJournal(path, noteId: 'note-two');

    expect(
      EditorRecoveryJournal.localPathForNoteId('note-one'),
      isNot(EditorRecoveryJournal.localPathForNoteId('note-two')),
    );
    expect(
      first.noteId,
      isNot(second.noteId),
    );

    // Write a tiny fake journal for the first note id and ensure purge is selective.
    final firstPath = EditorRecoveryJournal.localPathForNoteId('note-one')!;
    await File(firstPath).parent.create(recursive: true);
    await File(firstPath).writeAsBytes(Uint8List.fromList([1, 2, 3, 4]));
    final legacyPath = EditorRecoveryJournal.localPathForNoteBase(path);
    await File(legacyPath).writeAsBytes(Uint8List.fromList([5, 6, 7, 8]));

    await EditorRecoveryJournal.purgeAllForNote(
      noteBasePath: path,
      noteId: 'note-one',
    );
    expect(File(firstPath).existsSync(), isFalse);
    expect(File(legacyPath).existsSync(), isFalse);

    final secondPath = EditorRecoveryJournal.localPathForNoteId('note-two')!;
    await File(secondPath).writeAsBytes(Uint8List.fromList([9, 9, 9, 9]));
    await EditorRecoveryJournal.purgeAllForNote(
      noteBasePath: path,
      noteId: 'note-one',
    );
    expect(File(secondPath).existsSync(), isTrue);
    await File(secondPath).delete();
  });

  test('binary round-trip keeps noteId across SBNBinaryKeys.noteId', () {
    final writer = BinaryWriter();
    writer.writeKey(SBNBinaryKeys.noteId);
    writer.writeStringNoKey('id-123');
    final bytes = writer.toBytes();
    final reader = BinaryReader(bytes);
    expect(reader.readKey(), SBNBinaryKeys.noteId);
    expect(reader.readStringNoKey(), 'id-123');
  });
}
