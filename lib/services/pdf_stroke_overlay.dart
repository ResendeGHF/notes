// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io' show Directory, File, Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

/// Android: merges [overlayPath] (vector strokes, transparent page) onto
/// [basePath] using PDFBox. Returns the output path or null on failure /
/// unsupported platform.
class PdfStrokeOverlay {
  static const _channel = MethodChannel(
    'com.resendeghf.notes/pdf_stroke_overlay',
  );

  /// Same name as [EditorExporter] so native PDF failures show in one log stream.
  static final _log = Logger('EditorExporter');

  static void _logPlatformFailure(String method, Object error, StackTrace st) {
    if (error is PlatformException) {
      _log.warning(
        'pdf_stroke_overlay.$method failed: code=${error.code} '
        'message=${error.message} details=${error.details}',
        error,
        st,
      );
    } else {
      _log.warning('pdf_stroke_overlay.$method failed', error, st);
    }
  }

  /// Android: PDF page count via PDFBox (lightweight vs opening the whole doc in PDFium).
  static Future<int?> getPdfPageCount(String path) async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final n = await _channel.invokeMethod<int>('getPageCount', {
        'path': path,
      });
      if (n == null || n < 1) return null;
      return n;
    } catch (e, st) {
      _logPlatformFailure('getPageCount', e, st);
      return null;
    }
  }

  /// Android: replaces PDF bookmarks on [sourcePath], writing [outputPath].
  static Future<String?> setBookmarks({
    required String sourcePath,
    required String outputPath,
    required List<Map<String, dynamic>> outlines,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final out = await _channel.invokeMethod<String>('setBookmarks', {
        'sourcePath': sourcePath,
        'outputPath': outputPath,
        'outlines': outlines,
      });
      if (out == null || out.isEmpty) return null;
      if (!File(out).existsSync()) return null;
      return out;
    } catch (e, st) {
      _logPlatformFailure('setBookmarks', e, st);
      return null;
    }
  }

  static Future<String?> stamp({
    required String basePath,
    required String overlayPath,
    required String outputPath,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final out = await _channel.invokeMethod<String>('stamp', {
        'basePath': basePath,
        'overlayPath': overlayPath,
        'outputPath': outputPath,
      });
      if (out == null || out.isEmpty) return null;
      if (!File(out).existsSync()) return null;
      return out;
    } catch (e, st) {
      _logPlatformFailure('stamp', e, st);
      return null;
    }
  }

  /// Android: draws a full-page PNG (transparent stroke layer) on page 0 of [basePath].
  static Future<String?> stampPngOverlay({
    required String basePath,
    required String pngPath,
    required String outputPath,
    required double pageWidthPt,
    required double pageHeightPt,
    bool darkenBlend = true,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final out = await _channel.invokeMethod<String>('stampPngOverlay', {
        'basePath': basePath,
        'pngPath': pngPath,
        'outputPath': outputPath,
        'pageWidthPt': pageWidthPt,
        'pageHeightPt': pageHeightPt,
        'darkenBlend': darkenBlend,
      });
      if (out == null || out.isEmpty) return null;
      if (!File(out).existsSync()) return null;
      return out;
    } catch (e, st) {
      _logPlatformFailure('stampPngOverlay', e, st);
      return null;
    }
  }

  /// Android: copies [sourcePath] to [outputPath], then stamps only the listed
  /// pages (same maps as [exportFromRecipe] `stamp` / `stampPng`). For full
  /// linear exports this avoids re-importing every page into a new document.
  static Future<String?> exportInPlaceStamps({
    required String sourcePath,
    required String outputPath,
    required List<Map<String, dynamic>> stamps,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return null;
    if (stamps.isEmpty) return null;
    try {
      final out = await _channel.invokeMethod<String>('exportInPlaceStamps', {
        'sourcePath': sourcePath,
        'outputPath': outputPath,
        'stamps': stamps,
      });
      if (out == null || out.isEmpty) return null;
      if (!File(out).existsSync()) return null;
      return out;
    } catch (e, st) {
      _logPlatformFailure('exportInPlaceStamps', e, st);
      return null;
    }
  }

  /// Android: in-place stamps using one multi-page [mergedOverlayPath] (page *i*
  /// matches [jobs]\[*i*]) so PDFBox opens the overlay document once.
  static Future<String?> exportInPlaceStampsMerged({
    required String sourcePath,
    required String outputPath,
    required String mergedOverlayPath,
    required List<Map<String, dynamic>> jobs,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return null;
    if (jobs.isEmpty) return null;
    try {
      final out = await _channel
          .invokeMethod<String>('exportInPlaceStampsMerged', {
            'sourcePath': sourcePath,
            'outputPath': outputPath,
            'mergedOverlayPath': mergedOverlayPath,
            'jobs': jobs,
          });
      if (out == null || out.isEmpty) return null;
      if (!File(out).existsSync()) return null;
      return out;
    } catch (e, st) {
      _logPlatformFailure('exportInPlaceStampsMerged', e, st);
      return null;
    }
  }

  /// Android: one PDFBox load of [sourcePath], applies [ops] in order (copy ranges
  /// and/or vector stamp ops). Returns [outputPath] on success.
  static Future<String?> exportFromRecipe({
    required String sourcePath,
    required String outputPath,
    required List<Map<String, dynamic>> ops,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return null;
    if (ops.isEmpty) return null;
    try {
      final out = await _channel.invokeMethod<String>('exportFromRecipe', {
        'sourcePath': sourcePath,
        'outputPath': outputPath,
        'ops': ops,
      });
      if (out == null || out.isEmpty) return null;
      if (!File(out).existsSync()) return null;
      return out;
    } catch (e, st) {
      _logPlatformFailure('exportFromRecipe', e, st);
      return null;
    }
  }

  /// Android: copies multiple disjoint ranges from [sourcePath] with a single
  /// PDFBox source open (orders of magnitude faster than one [extractPageRangeInclusive]
  /// call per range on huge PDFs).
  static Future<bool> extractPageRangesBatch({
    required String sourcePath,
    required List<({int startPage0, int endPage0Inclusive, String outputPath})>
    jobs,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    if (jobs.isEmpty) return false;
    try {
      await _channel.invokeMethod<void>('extractPageRangesBatch', {
        'sourcePath': sourcePath,
        'jobs': jobs
            .map(
              (j) => {
                'startPage0': j.startPage0,
                'endPage0Inclusive': j.endPage0Inclusive,
                'outputPath': j.outputPath,
              },
            )
            .toList(),
      });
      for (final j in jobs) {
        if (!File(j.outputPath).existsSync()) return false;
      }
      return true;
    } catch (e, st) {
      _logPlatformFailure('extractPageRangesBatch', e, st);
      return false;
    }
  }

  /// Android: copies a contiguous 0-based page range from [sourcePath] into a new
  /// PDF using PDFBox stream copy (no re‑rasterization).
  static Future<String?> extractPageRangeInclusive({
    required String sourcePath,
    required int startPage0,
    required int endPage0Inclusive,
    required String outputPath,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final out = await _channel.invokeMethod<String>('extractPageRange', {
        'sourcePath': sourcePath,
        'startPage0': startPage0,
        'endPage0Inclusive': endPage0Inclusive,
        'outputPath': outputPath,
      });
      if (out == null || out.isEmpty) return null;
      if (!File(out).existsSync()) return null;
      return out;
    } catch (e, st) {
      _logPlatformFailure('extractPageRange', e, st);
      return null;
    }
  }

  /// Android: builds a multi-page vector stroke overlay PDF from a packed
  /// polygon blob (see [PdfStrokeVectorEncoder.packNativeOverlayBlob]).
  static Future<Uint8List?> encodeStrokeOverlayFromBlob({
    required Uint8List blob,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return null;
    if (blob.isEmpty) return null;
    try {
      final native = await _channel.invokeMethod<Uint8List>(
        'encodeStrokeOverlayBytes',
        <String, dynamic>{'blob': blob},
      );
      if (native != null && native.isNotEmpty) return native;
    } catch (e, st) {
      _logPlatformFailure('encodeStrokeOverlayBytes', e, st);
    }
    // Fallback: temp-file path (older native builds).
    try {
      final tempDir = Directory.systemTemp;
      final id = DateTime.now().microsecondsSinceEpoch;
      final blobPath = '${tempDir.path}/saber_stroke_blob_$id.bin';
      final outPath = '${tempDir.path}/saber_stroke_ov_$id.pdf';
      final blobFile = File(blobPath);
      final outFile = File(outPath);
      await blobFile.writeAsBytes(blob, flush: false);
      try {
        final out = await _channel.invokeMethod<String>('encodeStrokeOverlay', {
          'blobPath': blobPath,
          'outputPath': outPath,
        });
        if (out == null || out.isEmpty) return null;
        if (!File(out).existsSync()) return null;
        return await File(out).readAsBytes();
      } finally {
        try {
          if (blobFile.existsSync()) await blobFile.delete();
        } catch (_) {}
        try {
          if (outFile.existsSync()) await outFile.delete();
        } catch (_) {}
      }
    } catch (e, st) {
      _logPlatformFailure('encodeStrokeOverlay', e, st);
      return null;
    }
  }

  /// Android: merges PDFs in [inputPaths] order via PDFBox PDFMergerUtility.
  /// Returns [outputPath] on success; null on other platforms or failure.
  static Future<String?> mergePdfsOrdered({
    required List<String> inputPaths,
    required String outputPath,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return null;
    if (inputPaths.isEmpty) return null;
    try {
      final out = await _channel.invokeMethod<String>('mergePdfs', {
        'paths': inputPaths,
        'outputPath': outputPath,
      });
      if (out == null || out.isEmpty) return null;
      if (!File(out).existsSync()) return null;
      return out;
    } catch (e, st) {
      _logPlatformFailure('mergePdfs', e, st);
      return null;
    }
  }
}
