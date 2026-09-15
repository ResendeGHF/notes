// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

enum BackupArchiveType {
  data('data'),
  vault('vault'),
  incremental('incremental');

  const BackupArchiveType(this.id);
  final String id;
}

abstract final class BackupFormat {
  static const manifestPath = '_backup_manifest.json';
  static const preferencesPath = '_preferences.json';
  static const version = 3;

  static Map<String, dynamic> createManifest({
    required BackupArchiveType type,
    required Iterable<Map<String, dynamic>> files,
    Iterable<String> directories = const [],
    Map<String, dynamic> extra = const {},
  }) {
    final sortedFiles = files.toList()
      ..sort((a, b) => (a['path'] as String).compareTo(b['path'] as String));
    final sortedDirs = directories.map(normalizeArchivePath).toSet().toList()
      ..sort();
    return <String, dynamic>{
      'type': type.id,
      'version': version,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'files': sortedFiles,
      'directories': sortedDirs,
      ...extra,
    };
  }

  static bool isManifestV3(Map<String, dynamic> manifest) {
    return (manifest['version'] as num?)?.toInt() == version &&
        manifest['files'] is List;
  }

  static String normalizeArchivePath(String raw) {
    var path = raw.replaceAll('\\', '/').trim();
    while (path.startsWith('./')) {
      path = path.substring(2);
    }
    if (path.startsWith('/')) {
      throw FormatException('Unsafe absolute archive path: $raw');
    }
    final parts = <String>[];
    for (final part in path.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        throw FormatException('Unsafe parent archive path: $raw');
      }
      parts.add(part);
    }
    if (parts.isEmpty) {
      throw FormatException('Empty archive path: $raw');
    }
    return parts.join('/');
  }

  static String safeJoin(String root, String rawPath) {
    final rel = normalizeArchivePath(rawPath);
    final joined = p.normalize(p.joinAll([root, ...rel.split('/')]));
    final normalizedRoot = p.normalize(root);
    if (joined != normalizedRoot && !p.isWithin(normalizedRoot, joined)) {
      throw FormatException('Archive path escapes restore root: $rawPath');
    }
    return joined;
  }

  static void validateUniquePaths(Iterable<String> paths) {
    final seen = <String>{};
    for (final path in paths) {
      final normalized = normalizeArchivePath(path);
      if (!seen.add(normalized)) {
        throw FormatException('Duplicate archive path: $normalized');
      }
    }
  }

  static String sha256Hex(List<int> bytes) {
    return sha256.convert(bytes).toString();
  }

  static Map<String, dynamic> fileEntry({
    required String path,
    required List<int> bytes,
    int? modifiedMillis,
  }) {
    return <String, dynamic>{
      'path': normalizeArchivePath(path),
      'size': bytes.length,
      'sha256': sha256Hex(bytes),
      if (modifiedMillis != null) 'modified': modifiedMillis,
    };
  }

  static Map<String, Map<String, dynamic>> manifestFileMap(
    Map<String, dynamic> manifest,
  ) {
    final files = manifest['files'];
    if (files is! List) return {};
    return {
      for (final item in files.whereType<Map>())
        if (item['path'] is String)
          normalizeArchivePath(item['path'] as String):
              Map<String, dynamic>.from(item),
    };
  }

  static void verifyFileBytes(
    String path,
    List<int> bytes,
    Map<String, dynamic> entry,
  ) {
    final expectedSize = (entry['size'] as num?)?.toInt();
    if (expectedSize != null && expectedSize != bytes.length) {
      throw StateError('Invalid backup: size mismatch for $path');
    }
    final expectedSha = entry['sha256'] as String?;
    if (expectedSha != null && expectedSha != sha256Hex(bytes)) {
      throw StateError('Invalid backup: checksum mismatch for $path');
    }
  }

  static Future<Map<String, dynamic>> readSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      final value = prefs.get(key);
      if (value != null) out[key] = value;
    }
    return out;
  }

  static Future<void> restoreSharedPreferences(
    Map<String, dynamic> values, {
    Set<String> exclude = const {},
  }) async {
    final sharedPrefs = await SharedPreferences.getInstance();
    await sharedPrefs.clear();
    for (final entry in values.entries) {
      if (exclude.contains(entry.key)) continue;
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

  static Map<String, dynamic> decodeJsonFile(Uint8List bytes) {
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  static Uint8List encodeJsonFile(Map<String, dynamic> json) {
    return Uint8List.fromList(utf8.encode(jsonEncode(json)));
  }

  /// Write [bytes] to [destPath] without destroying a previous good file on
  /// crash: write temp → flush → rename into place (with `.old` swap).
  static void writeBytesAtomically(String destPath, List<int> bytes) {
    final dest = File(destPath);
    final parent = dest.parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final tmp = File('$destPath.tmp_$stamp');
    final old = File('$destPath.old_$stamp');
    try {
      tmp.writeAsBytesSync(bytes, flush: true);
      var movedOld = false;
      if (dest.existsSync()) {
        dest.renameSync(old.path);
        movedOld = true;
      }
      try {
        tmp.renameSync(destPath);
      } catch (e) {
        if (movedOld && old.existsSync() && !dest.existsSync()) {
          old.renameSync(destPath);
        }
        rethrow;
      }
      if (old.existsSync()) {
        try {
          old.deleteSync();
        } catch (_) {}
      }
    } catch (_) {
      if (tmp.existsSync()) {
        try {
          tmp.deleteSync();
        } catch (_) {}
      }
      rethrow;
    }
  }

  static bool canRestoreDevicePath(String value) {
    if (value.isEmpty) return true;
    if (!p.isAbsolute(value)) return true;
    try {
      final type = FileSystemEntity.typeSync(value);
      if (type != FileSystemEntityType.notFound) return true;
      final parent = Directory(p.dirname(value));
      return parent.existsSync();
    } catch (_) {
      return false;
    }
  }
}
