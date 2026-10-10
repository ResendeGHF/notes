// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';
import 'dart:ui' show Rect;

/// One entry from `media/mediaInfo.dat`.
class SdocxMediaEntry {
  SdocxMediaEntry({
    required this.bindId,
    required this.fileName,
    this.bytes,
  });

  final int bindId;
  final String fileName;
  Uint8List? bytes;

  bool get isImage {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }

  bool get isPdf => fileName.toLowerCase().endsWith('.pdf');

  /// Audio, sticker sub-notes (.sdocx), .spi painting data, etc.
  /// These are intentionally ignored on import (see requirements).
  bool get isSkipped =>
      !isImage && !isPdf;
}

/// A decoded pen stroke in Samsung page coordinates.
class SdocxStroke {
  SdocxStroke({
    required this.points,
    required this.pressures,
    this.colorArgb,
    required this.penWidth,
    required this.bbox,
  });

  /// Absolute page coordinates (same space as [bbox] and page size).
  final List<SdocxPoint> points;
  final List<double> pressures;
  final int? colorArgb;
  final double penWidth;
  final Rect bbox;
}

class SdocxPoint {
  SdocxPoint(this.x, this.y);

  final double x;
  final double y;
}

/// A placed raster image in Samsung page coordinates.
class SdocxImage {
  SdocxImage({
    required this.bbox,
    required this.mediaId,
    this.rotationDegrees,
  });

  final Rect bbox;
  final int? mediaId;
  final double? rotationDegrees;
}

/// PDF-backed paper: a Samsung page showing one page of a PDF asset.
class SdocxPdfPaper {
  SdocxPdfPaper({
    required this.mediaId,
    required this.pageIndex,
    required this.rect,
  });

  final int mediaId;
  final int pageIndex;
  final Rect rect;
}

/// One parsed `.page` record.
class SdocxPage {
  SdocxPage({
    required this.uuid,
    required this.width,
    required this.height,
    this.backgroundColorArgb,
    this.pdfPapers = const [],
    this.strokes = const [],
    this.images = const [],
  });

  final String uuid;
  final double width;
  final double height;
  final int? backgroundColorArgb;
  final List<SdocxPdfPaper> pdfPapers;
  final List<SdocxStroke> strokes;
  final List<SdocxImage> images;

  bool get isEmpty => strokes.isEmpty && images.isEmpty && pdfPapers.isEmpty;
}

/// Whole document in Samsung page order (`pageIdInfo.dat`).
class SdocxDocument {
  SdocxDocument({
    required this.pages,
    required this.mediaByBindId,
    required this.mediaByFileName,
    this.title,
  });

  final List<SdocxPage> pages;
  final Map<int, SdocxMediaEntry> mediaByBindId;
  final Map<String, SdocxMediaEntry> mediaByFileName;
  final String? title;
}
