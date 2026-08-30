// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:saber/data/backup/backup_format.dart';
import 'package:saber/services/sba_encryption.dart';

typedef MonolithBackupProgress = void Function(
  double progress,
  String message, {
  int totalNotes,
});

/// Count note bodies included in a monolith data backup scan.
int countMonolithDataNotes(Iterable<String> relativePaths) {
  var count = 0;
  for (final rel in relativePaths) {
    if (_isNoteBodyPath(rel)) count++;
  }
  return count;
}

bool _isNoteBodyPath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.sbn2') || lower.endsWith('.sbn');
}

void _report(
  MonolithBackupProgress? onProgress,
  double progress,
  String message, {
  int totalNotes = 0,
}) {
  final label = totalNotes > 0 ? '$totalNotes notes — $message' : message;
  onProgress?.call(progress, label, totalNotes: totalNotes);
}

void _addStoredFile(ZipFileEncoder encoder, String diskPath, String archivePath) {
  // Sync streaming add — level 0 stores without deflate. Do not use the async
  // addFile() from a sync isolate worker (it was previously fire-and-forget).
  encoder.addFileSync(File(diskPath), archivePath, ZipFileEncoder.store);
}

/// Streams files into a zip on disk (store-only), then encrypts chunk-by-chunk
/// to the destination. Peak RAM is roughly one file chunk (~1 MiB), not the
/// whole archive.
bool runMonolithBackupSync({
  required String destPath,
  required String password,
  required BackupArchiveType type,
  required Iterable<_MonolithSource> sources,
  required List<int> prefsJson,
  MonolithBackupProgress? onProgress,
}) {
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final tmpZip = '$destPath.monolith_$stamp.zip';
  final tmpEnc = '$destPath.monolith_$stamp.enc';
  final encoder = ZipFileEncoder();
  final manifestFiles = <Map<String, dynamic>>[];
  final manifestDirectories = <String>{};
  var noteCount = 0;

  try {
    encoder.create(tmpZip, level: 0);

    final prefsPath = BackupFormat.preferencesPath;
    encoder.addArchiveFile(
      ArchiveFile(prefsPath, prefsJson.length, prefsJson),
    );
    manifestFiles.add(
      BackupFormat.fileEntry(path: prefsPath, bytes: prefsJson),
    );

    final fileSources = sources.where((s) => s.isFile).toList();
    final total = fileSources.isEmpty ? 1 : fileSources.length;
    noteCount = countMonolithDataNotes(
      fileSources.map((s) => s.archivePath),
    );
    var done = 0;

    _report(onProgress, 0.02, 'Preparing backup...', totalNotes: noteCount);

    for (final source in fileSources) {
      final file = File(source.diskPath);
      if (!file.existsSync()) continue;
      final stat = file.statSync();
      _addStoredFile(encoder, source.diskPath, source.archivePath);
      // Size + mtime only — hashing every byte would re-read huge PDFs into RAM.
      manifestFiles.add(<String, dynamic>{
        'path': BackupFormat.normalizeArchivePath(source.archivePath),
        'size': stat.size,
        'modified': stat.modified.millisecondsSinceEpoch,
      });
      done++;
      if (done == total || done % 4 == 0) {
        _report(
          onProgress,
          0.02 + 0.72 * (done / total),
          source.archivePath,
          totalNotes: noteCount,
        );
      }
    }

    for (final source in sources.where((s) => !s.isFile)) {
      manifestDirectories.add(source.archivePath);
    }

    final manifest = BackupFormat.createManifest(
      type: type,
      files: manifestFiles,
      directories: manifestDirectories,
    );
    final manifestJson = BackupFormat.encodeJsonFile(manifest);
    encoder.addArchiveFile(
      ArchiveFile(
        BackupFormat.manifestPath,
        manifestJson.length,
        manifestJson,
      ),
    );
    encoder.closeSync();

    if (password.isEmpty) {
      _report(onProgress, 0.92, 'Writing backup...', totalNotes: noteCount);
      final zip = File(tmpZip);
      final dest = File(destPath);
      dest.parent.createSync(recursive: true);
      if (dest.existsSync()) dest.deleteSync();
      zip.renameSync(destPath);
    } else {
      _report(
        onProgress,
        0.78,
        'Encrypting archive (streaming)...',
        totalNotes: noteCount,
      );
      SbaEncryption.encryptFile(tmpZip, tmpEnc, password);
      _report(onProgress, 0.96, 'Writing backup...', totalNotes: noteCount);
      final dest = File(destPath);
      dest.parent.createSync(recursive: true);
      if (dest.existsSync()) dest.deleteSync();
      File(tmpEnc).renameSync(destPath);
    }

    _report(onProgress, 1, 'Backup complete', totalNotes: noteCount);
    return File(destPath).existsSync();
  } finally {
    for (final path in [tmpZip, tmpEnc]) {
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }
}

class _MonolithSource {
  const _MonolithSource({
    required this.diskPath,
    required this.archivePath,
    required this.isFile,
  });

  final String diskPath;
  final String archivePath;
  final bool isFile;
}

List<_MonolithSource> monolithDataSources(String docsDirPath) {
  final docsDir = Directory(docsDirPath);
  if (!docsDir.existsSync()) return const [];
  final out = <_MonolithSource>[];
  for (final entity in docsDir.listSync(recursive: true, followLinks: false)) {
    final relative = p
        .relative(entity.path, from: docsDir.path)
        .replaceAll('\\', '/');
    if (relative.isEmpty || relative == '.') continue;
    final zipPath = p.posix.join('data', relative);
    if (entity is File) {
      out.add(
        _MonolithSource(
          diskPath: entity.path,
          archivePath: zipPath,
          isFile: true,
        ),
      );
    } else if (entity is Directory) {
      out.add(
        _MonolithSource(
          diskPath: entity.path,
          archivePath: zipPath,
          isFile: false,
        ),
      );
    }
  }
  return out;
}

List<_MonolithSource> monolithVaultSources({
  required String vaultPath,
  required String configPath,
  required String dataDirPath,
  required String docsDirPath,
}) {
  final out = <_MonolithSource>[];

  void addFile(String diskPath, String archivePath) {
    out.add(
      _MonolithSource(
        diskPath: diskPath,
        archivePath: archivePath,
        isFile: true,
      ),
    );
  }

  addFile(vaultPath, p.basename(vaultPath));
  addFile(configPath, p.basename(configPath));

  final dataDir = Directory(dataDirPath);
  if (dataDir.existsSync()) {
    final rootPath = dataDir.parent.path;
    for (final entity in dataDir.listSync(recursive: true, followLinks: false)) {
      final relative = p
          .relative(entity.path, from: rootPath)
          .replaceAll('\\', '/');
      if (entity is File) {
        addFile(entity.path, relative);
      } else if (entity is Directory) {
        out.add(
          _MonolithSource(
            diskPath: entity.path,
            archivePath: relative,
            isFile: false,
          ),
        );
      }
    }
  }

  final docsDir = Directory(docsDirPath);
  if (docsDir.existsSync()) {
    for (final entity in docsDir.listSync(recursive: false)) {
      if (entity is File) {
        final name = p.basename(entity.path);
        if (name.startsWith('.saber_')) {
          addFile(entity.path, name);
        }
      }
    }
  }
  return out;
}

/// Worker isolate entry for data monolith backup.
@pragma('vm:entry-point')
void monolithDataBackupIsolateMain(Object? message) {
  final args = Map<String, dynamic>.from(message as Map);
  final send = args['sendPort'] as SendPort;
  try {
    final docsDir = args['docsDir'] as String;
    final sources = monolithDataSources(docsDir);
    final noteCount = countMonolithDataNotes(
      sources.where((s) => s.isFile).map((s) => s.archivePath),
    );
    runMonolithBackupSync(
      destPath: args['destPath'] as String,
      password: args['password'] as String,
      type: BackupArchiveType.data,
      sources: sources,
      prefsJson: (args['prefsJson'] as List).cast<int>(),
      onProgress: (p, m, {totalNotes = 0}) {
        send.send({
          'p': p,
          'm': m,
          'notes': totalNotes > 0 ? totalNotes : noteCount,
        });
      },
    );
    send.send({'done': true});
  } catch (e) {
    send.send({'error': e.toString()});
  }
}

/// Worker isolate entry for vault monolith backup.
@pragma('vm:entry-point')
void monolithVaultBackupIsolateMain(Object? message) {
  final args = Map<String, dynamic>.from(message as Map);
  final send = args['sendPort'] as SendPort;
  try {
    final noteCount = (args['noteCount'] as num?)?.toInt() ?? 0;
    final sources = monolithVaultSources(
      vaultPath: args['vaultPath'] as String,
      configPath: args['configPath'] as String,
      dataDirPath: args['dataDirPath'] as String,
      docsDirPath: args['docsDir'] as String,
    );
    runMonolithBackupSync(
      destPath: args['destPath'] as String,
      password: args['password'] as String,
      type: BackupArchiveType.vault,
      sources: sources,
      prefsJson: (args['prefsJson'] as List).cast<int>(),
      onProgress: (p, m, {totalNotes = 0}) {
        send.send({
          'p': p,
          'm': m,
          'notes': noteCount > 0 ? noteCount : totalNotes,
        });
      },
    );
    send.send({'done': true});
  } catch (e) {
    send.send({'error': e.toString()});
  }
}

Future<void> runMonolithBackupInIsolate({
  required Map<String, dynamic> spawnArgs,
  required void Function(double progress, String message, int totalNotes)
      onProgress,
  required void Function(Object?) isolateMain,
}) async {
  final receive = ReceivePort();
  try {
    await Isolate.spawn(
      isolateMain,
      {...spawnArgs, 'sendPort': receive.sendPort},
    );
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
          notes is num ? notes.toInt() : 0,
        );
      }
    }
  } finally {
    receive.close();
  }
}
