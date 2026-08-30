// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io' show File, Platform;
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image/image.dart' as img;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_drawing/path_drawing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_combiner/pdf_combiner.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:saber/components/canvas/_canvas_background_painter.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_shape_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
import 'package:saber/data/editor/canvas_background_pattern.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/link_export_expander.dart';
import 'package:saber/data/editor/page.dart' show EditorPage;
import 'package:saber/data/editor/pdf_export_spine.dart';
import 'package:saber/data/editor/pdf_outline.dart';
import 'package:saber/data/editor/pdf_stroke_vector_encoder.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/services/pdf_stroke_overlay.dart';
import 'package:saber/services/perf_timing.dart';
import 'package:saber/services/vault_adapter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:uuid/uuid.dart';

/// Result of [EditorExporter.generatePdfData]: either in-memory bytes (small /
/// fallback exports) or a temporary PDF on disk (large pdfrx assembled export).
/// Callers must pass a temp path to [FileManager.exportPdfTempFile], which
/// shares or copies the file then deletes it securely.
class PdfExportData {
  PdfExportData._({this.bytes, this.tempPdfPath})
    : assert(
        (bytes != null) ^ (tempPdfPath != null),
        'Exactly one of bytes or tempPdfPath must be set',
      );

  factory PdfExportData.bytes(Uint8List bytes) => PdfExportData._(bytes: bytes);

  factory PdfExportData.tempFile(String path) =>
      PdfExportData._(tempPdfPath: path);

  final Uint8List? bytes;

  /// Absolute path to a UTF-8 PDF; caller must not delete until after export.
  final String? tempPdfPath;
}

class _RecipeStampPayload {
  _RecipeStampPayload._({
    this.vectorBytes,
    this.pngBytes,
    this.vectorMergedPage0,
  }) : assert(
         vectorMergedPage0 != null
             ? vectorBytes == null && pngBytes == null
             : (vectorBytes != null && vectorBytes.isNotEmpty) ^
                   (pngBytes != null && pngBytes.isNotEmpty),
       );

  factory _RecipeStampPayload.vector(Uint8List b) =>
      _RecipeStampPayload._(vectorBytes: b);
  factory _RecipeStampPayload.png(Uint8List b) =>
      _RecipeStampPayload._(pngBytes: b);

  /// Page index in a shared multi-page overlay PDF produced by
  /// [_encodeVectorStrokeOverlaysPdfMerged].
  factory _RecipeStampPayload.vectorMergedPage(int overlayPage0) =>
      _RecipeStampPayload._(vectorMergedPage0: overlayPage0);

  final Uint8List? vectorBytes;
  final Uint8List? pngBytes;
  final int? vectorMergedPage0;
}

class _JpegEncodeArgs {
  const _JpegEncodeArgs({
    required this.rgba,
    required this.width,
    required this.height,
    required this.quality,
  });

  final TransferableTypedData rgba;
  final int width;
  final int height;
  final int quality;
}

Uint8List _encodeJpegInIsolate(_JpegEncodeArgs args) {
  final rgba = args.rgba.materialize().asUint8List();
  final decoded = img.Image.fromBytes(
    width: args.width,
    height: args.height,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(img.encodeJpg(decoded, quality: args.quality));
}

final _vaultAssetNumericSuffixRe = RegExp(r'\.sbn2\.\d+$');

class _RasterExportCache {
  final Map<String, pdfrx.PdfDocument> _pdfDocuments = {};
  final Map<String, Future<pdfrx.PdfDocument?>> _pdfOpenFutures = {};

  /// Export must not call [PdfDocument.loadPagesProgressively]: that prefetches
  /// every page and exhausts memory on large imports (while also making export
  /// feel hung). Pages load on demand via [PdfPage.render].

  static Future<pdfrx.PdfDocument> _openPdfFileForRaster(String path) async {
    return pdfrx.PdfDocument.openFile(path, useProgressiveLoading: true);
  }

  static Future<pdfrx.PdfDocument> _openPdfDataForRaster(
    Uint8List bytes,
  ) async {
    return pdfrx.PdfDocument.openData(bytes, useProgressiveLoading: true);
  }

  Future<ui.Image?> png(PngEditorImage image) {
    return EditorExporter._decodePngEditorImage(image);
  }

  Future<ui.Image?> svg(SvgEditorImage image) {
    return EditorExporter._rasterizeSvgEditorImage(image);
  }

  Future<ui.Image?> pdf(PdfEditorImage image, double pixelRatio) {
    return _pdfDocument(image).then(
      (document) => document == null
          ? null
          : EditorExporter._rasterizePdfPage(
              document,
              image.pdfPage,
              image.naturalSize,
              pixelRatio,
            ),
    );
  }

  Future<pdfrx.PdfDocument?> _pdfDocument(PdfEditorImage image) {
    final file = image.pdfFile;
    final source = file?.path ?? 'asset:${image.assetId}';
    final existing = _pdfDocuments[source];
    if (existing != null) return Future.value(existing);

    return _pdfOpenFutures.putIfAbsent(source, () {
      final fut = () async {
        try {
          final pdfrx.PdfDocument document;
          final path = file?.path;
          final norm = path?.replaceAll('\\', '/') ?? '';
          final useVaultTemp =
              path != null &&
              stows.localEncryptionEnabled.value &&
              VaultAdapter.isUnlocked &&
              _vaultAssetNumericSuffixRe.hasMatch(norm);

          if (useVaultTemp) {
            // Prefer temp/mmap when Secure PDF loading allows disk; otherwise
            // decrypt into RAM and openData — never write plaintext temps.
            final tempPath = await FileManager.readFileToTempFile(path);
            if (tempPath != null) {
              document = await _openPdfFileForRaster(tempPath);
            } else {
              final bytes = await FileManager.readFile(path);
              if (bytes == null || bytes.isEmpty) return null;
              document = await _openPdfDataForRaster(
                EditorExporter._asUint8List(bytes),
              );
            }
          } else if (file != null && await file.exists()) {
            document = await _openPdfFileForRaster(file.path);
          } else {
            final bytes = await image.assetCacheAll.getBytes(image.assetId);
            if (bytes.isEmpty) return null;
            document = await _openPdfDataForRaster(
              EditorExporter._asUint8List(bytes),
            );
          }
          _pdfDocuments[source] = document;
          return document;
        } finally {
          _pdfOpenFutures.remove(source);
        }
      }();
      return fut;
    });
  }

  void dispose() {
    for (final document in _pdfDocuments.values) {
      document.dispose();
    }
    _pdfDocuments.clear();
    _pdfOpenFutures.clear();
  }
}

class _AssembledExportSlot {
  _AssembledExportSlot({
    this.page,
    this.extraDoc,
    this.tempFileToDelete,
    this.nativePdfPartPath,
  }) : assert(
         page != null || nativePdfPartPath != null,
         'Assembled export slot needs a pdfrx page and/or a native PDF path',
       );

  final pdfrx.PdfPage? page;
  final pdfrx.PdfDocument? extraDoc;
  final String? tempFileToDelete;

  /// Single-page PDF on disk (Android PDFBox extract + stamp). When non-null,
  /// hybrid export can skip PDFium [encodePdf] for this chunk.
  final String? nativePdfPartPath;

  pdfrx.PdfDocument? _docOpenedForEncodeMerge;
  bool _nativePathHandedOff = false;

  void markNativePathHandedOff() {
    _nativePathHandedOff = true;
  }

  Future<pdfrx.PdfPage> resolvePageForPdfiumEncode() async {
    if (page != null) return page!;
    final path = nativePdfPartPath;
    if (path == null) {
      throw StateError('_AssembledExportSlot: no page or native path');
    }
    _docOpenedForEncodeMerge = await pdfrx.PdfDocument.openFile(
      path,
      useProgressiveLoading: true,
    );
    return await _docOpenedForEncodeMerge!.pages[0].ensureLoaded();
  }

  Future<void> disposeExtra() async {
    await _docOpenedForEncodeMerge?.dispose();
    _docOpenedForEncodeMerge = null;
    await extraDoc?.dispose();
    if (!_nativePathHandedOff && tempFileToDelete != null) {
      try {
        File(tempFileToDelete!).deleteSync();
      } catch (_) {}
    }
  }
}

abstract class EditorExporter {
  static final _log = Logger('EditorExporter');

  /// Counts Android [PdfStrokeOverlay.extractPageRangesBatch] invocations per
  /// [_buildHybridSpinePdfrxPartPaths] run (for [export.metrics] logs).
  static int _hybridSpinePdfBoxBatchInvocations = 0;

  /// Counts [pdfrx.PdfDocument.encodePdf] calls inside composed export chunks per
  /// [_buildHybridSpinePdfrxPartPaths] run.
  static int _hybridSpinePdfiumEncodeCalls = 0;

  /// Line color used in export when the page uses the default line gray. Matches
  /// [Page]'s default and avoids theme primary/secondary (e.g. blue/red) in PDF
  /// screenshots and JPEG raster backgrounds.
  static const exportDefaultLineGray = Color(0xFF9E9E9E);

  /// Default raster scale for PDF / screenshot export (lower on mobile for speed).
  static double defaultPdfRasterPixelRatio() =>
      (Platform.isAndroid || Platform.isIOS) ? 2.1 : 3.2;

  /// Keep image export inversion identical to [InvertWidget].
  static const _invertColorFilter = ColorFilter.matrix(<double>[
    1 - 2 * 0.213,
    -2 * 0.715,
    -2 * 0.072,
    0,
    255,
    -2 * 0.213,
    1 - 2 * 0.715,
    -2 * 0.072,
    0,
    255,
    -2 * 0.213,
    -2 * 0.715,
    1 - 2 * 0.072,
    0,
    255,
    0,
    0,
    0,
    1,
    0,
  ]);

  static bool _shouldRasterizeStroke(Stroke stroke) {
    return stroke.toolId == .highlighter || stroke is ShapeStroke;
  }

  /// Pattern actually painted behind content on this page (matches
  /// [_rasterizePageForRasterExport]).
  static CanvasBackgroundPattern _effectiveExportPattern(
    EditorCoreInfo info,
    EditorPage page,
  ) {
    if (page.backgroundImage != null) return CanvasBackgroundPattern.none;
    return page.backgroundPattern ?? info.backgroundPattern;
  }

  /// Pages that are only a PDF background plus vector strokes/images that go
  /// through the same raster pipeline with [includeStrokes: false] — no Quill,
  /// no invert (invert must touch the bitmap), no non-PDF overlays.
  ///
  /// True embedded vector PDF pages are not available via the open-source
  /// `package:pdf` API alone ([PdfDocumentParserBase] has no public
  /// implementation here); we reduce raster resolution instead for speed.
  static bool _isPdfBackgroundOnlyExportPage(
    EditorCoreInfo info,
    EditorPage page,
    bool invert,
  ) {
    if (invert) return false;
    if (_needsWidgetRasterExport(page)) return false;
    if (page.backgroundImage is! PdfEditorImage) return false;
    if (page.allImagesInDrawOrder.isNotEmpty) return false;
    return true;
  }

  /// Caps longest bitmap edge for PDF-background-only pages so pdfrx render +
  /// JPEG stay fast on thousand-page imports without changing stroke vectors.
  static double _rasterRatioForPdfExportCapture({
    required EditorCoreInfo info,
    required EditorPage page,
    required bool invert,
    required double baseRatio,
    required int totalExportPages,
  }) {
    if (!_isPdfBackgroundOnlyExportPage(info, page, invert)) return baseRatio;
    final size = page.size;
    if (size.width <= 0 || size.height <= 0) return baseRatio;

    // Long-edge cap for PDF-background-only raster fallback. Hybrid export keeps
    // most pages as vector; this path is only for pages that must be baked to
    // bitmap. Values below ~1200px were unreadable on dense textbook PDFs.
    final maxSideCap = totalExportPages > 1600
        ? 1320.0
        : (totalExportPages > 1200
              ? 1440.0
              : (totalExportPages > 700
                    ? 1680.0
                    : (totalExportPages > 350 ? 2048.0 : 2560.0)));

    var r = baseRatio;
    final rw = size.width * r;
    final rh = size.height * r;
    final longest = math.max(rw, rh);
    if (longest > maxSideCap) {
      r *= maxSideCap / longest;
    }
    return r;
  }

  /// Raster (or Quill screenshot) for one export page; used in batches for speed.
  static Future<Uint8List?> _captureExportPageRasterBytes({
    required EditorCoreInfo infoToExport,
    required BuildContext context,
    required int pageIndex,
    required bool invert,
    required double effectiveRasterRatio,
    required int totalExportPages,
    required ScreenshotController screenshotController,
    required _RasterExportCache rasterCache,
  }) async {
    final page = infoToExport.pages[pageIndex];
    final effPattern = _effectiveExportPattern(infoToExport, page);
    final needsRaster =
        page.backgroundImage != null ||
        page.allImagesInDrawOrder.isNotEmpty ||
        effPattern != CanvasBackgroundPattern.none;
    if (!needsRaster) return null;
    final captureRatio = _rasterRatioForPdfExportCapture(
      info: infoToExport,
      page: page,
      invert: invert,
      baseRatio: effectiveRasterRatio,
      totalExportPages: totalExportPages,
    );
    if (_needsWidgetRasterExport(page)) {
      return screenshotPage(
        coreInfo: infoToExport,
        pageIndex: pageIndex,
        screenshotController: screenshotController,
        context: context,
        invert: invert,
        fullPage: true,
        pixelRatio: captureRatio,
      );
    }
    final pageImage = await _rasterizePageForRasterExport(
      infoToExport,
      pageIndex: pageIndex,
      invert: invert,
      pixelRatio: captureRatio,
      cache: rasterCache,
      includeStrokes: false,
    );
    try {
      return await _encodeUiImageAsJpeg(pageImage, captureRatio);
    } finally {
      pageImage.dispose();
    }
  }

  static bool _isMultipleOf90Degrees(double degrees) {
    final snapped = (degrees / 90.0).round() * 90.0;
    return (degrees - snapped).abs() < 0.01;
  }

  static pdfrx.PdfPageRotation _pdfRotationDeltaFromDegrees(double degrees) {
    var q = (degrees / 90.0).round() % 4;
    if (q < 0) q += 4;
    return pdfrx.PdfPageRotation.values[q];
  }

  /// PDF page size in points for stroke overlays. For PDF backgrounds, uses
  /// [PdfEditorImage.naturalSize]; otherwise [EditorPage.size].
  static Size _exportOverlaySizeForPage(EditorPage page) {
    final bg = page.backgroundImage;
    if (bg is PdfEditorImage) {
      final n = bg.naturalSize;
      if (n.width > 0 && n.height > 0) {
        return n;
      }
    }
    return page.size;
  }

  /// Maps stroke coordinates (full [EditorPage.size]) onto the exported PDF
  /// media box ([exportSize] in points).
  ///
  /// PDF backgrounds are laid out in [PdfEditorImage.dstRect] (see
  /// [EditorImage.resize]); ink uses the whole page, so we subtract
  /// [(tx, ty)] and scale by the drawable rect, not the full page.
  static ({Size exportSize, double tx, double ty, double sx, double sy})
  _exportStrokeBasisForPage(EditorPage page) {
    final exportSize = _exportOverlaySizeForPage(page);
    final bg = page.backgroundImage;
    if (bg is PdfEditorImage) {
      final dst = bg.dstRect;
      if (dst.width > 0 && dst.height > 0) {
        return (
          exportSize: exportSize,
          tx: dst.left,
          ty: dst.top,
          sx: exportSize.width / dst.width,
          sy: exportSize.height / dst.height,
        );
      }
    }
    final editor = page.size;
    final sx = editor.width > 0 ? exportSize.width / editor.width : 1.0;
    final sy = editor.height > 0 ? exportSize.height / editor.height : 1.0;
    return (exportSize: exportSize, tx: 0.0, ty: 0.0, sx: sx, sy: sy);
  }

  /// Vector ink only (for PDF stamping on top of a vector page).
  ///
  /// [package:pdf]'s [PdfGraphics.setFillColor] ignores alpha in [PdfColor];
  /// semi-transparent ink must use [PdfGraphicState] (`ca` / `CA`). Highlighter
  /// matches [CanvasPainter]: [BlendMode.darken] on light backgrounds and
  /// [BlendMode.plus] when inverted ([PdfBlendMode.screen] is the closest PDF
  /// blend for additive light).
  static void paintVectorStrokesForPdfExport(
    PdfGraphics canvas,
    EditorPage page,
    bool invert,
  ) {
    PdfStrokeVectorEncoder.paintPageStrokes(canvas, page, invert);
  }

  static Future<Uint8List> _encodeVectorStrokeOverlayPdf(
    EditorPage page,
    bool invert,
  ) async {
    return _encodeVectorStrokeOverlaysPdfMerged([page], invert);
  }

  /// One multi-page PDF (transparent pages) in [pages] order: page *k* is the
  /// vector ink for [pages]\[k\]. Avoids N separate [pw.Document.save] calls and
  /// N small temp files before native stamping.
  static Future<Uint8List> _encodeVectorStrokeOverlaysPdfMerged(
    List<EditorPage> pages,
    bool invert,
  ) async {
    if (pages.isEmpty) return Uint8List(0);

    await PdfStrokeVectorEncoder.prepareExportPolygons(pages);

    // Android: PDFBox builds the overlay from packed polygons (no package:pdf
    // SVG/widget path). Huge win for dense handwriting.
    if (!kIsWeb &&
        Platform.isAndroid &&
        PdfStrokeVectorEncoder.pagesAreNativeEncodable(pages)) {
      try {
        final blob = PdfStrokeVectorEncoder.packNativeOverlayBlob(
          pages: pages,
          invert: invert,
          exportSizeOf: _exportOverlaySizeForPage,
          strokeBasisOf: (page) {
            final b = _exportStrokeBasisForPage(page);
            return (tx: b.tx, ty: b.ty, sx: b.sx, sy: b.sy);
          },
        );
        final native = await PdfStrokeOverlay.encodeStrokeOverlayFromBlob(
          blob: blob,
        );
        if (native != null && native.isNotEmpty) {
          _log.info(
            '[export.metrics] native_stroke_overlay pages=${pages.length} '
            'bytes=${native.length} points≈${PdfStrokeVectorEncoder.estimatePointCount(pages)}',
          );
          return native;
        }
      } on Object catch (e, st) {
        _log.warning(
          'native stroke overlay encode failed; using Dart PdfDocument path',
          e,
          st,
        );
      }
    }

    return PdfStrokeVectorEncoder.encodeOverlayPdf(
      pages: pages,
      invert: invert,
      exportSizeOf: _exportOverlaySizeForPage,
      strokeBasisOf: (page) {
        final b = _exportStrokeBasisForPage(page);
        return (tx: b.tx, ty: b.ty, sx: b.sx, sy: b.sy);
      },
    );
  }

  /// Pixel ratio for stroke-only PNG overlay (decoupled from full-page JPEG caps).
  /// Capped moderately so multi-page stamp exports stay fast on device.
  static double _strokeOverlayPixelRatio(Size size) {
    const maxEdge = 2400.0;
    final long = math.max(size.width, size.height);
    if (long <= 0) return 2.5;
    return (maxEdge / long).clamp(2.0, 4.0);
  }

  static Future<Uint8List?> _encodeStrokesOnlyPngBytes({
    required EditorPage page,
    required bool invert,
  }) async {
    if (page.allStrokesInDrawOrder.isEmpty) return null;
    await PdfStrokeVectorEncoder.prepareExportPolygons([page]);
    final basis = _exportStrokeBasisForPage(page);
    final exportSize = basis.exportSize;
    final pixelRatio = _strokeOverlayPixelRatio(exportSize);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.save();
    if (pixelRatio != 1.0) {
      canvas.scale(pixelRatio, pixelRatio);
    }
    canvas.translate(-basis.tx, -basis.ty);
    canvas.scale(basis.sx, basis.sy);
    canvas.translate(0, exportSize.height);
    canvas.scale(1, -1);

    for (final stroke in page.allStrokesInDrawOrder) {
      final color = stroke.color.withInversion(invert);
      final isPolygonStroke =
          stroke is! CircleStroke &&
          stroke is! RectangleStroke &&
          stroke is! ShapeStroke;
      final shapeStroke = stroke is ShapeStroke ? stroke : null;

      late final Path path;
      if (isPolygonStroke) {
        final poly = PdfStrokeVectorEncoder.exportPolygon(stroke);
        if (poly.length < 2) continue;
        path = Path()
          ..addPolygon([
            for (final p in poly)
              Offset(p.dx, PdfStrokeVectorEncoder.pdfY(p.dy, page.size.height)),
          ], true);
      } else {
        final pathStr = stroke.toSvgPath();
        if (pathStr.isEmpty) continue;
        path = parseSvgPathData(pathStr);
      }

      if (isPolygonStroke) {
        final paint = Paint()
          ..color = color
          ..style = PaintingStyle.fill
          ..isAntiAlias = true;
        if (stroke.toolId == ToolId.highlighter) {
          paint.blendMode = invert ? BlendMode.plus : BlendMode.darken;
        }
        canvas.drawPath(path, paint);
      } else if (shapeStroke != null && shapeStroke.fill) {
        final fillPaint = Paint()
          ..color = shapeStroke.fillColor.withInversion(invert)
          ..style = PaintingStyle.fill
          ..isAntiAlias = true;
        canvas.drawPath(path, fillPaint);
        final strokePaint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke.options.size
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
        if (stroke.toolId == ToolId.highlighter) {
          strokePaint.blendMode = invert ? BlendMode.plus : BlendMode.darken;
        }
        canvas.drawPath(path, strokePaint);
      } else {
        final paint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke.options.size
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
        if (stroke.toolId == ToolId.highlighter) {
          paint.blendMode = invert ? BlendMode.plus : BlendMode.darken;
        }
        canvas.drawPath(path, paint);
      }
    }

    canvas.restore();

    final picture = recorder.endRecording();
    final aspect = exportSize.height > 0
        ? exportSize.width / exportSize.height
        : 1.0;
    var w = (exportSize.width * pixelRatio).round().clamp(1, 16384);
    var h = (w / aspect).round().clamp(1, 16384);
    if (h > 16384) {
      h = 16384;
      w = (h * aspect).round().clamp(1, 16384);
    }
    final uiImg = await picture.toImage(w, h);
    try {
      final bd = await uiImg.toByteData(format: ui.ImageByteFormat.png);
      return bd?.buffer.asUint8List();
    } finally {
      uiImg.dispose();
    }
  }

  static Future<_AssembledExportSlot?> _assembleOneExportPage({
    required EditorCoreInfo info,
    required pdfrx.PdfDocument srcDoc,
    required String sharedPdfPath,

    /// Decrypted on-disk PDF (Android PDFBox). Enables fast stream-copy for
    /// single-page bases instead of PDFium [encodePdf] per page.
    String? plainPdfPathForNativeExtract,
    required int pageIndex,
    required int totalPages,
    required double effectiveRasterRatio,
    required bool invert,
    required BuildContext context,
    required ScreenshotController screenshotController,
  }) async {
    info.ensurePageHydrated(pageIndex);
    final page = info.pages[pageIndex];
    final bgImg = page.backgroundImage;
    if (bgImg is! PdfEditorImage) return null;
    if ((bgImg.pdfFile?.path ?? '') != sharedPdfPath) return null;
    final bg = bgImg;
    final pi = bg.pdfPage;
    if (pi < 0 || pi >= srcDoc.pages.length) return null;

    final hasStrokes = page.allStrokesInDrawOrder.isNotEmpty;
    final vectorRotationOk = _isMultipleOf90Degrees(bg.rotationDeg);
    final hasEmbImages = page.allImagesInDrawOrder.isNotEmpty;
    final hasQuill = _pageHasQuillContent(page);

    if (hasQuill) {
      final capRatio = _rasterRatioForPdfExportCapture(
        info: info,
        page: page,
        invert: invert,
        baseRatio: effectiveRasterRatio,
        totalExportPages: totalPages,
      );
      final shotBytes = await screenshotPage(
        coreInfo: info,
        pageIndex: pageIndex,
        screenshotController: screenshotController,
        context: context,
        invert: invert,
        fullPage: true,
        pixelRatio: capRatio,
      );
      final uiImg = await _decodeUiImage(shotBytes);
      try {
        final jpegBytes = await _encodeUiImageAsJpeg(uiImg, capRatio);
        final size = page.size;
        final jpegDoc = await pdfrx.PdfDocument.createFromJpegData(
          jpegBytes,
          width: size.width,
          height: size.height,
          sourceName: 'saber_export_quill_$pageIndex',
        );
        return _AssembledExportSlot(
          page: await jpegDoc.pages[0].ensureLoaded(),
          extraDoc: jpegDoc,
        );
      } finally {
        uiImg.dispose();
      }
    }

    if (!hasStrokes && vectorRotationOk && !hasEmbImages) {
      var p = await srcDoc.pages[pi].ensureLoaded();
      final delta = _pdfRotationDeltaFromDegrees(bg.rotationDeg);
      if (delta != pdfrx.PdfPageRotation.none) {
        p = p.rotatedBy(delta);
      }
      return _AssembledExportSlot(page: p);
    }

    if (hasStrokes &&
        vectorRotationOk &&
        !kIsWeb &&
        Platform.isAndroid &&
        !hasEmbImages) {
      pdfrx.PdfDocument? baseOne;
      try {
        final tempDir = await getTemporaryDirectory();
        final basePath = p.join(
          tempDir.path,
          'saber_vec_base_${const Uuid().v4()}.pdf',
        );
        final delta = _pdfRotationDeltaFromDegrees(bg.rotationDeg);
        var haveBaseFile = false;
        if (plainPdfPathForNativeExtract != null &&
            delta == pdfrx.PdfPageRotation.none) {
          final extracted = await PdfStrokeOverlay.extractPageRangeInclusive(
            sourcePath: plainPdfPathForNativeExtract,
            startPage0: pi,
            endPage0Inclusive: pi,
            outputPath: basePath,
          );
          haveBaseFile = extracted != null;
        }
        if (!haveBaseFile) {
          baseOne = await pdfrx.PdfDocument.createNew(
            sourceName: 'saber_base1',
          );
          var bp = await srcDoc.pages[pi].ensureLoaded();
          if (delta != pdfrx.PdfPageRotation.none) {
            bp = bp.rotatedBy(delta);
          }
          baseOne.pages = [bp];
          final baseBytes = await baseOne.encodePdf();
          await baseOne.dispose();
          baseOne = null;
          await File(basePath).writeAsBytes(baseBytes, flush: true);
        }

        final outPdfPath = p.join(
          tempDir.path,
          'saber_vec_out_${const Uuid().v4()}.pdf',
        );
        String? overlayPath;
        Uint8List? overlayBytes;
        try {
          overlayBytes = await _encodeVectorStrokeOverlayPdf(page, invert);
        } on Object catch (e, st) {
          _log.warning(
            'export: vector overlay encode failed pageIndex=$pageIndex '
            'pdfPage=$pi (platform=${Platform.operatingSystem})',
            e,
            st,
          );
        }
        if (overlayBytes != null && overlayBytes.isNotEmpty) {
          overlayPath = p.join(
            tempDir.path,
            'saber_vec_ink_${const Uuid().v4()}.pdf',
          );
          await File(overlayPath).writeAsBytes(overlayBytes, flush: true);
        }

        var stamped = overlayPath != null
            ? await PdfStrokeOverlay.stamp(
                basePath: basePath,
                overlayPath: overlayPath,
                outputPath: outPdfPath,
              )
            : null;

        if (stamped == null) {
          if (overlayPath != null) {
            _log.warning(
              'export fallback: vector PDF stamp failed pageIndex=$pageIndex '
              'pdfPage=$pi; trying PNG overlay '
              '(platform=${Platform.operatingSystem})',
            );
          }
          final pngBytes = await _encodeStrokesOnlyPngBytes(
            page: page,
            invert: invert,
          );
          if (pngBytes != null && pngBytes.isNotEmpty) {
            final pngPath = p.join(
              tempDir.path,
              'saber_stroke_${const Uuid().v4()}.png',
            );
            await File(pngPath).writeAsBytes(pngBytes, flush: true);
            final pngOutPath = p.join(
              tempDir.path,
              'saber_png_stamp_${const Uuid().v4()}.pdf',
            );
            final stampPts = _exportOverlaySizeForPage(page);
            stamped = await PdfStrokeOverlay.stampPngOverlay(
              basePath: basePath,
              pngPath: pngPath,
              outputPath: pngOutPath,
              pageWidthPt: stampPts.width,
              pageHeightPt: stampPts.height,
              darkenBlend: !invert,
            );
            try {
              File(pngPath).deleteSync();
            } catch (_) {}
            if (stamped == null) {
              try {
                File(pngOutPath).deleteSync();
              } catch (_) {}
            }
          }
        }

        try {
          File(basePath).deleteSync();
        } catch (_) {}
        if (overlayPath != null) {
          try {
            File(overlayPath).deleteSync();
          } catch (_) {}
        }

        if (stamped != null) {
          return _AssembledExportSlot(
            nativePdfPartPath: stamped,
            tempFileToDelete: stamped,
          );
        }
        try {
          File(outPdfPath).deleteSync();
        } catch (_) {}
      } catch (_) {
        await baseOne?.dispose();
      }
    }

    _log.warning(
      'export fallback: full-page JPEG raster pageIndex=$pageIndex pdfPage=$pi '
      '(platform=${Platform.operatingSystem})',
    );
    final capRatio = _rasterRatioForPdfExportCapture(
      info: info,
      page: page,
      invert: invert,
      baseRatio: effectiveRasterRatio,
      totalExportPages: totalPages,
    );
    final pageImage = await _rasterizePageForRasterExport(
      info,
      pageIndex: pageIndex,
      invert: invert,
      pixelRatio: capRatio,
      includeStrokes: hasStrokes,
      reusePdfForBackground: srcDoc,
    );
    final jpegBytes = await _encodeUiImageAsJpeg(pageImage, capRatio);
    pageImage.dispose();

    final size = page.size;
    final jpegDoc = await pdfrx.PdfDocument.createFromJpegData(
      jpegBytes,
      width: size.width,
      height: size.height,
      sourceName: 'saber_export_raster_$pageIndex',
    );
    return _AssembledExportSlot(
      page: await jpegDoc.pages[0].ensureLoaded(),
      extraDoc: jpegDoc,
    );
  }

  /// Chunk size for splitting large PDF exports ([encodePdf] + merge). Lower on
  /// mobile reduces peak native heap during PDFium encode at the cost of more
  /// parts and merge work.
  static const _exportChunkPagesIOS = 16;

  /// Android phones (esp. arm64) typically have enough RAM for larger PDFium
  /// batches; this cuts export time for thousand-page PDFs vs 16-page chunks.
  static const _exportChunkPagesAndroid = 72;
  static const _exportChunkPagesDesktop = 64;

  static int _exportChunkPageCap() {
    if (kIsWeb) return _exportChunkPagesDesktop;
    if (Platform.isAndroid) return _exportChunkPagesAndroid;
    if (Platform.isIOS) return _exportChunkPagesIOS;
    return _exportChunkPagesDesktop;
  }

  /// Vault assets are not always readable as plain [File] paths; PDFium and
  /// Android PDFBox need a decrypted filesystem file when Temp mode is allowed.
  /// In RAM-only mode, returns null (caller should use in-memory bytes instead).
  /// Caller must delete [decryptTempToDelete] after PDF handles are closed.
  static Future<({String plainPath, String? decryptTempToDelete})?>
  _resolvePlainPdfPathForExport(String logicalPath) async {
    if (logicalPath.isEmpty) return null;
    try {
      if (await File(logicalPath).exists()) {
        return (plainPath: logicalPath, decryptTempToDelete: null);
      }
    } catch (_) {}
    if (!await FileManager.doesFileExist(logicalPath)) return null;
    final tmp = await FileManager.readFileToTempFile(logicalPath);
    if (tmp == null) return null;
    return (plainPath: tmp, decryptTempToDelete: tmp);
  }

  static Future<void> _tryDeleteExportTempFile(String? path) async {
    if (path == null) return;
    try {
      await File(path).delete();
    } catch (_) {}
  }

  static Future<int?> _pdfPageCountOnPlainFile(String plainPath) async {
    if (!kIsWeb && Platform.isAndroid) {
      final c = await PdfStrokeOverlay.getPdfPageCount(plainPath);
      if (c != null && c >= 1) return c;
    }
    pdfrx.PdfDocument? doc;
    try {
      doc = await pdfrx.PdfDocument.openFile(
        plainPath,
        useProgressiveLoading: true,
      );
      return doc.pages.length;
    } on Object catch (e, st) {
      _log.warning(
        'pdf page count: failed to open plainPath '
        '(platform=${Platform.operatingSystem})',
        e,
        st,
      );
      return null;
    } finally {
      await doc?.dispose();
    }
  }

  static Future<bool> _validatePassthroughOutputPageCount(
    String path,
    int expected,
  ) async {
    pdfrx.PdfDocument? doc;
    try {
      doc = await pdfrx.PdfDocument.openFile(path, useProgressiveLoading: true);
      final len = doc.pages.length;
      if (len == expected) return true;
      _log.severe(
        'Passthrough PDF page count mismatch: expected $expected, got $len '
        '(platform=${Platform.operatingSystem})',
      );
      return false;
    } on Object catch (e, st) {
      _log.severe(
        'Passthrough PDF validation failed to open output '
        '(platform=${Platform.operatingSystem})',
        e,
        st,
      );
      return false;
    } finally {
      await doc?.dispose();
    }
  }

  /// Writes [startPage0]..[endPage0Inclusive] from an on-disk PDF into
  /// [outputPath] without Android PDFBox (iOS/desktop).
  static Future<bool> _extractPdfPageRangeWithPdfrx(
    String plainPath,
    int startPage0,
    int endPage0Inclusive,
    String outputPath,
  ) async {
    if (startPage0 < 0 || endPage0Inclusive < startPage0) return false;
    pdfrx.PdfDocument? doc;
    pdfrx.PdfDocument? outDoc;
    try {
      doc = await pdfrx.PdfDocument.openFile(
        plainPath,
        useProgressiveLoading: true,
      );
      if (endPage0Inclusive >= doc.pages.length) {
        _log.warning(
          'pdfrx extract: range out of bounds '
          '(platform=${Platform.operatingSystem}, path=$plainPath, '
          'range=$startPage0..$endPage0Inclusive, pages=${doc.pages.length})',
        );
        return false;
      }
      final pages = <pdfrx.PdfPage>[];
      for (var i = startPage0; i <= endPage0Inclusive; i++) {
        pages.add(await doc.pages[i].ensureLoaded());
      }
      outDoc = await pdfrx.PdfDocument.createNew(
        sourceName: 'saber_spine_segment',
      );
      outDoc.pages = pages;
      final bytes = await outDoc.encodePdf();
      await File(outputPath).writeAsBytes(bytes, flush: true);
      return true;
    } on Object catch (e, st) {
      _log.warning(
        'pdfrx extract page range failed '
        '(platform=${Platform.operatingSystem}, path=$plainPath, '
        'range=$startPage0..$endPage0Inclusive)',
        e,
        st,
      );
      return false;
    } finally {
      await outDoc?.dispose();
      await doc?.dispose();
    }
  }

  /// Stream-copy page range via PDFBox on Android; pdfrx slice elsewhere.
  static Future<String?> _materializeSpineSegmentToTemp({
    required String plainPath,
    required int startPage0,
    required int endPage0Inclusive,
    required String outputPath,
  }) async {
    if (!kIsWeb && Platform.isAndroid) {
      return PdfStrokeOverlay.extractPageRangeInclusive(
        sourcePath: plainPath,
        startPage0: startPage0,
        endPage0Inclusive: endPage0Inclusive,
        outputPath: outputPath,
      );
    }
    final ok = await _extractPdfPageRangeWithPdfrx(
      plainPath,
      startPage0,
      endPage0Inclusive,
      outputPath,
    );
    return ok ? outputPath : null;
  }

  /// When every exported page is PDF-background only with **no** ink, Quill,
  /// images, or rotation, and pages form an ordered spine (possibly across
  /// several asset files), copy or stream-extract + merge instead of full
  /// PDFium re-encode.
  ///
  /// **Multi-asset:** consecutive exported rows that share the same on-disk
  /// asset (see [FileManager.toRelativePath]) must use consecutive `pdfPage`
  /// indices; a new asset may start at any local page index.
  static Future<PdfExportData?> _tryPdfPassthroughUnmodifiedAssetCopy(
    EditorCoreInfo info, {
    required List<int> pageIndices,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (kIsWeb || pageIndices.isEmpty) return null;

    final segments = buildUnmodifiedPdfSpine(info, pageIndices);
    if (segments == null || segments.isEmpty) return null;

    final n = pageIndices.length;
    var spinePageSum = 0;
    for (final s in segments) {
      spinePageSum += s.endPage0Inclusive - s.startPage0 + 1;
    }
    if (spinePageSum != n) return null;

    final uniqueLogical = segments.map((s) => s.logicalPath).toSet();
    final plainByLogical = <String, String>{};
    final decryptTemps = <String>{};

    try {
      for (final logical in uniqueLogical) {
        final resolved = await _resolvePlainPdfPathForExport(logical);
        if (resolved == null) {
          _log.warning(
            'Passthrough: could not resolve PDF path '
            '(platform=${Platform.operatingSystem})',
          );
          return null;
        }
        plainByLogical[logical] = resolved.plainPath;
        if (resolved.decryptTempToDelete != null) {
          decryptTemps.add(resolved.decryptTempToDelete!);
        }
      }

      final pageCountByPlain = <String, int>{};
      Future<int?> countForPlain(String plain) async {
        final cached = pageCountByPlain[plain];
        if (cached != null) return cached;
        final cnt = await _pdfPageCountOnPlainFile(plain);
        if (cnt != null && cnt >= 1) pageCountByPlain[plain] = cnt;
        return cnt;
      }

      for (final logical in uniqueLogical) {
        final plain = plainByLogical[logical]!;
        final cnt = await countForPlain(plain);
        if (cnt == null || cnt < 1) {
          _log.warning(
            'Passthrough: invalid page count for segment file '
            '(platform=${Platform.operatingSystem})',
          );
          return null;
        }
      }

      for (final seg in segments) {
        final plain = plainByLogical[seg.logicalPath]!;
        final cnt = pageCountByPlain[plain]!;
        if (seg.startPage0 < 0 ||
            seg.endPage0Inclusive < seg.startPage0 ||
            seg.endPage0Inclusive >= cnt) {
          _log.warning(
            'Passthrough: segment page range out of bounds '
            '(platform=${Platform.operatingSystem})',
          );
          return null;
        }
      }

      final tempDir = await getTemporaryDirectory();
      final dest = p.join(
        tempDir.path,
        'saber_export_passthrough_${const Uuid().v4()}.pdf',
      );

      if (segments.length == 1) {
        final seg = segments.single;
        final plain = plainByLogical[seg.logicalPath]!;
        final pagesInFile = pageCountByPlain[plain]!;
        final coversWholeFile =
            seg.startPage0 == 0 && seg.endPage0Inclusive == pagesInFile - 1;
        try {
          if (coversWholeFile) {
            await File(plain).copy(dest);
          } else {
            final out = await _materializeSpineSegmentToTemp(
              plainPath: plain,
              startPage0: seg.startPage0,
              endPage0Inclusive: seg.endPage0Inclusive,
              outputPath: dest,
            );
            if (out == null) {
              _log.warning(
                'Passthrough: materialize single segment failed '
                '(platform=${Platform.operatingSystem})',
              );
              await _tryDeleteExportTempFile(dest);
              return null;
            }
          }
          if (!await _validatePassthroughOutputPageCount(dest, n)) {
            await _tryDeleteExportTempFile(dest);
            return null;
          }
          onProgress?.call(n, n);
          return PdfExportData.tempFile(dest);
        } on Object catch (e, st) {
          _log.warning(
            'Passthrough: single-segment export failed '
            '(platform=${Platform.operatingSystem})',
            e,
            st,
          );
          await _tryDeleteExportTempFile(dest);
          return null;
        }
      }

      final partPaths = <String>[];
      try {
        for (final seg in segments) {
          final plain = plainByLogical[seg.logicalPath]!;
          final partPath = p.join(
            tempDir.path,
            'saber_spine_part_${const Uuid().v4()}.pdf',
          );
          final out = await _materializeSpineSegmentToTemp(
            plainPath: plain,
            startPage0: seg.startPage0,
            endPage0Inclusive: seg.endPage0Inclusive,
            outputPath: partPath,
          );
          if (out == null) {
            _log.warning(
              'Passthrough: materialize spine part failed '
              '(platform=${Platform.operatingSystem})',
            );
            await _deletePdfExportTempPaths(partPaths);
            return null;
          }
          partPaths.add(partPath);
        }

        if (!kIsWeb && Platform.isAndroid) {
          final mergedPath = p.join(
            tempDir.path,
            'saber_export_merged_${const Uuid().v4()}.pdf',
          );
          final nativePath = await PdfStrokeOverlay.mergePdfsOrdered(
            inputPaths: partPaths,
            outputPath: mergedPath,
          );
          if (nativePath != null) {
            await _deletePdfExportTempPaths(partPaths);
            if (!await _validatePassthroughOutputPageCount(nativePath, n)) {
              await _tryDeleteExportTempFile(nativePath);
              return null;
            }
            onProgress?.call(n, n);
            return PdfExportData.tempFile(nativePath);
          }
          _log.warning(
            'Passthrough: native PDF merge failed; using PdfCombiner '
            '(platform=${Platform.operatingSystem})',
          );
        }

        final data = await _finalizeAssembledPartPathsToPdfExportData(
          partPaths,
        );
        final outPath = data.tempPdfPath;
        if (outPath == null ||
            !await _validatePassthroughOutputPageCount(outPath, n)) {
          await _tryDeleteExportTempFile(outPath);
          return null;
        }
        onProgress?.call(n, n);
        return data;
      } on Object catch (e, st) {
        _log.warning(
          'Passthrough: multi-segment export failed '
          '(platform=${Platform.operatingSystem})',
          e,
          st,
        );
        await _deletePdfExportTempPaths(partPaths);
        return null;
      }
    } finally {
      for (final t in decryptTemps) {
        await _tryDeleteExportTempFile(t);
      }
    }
  }

  static bool _exportPageIsAndroidSpineRawExtractable(
    EditorCoreInfo info,
    List<int> pageIndices,
    int exportPos,
    String sharedPdfPath,
    pdfrx.PdfDocument srcDoc,
  ) {
    if (!Platform.isAndroid) return false;
    final idx = pageIndices[exportPos];
    info.ensurePageHydrated(idx);
    final page = info.pages[idx];
    if (pageBlocksPdfPassthrough(page)) return false;
    final bg = page.backgroundImage;
    if (bg is! PdfEditorImage) return false;
    if ((bg.pdfFile?.path ?? '') != sharedPdfPath) return false;
    if (bg.rotationDeg.abs() > 0.01) return false;
    final pi = bg.pdfPage;
    if (pi < 0 || pi >= srcDoc.pages.length) return false;
    return true;
  }

  static int _sourcePdfPageAtExportPos(
    EditorCoreInfo info,
    List<int> pageIndices,
    int exportPos,
  ) {
    final idx = pageIndices[exportPos];
    info.ensurePageHydrated(idx);
    final bg = info.pages[idx].backgroundImage! as PdfEditorImage;
    return bg.pdfPage;
  }

  static Future<void> _deletePdfExportTempPaths(Iterable<String> paths) async {
    for (final path in paths) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  static Future<PdfExportData> _finalizeAssembledPartPathsToPdfExportData(
    List<String> partPaths,
  ) async {
    // Multi-part paths are merged with PDFBox on Android ([PdfStrokeOverlay.mergePdfFilesOrdered]).
    // For very large form-heavy PDFs, a future stream-preserving merge (e.g. qpdf) may improve
    // time and output size vs PDFMergerUtility.
    if (partPaths.length == 1) {
      return PdfExportData.tempFile(partPaths.single);
    }
    final tempDir = await getTemporaryDirectory();
    final mergedPath = p.join(
      tempDir.path,
      'saber_export_merged_${const Uuid().v4()}.pdf',
    );
    if (!kIsWeb && Platform.isAndroid) {
      await Future<void>.delayed(Duration.zero);
      final nativeOut = await PdfStrokeOverlay.mergePdfsOrdered(
        inputPaths: partPaths,
        outputPath: mergedPath,
      );
      if (nativeOut != null) {
        for (final pp in partPaths) {
          try {
            await File(pp).delete();
          } catch (_) {}
        }
        return PdfExportData.tempFile(nativeOut);
      }
      _log.warning(
        'finalize assembled parts: native merge failed; using PdfCombiner '
        '(platform=${Platform.operatingSystem}, parts=${partPaths.length})',
      );
    }
    await PdfCombiner.mergeMultiplePDFs(
      inputPaths: partPaths,
      outputPath: mergedPath,
    );
    for (final pp in partPaths) {
      try {
        await File(pp).delete();
      } catch (_) {}
    }
    return PdfExportData.tempFile(mergedPath);
  }

  static Future<List<String>?> _composedExportRangeToPartPaths({
    required EditorCoreInfo info,
    required BuildContext context,
    required pdfrx.PdfDocument srcDoc,
    required String sharedPath,
    String? plainPdfPathForNativeExtract,
    required List<int> pageIndices,
    required int exportStart,
    required int exportEndInclusive,
    required int total,
    required int chunkCap,
    required double effectiveRasterRatio,
    required bool invert,
    required ScreenshotController screenshotController,
    void Function(int completed, int total)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final out = <String>[];
    var pos = exportStart;
    while (pos <= exportEndInclusive) {
      final endBatch = math.min(pos + chunkCap - 1, exportEndInclusive);
      final chunkSlots = <_AssembledExportSlot>[];
      pdfrx.PdfDocument? chunkOut;
      try {
        Future<_AssembledExportSlot?> assembleSlot(int k) {
          return _assembleOneExportPage(
            info: info,
            srcDoc: srcDoc,
            sharedPdfPath: sharedPath,
            plainPdfPathForNativeExtract: plainPdfPathForNativeExtract,
            pageIndex: pageIndices[k],
            totalPages: total,
            effectiveRasterRatio: effectiveRasterRatio,
            invert: invert,
            context: context,
            screenshotController: screenshotController,
          );
        }

        final useParallelPageAssembly =
            !kIsWeb && !Platform.isAndroid && !Platform.isIOS;

        if (useParallelPageAssembly) {
          var batchNeedsQuillScreenshot = false;
          for (var k = pos; k <= endBatch; k++) {
            info.ensurePageHydrated(pageIndices[k]);
            if (_pageHasQuillContent(info.pages[pageIndices[k]])) {
              batchNeedsQuillScreenshot = true;
              break;
            }
          }
          if (batchNeedsQuillScreenshot) {
            for (var k = pos; k <= endBatch; k++) {
              if (k > pos) info.ensurePageHydrated(pageIndices[k]);
              final slot = await assembleSlot(k);
              if (slot == null) {
                for (final s in chunkSlots) {
                  await s.disposeExtra();
                }
                return null;
              }
              chunkSlots.add(slot);
              onProgress?.call(k + 1, total);
            }
          } else {
            for (var k = pos; k <= endBatch; k++) {
              info.ensurePageHydrated(pageIndices[k]);
            }
            final slots = await Future.wait(
              List.generate(
                endBatch - pos + 1,
                (offset) => assembleSlot(pos + offset),
              ),
            );
            for (var i = 0; i < slots.length; i++) {
              final slot = slots[i];
              if (slot == null) {
                for (final s in chunkSlots) {
                  await s.disposeExtra();
                }
                return null;
              }
              chunkSlots.add(slot);
              onProgress?.call(pos + i + 1, total);
            }
          }
        } else {
          for (var k = pos; k <= endBatch; k++) {
            info.ensurePageHydrated(pageIndices[k]);
            final slot = await assembleSlot(k);
            if (slot == null) {
              for (final s in chunkSlots) {
                await s.disposeExtra();
              }
              return null;
            }
            chunkSlots.add(slot);
            onProgress?.call(k + 1, total);
          }
        }

        final allAndroidNative =
            !kIsWeb &&
            Platform.isAndroid &&
            chunkSlots.isNotEmpty &&
            chunkSlots.every((s) => s.nativePdfPartPath != null);

        if (allAndroidNative) {
          if (chunkSlots.length == 1) {
            out.add(chunkSlots.single.nativePdfPartPath!);
            chunkSlots.single.markNativePathHandedOff();
          } else {
            final mergedPath = p.join(
              tempDir.path,
              'saber_native_chunk_${const Uuid().v4()}.pdf',
            );
            final nativePaths = chunkSlots
                .map((s) => s.nativePdfPartPath!)
                .toList();
            final merged = await PdfStrokeOverlay.mergePdfsOrdered(
              inputPaths: nativePaths,
              outputPath: mergedPath,
            );
            if (merged == null) {
              for (final s in chunkSlots) {
                await s.disposeExtra();
              }
              return null;
            }
            for (final s in chunkSlots) {
              try {
                File(s.nativePdfPartPath!).deleteSync();
              } catch (_) {}
              s.markNativePathHandedOff();
            }
            out.add(mergedPath);
          }
        } else {
          final outPages = <pdfrx.PdfPage>[];
          for (final s in chunkSlots) {
            outPages.add(await s.resolvePageForPdfiumEncode());
          }
          chunkOut = await pdfrx.PdfDocument.createNew(
            sourceName: 'saber_export_comp_$pos.pdf',
          );
          chunkOut.pages = outPages;
          _hybridSpinePdfiumEncodeCalls++;
          final bytes = await chunkOut.encodePdf();
          final partPath = p.join(
            tempDir.path,
            'saber_export_comp_${const Uuid().v4()}.pdf',
          );
          await File(partPath).writeAsBytes(bytes, flush: true);
          out.add(partPath);
        }
      } finally {
        await chunkOut?.dispose();
        for (final s in chunkSlots) {
          await s.disposeExtra();
        }
      }
      pos = endBatch + 1;
      await Future<void>.delayed(Duration.zero);
    }
    return out;
  }

  static Future<List<String>?> _buildHybridSpinePdfrxPartPaths({
    required EditorCoreInfo info,
    required BuildContext context,
    required pdfrx.PdfDocument srcDoc,
    required String sharedPath,
    required String diskPdfPathForNativeExtract,
    required List<int> pageIndices,
    required int total,
    required int chunkCap,
    required double effectiveRasterRatio,
    required bool invert,
    required ScreenshotController screenshotController,
    void Function(int completed, int total)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final all = <String>[];
    _hybridSpinePdfBoxBatchInvocations = 0;
    _hybridSpinePdfiumEncodeCalls = 0;
    var composedSegmentCount = 0;
    try {
      var n = 0;
      while (n < total) {
        if (_exportPageIsAndroidSpineRawExtractable(
          info,
          pageIndices,
          n,
          sharedPath,
          srcDoc,
        )) {
          var j = n;
          final srcStart = _sourcePdfPageAtExportPos(info, pageIndices, n);
          var expectedNext = srcStart + 1;
          while (j + 1 < total &&
              _exportPageIsAndroidSpineRawExtractable(
                info,
                pageIndices,
                j + 1,
                sharedPath,
                srcDoc,
              )) {
            final nextSrc = _sourcePdfPageAtExportPos(info, pageIndices, j + 1);
            if (nextSrc != expectedNext) break;
            j++;
            expectedNext = nextSrc + 1;
          }
          final srcEnd = _sourcePdfPageAtExportPos(info, pageIndices, j);
          if (srcEnd - srcStart != j - n) {
            return null;
          }
          // Native extract caps at 2048 pages/job; do not tie raw spine slices to composed chunkCap (72).
          const maxPerPart = 2048;
          final jobs =
              <({int startPage0, int endPage0Inclusive, String outputPath})>[];
          var exportLo = n;
          while (exportLo <= j) {
            final exportHi = math.min(exportLo + maxPerPart - 1, j);
            final srcLo = srcStart + (exportLo - n);
            final srcHi = srcStart + (exportHi - n);
            jobs.add((
              startPage0: srcLo,
              endPage0Inclusive: srcHi,
              outputPath: p.join(
                tempDir.path,
                'saber_spine_${const Uuid().v4()}.pdf',
              ),
            ));
            exportLo = exportHi + 1;
          }
          try {
            if (!kIsWeb && Platform.isAndroid) {
              _hybridSpinePdfBoxBatchInvocations++;
              final ok = await PdfStrokeOverlay.extractPageRangesBatch(
                sourcePath: diskPdfPathForNativeExtract,
                jobs: jobs,
              );
              if (!ok) {
                _log.warning(
                  'hybrid_spine_raw: PDFBox batch extract failed '
                  '(platform=${Platform.operatingSystem}, slices=${jobs.length})',
                );
                await _deletePdfExportTempPaths(all);
                await _deletePdfExportTempPaths(jobs.map((e) => e.outputPath));
                return null;
              }
            } else {
              for (final job in jobs) {
                final ok = await _extractPdfPageRangeWithPdfrx(
                  diskPdfPathForNativeExtract,
                  job.startPage0,
                  job.endPage0Inclusive,
                  job.outputPath,
                );
                if (!ok) {
                  _log.warning(
                    'hybrid_spine_raw: pdfrx slice failed '
                    '(platform=${Platform.operatingSystem})',
                  );
                  await _deletePdfExportTempPaths(all);
                  await _deletePdfExportTempPaths(
                    jobs.map((e) => e.outputPath),
                  );
                  return null;
                }
              }
            }
          } on Object catch (e, st) {
            _log.warning(
              'hybrid_spine_raw: extract failed '
              '(platform=${Platform.operatingSystem}, slices=${jobs.length})',
              e,
              st,
            );
            await _deletePdfExportTempPaths(all);
            await _deletePdfExportTempPaths(jobs.map((e) => e.outputPath));
            return null;
          }
          for (final job in jobs) {
            all.add(job.outputPath);
          }
          onProgress?.call(j + 1, total);
          n = j + 1;
          await Future<void>.delayed(Duration.zero);
        } else {
          composedSegmentCount++;
          var j = n;
          while (j + 1 < total &&
              !_exportPageIsAndroidSpineRawExtractable(
                info,
                pageIndices,
                j + 1,
                sharedPath,
                srcDoc,
              )) {
            j++;
          }
          final parts = await _composedExportRangeToPartPaths(
            info: info,
            context: context,
            srcDoc: srcDoc,
            sharedPath: sharedPath,
            plainPdfPathForNativeExtract: diskPdfPathForNativeExtract,
            pageIndices: pageIndices,
            exportStart: n,
            exportEndInclusive: j,
            total: total,
            chunkCap: chunkCap,
            effectiveRasterRatio: effectiveRasterRatio,
            invert: invert,
            screenshotController: screenshotController,
            onProgress: onProgress,
          );
          if (parts == null) {
            await _deletePdfExportTempPaths(all);
            return null;
          }
          all.addAll(parts);
          n = j + 1;
        }
      }
      _log.info(
        '[export.metrics] hybrid_spine pdfbox_batch_calls=$_hybridSpinePdfBoxBatchInvocations '
        'pdfium_encode_chunks=$_hybridSpinePdfiumEncodeCalls '
        'composed_segments=$composedSegmentCount temp_parts=${all.length}',
      );
      return all;
    } on Object catch (e, st) {
      _log.warning(
        'hybrid spine failed (platform=${Platform.operatingSystem}, phase=composed_or_loop)',
        e,
        st,
      );
      await _deletePdfExportTempPaths(all);
      return null;
    }
  }

  /// Single-asset Android export: every page is PDF background, no Quill/canvas
  /// images/non–90° rotation; ink uses pre-generated vector overlay PDFs. Used to
  /// build a one-pass PDFBox recipe (avoids reloading the source once per fragment).
  static bool _pageEligibleForAndroidRecipeExport(
    EditorCoreInfo info,
    int pageIndex,
    String sharedPath,
    pdfrx.PdfDocument srcDoc,
  ) {
    if (kIsWeb || !Platform.isAndroid) return false;
    info.ensurePageHydrated(pageIndex);
    final page = info.pages[pageIndex];
    if (_pageHasQuillContent(page)) return false;
    if (page.allImagesInDrawOrder.isNotEmpty) return false;
    final bgImg = page.backgroundImage;
    if (bgImg is! PdfEditorImage) return false;
    if ((bgImg.pdfFile?.path ?? '') != sharedPath) return false;
    if (!_isMultipleOf90Degrees(bgImg.rotationDeg)) return false;
    final pi = bgImg.pdfPage;
    if (pi < 0 || pi >= srcDoc.pages.length) return false;
    return true;
  }

  /// Parallel vector/PNG prefetches per batch (Android recipe) when falling
  /// back from multi-page vector encode. Higher values help PNG fallback.
  static const _androidRecipeStampBatch = 24;

  /// If every op is a vector `stamp` sharing one [overlayPath], native can use
  /// [PdfStrokeOverlay.exportInPlaceStampsMerged] (single overlay scope + form cache).
  static ({String mergedPath, List<Map<String, dynamic>> jobs})?
  _androidInPlaceMergedVectorJobsOrNull(List<Map<String, dynamic>> stampOps) {
    if (stampOps.isEmpty) return null;
    String? sharedOverlay;
    final jobs = <Map<String, dynamic>>[];
    for (final o in stampOps) {
      if (o['type'] != 'stamp') return null;
      final path = o['overlayPath'] as String?;
      if (path == null || path.isEmpty) return null;
      sharedOverlay ??= path;
      if (path != sharedOverlay) return null;
      final src = o['srcPage0'];
      if (src is! num) return null;
      final ov = o['overlayPage0'];
      final ov0 = ov is num ? ov.toInt() : 0;
      jobs.add({'srcPage0': src.toInt(), 'overlayPage0': ov0});
    }
    return (mergedPath: sharedOverlay!, jobs: jobs);
  }

  /// True when exporting the full source in order: output page [k] is source page [k].
  static bool _androidAssemblyIsInPlaceLinearOrder(
    EditorCoreInfo info,
    List<int> pageIndices,
    pdfrx.PdfDocument srcDoc,
  ) {
    if (pageIndices.length != srcDoc.pages.length) return false;
    for (var k = 0; k < pageIndices.length; k++) {
      info.ensurePageHydrated(pageIndices[k]);
      final bg = info.pages[pageIndices[k]].backgroundImage;
      if (bg is! PdfEditorImage) return false;
      if (bg.pdfPage != k) return false;
    }
    return true;
  }

  /// Parallel ink encoding for the Android PDFBox recipe (vector first, else PNG).
  ///
  /// When possible, builds **one** multi-page vector overlay PDF ([mergedVectorPdf])
  /// so native stamping opens a single overlay document (see PDFBox path cache).
  static Future<
    ({Map<int, _RecipeStampPayload> stamps, Uint8List? mergedVectorPdf})?
  >
  _prefillAndroidRecipeStamps({
    required List<int> pageIndices,
    required EditorCoreInfo info,
    required bool invert,
  }) async {
    final withStrokes = <({int idx, EditorPage page})>[];
    for (final idx in pageIndices) {
      info.ensurePageHydrated(idx);
      final page = info.pages[idx];
      if (page.allStrokesInDrawOrder.isNotEmpty) {
        withStrokes.add((idx: idx, page: page));
      }
    }
    if (withStrokes.isEmpty) {
      return (stamps: <int, _RecipeStampPayload>{}, mergedVectorPdf: null);
    }

    try {
      final merged = await _encodeVectorStrokeOverlaysPdfMerged(
        withStrokes.map((s) => s.page).toList(growable: false),
        invert,
      );
      if (merged.isNotEmpty) {
        final out = <int, _RecipeStampPayload>{};
        var o = 0;
        for (final s in withStrokes) {
          out[s.idx] = _RecipeStampPayload.vectorMergedPage(o++);
        }
        return (stamps: out, mergedVectorPdf: merged);
      }
    } on Object catch (e, st) {
      _log.warning(
        'recipe: multi-page vector overlay encode failed; '
        'falling back to per-page vector/PNG '
        '(platform=${Platform.operatingSystem})',
        e,
        st,
      );
    }

    final out = <int, _RecipeStampPayload>{};
    for (var i = 0; i < withStrokes.length; i += _androidRecipeStampBatch) {
      final end = math.min(i + _androidRecipeStampBatch, withStrokes.length);
      final batch = withStrokes.sublist(i, end);
      final partial = await Future.wait(
        batch.map((spec) async {
          Uint8List? vec;
          try {
            vec = await _encodeVectorStrokeOverlayPdf(spec.page, invert);
          } on Object catch (e, st) {
            _log.warning(
              'recipe: vector overlay encode failed pageIndex=${spec.idx}; '
              'using PNG stamp',
              e,
              st,
            );
          }
          if (vec != null && vec.isNotEmpty) {
            return MapEntry(spec.idx, _RecipeStampPayload.vector(vec));
          }
          final png = await _encodeStrokesOnlyPngBytes(
            page: spec.page,
            invert: invert,
          );
          if (png == null || png.isEmpty) {
            return MapEntry<int, _RecipeStampPayload?>(spec.idx, null);
          }
          return MapEntry(spec.idx, _RecipeStampPayload.png(png));
        }),
      );
      for (final e in partial) {
        final v = e.value;
        if (v == null) return null;
        out[e.key] = v;
      }
    }
    return (stamps: out, mergedVectorPdf: null);
  }

  static Future<
    ({
      List<Map<String, dynamic>> ops,
      List<String> overlayTemps,
      int stampCount,
      bool inPlaceLinear,
    })?
  >
  _buildAndroidExportRecipeOrNull({
    required EditorCoreInfo info,
    required pdfrx.PdfDocument srcDoc,
    required String sharedPath,
    required List<int> pageIndices,
    required bool invert,
  }) async {
    for (final idx in pageIndices) {
      if (!_pageEligibleForAndroidRecipeExport(info, idx, sharedPath, srcDoc)) {
        return null;
      }
    }
    final opsResult = <Map<String, dynamic>>[];
    final overlayTemps = <String>[];
    var stampCount = 0;
    var copyStart = -1;
    var copyEnd = -1;

    void flushCopy() {
      if (copyStart >= 0 && copyEnd >= 0) {
        opsResult.add({
          'type': 'copy',
          'startPage0': copyStart,
          'endPage0Inclusive': copyEnd,
        });
        copyStart = -1;
        copyEnd = -1;
      }
    }

    final stampPrefill = await _prefillAndroidRecipeStamps(
      pageIndices: pageIndices,
      info: info,
      invert: invert,
    );
    if (stampPrefill == null) return null;
    final stampByIndex = stampPrefill.stamps;

    final tempDir = await getTemporaryDirectory();
    String? sharedMergedVectorPath;
    final mergedPdfBytes = stampPrefill.mergedVectorPdf;
    if (mergedPdfBytes != null && mergedPdfBytes.isNotEmpty) {
      sharedMergedVectorPath = p.join(
        tempDir.path,
        'saber_recipe_merged_ov_${const Uuid().v4()}.pdf',
      );
      await File(
        sharedMergedVectorPath,
      ).writeAsBytes(mergedPdfBytes, flush: true);
      overlayTemps.add(sharedMergedVectorPath);
    }
    for (final idx in pageIndices) {
      info.ensurePageHydrated(idx);
      final page = info.pages[idx];
      final bg = page.backgroundImage! as PdfEditorImage;
      final srcPi = bg.pdfPage;
      final hasStrokes = page.allStrokesInDrawOrder.isNotEmpty;

      if (!hasStrokes) {
        if (copyStart < 0) {
          copyStart = copyEnd = srcPi;
        } else if (srcPi == copyEnd + 1) {
          copyEnd = srcPi;
        } else {
          flushCopy();
          copyStart = copyEnd = srcPi;
        }
      } else {
        flushCopy();
        final payload = stampByIndex[idx]!;
        if (payload.vectorMergedPage0 != null) {
          opsResult.add({
            'type': 'stamp',
            'srcPage0': srcPi,
            'overlayPath': sharedMergedVectorPath!,
            'overlayPage0': payload.vectorMergedPage0!,
          });
          stampCount++;
        } else if (payload.vectorBytes != null) {
          final overlayPath = p.join(
            tempDir.path,
            'saber_recipe_ov_${const Uuid().v4()}.pdf',
          );
          await File(
            overlayPath,
          ).writeAsBytes(payload.vectorBytes!, flush: true);
          overlayTemps.add(overlayPath);
          opsResult.add({
            'type': 'stamp',
            'srcPage0': srcPi,
            'overlayPath': overlayPath,
            'overlayPage0': 0,
          });
          stampCount++;
        } else {
          final pngBytes = payload.pngBytes!;
          final pngPath = p.join(
            tempDir.path,
            'saber_recipe_png_${const Uuid().v4()}.png',
          );
          await File(pngPath).writeAsBytes(pngBytes, flush: true);
          overlayTemps.add(pngPath);
          final stampPts = _exportOverlaySizeForPage(page);
          opsResult.add({
            'type': 'stampPng',
            'srcPage0': srcPi,
            'pngPath': pngPath,
            'pageWidthPt': stampPts.width,
            'pageHeightPt': stampPts.height,
            'darkenBlend': !invert,
          });
          stampCount++;
        }
      }
    }
    flushCopy();
    if (opsResult.isEmpty) return null;
    var expectedPages = 0;
    for (final op in opsResult) {
      final t = op['type'] as String?;
      if (t == 'copy') {
        final a = op['startPage0'] as int?;
        final b = op['endPage0Inclusive'] as int?;
        if (a == null || b == null || b < a) return null;
        expectedPages += b - a + 1;
      } else if (t == 'stamp' || t == 'stampPng') {
        expectedPages++;
      } else {
        for (final x in overlayTemps) {
          await _tryDeleteExportTempFile(x);
        }
        return null;
      }
    }
    if (expectedPages != pageIndices.length) {
      _log.warning(
        'recipe: internal page count mismatch expected=$expectedPages '
        'export=${pageIndices.length}',
      );
      for (final x in overlayTemps) {
        await _tryDeleteExportTempFile(x);
      }
      return null;
    }
    return (
      ops: opsResult,
      overlayTemps: overlayTemps,
      stampCount: stampCount,
      inPlaceLinear: _androidAssemblyIsInPlaceLinearOrder(
        info,
        pageIndices,
        srcDoc,
      ),
    );
  }

  static Future<PdfExportData?> _legacyPdfrxAssembledPdfExport({
    required EditorCoreInfo info,
    required BuildContext context,
    required pdfrx.PdfDocument srcDoc,
    required String sharedPath,
    String? plainPdfPathForNativeExtract,
    required List<int> pageIndices,
    required int chunkCap,
    required double effectiveRasterRatio,
    required bool invert,
    required ScreenshotController screenshotController,
    void Function(int completed, int total)? onProgress,
  }) async {
    final total = pageIndices.length;
    if (total > chunkCap) {
      final tempDir = await getTemporaryDirectory();
      final partPaths = <String>[];
      try {
        for (var start = 0; start < total; start += chunkCap) {
          final end = math.min(start + chunkCap, total);
          final chunkSlots = <_AssembledExportSlot>[];
          pdfrx.PdfDocument? chunkOut;
          try {
            for (var n = start; n < end; n++) {
              final idx = pageIndices[n];
              final slot = await _assembleOneExportPage(
                info: info,
                srcDoc: srcDoc,
                sharedPdfPath: sharedPath,
                plainPdfPathForNativeExtract: plainPdfPathForNativeExtract,
                pageIndex: idx,
                totalPages: total,
                effectiveRasterRatio: effectiveRasterRatio,
                invert: invert,
                context: context,
                screenshotController: screenshotController,
              );
              if (slot == null) {
                for (final s in chunkSlots) {
                  await s.disposeExtra();
                }
                return null;
              }
              chunkSlots.add(slot);
              onProgress?.call(n + 1, total);
            }

            final allAndroidNative =
                !kIsWeb &&
                Platform.isAndroid &&
                chunkSlots.isNotEmpty &&
                chunkSlots.every((s) => s.nativePdfPartPath != null);

            if (allAndroidNative) {
              if (chunkSlots.length == 1) {
                partPaths.add(chunkSlots.single.nativePdfPartPath!);
                chunkSlots.single.markNativePathHandedOff();
              } else {
                final mergedPath = p.join(
                  tempDir.path,
                  'saber_native_chunk_${const Uuid().v4()}.pdf',
                );
                final nativePaths = chunkSlots
                    .map((s) => s.nativePdfPartPath!)
                    .toList();
                final merged = await PdfStrokeOverlay.mergePdfsOrdered(
                  inputPaths: nativePaths,
                  outputPath: mergedPath,
                );
                if (merged == null) {
                  for (final s in chunkSlots) {
                    await s.disposeExtra();
                  }
                  return null;
                }
                for (final s in chunkSlots) {
                  try {
                    File(s.nativePdfPartPath!).deleteSync();
                  } catch (_) {}
                  s.markNativePathHandedOff();
                }
                partPaths.add(mergedPath);
              }
            } else {
              final outPages = <pdfrx.PdfPage>[];
              for (final s in chunkSlots) {
                outPages.add(await s.resolvePageForPdfiumEncode());
              }
              chunkOut = await pdfrx.PdfDocument.createNew(
                sourceName: 'saber_export_part_$start.pdf',
              );
              chunkOut.pages = outPages;
              final bytes = await chunkOut.encodePdf();
              final partPath = p.join(
                tempDir.path,
                'saber_export_part_${const Uuid().v4()}.pdf',
              );
              await File(partPath).writeAsBytes(bytes, flush: true);
              partPaths.add(partPath);
            }
          } finally {
            await chunkOut?.dispose();
            for (final s in chunkSlots) {
              await s.disposeExtra();
            }
          }
          await Future<void>.delayed(Duration.zero);
        }

        return _finalizeAssembledPartPathsToPdfExportData(partPaths);
      } catch (_) {
        for (final pp in partPaths) {
          try {
            await File(pp).delete();
          } catch (_) {}
        }
        return null;
      }
    }

    final allSlots = <_AssembledExportSlot>[];
    pdfrx.PdfDocument? outDoc;
    try {
      final outPages = <pdfrx.PdfPage>[];

      for (var n = 0; n < total; n++) {
        final idx = pageIndices[n];
        info.ensurePageHydrated(idx);

        final slot = await _assembleOneExportPage(
          info: info,
          srcDoc: srcDoc,
          sharedPdfPath: sharedPath,
          plainPdfPathForNativeExtract: plainPdfPathForNativeExtract,
          pageIndex: idx,
          totalPages: total,
          effectiveRasterRatio: effectiveRasterRatio,
          invert: invert,
          context: context,
          screenshotController: screenshotController,
        );
        if (slot == null) {
          for (final s in allSlots) {
            await s.disposeExtra();
          }
          return null;
        }
        allSlots.add(slot);
        outPages.add(await slot.resolvePageForPdfiumEncode());

        onProgress?.call(n + 1, total);
      }

      outDoc = await pdfrx.PdfDocument.createNew(
        sourceName: 'saber_export.pdf',
      );
      outDoc.pages = outPages;
      return PdfExportData.bytes(await outDoc.encodePdf());
    } finally {
      await outDoc?.dispose();
      for (final s in allSlots) {
        await s.disposeExtra();
      }
    }
  }

  /// **Hybrid spine path:** contiguous “raw” runs (same PDF asset, no ink/Quill/images,
  /// rotation 0) are copied with PDFBox
  /// [PdfStrokeOverlay.extractPageRangesBatch] on Android (single source open, capped
  /// slice size) or [EditorExporter._extractPdfPageRangeWithPdfrx] per slice elsewhere.
  /// Ink pages use composed segments as before.
  static Future<PdfExportData?> _tryPdfrxAssembledPdfExport(
    EditorCoreInfo info,
    BuildContext context, {
    required List<int> pageIndices,
    required bool invert,
    required double effectiveRasterRatio,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (kIsWeb || invert) return null;
    if (pageIndices.isEmpty) return null;

    info.ensurePageHydrated(pageIndices[0]);
    final p0 = info.pages[pageIndices[0]];
    final bg0 = p0.backgroundImage;
    if (bg0 is! PdfEditorImage) return null;
    final sharedPath = bg0.pdfFile?.path;
    if (sharedPath == null || sharedPath.isEmpty) return null;

    final resolvedPlain = await _resolvePlainPdfPathForExport(sharedPath);
    if (resolvedPlain == null) return null;
    final diskPdfPath = resolvedPlain.plainPath;
    final decryptTempToDelete = resolvedPlain.decryptTempToDelete;

    pdfrx.PdfDocument? srcDoc;
    final screenshotController = ScreenshotController();
    final perf = PerfTiming.start(
      'export.pdfrx_assembled',
      fields: {'pages': pageIndices.length},
    );

    try {
      srcDoc = await pdfrx.PdfDocument.openFile(
        diskPdfPath,
        useProgressiveLoading: true,
      );
      perf?.checkpoint('opened_src');

      final total = pageIndices.length;
      final chunkCap = _exportChunkPageCap();

      int? plainFileBytes;
      try {
        plainFileBytes = await File(diskPdfPath).length();
      } catch (_) {}
      _log.info(
        '[export.metrics] assembled_export_start pages=$total '
        'plain_pdf_bytes=${plainFileBytes ?? '?'}',
      );

      if (!kIsWeb && Platform.isAndroid && !invert) {
        final recipe = await _buildAndroidExportRecipeOrNull(
          info: info,
          srcDoc: srcDoc,
          sharedPath: sharedPath,
          pageIndices: pageIndices,
          invert: invert,
        );
        if (recipe != null) {
          final tempDir = await getTemporaryDirectory();
          final outRecipe = p.join(
            tempDir.path,
            'saber_export_recipe_${const Uuid().v4()}.pdf',
          );
          perf?.checkpoint('recipe_built');
          String? recipeOut;
          if (recipe.inPlaceLinear) {
            ({String mergedPath, List<Map<String, dynamic>> jobs})?
            mergedVectorJobs;
            if (recipe.stampCount == 0) {
              try {
                final srcF = File(diskPdfPath);
                await srcF.copy(outRecipe);
                recipeOut = outRecipe;
              } on Object catch (e, st) {
                _log.warning(
                  'recipe_export in_place file copy failed '
                  '(platform=${Platform.operatingSystem})',
                  e,
                  st,
                );
                recipeOut = null;
              }
            } else {
              final stampOps = recipe.ops
                  .where((o) => o['type'] == 'stamp' || o['type'] == 'stampPng')
                  .map((o) => Map<String, dynamic>.from(o))
                  .toList();
              mergedVectorJobs =
                  EditorExporter._androidInPlaceMergedVectorJobsOrNull(
                    stampOps,
                  );
              if (mergedVectorJobs != null) {
                recipeOut = await PdfStrokeOverlay.exportInPlaceStampsMerged(
                  sourcePath: diskPdfPath,
                  outputPath: outRecipe,
                  mergedOverlayPath: mergedVectorJobs.mergedPath,
                  jobs: mergedVectorJobs.jobs,
                );
              } else {
                recipeOut = await PdfStrokeOverlay.exportInPlaceStamps(
                  sourcePath: diskPdfPath,
                  outputPath: outRecipe,
                  stamps: stampOps,
                );
              }
            }
            try {
              final outB = recipeOut != null && File(recipeOut).existsSync()
                  ? await File(recipeOut).length()
                  : null;
              final ratio =
                  plainFileBytes != null && plainFileBytes > 0 && outB != null
                  ? (outB / plainFileBytes).toStringAsFixed(2)
                  : '?';
              final stampKind = recipe.stampCount == 0
                  ? 'file_copy'
                  : (mergedVectorJobs != null
                        ? 'exportInPlaceStampsMerged'
                        : 'exportInPlaceStamps');
              _log.info(
                '[export.metrics] recipe_export in_place_linear=true '
                'stamps=${recipe.stampCount} '
                '$stampKind '
                'out_bytes=${outB ?? "?"} ratio_vs_plain=$ratio',
              );
            } catch (_) {}
          } else {
            recipeOut = await PdfStrokeOverlay.exportFromRecipe(
              sourcePath: diskPdfPath,
              outputPath: outRecipe,
              ops: recipe.ops,
            );
            try {
              final outBytes = recipeOut != null && File(recipeOut).existsSync()
                  ? await File(recipeOut).length()
                  : null;
              final ratio =
                  plainFileBytes != null &&
                      plainFileBytes > 0 &&
                      outBytes != null
                  ? (outBytes / plainFileBytes).toStringAsFixed(2)
                  : '?';
              _log.info(
                '[export.metrics] recipe_export in_place_linear=false '
                'single_pdfbox_load=true '
                'ops=${recipe.ops.length} stamps=${recipe.stampCount} '
                'out_bytes=${outBytes ?? "?"} ratio_vs_plain=$ratio',
              );
            } catch (_) {}
          }
          if (recipeOut != null) {
            final valid = await _validatePassthroughOutputPageCount(
              recipeOut,
              pageIndices.length,
            );
            if (valid) {
              for (final t in recipe.overlayTemps) {
                await _tryDeleteExportTempFile(t);
              }
              perf?.checkpoint('recipe_export_done');
              perf?.end(
                fields: {
                  'parts': 1,
                  'recipe': true,
                  'recipe_ops': recipe.ops.length,
                  'recipe_stamps': recipe.stampCount,
                  'in_place_linear': recipe.inPlaceLinear,
                },
              );
              return PdfExportData.tempFile(recipeOut);
            }
            _log.warning(
              '[export.metrics] recipe_export page_count_check_failed; falling back',
            );
            await _tryDeleteExportTempFile(recipeOut);
            for (final t in recipe.overlayTemps) {
              await _tryDeleteExportTempFile(t);
            }
          } else {
            for (final t in recipe.overlayTemps) {
              await _tryDeleteExportTempFile(t);
            }
          }
        }
      }

      final hybridParts = await _buildHybridSpinePdfrxPartPaths(
        info: info,
        context: context,
        srcDoc: srcDoc,
        sharedPath: sharedPath,
        diskPdfPathForNativeExtract: diskPdfPath,
        pageIndices: pageIndices,
        total: total,
        chunkCap: chunkCap,
        effectiveRasterRatio: effectiveRasterRatio,
        invert: invert,
        screenshotController: screenshotController,
        onProgress: onProgress,
      );
      perf?.checkpoint('hybrid_spine_done');

      if (hybridParts != null && hybridParts.isNotEmpty) {
        final data = await _finalizeAssembledPartPathsToPdfExportData(
          hybridParts,
        );
        if (data.tempPdfPath != null) {
          try {
            final outB = await File(data.tempPdfPath!).length();
            _log.info(
              '[export.metrics] hybrid_finalize out_bytes=$outB '
              'plain_pdf_bytes=${plainFileBytes ?? '?'} parts=${hybridParts.length}',
            );
          } catch (_) {}
        }
        perf?.checkpoint('finalize_done');
        perf?.end(fields: {'parts': hybridParts.length});
        return data;
      }

      final legacy = await _legacyPdfrxAssembledPdfExport(
        info: info,
        context: context,
        srcDoc: srcDoc,
        sharedPath: sharedPath,
        plainPdfPathForNativeExtract: diskPdfPath,
        pageIndices: pageIndices,
        chunkCap: chunkCap,
        effectiveRasterRatio: effectiveRasterRatio,
        invert: invert,
        screenshotController: screenshotController,
        onProgress: onProgress,
      );
      perf?.checkpoint('legacy_done');
      perf?.end(fields: {'legacy': true});
      return legacy;
    } on Object catch (e, st) {
      _log.warning(
        'pdfrx assembled export failed (platform=${Platform.operatingSystem})',
        e,
        st,
      );
      perf?.end(fields: {'error': 'exception'});
      return null;
    } finally {
      await srcDoc?.dispose();
      await _tryDeleteExportTempFile(decryptTempToDelete);
    }
  }

  static double _effectiveRasterRatioForPageCount(
    double resolvedRasterRatio,
    int pageCount,
  ) {
    var effectiveRasterRatio = resolvedRasterRatio;
    // Slashing ratios to 0.3–0.55 for large exports made bitmaps smaller than
    // the PDF page box, so viewers scaled them up → unreadable blur. Chunking,
    // temp files, and hybrid vector extraction bound memory instead.
    final mobile = Platform.isAndroid || Platform.isIOS;
    if (pageCount > 2000) {
      effectiveRasterRatio = math.min(
        effectiveRasterRatio,
        mobile ? 1.72 : 2.2,
      );
    } else if (pageCount > 1400) {
      effectiveRasterRatio = math.min(
        effectiveRasterRatio,
        mobile ? 1.82 : 2.35,
      );
    } else if (pageCount > 900) {
      effectiveRasterRatio = math.min(
        effectiveRasterRatio,
        mobile ? 1.92 : 2.45,
      );
    } else if (pageCount > 500) {
      effectiveRasterRatio = math.min(
        effectiveRasterRatio,
        mobile ? 2.0 : 2.55,
      );
    }

    if (mobile) {
      effectiveRasterRatio = math.min(effectiveRasterRatio, 2.35);
    }
    return effectiveRasterRatio;
  }

  /// Builds a PDF for sharing. Prefer this over [generatePdf] when the result
  /// may be very large: [PdfExportData.tempFile] avoids loading the full PDF
  /// into the Dart heap.
  static Future<PdfExportData> generatePdfData(
    EditorCoreInfo coreInfo,
    BuildContext context, {
    List<int>? pageIndices,
    bool invert = false,
    bool shareLinks = false,
    double? rasterPixelRatio,
    void Function(int completed, int total)? onProgress,
  }) async {
    final resolvedRasterRatio =
        rasterPixelRatio ?? defaultPdfRasterPixelRatio();
    var infoToExport = coreInfo;
    if (shareLinks &&
        coreInfo.links.isNotEmpty &&
        coreInfo.links.any((l) => isExternalNoteLink(l, coreInfo.filePath))) {
      infoToExport = await expandLinksForShare(
        coreInfo,
        true,
        pageIndices: pageIndices,
      );
      // Force reset so the PDF generation iterates over the new, larger file count
      pageIndices = null;
    }

    // Strip links completely for PDF export so no popups/buttons render
    infoToExport = infoToExport.copyWith(links: const []);

    late final List<int> resolvedIndices;
    if (pageIndices == null) {
      resolvedIndices = List.generate(infoToExport.pages.length, (i) => i);
      if (resolvedIndices.isNotEmpty) {
        final last = resolvedIndices.last;
        infoToExport.ensurePageHydrated(last);
        if (infoToExport.pages[last].isEmpty) {
          resolvedIndices.removeLast();
        }
      }
    } else {
      resolvedIndices = List<int>.from(pageIndices);
    }

    final effectiveRasterRatio = _effectiveRasterRatioForPageCount(
      resolvedRasterRatio,
      resolvedIndices.length,
    );

    final remappedOutlines = remapPdfOutlinesForExport(
      infoToExport.pdfOutlines,
      pages: infoToExport.pages,
      resolvedNoteIndices: resolvedIndices,
    );
    // Native fast paths cannot attach package:pdf outlines. On Android we
    // inject bookmarks via PDFBox after export; elsewhere skip those paths.
    final skipNativeFastPathForOutlines =
        remappedOutlines != null &&
        remappedOutlines.isNotEmpty &&
        !(Platform.isAndroid);

    if (!kIsWeb && !invert && !skipNativeFastPathForOutlines) {
      final passthrough = await _tryPdfPassthroughUnmodifiedAssetCopy(
        infoToExport,
        pageIndices: resolvedIndices,
        onProgress: onProgress,
      );
      if (passthrough != null) {
        return _attachExportOutlinesIfNeeded(passthrough, remappedOutlines);
      }

      final quick = await _tryPdfrxAssembledPdfExport(
        infoToExport,
        context,
        pageIndices: resolvedIndices,
        invert: invert,
        effectiveRasterRatio: effectiveRasterRatio,
        onProgress: onProgress,
      );
      if (quick != null) {
        return _attachExportOutlinesIfNeeded(quick, remappedOutlines);
      }
    }

    final strokeOnly = await _tryStrokeOnlyFastPdfExport(
      infoToExport,
      resolvedIndices,
      invert: invert,
      onProgress: onProgress,
      exportOutlines: remappedOutlines,
    );
    if (strokeOnly != null) return PdfExportData.bytes(strokeOnly);

    final packagePdf = await _generatePdfUsingPackagePdf(
      infoToExport,
      context,
      pageIndices: resolvedIndices,
      invert: invert,
      effectiveRasterRatio: effectiveRasterRatio,
      onProgress: onProgress,
      exportOutlines: remappedOutlines,
    );
    return _attachExportOutlinesIfNeeded(packagePdf, remappedOutlines);
  }

  /// Injects remapped bookmarks into an already-built PDF (Android PDFBox).
  /// No-op when outlines are empty or already written by package:pdf.
  static Future<PdfExportData> _attachExportOutlinesIfNeeded(
    PdfExportData data,
    List<PdfOutlineItem>? remappedOutlines,
  ) async {
    if (remappedOutlines == null || remappedOutlines.isEmpty) return data;
    if (kIsWeb || !Platform.isAndroid) return data;

    final tempDir = await getTemporaryDirectory();
    late final String sourcePath;
    String? bytesTemp;
    try {
      if (data.tempPdfPath != null) {
        sourcePath = data.tempPdfPath!;
      } else {
        bytesTemp = p.join(
          tempDir.path,
          'saber_outline_src_${const Uuid().v4()}.pdf',
        );
        await File(bytesTemp).writeAsBytes(data.bytes!, flush: true);
        sourcePath = bytesTemp;
      }

      final outPath = p.join(
        tempDir.path,
        'saber_outline_out_${const Uuid().v4()}.pdf',
      );
      final injected = await PdfStrokeOverlay.setBookmarks(
        sourcePath: sourcePath,
        outputPath: outPath,
        outlines: pdfOutlinesToNativeMaps(remappedOutlines),
      );
      if (injected == null) return data;

      if (data.tempPdfPath != null && data.tempPdfPath != injected) {
        await _tryDeleteExportTempFile(data.tempPdfPath!);
      }
      if (bytesTemp != null) {
        await _tryDeleteExportTempFile(bytesTemp);
      }
      return PdfExportData.tempFile(injected);
    } catch (e, st) {
      _log.warning('Failed to attach export outlines', e, st);
      return data;
    }
  }

  /// Solid-background + vector ink only (no images / patterns / Quill).
  static bool _isStrokeOnlyVectorPage(EditorCoreInfo info, EditorPage page) {
    if (_needsWidgetRasterExport(page)) return false;
    if (page.backgroundImage != null) return false;
    if (page.allImagesInDrawOrder.isNotEmpty) return false;
    final pattern = _effectiveExportPattern(info, page);
    if (pattern != CanvasBackgroundPattern.none) return false;
    return true;
  }

  /// Fast path for handwritten notes: low-level [PdfDocument] + direct polygon
  /// ops (no widget tree / SVG). Used on all platforms; Android overlay encode
  /// has a further native path for PDF-background stamps.
  static Future<Uint8List?> _tryStrokeOnlyFastPdfExport(
    EditorCoreInfo info,
    List<int> pageIndices, {
    required bool invert,
    void Function(int completed, int total)? onProgress,
    List<PdfOutlineItem>? exportOutlines,
  }) async {
    if (pageIndices.isEmpty) return null;
    for (final idx in pageIndices) {
      info.ensurePageHydrated(idx);
      if (!_isStrokeOnlyVectorPage(info, info.pages[idx])) return null;
    }

    final sw = Stopwatch()..start();
    await PdfStrokeVectorEncoder.prepareExportPolygons([
      for (final idx in pageIndices) info.pages[idx],
    ]);
    final doc = PdfDocument();
    final total = pageIndices.length;
    for (var i = 0; i < total; i++) {
      final page = info.pages[pageIndices[i]];
      final size = page.size;
      final pdfPage = PdfPage(
        doc,
        pageFormat: PdfPageFormat(size.width, size.height, marginAll: 0),
      );
      final g = pdfPage.getGraphics();
      final bgColor =
          (info.backgroundColor ?? InnerCanvas.defaultBackgroundColor)
              .withInversion(invert);
      g.setFillColor(PdfColor.fromInt(bgColor.toARGB32()));
      g.drawRect(0, 0, size.width, size.height);
      g.fillPath();
      PdfStrokeVectorEncoder.paintPageStrokes(g, page, invert);
      onProgress?.call(i + 1, total);
      if (i.isOdd) await Future<void>.delayed(Duration.zero);
    }
    if (exportOutlines != null && exportOutlines.isNotEmpty) {
      attachPdfOutlinesToDocument(doc, exportOutlines);
    }
    final bytes = await doc.save();
    _log.info(
      '[export.metrics] stroke_only_fast_pdf pages=$total '
      'bytes=${bytes.length} ms=${sw.elapsedMilliseconds}',
    );
    return bytes;
  }

  /// Builds a PDF for sharing. Prefers PDFium page splicing ([pdfrx]) for
  /// PDF-background notes so multi‑thousand-page imports avoid full-document
  /// rasterization. Falls back to [pw.Document] when the layout needs it.
  ///
  /// For very large PDFs, [generatePdfData] + [FileManager.exportPdfTempFile]
  /// avoids an extra full-document copy in heap memory.
  static Future<Uint8List> generatePdf(
    EditorCoreInfo coreInfo,
    BuildContext context, {
    List<int>? pageIndices,
    bool invert = false,
    bool shareLinks = false,
    double? rasterPixelRatio,
    void Function(int completed, int total)? onProgress,
  }) async {
    final data = await generatePdfData(
      coreInfo,
      context,
      pageIndices: pageIndices,
      invert: invert,
      shareLinks: shareLinks,
      rasterPixelRatio: rasterPixelRatio,
      onProgress: onProgress,
    );
    if (data.bytes != null) return data.bytes!;
    final path = data.tempPdfPath!;
    try {
      return await File(path).readAsBytes();
    } finally {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  static Future<PdfExportData> _generatePdfUsingPackagePdf(
    EditorCoreInfo infoToExport,
    BuildContext context, {
    required List<int> pageIndices,
    required bool invert,
    required double effectiveRasterRatio,
    void Function(int completed, int total)? onProgress,
    List<PdfOutlineItem>? exportOutlines,
  }) async {
    final total = pageIndices.length;
    final chunkCap = _exportChunkPageCap();
    // Keep a single document when writing bookmarks so page refs stay valid.
    final mustBeSingleDoc = exportOutlines != null && exportOutlines.isNotEmpty;

    if (total <= chunkCap || mustBeSingleDoc) {
      final bytes = await _generatePdfUsingPackagePdfChunk(
        infoToExport,
        context,
        pageIndices: pageIndices,
        invert: invert,
        effectiveRasterRatio: effectiveRasterRatio,
        globalTotalPages: total,
        onProgress: onProgress,
        exportOutlines: exportOutlines,
      );
      return PdfExportData.bytes(bytes);
    }

    final tempDir = await getTemporaryDirectory();
    final partPaths = <String>[];
    try {
      for (var start = 0; start < total; start += chunkCap) {
        final end = math.min(start + chunkCap, total);
        final chunk = pageIndices.sublist(start, end);
        final bytes = await _generatePdfUsingPackagePdfChunk(
          infoToExport,
          context,
          pageIndices: chunk,
          invert: invert,
          effectiveRasterRatio: effectiveRasterRatio,
          globalTotalPages: total,
          onProgress: (done, sub) {
            onProgress?.call(start + done, total);
          },
        );
        final partPath = p.join(
          tempDir.path,
          'saber_pw_part_${const Uuid().v4()}.pdf',
        );
        await File(partPath).writeAsBytes(bytes, flush: true);
        partPaths.add(partPath);
        await Future<void>.delayed(Duration.zero);
      }

      if (partPaths.length == 1) {
        return PdfExportData.tempFile(partPaths.single);
      }

      final mergedPath = p.join(
        tempDir.path,
        'saber_pw_merged_${const Uuid().v4()}.pdf',
      );
      await PdfCombiner.mergeMultiplePDFs(
        inputPaths: partPaths,
        outputPath: mergedPath,
      );
      for (final pp in partPaths) {
        try {
          await File(pp).delete();
        } catch (_) {}
      }
      return PdfExportData.tempFile(mergedPath);
    } catch (_) {
      for (final pp in partPaths) {
        try {
          await File(pp).delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Single [pw.Document] for up to [pageIndices.length] pages; frees memory
  /// before callers merge chunks on huge exports.
  static Future<Uint8List> _generatePdfUsingPackagePdfChunk(
    EditorCoreInfo infoToExport,
    BuildContext context, {
    required List<int> pageIndices,
    required bool invert,
    required double effectiveRasterRatio,
    required int globalTotalPages,
    void Function(int completed, int total)? onProgress,
    List<PdfOutlineItem>? exportOutlines,
  }) async {
    final pdf = pw.Document();
    final screenshotController = ScreenshotController();
    final rasterCache = _RasterExportCache();

    void addExportPage(int pageIndex, Uint8List? capturedImageBytes) {
      final page = infoToExport.pages[pageIndex];
      final pageSize = page.size;
      final pageHeight = pageSize.height;
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(pageSize.width, pageHeight, marginAll: 0),
          build: (pw.Context context) {
            final children = <pw.Widget>[];

            if (capturedImageBytes != null && capturedImageBytes.isNotEmpty) {
              children.add(
                pw.Positioned(
                  left: 0,
                  bottom: 0,
                  child: pw.Image(
                    pw.MemoryImage(capturedImageBytes),
                    width: pageSize.width,
                    height: pageSize.height,
                    fit: pw.BoxFit.fill,
                  ),
                ),
              );
            }

            children.add(
              pw.Positioned(
                left: 0,
                bottom: 0,
                child: pw.CustomPaint(
                  size: PdfPoint(pageSize.width, pageSize.height),
                  painter: (PdfGraphics canvas, PdfPoint size) {
                    if (capturedImageBytes == null ||
                        capturedImageBytes.isEmpty) {
                      final bgColor =
                          (infoToExport.backgroundColor ??
                                  InnerCanvas.defaultBackgroundColor)
                              .withInversion(invert);
                      canvas.setFillColor(PdfColor.fromInt(bgColor.toARGB32()));
                      canvas.drawRect(0, 0, size.x, size.y);
                      canvas.fillPath();
                    }

                    paintVectorStrokesForPdfExport(canvas, page, invert);
                  },
                ),
              ),
            );

            return pw.FullPage(
              ignoreMargins: true,
              child: pw.Stack(children: children),
            );
          },
        ),
      );
    }

    try {
      for (final idx in pageIndices) {
        infoToExport.ensurePageHydrated(idx);
      }
      await PdfStrokeVectorEncoder.prepareExportPolygons([
        for (final idx in pageIndices) infoToExport.pages[idx],
      ]);
      var completedPages = 0;
      final total = pageIndices.length;
      // One page at a time on mobile: each raster can be tens of MB for large
      // PDF backgrounds; concurrency 2 routinely OOMs during export.save().
      final concurrency = (Platform.isAndroid || Platform.isIOS)
          ? 1
          : math.min(6, math.max(3, Platform.numberOfProcessors ~/ 2));

      var i = 0;
      while (i < total) {
        infoToExport.ensurePageHydrated(pageIndices[i]);
        final pageIndex = pageIndices[i];
        if (_needsWidgetRasterExport(infoToExport.pages[pageIndex])) {
          final bytes = await _captureExportPageRasterBytes(
            infoToExport: infoToExport,
            context: context,
            pageIndex: pageIndex,
            invert: invert,
            effectiveRasterRatio: effectiveRasterRatio,
            totalExportPages: globalTotalPages,
            screenshotController: screenshotController,
            rasterCache: rasterCache,
          );
          addExportPage(pageIndex, bytes);
          completedPages++;
          onProgress?.call(completedPages, total);
          i++;
          await Future<void>.delayed(Duration.zero);
          continue;
        }

        var j = i;
        while (j < total && j - i < concurrency) {
          infoToExport.ensurePageHydrated(pageIndices[j]);
          if (_needsWidgetRasterExport(infoToExport.pages[pageIndices[j]])) {
            break;
          }
          j++;
        }

        final batch = pageIndices.sublist(i, j);
        final bytesList = await Future.wait(
          batch.map((idx) async {
            infoToExport.ensurePageHydrated(idx);
            return _captureExportPageRasterBytes(
              infoToExport: infoToExport,
              context: context,
              pageIndex: idx,
              invert: invert,
              effectiveRasterRatio: effectiveRasterRatio,
              totalExportPages: globalTotalPages,
              screenshotController: screenshotController,
              rasterCache: rasterCache,
            );
          }),
        );

        for (var k = 0; k < batch.length; k++) {
          addExportPage(batch[k], bytesList[k]);
          completedPages++;
          onProgress?.call(completedPages, total);
        }
        i = j;
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      rasterCache.dispose();
    }

    if (exportOutlines != null && exportOutlines.isNotEmpty) {
      attachPdfOutlinesToDocument(pdf.document, exportOutlines);
    }

    return pdf.save();
  }

  static int jpegQualityForPixelRatio(double pixelRatio) {
    int q;
    if (pixelRatio >= 300 / 72 - 0.01) {
      q = 94;
    } else if (pixelRatio >= 150 / 72 - 0.01) {
      q = 90;
    } else if (pixelRatio >= 1.25 - 0.01) {
      q = 86;
    } else {
      q = 82;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      q -= 3;
    }
    return q.clamp(76, 94);
  }

  /// Matches [InnerCanvas] / [CanvasBackgroundPainter] line colors for export
  /// without relying on app theme primaries.
  static (Color primary, Color secondary) _patternLineColorsForExport(
    EditorPage page,
  ) {
    final lc = page.lineColor;
    if (lc.toARGB32() != 0xFF9E9E9E) {
      return (lc, lc.withValues(alpha: 0.5));
    }
    return (
      exportDefaultLineGray,
      exportDefaultLineGray.withValues(alpha: 0.5),
    );
  }

  static Future<Uint8List> _encodeUiImageAsJpeg(
    ui.Image image,
    double pixelRatio,
  ) async {
    final raw = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (raw == null) {
      throw StateError('Failed to read pixels for PDF raster export');
    }
    return compute(
      _encodeJpegInIsolate,
      _JpegEncodeArgs(
        rgba: TransferableTypedData.fromList([
          raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
        ]),
        width: image.width,
        height: image.height,
        quality: jpegQualityForPixelRatio(pixelRatio),
      ),
    );
  }

  static Uint8List _asUint8List(List<int> bytes) {
    return bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  }

  static bool _pageHasQuillContent(EditorPage page) {
    final doc = page.quill.controller.document;
    if (doc.isEmpty()) return false;
    return doc.toPlainText().trim().isNotEmpty;
  }

  static Rect _safeImageSrcRect(EditorImage image, Size fallbackSize) {
    if (image.srcRect.width > 0 && image.srcRect.height > 0) {
      return image.srcRect;
    }
    if (image.naturalSize.width > 0 && image.naturalSize.height > 0) {
      return Offset.zero & image.naturalSize;
    }
    return Offset.zero & fallbackSize;
  }

  static void _withImageTransform(
    Canvas canvas,
    Rect rect,
    double rotationDeg,
    void Function(Rect localRect) paint,
  ) {
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    if (rotationDeg != 0) {
      canvas.rotate(rotationDeg * math.pi / 180.0);
    }
    paint(
      Rect.fromCenter(
        center: Offset.zero,
        width: rect.width,
        height: rect.height,
      ),
    );
    canvas.restore();
  }

  static Future<ui.Image?> _decodePngEditorImage(PngEditorImage image) async {
    final bytes = await image.assetCacheAll.getBytes(image.assetId);
    if (bytes.isEmpty) return null;
    final codec = await ui.instantiateImageCodec(_asUint8List(bytes));
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  static Future<ui.Image?> _rasterizeSvgEditorImage(
    SvgEditorImage image,
  ) async {
    final bytes = await image.assetCacheAll.getBytes(image.assetId);
    final SvgLoader loader = bytes.isNotEmpty
        ? SvgBytesLoader(_asUint8List(bytes))
        : image.svgLoader;
    final pictureInfo = await vg.loadPicture(loader, null);
    try {
      final size = image.naturalSize.isEmpty
          ? pictureInfo.size
          : image.naturalSize;
      final width = size.width.round().clamp(1, 8192);
      final height = size.height.round().clamp(1, 8192);
      return pictureInfo.picture.toImage(width, height);
    } finally {
      pictureInfo.picture.dispose();
    }
  }

  static Future<ui.Image?> _rasterizePdfEditorImage(
    PdfEditorImage image,
    double pixelRatio,
  ) async {
    final file = image.pdfFile;
    final pdfrx.PdfDocument document;
    if (file != null && await file.exists()) {
      document = await _RasterExportCache._openPdfFileForRaster(file.path);
    } else {
      final bytes = await image.assetCacheAll.getBytes(image.assetId);
      if (bytes.isEmpty) return null;
      document = await _RasterExportCache._openPdfDataForRaster(
        _asUint8List(bytes),
      );
    }
    try {
      return await _rasterizePdfPage(
        document,
        image.pdfPage,
        image.naturalSize,
        pixelRatio,
      );
    } finally {
      document.dispose();
    }
  }

  static Future<ui.Image?> _rasterizePdfPage(
    pdfrx.PdfDocument document,
    int pageIndex,
    Size naturalSize,
    double pixelRatio,
  ) async {
    if (pageIndex < 0 || pageIndex >= document.pages.length) {
      return null;
    }
    final page = document.pages[pageIndex];
    final targetSize = naturalSize.isEmpty
        ? Size(page.width, page.height)
        : naturalSize;
    final rendered = await page.render(
      fullWidth: math.max(1, targetSize.width * pixelRatio),
      fullHeight: math.max(1, targetSize.height * pixelRatio),
      backgroundColor: Colors.white.toARGB32(),
    );
    if (rendered == null) return null;
    return rendered.createImage();
  }

  static Future<bool> _paintEditorImage(
    Canvas canvas,
    EditorImage image, {
    required Size pageSize,
    required bool invert,
    required double pixelRatio,
    bool isBackground = false,
    _RasterExportCache? cache,
  }) async {
    await image.loadIn();
    final rect = isBackground ? Offset.zero & pageSize : image.dstRect;
    if (rect.width <= 0 || rect.height <= 0) return true;

    final paint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.high
      ..colorFilter = invert && image.invertible ? _invertColorFilter : null;

    if (image is PngEditorImage) {
      final decoded = await (cache?.png(image) ?? _decodePngEditorImage(image));
      if (decoded == null) return false;
      try {
        if (isBackground) {
          paintImage(
            canvas: canvas,
            rect: rect,
            image: decoded,
            fit: image.backgroundFit,
            alignment: Alignment.center,
            colorFilter: paint.colorFilter,
            filterQuality: FilterQuality.high,
          );
        } else {
          final srcRect = _safeImageSrcRect(
            image,
            Size(decoded.width.toDouble(), decoded.height.toDouble()),
          );
          _withImageTransform(canvas, rect, image.rotationDeg, (localRect) {
            canvas.drawImageRect(decoded, srcRect, localRect, paint);
          });
        }
      } finally {
        decoded.dispose();
      }
      return true;
    }

    if (image is SvgEditorImage) {
      final decoded =
          await (cache?.svg(image) ?? _rasterizeSvgEditorImage(image));
      if (decoded == null) return false;
      try {
        final srcRect = _safeImageSrcRect(
          image,
          Size(decoded.width.toDouble(), decoded.height.toDouble()),
        );
        _withImageTransform(canvas, rect, image.rotationDeg, (localRect) {
          canvas.drawImageRect(decoded, srcRect, localRect, paint);
        });
      } finally {
        decoded.dispose();
      }
      return true;
    }

    if (image is PdfEditorImage) {
      final decoded =
          await (cache?.pdf(image, pixelRatio) ??
              _rasterizePdfEditorImage(image, pixelRatio));
      if (decoded == null) return false;
      try {
        final srcRect =
            Offset.zero &
            Size(decoded.width.toDouble(), decoded.height.toDouble());
        _withImageTransform(canvas, rect, image.rotationDeg, (localRect) {
          canvas.drawImageRect(decoded, srcRect, localRect, paint);
        });
      } finally {
        decoded.dispose();
      }
      return true;
    }

    return false;
  }

  /// Renders the page to a bitmap (same pipeline for PNG and JPEG export).
  ///
  /// When [reusePdfForBackground] is set and the page uses a [PdfEditorImage]
  /// background, rasterizes that page from this document instead of opening
  /// another PDF via [_RasterExportCache] (critical for large PDF-backed notes).
  static Future<ui.Image> _rasterizePageForRasterExport(
    EditorCoreInfo coreInfo, {
    required int pageIndex,
    bool invert = false,
    double pixelRatio = 2.0,
    _RasterExportCache? cache,
    bool includeStrokes = true,
    pdfrx.PdfDocument? reusePdfForBackground,
  }) async {
    final page = coreInfo.pages[pageIndex];
    final size = page.size;

    final baseNoteBg =
        coreInfo.backgroundColor ?? InnerCanvas.defaultBackgroundColor;
    final Color resolvedBgColor;
    if (page.backgroundImage != null) {
      resolvedBgColor = Colors.white;
    } else if (page.backgroundColor.toARGB32() != 0xFFFFFFFF) {
      resolvedBgColor = page.backgroundColor;
    } else {
      resolvedBgColor = baseNoteBg;
    }

    final pattern = page.backgroundImage != null
        ? CanvasBackgroundPattern.none
        : (page.backgroundPattern ?? coreInfo.backgroundPattern);

    final lineH = page.hasLocalLineHeight
        ? page.lineHeight
        : coreInfo.lineHeight;
    final lineT = page.hasLocalLineThickness
        ? page.lineThickness.round().clamp(1, 100)
        : coreInfo.lineThickness;

    final (patternPrimary, patternSecondary) = _patternLineColorsForExport(
      page,
    );

    final bool useBorder =
        page.hasLocalBorderColor ||
        page.marginLeft > 0 ||
        page.marginRight > 0 ||
        page.marginTop > 0 ||
        page.marginBottom > 0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.save();
    if (pixelRatio != 1.0) {
      canvas.scale(pixelRatio, pixelRatio);
    }

    CanvasBackgroundPainter(
      invert: invert,
      backgroundColor: resolvedBgColor,
      backgroundPattern: pattern,
      lineHeight: lineH,
      lineThickness: lineT,
      primaryColor: patternPrimary,
      secondaryColor: patternSecondary,
      marginLeft: page.marginLeft,
      marginRight: page.marginRight,
      marginTop: page.marginTop,
      marginBottom: page.marginBottom,
      borderColor: useBorder ? page.borderColor : null,
    ).paint(canvas, size);

    if (page.backgroundImage != null) {
      final bg = page.backgroundImage!;
      if (bg is PdfEditorImage &&
          reusePdfForBackground != null &&
          bg.pdfPage >= 0 &&
          bg.pdfPage < reusePdfForBackground.pages.length) {
        final pdfImage = await _rasterizePdfPage(
          reusePdfForBackground,
          bg.pdfPage,
          bg.naturalSize,
          pixelRatio,
        );
        if (pdfImage != null) {
          try {
            final paint = Paint()
              ..isAntiAlias = true
              ..filterQuality = FilterQuality.high
              ..colorFilter = invert && bg.invertible
                  ? _invertColorFilter
                  : null;
            final rect = Offset.zero & size;
            final srcRect =
                Offset.zero &
                Size(pdfImage.width.toDouble(), pdfImage.height.toDouble());
            _withImageTransform(canvas, rect, bg.rotationDeg, (localRect) {
              canvas.drawImageRect(pdfImage, srcRect, localRect, paint);
            });
          } finally {
            pdfImage.dispose();
          }
        } else {
          final paintedBackground = await _paintEditorImage(
            canvas,
            page.backgroundImage!,
            pageSize: size,
            invert: invert,
            pixelRatio: pixelRatio,
            isBackground: true,
            cache: cache,
          );
          if (!paintedBackground) {
            throw StateError('Failed to paint background image for export');
          }
        }
      } else {
        final paintedBackground = await _paintEditorImage(
          canvas,
          page.backgroundImage!,
          pageSize: size,
          invert: invert,
          pixelRatio: pixelRatio,
          isBackground: true,
          cache: cache,
        );
        if (!paintedBackground) {
          throw StateError('Failed to paint background image for export');
        }
      }
    }

    for (final image in page.allImagesInDrawOrder) {
      final paintedImage = await _paintEditorImage(
        canvas,
        image,
        pageSize: size,
        invert: invert,
        pixelRatio: pixelRatio,
        cache: cache,
      );
      if (!paintedImage) {
        throw StateError('Failed to paint canvas image for export');
      }
    }
    canvas.restore();

    if (includeStrokes) {
      canvas.save();
      if (pixelRatio != 1.0) {
        canvas.scale(pixelRatio, pixelRatio);
      }
      canvas.translate(0, size.height);
      canvas.scale(1, -1);

      for (final stroke in page.allStrokesInDrawOrder) {
        final color = stroke.color.withInversion(invert);
        final isPolygonStroke =
            stroke is! CircleStroke &&
            stroke is! RectangleStroke &&
            stroke is! ShapeStroke;
        final shapeStroke = stroke is ShapeStroke ? stroke : null;

        late final Path path;
        if (isPolygonStroke) {
          final poly = PdfStrokeVectorEncoder.exportPolygon(stroke);
          if (poly.length < 2) continue;
          path = Path()
            ..addPolygon([
              for (final p in poly)
                Offset(p.dx, PdfStrokeVectorEncoder.pdfY(p.dy, size.height)),
            ], true);
        } else {
          final pathStr = stroke.toSvgPath();
          if (pathStr.isEmpty) continue;
          path = parseSvgPathData(pathStr);
        }

        if (isPolygonStroke) {
          final paint = Paint()
            ..color = color
            ..style = PaintingStyle.fill
            ..isAntiAlias = true;
          if (stroke.toolId == ToolId.highlighter) {
            paint.blendMode = invert ? BlendMode.plus : BlendMode.darken;
          }
          canvas.drawPath(path, paint);
        } else if (shapeStroke != null && shapeStroke.fill) {
          final fillPaint = Paint()
            ..color = shapeStroke.fillColor.withInversion(invert)
            ..style = PaintingStyle.fill
            ..isAntiAlias = true;
          canvas.drawPath(path, fillPaint);
          final strokePaint = Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke.options.size
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..isAntiAlias = true;
          if (stroke.toolId == ToolId.highlighter) {
            strokePaint.blendMode = invert ? BlendMode.plus : BlendMode.darken;
          }
          canvas.drawPath(path, strokePaint);
        } else {
          final paint = Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke.options.size
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..isAntiAlias = true;
          if (stroke.toolId == ToolId.highlighter) {
            paint.blendMode = invert ? BlendMode.plus : BlendMode.darken;
          }
          canvas.drawPath(path, paint);
        }
      }
      canvas.restore();
    }

    final picture = recorder.endRecording();

    final w = (size.width * pixelRatio).round().clamp(1, 16384);
    final h = (size.height * pixelRatio).round().clamp(1, 16384);
    return picture.toImage(w, h);
  }

  static bool _needsWidgetRasterExport(EditorPage page) {
    return _pageHasQuillContent(page);
  }

  static Future<Uint8List> _screenshotPageForRasterExport(
    EditorCoreInfo coreInfo,
    BuildContext context, {
    required int pageIndex,
    bool invert = false,
    double pixelRatio = 2.0,
  }) {
    return screenshotPage(
      coreInfo: coreInfo,
      pageIndex: pageIndex,
      screenshotController: ScreenshotController(),
      context: context,
      invert: invert,
      fullPage: true,
      pixelRatio: pixelRatio,
    );
  }

  static Future<ui.Image> _decodeUiImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// Encodes with Skia (fast at high resolution). Prefer over [generateJpeg] when speed matters.
  static Future<Uint8List> generatePng(
    EditorCoreInfo coreInfo,
    BuildContext context, {
    required int pageIndex,
    bool invert = false,
    double pixelRatio = 2.0,
  }) async {
    return _generatePng(
      coreInfo,
      context,
      pageIndex: pageIndex,
      invert: invert,
      pixelRatio: pixelRatio,
    );
  }

  static Future<Uint8List> _generatePng(
    EditorCoreInfo coreInfo,
    BuildContext context, {
    required int pageIndex,
    bool invert = false,
    double pixelRatio = 2.0,
    _RasterExportCache? cache,
  }) async {
    coreInfo.ensurePageHydrated(pageIndex);
    final page = coreInfo.pages[pageIndex];
    if (_needsWidgetRasterExport(page)) {
      return _screenshotPageForRasterExport(
        coreInfo,
        context,
        pageIndex: pageIndex,
        invert: invert,
        pixelRatio: pixelRatio,
      );
    }

    final raster = await _rasterizePageForRasterExport(
      coreInfo,
      pageIndex: pageIndex,
      invert: invert,
      pixelRatio: pixelRatio,
      cache: cache,
    );
    try {
      final png = await raster.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) {
        throw StateError('Failed to encode PNG export');
      }
      return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
    } finally {
      raster.dispose();
    }
  }

  static Future<Uint8List> generateJpeg(
    EditorCoreInfo coreInfo,
    BuildContext context, {
    required int pageIndex,
    bool invert = false,
    double pixelRatio = 2.0,
    int? jpegQuality,
  }) async {
    return _generateJpeg(
      coreInfo,
      context,
      pageIndex: pageIndex,
      invert: invert,
      pixelRatio: pixelRatio,
      jpegQuality: jpegQuality,
    );
  }

  static Future<Uint8List> _generateJpeg(
    EditorCoreInfo coreInfo,
    BuildContext context, {
    required int pageIndex,
    bool invert = false,
    double pixelRatio = 2.0,
    int? jpegQuality,
    _RasterExportCache? cache,
  }) async {
    coreInfo.ensurePageHydrated(pageIndex);
    final page = coreInfo.pages[pageIndex];
    final ui.Image raster;
    if (_needsWidgetRasterExport(page)) {
      final screenshot = _screenshotPageForRasterExport(
        coreInfo,
        context,
        pageIndex: pageIndex,
        invert: invert,
        pixelRatio: pixelRatio,
      );
      raster = await _decodeUiImage(await screenshot);
    } else {
      raster = await _rasterizePageForRasterExport(
        coreInfo,
        pageIndex: pageIndex,
        invert: invert,
        pixelRatio: pixelRatio,
        cache: cache,
      );
    }
    try {
      final raw = await raster.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (raw == null) {
        throw StateError('Failed to read pixels for JPEG export');
      }
      final w = raster.width;
      final h = raster.height;
      final q = jpegQuality ?? jpegQualityForPixelRatio(pixelRatio);
      return compute(
        _encodeJpegInIsolate,
        _JpegEncodeArgs(
          rgba: TransferableTypedData.fromList([
            raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
          ]),
          width: w,
          height: h,
          quality: q,
        ),
      );
    } finally {
      raster.dispose();
    }
  }

  static Future<List<({int pageIndex, Uint8List bytes})>> generateRasterPages(
    EditorCoreInfo coreInfo,
    BuildContext context, {
    required List<int> pageIndices,
    required bool jpeg,
    bool invert = false,
    double pixelRatio = 2.0,
    void Function(int completed, int total)? onProgress,
  }) async {
    coreInfo.hydrateAllLazyPages();
    final cache = _RasterExportCache();
    final pages = <({int pageIndex, Uint8List bytes})>[];
    try {
      for (var i = 0; i < pageIndices.length; i++) {
        final pageIndex = pageIndices[i];
        final bytes = jpeg
            ? await _generateJpeg(
                coreInfo,
                context,
                pageIndex: pageIndex,
                invert: invert,
                pixelRatio: pixelRatio,
                cache: cache,
              )
            : await _generatePng(
                coreInfo,
                context,
                pageIndex: pageIndex,
                invert: invert,
                pixelRatio: pixelRatio,
                cache: cache,
              );
        pages.add((pageIndex: pageIndex, bytes: bytes));
        onProgress?.call(i + 1, pageIndices.length);
        if (i.isOdd) await Future<void>.delayed(Duration.zero);
      }
      return pages;
    } finally {
      cache.dispose();
    }
  }

  static Future<Uint8List> screenshotPage({
    required EditorCoreInfo coreInfo,
    required int pageIndex,
    required ScreenshotController screenshotController,
    required BuildContext context,
    bool invert = false,
    bool fullPage = false,
    double? pixelRatio,
  }) async {
    final resolvedPixelRatio = pixelRatio ?? defaultPdfRasterPixelRatio();
    final pageSize = coreInfo.pages[pageIndex].size;
    final coreInfoToRender = fullPage
        ? coreInfo
        : coreInfo.copyWith(
            pages: coreInfo.pages
                .map(
                  (page) => page.copyWith(
                    strokes: page.allStrokesInDrawOrder
                        .where(_shouldRasterizeStroke)
                        .toList(),
                  ),
                )
                .toList(),
          );

    final view = WidgetsBinding.instance.platformDispatcher.views.isNotEmpty
        ? WidgetsBinding.instance.platformDispatcher.views.first
        : null;
    final mediaQuery = view != null
        ? MediaQueryData.fromView(view)
        : const MediaQueryData(size: Size(800, 600));

    return await screenshotController.captureFromWidget(
      MediaQuery(
        data: mediaQuery,
        child: Localizations(
          locale: const Locale('en', 'US'),
          delegates: GlobalMaterialLocalizations.delegates,
          child: Theme(
            data: ThemeData(
              brightness: .light,
              colorScheme: const ColorScheme.light(
                primary: exportDefaultLineGray,
                secondary: exportDefaultLineGray,
              ),
            ),
            child: InnerCanvas(
              pageIndex: pageIndex,
              width: pageSize.width,
              height: pageSize.height,
              isPrint: true,
              textEditing: false,
              coreInfo: coreInfoToRender,
              currentStroke: null,
              currentStrokeDetectedShape: null,
              currentSelection: null,
              currentToolIsSelect: false,
              currentScale: double.maxFinite,
              overrideInvert: invert,
            ),
          ),
        ),
      ),
      context: context.mounted ? context : null,
      pixelRatio: resolvedPixelRatio,
      targetSize: pageSize,
      delay: Duration.zero,
    );
  }
}
