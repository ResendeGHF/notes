// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/backup/incremental_backup_core.dart';
import 'package:saber/services/sba_encryption.dart';

void main() {
  group('incremental backup core', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('saber_inc_bak_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('creates archive file on first run and writes idxoff sidecar', () {
      final docs = Directory('${tmp.path}/docs')..createSync();
      File('${docs.path}/note.txt').writeAsStringSync('first run');
      final nested = Directory('${tmp.path}/backups/nested')..createSync(recursive: true);
      final archivePath = '${nested.path}/notes_backup_archive.nba';
      // Parent exists but archive file does not — first-time user path.
      expect(File(archivePath).existsSync(), isFalse);

      prepareIncrementalBackupTarget(archivePath);
      expect(File(archivePath).existsSync(), isTrue);
      expect(File(archivePath).lengthSync(), 16);
      expect(File('$archivePath.idxoff').existsSync(), isTrue);

      runIncrementalBackupSync(
        request: IncrementalBackupRequest(
          docsDir: docs.path,
          targetPath: archivePath,
          password: 'first-key',
          prefsMap: {'__sourceMode__': 'data'},
        ),
        onProgress: (_, __) {},
        isCancelled: () => false,
      );

      expect(File(archivePath).lengthSync(), greaterThan(16));
      final side = File('$archivePath.idxoff').readAsBytesSync();
      final offset = ByteData.sublistView(
        Uint8List.fromList(side),
      ).getInt64(0, Endian.little);
      expect(offset, greaterThanOrEqualTo(16));
      expect(offset, lessThan(File(archivePath).lengthSync()));

      final snapshot = readIncrementalIndexSync(
        targetPath: archivePath,
        password: 'first-key',
      );
      expect((snapshot.index['files'] as Map).containsKey('note.txt'), isTrue);
    });

    test('mtime+size match skips encrypt', () {
      expect(
        incrementalFileUnchanged({'m': 10, 's': 4, 'h': 'x'}, 10, 4),
        isTrue,
      );
      expect(
        incrementalFileUnchanged({'m': 10, 's': 4, 'h': 'x'}, 11, 4),
        isFalse,
      );
    });

    test('roundtrip uses AES-256-GCM and skips unchanged files', () {
      final docs = Directory('${tmp.path}/docs')..createSync();
      File('${docs.path}/note.txt').writeAsStringSync('hello incremental');
      final archivePath = '${tmp.path}/notes_backup_archive.nba';
      const password = 'inc-key';

      runIncrementalBackupSync(
        request: IncrementalBackupRequest(
          docsDir: docs.path,
          targetPath: archivePath,
          password: password,
          prefsMap: {'__sourceMode__': 'data'},
        ),
        onProgress: (_, __) {},
        isCancelled: () => false,
      );

      final firstSize = File(archivePath).lengthSync();
      expect(firstSize, greaterThan(16));

      final snapshot = readIncrementalIndexSync(
        targetPath: archivePath,
        password: password,
      );
      final files = snapshot.index['files'] as Map;
      expect(files.containsKey('note.txt'), isTrue);
      final meta = Map<String, dynamic>.from(files['note.txt'] as Map);
      final raf = File(archivePath).openSync();
      try {
        raf.setPositionSync((meta['o'] as num).toInt());
        final block = Uint8List.fromList(
          raf.readSync((meta['l'] as num).toInt()),
        );
        expect(SbaEncryption.isEncrypted(block), isTrue);
        expect(block[13], 0x03);
        final plain = const ZLibDecoder().decodeBytes(
          SbaEncryption.decrypt(block, password),
        );
        expect(utf8.decode(plain), 'hello incremental');
      } finally {
        raf.closeSync();
      }

      runIncrementalBackupSync(
        request: IncrementalBackupRequest(
          docsDir: docs.path,
          targetPath: archivePath,
          password: password,
          prefsMap: {'__sourceMode__': 'data'},
        ),
        onProgress: (_, __) {},
        isCancelled: () => false,
      );
      final secondSize = File(archivePath).lengthSync();
      // Unchanged files rewrite only the index over the previous index slot.
      expect((secondSize - firstSize).abs(), lessThan(2048));

      File('${docs.path}/note.txt').writeAsStringSync('changed payload');
      runIncrementalBackupSync(
        request: IncrementalBackupRequest(
          docsDir: docs.path,
          targetPath: archivePath,
          password: password,
          prefsMap: {'__sourceMode__': 'data'},
        ),
        onProgress: (_, __) {},
        isCancelled: () => false,
      );
      final afterChange = readIncrementalIndexSync(
        targetPath: archivePath,
        password: password,
      );
      final changed = Map<String, dynamic>.from(
        (afterChange.index['files'] as Map)['note.txt'] as Map,
      );
      final raf2 = File(archivePath).openSync();
      try {
        raf2.setPositionSync((changed['o'] as num).toInt());
        final block = Uint8List.fromList(
          raf2.readSync((changed['l'] as num).toInt()),
        );
        final plain = utf8.decode(
          const ZLibDecoder().decodeBytes(
            SbaEncryption.decrypt(block, password),
          ),
        );
        expect(plain, 'changed payload');
      } finally {
        raf2.closeSync();
      }
    });

    test('unchanged rerun skips encrypt via sidecar cache', () {
      final docs = Directory('${tmp.path}/docs')..createSync();
      File('${docs.path}/note.txt').writeAsStringSync('stable');
      final archivePath = '${tmp.path}/notes_backup_archive.nba';
      const password = 'inc-key';
      final request = IncrementalBackupRequest(
        docsDir: docs.path,
        targetPath: archivePath,
        password: password,
        prefsMap: {'__sourceMode__': 'data', '/lastBackupTimestamp': 1},
      );

      runIncrementalBackupSync(
        request: request,
        onProgress: (_, __) {},
        isCancelled: () => false,
      );
      final afterFirst = File(archivePath).statSync();

      runIncrementalBackupSync(
        request: IncrementalBackupRequest(
          docsDir: docs.path,
          targetPath: archivePath,
          password: password,
          prefsMap: {'__sourceMode__': 'data', '/lastBackupTimestamp': 2},
        ),
        onProgress: (_, __) {},
        isCancelled: () => false,
      );
      final afterSecond = File(archivePath).statSync();
      expect(afterSecond.size, afterFirst.size);
      expect(
        afterSecond.modified.millisecondsSinceEpoch,
        afterFirst.modified.millisecondsSinceEpoch,
      );

      File('${docs.path}/note.txt').writeAsStringSync('now changed');
      runIncrementalBackupSync(
        request: IncrementalBackupRequest(
          docsDir: docs.path,
          targetPath: archivePath,
          password: password,
          prefsMap: {'__sourceMode__': 'data', '/lastBackupTimestamp': 3},
        ),
        onProgress: (_, __) {},
        isCancelled: () => false,
      );
      expect(File(archivePath).lengthSync(), greaterThan(afterSecond.size));
    });

    test('skips thumbnails and stores vault blobs uncompressed', () {
      final docs = Directory('${tmp.path}/docs')..createSync();
      final vaultBlob = Directory('${docs.path}/saber_vault/data/ab')
        ..createSync(recursive: true);
      File('${vaultBlob.path}/blob.enc').writeAsBytesSync(
        List<int>.generate(64, (i) => i),
      );
      File('${docs.path}/note.sbn2.p').writeAsStringSync('thumb');
      File('${docs.path}/note.sbn2').writeAsStringSync('note body');
      final archivePath = '${tmp.path}/notes_backup_archive.nba';
      const password = 'inc-key';

      runIncrementalBackupSync(
        request: IncrementalBackupRequest(
          docsDir: docs.path,
          targetPath: archivePath,
          password: password,
          prefsMap: {'__sourceMode__': 'vaultPhysical'},
          noteCount: 1,
        ),
        onProgress: (_, __) {},
        isCancelled: () => false,
      );

      final snapshot = readIncrementalIndexSync(
        targetPath: archivePath,
        password: password,
        sourceMode: 'vaultPhysical',
      );
      final files = snapshot.index['files'] as Map;
      expect(files.containsKey('note.sbn2.p'), isFalse);
      expect(files.containsKey('note.sbn2'), isTrue);
      expect(countIncrementalNoteBodies(files.keys.cast<String>()), 1);

      final blobMeta = Map<String, dynamic>.from(
        files['saber_vault/data/ab/blob.enc'] as Map,
      );
      expect((blobMeta['z'] as num?)?.toInt(), 0);
      expect((blobMeta['e'] as num?)?.toInt(), 0);

      final raf = File(archivePath).openSync();
      try {
        raf.setPositionSync((blobMeta['o'] as num).toInt());
        final block = Uint8List.fromList(
          raf.readSync((blobMeta['l'] as num).toInt()),
        );
        expect(SbaEncryption.isEncrypted(block), isFalse);
        final plain = decodeIncrementalPayload(blobMeta, block);
        expect(plain.length, 64);
        expect(plain.first, 0);
      } finally {
        raf.closeSync();
      }
    });

    test('verify decrypts index and every payload without restore', () {
      final docs = Directory('${tmp.path}/docs')..createSync();
      Directory('${docs.path}/folder').createSync();
      File('${docs.path}/folder/note.sbn2').writeAsStringSync('alpha');
      File('${docs.path}/root.txt').writeAsStringSync('beta');
      final archivePath = '${tmp.path}/notes_backup_archive.nba';
      const password = 'verify-key';

      runIncrementalBackupSync(
        request: IncrementalBackupRequest(
          docsDir: docs.path,
          targetPath: archivePath,
          password: password,
          prefsMap: {'__sourceMode__': 'data'},
        ),
        onProgress: (_, __) {},
        isCancelled: () => false,
      );

      final result = verifyIncrementalBackupSync(
        targetPath: archivePath,
        password: password,
      );
      expect(result.ok, isTrue);
      expect(result.hasIdxoff, isTrue);
      expect(result.indexedFileCount, greaterThanOrEqualTo(2));
      expect(result.checkedFileCount, result.indexedFileCount);
      expect(result.errors, isEmpty);
      expect(result.samplePaths, isNotEmpty);

      final bad = verifyIncrementalBackupSync(
        targetPath: archivePath,
        password: 'wrong',
      );
      expect(bad.ok, isFalse);
      expect(bad.errors, isNotEmpty);
    });

    test('verify completes with many encrypted files using decrypt session', () {
      final docs = Directory('${tmp.path}/docs')..createSync();
      for (var i = 0; i < 24; i++) {
        File('${docs.path}/note_$i.sbn2').writeAsStringSync('body-$i');
      }
      final archivePath = '${tmp.path}/notes_backup_archive.nba';
      const password = 'many-key';

      runIncrementalBackupSync(
        request: IncrementalBackupRequest(
          docsDir: docs.path,
          targetPath: archivePath,
          password: password,
          prefsMap: {'__sourceMode__': 'data'},
        ),
        onProgress: (_, __) {},
        isCancelled: () => false,
      );

      final progresses = <double>[];
      final result = verifyIncrementalBackupSync(
        targetPath: archivePath,
        password: password,
        onProgress: (p, _) => progresses.add(p),
      );
      expect(result.ok, isTrue);
      expect(result.checkedFileCount, 24);
      expect(progresses.last, 1.0);
      expect(progresses.any((p) => p > 0.12 && p < 1.0), isTrue);
    });
  });
}
