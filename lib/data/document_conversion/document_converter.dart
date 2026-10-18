// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Entry point for importing non-PDF documents.
//
// The app only knows how to display PDFs (pdfrx rendering, PDF links, PDF
// outlines), so `.djvu` and `.epub` files are normalized to PDF at import
// time. `createNoteFromPdf` then handles the note exactly like a PDF import;
// the outline returned here pre-seeds the note's Pages menu without a second
// extraction pass.
//
// Conversion is pure Dart, so it runs in a background isolate to keep large
// books from blocking the UI. The returned model is deliberately Flutter-free
// (the isolate must not depend on the UI layer).

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:saber/data/document_conversion/djvu/djvu_converter.dart';
import 'package:saber/data/document_conversion/djvu/djvu_navm.dart';
import 'package:saber/data/document_conversion/epub/epub_converter.dart';
import 'package:saber/data/document_conversion/epub/epub_scan_probe.dart';

/// Document formats the import pipeline accepts.
enum DocumentFormat {
  /// Passed through untouched; only listed so callers can share one switch.
  pdf,

  /// DjVu (`.djvu` / `.djv`), converted with the built-in decoder.
  djvu,

  /// EPUB 2/3, laid out into PDF pages with the built-in renderer.
  epub,
}

/// Detects the format of [path] from its extension.
///
/// Returns null for files the import pipeline does not handle.
DocumentFormat? documentFormatForPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return null;
  switch (path.substring(dot + 1).toLowerCase()) {
    case 'pdf':
      return DocumentFormat.pdf;
    case 'djvu':
    case 'djv':
      return DocumentFormat.djvu;
    case 'epub':
      return DocumentFormat.epub;
    default:
      return null;
  }
}

/// One entry of a converted document's outline, with a 0-based page index.
class ConvertedOutlineEntry {
  const ConvertedOutlineEntry({
    required this.title,
    required this.pageIndex,
    this.children = const [],
  });

  final String title;
  final int pageIndex;
  final List<ConvertedOutlineEntry> children;
}

/// The PDF and outline produced by [convertDocumentToPdf].
class ConvertedDocument {
  ConvertedDocument({
    required this.pdf,
    required this.pageCount,
    required this.outline,
    this.outputPath,
  });

  /// The normalized PDF.
  ///
  /// Empty when [outputPath] is set: the conversion then writes the file
  /// itself, inside the isolate, so the bytes never cross isolate boundaries
  /// (for a 60 MB scan that is the difference between a smooth import and a
  /// multi-second main-thread copy and flush).
  final Uint8List pdf;

  /// Number of pages in [pdf].
  final int pageCount;

  /// The document's outline, already resolved to page indices.
  final List<ConvertedOutlineEntry> outline;

  /// Where the PDF was written when the caller asked for file output.
  final String? outputPath;
}

/// Converts a `.djvu`/`.epub` file into a PDF.
///
/// [bytes] must be the whole document. The conversion runs in a background
/// isolate unless [useIsolate] is false (tests).
///
/// EPUB scan orientation needs a file path for its pre-pass, so callers of
/// this variant are expected to pass [EpubPdfOptions.scanOrientations]
/// themselves; [convertDocumentFileToPdf] detects them automatically.
///
/// Throws [DjvuDocumentException], [EpubConversionException] or
/// [ArgumentError] when the input cannot be converted.
Future<ConvertedDocument> convertDocumentToPdf(
  Uint8List bytes, {
  required DocumentFormat format,
  EpubPdfOptions epubOptions = const EpubPdfOptions(),
  bool autoOrientScans = true,
  String? outputPath,
  bool useIsolate = true,
}) {
  _checkFormat(format);

  Future<ConvertedDocument> convert() => _convert(
    bytes,
    format,
    epubOptions,
    autoOrientScans: autoOrientScans,
    outputPath: outputPath,
  );

  return useIsolate ? Isolate.run(convert) : convert();
}

/// Converts a `.djvu`/`.epub` file into a PDF, reading it inside the isolate.
///
/// Prefer this over [convertDocumentToPdf] in the app: large DjVu scans stay
/// out of the UI isolate's heap.
///
/// [autoOrientScans] reviews the pages before conversion and corrects scans
/// that are stored sideways (see `scan_orientation.dart`). For EPUB this runs
/// a pre-pass on the caller's isolate — the engine's native image codecs are
/// only available there — which yields between images and takes well under a
/// second for a few hundred scans; DjVu detection runs inside the conversion
/// isolate on the bitmaps it decodes anyway.
///
/// When [outputPath] is set the conversion writes the PDF straight to that
/// path (from inside the isolate) and [ConvertedDocument.pdf] is empty.
///
/// [onScanProgress] reports `(done, total)` for the EPUB pre-pass, if any.
Future<ConvertedDocument> convertDocumentFileToPdf(
  String path, {
  required DocumentFormat format,
  EpubPdfOptions epubOptions = const EpubPdfOptions(),
  bool autoOrientScans = true,
  String? outputPath,
  void Function(int done, int total)? onScanProgress,
  bool useIsolate = true,
}) async {
  _checkFormat(format);

  // A caller-provided orientation map (tests, caching) wins over detection.
  var options = epubOptions;
  if (format == DocumentFormat.epub &&
      autoOrientScans &&
      options.scanOrientations.isEmpty) {
    final orientations = await detectEpubScanOrientations(
      path,
      onProgress: onScanProgress,
    );
    options = options.withScanOrientations(orientations);
  }

  Future<ConvertedDocument> convert() async => _convert(
    await File(path).readAsBytes(),
    format,
    options,
    autoOrientScans: autoOrientScans,
    outputPath: outputPath,
  );

  return useIsolate ? Isolate.run(convert) : convert();
}

void _checkFormat(DocumentFormat format) {
  if (format == DocumentFormat.pdf) {
    throw ArgumentError.value(
      format,
      'format',
      'PDF input needs no conversion',
    );
  }
}

Future<ConvertedDocument> _convert(
  Uint8List bytes,
  DocumentFormat format,
  EpubPdfOptions epubOptions, {
  required bool autoOrientScans,
  String? outputPath,
}) async {
  switch (format) {
    case DocumentFormat.pdf:
      throw ArgumentError.value(
        format,
        'format',
        'PDF input needs no conversion',
      );
    case DocumentFormat.djvu:
      final result = convertDjvuToPdf(
        bytes,
        options: DjvuPdfOptions(autoOrientScans: autoOrientScans),
      );
      return _finish(
        result.pdf,
        result.pageCount,
        _mapDjvuOutline(result.bookmarks, result.pageCount),
        outputPath,
      );
    case DocumentFormat.epub:
      final result = await convertEpubToPdf(bytes, options: epubOptions);
      return _finish(
        result.pdf,
        result.pageCount,
        _mapEpubOutline(result.outline),
        outputPath,
      );
  }
}

/// Returns the conversion result, writing the PDF to [outputPath] when asked.
///
/// The write happens here so it runs in the conversion isolate: the caller's
/// isolate only ever sees the file path. `flush: false` is deliberate — the
/// note pipeline reads the file back right away (page cache), and forcing the
/// bytes to disk would only add latency.
Future<ConvertedDocument> _finish(
  Uint8List pdf,
  int pageCount,
  List<ConvertedOutlineEntry> outline,
  String? outputPath,
) async {
  if (outputPath == null) {
    return ConvertedDocument(
      pdf: pdf,
      pageCount: pageCount,
      outline: outline,
    );
  }
  await File(outputPath).writeAsBytes(pdf, flush: false);
  return ConvertedDocument(
    pdf: Uint8List(0),
    pageCount: pageCount,
    outline: outline,
    outputPath: outputPath,
  );
}

/// Maps DjVu NAVM bookmarks to outline entries.
///
/// Entries that do not point inside the document (external URLs, bare
/// anchors, out-of-range pages) are dropped; their children are promoted so a
/// broken parent does not hide a whole section.
List<ConvertedOutlineEntry> _mapDjvuOutline(
  List<DjvuBookmark> bookmarks,
  int pageCount,
) {
  final out = <ConvertedOutlineEntry>[];
  for (final bookmark in bookmarks) {
    final children = _mapDjvuOutline(bookmark.children, pageCount);
    final index = bookmarkPageIndex(bookmark.url);
    if (index == null || index < 0 || index >= pageCount) {
      out.addAll(children);
      continue;
    }
    out.add(
      ConvertedOutlineEntry(
        title: bookmark.title,
        pageIndex: index,
        children: children,
      ),
    );
  }
  return out;
}

List<ConvertedOutlineEntry> _mapEpubOutline(List<EpubOutlineEntry> entries) {
  return [
    for (final entry in entries)
      ConvertedOutlineEntry(
        title: entry.title,
        pageIndex: entry.pageIndex,
        children: _mapEpubOutline(entry.children ?? const []),
      ),
  ];
}
