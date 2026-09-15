// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:saber/data/backup/backup_format.dart';
import 'package:saber/data/backup/monolith_backup_core.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/home_data_cache.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/services/background_operation_lock.dart';
import 'package:saber/services/perf_timing.dart';
import 'package:saber/services/sba_encryption.dart';
import 'package:saber/services/thumbnail_cache.dart';
import 'package:saber/services/vault_blob_crypto.dart';
import 'package:saber/services/vault_worker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

bool _vaultUseAndroidNativeAesFileIo() {
  if (kIsWeb) return false;
  try {
    return Platform.isAndroid && Abi.current() == Abi.androidArm64;
  } catch (_) {
    return false;
  }
}

Uint8List _archiveFileBytes(ArchiveFile file) {
  final output = OutputMemoryStream();
  file.writeContent(output);
  return Uint8List.fromList(output.getBytes());
}

/// Worker entry: write bytes to a temp path (avoids MethodChannel copy for large notes).
bool _isolateWriteTempBytes(Map<String, dynamic> args) {
  final path = args['path'] as String;
  final bytes = args['bytes'] as Uint8List;
  File(path).writeAsBytesSync(bytes, flush: true);
  return true;
}

Future<bool> _isolateVaultBackupTask(Map<String, dynamic> args) async {
  final receive = ReceivePort();
  try {
    await Isolate.spawn(monolithVaultBackupIsolateMain, {
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

Future<bool> _isolateVaultRestoreTask(Map<String, dynamic> args) async {
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
      throw StateError('Invalid backup: missing manifest');
    }
    final manifest = BackupFormat.decodeJsonFile(
      _archiveFileBytes(manifestFiles.first),
    );
    if (manifest['type'] != 'vault') {
      throw StateError(
        'Invalid backup: wrong type (expected vault, got ${manifest['type']})',
      );
    }
    final isV3 = BackupFormat.isManifestV3(manifest);
    final manifestFileMap = isV3
        ? BackupFormat.manifestFileMap(manifest)
        : <String, Map<String, dynamic>>{};

    final hasIndex = archive.files.any((f) => f.name == 'saber_index.db');
    final hasConfig = archive.files.any(
      (f) => f.name == 'saber_index.db.config',
    );
    final hasData = archive.files.any((f) => f.name.startsWith('data/'));

    if (!hasIndex || !hasConfig || !hasData) {
      throw StateError('Invalid backup: missing required vault files');
    }

    if (isV3) {
      BackupFormat.validateUniquePaths(manifestFileMap.keys);
      final dirs = (manifest['directories'] as List?) ?? const [];
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
        final fileBytes = _archiveFileBytes(file);
        final manifestEntry = manifestFileMap[normalizedPath];
        if (isV3) {
          if (manifestEntry == null) {
            throw StateError('Invalid backup: unexpected file $normalizedPath');
          }
          BackupFormat.verifyFileBytes(
            normalizedPath,
            fileBytes,
            manifestEntry,
          );
        }
        final outFile = File(outPath);
        outFile.parent.createSync(recursive: true);
        outFile.writeAsBytesSync(fileBytes);
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
  final int cipherVer;
  _WriteResult(
    this.virtualPath,
    this.storageId,
    this.ivBase64,
    this.size, {
    this.cipherVer = kVaultCipherGcm,
  });
}

class _VaultFileMeta {
  final String storageId;
  final String ivBase64;
  final int cipherVer;

  const _VaultFileMeta({
    required this.storageId,
    required this.ivBase64,
    this.cipherVer = kVaultCipherCbc,
  });
}

class VaultAdapter {
  VaultAdapter._();
  static final VaultAdapter instance = VaultAdapter._();

  static final log = Logger('VaultAdapter');
  static const MethodChannel _vaultCryptoChannel = MethodChannel(
    'com.resendeghf.notes/vault_crypto',
  );

  /// SQLCipher `mlock`s every page when memory security is on. If
  /// `RLIMIT_MEMLOCK` stays at the usual ~64 KiB Android cap, those calls
  /// fail (errno 12) on every page and vault IO stalls. Keep it on only when
  /// the process can actually lock a working set (~8 MiB) or is unlimited.
  static const int _cipherMemorySecurityMinLockBytes = 8 * 1024 * 1024;

  Future<void> _applyCipherMemorySecurity(Database db) async {
    var enable = true;
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final budget = await _vaultCryptoChannel.invokeMethod<int>(
          'raiseMemlock',
        );
        if (budget != null &&
            budget >= 0 &&
            budget < _cipherMemorySecurityMinLockBytes) {
          enable = false;
          log.warning(
            'RLIMIT_MEMLOCK is ${budget}B after raise (need '
            '$_cipherMemorySecurityMinLockBytes); PRAGMA cipher_memory_security '
            'OFF so SQLCipher does not mlock-fail every page',
          );
        } else {
          log.info(
            'RLIMIT_MEMLOCK budget=$budget (-1=unlimited); '
            'cipher_memory_security ON',
          );
        }
      } catch (e) {
        log.warning('raiseMemlock failed: $e');
      }
    }
    await db.execute(
      'PRAGMA cipher_memory_security = ${enable ? 'ON' : 'OFF'}',
    );
  }

  static const _defaultScryptN = 16384;
  static const _defaultScryptR = 8;
  static const _defaultScryptP = 1;
  static const _totalFileCountConfigKey = 'total_file_count';
  static const _countsVersionConfigKey = 'counts_version';
  static const _countsVersionValue = '4';

  enc.Encrypter? _fileEncrypter;
  Uint8List? _masterKeyBytes;

  Database? _db;
  bool _isUnlocked = false;
  String? _vaultPath;
  Directory? _storageRoot;

  final LinkedHashMap<String, Uint8List> _readCache = LinkedHashMap();
  int _readCacheBytes = 0;

  /// In-memory decrypt cache (aarch64 Android–only product; tuned for phones).
  /// Prefer keeping many note-sized `.sbn2` bodies warm for near-instant reopen.
  static const int _maxReadCacheEntries = 48;

  static const int _maxReadCacheBytes = 256 * 1024 * 1024;

  /// Avoid keeping very large decrypted blobs in [\_readCache]; callers still get
  /// plaintext via [_decryptedTempFileByVaultPath] reuse without duplicating 100MB+
  /// in the Dart heap beside native/pdf buffers.
  static const int _maxBytesVaultRamReadCache = 64 * 1024 * 1024;

  /// [readFileToTempFile]: on Android arm64, native AES-CBC streaming decrypt is
  /// tried first; otherwise parallel multi-shard decrypt up to this ciphertext size,
  /// then sequential plaintext write. Above this, single-isolate streaming (rare).
  static const int _parallelTempDecryptMaxBytes = 512 * 1024 * 1024;

  /// Below this, a single [_isolateDecryptChunkToFile] avoids isolate spawn overhead.
  static const int _parallelTempDecryptMinBytes = 2 * 1024 * 1024;

  /// Hard cap on parallel decrypt isolates (oversubscription vs RAM / scheduler).
  static const int _decryptParallelMaxWorkers = 16;

  /// Target ciphertext per shard hint for very large blobs; with
  /// [_decryptParallelMaxWorkers] this caps at 16 workers (~320 MiB+ ciphertext)
  /// so disk latency can overlap AES when isolates outnumber cores.
  static const int _decryptParallelOversubscribeMinBytes = 96 * 1024 * 1024;

  static const int _decryptBytesPerWorkerHint = 20 * 1024 * 1024;

  /// Parallel AES shards for large vault blobs on aarch64 Android.
  static int _decryptWorkerCountForLength(int ciphertextLength) {
    final cores = max(1, Platform.numberOfProcessors);
    if (ciphertextLength <= 256 * 1024) return 1;
    if (ciphertextLength < 1024 * 1024) {
      return min(2, cores);
    }
    if (ciphertextLength >= _decryptParallelOversubscribeMinBytes) {
      final want = max(
        cores,
        (ciphertextLength / _decryptBytesPerWorkerHint).ceil(),
      );
      return min(_decryptParallelMaxWorkers, want);
    }
    if (ciphertextLength >= 48 * 1024 * 1024) {
      return min(cores, 8);
    }
    if (ciphertextLength >= 32 * 1024 * 1024 || cores <= 6) {
      return min(cores, 5);
    }
    return min(cores, 4);
  }

  final LinkedHashMap<String, _VaultFileMeta> _metaCache = LinkedHashMap();
  static const _maxMetaCacheEntries = 4096;

  /// Concurrent [readFileToTempFile] calls for the same vault path share one
  /// decrypt+write (e.g. editor prefetch while the note body is still loading).
  final Map<String, Future<String?>> _readFileToTempFileInflight = {};

  /// Plaintext temp path from the last successful [readFileToTempFile] for this
  /// vault path. Subsequent opens reuse it until the ciphertext is updated or
  /// the vault locks (avoids a second full AES pass once [inflight] completed).
  final Map<String, String> _decryptedTempFileByVaultPath = {};

  /// Concurrent [readFile] calls for the same path share one decrypt (e.g. note
  /// body read overlapping with `.sbn2.0` warm-up).
  final Map<String, Future<Uint8List?>> _readFileInflight = {};

  /// Depth of note-open critical sections — pauses idle CBC→GCM migration so
  /// decrypt workers stay available for the open path.
  int _openQuiesceDepth = 0;

  final Map<String, int> _folderCountCache = {};

  final List<Map<String, dynamic>> _pendingDbUpdates = [];
  final Set<String> _pendingPathsToCheck = {};
  Timer? _dbCommitTimer;
  static const _dbCommitDebounce = Duration(seconds: 2);
  bool _isFlushing = false;

  static bool get isUnlocked => instance._isUnlocked;
  static final unlockState = ValueNotifier(false);
  static ValueListenable<bool> get unlockListenable => unlockState;
  static int _preventLockDepth = 0;
  static bool get preventLock => _preventLockDepth > 0;
  static set preventLock(bool value) {
    if (value) {
      _preventLockDepth++;
    } else {
      _preventLockDepth = max(0, _preventLockDepth - 1);
    }
  }

  /// Bound from [App] so lock redirects can navigate without circular imports.
  static GoRouter? _router;
  static void bindRouter(GoRouter router) => _router = router;

  /// Locks the vault (if unlocked) and navigates to the vault login screen.
  static Future<void> lockAndGoToLogin() async {
    if (!stows.localEncryptionEnabled.value) return;

    try {
      if (isUnlocked) {
        // [lock] clears unlock state synchronously before its first await.
        final lockFuture = instance.lock();
        ensureLoginRouteIfLocked();
        await lockFuture;
      } else {
        unlockState.value = false;
        unlockState.notifyListeners();
        ensureLoginRouteIfLocked();
      }
    } catch (e, st) {
      log.warning('lockAndGoToLogin: lock failed: $e', e, st);
      ensureLoginRouteIfLocked();
    }
  }

  /// If encryption is on and the vault is locked, force the login route
  /// (unless already on login / settings). Also refreshes GoRouter redirects.
  static void ensureLoginRouteIfLocked() {
    if (!stows.localEncryptionEnabled.value) return;
    if (isUnlocked) return;

    final router = _router;
    if (router == null) return;

    final loc = router.state.matchedLocation;
    if (loc == RoutePaths.login) {
      router.refresh();
      return;
    }
    final onSettings =
        loc.startsWith(RoutePaths.prefixOfHome) &&
        (loc == '${RoutePaths.prefixOfHome}/settings' ||
            loc.endsWith('/settings'));
    if (onSettings) {
      router.refresh();
      return;
    }
    router.go(RoutePaths.login);
    router.refresh();
  }

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
        await _applyCipherMemorySecurity(_db!);
        final secureDelete = stows.vaultSecureDelete.value;
        await _db!.execute(
          'PRAGMA secure_delete = ${secureDelete ? 'ON' : 'OFF'}',
        );
      } catch (_) {}

      await _initFileEncryption();

      _isUnlocked = true;
      unlockState.value = true;
      log.info('Vault unlocked successfully. FBA Ready.');
      _attachSecurePdfPolicyListeners();
      _scheduleIdleGcmMigration();
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

    // LRU touch — return the same buffer (callers must not mutate).
    // Copying on every hit defeated warm-open latency.
    _readCache[normPath] = cached;
    return cached;
  }

  void _putCachedRead(String normPath, Uint8List data) {
    if (data.length > _maxReadCacheBytes) return;
    // Temp mode: skip caching huge blobs (reopen uses plaintext temp reuse).
    // RAM-only: keep large decrypts warm — plaintext must never hit disk.
    if (data.length > _maxBytesVaultRamReadCache &&
        vaultPathAllowsDiskBackedDecrypt(normPath)) {
      return;
    }

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
    _invalidateDecryptedTempFile(normPath);
  }

  void _invalidateDecryptedTempFile(String normPath) {
    final path = _decryptedTempFileByVaultPath.remove(normPath);
    if (path == null) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  void _invalidateDecryptedTempFilesByPrefix(String prefix) {
    final keys = _decryptedTempFileByVaultPath.keys
        .where((k) => k.startsWith(prefix))
        .toList();
    for (final k in keys) {
      _invalidateDecryptedTempFile(k);
    }
  }

  void _invalidateCachedReadsByPrefix(String prefix) {
    final toRemove = _readCache.keys
        .where((k) => k.startsWith(prefix))
        .toList();
    for (final key in toRemove) {
      final removed = _readCache.remove(key);
      if (removed != null) _readCacheBytes -= removed.length;
    }
    _invalidateDecryptedTempFilesByPrefix(prefix);
  }

  void _clearAllDecryptedTempFiles() {
    for (final path in _decryptedTempFileByVaultPath.values) {
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    _decryptedTempFileByVaultPath.clear();
  }

  /// Wipe any plaintext decrypt temps (e.g. user switched Secure PDF to RAM-only).
  void purgePlaintextDecryptTemps() => _clearAllDecryptedTempFiles();

  /// True when [path] is a vault-managed plaintext decrypt temp that must not be
  /// deleted by asset-cache close (reuse on reopen under Temp mode).
  bool isTrackedPlaintextDecryptTemp(String path) {
    if (path.isEmpty) return false;
    for (final tracked in _decryptedTempFileByVaultPath.values) {
      if (tracked == path) return true;
    }
    return false;
  }

  /// Drop plaintext temp for [path] when that path is (now) RAM-only.
  void purgePlaintextDecryptTempIfRamOnly(String path) {
    final norm = _normalizePath(path);
    if (vaultPathAllowsDiskBackedDecrypt(norm)) return;
    _invalidateDecryptedTempFile(norm);
  }

  bool _securePdfPolicyListenersAttached = false;

  void _attachSecurePdfPolicyListeners() {
    if (_securePdfPolicyListenersAttached) return;
    stows.vaultPdfLoadMode.addListener(_onSecurePdfLoadModeChanged);
    stows.vaultPdfLoadOverrides.addListener(_onSecurePdfLoadOverridesChanged);
    _securePdfPolicyListenersAttached = true;
    // Apply current policy immediately (temps from a prior session / mode).
    _onSecurePdfLoadModeChanged();
    _onSecurePdfLoadOverridesChanged();
  }

  void _detachSecurePdfPolicyListeners() {
    if (!_securePdfPolicyListenersAttached) return;
    stows.vaultPdfLoadMode.removeListener(_onSecurePdfLoadModeChanged);
    stows.vaultPdfLoadOverrides.removeListener(
      _onSecurePdfLoadOverridesChanged,
    );
    _securePdfPolicyListenersAttached = false;
  }

  void _onSecurePdfLoadModeChanged() {
    if (!_isUnlocked) return;
    // Drop temps only for paths that are RAM-only under the effective policy
    // (global + per-note overrides). Temp-override notes keep their files.
    _onSecurePdfLoadOverridesChanged();
  }

  void _onSecurePdfLoadOverridesChanged() {
    if (!_isUnlocked) return;
    final keys = _decryptedTempFileByVaultPath.keys.toList(growable: false);
    for (final k in keys) {
      if (!vaultPathAllowsDiskBackedDecrypt(k)) {
        _invalidateDecryptedTempFile(k);
      }
    }
  }

  void invalidateCachedReadForPath(String path) {
    _invalidateCachedRead(_normalizePath(path));
  }

  /// Pause idle vault re-encrypt work while a note is opening.
  void beginOpenQuiesce() {
    _openQuiesceDepth++;
    _gcmMigrationTimer?.cancel();
    _gcmMigrationTimer = null;
  }

  void endOpenQuiesce() {
    _openQuiesceDepth = max(0, _openQuiesceDepth - 1);
    if (_openQuiesceDepth == 0 &&
        _isUnlocked &&
        _physicalBackupQuiesceDepth == 0) {
      _scheduleIdleGcmMigration();
    }
  }

  bool get _shouldDeferIdleMigration =>
      _openQuiesceDepth > 0 ||
      _physicalBackupQuiesceDepth > 0 ||
      _readFileInflight.isNotEmpty ||
      _readFileToTempFileInflight.isNotEmpty;

  void _clearReadCache() {
    for (final bytes in _readCache.values) {
      try {
        bytes.fillRange(0, bytes.length, 0);
      } catch (_) {
        // Unmodifiable views (e.g. isolate/native buffers) cannot be wiped
        // in place; dropping the reference is enough.
      }
    }
    _readCache.clear();
    _readCacheBytes = 0;
    _clearAllDecryptedTempFiles();
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

  /// Zlib applies only to encrypted **note bodies** ([.sbn2]), not assets like
  /// [Foo.sbn2.0] ([FileManager.assetFileRegex]).
  bool _vaultAesPlaintextNeedsZlibNoteBody(String normPath) {
    if (!normPath.endsWith('.sbn2')) return false;
    return !FileManager.assetFileRegex.hasMatch(p.basename(normPath));
  }

  Uint8List _vaultApplyZlibIfNoteBody(Uint8List aesPlaintext, String normPath) {
    if (!_vaultAesPlaintextNeedsZlibNoteBody(normPath)) return aesPlaintext;
    try {
      return Uint8List.fromList(const ZLibDecoder().decodeBytes(aesPlaintext));
    } catch (_) {
      return aesPlaintext;
    }
  }

  static const int _largeVaultPlaintextTempPersistBytes = 12 * 1024 * 1024;

  /// Persists decrypted AES plaintext for fast reopen. **Only** when the caller
  /// already authorized disk-backed decrypt (temp_file mode / override).
  Future<void> _persistVaultAesPlainTempForReuse(
    String normPath,
    Uint8List aesPlaintext, {
    required bool allowDiskBackedDecrypt,
  }) async {
    if (!allowDiskBackedDecrypt) return;
    if (_decryptedTempFileByVaultPath.containsKey(normPath)) return;
    try {
      final tempDir = await getTemporaryDirectory();
      final path = p.join(tempDir.path, 'vault_aes_${const Uuid().v4()}.tmp');
      await File(
        path,
      ).writeAsBytes(Uint8List.fromList(aesPlaintext), flush: true);
      _decryptedTempFileByVaultPath[normPath] = path;
    } catch (e) {
      log.fine('Vault AES-plain temp persist skipped: $e');
    }
  }

  Future<Uint8List?> readFile(
    String filePath, {
    void Function(double)? onProgress,
    bool? allowDiskBackedDecrypt,
  }) async {
    if (!_isUnlocked ||
        _db == null ||
        _fileEncrypter == null ||
        _masterKeyBytes == null) {
      return null;
    }

    final sw = Stopwatch()..start();
    final normPath = _normalizePath(filePath);
    final allowDisk =
        allowDiskBackedDecrypt ?? vaultPathAllowsDiskBackedDecrypt(normPath);

    final cached = _getCachedRead(normPath);
    if (cached != null) {
      _logPerf('readFile', sw, extra: '(cache hit, ${cached.length} bytes)');
      return cached;
    }

    return _readFileInflight.putIfAbsent(normPath, () async {
      try {
        try {
          return await _readFileAfterCacheMiss(
            normPath,
            filePath,
            sw,
            onProgress: onProgress,
            allowDiskBackedDecrypt: allowDisk,
          );
        } catch (e, s) {
          log.severe('Read error: $filePath', e, s);
          return null;
        }
      } finally {
        _readFileInflight.remove(normPath);
      }
    });
  }

  Future<Uint8List?> _readFileAfterCacheMiss(
    String normPath,
    String filePath,
    Stopwatch sw, {
    void Function(double)? onProgress,
    required bool allowDiskBackedDecrypt,
  }) async {
    final cachedAgain = _getCachedRead(normPath);
    if (cachedAgain != null) {
      _logPerf(
        'readFile',
        sw,
        extra: '(cache hit, ${cachedAgain.length} bytes)',
      );
      return cachedAgain;
    }

    // SECURITY: never reuse plaintext temps when RAM-only is in effect.
    if (allowDiskBackedDecrypt) {
      final reusePlain = _decryptedTempFileByVaultPath[normPath];
      if (reusePlain != null) {
        try {
          final f = File(reusePlain);
          if (f.existsSync()) {
            final raw = await f.readAsBytes();
            final out = _vaultApplyZlibIfNoteBody(raw, normPath);
            _putCachedRead(normPath, out);
            _logPerf(
              'readFile',
              sw,
              extra: '(AES-plain temp reuse, ${out.length} bytes)',
            );
            return out;
          }
        } catch (e) {
          log.fine('Vault AES-plain temp reuse failed: $e');
          _invalidateDecryptedTempFile(normPath);
        }
      }
    } else {
      // Drop any stale plaintext temp from a prior temp_file session.
      _invalidateDecryptedTempFile(normPath);
    }

    final meta = await _resolveFileMeta(normPath);
    if (meta == null) return null;
    final storageId = meta.storageId;
    final ivBase64 = meta.ivBase64;
    final cipherVer = meta.cipherVer;

    final physicalFile = _getPhysicalFile(storageId);
    if (!physicalFile.existsSync()) {
      log.severe(
        'Data corruption: File indexed but missing on disk: $storageId',
      );
      return null;
    }

    final fileSize = physicalFile.lengthSync();
    final applyZlib = _vaultAesPlaintextNeedsZlibNoteBody(normPath);

    /// Ciphertext can exceed 100 MiB for large assets (e.g. PDFs). Optional
    /// temp-backed decrypt ([allowDiskBackedDecrypt]) avoids OOM; RAM-only PDF
    /// mode must not use that path (plaintext on disk).
    const int largeFileInRamThreshold = 100 * 1024 * 1024;
    if (fileSize > largeFileInRamThreshold && allowDiskBackedDecrypt) {
      log.fine(
        '[VaultAdapter.readFile] Large file ($fileSize B) → temp decrypt: $normPath',
      );
      final tempPath = await readFileToTempFile(
        filePath,
        onProgress: onProgress,
      );
      if (tempPath == null) return null;
      try {
        final f = File(tempPath);
        Uint8List decrypted = await f.readAsBytes();
        decrypted = _vaultApplyZlibIfNoteBody(decrypted, normPath);
        _putCachedRead(normPath, decrypted);
        _logPerf(
          'readFile',
          sw,
          extra: '(${decrypted.length} B, large via temp)',
        );
        return decrypted;
      } catch (e, st) {
        log.severe('Large vault read (temp) failed: $filePath', e, st);
        try {
          await File(tempPath).delete();
        } catch (_) {}
        return null;
      }
    }

    if (cipherVer == kVaultCipherGcm || cipherVer == kVaultCipherGcmChunked) {
      final decrypted = await _decryptGcmToBytes(
        physicalFile.path,
        storageId,
        ivBase64,
        cipherVer,
        applyZlib: applyZlib,
      );
      if (decrypted == null) return null;
      _putCachedRead(normPath, decrypted);
      _logPerf('readFile', sw, extra: '(${decrypted.length} bytes, gcm)');
      onProgress?.call(1);
      return decrypted;
    }

    if (_vaultUseAndroidNativeAesFileIo()) {
      try {
        final aesPlain = await _vaultCryptoChannel
            .invokeMethod<Uint8List>('decryptFileToBytesCbc', <String, dynamic>{
              'cipherPath': physicalFile.path,
              'key': _masterKeyBytes!,
              'iv': base64Decode(ivBase64),
            });
        if (aesPlain != null) {
          if (aesPlain.length >= _largeVaultPlaintextTempPersistBytes) {
            await _persistVaultAesPlainTempForReuse(
              normPath,
              aesPlain,
              allowDiskBackedDecrypt: allowDiskBackedDecrypt,
            );
          }
          final decrypted = applyZlib
              ? await vaultWorkerRun(vaultZlibDecodeBestEffort, aesPlain)
              : aesPlain;
          _putCachedRead(normPath, decrypted);
          _logPerf(
            'readFile',
            sw,
            extra: '(${decrypted.length} bytes, native-cbc)',
          );
          onProgress?.call(1);
          return decrypted;
        }
      } catch (e, st) {
        log.warning('Vault native CBC bytes decrypt failed', e, st);
      }
    }

    final numWorkers = _decryptWorkerCountForLength(fileSize);
    int workerChunkSize = (fileSize / numWorkers).ceil();
    workerChunkSize = ((workerChunkSize + 15) ~/ 16) * 16;

    final futures = <Future<TransferableTypedData>>[];
    for (int i = 0; i < numWorkers; i++) {
      final startOffset = i * workerChunkSize;
      if (startOffset >= fileSize) break;
      final endOffset = min(startOffset + workerChunkSize, fileSize);
      final isLast = endOffset == fileSize;

      futures.add(
        vaultWorkerRun(
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
    final joined = await vaultWorkerRun(
      vaultIsolateJoinAndMaybeZlib,
      VaultJoinDecryptArgs(chunks: chunks, applyZlib: applyZlib),
    );
    final decrypted = joined.materialize().asUint8List();
    if (!applyZlib &&
        decrypted.length >= _largeVaultPlaintextTempPersistBytes) {
      await _persistVaultAesPlainTempForReuse(
        normPath,
        decrypted,
        allowDiskBackedDecrypt: allowDiskBackedDecrypt,
      );
    }

    _putCachedRead(normPath, decrypted);
    _logPerf('readFile', sw, extra: '(${decrypted.length} bytes)');
    return decrypted;
  }

  Future<_VaultFileMeta?> _resolveFileMeta(String normPath) async {
    final cachedMeta = _getCachedMeta(normPath);
    if (cachedMeta != null) return cachedMeta;

    final pending = _findPendingUpdate(normPath);
    if (pending != null) {
      final meta = _VaultFileMeta(
        storageId: pending['storage_id'] as String,
        ivBase64: pending['iv'] as String? ?? '',
        cipherVer: _inferCipherVer(
          storedVer: pending['cipher_ver'] as int?,
          ivBase64: pending['iv'] as String? ?? '',
        ),
      );
      _putCachedMeta(normPath, meta);
      return meta;
    }

    final result = await _db!.query(
      'files',
      columns: ['storage_id', 'iv', 'cipher_ver'],
      where: 'path = ?',
      whereArgs: [normPath],
      limit: 1,
    );
    if (result.isEmpty) return null;
    final row = result.first;
    final ivBase64 = row['iv'] as String? ?? '';
    var cipherVer = _inferCipherVer(
      storedVer: row['cipher_ver'] as int?,
      ivBase64: ivBase64,
    );
    final storageId = row['storage_id'] as String;

    // Legacy rows may lack cipher_ver; peek on-disk magic for chunked GCM.
    if (cipherVer == kVaultCipherCbc) {
      final physical = _getPhysicalFile(storageId);
      if (physical.existsSync()) {
        final peeked = await _peekCipherVer(physical.path);
        if (peeked == kVaultCipherGcmChunked) {
          cipherVer = kVaultCipherGcmChunked;
        }
      }
    }

    final meta = _VaultFileMeta(
      storageId: storageId,
      ivBase64: ivBase64,
      cipherVer: cipherVer,
    );
    _putCachedMeta(normPath, meta);
    return meta;
  }

  /// Infer cipher from DB column and IV length (12 → GCM, 16 → CBC, empty → chunked/CBC).
  int _inferCipherVer({required int? storedVer, required String ivBase64}) {
    if (storedVer == kVaultCipherGcm || storedVer == kVaultCipherGcmChunked) {
      return storedVer!;
    }
    if (storedVer == kVaultCipherCbc || storedVer == null) {
      if (ivBase64.isEmpty) return kVaultCipherCbc;
      try {
        final iv = base64Decode(ivBase64);
        if (iv.length == kVaultGcmNonceBytes) return kVaultCipherGcm;
        if (iv.length == 16) return kVaultCipherCbc;
      } catch (_) {}
    }
    return storedVer ?? kVaultCipherCbc;
  }

  Future<int> _peekCipherVer(String cipherPath) async {
    if (_vaultUseAndroidNativeAesFileIo()) {
      try {
        final ver = await _vaultCryptoChannel.invokeMethod<int>(
          'peekCipherVer',
          <String, dynamic>{'cipherPath': cipherPath},
        );
        return ver ?? 0;
      } catch (_) {}
    }
    try {
      final raf = File(cipherPath).openSync(mode: FileMode.read);
      try {
        final magic = raf.readSync(4);
        if (magic.length == 4 &&
            magic[0] == 0x53 &&
            magic[1] == 0x42 &&
            magic[2] == 0x56 &&
            magic[3] == 0x32) {
          final ver = raf.readByteSync();
          if (ver == 2) return kVaultCipherGcmChunked;
        }
      } finally {
        raf.closeSync();
      }
    } catch (_) {}
    return 0;
  }

  Future<Uint8List?> _decryptGcmToBytes(
    String cipherPath,
    String storageId,
    String nonceBase64,
    int cipherVer, {
    required bool applyZlib,
  }) async {
    if (_vaultUseAndroidNativeAesFileIo()) {
      try {
        final plain = await _vaultCryptoChannel.invokeMethod<Uint8List>(
          'decryptFileToBytesGcmZlib',
          <String, dynamic>{
            'cipherPath': cipherPath,
            'key': _masterKeyBytes!,
            'nonce': nonceBase64.isEmpty ? null : base64Decode(nonceBase64),
            'cipherVer': cipherVer,
            'aadPrefix': Uint8List.fromList(utf8.encode(storageId)),
            'inflateZlib': applyZlib,
          },
        );
        return plain;
      } catch (e, st) {
        log.warning('Native GCM+zlib decrypt failed; trying Dart', e, st);
      }
    }

    try {
      final ttd = await vaultWorkerRun(
        vaultIsolateDecryptGcm,
        VaultDecryptGcmArgs(
          storagePath: cipherPath,
          keyBytes: _masterKeyBytes!,
          nonceBase64: nonceBase64,
          cipherVer: cipherVer,
          storageId: storageId,
          applyZlib: applyZlib,
        ),
      );
      return ttd.materialize().asUint8List();
    } catch (e, st) {
      log.severe('GCM decrypt failed', e, st);
      return null;
    }
  }

  Future<String?> readFileToTempFile(
    String filePath, {
    void Function(double)? onProgress,
  }) async {
    if (!_isUnlocked || _db == null || _masterKeyBytes == null) return null;

    final normPath = _normalizePath(filePath);

    // Defense in depth: never create/reuse plaintext temps under RAM-only.
    // Callers should gate via FileManager; this blocks direct VaultAdapter use.
    if (!vaultPathAllowsDiskBackedDecrypt(normPath)) {
      _invalidateDecryptedTempFile(normPath);
      return null;
    }

    final reused = _decryptedTempFileByVaultPath[normPath];
    if (reused != null) {
      try {
        if (File(reused).existsSync()) {
          onProgress?.call(1);
          return reused;
        }
      } catch (_) {}
      _decryptedTempFileByVaultPath.remove(normPath);
    }

    return _readFileToTempFileInflight.putIfAbsent(normPath, () {
      final done = _readFileToTempFileBody(
        normPath,
        filePath,
        onProgress: onProgress,
      );
      unawaited(
        done.whenComplete(() {
          _readFileToTempFileInflight.remove(normPath);
        }),
      );
      return done;
    });
  }

  Future<String?> _readFileToTempFileBody(
    String normPath,
    String filePath, {
    void Function(double)? onProgress,
  }) async {
    try {
      final meta = await _resolveFileMeta(normPath);
      if (meta == null) return null;
      final storageId = meta.storageId;
      final ivBase64 = meta.ivBase64;
      final cipherVer = meta.cipherVer;
      final sz = await getFileSize(normPath);
      if (sz == null || sz <= 0) return null;

      final physicalFile = _getPhysicalFile(storageId);
      if (!physicalFile.existsSync()) return null;

      final tempDir = await getTemporaryDirectory();
      final finalTempPath = p.join(
        tempDir.path,
        'vault_${const Uuid().v4()}.tmp',
      );

      final fileSize = physicalFile.lengthSync();
      onProgress?.call(0);

      if (cipherVer == kVaultCipherGcm || cipherVer == kVaultCipherGcmChunked) {
        final perfGcm = PerfTiming.start(
          'vault.readFileToTempFile.gcm',
          fields: {'cipherBytes': fileSize, 'cipherVer': cipherVer},
        );
        try {
          if (_vaultUseAndroidNativeAesFileIo()) {
            if (cipherVer == kVaultCipherGcmChunked) {
              await _vaultCryptoChannel.invokeMethod<void>(
                'decryptFileGcmChunked',
                <String, dynamic>{
                  'cipherPath': physicalFile.path,
                  'destPath': finalTempPath,
                  'key': _masterKeyBytes!,
                  'aadPrefix': Uint8List.fromList(utf8.encode(storageId)),
                },
              );
            } else {
              await _vaultCryptoChannel
                  .invokeMethod<void>('decryptFileGcm', <String, dynamic>{
                    'cipherPath': physicalFile.path,
                    'destPath': finalTempPath,
                    'key': _masterKeyBytes!,
                    'nonce': base64Decode(ivBase64),
                  });
            }
            onProgress?.call(1);
            _decryptedTempFileByVaultPath[normPath] = finalTempPath;
            return finalTempPath;
          }
          final plain = await _decryptGcmToBytes(
            physicalFile.path,
            storageId,
            ivBase64,
            cipherVer,
            applyZlib: false,
          );
          if (plain == null) return null;
          await File(finalTempPath).writeAsBytes(plain, flush: true);
          onProgress?.call(1);
          _decryptedTempFileByVaultPath[normPath] = finalTempPath;
          return finalTempPath;
        } catch (e, st) {
          log.warning('GCM temp decrypt failed', e, st);
          try {
            File(finalTempPath).deleteSync();
          } catch (_) {}
          return null;
        } finally {
          perfGcm?.end();
        }
      }

      if (_vaultUseAndroidNativeAesFileIo()) {
        final perfNative = PerfTiming.start(
          'vault.readFileToTempFile.native',
          fields: {'cipherBytes': fileSize},
        );
        try {
          final ok = await _tryVaultAndroidNativeDecryptFileToPath(
            physicalFile.path,
            finalTempPath,
            ivBase64,
          );
          if (ok) {
            onProgress?.call(1);
            _decryptedTempFileByVaultPath[normPath] = finalTempPath;
            return finalTempPath;
          }
        } finally {
          perfNative?.end();
        }
      }
      try {
        final useParallel =
            fileSize >= _parallelTempDecryptMinBytes &&
            fileSize <= _parallelTempDecryptMaxBytes;

        if (!useParallel) {
          /// Tiny files (<2 MiB) or ciphertext larger than [_parallelTempDecryptMaxBytes]:
          /// one isolate streams decrypt to the temp path.
          final perf = PerfTiming.start(
            'vault.readFileToTempFile.stream',
            fields: {'cipherBytes': fileSize},
          );
          try {
            await vaultWorkerRun(
              _isolateDecryptChunkToFile,
              _DecryptChunkToFilePayload(
                physicalFile.path,
                ivBase64,
                _masterKeyBytes!,
                finalTempPath,
                0,
                fileSize,
                true,
              ),
            );
          } finally {
            perf?.end();
          }
        } else {
          /// Parallel shard decrypt (full wave), then sequential write. Matches
          /// large textbook PDFs that would otherwise spend ~10s+ on streaming AES.
          final perf = PerfTiming.start(
            'vault.readFileToTempFile.parallel',
            fields: {'cipherBytes': fileSize},
          );
          try {
            final numWorkers = _decryptWorkerCountForLength(fileSize);
            var workerChunkSize = (fileSize / numWorkers).ceil();
            workerChunkSize = ((workerChunkSize + 15) ~/ 16) * 16;

            final ranges = <({int start, int end, bool isLast})>[];
            for (var i = 0; i < numWorkers; i++) {
              final startOffset = i * workerChunkSize;
              if (startOffset >= fileSize) break;
              final endOffset = min(startOffset + workerChunkSize, fileSize);
              ranges.add((
                start: startOffset,
                end: endOffset,
                isLast: endOffset == fileSize,
              ));
            }

            if (ranges.isEmpty) {
              log.warning('readFileToTempFile: empty shard list');
              return null;
            }
            perf?.checkpoint('shards', fields: {'count': ranges.length});

            final futures = <Future<TransferableTypedData>>[];
            for (final range in ranges) {
              futures.add(
                vaultWorkerRun(
                  _isolateReadChunk,
                  _ReadChunkPayload(
                    physicalFile.path,
                    ivBase64,
                    _masterKeyBytes!,
                    range.start,
                    range.end,
                    range.isLast,
                  ),
                ),
              );
            }
            final chunks = await Future.wait(futures);

            final waf = File(finalTempPath).openSync(mode: FileMode.write);
            try {
              for (var i = 0; i < chunks.length; i++) {
                final bytes = chunks[i].materialize().asUint8List();
                if (bytes.isNotEmpty) {
                  waf.writeFromSync(bytes);
                }
                onProgress?.call(0.05 + ((i + 1) / chunks.length) * 0.95);
              }
            } finally {
              waf.closeSync();
            }
          } finally {
            perf?.end();
          }
        }
      } catch (e, s) {
        log.severe('readFileToTempFile decrypt failed: $filePath', e, s);
        try {
          await File(finalTempPath).delete();
        } catch (_) {}
        return null;
      }
      onProgress?.call(1);
      _decryptedTempFileByVaultPath[normPath] = finalTempPath;
      return finalTempPath;
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
    bool compressZlib = false,
  }) async {
    try {
      await writeFilesBulk(
        {filePath: data},
        awaitDbCommit: awaitDbCommit,
        compressZlibPaths: compressZlib ? {filePath} : const {},
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _tryVaultAndroidNativeDecryptFileToPath(
    String cipherPath,
    String destPath,
    String ivBase64,
  ) async {
    if (_masterKeyBytes == null) return false;
    Uint8List ivBytes;
    try {
      ivBytes = base64Decode(ivBase64);
    } catch (_) {
      return false;
    }
    if (ivBytes.length != 16) return false;

    try {
      await _vaultCryptoChannel
          .invokeMethod<void>('decryptFileCbc', <String, dynamic>{
            'cipherPath': cipherPath,
            'destPath': destPath,
            'key': _masterKeyBytes!,
            'iv': ivBytes,
          });
      return true;
    } on PlatformException catch (e, s) {
      log.warning('Android native vault decrypt failed: ${e.message}', e, s);
      try {
        final f = File(destPath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
      return false;
    } catch (e, s) {
      log.warning('Android native vault decrypt failed', e, s);
      try {
        final f = File(destPath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
      return false;
    }
  }

  Future<_WriteResult?> _tryVaultAndroidNativeEncryptFileFromPathGcm(
    String sourcePath,
    String normPath,
  ) async {
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw FileSystemException('Source file not found', sourcePath);
    }
    final storageId = const Uuid().v4();
    final dataDir = Directory(p.join(_storageRoot!.path, 'data'));
    if (!dataDir.existsSync()) dataDir.createSync(recursive: true);
    final prefix = storageId.substring(0, 2);
    final fileDir = Directory(p.join(dataDir.path, prefix));
    if (!fileDir.existsSync()) fileDir.createSync();
    final outPath = p.join(fileDir.path, '$storageId.enc');
    final compressZlib = _vaultAesPlaintextNeedsZlibNoteBody(normPath);

    try {
      final raw = await _vaultCryptoChannel
          .invokeMethod<Map>('encryptFileToGcmZlib', <String, dynamic>{
            'sourcePath': sourcePath,
            'destPath': outPath,
            'key': _masterKeyBytes!,
            'compressZlib': compressZlib,
            'aadPrefix': Uint8List.fromList(utf8.encode(storageId)),
          });
      if (raw == null) return null;
      final cipherVer = (raw['cipherVer'] as int?) ?? kVaultCipherGcm;
      final plainSize = (raw['plainSize'] as int?) ?? source.lengthSync();
      final nonce = raw['nonce'];
      final nonceBytes = nonce is Uint8List
          ? nonce
          : (nonce is List ? Uint8List.fromList(nonce.cast<int>()) : null);
      return _WriteResult(
        normPath,
        storageId,
        (nonceBytes != null && nonceBytes.isNotEmpty)
            ? base64Encode(nonceBytes)
            : '',
        plainSize,
        cipherVer: cipherVer,
      );
    } on PlatformException catch (e, s) {
      log.warning('Android native GCM encrypt failed: ${e.message}', e, s);
      try {
        final f = File(outPath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
      return null;
    } catch (e, s) {
      log.warning('Android native GCM encrypt failed', e, s);
      try {
        final f = File(outPath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
      return null;
    }
  }

  Future<void> writeFileFromPath(
    String sourcePath,
    String virtualPath, {
    bool awaitDbCommit = false,
  }) async {
    if (!_isUnlocked || _db == null || _masterKeyBytes == null) return;
    final normPath = _normalizePath(virtualPath);
    final leaf = normPath.split('/').last;
    
    if (normPath.contains('saber_vault') ||
        (leaf.startsWith('.saber_') && leaf != '.saber_links.json')) {
      return;
    }
    final sw = Stopwatch()..start();
    late final _WriteResult result;
    late final String perfLabel;
    if (_vaultUseAndroidNativeAesFileIo()) {
      final nativeResult = await _tryVaultAndroidNativeEncryptFileFromPathGcm(
        sourcePath,
        normPath,
      );
      if (nativeResult != null) {
        result = nativeResult;
        perfLabel = 'writeFileFromPath.nativeGcm';
      } else {
        try {
          result = await vaultWorkerRun(
            _isolateEncryptFileFromPathGcm,
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
        perfLabel = 'writeFileFromPath.isolateGcm';
      }
    } else {
      try {
        result = await vaultWorkerRun(
          _isolateEncryptFileFromPathGcm,
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
      perfLabel = 'writeFileFromPath.isolateGcm';
    }
    _logPerf(perfLabel, sw, extra: '(size=${result.size})');

    _invalidateDecryptedTempFile(result.virtualPath);

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _putCachedMeta(
      result.virtualPath,
      _VaultFileMeta(
        storageId: result.storageId,
        ivBase64: result.ivBase64,
        cipherVer: result.cipherVer,
      ),
    );
    _pendingDbUpdates.add({
      'path': result.virtualPath,
      'storage_id': result.storageId,
      'iv': result.ivBase64,
      'last_modified': timestamp,
      'size': result.size,
      'cipher_ver': result.cipherVer,
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
    Set<String> compressZlibPaths = const {},
  }) async {
    if (!_isUnlocked || _db == null || _masterKeyBytes == null) return;
    if (filesData.isEmpty) return;

    final safeFiles = <String, Uint8List>{};
    final compressNorm = <String>{};
    for (final entry in filesData.entries) {
      final normPath = _normalizePath(entry.key);
      final leaf = normPath.split('/').last;
      
      // Ignore internal vault databases, but allow link configurations (.saber_links.json)
      if (normPath.contains('saber_vault') ||
          (leaf.startsWith('.saber_') && leaf != '.saber_links.json')) {
        continue;
      }
      safeFiles[normPath] = entry.value;
      if (compressZlibPaths.contains(entry.key) ||
          compressZlibPaths.contains(normPath) ||
          _vaultAesPlaintextNeedsZlibNoteBody(normPath)) {
        // Only auto-compress note bodies when caller did not already zlib.
        if (!vaultLooksLikeZlib(entry.value)) {
          compressNorm.add(normPath);
        }
      }
    }
    if (safeFiles.isEmpty) return;

    final swTotal = Stopwatch()..start();
    PerfTiming.beginVaultAutosaveWindow();

    List<_WriteResult> results;
    final swEncrypt = Stopwatch()..start();
    try {
      results = await _encryptAndWriteBulk(safeFiles, compressNorm);
    } catch (e, s) {
      log.severe('Bulk write encrypt error', e, s);
      PerfTiming.endVaultAutosaveWindow();
      rethrow;
    }
    _logPerf(
      'writeFilesBulk.encryptWrite',
      swEncrypt,
      extra:
          '(files=${results.length}, native=${_vaultUseAndroidNativeAesFileIo()})',
    );

    final timestamp = DateTime.now().millisecondsSinceEpoch;

    for (final norm in safeFiles.keys) {
      _invalidateDecryptedTempFile(norm);
    }

    for (final entry in filesData.entries) {
      _putCachedRead(_normalizePath(entry.key), entry.value);
    }
    for (final res in results) {
      _putCachedMeta(
        res.virtualPath,
        _VaultFileMeta(
          storageId: res.storageId,
          ivBase64: res.ivBase64,
          cipherVer: res.cipherVer,
        ),
      );
      _pendingDbUpdates.add({
        'path': res.virtualPath,
        'storage_id': res.storageId,
        'iv': res.ivBase64,
        'last_modified': timestamp,
        'size': res.size,
        'cipher_ver': res.cipherVer,
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
    PerfTiming.endVaultAutosaveWindow();
  }

  Future<List<_WriteResult>> _encryptAndWriteBulk(
    Map<String, Uint8List> safeFiles,
    Set<String> compressNorm,
  ) async {
    if (_vaultUseAndroidNativeAesFileIo()) {
      try {
        return await _nativeEncryptAndWriteBulk(safeFiles, compressNorm);
      } catch (e, st) {
        log.warning('Native bulk GCM failed; Dart worker fallback', e, st);
      }
    }
    final items = safeFiles.entries
        .map(
          (e) => VaultBulkWriteItem(
            e.key,
            TransferableTypedData.fromList([e.value]),
            compressZlib: compressNorm.contains(e.key),
          ),
        )
        .toList();
    final bulkResults = await vaultWorkerRun(
      vaultIsolateEncryptAndWrite,
      VaultBulkWriteArgs(
        items: items,
        keyBytes: _masterKeyBytes!,
        storageRootPath: _storageRoot!.path,
        cipherVer: kVaultCipherGcm,
      ),
    );
    return bulkResults
        .map(
          (r) => _WriteResult(
            r.virtualPath,
            r.storageId,
            r.ivBase64,
            r.size,
            cipherVer: r.cipherVer,
          ),
        )
        .toList();
  }

  Future<List<_WriteResult>> _nativeEncryptAndWriteBulk(
    Map<String, Uint8List> safeFiles,
    Set<String> compressNorm,
  ) async {
    final results = <_WriteResult>[];
    // Large payloads: avoid MethodChannel byte copies — write temp on a worker,
    // then one native zlib+GCM path encrypt.
    const pathBridgeMinBytes = 512 * 1024;
    for (final entry in safeFiles.entries) {
      final plain = entry.value;
      final doZlib = compressNorm.contains(entry.key);
      final storageId = const Uuid().v4();
      final dataDir = Directory(p.join(_storageRoot!.path, 'data'));
      if (!dataDir.existsSync()) dataDir.createSync(recursive: true);
      final prefix = storageId.substring(0, 2);
      final fileDir = Directory(p.join(dataDir.path, prefix));
      if (!fileDir.existsSync()) fileDir.createSync();
      final outPath = p.join(fileDir.path, '$storageId.enc');
      final aadPrefix = Uint8List.fromList(utf8.encode(storageId));

      late final Map resultMap;
      if (plain.length >= pathBridgeMinBytes) {
        final tempDir = await getTemporaryDirectory();
        final tempPlain = p.join(tempDir.path, 'vault_plain_$storageId.tmp');
        await vaultWorkerRun(_isolateWriteTempBytes, <String, dynamic>{
          'path': tempPlain,
          'bytes': plain,
        });
        try {
          final raw = await _vaultCryptoChannel
              .invokeMethod<Map>('encryptFileToGcmZlib', <String, dynamic>{
                'sourcePath': tempPlain,
                'destPath': outPath,
                'key': _masterKeyBytes!,
                'compressZlib': doZlib,
                'aadPrefix': aadPrefix,
              });
          if (raw == null) {
            throw StateError('Native encryptFileToGcmZlib returned null');
          }
          resultMap = raw;
        } finally {
          try {
            File(tempPlain).deleteSync();
          } catch (_) {}
        }
      } else {
        final raw = await _vaultCryptoChannel
            .invokeMethod<Map>('encryptBytesToFileGcmZlib', <String, dynamic>{
              'destPath': outPath,
              'plaintext': plain,
              'key': _masterKeyBytes!,
              'compressZlib': doZlib,
            });
        if (raw == null) {
          throw StateError('Native encryptBytesToFileGcmZlib returned null');
        }
        resultMap = raw;
      }

      final cipherVer = (resultMap['cipherVer'] as int?) ?? kVaultCipherGcm;
      final plainSize = (resultMap['plainSize'] as int?) ?? plain.length;
      final nonce = resultMap['nonce'];
      final nonceBytes = nonce is Uint8List
          ? nonce
          : (nonce is List ? Uint8List.fromList(nonce.cast<int>()) : null);
      final ivBase64 = (nonceBytes != null && nonceBytes.isNotEmpty)
          ? base64Encode(nonceBytes)
          : '';
      results.add(
        _WriteResult(
          entry.key,
          storageId,
          ivBase64,
          plainSize,
          cipherVer: cipherVer,
        ),
      );
    }
    return results;
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
    const int batchSize = 15;

    try {
      for (var i = 0; i < updates.length; i += batchSize) {
        if (i > 0) {
          // Yield to the frame pipeline between batches so inking stays smooth.
          await SchedulerBinding.instance.scheduleTask(() {}, Priority.idle);
          await Future<void>.delayed(Duration.zero);
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

            if (FileManager.isFolderSizeTrackedFile(path)) {
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
          } else {
            final tracksCount = FileManager.isCountableFile(path);
            final tracksSize = FileManager.isFolderSizeTrackedFile(path);
            if (tracksCount) totalCountDelta += 1;
            if (!tracksCount && !tracksSize) continue;
            for (final folderPath in _getAncestorFolders(path)) {
              final key = _normalizeFolderPath(folderPath);
              if (tracksCount) {
                folderCountDeltas[key] = (folderCountDeltas[key] ?? 0) + 1;
              }
              if (tracksSize) {
                folderSizeDeltas[key] = (folderSizeDeltas[key] ?? 0) + newSize;
              }
              if (tracksCount && _folderCountCache.containsKey(key)) {
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

  static _WriteResult _isolateEncryptFileFromPathGcm(
    _EncryptFileFromPathPayload args,
  ) {
    final source = File(args.sourcePath);
    if (!source.existsSync()) {
      throw FileSystemException('Source file not found', args.sourcePath);
    }
    final plain = source.readAsBytesSync();
    final items = [
      VaultBulkWriteItem(
        args.virtualPath,
        TransferableTypedData.fromList([plain]),
      ),
    ];
    final results = vaultIsolateEncryptAndWrite(
      VaultBulkWriteArgs(
        items: items,
        keyBytes: args.keyBytes,
        storageRootPath: args.storageRootPath,
        cipherVer: kVaultCipherGcm,
      ),
    );
    final r = results.first;
    return _WriteResult(
      r.virtualPath,
      r.storageId,
      r.ivBase64,
      r.size,
      cipherVer: r.cipherVer,
    );
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

    const chunkSize = 16 * 1024 * 1024;
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
      meta ??= await _resolveFileMeta(normPath);
      if (meta == null) return 0;

      // GCM blobs are not CBC-seekable; callers should use readFileToTempFile.
      if (meta.cipherVer == kVaultCipherGcm ||
          meta.cipherVer == kVaultCipherGcmChunked) {
        return 0;
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

      final transferable = await vaultWorkerRun(
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

        final tracksCount = FileManager.isCountableFile(normPath);
        final tracksSize = FileManager.isFolderSizeTrackedFile(normPath);
        if (tracksCount || tracksSize) {
          await _updateRecursiveCounts(
            txn,
            normPath,
            tracksCount ? -1 : 0,
            tracksSize ? -size : 0,
          );
        }
        if (tracksCount) {
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
        size INTEGER DEFAULT 0,
        cipher_ver INTEGER DEFAULT 0
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

  Timer? _gcmMigrationTimer;
  bool _gcmMigrationRunning = false;
  int _physicalBackupQuiesceDepth = 0;

  /// True while a physical vault snapshot (incremental backup) is in progress.
  bool get isPhysicalBackupQuiesced => _physicalBackupQuiesceDepth > 0;

  /// Flush pending index writes and pause idle CBC→GCM migration so a physical
  /// on-disk snapshot stays consistent without fully locking the vault.
  Future<void> beginPhysicalBackupQuiesce() async {
    _physicalBackupQuiesceDepth++;
    _gcmMigrationTimer?.cancel();
    _gcmMigrationTimer = null;
    if (_isUnlocked) {
      try {
        await _flushPendingDbUpdates();
      } catch (e, st) {
        log.warning('Flush before physical backup failed: $e', e, st);
      }
      try {
        await _db?.rawQuery('PRAGMA wal_checkpoint(FULL)');
      } catch (e, st) {
        log.fine('wal_checkpoint during backup quiesce: $e', e, st);
      }
    }
  }

  void endPhysicalBackupQuiesce() {
    _physicalBackupQuiesceDepth = max(0, _physicalBackupQuiesceDepth - 1);
    if (_physicalBackupQuiesceDepth == 0 && _isUnlocked) {
      _scheduleIdleGcmMigration();
    }
  }

  /// Idle-priority lazy migrate of legacy CBC blobs to GCM after unlock.
  void _scheduleIdleGcmMigration() {
    if (_shouldDeferIdleMigration) return;
    _gcmMigrationTimer?.cancel();
    _gcmMigrationTimer = Timer(const Duration(seconds: 8), () {
      unawaited(_idleMigrateCbcBlobsToGcm());
    });
  }

  Future<void> _idleMigrateCbcBlobsToGcm() async {
    if (!_isUnlocked ||
        _db == null ||
        _gcmMigrationRunning ||
        _shouldDeferIdleMigration) {
      return;
    }
    _gcmMigrationRunning = true;
    try {
      final rows = await _db!.query(
        'files',
        columns: ['path', 'size'],
        where: '(cipher_ver IS NULL OR cipher_ver = 0) AND size <= ?',
        whereArgs: [8 * 1024 * 1024],
        limit: 8,
      );
      for (final row in rows) {
        if (!_isUnlocked || _shouldDeferIdleMigration) break;
        final path = row['path'] as String?;
        if (path == null) continue;
        await SchedulerBinding.instance.scheduleTask(() {}, Priority.idle);
        await Future<void>.delayed(Duration.zero);
        if (_shouldDeferIdleMigration) break;
        final bytes = await readFile(path);
        if (bytes == null) continue;
        await writeFile(
          path,
          bytes,
          compressZlib: _vaultAesPlaintextNeedsZlibNoteBody(path),
        );
        log.fine('Migrated vault blob to GCM: $path');
      }
      if (_isUnlocked && !_shouldDeferIdleMigration && rows.length >= 8) {
        _scheduleIdleGcmMigration();
      }
    } catch (e, st) {
      log.warning('Idle GCM migration failed', e, st);
    } finally {
      _gcmMigrationRunning = false;
    }
  }

  Future<void> lock() async {
    _gcmMigrationTimer?.cancel();
    _gcmMigrationTimer = null;
    _detachSecurePdfPolicyListeners();

    // Mark locked immediately so GoRouter can redirect to login before
    // (potentially slow) DB flush / cleanup finishes.
    final wasUnlocked = _isUnlocked;
    _isUnlocked = false;
    if (unlockState.value || wasUnlocked) {
      unlockState.value = false;
    }

    try {
      await _close(alreadyMarkedLocked: true);
    } catch (e, st) {
      log.warning('Vault lock cleanup failed: $e', e, st);
    }
    HomeDataCache.instance.invalidate();
    ThumbnailCache.instance.clear();
    log.info('Vault locked');
  }

  Future<void> _close({bool alreadyMarkedLocked = false}) async {
    try {
      await _flushPendingDbUpdates();
    } catch (e, st) {
      log.warning('Flush before vault close failed: $e', e, st);
    }
    _dbCommitTimer?.cancel();
    try {
      await _db?.close();
    } catch (_) {}
    _db = null;
    _fileEncrypter = null;
    _clearReadCache();
    _clearMetaCache();
    _invalidateAllFolderCounts();
    if (!alreadyMarkedLocked) {
      _isUnlocked = false;
      unlockState.value = false;
    } else {
      _isUnlocked = false;
      if (unlockState.value) unlockState.value = false;
    }
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

    try {
      await _db!.rawQuery('SELECT cipher_ver FROM files LIMIT 0');
    } catch (_) {
      log.info('Migrating files table to include cipher_ver...');
      try {
        await _db!.execute(
          'ALTER TABLE files ADD COLUMN cipher_ver INTEGER DEFAULT 0',
        );
      } catch (_) {}
    }
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
        if (path == null) continue;
        if (FileManager.isCountableFile(path)) {
          count++;
        }
        if (FileManager.isFolderSizeTrackedFile(path)) {
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

  Future<Map<String, Map<String, int>>> getAllFileMetadata() async {
    if (!_isUnlocked || _db == null) return {};
    final res = await _db!.query(
      'files',
      columns: ['path', 'last_modified', 'size'],
    );
    final metadata = <String, Map<String, int>>{};
    for (final row in res) {
      metadata[row['path'] as String] = {
        'm': row['last_modified'] as int,
        's': row['size'] as int? ?? 0,
      };
    }
    for (final pending in _pendingDbUpdates) {
      metadata[pending['path'] as String] = {
        'm': pending['last_modified'] as int,
        's': pending['size'] as int? ?? 0,
      };
    }
    return metadata;
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

  /// Immediate children only (not nested), excluding thumbnail/asset sidecars.
  /// Used by the file tree so vault unlock does not materialize the whole tree.
  Future<List<String>> getDirectChildFiles(String folderPath) async {
    if (!_isUnlocked || _db == null) return [];
    final normalized = _normalizeFolderPath(folderPath);
    final res = await _db!.rawQuery(
      '''
      SELECT path FROM files
      WHERE path LIKE ? || '%'
        AND instr(substr(path, length(?) + 1), '/') = 0
        AND path NOT LIKE '%.sbn2.%'
        AND path NOT LIKE '%.sbn.%'
      ''',
      [normalized, normalized],
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

  /// Immediate child folders only (one segment under [folderPath]).
  /// Merges explicit `folders` rows with DISTINCT first-segment hints from
  /// nested files so trees stay complete even if a folder row is missing.
  Future<List<String>> getDirectChildFolders(String folderPath) async {
    if (!_isUnlocked || _db == null) return [];
    final normalized = _normalizeFolderPath(folderPath);
    final explicit = await _db!.rawQuery(
      '''
      SELECT path FROM folders
      WHERE path LIKE ? || '%'
        AND path != ?
        AND path LIKE '%/'
        AND instr(
          rtrim(substr(path, length(?) + 1), '/'),
          '/'
        ) = 0
      ''',
      [normalized, normalized, normalized],
    );
    final implied = await _db!.rawQuery(
      '''
      SELECT DISTINCT substr(
        path,
        1,
        length(?) + instr(substr(path, length(?) + 1), '/')
      ) AS path
      FROM files
      WHERE path LIKE ? || '%/%'
        AND instr(substr(path, length(?) + 1), '/') > 0
      ''',
      [normalized, normalized, normalized, normalized],
    );
    final seen = <String>{};
    final out = <String>[];
    for (final row in [...explicit, ...implied]) {
      final path = row['path'] as String?;
      if (path == null || path.isEmpty || !path.endsWith('/')) continue;
      if (VaultAdapter.hasConsecutiveDuplicateSegment(path)) continue;
      if (seen.add(path)) out.add(path);
    }
    return out;
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
      final leaf = p.split('/').last;
      
      // Ignore internal vault databases, but allow link configurations (.saber_links.json)
      if (p.contains('saber_vault') ||
          (leaf.startsWith('.saber_') && leaf != '.saber_links.json')) {
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
    for (final path in paths) {
      try {
        final data = await readFile(path);
        if (data == null) continue;

        // Ensure we treat the path as relative to documentsDirectory
        final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
        final file = File(
          p.join(FileManager.documentsDirectory, normalizedPath),
        );

        await file.parent.create(recursive: true);
        await file.writeAsBytes(data);

        await deleteFile(path);
      } catch (e) {
        log.warning('Migration failed for $path: $e');
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
        final fromTracksSize = FileManager.isFolderSizeTrackedFile(normFrom);
        final toTracksSize = FileManager.isFolderSizeTrackedFile(normTo);

        final ancestorCountDeltas = <String, int>{};
        final ancestorSizeDeltas = <String, int>{};

        if (fromCountable || fromTracksSize) {
          for (final dir in _getAncestorFolders(normFrom)) {
            if (fromCountable) {
              ancestorCountDeltas[dir] = (ancestorCountDeltas[dir] ?? 0) - 1;
            }
            if (fromTracksSize) {
              ancestorSizeDeltas[dir] = (ancestorSizeDeltas[dir] ?? 0) - size;
            }
          }
        }
        if (toCountable || toTracksSize) {
          for (final dir in _getAncestorFolders(normTo)) {
            if (toCountable) {
              ancestorCountDeltas[dir] = (ancestorCountDeltas[dir] ?? 0) + 1;
            }
            if (toTracksSize) {
              ancestorSizeDeltas[dir] = (ancestorSizeDeltas[dir] ?? 0) + size;
            }
          }
        }

        final changedAncestors = {
          ...ancestorCountDeltas.keys,
          ...ancestorSizeDeltas.keys,
        };
        for (final dir in changedAncestors) {
          final cDelta = ancestorCountDeltas[dir] ?? 0;
          final sDelta = ancestorSizeDeltas[dir] ?? 0;
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

      final movedTemp = _decryptedTempFileByVaultPath.remove(normFrom);
      if (movedTemp != null) {
        _decryptedTempFileByVaultPath[normTo] = movedTemp;
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

    final native = _vaultUseAndroidNativeAesFileIo();
    return {
      'Status': 'Unlocked',
      'Architecture': 'Hybrid FBA (Index + Encrypted Blobs)',
      'Cipher': 'AES-256-GCM (default)',
      'Blob Format': 'v2 GCM; legacy CBC readable; idle migrate',
      'Crypto Path': native
          ? 'Native Kotlin (Conscrypt/AES-GCM + zlib)'
          : 'Dart worker (PointyCastle GCM)',
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
    String password, {
    void Function(double progress, String message, {int totalNotes})?
    onProgress,
  }) async {
    final noteCountBeforeLock = _isUnlocked ? await getTotalFileCount() : 0;
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
    final noteCount = noteCountBeforeLock;

    if (onProgress != null) {
      await runMonolithBackupInIsolate(
        spawnArgs: {
          'vaultPath': _vaultPath!,
          'configPath': configFile.path,
          'dataDirPath': dataDir.path,
          'destPath': destinationPath,
          'password': password,
          'prefsJson': prefsJson,
          'docsDir': docsDir,
          'noteCount': noteCount,
        },
        onProgress: (p, m, notes) => onProgress(p, m, totalNotes: notes),
        isolateMain: monolithVaultBackupIsolateMain,
      );
    } else {
      await compute(_isolateVaultBackupTask, {
        'vaultPath': _vaultPath!,
        'configPath': configFile.path,
        'dataDirPath': dataDir.path,
        'destPath': destinationPath,
        'password': password,
        'prefsJson': prefsJson,
        'docsDir': docsDir,
        'noteCount': noteCount,
      });
    }

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

      final prefsFile = File(p.join(tempDir.path, '_preferences.json'));
      if (prefsFile.existsSync()) {
        final prefsJson =
            jsonDecode(await prefsFile.readAsString()) as Map<String, dynamic>;
        await BackupFormat.restoreSharedPreferences(
          prefsJson,
          exclude: _unrestorableDevicePathPrefs(prefsJson),
        );
        await prefsFile.delete();
      }

      final docDir = await FileManager.getDocumentsDirectory();
      FileManager.documentsDirectory = docDir;
      BackgroundOperationLock.configure(docDir);

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
      final oldDir = Directory(
        '$destinationRoot.restore_old_${DateTime.now().microsecondsSinceEpoch}',
      );
      var movedOld = false;
      try {
        if (destinationDir.existsSync()) {
          await destinationDir.rename(oldDir.path);
          movedOld = true;
        }
        await destinationDir.create(recursive: true);
        await _moveDirectoryContents(tempDir, destinationDir);
        if (movedOld && oldDir.existsSync()) {
          await oldDir.delete(recursive: true);
        }
      } catch (_) {
        if (destinationDir.existsSync()) {
          await destinationDir.delete(recursive: true);
        }
        if (movedOld && oldDir.existsSync()) {
          await oldDir.rename(destinationDir.path);
        }
        rethrow;
      }
    } finally {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  Set<String> _unrestorableDevicePathPrefs(Map<String, dynamic> prefs) {
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

    return vaultWorkerRun(_deriveKeyHexFromArgs, args);
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
