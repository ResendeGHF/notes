// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/backup/backup_format.dart';
import 'package:saber/data/backup/incremental_backup_core.dart';
import 'package:saber/data/backup/monolith_backup_core.dart';
import 'package:saber/services/sba_encryption.dart';

void main() {
  group('monolith backup core', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('saber_monolith_bak_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('streams data backup and reports note count', () {
      final docs = Directory('${tmp.path}/docs')..createSync();
      File('${docs.path}/a.sbn2').writeAsStringSync('note-a');
      File('${docs.path}/b.sbn2').writeAsStringSync('note-b');
      File('${docs.path}/extra.txt').writeAsStringSync('meta');
      final dest = '${tmp.path}/notes_data_backup.nba';
      const password = 'mono-key';

      final ok = runMonolithBackupSync(
        destPath: dest,
        password: password,
        type: BackupArchiveType.data,
        sources: monolithDataSources(docs.path),
        prefsJson: utf8.encode('{}'),
        onProgress: (_, __, {totalNotes = 0}) {
          expect(totalNotes, 2);
        },
      );

      expect(ok, isTrue);
      expect(File(dest).existsSync(), isTrue);
      expect(SbaEncryption.isChunkedEncryptedFile(dest), isTrue);

      final zipPath = '${tmp.path}/decrypted.zip';
      SbaEncryption.decryptFile(dest, zipPath, password);
      final input = InputFileStream(zipPath);
      final archive = ZipDecoder().decodeStream(input);
      input.closeSync();
      expect(
        archive.files.any((f) => f.name == 'data/a.sbn2'),
        isTrue,
      );
    });

    test('chunked encrypt does not require loading whole zip', () {
      final src = File('${tmp.path}/big.bin')
        ..writeAsBytesSync(List<int>.generate(3 * 1024 * 1024, (i) => i % 256));
      final dest = '${tmp.path}/big.enc';
      SbaEncryption.encryptFile(src.path, dest, 'pw');
      expect(SbaEncryption.isChunkedEncryptedFile(dest), isTrue);
      final out = '${tmp.path}/big.out';
      SbaEncryption.decryptFile(dest, out, 'pw');
      expect(File(out).readAsBytesSync(), src.readAsBytesSync());
    });
  });

  group('incremental raw vault blobs', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('saber_inc_raw_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('stores .enc without second AES layer', () {
      final docs = Directory('${tmp.path}/docs')..createSync();
      final vaultBlob = Directory('${docs.path}/saber_vault/data/ab')
        ..createSync(recursive: true);
      final payload = List<int>.generate(2048, (i) => i % 256);
      File('${vaultBlob.path}/blob.enc').writeAsBytesSync(payload);
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
      final blobMeta = Map<String, dynamic>.from(
        files['saber_vault/data/ab/blob.enc'] as Map,
      );
      expect((blobMeta['e'] as num?)?.toInt(), 0);

      final raf = File(archivePath).openSync();
      try {
        raf.setPositionSync((blobMeta['o'] as num).toInt());
        final block = raf.readSync((blobMeta['l'] as num).toInt());
        expect(block, payload);
        expect(SbaEncryption.isEncrypted(Uint8List.fromList(block)), isFalse);
      } finally {
        raf.closeSync();
      }
    });
  });
}
