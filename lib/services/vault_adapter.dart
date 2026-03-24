// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/home_data_cache.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/services/sba_encryption.dart';
import 'package:saber/services/thumbnail_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

Future<bool> _isolateVaultBackupTask(Map<String, dynamic> args) async {
  final vaultPath = args['vaultPath'] as String;
  final configPath = args['configPath'] as String;
  final dataDirPath = args['dataDirPath'] as String;
  final destPath = args['destPath'] as String;
  final password = args['password'] as String;
  final prefsJson = args['prefsJson'] as List<int>;
  final docsDir = Directory(args['docsDir'] as String);

  final archive = Archive();

  final indexFile = File(vaultPath);
  archive.addFile(
    ArchiveFile(
      p.basename(vaultPath),
      indexFile.lengthSync(),
      indexFile.readAsBytesSync(),
    ),
  );

  final configFile = File(configPath);
  archive.addFile(
    ArchiveFile(
      p.basename(configPath),
      configFile.lengthSync(),
      configFile.readAsBytesSync(),
    ),
  );

  final dataDir = Directory(dataDirPath);
  if (dataDir.existsSync()) {
    final rootPath = Directory(dataDirPath).parent.path;
    final entities = dataDir.listSync(recursive: true);
    for (final entity in entities) {
      if (entity is File) {
        final relative = p.relative(entity.path, from: rootPath);
        archive.addFile(
          ArchiveFile(relative, entity.lengthSync(), entity.readAsBytesSync()),
        );
      }
    }
  }

  archive.addFile(
    ArchiveFile('_preferences.json', prefsJson.length, prefsJson),
  );

  if (docsDir.existsSync()) {
    final entities = docsDir.listSync(recursive: false);
    for (final entity in entities) {
      if (entity is File) {
        final name = p.basename(entity.path);
        if (name.startsWith('.saber_')) {
          archive.addFile(
            ArchiveFile(name, entity.lengthSync(), entity.readAsBytesSync()),
          );
        }
      }
    }
  }

  const manifest = {'type': 'vault', 'version': 2};
  final manifestJson = utf8.encode(jsonEncode(manifest));
  archive.addFile(
    ArchiveFile('_backup_manifest.json', manifestJson.length, manifestJson),
  );

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

Future<bool> _isolateVaultRestoreTask(Map<String, dynamic> args) async {
  final archivePath = args['archivePath'] as String;
  final password = args['password'] as String;
  final tempDirPath = args['tempDirPath'] as String;

  List<int> bytes = File(archivePath).readAsBytesSync();
  final byteList = Uint8List.fromList(bytes);

  if (SbaEncryption.isEncrypted(byteList)) {
    if (password.isEmpty) {
      throw StateError('Backup is encrypted but no password was provided.');
    }
    bytes = SbaEncryption.decrypt(byteList, password);
  }

  final archive = ZipDecoder().decodeBytes(bytes);

  final hasIndex = archive.files.any((f) => f.name == 'saber_index.db');
  final hasConfig = archive.files.any((f) => f.name == 'saber_index.db.config');
  final hasData = archive.files.any((f) => f.name.startsWith('data/'));

  if (!hasIndex || !hasConfig || !hasData) {
    throw StateError('Invalid backup: missing required vault files');
  }

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

String _deriveKeyHexFromArgs(Map<String, dynamic> args) {
  final password = args['password'] as String;
  final saltBase64 = args['saltBase64'] as String;
  final n = args['n'] as int;
  final r = args['r'] as int;
  final p = args['p'] as int;
  final salt = base64Decode(saltBase64);
  final passBytes = Uint8List.fromList(utf8.encode(password));
  try {
    final scrypt = pc.Scrypt()..init(pc.ScryptParameters(n, r, p, 32, salt));
    final derived = scrypt.process(passBytes);
    final hex = derived.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    for (var i = 0; i < derived.length; i++) {
      derived[i] = 0;
    }
    return hex;
  } finally {
    for (var i = 0; i < passBytes.length; i++) {
      passBytes[i] = 0;
    }
  }
}

void isolateSecureDeletePaths(List<String> paths) {
  if (paths.isEmpty) return;
  final random = Random.secure();
  const chunkSize = 64 * 1024;
  final buffer = Uint8List(chunkSize);
  for (var i = 0; i < chunkSize; i++) {
    buffer[i] = random.nextInt(256);
  }
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    try {
      final length = file.lengthSync();
      final raf = file.openSync(mode: FileMode.write);
      var written = 0;
      while (written < length) {
        final toWrite = (length - written) < chunkSize
            ? (length - written)
            : chunkSize;
        raf.writeFromSync(buffer, 0, toWrite);
        written += toWrite;
      }
      raf.flushSync();
      raf.closeSync();
      file.deleteSync();
    } catch (_) {
      try {
        file.deleteSync();
      } catch (_) {}
    }
  }
}

class _WritePayload {
  final String path;
  final TransferableTypedData data;
  _WritePayload(this.path, this.data);
}

class _ReadChunkPayload {
  final String storagePath;
  final String ivBase64;
  final Uint8List keyBytes;
  final int startOffset;
  final int endOffset;
  final bool isLastChunk;
  _ReadChunkPayload(
    this.storagePath,
    this.ivBase64,
    this.keyBytes,
    this.startOffset,
    this.endOffset,
    this.isLastChunk,
  );
}

class _DecryptChunkToFilePayload {
  final String storagePath;
  final String ivBase64;
  final Uint8List keyBytes;
  final String chunkOutputPath;
  final int startOffset;
  final int endOffset;
  final bool isLastChunk;
  _DecryptChunkToFilePayload(
    this.storagePath,
    this.ivBase64,
    this.keyBytes,
    this.chunkOutputPath,
    this.startOffset,
    this.endOffset,
    this.isLastChunk,
  );
}

class _MergeChunkFilesPayload {
  final List<String> chunkPaths;
  final String finalTempPath;
  _MergeChunkFilesPayload(this.chunkPaths, this.finalTempPath);
}

class _BulkWritePayload {
  final List<_WritePayload> items;
  final Uint8List keyBytes;
  final String storageRootPath;
  _BulkWritePayload(this.items, this.keyBytes, this.storageRootPath);
}

class _EncryptFileFromPathPayload {
  final String sourcePath;
  final String storageRootPath;
  final Uint8List keyBytes;
  final String virtualPath;
  _EncryptFileFromPathPayload(
    this.sourcePath,
    this.storageRootPath,
    this.keyBytes,
    this.virtualPath,
  );
}

class _WriteResult {
  final String virtualPath;
  final String storageId;
  final String ivBase64;
  final int size;
  _WriteResult(this.virtualPath, this.storageId, this.ivBase64, this.size);
}

class _VaultFileMeta {
  final String storageId;
  final String ivBase64;

  const _VaultFileMeta({required this.storageId, required this.ivBase64});
}

class VaultAdapter {
  VaultAdapter._();
  static final VaultAdapter instance = VaultAdapter._();

  static final log = Logger('VaultAdapter');
  static const _defaultScryptN = 16384;
  static const _defaultScryptR = 8;
  static const _defaultScryptP = 1;
  static const _totalFileCountConfigKey = 'total_file_count';
  static const _countsVersionConfigKey = 'counts_version';
  static const _countsVersionValue = '3';

  enc.Encrypter? _fileEncrypter;
  Uint8List? _masterKeyBytes;

  Database? _db;
  bool _isUnlocked = false;
  String? _vaultPath;
  Directory? _storageRoot;

  final LinkedHashMap<String, Uint8List> _readCache = LinkedHashMap();
  int _readCacheBytes = 0;
  static const _maxReadCacheEntries = 96;
  static const _maxReadCacheBytes = 128 * 1024 * 1024;

  final LinkedHashMap<String, _VaultFileMeta> _metaCache = LinkedHashMap();
  static const _maxMetaCacheEntries = 4096;

  final Map<String, int> _folderCountCache = {};

  final List<Map<String, dynamic>> _pendingDbUpdates = [];
  final Set<String> _pendingPathsToCheck = {};
  Timer? _dbCommitTimer;
  static const _dbCommitDebounce = Duration(seconds: 2);
  bool _isFlushing = false;

  static bool get isUnlocked => instance._isUnlocked;
  static final unlockState = ValueNotifier(false);
  static ValueListenable<bool> get unlockListenable => unlockState;
  static bool preventLock = false;

  String get vaultPath {
    if (_vaultPath != null) return _vaultPath!;
    try {
      return p.join(
        FileManager.documentsDirectory,
        'saber_vault',
        'saber_index.db',
      );
    } catch (e) {
      log.severe('[VaultAdapter] documentsDirectory unavailable');
      return '';
    }
  }

  Future<bool> unlock(String path, String password) async {
    try {
      _setupPaths(path);

      final indexFile = File(_vaultPath!);
      if (!indexFile.existsSync()) {
        log.warning('Vault index not found at $_vaultPath');
        return false;
      }

      final config = await _readVaultConfig(_vaultPath!);
      final kdfIter = config['kdf_iter'] as int? ?? 256000;
      final pageSize = config['cipher_page_size'] as int? ?? 4096;
      final saltBase64 = config['salt'] as String?;
      final scryptN = config['scrypt_n'] as int? ?? _defaultScryptN;
      final scryptR = config['scrypt_r'] as int? ?? _defaultScryptR;
      final scryptP = config['scrypt_p'] as int? ?? _defaultScryptP;

      if (saltBase64 == null) {
        log.severe('Missing salt in vault config. Cannot unlock.');
        return false;
      }

      final salt = base64Decode(saltBase64);
      final keyHexRaw = await _deriveKeyHexAsync(
        password,
        salt,
        n: scryptN,
        r: scryptR,
        p: scryptP,
      );

      final keyHex = "x'$keyHexRaw'";

      log.info(
        '[VaultAdapter] Unlocking Index: KDF=$kdfIter, Page=$pageSize, '
        'Scrypt(N=$scryptN, r=$scryptR, p=$scryptP)',
      );

      _db = await openDatabase(
        _vaultPath!,
        password: keyHex,
        version: 1,
        singleInstance: false,
        onConfigure: (db) async {
          await db.execute('PRAGMA cipher_page_size = $pageSize');
          await db.execute('PRAGMA kdf_iter = $kdfIter');
          await db.execute('PRAGMA cipher_default_use_hmac = ON');

          await db.rawQuery('PRAGMA journal_mode = WAL');

          await db.rawQuery('PRAGMA synchronous = NORMAL');

          await db.rawQuery('PRAGMA wal_autocheckpoint = 1000');
        },
      );

      await _ensureSchema();

      await _db!.rawQuery('SELECT count(*) FROM sqlite_master');

      // Init Security Pragmas. secure_delete: user pref (ON = overwrite index pages with zeros; file blobs wiped in isolate via isolateSecureDeletePaths).
      try {
        await _db!.execute('PRAGMA cipher_memory_security = ON');
        final secureDelete = stows.vaultSecureDelete.value;
        await _db!.execute(
          'PRAGMA secure_delete = ${secureDelete ? 'ON' : 'OFF'}',
        );
      } catch (_) {}

      await _initFileEncryption();

      _isUnlocked = true;
      unlockState.value = true;
      log.info('Vault unlocked successfully. FBA Ready.');
      return true;
    } catch (e) {
      log.severe('Failed to unlock vault: $e');
      await _close();
      return false;
    }
  }

  Future<bool> create(
    String path,
    String password, {
    int kdfIter = 256000,
    int pageSize = 4096,
    int scryptN = _defaultScryptN,
    int scryptR = _defaultScryptR,
    int scryptP = _defaultScryptP,
  }) async {
    try {
      _setupPaths(path);

      if (_storageRoot!.existsSync()) {
        _storageRoot!.deleteSync(recursive: true);
      }
      _storageRoot!.createSync(recursive: true);

      final dataDir = Directory(p.join(_storageRoot!.path, 'data'));
      dataDir.createSync();

      log.info('[VaultAdapter] Creating vault at $_vaultPath');

      final salt = enc.Key.fromSecureRandom(32).bytes;
      final keyHexRaw = await _deriveKeyHexAsync(
        password,
        salt,
        n: scryptN,
        r: scryptR,
        p: scryptP,
      );
      final keyHex = "x'$keyHexRaw'";

      await _writeVaultConfig(
        _vaultPath!,
        kdfIter,
        pageSize,
        base64Encode(salt),
        scryptN: scryptN,
        scryptR: scryptR,
        scryptP: scryptP,
      );

      final db = await openDatabase(
        _vaultPath!,
        password: keyHex,
        version: 1,
        singleInstance: false,
        onConfigure: (db) async {
          await db.execute('PRAGMA cipher_page_size = $pageSize');
          await db.execute('PRAGMA kdf_iter = $kdfIter');
          await db.execute('PRAGMA cipher_default_use_hmac = ON');
          await db.rawQuery('PRAGMA journal_mode = WAL');
          await db.rawQuery('PRAGMA synchronous = NORMAL');
        },
        onCreate: (db, version) async {
          await db.execute('PRAGMA encoding = "UTF-8"');
          await _createTables(db);

          final masterKey = enc.Key.fromSecureRandom(32).base64;
          await db.insert('config', {
            'key': 'file_master_key',
            'value': masterKey,
          });
          await db.insert('config', {
            'key': _totalFileCountConfigKey,
            'value': '0',
          });
          await db.insert('config', {
            'key': _countsVersionConfigKey,
            'value': _countsVersionValue,
          });
        },
      );
      await db.close();

      return await unlock(path, password);
    } catch (e) {
      log.severe('Failed to create vault: $e');
      await _close();
      return false;
    }
  }

  Future<void> _initFileEncryption() async {
    final result = await _db!.query(
      'config',
      where: 'key = ?',
      whereArgs: ['file_master_key'],
    );
    String keyBase64;

    if (result.isEmpty) {

      log.warning('No file_master_key found. Generating new one.');
      keyBase64 = enc.Key.fromSecureRandom(32).base64;
      await _db!.insert('config', {
        'key': 'file_master_key',
        'value': keyBase64,
      });
    } else {
      keyBase64 = result.first['value'] as String;
    }

    final key = enc.Key.fromBase64(keyBase64);
    _masterKeyBytes = key.bytes;

    _fileEncrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
  }

  Uint8List? _getCachedRead(String normPath) {
    final cached = _readCache.remove(normPath);
    if (cached == null) return null;

    _readCache[normPath] = cached;
    return Uint8List.fromList(cached);
  }

  void _putCachedRead(String normPath, Uint8List data) {

    if (data.length > (_maxReadCacheBytes ~/ 2)) return;

    final existing = _readCache.remove(normPath);
    if (existing != null) {
      _readCacheBytes -= existing.length;
    }

    final stored = data;
    _readCache[normPath] = stored;
    _readCacheBytes += stored.length;

    while (_readCache.length > _maxReadCacheEntries ||
        _readCacheBytes > _maxReadCacheBytes) {
      final oldestKey = _readCache.keys.first;
      final oldest = _readCache.remove(oldestKey);
      if (oldest != null) {
        _readCacheBytes -= oldest.length;
      }
    }
  }

  void _invalidateCachedRead(String normPath) {
    final removed = _readCache.remove(normPath);
    if (removed != null) _readCacheBytes -= removed.length;
  }

  void _invalidateCachedReadsByPrefix(String prefix) {
    final toRemove = _readCache.keys
        .where((k) => k.startsWith(prefix))
        .toList();
    for (final key in toRemove) {
      _invalidateCachedRead(key);
    }
  }

  void invalidateCachedReadForPath(String path) {
    _invalidateCachedRead(_normalizePath(path));
  }

  void _clearReadCache() {
    for (final bytes in _readCache.values) {
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = 0;
      }
    }
    _readCache.clear();
    _readCacheBytes = 0;
  }

  _VaultFileMeta? _getCachedMeta(String normPath) {
    final cached = _metaCache.remove(normPath);
    if (cached == null) return null;
    _metaCache[normPath] = cached;
    return cached;
  }

  void _putCachedMeta(String normPath, _VaultFileMeta meta) {
    _metaCache.remove(normPath);
    _metaCache[normPath] = meta;
    while (_metaCache.length > _maxMetaCacheEntries) {
      _metaCache.remove(_metaCache.keys.first);
    }
  }

  void _invalidateCachedMeta(String normPath) {
    _metaCache.remove(normPath);
  }

  void _invalidateCachedMetaByPrefix(String prefix) {
    final toRemove = _metaCache.keys
        .where((k) => k.startsWith(prefix))
        .toList();
    for (final key in toRemove) {
      _metaCache.remove(key);
    }
  }

  void _clearMetaCache() {
    _metaCache.clear();
  }

  int? _getCachedFolderCount(String normPath) => _folderCountCache[normPath];
  void _putCachedFolderCount(String normPath, int count) {
    _folderCountCache[normPath] = count;
  }

  void _invalidateAllFolderCounts() {
    _folderCountCache.clear();
  }

  Map<String, dynamic>? _findPendingUpdate(String path) {
    for (var i = _pendingDbUpdates.length - 1; i >= 0; i--) {
      if (_pendingDbUpdates[i]['path'] == path) return _pendingDbUpdates[i];
    }
    return null;
  }

  void _logPerf(String op, Stopwatch sw, {String? extra}) {
    final msg =
        '[PERF][VaultAdapter.$op] ${sw.elapsedMilliseconds}ms'
        '${extra == null ? '' : ' $extra'}';
    if (sw.elapsedMilliseconds >= 120) {
      log.info(msg);
    } else {
      log.fine(msg);
    }
  }

  Future<Uint8List?> readFile(
    String filePath, {
    void Function(double)? onProgress,
  }) async {
    if (!_isUnlocked ||
        _db == null ||
        _fileEncrypter == null ||
        _masterKeyBytes == null) {
      return null;
    }

    final sw = Stopwatch()..start();
    try {
      final normPath = _normalizePath(filePath);

      final cached = _getCachedRead(normPath);
      if (cached != null) {
        _logPerf('readFile', sw, extra: '(cache hit, ${cached.length} bytes)');
        return cached;
      }

      final cachedMeta = _getCachedMeta(normPath);
      String storageId;
      String ivBase64;
      if (cachedMeta != null) {
        storageId = cachedMeta.storageId;
        ivBase64 = cachedMeta.ivBase64;
      } else {
        final pending = _findPendingUpdate(normPath);
        if (pending != null) {
          storageId = pending['storage_id'] as String;
          ivBase64 = pending['iv'] as String;
          _putCachedMeta(
            normPath,
            _VaultFileMeta(storageId: storageId, ivBase64: ivBase64),
          );
        } else {
          final result = await _db!.query(
            'files',
            columns: ['storage_id', 'iv'],
            where: 'path = ?',
            whereArgs: [normPath],
            limit: 1,
          );
          if (result.isEmpty) return null;

          final row = result.first;
          storageId = row['storage_id'] as String;
          ivBase64 = row['iv'] as String;
          _putCachedMeta(
            normPath,
            _VaultFileMeta(storageId: storageId, ivBase64: ivBase64),
          );
        }
      }

      final physicalFile = _getPhysicalFile(storageId);
      if (!physicalFile.existsSync()) {
        log.severe(
          'Data corruption: File indexed but missing on disk: $storageId',
        );
        return null;
      }

      const int largeFileThreshold = 100 * 1024 * 1024;
      final fileSize = physicalFile.lengthSync();
      if (fileSize > largeFileThreshold) {
        log.info(
          'Read skipped (file too large for memory, use readFileToTempFile): $normPath',
        );
        return null;
      }

      final numWorkers = Platform.numberOfProcessors.clamp(1, 8);
      int workerChunkSize = (fileSize / numWorkers).ceil();
      workerChunkSize =
          ((workerChunkSize + 15) ~/ 16) * 16;

      final futures = <Future<TransferableTypedData>>[];
      for (int i = 0; i < numWorkers; i++) {
        final startOffset = i * workerChunkSize;
        if (startOffset >= fileSize) break;
        final endOffset = min(startOffset + workerChunkSize, fileSize);
        final isLast = endOffset == fileSize;

        futures.add(
          compute(
            _isolateReadChunk,
            _ReadChunkPayload(
              physicalFile.path,
              ivBase64,
              _masterKeyBytes!,
              startOffset,
              endOffset,
              isLast,
            ),
          ),
        );
      }

      final numChunks = futures.length;
      var completed = 0;
      final wrappedFutures = futures
          .map(
            (f) => f.then((data) {
              completed++;
              onProgress?.call(completed / numChunks);
              return data;
            }),
          )
          .toList();
      final chunks = await Future.wait(wrappedFutures);
      final builder = BytesBuilder(copy: false);
      for (final chunk in chunks) {
        builder.add(chunk.materialize().asUint8List());
      }
      Uint8List decrypted = builder.toBytes();

      if (normPath.endsWith('.sbn2')) {
        try {
          final decompressed = const ZLibDecoder().decodeBytes(decrypted);
          decrypted = Uint8List.fromList(decompressed);
        } catch (e) {

        }
      }

      _putCachedRead(normPath, decrypted);
      _logPerf('readFile', sw, extra: '(${decrypted.length} bytes)');
      return decrypted;
    } catch (e, s) {
      log.severe('Read error: $filePath', e, s);
      return null;
    }
  }

  Future<String?> readFileToTempFile(
    String filePath, {
    void Function(double)? onProgress,
  }) async {
    if (!_isUnlocked || _db == null || _masterKeyBytes == null) return null;

    try {
      final normPath = _normalizePath(filePath);
      final cachedMeta = _getCachedMeta(normPath);
      String storageId;
      String ivBase64;
      if (cachedMeta != null) {
        storageId = cachedMeta.storageId;
        ivBase64 = cachedMeta.ivBase64;
        final sz = await getFileSize(normPath);
        if (sz == null || sz <= 0) return null;
      } else {
        final pending = _findPendingUpdate(normPath);
        if (pending != null) {
          storageId = pending['storage_id'] as String;
          ivBase64 = pending['iv'] as String;
          final sz = pending['size'] as int?;
          if (sz == null || sz <= 0) return null;
        } else {
          final result = await _db!.query(
            'files',
            columns: ['storage_id', 'iv', 'size'],
            where: 'path = ?',
            whereArgs: [normPath],
            limit: 1,
          );
          if (result.isEmpty) return null;
          final row = result.first;
          storageId = row['storage_id'] as String;
          ivBase64 = row['iv'] as String;
          final sz = row['size'] as int?;
          if (sz == null || sz <= 0) return null;
        }
      }

      final physicalFile = _getPhysicalFile(storageId);
      if (!physicalFile.existsSync()) return null;

      final tempDir = await getTemporaryDirectory();
      final finalTempPath = p.join(
        tempDir.path,
        'vault_${const Uuid().v4()}.tmp',
      );

      final fileSize = physicalFile.lengthSync();
      final numWorkers = Platform.numberOfProcessors.clamp(2, 8);
      int workerChunkSize = (fileSize / numWorkers).ceil();
      workerChunkSize = ((workerChunkSize + 15) ~/ 16) * 16;

      final futures = <Future<String>>[];
      for (int i = 0; i < numWorkers; i++) {
        final startOffset = i * workerChunkSize;
        if (startOffset >= fileSize) break;
        final endOffset = min(startOffset + workerChunkSize, fileSize);
        final isLast = endOffset == fileSize;

        final chunkTempPath = p.join(
          tempDir.path,
          'vault_chunk_${const Uuid().v4()}.tmp',
        );
        futures.add(
          compute(
            _isolateDecryptChunkToFile,
            _DecryptChunkToFilePayload(
              physicalFile.path,
              ivBase64,
              _masterKeyBytes!,
              chunkTempPath,
              startOffset,
              endOffset,
              isLast,
            ),
          ),
        );
      }

      final numChunks = futures.length;
      var completed = 0;
      final wrappedFutures = futures
          .map(
            (f) => f.then((path) {
              completed++;
              onProgress?.call(completed / numChunks);
              return path;
            }),
          )
          .toList();
      final chunkPaths = await Future.wait(wrappedFutures);

      return await compute(
        _isolateMergeChunkFiles,
        _MergeChunkFilesPayload(chunkPaths, finalTempPath),
      );
    } catch (e, s) {
      log.severe('readFileToTempFile error: $filePath', e, s);
      return null;
    }
  }

  Future<bool> writeFile(
    String filePath,
    Uint8List data, {
    DateTime? lastModified,
    bool awaitDbCommit = false,
  }) async {
    try {
      await writeFilesBulk({filePath: data}, awaitDbCommit: awaitDbCommit);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> writeFileFromPath(
    String sourcePath,
    String virtualPath, {
    bool awaitDbCommit = false,
  }) async {
    if (!_isUnlocked || _db == null || _masterKeyBytes == null) return;
    final normPath = _normalizePath(virtualPath);
    if (normPath.contains('saber_vault') ||
        normPath.split('/').last.startsWith('.saber_')) {
      return;
    }
    final sw = Stopwatch()..start();
    _WriteResult result;
    try {
      result = await compute(
        _isolateEncryptFileFromPath,
        _EncryptFileFromPathPayload(
          sourcePath,
          _storageRoot!.path,
          _masterKeyBytes!,
          normPath,
        ),
      );
    } catch (e, s) {
      log.severe('writeFileFromPath isolate error', e, s);
      rethrow;
    }
    _logPerf('writeFileFromPath.isolate', sw, extra: '(size=${result.size})');

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _putCachedMeta(
      result.virtualPath,
      _VaultFileMeta(storageId: result.storageId, ivBase64: result.ivBase64),
    );
    _pendingDbUpdates.add({
      'path': result.virtualPath,
      'storage_id': result.storageId,
      'iv': result.ivBase64,
      'last_modified': timestamp,
      'size': result.size,
    });
    _pendingPathsToCheck.add(result.virtualPath);

    if (awaitDbCommit) {
      await _flushPendingDbUpdates();
    } else {
      _dbCommitTimer?.cancel();
      _dbCommitTimer = Timer(_dbCommitDebounce, () {
        unawaited(_flushPendingDbUpdates());
      });
    }
  }

  Future<void> writeFilesBulk(
    Map<String, Uint8List> filesData, {
    bool awaitDbCommit = false,
  }) async {
    if (!_isUnlocked || _db == null || _masterKeyBytes == null) return;
    if (filesData.isEmpty) return;

    final safeFiles = <String, Uint8List>{};
    for (final entry in filesData.entries) {
      final normPath = _normalizePath(entry.key);
      if (normPath.contains('saber_vault') ||
          normPath.split('/').last.startsWith('.saber_')) {
        continue;
      }
      safeFiles[normPath] = entry.value;
    }
    if (safeFiles.isEmpty) return;

    final swTotal = Stopwatch()..start();

    final payloadItems = safeFiles.entries.map((e) {
      return _WritePayload(e.key, TransferableTypedData.fromList([e.value]));
    }).toList();

    final swIsolate = Stopwatch()..start();
    List<_WriteResult> results;
    try {
      results = await compute(
        _isolateEncryptAndWrite,
        _BulkWritePayload(payloadItems, _masterKeyBytes!, _storageRoot!.path),
      );
    } catch (e, s) {
      log.severe('Bulk write isolate error', e, s);
      rethrow;
    }
    _logPerf(
      'writeFilesBulk.isolateEncryptWrite',
      swIsolate,
      extra: '(files=${results.length})',
    );

    final timestamp = DateTime.now().millisecondsSinceEpoch;

    for (final entry in filesData.entries) {
      _putCachedRead(_normalizePath(entry.key), entry.value);
    }
    for (final res in results) {
      _putCachedMeta(
        res.virtualPath,
        _VaultFileMeta(storageId: res.storageId, ivBase64: res.ivBase64),
      );
      _pendingDbUpdates.add({
        'path': res.virtualPath,
        'storage_id': res.storageId,
        'iv': res.ivBase64,
        'last_modified': timestamp,
        'size': res.size,
      });
      _pendingPathsToCheck.add(res.virtualPath);
    }

    if (awaitDbCommit) {
      await _flushPendingDbUpdates();
      _logPerf(
        'writeFilesBulk.total',
        swTotal,
        extra: '(files=${results.length}, awaited)',
      );
    } else {
      _dbCommitTimer?.cancel();
      _dbCommitTimer = Timer(_dbCommitDebounce, () {
        unawaited(_flushPendingDbUpdates());
      });
      _logPerf(
        'writeFilesBulk.total',
        swTotal,
        extra: '(files=${results.length}, queued)',
      );
    }
  }

  Future<void> _flushPendingDbUpdates() async {
    if (_pendingDbUpdates.isEmpty || _db == null || _isFlushing) return;
    _isFlushing = true;

    final updates = List<Map<String, dynamic>>.from(_pendingDbUpdates);
    _pendingDbUpdates.clear();
    _pendingPathsToCheck.clear();
    _dbCommitTimer?.cancel();

    final cleanupIds = <String>[];
    final sw = Stopwatch()..start();
    const int batchSize =
        15;

    try {
      for (var i = 0; i < updates.length; i += batchSize) {
        if (i > 0) {
          await Future.delayed(
            const Duration(milliseconds: 16),
          );
        }

        final end = min(i + batchSize, updates.length);
        final batchUpdates = updates.sublist(i, end);
        final batchPaths = batchUpdates
            .map((u) => u['path'] as String)
            .toList();

        final existingFiles = <String, Map<String, dynamic>>{};
        if (batchPaths.isNotEmpty) {
          final placeholders = List.filled(batchPaths.length, '?').join(',');
          final rows = await _db!.rawQuery(
            'SELECT path, storage_id, size FROM files WHERE path IN ($placeholders)',
            batchPaths,
          );
          for (final row in rows) {
            existingFiles[row['path'] as String] = row;
          }
        }

        final folderCountDeltas = <String, int>{};
        final folderSizeDeltas = <String, int>{};
        var totalCountDelta = 0;
        final timestamp = batchUpdates.isNotEmpty
            ? batchUpdates.first['last_modified'] as int
            : 0;

        for (final update in batchUpdates) {
          final path = update['path'] as String;
          final newSize = update['size'] as int? ?? 0;

          if (existingFiles.containsKey(path)) {
            cleanupIds.add(existingFiles[path]!['storage_id'] as String);

            if (FileManager.isCountableFile(path)) {
              final oldSize = existingFiles[path]!['size'] as int? ?? 0;
              final sizeDelta = newSize - oldSize;
              if (sizeDelta != 0) {
                for (final folderPath in _getAncestorFolders(path)) {
                  final key = _normalizeFolderPath(folderPath);
                  folderSizeDeltas[key] =
                      (folderSizeDeltas[key] ?? 0) + sizeDelta;
                }
              }
            }
          } else if (FileManager.isCountableFile(path)) {
            totalCountDelta += 1;
            for (final folderPath in _getAncestorFolders(path)) {
              final key = _normalizeFolderPath(folderPath);
              folderCountDeltas[key] = (folderCountDeltas[key] ?? 0) + 1;
              folderSizeDeltas[key] = (folderSizeDeltas[key] ?? 0) + newSize;
              if (_folderCountCache.containsKey(key)) {
                _folderCountCache[key] = (_folderCountCache[key] ?? 0) + 1;
              }
            }
          }
        }

        final rootFolderPathsToSkip = <String>{};
        final allFolderKeys = {
          ...folderCountDeltas.keys,
          ...folderSizeDeltas.keys,
        };
        if (allFolderKeys.isNotEmpty) {
          for (final folderPath in allFolderKeys) {
            if (!_isRootLevelFolder(folderPath)) continue;
            final segment = folderPath.replaceAll(RegExp(r'^/|/$'), '');
            final existing = await _db!.rawQuery(
              'SELECT path FROM folders WHERE path LIKE ? AND path != ? LIMIT 1',
              ['%/$segment/', folderPath],
            );
            if (existing.isNotEmpty) {
              rootFolderPathsToSkip.add(folderPath);
            }
          }
        }

        await _db!.transaction((txn) async {
          final batch = txn.batch();
          for (final update in batchUpdates) {
            batch.insert(
              'files',
              update,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          if (allFolderKeys.isNotEmpty) {
            for (final folderPath in allFolderKeys) {
              if (_hasConsecutiveDuplicateSegment(folderPath)) continue;
              if (_isRootLevelFolder(folderPath) &&
                  rootFolderPathsToSkip.contains(folderPath)) {
                continue;
              }
              batch.insert('folders', {
                'path': folderPath,
                'last_modified': timestamp,
                'created_at': timestamp,
                'file_count': 0,
                'total_size': 0,
              }, conflictAlgorithm: ConflictAlgorithm.ignore);
            }
            for (final folderPath in allFolderKeys) {
              final cDelta = folderCountDeltas[folderPath] ?? 0;
              final sDelta = folderSizeDeltas[folderPath] ?? 0;
              if (cDelta != 0 || sDelta != 0) {
                batch.rawUpdate(
                  'UPDATE folders SET file_count = MAX(0, file_count + ?), total_size = MAX(0, total_size + ?) WHERE path = ?',
                  [cDelta, sDelta, folderPath],
                );
              }
            }
          }
          if (totalCountDelta != 0) {
            await _incrementTotalFileCount(txn, totalCountDelta);
          }
          await batch.commit(noResult: true);
        });
      }

      _logPerf(
        'flushDbUpdates',
        sw,
        extra:
            '(chunks=${(updates.length / batchSize).ceil()}, files=${updates.length})',
      );
      _cleanupOldFilesBackground(cleanupIds);
    } catch (e, s) {
      log.severe('Flush DB error', e, s);
      for (final update in updates) {
        try {
          final id = update['storage_id'] as String?;
          if (id != null) _getPhysicalFile(id).deleteSync();
        } catch (_) {}
      }
    } finally {
      _isFlushing = false;
      if (_pendingDbUpdates.isNotEmpty) {
        _dbCommitTimer?.cancel();
        _dbCommitTimer = Timer(_dbCommitDebounce, () {
          unawaited(_flushPendingDbUpdates());
        });
      }
    }
  }

  static _WriteResult _isolateEncryptFileFromPath(
    _EncryptFileFromPathPayload args,
  ) {
    const int chunkSize =
        1024 * 1024;
    const int blockSize = 16;
    const uuid = Uuid();
    final storageId = uuid.v4();
    final ivBytes = Uint8List(blockSize);
    final random = Random.secure();
    for (var i = 0; i < blockSize; i++) ivBytes[i] = random.nextInt(256);
    final initialIvBase64 = base64Encode(ivBytes);

    final dataDir = Directory(p.join(args.storageRootPath, 'data'));
    if (!dataDir.existsSync()) dataDir.createSync(recursive: true);
    final prefix = storageId.substring(0, 2);
    final fileDir = Directory(p.join(dataDir.path, prefix));
    if (!fileDir.existsSync()) fileDir.createSync();
    final outPath = p.join(fileDir.path, '$storageId.enc');
    final source = File(args.sourcePath);
    if (!source.existsSync()) {
      throw FileSystemException('Source file not found', args.sourcePath);
    }
    final length = source.lengthSync();
    final raf = source.openSync(mode: FileMode.read);
    final waf = File(outPath).openSync(mode: FileMode.write);

    Uint8List cbcIv = Uint8List.fromList(ivBytes);
    int totalWritten = 0;
    try {
      int offset = 0;
      while (offset < length) {
        final toRead = (offset + chunkSize <= length)
            ? chunkSize
            : (length - offset);
        if (toRead <= 0) break;
        final chunk = raf.readSync(toRead);
        if (chunk.isEmpty) break;
        Uint8List plain = Uint8List.fromList(chunk);
        final isLastChunk = (offset + chunk.length >= length);
        if (!isLastChunk) {
          if (plain.length % blockSize != 0) {
            throw StateError(
              'Chunked encrypt: non-final chunk must be multiple of $blockSize',
            );
          }
          _processCbcBlocks(true, args.keyBytes, cbcIv, plain, waf, cbcIv);
        } else {

          final padLen = blockSize - (plain.length % blockSize);
          if (padLen != blockSize) {
            final padded = Uint8List(plain.length + padLen);
            padded.setRange(0, plain.length, plain);
            for (var i = 0; i < padLen; i++) {
              padded[plain.length + i] = padLen;
            }
            plain = padded;
          } else {
            final padded = Uint8List(plain.length + blockSize);
            padded.setRange(0, plain.length, plain);
            for (var i = 0; i < blockSize; i++) {
              padded[plain.length + i] = blockSize;
            }
            plain = padded;
          }
          _processCbcBlocks(true, args.keyBytes, cbcIv, plain, waf, cbcIv);
        }
        totalWritten += chunk.length;
        offset += chunk.length;
      }
    } finally {
      raf.closeSync();
      waf.closeSync();
    }
    return _WriteResult(
      args.virtualPath,
      storageId,
      initialIvBase64,
      totalWritten,
    );
  }

  static void _processCbcBlocks(
    bool encrypt,
    Uint8List keyBytes,
    Uint8List iv,
    Uint8List plain,
    RandomAccessFile waf,
    Uint8List nextIv,
  ) {
    final cipher = pc.CBCBlockCipher(pc.AESEngine())
      ..init(encrypt, pc.ParametersWithIV(pc.KeyParameter(keyBytes), iv));
    const blockSize = 16;

    final outBuffer = Uint8List(plain.length);
    for (var off = 0; off < plain.length; off += blockSize) {
      cipher.processBlock(plain, off, outBuffer, off);
    }
    waf.writeFromSync(outBuffer);

    if (plain.length >= blockSize) {
      if (encrypt) {
        nextIv.setAll(0, outBuffer.sublist(outBuffer.length - blockSize));
      } else {
        nextIv.setAll(0, plain.sublist(plain.length - blockSize));
      }
    }
  }

  static List<_WriteResult> _isolateEncryptAndWrite(_BulkWritePayload args) {
    final key = enc.Key(args.keyBytes);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    const uuid = Uuid();
    final results = <_WriteResult>[];
    final dataDir = Directory(p.join(args.storageRootPath, 'data'));
    if (!dataDir.existsSync()) dataDir.createSync(recursive: true);

    for (final item in args.items) {
      final material = item.data.materialize();

      final data = Uint8List.view(material, 0, material.lengthInBytes);
      final iv = enc.IV.fromSecureRandom(16);
      final encrypted = encrypter.encryptBytes(data, iv: iv);
      final storageId = uuid.v4();
      final prefix = storageId.substring(0, 2);
      final fileDir = Directory(p.join(dataDir.path, prefix));
      if (!fileDir.existsSync()) fileDir.createSync();
      final file = File(p.join(fileDir.path, '$storageId.enc'));
      file.writeAsBytesSync(encrypted.bytes, flush: false);
      results.add(_WriteResult(item.path, storageId, iv.base64, data.length));
    }
    return results;
  }

  void _cleanupOldFilesBackground(List<String> storageIds) {
    if (storageIds.isEmpty) return;
    final paths = storageIds
        .map((id) => _getPhysicalFile(id).path)
        .where((path) => File(path).existsSync())
        .toList();
    if (paths.isEmpty) return;
    unawaited(compute(isolateSecureDeletePaths, paths));
  }

  static TransferableTypedData _isolateReadChunk(_ReadChunkPayload args) {
    final file = File(args.storagePath);
    final raf = file.openSync(mode: FileMode.read);
    Uint8List iv;
    if (args.startOffset == 0) {
      iv = base64Decode(args.ivBase64);
      raf.setPositionSync(0);
    } else {
      raf.setPositionSync(args.startOffset - 16);
      iv = raf.readSync(16);
    }

    final cipher = pc.CBCBlockCipher(pc.AESEngine())
      ..init(false, pc.ParametersWithIV(pc.KeyParameter(args.keyBytes), iv));

    final length = args.endOffset - args.startOffset;
    final chunk = raf.readSync(length);
    raf.closeSync();

    final plain = Uint8List(chunk.length);
    for (var off = 0; off < chunk.length; off += 16) {
      cipher.processBlock(chunk, off, plain, off);
    }

    if (args.isLastChunk) {
      final padLength = plain.isNotEmpty ? plain.last : 0;
      if (padLength > 0 && padLength <= 16) {
        return TransferableTypedData.fromList([
          Uint8List.sublistView(plain, 0, plain.length - padLength),
        ]);
      }
    }
    return TransferableTypedData.fromList([plain]);
  }

  static String _isolateDecryptChunkToFile(_DecryptChunkToFilePayload args) {
    final file = File(args.storagePath);
    final raf = file.openSync(mode: FileMode.read);
    Uint8List iv;
    if (args.startOffset == 0) {
      iv = base64Decode(args.ivBase64);
      raf.setPositionSync(0);
    } else {
      raf.setPositionSync(args.startOffset - 16);
      iv = raf.readSync(16);
    }

    final cipher = pc.CBCBlockCipher(pc.AESEngine())
      ..init(false, pc.ParametersWithIV(pc.KeyParameter(args.keyBytes), iv));

    final out = File(args.chunkOutputPath);
    final waf = out.openSync(mode: FileMode.write);

    const chunkSize = 4 * 1024 * 1024;
    int remaining = args.endOffset - args.startOffset;
    final buf = Uint8List(chunkSize);
    final plainBuf = Uint8List(chunkSize);

    while (remaining > 0) {
      final toRead = remaining > chunkSize ? chunkSize : remaining;
      final n = raf.readIntoSync(Uint8List.sublistView(buf, 0, toRead));
      if (n == 0) break;

      for (var off = 0; off < n; off += 16) {
        cipher.processBlock(buf, off, plainBuf, off);
      }

      int toWrite = n;
      if (args.isLastChunk && remaining <= n) {
        final padLength = plainBuf[n - 1];
        if (padLength > 0 && padLength <= 16) {
          toWrite = n - padLength;
        }
      }
      if (toWrite > 0) {
        waf.writeFromSync(plainBuf, 0, toWrite);
      }
      remaining -= n;
    }
    raf.closeSync();
    waf.closeSync();
    return args.chunkOutputPath;
  }

  static String _isolateMergeChunkFiles(_MergeChunkFilesPayload args) {
    const bufSize = 4 * 1024 * 1024;
    final buf = Uint8List(bufSize);
    final out = File(args.finalTempPath);
    final waf = out.openSync(mode: FileMode.write);
    for (final cp in args.chunkPaths) {
      final cf = File(cp);
      final raf = cf.openSync(mode: FileMode.read);
      int bytesRead;
      while ((bytesRead = raf.readIntoSync(buf)) > 0) {
        waf.writeFromSync(buf, 0, bytesRead);
      }
      raf.closeSync();
      cf.deleteSync();
    }
    waf.closeSync();
    return args.finalTempPath;
  }

  Future<int> readEncryptedChunk(
    String filePath,
    int offset,
    int size,
    Uint8List destBuffer,
  ) async {
    if (!_isUnlocked || _db == null || _masterKeyBytes == null) return 0;
    try {
      final normPath = _normalizePath(filePath);
      var meta = _getCachedMeta(normPath);
      if (meta == null) {
        final pending = _findPendingUpdate(normPath);
        if (pending != null) {
          meta = _VaultFileMeta(
            storageId: pending['storage_id'] as String,
            ivBase64: pending['iv'] as String,
          );
        } else {
          final res = await _db!.query(
            'files',
            columns: ['storage_id', 'iv'],
            where: 'path = ?',
            whereArgs: [normPath],
            limit: 1,
          );
          if (res.isEmpty) return 0;
          meta = _VaultFileMeta(
            storageId: res.first['storage_id'] as String,
            ivBase64: res.first['iv'] as String,
          );
        }
        _putCachedMeta(normPath, meta);
      }

      final physicalFile = _getPhysicalFile(meta.storageId);
      if (!physicalFile.existsSync()) return 0;
      final physicalLength = physicalFile.lengthSync();
      if (physicalLength == 0) return 0;

      int blockOffset = (offset ~/ 16) * 16;
      int diff = offset - blockOffset;
      int readSize = ((diff + size + 15) ~/ 16) * 16;

      if (blockOffset >= physicalLength) return 0;
      if (blockOffset + readSize > physicalLength) {
        readSize = physicalLength - blockOffset;
      }

      final transferable = await compute(
        _isolateReadChunk,
        _ReadChunkPayload(
          physicalFile.path,
          meta.ivBase64,
          _masterKeyBytes!,
          blockOffset,
          blockOffset + readSize,
          (blockOffset + readSize) >= physicalLength,
        ),
      );

      final plain = transferable.materialize().asUint8List();

      int available = plain.length - diff;
      int outLen = size < available ? size : available;
      if (outLen <= 0) return 0;

      destBuffer.setRange(0, outLen, plain, diff);
      return outLen;
    } catch (e, s) {
      log.severe('readEncryptedChunk error', e, s);
      return 0;
    }
  }

  Future<bool> deleteFile(String filePath) async {
    if (!_isUnlocked || _db == null) return false;
    await _flushPendingDbUpdates();

    try {
      final normPath = _normalizePath(filePath);
      String? storageId;

      await _db!.transaction((txn) async {

        final result = await txn.query(
          'files',
          columns: ['storage_id', 'size'],
          where: 'path = ?',
          whereArgs: [normPath],
        );
        if (result.isEmpty) return;

        storageId = result.first['storage_id'] as String;
        final size = result.first['size'] as int? ?? 0;

        await txn.delete('files', where: 'path = ?', whereArgs: [normPath]);

        if (FileManager.isCountableFile(normPath)) {
          await _updateRecursiveCounts(txn, normPath, -1, -size);
          await _incrementTotalFileCount(txn, -1);
        }
      });

      if (storageId != null) {
        final file = _getPhysicalFile(storageId!);
        if (file.existsSync()) {
          await compute(isolateSecureDeletePaths, [file.path]);
        }
      }

      _invalidateCachedRead(normPath);
      _invalidateCachedMeta(normPath);
      _invalidateAllFolderCounts();

      return true;
    } catch (e) {
      log.severe('Delete error: $e');
      return false;
    }
  }

  File _getPhysicalFile(String uuid) {

    final prefix = uuid.substring(0, 2);
    return File(p.join(_storageRoot!.path, 'data', prefix, '$uuid.enc'));
  }

  void _setupPaths(String inputPath) {
    if (inputPath.endsWith('.db')) {
      _vaultPath = inputPath;
      _storageRoot = File(inputPath).parent;
    } else {
      _storageRoot = Directory(inputPath);
      _vaultPath = p.join(inputPath, 'saber_index.db');
    }
  }

  Future<void> _createTables(Database db) async {

    await db.execute('''
      CREATE TABLE IF NOT EXISTS files (
        path TEXT PRIMARY KEY,
        storage_id TEXT NOT NULL,
        iv TEXT NOT NULL,
        last_modified INTEGER NOT NULL,
        size INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS folders (
        path TEXT PRIMARY KEY,
        last_modified INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        file_count INTEGER DEFAULT 0,
        total_size INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS config (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_path ON files(path)');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_folder_path ON folders(path)',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_folders_list ON folders(path, file_count)',
    );
  }

  Future<void> lock() async {
    await _close();
    HomeDataCache.instance.invalidate();
    ThumbnailCache.instance.clear();
    log.info('Vault locked');
  }

  Future<void> _close() async {
    await _flushPendingDbUpdates();
    _dbCommitTimer?.cancel();
    try {
      await _db?.close();
    } catch (_) {}
    _db = null;
    _fileEncrypter = null;
    _clearReadCache();
    _clearMetaCache();
    _invalidateAllFolderCounts();
    _isUnlocked = false;
    unlockState.value = false;
  }

  String _normalizePath(String path) => FileManager.toRelativePath(path);

  String _normalizeFolderPath(String path) {
    var normalized = _normalizePath(path);
    if (!normalized.endsWith('/')) normalized += '/';
    if (normalized.length > 1 && !normalized.startsWith('/')) {
      normalized = '/$normalized';
    }
    return normalized;
  }

  bool _hasConsecutiveDuplicateSegment(String folderPath) =>
      _hasConsecutiveDuplicateSegmentStatic(folderPath);

  static bool hasConsecutiveDuplicateSegment(String folderPath) =>
      _hasConsecutiveDuplicateSegmentStatic(folderPath);

  static bool _hasConsecutiveDuplicateSegmentStatic(String folderPath) {
    final parts = folderPath.split('/').where((s) => s.isNotEmpty).toList();
    for (int i = 1; i < parts.length; i++) {
      if (parts[i] == parts[i - 1]) return true;
    }
    return false;
  }

  bool _isRootLevelFolder(String folderPath) {
    final parts = folderPath.split('/').where((s) => s.isNotEmpty).toList();
    return parts.length == 1;
  }

  Future<void> _ensureSchema() async {
    if (_db == null) return;

    await _createTables(_db!);

    var needsFolderCountRebuild = false;
    try {
      await _db!.rawQuery(
        'SELECT file_count, total_size, created_at FROM folders LIMIT 0',
      );
    } catch (_) {
      log.info(
        'Migrating folders table to include file_count, total_size, and created_at...',
      );
      try {
        await _db!.execute(
          'ALTER TABLE folders ADD COLUMN file_count INTEGER DEFAULT 0',
        );
      } catch (_) {}
      try {
        await _db!.execute(
          'ALTER TABLE folders ADD COLUMN total_size INTEGER DEFAULT 0',
        );
      } catch (_) {}
      try {
        await _db!.execute(
          'ALTER TABLE folders ADD COLUMN created_at INTEGER DEFAULT 0',
        );
      } catch (_) {}
      needsFolderCountRebuild = true;
    }

    final countsVersion = await _readConfigValue(_db!, _countsVersionConfigKey);
    final needsVersionedRebuild =
        countsVersion == null || countsVersion != _countsVersionValue;

    if (needsFolderCountRebuild || needsVersionedRebuild) {
      await _rebuildAllFolderCounts(_db!);
      final computedTotal = await _countAllCountableFiles(_db!);
      await _db!.insert('config', {
        'key': _totalFileCountConfigKey,
        'value': '$computedTotal',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _db!.insert('config', {
        'key': _countsVersionConfigKey,
        'value': _countsVersionValue,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await _ensureTotalFileCountRow(_db!);
  }

  Future<void> _rebuildAllFolderCounts(DatabaseExecutor executor) async {
    final folderRows = await executor.query('folders', columns: ['path']);
    final batch = executor.batch();
    for (final row in folderRows) {
      final folderPath = row['path'] as String?;
      if (folderPath == null) continue;

      final patternWithSlash = '$folderPath%';
      final patternNoLeading = folderPath.startsWith('/')
          ? '${folderPath.substring(1)}%'
          : patternWithSlash;

      final fileRes = await executor.query(
        'files',
        columns: ['path', 'size'],
        where: 'path LIKE ? OR path LIKE ?',
        whereArgs: [patternWithSlash, patternNoLeading],
      );

      int count = 0;
      int size = 0;
      for (final fRow in fileRes) {
        final path = fRow['path'] as String?;
        if (path != null && FileManager.isCountableFile(path)) {
          count++;
          size += (fRow['size'] as int? ?? 0);
        }
      }

      batch.rawUpdate(
        'UPDATE folders SET file_count = ?, total_size = ?, last_modified = ? WHERE path = ?',
        [count, size, DateTime.now().millisecondsSinceEpoch, folderPath],
      );
    }
    await batch.commit(noResult: true);
  }

  List<String> _getAncestorFolders(String path) {
    var normalized = _normalizePath(path);
    if (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    final parts = normalized
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (parts.length <= 1) return const [];

    final ancestors = <String>[];
    var current = '';
    for (int i = 0; i < parts.length - 1; i++) {
      current = current.isEmpty ? '/${parts[i]}' : '$current${parts[i]}';
      if (!current.endsWith('/')) current += '/';
      if (!_hasConsecutiveDuplicateSegment(current)) {
        ancestors.add(current);
      }
    }
    return ancestors;
  }

  Future<void> _ensureFolderRow(Transaction txn, String folderPath) async {
    if (_hasConsecutiveDuplicateSegment(folderPath)) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await txn.insert('folders', {
      'path': folderPath,
      'last_modified': now,
      'created_at': now,
      'file_count': 0,
      'total_size': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _updateRecursiveCounts(
    Transaction txn,
    String path,
    int countDelta,
    int sizeDelta,
  ) async {

    for (final folderPath in _getAncestorFolders(path)) {
      await _ensureFolderRow(txn, folderPath);
      await txn.rawUpdate(
        'UPDATE folders SET file_count = MAX(0, file_count + ?), total_size = MAX(0, total_size + ?) WHERE path = ?',
        [countDelta, sizeDelta, folderPath],
      );
    }
  }

  Future<void> _writeVaultConfig(
    String path,
    int kdf,
    int pageSize,
    String salt, {
    int scryptN = _defaultScryptN,
    int scryptR = _defaultScryptR,
    int scryptP = _defaultScryptP,
  }) async {
    final f = File('$path.config');
    await f.writeAsString(
      jsonEncode({
        'kdf_iter': kdf,
        'cipher_page_size': pageSize,
        'salt': salt,
        'scrypt_n': scryptN,
        'scrypt_r': scryptR,
        'scrypt_p': scryptP,
      }),
    );
  }

  Future<Map<String, dynamic>> _readVaultConfig(String path) async {
    final f = File('$path.config');
    if (f.existsSync()) return jsonDecode(await f.readAsString());
    return {};
  }

  Future<bool> fileExists(String p) async {
    if (!_isUnlocked || _db == null) return false;
    final normPath = _normalizePath(p);
    if (_findPendingUpdate(normPath) != null) return true;
    final res = await _db!.query(
      'files',
      where: 'path = ?',
      whereArgs: [normPath],
    );
    return res.isNotEmpty;
  }

  Future<Map<String, bool>> fileExistsBulk(Iterable<String> paths) async {
    if (!_isUnlocked || _db == null) return const {};
    final normalized = paths.map(_normalizePath).toSet().toList();
    if (normalized.isEmpty) return const {};

    final result = <String, bool>{for (final p in normalized) p: false};
    for (final path in normalized) {
      if (_findPendingUpdate(path) != null) result[path] = true;
    }
    const chunkSize = 900;
    for (int i = 0; i < normalized.length; i += chunkSize) {
      final end = (i + chunkSize < normalized.length)
          ? i + chunkSize
          : normalized.length;
      final chunk = normalized.sublist(i, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await _db!.rawQuery(
        'SELECT path FROM files WHERE path IN ($placeholders)',
        chunk,
      );
      for (final row in rows) {
        final path = row['path'] as String?;
        if (path != null) result[path] = true;
      }
    }
    return result;
  }

  Future<int> deleteUnusedAssetFilesForBase(
    String basePath,
    int keepAssets,
  ) async {
    if (!_isUnlocked || _db == null) return 0;
    await _flushPendingDbUpdates();
    final normalizedBase = _normalizePath(basePath);
    final sw = Stopwatch()..start();

    final assetPaths = await getAssetPathsForBase(normalizedBase);
    if (assetPaths.isEmpty) return 0;

    final toDelete = <String>[];
    for (final path in assetPaths) {
      if (!path.startsWith('$normalizedBase.')) continue;
      final suffix = path.substring(normalizedBase.length + 1);
      final assetIndex = int.tryParse(suffix);
      if (assetIndex != null && assetIndex >= keepAssets) {
        toDelete.add(path);
      }
    }
    if (toDelete.isEmpty) return 0;

    final storageIds = <String>[];
    await _db!.transaction((txn) async {
      const chunkSize = 900;
      for (int i = 0; i < toDelete.length; i += chunkSize) {
        final end = (i + chunkSize < toDelete.length)
            ? i + chunkSize
            : toDelete.length;
        final chunk = toDelete.sublist(i, end);
        final placeholders = List.filled(chunk.length, '?').join(',');
        final rows = await txn.rawQuery(
          'SELECT path, storage_id FROM files WHERE path IN ($placeholders)',
          chunk,
        );
        for (final row in rows) {
          final path = row['path'] as String?;
          final storageId = row['storage_id'] as String?;
          if (path == null || storageId == null) continue;
          storageIds.add(storageId);
          _invalidateCachedRead(path);
          _invalidateCachedMeta(path);
        }
        await txn.rawDelete(
          'DELETE FROM files WHERE path IN ($placeholders)',
          chunk,
        );
      }
    });

    final paths = storageIds
        .map((id) => _getPhysicalFile(id).path)
        .where((path) => File(path).existsSync())
        .toList();
    if (paths.isNotEmpty) {
      await compute(isolateSecureDeletePaths, paths);
    }

    _logPerf(
      'deleteUnusedAssetFilesForBase',
      sw,
      extra: '(base=$normalizedBase, deleted=${storageIds.length})',
    );
    return storageIds.length;
  }

  Future<bool> folderExists(String p) async {
    if (!_isUnlocked || _db == null) return false;
    final normalized = _normalizeFolderPath(p);
    final res = await _db!.query(
      'folders',
      where: 'path = ?',
      whereArgs: [normalized],
    );
    return res.isNotEmpty;
  }

  Future<List<String>> getAllFolders() async {
    if (!_isUnlocked || _db == null) return [];
    final res = await _db!.query('folders', columns: ['path']);
    return res.map((r) => r['path'] as String).toList();
  }

  Future<void> createFolder(String path) async {
    if (!_isUnlocked || _db == null) return;
    final normalized = _normalizeFolderPath(path);
    if (normalized == '/') return;
    if (_hasConsecutiveDuplicateSegment(normalized)) return;

    final parts = normalized
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    await _db!.transaction((txn) async {
      final batch = txn.batch();
      var current = '';
      for (final part in parts) {
        final base = current.isEmpty || current == '/'
            ? ''
            : current.replaceAll(RegExp(r'/$'), '');
        current = p.posix.normalize('/$base/$part');
        if (!current.endsWith('/')) current += '/';
        if (_hasConsecutiveDuplicateSegment(current)) continue;
        batch.insert('folders', {
          'path': current,
          'last_modified': timestamp,
          'created_at': timestamp,
          'file_count': 0,
          'total_size': 0,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<DateTime?> getFileLastModified(String p) async {
    if (!_isUnlocked || _db == null) return null;
    final normPath = _normalizePath(p);
    final pending = _findPendingUpdate(normPath);
    if (pending != null) {
      return DateTime.fromMillisecondsSinceEpoch(
        pending['last_modified'] as int,
      );
    }
    final res = await _db!.query(
      'files',
      columns: ['last_modified'],
      where: 'path = ?',
      whereArgs: [normPath],
    );
    if (res.isEmpty) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      res.first['last_modified'] as int,
    );
  }

  Future<List<String>> getAllFiles() async {
    if (!_isUnlocked || _db == null) return [];
    final res = await _db!.query('files', columns: ['path']);
    return res.map((r) => r['path'] as String).toList();
  }

  Future<List<String>> getFilesByPrefix(
    String prefix, {
    bool ensureTrailingSlash = false,
  }) async {
    if (!_isUnlocked || _db == null) return [];
    final normalized = ensureTrailingSlash
        ? _normalizeFolderPath(prefix)
        : _normalizePath(prefix);
    final res = await _db!.query(
      'files',
      columns: ['path'],
      where: 'path LIKE ?',
      whereArgs: ['$normalized%'],
    );
    return res.map((r) => r['path'] as String).toList();
  }

  Future<List<String>> getFoldersByPrefix(
    String prefix, {
    bool ensureTrailingSlash = false,
  }) async {
    if (!_isUnlocked || _db == null) return [];
    final normalized = ensureTrailingSlash
        ? _normalizeFolderPath(prefix)
        : _normalizePath(prefix);
    final res = await _db!.query(
      'folders',
      columns: ['path'],
      where: 'path LIKE ?',
      whereArgs: ['$normalized%'],
    );
    return res.map((r) => r['path'] as String).toList();
  }

  Future<List<String>> getAssetPathsForBase(String basePath) async {
    if (!_isUnlocked || _db == null) return [];
    final normalized = _normalizePath(basePath);
    final res = await _db!.query(
      'files',
      columns: ['path'],
      where: 'path LIKE ? OR path = ?',
      whereArgs: ['$normalized.%', '$normalized.p'],
    );
    return res.map((r) => r['path'] as String).toList();
  }

  Future<bool> hasChildren(String folderPath) async {
    if (!_isUnlocked || _db == null) return false;
    final normalized = _normalizeFolderPath(folderPath);
    final fileRes = await _db!.query(
      'files',
      columns: ['path'],
      where: 'path LIKE ?',
      whereArgs: ['$normalized%'],
      limit: 1,
    );
    if (fileRes.isNotEmpty) return true;
    final folderRes = await _db!.query(
      'folders',
      columns: ['path'],
      where: 'path LIKE ? AND path != ?',
      whereArgs: ['$normalized%', normalized],
      limit: 1,
    );
    return folderRes.isNotEmpty;
  }

  Future<void> dispose() => _close();

  Future<bool> migrateFromDisk(List<String> paths) async {
    int fail = 0;
    for (final p in paths) {
      if (p.contains('saber_vault') ||
          p.split('/').last.startsWith('.saber_')) {
        continue;
      }
      try {
        final f = FileManager.getFile(p);
        if (!f.existsSync()) continue;

        final data = await f.readAsBytes();

        await writeFile(p, data, lastModified: await f.lastModified());

        await FileManager.secureDelete(f);
      } catch (e) {
        log.warning('Migration failed for $p: $e');
        fail++;
      }
    }
    return fail == 0;
  }

  Future<bool> migrateToDisk(List<String> paths) async {
    int fail = 0;
    for (final p in paths) {
      try {

        final data = await readFile(p);
        if (data == null) continue;

        final f = FileManager.getFile(p);
        if (!f.parent.existsSync()) f.parent.createSync(recursive: true);
        await f.writeAsBytes(data);

        await deleteFile(p);
      } catch (e) {
        log.warning('Migration failed for $p: $e');
        fail++;
      }
    }
    return fail == 0;
  }

  Future<bool> moveFile(String from, String to) async {
    if (!_isUnlocked || _db == null) return false;
    await _flushPendingDbUpdates();
    try {
      final normFrom = _normalizePath(from);
      final normTo = _normalizePath(to);

      int rowsUpdated = 0;
      await _db!.transaction((txn) async {

        final sizeRes = await txn.query(
          'files',
          columns: ['size'],
          where: 'path = ?',
          whereArgs: [normFrom],
        );
        final size = sizeRes.isNotEmpty
            ? sizeRes.first['size'] as int? ?? 0
            : 0;

        rowsUpdated = await txn.update(
          'files',
          {'path': normTo},
          where: 'path = ?',
          whereArgs: [normFrom],
        );

        if (rowsUpdated != 1) return;

        final fromCountable = FileManager.isCountableFile(normFrom);
        final toCountable = FileManager.isCountableFile(normTo);

        final ancestorCountDeltas = <String, int>{};
        final ancestorSizeDeltas = <String, int>{};

        if (fromCountable) {
          for (final dir in _getAncestorFolders(normFrom)) {
            ancestorCountDeltas[dir] = (ancestorCountDeltas[dir] ?? 0) - 1;
            ancestorSizeDeltas[dir] = (ancestorSizeDeltas[dir] ?? 0) - size;
          }
        }
        if (toCountable) {
          for (final dir in _getAncestorFolders(normTo)) {
            ancestorCountDeltas[dir] = (ancestorCountDeltas[dir] ?? 0) + 1;
            ancestorSizeDeltas[dir] = (ancestorSizeDeltas[dir] ?? 0) + size;
          }
        }

        for (final dir in ancestorCountDeltas.keys) {
          final cDelta = ancestorCountDeltas[dir]!;
          final sDelta = ancestorSizeDeltas[dir]!;
          if (cDelta != 0 || sDelta != 0) {
            await _ensureFolderRow(txn, dir);
            await txn.rawUpdate(
              'UPDATE folders SET file_count = MAX(0, file_count + ?), total_size = MAX(0, total_size + ?) WHERE path = ?',
              [cDelta, sDelta, dir],
            );
          }
        }

        if (fromCountable && !toCountable) {
          await _incrementTotalFileCount(txn, -1);
        } else if (!fromCountable && toCountable) {
          await _incrementTotalFileCount(txn, 1);
        }
      });

      if (rowsUpdated != 1) {
        log.warning('Vault moveFile: source not found in index: $normFrom');
        return false;
      }
      final movedCached = _getCachedRead(normFrom);
      if (movedCached != null) {
        _putCachedRead(normTo, movedCached);
      }
      final movedMeta = _getCachedMeta(normFrom);
      if (movedMeta != null) {
        _putCachedMeta(normTo, movedMeta);
      }
      _invalidateCachedRead(normFrom);
      _invalidateCachedMeta(normFrom);
      _invalidateAllFolderCounts();

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> moveDirectory(String from, String to) async {
    if (!_isUnlocked || _db == null) return false;
    await _flushPendingDbUpdates();
    try {
      var source = _normalizePath(from);
      var dest = _normalizePath(to);
      if (!source.endsWith('/')) source += '/';
      if (!dest.endsWith('/')) dest += '/';

      await _db!.transaction((txn) async {

        final res = await txn.query(
          'folders',
          columns: ['file_count', 'total_size'],
          where: 'path = ?',
          whereArgs: [source],
        );
        final count = res.isNotEmpty
            ? (res.first['file_count'] as int? ?? 0)
            : 0;
        final size = res.isNotEmpty
            ? (res.first['total_size'] as int? ?? 0)
            : 0;

        await txn.rawUpdate(
          'UPDATE folders SET path = ? || SUBSTR(path, ?) WHERE path LIKE ?',
          [dest, source.length + 1, '$source%'],
        );

        await txn.rawUpdate(
          'UPDATE files SET path = ? || SUBSTR(path, ?) WHERE path LIKE ?',
          [dest, source.length + 1, '$source%'],
        );

        final ancestorCountDeltas = <String, int>{};
        final ancestorSizeDeltas = <String, int>{};

        for (final dir in _getAncestorFolders(source)) {
          ancestorCountDeltas[dir] = (ancestorCountDeltas[dir] ?? 0) - count;
          ancestorSizeDeltas[dir] = (ancestorSizeDeltas[dir] ?? 0) - size;
        }
        for (final dir in _getAncestorFolders(dest)) {
          ancestorCountDeltas[dir] = (ancestorCountDeltas[dir] ?? 0) + count;
          ancestorSizeDeltas[dir] = (ancestorSizeDeltas[dir] ?? 0) + size;
        }

        for (final dir in ancestorCountDeltas.keys) {
          final cDelta = ancestorCountDeltas[dir]!;
          final sDelta = ancestorSizeDeltas[dir]!;
          if (cDelta != 0 || sDelta != 0) {
            await _ensureFolderRow(txn, dir);
            await txn.rawUpdate(
              'UPDATE folders SET file_count = MAX(0, file_count + ?), total_size = MAX(0, total_size + ?) WHERE path = ?',
              [cDelta, sDelta, dir],
            );
          }
        }
      });

      _invalidateCachedReadsByPrefix(source);
      _invalidateCachedReadsByPrefix(dest);
      _invalidateCachedMetaByPrefix(source);
      _invalidateCachedMetaByPrefix(dest);
      _invalidateAllFolderCounts();

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteDirectory(String dir) async {
    if (!_isUnlocked || _db == null) return false;
    await _flushPendingDbUpdates();
    var normalized = _normalizePath(dir);
    if (!normalized.endsWith('/')) normalized += '/';

    try {
      final filesToDelete = <String>[];
      await _db!.transaction((txn) async {

        final res = await txn.query(
          'folders',
          columns: ['file_count', 'total_size'],
          where: 'path = ?',
          whereArgs: [normalized],
        );
        final count = res.isNotEmpty
            ? (res.first['file_count'] as int? ?? 0)
            : 0;
        final size = res.isNotEmpty
            ? (res.first['total_size'] as int? ?? 0)
            : 0;

        await txn.delete(
          'folders',
          where: 'path LIKE ?',
          whereArgs: ['$normalized%'],
        );

        final files = await txn.query(
          'files',
          columns: ['path', 'storage_id'],
          where: 'path LIKE ?',
          whereArgs: ['$normalized%'],
        );

        await _updateRecursiveCounts(txn, normalized, -count, -size);
        if (count != 0) {
          await _incrementTotalFileCount(txn, -count);
        }

        for (final r in files) {

          filesToDelete.add(r['storage_id'] as String);
        }
        await txn.delete(
          'files',
          where: 'path LIKE ?',
          whereArgs: ['$normalized%'],
        );
      });

      _invalidateCachedReadsByPrefix(normalized);
      _invalidateCachedMetaByPrefix(normalized);
      _invalidateAllFolderCounts();

      final paths = filesToDelete
          .map((id) => _getPhysicalFile(id).path)
          .where((path) => File(path).existsSync())
          .toList();
      if (paths.isNotEmpty) {
        await compute(isolateSecureDeletePaths, paths);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<int> mergeBackup(
    String path,
    String pass, {
    int? kdfIter,
    int? pageSize,
  }) async {

    log.warning('Merge Backup not yet implemented for FBA architecture');
    return 0;
  }

  Future<Map<String, String>> getSecuritySettings() async {
    if (!_isUnlocked || _db == null) return {};
    final config = await _readVaultConfig(_vaultPath!);
    final scryptN = config['scrypt_n']?.toString() ?? 'unknown';
    final scryptR = config['scrypt_r']?.toString() ?? 'unknown';
    final scryptP = config['scrypt_p']?.toString() ?? 'unknown';
    final kdfIter = config['kdf_iter']?.toString() ?? 'unknown';
    final pageSize = config['cipher_page_size']?.toString() ?? 'unknown';
    final saltStatus = ((config['salt'] as String?)?.isNotEmpty ?? false)
        ? 'Present'
        : 'Missing';

    return {
      'Status': 'Unlocked',
      'Architecture': 'Hybrid FBA (Index + Encrypted Blobs)',
      'Cipher': 'AES-256-CBC',
      'KDF': 'Scrypt (N=$scryptN, r=$scryptR, p=$scryptP)',
      'Salt Status': saltStatus,
      'Index Page Size': pageSize,
      'Index KDF Iterations': kdfIter,
    };
  }

  Future<int?> getFileSize(String p) async {
    if (!_isUnlocked || _db == null) return null;
    final normPath = _normalizePath(p);
    final pending = _findPendingUpdate(normPath);
    if (pending != null) return pending['size'] as int?;
    final res = await _db!.query(
      'files',
      columns: ['size'],
      where: 'path = ?',
      whereArgs: [normPath],
    );
    if (res.isEmpty) return null;
    return res.first['size'] as int;
  }

  Future<int> getFolderFileCount(String p) async {
    if (!_isUnlocked || _db == null) return 0;
    final normalized = _normalizeFolderPath(p);
    final cached = _getCachedFolderCount(normalized);
    if (cached != null) return cached;
    final rows = await _db!.query(
      'folders',
      columns: ['file_count'],
      where: 'path = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    final val = rows.isEmpty ? 0 : rows.first['file_count'] as int? ?? 0;
    _putCachedFolderCount(normalized, val);
    return val;
  }

  Future<Map<String, int>> getFolderFileCounts(
    Iterable<String> folderPaths,
  ) async {
    if (!_isUnlocked || _db == null) return const {};
    final normalized = folderPaths
        .map(_normalizeFolderPath)
        .where((p) => p != '/')
        .toSet()
        .toList();
    if (normalized.isEmpty) return const {};

    final result = <String, int>{};
    final missing = <String>[];
    for (final path in normalized) {
      final cached = _getCachedFolderCount(path);
      if (cached != null) {
        result[path] = cached;
      } else {
        missing.add(path);
      }
    }
    if (missing.isNotEmpty) {
      const chunkSize = 900;
      for (var i = 0; i < missing.length; i += chunkSize) {
        final end = min(i + chunkSize, missing.length);
        final chunk = missing.sublist(i, end);
        final placeholders = List.filled(chunk.length, '?').join(',');
        final rows = await _db!.rawQuery(
          'SELECT path, file_count FROM folders WHERE path IN ($placeholders)',
          chunk,
        );
        for (final row in rows) {
          final path = row['path'] as String?;
          if (path == null) continue;
          final count = row['file_count'] as int? ?? 0;
          result[path] = count;
          _putCachedFolderCount(path, count);
        }
      }
    }
    for (final folderPath in normalized) {
      result.putIfAbsent(folderPath, () => 0);
      if (!_folderCountCache.containsKey(folderPath)) {
        _putCachedFolderCount(folderPath, result[folderPath]!);
      }
    }
    return result;
  }

  Future<int> getTotalFileCount() async {
    if (!_isUnlocked || _db == null) return 0;
    await _ensureTotalFileCountRow(_db!);
    final rows = await _db!.query(
      'config',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_totalFileCountConfigKey],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return int.tryParse(rows.first['value'] as String? ?? '0') ?? 0;
  }

  Future<void> _ensureTotalFileCountRow(DatabaseExecutor executor) async {
    final row = await executor.query(
      'config',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_totalFileCountConfigKey],
      limit: 1,
    );
    if (row.isNotEmpty) return;
    final computed = await _countAllCountableFiles(executor);
    await executor.insert('config', {
      'key': _totalFileCountConfigKey,
      'value': '$computed',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> _readConfigValue(
    DatabaseExecutor executor,
    String key,
  ) async {
    final rows = await executor.query(
      'config',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> _incrementTotalFileCount(
    DatabaseExecutor executor,
    int delta,
  ) async {
    if (delta == 0) return;
    await _ensureTotalFileCountRow(executor);
    final row = await executor.query(
      'config',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_totalFileCountConfigKey],
      limit: 1,
    );
    final current = row.isEmpty
        ? 0
        : int.tryParse(row.first['value'] as String? ?? '0') ?? 0;
    final next = max(0, current + delta);
    await executor.update(
      'config',
      {'value': '$next'},
      where: 'key = ?',
      whereArgs: [_totalFileCountConfigKey],
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> _countAllCountableFiles(DatabaseExecutor executor) async {
    final fileRows = await executor.query('files', columns: ['path']);
    var count = 0;
    for (final row in fileRows) {
      final path = row['path'] as String?;
      if (path != null && FileManager.isCountableFile(path)) {
        count++;
      }
    }
    return count;
  }

  Future<File> createBackupArchive(
    String destinationPath,
    String password,
  ) async {
    if (_isUnlocked) {
      await lock();
    }

    final vaultFilePath = _vaultPath ?? vaultPath;
    _setupPaths(vaultFilePath);

    final indexFile = File(_vaultPath!);
    if (!indexFile.existsSync()) {
      throw StateError('Vault index not found at $_vaultPath');
    }

    final configFile = File('${_vaultPath!}.config');
    final dataDir = Directory(p.join(_storageRoot!.path, 'data'));

    if (!configFile.existsSync()) {
      throw StateError('Vault config sidecar missing at ${configFile.path}');
    }

    final prefs = await SharedPreferences.getInstance();
    final prefsMap = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      final value = prefs.get(key);
      if (value != null) {
        prefsMap[key] = value;
      }
    }
    final prefsJson = utf8.encode(jsonEncode(prefsMap));
    final docsDir = await FileManager.getDocumentsDirectory();

    await compute(_isolateVaultBackupTask, {
      'vaultPath': _vaultPath!,
      'configPath': configFile.path,
      'dataDirPath': dataDir.path,
      'destPath': destinationPath,
      'password': password,
      'prefsJson': prefsJson,
      'docsDir': docsDir,
    });

    return File(destinationPath);
  }

  Future<void> restoreBackupArchive(String archivePath, String password) async {
    await lock();

    final tempDir = await Directory.systemTemp.createTemp(
      'saber_vault_restore_',
    );
    try {

      await compute(_isolateVaultRestoreTask, {
        'archivePath': archivePath,
        'password': password,
        'tempDirPath': tempDir.path,
      });

      final configPath = p.join(tempDir.path, 'saber_index.db.config');
      final configJson = jsonDecode(await File(configPath).readAsString());
      final salt = configJson['salt'] as String?;
      if (salt == null || salt.isEmpty) {
        throw StateError('Invalid backup: missing scrypt salt');
      }

      final docDir = await FileManager.getDocumentsDirectory();

      final prefsFile = File(p.join(tempDir.path, '_preferences.json'));
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
        await prefsFile.delete();
      }

      final tempEntities = tempDir.listSync(recursive: false);
      for (final e in tempEntities) {
        if (e is File && p.basename(e.path).startsWith('.saber_')) {
          final dest = File(p.join(docDir, p.basename(e.path)));
          if (dest.existsSync()) dest.deleteSync();
          await e.rename(dest.path);
        }
      }

      final destinationRoot = p.join(docDir, 'saber_vault');
      _setupPaths(destinationRoot);
      final destinationDir = Directory(destinationRoot);
      if (destinationDir.existsSync()) {
        await destinationDir.delete(recursive: true);
      }
      await destinationDir.create(recursive: true);
      await _moveDirectoryContents(tempDir, destinationDir);
    } finally {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  Future<String> _deriveKeyHexAsync(
    String password,
    Uint8List salt, {
    required int n,
    required int r,
    required int p,
  }) async {
    final args = <String, dynamic>{
      'password': password,
      'saltBase64': base64Encode(salt),
      'n': n,
      'r': r,
      'p': p,
    };

    return compute(_deriveKeyHexFromArgs, args);
  }

  Future<void> _moveDirectoryContents(
    Directory source,
    Directory destination,
  ) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: true)) {
      final relative = p.relative(entity.path, from: source.path);
      final targetPath = p.join(destination.path, relative);

      if (entity is Directory) {
        await Directory(targetPath).create(recursive: true);
        continue;
      }

      if (entity is File) {
        await File(targetPath).parent.create(recursive: true);
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

  Future<Map<String, dynamic>?> getFolderProperties(String path) async {
    if (!_isUnlocked || _db == null) return null;
    final normalized = _normalizeFolderPath(path);
    final res = await _db!.query(
      'folders',
      where: 'path = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    if (res.isEmpty) return null;
    return {
      'file_count': res.first['file_count'],
      'total_size': res.first['total_size'],
      'last_modified': res.first['last_modified'],
      'created_at': res.first['created_at'],
    };
  }
}
