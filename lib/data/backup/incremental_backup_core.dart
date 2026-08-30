// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:saber/services/sba_encryption.dart';

/// On-disk incremental archive: `SBA_INC1` + little-endian index offset +
/// AES-256-GCM blocks (`SABER_SBA_ENC\x03`) + zlib JSON index.
const incrementalArchiveMagic = 'SBA_INC1';

final incrementalMagicBytes = utf8.encode(incrementalArchiveMagic);

/// Sidecar next to the archive so a no-op run can skip Scrypt/index I/O.
String incrementalStateCachePath(String targetPath) =>
    '$targetPath.inc_state.json';

/// Prefs that change because a backup ran — must not bust the skip cache.
const incrementalVolatilePrefKeys = {
  '/lastBackupTimestamp',
  'lastBackupTimestamp',
};

/// Fast zlib: encrypted vault blobs and notes compress poorly at default
/// level 6, and that extra CPU is what made incremental backup feel frozen.
const _fastZlibLevel = 1;

List<int> _fastZlibEncode(List<int> bytes) {
  return const ZLibEncoder().encode(bytes, level: _fastZlibLevel);
}

/// Sidecar/thumbnail/journal paths are regenerated or checkpointed separately.
bool incrementalExcludedPath(String relativePath) {
  final name = p.basename(relativePath);
  if (name.endsWith('.p')) return true;
  if (name.endsWith('.inc_state.json')) return true;
  if (name.endsWith('.idxoff')) return true;
  if (name.endsWith('-journal')) return true;
  if (name.endsWith('-wal')) return true;
  if (name.endsWith('-shm')) return true;
  return false;
}

/// Vault ciphertext and other high-entropy blobs barely shrink with zlib.
bool incrementalPayloadNeedsZlib(String relativePath) {
  final norm = relativePath.replaceAll('\\', '/').toLowerCase();
  if (norm.contains('/saber_vault/data/') ||
      norm.startsWith('saber_vault/data/')) {
    return false;
  }
  if (norm.endsWith('.enc')) return false;
  return true;
}

/// Already-encrypted vault blobs must not be AES-wrapped again — PointyCastle
/// GCM on multi‑MB PDFs made incremental backup stall for hours.
bool incrementalStoreAsRawOpaque(String relativePath) {
  final norm = relativePath.replaceAll('\\', '/').toLowerCase();
  if (norm.endsWith('.enc')) return true;
  if (norm.contains('/saber_vault/data/') ||
      norm.startsWith('saber_vault/data/')) {
    return true;
  }
  return false;
}

Uint8List _encodeIncrementalPayload(String relativePath, Uint8List data) {
  if (incrementalPayloadNeedsZlib(relativePath)) {
    return Uint8List.fromList(_fastZlibEncode(data));
  }
  return data;
}

Uint8List _decodeIncrementalPayload(Map<String, dynamic> block, Uint8List plain) {
  final compressed = (block['z'] as num?)?.toInt() ?? 1;
  if (compressed == 0) return plain;
  return Uint8List.fromList(const ZLibDecoder().decodeBytes(plain));
}

Uint8List decodeIncrementalPayload(Map<String, dynamic> block, Uint8List plain) {
  return _decodeIncrementalPayload(block, plain);
}

/// Note bodies in data mode (`.sbn2` / `.sbn`).
bool incrementalPathIsNoteBody(String relativePath) {
  final lower = relativePath.toLowerCase();
  return lower.endsWith('.sbn2') || lower.endsWith('.sbn');
}

int countIncrementalNoteBodies(Iterable<String> paths) {
  return paths.where(incrementalPathIsNoteBody).length;
}

String incrementalProgressLabel({
  required int totalNotes,
  required int fileIndex,
  required int fileTotal,
  required String path,
}) {
  final name = path.startsWith('__db__/') ? 'Databases...' : path;
  if (totalNotes <= 0) {
    return 'File $fileIndex of $fileTotal — $name';
  }
  return '$totalNotes notes — file $fileIndex of $fileTotal — $name';
}

/// True when the previous index already has this file at the same mtime+size.
/// Incremental backups skip the read/encrypt path in that case.
bool incrementalFileUnchanged(
  Map<String, dynamic>? oldEntry,
  int modifiedMillis,
  int size,
) {
  if (oldEntry == null) return false;
  final oldM = (oldEntry['m'] as num?)?.toInt();
  final oldS = (oldEntry['s'] as num?)?.toInt();
  return oldM == modifiedMillis && oldS == size;
}

String incrementalPrefsFingerprint(Map<String, dynamic> prefsMap) {
  final keys =
      prefsMap.keys
          .where((k) => !incrementalVolatilePrefKeys.contains(k))
          .toList()
        ..sort();
  final filtered = <String, dynamic>{
    for (final key in keys) key: prefsMap[key],
  };
  return sha256.convert(utf8.encode(jsonEncode(filtered))).toString();
}

bool incrementalSkipCacheMatches({
  required Map<String, dynamic> cache,
  required IncrementalBackupScan scan,
  required Map<String, Map<String, int>> extraMetadata,
  required Map<String, dynamic> prefsMap,
  required int archiveLength,
  required int archiveModifiedMillis,
}) {
  if ((cache['v'] as num?)?.toInt() != 1) return false;
  if ((cache['archiveLen'] as num?)?.toInt() != archiveLength) return false;
  if ((cache['archiveM'] as num?)?.toInt() != archiveModifiedMillis) {
    return false;
  }
  if (cache['prefs'] != incrementalPrefsFingerprint(prefsMap)) return false;

  final cachedFiles = cache['files'];
  if (cachedFiles is! Map) return false;
  final expected = <String, Map<String, int>>{
    ...scan.metadata,
    ...extraMetadata,
  };
  if (cachedFiles.length != expected.length) return false;
  for (final entry in expected.entries) {
    final raw = cachedFiles[entry.key];
    if (raw is! Map) return false;
    if ((raw['m'] as num?)?.toInt() != entry.value['m']) return false;
    if ((raw['s'] as num?)?.toInt() != entry.value['s']) return false;
  }

  final cachedFolders = cache['folders'];
  if (cachedFolders is! List) return false;
  if (cachedFolders.length != scan.folders.length) return false;
  final folderSet = scan.folders.toSet();
  for (final folder in cachedFolders) {
    if (!folderSet.contains(folder.toString())) return false;
  }
  return true;
}

class IncrementalBackupRequest {
  const IncrementalBackupRequest({
    required this.docsDir,
    required this.targetPath,
    required this.password,
    required this.prefsMap,
    this.extraDbFiles = const {},
    this.noteCount = 0,
  });

  final String docsDir;
  final String targetPath;
  final String password;
  final Map<String, dynamic> prefsMap;

  /// Archive path (`__db__/name`) → absolute disk path.
  final Map<String, String> extraDbFiles;

  /// Logical note count for progress (vault index total in vault mode).
  final int noteCount;
}

class IncrementalBackupScan {
  const IncrementalBackupScan({
    required this.files,
    required this.folders,
    required this.metadata,
  });

  final List<String> files;
  final List<String> folders;
  final Map<String, Map<String, int>> metadata;
}

class IncrementalIndexSnapshot {
  const IncrementalIndexSnapshot({
    required this.index,
    required this.indexOffset,
  });

  final Map<String, dynamic> index;
  final int indexOffset;
}

IncrementalBackupScan scanIncrementalBackupEntries({
  required String docsDir,
  String? skipAbsolutePath,
  void Function(int scanned)? onProgress,
}) {
  final dir = Directory(docsDir);
  if (!dir.existsSync()) {
    return const IncrementalBackupScan(files: [], folders: [], metadata: {});
  }
  final skip = skipAbsolutePath == null ? null : p.normalize(skipAbsolutePath);
  final files = <String>[];
  final folders = <String>[];
  final metadata = <String, Map<String, int>>{};
  var scanned = 0;
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    scanned++;
    if (onProgress != null && (scanned <= 8 || scanned % 64 == 0)) {
      onProgress(scanned);
    }
    if (skip != null && p.normalize(entity.path) == skip) continue;
    if (entity.path.endsWith('.inc_state.json')) continue;
    if (entity.path.endsWith('.idxoff')) continue;
    final rel = p.relative(entity.path, from: dir.path).replaceAll('\\', '/');
    if (rel.isEmpty || rel == '.') continue;
    if (incrementalExcludedPath(rel)) continue;
    if (entity is File) {
      final stat = entity.statSync();
      files.add(rel);
      metadata[rel] = {
        'm': stat.modified.millisecondsSinceEpoch,
        's': stat.size,
      };
    } else if (entity is Directory) {
      folders.add(rel);
    }
  }
  return IncrementalBackupScan(
    files: files,
    folders: folders,
    metadata: metadata,
  );
}

IncrementalIndexSnapshot emptyIncrementalIndex({String sourceMode = 'data'}) {
  return IncrementalIndexSnapshot(
    index: {
      'version': 2,
      'sourceMode': sourceMode,
      'files': <String, dynamic>{},
      'preferences': <String, dynamic>{},
    },
    indexOffset: 16,
  );
}

IncrementalIndexSnapshot readIncrementalIndexSync({
  required String targetPath,
  required String password,
  String sourceMode = 'data',
}) {
  final empty = emptyIncrementalIndex(sourceMode: sourceMode);
  final file = File(targetPath);
  if (!file.existsSync() || file.lengthSync() < 16) return empty;

  final fileLength = file.lengthSync();
  final currentIndexOffset = _readIndexOffset(file, fileLength);
  if (currentIndexOffset < 16 || currentIndexOffset >= fileLength) {
    return empty;
  }

  final indexLen = fileLength - currentIndexOffset;
  // Index is zlib+JSON metadata — multi‑MB "indexes" mean the header/sidecar
  // offset is wrong (classic O_APPEND never-patched-offset bug). Treat as empty
  // so the next run truncates and rebuilds instead of hanging on decrypt.
  if (indexLen > 32 * 1024 * 1024) {
    return empty;
  }

  final raf = file.openSync(mode: FileMode.read);
  try {
    final magic = raf.readSync(8);
    if (magic.length != incrementalMagicBytes.length) return empty;
    for (var i = 0; i < incrementalMagicBytes.length; i++) {
      if (magic[i] != incrementalMagicBytes[i]) return empty;
    }
    raf.setPositionSync(currentIndexOffset);
    final encryptedIndex = raf.readSync(indexLen);
    if (encryptedIndex.isEmpty) return empty;
    final decryptedIndex = SbaEncryption.decrypt(
      Uint8List.fromList(encryptedIndex),
      password,
    );
    return IncrementalIndexSnapshot(
      index:
          jsonDecode(
                utf8.decode(const ZLibDecoder().decodeBytes(decryptedIndex)),
              )
              as Map<String, dynamic>,
      indexOffset: currentIndexOffset,
    );
  } finally {
    raf.closeSync();
  }
}

void ensureIncrementalArchiveExists(String targetPath) {
  if (targetPath.trim().isEmpty) {
    throw ArgumentError('Incremental backup target path is empty.');
  }
  final file = File(targetPath);
  final parent = file.parent;
  if (parent.path.isEmpty || parent.path == file.path) {
    throw ArgumentError(
      'Incremental backup target must be a file path, not a directory: '
      '$targetPath',
    );
  }
  try {
    parent.createSync(recursive: true);
  } on FileSystemException catch (e) {
    throw FileSystemException(
      'Cannot create backup folder "${parent.path}"',
      parent.path,
      e.osError,
    );
  }

  if (file.existsSync() && file.lengthSync() >= 16) {
    try {
      final probe = file.openSync(mode: FileMode.append);
      probe.closeSync();
    } on FileSystemException catch (e) {
      throw FileSystemException(
        'Backup file is not writable: $targetPath',
        targetPath,
        e.osError,
      );
    }
    return;
  }

  try {
    if (!file.existsSync()) {
      file.createSync(recursive: false);
    }
    final raf = file.openSync(mode: FileMode.write);
    try {
      raf.writeFromSync(incrementalMagicBytes);
      final offsetData = ByteData(8)..setInt64(0, 16, Endian.little);
      raf.writeFromSync(offsetData.buffer.asUint8List());
      raf.truncateSync(16);
    } finally {
      raf.closeSync();
    }
    _writeIndexOffsetSidecar(targetPath, 16);
  } on FileSystemException catch (e) {
    throw FileSystemException(
      'Cannot create backup file at "$targetPath". '
      'Pick a public folder such as Documents or Downloads.',
      targetPath,
      e.osError,
    );
  }
}

/// Creates the `.nba` stub (magic + index offset) if missing and verifies the
/// path is writable. Call from the UI isolate before spawning backup work.
void prepareIncrementalBackupTarget(String targetPath) {
  ensureIncrementalArchiveExists(targetPath);
}

/// Sidecar next to the archive: Linux/Android `FileMode.append` uses `O_APPEND`,
/// so in-place header seeks cannot reliably patch the 8-byte index offset.
String incrementalIndexOffsetPath(String targetPath) => '$targetPath.idxoff';

void _writeIndexOffsetSidecar(String targetPath, int offset) {
  final data = ByteData(8)..setInt64(0, offset, Endian.little);
  File(incrementalIndexOffsetPath(targetPath)).writeAsBytesSync(
    data.buffer.asUint8List(),
    flush: true,
  );
}

void _patchIndexOffset(File file, int offset) {
  // Do not seek+write the archive header here. On Linux/Android,
  // FileMode.append sets O_APPEND so writes ignore seek and append 8 bytes
  // after the index, which breaks decrypt. The `.idxoff` sidecar is the
  // source of truth for the index offset.
  _writeIndexOffsetSidecar(file.path, offset);
}

int _readIndexOffset(File file, int fileLength) {
  final side = File(incrementalIndexOffsetPath(file.path));
  if (side.existsSync() && side.lengthSync() >= 8) {
    try {
      final bytes = side.readAsBytesSync();
      final offset = ByteData.sublistView(
        Uint8List.fromList(bytes),
      ).getInt64(0, Endian.little);
      if (offset >= 16 && offset < fileLength) return offset;
    } catch (_) {}
  }
  final raf = file.openSync(mode: FileMode.read);
  try {
    raf.setPositionSync(8);
    final offsetBytes = raf.readSync(8);
    if (offsetBytes.length != 8) return -1;
    return ByteData.sublistView(
      Uint8List.fromList(offsetBytes),
    ).getInt64(0, Endian.little);
  } finally {
    raf.closeSync();
  }
}

/// Shared append-only engine: one Scrypt, AES-256-GCM per changed block.
class IncrementalBackupEngine {
  IncrementalBackupEngine({
    required this.request,
    required this.onProgress,
    required this.isCancelled,
  });

  final IncrementalBackupRequest request;
  final void Function(double progress, String message) onProgress;
  final bool Function() isCancelled;

  late final File _file;
  late final int _baselineLength;
  late final int _indexOffset;
  RandomAccessFile? _raf;
  SbaEncryptSession? _session;
  late Map<String, dynamic> _oldIndexFiles;
  late Map<String, dynamic> _newIndexFiles;
  late Map<String, dynamic> _index;
  late List<String> _sourceFilesList;
  var _writePos = 0;
  var _wroteNewBlocks = false;
  var _rafOpen = false;
  var skippedUnchanged = false;
  late Map<String, Map<String, int>> _metadata;
  late List<String> _foldersList;
  late int _totalNotes;

  List<String> get sourceFiles => _sourceFilesList;
  int get totalNotes => _totalNotes;

  SbaEncryptSession _ensureSession() {
    return _session ??= SbaEncryptSession(request.password);
  }

  Map<String, Map<String, int>> _extraDbMetadata() {
    final extra = <String, Map<String, int>>{};
    for (final entry in request.extraDbFiles.entries) {
      final dbFile = File(entry.value);
      if (!dbFile.existsSync()) continue;
      final stat = dbFile.statSync();
      extra[entry.key] = {
        'm': stat.modified.millisecondsSinceEpoch,
        's': stat.size,
      };
    }
    return extra;
  }

  bool _trySkipFromCache({
    required IncrementalBackupScan scan,
    required Map<String, Map<String, int>> extraMetadata,
  }) {
    final cacheFile = File(incrementalStateCachePath(request.targetPath));
    if (!cacheFile.existsSync()) return false;
    final archive = File(request.targetPath);
    if (!archive.existsSync() || archive.lengthSync() < 16) return false;
    try {
      final cache =
          jsonDecode(cacheFile.readAsStringSync()) as Map<String, dynamic>;
      final stat = archive.statSync();
      return incrementalSkipCacheMatches(
        cache: cache,
        scan: scan,
        extraMetadata: extraMetadata,
        prefsMap: request.prefsMap,
        archiveLength: stat.size,
        archiveModifiedMillis: stat.modified.millisecondsSinceEpoch,
      );
    } catch (_) {
      return false;
    }
  }

  void _writeSkipCache() {
    try {
      final archive = File(request.targetPath);
      if (!archive.existsSync()) return;
      final stat = archive.statSync();
      File(incrementalStateCachePath(request.targetPath)).writeAsStringSync(
        jsonEncode({
          'v': 1,
          'archiveLen': stat.size,
          'archiveM': stat.modified.millisecondsSinceEpoch,
          'prefs': incrementalPrefsFingerprint(request.prefsMap),
          'files': _metadata,
          'folders': _foldersList,
        }),
      );
    } catch (_) {
      // Cache is an acceleration only.
    }
  }

  void start() {
    // Never report 0.0 — the progress dialog rounds that to a stuck "0%".
    onProgress(0.02, 'Preparing backup file...');
    ensureIncrementalArchiveExists(request.targetPath);

    _file = File(request.targetPath);
    _baselineLength = _file.lengthSync();

    onProgress(0.04, 'Scanning files...');
    final scan = scanIncrementalBackupEntries(
      docsDir: request.docsDir,
      skipAbsolutePath: request.targetPath,
      onProgress: (scanned) {
        // Keep the dial moving during a large first-time vault scan.
        final p = (0.04 + (scanned / (scanned + 200)).clamp(0.0, 1.0) * 0.04)
            .clamp(0.04, 0.08);
        onProgress(p, 'Scanning files... ($scanned)');
      },
    );
    final extraMetadata = _extraDbMetadata();
    _metadata = {...scan.metadata, ...extraMetadata};
    _sourceFilesList = [...scan.files, ...extraMetadata.keys];
    _foldersList = List<String>.from(scan.folders);
    _totalNotes = request.noteCount > 0
        ? request.noteCount
        : countIncrementalNoteBodies(scan.files);

    if (_trySkipFromCache(scan: scan, extraMetadata: extraMetadata)) {
      skippedUnchanged = true;
      onProgress(
        1,
        incrementalProgressLabel(
          totalNotes: _totalNotes,
          fileIndex: _sourceFilesList.length,
          fileTotal: _sourceFilesList.length,
          path: 'Backup complete',
        ),
      );
      return;
    }

    onProgress(0.09, 'Reading previous backup...');
    IncrementalIndexSnapshot snapshot;
    try {
      snapshot = readIncrementalIndexSync(
        targetPath: request.targetPath,
        password: request.password,
        sourceMode: request.prefsMap['__sourceMode__']?.toString() ?? 'data',
      );
    } catch (_) {
      snapshot = emptyIncrementalIndex(
        sourceMode: request.prefsMap['__sourceMode__']?.toString() ?? 'data',
      );
    }

    _index = snapshot.index;
    _indexOffset = snapshot.indexOffset < 16 ? 16 : snapshot.indexOffset;
    final prefsMap = Map<String, dynamic>.from(request.prefsMap);
    prefsMap['__folders__'] = _foldersList;
    _index['preferences'] = prefsMap;
    _index['version'] = 2;
    _index['sourceMode'] = prefsMap['__sourceMode__'];

    _oldIndexFiles = Map<String, dynamic>.from(
      (_index['files'] as Map?)?.map((k, v) => MapEntry(k.toString(), v)) ??
          const {},
    );
    _newIndexFiles = <String, dynamic>{};

    // Small files first so progress moves quickly and huge PDFs don't stall
    // the first few percent for hours.
    _sourceFilesList.sort((a, b) {
      final sa = _metadata[a]?['s'] ?? 0;
      final sb = _metadata[b]?['s'] ?? 0;
      return sa.compareTo(sb);
    });

    onProgress(
      0.10,
      incrementalProgressLabel(
        totalNotes: _totalNotes,
        fileIndex: 0,
        fileTotal: _sourceFilesList.isEmpty ? 1 : _sourceFilesList.length,
        path: 'Starting file backup...',
      ),
    );

    _raf = _file.openSync(mode: FileMode.append);
    _rafOpen = true;
    // Truncate away the old index, then seek. Without setPositionSync, the
    // fd position can stay past EOF and writeFromSync creates a sparse hole
    // — progress looks fine while the next read hangs/fails at ~0%.
    if (_raf!.lengthSync() > _indexOffset) {
      _raf!.truncateSync(_indexOffset);
    }
    _writePos = _indexOffset;
    _raf!.setPositionSync(_writePos);
  }

  void _writeBytes(List<int> bytes) {
    _raf!.setPositionSync(_writePos);
    _raf!.writeFromSync(bytes);
    _writePos += bytes.length;
  }

  /// Returns a short label for [path], or null if the file was skipped.
  String? processFile(String path) {
    final metadata = _metadata[path];
    if (metadata == null) return null;
    final modified = metadata['m'] ?? 0;
    final size = metadata['s'] ?? 0;

    final oldData = _oldIndexFiles[path];
    final oldMap = oldData is Map ? Map<String, dynamic>.from(oldData) : null;
    if (incrementalFileUnchanged(oldMap, modified, size)) {
      _newIndexFiles[path] = oldData;
      return path;
    }

    final storeRaw = incrementalStoreAsRawOpaque(path);
    if (storeRaw) {
      final diskPath = path.startsWith('__db__/')
          ? request.extraDbFiles[path]
          : p.join(request.docsDir, path);
      if (diskPath == null) return null;
      final src = File(diskPath);
      if (!src.existsSync()) return null;
      final start = _writePos;
      final rafSrc = src.openSync(mode: FileMode.read);
      try {
        const chunk = 1024 * 1024;
        while (true) {
          final bytes = rafSrc.readSync(chunk);
          if (bytes.isEmpty) break;
          _writeBytes(bytes);
        }
      } finally {
        rafSrc.closeSync();
      }
      _wroteNewBlocks = true;
      _newIndexFiles[path] = {
        'o': start,
        'l': _writePos - start,
        'm': modified,
        's': size,
        'e': 0,
        'z': 0,
      };
      return path.startsWith('__db__/') ? 'Databases...' : path;
    }

    final Uint8List data;
    if (path.startsWith('__db__/')) {
      final disk = request.extraDbFiles[path];
      if (disk == null) return null;
      data = File(disk).readAsBytesSync();
    } else {
      data = File(p.join(request.docsDir, path)).readAsBytesSync();
    }

    final payload = _encodeIncrementalPayload(path, data);
    final toWrite = _ensureSession().encrypt(payload);
    final start = _writePos;
    _writeBytes(toWrite);
    _wroteNewBlocks = true;
    _newIndexFiles[path] = {
      'o': start,
      'l': toWrite.length,
      'm': modified,
      's': size,
      if (!incrementalPayloadNeedsZlib(path)) 'z': 0,
    };
    return path.startsWith('__db__/') ? 'Databases...' : path;
  }

  bool get _fileSetUnchanged {
    if (_newIndexFiles.length != _oldIndexFiles.length) return false;
    for (final key in _newIndexFiles.keys) {
      if (!_oldIndexFiles.containsKey(key)) return false;
    }
    return true;
  }

  void finish() {
    if (skippedUnchanged) return;
    if (!_wroteNewBlocks && _fileSetUnchanged) {
      onProgress(0.98, 'Finalizing...');
      _closeRaf();
      _disposeSession();
      _writeSkipCache();
      onProgress(1, incrementalProgressLabel(
        totalNotes: _totalNotes,
        fileIndex: _sourceFilesList.length,
        fileTotal: _sourceFilesList.length,
        path: 'Backup complete',
      ));
      return;
    }
    onProgress(0.98, 'Finalizing...');
    _index['files'] = _newIndexFiles;
    final indexPlain = _fastZlibEncode(utf8.encode(jsonEncode(_index)));
    final indexEncrypted = _ensureSession().encrypt(
      Uint8List.fromList(indexPlain),
    );
    final newIndexOffset = _writePos;
    _writeBytes(indexEncrypted);
    _wroteNewBlocks = true;
    _raf!.truncateSync(_writePos);
    _closeRaf();
    _patchIndexOffset(_file, newIndexOffset);
    _disposeSession();
    _writeSkipCache();
    onProgress(1, incrementalProgressLabel(
      totalNotes: _totalNotes,
      fileIndex: _sourceFilesList.length,
      fileTotal: _sourceFilesList.length,
      path: 'Backup complete',
    ));
  }

  void abortToBaseline() {
    _closeRaf();
    if (_wroteNewBlocks &&
        _file.existsSync() &&
        _file.lengthSync() > _baselineLength) {
      final trim = _file.openSync(mode: FileMode.append);
      try {
        trim.truncateSync(_baselineLength);
      } finally {
        trim.closeSync();
      }
    }
    _disposeSession();
  }

  void dispose() {
    _closeRaf();
    _disposeSession();
  }

  void _closeRaf() {
    if (!_rafOpen) return;
    _rafOpen = false;
    _raf?.closeSync();
    _raf = null;
  }

  void _disposeSession() {
    _session?.dispose();
    _session = null;
  }
}

/// Encrypts changed files with one Scrypt + AES-256-GCM per block (unique
/// nonce). Unchanged mtime+size entries are copied from the previous index.
void runIncrementalBackupSync({
  required IncrementalBackupRequest request,
  required void Function(double progress, String message) onProgress,
  required bool Function() isCancelled,
}) {
  final engine = IncrementalBackupEngine(
    request: request,
    onProgress: onProgress,
    isCancelled: isCancelled,
  );
  engine.start();
  if (engine.skippedUnchanged) return;
  try {
    final files = engine.sourceFiles;
    final total = files.isEmpty ? 1 : files.length;
    var count = 0;
    for (final path in files) {
      if (isCancelled()) {
        engine.abortToBaseline();
        return;
      }
      try {
        engine.processFile(path);
      } catch (_) {
        // File disappeared mid-scan; skip.
      }
      count++;
      if (count == total || count % 2 == 0 || count <= 8) {
        onProgress(
          0.10 + (count / total) * 0.87,
          incrementalProgressLabel(
            totalNotes: engine.totalNotes,
            fileIndex: count,
            fileTotal: total,
            path: path,
          ),
        );
      }
    }
    if (isCancelled()) {
      engine.abortToBaseline();
      return;
    }
    engine.finish();
  } catch (_) {
    engine.dispose();
    rethrow;
  }
}

/// Same as [runIncrementalBackupSync], but yields so a main-isolate progress
/// card can paint text (no animation required).
Future<void> runIncrementalBackup({
  required IncrementalBackupRequest request,
  required void Function(double progress, String message) onProgress,
  required bool Function() isCancelled,
  bool yieldToEventLoop = false,
}) async {
  if (!yieldToEventLoop) {
    runIncrementalBackupSync(
      request: request,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    return;
  }

  final engine = IncrementalBackupEngine(
    request: request,
    onProgress: onProgress,
    isCancelled: isCancelled,
  );
  engine.start();
  if (engine.skippedUnchanged) return;
  try {
    await Future<void>.delayed(Duration.zero);
    final files = engine.sourceFiles;
    final total = files.isEmpty ? 1 : files.length;
    var count = 0;
    final yieldWatch = Stopwatch()..start();
    for (final path in files) {
      if (isCancelled()) {
        engine.abortToBaseline();
        return;
      }
      try {
        engine.processFile(path);
      } catch (_) {}
      count++;
      if (count == total || count % 2 == 0 || count <= 8) {
        onProgress(
          0.10 + (count / total) * 0.87,
          incrementalProgressLabel(
            totalNotes: engine.totalNotes,
            fileIndex: count,
            fileTotal: total,
            path: path,
          ),
        );
      }
      if (yieldWatch.elapsedMilliseconds >= 80) {
        await Future<void>.delayed(Duration.zero);
        yieldWatch.reset();
      }
    }
    if (isCancelled()) {
      engine.abortToBaseline();
      return;
    }
    engine.finish();
  } catch (_) {
    engine.dispose();
    rethrow;
  }
}

/// Public index-offset reader (prefers `.idxoff` sidecar).
int readIncrementalIndexOffset(String targetPath) {
  final file = File(targetPath);
  if (!file.existsSync()) return -1;
  return _readIndexOffset(file, file.lengthSync());
}

/// Result of [verifyIncrementalBackupSync] — dry-run without writing docs.
class IncrementalBackupVerifyResult {
  const IncrementalBackupVerifyResult({
    required this.ok,
    required this.archivePath,
    required this.archiveBytes,
    required this.indexedFileCount,
    required this.indexedFolderCount,
    required this.indexedPayloadBytes,
    required this.noteBodyCount,
    required this.hasIdxoff,
    required this.hasIncState,
    required this.sourceMode,
    required this.samplePaths,
    required this.errors,
    this.checkedFileCount = 0,
  });

  final bool ok;
  final String archivePath;
  final int archiveBytes;
  final int indexedFileCount;
  final int indexedFolderCount;
  final int indexedPayloadBytes;
  final int noteBodyCount;
  final bool hasIdxoff;
  final bool hasIncState;
  final String sourceMode;
  final List<String> samplePaths;
  final List<String> errors;
  final int checkedFileCount;

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'archivePath': archivePath,
        'archiveBytes': archiveBytes,
        'indexedFileCount': indexedFileCount,
        'indexedFolderCount': indexedFolderCount,
        'indexedPayloadBytes': indexedPayloadBytes,
        'noteBodyCount': noteBodyCount,
        'hasIdxoff': hasIdxoff,
        'hasIncState': hasIncState,
        'sourceMode': sourceMode,
        'samplePaths': samplePaths,
        'errors': errors,
        'checkedFileCount': checkedFileCount,
      };

  factory IncrementalBackupVerifyResult.fromJson(Map<String, dynamic> json) {
    return IncrementalBackupVerifyResult(
      ok: json['ok'] == true,
      archivePath: json['archivePath']?.toString() ?? '',
      archiveBytes: (json['archiveBytes'] as num?)?.toInt() ?? 0,
      indexedFileCount: (json['indexedFileCount'] as num?)?.toInt() ?? 0,
      indexedFolderCount: (json['indexedFolderCount'] as num?)?.toInt() ?? 0,
      indexedPayloadBytes: (json['indexedPayloadBytes'] as num?)?.toInt() ?? 0,
      noteBodyCount: (json['noteBodyCount'] as num?)?.toInt() ?? 0,
      hasIdxoff: json['hasIdxoff'] == true,
      hasIncState: json['hasIncState'] == true,
      sourceMode: json['sourceMode']?.toString() ?? 'data',
      samplePaths: (json['samplePaths'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      errors:
          (json['errors'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      checkedFileCount: (json['checkedFileCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Decrypts the index and every payload block without writing to documents.
/// Confirms folder/file structure is readable before a real restore.
IncrementalBackupVerifyResult verifyIncrementalBackupSync({
  required String targetPath,
  required String password,
  void Function(double progress, String message)? onProgress,
}) {
  void progress(double p, String m) => onProgress?.call(p, m);

  final errors = <String>[];
  final archive = File(targetPath);
  final hasIdxoff = File(incrementalIndexOffsetPath(targetPath)).existsSync();
  final hasIncState = File(incrementalStateCachePath(targetPath)).existsSync();

  if (!archive.existsSync()) {
    return IncrementalBackupVerifyResult(
      ok: false,
      archivePath: targetPath,
      archiveBytes: 0,
      indexedFileCount: 0,
      indexedFolderCount: 0,
      indexedPayloadBytes: 0,
      noteBodyCount: 0,
      hasIdxoff: hasIdxoff,
      hasIncState: hasIncState,
      sourceMode: 'data',
      samplePaths: const [],
      errors: ['Backup file not found.'],
    );
  }

  final archiveBytes = archive.lengthSync();
  progress(0.02, 'Checking archive header...');

  if (archiveBytes < 16) {
    return IncrementalBackupVerifyResult(
      ok: false,
      archivePath: targetPath,
      archiveBytes: archiveBytes,
      indexedFileCount: 0,
      indexedFolderCount: 0,
      indexedPayloadBytes: 0,
      noteBodyCount: 0,
      hasIdxoff: hasIdxoff,
      hasIncState: hasIncState,
      sourceMode: 'data',
      samplePaths: const [],
      errors: ['Archive is too small to be a valid incremental backup.'],
    );
  }

  if (!hasIdxoff) {
    errors.add(
      'Missing .idxoff sidecar (needed to locate the encrypted index).',
    );
  }

  late final IncrementalIndexSnapshot snapshot;
  final decryptSession = SbaDecryptSession(password);
  try {
    progress(0.08, 'Decrypting index...');
    snapshot = readIncrementalIndexSync(
      targetPath: targetPath,
      password: password,
    );
  } catch (e) {
    decryptSession.dispose();
    return IncrementalBackupVerifyResult(
      ok: false,
      archivePath: targetPath,
      archiveBytes: archiveBytes,
      indexedFileCount: 0,
      indexedFolderCount: 0,
      indexedPayloadBytes: 0,
      noteBodyCount: 0,
      hasIdxoff: hasIdxoff,
      hasIncState: hasIncState,
      sourceMode: 'data',
      samplePaths: const [],
      errors: [
        ...errors,
        'Cannot decrypt index (wrong key or corrupt archive): $e',
      ],
    );
  }

  final filesMap = Map<String, dynamic>.from(
    snapshot.index['files'] as Map? ?? {},
  );
  final prefs = Map<String, dynamic>.from(
    snapshot.index['preferences'] as Map? ?? {},
  );
  final foldersRaw = prefs['__folders__'];
  final folders = foldersRaw is List
      ? foldersRaw.map((e) => e.toString()).toList()
      : <String>[];
  final sourceMode =
      snapshot.index['sourceMode']?.toString() ??
      prefs['__sourceMode__']?.toString() ??
      'data';

  if (filesMap.isEmpty && archiveBytes > 16) {
    errors.add(
      'Index lists no files but the archive is $archiveBytes bytes — '
      'index offset may be wrong or the backup never finished.',
    );
  }

  var payloadBytes = 0;
  var noteBodies = 0;
  var checked = 0;
  final samplePaths = <String>[];
  final paths = filesMap.keys.toList()..sort();
  final total = paths.isEmpty ? 1 : paths.length;
  // Raw vault blobs can be multi‑GB; do not load them fully just to verify.
  const largeRawProbeBytes = 4 * 1024 * 1024;

  progress(0.12, 'Checking ${paths.length} indexed files...');

  final raf = archive.openSync(mode: FileMode.read);
  try {
    final magic = raf.readSync(8);
    var magicOk = magic.length == incrementalMagicBytes.length;
    if (magicOk) {
      for (var i = 0; i < incrementalMagicBytes.length; i++) {
        if (magic[i] != incrementalMagicBytes[i]) {
          magicOk = false;
          break;
        }
      }
    }
    if (!magicOk) {
      errors.add('Invalid magic (expected $incrementalArchiveMagic).');
    }

    for (var i = 0; i < paths.length; i++) {
      final path = paths[i];
      if (samplePaths.length < 12) samplePaths.add(path);
      if (incrementalPathIsNoteBody(path)) noteBodies++;

      final blockRaw = filesMap[path];
      final block = blockRaw is Map<String, dynamic>
          ? blockRaw
          : Map<String, dynamic>.from(blockRaw as Map);
      final offset = (block['o'] as num?)?.toInt();
      final length = (block['l'] as num?)?.toInt();
      final expectedSize = (block['s'] as num?)?.toInt();
      if (expectedSize != null && expectedSize > 0) {
        payloadBytes += expectedSize;
      }

      if (offset == null ||
          length == null ||
          offset < 16 ||
          length < 0 ||
          offset + length > archiveBytes) {
        errors.add('Bad block bounds for "$path" (o=$offset l=$length).');
        if (errors.length >= 25) break;
        continue;
      }

      try {
        final isRaw = (block['e'] as num?)?.toInt() == 0;
        if (isRaw) {
          if (expectedSize != null && length != expectedSize) {
            errors.add(
              'Size mismatch for "$path": block length $length, index says $expectedSize.',
            );
          } else if (length > largeRawProbeBytes) {
            // Probe head/tail only — full read would OOM on vault PDFs.
            raf.setPositionSync(offset);
            final head = raf.readSync(64);
            if (head.isEmpty) {
              errors.add('Unreadable raw block for "$path".');
            } else {
              raf.setPositionSync(offset + length - 1);
              final tail = raf.readSync(1);
              if (tail.isEmpty) {
                errors.add('Truncated raw block for "$path".');
              } else {
                checked++;
              }
            }
          } else {
            raf.setPositionSync(offset);
            final raw = Uint8List.fromList(raf.readSync(length));
            if (raw.length != length) {
              errors.add('Short read for "$path".');
            } else {
              final data = decodeIncrementalPayload(block, raw);
              if (expectedSize != null && data.length != expectedSize) {
                errors.add(
                  'Size mismatch for "$path": got ${data.length}, index says $expectedSize.',
                );
              }
              final hash = block['h'] as String?;
              if (hash != null) {
                final digest = sha256.convert(data).toString();
                if (digest != hash) {
                  errors.add('Checksum mismatch for "$path".');
                }
              }
              checked++;
            }
          }
        } else {
          raf.setPositionSync(offset);
          final encrypted = Uint8List.fromList(raf.readSync(length));
          if (encrypted.length != length) {
            errors.add('Short read for "$path".');
          } else {
            final payloadBytesRaw = decryptSession.decrypt(encrypted);
            final data = decodeIncrementalPayload(block, payloadBytesRaw);
            if (expectedSize != null && data.length != expectedSize) {
              errors.add(
                'Size mismatch for "$path": got ${data.length}, index says $expectedSize.',
              );
            }
            final hash = block['h'] as String?;
            if (hash != null) {
              final digest = sha256.convert(data).toString();
              if (digest != hash) {
                errors.add('Checksum mismatch for "$path".');
              }
            }
            checked++;
          }
        }
      } catch (e) {
        errors.add('Cannot decrypt/read "$path": $e');
        if (errors.length >= 25) {
          errors.add('… stopping after 25 errors.');
          break;
        }
      }

      if (i == paths.length - 1 || i % 4 == 0 || i < 8) {
        progress(
          0.12 + 0.86 * ((i + 1) / total),
          'Checked ${i + 1} of ${paths.length} — $path',
        );
      }
    }
  } finally {
    raf.closeSync();
    decryptSession.dispose();
  }

  progress(1, 'Verification complete');
  final success = errors.isEmpty &&
      (paths.isEmpty ? archiveBytes <= 16 : checked == paths.length);

  return IncrementalBackupVerifyResult(
    ok: success,
    archivePath: targetPath,
    archiveBytes: archiveBytes,
    indexedFileCount: paths.length,
    indexedFolderCount: folders.length,
    indexedPayloadBytes: payloadBytes,
    noteBodyCount: noteBodies,
    hasIdxoff: hasIdxoff,
    hasIncState: hasIncState,
    sourceMode: sourceMode,
    samplePaths: samplePaths,
    errors: errors,
    checkedFileCount: checked,
  );
}

/// Worker isolate entry with live progress (SendPort), matching backup.
@pragma('vm:entry-point')
void incrementalVerifyIsolateMain(Object? message) {
  final args = Map<String, dynamic>.from(message as Map);
  final send = args['sendPort'] as SendPort;
  try {
    final result = verifyIncrementalBackupSync(
      targetPath: args['targetPath'] as String,
      password: args['password'] as String,
      onProgress: (p, m) => send.send({'p': p, 'm': m}),
    );
    send.send({'done': true, 'result': result.toJson()});
  } catch (e) {
    send.send({'error': e.toString()});
  }
}

/// Legacy [compute] entry (no progress). Prefer [incrementalVerifyIsolateMain].
@pragma('vm:entry-point')
Map<String, dynamic> incrementalVerifyIsolateEntry(Map<String, dynamic> args) {
  final result = verifyIncrementalBackupSync(
    targetPath: args['targetPath'] as String,
    password: args['password'] as String,
  );
  return result.toJson();
}

/// Worker isolate entry. [args] must include a [SendPort] at `sendPort`.
@pragma('vm:entry-point')
void incrementalBackupIsolateMain(Object? message) {
  final args = Map<String, dynamic>.from(message as Map);
  final send = args['sendPort'] as SendPort;
  try {
    final extra = <String, String>{};
    final extraRaw = args['extraDbFiles'];
    if (extraRaw is Map) {
      extraRaw.forEach((k, v) {
        extra[k.toString()] = v.toString();
      });
    }
    runIncrementalBackupSync(
      request: IncrementalBackupRequest(
        docsDir: args['docsDir'] as String,
        targetPath: args['targetPath'] as String,
        password: args['password'] as String,
        prefsMap: Map<String, dynamic>.from(args['prefsMap'] as Map),
        extraDbFiles: extra,
        noteCount: (args['noteCount'] as num?)?.toInt() ?? 0,
      ),
      onProgress: (p, m) {
        // noteCount is embedded in the progress label; also send explicit
        // total when the engine has computed it (parsed from label prefix).
        final match = RegExp(r'^(\d+) notes').firstMatch(m);
        send.send({
          'p': p,
          'm': m,
          if (match != null) 'notes': int.parse(match.group(1)!),
        });
      },
      isCancelled: () => false,
    );
    send.send({'done': true});
  } catch (e) {
    send.send({'error': e.toString()});
  }
}
