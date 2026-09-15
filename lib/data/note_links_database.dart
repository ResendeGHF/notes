// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:saber/data/editor/editor_core_info.dart';

class NoteLinksDatabase {
  NoteLinksDatabase._();

  static final NoteLinksDatabase instance = NoteLinksDatabase._();

  static const int _version = 2;
  static const String _table = 'note_links';
  static const int _maxInClause = 500;

  Database? _db;
  String? _dbPath;

  static String normalizePath(String path) {
    var normalized = path.replaceAll(r'\', '/').trim();
    if (normalized.isEmpty) return '/';
    normalized = p.posix.normalize(normalized);
    if (!normalized.startsWith('/')) normalized = '/$normalized';
    return normalized.replaceAll(RegExp(r'/+'), '/');
  }

  String _resolveTargetPath(String sourcePath, String targetPath) {
    final target = targetPath.trim();
    if (target.isEmpty) return '';
    if (target.startsWith('/')) return normalizePath(target);

    final sourceDir = p.posix.dirname(sourcePath);
    return normalizePath(p.posix.join(sourceDir, target));
  }

  Future<Database> _ensureOpen({required String rootDirectory}) async {
    final dir = Directory(rootDirectory);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final path = p.join(rootDirectory, '.saber_note_links.db');
    if (_db != null && _db!.isOpen && _dbPath == path) return _db!;

    if (_db != null && _db!.isOpen && _dbPath != path) {
      await _db!.close();
      _db = null;
      _dbPath = null;
    }

    _dbPath = path;
    _db = await openDatabase(
      _dbPath!,
      version: _version,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source_path TEXT NOT NULL,
            source_page_index INTEGER NOT NULL,
            source_page_id INTEGER,
            target_path TEXT NOT NULL,
            target_page_index INTEGER NOT NULL,
            label TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_note_links_source ON $_table (source_path)',
        );
        await db.execute(
          'CREATE INDEX idx_note_links_target ON $_table (target_path)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN source_page_id INTEGER',
          );
        }
      },
    );
    return _db!;
  }

  Future<void> setLinksForPath(
    String sourcePath,
    List<NoteLink> links, {
    required String rootDirectory,
  }) async {
    final db = await _ensureOpen(rootDirectory: rootDirectory);
    final source = normalizePath(sourcePath);
    await db.transaction((txn) async {
      await txn.delete(_table, where: 'source_path = ?', whereArgs: [source]);
      final seen = <String>{};
      for (final link in links) {
        final target = _resolveTargetPath(source, link.targetPath);
        if (target.isEmpty) continue;
        final label = link.label?.trim();
        final key =
            '$source|${link.sourcePageId ?? link.sourcePageIndex}|$target|${link.targetPageIndex}|${link.targetPageIndexEnd ?? -1}|${label ?? ''}';
        if (!seen.add(key)) continue;
        await txn.insert(_table, {
          'source_path': source,
          'source_page_index': link.sourcePageIndex,
          'source_page_id': link.sourcePageId,
          'target_path': target,
          'target_page_index': link.targetPageIndex,
          'label': (label == null || label.isEmpty) ? null : label,
        });
      }
    });
  }

  Future<Map<String, List<String>>> getTargetPathsForSources(
    List<String> sourcePaths, {
    required String rootDirectory,
  }) async {
    if (sourcePaths.isEmpty) return {};
    final db = await _ensureOpen(rootDirectory: rootDirectory);
    final result = <String, Set<String>>{};
    final normalized = sourcePaths.map(normalizePath).toList();
    for (final source in normalized) {
      result[source] = <String>{};
    }

    for (var i = 0; i < normalized.length; i += _maxInClause) {
      final chunk = normalized.sublist(
        i,
        i + _maxInClause > normalized.length
            ? normalized.length
            : i + _maxInClause,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery(
        'SELECT DISTINCT source_path, target_path FROM $_table WHERE source_path IN ($placeholders)',
        chunk,
      );
      for (final row in rows) {
        final source = row['source_path'] as String?;
        final target = row['target_path'] as String?;
        if (source == null || target == null) continue;
        if (result.containsKey(source)) result[source]!.add(target);
      }
    }

    return {
      for (final entry in result.entries)
        entry.key: (entry.value.toList()..sort()),
    };
  }

  Future<void> remapPath(
    String oldPath,
    String newPath, {
    required String rootDirectory,
  }) async {
    final db = await _ensureOpen(rootDirectory: rootDirectory);
    final oldNorm = normalizePath(oldPath);
    final newNorm = normalizePath(newPath);
    if (oldNorm == newNorm) return;

    await db.transaction((txn) async {
      await txn.update(
        _table,
        {'source_path': newNorm},
        where: 'source_path = ?',
        whereArgs: [oldNorm],
      );
      await txn.update(
        _table,
        {'target_path': newNorm},
        where: 'target_path = ?',
        whereArgs: [oldNorm],
      );
    });
  }

  Future<void> removePath(String path, {required String rootDirectory}) async {
    final db = await _ensureOpen(rootDirectory: rootDirectory);
    final norm = normalizePath(path);
    await db.transaction((txn) async {
      await txn.delete(_table, where: 'source_path = ?', whereArgs: [norm]);
      await txn.delete(_table, where: 'target_path = ?', whereArgs: [norm]);
    });
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _dbPath = null;
  }
}
