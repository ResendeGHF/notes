// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:saber/components/home/sort_button.dart';
import 'package:saber/data/file_manager/file_manager.dart';

/// In-memory library for the Recent Notes home tab.
///
/// Every note stays in this index until a confirmed delete/rename/move.
/// Filesystem-watcher deletes are returned as [unverifiedDeletes] so the page
/// can existence-check instead of flashing the card away on a rewrite.
class RecentNotesIndex {
  RecentNotesIndex({SortOverride? sort, Iterable<NoteIndexEntry>? notes})
    : sort = sort ?? SortOverride() {
    if (notes != null) {
      for (final note in notes) {
        _byPath[note.path] = note;
      }
    }
  }

  final SortOverride sort;
  final Map<String, NoteIndexEntry> _byPath = {};

  int get length => _byPath.length;
  bool get isEmpty => _byPath.isEmpty;
  bool get isNotEmpty => _byPath.isNotEmpty;
  Iterable<String> get paths => _byPath.keys;
  bool contains(String path) => _byPath.containsKey(path);
  NoteIndexEntry? operator [](String path) => _byPath[path];

  List<NoteIndexEntry> get entries => _byPath.values.toList(growable: false);

  List<String> sortedPaths() {
    final copy = _byPath.values.toList();
    SortNotes.sortNoteIndex(copy, sort);
    return [for (final e in copy) e.path];
  }

  /// Merge a disk/vault snapshot. Local notes are never dropped unless
  /// [dropMissing] is true (pull-to-refresh / user-confirmed delete reload).
  void mergeFromDisk(
    Iterable<NoteIndexEntry> disk, {
    bool dropMissing = false,
  }) {
    if (dropMissing) {
      final keep = <String>{for (final e in disk) e.path};
      _byPath.removeWhere((path, _) => !keep.contains(path));
    }
    for (final e in disk) {
      final prev = _byPath[e.path];
      if (prev == null) {
        _byPath[e.path] = e;
        continue;
      }
      _byPath[e.path] = NoteIndexEntry(
        path: e.path,
        modifiedMillis: e.modifiedMillis >= prev.modifiedMillis
            ? e.modifiedMillis
            : prev.modifiedMillis,
        sizeBytes: e.sizeBytes > 0 ? e.sizeBytes : prev.sizeBytes,
      );
    }
  }

  void upsert(NoteIndexEntry entry) {
    _byPath[entry.path] = entry;
  }

  void remove(String path) {
    _byPath.remove(path);
  }

  /// Apply a batched stream of file events.
  ///
  /// Same-path delete+write (atomic rewrite / watcher) keeps the note.
  /// Rename/move delete the old path; the new path is upserted from the write.
  RecentNotesOpResult applyOperations(
    Iterable<FileOperation> ops, {
    int? nowMillis,
  }) {
    final writes = <String>{};
    final deletes = <String, FileRemovalCause?>{};

    for (final event in ops) {
      if (event.isThumbnail) continue;
      final path = FileManager.notePathWithoutExtension(event.filePath);
      if (path.isEmpty || !_isVisibleHomeNote(path)) continue;

      if (event.type == FileOperationType.write) {
        writes.add(path);
        deletes.remove(path);
      } else if (event.type == FileOperationType.delete) {
        if (writes.contains(path)) continue;
        deletes[path] = event.removal;
      }
    }

    final unverified = <String>{};
    final removed = <String>{};
    for (final entry in deletes.entries) {
      switch (entry.value) {
        case FileRemovalCause.deleted:
        case FileRemovalCause.renamed:
        case FileRemovalCause.moved:
          _byPath.remove(entry.key);
          removed.add(entry.key);
        case null:
          unverified.add(entry.key);
      }
    }

    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    final written = <String>{};
    for (final path in writes) {
      final prev = _byPath[path];
      final next = NoteIndexEntry(
        path: path,
        modifiedMillis: now,
        sizeBytes: prev?.sizeBytes ?? 0,
      );
      _byPath[path] = next;
      written.add(path);
    }
    return RecentNotesOpResult(
      written: written,
      removed: removed,
      unverifiedDeletes: unverified,
    );
  }

  /// Prefer peeked mtime/size without moving a note backward in time.
  void applyPeekedMeta(NoteIndexEntry peeked) {
    final prev = _byPath[peeked.path];
    if (prev == null) return;
    final merged = NoteIndexEntry(
      path: peeked.path,
      modifiedMillis: peeked.modifiedMillis >= prev.modifiedMillis
          ? peeked.modifiedMillis
          : prev.modifiedMillis,
      sizeBytes: peeked.sizeBytes > 0 ? peeked.sizeBytes : prev.sizeBytes,
    );
    if (merged.modifiedMillis == prev.modifiedMillis &&
        merged.sizeBytes == prev.sizeBytes) {
      return;
    }
    _byPath[peeked.path] = merged;
  }

  static bool _isVisibleHomeNote(String path) {
    final name = path.split('/').last;
    return name.isNotEmpty &&
        !name.startsWith('.') &&
        !name.startsWith('TmPmP_') &&
        !name.contains('.sbn2.');
  }
}

class RecentNotesOpResult {
  const RecentNotesOpResult({
    required this.written,
    required this.removed,
    required this.unverifiedDeletes,
  });

  final Set<String> written;
  final Set<String> removed;
  final Set<String> unverifiedDeletes;
}
