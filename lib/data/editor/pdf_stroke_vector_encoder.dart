// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Size;

import 'package:flutter/painting.dart' show Color;
import 'package:pdf/pdf.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_shape_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/export_stroke_vectorize.dart';
import 'package:saber/data/editor/page.dart' show EditorPage;
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

/// Fast stroke → PDF vector helpers.
///
/// Avoids the old `toSvgPath()` → string → [PdfGraphics.drawShape] parse round-trip,
/// which dominated export time for dense handwriting.
abstract final class PdfStrokeVectorEncoder {
  /// Cap outline vertices per stroke so huge pressure meshes stay exportable.
  static const int maxExportPolygonPoints = 720;

  /// Binary magic for Android native overlay encoder (`SBRKOV01`).
  static const List<int> nativeOverlayMagic = [
    0x53,
    0x42,
    0x52,
    0x4B,
    0x4F,
    0x56,
    0x30,
    0x31,
  ];

  static const int flagFill = 1 << 0;
  static const int flagHighlighter = 1 << 1;
  static const int flagShapeStroked = 1 << 2;
  static const int flagScreenBlend = 1 << 3;

  /// Same Y convention as [Stroke.toSvgPath] (Flutter Y-down → PDF page Y-up).
  static double pdfY(double flutterY, double pageHeight) =>
      pageHeight - flutterY;

  /// Reduced outline for export; prefers cached [Stroke.highQualityPolygon].
  static List<Offset> exportPolygon(Stroke stroke) {
    final cached = stroke.cachedExportPolygon;
    if (cached != null) return cached;
    final raw = stroke.highQualityPolygon;
    if (raw.length <= 2) {
      stroke.cacheExportPolygon(raw);
      return raw;
    }
    final finite = <Offset>[];
    Offset? prev;
    const epsilon = 1e-4;
    for (final p in raw) {
      if (!p.dx.isFinite || !p.dy.isFinite) continue;
      if (prev != null &&
          (p.dx - prev.dx).abs() <= epsilon &&
          (p.dy - prev.dy).abs() <= epsilon) {
        continue;
      }
      finite.add(p);
      prev = p;
    }
    final result = finite.length <= maxExportPolygonPoints
        ? finite
        : _decimate(finite, maxExportPolygonPoints);
    stroke.cacheExportPolygon(result);
    return result;
  }

  /// Warm high-quality + export polygons (isolates when the note is ink-heavy).
  static Future<void> prepareExportPolygons(Iterable<EditorPage> pages) {
    return prepareExportStrokePolygons(pages);
  }

  static List<Offset> _decimate(List<Offset> pts, int maxPoints) {
    if (pts.length <= maxPoints) return pts;
    final out = <Offset>[pts.first];
    final step = (pts.length - 1) / (maxPoints - 1);
    for (var i = 1; i < maxPoints - 1; i++) {
      out.add(pts[(i * step).round().clamp(1, pts.length - 2)]);
    }
    out.add(pts.last);
    return out;
  }

  /// Draws one stroke onto [canvas] using direct path ops (no SVG).
  ///
  /// Coordinates match historical [Stroke.toSvgPath] (Y flipped by [pageHeight]).
  static void paintStroke(
    PdfGraphics canvas,
    Stroke stroke,
    bool invert, {
    required double pageHeight,
  }) {
    final color = stroke.color.withInversion(invert);
    final strokeOpacity = color.a.clamp(0.0, 1.0);
    
    final shapeStroke = stroke is ShapeStroke ? stroke : null;
    double fillOpacity = strokeOpacity;
    if (shapeStroke != null && shapeStroke.fill) {
      fillOpacity = shapeStroke.fillColor.withInversion(invert).a.clamp(0.0, 1.0);
    }

    canvas.saveContext(); // 1. Isola as propriedades desse stroke

    // 2. Define o BlendMode equivalente ao do Flutter
    PdfBlendMode blendMode = PdfBlendMode.normal;
    if (stroke.toolId == ToolId.highlighter) {
      // Screen é o equivalente no PDF para o BlendMode.plus (luz aditiva)
      blendMode = invert ? PdfBlendMode.screen : PdfBlendMode.darken;
    }

    // 3. Força a opacidade global da camada, pois o setFillColor não aceita alpha nativamente
    canvas.setGraphicState(PdfGraphicState(
      fillOpacity: fillOpacity,
      strokeOpacity: strokeOpacity,
      blendMode: blendMode,
    ));

    // 4. Setamos a cor ignorando o canal Alpha
    final pdfSolidColor = PdfColor(color.r, color.g, color.b);

    try {
      _paintStrokeBody(canvas, stroke, invert, pdfSolidColor, pageHeight);
    } finally {
      canvas.restoreContext(); // 5. Limpa a transparência/blend para o próximo stroke
    }
  }

  static void _paintStrokeBody(
    PdfGraphics canvas,
    Stroke stroke,
    bool invert,
    PdfColor pdfRgb,
    double pageHeight,
  ) {
    if (stroke is CircleStroke) {
      _paintCircle(canvas, stroke, pdfRgb, pageHeight);
      return;
    }
    if (stroke is RectangleStroke) {
      _paintRectangle(canvas, stroke, pdfRgb, pageHeight);
      return;
    }

    final shapeStroke = stroke is ShapeStroke ? stroke : null;
    final isPolygonStroke = shapeStroke == null;

    if (isPolygonStroke) {
      final poly = exportPolygon(stroke);
      if (poly.length < 2) return;
      canvas.setFillColor(pdfRgb);
      _appendPolygon(canvas, poly, pageHeight);
      canvas.fillPath();
      return;
    }

    final pathStr = stroke.toSvgPath();
    if (pathStr.isEmpty) return;
    if (shapeStroke.fill) {
      final fillC = shapeStroke.fillColor.withInversion(invert);
      canvas.setFillColor(PdfColor(fillC.r, fillC.g, fillC.b));
      canvas.drawShape(pathStr);
      canvas.fillPath();
    }
    canvas.setStrokeColor(pdfRgb);
    canvas.setLineWidth(stroke.options.size);
    canvas.setLineCap(PdfLineCap.round);
    canvas.setLineJoin(PdfLineJoin.round);
    canvas.drawShape(pathStr);
    canvas.strokePath();
  }

  static void _paintCircle(
    PdfGraphics canvas,
    CircleStroke stroke,
    PdfColor color,
    double pageHeight,
  ) {
    // Match legacy CircleStroke.toSvgPath (no Y flip on center).
    final c = stroke.center;
    final r = stroke.radius;
    canvas.setStrokeColor(color);
    canvas.setLineWidth(stroke.options.size);
    canvas.drawEllipse(c.dx - r, c.dy - r, r * 2, r * 2);
    canvas.strokePath();
  }

  static void _paintRectangle(
    PdfGraphics canvas,
    RectangleStroke stroke,
    PdfColor color,
    double pageHeight,
  ) {
    // Match legacy RectangleStroke.toSvgPath (Flutter coords, no Y flip).
    final rect = stroke.rect;
    canvas.setStrokeColor(color);
    canvas.setLineWidth(stroke.options.size);
    canvas.drawRect(rect.left, rect.top, rect.width, rect.height);
    canvas.strokePath();
  }

  static void _appendPolygon(
    PdfGraphics canvas,
    List<Offset> poly,
    double pageHeight,
  ) {
    final first = poly.first;
    canvas.moveTo(first.dx, pdfY(first.dy, pageHeight));
    for (var i = 1; i < poly.length; i++) {
      final p = poly[i];
      canvas.lineTo(p.dx, pdfY(p.dy, pageHeight));
    }
    canvas.closePath();
  }

  /// Paints all strokes on [page] (same semantics as historical exporter).
  static void paintPageStrokes(
    PdfGraphics canvas,
    EditorPage page,
    bool invert,
  ) {
    final pageHeight = page.size.height;
    for (final stroke in page.allStrokesInDrawOrder) {
      paintStroke(
        canvas,
        stroke,
        invert,
        pageHeight: pageHeight,
      );
    }
  }

  /// Low-level multi-page transparent overlay PDF (no widget tree).
  static Future<Uint8List> encodeOverlayPdf({
    required List<EditorPage> pages,
    required bool invert,
    required Size Function(EditorPage page) exportSizeOf,
    required ({double tx, double ty, double sx, double sy}) Function(
      EditorPage page,
    )
    strokeBasisOf,
  }) async {
    final doc = PdfDocument();
    for (final page in pages) {
      final basis = strokeBasisOf(page);
      final exportSize = exportSizeOf(page);
      final pdfPage = PdfPage(
        doc,
        pageFormat: PdfPageFormat(
          exportSize.width,
          exportSize.height,
          marginAll: 0,
        ),
      );
      final g = pdfPage.getGraphics();
      final trans = Matrix4.translationValues(-basis.tx, -basis.ty, 0);
      final scaleM = Matrix4.diagonal3Values(basis.sx, basis.sy, 1);
      final flipY = Matrix4.translationValues(0, exportSize.height, 0)
        ..multiply(Matrix4.diagonal3Values(1, -1, 1));
      final ctm = flipY.clone()
        ..multiply(scaleM)
        ..multiply(trans);
      g.saveContext();
      g.setTransform(ctm);
      paintPageStrokes(g, page, invert);
      g.restoreContext();
    }
    final bytes = await doc.save();
    return bytes;
  }

  /// Packed stroke geometry for Android PDFBox overlay writer.
  ///
  /// Points use the same Y-flipped space as [paintStroke]; native applies the
  /// Dart overlay CTM (`flipY * scale * translate`).
  static Uint8List packNativeOverlayBlob({
    required List<EditorPage> pages,
    required bool invert,
    required Size Function(EditorPage page) exportSizeOf,
    required ({double tx, double ty, double sx, double sy}) Function(
      EditorPage page,
    )
    strokeBasisOf,
  }) {
    final out = BytesBuilder(copy: false);
    out.add(nativeOverlayMagic);
    final header = ByteData(4)..setUint32(0, pages.length, Endian.little);
    out.add(header.buffer.asUint8List());

    for (final page in pages) {
      final exportSize = exportSizeOf(page);
      final basis = strokeBasisOf(page);
      final pageHeader = ByteData(4 * 6);
      pageHeader.setFloat32(0, exportSize.width, Endian.little);
      pageHeader.setFloat32(4, exportSize.height, Endian.little);
      pageHeader.setFloat32(8, basis.tx, Endian.little);
      pageHeader.setFloat32(12, basis.ty, Endian.little);
      pageHeader.setFloat32(16, basis.sx, Endian.little);
      pageHeader.setFloat32(20, basis.sy, Endian.little);
      out.add(pageHeader.buffer.asUint8List());

      final strokes = page.allStrokesInDrawOrder;
      // Only pack filled outline strokes (the slow path). Shapes stay on Dart.
      final packed = <Stroke>[];
      for (final s in strokes) {
        if (s is CircleStroke || s is RectangleStroke || s is ShapeStroke) {
          continue;
        }
        packed.add(s);
      }
      final countBuf = ByteData(4)..setUint32(0, packed.length, Endian.little);
      out.add(countBuf.buffer.asUint8List());

      for (final stroke in packed) {
        final color = stroke.color.withInversion(invert);
        var flags = flagFill;
        if (stroke.toolId == ToolId.highlighter) {
          flags |= flagHighlighter;
          if (invert) flags |= flagScreenBlend;
        }
        final poly = exportPolygon(stroke);
        final strokeHeader = ByteData(4 + 4 + 4 + 4);
        strokeHeader.setUint32(0, flags, Endian.little);
        strokeHeader.setUint32(4, _colorToArgb(color), Endian.little);
        strokeHeader.setFloat32(8, color.a.clamp(0.0, 1.0), Endian.little);
        strokeHeader.setUint32(12, poly.length, Endian.little);
        out.add(strokeHeader.buffer.asUint8List());
        if (poly.isEmpty) continue;
        // Store the same Y-flipped coords [paintStroke] uses; native applies the
        // same flipY×scale×translate CTM as the Dart overlay encoder.
        final pageHeight = page.size.height;
        final pts = Float32List(poly.length * 2);
        for (var i = 0; i < poly.length; i++) {
          pts[i * 2] = poly[i].dx;
          pts[i * 2 + 1] = pdfY(poly[i].dy, pageHeight);
        }
        out.add(pts.buffer.asUint8List());
      }
    }
    return out.toBytes();
  }

  static int _colorToArgb(Color c) {
    final a = (c.a * 255.0).round().clamp(0, 255);
    final r = (c.r * 255.0).round().clamp(0, 255);
    final g = (c.g * 255.0).round().clamp(0, 255);
    final b = (c.b * 255.0).round().clamp(0, 255);
    return (a << 24) | (r << 16) | (g << 8) | b;
  }

  /// True when every stroke on [pages] can be packed for the native encoder
  /// (no circles/rects/shapes that still need SVG/path special-cases).
  static bool pagesAreNativeEncodable(List<EditorPage> pages) {
    for (final page in pages) {
      for (final s in page.allStrokesInDrawOrder) {
        if (s is CircleStroke || s is RectangleStroke || s is ShapeStroke) {
          return false;
        }
      }
    }
    return true;
  }

  static int estimatePointCount(List<EditorPage> pages) {
    var n = 0;
    for (final page in pages) {
      for (final s in page.allStrokesInDrawOrder) {
        if (s is CircleStroke || s is RectangleStroke || s is ShapeStroke) {
          continue;
        }
        final cached = s.cachedExportPolygon;
        if (cached != null) {
          n += cached.length;
          continue;
        }
        if (s.hasCachedHighQualityPolygon) {
          n += math.min(s.highQualityPolygon.length, maxExportPolygonPoints);
          continue;
        }
        n += math.min(s.sampleCount * 2, maxExportPolygonPoints);
      }
    }
    return n;
  }
}
