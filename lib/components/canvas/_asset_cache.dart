// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:logging/logging.dart';
import 'package:mutex/mutex.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/services/vault_adapter.dart';

const int _largeAssetThresholdBytes = 50 * 1024 * 1024;

int _fnv1aInit(int fileSize) {
  int hash = 0x811C9DC5;
  hash ^= (fileSize & 0xFF);
  hash = (hash * 0x01000193) & 0xFFFFFFFF;
  hash ^= ((fileSize >> 8) & 0xFF);
  hash = (hash * 0x01000193) & 0xFFFFFFFF;
  hash ^= ((fileSize >> 16) & 0xFF);
  hash = (hash * 0x01000193) & 0xFFFFFFFF;
  hash ^= ((fileSize >> 24) & 0xFF);
  return hash;
}

int _isolateComputeFullHash(Map<String, dynamic> args) {
  final path = args['path'] as String;
  final size = args['size'] as int;
  int hash = _fnv1aInit(size);

  final raf = File(path).openSync();
  final buffer = Uint8List(64 * 1024);
  while (true) {
    final readCount = raf.readIntoSync(buffer);
    if (readCount == 0) break;
    for (int i = 0; i < readCount; i++) {
      hash ^= buffer[i];
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
  }
  raf.closeSync();
  return hash;
}

int _isolateComputePreviewHash(Map<String, dynamic> args) {
  final path = args['path'] as String;
  final size = args['size'] as int;
  int hash = _fnv1aInit(size);

  final raf = File(path).openSync();
  final toRead = size < 100 * 1024 ? size : 100 * 1024;
  final buffer = raf.readSync(toRead);
  raf.closeSync();

  for (int i = 0; i < buffer.length; i++) {
    hash ^= buffer[i];
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

class RandomFileName {
  static String generateRandomFileName([String extension = '.txt']) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(1 << 32);
    return 'file_${timestamp}_$random$extension';
  }
}

class PdfInfoExtractor {
  static Future<Map<String, String>> extractInfo(File file) async {
    return {};
  }
}

enum AssetType { image, pdf, svg, unknown }

class CacheItem {
  Object? value;
  final AssetType assetType;

  int? previewHash;
  int? hash;
  String? fileInfo;
  int? fileSize;

  String? filePath;
  final String? fileExt;
  File? originalFile;

  int _refCount = 0;
  int assetIdOnSave = -1;
  bool _dirtyForSave;

  final ValueNotifier<ImageProvider?> imageProviderNotifier;

  PdfDocument? _pdfDocument;
  final ValueNotifier<PdfDocument?> pdfDocumentNotifier;

  CacheItem(
    this.value, {
    this.hash,
    this.filePath,
    this.previewHash,
    this.fileSize,
    this.fileExt,
    this.fileInfo,
    ValueNotifier<PdfDocument?>? pdfDocumentNotifier,
    ValueNotifier<ImageProvider?>? imageProviderNotifier,
    bool dirtyForSave = false,
  }) : assetType = _detectTypeFromExtension(fileExt),
       _dirtyForSave = dirtyForSave,
       pdfDocumentNotifier = pdfDocumentNotifier ?? ValueNotifier(null),
       imageProviderNotifier = imageProviderNotifier ?? ValueNotifier(null),
       originalFile = value is File ? value : null;

  CacheItem.placeholder()
    : value = null,
      fileExt = null,
      fileSize = null,
      assetType = AssetType.unknown,
      filePath = null,
      _dirtyForSave = false,
      pdfDocumentNotifier = ValueNotifier(null),
      imageProviderNotifier = ValueNotifier(null);

  bool get isImage => assetType == AssetType.image;
  bool get isPdf => assetType == AssetType.pdf;
  bool get isSvg => assetType == AssetType.svg;

  static AssetType _detectTypeFromExtension(String? extension) {
    if (extension == null) return AssetType.unknown;
    final ext = extension.toLowerCase();
    if (['.jpg', '.jpeg', '.png', '.gif', '.bmp'].contains(ext)) {
      return AssetType.image;
    } else if (ext == '.pdf') {
      return AssetType.pdf;
    } else if (ext == '.svg') {
      return AssetType.svg;
    }
    return AssetType.unknown;
  }

  void dispose() {
    if (isPdf) {
      if (pdfDocumentNotifier.value != null) {
        _pdfDocument?.dispose();
        pdfDocumentNotifier.value = null;
      }
    }

    // SECURITY: Best-effort wipe of sensitive data from heap.

    if (value is Uint8List) {
      final bytes = value as Uint8List;

      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = 0;
      }
    }

    value = null;
    originalFile = null;
    filePath = null;
    imageProviderNotifier.value = null;
  }

  void addUse() => _refCount++;
  void freeUse() {
    if (_refCount > 0) _refCount--;
  }

  int get refCount => _refCount;
  bool get isUnused => _refCount == 0;
  bool get isDirtyForSave => _dirtyForSave;
  void markDirtyForSave() => _dirtyForSave = true;
  void markSaved() => _dirtyForSave = false;

  void invalidateImageProvider() {
    imageProviderNotifier.value = null;
  }

  Future<void> copyAssetToTemporaryFile() async {
    // SECURITY: If Vault is unlocked, NEVER write temp files to disk.

    if (VaultAdapter.isUnlocked) {
      try {
        if (value is File) {
          final f = value as File;
          // PDFs: do NOT load into RAM regardless of size.

          if (assetType == AssetType.pdf) {
            filePath = f.path;
            originalFile = f;
            return;
          }

          value = await f.readAsBytes();
        } else if (value is! Uint8List &&
            value is! MemoryImage &&
            value != null) {
          if (filePath != null) {
            final bytes = await FileManager.readFile(filePath!);
            if (bytes != null) value = bytes;
          }
        }
      } catch (e) {
        // SECURITY: If we cannot load the file into RAM, we must abort.

        rethrow;
      }

      filePath = null;
      originalFile = null;
      return;
    }

    Directory? dir;
    try {
      dir = await FileManager.getTmpAssetDir();
    } catch (e) {
      throw ('Error getting temporary directory');
    }
    String newPath = FileManager.fixFileNameDelimiters(
      '${dir.path}${Platform.pathSeparator}TmPmP_${RandomFileName.generateRandomFileName(fileExt ?? 'tmp')}',
    );

    if (originalFile == null && value is File) {
      originalFile = value as File;
    }

    final val = value;
    if (val is File) {
      value = await val.copy(newPath);
      filePath = newPath;
    }
  }

  Future<void> moveAssetToTemporaryFile() async {
    // SECURITY: If Vault is unlocked, NEVER write temp files to disk.
    if (VaultAdapter.isUnlocked) {
      if (value is File) {
        final sourceFile = value as File;

        value = await sourceFile.readAsBytes();
        try {
          await sourceFile.delete();
        } catch (_) {}
      }
      filePath = null;
      return;
    }

    Directory? dir;
    try {
      dir = await FileManager.getTmpAssetDir();
    } catch (e) {
      throw ('Error getting temporary directory');
    }
    String newPath = FileManager.fixFileNameDelimiters(
      '${dir.path}${Platform.pathSeparator}TmPmP_${RandomFileName.generateRandomFileName(fileExt ?? 'tmp')}',
    );
    value = await safeMoveFile((value as File), newPath);
    filePath = newPath;
  }

  Future<File> safeMoveFile(File source, String newPath) async {
    final String parentDirectory = newPath.substring(
      0,
      newPath.lastIndexOf(Platform.pathSeparator),
    );
    await Directory(parentDirectory).create(recursive: true);
    try {
      return await source.rename(newPath);
    } on FileSystemException catch (e) {
      final code = e.osError?.errorCode ?? -1;
      if (code == 18 || code == 17 || code == 32) {
        final newFile = await source.copy(newPath);
        try {
          await source.delete();
        } on FileSystemException {}
        return newFile;
      } else {
        rethrow;
      }
    }
  }

  @override
  String toString() =>
      'CacheItem(path: $filePath, preview=$previewHash, full=$hash, refs=$_refCount)';
}

class _PdfLoadCancelledException implements Exception {}

class AssetCacheAll {
  final List<CacheItem> _items = [];

  /// Highest first: visible page / user-critical decodes.
  static const int kImageDecodePriorityVisible = 1000000;

  /// Neighbor pages while opening or scrolling.
  static const int kImageDecodePriorityNearby = 500000;

  final Map<int, int> _previewHashIndex = {};

  final Map<String, int> _filePathIndex = {};

  final Map<int, Future<PdfDocument>> _openingDocs = {};

  final Map<int, DateTime> _pdfOpenFailedAt = {};

  final Map<int, String> _pdfTempPaths = {};

  bool _disposed = false;

  final Set<int> _cancelledPdfAssetIds = {};

  final Map<int, ValueNotifier<double>> _pdfProgressMap = {};

  final Map<int, String> _pdfLoadingLabels = {};

  final ValueNotifier<({double progress, String label})?> pdfLoadingState =
      ValueNotifier(null);

  final Mutex _mutex = Mutex();
  final log = Logger('OrderedAssetCache');

  /// pdfrx loads metadata for every page inside [PdfDocument.openFile]/[openData] by
  /// default ([useProgressiveLoading]: false), which can take many seconds on large
  /// PDFs. Opening with progressive mode and finishing metadata in the background
  /// lets the editor show the first page quickly; [PdfPageView] listens for page
  /// updates when each page's real size is known.
  void _schedulePdfBackgroundPageLoad(PdfDocument doc) {
    unawaited(
      doc.loadPagesProgressively().catchError((Object e, StackTrace st) {
        log.warning('PDF background page metadata load failed: $e');
      }),
    );
  }

  bool allowRemovingAssets = true;

  final Set<int> _pendingImageDecodes = {};
  final Map<int, int> _imageDecodePriority = {};
  final Set<int> _inflightImageDecodes = {};
  int _activeImageDecodes = 0;

  /// Product target is aarch64 Android only; keep decode parallelism modest.
  int get _maxConcurrentImageDecodes => 4;

  void _trackFilePathChange(int index, String? oldPath, String? newPath) {
    if (oldPath != null && _filePathIndex[oldPath] == index) {
      _filePathIndex.remove(oldPath);
    }
    if (newPath != null) {
      _filePathIndex[newPath] = index;
    }
  }

  ValueNotifier<PdfDocument?> getPdfNotifier(int assetId) {
    if (assetId < 0 || assetId >= _items.length) {
      log.severe('getPdfNotifier: invalid assetId $assetId');
      return ValueNotifier(null);
    }

    final item = _items[assetId];
    if (item.assetType != AssetType.pdf) {
      log.warning('getPdfNotifier called for non-pdf asset: ${item.assetType}');
      return ValueNotifier(null);
    }

    final canOpen =
        item._pdfDocument == null &&
        (item.value != null || item.filePath != null);
    if (canOpen) {
      final failedAt = _pdfOpenFailedAt[assetId];
      if (failedAt != null &&
          DateTime.now().difference(failedAt) < const Duration(seconds: 3)) {
        return item.pdfDocumentNotifier;
      }

      if (_openingDocs[assetId] == null) {
        void clearProgressForAsset() {
          _pdfProgressMap.remove(assetId);
          _pdfLoadingLabels.remove(assetId);
          _updatePdfLoadingState();
        }

        void onDocumentReady() {
          item.pdfDocumentNotifier.removeListener(onDocumentReady);
          clearProgressForAsset();
        }

        item.pdfDocumentNotifier.addListener(onDocumentReady);

        final future = _openPdfDocument(assetId, item);
        _openingDocs[assetId] = future;
        
        future.then((doc) {
          if (_disposed || _cancelledPdfAssetIds.contains(assetId)) {
            doc.dispose();
            clearProgressForAsset();
            _openingDocs.remove(assetId);
            return;
          }
          log.fine('_pdfDocument read for $assetId');
          item.pdfDocumentNotifier.removeListener(onDocumentReady);
          _pdfOpenFailedAt.remove(assetId);
          clearProgressForAsset();
          item._pdfDocument = doc;
          item.pdfDocumentNotifier.value = doc;
          _openingDocs.remove(assetId);
        }).catchError((e, st) {
          _pdfOpenFailedAt[assetId] = DateTime.now();
          _pdfProgressMap.remove(assetId);
          _pdfLoadingLabels.remove(assetId);
          _updatePdfLoadingState();
          log.severe('Error opening PDF $assetId: $e\n$st');
          _openingDocs.remove(assetId);
        });
      }
    } else if (item._pdfDocument != null) {
      if (item.pdfDocumentNotifier.value != item._pdfDocument) {
        final doc = item._pdfDocument;
        scheduleMicrotask(() {
          if (_disposed) return;
          if (!identical(item._pdfDocument, doc)) return;
          if (item.pdfDocumentNotifier.value != doc) {
            item.pdfDocumentNotifier.value = doc;
          }
        });
      }
    }
    return item.pdfDocumentNotifier;
  }

  ValueNotifier<double>? getPdfProgressNotifier(int assetId) {
    if (assetId < 0 || assetId >= _items.length) return null;
    return _pdfProgressMap[assetId];
  }

  static String _pdfLabelFromPath(String path) {
    final last = path.split('/').last.replaceAll(RegExp(r'\.sbn2\.\d+$'), '');
    final name = last.replaceAll(RegExp(r'\.sbn2$'), '');
    if (name.isEmpty) return 'PDF';
    const maxLen = 72;
    final display = name.length > maxLen
        ? '…${name.substring(name.length - maxLen + 1)}'
        : name;
    return '$display.pdf';
  }

  void prefetchAllPdfAssets() {
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].assetType == AssetType.pdf) {
        getPdfNotifier(i);
      }
    }
  }

  void _updatePdfLoadingState() {
    // Editor no longer shows a PDF/opening progress bar.
  }

  static bool _isAssetPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.contains('.sbn2.') &&
        RegExp(r'\.sbn2\.\d+$').hasMatch(normalized);
  }

  static bool _looksLikeImage(Uint8List bytes) {
    if (bytes.length < 3) return false;
    if (bytes[0] == 0x89 &&
        bytes.length >= 8 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47)
      return true;
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return true;
    return false;
  }

  Future<PdfDocument> _openPdfDocument(int assetId, CacheItem item) async {
    try {
      final path = item.filePath;

      if (item.value is Uint8List) {
        final bytes = item.value as Uint8List;

        final doc = await PdfDocument.openData(
          bytes,
          sourceName: 'memory_asset_$assetId',
          useProgressiveLoading: true,
        );
        _schedulePdfBackgroundPageLoad(doc);
        return doc;
      }

      if (path == null) {
        throw StateError('PDF file path is null and no bytes provided.');
      }

      final isVaultEnabled =
          stows.localEncryptionEnabled.value && VaultAdapter.isUnlocked;
      final isVaultAsset = AssetCacheAll._isAssetPath(path) && isVaultEnabled;

      if (isVaultAsset) {
        final progressNotifier = ValueNotifier<double>(0.0);
        _pdfProgressMap[assetId] = progressNotifier;
        _pdfLoadingLabels[assetId] = _pdfLabelFromPath(path);
        _updatePdfLoadingState();

        var lastVaultProgressStep = -1;
        void reportVaultProgress(double p) {
          final step = (p * 32).floor();
          if (step != lastVaultProgressStep || p >= 1.0) {
            lastVaultProgressStep = step;
            progressNotifier.value = p;
            _updatePdfLoadingState();
          }
        }

        void clearPdfProgress() {
          _pdfProgressMap.remove(assetId);
          _pdfLoadingLabels.remove(assetId);
          _updatePdfLoadingState();
        }

        try {
          final fileSize = await VaultAdapter.instance.getFileSize(path) ?? 0;
          if (fileSize <= 0) {
            throw StateError('Invalid or missing vault PDF size: $path');
          }

          /// Temp/mmap open whenever Secure PDF loading allows disk (global
          /// Temp or per-note override). RAM-only never writes plaintext to
          /// disk — open via [PdfDocument.openData] instead.
          final allowTempDisk = vaultPathAllowsDiskBackedDecrypt(path);

          if (allowTempDisk) {
            final tempPath = await FileManager.readFileToTempFile(
              path,
              onProgress: reportVaultProgress,
            );
            if (tempPath == null) {
              throw StateError('Failed to decrypt vault PDF: $path');
            }
            _pdfTempPaths[assetId] = tempPath;
            final mmapDoc = await PdfDocument.openFile(
              tempPath,
              useProgressiveLoading: true,
            );
            _schedulePdfBackgroundPageLoad(mmapDoc);
            return mmapDoc;
          }

          // RAM-only: decrypt entirely into memory.
          if (fileSize >= 40 * 1024 * 1024 &&
              !stows.vaultPdfAllowLargeRam.value) {
            throw StateError(
              'Vault PDF is too large for RAM-only mode ($fileSize B). '
              'Enable Temp mode for this note, or allow large RAM PDFs in Settings.',
            );
          }

          final bytes = await FileManager.readFile(
            path,
            onProgress: reportVaultProgress,
          );
          if (bytes == null || bytes.isEmpty) {
            throw StateError('Failed to read vault PDF: $path');
          }
          final ramDoc = await PdfDocument.openData(
            bytes,
            sourceName: path,
            useProgressiveLoading: true,
          );
          // Avoid holding a second full copy in the vault decrypt LRU while
          // pdfrx already owns [bytes] for this open.
          if (bytes.length > 12 * 1024 * 1024) {
            VaultAdapter.instance.invalidateCachedReadForPath(path);
          }
          _schedulePdfBackgroundPageLoad(ramDoc);
          return ramDoc;
        } finally {
          clearPdfProgress();
        }
      }

      File diskFile;
      if (item.originalFile != null && item.originalFile!.existsSync()) {
        diskFile = item.originalFile!;
      } else if (item.value is File && (item.value as File).existsSync()) {
        diskFile = item.value as File;
      } else {
        diskFile = FileManager.getFile(path);
      }

      if (diskFile.existsSync()) {
        final diskDoc = await PdfDocument.openFile(
          diskFile.path,
          useProgressiveLoading: true,
        );
        _schedulePdfBackgroundPageLoad(diskDoc);
        return diskDoc;
      }

      throw StateError('PDF file does not exist: $path');
    } catch (e) {
      log.severe('Failed to open PDF (id: ${item.filePath}): $e');
      rethrow;
    }
  }

  Future<void> clearPdfDocumentNotifier(int assetId) async {
    final item = _items[assetId];
    if (item.assetType != AssetType.pdf) return;

    _cancelledPdfAssetIds.add(assetId);
    _pdfProgressMap.remove(assetId);
    _pdfLoadingLabels.remove(assetId);
    _updatePdfLoadingState();

    final tempPath = _pdfTempPaths.remove(assetId);
    if (item.pdfDocumentNotifier.value != null) {
      item._pdfDocument = null;
      _openingDocs.remove(assetId);
      item.pdfDocumentNotifier.value!.dispose();
      item.pdfDocumentNotifier.value = null;
    }
    // Do NOT delete [tempPath] here when it is a vault-managed plaintext temp
    // (registered in VaultAdapter). Wiping it forced a full re-decrypt on
    // reopen under Temp mode. Vault lock / RAM-only policy purge owns cleanup.
    // Only delete orphan runtime temps that vault does not track.
    if (tempPath != null &&
        !VaultAdapter.instance.isTrackedPlaintextDecryptTemp(tempPath)) {
      try {
        await FileManager.secureDelete(File(tempPath));
      } catch (e) {
        log.warning('Failed to secure-delete temp PDF file: $tempPath');
      }
    }
  }

  Future<void> clearImageProvider(int assetId) async {
    final item = _items[assetId];
    if (item.assetType != AssetType.image) return;

    if (item.imageProviderNotifier.value != null && item.value is File) {
      final file = FileImage(item.value as File);
      final key = await file.obtainKey(ImageConfiguration());
      imageCache.evict(key);
    }
  }

  ValueNotifier<ImageProvider?> getImageProviderNotifier(int assetId) {
    if (assetId < 0 || assetId >= _items.length) {
      return ValueNotifier(null);
    }
    final item = _items[assetId];
    if (item.assetType != AssetType.image) {
      return ValueNotifier(null);
    }

    if (item.imageProviderNotifier.value != null) {
      return item.imageProviderNotifier;
    }

    if (item.value is File) {
      final file = item.value as File;

      if (file.existsSync()) {
        item.imageProviderNotifier.value = FileImage(file);
      } else {
        _enqueueImageDecode(assetId);
      }
    } else if (item.value is Uint8List) {
      item.imageProviderNotifier.value = MemoryImage(item.value as Uint8List);
    } else if (item.value is MemoryImage) {
      item.imageProviderNotifier.value = item.value as MemoryImage;
    } else if (item.value is FileImage) {
      item.imageProviderNotifier.value = item.value as FileImage;
    } else if (item.filePath != null) {
      _enqueueImageDecode(assetId);
    }

    return item.imageProviderNotifier;
  }

  /// Prefer decoding these assets first (e.g. visible canvas pages). Higher [priority] wins.
  void prioritizeImageDecode(int assetId, int priority) {
    if (_disposed || assetId < 0 || assetId >= _items.length) return;
    final item = _items[assetId];
    if (item.assetType != AssetType.image) return;
    if (item.imageProviderNotifier.value != null) return;
    _enqueueImageDecode(assetId, priority: priority);
  }

  void _enqueueImageDecode(int assetId, {int priority = 0}) {
    if (_disposed || assetId < 0 || assetId >= _items.length) return;
    final item = _items[assetId];
    if (item.assetType != AssetType.image) return;
    if (item.imageProviderNotifier.value != null) return;

    final prev = _imageDecodePriority[assetId] ?? 0;
    _imageDecodePriority[assetId] = priority > prev ? priority : prev;
    _pendingImageDecodes.add(assetId);
    _scheduleImageDecodePump();
  }

  bool _imageDecodePumpScheduled = false;

  void _scheduleImageDecodePump() {
    if (_disposed || _imageDecodePumpScheduled) return;
    _imageDecodePumpScheduled = true;
    scheduleMicrotask(() {
      _imageDecodePumpScheduled = false;
      unawaited(_pumpImageDecodeQueue());
    });
  }

  int? _takeHighestPriorityImageDecode() {
    if (_pendingImageDecodes.isEmpty) return null;
    var best = _pendingImageDecodes.first;
    var bestP = _imageDecodePriority[best] ?? 0;
    for (final id in _pendingImageDecodes) {
      final p = _imageDecodePriority[id] ?? 0;
      if (p > bestP || (p == bestP && id < best)) {
        best = id;
        bestP = p;
      }
    }
    _pendingImageDecodes.remove(best);
    return best;
  }

  Future<void> _pumpImageDecodeQueue() async {
    if (_disposed) return;
    while (_activeImageDecodes < _maxConcurrentImageDecodes &&
        _pendingImageDecodes.isNotEmpty) {
      final assetId = _takeHighestPriorityImageDecode();
      if (assetId == null) break;
      if (_inflightImageDecodes.contains(assetId)) continue;
      final item = _items[assetId];
      if (item.assetType != AssetType.image ||
          item.imageProviderNotifier.value != null) {
        _imageDecodePriority.remove(assetId);
        continue;
      }
      _inflightImageDecodes.add(assetId);
      _activeImageDecodes++;
      final capturedId = assetId;
      unawaited(_runOneImageDecode(capturedId));
    }
  }

  Future<void> _runOneImageDecode(int assetId) async {
    try {
      await _loadImageFromPath(assetId);
    } finally {
      _activeImageDecodes--;
      _inflightImageDecodes.remove(assetId);
      _imageDecodePriority.remove(assetId);
      if (!_disposed) {
        unawaited(_pumpImageDecodeQueue());
      }
    }
  }

  Future<void> _loadImageFromPath(int assetId) async {
    final item = _items[assetId];
    if (item.filePath == null) return;
    if (item.imageProviderNotifier.value != null) return;

    try {
      Uint8List? bytes = await FileManager.readFile(
        item.filePath!,
        suppressLogs: true,
      );
      if (bytes != null && bytes.isNotEmpty) {
        if (!AssetCacheAll._looksLikeImage(bytes) &&
            AssetCacheAll._isAssetPath(item.filePath!) &&
            VaultAdapter.isUnlocked) {
          VaultAdapter.instance.invalidateCachedReadForPath(item.filePath!);
          bytes = await FileManager.readFile(
            item.filePath!,
            suppressLogs: true,
          );
        }
        if (bytes != null &&
            bytes.isNotEmpty &&
            AssetCacheAll._looksLikeImage(bytes)) {
          item.value = bytes;
          item.imageProviderNotifier.value = MemoryImage(bytes);
        }
      }
    } catch (e) {
      log.warning('Failed to lazy load image asset $assetId: $e');
    }
  }

  void ensureCapacity(int count, String mainFilePath) {
    if (_items.length >= count) return;
    final startIndex = _items.length;
    final toAdd = count - _items.length;
    final newItems = List.generate(toAdd, (i) {
      final expectedPath = '$mainFilePath.${startIndex + i}';
      return CacheItem.placeholder()..filePath = expectedPath;
    });
    _items.addAll(newItems);
    for (int i = 0; i < toAdd; i++) {
      final index = startIndex + i;
      _trackFilePathChange(index, null, _items[index].filePath);
    }
  }

  void setImageProvider(int assetId, ImageProvider provider) {
    final item = _items[assetId];
    if (item.assetType != AssetType.image) return;
    item.imageProviderNotifier.value = provider;
  }

  int _initHash(int fileSize) {
    int hash = 0x811C9DC5;
    hash ^= (fileSize & 0xFF);
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
    hash ^= ((fileSize >> 8) & 0xFF);
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
    hash ^= ((fileSize >> 16) & 0xFF);
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
    hash ^= ((fileSize >> 24) & 0xFF);
    return hash;
  }

  int calculateHash(List<int> bytes, int fileSize) {
    int hash = _initHash(fileSize);
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  Future<int> calculateHashFromFile(File file, int fileSize) async {
    if (fileSize > 1024 * 1024) {
      final stat = await file.stat();
      return _initHash(fileSize) ^ stat.modified.millisecondsSinceEpoch;
    }

    return await compute(_isolateComputeFullHash, {
      'path': file.path,
      'size': fileSize,
    });
  }

  Future<int> getFilePreviewHashAsync(File file) async {
    final stat = await file.stat();
    if (stat.size > 1024 * 1024) {
      return _initHash(stat.size) ^ stat.modified.millisecondsSinceEpoch;
    }
    return await compute(_isolateComputePreviewHash, {
      'path': file.path,
      'size': stat.size,
    });
  }

  void removeUse(int id) {
    if (id >= 0 && id < _items.length) _items[id].freeUse();
  }

  void addUse(int id) {
    if (id >= 0 && id < _items.length) _items[id].addUse();
  }

  int addSync(
    Object value,
    String extension,
    int assetIdNote,
    String? fileInfo,
    int? previewHash,
    int? fileSize,
    int? hash,
  ) {
    if (assetIdNote < 0) {
      assetIdNote = _items.length;
    }
    if (value is File) {
      if (assetIdNote < _items.length) {
        final existing = _items[assetIdNote];
        if (existing.filePath == value.path) {
          if (existing.assetType == AssetType.unknown ||
              existing.fileExt == null) {
            final refreshed = CacheItem(
              value,
              filePath: value.path,
              previewHash: previewHash,
              fileSize: fileSize,
              fileExt: extension,
              fileInfo: fileInfo,
              hash: hash,
              dirtyForSave: false,
            )..addUse();
            final oldPath = existing.filePath;
            _items[assetIdNote] = refreshed;
            _trackFilePathChange(assetIdNote, oldPath, refreshed.filePath);
          } else {
            existing.addUse();
          }
          _trackFilePathChange(assetIdNote, null, value.path);
          return assetIdNote;
        }
      }

      if (_items.length < assetIdNote) {
        final startIndex = _items.length;
        final toAdd = assetIdNote - _items.length;
        _items.addAll(List.generate(toAdd, (_) => CacheItem.placeholder()));
        for (int i = 0; i < toAdd; i++) {
          _trackFilePathChange(startIndex + i, null, null);
        }
      }

      final newItem = CacheItem(
        value,
        filePath: value.path,
        previewHash: previewHash,
        fileSize: fileSize,
        fileExt: extension,
        fileInfo: fileInfo,
        hash: hash,
        dirtyForSave: false,
      )..addUse();

      if (_items.length == assetIdNote) {
        _items.add(newItem);
      } else {
        final oldPath = _items[assetIdNote].filePath;
        _items[assetIdNote] = newItem;
        _trackFilePathChange(assetIdNote, oldPath, newItem.filePath);
      }

      _trackFilePathChange(assetIdNote, null, newItem.filePath);
      return assetIdNote;
    } else {
      if (_items.length < assetIdNote) {
        final startIndex = _items.length;
        final toAdd = assetIdNote - _items.length;
        _items.addAll(List.generate(toAdd, (_) => CacheItem.placeholder()));
        for (int i = 0; i < toAdd; i++) {
          _trackFilePathChange(startIndex + i, null, null);
        }
      }
      final newItem = CacheItem(value, fileExt: extension)..addUse();
      if (_items.length == assetIdNote) {
        _items.add(newItem);
      } else {
        _items[assetIdNote] = newItem;
      }
      return assetIdNote;
    }
  }

  Future<int> add(
    Object value, {
    bool copyFromSource = true,
    bool forceNew = false,
    String? fileInfo,
  }) async {
    return await _mutex.protect(() async {
      if (value is File) {
        final path = value.path;
        final extension = '.${value.path.split('.').last.toLowerCase()}';

        if (!forceNew) {
          final existingIndex = _filePathIndex[path];
          if (existingIndex != null && existingIndex < _items.length) {
            final existing = _items[existingIndex];
            if (existing.filePath == path) {
              existing.addUse();
              return existingIndex;
            }
            _filePathIndex.remove(path);
          }
        }

        final stat = value.statSync();
        final fileSize = stat.size;
        final previewHash = await getFilePreviewHashAsync(value);

        if (!forceNew && _previewHashIndex.containsKey(previewHash)) {
          final existingIndex = _previewHashIndex[previewHash]!;

          _items[existingIndex].addUse();
          return existingIndex;
        }

        final hash = await calculateHashFromFile(value, fileSize);

        final newItem =
            CacheItem(
                value,
                filePath: value.path,
                previewHash: previewHash,
                hash: hash,
                fileExt: extension,
                fileSize: fileSize,
                fileInfo: fileInfo,
                dirtyForSave: true,
              )
              ..addUse()
              ..originalFile = value;

        if (copyFromSource) {
          await newItem.copyAssetToTemporaryFile();
        }

        _items.add(newItem);
        final index = _items.length - 1;
        _trackFilePathChange(index, null, newItem.filePath);
        if (!forceNew) {
          _previewHashIndex[previewHash] = index;
        }
        return index;
      } else {
        throw Exception('assetCacheAll.add: unknown type ${value.runtimeType}');
      }
    });
  }

  Future<int> addPdfFast(File pdfFile) async {
    return await _mutex.protect(() async {
      final path = pdfFile.path;
      final extension = '.pdf';

      final stat = pdfFile.statSync();
      final fileSize = stat.size;

      final previewHash = _initHash(fileSize);

      final newItem =
          CacheItem(
              pdfFile,
              filePath: path,
              previewHash: previewHash,
              hash: previewHash,
              fileExt: extension,
              fileSize: fileSize,
              fileInfo: null,
              dirtyForSave: true,
            )
            ..addUse()
            ..originalFile = pdfFile;

      // Do NOT copy: keep File reference. On save, renumberBeforeSave uses

      _items.add(newItem);
      final index = _items.length - 1;
      _trackFilePathChange(index, null, path);
      return index;
    });
  }

  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

  Future<List<int>> getBytes(int index) async {
    if (index < 0 || index >= _items.length) return [];

    final item = _items[index];
    final filePath = item.filePath;

    if (filePath != null) {
      final bytes = await FileManager.readFile(filePath);
      if (bytes != null) return bytes;
    }

    final value = item.value;
    if (value is List<int>) {
      return value;
    } else if (value is Uint8List) {
      return value;
    } else if (value is String) {
      return utf8.encode(value);
    } else if (value is MemoryImage) {
      return value.bytes;
    }

    // SECURITY: Only read from disk if Vault is NOT enabled/unlocked, or path is a known temp/cache.

    if (value is File || value is FileImage) {
      final file = value is File ? value : (value as FileImage).file;

      if (!VaultAdapter.isUnlocked) {
        if (file.existsSync()) {
          return file.readAsBytesSync();
        }
      } else {
        final path = file.path;
        final isTempOrCache =
            path.contains('cache') ||
            path.contains('tmp') ||
            path.contains('TmPmP') ||
            path.contains('file_picker');
        if (isTempOrCache && await file.exists()) {
          return await file.readAsBytes();
        }
        log.severe(
          '[AssetCache.getBytes] Blocked disk read in Vault mode for: ${file.path}',
        );
        return [];
      }
    }

    return [];
  }

  int getAssetIdOnSave(int index) => _items[index].assetIdOnSave;
  int getAssetPreviewHash(int index) => _items[index].previewHash ?? 0;
  int? getAssetHash(int index) => _items[index].hash;
  String getAssetFileInfo(int index) => _items[index].fileInfo ?? '';
  int getAssetFileSize(int index) => _items[index].fileSize ?? 0;

  String getAssetExtension(int index) => index >= 0 && index < _items.length
      ? (_items[index].fileExt ?? '.bin')
      : '.bin';

  File getAssetFile(int id) {
    final item = _items[id];
    if (item.value is File) {
      return (item.value as File);
    } else if (item.value is FileImage) {
      return (item.value as FileImage).file;
    }
    if (item.filePath != null && !VaultAdapter.isUnlocked) {
      final rawFile = File(item.filePath!);
      if (rawFile.existsSync()) return rawFile;
      return FileManager.getFile(item.filePath!);
    }
    throw Exception('getAssetFile: item is not a file');
  }

  File createRuntimeFile(String ext, Uint8List bytes) {
    final dir = Directory.systemTemp;
    final file = File(
      '${dir.path}${Platform.pathSeparator}TmPmP_${RandomFileName.generateRandomFileName(ext)}',
    );
    file.writeAsBytesSync(bytes, flush: true);
    return file;
  }

  Future<void> replaceImage(Object value, int id) async {
    await _mutex.protect(() async {
      if (value is File) {
        final stat = value.statSync();
        final fileSize = stat.size;
        final previewHash = await getFilePreviewHashAsync(value);

        final oldItem = _items[id];
        final wasMemoryImage =
            oldItem.imageProviderNotifier.value is MemoryImage;
        MemoryImage? preservedMemoryImage;
        if (wasMemoryImage) {
          final bytes = await value.readAsBytes();
          preservedMemoryImage = MemoryImage(bytes);
        }

        final newItem = CacheItem(
          value,
          filePath: value.path,
          previewHash: previewHash,
          hash: oldItem.hash,
          fileSize: fileSize,
          fileInfo: oldItem.fileInfo,
          imageProviderNotifier: oldItem.imageProviderNotifier,
          dirtyForSave: true,
        ).._refCount = oldItem._refCount;

        // SECURITY: If Vault is enabled, immediately load data to RAM and detach from Disk.

        if (VaultAdapter.isUnlocked) {
          await newItem.copyAssetToTemporaryFile();
        }

        final oldPath = _items[id].filePath;
        _items[id] = newItem;
        _trackFilePathChange(id, oldPath, newItem.filePath);

        if (wasMemoryImage && preservedMemoryImage != null) {
          _items[id].imageProviderNotifier.value = preservedMemoryImage;
        } else {
          _items[id].invalidateImageProvider();
        }
      }
    });
  }

  Future<void> _applySaveResultToItem(
    int idx,
    String path,
    bool shouldUseVault,
  ) async {
    final item = _items[idx];
    final oldPath = item.filePath;
    item.filePath = path;
    _trackFilePathChange(idx, oldPath, path);
    _pdfOpenFailedAt.remove(idx);
    if (item.isImage) await clearImageProvider(idx);
    if (!shouldUseVault) {
      item.value = FileManager.getFile(path);
    }
    item.markSaved();
    if (item.isImage) {
      final currentProvider = item.imageProviderNotifier.value;
      if (currentProvider is! MemoryImage) {
        item.invalidateImageProvider();
        getImageProviderNotifier(idx);
      }
    }
  }

  Future<Uint8List?> _resolveAssetBytesForSave(
    CacheItem item,
    bool shouldUseVault,
  ) async {
    Uint8List? dataToWrite;

    if (item.value is Uint8List) {
      return item.value as Uint8List;
    }

    if (item.isImage) {
      final provider = item.imageProviderNotifier.value;
      if (provider is MemoryImage) {
        return provider.bytes;
      }
    }

    if (item.value is File) {
      final sourceFile = item.value as File;
      if (sourceFile.existsSync()) {
        dataToWrite = sourceFile.readAsBytesSync();
      } else if (shouldUseVault) {
        try {
          dataToWrite = await FileManager.readFile(sourceFile.path);
        } catch (_) {}
      }
      if (dataToWrite != null) return dataToWrite;
    }

    if (item.originalFile != null) {
      final sourceFile = item.originalFile!;
      if (sourceFile.existsSync()) {
        return sourceFile.readAsBytesSync();
      }
    }

    if (item.filePath != null) {
      var path = item.filePath!;
      if (shouldUseVault) path = FileManager.toRelativePath(path);
      dataToWrite = await FileManager.readFile(path);
      if (dataToWrite != null) return dataToWrite;

      if (!shouldUseVault && path.startsWith('/') && File(path).existsSync()) {
        return File(path).readAsBytesSync();
      }

      if (shouldUseVault &&
          (path.contains('cache') ||
              path.contains('tmp') ||
              path.contains('TmPmP'))) {
        final temp = File(item.filePath!);
        if (temp.existsSync()) {
          return temp.readAsBytesSync();
        }
      }
    }

    return null;
  }

  /// Resolves/compacts on-disk asset paths for this note before BSON write.
  ///
  /// Returns true when any in-memory image path or layout was updated such that
  /// embedded page binary may need a full re-encode.
  Future<bool> renumberBeforeSave(
    String noteFilePath, {
    bool awaitWrite = false,
    bool? awaitDbCommit,
    bool hasLazyPages = false,
  }) async {
    final commitVaultDb = awaitDbCommit ?? awaitWrite;
    if (_items.isEmpty) return false;
    final sw = Stopwatch()..start();
    var pathsMutated = false;
    await _mutex.protect(() async {
      int currentId = -1;
      for (int i = 0; i < _items.length; i++) {
        final item = _items[i];
        // Proteção Crítica: Se existem páginas Lazy que não entraram na memória, 
        // ASSUMA que os itens do cache podem estar sendo utilizados nelas.
        if (item.refCount > 0 || hasLazyPages) {
          currentId++;
          item.assetIdOnSave = currentId;
        } else {
          item.assetIdOnSave = -1;
        }
      }

      final relativeNotePath = FileManager.toRelativePath(noteFilePath);
      final shouldUseVault =
          stows.localEncryptionEnabled.value && VaultAdapter.isUnlocked;

      for (int i = _items.length - 1; i >= 0; i--) {
        final item = _items[i];
        if (item.refCount >= 1) continue;
        final filePath = item.filePath;
        if (filePath != null && filePath.startsWith(noteFilePath)) {
          if (item.isImage)
            await clearImageProvider(i);
          else if (item.isPdf)
            await clearPdfDocumentNotifier(i);

          final oldPath = item.filePath;
          try {
            await item.moveAssetToTemporaryFile();
          } catch (e) {
            log.warning('Error saving unused asset to temp: $e');
          }
          _trackFilePathChange(i, oldPath, item.filePath);

          if (item.isImage) {
            final currentProvider = item.imageProviderNotifier.value;
            if (currentProvider is! MemoryImage) {
              item.invalidateImageProvider();
              getImageProviderNotifier(i);
            }
          }
        }
      }

      const int batchSize = 5;
      final candidates = <({int index, String newPath})>[];
      for (int i = _items.length - 1; i >= 0; i--) {
        final item = _items[i];
        if (item.refCount < 1) continue;

        final idOnSave = item.assetIdOnSave;
        final newPath = '$relativeNotePath.$idOnSave';
        final pathUnchanged = item.filePath == newPath;

        if (pathUnchanged && !item.isDirtyForSave) continue;

        candidates.add((index: i, newPath: newPath));
      }

      for (int i = 0; i < candidates.length; i += batchSize) {
        final end = (i + batchSize < candidates.length)
            ? i + batchSize
            : candidates.length;
        final batch = candidates.sublist(i, end);
        final batchWrites = <String, Uint8List>{};
        final itemsToUpdate = <int, String>{};
        final largeFileBatch =
            <({int index, String newPath, String sourcePath})>[];

        for (final c in batch) {
          final item = _items[c.index];
          final sourceFile = item.value is File
              ? item.value as File
              : item.originalFile;
          if (sourceFile != null &&
              await sourceFile.exists() &&
              (await sourceFile.length()) > _largeAssetThresholdBytes) {
            largeFileBatch.add((
              index: c.index,
              newPath: c.newPath,
              sourcePath: sourceFile.path,
            ));
            continue;
          }
          final data = await _resolveAssetBytesForSave(item, shouldUseVault);
          if (data == null || data.isEmpty) {
            if (shouldUseVault &&
                await VaultAdapter.instance.fileExists(c.newPath)) {
              pathsMutated = true;
              await _applySaveResultToItem(c.index, c.newPath, shouldUseVault);
              continue;
            }

            if (data == null) {
              log.fine(
                '[AssetCache.renumberBeforeSave] No data available for asset ${c.index}. Skipping (likely background moved).',
              );
            }
            continue;
          }
          batchWrites[c.newPath] = data;
          itemsToUpdate[c.index] = c.newPath;
        }

        if (batchWrites.isNotEmpty) {
          try {
            await FileManager.writeFilesBulk(
              batchWrites,
              awaitWrite: awaitWrite,
              awaitDbCommit: commitVaultDb,
            );
            for (final entry in itemsToUpdate.entries) {
              pathsMutated = true;
              await _applySaveResultToItem(
                entry.key,
                entry.value,
                shouldUseVault,
              );
            }
          } catch (e, stack) {
            log.severe('[AssetCache] Batch save failed', e, stack);
            rethrow;
          }
        }

        for (final e in largeFileBatch) {
          try {
            await FileManager.writeFileFromPath(
              e.sourcePath,
              e.newPath,
              awaitWrite: awaitWrite,
              awaitDbCommit: commitVaultDb,
            );
            pathsMutated = true;
            await _applySaveResultToItem(e.index, e.newPath, shouldUseVault);
          } catch (err, stack) {
            log.severe(
              '[AssetCache] Large file save failed (${e.newPath})',
              err,
              stack,
            );
            rethrow;
          }
        }

        if (i + batchSize < candidates.length) {
          await Future.delayed(const Duration(milliseconds: 16));
        }
      }
    });
    final msg =
        '[PERF][AssetCache.renumberBeforeSave] ${sw.elapsedMilliseconds}ms (items=${_items.length})';
    if (sw.elapsedMilliseconds >= 120) {
      log.info(msg);
    } else {
      log.fine(msg);
    }
    return pathsMutated;
  }

  void dispose() {
    _disposed = true;
    _pendingImageDecodes.clear();
    _imageDecodePriority.clear();
    _inflightImageDecodes.clear();
    _activeImageDecodes = 0;
    for (final item in _items) {
      item.dispose();
    }
    _items.clear();
    _cleanupCacheAll();
    _openingDocs.clear();
    _previewHashIndex.clear();
    _filePathIndex.clear();
  }

  Future<void> _cleanupCacheAll() async {
    try {
      final dir = await FileManager.getTmpAssetDir();
      if (dir.existsSync()) {
        final entities = dir.listSync(recursive: false);
        for (final entity in entities) {
          if (entity is File &&
              entity.uri.pathSegments.last.startsWith('TmPmP')) {
            try {
              // SECURITY OPTIMIZATION: Overwrite the unencrypted temp files

              await FileManager.secureDelete(entity);
            } catch (e) {
              log.warning('Failed to secure-delete temp file: ${entity.path}');
            }
          }
        }
      }
    } catch (e) {
      log.warning('Failed to cleanup cache dir: $e');
    }
  }
}
