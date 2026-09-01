// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive_io.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:pdfrx/pdfrx.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saber/components/canvas/canvas_preview.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/backup/backup_format.dart';
import 'package:saber/data/backup/incremental_backup_core.dart';
import 'package:saber/data/backup/monolith_backup_core.dart';
import 'package:saber/components/editor/pdf_outline_extractor.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/editor_exporter.dart';
import 'package:saber/data/editor/editor_recovery_journal.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/editor/pdf_outline.dart';
import 'package:saber/data/home_data_cache.dart';
import 'package:saber/data/note_links_database.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tags_database.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:saber/services/background_operation_lock.dart';
import 'package:saber/services/background_operation_queue.dart';
import 'package:saber/services/sba_encryption.dart';
import 'package:saber/services/thumbnail_cache.dart';
import 'package:saber/services/vault_adapter.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:screenshot/screenshot.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:jdenticon_dart/jdenticon_dart.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight home-list index: path plus cheap mtime/size (no note decrypt).
class NoteIndexEntry {
  const NoteIndexEntry({
    required this.path,
    required this.modifiedMillis,
    required this.sizeBytes,
  });

  final String path;
  final int modifiedMillis;
  final int sizeBytes;

  NoteIndexEntry copyWith({int? modifiedMillis, int? sizeBytes}) {
    return NoteIndexEntry(
      path: path,
      modifiedMillis: modifiedMillis ?? this.modifiedMillis,
      sizeBytes: sizeBytes ?? this.sizeBytes,
    );
  }
}

/// Home list row metadata — same sources as [showNotePropertiesDialog] (note file
/// + bundle sizes; [EditorCoreInfo] timestamps).
class NoteListRowStats {
  const NoteListRowStats({
    required this.sizeBytes,
    required this.created,
    required this.modified,
    this.accessed,
  });

  final int sizeBytes;
  final DateTime? created;
  final DateTime? modified;

  /// From note metadata (`lad`); null if never recorded.
  final DateTime? accessed;
}

Uint8List _archiveFileBytes(ArchiveFile file) {
  final output = OutputMemoryStream();
  file.writeContent(output);
  return Uint8List.fromList(output.getBytes());
}

Future<bool> _isolateDataBackupTask(Map<String, dynamic> args) async {
  final receive = ReceivePort();
  try {
    await Isolate.spawn(monolithDataBackupIsolateMain, {
      ...args,
      'sendPort': receive.sendPort,
    });
    await for (final raw in receive) {
      if (raw is! Map) continue;
      if (raw['error'] != null) {
        throw Exception(raw['error'].toString());
      }
      if (raw['done'] == true) {
        return File(args['destPath'] as String).existsSync();
      }
    }
    return false;
  } finally {
    receive.close();
  }
}

Future<bool> _isolateDataRestoreTask(Map<String, dynamic> args) async {
  final archivePath = args['archivePath'] as String;
  final password = args['password'] as String;
  final tempDirPath = args['tempDirPath'] as String;

  final stamp = DateTime.now().microsecondsSinceEpoch;
  final tmpZip = p.join(tempDirPath, '_monolith_dec_$stamp.zip');
  var zipPath = archivePath;
  var ownsZip = false;

  final header = File(archivePath).openSync(mode: FileMode.read);
  late final Uint8List peek;
  try {
    peek = Uint8List.fromList(header.readSync(32));
  } finally {
    header.closeSync();
  }

  if (SbaEncryption.isEncrypted(peek)) {
    if (password.isEmpty) {
      throw StateError('Backup is encrypted but no password was provided.');
    }
    SbaEncryption.decryptFile(archivePath, tmpZip, password);
    zipPath = tmpZip;
    ownsZip = true;
  }

  try {
    final input = InputFileStream(zipPath);
    final archive = ZipDecoder().decodeStream(input);

    final manifestFiles = archive.files
        .where((f) => f.name == BackupFormat.manifestPath)
        .toList();
    if (manifestFiles.isEmpty) {
      throw StateError(
        'Invalid backup: missing manifest (not a data backup archive)',
      );
    }
    final manifestJson = BackupFormat.decodeJsonFile(
      _archiveFileBytes(manifestFiles.first),
    );
    if (manifestJson['type'] != 'data') {
      throw StateError(
        'Invalid backup: wrong type (expected data, got ${manifestJson['type']})',
      );
    }

    final isV3 = BackupFormat.isManifestV3(manifestJson);
    final manifestFileMap = isV3
        ? BackupFormat.manifestFileMap(manifestJson)
        : <String, Map<String, dynamic>>{};
    if (isV3) {
      BackupFormat.validateUniquePaths(manifestFileMap.keys);
      final dirs = (manifestJson['directories'] as List?) ?? const [];
      for (final dir in dirs) {
        Directory(
          BackupFormat.safeJoin(tempDirPath, dir.toString()),
        ).createSync(recursive: true);
      }
    }

    for (final file in archive.files) {
      final normalizedPath = BackupFormat.normalizeArchivePath(file.name);
      if (normalizedPath == BackupFormat.manifestPath) continue;
      final outPath = BackupFormat.safeJoin(tempDirPath, normalizedPath);
      if (file.isFile) {
        final bytes = _archiveFileBytes(file);
        final manifestEntry = manifestFileMap[normalizedPath];
        if (isV3) {
          if (manifestEntry == null) {
            throw StateError('Invalid backup: unexpected file $normalizedPath');
          }
          BackupFormat.verifyFileBytes(normalizedPath, bytes, manifestEntry);
        }
        final outFile = File(outPath);
        outFile.parent.createSync(recursive: true);
        outFile.writeAsBytesSync(bytes);
      } else {
        Directory(outPath).createSync(recursive: true);
      }
    }
    input.closeSync();
    return true;
  } finally {
    if (ownsZip) {
      try {
        final f = File(tmpZip);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }
}

class _SbaUnpackRequest {
  const _SbaUnpackRequest({
    required this.rawBytes,
    required this.encrypted,
    this.password,
  });

  final Uint8List rawBytes;
  final bool encrypted;
  final String? password;
}

class _SbaArchiveMember {
  const _SbaArchiveMember({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// Decrypt (if needed) and expand an `.sba` zip on a worker — heavy CPU for large archives.
List<_SbaArchiveMember> _unpackSbaArchiveSync(_SbaUnpackRequest req) {
  Uint8List data = req.rawBytes;
  if (req.encrypted) {
    if (req.password == null || req.password!.isEmpty) {
      throw StateError('SBA unpack: encrypted archive requires a password');
    }
    data = SbaEncryption.decrypt(data, req.password!);
  }
  final archive = ZipDecoder().decodeBytes(data);
  final out = <_SbaArchiveMember>[];
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final output = OutputMemoryStream();
    file.writeContent(output);
    out.add(
      _SbaArchiveMember(
        name: file.name,
        bytes: Uint8List.fromList(output.getBytes()),
      ),
    );
  }
  return out;
}

Uint8List _zlibEncodeBytes(Uint8List bytes) {
  return Uint8List.fromList(const ZLibEncoder().encode(bytes));
}

/// Vault paths in the incremental index are absolute (`/folder/file`). If used
/// as the second argument to [p.join], POSIX treats them as absolute and the
/// prefix is ignored, so files end up under `/` (EROFS on Android).
String _stripLeadingSlashesForPathJoin(String path) {
  var s = path.replaceAll('\\', '/').trim();
  while (s.startsWith('/')) {
    s = s.substring(1);
  }
  return s;
}

Future<Map<String, dynamic>> _isolateIncrementalRestoreTask(
  Map<String, dynamic> args,
) async {
  final targetPath = args['targetPath'] as String;
  final password = args['password'] as String;
  final tempDirPath = args['tempDirPath'] as String;

  final file = File(targetPath);
  if (!file.existsSync() || file.lengthSync() < 16) {
    throw Exception('Backup file not found or incomplete.');
  }

  late final Map<String, dynamic> index;
  try {
    final snapshot = readIncrementalIndexSync(
      targetPath: targetPath,
      password: password,
    );
    index = snapshot.index;
  } catch (e) {
    throw Exception('Invalid Key or corrupted backup archive.');
  }

  final filesMap = index['files'] as Map<String, dynamic>? ?? {};
  final sourceMode = index['sourceMode']?.toString() ?? 'data';
  if (filesMap.isEmpty && file.lengthSync() > 16) {
    throw Exception(
      'Backup index lists no files (corrupt index offset or unfinished backup).',
    );
  }

  final decryptSession = SbaDecryptSession(password);
  final raf = file.openSync(mode: FileMode.read);
  try {
    final magic = raf.readSync(8);
    var magicValid = magic.length == incrementalMagicBytes.length;
    if (magicValid) {
      for (var i = 0; i < incrementalMagicBytes.length; i++) {
        if (magic[i] != incrementalMagicBytes[i]) {
          magicValid = false;
          break;
        }
      }
    }
    if (!magicValid) {
      throw Exception('Invalid Backup File Format.');
    }

    const copyChunk = 1024 * 1024;
    for (final entry in filesMap.entries) {
      final filePath = entry.key;
      final block = entry.value;
      final blockMap = block is Map<String, dynamic>
          ? block
          : Map<String, dynamic>.from(block as Map);

      final offset = (blockMap['o'] as num).toInt();
      final length = (blockMap['l'] as num).toInt();
      final rel = _stripLeadingSlashesForPathJoin(filePath);
      if (rel.isEmpty) continue;

      final destFile = File(p.join(tempDirPath, rel));
      destFile.parent.createSync(recursive: true);

      final isRaw = (blockMap['e'] as num?)?.toInt() == 0;
      if (isRaw) {
        // Stream vault/opaque blobs — never hold multi‑GB PDFs in RAM.
        raf.setPositionSync(offset);
        final out = destFile.openSync(mode: FileMode.write);
        try {
          var remaining = length;
          while (remaining > 0) {
            final n = remaining > copyChunk ? copyChunk : remaining;
            final chunk = raf.readSync(n);
            if (chunk.isEmpty) {
              throw Exception('Truncated raw block for $rel');
            }
            out.writeFromSync(chunk);
            remaining -= chunk.length;
          }
        } finally {
          out.closeSync();
        }
        final hash = blockMap['h'] as String?;
        if (hash != null && length <= 4 * 1024 * 1024) {
          final data = destFile.readAsBytesSync();
          BackupFormat.verifyFileBytes(rel, data, {
            'sha256': hash,
            'size': (blockMap['s'] as num?)?.toInt() ?? data.length,
          });
        }
        continue;
      }

      raf.setPositionSync(offset);
      final encrypted = Uint8List.fromList(raf.readSync(length));
      final payloadBytes = decryptSession.decrypt(encrypted);
      final data = decodeIncrementalPayload(blockMap, payloadBytes);

      final hash = blockMap['h'] as String?;
      if (hash != null) {
        BackupFormat.verifyFileBytes(rel, data, {
          'sha256': hash,
          'size': (blockMap['s'] as num?)?.toInt() ?? data.length,
        });
      }

      destFile.writeAsBytesSync(data);
    }
  } finally {
    raf.closeSync();
    decryptSession.dispose();
  }

  final preferences = Map<String, dynamic>.from(
    index['preferences'] as Map<String, dynamic>? ?? {},
  );
  preferences['__sourceMode__'] = sourceMode;
  return preferences;
}

Uint8List _isolateEncodeFolderArchive(Map<String, dynamic> args) {
  final archive = args['archive'] as Archive;
  final format = args['format'] as FolderArchiveFormat;
  return FileManager.encodeFolderArchive(archive, format);
}

enum FolderArchiveFormat {
  zip,
  tarXz;

  String get extension => this == FolderArchiveFormat.zip ? 'zip' : 'tar.xz';
}

class FolderArchiveData {
  const FolderArchiveData({
    required this.fileName,
    required this.bytes,
    this.skippedMissingTargets = 0,
    this.skippedCyclicLinks = 0,
  });

  final String fileName;
  final Uint8List bytes;
  final int skippedMissingTargets;
  final int skippedCyclicLinks;
}

class _FolderArchiveStats {
  int skippedMissingTargets = 0;
  int skippedCyclicLinks = 0;
}

class FileManager {
  FileManager._();

  static final log = Logger('FileManager');

  static bool get _shouldUseVault {
    return stows.localEncryptionEnabled.value;
  }

  static const appRootDirectoryPrefix = 'Saber';

  static late String documentsDirectory;

  static final fileWriteStream = StreamController<FileOperation>.broadcast();

  static String _sanitisePath(String path) => File(path).path;

  static String toRelativePath(String path) {
    if (path.isEmpty) return '/';

    final context = p.Context(style: p.Style.posix);

    path = path.replaceAll('\\', '/');
    var rootDir = documentsDirectory.replaceAll('\\', '/');

    path = context.normalize(path);
    rootDir = context.normalize(rootDir);

    if (path.startsWith(rootDir)) {
      if (path.length == rootDir.length) {
        return '/';
      }
      if (path[rootDir.length] == '/') {
        return path.substring(rootDir.length);
      }
    }

    if (!path.startsWith('/')) {
      path = '/$path';
    }

    return path.replaceAll(RegExp(r'/+'), '/');
  }

  static final assetFileRegex = RegExp(r'\.sbn2?\.[\dp]+$');
  static const int _folderBundleSizeVersion = 2;

  /// Normalize folder keys the same way vault does (`/folder/`).
  static String normalizeFolderCountPath(String folderPath) {
    var normalized = toRelativePath(folderPath);
    if (!normalized.endsWith('/')) normalized += '/';
    if (normalized.length > 1 && !normalized.startsWith('/')) {
      normalized = '/$normalized';
    }
    return normalized;
  }

  static bool isCountableFile(String path) {
    final name = p.basename(path);
    if (name.startsWith('.')) return false;
    if (name.endsWith('.p')) return false;
    if (assetFileRegex.hasMatch(name)) return false;

    final normalized = path.toLowerCase();
    if (normalized.contains('/data/') ||
        normalized.startsWith('data/') ||
        normalized.endsWith('.recovery') ||
        normalized.contains('/file_picker/') ||
        normalized.startsWith('file_picker/')) {
      return false;
    }

    return true;
  }

  static bool isFolderSizeTrackedFile(String path) {
    final name = p.basename(path);
    if (name.startsWith('.')) return false;

    final normalized = path.toLowerCase();
    if (normalized.contains('/data/') ||
        normalized.startsWith('data/') ||
        normalized.endsWith('.recovery') ||
        normalized.contains('/file_picker/') ||
        normalized.startsWith('file_picker/')) {
      return false;
    }

    return path.endsWith(Editor.extension) ||
        path.endsWith(Editor.extensionOldJson) ||
        name.endsWith('.p') ||
        assetFileRegex.hasMatch(name);
  }

  static Future<void> init({
    String? documentsDirectory,
    bool shouldWatchRootDirectory = true,
  }) async {
    FileManager.documentsDirectory =
        documentsDirectory ?? await getDocumentsDirectory();

    BackgroundOperationLock.configure(FileManager.documentsDirectory);
    await BackgroundOperationLock.recoverOrphanAtStartup();

    if (shouldWatchRootDirectory) unawaited(watchRootDirectory());

    unawaited(_cleanupVaultTempFiles());
  }

  static Future<void> _cleanupVaultTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (!tempDir.existsSync()) return;
      final entities = tempDir.listSync();
      for (final e in entities) {
        if (e is! File) continue;
        final name = p.basename(e.path);
        if (name.startsWith('vault_') && name.endsWith('.tmp')) {
          try {
            e.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  static Future<String> getDocumentsDirectory() async =>
      stows.customDataDir.value ?? await getDefaultDocumentsDirectory();

  static Future<String> getDefaultDocumentsDirectory() async =>
      '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}$appRootDirectoryPrefix';

  static Future<void> migrateDataDir() async {
    final oldDir = Directory(documentsDirectory);
    final newDir = Directory(await getDocumentsDirectory());
    if (oldDir.path == newDir.path) return;
    log.info('Migrating data directory from $oldDir to $newDir');

    final oldDirEmpty = oldDir.existsSync() ? oldDir.listSync().isEmpty : true;
    final newDirEmpty = newDir.existsSync() ? newDir.listSync().isEmpty : true;

    if (!oldDirEmpty && !newDirEmpty) {
      log.severe('New and old data directory aren\'t empty, can\'t migrate');
      return;
    }

    documentsDirectory = newDir.path;
    BackgroundOperationLock.configure(documentsDirectory);
    await BackgroundOperationLock.recoverOrphanAtStartup();
    if (oldDirEmpty) {
      log.fine('Old data directory is empty or missing, nothing to migrate');
    } else {
      await moveDirContents(oldDir: oldDir, newDir: newDir);
      await oldDir.delete(recursive: true);
    }
  }

  static String fixFileNameDelimiters(String filePath) {
    return filePath.replaceAll('\\', '/');
  }

  static Future<Directory> getTmpAssetDir() async {
    try {
      final baseDir = Directory(documentsDirectory);

      final hiddenDir = Directory(
        '${baseDir.path}${Platform.pathSeparator}.tmpAssets',
      );

      if (!await hiddenDir.exists()) {
        await hiddenDir.create(recursive: true);
      }
      return hiddenDir;
    } on FileSystemException catch (e) {
      log.info('getTmpAssetDir $e');
      rethrow;
    }
  }

  static Future<void> moveDirContents({
    required Directory oldDir,
    required Directory newDir,
  }) async {
    await newDir.create(recursive: true);

    await for (final entity in oldDir.list(recursive: true)) {
      final relative = p.relative(entity.path, from: oldDir.path);
      final targetPath = p.join(newDir.path, relative);

      if (entity is Directory) {
        await Directory(targetPath).create(recursive: true);
        continue;
      }

      if (entity is File) {
        await entity.parent.create(recursive: true);

        try {
          await entity.rename(targetPath);
        } on FileSystemException catch (e) {
          const exdev = 18;
          if (e.osError?.errorCode == exdev) {
            await entity.copy(targetPath);
            await entity.delete();
          } else {
            rethrow;
          }
        }
      }
    }
  }

  static const String _dataBackupManifestPath = '_backup_manifest.json';

  static const String _preferencesBackupPath = '_preferences.json';

  static Future<File> createDataBackupArchive(
    String destinationPath,
    String password, {
    void Function(double progress, String message, {int totalNotes})?
        onProgress,
  }) async {
    final docsDir = Directory(documentsDirectory);
    if (!docsDir.existsSync()) {
      throw StateError('Documents directory not found: $documentsDirectory');
    }

    await TagDatabase.instance.close();
    await NoteLinksDatabase.instance.close();

    final prefs = await SharedPreferences.getInstance();
    final prefsMap = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      final value = prefs.get(key);
      if (value != null) {
        prefsMap[key] = value;
      }
    }
    final prefsJson = utf8.encode(jsonEncode(prefsMap));

    if (onProgress != null) {
      await runMonolithBackupInIsolate(
        spawnArgs: {
          'docsDir': docsDir.path,
          'destPath': destinationPath,
          'password': password,
          'prefsJson': prefsJson,
        },
        onProgress: (p, m, notes) => onProgress(p, m, totalNotes: notes),
        isolateMain: monolithDataBackupIsolateMain,
      );
    } else {
      await compute(_isolateDataBackupTask, {
        'docsDir': docsDir.path,
        'destPath': destinationPath,
        'password': password,
        'prefsJson': prefsJson,
      });
    }

    return File(destinationPath);
  }

  static Future<void> restoreDataBackupArchive(
    String archivePath,
    String password,
  ) async {
    final tempDir = await Directory.systemTemp.createTemp(
      'saber_data_restore_',
    );
    try {
      await compute(_isolateDataRestoreTask, {
        'archivePath': archivePath,
        'password': password,
        'tempDirPath': tempDir.path,
      });

      final prefsFile = File(p.join(tempDir.path, _preferencesBackupPath));
      if (prefsFile.existsSync()) {
        final prefsJson =
            jsonDecode(await prefsFile.readAsString()) as Map<String, dynamic>;
        await BackupFormat.restoreSharedPreferences(
          prefsJson,
          exclude: _unrestorableDevicePathPrefs(prefsJson),
        );
      }

      documentsDirectory = await getDocumentsDirectory();
      BackgroundOperationLock.configure(documentsDirectory);
      await BackgroundOperationLock.recoverOrphanAtStartup();

      final dataDir = Directory(p.join(tempDir.path, 'data'));
      if (dataDir.existsSync()) {
        await TagDatabase.instance.close();
        await NoteLinksDatabase.instance.close();

        final docDir = documentsDirectory;
        final destDir = Directory(docDir);
        final oldDir = Directory(
          '$docDir.restore_old_${DateTime.now().microsecondsSinceEpoch}',
        );
        var movedOld = false;
        try {
          if (destDir.existsSync()) {
            await destDir.rename(oldDir.path);
            movedOld = true;
          }
          await destDir.create(recursive: true);
          await moveDirContents(oldDir: dataDir, newDir: destDir);
          if (movedOld && oldDir.existsSync()) {
            await oldDir.delete(recursive: true);
          }
        } catch (_) {
          if (destDir.existsSync()) {
            await destDir.delete(recursive: true);
          }
          if (movedOld && oldDir.existsSync()) {
            await oldDir.rename(destDir.path);
          }
          rethrow;
        }
      }

      documentsDirectory = await getDocumentsDirectory();
      BackgroundOperationLock.configure(documentsDirectory);
    } finally {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  static Set<String> _unrestorableDevicePathPrefs(Map<String, dynamic> prefs) {
    const devicePathPrefs = {
      'customDataDir',
      '/backupFilePath',
      '/backupDirectoryPath',
      '/defaultExportPath',
    };
    return {
      for (final key in devicePathPrefs)
        if (prefs[key] is String &&
            !BackupFormat.canRestoreDevicePath(prefs[key] as String))
          key,
    };
  }

  static Future<bool> isDataBackupArchive(String path) async {
    try {
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final tmpZip = '$path.isdata_$stamp.zip';
      var zipPath = path;
      var ownsZip = false;
      try {
        final header = File(path).openSync(mode: FileMode.read);
        late final Uint8List peek;
        try {
          peek = Uint8List.fromList(header.readSync(32));
        } finally {
          header.closeSync();
        }
        // Encrypted monoliths need a password — caller should use the
        // password-aware check. Treat encrypted files as "not plain data".
        if (SbaEncryption.isEncrypted(peek)) return false;

        final input = InputFileStream(zipPath);
        final archive = ZipDecoder().decodeStream(input);
        final manifestFiles = archive.files
            .where((f) => f.name == _dataBackupManifestPath)
            .toList();
        input.closeSync();
        final manifestFile =
            manifestFiles.isNotEmpty ? manifestFiles.first : null;
        if (manifestFile == null) return false;
        final manifestJson = BackupFormat.decodeJsonFile(
          _archiveFileBytes(manifestFile),
        );
        return manifestJson['type'] == 'data';
      } finally {
        if (ownsZip) {
          try {
            final f = File(tmpZip);
            if (f.existsSync()) f.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  static Future<void> watchRootDirectory() async {
    if (_shouldUseVault) return;

    final rootDir = Directory(documentsDirectory);
    await rootDir.create(recursive: true);
    rootDir.watch(recursive: true).listen((event) {
      final FileOperationType type = switch (event.type) {
        FileSystemEvent.delete => FileOperationType.delete,
        FileSystemEvent.create => FileOperationType.write,
        FileSystemEvent.modify => FileOperationType.write,
        FileSystemEvent.move => FileOperationType.write,
        _ =>
          kDebugMode
              ? throw UnimplementedError(
                  'Unhandled FileSystemEvent type: ${event.type}',
                )
              : FileOperationType.write,
      };
      final String path = event.path
          .replaceAll('\\', '/')
          .replaceFirst(documentsDirectory, '');
      broadcastFileWrite(type, path);
    });
  }

  static bool _isThumbnailSidecarPath(String filePath) {
    return filePath.endsWith('${Editor.extension}.p') ||
        filePath.endsWith('${Editor.extensionOldJson}.p');
  }

  static String _stripToNotePath(String path) {
    path = toRelativePath(path);
    if (path.endsWith('${Editor.extension}.p')) {
      return path.substring(0, path.length - Editor.extension.length - 2);
    }
    if (path.endsWith('${Editor.extensionOldJson}.p')) {
      return path.substring(
        0,
        path.length - Editor.extensionOldJson.length - 2,
      );
    }
    if (path.endsWith(Editor.extension)) {
      return path.substring(0, path.length - Editor.extension.length);
    }
    if (path.endsWith(Editor.extensionOldJson)) {
      return path.substring(0, path.length - Editor.extensionOldJson.length);
    }
    return path;
  }

  static FileRemovalCause _removalCauseForRelocate(
    String fromPath,
    String toPath,
  ) {
    String parentOf(String p) {
      final note = _stripToNotePath(p);
      final i = note.lastIndexOf('/');
      return i <= 0 ? '/' : note.substring(0, i);
    }

    return parentOf(fromPath) == parentOf(toPath)
        ? FileRemovalCause.renamed
        : FileRemovalCause.moved;
  }

  static void _rememberThumbnailBytes(String filePath, List<int> bytes) {
    if (!_isThumbnailSidecarPath(filePath) || bytes.isEmpty) return;
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    ThumbnailCache.instance.put(_stripToNotePath(filePath), data);
  }

  @visibleForTesting
  static void broadcastFileWrite(
    FileOperationType type,
    String path, {
    FileRemovalCause? removal,
    bool isThumbnail = false,
  }) async {
    if (!fileWriteStream.hasListener) return;

    final thumbnailSidecar = isThumbnail || _isThumbnailSidecarPath(path);
    path = _stripToNotePath(path);

    fileWriteStream.add(
      FileOperation(
        type,
        path,
        removal: removal,
        isThumbnail: thumbnailSidecar,
      ),
    );
  }

  /// Note bodies ([Editor.extension]) are zlib-compressed for vault and disk.
  /// After read, decompress so [EditorCoreInfo] sees native binary (or BSON for
  /// legacy). If [data] is not zlib (legacy uncompressed), decoding fails and
  /// we return [data] unchanged — same behavior as the disk branch.
  static Uint8List _maybeDecompressSbn2Note(Uint8List data, String filePath) {
    if (!filePath.endsWith(Editor.extension) || data.isEmpty) return data;
    try {
      final decompressed = const ZLibDecoder().decodeBytes(data);
      return Uint8List.fromList(decompressed);
    } catch (_) {
      return data;
    }
  }

  /// When false, vault reads must not write plaintext to disk (RAM-only mode).
  static bool _vaultReadAllowDiskBackedDecrypt(String relativeVaultPath) =>
      vaultPathAllowsDiskBackedDecrypt(relativeVaultPath);

  static Future<Uint8List?> readFile(
    String filePath, {
    int retries = 3,
    bool suppressLogs = false,
    bool allowMissing = false,
    void Function(double)? onProgress,
  }) async {
    final originalPath = filePath;

    filePath = _sanitisePath(filePath);

    if (!suppressLogs) {
      log.info(
        '[FileManager.readFile] Reading file: $filePath (original: $originalPath, vault: $_shouldUseVault, retries: $retries)',
      );
    }

    if (_shouldUseVault) {
      try {
        if (!VaultAdapter.isUnlocked) {
          if (!suppressLogs) {
            log.warning(
              '[FileManager.readFile] Vault locked, cannot read: $filePath',
            );
          }
          return null;
        }

        if (_isExternalTempPath(filePath)) {
          final tempBytes = await _readExternalTempFile(filePath);
          if (tempBytes != null) {
            return tempBytes;
          }
        }

        final relativePath = toRelativePath(filePath);
        if (!suppressLogs) {
          log.fine('[FileManager.readFile] Reading from vault: $relativePath');
        }

        final result = await VaultAdapter.instance.readFile(
          relativePath,
          onProgress: onProgress,
          allowDiskBackedDecrypt: _vaultReadAllowDiskBackedDecrypt(
            relativePath,
          ),
        );

        if (result != null) {
          if (result.isEmpty) {
            if (!suppressLogs && !allowMissing) {
              log.warning(
                '[FileManager.readFile] Read empty file from vault: $relativePath',
              );
            }
          } else {
            if (!suppressLogs) {
              log.info(
                '[FileManager.readFile] Successfully read ${result.length} bytes from vault: $relativePath',
              );
            }
          }
          return _maybeDecompressSbn2Note(result, filePath);
        }

        if (!suppressLogs && !allowMissing) {
          log.fine(
            '[FileManager.readFile] File not found in vault: $relativePath. (Likely a new note creation)',
          );
        }
        // SECURITY: If Vault is enabled, DO NOT fallback to disk.

        return null;
      } catch (e, stack) {
        if (!suppressLogs) {
          log.severe(
            '[FileManager.readFile] Error reading from vault: $filePath',
            e,
            stack,
          );
        }
        // SECURITY: Critical failure in vault read.
        // Do NOT allow flow to continue to disk operations.
        return null;
      }
    }

    // SECURITY CHECK:

    if (_shouldUseVault) {
      if (!suppressLogs) {
        log.severe(
          '[FileManager.readFile] Logic error: Vault enabled but fell through to disk read for $filePath',
        );
      }
      return null;
    }

    Uint8List? result;
    final file = getFile(filePath);
    if (file.existsSync()) {
      try {
        result = await file.readAsBytes();
        if (result.isEmpty) {
          if (!suppressLogs && !allowMissing) {
            log.warning('[FileManager.readFile] File is empty: $filePath');
          }
          result = null;
        } else {
          result = _maybeDecompressSbn2Note(result, filePath);
          if (!suppressLogs) {
            log.fine(
              '[FileManager.readFile] Successfully read ${result.length} bytes from disk: $filePath',
            );
          }
        }
      } catch (e, stack) {
        if (!suppressLogs) {
          log.severe(
            '[FileManager.readFile] Error reading from disk: $filePath',
            e,
            stack,
          );
        }
        result = null;
      }
    } else {
      if (!suppressLogs && !allowMissing) {
        log.warning('[FileManager.readFile] File does not exist: $filePath');
      }
      retries = 0;
    }

    if (result == null && retries > 0) {
      if (!suppressLogs) {
        log.fine('[FileManager.readFile] Retrying read from disk: $filePath');
      }
      await Future.delayed(const Duration(milliseconds: 100));
      return readFile(
        filePath,
        retries: retries - 1,
        suppressLogs: suppressLogs,
        allowMissing: allowMissing,
      );
    }
    return result;
  }

  static Future<String?> readFileToTempFile(
    String filePath, {
    void Function(double)? onProgress,
  }) async {
    if (!_shouldUseVault || !VaultAdapter.isUnlocked) return null;
    final relativePath = toRelativePath(filePath);
    // SECURITY: RAM-only policy — never create plaintext temp files.
    if (!_vaultReadAllowDiskBackedDecrypt(relativePath)) {
      log.fine(
        '[FileManager.readFileToTempFile] Refused (RAM-only): $relativePath',
      );
      return null;
    }
    return VaultAdapter.instance.readFileToTempFile(
      relativePath,
      onProgress: onProgress,
    );
  }

  static bool _isExternalTempPath(String path) {
    if (path.isEmpty) return false;
    final normalized = path.replaceAll('\\', '/').toLowerCase();
    final docs = documentsDirectory.replaceAll('\\', '/').toLowerCase();

    if (normalized.startsWith(docs)) return false;

    return normalized.contains('/cache/') ||
        normalized.contains('/tmp') ||
        normalized.contains('/file_picker/');
  }

  static Future<Uint8List?> _readExternalTempFile(String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) {
        return await file.readAsBytes();
      }
    } catch (_) {}
    return null;
  }

  @visibleForTesting
  static var shouldUseRawFilePath = false;

  /// Total bytes for note body + `.p` thumbnail + `.$n` assets (same as note properties).
  static Future<int> getNoteBundleSizeBytes(String noteBasePath) async {
    var base = _sanitisePath(noteBasePath).replaceAll('\\', '/');
    if (!base.startsWith('/')) base = '/$base';

    final ext = (await doesFileExist(base + Editor.extension))
        ? Editor.extension
        : (await doesFileExist(base + Editor.extensionOldJson))
        ? Editor.extensionOldJson
        : null;
    if (ext == null) return 0;

    final bundle = base + ext;
    var total = 0;
    total += await getFileSize(bundle);
    total += await getFileSize('$bundle.p');
    for (var assetNumber = 0; ; assetNumber++) {
      final assetSize = await getFileSize('$bundle.$assetNumber');
      if (assetSize == 0) break;
      total += assetSize;
    }
    return total;
  }

  /// List row metadata for [noteBasePath] without `.sbn2` / `.sbn` — same fields as
  /// opening properties (note timestamps + bundle size). Returns null if missing or unreadable.
  ///
  /// In vault mode this uses the SQLCipher index (size + last_modified) and does
  /// **not** AES-decrypt the note body — list scrolling must stay cheap.
  static Future<NoteListRowStats?> getNoteListRowStats(
    String noteBasePath,
  ) async {
    var base = _sanitisePath(noteBasePath).replaceAll('\\', '/');
    if (!base.startsWith('/')) base = '/$base';

    final ext = (await doesFileExist(base + Editor.extension))
        ? Editor.extension
        : (await doesFileExist(base + Editor.extensionOldJson))
        ? Editor.extensionOldJson
        : null;
    if (ext == null) return null;

    final full = base + ext;
    if (!await doesFileExist(full)) return null;

    try {
      final sizeBytes = await getNoteBundleSizeBytes(base);
      final modified = await lastModified(full);

      if (_shouldUseVault) {
        // Avoid full note decrypt just to populate list chips.
        return NoteListRowStats(
          sizeBytes: sizeBytes,
          created: modified,
          modified: modified,
          accessed: modified,
        );
      }

      final core = await EditorCoreInfo.loadFromFilePath(
        base,
        readOnly: true,
        onlyFirstPage: true,
      );
      final created = core.creationDate > 0
          ? DateTime.fromMillisecondsSinceEpoch(core.creationDate)
          : modified;
      final mod = core.lastModification > 0
          ? DateTime.fromMillisecondsSinceEpoch(core.lastModification)
          : modified;
      final accessed = core.lastAccess > 0
          ? DateTime.fromMillisecondsSinceEpoch(core.lastAccess)
          : mod;
      return NoteListRowStats(
        sizeBytes: sizeBytes,
        created: created,
        modified: mod,
        accessed: accessed,
      );
    } catch (_) {
      return null;
    }
  }

  static File getFile(String filePath) {
    if (shouldUseRawFilePath) {
      return File(fixFileNameDelimiters(filePath));
    } else {
      final cleanPath = fixFileNameDelimiters(filePath);
      final cleanDocs = fixFileNameDelimiters(documentsDirectory);

      if (cleanPath.startsWith(cleanDocs)) {
        return File(cleanPath);
      }

      assert(
        filePath.startsWith('/'),
        'Expected filePath to start with a slash, got $filePath',
      );
      return File(fixFileNameDelimiters(documentsDirectory + filePath));
    }
  }

  static String getFilePath(String filePath) {
    if (shouldUseRawFilePath) {
      return fixFileNameDelimiters(filePath);
    } else {
      assert(
        filePath.startsWith('/'),
        'Expected filePath to start with a slash, got $filePath',
      );
      return fixFileNameDelimiters('$documentsDirectory$filePath');
    }
  }

  static Directory getRootDirectory() => Directory(documentsDirectory);

  static Future<void> writeFile(
    String filePath,
    List<int> toWrite, {
    bool awaitWrite = false,
    bool? awaitDbCommit,
    bool alsoUpload = true,
    DateTime? lastModified,
  }) async {
    final commitVaultDb = awaitDbCommit ?? awaitWrite;
    final originalPath = filePath;

    filePath = _sanitisePath(filePath);

    log.info(
      '[FileManager.writeFile] Writing ${toWrite.length} bytes to: $filePath (original: $originalPath, vault: $_shouldUseVault)',
    );

    await _saveFileAsRecentlyAccessed(filePath);

    if (_shouldUseVault) {
      final relativePath = toRelativePath(filePath);

      // Hand off raw note bytes; vault worker does zlib + encrypt together so
      // the UI isolate never pays sync compress or a second isolate spawn.
      final dataToWrite = toWrite is Uint8List
          ? toWrite
          : Uint8List.fromList(toWrite);
      final compressZlib = filePath.endsWith(Editor.extension);

      log.info(
        '[FileManager.writeFile] Writing to vault: $relativePath (${dataToWrite.length} bytes, awaitWrite: $awaitWrite)',
      );

      if (!VaultAdapter.isUnlocked) {
        log.severe(
          '[FileManager.writeFile] Vault is locked, cannot write: $relativePath',
        );
        throw Exception('Vault is locked, cannot write file: $relativePath');
      }

      Future<void> runVaultWrite() async {
        try {
          final success = await VaultAdapter.instance.writeFile(
            relativePath,
            dataToWrite,
            lastModified: lastModified,
            awaitDbCommit: commitVaultDb,
            compressZlib: compressZlib,
          );
          if (!success) {
            throw Exception('Failed to write file to vault: $relativePath');
          }
          log.info(
            '[FileManager.writeFile] Successfully wrote to vault: $relativePath',
          );
          _rememberThumbnailBytes(filePath, dataToWrite);
          broadcastFileWrite(FileOperationType.write, filePath);
          if (filePath.endsWith(Editor.extension)) {
            _removeReferences(
              '${filePath.substring(0, filePath.length - Editor.extension.length)}'
              '${Editor.extensionOldJson}',
            );
          }
        } catch (e, stack) {
          log.severe(
            '[FileManager.writeFile] Error writing to vault: $filePath',
            e,
            stack,
          );
          rethrow;
        }
      }

      if (awaitWrite) {
        await runVaultWrite();
      } else {
        unawaited(
          Future.delayed(Duration.zero, () async {
            try {
              await runVaultWrite();
            } catch (e) {
              log.warning(
                '[FileManager.writeFile] Background vault save error: $e',
              );
            }
          }),
        );
      }
      return;
    }

    try {
      final file = getFile(filePath);

      final bool isNewFile = !file.existsSync();
      final int oldSize = isNewFile ? 0 : file.lengthSync();

      await _createFileDirectory(filePath);

      List<int> dataToWrite = toWrite;
      if (filePath.endsWith(Editor.extension)) {
        try {
          bool alreadyCompressed = false;
          if (toWrite.length > 2) {
            final cmf = toWrite[0];
            final flg = toWrite[1];
            if (cmf == 0x78 && ((cmf << 8) + flg) % 31 == 0) {
              alreadyCompressed = true;
            }
          }
          if (!alreadyCompressed) {
            final bytes = toWrite is Uint8List
                ? toWrite
                : Uint8List.fromList(toWrite);
            // Lower threshold to 64KB to avoid UI thread blocking during autosave
            dataToWrite = bytes.length >= 64 * 1024
                ? await compute(_zlibEncodeBytes, bytes)
                : const ZLibEncoder().encode(bytes);
          }
        } catch (e) {
          log.warning('Failed to compress file: $filePath', e);
        }
      }

      Future writeFuture = Future.wait([
        file.writeAsBytes(dataToWrite).then((file) async {
          if (lastModified != null) await file.setLastModified(lastModified);
        }),

        if (filePath.endsWith(Editor.extension))
          getFile(
            '${filePath.substring(0, filePath.length - Editor.extension.length)}'
            '${Editor.extensionOldJson}',
          ).delete().catchError(
            (_) => File(''),
            test: (e) => e is PathNotFoundException,
          ),
      ]);

      void afterWrite() {
        log.fine(
          '[FileManager.writeFile] Successfully wrote to disk: $filePath',
        );

        final tracksSize = isFolderSizeTrackedFile(filePath);
        final tracksCount = isCountableFile(filePath);
        if (tracksSize || tracksCount) {
          final newSize = dataToWrite.length;
          _updateDiskFolderProps(
            filePath,
            tracksCount && isNewFile ? 1 : 0,
            tracksSize ? newSize - oldSize : 0,
          );
        }
        _rememberThumbnailBytes(filePath, dataToWrite);
        broadcastFileWrite(FileOperationType.write, filePath);
        if (filePath.endsWith(Editor.extension)) {
          _removeReferences(
            '${filePath.substring(0, filePath.length - Editor.extension.length)}'
            '${Editor.extensionOldJson}',
          );
        }
      }

      writeFuture = writeFuture.then((_) => afterWrite());
      if (awaitWrite) await writeFuture;
    } catch (e, stack) {
      log.severe(
        '[FileManager.writeFile] Error writing to disk: $filePath',
        e,
        stack,
      );
      rethrow;
    }
  }

  static Future<void> writeFileFromPath(
    String sourcePath,
    String filePath, {
    bool awaitWrite = false,
    bool? awaitDbCommit,
  }) async {
    final commitVaultDb = awaitDbCommit ?? awaitWrite;
    filePath = _sanitisePath(filePath);
    if (_shouldUseVault) {
      final relativePath = toRelativePath(filePath);
      if (!VaultAdapter.isUnlocked) {
        throw Exception('Vault is locked');
      }
      await VaultAdapter.instance.writeFileFromPath(
        sourcePath,
        relativePath,
        awaitDbCommit: commitVaultDb,
      );
      broadcastFileWrite(FileOperationType.write, filePath);
      return;
    }
    await _createFileDirectory(filePath);
    final dest = getFile(filePath);
    final isNewFile = !dest.existsSync();
    final oldSize = isNewFile ? 0 : dest.lengthSync();
    await File(sourcePath).copy(dest.path);
    final tracksCount = isCountableFile(filePath);
    final tracksSize = isFolderSizeTrackedFile(filePath);
    if (tracksCount || tracksSize) {
      await _updateDiskFolderProps(
        filePath,
        tracksCount && isNewFile ? 1 : 0,
        tracksSize ? dest.lengthSync() - oldSize : 0,
      );
    }
    broadcastFileWrite(FileOperationType.write, filePath);
  }

  static Future<void> writeFilesBulk(
    Map<String, Uint8List> files, {
    bool awaitWrite = true,
    bool? awaitDbCommit,
  }) async {
    final commitVaultDb = awaitDbCommit ?? awaitWrite;
    final sw = Stopwatch()..start();
    if (_shouldUseVault) {
      final relativeFiles = <String, Uint8List>{};
      files.forEach((path, data) {
        relativeFiles[toRelativePath(path)] = data;
      });

      if (!VaultAdapter.isUnlocked) {
        throw Exception('Vault is locked');
      }
      await VaultAdapter.instance.writeFilesBulk(
        relativeFiles,
        awaitDbCommit: commitVaultDb,
      );

      for (final path in files.keys) {
        broadcastFileWrite(FileOperationType.write, path);
      }
    } else {
      for (final entry in files.entries) {
        await writeFile(entry.key, entry.value, awaitWrite: true);
      }
    }
    final msg =
        '[PERF][FileManager.writeFilesBulk] ${sw.elapsedMilliseconds}ms (files=${files.length}, vault=$_shouldUseVault)';
    if (sw.elapsedMilliseconds >= 120) {
      log.info(msg);
    } else {
      log.fine(msg);
    }
  }

  static Future<void> copyFile(
    File fileFrom,
    String filePath, {
    bool awaitWrite = false,
    bool alsoUpload = true,
    DateTime? lastModified,
  }) async {
    filePath = _sanitisePath(filePath);
    log.info(
      '[FileManager.copyFile] Copying from ${fileFrom.path} to $filePath (vault: $_shouldUseVault)',
    );

    if (_shouldUseVault) {
      try {
        final relativePath = toRelativePath(filePath);

        Uint8List? sourceData;

        if (await fileFrom.exists()) {
          sourceData = await fileFrom.readAsBytes();
        } else {
          final sourceRelative = toRelativePath(fileFrom.path);
          sourceData = await VaultAdapter.instance.readFile(
            sourceRelative,
            allowDiskBackedDecrypt: _vaultReadAllowDiskBackedDecrypt(
              sourceRelative,
            ),
          );
        }

        if (sourceData == null) {
          log.severe(
            '[FileManager.copyFile] Source file not found: ${fileFrom.path}',
          );
          throw Exception('Source file not found: ${fileFrom.path}');
        }

        final success = await VaultAdapter.instance.writeFile(
          relativePath,
          sourceData,
          lastModified: lastModified,
        );

        if (success) {
          log.fine(
            '[FileManager.copyFile] Successfully copied to vault: $filePath',
          );
          await _saveFileAsRecentlyAccessed(filePath);
          broadcastFileWrite(FileOperationType.write, filePath);
          if (filePath.endsWith(Editor.extension)) {
            _removeReferences(
              '${filePath.substring(0, filePath.length - Editor.extension.length)}'
              '${Editor.extensionOldJson}',
            );
          }
        } else {
          log.severe(
            '[FileManager.copyFile] Failed to copy to vault: $filePath',
          );
          throw Exception('Failed to copy file to vault');
        }
      } catch (e, stack) {
        log.severe(
          '[FileManager.copyFile] Error copying to vault: $filePath',
          e,
          stack,
        );
        rethrow;
      }
      return;
    }

    await _createFileDirectory(filePath);

    final relativePathForCount = filePath;
    final fullPath = getFilePath(filePath);
    final isNewFile = !getFile(relativePathForCount).existsSync();

    filePath = fullPath;
    if (fileFrom.path == filePath) {
      log.fine(
        '[FileManager.copyFile] Source and destination are the same, skipping: $filePath',
      );
      return;
    }

    try {
      final int oldSize = isNewFile
          ? 0
          : getFile(relativePathForCount).lengthSync();
      await _saveFileAsRecentlyAccessed(filePath);
      final file = await fileFrom.copy(filePath);
      Future writeFuture = Future.wait([
        if (lastModified != null) file.setLastModified(lastModified),

        if (relativePathForCount.endsWith(Editor.extension))
          getFile(
            '${relativePathForCount.substring(0, relativePathForCount.length - Editor.extension.length)}'
            '${Editor.extensionOldJson}',
          ).delete().catchError(
            (_) => File(''),
            test: (e) => e is PathNotFoundException,
          ),
      ]);

      void afterWrite() async {
        log.fine(
          '[FileManager.copyFile] Successfully copied to disk: $filePath',
        );
        final tracksSize = isFolderSizeTrackedFile(relativePathForCount);
        final tracksCount = isCountableFile(relativePathForCount);
        if (tracksSize || tracksCount) {
          final newSize = fileFrom.lengthSync();
          _updateDiskFolderProps(
            relativePathForCount,
            tracksCount && isNewFile ? 1 : 0,
            tracksSize ? newSize - oldSize : 0,
          );
        }
        broadcastFileWrite(FileOperationType.write, filePath);
        if (relativePathForCount.endsWith(Editor.extension)) {
          _removeReferences(
            '${relativePathForCount.substring(0, relativePathForCount.length - Editor.extension.length)}'
            '${Editor.extensionOldJson}',
          );
        }
      }

      writeFuture = writeFuture.then((_) => afterWrite());
      if (awaitWrite) await writeFuture;
    } catch (e, stack) {
      log.severe(
        '[FileManager.copyFile] Error copying to disk: $filePath',
        e,
        stack,
      );
      rethrow;
    }
  }

  static Future<void> markFileAsSaved(
    File fileFrom, {
    bool awaitWrite = false,
    bool alsoUpload = true,
  }) async {
    log.fine('Marking file as Saved');

    await _saveFileAsRecentlyAccessed(fileFrom.path);
    broadcastFileWrite(FileOperationType.write, fileFrom.path);
    if (fileFrom.path.endsWith(Editor.extension)) {
      _removeReferences(
        '${fileFrom.path.substring(0, fileFrom.path.length - Editor.extension.length)}'
        '${Editor.extensionOldJson}',
      );
    }
  }

  static Future<void> duplicateFile(String filePath) async {
    filePath = _sanitisePath(filePath);
    log.info(
      '[FileManager.duplicateFile] Duplicating file: $filePath (vault: $_shouldUseVault)',
    );

    final oldPathWithoutExt = filePath;

    String ext;
    if (_shouldUseVault) {
      final oldRelative = toRelativePath(oldPathWithoutExt);
      final hasOldJson = await VaultAdapter.instance.fileExists(
        oldRelative + Editor.extensionOldJson,
      );
      ext = hasOldJson ? Editor.extensionOldJson : Editor.extension;
    } else {
      ext = await doesFileExist(oldPathWithoutExt + Editor.extensionOldJson)
          ? Editor.extensionOldJson
          : Editor.extension;
    }

    final oldPathWithExt = oldPathWithoutExt + ext;
    final newPathWithoutExt = await suffixFilePathToMakeItUnique(
      oldPathWithoutExt,
    );
    final newPathWithExt = newPathWithoutExt + ext;

    if (_shouldUseVault) {
      try {
        final oldRelative = toRelativePath(oldPathWithExt);
        final newRelative = toRelativePath(newPathWithExt);

        final data = await VaultAdapter.instance.readFile(
          oldRelative,
          allowDiskBackedDecrypt: _vaultReadAllowDiskBackedDecrypt(oldRelative),
        );
        if (data != null) {
          await VaultAdapter.instance.writeFile(newRelative, data);
          log.fine(
            '[FileManager.duplicateFile] Copied main file to vault: $newRelative',
          );
        }
      } catch (e, stack) {
        log.severe(
          '[FileManager.duplicateFile] Error duplicating main file in vault: $oldPathWithExt',
          e,
          stack,
        );
        rethrow;
      }
    } else {
      final oldFile = getFile(oldPathWithExt);
      final newFile = getFile(newPathWithExt);
      if (oldFile.existsSync()) {
        await oldFile.copy(newFile.path);
        log.fine(
          '[FileManager.duplicateFile] Copied main file to disk: $newPathWithExt',
        );
        if (isCountableFile(newPathWithExt)) {
          final size = await newFile.length();
          await _updateDiskFolderProps(newPathWithExt, 1, size);
        }
      }
    }

    final assets = <String>[];
    for (int assetNumber = 0; true; assetNumber++) {
      final assetPath = '$oldPathWithExt.$assetNumber';
      bool exists;
      if (_shouldUseVault) {
        final assetRelative = toRelativePath(assetPath);
        exists = await VaultAdapter.instance.fileExists(assetRelative);
      } else {
        exists = getFile(assetPath).existsSync();
      }

      if (exists) {
        assets.add(assetNumber.toString());
      } else {
        break;
      }
    }

    final previewPath = '$oldPathWithExt.p';
    bool previewExists;
    if (_shouldUseVault) {
      final previewRelative = toRelativePath(previewPath);
      previewExists = await VaultAdapter.instance.fileExists(previewRelative);
    } else {
      previewExists = getFile(previewPath).existsSync();
    }

    if (previewExists) {
      assets.add('p');
    }

    if (_shouldUseVault) {
      try {
        await Future.wait([
          for (final assetExt in assets)
            () async {
              final oldAssetPath = '$oldPathWithExt.$assetExt';
              final newAssetPath = '$newPathWithExt.$assetExt';

              final oldRelative = toRelativePath(oldAssetPath);
              final newRelative = toRelativePath(newAssetPath);

              final data = await VaultAdapter.instance.readFile(
                oldRelative,
                allowDiskBackedDecrypt: _vaultReadAllowDiskBackedDecrypt(
                  oldRelative,
                ),
              );
              if (data != null) {
                await VaultAdapter.instance.writeFile(newRelative, data);
              }
            }(),
        ]);
        log.fine(
          '[FileManager.duplicateFile] Copied ${assets.length} assets to vault for: $newPathWithoutExt',
        );
      } catch (e, stack) {
        log.severe(
          '[FileManager.duplicateFile] Error duplicating assets in vault: $oldPathWithExt',
          e,
          stack,
        );
        rethrow;
      }
    } else {
      final copiedAssetSizes = await Future.wait([
        for (final assetExt in assets)
          getFile(
            '$oldPathWithExt.$assetExt',
          ).copy(getFile('$newPathWithExt.$assetExt').path),
      ]);
      final assetSize = copiedAssetSizes.fold<int>(
        0,
        (total, file) => total + file.lengthSync(),
      );
      if (assetSize != 0) {
        await _updateDiskFolderProps(newPathWithExt, 0, assetSize);
      }
      log.fine(
        '[FileManager.duplicateFile] Copied ${assets.length} assets to disk for: $newPathWithoutExt',
      );
    }

    broadcastFileWrite(FileOperationType.write, newPathWithoutExt);
    log.info(
      '[FileManager.duplicateFile] Successfully duplicated: $oldPathWithoutExt -> $newPathWithoutExt',
    );
  }

  static Future<void> createFolder(String folderPath) async {
    if (_shouldUseVault) {
      folderPath = toRelativePath(folderPath);
      log.info(
        '[FileManager.createFolder] Creating folder in vault: $folderPath',
      );
      await VaultAdapter.instance.createFolder(folderPath);
      broadcastFileWrite(FileOperationType.write, folderPath);
      return;
    }
    folderPath = _sanitisePath(folderPath);

    final dir = Directory(documentsDirectory + folderPath);
    await dir.create(recursive: true);

    broadcastFileWrite(FileOperationType.write, folderPath);
  }

  static Future<void> saveFileToPath(List<int> bytes, String filePath) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  static Future exportFile(
    String fileName,
    List<int> bytes, {
    bool isImage = false,
    String? saveToPath,
    required BuildContext context,
  }) async {
    File? tempFile;
    Future<File> getTempFile() async {
      final tempFolder = (await getTemporaryDirectory()).path;
      final file = File('$tempFolder/$fileName');
      await file.writeAsBytes(bytes);
      return file;
    }

    VaultAdapter.preventLock = true;
    try {
      if (isImage) {
        var savedToGallery = false;
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          try {
            final permissionGranted = await _requestPhotosPermission();
            if (permissionGranted) {
              await SaverGallery.saveImage(
                Uint8List.fromList(bytes),
                fileName: fileName,
                androidRelativePath: 'Pictures/Saber',
                skipIfExists: true,
              );
              savedToGallery = true;
            }
          } catch (e, st) {
            log.warning('[exportFile] SaverGallery (Android): $e', e, st);
          }
        } else {
          try {
            await SaverGallery.saveImage(
              Uint8List.fromList(bytes),
              fileName: fileName,
              androidRelativePath: 'Pictures/Saber',
              skipIfExists: true,
            );
            savedToGallery = true;
          } catch (e, st) {
            log.fine('[exportFile] SaverGallery: $e', e, st);
          }
        }
        if (!savedToGallery) {
          if (saveToPath != null && saveToPath.isNotEmpty) {
            await saveFileToPath(bytes, p.join(saveToPath, fileName));
          } else {
            tempFile = await getTempFile();
            await SharePlus.instance.share(
              ShareParams(files: [XFile(tempFile.path)]),
            );
          }
        }
      } else if (saveToPath != null && saveToPath.isNotEmpty) {
        await saveFileToPath(bytes, p.join(saveToPath, fileName));
      } else {
        tempFile = await getTempFile();
        await SharePlus.instance.share(
          ShareParams(files: [XFile(tempFile.path)]),
        );
      }
    } finally {
      VaultAdapter.preventLock = false;
    }

    if (tempFile != null) {
      await secureDelete(tempFile);
    }
  }

  /// Shares or copies an arbitrary temp file (ZIP, PDF, …), then securely deletes it.
  static Future<void> exportTempFile(
    String tempPath,
    String fileName, {
    String? saveToPath,
    required BuildContext context,
  }) async {
    final source = File(tempPath);
    VaultAdapter.preventLock = true;
    try {
      if (saveToPath != null && saveToPath.isNotEmpty) {
        final dest = File(p.join(saveToPath, fileName));
        await dest.parent.create(recursive: true);
        await source.copy(dest.path);
      } else {
        await SharePlus.instance.share(
          ShareParams(files: [XFile(tempPath, name: fileName)]),
        );
      }
    } finally {
      VaultAdapter.preventLock = false;
      await secureDelete(source);
    }
  }

  /// Shares or copies a PDF already on disk (e.g. large pdfrx export), then
  /// securely deletes [tempPdfPath]. Do not use the path after this returns.
  static Future<void> exportPdfTempFile(
    String tempPdfPath,
    String fileName, {
    String? saveToPath,
    required BuildContext context,
  }) => exportTempFile(
    tempPdfPath,
    fileName,
    saveToPath: saveToPath,
    context: context,
  );

  static Future<List<({String notePath, String archivePath})>>
  getNotePathsInFolder(
    String folderPath, {
    required String archiveRootName,
    Set<String> ancestorTargets = const {},
  }) async {
    final normalizedSource = toRelativePath(folderPath);
    final normalizedArchiveDir = _sanitizeArchiveEntryName(archiveRootName);

    if (!await isDirectory(normalizedSource)) return [];

    final results = <({String notePath, String archivePath})>[];
    final nextAncestors = {...ancestorTargets, normalizedSource};

    final children = await getChildrenOfDirectory(
      normalizedSource,
      includeExtensions: true,
      includeAssets: false,
    );
    if (children == null) return results;

    for (final directoryName in children.directories) {
      if (_shouldSkipFolderArchiveDirectory(directoryName)) continue;
      final childSourcePath = p.posix
          .join(normalizedSource, directoryName)
          .replaceAll('//', '/');
      final childTarget = toRelativePath(childSourcePath);
      if (nextAncestors.contains(childTarget)) continue;

      results.addAll(
        await getNotePathsInFolder(
          childSourcePath,
          archiveRootName: p.posix.join(normalizedArchiveDir, directoryName),
          ancestorTargets: nextAncestors,
        ),
      );
    }

    for (final fileName in children.files) {
      final notePath = _notePathFromMainNoteFile(fileName);
      if (notePath == null) continue;
      final fullNotePath = p.posix.join(normalizedSource, notePath);
      final ext = fileName.endsWith(Editor.extension)
          ? Editor.extension
          : Editor.extensionOldJson;
      final baseName = fileName.substring(0, fileName.length - ext.length);
      results.add((
        notePath: fullNotePath,
        archivePath: p.posix.join(normalizedArchiveDir, '$baseName'),
      ));
    }

    final links = await FolderLinkManager.getLinks(normalizedSource);
    for (final entry in links.entries) {
      final linkName = entry.key;
      if (linkName.startsWith('.')) continue;
      final targetPath = toRelativePath(entry.value);
      if (await isDirectory(targetPath)) {
        if (nextAncestors.contains(targetPath)) continue;
        results.addAll(
          await getNotePathsInFolder(
            targetPath,
            archiveRootName: p.posix.join(normalizedArchiveDir, linkName),
            ancestorTargets: {...nextAncestors, targetPath},
          ),
        );
      } else {
        final notePath = _notePathFromMainNoteFile(linkName);
        if (notePath == null) continue;
        final ext = linkName.endsWith(Editor.extension)
            ? Editor.extension
            : Editor.extensionOldJson;
        final baseName = linkName.substring(0, linkName.length - ext.length);
        results.add((
          notePath: targetPath,
          archivePath: p.posix.join(normalizedArchiveDir, '$baseName'),
        ));
      }
    }

    return results;
  }

  static Future<FolderArchiveData> createFolderArchive(
    String folderPath, {
    required String archiveRootName,
    FolderArchiveFormat format = FolderArchiveFormat.zip,
  }) async {
    final normalizedFolderPath = toRelativePath(folderPath);
    if (!await isDirectory(normalizedFolderPath)) {
      throw StateError('Folder not found: $normalizedFolderPath');
    }

    final archive = Archive();
    final stats = _FolderArchiveStats();
    final archiveRoot = _sanitizeArchiveEntryName(archiveRootName);

    await _appendFolderToArchive(
      archive,
      sourceDirectoryPath: normalizedFolderPath,
      archiveDirectoryPath: archiveRoot,
      ancestorTargets: {normalizedFolderPath},
      stats: stats,
    );

    final bytes = await encodeFolderArchiveAsync(archive, format);
    return FolderArchiveData(
      fileName: '$archiveRoot.${format.extension}',
      bytes: bytes,
      skippedMissingTargets: stats.skippedMissingTargets,
      skippedCyclicLinks: stats.skippedCyclicLinks,
    );
  }

  static Uint8List encodeFolderArchive(
    Archive archive,
    FolderArchiveFormat format,
  ) {
    switch (format) {
      case FolderArchiveFormat.zip:
        final zipBytes = ZipEncoder().encode(archive);
        return Uint8List.fromList(zipBytes);
      case FolderArchiveFormat.tarXz:
        final tarBytes = TarEncoder().encode(archive);
        final xzBytes = XZEncoder().encode(tarBytes);
        return Uint8List.fromList(xzBytes);
    }
  }

  static Future<Uint8List> encodeFolderArchiveAsync(
    Archive archive,
    FolderArchiveFormat format,
  ) {
    return compute(_isolateEncodeFolderArchive, {
      'archive': archive,
      'format': format,
    });
  }

  static Future<void> _appendFolderToArchive(
    Archive archive, {
    required String sourceDirectoryPath,
    required String archiveDirectoryPath,
    required Set<String> ancestorTargets,
    required _FolderArchiveStats stats,
  }) async {
    final normalizedSource = toRelativePath(sourceDirectoryPath);
    final normalizedArchiveDir = _sanitizeArchiveEntryName(
      archiveDirectoryPath,
    );
    archive.add(ArchiveFile.directory('$normalizedArchiveDir/'));

    final children = await getChildrenOfDirectory(
      normalizedSource,
      includeExtensions: true,
      includeAssets: true,
    );
    if (children == null) {
      stats.skippedMissingTargets++;
      return;
    }

    for (final directoryName in children.directories) {
      if (_shouldSkipFolderArchiveDirectory(directoryName)) continue;

      final childSourcePath = p.posix
          .join(normalizedSource, directoryName)
          .replaceAll('//', '/');
      final childTarget = toRelativePath(childSourcePath);
      final nextAncestors = {...ancestorTargets, childTarget};

      await _appendFolderToArchive(
        archive,
        sourceDirectoryPath: childSourcePath,
        archiveDirectoryPath: p.posix.join(normalizedArchiveDir, directoryName),
        ancestorTargets: nextAncestors,
        stats: stats,
      );
    }

    for (final fileName in children.files) {
      if (_shouldSkipFolderArchiveFile(fileName)) continue;

      final filePath = p.posix.join(normalizedSource, fileName);
      final bytes = await _readFileForArchive(filePath);
      if (bytes == null) {
        stats.skippedMissingTargets++;
        continue;
      }

      archive.addFile(
        ArchiveFile(
          p.posix.join(normalizedArchiveDir, fileName),
          bytes.length,
          bytes,
        ),
      );
    }

    final links = await FolderLinkManager.getLinks(normalizedSource);
    for (final entry in links.entries) {
      final linkName = entry.key;
      if (linkName.startsWith('.')) continue;

      final targetPath = toRelativePath(entry.value);
      if (await isDirectory(targetPath)) {
        if (ancestorTargets.contains(targetPath)) {
          stats.skippedCyclicLinks++;
          continue;
        }

        final nextAncestors = {...ancestorTargets, targetPath};
        await _appendFolderToArchive(
          archive,
          sourceDirectoryPath: targetPath,
          archiveDirectoryPath: p.posix.join(normalizedArchiveDir, linkName),
          ancestorTargets: nextAncestors,
          stats: stats,
        );
        continue;
      }

      if (_shouldSkipFolderArchiveFile(linkName)) continue;

      final bytes = await _readFileForArchive(targetPath);
      if (bytes == null) {
        stats.skippedMissingTargets++;
        continue;
      }

      archive.addFile(
        ArchiveFile(
          p.posix.join(normalizedArchiveDir, linkName),
          bytes.length,
          bytes,
        ),
      );
    }
  }

  static Future<Uint8List?> _readFileForArchive(String filePath) async {
    final bytes = await readFile(
      filePath,
      suppressLogs: true,
      allowMissing: true,
    );
    if (bytes == null) return null;
    if (!filePath.endsWith(Editor.extension)) return bytes;

    try {
      final alreadyCompressed =
          bytes.length > 2 &&
          bytes[0] == 0x78 &&
          ((bytes[0] << 8) + bytes[1]) % 31 == 0;
      if (alreadyCompressed) return bytes;
      return Uint8List.fromList(const ZLibEncoder().encode(bytes));
    } catch (_) {
      return bytes;
    }
  }

  static bool _shouldSkipFolderArchiveDirectory(String directoryName) {
    return directoryName.startsWith('.');
  }

  static bool _shouldSkipFolderArchiveFile(String fileName) {
    if (fileName.startsWith('.')) return true;
    if (fileName.startsWith('TmPmP_')) return true;
    if (fileName.endsWith('.p')) return true;
    return false;
  }

  static String _sanitizeArchiveEntryName(String name) {
    final normalized = name
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^/+'), '');
    final safe = p.posix
        .normalize(normalized)
        .replaceFirst(RegExp(r'^(\.\./)+'), '');
    return safe.isEmpty ? 'folder' : safe;
  }

  static Future<void> secureDelete(File file) async {
    if (!await file.exists()) return;
    try {
      await compute(isolateSecureDeletePaths, [file.path]);
    } catch (e) {
      log.warning('Secure wipe failed: $e');
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  static Future<bool> _requestPhotosPermission() async {
    final sdkInt = await DeviceInfoPlugin().androidInfo.then(
      (info) => info.version.sdkInt,
    );
    if (sdkInt > 33) {
      return await Permission.photos.request().isGranted;
    } else {
      return await Permission.storage.request().isGranted;
    }
  }

  static String? _notePathFromMainNoteFile(String path) {
    if (assetFileRegex.hasMatch(path)) return null;
    if (path.endsWith(Editor.extension)) {
      return path.substring(0, path.length - Editor.extension.length);
    }
    if (path.endsWith(Editor.extensionOldJson)) {
      return path.substring(0, path.length - Editor.extensionOldJson.length);
    }
    return null;
  }

  static Future<String> moveFile(
    String fromPath,
    String toPath, {
    bool replaceExistingFile = false,
    bool alsoMoveAssets = true,
  }) async {
    fromPath = _sanitisePath(fromPath);
    toPath = _sanitisePath(toPath);

    if (!await doesFileExist(fromPath)) {
      log.fine(
        '[FileManager.moveFile] Source already moved or deleted: $fromPath',
      );
      return toPath;
    }

    log.info(
      '[FileManager.moveFile] Moving file: $fromPath -> $toPath (vault: $_shouldUseVault, alsoMoveAssets: $alsoMoveAssets)',
    );

    if (!toPath.contains('/')) {
      toPath = fromPath.substring(0, fromPath.lastIndexOf('/') + 1) + toPath;
    }

    if (!replaceExistingFile || Editor.isReservedPath(toPath)) {
      toPath = await suffixFilePathToMakeItUnique(
        toPath,
        currentPath: fromPath,
      );
    }

    if (fromPath == toPath) {
      log.fine(
        '[FileManager.moveFile] Source and destination are the same, skipping: $fromPath',
      );
      return toPath;
    }

    final fromNotePath = _notePathFromMainNoteFile(fromPath);
    final toNotePath = _notePathFromMainNoteFile(toPath);

    if (_shouldUseVault) {
      try {
        final fromRelative = toRelativePath(fromPath);
        final toRelative = toRelativePath(toPath);

        final success = await VaultAdapter.instance.moveFile(
          fromRelative,
          toRelative,
        );

        if (!success) {
          log.severe(
            '[FileManager.moveFile] Failed to move file in vault: $fromRelative -> $toRelative',
          );
          throw Exception('Failed to move file in vault');
        }

        if (alsoMoveAssets && !assetFileRegex.hasMatch(fromRelative)) {
          final assets = await VaultAdapter.instance.getAssetPathsForBase(
            fromRelative,
          );

          // Ciphertext-only moves (no decrypt). Preserve Temp/RAM policy.
          await Future.wait([
            for (final assetPath in assets)
              () async {
                if (!assetPath.startsWith(fromRelative)) return;
                final suffix = assetPath.substring(fromRelative.length);
                final newAssetPath = '$toRelative$suffix';
                final ok = await VaultAdapter.instance.moveFile(
                  assetPath,
                  newAssetPath,
                );
                if (!ok) {
                  log.warning(
                    '[FileManager.moveFile] Vault asset move failed: '
                    '$assetPath -> $newAssetPath',
                  );
                }
              }(),
          ]);
          log.fine(
            '[FileManager.moveFile] Moved ${assets.length} assets and preview in vault',
          );
        }

        _renameReferences(fromPath, toPath);
        broadcastFileWrite(
          FileOperationType.delete,
          fromPath,
          removal: _removalCauseForRelocate(fromPath, toPath),
        );
        broadcastFileWrite(FileOperationType.write, toPath);
        log.info(
          '[FileManager.moveFile] Successfully moved in vault: $fromPath -> $toPath',
        );
      } catch (e, stack) {
        log.severe(
          '[FileManager.moveFile] Error moving file in vault: $fromPath -> $toPath',
          e,
          stack,
        );
        rethrow;
      }
    }

    final fromFile = getFile(fromPath);
    final toFile = getFile(toPath);
    await _createFileDirectory(toPath);
    if (fromFile.existsSync()) {
      try {
        final int fileSize = fromFile.lengthSync();

        await fromFile.rename(toFile.path);
        log.fine(
          '[FileManager.moveFile] Successfully moved on disk: $fromPath -> $toPath',
        );
        await _updateDiskFolderPropsMove(fromPath, toPath, fileSize);
      } catch (e, stack) {
        log.severe(
          '[FileManager.moveFile] Error moving file on disk: $fromPath -> $toPath',
          e,
          stack,
        );
        rethrow;
      }
    } else {
      log.warning(
        '[FileManager.moveFile] Tried to move non-existent file from $fromPath to $toPath',
      );
    }

    _renameReferences(fromPath, toPath);
    broadcastFileWrite(
      FileOperationType.delete,
      fromPath,
      removal: _removalCauseForRelocate(fromPath, toPath),
    );
    broadcastFileWrite(FileOperationType.write, toPath);

    if (alsoMoveAssets && !assetFileRegex.hasMatch(fromPath)) {
      final assets = <String>[];
      for (int assetNumber = 0; true; assetNumber++) {
        final assetFile = getFile('$fromPath.$assetNumber');
        if (assetFile.existsSync()) {
          assets.add('$assetNumber');
        } else {
          break;
        }
      }
      {
        const assetNumber = 'p';
        final assetFile = getFile('$fromPath.$assetNumber');
        if (assetFile.existsSync()) {
          assets.add(assetNumber);
        }
      }

      await Future.wait([
        for (final assetNumber in assets)
          moveFile(
            '$fromPath.$assetNumber',
            '$toPath.$assetNumber',
            replaceExistingFile: replaceExistingFile,
          ),
      ]);
      log.fine('[FileManager.moveFile] Moved ${assets.length} assets on disk');
    }

    if (fromNotePath != null && toNotePath != null) {
      try {
        await NoteLinksDatabase.instance.remapPath(
          fromNotePath,
          toNotePath,
          rootDirectory: documentsDirectory,
        );
      } catch (e) {
        log.warning('[FileManager.moveFile] Failed to remap note links: $e');
      }
    }

    // Preserve per-note Secure PDF loading override across rename/move.
    if (!assetFileRegex.hasMatch(fromPath)) {
      remapVaultPdfLoadOverride(fromPath, toPath);
    }

    return toPath;
  }

  static Future deleteFile(
    String filePath, {
    bool alsoUpload = true,
    bool alsoDeleteAssets = true,
  }) async {
    filePath = _sanitisePath(filePath);

    final notePath = _notePathFromMainNoteFile(filePath);

    if (notePath != null) {
      // Invalidate before existence checks so in-flight saves cannot resurrect
      // a deleted note when the same display path is reused.
      EditorState.invalidateDeletedNotePath(notePath);
      ThumbnailCache.instance.invalidate(notePath);
      unawaited(EditorRecoveryJournal.purgeAllForNote(noteBasePath: notePath));

      await TagDatabase.instance.removePath(notePath);
      try {
        await NoteLinksDatabase.instance.removePath(
          notePath,
          rootDirectory: documentsDirectory,
        );
      } catch (e) {
        log.warning('[FileManager.deleteFile] Failed to remove note links: $e');
      }
    }

    if (!await doesFileExist(filePath)) {
      log.fine('[FileManager.deleteFile] Source already deleted: $filePath');
      // Still try to clean sidecars for main notes (preview / recovery / assets).
      if (notePath != null && alsoDeleteAssets) {
        await _deleteNoteSidecars(filePath);
      }
      return;
    }

    log.info(
      '[FileManager.deleteFile] Deleting file: $filePath (vault: $_shouldUseVault, alsoDeleteAssets: $alsoDeleteAssets)',
    );

    if (_shouldUseVault) {
      try {
        final relativePath = toRelativePath(filePath);

        final exists = await VaultAdapter.instance.fileExists(relativePath);
        if (!exists) {
          log.fine(
            '[FileManager.deleteFile] File does not exist in vault: $relativePath',
          );
          // Still drop Recent / home cache entries (empty notes may never
          // have been written, but were seeded into Recent on editor exit).
          _removeReferences(filePath);
          broadcastFileWrite(
            FileOperationType.delete,
            filePath,
            removal: FileRemovalCause.deleted,
          );
        } else {
          await VaultAdapter.instance.deleteFile(relativePath);
          log.fine(
            '[FileManager.deleteFile] Successfully deleted from vault: $relativePath',
          );
          _removeReferences(filePath);
          broadcastFileWrite(
            FileOperationType.delete,
            filePath,
            removal: FileRemovalCause.deleted,
          );

          if (alsoDeleteAssets && !assetFileRegex.hasMatch(relativePath)) {
            final assets = await VaultAdapter.instance.getAssetPathsForBase(
              relativePath,
            );
            await Future.wait([
              for (final assetPath in assets)
                deleteFile(assetPath, alsoDeleteAssets: false),
            ]);
            log.fine(
              '[FileManager.deleteFile] Deleted ${assets.length} assets and preview from vault for: $relativePath',
            );
          }
        }
      } catch (e, stack) {
        log.severe(
          '[FileManager.deleteFile] Error deleting from vault: $filePath',
          e,
          stack,
        );
        rethrow;
      }
      // CRITICAL FIX: Do not return here.
    }

    final file = getFile(filePath);
    if (!file.existsSync()) {
      log.fine(
        '[FileManager.deleteFile] File does not exist on disk: $filePath',
      );
      _removeReferences(filePath);
      broadcastFileWrite(
        FileOperationType.delete,
        filePath,
        removal: FileRemovalCause.deleted,
      );
      if (notePath != null && alsoDeleteAssets) {
        await _deleteNoteSidecars(filePath);
      }
      return;
    }

    try {
      final int oldSize = file.lengthSync();

      await file.delete();
      log.fine(
        '[FileManager.deleteFile] Successfully deleted from disk: $filePath',
      );
      final tracksSize = isFolderSizeTrackedFile(filePath);
      final tracksCount = isCountableFile(filePath);
      if (tracksSize || tracksCount) {
        _updateDiskFolderProps(
          filePath,
          tracksCount ? -1 : 0,
          tracksSize ? -oldSize : 0,
        );
      }
      _removeReferences(filePath);
      broadcastFileWrite(
        FileOperationType.delete,
        filePath,
        removal: FileRemovalCause.deleted,
      );

      if (alsoDeleteAssets && !assetFileRegex.hasMatch(filePath)) {
        await _deleteNoteSidecars(filePath);
      }
    } catch (e, stack) {
      log.severe(
        '[FileManager.deleteFile] Error deleting from disk: $filePath',
        e,
        stack,
      );
      rethrow;
    }
  }

  /// Deletes preview, recovery, and numbered asset sidecars for a main note file.
  static Future<void> _deleteNoteSidecars(String mainNoteFilePath) async {
    final assets = <int>[];
    for (int assetNumber = 0; true; assetNumber++) {
      final assetFile = getFile('$mainNoteFilePath.$assetNumber');
      if (assetFile.existsSync()) {
        assets.add(assetNumber);
      } else {
        break;
      }
    }

    final previewFile = getFile('$mainNoteFilePath.p');
    final recoveryFile = getFile('$mainNoteFilePath.recovery');
    await Future.wait([
      for (final assetNumber in assets)
        deleteFile('$mainNoteFilePath.$assetNumber', alsoDeleteAssets: false),
      if (previewFile.existsSync())
        deleteFile('$mainNoteFilePath.p', alsoDeleteAssets: false),
      if (recoveryFile.existsSync())
        deleteFile('$mainNoteFilePath.recovery', alsoDeleteAssets: false),
    ]);
    if (_shouldUseVault) {
      try {
        final relativePath = toRelativePath(mainNoteFilePath);
        final vaultAssets = await VaultAdapter.instance.getAssetPathsForBase(
          relativePath,
        );
        await Future.wait([
          for (final assetPath in vaultAssets)
            deleteFile(assetPath, alsoDeleteAssets: false),
        ]);
      } catch (e) {
        log.fine('[FileManager._deleteNoteSidecars] Vault sidecar cleanup: $e');
      }
    }
  }

  static Future removeUnusedAssets(
    String filePath, {
    required int numAssets,
  }) async {
    final sw = Stopwatch()..start();
    log.info(
      '[FileManager.removeUnusedAssets] Removing unused assets for: $filePath (keep: $numAssets, vault: $_shouldUseVault)',
    );

    for (int assetNumber = numAssets; true; assetNumber++) {
      if (_shouldUseVault) {
        final normalized = toRelativePath(filePath);
        final deleted = await VaultAdapter.instance
            .deleteUnusedAssetFilesForBase(normalized, numAssets);
        final msg =
            '[PERF][FileManager.removeUnusedAssets] ${sw.elapsedMilliseconds}ms (vault deleted=$deleted, base=$normalized)';
        if (sw.elapsedMilliseconds >= 120) {
          log.info(msg);
        } else {
          log.fine(msg);
        }
        return;
      }

      final assetPath = '$filePath.$assetNumber';
      final exists = getFile(assetPath).existsSync();
      if (!exists) break;
      await deleteFile(assetPath);
    }
    final msg =
        '[PERF][FileManager.removeUnusedAssets] ${sw.elapsedMilliseconds}ms (disk base=$filePath)';
    if (sw.elapsedMilliseconds >= 120) {
      log.info(msg);
    } else {
      log.fine(msg);
    }
  }

  static Future renameDirectory(String directoryPath, String newName) async {
    // SECURITY: Handle Vault Renaming
    if (_shouldUseVault) {
      final oldRelative = toRelativePath(directoryPath);
      final parentPath = oldRelative.contains('/')
          ? oldRelative.substring(0, oldRelative.lastIndexOf('/'))
          : '';
      final newRelative = '$parentPath/$newName'.replaceAll('//', '/');

      log.info(
        '[FileManager.renameDirectory] Renaming in vault: $oldRelative -> $newRelative',
      );

      final success = await VaultAdapter.instance.moveDirectory(
        oldRelative,
        newRelative,
      );

      if (success) {
        final oldPrefix = oldRelative.endsWith('/')
            ? oldRelative
            : '$oldRelative/';
        final newPrefix = newRelative.endsWith('/')
            ? newRelative
            : '$newRelative/';
        final allFiles = await VaultAdapter.instance.getFilesByPrefix(
          newPrefix,
          ensureTrailingSlash: true,
        );
        for (final path in allFiles) {
          final suffix = path.substring(newPrefix.length);
          final oldPath = '$oldPrefix$suffix';
          _renameReferences(oldPath, path);
        }
        broadcastFileWrite(
          FileOperationType.delete,
          oldRelative,
          removal: _removalCauseForRelocate(oldRelative, newRelative),
        );
        broadcastFileWrite(FileOperationType.write, newRelative);
      }
      return;
    }

    directoryPath = _sanitisePath(directoryPath);

    final directory = Directory(documentsDirectory + directoryPath);
    if (!directory.existsSync()) return;

    final List<String> children = [];
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        children.add(entity.path.substring(directory.path.length));
      }
    }

    final String newPath =
        directoryPath.substring(0, directoryPath.lastIndexOf('/') + 1) +
        newName;
    await directory.rename(documentsDirectory + newPath);

    for (final child in children) {
      _renameReferences(directoryPath + child, newPath + child);
      broadcastFileWrite(
        FileOperationType.delete,
        directoryPath + child,
        removal: _removalCauseForRelocate(
          directoryPath + child,
          newPath + child,
        ),
      );
      broadcastFileWrite(FileOperationType.write, newPath + child);
    }
  }

  static Future moveDirectory(
    String directoryPath,
    String destinationParent,
  ) async {
    // SECURITY: Handle Vault Moving
    if (_shouldUseVault) {
      final oldRelative = toRelativePath(directoryPath);
      var parentRelative = toRelativePath(destinationParent);

      final folderName = oldRelative.split('/').last;
      var newRelative = '$parentRelative/$folderName'.replaceAll('//', '/');

      if (await VaultAdapter.instance.folderExists(newRelative) ||
          await VaultAdapter.instance.fileExists('$newRelative/.nomedia') ||
          await VaultAdapter.instance.hasChildren(newRelative)) {
        newRelative = await suffixFilePathToMakeItUnique(
          newRelative,
          intendedExtension: '',
        );
      }

      log.info(
        '[FileManager.moveDirectory] Moving in vault: $oldRelative -> $newRelative',
      );

      final success = await VaultAdapter.instance.moveDirectory(
        oldRelative,
        newRelative,
      );

      if (success) {
        final oldPrefix = oldRelative.endsWith('/')
            ? oldRelative
            : '$oldRelative/';
        final newPrefix = newRelative.endsWith('/')
            ? newRelative
            : '$newRelative/';
        final allFiles = await VaultAdapter.instance.getFilesByPrefix(
          newPrefix,
          ensureTrailingSlash: true,
        );
        for (final path in allFiles) {
          final suffix = path.substring(newPrefix.length);
          final oldPath = '$oldPrefix$suffix';
          _renameReferences(oldPath, path);
        }
        broadcastFileWrite(
          FileOperationType.delete,
          oldRelative,
          removal: _removalCauseForRelocate(oldRelative, newRelative),
        );
        broadcastFileWrite(FileOperationType.write, newRelative);
      }
      return;
    }

    directoryPath = _sanitisePath(directoryPath);
    destinationParent = _sanitisePath(destinationParent);

    final directory = Directory(documentsDirectory + directoryPath);
    if (!directory.existsSync()) return;

    final props = await getFolderProperties(directoryPath);
    final currentCount = props?['file_count'] as int? ?? 0;
    final currentSize = props?['total_size'] as int? ?? 0;

    final folderName = p.basename(directoryPath);
    String newPath = p.join(destinationParent, folderName);

    if (newPath.startsWith('/')) newPath = newPath.substring(1);
    if (!newPath.startsWith('/') && directoryPath.startsWith('/'))
      newPath = '/$newPath';

    if (await isDirectory(newPath)) {
      newPath = await suffixFilePathToMakeItUnique(
        newPath,
        intendedExtension: '',
      );
    }

    final List<String> children = [];
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        children.add(entity.path.substring(directory.path.length));
      }
    }

    final targetDir = Directory(documentsDirectory + newPath);
    await targetDir.parent.create(recursive: true);
    await directory.rename(targetDir.path);

    await _updateDiskFolderPropsMoveDir(
      directoryPath,
      newPath,
      currentCount,
      currentSize,
    );

    for (final child in children) {
      _renameReferences(directoryPath + child, newPath + child);
      broadcastFileWrite(
        FileOperationType.delete,
        directoryPath + child,
        removal: _removalCauseForRelocate(
          directoryPath + child,
          newPath + child,
        ),
      );
      broadcastFileWrite(FileOperationType.write, newPath + child);
    }
  }

  static Future deleteDirectory(
    String directoryPath, [
    bool recursive = true,
  ]) async {
    // SECURITY: Handle Vault Deletion
    if (_shouldUseVault) {
      final relativePath = toRelativePath(directoryPath);
      log.info(
        '[FileManager.deleteDirectory] Deleting folder in vault: $relativePath',
      );

      var normalized = relativePath;
      if (!normalized.endsWith('/')) normalized += '/';
      final allFiles = await VaultAdapter.instance.getFilesByPrefix(
        normalized,
        ensureTrailingSlash: true,
      );
      for (final filePath in allFiles) {
        if (filePath.endsWith(Editor.extension)) {
          _removeReferences(
            filePath.substring(0, filePath.length - Editor.extension.length),
          );
        } else if (filePath.endsWith(Editor.extensionOldJson)) {
          _removeReferences(
            filePath.substring(
              0,
              filePath.length - Editor.extensionOldJson.length,
            ),
          );
        }
      }

      await VaultAdapter.instance.deleteDirectory(relativePath);

      broadcastFileWrite(
        FileOperationType.delete,
        relativePath,
        removal: FileRemovalCause.deleted,
      );
      return;
    }

    directoryPath = _sanitisePath(directoryPath);

    final directory = Directory(documentsDirectory + directoryPath);
    if (!directory.existsSync()) return;

    final props = await getFolderProperties(directoryPath);
    final currentCount = props?['file_count'] as int? ?? 0;
    final currentSize = props?['total_size'] as int? ?? 0;

    if (recursive) {
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          final childPath = entity.path.substring(documentsDirectory.length);
          _removeReferences(childPath);
          broadcastFileWrite(
            FileOperationType.delete,
            childPath,
            removal: FileRemovalCause.deleted,
          );
        }
      }
    }

    await directory.delete(recursive: recursive);

    await _updateDiskFolderProps(directoryPath, -currentCount, -currentSize);
  }

  static Future<DirectoryChildren?> getChildrenOfDirectory(
    String directory, {
    bool includeExtensions = false,
    bool includeAssets = false,
  }) async {
    assert(
      !includeAssets || includeExtensions,
      'includeAssets can\'t be true without includeExtensions',
    );

    if (_shouldUseVault) {
      directory = toRelativePath(directory);
    } else {
      directory = _sanitisePath(directory);
    }
    if (!directory.endsWith('/')) directory += '/';

    if (_shouldUseVault) {
      log.fine(
        '[FileManager.getChildrenOfDirectory] Getting children for vault directory: $directory',
      );
      // Direct children only — full-prefix scans pulled every nested note +
      // .sbn2.N / .p asset and made the file tree crawl on unlock.
      final matchingFiles = includeAssets
          ? await VaultAdapter.instance.getFilesByPrefix(
              directory,
              ensureTrailingSlash: true,
            )
          : await VaultAdapter.instance.getDirectChildFiles(directory);
      final matchingFolders = includeAssets
          ? await VaultAdapter.instance.getFoldersByPrefix(
              directory,
              ensureTrailingSlash: true,
            )
          : await VaultAdapter.instance.getDirectChildFolders(directory);
      log.fine(
        '[FileManager.getChildrenOfDirectory] Found ${matchingFiles.length} files, '
        '${matchingFolders.length} folders for $directory',
      );
      final List<String> directories = [], files = [];

      final directoryPrefixLength = directory.length;
      final Set<String> seenDirs = {};

      for (final folderPath in matchingFolders) {
        if (!folderPath.startsWith(directory)) continue;
        if (VaultAdapter.hasConsecutiveDuplicateSegment(folderPath)) continue;
        final relativePath = folderPath.substring(directoryPrefixLength);
        if (relativePath.isEmpty) continue;
        final parts = relativePath.split('/');
        final dirName = parts.first;
        if (dirName.isEmpty) continue;
        if (dirName == 'data' || dirName == 'file_picker') continue;
        if (!seenDirs.contains(dirName)) {
          directories.add(dirName);
          seenDirs.add(dirName);
        }
      }

      for (final filePath in matchingFiles) {
        final relativePath = filePath.substring(directoryPrefixLength);
        if (relativePath.isEmpty) continue;

        final parts = relativePath.split('/');
        if (parts.length > 1) {
          final dirName = parts[0];
          if (dirName == 'data' || dirName == 'file_picker') continue;
          if (!VaultAdapter.hasConsecutiveDuplicateSegment(
                '$directory$dirName/',
              ) &&
              !seenDirs.contains(dirName)) {
            directories.add(dirName);
            seenDirs.add(dirName);
          }
        } else {
          final fileName = parts[0];

          if (fileName == '.nomedia') continue;

          if (Editor.isReservedPath('/$fileName')) continue;

          late final isSbn2 = fileName.endsWith(Editor.extension);
          late final isSbn1 = fileName.endsWith(Editor.extensionOldJson);

          if (!includeExtensions) {
            if (isSbn2) {
              files.add(
                fileName.substring(
                  0,
                  fileName.length - Editor.extension.length,
                ),
              );
            } else if (isSbn1) {
              files.add(
                fileName.substring(
                  0,
                  fileName.length - Editor.extensionOldJson.length,
                ),
              );
            } else if (includeAssets) {
              files.add(fileName);
            }
          } else if (!includeAssets) {
            final isAsset = !isSbn2 && !isSbn1;
            if (!isAsset) {
              files.add(fileName);
            }
          } else {
            files.add(fileName);
          }
        }
      }

      return DirectoryChildren(directories, files);
    }

    final dir = Directory(documentsDirectory + directory);
    if (!dir.existsSync()) return null;

    final int directoryPrefixLength = directory.endsWith('/')
        ? directory.length
        : directory.length + 1;
    final List<String> directories = [];
    final List<String> files = [];

    // Classify from list() entity types — avoid a second isDirectory() round-trip
    // per child (that dominated navbar FileTree latency on large folders).
    await for (final entity in dir.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (name == 'data' || name == 'file_picker' || name == '.nomedia') {
        continue;
      }
      final filePath = entity.path.substring(documentsDirectory.length);

      if (entity is Directory) {
        final child = filePath.substring(directoryPrefixLength);
        if (child.isNotEmpty && !directories.contains(child)) {
          directories.add(child);
        }
        continue;
      }

      if (Editor.isReservedPath(filePath)) continue;

      final isSbn2 = filePath.endsWith(Editor.extension);
      final isSbn1 = filePath.endsWith(Editor.extensionOldJson);

      String? child;
      if (!includeExtensions) {
        if (isSbn2) {
          child = filePath.substring(
            0,
            filePath.length - Editor.extension.length,
          );
        } else if (isSbn1) {
          child = filePath.substring(
            0,
            filePath.length - Editor.extensionOldJson.length,
          );
        } else if (includeAssets) {
          child = filePath;
        }
      } else if (!includeAssets) {
        if (isSbn2 || isSbn1) child = filePath;
      } else {
        child = filePath;
      }
      if (child == null) continue;
      final relative = child.substring(directoryPrefixLength);
      if (relative.isEmpty) continue;
      if (!includeAssets && assetFileRegex.hasMatch(relative)) continue;
      files.add(relative);
    }

    return DirectoryChildren(directories, files);
  }

  static Future<List<String>> getAllFiles({
    bool includeExtensions = false,
    bool includeAssets = false,
  }) async {
    if (_shouldUseVault) {
      final vaultFiles = await VaultAdapter.instance.getAllFiles();
      final results = <String>[];
      for (final path in vaultFiles) {
        final normalized = path.toLowerCase();
        if (normalized.contains('/data/') ||
            normalized.startsWith('data/') ||
            normalized.contains('/file_picker/') ||
            normalized.startsWith('file_picker/')) {
          continue;
        }
        final isSbn2 = path.endsWith(Editor.extension);
        final isSbn1 = path.endsWith(Editor.extensionOldJson);
        if (!includeExtensions) {
          if (isSbn2) {
            results.add(
              path.substring(0, path.length - Editor.extension.length),
            );
          } else if (isSbn1) {
            results.add(
              path.substring(0, path.length - Editor.extensionOldJson.length),
            );
          } else if (includeAssets) {
            results.add(path);
          }
        } else if (!includeAssets) {
          if (isSbn2 || isSbn1) {
            results.add(path);
          }
        } else {
          results.add(path);
        }
      }
      return results;
    }

    final allFiles = <String>[];
    final directories = <String>['/'];

    while (directories.isNotEmpty) {
      final directory = directories.removeLast();
      final children = await getChildrenOfDirectory(
        directory,
        includeExtensions: includeExtensions,
        includeAssets: includeAssets,
      );
      if (children == null) continue;

      for (final file in children.files) {
        allFiles.add('$directory$file');
      }
      for (final childDirectory in children.directories) {
        directories.add('$directory$childDirectory/');
      }
    }

    return allFiles;
  }

  static bool _isVisibleHomeNotePath(String path) {
    final name = path.split('/').last;
    return name.isNotEmpty &&
        !name.startsWith('.') &&
        !name.startsWith('TmPmP_') &&
        !name.contains('.sbn2.');
  }

  /// Every user note with last-modified and size. Used by Recent (all notes)
  /// so sorting does not decrypt bodies or cap the list.
  static Future<List<NoteIndexEntry>> getAllNotesWithMeta() async {
    final bases = await getAllFiles();
    final seen = <String>{};
    final visible = <String>[];
    for (final path in bases) {
      if (!_isVisibleHomeNotePath(path)) continue;
      if (!seen.add(path)) continue;
      visible.add(path);
    }
    if (visible.isEmpty) return const [];

    if (_shouldUseVault) {
      final raw = await VaultAdapter.instance.getAllFileMetadata();
      final byBase = <String, Map<String, int>>{};
      for (final entry in raw.entries) {
        final base = notePathWithoutExtension(entry.key);
        if (base.isEmpty || !_isVisibleHomeNotePath(base)) continue;
        final prev = byBase[base];
        final m = entry.value['m'] ?? 0;
        if (prev == null || m >= (prev['m'] ?? 0)) {
          byBase[base] = entry.value;
        }
      }
      return [
        for (final path in visible)
          NoteIndexEntry(
            path: path,
            modifiedMillis: byBase[path]?['m'] ?? 0,
            sizeBytes: byBase[path]?['s'] ?? 0,
          ),
      ];
    }

    final out = <NoteIndexEntry>[];
    for (final path in visible) {
      out.add(_noteIndexEntryFromDisk(path));
    }
    return out;
  }

  static NoteIndexEntry _noteIndexEntryFromDisk(String path) {
    var modified = 0;
    var size = 0;
    try {
      final file2 = getFile(path + Editor.extension);
      final file = file2.existsSync()
          ? file2
          : getFile(path + Editor.extensionOldJson);
      if (file.existsSync()) {
        final stat = file.statSync();
        modified = stat.modified.millisecondsSinceEpoch;
        size = stat.size;
      }
    } catch (_) {}
    return NoteIndexEntry(
      path: path,
      modifiedMillis: modified,
      sizeBytes: size,
    );
  }

  /// Cheap mtime/size for one note after a write. Does not decrypt the body.
  static Future<NoteIndexEntry> peekNoteIndexEntry(String path) async {
    final base = notePathWithoutExtension(path);
    if (base.isEmpty) {
      return NoteIndexEntry(
        path: path,
        modifiedMillis: DateTime.now().millisecondsSinceEpoch,
        sizeBytes: 0,
      );
    }
    if (_shouldUseVault) {
      final sbn2 = toRelativePath(base + Editor.extension);
      var modified = await VaultAdapter.instance.getFileLastModified(sbn2);
      var size = await VaultAdapter.instance.getFileSize(sbn2);
      if (modified == null) {
        final sbn = toRelativePath(base + Editor.extensionOldJson);
        modified = await VaultAdapter.instance.getFileLastModified(sbn);
        size = await VaultAdapter.instance.getFileSize(sbn);
      }
      return NoteIndexEntry(
        path: base,
        modifiedMillis:
            modified?.millisecondsSinceEpoch ??
            DateTime.now().millisecondsSinceEpoch,
        sizeBytes: size ?? 0,
      );
    }
    return _noteIndexEntryFromDisk(base);
  }

  static Future<List<String>> getRecentlyAccessed() async {
    if (!stows.recentFiles.loaded) await stows.recentFiles.waitUntilRead();
    return stows.recentFiles.value
        .where((String file) {
          if (Editor.isReservedPath(file)) return false;
          final normalized = file.toLowerCase();
          if (normalized.contains('/data/') ||
              normalized.startsWith('data/') ||
              normalized.contains('/file_picker/') ||
              normalized.startsWith('file_picker/')) {
            return false;
          }
          return true;
        })
        .map(notePathWithoutExtension)
        .toList();
  }

  static Future<bool> isDirectory(String filePath) async {
    if (_shouldUseVault) {
      final relative = toRelativePath(filePath);

      if (await VaultAdapter.instance.folderExists(relative)) {
        return true;
      }

      if (await VaultAdapter.instance.fileExists('$relative/.nomedia')) {
        return true;
      }

      return await VaultAdapter.instance.hasChildren(relative);
    }

    filePath = _sanitisePath(filePath);
    final directory = Directory(documentsDirectory + filePath);
    return directory.existsSync();
  }

  static Future<bool> doesNoteExist(String basePath) async {
    final base = notePathWithoutExtension(basePath);
    if (base.isEmpty) return false;
    return await doesFileExist(base + Editor.extension) ||
        await doesFileExist(base + Editor.extensionOldJson);
  }

  static Future<bool> doesFileExist(String filePath) async {
    if (_shouldUseVault) {
      final relativePath = toRelativePath(filePath);
      return await VaultAdapter.instance.fileExists(relativePath);
    }

    filePath = _sanitisePath(filePath);
    final file = getFile(filePath);
    return file.existsSync();
  }

  static Future<DateTime> lastModified(String filePath) async {
    if (_shouldUseVault) {
      final relative = toRelativePath(filePath);
      final date = await VaultAdapter.instance.getFileLastModified(relative);
      return date ?? DateTime.now();
    }

    filePath = _sanitisePath(filePath);
    final file = getFile(filePath);
    if (!file.existsSync()) return DateTime.now();
    return file.lastModified();
  }

  static Future<int> getFileSize(String filePath) async {
    if (_shouldUseVault) {
      final relative = toRelativePath(filePath);
      final size = await VaultAdapter.instance.getFileSize(relative);
      return size ?? 0;
    }

    filePath = _sanitisePath(filePath);
    final file = getFile(filePath);
    if (!file.existsSync()) return 0;
    return await file.length();
  }

  static Future<int> getFolderFileCount(String folderPath) async {
    if (_shouldUseVault) {
      return await VaultAdapter.instance.getFolderFileCount(folderPath);
    }

    // Match vault: always return a recursive countable-file total. Disk props
    // are rebuilt when missing or stale (see [getFolderProperties]).
    final props = await getFolderProperties(folderPath);
    return (props?['file_count'] as num?)?.toInt() ?? 0;
  }

  static Future<Map<String, int>> getFolderFileCountsBatch(
    List<String> folderPaths,
  ) async {
    if (folderPaths.isEmpty) return const {};
    if (_shouldUseVault) {
      return VaultAdapter.instance.getFolderFileCounts(folderPaths);
    }

    final unique = <String, String>{}; // normalized → original
    for (final folderPath in folderPaths) {
      unique.putIfAbsent(
        normalizeFolderCountPath(folderPath),
        () => folderPath,
      );
    }

    final entries = await Future.wait(
      unique.entries.map((entry) async {
        final count = await getFolderFileCount(entry.value);
        return MapEntry(entry.key, count);
      }),
    );
    return Map<String, int>.fromEntries(entries);
  }

  static Future<int> getTotalFileCount() async {
    if (_shouldUseVault) {
      return await VaultAdapter.instance.getTotalFileCount();
    }

    // Root recursive count — same source of truth as per-folder counters.
    final props = await getFolderProperties('/');
    return (props?['file_count'] as num?)?.toInt() ?? 0;
  }

  static Future<void> _updateDiskFolderProps(
    String filePath,
    int countDelta,
    int sizeDelta,
  ) async {
    if (_shouldUseVault) return;

    try {
      final fileDir = p.dirname(_sanitisePath(filePath));
      var currentPath = fileDir;
      final now = DateTime.now().millisecondsSinceEpoch;

      while (true) {
        final dir = Directory(documentsDirectory + currentPath);
        if (!dir.existsSync()) break;

        final propsFile = File(p.join(dir.path, '.folder_props'));
        int count = 0;
        int size = 0;
        int created = now;

        if (await propsFile.exists()) {
          try {
            final content = jsonDecode(await propsFile.readAsString());
            count = content['file_count'] ?? 0;
            size = content['total_size'] ?? 0;
            created = content['created_at'] ?? now;
          } catch (_) {}
        } else {
          final countFile = File(p.join(dir.path, '.folder_count'));
          if (await countFile.exists()) {
            count = int.tryParse(await countFile.readAsString()) ?? 0;
          }
        }

        count = max(0, count + countDelta);
        size = max(0, size + sizeDelta);

        await propsFile.writeAsString(
          jsonEncode({
            'file_count': count,
            'total_size': size,
            'bundle_size_version': _folderBundleSizeVersion,
            'created_at': created,
            'last_modified': now,
          }),
        );

        if (currentPath == '/' || currentPath == '.') break;
        currentPath = p.dirname(currentPath);
      }
    } catch (_) {}
  }

  static Future<void> _updateDiskFolderPropsMove(
    String fromPath,
    String toPath,
    int size,
  ) async {
    if (_shouldUseVault) return;

    final fromCountable = isCountableFile(fromPath);
    final toCountable = isCountableFile(toPath);
    final fromTracksSize = isFolderSizeTrackedFile(fromPath);
    final toTracksSize = isFolderSizeTrackedFile(toPath);
    if (!fromCountable && !toCountable && !fromTracksSize && !toTracksSize) {
      return;
    }

    final deltasC = <String, int>{};
    final deltasS = <String, int>{};

    void addPath(String filePath, int countSign, int sizeSign) {
      var currentPath = p.dirname(_sanitisePath(filePath));
      while (true) {
        deltasC[currentPath] = (deltasC[currentPath] ?? 0) + countSign;
        deltasS[currentPath] = (deltasS[currentPath] ?? 0) + (sizeSign * size);
        if (currentPath == '/' || currentPath == '.') break;
        currentPath = p.dirname(currentPath);
      }
    }

    addPath(fromPath, fromCountable ? -1 : 0, fromTracksSize ? -1 : 0);
    addPath(toPath, toCountable ? 1 : 0, toTracksSize ? 1 : 0);

    final now = DateTime.now().millisecondsSinceEpoch;
    for (final entry in deltasC.entries) {
      final dirPath = entry.key;
      final cDelta = entry.value;
      final sDelta = deltasS[dirPath] ?? 0;

      if (cDelta == 0 && sDelta == 0) continue;

      try {
        final dir = Directory(documentsDirectory + dirPath);
        if (!dir.existsSync()) continue;

        final propsFile = File(p.join(dir.path, '.folder_props'));
        int count = 0;
        int sz = 0;
        int created = now;

        if (await propsFile.exists()) {
          try {
            final content = jsonDecode(await propsFile.readAsString());
            count = content['file_count'] ?? 0;
            sz = content['total_size'] ?? 0;
            created = content['created_at'] ?? now;
          } catch (_) {}
        } else {
          final countFile = File(p.join(dir.path, '.folder_count'));
          if (await countFile.exists()) {
            count = int.tryParse(await countFile.readAsString()) ?? 0;
          }
        }

        count = max(0, count + cDelta);
        sz = max(0, sz + sDelta);

        await propsFile.writeAsString(
          jsonEncode({
            'file_count': count,
            'total_size': sz,
            'bundle_size_version': _folderBundleSizeVersion,
            'created_at': created,
            'last_modified': now,
          }),
        );
      } catch (_) {}
    }
  }

  static Future<void> _updateDiskFolderPropsMoveDir(
    String fromPath,
    String toPath,
    int countDelta,
    int sizeDelta,
  ) async {
    if (_shouldUseVault) return;

    final deltasC = <String, int>{};
    final deltasS = <String, int>{};

    void addPath(String dirPath, int sign) {
      var currentPath = p.dirname(_sanitisePath(dirPath));
      while (true) {
        deltasC[currentPath] =
            (deltasC[currentPath] ?? 0) + (sign * countDelta);
        deltasS[currentPath] = (deltasS[currentPath] ?? 0) + (sign * sizeDelta);
        if (currentPath == '/' || currentPath == '.') break;
        currentPath = p.dirname(currentPath);
      }
    }

    addPath(fromPath, -1);
    addPath(toPath, 1);

    final now = DateTime.now().millisecondsSinceEpoch;
    for (final entry in deltasC.entries) {
      final dirPath = entry.key;
      final cDelta = entry.value;
      final sDelta = deltasS[dirPath] ?? 0;

      if (cDelta == 0 && sDelta == 0) continue;

      try {
        final dir = Directory(documentsDirectory + dirPath);
        if (!dir.existsSync()) continue;

        final propsFile = File(p.join(dir.path, '.folder_props'));
        int count = 0;
        int sz = 0;
        int created = now;

        if (await propsFile.exists()) {
          try {
            final content = jsonDecode(await propsFile.readAsString());
            count = content['file_count'] ?? 0;
            sz = content['total_size'] ?? 0;
            created = content['created_at'] ?? now;
          } catch (_) {}
        } else {
          final countFile = File(p.join(dir.path, '.folder_count'));
          if (await countFile.exists()) {
            count = int.tryParse(await countFile.readAsString()) ?? 0;
          }
        }

        count = max(0, count + cDelta);
        sz = max(0, sz + sDelta);

        await propsFile.writeAsString(
          jsonEncode({
            'file_count': count,
            'total_size': sz,
            'bundle_size_version': _folderBundleSizeVersion,
            'created_at': created,
            'last_modified': now,
          }),
        );
      } catch (_) {}
    }
  }

  static Future<Map<String, dynamic>?> _rebuildDiskFolderProperties(
    String folderPath,
  ) async {
    try {
      final normalized = _sanitisePath(folderPath);
      final dir = Directory(documentsDirectory + normalized);
      if (!await dir.exists()) return null;

      var count = 0;
      var size = 0;
      var latestModified = dir.statSync().modified.millisecondsSinceEpoch;

      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;

        final relativePath = toRelativePath(entity.path);
        if (isCountableFile(relativePath)) count++;
        if (isFolderSizeTrackedFile(relativePath)) {
          final stat = await entity.stat();
          size += stat.size;
          final modified = stat.modified.millisecondsSinceEpoch;
          if (modified > latestModified) latestModified = modified;
        }
      }

      final propsFile = File(p.join(dir.path, '.folder_props'));
      final now = DateTime.now().millisecondsSinceEpoch;
      int created = dir.statSync().changed.millisecondsSinceEpoch;
      if (await propsFile.exists()) {
        try {
          final content = jsonDecode(await propsFile.readAsString());
          created = content['created_at'] ?? created;
        } catch (_) {}
      }

      final props = {
        'file_count': count,
        'total_size': size,
        'bundle_size_version': _folderBundleSizeVersion,
        'created_at': created,
        'last_modified': max(latestModified, now),
      };
      await propsFile.writeAsString(jsonEncode(props));
      return props;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getFolderProperties(
    String folderPath,
  ) async {
    if (_shouldUseVault) {
      return VaultAdapter.instance.getFolderProperties(folderPath);
    }
    try {
      folderPath = _sanitisePath(folderPath);
      final dir = Directory(documentsDirectory + folderPath);
      if (!await dir.exists()) return null;

      final propsFile = File(p.join(dir.path, '.folder_props'));
      if (await propsFile.exists()) {
        try {
          final props = jsonDecode(await propsFile.readAsString());
          if (props['bundle_size_version'] == _folderBundleSizeVersion) {
            return props;
          }
          final rebuilt = await _rebuildDiskFolderProperties(folderPath);
          return rebuilt ?? props;
        } catch (_) {}
      }
      return await _rebuildDiskFolderProperties(folderPath) ??
          {
            'file_count': 0,
            'total_size': 0,
            'bundle_size_version': _folderBundleSizeVersion,
            'created_at': (dir.statSync()).changed.millisecondsSinceEpoch,
            'last_modified': (dir.statSync()).modified.millisecondsSinceEpoch,
          };
    } catch (_) {
      return null;
    }
  }

  static Future<String> newFilePath([String parentPath = '/']) async {
    assert(parentPath.endsWith('/'));

    final DateTime now = DateTime.now();
    final filePath =
        '$parentPath${DateFormat('yy-MM-dd').format(now)} '
        '${t.editor.untitled}';

    return await suffixFilePathToMakeItUnique(filePath);
  }

  static Future<String> suffixFilePathToMakeItUnique(
    String filePath, {
    String? intendedExtension,
    String? currentPath,
  }) async {
    String newFilePath = filePath;
    bool hasExtension = false;

    if (filePath.endsWith(Editor.extension)) {
      filePath = filePath.substring(
        0,
        filePath.length - Editor.extension.length,
      );
      newFilePath = filePath;
      hasExtension = true;
      intendedExtension ??= Editor.extension;
    } else if (filePath.endsWith(Editor.extensionOldJson)) {
      filePath = filePath.substring(
        0,
        filePath.length - Editor.extensionOldJson.length,
      );
      newFilePath = filePath;
      hasExtension = true;
      intendedExtension ??= Editor.extensionOldJson;
    } else {
      intendedExtension ??= Editor.extension;
    }

    Set<String>? existingNames;
    if (_shouldUseVault) {
      final slash = filePath.lastIndexOf('/');
      final parent = slash >= 0 ? filePath.substring(0, slash + 1) : '/';
      final children = await getChildrenOfDirectory(
        parent,
        includeExtensions: true,
        includeAssets: false,
      );
      if (children != null) {
        existingNames = children.files.toSet();
      }
    }

    bool existsCandidate(String candidateWithoutExt) {
      if (existingNames != null) {
        final Set<String> names = existingNames;
        final slash = candidateWithoutExt.lastIndexOf('/');
        final leaf = slash >= 0
            ? candidateWithoutExt.substring(slash + 1)
            : candidateWithoutExt;
        return names.contains('$leaf${Editor.extension}') ||
            names.contains('$leaf${Editor.extensionOldJson}');
      }
      return false;
    }

    int i = 1;
    while (true) {
      final bool exists;
      if (existingNames != null) {
        exists = existsCandidate(newFilePath);
      } else {
        final existsSbn2 = await doesFileExist(newFilePath + Editor.extension);
        final existsJson = await doesFileExist(
          newFilePath + Editor.extensionOldJson,
        );
        exists = existsSbn2 || existsJson;
      }

      if (!exists) break;
      if (newFilePath + Editor.extension == currentPath) break;
      if (newFilePath + Editor.extensionOldJson == currentPath) break;
      i++;
      newFilePath = '$filePath ($i)';
    }

    return newFilePath + (hasExtension ? intendedExtension : '');
  }

  static Future<String?> importFile(
    String path,
    String? parentDir, {
    String? extension,
    bool awaitWrite = true,
    Future<String?> Function()? getEncryptionPassword,

    ThemeData? theme,
    MediaQueryData? mediaQuery,
  }) async {
    assert(
      parentDir == null || parentDir.startsWith('/') && parentDir.endsWith('/'),
    );

    if (extension == null) {
      extension = '.${path.split('.').last}';
      assert(extension.length > 1);
    } else {
      assert(extension.startsWith('.'));
    }

    String fileName = path.split(RegExp(r'[\\/]')).last;
    fileName = fileName.substring(0, fileName.lastIndexOf('.'));
    final String importedPath;

    final writeFutures = <Future>[];

    if (extension.toLowerCase() == '.sba') {
      final rawBytes = await File(path).readAsBytes();
      final encrypted = SbaEncryption.isEncrypted(rawBytes);
      String? password;
      if (encrypted) {
        password = await getEncryptionPassword?.call();
        if (password == null || password.isEmpty) {
          log.warning(
            'Encrypted SBA requires password. Provide getEncryptionPassword.',
          );
          return null;
        }
      }

      const sbaUnpackIsolateBytes = 256 * 1024;
      final unpackReq = _SbaUnpackRequest(
        rawBytes: rawBytes,
        encrypted: encrypted,
        password: password,
      );
      final List<_SbaArchiveMember> members;
      try {
        if (Platform.isAndroid && rawBytes.length >= sbaUnpackIsolateBytes) {
          members = await Isolate.run(() => _unpackSbaArchiveSync(unpackReq));
        } else {
          members = _unpackSbaArchiveSync(unpackReq);
        }
      } on ArgumentError catch (e) {
        log.warning('SBA decryption failed: $e');
        return null;
      }

      _SbaArchiveMember? mainEntry;
      for (final m in members) {
        final lower = m.name.toLowerCase();
        if (lower.endsWith('sbn') || lower.endsWith('sbn2')) {
          mainEntry = m;
          break;
        }
      }
      if (mainEntry == null) {
        log.severe('Failed to find main note in sba: $path');
        return null;
      }
      final mainFileExtension = '.${mainEntry.name.split('.').last}'
          .toLowerCase();
      importedPath = await suffixFilePathToMakeItUnique(
        '${parentDir ?? '/'}$fileName',
        intendedExtension: mainFileExtension,
      );

      // Commit note + assets as a unit: any write failure rolls back prior
      // files from this import so we never leave a half-imported .sba.
      final committedPaths = <String>[];
      try {
        final mainPath = importedPath + mainFileExtension;
        await writeFile(mainPath, mainEntry.bytes, awaitWrite: true);
        committedPaths.add(mainPath);

        for (final m in members) {
          if (m.name == mainEntry.name) continue;
          final assetExt = m.name.split('.').last;
          final assetNumber = int.tryParse(assetExt);
          if (assetNumber == null || assetNumber < 0) continue;
          final assetPath = '$importedPath$mainFileExtension.$assetNumber';
          await writeFile(assetPath, m.bytes, awaitWrite: true);
          committedPaths.add(assetPath);
        }
      } catch (e, st) {
        log.severe('SBA import failed mid-write; rolling back: $e', e, st);
        for (final committed in committedPaths.reversed) {
          try {
            await deleteFile(committed, alsoDeleteAssets: false);
          } catch (_) {}
        }
        return null;
      }
    } else {
      final file = File(path);
      final fileContents = await file.readAsBytes();
      importedPath = await suffixFilePathToMakeItUnique(
        '${parentDir ?? '/'}$fileName',
        intendedExtension: extension.toLowerCase(),
      );
      writeFutures.add(
        writeFile(
          importedPath + extension.toLowerCase(),
          fileContents,
          awaitWrite: awaitWrite,
        ),
      );
    }

    await Future.wait(writeFutures);

    try {
      final coreInfo = await EditorCoreInfo.loadFromFilePath(importedPath);

      if (coreInfo.pages.isNotEmpty) {
        final thumbnailPath = '$importedPath${Editor.extension}.p';
        if (coreInfo.isInfinite) {
          await generateJdenticonThumbnail(importedPath, thumbnailPath);
        } else {
          final themeToUse = theme ?? ThemeData.light();
          final mediaQueryToUse = mediaQuery ?? MediaQueryData();
          await _generateThumbnail(
            coreInfo: coreInfo,
            theme: themeToUse,
            mediaQuery: mediaQueryToUse,
            path: thumbnailPath,
          );
        }
      }
      coreInfo.dispose();
    } catch (e) {
      log.warning('Failed to generate thumbnail for imported file: $e');
    }

    HomeDataCache.instance.invalidate();
    return importedPath;
  }

  static Future<bool> createNoteFromPdf(
    String sbnFilePath,
    String pdfPath, {
    required ThemeData theme,
    required MediaQueryData mediaQuery,
    List<PdfOutlineItem>? pdfOutlines,
    void Function(double progress, String status)? onImportProgress,
  }) async {
    try {
      final pdfFile = File(pdfPath);
      if (!pdfFile.existsSync()) return false;

      onImportProgress?.call(0.04, 'Opening PDF');
      final coreInfo = EditorCoreInfo(filePath: sbnFilePath);

      final assetId = await coreInfo.assetCacheAll.addPdfFast(pdfFile);

      final doc = await PdfDocument.openFile(
        pdfPath,
        useProgressiveLoading: true,
      );
      unawaited(
        doc.loadPagesProgressively().catchError((Object _, StackTrace __) {}),
      );

      Future<List<PdfOutlineItem>?>? outlineFuture;
      if (pdfOutlines == null) {
        outlineFuture = PdfOutlineExtractor.extractOutlines(doc);
      } else {
        coreInfo.pdfOutlines = pdfOutlines;
      }

      final n = doc.pages.length;
      for (int i = 0; i < n; i++) {
        if (i % 32 == 0 || i == n - 1) {
          onImportProgress?.call(
            0.08 + (i + 1) / max(n, 1) * 0.60,
            'Preparing pages',
          );
        }
        final pdfPage = doc.pages[i];
        final naturalSize = Size(pdfPage.width, pdfPage.height);

        const width = EditorPage.defaultWidth;
        final height = width * (naturalSize.height / naturalSize.width);
        final pageSize = Size(width, height);

        final page = EditorPage(width: width, height: height);

        page.backgroundImage = PdfEditorImage(
          id: coreInfo.nextImageId++,
          assetCacheAll: coreInfo.assetCacheAll,
          assetId: assetId,
          pdfFile: pdfFile,
          pdfPage: i,
          pageIndex: i,
          pageSize: pageSize,
          naturalSize: naturalSize,
          dstRect: Rect.fromLTWH(0, 0, width, height),

          onMoveImage: null,
          onDeleteImage: null,
          onMiscChange: null,
          onLoad: null,
        );

        coreInfo.pages.add(page);
        coreInfo.assetCacheAll.addUse(assetId);
      }

      if (outlineFuture != null) {
        try {
          coreInfo.pdfOutlines = await outlineFuture;
        } catch (e) {
          log.fine('Could not extract PDF outlines: $e');
        }
      }

      for (final page in coreInfo.pages) {
        page.id ??= coreInfo.allocatePageId();
      }
      syncPdfOutlinesWithPages(coreInfo.pdfOutlines, coreInfo.pages);

      onImportProgress?.call(0.70, 'Saving');

      final fullSavePath = getFilePath(sbnFilePath + Editor.extension);
      final didLayoutTouch = await coreInfo.assetCacheAll.renumberBeforeSave(
        fullSavePath,
      );
      if (didLayoutTouch) {
        coreInfo.invalidatePageBinaryEncodeCaches();
      }

      onImportProgress?.call(0.82, 'Saving');
      final bson = coreInfo.saveToBinary(currentPageIndex: 0);

      await writeFile(sbnFilePath + Editor.extension, bson, awaitWrite: true);

      onImportProgress?.call(0.92, 'Thumbnail');
      final bool thumbnailGenerated = await generateThumbnailFromPdf(
        pdfPath,
        '$sbnFilePath${Editor.extension}.p',
        document: doc,
      );

      if (!thumbnailGenerated) {
        await _generateThumbnail(
          coreInfo: coreInfo,
          theme: theme,
          mediaQuery: mediaQuery,
          path: '$sbnFilePath${Editor.extension}.p',
        );
      }

      doc.dispose();
      coreInfo.dispose();
      HomeDataCache.instance.invalidate();

      return true;
    } catch (e, stack) {
      log.severe('Erro ao criar nota via PDF em background: $e', e, stack);
      return false;
    }
  }

  static Future _createFileDirectory(String filePath) async {
    assert(filePath.contains('/'), 'filePath must be a path, not a file name');
    final parentDirectory = filePath.substring(0, filePath.lastIndexOf('/'));
    await Directory(
      documentsDirectory + parentDirectory,
    ).create(recursive: true);
  }

  /// Home / recent lists store note base paths (no `.sbn2` / `.sbn`).
  static String notePathWithoutExtension(String filePath) {
    if (filePath.endsWith(Editor.extension)) {
      return filePath.substring(0, filePath.length - Editor.extension.length);
    }
    if (filePath.endsWith(Editor.extensionOldJson)) {
      return filePath.substring(
        0,
        filePath.length - Editor.extensionOldJson.length,
      );
    }
    if (filePath.endsWith('.sba')) {
      return filePath.substring(0, filePath.length - 4);
    }
    return filePath;
  }

  static Future _renameReferences(String fromPath, String toPath) async {
    final fromBase = notePathWithoutExtension(toRelativePath(fromPath));
    final toBase = notePathWithoutExtension(toRelativePath(toPath));
    final recent = List<String>.from(stows.recentFiles.value);
    bool replaced = false;
    for (int i = 0; i < recent.length; i++) {
      final recentBase = notePathWithoutExtension(toRelativePath(recent[i]));
      if (recentBase != fromBase) continue;
      if (!replaced) {
        recent[i] = toBase;
        replaced = true;
      } else {
        recent.removeAt(i);
        i--;
      }
    }
    stows.recentFiles.value = recent;
    stows.recentFiles.notifyListeners();
  }

  static Future _removeReferences(String filePath) async {
    final normalizedTarget = notePathWithoutExtension(toRelativePath(filePath));

    final recent = List<String>.from(stows.recentFiles.value);
    for (int i = recent.length - 1; i >= 0; i--) {
      final normalizedRecent = notePathWithoutExtension(
        toRelativePath(recent[i]),
      );

      if (normalizedRecent == normalizedTarget) {
        recent.removeAt(i);
      }
    }

    stows.recentFiles.value = recent;
    stows.recentFiles.notifyListeners();
    HomeDataCache.instance.forgetRecentPaths([normalizedTarget]);
  }

  static Future _saveFileAsRecentlyAccessed(String filePath) async {
    if (assetFileRegex.hasMatch(filePath)) return;

    // Prefs / Home expect base paths; storing `.sbn2` breaks PreviewCard
    // thumbnails (`note.sbn2.sbn2.p`) and shows the extension in titles.
    final basePath = notePathWithoutExtension(filePath);
    if (basePath.isEmpty) return;

    // Single path into the Recent window: inserts at front and drops the
    // oldest when at capacity so the home grid never grows a lonely row.
    HomeDataCache.instance.rememberRecentPaths([basePath]);
  }

  /// Kept in sync with [HomeDataCache.maxRecentNotes] (10×7 Recent grid).
  static const maxRecentlyAccessedFiles = HomeDataCache.maxRecentNotes;

  static Future<void> generateThumbnailForNote({
    required EditorCoreInfo coreInfo,
    required ThemeData theme,
    required MediaQueryData mediaQuery,
    required String path,
  }) => _generateThumbnail(
    coreInfo: coreInfo,
    theme: theme,
    mediaQuery: mediaQuery,
    path: path,
  );

  static Future<bool> writeInfiniteCoverThumbnail(
    Uint8List imageBytes,
    String destinationPath,
  ) async {
    try {
      const size = 360;
      final screenshotter = ScreenshotController();
      final thumbnailBytes = await screenshotter.captureFromWidget(
        Container(
          width: size.toDouble(),
          height: size.toDouble(),
          color: Colors.white,
          child: FittedBox(fit: BoxFit.cover, child: Image.memory(imageBytes)),
        ),
        pixelRatio: 1.0,
        targetSize: const Size(360.0, 360.0),
      );
      if (thumbnailBytes.isNotEmpty) {
        await writeFile(destinationPath, thumbnailBytes, awaitWrite: true);
        return true;
      }
    } catch (e) {
      log.warning('Infinite cover thumbnail failed: $e');
    }
    return false;
  }

  static Future<void> generateJdenticonThumbnail(
    String seedId,
    String destinationPath,
  ) async {
    try {
      const size = 360;
      final svg = Jdenticon.toSvg(seedId, size: size);
      final screenshotter = ScreenshotController();
      final thumbnailBytes = await screenshotter.captureFromWidget(
        Container(
          width: size.toDouble(),
          height: size.toDouble(),
          color: Colors.white,
          child: SvgPicture.string(
            svg,
            fit: BoxFit.contain,
            width: size.toDouble(),
            height: size.toDouble(),
          ),
        ),
        pixelRatio: 1.0,
        targetSize: const Size(360.0, 360.0),
      );
      if (thumbnailBytes.isNotEmpty) {
        unawaited(
          writeFile(destinationPath, thumbnailBytes, awaitWrite: false),
        );
      }
    } catch (e) {
      log.warning('Jdenticon thumbnail generation failed: $e');
    }
  }

  static Future<void> _generateThumbnail({
    required EditorCoreInfo coreInfo,
    required ThemeData theme,
    required MediaQueryData mediaQuery,
    required String path,
  }) async {
    if (!coreInfo.shouldGenerateThumbnail) {
      log.fine('Skipping thumbnail generation: Hash matches.');
      return;
    }

    if (coreInfo.pages.isEmpty) return;

    final page = coreInfo.pages.first;
    bool success = false;

    if (page.backgroundImage is PdfEditorImage) {
      try {
        final pdfImg = page.backgroundImage as PdfEditorImage;

        if (pdfImg.pdfFile != null && pdfImg.pdfFile!.existsSync()) {
          success = await generateThumbnailFromPdf(pdfImg.pdfFile!.path, path);
        }

        if (!success) {
          final bytes = await coreInfo.assetCacheAll.getBytes(pdfImg.assetId);
          if (bytes.isNotEmpty) {
            success = await generateThumbnailFromPdf(
              '',
              path,
              fileBytes: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
            );
          }
        }
      } catch (e) {
        log.warning(
          'Fast PDF thumbnail generation failed, falling back to screenshot: $e',
        );
      }
    }

    if (!success) {
      final screenshotter = ScreenshotController();
      final double previewHeight = page.previewHeight();

      if (previewHeight > 0 && page.size.width > 0) {
        final thumbnailSize = Size(360, 360 * previewHeight / page.size.width);

        try {
          final thumbnailBytes = await screenshotter.captureFromWidget(
            MediaQuery(
              data: mediaQuery,
              child: Theme(
                data: theme.copyWith(
                  brightness: Brightness.light,
                  colorScheme: const ColorScheme.light(
                    primary: EditorExporter.exportDefaultLineGray,
                    secondary: EditorExporter.exportDefaultLineGray,
                    surface: Colors.white,
                    onSurface: Colors.black,
                  ),
                ),
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Container(
                    color: Colors.white,
                    width: thumbnailSize.width,
                    height: thumbnailSize.height,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: CanvasPreview(
                        pageIndex: 0,
                        height: previewHeight,
                        coreInfo: coreInfo,
                        highQuality: false,
                        overrideInvert: false,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            delay: const Duration(milliseconds: 500),
            pixelRatio: 1.0,
            targetSize: thumbnailSize,
          );

          if (thumbnailBytes.isNotEmpty) {
            unawaited(
              FileManager.writeFile(path, thumbnailBytes, awaitWrite: false),
            );
            success = true;
          }
        } catch (e) {
          log.warning('Erro ao gerar thumbnail headless: $e');
        }
      }
    }

    if (success) {
      coreInfo.notifyThumbnailGenerated();
    }
  }

  static Future<bool> generateThumbnailFromPdf(
    String pdfPath,
    String destinationPath, {
    Uint8List? fileBytes,
    PdfDocument? document,
  }) async {
    final shouldDisposeDocument = document == null;
    try {
      if (document == null && fileBytes != null) {
        document = await PdfDocument.openData(fileBytes);
      } else if (document == null && await File(pdfPath).exists()) {
        document = await PdfDocument.openFile(pdfPath);
      } else if (document == null) {
        final bytes = await FileManager.readFile(pdfPath);
        if (bytes != null) document = await PdfDocument.openData(bytes);
      }

      if (document == null || document.pages.isEmpty) return false;

      final page = document.pages[0];

      final double scale = 360.0 / page.width;
      final int width = (page.width * scale).toInt();
      final int height = (page.height * scale).toInt();

      final pdfImage = await page.render(
        fullWidth: width.toDouble(),
        fullHeight: height.toDouble(),

        backgroundColor: Colors.white.value,
      );

      if (pdfImage != null) {
        final image = await pdfImage.createImage();
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();

        if (byteData != null) {
          unawaited(
            writeFile(
              destinationPath,
              byteData.buffer.asUint8List(),
              awaitWrite: false,
            ),
          );
          return true;
        }
      }
      return false;
    } catch (e) {
      log.warning('Failed to generate thumbnail directly from PDF: $e');
      return false;
    } finally {
      if (shouldDisposeDocument) document?.dispose();
    }
  }
}

class DirectoryChildren {
  final List<String> directories;
  final List<String> files;
  final Map<String, String> linkedDirectories;
  final Map<String, String> linkedFiles;

  DirectoryChildren(
    this.directories,
    this.files, {
    this.linkedDirectories = const {},
    this.linkedFiles = const {},
  });

  bool onlyOneChild() =>
      directories.length +
          files.length +
          linkedDirectories.length +
          linkedFiles.length <=
      1;

  bool get isEmpty =>
      directories.isEmpty &&
      files.isEmpty &&
      linkedDirectories.isEmpty &&
      linkedFiles.isEmpty;
  bool get isNotEmpty => !isEmpty;
}

class FolderLinkManager {
  static const String _linksFileName = '.saber_links.json';

  static Future<Map<String, String>> getLinks(String directoryPath) async {
    try {
      // Força o padrão POSIX (/) e garante que termina com barra
      var dir = directoryPath.replaceAll('\\', '/');
      if (!dir.endsWith('/')) dir += '/';
      final path = '${dir}$_linksFileName';
      
      final bytes = await FileManager.readFile(
        path,
        suppressLogs: true,
        allowMissing: true,
      );
      
      if (bytes != null && bytes.isNotEmpty) {
        // allowMalformed protege contra bytes de padding perdidos no cofre
        final content = utf8.decode(bytes, allowMalformed: true);
        final dynamic map = jsonDecode(content);
        if (map is Map) {
          return map.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      }
    } catch (e) {
      FileManager.log.warning('Failed to read links in $directoryPath: $e');
    }
    return {};
  }

  static Future<void> addLink(String directoryPath, String targetPath) async {
    final links = await getLinks(directoryPath);
    
    // Remove barras invertidas e qualquer barra solitária no final do caminho 
    // para evitar que o nome da pasta seja uma string vazia ("")
    var cleanTarget = targetPath.replaceAll('\\', '/');
    while (cleanTarget.endsWith('/') && cleanTarget.length > 1) {
      cleanTarget = cleanTarget.substring(0, cleanTarget.length - 1);
    }
    
    final parts = cleanTarget.split('/');
    String name = parts.last;

    var counter = 1;
    String finalName = name;
    // Se já existir um link com esse nome, adiciona um contador
    while (links.containsKey(finalName)) {
      finalName = '$name ($counter)';
      counter++;
    }

    links[finalName] = targetPath;
    
    var dir = directoryPath.replaceAll('\\', '/');
    if (!dir.endsWith('/')) dir += '/';
    final path = '${dir}$_linksFileName';
    
    await FileManager.writeFile(
      path,
      utf8.encode(jsonEncode(links)),
      awaitWrite: true,
    );
  }

  static Future<void> removeLink(String directoryPath, String linkKey) async {
    final links = await getLinks(directoryPath);
    if (links.remove(linkKey) != null) {
      var dir = directoryPath.replaceAll('\\', '/');
      if (!dir.endsWith('/')) dir += '/';
      final path = '${dir}$_linksFileName';
      
      await FileManager.writeFile(
        path,
        utf8.encode(jsonEncode(links)),
        awaitWrite: true,
      );
    }
  }

  static Future<void> showBrokenLinkDialog(BuildContext context) async {
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.4),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                width: 320,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.2),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 16,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.link_off_rounded,
                        size: 36,
                        color: Colors.redAccent,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Broken Link',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'The original file or folder has been deleted or moved.\n\nThis link will now be removed.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        decoration: TextDecoration.none,
                        fontWeight: FontWeight.normal,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Understood',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
    );
  }
}

enum FileOperationType { write, delete }

/// Why a [FileOperationType.delete] happened. Rename/move must not look like
/// a destructive delete in the preview card.
enum FileRemovalCause { deleted, renamed, moved }

class FileOperation {
  final FileOperationType type;
  final String filePath;
  final FileRemovalCause? removal;
  final bool isThumbnail;

  const FileOperation(
    this.type,
    this.filePath, {
    this.removal,
    this.isThumbnail = false,
  });
}

class BackupStatus {
  final bool isRunning;
  final double progress;
  final String currentFile;
  final int totalNotes;
  const BackupStatus({
    this.isRunning = false,
    this.progress = 0.0,
    this.currentFile = '',
    this.totalNotes = 0,
  });
}

class ExportStatus {
  final bool isExporting;
  final double progress;
  final String currentFile;
  const ExportStatus({
    this.isExporting = false,
    this.progress = 0.0,
    this.currentFile = '',
  });
}

class ExportManager {
  static final status = ValueNotifier(const ExportStatus());
  static final _log = Logger('ExportManager');

  static Future<T> exportInBackground<T>(
    String initialMessage,
    Future<T> Function(
      void Function(double progress, String message) onProgress,
    )
    exportFn,
  ) async {
    return BackgroundOperationQueue.instance.enqueue<T>(
      kind: BackgroundOperationKind.exportFile,
      headline: initialMessage,
      initialDetail: initialMessage,
      work: (bgOnProgress) async {
        try {
          return await exportFn((progress, message) {
            status.value = ExportStatus(
              isExporting: true,
              progress: progress,
              currentFile: message,
            );
            bgOnProgress(progress, message, indeterminate: false);
          });
        } catch (e, st) {
          _log.warning('Export failed: $e\n$st');
          rethrow;
        } finally {
          status.value = const ExportStatus();
        }
      },
    );
  }
}

class BackupManager {
  static final status = ValueNotifier(const BackupStatus());
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static final _log = Logger('BackupManager');
  static bool _notificationsInitialized = false;
  static bool _isCancelled = false;

  static void cancelBackup() {
    if (status.value.isRunning) {
      _isCancelled = true;
      status.value = const BackupStatus(
        isRunning: true,
        currentFile: 'Cancelling...',
        progress: 1.0,
      );
    }
  }

  static Future<void> initNotifications() async {
    if (_notificationsInitialized) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _notificationsPlugin.initialize(
        const InitializationSettings(android: androidInit),
      );
      _notificationsInitialized = true;
    } catch (e) {
      _log.warning('Failed to init notifications: $e');
    }
  }

  static bool get _canRunIncrementalBackup {
    final targetPath = stows.backupFilePath.value;
    final password = stows.backupPassword.value;
    if (targetPath.isEmpty || password.isEmpty) return false;
    if (FileManager._shouldUseVault && !VaultAdapter.isUnlocked) return false;
    return true;
  }

  /// Blocking Backup now: worker isolate so Android does not ANR.
  static Future<void> performIncrementalBackupForeground() async {
    if (!_canRunIncrementalBackup) {
      throw Exception(
        'Please select a target file and generate a key first.',
      );
    }
    await BackgroundOperationLock.runSerialized(() async {
      await _performIncrementalBackupWork(backgroundIsolate: false);
    });
  }

  /// Run in background / auto-backup: worker isolate, UI stays usable.
  static Future<void> performIncrementalBackupBackground() async {
    if (!_canRunIncrementalBackup) {
      throw Exception(
        'Please select a target file and generate a key first.',
      );
    }
    await BackgroundOperationQueue.instance.enqueue<void>(
      kind: BackgroundOperationKind.backup,
      headline: t.backup.notificationTitle,
      initialDetail: t.backup.notificationTitle,
      work: (onProgress) async {
        await _performIncrementalBackupWork(
          backgroundIsolate: true,
          onQueueProgress: onProgress,
        );
      },
    );
  }

  /// Same as [performIncrementalBackupBackground] (legacy callers / auto).
  static Future<void> performIncrementalBackup() =>
      performIncrementalBackupBackground();

  /// Headless WorkManager — worker isolate, never the UI isolate.
  static Future<void> performIncrementalBackupFromWorkManager() async {
    if (!_canRunIncrementalBackup) return;
    await BackgroundOperationLock.runSerialized(() async {
      await _performIncrementalBackupWork(backgroundIsolate: true);
    });
  }

  static Future<void> _performIncrementalBackupWork({
    required bool backgroundIsolate,
    BackgroundProgressCallback? onQueueProgress,
  }) async {
    final targetPath = stows.backupFilePath.value;
    final password = stows.backupPassword.value;

    _isCancelled = false;

    void report(double p, String msg, {bool indeterminate = false, int totalNotes = 0}) {
      status.value = BackupStatus(
        isRunning: true,
        progress: p,
        currentFile: msg,
        totalNotes: totalNotes,
      );
      onQueueProgress?.call(p, msg, indeterminate: indeterminate);
    }

    report(0.01, 'Preparing backup file...');
    await Future<void>.delayed(Duration.zero);

    // Create the archive on the UI isolate first so a first-time backup has a
    // real file at the chosen path, and permission errors surface immediately
    // instead of looking like a hang at 0% inside the worker isolate.
    try {
      prepareIncrementalBackupTarget(targetPath);
    } catch (e) {
      if (e is PathAccessException || e is FileSystemException) {
        throw Exception(
          'Cannot create backup file. Pick a public folder like Documents '
          'or Downloads. ($e)',
        );
      }
      rethrow;
    }
    report(0.02, 'Preparing...');

    VaultAdapter.preventLock = true;
    var physicalQuiesce = false;
    await initNotifications();

    try {
      await TagDatabase.instance.close();
      await NoteLinksDatabase.instance.close();

      if (FileManager._shouldUseVault && VaultAdapter.isUnlocked) {
        await VaultAdapter.instance.beginPhysicalBackupQuiesce();
        physicalQuiesce = true;
      }

      final extraDbFiles = <String, String>{};
      const dbNames = [
        '.saber_tags.db',
        '.saber_note_links.db',
      ];
      for (final dbName in dbNames) {
        final dbPath = p.join(FileManager.documentsDirectory, dbName);
        if (File(dbPath).existsSync()) {
          extraDbFiles['__db__/$dbName'] = dbPath;
        }
      }

      var noteCount = 0;
      if (FileManager._shouldUseVault && VaultAdapter.isUnlocked) {
        noteCount = await VaultAdapter.instance.getTotalFileCount();
      }
      // Data-mode note count is computed inside the worker isolate so a huge
      // documents tree does not freeze the UI at 0%.

      report(
        0.03,
        noteCount > 0
            ? 'Backing up $noteCount notes...'
            : 'Starting backup...',
        indeterminate: true,
        totalNotes: noteCount,
      );

      final prefs = await SharedPreferences.getInstance();
      final prefsMap = <String, dynamic>{};
      for (final key in prefs.getKeys()) {
        prefsMap[key] = prefs.get(key);
      }
      prefsMap['__sourceMode__'] = FileManager._shouldUseVault
          ? 'vaultPhysical'
          : 'data';

      final request = IncrementalBackupRequest(
        docsDir: FileManager.documentsDirectory,
        targetPath: targetPath,
        password: password,
        prefsMap: prefsMap,
        extraDbFiles: extraDbFiles,
        noteCount: noteCount,
      );

      var lastNotifyAt = 0.0;
      var lastNotes = noteCount;
      void reportThrottled(double p, String msg, {int? totalNotes}) {
        if (totalNotes != null && totalNotes > 0) lastNotes = totalNotes;
        report(p, msg, indeterminate: p < 0.05, totalNotes: lastNotes);
        if (backgroundIsolate && (p - lastNotifyAt >= 0.02 || p >= 1)) {
          lastNotifyAt = p;
          unawaited(_updateNotification(
            (p * 100).round().clamp(0, 100),
            100,
            totalNotes: lastNotes,
          ));
        }
      }

      // Never encrypt/scan on the UI isolate — Scrypt + listSync + zlib
      // block the Android main thread long enough for an ANR.
      await _runIncrementalBackupInIsolate(request, reportThrottled);

      if (!_isCancelled) {
        stows.lastBackupTimestamp.value = DateTime.now().millisecondsSinceEpoch;
      }
    } catch (e) {
      if (e is PathAccessException) {
        throw Exception(
          'Permission Denied. Please pick a public folder like "Documents".',
        );
      }
      rethrow;
    } finally {
      if (physicalQuiesce) {
        VaultAdapter.instance.endPhysicalBackupQuiesce();
      }
      status.value = const BackupStatus(isRunning: false);
      VaultAdapter.preventLock = false;
      await _cancelNotification();
    }
  }

  static Future<void> _runIncrementalBackupInIsolate(
    IncrementalBackupRequest request,
    void Function(double progress, String message, {int? totalNotes})
        onProgress,
  ) async {
    final receive = ReceivePort();
    try {
      await Isolate.spawn(incrementalBackupIsolateMain, <String, dynamic>{
        'sendPort': receive.sendPort,
        'docsDir': request.docsDir,
        'targetPath': request.targetPath,
        'password': request.password,
        'prefsMap': request.prefsMap,
        'extraDbFiles': request.extraDbFiles,
        'noteCount': request.noteCount,
      });
      await for (final raw in receive) {
        if (raw is! Map) continue;
        if (raw['error'] != null) {
          throw Exception(raw['error'].toString());
        }
        if (raw['done'] == true) return;
        final pVal = raw['p'];
        final m = raw['m'];
        final notes = raw['notes'];
        if (pVal is num && m is String) {
          onProgress(
            pVal.toDouble(),
            m,
            totalNotes: notes is num ? notes.toInt() : null,
          );
        }
      }
    } finally {
      receive.close();
    }
  }

  static Future<IncrementalBackupVerifyResult> verifyIncrementalBackup(
    String targetPath,
    String password,
  ) async {
    final file = File(targetPath);
    if (!file.existsSync()) {
      throw Exception('Backup file not found at path.');
    }

    void report(double p, String msg) {
      status.value = BackupStatus(
        isRunning: true,
        progress: p,
        currentFile: msg,
      );
    }

    report(0.02, 'Verifying backup...');

    final receive = ReceivePort();
    try {
      await Isolate.spawn(incrementalVerifyIsolateMain, <String, dynamic>{
        'sendPort': receive.sendPort,
        'targetPath': targetPath,
        'password': password,
      });
      await for (final raw in receive) {
        if (raw is! Map) continue;
        if (raw['error'] != null) {
          throw Exception(raw['error'].toString());
        }
        if (raw['done'] == true) {
          final resultMap = raw['result'];
          if (resultMap is! Map) {
            throw Exception('Verify returned no result.');
          }
          return IncrementalBackupVerifyResult.fromJson(
            Map<String, dynamic>.from(resultMap),
          );
        }
        final pVal = raw['p'];
        final m = raw['m'];
        if (pVal is num && m is String) {
          report(pVal.toDouble(), m);
        }
      }
      throw Exception('Verify isolate ended unexpectedly.');
    } finally {
      receive.close();
      status.value = const BackupStatus(isRunning: false);
    }
  }

  static Future<void> restoreIncrementalBackup(
    String targetPath,
    String password,
  ) async {
    final file = File(targetPath);
    if (!file.existsSync()) {
      throw Exception('Backup file not found at path.');
    }
    await BackgroundOperationQueue.instance.enqueue<void>(
      kind: BackgroundOperationKind.restoreBackup,
      headline: t.backup.restoreProgressTitle,
      initialDetail: t.backup.restoreProgressTitle,
      work: (onProgress) => _restoreIncrementalBackupWork(
        targetPath: targetPath,
        password: password,
        onQueueProgress: onProgress,
      ),
    );
  }

  static Future<void> _restoreIncrementalBackupWork({
    required String targetPath,
    required String password,
    required BackgroundProgressCallback onQueueProgress,
  }) async {
    void report(double p, String msg, {bool indeterminate = false}) {
      status.value = BackupStatus(
        isRunning: true,
        progress: p,
        currentFile: msg,
      );
      onQueueProgress(p, msg, indeterminate: indeterminate);
    }

    VaultAdapter.preventLock = true;

    final tempDir = await Directory.systemTemp.createTemp('saber_inc_restore_');
    try {
      report(0, 'Extracting backup...', indeterminate: true);

      await TagDatabase.instance.close();
      await NoteLinksDatabase.instance.close();

      final prefsData = await compute(_isolateIncrementalRestoreTask, {
        'targetPath': targetPath,
        'password': password,
        'tempDirPath': tempDir.path,
      });

      report(0.12, 'Applying data...', indeterminate: true);

      final sourceMode = prefsData['__sourceMode__']?.toString() ?? 'data';
      final physicalRestore =
          sourceMode == 'data' || sourceMode == 'vaultPhysical';

      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      for (final entry in prefsData.entries) {
        // Keep current storage root: documents were extracted there using the
        // active directory. Restoring a stale customDataDir could desync paths.
        if (entry.key == '__folders__' || entry.key == '__sourceMode__')
          continue;
        if (FileManager._unrestorableDevicePathPrefs(
          prefsData,
        ).contains(entry.key))
          continue;
        if (entry.value is String)
          await prefs.setString(entry.key, entry.value);
        else if (entry.value is int)
          await prefs.setInt(entry.key, entry.value);
        else if (entry.value is double)
          await prefs.setDouble(entry.key, entry.value);
        else if (entry.value is bool)
          await prefs.setBool(entry.key, entry.value);
        else if (entry.value is List)
          await prefs.setStringList(
            entry.key,
            (entry.value as List).cast<String>(),
          );
      }

      FileManager.documentsDirectory =
          await FileManager.getDocumentsDirectory();
      BackgroundOperationLock.configure(FileManager.documentsDirectory);

      if (!physicalRestore && FileManager._shouldUseVault) {
        final all = await VaultAdapter.instance.getAllFiles();
        for (final f in all) await VaultAdapter.instance.deleteFile(f);

        final foldersList = prefsData['__folders__'] as List<dynamic>? ?? [];
        for (final folder in foldersList) {
          await VaultAdapter.instance.createFolder(folder.toString());
        }

        final extractedFiles = await tempDir
            .list(recursive: true)
            .where((e) => e is File)
            .cast<File>()
            .toList();
        final total = extractedFiles.length;
        final tMax = total > 0 ? total : 1;
        var count = 0;

        for (final extractedFile in extractedFiles) {
          final relativePath = p
              .relative(extractedFile.path, from: tempDir.path)
              .replaceAll('\\', '/');

          if (relativePath.startsWith('__db__/')) {
            final destFile = File(
              p.join(FileManager.documentsDirectory, relativePath.substring(7)),
            );
            await destFile.parent.create(recursive: true);
            await extractedFile.copy(destFile.path);
          } else {
            final rel = _stripLeadingSlashesForPathJoin(relativePath);
            if (rel.isEmpty) continue;
            await VaultAdapter.instance.writeFile(
              rel,
              await extractedFile.readAsBytes(),
            );
          }

          count++;
          if (count % 10 == 0 || count == total) {
            final detail = relativePath.startsWith('__db__/')
                ? 'Database...'
                : relativePath;
            report(0.12 + 0.88 * (count / tMax), detail, indeterminate: false);
          }
          if (count % 5 == 0) await Future.delayed(Duration.zero);
        }
        if (total == 0) {
          report(1, 'Restore complete', indeterminate: false);
        }
      } else {
        // Physical restore: stage into a sibling dir, then swap atomically so a
        // crash never leaves an empty documents tree.
        final stagingDir = Directory(
          '${FileManager.documentsDirectory}.restore_new_${DateTime.now().microsecondsSinceEpoch}',
        );
        if (stagingDir.existsSync()) {
          await stagingDir.delete(recursive: true);
        }
        await stagingDir.create(recursive: true);

        final foldersList = prefsData['__folders__'] as List<dynamic>? ?? [];
        for (final folder in foldersList) {
          final rel = _stripLeadingSlashesForPathJoin(folder.toString());
          if (rel.isEmpty) continue;
          Directory(p.join(stagingDir.path, rel)).createSync(recursive: true);
        }

        final extractedFiles = await tempDir
            .list(recursive: true)
            .where((e) => e is File)
            .cast<File>()
            .toList();
        final total = extractedFiles.length;
        final tMax = total > 0 ? total : 1;
        var count = 0;

        for (final extractedFile in extractedFiles) {
          final relativePath = p
              .relative(extractedFile.path, from: tempDir.path)
              .replaceAll('\\', '/');

          final String destRel;
          if (relativePath.startsWith('__db__/')) {
            destRel = relativePath.substring(7);
          } else {
            destRel = _stripLeadingSlashesForPathJoin(relativePath);
          }
          if (destRel.isEmpty) continue;
          final destFile = File(p.join(stagingDir.path, destRel));
          await destFile.parent.create(recursive: true);
          await extractedFile.copy(destFile.path);

          count++;
          if (count % 10 == 0 || count == total) {
            final detail = relativePath.startsWith('__db__/')
                ? 'Database...'
                : relativePath;
            report(0.12 + 0.85 * (count / tMax), detail, indeterminate: false);
          }
          if (count % 5 == 0) await Future.delayed(Duration.zero);
        }

        report(0.97, 'Swapping documents...', indeterminate: true);
        final liveDir = Directory(FileManager.documentsDirectory);
        final oldDir = Directory(
          '${FileManager.documentsDirectory}.restore_old_${DateTime.now().microsecondsSinceEpoch}',
        );
        var movedOld = false;
        try {
          if (liveDir.existsSync()) {
            await liveDir.rename(oldDir.path);
            movedOld = true;
          }
          await stagingDir.rename(liveDir.path);
          if (movedOld && oldDir.existsSync()) {
            try {
              await oldDir.delete(recursive: true);
            } catch (_) {}
          }
        } catch (e) {
          if (movedOld && oldDir.existsSync() && !liveDir.existsSync()) {
            try {
              await oldDir.rename(liveDir.path);
            } catch (_) {}
          }
          if (stagingDir.existsSync()) {
            try {
              await stagingDir.delete(recursive: true);
            } catch (_) {}
          }
          rethrow;
        }

        report(1, 'Restore complete', indeterminate: false);
      }

      FileManager.documentsDirectory =
          await FileManager.getDocumentsDirectory();
      BackgroundOperationLock.configure(FileManager.documentsDirectory);
    } finally {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
      status.value = const BackupStatus(isRunning: false);
      VaultAdapter.preventLock = false;
    }
  }

  static Future<void> _updateNotification(
    int current,
    int total, {
    int totalNotes = 0,
  }) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        'backup_channel',
        'Backup Progress',
        channelDescription: 'Shows background backup progress',
        importance: Importance.low,
        priority: Priority.low,
        showProgress: true,
        maxProgress: total,
        progress: current,
        ongoing: true,
        onlyAlertOnce: true,
      );
      final body = totalNotes > 0
          ? '$totalNotes notes — $current%'
          : '$current / $total assets synced';
      await _notificationsPlugin.show(
        888,
        t.backup.notificationTitle,
        body,
        NotificationDetails(android: androidDetails),
      );
    } catch (_) {}
  }

  static Future<void> _cancelNotification() async {
    try {
      await _notificationsPlugin.cancel(888);
    } catch (_) {}
  }
}
