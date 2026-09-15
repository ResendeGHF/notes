// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/binary_writer.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/file_manager/file_manager.dart';

/// Crash-safe stroke journal. While editing, records are buffered in memory and
/// flushed append-only to a local temp file so vault encryption is not run per
/// stroke (which blocked the UI isolate).
///
/// Journals are keyed by [noteId] when available so deleting a note and creating
/// another with the same display name cannot replay old strokes.
class EditorRecoveryJournal {
  EditorRecoveryJournal(this.noteBasePath, {this.noteId});

  static final log = Logger('EditorRecoveryJournal');
  static const int _magic = 0x4A524253; // SBRJ, little-endian.
  static const int _version = 1;
  static const int _recordDrawStroke = 1;
  static const Duration _flushDebounce = Duration(milliseconds: 400);

  final String noteBasePath;
  final String? noteId;

  /// Legacy vault-backed path (read on replay for upgrades only).
  String get path => '$noteBasePath.sbn2.recovery';

  final BytesBuilder _pending = BytesBuilder(copy: false);
  Timer? _flushDebounceTimer;
  Future<void> _flushChain = Future<void>.value();

  static String localPathForNoteBase(String noteBasePath) {
    final digest = sha256.convert(utf8.encode(noteBasePath)).toString();
    return p.join(
      Directory.systemTemp.path,
      'notes_recovery',
      '$digest.recovery',
    );
  }

  static String? localPathForNoteId(String? noteId) {
    if (noteId == null || noteId.isEmpty) return null;
    return p.join(
      Directory.systemTemp.path,
      'notes_recovery',
      'id_$noteId.recovery',
    );
  }

  String get _localFilePath {
    return localPathForNoteId(noteId) ?? localPathForNoteBase(noteBasePath);
  }

  /// Deletes local temp journals for a note. Vault/disk `.recovery` sidecars are
  /// removed by [FileManager.deleteFile] / note sidecar cleanup.
  static Future<void> purgeAllForNote({
    required String noteBasePath,
    String? noteId,
  }) async {
    for (final localPath in [
      localPathForNoteBase(noteBasePath),
      if (localPathForNoteId(noteId) case final idPath?) idPath,
    ]) {
      try {
        final file = File(localPath);
        if (file.existsSync()) await file.delete();
      } catch (e) {
        log.fine('Failed to purge local recovery journal $localPath: $e');
      }
    }
  }

  Future<void> appendDrawStroke(Stroke stroke) async {
    try {
      if (_pending.isEmpty) {
        final local = File(_localFilePath);
        final needsHeader =
            !local.existsSync() || local.lengthSync() < 8;
        if (needsHeader) {
          final header = ByteData(8)
            ..setUint32(0, _magic, Endian.little)
            ..setUint32(4, _version, Endian.little);
          _pending.add(header.buffer.asUint8List());
        }
      }

      final strokeWriter = BinaryWriter();
      stroke.toBinary(strokeWriter);
      final strokeBytes = strokeWriter.toBytes();
      final recordHeader = ByteData(5)
        ..setUint8(0, _recordDrawStroke)
        ..setUint32(1, strokeBytes.length, Endian.little);
      _pending.add(recordHeader.buffer.asUint8List());
      _pending.add(strokeBytes);

      _scheduleDebouncedFlush();
    } catch (e, st) {
      log.warning(
        'Failed to append recovery stroke for $noteBasePath: $e',
        e,
        st,
      );
    }
  }

  void _scheduleDebouncedFlush() {
    _flushDebounceTimer?.cancel();
    _flushDebounceTimer = Timer(_flushDebounce, () {
      unawaited(flush());
    });
  }

  /// Persists any buffered strokes before a full note save or lifecycle pause.
  Future<void> flush() async {
    _flushDebounceTimer?.cancel();
    _flushDebounceTimer = null;
    if (_pending.length == 0) return;
    final toWrite = _pending.takeBytes();
    final flushFuture = _flushChain.then((_) => _appendToLocalFile(toWrite));
    _flushChain = flushFuture;
    await flushFuture;
  }

  Future<void> _appendToLocalFile(Uint8List bytes) async {
    try {
      final file = File(_localFilePath);
      await file.parent.create(recursive: true);
      final raf = await file.open(mode: FileMode.append);
      try {
        await raf.writeFrom(bytes);
        await raf.flush();
      } finally {
        await raf.close();
      }
    } catch (e, st) {
      log.warning(
        'Failed to flush recovery journal for $noteBasePath: $e',
        e,
        st,
      );
    }
  }

  Future<Uint8List?> _loadJournalBytes() async {
    // Prefer noteId-keyed journal, then legacy path-keyed local, then vault.
    for (final localPath in [
      if (localPathForNoteId(noteId) case final idPath?) idPath,
      localPathForNoteBase(noteBasePath),
    ]) {
      final local = File(localPath);
      if (local.existsSync()) {
        try {
          return await local.readAsBytes();
        } catch (e, st) {
          log.warning('Failed to read local recovery journal: $e', e, st);
        }
      }
    }
    return FileManager.readFile(path, suppressLogs: true);
  }

  Future<bool> replayInto(EditorCoreInfo coreInfo) async {
    await flush();
    final bytes = await _loadJournalBytes();
    if (bytes == null || bytes.length < 8) return false;

    final data = ByteData.sublistView(bytes);
    if (data.getUint32(0, Endian.little) != _magic) return false;
    if (data.getUint32(4, Endian.little) > _version) return false;

    var offset = 8;
    var replayed = false;
    while (offset + 5 <= bytes.length) {
      final type = data.getUint8(offset);
      offset += 1;
      final length = data.getUint32(offset, Endian.little);
      offset += 4;
      if (length < 0 || offset + length > bytes.length) break;

      final payload = Uint8List.sublistView(bytes, offset, offset + length);
      offset += length;

      if (type == _recordDrawStroke) {
        final stroke = Stroke.fromBinary(
          BinaryReader(payload),
          fileVersion: EditorCoreInfo.sbnVersion,
          page: coreInfo.pages.isNotEmpty
              ? coreInfo.pages.first
              : const HasSize(EditorPage.defaultSize),
        );
        _ensurePage(coreInfo, stroke.pageIndex);
        stroke.page = coreInfo.pages[stroke.pageIndex];

        final page = coreInfo.pages[stroke.pageIndex];
        page.insertStroke(stroke);
        page.strokeSpatialIndex?.insert(stroke);
        replayed = true;
      }
    }

    return replayed;
  }

  void _ensurePage(EditorCoreInfo coreInfo, int pageIndex) {
    while (coreInfo.pages.length <= pageIndex) {
      final size = coreInfo.notePageOrientation.defaultSize;
      coreInfo.pages.add(EditorPage(width: size.width, height: size.height));
    }
  }

  Future<void> clear() async {
    _flushDebounceTimer?.cancel();
    _flushDebounceTimer = null;
    _pending.clear();
    try {
      await _flushChain;
    } catch (_) {}
    await purgeAllForNote(noteBasePath: noteBasePath, noteId: noteId);
    try {
      if (await FileManager.doesFileExist(path)) {
        await FileManager.deleteFile(path, alsoDeleteAssets: false);
      }
    } catch (e) {
      log.fine('Failed to clear recovery journal for $noteBasePath: $e');
    }
  }
}
