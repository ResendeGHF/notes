// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
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
import 'package:saber/components/editor/pdf_outline_extractor.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/editor_exporter.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/editor/pdf_outline.dart';
import 'package:saber/data/home_data_cache.dart';
import 'package:saber/data/note_links_database.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tags_database.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:saber/services/sba_encryption.dart';
import 'package:saber/services/vault_adapter.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:screenshot/screenshot.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:jdenticon_dart/jdenticon_dart.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<bool> _isolateDataBackupTask(Map<String, dynamic> args) async {
  final docsDir = Directory(args['docsDir'] as String);
  final destPath = args['destPath'] as String;
  final password = args['password'] as String;
  final prefsJson = args['prefsJson'] as List<int>;

  const manifest = {'type': 'data', 'version': 2};
  final manifestJson = utf8.encode(jsonEncode(manifest));

  final archive = Archive();
  archive.addFile(
    ArchiveFile('_backup_manifest.json', manifestJson.length, manifestJson),
  );
  archive.addFile(
    ArchiveFile('_preferences.json', prefsJson.length, prefsJson),
  );

  if (docsDir.existsSync()) {
    final entities = docsDir.listSync(recursive: true);
    for (final entity in entities) {
      if (entity is File) {
        final relative = p.relative(entity.path, from: docsDir.path);
        final zipPath = p.posix.join('data', relative);
        final bytes = entity.readAsBytesSync();
        archive.addFile(ArchiveFile(zipPath, bytes.length, bytes));
      }
    }
  }

  final zipBytes = ZipEncoder().encode(archive);

  List<int> finalBytes = zipBytes;
  if (password.isNotEmpty) {
    finalBytes = SbaEncryption.encrypt(Uint8List.fromList(zipBytes), password);
  }

  final target = File(destPath);
  if (target.existsSync()) {
    target.deleteSync();
  }
  target.writeAsBytesSync(finalBytes);
  return true;
}

Future<bool> _isolateDataRestoreTask(Map<String, dynamic> args) async {
  final archivePath = args['archivePath'] as String;
  final password = args['password'] as String;
  final tempDirPath = args['tempDirPath'] as String;

  List<int> bytes = File(archivePath).readAsBytesSync();
  final byteList = Uint8List.fromList(bytes);

  if (SbaEncryption.isEncrypted(byteList)) {
    if (password.isEmpty)
      throw StateError('Backup is encrypted but no password was provided.');
    bytes = SbaEncryption.decrypt(byteList, password);
  }

  final archive = ZipDecoder().decodeBytes(bytes);

  final manifestFiles = archive.files
      .where((f) => f.name == '_backup_manifest.json')
      .toList();
  if (manifestFiles.isEmpty)
    throw StateError(
      'Invalid backup: missing manifest (not a data backup archive)',
    );
  final manifestJson =
      jsonDecode(utf8.decode(manifestFiles.first.content as List<int>))
          as Map<String, dynamic>;
  if (manifestJson['type'] != 'data')
    throw StateError(
      'Invalid backup: wrong type (expected data, got ${manifestJson['type']})',
    );

  for (final file in archive.files) {
    final outPath = p.join(tempDirPath, file.name);
    if (file.isFile) {
      final outFile = File(outPath);
      outFile.parent.createSync(recursive: true);
      outFile.writeAsBytesSync(file.content as List<int>);
    } else {
      Directory(outPath).createSync(recursive: true);
    }
  }
  return true;
}

Future<Uint8List> _isolateEncryptBlock(Map<String, dynamic> args) async {
  final data = args['data'] as Uint8List;
  final password = args['password'] as String;
  final compressed = const ZLibEncoder().encode(data);
  return SbaEncryption.encrypt(Uint8List.fromList(compressed), password);
}

Future<Uint8List> _isolateEncryptIndex(Map<String, dynamic> args) async {
  final index = args['index'] as Map<String, dynamic>;
  final password = args['password'] as String;
  final compressed = const ZLibEncoder().encode(utf8.encode(jsonEncode(index)));
  return SbaEncryption.encrypt(Uint8List.fromList(compressed), password);
}

Future<Map<String, dynamic>> _isolateIncrementalRestoreTask(
  Map<String, dynamic> args,
) async {
  final targetPath = args['targetPath'] as String;
  final password = args['password'] as String;
  final tempDirPath = args['tempDirPath'] as String;

  final file = File(targetPath);
  final raf = file.openSync(mode: FileMode.read);
  final magicBytes = utf8.encode('SBA_INC1');

  final magic = raf.readSync(8);
  bool magicValid = true;
  for (int i = 0; i < 8; i++) {
    if (magic[i] != magicBytes[i]) magicValid = false;
  }
  if (!magicValid) {
    raf.closeSync();
    throw Exception('Invalid Backup File Format.');
  }

  raf.setPositionSync(8);
  final offsetBytes = raf.readSync(8);
  final indexOffset = ByteData.view(
    offsetBytes.buffer,
  ).getInt64(0, Endian.little);

  raf.setPositionSync(indexOffset);
  final encryptedIndex = raf.readSync(file.lengthSync() - indexOffset);

  late Map<String, dynamic> index;
  try {
    final decryptedIndex = SbaEncryption.decrypt(encryptedIndex, password);
    final indexJson = utf8.decode(
      const ZLibDecoder().decodeBytes(decryptedIndex),
    );
    index = jsonDecode(indexJson) as Map<String, dynamic>;
  } catch (e) {
    raf.closeSync();
    throw Exception('Invalid Key or corrupted backup archive.');
  }

  final filesMap = index['files'] as Map<String, dynamic>? ?? {};

  for (final entry in filesMap.entries) {
    final filePath = entry.key;
    final block = entry.value;

    raf.setPositionSync(block['o'] as int);
    final encrypted = raf.readSync(block['l'] as int);
    final data = const ZLibDecoder().decodeBytes(
      SbaEncryption.decrypt(encrypted, password),
    );

    final destFile = File(p.join(tempDirPath, filePath));
    destFile.parent.createSync(recursive: true);
    destFile.writeAsBytesSync(data);
  }
  raf.closeSync();

  return index['preferences'] as Map<String, dynamic>? ?? {};
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

  static bool isCountableFile(String path) {
    final name = p.basename(path);
    if (name.startsWith('.')) return false;
    if (name.endsWith('.p')) return false;
    if (assetFileRegex.hasMatch(name)) return false;

    final normalized = path.toLowerCase();
    if (normalized.contains('/data/') ||
        normalized.startsWith('data/') ||
        normalized.contains('/file_picker/') ||
        normalized.startsWith('file_picker/')) {
      return false;
    }

    return true;
  }

  static Future<void> init({
    String? documentsDirectory,
    bool shouldWatchRootDirectory = true,
  }) async {
    FileManager.documentsDirectory =
        documentsDirectory ?? await getDocumentsDirectory();

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
    String password,
  ) async {
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

    await compute(_isolateDataBackupTask, {
      'docsDir': docsDir.path,
      'destPath': destinationPath,
      'password': password,
      'prefsJson': prefsJson,
    });

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

      final dataDir = Directory(p.join(tempDir.path, 'data'));
      if (dataDir.existsSync()) {

        await TagDatabase.instance.close();
        await NoteLinksDatabase.instance.close();

        final docDir = await getDocumentsDirectory();
        final destDir = Directory(docDir);
        if (destDir.existsSync()) {
          await destDir.delete(recursive: true);
        }
        await destDir.create(recursive: true);
        await moveDirContents(oldDir: dataDir, newDir: destDir);
      }

      documentsDirectory = await getDocumentsDirectory();

      final prefsFile = File(p.join(tempDir.path, _preferencesBackupPath));
      if (prefsFile.existsSync()) {
        const excludePrefs = {'customDataDir'};
        final prefsJson =
            jsonDecode(await prefsFile.readAsString()) as Map<String, dynamic>;
        final sharedPrefs = await SharedPreferences.getInstance();
        await sharedPrefs.clear();
        for (final entry in prefsJson.entries) {
          if (excludePrefs.contains(entry.key)) continue;
          final value = entry.value;
          if (value == null) continue;
          if (value is int) {
            await sharedPrefs.setInt(entry.key, value);
          } else if (value is double) {
            await sharedPrefs.setDouble(entry.key, value);
          } else if (value is bool) {
            await sharedPrefs.setBool(entry.key, value);
          } else if (value is String) {
            await sharedPrefs.setString(entry.key, value);
          } else if (value is List) {
            await sharedPrefs.setStringList(
              entry.key,
              value.map((e) => e.toString()).toList(),
            );
          }
        }
      }
    } finally {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  static Future<bool> isDataBackupArchive(String path) async {
    try {
      final bytes = File(path).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      final manifestFiles = archive.files
          .where((f) => f.name == _dataBackupManifestPath)
          .toList();
      final manifestFile = manifestFiles.isNotEmpty
          ? manifestFiles.first
          : null;
      if (manifestFile == null) return false;
      final manifestJson =
          jsonDecode(utf8.decode(manifestFile.content as List<int>))
              as Map<String, dynamic>;
      return manifestJson['type'] == 'data';
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

  @visibleForTesting
  static void broadcastFileWrite(FileOperationType type, String path) async {
    if (!fileWriteStream.hasListener) return;

    path = toRelativePath(path);

    if (path.endsWith(Editor.extension)) {
      path = path.substring(0, path.length - Editor.extension.length);
    } else if (path.endsWith(Editor.extensionOldJson)) {
      path = path.substring(0, path.length - Editor.extensionOldJson.length);
    }

    fileWriteStream.add(FileOperation(type, path));
  }

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

        var result = await VaultAdapter.instance.readFile(
          relativePath,
          onProgress: onProgress,
        );

        if (result != null) {
          if (result.isEmpty) {
            if (!suppressLogs && !allowMissing) {
              log.warning(
                '[FileManager.readFile] Read empty file from vault: $relativePath',
              );
            }
          } else {
            if (filePath.endsWith(Editor.extension)) {
              try {
                final decompressed = const ZLibDecoder().decodeBytes(result);
                result = Uint8List.fromList(decompressed);
              } catch (e) {

              }
            }
            if (!suppressLogs) {
              log.info(
                '[FileManager.readFile] Successfully read ${result?.length} bytes from vault: $relativePath',
              );
            }
          }
          return result;
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
          if (filePath.endsWith(Editor.extension)) {
            try {
              final decompressed = const ZLibDecoder().decodeBytes(result);
              result = Uint8List.fromList(decompressed);
            } catch (e) {

            }
          }
          if (!suppressLogs) {
            log.fine(
              '[FileManager.readFile] Successfully read ${result!.length} bytes from disk: $filePath',
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
    bool alsoUpload = true,
    DateTime? lastModified,
  }) async {
    final originalPath = filePath;

    filePath = _sanitisePath(filePath);

    log.info(
      '[FileManager.writeFile] Writing ${toWrite.length} bytes to: $filePath (original: $originalPath, vault: $_shouldUseVault)',
    );

    await _saveFileAsRecentlyAccessed(filePath);

    if (_shouldUseVault) {
      final relativePath = toRelativePath(filePath);

      List<int> compressedData = toWrite;
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
            compressedData = const ZLibEncoder().encode(toWrite);
          }
        } catch (e) {
          log.warning('Failed to compress file before vaulting: $filePath', e);
        }
      }

      final dataToWrite = compressedData is Uint8List
          ? compressedData
          : Uint8List.fromList(compressedData);

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
            awaitDbCommit: awaitWrite,
          );
          if (!success) {
            throw Exception('Failed to write file to vault: $relativePath');
          }
          log.info(
            '[FileManager.writeFile] Successfully wrote to vault: $relativePath',
          );
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
            dataToWrite = const ZLibEncoder().encode(toWrite);
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
          ).delete()

          .catchError((_) => File(''), test: (e) => e is PathNotFoundException),
      ]);

      void afterWrite() {
        log.fine(
          '[FileManager.writeFile] Successfully wrote to disk: $filePath',
        );

        if (isCountableFile(filePath)) {
          final newSize = toWrite.length;
          _updateDiskFolderProps(
            filePath,
            isNewFile ? 1 : 0,
            newSize - oldSize,
          );
        }
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
  }) async {
    filePath = _sanitisePath(filePath);
    if (_shouldUseVault) {
      final relativePath = toRelativePath(filePath);
      if (!VaultAdapter.isUnlocked) {
        throw Exception('Vault is locked');
      }
      await VaultAdapter.instance.writeFileFromPath(
        sourcePath,
        relativePath,
        awaitDbCommit: awaitWrite,
      );
      broadcastFileWrite(FileOperationType.write, filePath);
      return;
    }
    await _createFileDirectory(filePath);
    final dest = getFile(filePath);
    await File(sourcePath).copy(dest.path);
    broadcastFileWrite(FileOperationType.write, filePath);
  }

  static Future<void> writeFilesBulk(
    Map<String, Uint8List> files, {
    bool awaitWrite = true,
  }) async {
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
        awaitDbCommit: awaitWrite,
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
          sourceData = await VaultAdapter.instance.readFile(sourceRelative);
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

    await _createFileDirectory(
      filePath,
    );

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
          ).delete()

          .catchError((_) => File(''), test: (e) => e is PathNotFoundException),
      ]);

      void afterWrite() async {
        log.fine(
          '[FileManager.copyFile] Successfully copied to disk: $filePath',
        );
        if (isCountableFile(relativePathForCount)) {
          final newSize = fileFrom.lengthSync();
          _updateDiskFolderProps(
            relativePathForCount,
            isNewFile ? 1 : 0,
            newSize - oldSize,
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

        final data = await VaultAdapter.instance.readFile(oldRelative);
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

              final data = await VaultAdapter.instance.readFile(oldRelative);
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
      await Future.wait([
        for (final assetExt in assets)
          getFile(
            '$oldPathWithExt.$assetExt',
          ).copy(getFile('$newPathWithExt.$assetExt').path),
      ]);
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
        final baseName =
            linkName.substring(0, linkName.length - ext.length);
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

    final bytes = encodeFolderArchive(archive, format);
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

          await Future.wait([
            for (final assetPath in assets)
              () async {
                if (!assetPath.startsWith(fromRelative)) return;
                final suffix = assetPath.substring(fromRelative.length);
                final oldAssetPath = assetPath;
                final newAssetPath = '$toRelative$suffix';
                final assetData = await VaultAdapter.instance.readFile(
                  oldAssetPath,
                );
                if (assetData != null) {
                  await VaultAdapter.instance.writeFile(
                    newAssetPath,
                    assetData,
                  );
                  await VaultAdapter.instance.deleteFile(oldAssetPath);
                }
              }(),
          ]);
          log.fine(
            '[FileManager.moveFile] Moved ${assets.length} assets and preview in vault',
          );
        }

        _renameReferences(fromPath, toPath);
        broadcastFileWrite(FileOperationType.delete, fromPath);
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
    broadcastFileWrite(FileOperationType.delete, fromPath);
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

    return toPath;
  }

  static Future deleteFile(
    String filePath, {
    bool alsoUpload = true,
    bool alsoDeleteAssets = true,
  }) async {
    filePath = _sanitisePath(filePath);

    if (!await doesFileExist(filePath)) {
      log.fine('[FileManager.deleteFile] Source already deleted: $filePath');
      return;
    }

    final notePath = _notePathFromMainNoteFile(filePath);

    if (notePath != null) {
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
          return;
        }

        await VaultAdapter.instance.deleteFile(relativePath);
        log.fine(
          '[FileManager.deleteFile] Successfully deleted from vault: $relativePath',
        );
        _removeReferences(filePath);
        broadcastFileWrite(FileOperationType.delete, filePath);

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
      return;
    }

    try {
      final int oldSize = file.lengthSync();

      await file.delete();
      log.fine(
        '[FileManager.deleteFile] Successfully deleted from disk: $filePath',
      );
      if (isCountableFile(filePath)) {
        _updateDiskFolderProps(filePath, -1, -oldSize);
      }
      _removeReferences(filePath);
      broadcastFileWrite(FileOperationType.delete, filePath);

      if (alsoDeleteAssets && !assetFileRegex.hasMatch(filePath)) {
        final assets = <int>[];
        for (int assetNumber = 0; true; assetNumber++) {
          final assetFile = getFile('$filePath.$assetNumber');
          if (assetFile.existsSync()) {
            assets.add(assetNumber);
          } else {
            break;
          }
        }

        final previewFile = getFile('$filePath.p');
        await Future.wait([
          for (final assetNumber in assets)
            deleteFile('$filePath.$assetNumber', alsoDeleteAssets: false),
          if (previewFile.existsSync())
            deleteFile('$filePath.p', alsoDeleteAssets: false),
        ]);
        log.fine(
          '[FileManager.deleteFile] Deleted ${assets.length} assets and preview from disk for: $filePath',
        );
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
        broadcastFileWrite(FileOperationType.delete, oldRelative);
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
      broadcastFileWrite(FileOperationType.delete, directoryPath + child);
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
        broadcastFileWrite(FileOperationType.delete, oldRelative);
        broadcastFileWrite(FileOperationType.write, newRelative);
      }
      return;
    }

    directoryPath = _sanitisePath(directoryPath);
    destinationParent = _sanitisePath(destinationParent);

    final directory = Directory(documentsDirectory + directoryPath);
    if (!directory.existsSync()) return;

    int currentCount = 0;
    int currentSize = 0;
    final propsFile = File(p.join(directory.path, '.folder_props'));
    if (await propsFile.exists()) {
      try {
        final content = jsonDecode(await propsFile.readAsString());
        currentCount = content['file_count'] ?? 0;
        currentSize = content['total_size'] ?? 0;
      } catch (_) {}
    }

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
      broadcastFileWrite(FileOperationType.delete, directoryPath + child);
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

      broadcastFileWrite(FileOperationType.delete, relativePath);
      return;
    }

    directoryPath = _sanitisePath(directoryPath);

    final directory = Directory(documentsDirectory + directoryPath);
    if (!directory.existsSync()) return;

    int currentCount = 0;
    int currentSize = 0;
    final propsFile = File(p.join(directory.path, '.folder_props'));
    if (await propsFile.exists()) {
      try {
        final content = jsonDecode(await propsFile.readAsString());
        currentCount = content['file_count'] ?? 0;
        currentSize = content['total_size'] ?? 0;
      } catch (_) {}
    }

    if (recursive) {

      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          final childPath = entity.path.substring(documentsDirectory.length);
          _removeReferences(childPath);
          broadcastFileWrite(FileOperationType.delete, childPath);
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
      final matchingFiles = await VaultAdapter.instance.getFilesByPrefix(
        directory,
        ensureTrailingSlash: true,
      );
      final matchingFolders = await VaultAdapter.instance.getFoldersByPrefix(
        directory,
        ensureTrailingSlash: true,
      );
      log.fine(
        '[FileManager.getChildrenOfDirectory] Found ${matchingFiles.length} files matching directory prefix',
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

    final Iterable<String> allChildren;
    final List<String> directories = [], files = [];

    final dir = Directory(documentsDirectory + directory);
    if (!dir.existsSync()) return null;

    final int directoryPrefixLength = directory.endsWith('/')
        ? directory.length
        : directory.length + 1;
    allChildren = await dir
        .list()
        .map((FileSystemEntity entity) {
          final filePath = entity.path.substring(documentsDirectory.length);
          final name = p.basename(entity.path);

          if (name == 'data' || name == 'file_picker') return null;

          if (entity is Directory) return filePath;

          if (Editor.isReservedPath(filePath)) return null;

          late final isSbn2 = filePath.endsWith(Editor.extension);
          late final isSbn1 = filePath.endsWith(Editor.extensionOldJson);

          if (!includeExtensions) {
            if (isSbn2) {
              return filePath.substring(
                0,
                filePath.length - Editor.extension.length,
              );
            } else if (isSbn1) {
              return filePath.substring(
                0,
                filePath.length - Editor.extensionOldJson.length,
              );
            } else {
              return null;
            }
          } else if (!includeAssets) {
            final isAsset = !isSbn2 && !isSbn1;
            if (isAsset) return null;
          }

          return filePath;
        })
        .where((String? file) => file != null)

        .map((file) => file!.substring(directoryPrefixLength))
        .toList();

    await Future.wait(
      allChildren.map((child) async {

        if (await FileManager.isDirectory(directory + child) &&
            !directories.contains(child)) {
          directories.add(child);
        } else if (!includeAssets && assetFileRegex.hasMatch(child)) {

        } else {
          files.add(child);
        }
      }),
    );

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
        .map((String filePath) {
          if (filePath.endsWith(Editor.extension)) {
            return filePath.substring(
              0,
              filePath.length - Editor.extension.length,
            );
          } else if (filePath.endsWith(Editor.extensionOldJson)) {
            return filePath.substring(
              0,
              filePath.length - Editor.extensionOldJson.length,
            );
          } else {
            return filePath;
          }
        })
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

    try {
      folderPath = _sanitisePath(folderPath);
      if (!folderPath.startsWith('/')) folderPath = '/$folderPath';
      final dirPath = documentsDirectory + folderPath;

      final propsFile = File(p.join(dirPath, '.folder_props'));
      if (await propsFile.exists()) {
        try {
          final content = jsonDecode(await propsFile.readAsString());
          return content['file_count'] ?? 0;
        } catch (_) {}
      }

      final countFile = File(p.join(dirPath, '.folder_count'));
      if (await countFile.exists()) {
        final content = await countFile.readAsString();
        return int.tryParse(content) ?? 0;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  static Future<Map<String, int>> getFolderFileCountsBatch(
    List<String> folderPaths,
  ) async {
    if (folderPaths.isEmpty) return const {};
    if (_shouldUseVault) {
      return VaultAdapter.instance.getFolderFileCounts(folderPaths);
    }

    final result = <String, int>{};
    for (final folderPath in folderPaths) {
      var normalized = toRelativePath(folderPath);
      if (!normalized.endsWith('/')) normalized += '/';
      result[normalized] = await getFolderFileCount(folderPath);
    }
    return result;
  }

  static Future<int> getTotalFileCount() async {
    if (_shouldUseVault) {
      return await VaultAdapter.instance.getTotalFileCount();
    }

    try {
      final rootPropsFile = File(p.join(documentsDirectory, '.folder_props'));
      if (await rootPropsFile.exists()) {
        try {
          final content = jsonDecode(await rootPropsFile.readAsString());
          return content['file_count'] ?? 0;
        } catch (_) {}
      }

      final rootCountFile = File(p.join(documentsDirectory, '.folder_count'));
      if (await rootCountFile.exists()) {
        final cached = int.tryParse(await rootCountFile.readAsString());
        if (cached != null) return cached;
      }
      return 0;
    } catch (_) {
      return 0;
    }
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
    if (!fromCountable && !toCountable) return;

    final deltasC = <String, int>{};
    final deltasS = <String, int>{};

    void addPath(String filePath, int sign) {
      var currentPath = p.dirname(_sanitisePath(filePath));
      while (true) {
        deltasC[currentPath] = (deltasC[currentPath] ?? 0) + sign;
        deltasS[currentPath] = (deltasS[currentPath] ?? 0) + (sign * size);
        if (currentPath == '/' || currentPath == '.') break;
        currentPath = p.dirname(currentPath);
      }
    }

    if (fromCountable) addPath(fromPath, -1);
    if (toCountable) addPath(toPath, 1);

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
            'created_at': created,
            'last_modified': now,
          }),
        );
      } catch (_) {}
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
          return jsonDecode(await propsFile.readAsString());
        } catch (_) {}
      }
      final size = await getFolderFileCount(folderPath);
      return {
        'file_count': size,
        'total_size': 0,
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
      List<int> sbaBytes = await File(path).readAsBytes();
      final bytesList = Uint8List.fromList(sbaBytes);

      if (SbaEncryption.isEncrypted(bytesList)) {
        final password = await getEncryptionPassword?.call();
        if (password == null || password.isEmpty) {
          log.warning(
            'Encrypted SBA requires password. Provide getEncryptionPassword.',
          );
          return null;
        }
        try {
          sbaBytes = SbaEncryption.decrypt(bytesList, password);
        } on ArgumentError catch (e) {
          log.warning('SBA decryption failed: $e');
          return null;
        }
      }

      final archive = ZipDecoder().decodeBytes(Uint8List.fromList(sbaBytes));

      final mainFile = archive.files.cast<ArchiveFile?>().firstWhere(
        (file) =>
            file!.name.toLowerCase().endsWith('sbn') ||
            file.name.toLowerCase().endsWith('sbn2'),
        orElse: () => null,
      );
      if (mainFile == null) {
        log.severe('Failed to find main note in sba: $path');
        return null;
      }
      final mainFileExtension = '.${mainFile.name.split('.').last}'
          .toLowerCase();
      importedPath = await suffixFilePathToMakeItUnique(
        '${parentDir ?? '/'}$fileName',
        intendedExtension: mainFileExtension,
      );
      final mainFileContents = () {
        final output = OutputMemoryStream();
        mainFile.writeContent(output);
        return output.getBytes();
      }();
      writeFutures.add(
        writeFile(
          importedPath + mainFileExtension,
          mainFileContents,
          awaitWrite: awaitWrite,
        ),
      );

      for (final file in archive.files) {
        if (!file.isFile) continue;
        if (file == mainFile) continue;

        final extension = file.name.split('.').last;
        final assetNumber = int.tryParse(extension);
        if (assetNumber == null) continue;
        if (assetNumber < 0) continue;

        final assetBytes = () {
          final output = OutputMemoryStream();
          file.writeContent(output);
          return output.getBytes();
        }();
        writeFutures.add(
          writeFile(
            '$importedPath$mainFileExtension.$assetNumber',
            assetBytes,
            awaitWrite: awaitWrite,
          ),
        );
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
  }) async {
    try {
      final pdfFile = File(pdfPath);
      if (!pdfFile.existsSync()) return false;

      final coreInfo = EditorCoreInfo(filePath: sbnFilePath);

      final assetId = await coreInfo.assetCacheAll.addPdfFast(pdfFile);

      final doc = await PdfDocument.openFile(pdfPath);
      if (pdfOutlines == null) {
        try {
          coreInfo.pdfOutlines = await PdfOutlineExtractor.extractOutlines(doc);
        } catch (e) {
          log.fine('Could not extract PDF outlines: $e');
        }
      } else {
        coreInfo.pdfOutlines = pdfOutlines;
      }

      for (int i = 0; i < doc.pages.length; i++) {
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

      final fullSavePath = getFilePath(sbnFilePath + Editor.extension);
      await coreInfo.assetCacheAll.renumberBeforeSave(fullSavePath);

      final bson = coreInfo.saveToBinary(currentPageIndex: 0);

      await writeFile(sbnFilePath + Editor.extension, bson, awaitWrite: true);

      final bool thumbnailGenerated = await generateThumbnailFromPdf(
        pdfPath,
        '$sbnFilePath${Editor.extension}.p',
      );

      if (!thumbnailGenerated) {
        await _generateThumbnail(
          coreInfo: coreInfo,
          theme: theme,
          mediaQuery: mediaQuery,
          path: '$sbnFilePath${Editor.extension}.p',
        );
      }

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

  static Future _renameReferences(String fromPath, String toPath) async {

    bool replaced = false;
    for (int i = 0; i < stows.recentFiles.value.length; i++) {
      if (stows.recentFiles.value[i] != fromPath) continue;
      if (!replaced) {
        stows.recentFiles.value[i] = toPath;
        replaced = true;
      } else {
        stows.recentFiles.value.removeAt(i);
      }
    }
    stows.recentFiles.notifyListeners();
  }

  static Future _removeReferences(String filePath) async {

    final normalizedTarget = toRelativePath(filePath);

    for (int i = stows.recentFiles.value.length - 1; i >= 0; i--) {
      final normalizedRecent = toRelativePath(stows.recentFiles.value[i]);

      if (normalizedRecent == normalizedTarget) {
        stows.recentFiles.value.removeAt(i);
      }
    }

    stows.recentFiles.notifyListeners();
  }

  static Future _saveFileAsRecentlyAccessed(String filePath) async {

    if (assetFileRegex.hasMatch(filePath)) return;

    stows.recentFiles.value.remove(filePath);
    stows.recentFiles.value.insert(0, filePath);
    if (stows.recentFiles.value.length > maxRecentlyAccessedFiles)
      stows.recentFiles.value.removeLast();

    stows.recentFiles.notifyListeners();
  }

  static const maxRecentlyAccessedFiles = 30;

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
                        overrideInvert:
                            false,
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
  }) async {
    PdfDocument? document;
    try {

      if (fileBytes != null) {
        document = await PdfDocument.openData(fileBytes);
      }

      else if (await File(pdfPath).exists()) {
        document = await PdfDocument.openFile(pdfPath);
      }

      else {
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
      document?.dispose();
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
      final path = p.join(directoryPath, _linksFileName).replaceAll('\\', '/');
      final bytes = await FileManager.readFile(
        path,
        suppressLogs: true,
        allowMissing: true,
      );
      if (bytes != null && bytes.isNotEmpty) {
        final content = utf8.decode(bytes);
        final map = jsonDecode(content) as Map<String, dynamic>;
        return map.map((k, v) => MapEntry(k, v.toString()));
      }
    } catch (e) {
      FileManager.log.warning('Failed to read links in $directoryPath: $e');
    }
    return {};
  }

  static Future<void> addLink(String directoryPath, String targetPath) async {
    final links = await getLinks(directoryPath);
    String name = p.basename(targetPath);

    var counter = 1;
    String finalName = name;
    while (links.containsKey(finalName)) {
      finalName = '$name ($counter)';
      counter++;
    }

    links[finalName] = targetPath;
    final path = p.join(directoryPath, _linksFileName).replaceAll('\\', '/');
    await FileManager.writeFile(
      path,
      utf8.encode(jsonEncode(links)),
      awaitWrite: true,
    );
  }

  static Future<void> removeLink(String directoryPath, String linkKey) async {
    final links = await getLinks(directoryPath);
    if (links.remove(linkKey) != null) {
      final path = p.join(directoryPath, _linksFileName).replaceAll('\\', '/');
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

class FileOperation {
  final FileOperationType type;
  final String filePath;

  const FileOperation(this.type, this.filePath);
}

class BackupStatus {
  final bool isRunning;
  final double progress;
  final String currentFile;
  const BackupStatus({
    this.isRunning = false,
    this.progress = 0.0,
    this.currentFile = '',
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
  static Completer<void>? _exportCompleter;

  static Future<void> awaitExportComplete() async {
    while (status.value.isExporting) {
      _exportCompleter ??= Completer<void>();
      await _exportCompleter!.future;
    }
  }

  static void _onExportDone() {
    status.value = const ExportStatus();
    _exportCompleter?.complete();
    _exportCompleter = null;
  }

  static Future<T?> exportInBackground<T>(
    String initialMessage,
    Future<T> Function(void Function(double progress, String message) onProgress)
        exportFn,
  ) async {
    if (status.value.isExporting) return null;
    _exportCompleter = Completer<void>();
    status.value = ExportStatus(
      isExporting: true,
      progress: 0.0,
      currentFile: initialMessage,
    );
    try {
      final result = await exportFn((progress, message) {
        status.value = ExportStatus(
          isExporting: true,
          progress: progress,
          currentFile: message,
        );
      });
      _onExportDone();
      return result;
    } catch (e, st) {
      _log.warning('Export failed: $e\n$st');
      _onExportDone();
      rethrow;
    }
  }
}

class BackupManager {
  static final status = ValueNotifier(const BackupStatus());
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static final _log = Logger('BackupManager');
  static final _magicBytes = utf8.encode('SBA_INC1');
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

  static Future<List<String>> _getAllDiskFilesForBackup() async {
    final dir = Directory(FileManager.documentsDirectory);
    if (!dir.existsSync()) return [];
    final files = await dir
        .list(recursive: true)
        .where((e) => e is File)
        .cast<File>()
        .toList();
    return files
        .map((f) => p.relative(f.path, from: dir.path).replaceAll('\\', '/'))
        .toList();
  }

  static Future<void> performIncrementalBackup() async {
    final targetPath = stows.backupFilePath.value;
    final password = stows.backupPassword.value;

    if (targetPath.isEmpty || password.isEmpty) return;
    if (status.value.isRunning) return;
    if (FileManager._shouldUseVault && !VaultAdapter.isUnlocked) return;

    await ExportManager.awaitExportComplete();

    _isCancelled = false;
    status.value = const BackupStatus(
      isRunning: true,
      progress: 0.0,
      currentFile: 'Initializing...',
    );
    VaultAdapter.preventLock = true;
    await initNotifications();

    try {

      await TagDatabase.instance.close();
      await NoteLinksDatabase.instance.close();

      final file = File(targetPath);
      Map<String, dynamic> index = {
        'files': <String, dynamic>{},
        'preferences': <String, dynamic>{},
      };

      if (!file.existsSync() || file.lengthSync() < 16) {
        try {
          await file.parent.create(recursive: true);
          await file.create();
        } on PathAccessException catch (_) {
          throw Exception(
            'Permission Denied. Pick a public folder like "Documents".',
          );
        }
        final rafInit = await file.open(mode: FileMode.write);
        await rafInit.writeFrom(_magicBytes);
        final offsetData = ByteData(8)..setInt64(0, 16, Endian.little);
        await rafInit.writeFrom(offsetData.buffer.asUint8List());
        await rafInit.close();
      }

      final raf = await file.open(mode: FileMode.append);
      await raf.setPosition(8);
      final offsetBytes = await raf.read(8);
      final currentIndexOffset = ByteData.view(
        offsetBytes.buffer,
      ).getInt64(0, Endian.little);

      if (currentIndexOffset < file.lengthSync()) {
        await raf.setPosition(currentIndexOffset);
        final encryptedIndex = await raf.read(
          file.lengthSync() - currentIndexOffset,
        );
        if (encryptedIndex.isNotEmpty) {
          try {
            final decryptedIndex = SbaEncryption.decrypt(
              encryptedIndex,
              password,
            );
            index = jsonDecode(
              utf8.decode(const ZLibDecoder().decodeBytes(decryptedIndex)),
            );
          } catch (e) {
            _log.warning('Corrupted archive index. Starting fresh block.');
          }
        }
      }

      final sourceFilesList = FileManager._shouldUseVault
          ? await VaultAdapter.instance.getAllFiles()
          : await _getAllDiskFilesForBackup();

      final dbNames = [
        '.saber_tags.db',
        '.saber_note_links.db',
        '.saber_tags.db-journal',
        '.saber_note_links.db-journal',
      ];
      for (final dbName in dbNames) {
        if (File(p.join(FileManager.documentsDirectory, dbName)).existsSync()) {
          sourceFilesList.add('__db__/$dbName');
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final prefsMap = <String, dynamic>{};
      for (final key in prefs.getKeys()) prefsMap[key] = prefs.get(key);

      final foldersList = <String>[];
      if (FileManager._shouldUseVault) {
        foldersList.addAll(
          await VaultAdapter.instance.getFoldersByPrefix(
            '/',
            ensureTrailingSlash: true,
          ),
        );
      } else {
        final dir = Directory(FileManager.documentsDirectory);
        if (dir.existsSync()) {
          await for (final entity in dir.list(recursive: true)) {
            if (entity is Directory) {
              final rel = p
                  .relative(entity.path, from: dir.path)
                  .replaceAll('\\', '/');
              if (rel.isNotEmpty && rel != '.') foldersList.add(rel);
            }
          }
        }
      }
      prefsMap['__folders__'] = foldersList;
      index['preferences'] = prefsMap;

      final Map<String, dynamic> oldIndexFiles = index['files'] ?? {};
      final Map<String, dynamic> newIndexFiles = {};

      await raf.setPosition(currentIndexOffset);
      int writePos = currentIndexOffset;
      int count = 0;
      int total = sourceFilesList.length;

      for (final path in sourceFilesList) {
        if (_isCancelled) {
          await raf.close();
          _log.info('Backup cancelled. Rollback successful.');
          return;
        }

        try {
          int modified = 0;
          int size = 0;
          Uint8List? data;

          if (path.startsWith('__db__/')) {
            final f = File(
              p.join(FileManager.documentsDirectory, path.substring(7)),
            );
            if (f.existsSync()) {
              modified = f.lastModifiedSync().millisecondsSinceEpoch;
              size = f.lengthSync();
            } else {
              continue;
            }
          } else if (FileManager._shouldUseVault) {
            modified =
                (await VaultAdapter.instance.getFileLastModified(
                  path,
                ))?.millisecondsSinceEpoch ??
                0;
            size = (await VaultAdapter.instance.getFileSize(path)) ?? 0;
          } else {
            final f = File(p.join(FileManager.documentsDirectory, path));
            if (f.existsSync()) {
              modified = f.lastModifiedSync().millisecondsSinceEpoch;
              size = f.lengthSync();
            } else {
              continue;
            }
          }

          bool needsUpdate = true;
          if (oldIndexFiles.containsKey(path)) {
            final oldData = oldIndexFiles[path];
            if (oldData['m'] >= modified && oldData['s'] == size) {
              needsUpdate = false;
              newIndexFiles[path] = oldData;
            }
          }

          if (needsUpdate) {
            if (path.startsWith('__db__/')) {
              data = await File(
                p.join(FileManager.documentsDirectory, path.substring(7)),
              ).readAsBytes();
            } else if (FileManager._shouldUseVault) {
              data = await VaultAdapter.instance.readFile(path);
            } else {
              data = await File(
                p.join(FileManager.documentsDirectory, path),
              ).readAsBytes();
            }

            if (data != null && data.isNotEmpty) {
              await Future.delayed(Duration.zero);
              final encrypted = await compute(_isolateEncryptBlock, {
                'data': data,
                'password': password,
              });
              await raf.writeFrom(encrypted);
              newIndexFiles[path] = {
                'o': writePos,
                'l': encrypted.length,
                'm': modified,
                's': size,
              };
              writePos += encrypted.length;
            }
          }
        } catch (e) {
          _log.warning('Skipped file during backup (likely deleted): $path');
        }

        count++;
        if (count % 10 == 0 || count == total) {
          status.value = BackupStatus(
            isRunning: true,
            progress: count / total,
            currentFile: path.startsWith('__db__/') ? 'Databases...' : path,
          );
          _updateNotification(count, total);
        }
      }

      if (_isCancelled) {
        await raf.close();
        return;
      }

      status.value = const BackupStatus(
        isRunning: true,
        progress: 0.99,
        currentFile: 'Finalizing...',
      );
      index['files'] = newIndexFiles;
      final indexEncrypted = await compute(_isolateEncryptIndex, {
        'index': index,
        'password': password,
      });

      final newIndexOffset = writePos;
      await raf.writeFrom(indexEncrypted);
      await raf.truncate(await raf.position());

      await raf.setPosition(8);
      final newOffsetData = ByteData(8)
        ..setInt64(0, newIndexOffset, Endian.little);
      await raf.writeFrom(newOffsetData.buffer.asUint8List());
      await raf.close();

      stows.lastBackupTimestamp.value = DateTime.now().millisecondsSinceEpoch;
    } catch (e) {
      if (e is PathAccessException) {
        throw Exception(
          'Permission Denied. Please pick a public folder like "Documents".',
        );
      }
      rethrow;
    } finally {
      status.value = const BackupStatus(isRunning: false);
      VaultAdapter.preventLock = false;
      await _cancelNotification();
    }
  }

  static Future<void> restoreIncrementalBackup(
    String targetPath,
    String password,
  ) async {
    final file = File(targetPath);
    if (!file.existsSync()) throw Exception('Backup file not found at path.');
    status.value = const BackupStatus(
      isRunning: true,
      progress: 0.0,
      currentFile: 'Extracting backup...',
    );
    VaultAdapter.preventLock = true;

    final tempDir = await Directory.systemTemp.createTemp('saber_inc_restore_');
    try {
      await TagDatabase.instance.close();
      await NoteLinksDatabase.instance.close();

      final prefsData = await compute(_isolateIncrementalRestoreTask, {
        'targetPath': targetPath,
        'password': password,
        'tempDirPath': tempDir.path,
      });

      status.value = const BackupStatus(
        isRunning: true,
        progress: 0.5,
        currentFile: 'Applying data...',
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      for (final entry in prefsData.entries) {
        if (entry.key == 'customDataDir' ||
            entry.key == 'backupFilePath' ||
            entry.key == '__folders__')
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

      if (FileManager._shouldUseVault) {
        final all = await VaultAdapter.instance.getAllFiles();
        for (var f in all) await VaultAdapter.instance.deleteFile(f);
      } else {
        final dir = Directory(FileManager.documentsDirectory);
        if (dir.existsSync()) await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }

      final foldersList = prefsData['__folders__'] as List<dynamic>? ?? [];
      for (final folder in foldersList) {
        if (FileManager._shouldUseVault) {
          await VaultAdapter.instance.createFolder(folder.toString());
        } else {
          Directory(
            p.join(FileManager.documentsDirectory, folder.toString()),
          ).createSync(recursive: true);
        }
      }

      final extractedFiles = await tempDir
          .list(recursive: true)
          .where((e) => e is File)
          .cast<File>()
          .toList();
      int total = extractedFiles.length;
      int count = 0;

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
        } else if (FileManager._shouldUseVault) {
          await VaultAdapter.instance.writeFile(
            relativePath,
            await extractedFile.readAsBytes(),
          );
        } else {
          final destFile = File(
            p.join(FileManager.documentsDirectory, relativePath),
          );
          await destFile.parent.create(recursive: true);
          await extractedFile.copy(destFile.path);
        }

        count++;
        if (count % 10 == 0 || count == total) {
          status.value = BackupStatus(
            isRunning: true,
            progress: 0.5 + ((count / total) * 0.5),
            currentFile: relativePath.startsWith('__db__/')
                ? 'Database...'
                : relativePath,
          );
        }
        if (count % 5 == 0) await Future.delayed(Duration.zero);
      }
      FileManager.documentsDirectory =
          await FileManager.getDocumentsDirectory();
    } finally {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
      status.value = const BackupStatus(isRunning: false);
      VaultAdapter.preventLock = false;
    }
  }

  static Future<void> _updateNotification(int current, int total) async {
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
      await _notificationsPlugin.show(
        888,
        t.backup.notificationTitle,
        '$current / $total assets synced',
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
