// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:logging/logging.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:saber/services/vault_adapter.dart';

/// Encodes BGRA pixels to JPEG off the UI thread. Pixels arrive as
/// [TransferableTypedData] (zero-copy isolate handoff): a plain Uint8List
/// message would copy tens of MB twice (send + receive) and spike the heap
/// straight into OOM territory on big tiles.
Uint8List _encodeJpgIsolate(Map<String, dynamic> args) {
  final transferable = args['pixels'] as TransferableTypedData;
  final pixels = transferable.materialize().asUint8List();
  final width = args['width'] as int;
  final height = args['height'] as int;
  final quality = args['quality'] as int? ?? 72;
  final decoded = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: pixels.buffer,
    order: img.ChannelOrder.bgra,
  );
  return Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
}

/// Aggressive background tile cache (Samsung Notes parity).
///
/// Native apps feel instant because opening a file shows pre-rendered
/// low-resolution rasters immediately while the heavy engine warms up in the
/// background. This cache provides exactly that:
///
/// - First open of a page renders a ~360px-wide JPEG on pdfrx's background
///   worker (never the UI thread) and stores it under the app cache dir.
/// - Every later open loads the JPEG synchronously from disk on the main
///   thread: no PDFium init, no FFI copy, no GPU upload of a 20 MB bitmap.
/// - Vault RAM-only mode never touches disk: thumbnails stay in a bounded
///   in-memory LRU instead (plaintext must not be written to disk).
///
/// Cache key binds file identity (size + mtime) + page + width so edits and
/// rotations invalidate automatically.
abstract final class PdfPageThumbnailCache {
  static final _log = Logger('PdfPageThumbnailCache');

  static const String _dirName = 'pdf_page_thumbs';
  static const int defaultThumbWidthPx = 360;

  /// Disk budget: evict oldest-first beyond this.
  static const int maxDiskFiles = 800;
  static const int maxDiskBytes = 200 * 1024 * 1024;

  /// Memory budget for vault mode (plaintext stays in RAM only). Sized to
  /// hold several hundred small JPEG tiles so scrolling back never
  /// re-renders: tiles are ~50-150 KB each, and re-rendering on every
  /// scroll-back is exactly the "PDF takes forever to appear" loop.
  static const int maxMemoryBytes = 64 * 1024 * 1024;

  static Directory? _dir;
  static final LinkedHashMap<String, Uint8List> _memory = LinkedHashMap();
  static int _memoryBytes = 0;

  static final Map<String, Future<File?>> _inflight = {};
  static int _activeRenders = 0;
  static const int _maxConcurrentRenders = 2;

  /// Disk cache is forbidden while the vault is unlocked: thumbnails are
  /// decrypted page content, and RAM-only policy forbids plaintext on disk.
  /// (Temp-file vault mode still keeps decrypted PDFs in managed temps that
  /// are wiped on lock; thumbnails in the shared cache dir would outlive
  /// that. So: vault unlocked => memory only, always.)
  static bool get diskCacheAllowed => !VaultAdapter.isUnlocked;

  static String _fnvKey(String raw, int pageIndex, int targetWidth) {
    var hash = 0x811C9DC5;
    for (var i = 0; i < raw.length; i++) {
      hash ^= raw.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return 'v2_${hash.toRadixString(16)}_p${pageIndex}_w$targetWidth.jpg';
  }

  static String cacheKeyFor({
    required int fileSize,
    required int mtimeMs,
    required int pageIndex,
    required int targetWidth,
  }) {
    return _fnvKey(
      '$fileSize|$mtimeMs|$pageIndex|$targetWidth',
      pageIndex,
      targetWidth,
    );
  }

  /// Content-identity key: stable across rewrites/mtime bumps (unlike stat
  /// keys) because [identityHash] derives from bytes, not filesystem time.
  /// Preferred whenever the caller has asset metadata (open + import use the
  /// same stored values, so their keys agree by construction).
  static String cacheKeyForIdentity({
    required int fileSize,
    required int identityHash,
    required int pageIndex,
    required int targetWidth,
  }) {
    return _fnvKey(
      '$fileSize#$identityHash|$pageIndex|$targetWidth',
      pageIndex,
      targetWidth,
    );
  }

  /// Single source of truth for tile keys: asset identity when the caller
  /// has it (no filesystem I/O, stable across mtime churn), stat fallback
  /// otherwise. Both open-time probing and import-time generation go through
  /// here, so their keys always agree.
  static String? keyForPage({
    int? fileSize,
    int? identityHash,
    required String filePath,
    required int pageIndex,
    int targetWidth = defaultThumbWidthPx,
  }) {
    if (fileSize != null &&
        fileSize > 0 &&
        identityHash != null &&
        identityHash != 0) {
      return cacheKeyForIdentity(
        fileSize: fileSize,
        identityHash: identityHash,
        pageIndex: pageIndex,
        targetWidth: targetWidth,
      );
    }
    return cacheKeyForFile(filePath, pageIndex, targetWidth: targetWidth);
  }

  static bool _v1Purged = false;

  /// One-time purge of v1 (unprefixed) tiles: the v2 scheme never matches
  /// them, so without this they would linger to LRU pressure. Cheap (runs
  /// once per process, only lists the tile dir).
  static Future<void> _purgeV1Once() async {
    if (_v1Purged) return;
    _v1Purged = true;
    try {
      final dir = await _cacheDir();
      for (final e in dir.listSync()) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        if (name.endsWith('.jpg') && !name.startsWith('v2_')) {
          try {
            e.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Convenience key from a file on disk. Returns null when the file cannot
  /// be statted (caller should skip caching).
  static String? cacheKeyForFile(
    String filePath,
    int pageIndex, {
    int targetWidth = defaultThumbWidthPx,
  }) {
    try {
      final stat = File(filePath).statSync();
      return cacheKeyFor(
        fileSize: stat.size,
        mtimeMs: stat.modified.millisecondsSinceEpoch,
        pageIndex: pageIndex,
        targetWidth: targetWidth,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<Directory> _cacheDir() async {
    final existing = _dir;
    if (existing != null) return existing;
    // One-time v1 purge on first real cache use (never on the vault
    // memory-only path, which never touches disk).
    if (diskCacheAllowed) unawaited(_purgeV1Once());
    final base = Directory.systemTemp;
    final dir = Directory('${base.path}/$_dirName');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _dir = dir;
    return dir;
  }

  /// Synchronous disk probe for instant first-paint. No async, no I/O stall
  /// beyond a stat: call during build and show the file immediately if hit.
  static File? tryGetDiskFileSync(String cacheKey) {
    if (!diskCacheAllowed) return null;
    try {
      final dir = _dir;
      final file = File(
        dir == null
            ? '${Directory.systemTemp.path}/$_dirName/$cacheKey'
            : '${dir.path}/$cacheKey',
      );
      if (file.existsSync() && file.lengthSync() > 0) return file;
    } catch (_) {}
    return null;
  }

  static Uint8List? tryGetMemory(String cacheKey) {
    final hit = _memory[cacheKey];
    if (hit == null) return null;
    // LRU refresh.
    _memory.remove(cacheKey);
    _memory[cacheKey] = hit;
    return hit;
  }

  /// Stores externally rendered bytes (e.g. the native PdfRenderer thumbnail
  /// fast path) under [cacheKey]: memory LRU always, disk when allowed.
  /// Shared by the sidebar and the main canvas so one render serves both.
  static Future<File?> putBytes(String cacheKey, Uint8List bytes) async {
    if (bytes.isEmpty) return null;
    _putMemory(cacheKey, bytes);
    if (!diskCacheAllowed) return null;
    try {
      final dir = await _cacheDir();
      final out = File('${dir.path}/$cacheKey');
      await out.writeAsBytes(bytes, flush: false);
      unawaited(_evictIfNeeded());
      return out;
    } catch (_) {
      return tryGetDiskFileSync(cacheKey);
    }
  }

  static void _putMemory(String cacheKey, Uint8List bytes) {
    if (bytes.isEmpty) return;
    final prev = _memory.remove(cacheKey);
    if (prev != null) _memoryBytes -= prev.length;
    while (_memory.isNotEmpty && _memoryBytes + bytes.length > maxMemoryBytes) {
      final first = _memory.keys.first;
      _memoryBytes -= _memory.remove(first)!.length;
    }
    _memory[cacheKey] = bytes;
    _memoryBytes += bytes.length;
  }

  /// Render [pageIndex] of [doc] at [targetWidth] px wide (aspect-preserved)
  /// and cache the JPEG. Returns the cached file, or null in memory-only
  /// mode (bytes are kept in the memory LRU; use [tryGetMemory]).
  ///
  /// The heavy work (PDFium render) already runs on pdfrx's background
  /// worker; JPEG encoding is pushed to a `compute` isolate. Never call with
  /// a large [targetWidth]: this is the low-res placeholder path, not the
  /// full-page renderer.
  static Future<File?> getOrRender({
    required PdfDocument doc,
    required int pageIndex,
    required String cacheKey,
    int targetWidth = defaultThumbWidthPx,
    int jpegQuality = 72,
    bool Function()? stillNeeded,
  }) {
    final existing = _inflight[cacheKey];
    if (existing != null) return existing;
    final fut = _getOrRenderInner(
      doc: doc,
      pageIndex: pageIndex,
      cacheKey: cacheKey,
      targetWidth: targetWidth,
      jpegQuality: jpegQuality,
      stillNeeded: stillNeeded,
    );
    _inflight[cacheKey] = fut;
    fut.whenComplete(() {
      if (identical(_inflight[cacheKey], fut)) _inflight.remove(cacheKey);
    });
    return fut;
  }

  static Future<File?> _getOrRenderInner({
    required PdfDocument doc,
    required int pageIndex,
    required String cacheKey,
    required int targetWidth,
    required int jpegQuality,
    bool Function()? stillNeeded,
  }) async {
    if (tryGetMemory(cacheKey) != null && !diskCacheAllowed) {
      return null;
    }
    if (diskCacheAllowed) {
      final hit = tryGetDiskFileSync(cacheKey);
      if (hit != null) return hit;
    }
    while (_activeRenders >= _maxConcurrentRenders) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    _activeRenders++;
    try {
      if (pageIndex < 0 || pageIndex >= doc.pages.length) return null;
      // ACTIVE parse starting at our page: PdfPage.ensureLoaded() is purely
      // passive (it only waits for someone else to parse), so without this a
      // far page stalls here until the paced background streamer reaches it
      // (~seconds on big docs). Parsing starts AT the requested page and
      // stops as soon as it is loaded; the post-paint kick streams the rest.
      if (!doc.pages[pageIndex].isLoaded) {
        try {
          await doc.loadPagesProgressively(
            startPageNumber: pageIndex + 1,
            onPageLoadProgress: (loaded, total, data) {
              if (stillNeeded != null && !stillNeeded()) return false;
              try {
                if (pageIndex < 0 || pageIndex >= doc.pages.length) {
                  return false;
                }
                if (doc.pages[pageIndex].isLoaded) return false;
              } catch (_) {
                return false;
              }
              return true;
            },
          );
        } catch (_) {
          // Fall through to the passive wait below (best effort).
        }
        // Superseded while parsing: skip the render entirely.
        if (stillNeeded != null && !stillNeeded()) {
          return diskCacheAllowed ? tryGetDiskFileSync(cacheKey) : null;
        }
        try {
          // Resolves immediately now that our page parsed (timeout guards a
          // missed status race so a tile never hangs forever).
          await doc.pages[pageIndex].ensureLoaded().timeout(
            const Duration(seconds: 10),
          );
        } catch (_) {
          return null;
        }
      }
      // Re-fetch: progressive loading may replace the page instance when it
      // becomes loaded; rendering a stale instance can produce a blank tile.
      final page = doc.pages[pageIndex];
      final aspect = page.height <= 0 ? 1.0 : page.width / page.height;
      final w = targetWidth.clamp(96, 1440);
      final h = (w / (aspect <= 0 ? 1.0 : aspect)).round().clamp(96, 1440);
      final rendered = await page.render(
        fullWidth: w.toDouble(),
        fullHeight: h.toDouble(),
        backgroundColor: 0xffffffff,
      );
      if (rendered == null) return null;
      // Superseded while rendering (retile moved on): skip the JPEG
      // encode + disk write entirely instead of caching a dead tile.
      if (stillNeeded != null && !stillNeeded()) {
        rendered.dispose();
        return diskCacheAllowed ? tryGetDiskFileSync(cacheKey) : null;
      }
      try {
        // Copy out of the native malloc buffer before isolate transfer and
        // before dispose: the view is only valid until dispose(). Single
        // copy; the isolate handoff itself is zero-copy (transferable).
        final pixels = Uint8List.fromList(rendered.pixels);
        final rw = rendered.width;
        final rh = rendered.height;
        rendered.dispose();
        final jpg = await compute(_encodeJpgIsolate, {
          'pixels': TransferableTypedData.fromList([pixels]),
          'width': rw,
          'height': rh,
          'quality': jpegQuality,
        });
        if (jpg.isEmpty) return null;
        _putMemory(cacheKey, jpg);
        if (!diskCacheAllowed) return null;
        final dir = await _cacheDir();
        final out = File('${dir.path}/$cacheKey');
        await out.writeAsBytes(jpg, flush: false);
        unawaited(_evictIfNeeded());
        return out;
      } catch (e) {
        _log.warning('PDF thumb render failed p$pageIndex: $e');
        try {
          rendered.dispose();
        } catch (_) {}
        return diskCacheAllowed ? tryGetDiskFileSync(cacheKey) : null;
      }
    } catch (e) {
      _log.warning('PDF thumb render failed p$pageIndex: $e');
      return null;
    } finally {
      _activeRenders--;
    }
  }

  /// Fire-and-forget warmup: render [pageIndices] at placeholder resolution
  /// so scrolling/returning feels instant. Bounded concurrency, low priority
  /// gaps between pages, silent on failure.
  static void prefetch({
    required PdfDocument doc,
    required List<int> pageIndices,
    required String? Function(int pageIndex) cacheKeyForPage,
    int targetWidth = defaultThumbWidthPx,
    int jpegQuality = 75,
  }) {
    if (pageIndices.isEmpty) return;
      unawaited(
      () async {
        for (final i in pageIndices) {
          try {
            final key = cacheKeyForPage(i);
            if (key == null) continue;
            await getOrRender(
              doc: doc,
              pageIndex: i,
              cacheKey: key,
              targetWidth: targetWidth,
              jpegQuality: jpegQuality,
            );
          } catch (_) {
            // Warmup must never surface errors; a disposed document throws
            // here, which also ends the prefetch.
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
      }(),
    );
  }

  static Future<void> _evictIfNeeded() async {
    try {
      final dir = await _cacheDir();
      final files = dir
          .listSync()
          .whereType<File>()
          .toList(growable: false);
      if (files.length <= maxDiskFiles) {
        var total = 0;
        for (final f in files) {
          try {
            total += f.lengthSync();
          } catch (_) {}
        }
        if (total <= maxDiskBytes) return;
      }
      files.sort((a, b) {
        DateTime am, bm;
        try {
          am = a.lastModifiedSync();
        } catch (_) {
          am = DateTime.fromMillisecondsSinceEpoch(0);
        }
        try {
          bm = b.lastModifiedSync();
        } catch (_) {
          bm = DateTime.fromMillisecondsSinceEpoch(0);
        }
        return am.compareTo(bm);
      });
      var total = 0;
      final sizes = <File, int>{};
      for (final f in files) {
        try {
          sizes[f] = f.lengthSync();
          total += sizes[f]!;
        } catch (_) {
          sizes[f] = 0;
        }
      }
      for (final f in files) {
        if (files.length <= maxDiskFiles && total <= maxDiskBytes) break;
        try {
          f.deleteSync();
          total -= sizes[f] ?? 0;
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Key-space probe used by tests and by the renderer to decide whether a
  /// synchronous paint is possible without touching PDFium.
  @visibleForTesting
  static bool looksLikeCacheKey(String s) =>
      RegExp(r'^(v2_)?[0-9a-f]+_p\d+_w\d+\.jpg$').hasMatch(s);
}
