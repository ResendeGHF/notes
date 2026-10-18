// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// DjVu → PDF conversion.
//
// Produces a PDF 1.4 file that reuses the app's PDF pipeline (pdfrx rendering,
// outline navigation, link handling) instead of a bespoke renderer:
//
// - bilevel-only pages embed their JB2 mask as a Flate ImageMask stencil;
// - mixed pages embed their IW44 (or `BGjp`) background layer at its native
//   resolution and repaint the foreground on top:
//     * `FGbz` palette pages get one cropped 1-bit stencil per colour used,
//       painted in that colour;
//     * continuous-tone foregrounds (`FG44`/`FGjp`) whose colour under the mask
//       is near-uniform get a single flat stencil in that colour (crisp,
//       small);
//     * multi-colour continuous foregrounds embed the foreground image itself
//       with a `/Mask` referencing the page mask, so colours and native
//       resolution are preserved without rasterizing a page-sized composite;
// - the INFO rotation becomes the page's `/Rotate`;
// - NAVM bookmarks become the PDF outline and ANTz map areas become link
//   annotations; internal `#page_N` targets are emitted as PDF internal
//   destinations (not URIs), so preview navigation works in pdfrx.
//
// The reference converter (djvu-rs `src/pdf/`) renders a composited RGB raster
// for every non-bilevel page; embedding the layers directly keeps the output
// smaller and the text crisper, at the cost of a composited-raster fallback
// for the rare cases above that the stencil policy cannot express (which we
// avoid with the `/Mask` foreground image instead).
//
// Streaming: object bodies are written to a [PdfByteSink] as they are
// produced, so peak memory is O(1 page) plus the xref bookkeeping.

import 'dart:typed_data';

import 'package:saber/data/document_conversion/djvu/djvu_annotations.dart';
import 'package:saber/data/document_conversion/djvu/djvu_bitmap.dart';
import 'package:saber/data/document_conversion/djvu/djvu_bzz.dart';
import 'package:saber/data/document_conversion/djvu/djvu_document.dart';
import 'package:saber/data/document_conversion/djvu/djvu_fgbz.dart';
import 'package:saber/data/document_conversion/djvu/djvu_iff.dart';
import 'package:saber/data/document_conversion/djvu/djvu_iw44.dart';
import 'package:saber/data/document_conversion/djvu/djvu_jb2.dart';
import 'package:saber/data/document_conversion/djvu/djvu_navm.dart';
import 'package:saber/data/document_conversion/djvu/djvu_pdf_writer.dart';
import 'package:saber/data/document_conversion/scan_orientation.dart';

/// Options for DjVu → PDF conversion.
class DjvuPdfOptions {
  const DjvuPdfOptions({
    this.jpegQuality = kDefaultJpegQuality,
    this.autoOrientScans = true,
  });

  /// JPEG quality for raster layers, or null to force lossless FlateDecode
  /// everywhere. The adaptive policy in [makeRgbImageBody] decides per image
  /// whether a JPEG candidate is worth trying at all.
  final int? jpegQuality;

  /// Whether the INFO rotation tag may be overridden from the page pixels.
  ///
  /// Many DjVu scans carry a wrong tag: the raster is stored upright (text
  /// already horizontal) while the tag still asks viewers to turn the page,
  /// which shows the whole book sideways. When this is enabled, each page is
  /// scored (see `scan_orientation.dart`) and the tag is corrected when the
  /// pixels clearly disagree with it. Pages with no clear verdict keep their
  /// tag untouched.
  final bool autoOrientScans;
}

/// The PDF bytes and outline of a converted DjVu document.
class DjvuConversionResult {
  DjvuConversionResult({
    required this.pdf,
    required this.bookmarks,
    required this.pageCount,
  });

  /// The complete PDF file.
  final Uint8List pdf;

  /// The document's NAVM bookmarks, for the app's outline navigation.
  final List<DjvuBookmark> bookmarks;

  /// Number of pages in the document.
  final int pageCount;
}

/// Converts a DjVu file into a PDF document.
///
/// [resolver] is required for indirect `FORM:DJVM` catalogs (component files
/// referenced by name instead of bundled).
DjvuConversionResult convertDjvuToPdf(
  Uint8List data, {
  DjvuComponentResolver? resolver,
  DjvuPdfOptions options = const DjvuPdfOptions(),
}) =>
    convertDjvuDocumentToPdf(
      DjvuDocument.parse(data, resolver: resolver),
      options: options,
    );

/// Converts an already-parsed [document] into PDF bytes.
DjvuConversionResult convertDjvuDocumentToPdf(
  DjvuDocument document, {
  DjvuPdfOptions options = const DjvuPdfOptions(),
}) {
  final sink = BytesBuilder(copy: false);
  final bookmarks = writeDjvuPdf(document, sink.add, options: options);
  return DjvuConversionResult(
    pdf: sink.takeBytes(),
    bookmarks: bookmarks,
    pageCount: document.pageCount,
  );
}

/// Streams [document] as a PDF 1.4 file into [sink].
///
/// Returns the document's bookmarks (also emitted as the PDF outline).
/// Throws [DjvuFormatException] for a document without pages.
List<DjvuBookmark> writeDjvuPdf(
  DjvuDocument document,
  PdfByteSink sink, {
  DjvuPdfOptions options = const DjvuPdfOptions(),
}) {
  if (document.pageCount == 0) {
    throw const DjvuDocumentException('document has no pages');
  }

  final writer = DjvuPdfWriter(sink);

  // The catalog is object 1 by convention (the writer's default root id);
  // page object ids are reserved up front so link and outline destinations
  // can reference them before the pages themselves are emitted.
  final catalogId = writer.reserveId();
  final pagesId = writer.reserveId();
  final pageIds = [
    for (var i = 0; i < document.pageCount; i++) writer.reserveId(),
  ];

  for (var i = 0; i < document.pageCount; i++) {
    final rendered = _renderPage(
      document.page(i),
      document.pageCount,
      options,
    );
    _emitPage(writer, pageIds[i], pagesId, pageIds, rendered, options);
  }

  final outlineId = _buildOutline(writer, document.bookmarks, pageIds);

  final kids = [for (final id in pageIds) '$id 0 R'].join(' ');
  writer.writeObject(
    pagesId,
    _ascii('<< /Type /Pages /Kids [$kids] /Count ${pageIds.length} >>'),
  );
  final outlineRef = outlineId == null
      ? ''
      : ' /Outlines $outlineId 0 R /PageMode /UseOutlines';
  writer.writeObject(
    catalogId,
    _ascii('<< /Type /Catalog /Pages $pagesId 0 R$outlineRef >>'),
  );
  writer.finish(rootId: catalogId);
  return document.bookmarks;
}

/// Above this many colours actually used by the mask, the per-colour stencil
/// planes are replaced by a single black stencil.
///
/// Real `FGbz` palettes are small (a handful of ink colours); a mask using
/// hundreds of colours is photo-like content mis-encoded as a palette, where
/// one stencil per colour would explode the object count.
const _maxPaletteLayers = 256;

/// Total pixel area of all per-colour stencil planes above which the stencil
/// policy is abandoned for the plain black stencil.
///
/// Each plane is a cropped bitmap whose bounding box can cover the whole page;
/// this bounds the transient allocation (planes hold one bit per pixel).
const _maxStencilPlanePixels = 256 * 1024 * 1024;

/// Per-channel spread (max−min) of the continuous foreground colour under the
/// mask above which the foreground counts as multi-coloured and the flat
/// stencil is skipped.
const _fgUniformSpread = 48;

/// One page rendered into pre-encoded XObjects and link targets.
class _RenderedPage {
  _RenderedPage({
    required this.ptW,
    required this.ptH,
    required this.rotate,
    required this.img0,
    required this.img0IsMask,
    required this.maskedForeground,
    required this.layers,
    required this.links,
  });

  /// Page width in PDF points (native orientation).
  final double ptW;

  /// Page height in PDF points (native orientation).
  final double ptH;

  /// Clockwise `/Rotate` angle for the INFO rotation.
  final int rotate;

  /// The background XObject body: a bilevel mask, a colour raster, a `BGjp`
  /// passthrough JPEG, or null for a blank page.
  final Uint8List? img0;

  /// Whether [img0] is an ImageMask painted in the current fill colour.
  final bool img0IsMask;

  /// A continuous-tone foreground image restricted by the page mask (multi
  /// colour `FG44`/`FGjp` pages), or null.
  final _MaskedImage? maskedForeground;

  /// Per-colour foreground stencils, painted in order.
  final List<_MaskLayer> layers;

  /// Link targets (`#page_N` destinations or external URIs).
  final List<_LinkTarget> links;
}

/// One foreground stencil layer: an ImageMask XObject body painted in `rgb`.
///
/// `(x0, y0)` is the layer's pixel bounding box within the full mask of
/// `maskW x maskH` pixels; the content stream scales and translates each
/// stencil back into place.
class _MaskLayer {
  _MaskLayer({
    required this.r,
    required this.g,
    required this.b,
    required this.x0,
    required this.y0,
    required this.bw,
    required this.bh,
    required this.maskW,
    required this.maskH,
    required this.body,
  });

  final int r;
  final int g;
  final int b;
  final int x0;
  final int y0;
  final int bw;
  final int bh;
  final int maskW;
  final int maskH;
  final Uint8List body;
}

/// A foreground image painted through the page mask (`/Mask` entry).
///
/// Exactly one of [rgb] (packed RGB) and [jpeg] (unchanged JPEG bytes) is set.
class _MaskedImage {
  _MaskedImage.rgb({
    required Uint8List this.rgb,
    required this.width,
    required this.height,
    required this.mask,
  }) : jpeg = null,
       jpegChannels = 0;

  _MaskedImage.jpeg({
    required Uint8List this.jpeg,
    required this.jpegChannels,
    required this.width,
    required this.height,
    required this.mask,
  }) : rgb = null;

  final Uint8List? rgb;
  final Uint8List? jpeg;
  final int jpegChannels;
  final int width;
  final int height;
  final DjvuBitmap mask;
}

/// A link annotation target.
class _LinkTarget {
  _LinkTarget.dest({
    required this.pageIndex,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  }) : url = null;

  _LinkTarget.uri({
    required String this.url,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  }) : pageIndex = -1;

  /// 0-based destination page for internal links, else -1.
  final int pageIndex;

  /// External URL, or null for internal links.
  final String? url;

  final double x1;
  final double y1;
  final double x2;
  final double y2;
}

/// Renders one page into its XObjects and link targets.
_RenderedPage _renderPage(
  DjvuPage page,
  int pageCount,
  DjvuPdfOptions options,
) {
  final pw = page.width;
  final ph = page.height;
  final dpi = page.dpi.toDouble();
  final ptW = pw * 72.0 / dpi;
  final ptH = ph * 72.0 / dpi;

  final hasMask = page.rawChunk('Sjbz') != null;
  final bgChunks = page.bg44Chunks();
  final bgjp = page.rawChunk('BGjp');
  final hasBackground = bgChunks.isNotEmpty || (bgjp != null && bgjp.isNotEmpty);

  Uint8List? img0;
  var img0IsMask = false;
  _MaskedImage? maskedForeground;
  var layers = const <_MaskLayer>[];
  var orientation = ScanOrientation.unknown;

  if (hasMask && !hasBackground) {
    // Bilevel fast path: the page is its mask, painted black.
    final mask = _tryMask(page);
    if (mask != null) {
      if (options.autoOrientScans) {
        orientation = scoreScanOrientation(_maskGrid(mask));
      }
      img0 = makeMaskBody(mask);
      img0IsMask = true;
    }
  } else {
    // Background layer at its native resolution; the page `cm` scales it to
    // the MediaBox, so subsampled backgrounds stay subsampled.
    if (bgChunks.isNotEmpty) {
      final background = page.decodeBackground()!;
      if (background.isColor) {
        final rgb = background.toRgb();
        if (options.autoOrientScans) {
          orientation = scoreScanOrientation(_rgbaGrid(rgb));
        }
        img0 = makeRgbImageBody(
          rgb.toRgbBytes(),
          rgb.width,
          rgb.height,
          jpegQuality: options.jpegQuality,
        );
      } else {
        final gray = background.toGray8();
        if (options.autoOrientScans) {
          orientation = scoreScanOrientation(_grayGrid(gray));
        }
        img0 = makeGrayImageBody(
          gray.data,
          gray.width,
          gray.height,
          jpegQuality: options.jpegQuality,
        );
      }
    } else if (bgjp != null && bgjp.isNotEmpty) {
      img0 = _bgjpBody(bgjp, options);
    }

    if (hasMask) {
      final palette = _usablePalette(page);
      if (palette != null) {
        layers = _paletteLayers(page, palette);
      } else {
        final outcome = _continuousForegroundLayers(page);
        layers = outcome.layers;
        maskedForeground = outcome.masked;
      }
    }
  }

  return _RenderedPage(
    ptW: ptW,
    ptH: ptH,
    rotate: djvuDisplayRotation(
      orientation,
      _pdfRotate(page.rotation),
      autoOrient: options.autoOrientScans,
    ),
    img0: img0,
    img0IsMask: img0IsMask,
    maskedForeground: maskedForeground,
    layers: layers,
    links: _pageLinks(page, dpi, pageCount),
  );
}

/// The PDF `/Rotate` angle (clockwise degrees) for an INFO rotation.
int _pdfRotate(DjvuRotation rotation) => switch (rotation) {
  DjvuRotation.none => 0,
  DjvuRotation.cw90 => 90,
  DjvuRotation.rot180 => 180,
  DjvuRotation.ccw90 => 270,
};

/// The PDF `/Rotate` angle to display a page whose raw raster reads as
/// [orientation] and whose INFO tag maps to [tag].
///
/// A confidently sideways raster always wins: no tag makes vertical text read
/// horizontally except the 90/270 turn the scorer reports. An upright raster
/// only overrides tags that would show it sideways (90/270) — those are the
/// bogus ones real scans carry; a `180` tag is kept because pixels cannot tell
/// a page from its 180° twin.
int djvuDisplayRotation(
  ScanOrientation orientation,
  int tag, {
  required bool autoOrient,
}) {
  if (!autoOrient) return tag;
  switch (orientation) {
    case ScanOrientation.upright:
      return (tag == 90 || tag == 270) ? 0 : tag;
    case ScanOrientation.rotateClockwise:
      return 90;
    case ScanOrientation.rotateCounterClockwise:
      return 270;
    case ScanOrientation.unknown:
      return tag;
  }
}

/// Ink grids for the orientation scorer.
///
/// The bilevel mask is the cleanest signal; the background rasters are
/// sampled when the page has no mask to decode.
ScanInkGrid _maskGrid(DjvuBitmap mask) => ScanInkGrid.sample(
  width: mask.width,
  height: mask.height,
  inkAt: (x, y) => mask.get(x, y) ? 1.0 : 0.0,
);

ScanInkGrid _grayGrid(Gray8Image gray) => ScanInkGrid.sample(
  width: gray.width,
  height: gray.height,
  inkAt: (x, y) => 1.0 - gray.data[y * gray.width + x] / 255.0,
);

ScanInkGrid _rgbaGrid(RgbaImage image) => ScanInkGrid.sample(
  width: image.width,
  height: image.height,
  inkAt: (x, y) {
    final (r, g, b) = image.getRgb(x, y);
    final luma = 0.299 * r + 0.587 * g + 0.114 * b;
    return 1.0 - luma / 255.0;
  },
);

/// Decodes the page mask, tolerating a malformed stream (matching the
/// reference's render-gracefully policy).
DjvuBitmap? _tryMask(DjvuPage page) {
  try {
    return page.decodeMask();
  } on Jb2Exception {
    return null;
  }
}

/// The page's `FGbz` palette, when it has one worth using.
///
/// An all-black palette is equivalent to the plain black stencil and treated
/// as absent (matching the reference).
DjvuFgbzPalette? _usablePalette(DjvuPage page) {
  final chunk = page.findChunk('FGbz');
  if (chunk == null) return null;
  DjvuFgbzPalette palette;
  try {
    palette = parseFgbzPalette(chunk.data);
  } on BzzException {
    return null;
  }
  if (palette.colors.isEmpty) return null;
  for (final color in palette.colors) {
    if (color.r != 0 || color.g != 0 || color.b != 0) return palette;
  }
  return null;
}

/// A single full-mask stencil painted in `rgb`.
_MaskLayer _stencilLayer(DjvuBitmap mask, int r, int g, int b) => _MaskLayer(
  r: r,
  g: g,
  b: b,
  x0: 0,
  y0: 0,
  bw: mask.width,
  bh: mask.height,
  maskW: mask.width,
  maskH: mask.height,
  body: makeMaskBody(mask),
);

/// Builds per-colour stencils for an `FGbz` palette page.
///
/// Colour lookup mirrors the reference renderer: the mask's blit record index
/// selects an entry of the palette, through the optional index table, falling
/// back to colour 0. Each used colour's plane is cropped to its bounding box,
/// which is what keeps the multi-stencil overhead small.
///
/// Falls back to a single black stencil when the indexed decode fails or the
/// palette is too large to stencil (see [_maxPaletteLayers]).
List<_MaskLayer> _paletteLayers(DjvuPage page, DjvuFgbzPalette palette) {
  (DjvuBitmap, Int32List)? indexed;
  try {
    indexed = page.decodeMaskIndexed();
  } on Jb2Exception {
    indexed = null;
  }
  if (indexed == null) {
    final mask = _tryMask(page);
    return mask == null ? const [] : [_stencilLayer(mask, 0, 0, 0)];
  }

  final (mask, blitMap) = indexed;
  final w = mask.width;
  final h = mask.height;
  final colorCount = palette.colors.length;

  // Pass 1: per-pixel colour index and per-colour bounding boxes.
  const none = 0xffff;
  final colorOfPixel = Uint16List(w * h);
  colorOfPixel.fillRange(0, colorOfPixel.length, none);
  final bbox = Uint32List(colorCount * 4);
  // Minima start at the sentinel, maxima at zero; a colour is used when its
  // min-x is no longer the sentinel.
  for (var ci = 0; ci < colorCount; ci++) {
    bbox[ci * 4] = 0xffffffff;
    bbox[ci * 4 + 1] = 0xffffffff;
  }
  var usedColors = 0;
  for (var y = 0; y < h; y++) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      if (!mask.get(x, y)) continue;
      final mi = row + x;
      final ci = _paletteColorIndex(palette, blitMap[mi]);
      colorOfPixel[mi] = ci;
      final base = ci * 4;
      if (bbox[base] == 0xffffffff) usedColors++;
      if (x < bbox[base]) bbox[base] = x;
      if (y < bbox[base + 1]) bbox[base + 1] = y;
      if (x > bbox[base + 2]) bbox[base + 2] = x;
      if (y > bbox[base + 3]) bbox[base + 3] = y;
    }
  }
  if (usedColors == 0) return const [];

  var planePixels = 0;
  for (var ci = 0; ci < colorCount; ci++) {
    final base = ci * 4;
    if (bbox[base] == 0xffffffff) continue;
    planePixels +=
        (bbox[base + 2] - bbox[base] + 1) * (bbox[base + 3] - bbox[base + 1] + 1);
  }
  if (usedColors > _maxPaletteLayers || planePixels > _maxStencilPlanePixels) {
    return [_stencilLayer(mask, 0, 0, 0)];
  }

  // Pass 2: one cropped plane per used colour.
  final planes = List<DjvuBitmap?>.filled(colorCount, null);
  for (var y = 0; y < h; y++) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      final ci = colorOfPixel[row + x];
      if (ci == none) continue;
      final base = ci * 4;
      final x0 = bbox[base];
      final y0 = bbox[base + 1];
      final plane = planes[ci] ??= DjvuBitmap(
        bbox[base + 2] - x0 + 1,
        bbox[base + 3] - y0 + 1,
      );
      plane.setBlack(x - x0, y - y0);
    }
  }

  final layers = <_MaskLayer>[];
  for (var ci = 0; ci < colorCount; ci++) {
    final plane = planes[ci];
    if (plane == null) continue;
    final base = ci * 4;
    final color = palette.colors[ci];
    layers.add(
      _MaskLayer(
        r: color.r,
        g: color.g,
        b: color.b,
        x0: bbox[base],
        y0: bbox[base + 1],
        bw: plane.width,
        bh: plane.height,
        maskW: w,
        maskH: h,
        body: makeMaskBody(plane),
      ),
    );
  }
  return layers;
}

/// Maps a mask blit record index to a palette colour index.
int _paletteColorIndex(DjvuFgbzPalette palette, int blitIndex) {
  if (blitIndex < 0) return 0;
  var raw = blitIndex;
  if (palette.indices.isNotEmpty) {
    raw = blitIndex < palette.indices.length ? palette.indices[blitIndex] : 0;
  }
  return raw >= 0 && raw < palette.colors.length ? raw : 0;
}

/// The result of the continuous-tone foreground policy.
class _ForegroundOutcome {
  const _ForegroundOutcome(this.layers, this.masked);

  final List<_MaskLayer> layers;
  final _MaskedImage? masked;
}

/// Builds foreground layers for a page without a usable palette: a flat
/// stencil when the `FG44`/`FGjp` colour under the mask is near-uniform, a
/// masked foreground image when it is multi-coloured, or a single black
/// stencil when the page has no continuous foreground at all.
_ForegroundOutcome _continuousForegroundLayers(DjvuPage page) {
  final mask = _tryMask(page);
  if (mask == null) return const _ForegroundOutcome([], null);

  final fg44 = page.fg44Chunks();
  Uint8List? fgjp;
  if (fg44.isEmpty) {
    final chunk = page.rawChunk('FGjp');
    if (chunk != null && chunk.isNotEmpty) fgjp = chunk;
  }

  RgbaImage? fg;
  if (fg44.isNotEmpty) {
    try {
      final image = Iw44Image();
      for (final chunk in fg44) {
        image.decodeChunk(chunk);
      }
      fg = image.toRgb();
    } on Iw44Exception {
      fg = null;
    }
  } else if (fgjp != null) {
    fg = decodeJpegToRgbaImage(fgjp);
  }

  if (fg == null) {
    // No continuous-tone foreground at all: the mask is black ink.
    if (fg44.isNotEmpty || fgjp != null) return const _ForegroundOutcome([], null);
    return _ForegroundOutcome([_stencilLayer(mask, 0, 0, 0)], null);
  }

  final uniform = _uniformFgColor(fg, mask);
  if (uniform != null) {
    return _ForegroundOutcome(
      [_stencilLayer(mask, uniform.$1, uniform.$2, uniform.$3)],
      null,
    );
  }

  final jpegInfo = fgjp == null ? null : _jpegFrameInfo(fgjp);
  if (jpegInfo != null &&
      (jpegInfo.channels == 1 || jpegInfo.channels == 3)) {
    return _ForegroundOutcome(
      [],
      _MaskedImage.jpeg(
        jpeg: fgjp!,
        jpegChannels: jpegInfo.channels,
        width: jpegInfo.width,
        height: jpegInfo.height,
        mask: mask,
      ),
    );
  }
  return _ForegroundOutcome(
    [],
    _MaskedImage.rgb(
      rgb: _rgbaToRgb(fg.data),
      width: fg.width,
      height: fg.height,
      mask: mask,
    ),
  );
}

/// The page's FG44/FGjp foreground colour if it is near-uniform under the
/// mask, else null.
///
/// Samples the (possibly subsampled) foreground image at every marked mask
/// pixel and returns the mean colour when every channel's spread stays within
/// [_fgUniformSpread].
(int, int, int)? _uniformFgColor(RgbaImage fg, DjvuBitmap mask) {
  if (fg.width == 0 || fg.height == 0 || mask.width == 0 || mask.height == 0) {
    return null;
  }
  final min = [255, 255, 255];
  final max = [0, 0, 0];
  final sum = [0, 0, 0];
  var n = 0;
  final data = fg.data;
  for (var y = 0; y < mask.height; y++) {
    final fy = y * fg.height ~/ mask.height;
    final fyClamped = fy >= fg.height ? fg.height - 1 : fy;
    for (var x = 0; x < mask.width; x++) {
      if (!mask.get(x, y)) continue;
      final fx = x * fg.width ~/ mask.width;
      final fxClamped = fx >= fg.width ? fg.width - 1 : fx;
      final pi = (fyClamped * fg.width + fxClamped) * 4;
      for (var c = 0; c < 3; c++) {
        final value = data[pi + c];
        if (value < min[c]) min[c] = value;
        if (value > max[c]) max[c] = value;
        sum[c] += value;
      }
      n++;
    }
  }
  if (n == 0) return null;
  for (var c = 0; c < 3; c++) {
    if (max[c] - min[c] > _fgUniformSpread) return null;
  }
  return (sum[0] ~/ n, sum[1] ~/ n, sum[2] ~/ n);
}

/// Packs RGBA bytes into RGB (PDF images have no alpha; DjVu pixels are
/// opaque).
Uint8List _rgbaToRgb(Uint8List rgba) {
  final out = Uint8List(rgba.length ~/ 4 * 3);
  for (var i = 0, j = 0; i < rgba.length; i += 4, j += 3) {
    out[j] = rgba[i];
    out[j + 1] = rgba[i + 1];
    out[j + 2] = rgba[i + 2];
  }
  return out;
}

/// Builds the XObject body for a `BGjp` background: the original JPEG bytes
/// are embedded unchanged (`/DCTDecode`), falling back to a re-encoded raster
/// when the frame header cannot be read.
Uint8List _bgjpBody(Uint8List jpeg, DjvuPdfOptions options) {
  final info = _jpegFrameInfo(jpeg);
  if (info != null && (info.channels == 1 || info.channels == 3)) {
    final colorSpace = info.channels == 1 ? '/DeviceGray' : '/DeviceRGB';
    return makeDctStream(
      ' /Type /XObject /Subtype /Image'
      ' /Width ${info.width} /Height ${info.height}'
      ' /ColorSpace $colorSpace /BitsPerComponent 8',
      jpeg,
    );
  }
  final rgba = decodeJpegToRgbaImage(jpeg);
  if (rgba == null) {
    throw const DjvuDocumentException('undecodable BGjp background image');
  }
  return makeRgbImageBody(
    _rgbaToRgb(rgba.data),
    rgba.width,
    rgba.height,
    jpegQuality: options.jpegQuality,
  );
}

/// The JPEG frame header of [data], or null when it cannot be read.
///
/// Scans for the first SOF marker (`FFC0`–`FFCF`, excluding the DHT/JPG/DAC
/// markers) and returns its dimensions and component count.
({int width, int height, int channels})? _jpegFrameInfo(Uint8List data) {
  if (data.length < 2 || data[0] != 0xff || data[1] != 0xd8) return null;
  var pos = 2;
  while (pos + 4 <= data.length) {
    if (data[pos] != 0xff) return null;
    var marker = data[pos + 1];
    // Skip any 0xFF fill bytes preceding the marker.
    while (marker == 0xff) {
      pos++;
      if (pos + 1 >= data.length) return null;
      marker = data[pos + 1];
    }
    if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd9)) {
      // Standalone markers (TEM, RSTn, SOI, EOI): no payload.
      pos += 2;
      if (marker == 0xd9) return null;
      continue;
    }
    if (marker == 0xda) return null; // SOS reached without a frame header.
    if (pos + 4 > data.length) return null;
    final length = (data[pos + 2] << 8) | data[pos + 3];
    if (length < 2 || pos + 2 + length > data.length) return null;
    if (marker >= 0xc0 &&
        marker <= 0xcf &&
        marker != 0xc4 &&
        marker != 0xc8 &&
        marker != 0xcc) {
      if (length < 8) return null;
      final height = (data[pos + 5] << 8) | data[pos + 6];
      final width = (data[pos + 7] << 8) | data[pos + 8];
      final channels = data[pos + 9];
      if (width == 0 || height == 0 || channels == 0) return null;
      return (width: width, height: height, channels: channels);
    }
    pos += 2 + length;
  }
  return null;
}

/// Builds the page's link targets from its ANTz annotations.
///
/// Internal `#page_N`-style URLs become destinations when they fall inside the
/// document; everything else keeps its URI. A malformed annotation chunk
/// yields no links (matching the reference's tolerance).
List<_LinkTarget> _pageLinks(DjvuPage page, double dpi, int pageCount) {
  List<DjvuMapArea> areas;
  try {
    areas = page.hyperlinks();
  } on BzzException {
    return const [];
  } on DjvuFormatException {
    return const [];
  }

  final out = <_LinkTarget>[];
  for (final area in areas) {
    final bbox = djvuShapeBbox(area.shape);
    if (bbox == null) continue;
    final x1 = bbox.x * 72.0 / dpi;
    final y1 = bbox.y * 72.0 / dpi;
    final x2 = (bbox.x + bbox.width) * 72.0 / dpi;
    final y2 = (bbox.y + bbox.height) * 72.0 / dpi;
    final index = bookmarkPageIndex(area.url);
    if (index != null && index < pageCount) {
      out.add(
        _LinkTarget.dest(pageIndex: index, x1: x1, y1: y1, x2: x2, y2: y2),
      );
    } else {
      out.add(_LinkTarget.uri(url: area.url, x1: x1, y1: y1, x2: x2, y2: y2));
    }
  }
  return out;
}

/// Emits a rendered page: its XObjects, content stream, annotations and page
/// dictionary.
void _emitPage(
  DjvuPdfWriter writer,
  int pageId,
  int pagesId,
  List<int> pageIds,
  _RenderedPage page,
  DjvuPdfOptions options,
) {
  final imgId = page.img0 == null ? null : writer.addObject(page.img0!);

  final maskIds = <int>[];
  for (final layer in page.layers) {
    maskIds.add(writer.addObject(layer.body));
  }

  int? fgId;
  final masked = page.maskedForeground;
  if (masked != null) {
    final maskId = writer.addObject(makeMaskBody(masked.mask));
    if (masked.jpeg != null) {
      final colorSpace = masked.jpegChannels == 1 ? '/DeviceGray' : '/DeviceRGB';
      fgId = writer.addObject(
        makeDctStream(
          ' /Type /XObject /Subtype /Image'
          ' /Width ${masked.width} /Height ${masked.height}'
          ' /ColorSpace $colorSpace /BitsPerComponent 8'
          ' /Mask $maskId 0 R',
          masked.jpeg!,
        ),
      );
    } else {
      fgId = writer.addObject(
        makeRgbImageBodyWithExtra(
          masked.rgb!,
          masked.width,
          masked.height,
          ' /Mask $maskId 0 R',
          jpegQuality: options.jpegQuality,
        ),
      );
    }
  }

  final ptW = fmtPt(page.ptW);
  final ptH = fmtPt(page.ptH);
  final content = StringBuffer();
  if (imgId != null) {
    if (page.img0IsMask) {
      // An ImageMask stencil paints in the current fill colour, so the
      // bilevel page's ink must be black.
      content.write('0 0 0 rg\n');
    }
    content.write('q $ptW 0 0 $ptH 0 0 cm /Im0 Do Q\n');
  }
  for (var i = 0; i < page.layers.length; i++) {
    final layer = page.layers[i];
    // Map the cropped stencil back into place: PDF images fill the unit
    // square of the current transform, rows top-down, page origin
    // bottom-left.
    final sw = page.ptW * layer.bw / layer.maskW;
    final sh = page.ptH * layer.bh / layer.maskH;
    final tx = page.ptW * layer.x0 / layer.maskW;
    final ty = page.ptH * (layer.maskH - layer.y0 - layer.bh) / layer.maskH;
    content.write(
      'q ${fmtRgComponent(layer.r)} ${fmtRgComponent(layer.g)}'
      ' ${fmtRgComponent(layer.b)} rg'
      ' ${fmtPt(sw)} 0 0 ${fmtPt(sh)} ${fmtPt(tx)} ${fmtPt(ty)} cm'
      ' /Mask$i Do Q\n',
    );
  }
  if (fgId != null) {
    content.write('q $ptW 0 0 $ptH 0 0 cm /Im1 Do Q\n');
  }

  final contentId = writer.addFlateStream(
    '',
    _ascii(content.toString()),
  );

  final resources = StringBuffer('/XObject <<');
  if (imgId != null) resources.write(' /Im0 $imgId 0 R');
  if (fgId != null) resources.write(' /Im1 $fgId 0 R');
  for (var i = 0; i < maskIds.length; i++) {
    resources.write(' /Mask$i ${maskIds[i]} 0 R');
  }
  resources.write(' >>');

  final annotIds = <int>[];
  for (final link in page.links) {
    annotIds.add(writer.addObject(_linkAnnotBody(link, pageIds)));
  }
  final annots = annotIds.isEmpty
      ? ''
      : ' /Annots [${[for (final id in annotIds) ' $id 0 R'].join()} ]';

  final rotate = page.rotate == 0 ? '' : ' /Rotate ${page.rotate}';
  writer.writeObject(
    pageId,
    _ascii(
      '<< /Type /Page /Parent $pagesId 0 R\n'
      '/MediaBox [0 0 $ptW $ptH]$rotate\n'
      '/Contents $contentId 0 R\n'
      '/Resources << $resources >>$annots >>',
    ),
  );
}

/// Builds a link annotation body: an internal destination when the target
/// page is inside the document, else a URI action.
Uint8List _linkAnnotBody(_LinkTarget link, List<int> pageIds) {
  final rect =
      '${fmtPt(link.x1)} ${fmtPt(link.y1)} ${fmtPt(link.x2)} ${fmtPt(link.y2)}';
  final String action;
  if (link.pageIndex >= 0 && link.pageIndex < pageIds.length) {
    action = ' /Dest [${pageIds[link.pageIndex]} 0 R /Fit]';
  } else {
    action = ' /A << /S /URI /URI ${pdfStringLiteral(link.url ?? '')} >>';
  }
  return _ascii(
    '<< /Type /Annot /Subtype /Link\n'
    '/Rect [$rect]\n'
    '/Border [0 0 0]$action >>',
  );
}

/// Builds the PDF outline from NAVM bookmarks; returns the outline root id, or
/// null when there are no bookmarks.
int? _buildOutline(
  DjvuPdfWriter writer,
  List<DjvuBookmark> bookmarks,
  List<int> pageIds,
) {
  if (bookmarks.isEmpty) return null;
  final outlineId = writer.reserveId();
  final itemIds = _writeOutlineItems(writer, bookmarks, outlineId, pageIds);
  if (itemIds.isEmpty) return null;
  writer.writeObject(
    outlineId,
    _ascii(
      '<< /Type /Outlines /First ${itemIds.first} 0 R'
      ' /Last ${itemIds.last} 0 R'
      ' /Count ${_countOutlineItems(bookmarks)} >>',
    ),
  );
  return outlineId;
}

/// Recursively writes outline items; returns the ids of the top-level items
/// written at this level.
List<int> _writeOutlineItems(
  DjvuPdfWriter writer,
  List<DjvuBookmark> bookmarks,
  int parentId,
  List<int> pageIds,
) {
  final ids = [for (var i = 0; i < bookmarks.length; i++) writer.reserveId()];
  for (var i = 0; i < bookmarks.length; i++) {
    final bookmark = bookmarks[i];
    final itemId = ids[i];
    final prev = i > 0 ? ' /Prev ${ids[i - 1]} 0 R' : '';
    final next = i + 1 < ids.length ? ' /Next ${ids[i + 1]} 0 R' : '';

    final index = bookmarkPageIndex(bookmark.url);
    final String dest;
    if (index != null && index < pageIds.length) {
      dest = ' /Dest [${pageIds[index]} 0 R /Fit]';
    } else if (bookmark.url.isNotEmpty) {
      dest = ' /A << /S /URI /URI ${pdfStringLiteral(bookmark.url)} >>';
    } else {
      dest = '';
    }

    final childIds = _writeOutlineItems(writer, bookmark.children, itemId, pageIds);
    final children = childIds.isEmpty
        ? ''
        : ' /First ${childIds.first} 0 R'
              ' /Last ${childIds.last} 0 R'
              ' /Count ${_countOutlineItems(bookmark.children)}';

    writer.writeObject(
      itemId,
      _ascii(
        '<< /Title ${pdfStringLiteral(bookmark.title)}'
        ' /Parent $parentId 0 R$prev$next$dest$children >>',
      ),
    );
  }
  return ids;
}

/// Number of outline items in [bookmarks], children included.
int _countOutlineItems(List<DjvuBookmark> bookmarks) {
  var n = bookmarks.length;
  for (final bookmark in bookmarks) {
    n += _countOutlineItems(bookmark.children);
  }
  return n;
}

/// Latin-1 encodes generated PDF syntax (all of which is ASCII).
Uint8List _ascii(String text) {
  final bytes = Uint8List(text.length);
  for (var i = 0; i < text.length; i++) {
    bytes[i] = text.codeUnitAt(i);
  }
  return bytes;
}
