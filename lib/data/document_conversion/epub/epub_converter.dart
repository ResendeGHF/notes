// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// EPUB -> PDF conversion.
//
// Normalizes an EPUB to a PDF that reuses the app's PDF pipeline (pdfrx
// rendering, outline navigation, link handling) instead of a bespoke reader:
//
// - every renderable spine document becomes a `pw.MultiPage` laid out on A5
//   portrait, in reading order;
// - the EPUB table of contents becomes the PDF outline (`pw.Outline` widgets
//   attach entries to their target blocks as they are laid out, so navigation
//   lands on the right page even when a target sits mid-chapter);
// - internal links become named-destination link annotations resolved through
//   element ids, external links become URI annotations;
// - [EpubConversionResult.outline] carries the laid-out outline tree so the
//   app can pre-seed `EditorCoreInfo.pdfOutlines` exactly like the DjVu
//   importer, without a second pdfrx extraction pass.
//
// The conversion is pure Dart (the `pdf` widget layer has no Flutter
// dependencies), so callers can run it in an isolate.

import 'dart:typed_data';

// html is pulled in through the pdf package rather than declared directly.
// ignore_for_file: depend_on_referenced_packages

import 'package:html/dom.dart' as dom;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:saber/data/document_conversion/epub/epub_css.dart';
import 'package:saber/data/document_conversion/epub/epub_document.dart';
import 'package:saber/data/document_conversion/epub/epub_parser.dart';
import 'package:saber/data/document_conversion/scan_orientation.dart';

/// Highest number of A5 pages a single spine document may produce before the
/// layout is treated as broken (a widget that can never fit keeps generating
/// pages forever).
const kEpubMaxPagesPerChapter = 10000;

/// Fonts used for EPUB text, as raw TrueType data.
///
/// The app loads `assets/google_fonts/Atkinson_Hyperlegible_Next/` and passes
/// the bytes in; with every font null the built-in Helvetica family is used,
/// which keeps tests and minimal environments independent of asset bundles.
class EpubPdfOptions {
  const EpubPdfOptions({
    this.regularFont,
    this.boldFont,
    this.italicFont,
    this.boldItalicFont,
    this.scanOrientations = const {},
  });

  final ByteData? regularFont;
  final ByteData? boldFont;
  final ByteData? italicFont;
  final ByteData? boldItalicFont;

  /// Orientation corrections for sideways page scans, keyed by archive entry
  /// name (`ArchiveFile.name`), as produced by `detectEpubScanOrientations`.
  /// Images without an entry are laid out exactly as stored.
  final Map<String, ScanOrientation> scanOrientations;

  /// Copy of these options with [scanOrientations] replaced.
  EpubPdfOptions withScanOrientations(
    Map<String, ScanOrientation> orientations,
  ) {
    return EpubPdfOptions(
      regularFont: regularFont,
      boldFont: boldFont,
      italicFont: italicFont,
      boldItalicFont: boldItalicFont,
      scanOrientations: orientations,
    );
  }
}

/// One entry of the converted document's outline, with its page index.
class EpubOutlineEntry {
  const EpubOutlineEntry({
    required this.title,
    required this.pageIndex,
    this.children,
  });

  final String title;
  final int pageIndex;
  final List<EpubOutlineEntry>? children;
}

/// The PDF and outline of a converted EPUB.
class EpubConversionResult {
  EpubConversionResult({
    required this.pdf,
    required this.outline,
    required this.pageCount,
  });

  /// The complete PDF file.
  final Uint8List pdf;

  /// The table of contents with resolved page indices, for the app's outline
  /// navigation.
  final List<EpubOutlineEntry> outline;

  /// Number of pages in the document.
  final int pageCount;
}

/// Converts an EPUB file into a PDF document.
///
/// Throws [EpubConversionException] when the file is not a readable EPUB or
/// has no renderable content.
Future<EpubConversionResult> convertEpubToPdf(
  Uint8List bytes, {
  EpubPdfOptions options = const EpubPdfOptions(),
}) async {
  final book = parseEpub(bytes);
  final registry = EpubAnchorRegistry();

  // Pass 1: parse every renderable spine document, claim its anchor names and
  // read its stylesheets. Rendering happens in pass 3, once the table of
  // contents has been resolved in pass 2.
  final chapters = <_EpubChapter>[];
  for (final item in book.spine) {
    final manifestItem = item.item;
    final path = manifestItem?.href;
    if (manifestItem == null || path == null) continue;
    if (!isXhtmlMediaType(manifestItem.mediaType)) continue;
    final rawBytes = book.archive.readFile(path);
    if (rawBytes == null) continue;
    final document = parseEpubHtml(decodeEpubText(rawBytes));
    if (document == null) continue;

    final scan = scanEpubDocument(document);
    final anchorNames = <String, String>{};
    for (final id in scan.ids) {
      // Ids are unique within a document; the name also encodes the spine
      // index, so claiming can only fail for a duplicate spine entry.
      final name = epubAnchorName(item.index, id);
      if (registry.claim(name)) anchorNames[id] = name;
    }
    // The start-of-chapter destination is painted by the first rendered block
    // of the chapter; claim it so `EpubAnchor` publishes it.
    registry.claim(epubTopAnchorName(item.index));

    chapters.add(
      _EpubChapter(
        spineIndex: item.index,
        docPath: path,
        document: document,
        stylesheet: loadEpubStylesheet(book, path, document),
        anchorNames: anchorNames,
      ),
    );
  }

  if (chapters.isEmpty) {
    throw const EpubConversionException('EPUB has no readable spine documents');
  }

  final chapterBySpine = <int, _EpubChapter>{
    for (final chapter in chapters) chapter.spineIndex: chapter,
  };
  final spineByPath = <String, int>{};
  for (final chapter in chapters) {
    spineByPath.putIfAbsent(chapter.docPath, () => chapter.spineIndex);
  }

  // Pass 2: resolve the table of contents into outline targets. Entries
  // pointing at a document outside the spine (or at an id that was never
  // claimed) fall back to the start of their chapter, so no TOC entry is lost.
  final idTargets = <int, Map<String, List<EpubOutlineTarget>>>{};
  final topTargets = <int, List<EpubOutlineTarget>>{};

  void addTarget(_EpubChapter chapter, String fragment, String title, int level) {
    final name =
        chapter.anchorNames[fragment] ?? epubTopAnchorName(chapter.spineIndex);
    final target = EpubOutlineTarget(anchor: name, title: title, level: level);
    if (name == epubTopAnchorName(chapter.spineIndex)) {
      (topTargets[chapter.spineIndex] ??= []).add(target);
    } else {
      ((idTargets[chapter.spineIndex] ??= {})[fragment] ??= []).add(target);
    }
  }

  void walkToc(List<EpubTocEntry> entries, int level) {
    for (final entry in entries) {
      final title = entry.title.trim();
      final path = resolveArchivePath(book.tocBasePath, entry.href);
      final spineIndex = path == null ? null : spineByPath[path];
      if (title.isNotEmpty && spineIndex != null) {
        final fragment = decodeHref(splitHref(entry.href.trim()).fragment);
        addTarget(chapterBySpine[spineIndex]!, fragment, title, level);
      }
      walkToc(entry.children, level + 1);
    }
  }

  walkToc(book.toc, 0);

  // Pass 3: render. One MultiPage per chapter keeps page breaks and anchor
  // resolution per document; the returned outline tree is already laid out.
  final document = pw.Document(
    title: book.title.isEmpty ? null : book.title,
    author: book.author.isEmpty ? null : book.author,
    theme: _epubTheme(options),
    // PDF 1.4 keeps the classic cross-reference table, matching the DjVu
    // writer's output and every reader; 1.5 only adds a compressed xref here.
    version: PdfVersion.pdf_1_4,
  );
  const portraitFormat = PdfPageFormat(kEpubPageWidth, kEpubPageHeight);
  const landscapeFormat = PdfPageFormat(kEpubPageHeight, kEpubPageWidth);
  const margin = pw.EdgeInsets.all(kEpubPageMargin);

  for (final chapter in chapters) {
    final builder = EpubChapterBuilder(
      book: book,
      spineIndex: chapter.spineIndex,
      docPath: chapter.docPath,
      document: chapter.document,
      stylesheet: chapter.stylesheet,
      registry: registry,
      anchorNames: chapter.anchorNames,
      outlineTargets: idTargets[chapter.spineIndex] ?? const {},
      topOutlineTargets: topTargets[chapter.spineIndex] ?? const [],
      resolveLink: (href) => _resolveLink(
        book: book,
        chapter: chapter,
        href: href,
        spineByPath: spineByPath,
        chapterBySpine: chapterBySpine,
      ),
      scanOrientations: options.scanOrientations,
    );
    final widgets = builder.build();
    if (widgets.isEmpty) continue;
    // A chapter that is one sideways landscape scan per page is laid out
    // landscape, so the corrected scans fill their pages. The builder takes
    // care of the widget geometry; the page format is applied here.
    final landscape = builder.prefersLandscapePages;
    try {
      document.addPage(
        pw.MultiPage(
          pageFormat: landscape ? landscapeFormat : portraitFormat,
          margin: margin,
          maxPages: kEpubMaxPagesPerChapter,
          build: (context) => widgets,
        ),
      );
    } on EpubConversionException {
      rethrow;
    } catch (e) {
      throw EpubConversionException(
        'Failed to render ${chapter.docPath}: $e',
      );
    }
  }

  final pageCount = document.document.pdfPageList.pages.length;
  if (pageCount == 0) {
    throw const EpubConversionException('EPUB has no renderable content');
  }

  final pdf = await document.save();
  return EpubConversionResult(
    pdf: pdf,
    outline: _readOutline(document.document.outline),
    pageCount: pageCount,
  );
}

/// One renderable spine document with its pre-computed rendering state.
class _EpubChapter {
  _EpubChapter({
    required this.spineIndex,
    required this.docPath,
    required this.document,
    required this.stylesheet,
    required this.anchorNames,
  });

  final int spineIndex;
  final String docPath;
  final dom.Document document;
  final EpubCssStylesheet stylesheet;

  /// Element id -> claimed named destination.
  final Map<String, String> anchorNames;
}

/// Resolves an href written in [chapter] to a PDF link.
///
/// Only targets that will actually be painted are kept: links to documents
/// outside the spine and to unknown fragments are dropped (a dangling named
/// destination is worse than no link).
EpubResolvedLink? _resolveLink({
  required EpubBook book,
  required _EpubChapter chapter,
  required String href,
  required Map<String, int> spineByPath,
  required Map<int, _EpubChapter> chapterBySpine,
}) {
  final raw = href.trim();
  if (raw.isEmpty) return null;

  if (hrefHasScheme(raw)) {
    final lower = raw.toLowerCase();
    if (lower.startsWith('javascript:') ||
        lower.startsWith('data:') ||
        lower.startsWith('file:')) {
      return null;
    }
    return EpubResolvedLink.external(raw);
  }

  final parts = splitHref(raw);
  final fragment = decodeHref(parts.fragment);
  if (parts.path.isEmpty) {
    // Same-document link.
    if (fragment.isEmpty) return null;
    final name = chapter.anchorNames[fragment];
    return name == null ? null : EpubResolvedLink.destination(name);
  }

  final path = resolveArchivePath(chapter.docPath, raw);
  final spineIndex = path == null ? null : spineByPath[path];
  if (spineIndex == null) return null;
  if (fragment.isEmpty) {
    return EpubResolvedLink.destination(epubTopAnchorName(spineIndex));
  }
  final name = chapterBySpine[spineIndex]!.anchorNames[fragment];
  return name == null ? null : EpubResolvedLink.destination(name);
}

/// Builds the theme: the supplied TTFs, or the built-in Helvetica family.
///
/// Helvetica is always kept as a fallback so characters outside the supplied
/// font (e.g. a stray CJK glyph) render instead of being dropped.
pw.ThemeData _epubTheme(EpubPdfOptions options) {
  final regular = options.regularFont;
  if (regular == null) return pw.ThemeData.base();

  pw.Font font(ByteData? data) => pw.Font.ttf(data ?? regular);
  return pw.ThemeData.withFont(
    base: font(regular),
    bold: font(options.boldFont),
    italic: font(options.italicFont),
    boldItalic: font(options.boldItalicFont),
    fontFallback: [pw.Font.helvetica()],
  );
}

/// Copies the laid-out PDF outline into the app-facing tree.
List<EpubOutlineEntry> _readOutline(PdfOutline root) {
  return [
    for (final node in root.outlines)
      EpubOutlineEntry(
        title: node.title ?? '',
        pageIndex: _outlinePageIndex(node),
        children: node.outlines.isEmpty ? null : _readOutline(node),
      ),
  ];
}

int _outlinePageIndex(PdfOutline node) {
  final page = int.tryParse(node.page ?? '');
  if (page == null) return 0;
  return page - 1 < 0 ? 0 : page - 1;
}
