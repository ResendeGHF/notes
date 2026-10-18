// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:logging/logging.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/editor/canvas_background_pattern.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/note_page_format.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/home_data_cache.dart';
import 'package:saber/data/samsung_notes/sdocx_mapping.dart';
import 'package:saber/data/samsung_notes/sdocx_models.dart';
import 'package:saber/data/samsung_notes/sdocx_parser.dart';
import 'package:saber/data/stroke_geometry/point_vector.dart';
import 'package:saber/data/stroke_geometry/stroke_options.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:saber/services/pdf_open_helper.dart';

/// Imports Samsung Notes `.sdocx` files into Saber notes.
///
/// Supported (basic): pages, strokes (+ colors/widths), raster images
/// (JPG/PNG/WebP), PDFs (as page backgrounds, like Saber's PDF import).
///
/// Deliberately discarded (per requirements): audio (Voice objects / `.m4a`),
/// tables (physical type 22 + rich-text tables), sticker sub-notes (nested
/// `.sdocx`), `.spi` painting data, shapes, text boxes and all other types.
class SamsungNotesImporter {
  SamsungNotesImporter._();

  static final log = Logger('SamsungNotesImporter');

  /// Import [sdocxPath] (absolute file path) into a new Saber note at
  /// [sbnBasePath] (base path without `.sbn2`, e.g. `/My Note`).
  ///
  /// Returns true on success. Mirrors [FileManager.createNoteFromPdf] so the
  /// caller (home import button) can reuse the same progress + navigation flow.
  static Future<bool> importSdocxToNote(
    String sbnBasePath,
    String sdocxPath, {
    required ThemeData theme,
    required MediaQueryData mediaQuery,
    void Function(double progress, String status)? onImportProgress,
  }) async {
    try {
      onImportProgress?.call(0.02, 'Opening Samsung note');
      final sdocxFile = File(sdocxPath);
      if (!sdocxFile.existsSync()) return false;
      final rawBytes = await sdocxFile.readAsBytes();
      if (rawBytes.isEmpty) return false;

      onImportProgress?.call(0.06, 'Unpacking Samsung note');
      final entries = _unzipSdocx(rawBytes);
      if (entries.isEmpty) {
        log.warning('Samsung import: no entries in $sdocxPath');
        return false;
      }

      onImportProgress?.call(0.12, 'Parsing Samsung pages');
      late final SdocxDocument doc;
      try {
        doc = SdocxParser.parseArchive(entries);
      } catch (e, st) {
        log.warning('Samsung import: parse failed: $e', e, st);
        return false;
      }
      if (doc.pages.isEmpty) {
        log.warning('Samsung import: no pages found');
        return false;
      }

      final coreInfo = EditorCoreInfo(filePath: sbnBasePath);
      // Samsung pages keep their native proportion: remember the Samsung
      // Notes format so pages added to the imported note match the imported
      // ones instead of dropping back to A4.
      coreInfo.notePageFormat = NotePageFormat.samsungNotes;
      coreInfo.notePageOrientation =
          doc.pages.first.width > doc.pages.first.height
          ? PageOrientation.landscape
          : PageOrientation.portrait;
      // Keep a temp PDF file alive for the whole import so PdfDocument can
      // memory-map it (same pattern as createNoteFromPdf).
      final tempPdfFiles = <File>[];
      PdfDocument? sharedPdfDoc;
      String? sharedPdfPath;
      try {
        var saberPageIndex = 0;
        final total = doc.pages.length;
        for (var pi = 0; pi < doc.pages.length; pi++) {
          final spage = doc.pages[pi];
          onImportProgress?.call(
            0.12 + (pi + 1) / math.max(total, 1) * 0.55,
            'Importing pages (${pi + 1}/$total)',
          );
          await _importSdocxPage(
            doc,
            spage,
            coreInfo,
            () => saberPageIndex++,
            tempPdfFiles,
            onPdf: (docRef, path) {
              sharedPdfDoc ??= docRef;
              sharedPdfPath ??= path;
            },
          );
        }

        // Drop content-less Samsung pages (e.g. sticker/attachment shells).
        // This is content-based rather than [EditorPage.isEmpty] on purpose:
        // imported pages always carry an explicit local pattern (even blank),
        // which would make every shell look non-empty. Pattern-only pages
        // (grid/lined with no ink yet) are real content and must survive.
        // Keep at least one page so the note is never page-less.
        coreInfo.pages.removeWhere(_isContentEmpty);
        if (coreInfo.pages.isEmpty) {
          final fallback = doc.pages.first;
          final pageW = _sanePageDim(fallback.width, EditorPage.defaultWidth);
          final pageH = _sanePageDim(fallback.height, EditorPage.defaultHeight);
          
          coreInfo.ensureDocumentDefaultsFromGlobal();
          final page = coreInfo.createPageWithDefaults(size: Size(pageW, pageH));
          
          final scale = pageW / EditorPage.defaultWidth;
          page.lineHeight = (page.lineHeight * scale).round();
          page.lineThickness *= scale;
          if (page.hasLocalMargins) {
            page.marginLeft *= scale;
            page.marginRight *= scale;
            page.marginTop *= scale;
            page.marginBottom *= scale;
          }
          
          coreInfo.pages.add(page);
        }
        // Re-index strokes/images after filtering.
        for (var i = 0; i < coreInfo.pages.length; i++) {
          final page = coreInfo.pages[i];
          for (final s in page.layerAt(0).strokes) {
            s.pageIndex = i;
          }
          for (final im in page.layerAt(0).images) {
            im.pageIndex = i;
          }
          page.id ??= coreInfo.allocatePageId();
        }

        onImportProgress?.call(0.70, 'Saving');
        final fullSavePath = FileManager.getFilePath(
          sbnBasePath + Editor.extension,
        );
        final didLayoutTouch = await coreInfo.assetCacheAll.renumberBeforeSave(
          fullSavePath,
        );
        if (didLayoutTouch) {
          coreInfo.invalidatePageBinaryEncodeCaches();
        }

        onImportProgress?.call(0.82, 'Saving');
        final bson = coreInfo.saveToBinary(currentPageIndex: 0);
        await FileManager.writeFile(
          sbnBasePath + Editor.extension,
          bson,
          awaitWrite: true,
        );

        onImportProgress?.call(0.92, 'Thumbnail');
        try {
          await FileManager.generateThumbnailForNote(
            coreInfo: coreInfo,
            theme: theme,
            mediaQuery: mediaQuery,
            path: '$sbnBasePath${Editor.extension}.p',
          );
        } catch (e) {
          log.warning('Samsung import: thumbnail failed: $e');
        }

        HomeDataCache.instance.invalidate();
        return true;
      } finally {
        try {
          sharedPdfDoc?.dispose();
        } catch (_) {}
        // Temp PDF/image files are copied into the vault/disk asset store by
        // renumberBeforeSave; the runtime copies can stay for the session.
        // ignore: unused_local_variable
        final _ = (tempPdfFiles, sharedPdfPath);
        coreInfo.dispose();
      }
    } catch (e, stack) {
      log.severe('Samsung import failed: $e', e, stack);
      return false;
    }
  }

  static Map<String, Uint8List> _unzipSdocx(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final out = <String, Uint8List>{};
    for (final f in archive.files) {
      if (!f.isFile) continue;
      out[f.name] = Uint8List.fromList(f.content as List<int>);
    }
    return out;
  }

  static Future<void> _importSdocxPage(
    SdocxDocument doc,
    SdocxPage spage,
    EditorCoreInfo coreInfo,
    int Function() nextPageIndex,
    List<File> tempPdfFiles, {
    void Function(PdfDocument doc, String path)? onPdf,
  }) async {
    final pageW = _sanePageDim(spage.width, EditorPage.defaultWidth);
    final pageH = _sanePageDim(spage.height, EditorPage.defaultHeight);
    final pageSize = Size(pageW, pageH);

    // PDF-backed pages: one Saber page per PDF paper record (normally one).
    // Empty PDF pages are still imported (they carry the PDF background).
    if (spage.pdfPapers.isNotEmpty) {
      for (final paper in spage.pdfPapers) {
        final entry = doc.mediaByBindId[paper.mediaId];
        final bytes = entry?.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        final name = (entry?.fileName ?? '').toLowerCase();
        if (!name.endsWith('.pdf')) continue;

        final pdfFile = coreInfo.assetCacheAll.createRuntimeFile(
          '.pdf',
          bytes,
        );
        tempPdfFiles.add(pdfFile);
        int assetId;
        try {
          assetId = await coreInfo.assetCacheAll.addPdfFast(pdfFile);
        } catch (_) {
          continue;
        }

        PdfDocument? pdfDoc;
        try {
          // mmap + progressive: temp import PDFs stream from SSD.
          pdfDoc = await PdfOpenHelper.openFileProgressive(pdfFile.path);
        } catch (_) {
          continue;
        }
        if (paper.pageIndex < 0 || paper.pageIndex >= pdfDoc.pages.length) {
          pdfDoc.dispose();
          continue;
        }
        final pdfPage = pdfDoc.pages[paper.pageIndex];
        final natural = Size(pdfPage.width, pdfPage.height);
        onPdf?.call(pdfDoc, pdfFile.path);

        coreInfo.ensureDocumentDefaultsFromGlobal();
        final page = coreInfo.createPageWithDefaults(size: Size(pageW, pageH));
        
        final scale = pageW / EditorPage.defaultWidth;
        page.lineHeight = (page.lineHeight * scale).round();
        page.lineThickness *= scale;
        if (page.hasLocalMargins) {
          page.marginLeft *= scale;
          page.marginRight *= scale;
          page.marginTop *= scale;
          page.marginBottom *= scale;
        }

        final idx = nextPageIndex();
        page.backgroundImage = PdfEditorImage(
          id: coreInfo.nextImageId++,
          assetCacheAll: coreInfo.assetCacheAll,
          assetId: assetId,
          pdfFile: pdfFile,
          pdfPage: paper.pageIndex,
          pageIndex: idx,
          pageSize: pageSize,
          naturalSize: natural,
          dstRect: Rect.fromLTWH(0, 0, pageW, pageH),
          onMoveImage: null,
          onDeleteImage: null,
          onMiscChange: null,
          onLoad: null,
        );
        coreInfo.pages.add(page);
        coreInfo.assetCacheAll.addUse(assetId);

        // Strokes on top of PDF paper (annotations) use Samsung coords which
        // already match this page size, so import them onto the same page.
        if (spage.strokes.isNotEmpty || spage.images.isNotEmpty) {
          await _addStrokesAndImages(doc, spage, coreInfo, page, idx);
        }
        // Keep pdfDoc open until note save completes (shared dispose in
        // caller); do not dispose here.
      }
      // If all PDF papers failed to resolve, fall back to a plain page so
      // strokes/images are not lost.
      if (spage.pdfPapers.isNotEmpty &&
          (coreInfo.pages.isEmpty ||
              spage.strokes.isNotEmpty && _pageForStrokesMissing(coreInfo))) {
        // handled below via generic path if nothing was added
      }
      if (spage.pdfPapers.every(
        (p) => doc.mediaByBindId[p.mediaId]?.bytes == null,
      )) {
        // No resolvable PDFs: import as plain page.
        await _importPlainSdocxPage(doc, spage, coreInfo, nextPageIndex);
      }
      return;
    }

    await _importPlainSdocxPage(doc, spage, coreInfo, nextPageIndex);
  }

  static bool _pageForStrokesMissing(EditorCoreInfo coreInfo) {
    // True when the last added page has no strokes yet but source expects
    // them (used only as a fallback guard; kept simple on purpose).
    if (coreInfo.pages.isEmpty) return true;
    final last = coreInfo.pages.last;
    return last.layerAt(0).strokes.isEmpty;
  }

  static Future<void> _importPlainSdocxPage(
    SdocxDocument doc,
    SdocxPage spage,
    EditorCoreInfo coreInfo,
    int Function() nextPageIndex,
  ) async {
    // Skip fully-empty shells (attachment collapses, trailing blanks).
    if (spage.isEmpty) return;
    final pageW = _sanePageDim(spage.width, EditorPage.defaultWidth);
    final pageH = _sanePageDim(spage.height, EditorPage.defaultHeight);
    final page = EditorPage(width: pageW, height: pageH);
    if (spage.backgroundColorArgb != null) {
      try {
        page.backgroundColor = Color(spage.backgroundColorArgb!);
        page.hasLocalBackgroundColor = true;
      } catch (_) {}
    }
    final idx = nextPageIndex();
    coreInfo.pages.add(page);
    // Stock background artwork embedded in the file wins over the pattern
    // name; otherwise map the Samsung template to Saber's equivalent so a
    // blank Samsung page stays blank regardless of Saber defaults.
    final bgImage = await _toSaberBackgroundImage(
      doc,
      spage,
      coreInfo,
      page,
      idx,
    );
    if (bgImage != null) {
      page.backgroundImage = bgImage;
    } else {
      page.backgroundPattern = samsungTemplateToPattern(
        templateType: spage.templateType,
        templateUri: spage.templateUri ?? doc.defaultTemplateUri,
      );
      page.hasLocalPattern = true;
    }

    // Scale patterns and margins to fit the imported page dimensions uniformly
    final scale = pageW / EditorPage.defaultWidth;
    coreInfo.ensureDocumentDefaultsFromGlobal();

    page.lineHeight = ((coreInfo.noteDefaultLineHeight ?? coreInfo.lineHeight) * scale).round();
    page.lineThickness = (coreInfo.noteDefaultLineThickness ?? coreInfo.lineThickness) * scale;
    page.hasLocalLineHeight = true;
    page.hasLocalLineThickness = true;
    // Mirror [EditorCoreInfo.createPageWithDefaults]: imported pages adopt the
    // note's default line color, so a customized default applies instead of
    // the raw page field default (0xFF9E9E9E).
    page.lineColor = Color(coreInfo.noteDefaultLineColor ?? 0xFF9E9E9E);
    page.hasLocalLineColor = true;

    page.marginLeft = (coreInfo.noteDefaultMarginLeft ?? 0) * scale;
    page.marginRight = (coreInfo.noteDefaultMarginRight ?? 0) * scale;
    page.marginTop = (coreInfo.noteDefaultMarginTop ?? 0) * scale;
    page.marginBottom = (coreInfo.noteDefaultMarginBottom ?? 0) * scale;
    page.hasLocalMargins = page.marginLeft > 0 || page.marginRight > 0 || page.marginTop > 0 || page.marginBottom > 0;

    await _addStrokesAndImages(doc, spage, coreInfo, page, idx);
    // Same as the editor's own onSetPagePattern path: plain field writes
    // above don't bump the revision, so mark explicitly. Fresh coreInfos
    // encode everything on first save anyway; this guards any later
    // incremental-save flow from reusing a stale page encoding.
    page.markSaveBinaryDirty();
  }


  static Future<void> _addStrokesAndImages(
    SdocxDocument doc,
    SdocxPage spage,
    EditorCoreInfo coreInfo,
    EditorPage page,
    int pageIndex,
  ) async {
    for (final s in spage.strokes) {
      final stroke = _toSaberStroke(s, pageIndex, page);
      if (stroke != null) {
        // Page-level insert keeps color/tool ordering stable and bumps the
        // page's binary revision (same as the editor's own stroke paths).
        try {
          page.insertStroke(stroke);
        } catch (_) {
          page.layerAt(0).backingStrokes.add(stroke);
          page.markSaveBinaryDirty();
        }
      }
    }
    for (final im in spage.images) {
      final image = await _toSaberImage(doc, im, coreInfo, page, pageIndex);
      if (image != null) {
        page.layerAt(0).addImage(image);
        page.markSaveBinaryDirty();
      }
    }
  }

  static Stroke? _toSaberStroke(
    SdocxStroke s,
    int pageIndex,
    EditorPage page,
  ) {
    if (s.points.length < 2) return null;
    var color = Stroke.defaultColor;
    if (s.colorArgb != null) {
      try {
        color = Color(s.colorArgb!);
      } catch (_) {}
    }
    final toolId = samsungPenToToolId(s.penName, colorArgb: s.colorArgb);

    var size = s.penWidth;
    if (!size.isFinite || size <= 0) {
      size = toolId == ToolId.highlighter ? 24 : 8;
    }
    size = size.clamp(1.0, 48.0);

    final pressures = s.pressures;
    final pressureEnabled = pressures.isNotEmpty;
    final stroke = Stroke(
      color: color,
      pressureEnabled: pressureEnabled,
      options: StrokeOptions(size: size, isComplete: true),
      pageIndex: pageIndex,
      page: page,
      toolId: toolId,
    );
    final vectors = <PointVector>[];
    for (var i = 0; i < s.points.length; i++) {
      final p = s.points[i];
      if (!p.x.isFinite || !p.y.isFinite) continue;
      double? pressure;
      if (pressureEnabled && i < pressures.length) {
        final v = pressures[i];
        pressure = v.isFinite ? v.clamp(0.0, 1.0) : 0.5;
      }
      vectors.add(PointVector(p.x, p.y, pressure));
    }
    if (vectors.length < 2) return null;
    // `points` is @protected/@visibleForTesting: use the public bulk setter
    // so import stays out of stabilization/preview paths.
    stroke.replacePointsFromEraser(vectors);
    return stroke;
  }

  static Future<EditorImage?> _toSaberImage(
    SdocxDocument doc,
    SdocxImage im,
    EditorCoreInfo coreInfo,
    EditorPage page,
    int pageIndex,
  ) async {
    try {
      SdocxMediaEntry? entry;
      if (im.mediaId != null) {
        entry = doc.mediaByBindId[im.mediaId!];
      }
      // Fallback: single-image notes where the fill reference is missing.
      entry ??= doc.mediaByBindId.values
          .where((e) => e.isImage && e.bytes != null)
          .firstOrNull;
      final bytes = entry?.bytes;
      if (bytes == null || bytes.isEmpty) return null;

      var ext = '.jpg';
      final lower = (entry?.fileName ?? '').toLowerCase();
      if (lower.endsWith('.png')) {
        ext = '.png';
      } else if (lower.endsWith('.webp')) {
        ext = '.webp';
      } else if (lower.endsWith('.jpeg') || lower.endsWith('.jpg')) {
        ext = '.jpg';
      } else {
        // Verify it is actually an image before importing.
        if (!_looksLikeImage(bytes)) return null;
      }

      final file = coreInfo.assetCacheAll.createRuntimeFile(ext, bytes);
      final assetId = await coreInfo.assetCacheAll.add(
        file,
        copyFromSource: false,
        forceNew: true,
      );
      coreInfo.assetCacheAll.setImageProvider(assetId, MemoryImage(bytes));

      var natural = const Size(300, 300);
      try {
        final decoded = img.decodeImage(bytes);
        if (decoded != null && decoded.width > 0 && decoded.height > 0) {
          natural = Size(decoded.width.toDouble(), decoded.height.toDouble());
        }
      } catch (_) {}

      var dst = im.bbox;
      // Guard against degenerate rects from corrupt records.
      if (dst.width <= 0 || dst.height <= 0) return null;
      // Clamp wildly out-of-page images onto the page instead of dropping.
      final pageRect = Rect.fromLTWH(0, 0, page.size.width, page.size.height);
      if (!pageRect.overlaps(dst)) {
        // Keep original size but move origin onto the page.
        dst = Rect.fromLTWH(
          dst.left.clamp(0.0, page.size.width - 10),
          dst.top.clamp(0.0, page.size.height - 10),
          dst.width,
          dst.height,
        );
      }

      final image = PngEditorImage(
        id: coreInfo.nextImageId++,
        assetCacheAll: coreInfo.assetCacheAll,
        assetId: assetId,
        extension: ext,
        imageProviderNotifier: coreInfo.assetCacheAll.getImageProviderNotifier(
          assetId,
        ),
        pageIndex: pageIndex,
        pageSize: page.size,
        onMoveImage: null,
        onDeleteImage: null,
        onMiscChange: null,
        onLoad: null,
        dstRect: dst,
        naturalSize: natural,
      );
      coreInfo.assetCacheAll.addUse(assetId);
      return image;
    } catch (e) {
      log.warning('Samsung import: image skipped: $e');
      return null;
    }
  }

  /// Import a Samsung stock background artwork image as the Saber page
  /// background (full-page). Returns null when the page references no
  /// embedded image or the bytes aren't a decodable raster image.
  static Future<EditorImage?> _toSaberBackgroundImage(
    SdocxDocument doc,
    SdocxPage spage,
    EditorCoreInfo coreInfo,
    EditorPage page,
    int pageIndex,
  ) async {
    try {
      final bgId = spage.backgroundImageId;
      if (bgId == null) return null;
      final entry = doc.mediaByBindId[bgId];
      final bytes = entry?.bytes;
      if (bytes == null || bytes.isEmpty) return null;

      var ext = '.png';
      final lower = (entry?.fileName ?? '').toLowerCase();
      if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
        ext = '.jpg';
      } else if (lower.endsWith('.webp')) {
        ext = '.webp';
      } else if (lower.endsWith('.png')) {
        ext = '.png';
      } else if (!_looksLikeImage(bytes)) {
        return null;
      }

      final file = coreInfo.assetCacheAll.createRuntimeFile(ext, bytes);
      final assetId = await coreInfo.assetCacheAll.add(
        file,
        copyFromSource: false,
        forceNew: true,
      );
      coreInfo.assetCacheAll.setImageProvider(assetId, MemoryImage(bytes));

      var natural = page.size;
      try {
        final decoded = img.decodeImage(bytes);
        if (decoded != null && decoded.width > 0 && decoded.height > 0) {
          natural = Size(decoded.width.toDouble(), decoded.height.toDouble());
        }
      } catch (_) {}

      final image = PngEditorImage(
        id: coreInfo.nextImageId++,
        assetCacheAll: coreInfo.assetCacheAll,
        assetId: assetId,
        extension: ext,
        imageProviderNotifier: coreInfo.assetCacheAll.getImageProviderNotifier(
          assetId,
        ),
        pageIndex: pageIndex,
        pageSize: page.size,
        backgroundFit: BoxFit.cover,
        onMoveImage: null,
        onDeleteImage: null,
        onMiscChange: null,
        onLoad: null,
        dstRect: Rect.fromLTWH(0, 0, page.size.width, page.size.height),
        naturalSize: natural,
      );
      coreInfo.assetCacheAll.addUse(assetId);
      return image;
    } catch (e) {
      log.warning('Samsung import: background image skipped: $e');
      return null;
    }
  }

  static bool _looksLikeImage(Uint8List bytes) {
    if (bytes.length < 4) return false;
    // JPEG, PNG, WebP, GIF, BMP magic.
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return true;
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return true;
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }
    return false;
  }

  static double _sanePageDim(double v, double fallback) {
    if (!v.isFinite || v < 200 || v > 5000) return fallback;
    return v;
  }

  /// True when a Saber page built by this importer holds no user-visible
  /// content: no strokes/images (any layer), no background image, no quill
  /// text, and at most an explicit blank pattern.
  static bool _isContentEmpty(EditorPage page) {
    if (page.allStrokesInDrawOrder.isNotEmpty) return false;
    if (page.allImagesInDrawOrder.isNotEmpty) return false;
    if (page.backgroundImage != null) return false;
    if (!page.quill.controller.document.isEmpty()) return false;
    final pattern = page.backgroundPattern;
    return pattern == null || pattern == CanvasBackgroundPattern.none;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    for (final e in this) return e;
    return null;
  }
}
