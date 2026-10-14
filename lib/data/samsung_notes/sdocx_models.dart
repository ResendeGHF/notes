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
    this.penName,
    this.penNameId,
    this.advancedSettingId,
    this.toolTypeRaw,
  });

  /// Absolute page coordinates (same space as [bbox] and page size).
  final List<SdocxPoint> points;
  final List<double> pressures;
  final int? colorArgb;
  final double penWidth;
  final Rect bbox;

  /// Resolved Samsung pen name with the preload package prefix stripped
  /// (e.g. `InkPen2`, `FountainPen`, `Marker4`, `Pencil2`). Null when the
  /// stroke carries no resolvable pen id (unknown format version).
  final String? penName;

  /// Raw style ids from the stroke frame (for debugging/future mapping).
  final int? penNameId;
  final int? advancedSettingId;

  /// Raw tool/input type from the stroke channel data (1..3 normally means
  /// finger/stylus variants, *not* the pen type; kept for debugging).
  final int? toolTypeRaw;
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
    this.templateUri,
    this.templateType,
    this.backgroundImageId,
    this.backgroundImageMode,
    this.backgroundWidth,
    this.backgroundRotation,
  });

  final String uuid;
  final double width;
  final double height;
  final int? backgroundColorArgb;
  final List<SdocxPdfPaper> pdfPapers;
  final List<SdocxStroke> strokes;
  final List<SdocxImage> images;

  /// Built-in page-template backing (bit 2): e.g. a URI naming the
  /// ruled/grid/dotted stock template. Null when absent.
  final String? templateUri;

  /// Built-in page-template id (bit 9): 1..3 ruled, 4..6 grid, 7..9 dots,
  /// 0/absent means blank. Other ids are retained but map to blank.
  final int? templateType;

  /// Stock background artwork reference (bits 3/4): media bind id of an
  /// embedded pattern image plus its mode. Null when absent.
  final int? backgroundImageId;
  final int? backgroundImageMode;
  final int? backgroundWidth;
  final int? backgroundRotation;

  bool get isEmpty => strokes.isEmpty && images.isEmpty && pdfPapers.isEmpty;
}

/// Whole document in Samsung page order (`pageIdInfo.dat`).
class SdocxDocument {
  SdocxDocument({
    required this.pages,
    required this.mediaByBindId,
    required this.mediaByFileName,
    this.title,
    this.stringTable = const {},
    this.defaultTemplateUri,
  });

  final List<SdocxPage> pages;
  final Map<int, SdocxMediaEntry> mediaByBindId;
  final Map<String, SdocxMediaEntry> mediaByFileName;
  final String? title;

  /// `note.note` string table (id -> text): resolves stroke pen names
  /// (`pen_name_id`) and advanced pen settings. Empty when unavailable.
  final Map<int, String> stringTable;

  /// Note-level default page-template URI (`note.note` bit 6), used when a
  /// page carries no template of its own.
  final String? defaultTemplateUri;
}
