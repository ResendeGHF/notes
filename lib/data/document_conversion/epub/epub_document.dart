// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// XHTML -> pdf widget rendering for the EPUB converter.
//
// The renderer walks a parsed XHTML document and produces a flat list of
// block widgets for a `pw.MultiPage`. Author stylesheets are cascaded by
// `epub_css.dart`; this file maps the resulting computed style onto pdf
// text/box styles. Every block keeps only what the PDF reader needs: text,
// spacing, backgrounds, images, tables and link destinations.
//
// Anchors are deliberately not plain `pw.Anchor` widgets. `MultiPage`
// re-paints spanning widgets once per page, and named destinations are
// last-write-wins, so a link pointing at the start of a long paragraph would
// end up on the last page it paints on. `EpubAnchor` records the first page
// it is painted on and rewrites every one of its destination names with those
// coordinates on every paint.

// html is pulled in through the pdf package rather than declared directly.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:saber/data/document_conversion/epub/epub_css.dart';
import 'package:saber/data/document_conversion/epub/epub_parser.dart';
import 'package:saber/data/document_conversion/scan_orientation.dart';

/// Base font size used for EPUB body text, in points.
const kEpubBaseFontSize = 11.0;

/// A5 portrait page geometry (148mm x 210mm, 16mm margins).
const kEpubPageWidth = 148 * PdfPageFormat.mm;
const kEpubPageHeight = 210 * PdfPageFormat.mm;
const kEpubPageMargin = 16 * PdfPageFormat.mm;
const kEpubContentWidth = kEpubPageWidth - 2 * kEpubPageMargin;
const kEpubContentHeight = kEpubPageHeight - 2 * kEpubPageMargin;

/// Images above this many pixels are skipped to keep conversions bounded.
const kEpubMaxImagePixels = 40 * 1000 * 1000;

const _baseStyle = EpubStyle(
  fontSize: kEpubBaseFontSize,
  color: PdfColors.black,
  lineHeightFactor: 1.45,
);

/// Tracks the first page each named destination is painted on.
///
/// Destination names are claimed up front (so collisions can be resolved) and
/// recorded while the PDF is painted. [claim] is also used by the converter to
/// reserve the anchors carried by the table of contents.
class EpubAnchorRegistry {
  final _claimed = <String>{};
  final _first = <String, ({PdfPage page, PdfPoint position})>{};

  /// Reserves [name]. Returns false when it was already claimed.
  bool claim(String name) => _claimed.add(name);

  /// Records the first sighting of [name], or returns the stored sighting.
  ({PdfPage page, PdfPoint position})? record(
    String name,
    PdfPage page,
    PdfPoint position,
  ) {
    if (!_claimed.contains(name)) return null;
    return _first.putIfAbsent(name, () => (page: page, position: position));
  }

  /// The first page [name] was painted on, or null when it never was.
  PdfPage? pageFor(String name) => _first[name]?.page;

  /// The position of [name] on [pageFor], if it was painted.
  PdfPoint? positionFor(String name) => _first[name]?.position;
}

/// A widget that registers the first page it paints on for [names].
class EpubAnchor extends pw.SingleChildWidget {
  EpubAnchor({
    required this.names,
    required this.registry,
    super.child,
  });

  final List<String> names;
  final EpubAnchorRegistry registry;

  @override
  void paint(pw.Context context) {
    super.paint(context);
    paintChild(context);

    final box = this.box;
    if (box == null || names.isEmpty) return;
    final point = context.localToGlobalPoint(
      PdfPoint(box.left, box.top),
    );
    for (final name in names) {
      final first = registry.record(name, context.page, point);
      if (first == null) continue;
      context.document.pdfNames.addDest(
        name,
        first.page,
        posX: first.position.x,
        posY: first.position.y,
      );
    }
  }
}

/// Builds the named destination for an element id in spine document
/// [spineIndex]. The result is limited to characters that are safe inside a
/// PDF name tree entry; lossy conversions get a stable hash suffix.
String epubAnchorName(int spineIndex, String id) {
  var safe = id.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  var lossy = safe.length != id.length;
  if (safe.length > 80) {
    safe = safe.substring(0, 80);
    lossy = true;
  }
  if (safe.isEmpty) safe = 'id';
  final name = 'ch_${spineIndex}_id_$safe';
  return lossy ? '${name}_${_fnv1a(id)}' : name;
}

/// The destination for the start of spine document [spineIndex].
String epubTopAnchorName(int spineIndex) => 'ch_${spineIndex}_top';

String _fnv1a(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// A table-of-contents entry attached to a rendered block.
class EpubOutlineTarget {
  const EpubOutlineTarget({
    required this.anchor,
    required this.title,
    required this.level,
  });

  final String anchor;
  final String title;
  final int level;
}

/// The result of resolving an href in a chapter.
class EpubResolvedLink {
  const EpubResolvedLink.destination(String this.destination) : url = null;
  const EpubResolvedLink.external(String this.url) : destination = null;

  final String? destination;
  final String? url;
}

/// Resolves an href as written in the document being rendered.
typedef EpubLinkResolver = EpubResolvedLink? Function(String href);

/// Ids and title collected from one spine document.
class EpubDocumentScan {
  const EpubDocumentScan({required this.ids, required this.title});

  final List<String> ids;
  final String title;
}

/// Collects unique element ids (first occurrence wins) and the document title.
EpubDocumentScan scanEpubDocument(dom.Document document) {
  final ids = <String>[];
  final seen = <String>{};
  for (final element in document.querySelectorAll('[id]')) {
    final id = element.id;
    if (id.isNotEmpty && seen.add(id)) ids.add(id);
  }
  final title = document.querySelector('title')?.text.trim() ?? '';
  return EpubDocumentScan(ids: ids, title: title);
}

/// Decodes EPUB text content as UTF-8, tolerating malformed bytes and a BOM.
String decodeEpubText(Uint8List bytes) {
  var data = bytes;
  if (data.length >= 3 &&
      data[0] == 0xEF &&
      data[1] == 0xBB &&
      data[2] == 0xBF) {
    data = Uint8List.sublistView(data, 3);
  }
  return utf8.decode(data, allowMalformed: true);
}

/// Loads every `<style>` and linked stylesheet of [document].
EpubCssStylesheet loadEpubStylesheet(
  EpubBook book,
  String docPath,
  dom.Document document,
) {
  final stylesheet = EpubCssStylesheet();
  final seenImports = <String>{};

  String? loadCss(String basePath, String href, {bool isImport = false}) {
    final path = resolveArchivePath(basePath, href);
    if (path == null) return null;
    if (isImport && !seenImports.add(path)) return null;
    final bytes = book.archive.readFile(path);
    if (bytes == null) return null;
    return decodeEpubText(bytes);
  }

  for (final link in document.querySelectorAll('link')) {
    final rel = (link.attributes['rel'] ?? '').toLowerCase();
    if (!rel.split(RegExp(r'\s+')).contains('stylesheet')) continue;
    final href = link.attributes['href'];
    if (href == null || href.trim().isEmpty) continue;
    final cssPath = resolveArchivePath(docPath, href);
    final css = loadCss(docPath, href);
    if (css == null) continue;
    final base = cssPath == null ? docPath : _dirname(cssPath);
    stylesheet.add(
      css,
      loadImport: (uri) => loadCss(base, _normalizeCssUrl(uri), isImport: true),
    );
  }

  for (final style in document.querySelectorAll('style')) {
    final text = style.text;
    if (text.trim().isEmpty) continue;
    stylesheet.add(
      text,
      loadImport: (uri) =>
          loadCss(docPath, _normalizeCssUrl(uri), isImport: true),
    );
  }

  return stylesheet;
}

String _normalizeCssUrl(String value) {
  var url = value.trim();
  final functional = RegExp(
    r'^url\(\s*(.*?)\s*\)$',
    caseSensitive: false,
  ).firstMatch(url);
  if (functional != null) url = functional.group(1)!.trim();
  if (url.length >= 2 &&
      ((url.startsWith('"') && url.endsWith('"')) ||
          (url.startsWith("'") && url.endsWith("'")))) {
    url = url.substring(1, url.length - 1);
  }
  return url;
}

String _dirname(String path) {
  final slash = path.lastIndexOf('/');
  return slash <= 0 ? '' : path.substring(0, slash);
}

/// Removes control characters and normalises whitespace for PDF text.
///
/// In collapse mode every run of whitespace becomes a single space. In
/// preserve mode (CSS `white-space: pre`) line breaks are kept and tabs are
/// expanded. Unpaired surrogates are dropped so they cannot break font
/// subsetting.
String normalizeEpubText(
  String value, {
  required bool preserveWhitespace,
}) {
  final out = StringBuffer();
  final runes = value.runes.toList(growable: false);
  var previousWasCarriageReturn = false;
  var pendingSpace = false;

  for (var index = 0; index < runes.length; index++) {
    final rune = runes[index];
    if (rune == 0x0D) {
      previousWasCarriageReturn = true;
      if (preserveWhitespace) {
        out.write('\n');
        pendingSpace = false;
      } else if (!pendingSpace) {
        out.write(' ');
        pendingSpace = true;
      }
      continue;
    }
    if (rune == 0x0A) {
      if (previousWasCarriageReturn) {
        previousWasCarriageReturn = false;
        continue;
      }
      if (preserveWhitespace) {
        out.write('\n');
        pendingSpace = false;
      } else if (!pendingSpace) {
        out.write(' ');
        pendingSpace = true;
      }
      continue;
    }
    previousWasCarriageReturn = false;
    if (rune == 0x09) {
      if (preserveWhitespace) {
        out.write('    ');
        pendingSpace = false;
      } else if (!pendingSpace) {
        out.write(' ');
        pendingSpace = true;
      }
      continue;
    }
    if (rune == 0x2028 || rune == 0x2029) {
      if (preserveWhitespace) {
        out.write('\n');
        pendingSpace = false;
      } else if (!pendingSpace) {
        out.write(' ');
        pendingSpace = true;
      }
      continue;
    }
    if (rune == 0x20 || rune == 0xA0) {
      if (preserveWhitespace) {
        out.write(rune == 0xA0 ? '\u00A0' : ' ');
        pendingSpace = false;
      } else if (!pendingSpace) {
        out.write(' ');
        pendingSpace = true;
      }
      continue;
    }
    if (rune < 0x20 ||
        rune == 0x7F ||
        (rune >= 0x80 && rune <= 0x9F) ||
        rune == 0xFEFF ||
        rune == 0xFFFE ||
        rune == 0xFFFF ||
        (rune >= 0xD800 && rune <= 0xDFFF)) {
      continue;
    }
    out.writeCharCode(rune);
    pendingSpace = false;
  }

  return out.toString();
}

/// Decodes [path] into a PDF image, or returns null when it is missing,
/// malformed, or larger than [maxPixels].
///
/// JPEGs are embedded directly; every other supported format is decoded and
/// re-encoded as PNG (the only raster format the pdf package accepts besides
/// JPEG).
pw.MemoryImage? loadEpubImage(
  EpubArchive archive,
  String path, {
  int maxPixels = kEpubMaxImagePixels,
}) {
  final bytes = archive.readFile(path);
  if (bytes == null || bytes.isEmpty) return null;

  if (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    try {
      final info = PdfJpegInfo(bytes);
      final width = info.width;
      final height = info.height;
      if (width == null || width <= 0 || height <= 0) return null;
      if (width * height > maxPixels) return null;
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    if (decoded.width * decoded.height > maxPixels) return null;
    return pw.MemoryImage(img.encodePng(decoded));
  } catch (_) {
    return null;
  }
}

class _BlockDecoration {
  const _BlockDecoration({required this.names, required this.outlines});

  final List<String> names;
  final List<EpubOutlineTarget> outlines;
}

/// An image widget plus the orientation correction the scan pre-pass found for
/// it. `unknown` (the default) lays the image out exactly as stored.
class _LoadedImage {
  const _LoadedImage({required this.image, required this.orientation});

  final pw.MemoryImage image;
  final ScanOrientation orientation;
}

/// Renders one spine document into a flat list of [pw.MultiPage] widgets.
///
/// Containers are flattened so CSS `page-break-before`/`after` can always be
/// expressed as a direct `pw.NewPage` child (which is the only place
/// `MultiPage` honours it). Horizontal padding/margins are folded into an
/// indent while descending; vertical spacing becomes explicit spacers.
class EpubChapterBuilder {
  EpubChapterBuilder({
    required this.book,
    required this.spineIndex,
    required this.docPath,
    required this.document,
    required this.stylesheet,
    required this.registry,
    required this.anchorNames,
    required this.outlineTargets,
    required this.topOutlineTargets,
    required this.resolveLink,
    this.scanOrientations = const {},
  });

  final EpubBook book;
  final int spineIndex;
  final String docPath;
  final dom.Document document;
  final EpubCssStylesheet stylesheet;
  final EpubAnchorRegistry registry;

  /// Orientation corrections for sideways page scans, keyed by archive entry
  /// name; see `epub_scan_probe.dart`. Images without an entry are laid out
  /// as stored.
  final Map<String, ScanOrientation> scanOrientations;

  /// Element id -> named destination allocated by the converter.
  final Map<String, String> anchorNames;

  /// Element id -> table-of-contents entries targeting that element.
  final Map<String, List<EpubOutlineTarget>> outlineTargets;

  /// Table-of-contents entries targeting the start of this document.
  final List<EpubOutlineTarget> topOutlineTargets;

  final EpubLinkResolver resolveLink;

  final _widgets = <pw.Widget>[];
  final _pendingDecorations = <_BlockDecoration>[];
  final _usedAnchorNames = <String>{};
  final _imageCache = <String, _LoadedImage?>{};
  var _pageImageScanDone = false;
  var _rotatedBlockImages = 0;
  var _portraitBlockImages = 0;

  double _indent = 0;
  PdfColor? _background;
  var _pendingBreak = false;
  var _topAttached = false;
  var _pendingSpace = true;

  /// Whether every page image this chapter lays out is a landscape scan after
  /// correction, and at least two of them had to be turned.
  ///
  /// That is the "scanned book" shape: one page image per page, stored
  /// sideways. Such chapters get landscape pages so each scan fills its page
  /// instead of floating on a portrait sheet.
  bool get prefersLandscapePages {
    _scanPageImages();
    return _rotatedBlockImages >= 2 && _portraitBlockImages == 0;
  }

  /// Content box of this chapter's pages; landscape scan chapters get the
  /// swapped box so the scans fill the page.
  double get contentWidth =>
      prefersLandscapePages ? kEpubContentHeight : kEpubContentWidth;
  double get contentHeight =>
      prefersLandscapePages ? kEpubContentWidth : kEpubContentHeight;

  /// Reviews every `<img>` before layout so [prefersLandscapePages] is known
  /// while widgets are built. Images land in [_imageCache], so the render pass
  /// does not load anything twice.
  void _scanPageImages() {
    if (_pageImageScanDone || scanOrientations.isEmpty) return;
    _pageImageScanDone = true;
    for (final element in document.querySelectorAll('img')) {
      final loaded = _loadImage(element);
      if (loaded == null) continue;
      if (loaded.orientation == ScanOrientation.unknown) continue;
      final width = loaded.image.width ?? 0;
      final height = loaded.image.height ?? 0;
      if (width <= 0 || height <= 0) continue;
      if (loaded.orientation != ScanOrientation.upright) {
        _rotatedBlockImages++;
      }
      if (!scanCorrectedIsLandscape(width, height, loaded.orientation)) {
        _portraitBlockImages++;
      }
    }
  }

  /// Builds the chapter. The returned list is owned by the caller.
  List<pw.Widget> build() {
    _scanPageImages();
    final body = document.body ?? document.documentElement;
    if (body == null) return _widgets;

    var style = _baseStyle;
    final root = document.documentElement;
    if (root != null && root != body) {
      style = _styleFor(root, style);
    }
    style = _styleFor(body, style);
    _renderContents(body, style);

    while (_widgets.isNotEmpty && _widgets.last is pw.NewPage) {
      _widgets.removeLast();
    }
    return _widgets;
  }

  void _renderContents(dom.Element element, EpubStyle style) {
    final inline = <dom.Node>[];
    for (final node in element.nodes) {
      if (node is dom.Element) {
        if (_isBlock(node, style)) {
          _flushInline(inline, style);
          _renderBlock(node, style);
        } else {
          inline.add(node);
        }
      } else if (node is dom.Text) {
        if (node.data.trim().isNotEmpty) inline.add(node);
      }
    }
    _flushInline(inline, style);
  }

  void _flushInline(List<dom.Node> nodes, EpubStyle style) {
    if (nodes.isEmpty) return;
    _pendingSpace = true;
    final spans = _inlineChildren(nodes, style);
    _trimTrailingSpace(spans);
    nodes.clear();
    if (spans.isEmpty) return;
    _appendBlock(
      pw.RichText(
        text: pw.TextSpan(children: spans),
        textAlign: style.textAlign,
        // Allow paragraphs taller than a page to split across pages instead
        // of failing the whole layout.
        overflow: pw.TextOverflow.span,
      ),
      style,
      applyBox: false,
    );
  }

  void _renderBlock(dom.Element element, EpubStyle parentStyle) {
    final tag = element.localName ?? '';
    // Covers (and some page-spread documents) export as an SVG element whose
    // only payload is one raster `<image>`; it draws like a plain `<img>`.
    if (tag == 'svg') {
      _renderSvgImage(element, parentStyle);
      return;
    }
    final style = _styleFor(element, parentStyle);
    if (_hidden(element, style)) return;

    switch (tag) {
      case 'hr':
        _renderHorizontalRule(element, style);
      case 'table':
        _renderTable(element, style);
      case 'ul':
      case 'ol':
        _renderList(element, style);
      case 'pre':
        _renderPre(element, style);
      case 'img':
        _renderImage(element, style);
      case 'br':
        _addSpacer(style.fontSize);
      case 'p':
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        _renderParagraph(element, style);
      default:
        if (_hasBlockChildren(element, style)) {
          _renderContainer(element, style);
        } else {
          _renderParagraph(element, style);
        }
    }
  }

  bool _isBlock(dom.Element element, EpubStyle parentStyle) {
    final tag = element.localName ?? '';
    if (tag == 'img') return true;
    if (tag == 'svg') return _svgRasterImage(element) != null;
    if (tag == 'br') return false;
    if (tag == 'hr' ||
        tag == 'table' ||
        tag == 'pre' ||
        tag == 'blockquote' ||
        tag == 'figure') {
      return true;
    }
    if (isDefaultBlockTag(tag)) return true;
    final display = _styleFor(element, parentStyle).display;
    return display == 'none' ||
        display == 'block' ||
        display == 'list-item';
  }

  bool _hasBlockChildren(dom.Element element, EpubStyle style) {
    for (final child in element.children) {
      if (_isBlock(child, style)) return true;
    }
    return false;
  }

  bool _hidden(dom.Element element, EpubStyle style) {
    if (style.display == 'none') return true;
    if (element.attributes.containsKey('hidden')) return true;
    if ((element.attributes['aria-hidden'] ?? '').toLowerCase() == 'true') {
      return true;
    }
    if ((element.localName ?? '') == 'svg') {
      // Vector SVG is out of scope; only the raster-carrying cover form draws.
      return _svgRasterImage(element) == null;
    }
    switch (element.localName) {
      case 'script':
      case 'style':
      case 'head':
      case 'title':
      case 'meta':
      case 'link':
      case 'template':
        return true;
    }
    return false;
  }

  EpubStyle _styleFor(dom.Element element, EpubStyle parent) {
    var style = parent;
    final ua = kEpubUserAgentStyles[element.localName];
    if (ua != null) {
      style = style.apply(
        ua,
        rootFontSize: kEpubBaseFontSize,
        percentBase: kEpubContentWidth,
      );
    }
    final declared = stylesheet.declarationsFor(element);
    if (declared.isNotEmpty) {
      style = style.apply(
        declared,
        rootFontSize: kEpubBaseFontSize,
        percentBase: kEpubContentWidth,
      );
    }
    final inline = EpubCssStylesheet.parseInlineStyle(
      element.attributes['style'] ?? '',
    );
    if (inline.isNotEmpty) {
      style = style.apply(
        inline,
        rootFontSize: kEpubBaseFontSize,
        percentBase: kEpubContentWidth,
      );
    }
    return style;
  }

  // Block layout -----------------------------------------------------------

  void _appendBlock(
    pw.Widget widget,
    EpubStyle style, {
    _BlockDecoration? decorations,
    bool applyBox = true,
  }) {
    final collected = <_BlockDecoration>[
      ..._pendingDecorations,
      ?decorations,
    ];
    _pendingDecorations.clear();
    if (!_topAttached) {
      _topAttached = true;
      collected.insert(
        0,
        _BlockDecoration(
          names: [epubTopAnchorName(spineIndex)],
          outlines: topOutlineTargets,
        ),
      );
    }

    var block = _decorateWidget(widget, collected);
    if (applyBox) {
      final left = _indent + style.marginLeft + style.paddingLeft;
      final right = style.marginRight + style.paddingRight;
      final background = style.background ?? _background;
      if (left > 0 ||
          right > 0 ||
          style.paddingTop > 0 ||
          style.paddingBottom > 0 ||
          background != null) {
        block = pw.Container(
          padding: pw.EdgeInsets.only(
            left: left,
            right: right,
            top: style.paddingTop,
            bottom: style.paddingBottom,
          ),
          color: background,
          child: block,
        );
      }
    }

    if (applyBox && style.breakBefore) _pendingBreak = true;
    if (applyBox && style.marginTop > 0) _addSpacer(style.marginTop);
    _flushPendingBreak();
    _widgets.add(block);
    if (applyBox && style.marginBottom > 0) _addSpacer(style.marginBottom);
    if (applyBox && style.breakAfter) _pendingBreak = true;
  }

  pw.Widget _decorateWidget(
    pw.Widget widget,
    List<_BlockDecoration> decorations,
  ) {
    final names = <String>[];
    final outlines = <EpubOutlineTarget>[];
    for (final decoration in decorations) {
      for (final name in decoration.names) {
        if (!names.contains(name)) names.add(name);
      }
      outlines.addAll(decoration.outlines);
    }

    var result = widget;
    for (final target in outlines.reversed) {
      result = pw.Outline(
        name: target.anchor,
        title: target.title,
        level: target.level,
        child: result,
      );
    }
    if (names.isNotEmpty) {
      result = EpubAnchor(names: names, registry: registry, child: result);
    }
    return result;
  }

  void _addSpacer(double height) {
    if (height <= 0) return;
    _flushPendingBreak();
    if (_widgets.isEmpty) return;
    _widgets.add(pw.SizedBox(height: height));
  }

  void _flushPendingBreak() {
    if (!_pendingBreak) return;
    _pendingBreak = false;
    if (_widgets.isEmpty) return;
    if (_widgets.last is pw.NewPage) return;
    _widgets.add(pw.NewPage());
  }

  _BlockDecoration? _decorationFor(dom.Element element) {
    final names = <String>[];
    final outlines = <EpubOutlineTarget>[];
    final id = element.id;
    if (id.isNotEmpty) {
      final name = anchorNames[id];
      if (name != null && _usedAnchorNames.add(name)) names.add(name);
      outlines.addAll(outlineTargets[id] ?? const <EpubOutlineTarget>[]);
    }
    if (names.isEmpty && outlines.isEmpty) return null;
    return _BlockDecoration(names: names, outlines: outlines);
  }

  // Paragraphs and inline content -----------------------------------------

  void _renderParagraph(
    dom.Element element,
    EpubStyle style, {
    List<pw.InlineSpan> prefix = const <pw.InlineSpan>[],
  }) {
    _pendingSpace = true;
    final spans = <pw.InlineSpan>[
      ...prefix,
      ..._inlineChildren(element.nodes, style),
    ];
    _trimTrailingSpace(spans);
    if (spans.isEmpty) return;
    _appendBlock(
      pw.RichText(
        text: pw.TextSpan(children: spans),
        textAlign: style.textAlign,
        // Allow paragraphs taller than a page to split across pages instead
        // of failing the whole layout.
        overflow: pw.TextOverflow.span,
      ),
      style,
      decorations: _decorationFor(element),
    );
  }

  List<pw.InlineSpan> _inlineChildren(
    List<dom.Node> nodes,
    EpubStyle style,
  ) {
    final out = <pw.InlineSpan>[];
    for (final node in nodes) {
      _inlineNode(out, node, style);
    }
    return out;
  }

  void _inlineNode(
    List<pw.InlineSpan> out,
    dom.Node node,
    EpubStyle parentStyle,
  ) {
    if (node is dom.Text) {
      _addText(
        out,
        node.data,
        parentStyle,
        spanBackground: false,
      );
      return;
    }
    if (node is! dom.Element) return;

    final tag = node.localName ?? '';
    if (tag == 'br') {
      out.add(const pw.TextSpan(text: '\n'));
      _pendingSpace = true;
      return;
    }

    final style = _styleFor(node, parentStyle);
    if (_hidden(node, style)) return;

    final decoration = _decorationFor(node);
    if (decoration != null) {
      out.add(
        pw.WidgetSpan(
          child: _decorateWidget(pw.SizedBox.shrink(), [decoration]),
        ),
      );
    }

    if (tag == 'img') {
      final image = _loadImage(node);
      if (image != null) {
        out.add(
          pw.WidgetSpan(child: _imageWidget(image, node, inline: true)),
        );
      }
      return;
    }

    final children = <pw.InlineSpan>[];
    for (final child in node.nodes) {
      if (child is dom.Text) {
        _addText(
          children,
          child.data,
          style,
          spanBackground: style.background != null,
        );
      } else {
        _inlineNode(children, child, style);
      }
    }

    final href = node.attributes['href'] ?? '';
    final resolved = tag == 'a' && href.trim().isNotEmpty
        ? resolveLink(href)
        : null;
    if (resolved != null && children.isNotEmpty) {
      final annotation = resolved.destination != null
          ? pw.AnnotationLink(resolved.destination!)
          : pw.AnnotationUrl(resolved.url!);
      out.add(pw.TextSpan(annotation: annotation, children: children));
    } else {
      out.addAll(children);
    }
  }

  void _addText(
    List<pw.InlineSpan> out,
    String raw,
    EpubStyle style, {
    required bool spanBackground,
  }) {
    if (raw.isEmpty) return;
    final preserve = style.whiteSpacePre;
    var text = normalizeEpubText(raw, preserveWhitespace: preserve);
    if (text.isEmpty) return;
    if (!preserve) {
      if (_pendingSpace && text.startsWith(' ')) {
        text = text.substring(1);
      }
      if (text.isEmpty) return;
      _pendingSpace = text.endsWith(' ');
    } else {
      _pendingSpace = false;
    }
    out.add(
      _textSpan(
        text,
        style,
        spanBackground: spanBackground,
      ),
    );
  }

  pw.TextSpan _textSpan(
    String text,
    EpubStyle style, {
    bool spanBackground = false,
  }) {
    final baseline = style.superscript
        ? style.fontSize * 0.35
        : (style.subscript ? -style.fontSize * 0.2 : 0.0);
    return pw.TextSpan(
      text: text,
      baseline: baseline,
      style: _textStyle(style, spanBackground: spanBackground),
    );
  }

  pw.TextStyle _textStyle(
    EpubStyle style, {
    bool spanBackground = false,
  }) {
    final lineSpacing = (style.lineHeightFactor - 1) * style.fontSize;
    return pw.TextStyle(
      fontSize: style.fontSize,
      color: style.color,
      fontWeight: style.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      fontStyle: style.italic ? pw.FontStyle.italic : pw.FontStyle.normal,
      lineSpacing: lineSpacing > 0 ? lineSpacing : 0,
      decoration: _textDecoration(style),
      background: spanBackground && style.background != null
          ? pw.BoxDecoration(color: style.background)
          : null,
    );
  }

  pw.TextDecoration? _textDecoration(EpubStyle style) {
    if (!style.underline && !style.lineThrough) return null;
    final decorations = <pw.TextDecoration>[
      if (style.underline) pw.TextDecoration.underline,
      if (style.lineThrough) pw.TextDecoration.lineThrough,
    ];
    return decorations.length == 1
        ? decorations.single
        : pw.TextDecoration.combine(decorations);
  }

  void _trimTrailingSpace(List<pw.InlineSpan> spans) {
    for (var index = spans.length - 1; index >= 0; index--) {
      final span = spans[index];
      if (span is! pw.TextSpan) continue;
      final children = span.children;
      if (children != null && children.isNotEmpty) {
        _trimTrailingSpace(children);
        return;
      }
      final text = span.text;
      if (text == null || text.isEmpty) continue;
      if (text.endsWith(' ')) {
        spans[index] = pw.TextSpan(
          text: text.substring(0, text.length - 1),
          style: span.style,
          baseline: span.baseline,
          annotation: span.annotation,
        );
      }
      return;
    }
  }

  // Containers -------------------------------------------------------------

  void _renderContainer(dom.Element element, EpubStyle style) {
    if (style.breakBefore) _pendingBreak = true;
    final topSpace = style.marginTop + style.paddingTop;
    if (topSpace > 0) _addSpacer(topSpace);

    final decoration = _decorationFor(element);
    if (decoration != null) _pendingDecorations.add(decoration);

    final savedIndent = _indent;
    final savedBackground = _background;
    _indent += style.marginLeft + style.paddingLeft;
    if (style.background != null) _background = style.background;

    _renderContents(element, style);

    _indent = savedIndent;
    _background = savedBackground;
    if (decoration != null && _pendingDecorations.contains(decoration)) {
      _pendingDecorations.remove(decoration);
    }

    final bottomSpace = style.marginBottom + style.paddingBottom;
    if (bottomSpace > 0) _addSpacer(bottomSpace);
    if (style.breakAfter) _pendingBreak = true;
  }

  // Lists ------------------------------------------------------------------

  void _renderList(dom.Element list, EpubStyle style) {
    if (style.breakBefore) _pendingBreak = true;
    final topSpace = style.marginTop + style.paddingTop;
    if (topSpace > 0) _addSpacer(topSpace);

    final ordered = list.localName == 'ol';
    var itemIndex = int.tryParse((list.attributes['start'] ?? '').trim()) ?? 1;
    final savedIndent = _indent;
    _indent += 14;

    for (final item in list.children) {
      if (item.localName != 'li') continue;
      _renderListItem(item, style, ordered, itemIndex);
      itemIndex++;
    }

    _indent = savedIndent;
    final bottomSpace = style.marginBottom + style.paddingBottom;
    if (bottomSpace > 0) _addSpacer(bottomSpace);
    if (style.breakAfter) _pendingBreak = true;
  }

  void _renderListItem(
    dom.Element item,
    EpubStyle listStyle,
    bool ordered,
    int index,
  ) {
    final style = _styleFor(item, listStyle);
    if (_hidden(item, style)) return;

    final decoration = _decorationFor(item);
    if (decoration != null) _pendingDecorations.add(decoration);

    final type =
        style.listStyleType ??
        listStyle.listStyleType ??
        (ordered ? 'decimal' : 'disc');
    final marker = _listMarker(type, index);
    final markerSpan = marker.isEmpty
        ? null
        : _textSpan('$marker\u00A0', style);

    final inline = <dom.Node>[];
    final blocks = <dom.Element>[];
    for (final node in item.nodes) {
      if (node is dom.Element && _isBlock(node, style)) {
        blocks.add(node);
      } else if (node is dom.Text) {
        if (node.data.trim().isNotEmpty) inline.add(node);
      } else if (node is dom.Element) {
        inline.add(node);
      }
    }

    final hasInline = inline.isNotEmpty;
    if (hasInline) {
      _pendingSpace = true;
      final spans = <pw.InlineSpan>[
        ?markerSpan,
        ..._inlineChildren(inline, style),
      ];
      _trimTrailingSpace(spans);
      _appendBlock(
        pw.RichText(
          text: pw.TextSpan(children: spans),
          textAlign: style.textAlign,
          overflow: pw.TextOverflow.span,
        ),
        style,
      );
    } else if (blocks.isNotEmpty && markerSpan != null) {
      final first = blocks.first;
      final firstStyle = _styleFor(first, style);
      final isParagraph =
          first.localName == 'p' ||
          RegExp(r'^h[1-6]$').hasMatch(first.localName ?? '');
      if (isParagraph &&
          !_hidden(first, firstStyle) &&
          !_hasBlockChildren(first, firstStyle)) {
        blocks.removeAt(0);
        _renderParagraph(first, firstStyle, prefix: [markerSpan]);
      } else {
        _appendBlock(
          pw.RichText(text: pw.TextSpan(children: [markerSpan])),
          style,
          applyBox: false,
        );
      }
    }

    for (final block in blocks) {
      if (block.localName == 'ul' || block.localName == 'ol') {
        _renderList(block, style);
      } else {
        _renderBlock(block, style);
      }
    }

    if (decoration != null && _pendingDecorations.contains(decoration)) {
      _pendingDecorations.remove(decoration);
    }
  }

  String _listMarker(String type, int index) {
    switch (type) {
      case 'none':
        return '';
      case 'circle':
        return '\u25E6';
      case 'square':
        return '\u25AA';
      case 'decimal':
        return '$index.';
      case 'decimal-leading-zero':
        return index < 10 ? '0$index.' : '$index.';
      case 'lower-alpha':
      case 'lower-latin':
        return '${_alphaMarker(index).toLowerCase()}.';
      case 'upper-alpha':
      case 'upper-latin':
        return '${_alphaMarker(index)}.';
      case 'lower-roman':
        return '${_romanMarker(index).toLowerCase()}.';
      case 'upper-roman':
        return '${_romanMarker(index)}.';
      case 'disc':
      default:
        return '\u2022';
    }
  }

  String _alphaMarker(int index) {
    if (index <= 0) return '';
    var value = index;
    final buffer = StringBuffer();
    while (value > 0) {
      value--;
      buffer.writeCharCode(0x41 + value % 26);
      value ~/= 26;
    }
    return String.fromCharCodes(buffer.toString().codeUnits.reversed);
  }

  String _romanMarker(int index) {
    if (index <= 0 || index > 3999) return '$index';
    const values = <int>[
      1000,
      900,
      500,
      400,
      100,
      90,
      50,
      40,
      10,
      9,
      5,
      4,
      1,
    ];
    const symbols = <String>[
      'M',
      'CM',
      'D',
      'CD',
      'C',
      'XC',
      'L',
      'XL',
      'X',
      'IX',
      'V',
      'IV',
      'I',
    ];
    final buffer = StringBuffer();
    var remaining = index;
    for (var i = 0; i < values.length; i++) {
      while (remaining >= values[i]) {
        buffer.write(symbols[i]);
        remaining -= values[i];
      }
    }
    return buffer.toString();
  }

  // Media and special blocks ----------------------------------------------

  void _renderHorizontalRule(dom.Element element, EpubStyle style) {
    _appendBlock(
      pw.Divider(
        color: style.color,
        thickness: 0.6,
        height: style.marginTop + style.marginBottom > 0
            ? style.fontSize
            : 12,
      ),
      style,
      decorations: _decorationFor(element),
    );
  }

  void _renderPre(dom.Element element, EpubStyle style) {
    var text = element.text;
    if (text.startsWith('\n')) text = text.substring(1);
    final normalized = normalizeEpubText(text, preserveWhitespace: true);
    if (normalized.trim().isEmpty) return;
    _appendBlock(
      pw.Container(
        padding: const pw.EdgeInsets.all(4),
        color: PdfColors.grey100,
        child: pw.RichText(
          text: pw.TextSpan(children: [_textSpan(normalized, style)]),
          overflow: pw.TextOverflow.span,
        ),
      ),
      style,
      decorations: _decorationFor(element),
    );
  }

  void _renderImage(dom.Element element, EpubStyle style) {
    final image = _loadImage(element);
    if (image == null) return;
    _appendBlock(
      pw.Align(
        alignment: pw.Alignment.center,
        child: _imageWidget(image, element, inline: false),
      ),
      style,
      decorations: _decorationFor(element),
    );
  }

  /// Draws the raster an SVG element wraps, if any.
  ///
  /// SVG rasterization is out of scope, but EPUB covers are routinely exported
  /// as a single `<image xlink:href="cover.jpg">` inside an SVG element that
  /// only exists to carry the page box; the inner raster is drawn through the
  /// regular image path, rotation mapping and all.
  void _renderSvgImage(dom.Element element, EpubStyle parentStyle) {
    final imageElement = _svgRasterImage(element);
    if (imageElement == null) return;
    final style = _styleFor(element, parentStyle);
    if (_hidden(element, style)) return;
    final image = _loadImage(imageElement);
    if (image == null) return;
    _appendBlock(
      pw.Align(
        alignment: pw.Alignment.center,
        child: _imageWidget(image, imageElement, inline: false),
      ),
      style,
      decorations: _decorationFor(element),
    );
  }

  /// The first raster `<image>` inside [svg], or null for vector-only SVG.
  dom.Element? _svgRasterImage(dom.Element svg) {
    for (final node in svg.querySelectorAll('image')) {
      if ((node.localName ?? '') != 'image') continue;
      final href = _attribute(node, 'xlink:href') ?? _attribute(node, 'href');
      if (href == null || href.trim().isEmpty) continue;
      if (resolveArchivePath(docPath, href.trim()) == null) continue;
      return node;
    }
    return null;
  }

  /// An attribute by qualified name.
  ///
  /// `package:html` keys namespaced attributes (`xlink:href`) by an
  /// [dom.AttributeName], so a plain map lookup misses them; the qualified
  /// name still matches through [Object.toString].
  static String? _attribute(dom.Element element, String name) {
    final direct = element.attributes[name];
    if (direct != null) return direct;
    for (final entry in element.attributes.entries) {
      if (entry.key.toString() == name) return entry.value;
    }
    return null;
  }

  _LoadedImage? _loadImage(dom.Element element) {
    final raw =
        _attribute(element, 'src') ??
        _attribute(element, 'xlink:href') ??
        _attribute(element, 'href');
    if (raw == null || raw.trim().isEmpty) return null;
    final path = resolveArchivePath(docPath, raw.trim());
    if (path == null) return null;
    if (_imageCache.containsKey(path)) return _imageCache[path];
    final file = book.archive.findFile(path);
    final image = loadEpubImage(book.archive, path);
    final loaded = image == null
        ? null
        : _LoadedImage(
            image: image,
            orientation: file == null
                ? ScanOrientation.unknown
                : scanOrientations[file.name] ?? ScanOrientation.unknown,
          );
    _imageCache[path] = loaded;
    return loaded;
  }

  pw.Widget _imageWidget(
    _LoadedImage loaded,
    dom.Element element, {
    required bool inline,
  }) {
    final image = loaded.image;
    final naturalWidth = (image.width ?? 1).toDouble() * kCssPxToPt;
    final naturalHeight = (image.height ?? 1).toDouble() * kCssPxToPt;
    if (naturalWidth <= 0 || naturalHeight <= 0) return pw.SizedBox.shrink();

    final maxWidth = contentWidth;
    final maxHeight = inline ? contentHeight * 0.6 : contentHeight;

    // A sideways page scan is turned upright and laid out at its natural
    // (corrected) size: its width/height attributes describe the stored
    // raster, not the page. `rotateBox` swaps the layout box accordingly.
    final angle = switch (loaded.orientation) {
      ScanOrientation.rotateClockwise => -math.pi / 2,
      ScanOrientation.rotateCounterClockwise => math.pi / 2,
      ScanOrientation.unknown || ScanOrientation.upright => null,
    };
    if (angle != null) {
      final displayedWidth = naturalHeight;
      final displayedHeight = naturalWidth;
      final scale = _fitScale(
        displayedWidth,
        displayedHeight,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );
      final turned = pw.Transform.rotateBox(
        angle: angle,
        child: pw.Image(
          image,
          width: naturalWidth * scale,
          height: naturalHeight * scale,
          fit: pw.BoxFit.contain,
        ),
      );
      if (inline) return turned;
      // A turned page scan keeps its page to itself: it is laid out inside a
      // full-content-height box (centred, like a viewer shows a landscape scan
      // in a portrait window) so the next scan starts on a fresh page instead
      // of stacking under it at half the size. The box is a hair shorter than
      // the content area: exactly matching it can round to "does not fit" in
      // MultiPage pagination, which loops until the page limit.
      return pw.SizedBox(
        height: math.max(1, contentHeight - 0.5),
        child: pw.Center(child: turned),
      );
    }

    var width = naturalWidth;
    var height = naturalHeight;
    final attrWidth = _cssSize(element.attributes['width']);
    final attrHeight = _cssSize(element.attributes['height']);
    if (attrWidth != null && attrWidth > 0) {
      width = attrWidth;
      height = naturalHeight * width / naturalWidth;
    }
    if (attrHeight != null && attrHeight > 0) {
      height = attrHeight;
      if (attrWidth == null) width = naturalWidth * height / naturalHeight;
    }

    final scale = _fitScale(
      width,
      height,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
    return pw.Image(
      image,
      width: width * scale,
      height: height * scale,
      fit: pw.BoxFit.contain,
    );
  }

  /// The scale that fits a [width]×[height] box into the [maxWidth]×[maxHeight]
  /// content area, leaving a hair of slack on the binding side.
  ///
  /// `a * (b / a)` is not exactly `b`: a scale computed from the exact limit
  /// can lay the widget out one floating-point step over it, and a layout box
  /// even one ULP taller than the page makes `pdf`'s MultiPage refuse the
  /// whole chapter ("widget won't fit into the page"). Staying 0.1pt inside is
  /// invisible but cannot round past the limit.
  double _fitScale(
    double width,
    double height, {
    required double maxWidth,
    required double maxHeight,
  }) {
    const slack = 0.1;
    return math.min(
      1.0,
      math.min((maxWidth - slack) / width, (maxHeight - slack) / height),
    );
  }

  double? _cssSize(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    return cssLengthToPt(
      raw,
      fontSize: kEpubBaseFontSize,
      percentBase: kEpubContentWidth,
    );
  }

  // Tables ----------------------------------------------------------------

  void _renderTable(dom.Element element, EpubStyle style) {
    final rows = <pw.TableRow>[];

    void addRows(dom.Element parent, {required bool header}) {
      for (final child in parent.children) {
        switch (child.localName) {
          case 'thead':
            addRows(child, header: true);
          case 'tbody':
          case 'tfoot':
            addRows(child, header: false);
          case 'tr':
            final cells = <pw.Widget>[];
            for (final cell in child.children) {
              if (cell.localName != 'td' && cell.localName != 'th') continue;
              final cellStyle = _styleFor(cell, style);
              if (cellStyle.display == 'none') continue;
              final isHeader = cell.localName == 'th';
              cells.add(
                pw.Container(
                  padding: const pw.EdgeInsets.all(3),
                  color: isHeader ? PdfColors.grey200 : null,
                  child: pw.RichText(
                    text: pw.TextSpan(
                      children: _cellSpans(cell, cellStyle),
                    ),
                    textAlign: cellStyle.textAlign,
                  ),
                ),
              );
            }
            if (cells.isNotEmpty) {
              rows.add(pw.TableRow(children: cells, repeat: header));
            }
        }
      }
    }

    addRows(element, header: false);
    if (rows.isEmpty) return;
    _appendBlock(
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.4),
        defaultColumnWidth: const pw.FlexColumnWidth(),
        children: rows,
      ),
      style,
      decorations: _decorationFor(element),
    );
  }

  List<pw.InlineSpan> _cellSpans(dom.Element cell, EpubStyle style) {
    final out = <pw.InlineSpan>[];
    _pendingSpace = true;

    void visit(dom.Node node, EpubStyle current) {
      if (node is dom.Text) {
        _addText(out, node.data, current, spanBackground: false);
        return;
      }
      if (node is! dom.Element) return;
      final tag = node.localName ?? '';
      if (tag == 'br') {
        out.add(const pw.TextSpan(text: '\n'));
        _pendingSpace = true;
        return;
      }
      final childStyle = _styleFor(node, current);
      if (_hidden(node, childStyle)) return;
      if (tag == 'img') {
        final image = _loadImage(node);
        if (image != null) {
          out.add(
            pw.WidgetSpan(child: _imageWidget(image, node, inline: true)),
          );
        }
        return;
      }
      if (tag == 'table') return;
      final childBlock =
          isDefaultBlockTag(tag) ||
          childStyle.display == 'block' ||
          childStyle.display == 'list-item';
      if (childBlock && out.isNotEmpty) {
        out.add(const pw.TextSpan(text: '\n'));
        _pendingSpace = true;
      }
      for (final inner in node.nodes) {
        visit(inner, childStyle);
      }
      if (childBlock) {
        out.add(const pw.TextSpan(text: '\n'));
        _pendingSpace = true;
      }
    }

    for (final node in cell.nodes) {
      visit(node, style);
    }
    _trimTrailingSpace(out);
    while (out.isNotEmpty) {
      final first = out.first;
      if (first is pw.TextSpan && (first.text?.trim().isEmpty ?? true)) {
        out.removeAt(0);
      } else {
        break;
      }
    }
    while (out.isNotEmpty) {
      final last = out.last;
      if (last is pw.TextSpan && (last.text?.trim().isEmpty ?? true)) {
        out.removeLast();
      } else {
        break;
      }
    }
    return out;
  }
}
