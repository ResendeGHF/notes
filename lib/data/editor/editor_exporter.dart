// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io' show File;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:image/image.dart' as img;
import 'package:path_drawing/path_drawing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
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
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:screenshot/screenshot.dart';

class _JpegEncodeArgs {
  const _JpegEncodeArgs({
    required this.rgba,
    required this.width,
    required this.height,
    required this.quality,
  });

  final Uint8List rgba;
  final int width;
  final int height;
  final int quality;
}

Uint8List _encodeJpegInIsolate(_JpegEncodeArgs args) {
  final decoded = img.Image.fromBytes(
    width: args.width,
    height: args.height,
    bytes: args.rgba.buffer,
    bytesOffset: args.rgba.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(img.encodeJpg(decoded, quality: args.quality));
}

abstract class EditorExporter {

  /// Line color used in export when the page uses the default line gray. Matches
  /// [Page]'s default and avoids theme primary/secondary (e.g. blue/red) in PDF
  /// screenshots and JPEG raster backgrounds.
  static const exportDefaultLineGray = Color(0xFF9E9E9E);

  /// Raster page captures (images, PDF backgrounds, etc.) use this scale for PDF export.
  /// Higher = sharper PDFs; 3.5 balances quality and speed on typical devices.
  static const pdfRasterPixelRatio = 3.5;

  static bool _shouldRasterizeStroke(Stroke stroke) {
    return stroke.toolId == .highlighter || stroke is ShapeStroke;
  }

  static const double _linkMarginHeight = 36;
  static const double _linkCardPadding = 12;

  static Future<pw.Document> generatePdf(
    EditorCoreInfo coreInfo,
    BuildContext context, {
    List<int>? pageIndices,
    bool invert = false,
    bool shareLinks = false,
    double rasterPixelRatio = pdfRasterPixelRatio,
  }) async {
    var infoToExport = coreInfo;
    if (shareLinks &&
        coreInfo.links.isNotEmpty &&
        coreInfo.links.any((l) => isExternalNoteLink(l, coreInfo.filePath))) {
      infoToExport = await expandLinksForShare(coreInfo, true);
    }

    if (pageIndices == null) {
      pageIndices = List.generate(infoToExport.pages.length, (index) => index);
      if (infoToExport.pages.isNotEmpty && infoToExport.pages.last.isEmpty) {
        pageIndices.removeLast();
      }
    }

    // No title/author/creator/producer — PDF carries no Saber note metadata.
    final pdf = pw.Document();
    final screenshotController = ScreenshotController();

    for (final pageIndex in pageIndices) {
      final page = infoToExport.pages[pageIndex];
      final pageSize = page.size;

      final linksOnPage = infoToExport.linksForPage(page, pageIndex);
      final appendedLink = infoToExport.links.where((l) {
        if (l.targetPath.isEmpty) return false;
        final start = l.targetPageIndex;
        final end = l.targetPageIndexEnd ?? l.targetPageIndex;
        return pageIndex >= start && pageIndex <= end;
      }).firstOrNull;

      final hasAppendedMargin = shareLinks && appendedLink != null;
      final hasLinkCard =
          shareLinks && linksOnPage.isNotEmpty && !hasAppendedMargin;

      final pageHeight =
          pageSize.height + (hasAppendedMargin ? _linkMarginHeight : 0);

      final needsScreenshot =
          page.backgroundImage != null ||
          page.allImagesInDrawOrder.isNotEmpty ||
          page.backgroundPattern != null;
      Uint8List? pageImageBytes;
      if (needsScreenshot) {
        pageImageBytes = await screenshotPage(
          coreInfo: infoToExport,
          pageIndex: pageIndex,
          screenshotController: screenshotController,
          context: context,
          invert: invert,
          fullPage: true,
          pixelRatio: rasterPixelRatio,
        );
      }

      final capturedImageBytes = pageImageBytes;

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
            } else {
              children.add(
                pw.Positioned(
                  left: 0,
                  bottom: 0,
                  child: pw.CustomPaint(
                    size: PdfPoint(pageSize.width, pageSize.height),
                    painter: (PdfGraphics canvas, PdfPoint size) {
                      final bgColor =
                          (infoToExport.backgroundColor ??
                                  InnerCanvas.defaultBackgroundColor)
                              .withInversion(invert);
                      canvas.setFillColor(PdfColor.fromInt(bgColor.toARGB32()));
                      canvas.drawRect(0, 0, size.x, size.y);
                      canvas.fillPath();

                      for (final stroke in page.allStrokesInDrawOrder) {
                        final color = stroke.color.withInversion(invert);
                        final path = stroke.toSvgPath();
                        if (path.isEmpty) continue;

                        final isPolygonStroke =
                            stroke is! CircleStroke &&
                            stroke is! RectangleStroke &&
                            stroke is! ShapeStroke;
                        final shapeStroke = stroke is ShapeStroke
                            ? stroke
                            : null;

                        if (isPolygonStroke) {
                          canvas.setFillColor(
                            PdfColor.fromInt(color.toARGB32()),
                          );
                          canvas.drawShape(path);
                          canvas.fillPath();
                        } else if (shapeStroke != null && shapeStroke.fill) {
                          canvas.setFillColor(
                            PdfColor.fromInt(
                              shapeStroke.fillColor
                                  .withInversion(invert)
                                  .toARGB32(),
                            ),
                          );
                          canvas.drawShape(path);
                          canvas.fillPath();
                          canvas.setStrokeColor(
                            PdfColor.fromInt(color.toARGB32()),
                          );
                          canvas.setLineWidth(stroke.options.size);
                          canvas.drawShape(path);
                          canvas.strokePath();
                        } else {
                          canvas.setStrokeColor(
                            PdfColor.fromInt(color.toARGB32()),
                          );
                          canvas.setLineWidth(stroke.options.size);
                          canvas.drawShape(path);
                          canvas.strokePath();
                        }
                      }
                    },
                  ),
                ),
              );
            }

            if (hasAppendedMargin) {
              final label = formatLinkLabelForPdf(appendedLink);
              children.insert(
                0,
                pw.Positioned(
                  left: 0,
                  top: 0,
                  child: pw.Container(
                    width: pageSize.width,
                    height: _linkMarginHeight,
                    padding: const pw.EdgeInsets.all(_linkCardPadding),
                    color: PdfColors.grey300,
                    child: pw.Align(
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Text(
                        label,
                        style: pw.TextStyle(
                          fontSize: 11,
                          color: PdfColors.grey800,
                        ),
                        maxLines: 1,
                        overflow: pw.TextOverflow.clip,
                      ),
                    ),
                  ),
                ),
              );
            }

            if (hasLinkCard) {
              final linkLabels = linksOnPage
                  .map((l) => formatLinkLabelForPdf(l))
                  .toList();
              children.add(
                pw.Positioned(
                  left: _linkCardPadding,
                  top: _linkCardPadding,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(_linkCardPadding),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      border: pw.Border.all(color: PdfColors.grey400, width: 1),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Column(
                      mainAxisSize: pw.MainAxisSize.min,
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: linkLabels
                          .map(
                            (text) => pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(
                                vertical: 4,
                              ),
                              child: pw.Text(
                                text,
                                style: const pw.TextStyle(
                                  fontSize: 10,
                                  color: PdfColors.grey900,
                                ),
                                maxLines: 1,
                                overflow: pw.TextOverflow.clip,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              );
            }

            return pw.FullPage(
              ignoreMargins: true,
              child: pw.Stack(children: children),
            );
          },
        ),
      );
    }

    return pdf;
  }

  static int jpegQualityForPixelRatio(double pixelRatio) {
    if (pixelRatio >= 300 / 72 - 0.01) return 94;
    if (pixelRatio >= 150 / 72 - 0.01) return 88;
    return 80;
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

  static Future<ui.Image?> _decodeRasterBackgroundForExport(
    EditorCoreInfo coreInfo,
    EditorImage image,
  ) async {
    if (image is! PngEditorImage) return null;
    final File file = coreInfo.assetCacheAll.getAssetFile(image.assetId);
    if (!file.existsSync()) return null;
    final bytes = file.readAsBytesSync();
    if (bytes.isEmpty) return null;
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// Renders the page to a bitmap (same pipeline for PNG and JPEG export).
  static Future<ui.Image> _rasterizePageForRasterExport(
    EditorCoreInfo coreInfo, {
    required int pageIndex,
    bool invert = false,
    double pixelRatio = 2.0,
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

    final lineH =
        page.hasLocalLineHeight ? page.lineHeight : coreInfo.lineHeight;
    final lineT = page.hasLocalLineThickness
        ? page.lineThickness.round().clamp(1, 100)
        : coreInfo.lineThickness;

    final (patternPrimary, patternSecondary) = _patternLineColorsForExport(page);

    final bool useBorder = page.hasLocalBorderColor ||
        page.marginLeft > 0 ||
        page.marginRight > 0 ||
        page.marginTop > 0 ||
        page.marginBottom > 0;

    ui.Image? bgImage;
    if (page.backgroundImage != null) {
      bgImage = await _decodeRasterBackgroundForExport(
        coreInfo,
        page.backgroundImage!,
      );
    }

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

    if (bgImage != null) {
      paintImage(
        canvas: canvas,
        rect: Offset.zero & size,
        image: bgImage,
        fit: page.backgroundImage!.backgroundFit,
        alignment: Alignment.center,
        colorFilter: invert
            ? const ColorFilter.matrix(<double>[
                -1,
                0,
                0,
                0,
                255,
                0,
                -1,
                0,
                0,
                255,
                0,
                0,
                -1,
                0,
                255,
                0,
                0,
                0,
                1,
                0,
              ])
            : null,
      );
    }
    canvas.restore();

    canvas.save();
    if (pixelRatio != 1.0) {
      canvas.scale(pixelRatio, pixelRatio);
    }
    canvas.translate(0, size.height);
    canvas.scale(1, -1);

    for (final stroke in page.allStrokesInDrawOrder) {
      final color = stroke.color.withInversion(invert);
      final pathStr = stroke.toSvgPath();
      if (pathStr.isEmpty) continue;

      final path = parseSvgPathData(pathStr);
      final isPolygonStroke =
          stroke is! CircleStroke &&
          stroke is! RectangleStroke &&
          stroke is! ShapeStroke;
      final shapeStroke = stroke is ShapeStroke ? stroke : null;

      if (isPolygonStroke) {
        final paint = Paint()
          ..color = color
          ..style = PaintingStyle.fill
          ..isAntiAlias = true;
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
        canvas.drawPath(path, strokePaint);
      } else {
        final paint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke.options.size
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
        canvas.drawPath(path, paint);
      }
    }
    canvas.restore();

    final picture = recorder.endRecording();
    bgImage?.dispose();

    final w = (size.width * pixelRatio).round().clamp(1, 16384);
    final h = (size.height * pixelRatio).round().clamp(1, 16384);
    return picture.toImage(w, h);
  }

  /// Encodes with Skia (fast at high resolution). Prefer over [generateJpeg] when speed matters.
  static Future<Uint8List> generatePng(
    EditorCoreInfo coreInfo,
    BuildContext context, {
    required int pageIndex,
    bool invert = false,
    double pixelRatio = 2.0,
  }) async {
    final raster = await _rasterizePageForRasterExport(
      coreInfo,
      pageIndex: pageIndex,
      invert: invert,
      pixelRatio: pixelRatio,
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
    final raster = await _rasterizePageForRasterExport(
      coreInfo,
      pageIndex: pageIndex,
      invert: invert,
      pixelRatio: pixelRatio,
    );
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
      final rgba = Uint8List.fromList(
        raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
      );
      return compute(
        _encodeJpegInIsolate,
        _JpegEncodeArgs(rgba: rgba, width: w, height: h, quality: q),
      );
    } finally {
      raster.dispose();
    }
  }

  static Future<Uint8List> screenshotPage({
    required EditorCoreInfo coreInfo,
    required int pageIndex,
    required ScreenshotController screenshotController,
    required BuildContext context,
    bool invert = false,
    bool fullPage = false,
    double pixelRatio = pdfRasterPixelRatio,
  }) async {
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
      pixelRatio: pixelRatio,
      targetSize: pageSize,
      delay: fullPage ? const Duration(milliseconds: 500) : Duration.zero,
    );
  }
}
