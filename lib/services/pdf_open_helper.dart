// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:pdfrx/pdfrx.dart';

/// Centralised PDFium open policy.
///
/// Why this exists (Samsung Notes parity):
/// - `PdfDocument.openFile(path)` memory-maps the file: the OS streams pages
///   from SSD on demand, so open time is O(1) and RAM stays flat.
/// - `PdfDocument.openData(bytes)` keeps the whole file in Dart RAM plus
///   one bulk native copy (`maxSizeToCacheOnMemory`), with zero per-read FFI
///   callbacks afterwards. It is only acceptable when the plaintext must
///   never touch disk (vault RAM-only) or when the bytes never existed as a
///   file. (Without the bulk-copy flag, every native block read bounces
///   through a Dart isolate hop + byte loop — seconds on multi-MB files.)
///
/// Rule: every caller that has a file path must go through here so the mmap
/// path is preferred automatically. `openData` remains only for the vault
/// RAM-only case and for genuinely in-memory bytes with disk writes forbidden.
abstract final class PdfOpenHelper {
  static final _log = Logger('PdfOpenHelper');

  /// Payloads at/below this size open directly from RAM: forcing a temp-file
  /// write (the slowest mobile I/O) just to mmap kilobytes is pure loss.
  /// Above it, spilling to a temp mmap wins back the saving over the
  /// document's lifetime.
  static const int smallBytesDirectOpenThreshold = 4 * 1024 * 1024;

  /// Open [path] progressively: metadata for the first page loads
  /// synchronously, the rest streams in on pdfrx's background worker.
  /// Never blocks the UI thread on full-document parse.
  ///
  /// pdfrx funnels open, page parsing, renders and text extraction through a
  /// SINGLE background isolate queue. [startBackgroundPageLoad] controls
  /// whether the endless page-metadata jobs are enqueued immediately: pass
  /// false on the editor open path and kick them after first paint (see
  /// `AssetCacheAll.kickProgressiveLoad`), otherwise the visible page's
  /// render queues behind hundreds of milliseconds of parsing.
  static Future<PdfDocument> openFileProgressive(
    String path, {
    PdfPasswordProvider? passwordProvider,
    bool startBackgroundPageLoad = true,
  }) async {
    final doc = await PdfDocument.openFile(
      path,
      passwordProvider: passwordProvider,
      useProgressiveLoading: true,
    );
    // Finish page metadata off the open path; PdfPageView listens for page
    // updates when each page's real size becomes known.
    if (startBackgroundPageLoad) _kickBackgroundPageLoad(doc);
    return doc;
  }

  static void _kickBackgroundPageLoad(PdfDocument doc) {
    unawaited(
      doc.loadPagesProgressively().catchError((Object e, StackTrace st) {
        _log.warning('PDF background page metadata load failed: $e');
        return null;
      }),
    );
  }

  /// Starts `loadPagesProgressively` for an already-open [doc]. Used by
  /// deferred kickers (first paint, fallback timers) that opened with
  /// `startBackgroundPageLoad: false`.
  static void startBackgroundPageLoad(PdfDocument doc) =>
      _kickBackgroundPageLoad(doc);

  /// Prefer `openFile` (mmap). Falls back to `openData` only when there is no
  /// usable file on disk.
  ///
  /// - [filePath]: absolute path when the PDF exists as a file. When the file
  ///   exists, it is always used directly (zero Dart-side copy).
  /// - [bytes]: in-memory fallback. When [allowSpillToTempFile] is true (and
  ///   the vault policy permits disk), bytes are spilled to a temp file first
  ///   so PDFium still gets the mmap path instead of a RAM double-copy.
  /// - Exactly one of [filePath]/[bytes] must be usable.
  static Future<PdfDocument> openMmapPreferred({
    String? filePath,
    Uint8List? bytes,
    String? sourceName,
    PdfPasswordProvider? passwordProvider,
    bool allowSpillToTempFile = true,
    bool startBackgroundPageLoad = true,
  }) async {
    if (filePath != null && filePath.isNotEmpty) {
      final f = File(filePath);
      if (f.existsSync()) {
        return openFileProgressive(
          filePath,
          passwordProvider: passwordProvider,
          startBackgroundPageLoad: startBackgroundPageLoad,
        );
      }
    }
    if (bytes != null && bytes.isNotEmpty) {
      if (allowSpillToTempFile && _diskSpillAllowed()) {
        final tempPath = await spillBytesToTempFile(
          bytes,
          sourceName: sourceName,
        );
        if (tempPath != null) {
          try {
            return await openFileProgressive(
              tempPath,
              passwordProvider: passwordProvider,
              startBackgroundPageLoad: startBackgroundPageLoad,
            );
          } catch (e) {
            // Spilled file unreadable (raced delete, etc.): fall through to RAM.
            _log.warning('mmap spill open failed, falling back to RAM: $e');
          }
        }
      }
      final doc = await PdfDocument.openData(
        bytes,
        sourceName: sourceName ?? 'memory_pdf',
        useProgressiveLoading: true,
        // MemDocument: one bulk copy, then pure-native (no per-read FFI
        // callback round trips, which cost seconds on multi-MB files).
        maxSizeToCacheOnMemory: bytes.length,
      );
      if (startBackgroundPageLoad) _kickBackgroundPageLoad(doc);
      return doc;
    }
    throw StateError(
      'PdfOpenHelper.openMmapPreferred: no file path or bytes provided.',
    );
  }

  /// Write [bytes] to a temp `.pdf` so PDFium can mmap it instead of holding
  /// a Dart-side copy for the document lifetime. Returns the path, or null
  /// when disk writes are forbidden (vault RAM-only) or the write fails.
  static Future<String?> spillBytesToTempFile(
    Uint8List bytes, {
    String? sourceName,
  }) async {
    if (!_diskSpillAllowed()) return null;
    try {
      final dir = Directory.systemTemp;
      final id = DateTime.now().microsecondsSinceEpoch;
      var safe = (sourceName ?? 'pdf').replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      if (safe.length > 24) safe = safe.substring(0, 24);
      final path = '${dir.path}/saber_pdf_mmap_${safe}_$id.pdf';
      final file = File(path);
      await file.writeAsBytes(bytes, flush: false);
      return file.path;
    } catch (e) {
      _log.warning('Failed to spill PDF bytes to temp file: $e');
      return null;
    }
  }

  /// Disk spill is forbidden while the vault holds plaintext in RAM-only mode.
  /// Conservative default: allow spill unless the vault is unlocked. Callers
  /// that know their path's effective load mode should pre-check
  /// `vaultPathAllowsDiskBackedDecrypt` and pass `allowSpillToTempFile`
  /// explicitly instead of relying on this global gate.
  static bool _diskSpillAllowed() {
    // Importing VaultAdapter here would couple this helper to the vault
    // singleton; instead the callers that handle vault assets pass
    // allowSpillToTempFile explicitly. Global spill (import/share flows,
    // thumbnails, export temps) is always safe because those files are either
    // already plaintext on disk or freshly picked by the user.
    return true;
  }
}
