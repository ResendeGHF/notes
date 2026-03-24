// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:saber/data/file_manager/file_manager.dart';

class TagDatabase {
  TagDatabase._();

  static final TagDatabase instance = TagDatabase._();

  static const int _version = 1;
  static const String _table = 'note_tags';

  Database? _db;
  String? _dbPath;

  Future<Database> _ensureOpen() async {
    if (_db != null && _db!.isOpen) return _db!;

    final root = FileManager.documentsDirectory;
    final dir = Directory(root);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    _dbPath = p.join(root, '.saber_tags.db');
    _db = await openDatabase(
      _dbPath!,
      version: _version,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            note_path TEXT NOT NULL,
            tag TEXT NOT NULL,
            PRIMARY KEY (note_path, tag)
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_note_tags_tag ON $_table (tag)',
        );
        await db.execute(
          'CREATE INDEX idx_note_tags_path ON $_table (note_path)',
        );
      },
    );
    return _db!;
  }

  static String normalizePath(String path) {
    path = path.replaceAll(r'\', '/');
    if (!path.startsWith('/')) path = '/$path';
    return path;
  }

  static String _normalizePath(String path) => normalizePath(path);

  Future<List<String>> getTagsForPath(String path) async {
    final db = await _ensureOpen();
    final rows = await db.query(
      _table,
      columns: ['tag'],
      where: 'note_path = ?',
      whereArgs: [_normalizePath(path)],
    );
    return rows.map((r) => r['tag']! as String).toList()..sort();
  }

  Future<void> setTagsForPath(String path, List<String> tags) async {
    final db = await _ensureOpen();
    final norm = _normalizePath(path);
    await db.delete(_table, where: 'note_path = ?', whereArgs: [norm]);
    final normalized = tags.map((t) => t.trim().toLowerCase()).where((t) => t.isNotEmpty).toSet().toList();
    for (final tag in normalized) {
      await db.insert(_table, {'note_path': norm, 'tag': tag});
    }
  }

  static const int _maxInClause = 500;

  Future<Map<String, Set<String>>> getTagsForPaths(List<String> paths) async {
    if (paths.isEmpty) return {};
    final db = await _ensureOpen();
    final result = <String, Set<String>>{};
    for (final path in paths) result[_normalizePath(path)] = {};
    for (var i = 0; i < paths.length; i += _maxInClause) {
      final chunk = paths.sublist(i, i + _maxInClause > paths.length ? paths.length : i + _maxInClause);
      final normPaths = chunk.map(_normalizePath).toList();
      final placeholders = List.filled(normPaths.length, '?').join(',');
      final rows = await db.query(
        _table,
        columns: ['note_path', 'tag'],
        where: 'note_path IN ($placeholders)',
        whereArgs: normPaths,
      );
      for (final r in rows) {
        final path = r['note_path']! as String;
        final tag = r['tag']! as String;
        if (result.containsKey(path)) result[path]!.add(tag);
      }
    }
    return result;
  }

  Future<List<String>> mergeTagsFromNote(String path, List<String> fileTags) async {
    if (fileTags.isEmpty) return getTagsForPath(path);
    final existing = await getTagsForPath(path);
    final merged = {...existing, ...fileTags.map((t) => t.trim().toLowerCase()).where((t) => t.isNotEmpty)};
    await setTagsForPath(path, merged.toList());
    return merged.toList()..sort();
  }

  Future<void> removePath(String path) async {
    final db = await _ensureOpen();
    await db.delete(_table, where: 'note_path = ?', whereArgs: [_normalizePath(path)]);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _dbPath = null;
  }
}
