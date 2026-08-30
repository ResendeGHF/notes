import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/backup/backup_format.dart';
import 'package:saber/data/file_manager/file_manager.dart';

void main() {
  group('FileManager path & countable helpers', () {
    setUp(() {
      FileManager.documentsDirectory = '/app/SaberDocuments';
    });

    test('toRelativePath strips documents root', () {
      expect(
        FileManager.toRelativePath('/app/SaberDocuments/notes/a.sbn2'),
        '/notes/a.sbn2',
      );
    });

    test('toRelativePath normalizes backslashes', () {
      expect(
        FileManager.toRelativePath(r'\app\SaberDocuments\x\y.sbn2'),
        '/x/y.sbn2',
      );
    });

    test('fixFileNameDelimiters uses forward slashes', () {
      expect(FileManager.fixFileNameDelimiters(r'a\b\c.sbn2'), 'a/b/c.sbn2');
    });

    test('isCountableFile ignores assets and hidden', () {
      expect(FileManager.isCountableFile('/x/.hidden'), isFalse);
      expect(FileManager.isCountableFile('/x/note.sbn2.p'), isFalse);
      expect(FileManager.isCountableFile('/x/note.sbn2.1'), isFalse);
      expect(FileManager.isCountableFile('/x/note.sbn2'), isTrue);
    });
  });

  group('FileManager backup archive detection', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('saber_fm_test_');
    });

    tearDown(() {
      if (tmp.existsSync()) {
        tmp.deleteSync(recursive: true);
      }
    });

    test('isDataBackupArchive true for valid data manifest', () async {
      final manifest = utf8.encode(jsonEncode({'type': 'data', 'version': 2}));
      final archive = Archive()
        ..addFile(
          ArchiveFile('_backup_manifest.json', manifest.length, manifest),
        )
        ..addFile(
          ArchiveFile('_preferences.json', 2, Uint8List.fromList([91, 93])),
        );
      final zipBytes = ZipEncoder().encode(archive);
      final f = File('${tmp.path}/backup.zip');
      await f.writeAsBytes(zipBytes, flush: true);

      expect(await FileManager.isDataBackupArchive(f.path), isTrue);
    });

    test('isDataBackupArchive false for random zip', () async {
      final archive = Archive()
        ..addFile(
          ArchiveFile('readme.txt', 4, Uint8List.fromList([1, 2, 3, 4])),
        );
      final zipBytes = ZipEncoder().encode(archive);
      final f = File('${tmp.path}/other.zip');
      await f.writeAsBytes(zipBytes, flush: true);

      expect(await FileManager.isDataBackupArchive(f.path), isFalse);
    });

    test('isDataBackupArchive false for missing path', () async {
      expect(
        await FileManager.isDataBackupArchive('${tmp.path}/nope.zip'),
        isFalse,
      );
    });
  });

  group('BackupFormat path safety', () {
    test('normalizes safe relative paths', () {
      expect(
        BackupFormat.normalizeArchivePath(r'./data\folder/note.sbn2'),
        'data/folder/note.sbn2',
      );
    });

    test('rejects archive paths that escape restore root', () {
      expect(
        () => BackupFormat.normalizeArchivePath('../outside.txt'),
        throwsFormatException,
      );
      expect(
        () => BackupFormat.normalizeArchivePath('/absolute/outside.txt'),
        throwsFormatException,
      );
      expect(
        () => BackupFormat.safeJoin(
          '/tmp/saber_restore',
          'data/../../outside.txt',
        ),
        throwsFormatException,
      );
    });

    test('manifest file entries include sha256 and size', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final entry = BackupFormat.fileEntry(path: 'data/a.bin', bytes: bytes);
      expect(entry['path'], 'data/a.bin');
      expect(entry['size'], 3);
      expect(entry['sha256'], BackupFormat.sha256Hex(bytes));
      BackupFormat.verifyFileBytes('data/a.bin', bytes, entry);
    });

    test('writeBytesAtomically replaces destination without leftover temps', () {
      final dir = Directory.systemTemp.createTempSync('saber_atomic_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final dest = File('${dir.path}/archive.nba');
      dest.writeAsBytesSync(utf8.encode('good-v1'), flush: true);
      BackupFormat.writeBytesAtomically(dest.path, utf8.encode('good-v2'));
      expect(utf8.decode(dest.readAsBytesSync()), 'good-v2');
      expect(
        dir
            .listSync()
            .whereType<File>()
            .where(
              (f) => f.path.contains('.tmp_') || f.path.contains('.old_'),
            ),
        isEmpty,
      );
    });
  });

  group('FileManager.encodeFolderArchive', () {
    test('empty archive encodes to zip bytes', () {
      final empty = Archive();
      final bytes = FileManager.encodeFolderArchive(
        empty,
        FolderArchiveFormat.zip,
      );
      expect(bytes.isNotEmpty, isTrue);
      final decoded = ZipDecoder().decodeBytes(bytes);
      expect(decoded.files.isEmpty, isTrue);
    });
  });
}
