// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:saber/components/canvas/_canvas_background_painter.dart';
import 'package:saber/components/canvas/_canvas_painter.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/editor/canvas_background_pattern.dart';
import 'package:saber/data/editor/page.dart';

/// Thrown when a page cannot be rasterized for VLM transcription.
class VlmPageRenderException implements Exception {
  VlmPageRenderException(this.message);

  final String message;

  @override
  String toString() => 'VlmPageRenderException: $message';
}

/// Renders an [EditorPage] (or a cropped region of it) to PNG bytes using
/// the same painters as the live canvas: background, PDF, embedded images,
/// committed ink and quill text. [crop] (page coordinates) restricts
/// rendering to a region, e.g. a text selection. Output is bounded by
/// [maxLongEdge] to cap model token usage.
/// With [blankBackground] (the default for model input), ruled/grid/dot
/// pattern lines are stripped — models consistently misread them as
/// content — while ink, images and quill text render unchanged.
final class PageImageRenderer {
  const PageImageRenderer._();

  /// Longest output edge in pixels. 1280 keeps handwriting legible for the
  /// vision encoder while bounding prefill cost on CPU (image tokens scale
  /// with resolution, and prefill dominates wall-clock time there).
  static const double maxLongEdge = 1280;

  /// Output dimensions for [src] bounded by [maxLongEdge], as (width, height).
  @visibleForTesting
  static (int, int) outputSizeFor(Rect src, double maxLongEdge) {
    final scale = (maxLongEdge / math.max(src.width, src.height)).clamp(
      0.2,
      3.0,
    );
    return (
      math.max(1, (src.width * scale).round()),
      math.max(1, (src.height * scale).round()),
    );
  }

  static Future<Uint8List> renderPagePng({
    required EditorPage page,
    required int pageIndex,
    required int totalPages,
    required bool invert,
    required Color backgroundColor,
    required CanvasBackgroundPattern backgroundPattern,
    required int lineHeight,
    required double lineThickness,
    required Color primaryColor,
    required Color secondaryColor,
    Rect? crop,
    double maxLongEdge = PageImageRenderer.maxLongEdge,
    bool blankBackground = true,
  }) async {
    final full = Offset.zero & page.size;
    final src = (crop == null ? full : crop.intersect(full));
    if (src.isEmpty || !src.isFinite) {
      throw VlmPageRenderException('empty render region');
    }
    final (w, h) = outputSizeFor(src, maxLongEdge);
    final picture = await recordPagePicture(
      page: page,
      pageIndex: pageIndex,
      totalPages: totalPages,
      invert: invert,
      backgroundColor: backgroundColor,
      backgroundPattern: backgroundPattern,
      lineHeight: lineHeight,
      lineThickness: lineThickness,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
      src: src,
      outputWidth: w,
      outputHeight: h,
      blankBackground: blankBackground,
    );
    try {
      final image = await _rasterizeSyncFirst(picture, w, h);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final png = bytes?.buffer.asUint8List();
        if (png == null || png.isEmpty) {
          throw VlmPageRenderException('PNG encoding produced no bytes');
        }
        return Uint8List.fromList(png);
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  /// Records the page (or [src] region) mapped 1:1 onto an
  /// [outputWidth]x[outputHeight] picture. Fully synchronous, so it runs
  /// identically on-device and headless. The caller rasterizes/encodes.
  static Future<ui.Picture> recordPagePicture({
    required EditorPage page,
    required int pageIndex,
    required int totalPages,
    required bool invert,
    required Color backgroundColor,
    required CanvasBackgroundPattern backgroundPattern,
    required int lineHeight,
    required double lineThickness,
    required Color primaryColor,
    required Color secondaryColor,
    required Rect src,
    required int outputWidth,
    required int outputHeight,
    bool blankBackground = true,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
    );
    final w = outputWidth;
    final h = outputHeight;
    canvas.save();
    canvas.scale(w / src.width, h / src.height);
    canvas.translate(-src.left, -src.top);
    canvas.clipRect(src);

    try {
      CanvasBackgroundPainter(
        invert: invert,
        backgroundColor: page.backgroundImage != null
            ? Colors.white
            : (page.backgroundColor.toARGB32() != 0xFFFFFFFF
                  ? page.backgroundColor
                  : backgroundColor),
        backgroundPattern: (page.backgroundImage != null || blankBackground)
            ? CanvasBackgroundPattern.none
            : (page.backgroundPattern ?? backgroundPattern),
        lineHeight: page.hasLocalLineHeight ? page.lineHeight : lineHeight,
        lineThickness: page.hasLocalLineThickness
            ? page.lineThickness.toInt()
            : lineThickness.toInt(),
        primaryColor: page.lineColor.toARGB32() != 0xFF9E9E9E
            ? page.lineColor
            : primaryColor,
        secondaryColor: secondaryColor,
        preview: true,
        marginLeft: page.marginLeft,
        marginRight: page.marginRight,
        marginTop: page.marginTop,
        marginBottom: page.marginBottom,
        borderColor:
            page.hasLocalBorderColor ||
                (page.marginLeft > 0 ||
                    page.marginRight > 0 ||
                    page.marginTop > 0 ||
                    page.marginBottom > 0)
            ? page.borderColor
            : null,
      ).paint(canvas, page.size);

      await _paintPdfBackground(canvas, page, w / src.width);
      await _paintEmbeddedImages(canvas, page);
      _paintStrokes(
        canvas,
        page: page,
        pageIndex: pageIndex,
        totalPages: totalPages,
        invert: invert,
        primaryColor: primaryColor,
      );
      _paintQuillText(canvas, page: page, invert: invert);
    } finally {
      canvas.restore();
    }

    return recorder.endRecording();
  }

  /// Rasterizes [picture], preferring the synchronous path (same as the tile
  /// cache): it works identically on-device and headless, where async
  /// toImage can stall waiting for a rasterizer that never runs.
  static Future<ui.Image> _rasterizeSyncFirst(
    ui.Picture picture,
    int w,
    int h,
  ) {
    try {
      return Future.value(picture.toImageSync(w, h));
    } catch (_) {
      return picture.toImage(w, h);
    }
  }

  static void _paintStrokes(
    Canvas canvas, {
    required EditorPage page,
    required int pageIndex,
    required int totalPages,
    required bool invert,
    required Color primaryColor,
  }) {
    final strokes = page.allStrokesInDrawOrder.toList(growable: false);
    if (strokes.isEmpty) return;
    CanvasPainter(
      invert: invert,
      strokes: strokes,
      laserStrokes: const [],
      currentStroke: null,
      currentSelection: null,
      primaryColor: primaryColor,
      page: page,
      showPageIndicator: false,
      pageIndex: pageIndex,
      totalPages: totalPages,
      currentScale: 1.0,
      defaultTextStyle: const TextStyle(),
      doneSelecting: true,
    ).paint(canvas, page.size);
  }

  /// Best-effort PDF backdrop (only when its document is already open;
  /// otherwise ink-only output, which is still transcribable).
  static Future<void> _paintPdfBackground(
    Canvas canvas,
    EditorPage page,
    double pixelRatio,
  ) async {
    final bg = page.backgroundImage;
    if (bg is! PdfEditorImage) return;
    try {
      final document = bg.assetCacheAll.getPdfNotifier(bg.assetId).value;
      if (document == null) return;
      if (bg.pdfPage < 0 || bg.pdfPage >= document.pages.length) return;
      final pdfPage = document.pages[bg.pdfPage];
      final dst = bg.dstRect;
      final rendered = await pdfPage
          .render(
            fullWidth: math.max(1, dst.width * pixelRatio),
            fullHeight: math.max(1, dst.height * pixelRatio),
            backgroundColor: Colors.white.toARGB32(),
          )
          .timeout(const Duration(seconds: 20));
      if (rendered == null) return;
      final image = await rendered.createImage();
      try {
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(
            0,
            0,
            image.width.toDouble(),
            image.height.toDouble(),
          ),
          dst,
          Paint()..filterQuality = FilterQuality.medium,
        );
      } finally {
        image.dispose();
      }
    } catch (_) {
      // Ink-only render remains useful; never fail transcription for this.
    }
  }

  /// Best-effort embedded rasters (PNG snapshots). Anything undecodable is
  /// skipped; strokes carry the transcription either way.
  static Future<void> _paintEmbeddedImages(
    Canvas canvas,
    EditorPage page,
  ) async {
    for (final image in page.allImagesInDrawOrder) {
      if (image is! PngEditorImage) continue;
      try {
        final ui.Image? decoded = await _decodePng(image).timeout(
          const Duration(seconds: 10),
        );
        if (decoded == null) continue;
        try {
          canvas.save();
          final center = image.dstRect.center;
          canvas.translate(center.dx, center.dy);
          canvas.rotate(image.rotationDeg * math.pi / 180);
          canvas.translate(-center.dx, -center.dy);
          canvas.drawImageRect(
            decoded,
            Rect.fromLTWH(
              0,
              0,
              decoded.width.toDouble(),
              decoded.height.toDouble(),
            ),
            image.dstRect,
            Paint()..filterQuality = FilterQuality.medium,
          );
          canvas.restore();
        } finally {
          decoded.dispose();
        }
      } catch (_) {
        // Skip undecodable images; keep transcribing the ink.
      }
    }
  }

  static Future<ui.Image?> _decodePng(PngEditorImage image) async {
    try {
      // Vault-aware bytes first; the in-memory provider is a fast path.
      final provider = image.imageProvider;
      Uint8List bytes;
      if (provider is MemoryImage && provider.bytes.isNotEmpty) {
        bytes = provider.bytes;
      } else {
        final raw = await image.assetCacheAll.getBytes(image.assetId);
        if (raw.isEmpty) return null;
        bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
      }
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  /// Quill text has no vector strokes; paint its plain content so the VLM
  /// reads typed paragraphs too.
  static void _paintQuillText(
    Canvas canvas, {
    required EditorPage page,
    required bool invert,
  }) {
    final plain = page.quill.controller.document.toPlainText().trim();
    if (plain.isEmpty) return;
    final painter = TextPainter(
      text: TextSpan(
        text: plain,
        style: TextStyle(
          color: invert ? const Color(0xFFF2F2F2) : const Color(0xFF1A1A1A),
          fontSize: 28,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 256,
    );
    painter.layout(maxWidth: math.max(100, page.size.width - 80));
    painter.paint(canvas, const Offset(40, 40));
  }
}
