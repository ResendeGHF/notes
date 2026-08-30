// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui';

import 'package:logging/logging.dart';
import 'package:pdfrx/pdfrx.dart';

class PdfLink {
  final Rect rect;
  final List<Rect> rects;
  final int? targetPageIndex;
  final Rect? targetRegion;
  final String? uri;

  PdfLink({
    required this.rect,
    List<Rect>? rects,
    this.targetPageIndex,
    this.targetRegion,
    this.uri,
  }) : rects = rects ?? (rect == Rect.zero ? const <Rect>[] : <Rect>[rect]);

  bool contains(Offset position) {
    if (rects.isNotEmpty) {
      return rects.any((r) => r.contains(position));
    }
    return rect.contains(position);
  }
}

class PdfLinkDetector {
  static final log = Logger('PdfLinkDetector');

  static Future<List<PdfLink>> detectLinksOnPage(
    PdfDocument pdfDocument,
    int pageIndex,
  ) async {
    try {
      if (pdfDocument.pages.isEmpty) {
        return [];
      }
      if (pageIndex < 0 || pageIndex >= pdfDocument.pages.length) {
        return [];
      }

      // Progressive loading: loadLinks() returns [] until the page is fully
      // loaded. Wait so highlights appear on first open, not only after a
      // remount (sidebar/scroll).
      final page = await pdfDocument.pages[pageIndex].ensureLoaded();
      final pdfrxLinks = await page.loadLinks();
      final double pageWidth = page.width;

      return pdfrxLinks.map((link) {
        int? targetPage;
        Rect? targetRect;
        String? uri;

        if (link.dest != null) {
          targetPage = link.dest!.pageNumber - 1;

          if (link.dest!.params != null && link.dest!.params!.length >= 2) {
            final double? destTop = link.dest!.params![1];

            if (destTop != null) {
              const double contextHeight = 150.0;
              const double contextAbove = 50.0;

              targetRect = Rect.fromLTRB(
                0,
                destTop - contextHeight,
                pageWidth,
                destTop + contextAbove,
              );
            }
          }
        } else if (link.url != null) {
          uri = link.url.toString();
        }

        final normalizedRects = <Rect>[];
        for (final r in link.rects) {
          normalizedRects.add(
            Rect.fromLTRB(
              r.left < r.right ? r.left : r.right,
              r.top < r.bottom ? r.top : r.bottom,
              r.left < r.right ? r.right : r.left,
              r.top < r.bottom ? r.bottom : r.top,
            ),
          );
        }

        final linkRect = normalizedRects.isNotEmpty
            ? normalizedRects.first
            : Rect.zero;

        return PdfLink(
          rect: linkRect,
          rects: normalizedRects,
          targetPageIndex: targetPage,
          targetRegion: targetRect,
          uri: uri,
        );
      }).toList();
    } catch (e, stackTrace) {
      final errStr = e.toString();
      if (!errStr.contains('not yet loaded')) {
        log.warning(
          'Failed to detect links on page $pageIndex: $e',
          e,
          stackTrace,
        );
      }
      return [];
    }
  }

  static Future<PdfLink?> findLinkAtPosition(
    PdfDocument pdfDocument,
    int pageIndex,
    Offset position,
  ) async {
    final links = await detectLinksOnPage(pdfDocument, pageIndex);
    for (final link in links) {
      if (link.contains(position)) {
        return link;
      }
    }
    return null;
  }

  /// Maps a PDF-space rect (origin bottom-left) into widget/local space
  /// (origin top-left) for the rendered page.
  static Rect pdfRectToWidgetRect(
    Rect pdfRect,
    Size widgetSize,
    Size pdfNaturalSize,
  ) {
    if (widgetSize.isEmpty || pdfNaturalSize.isEmpty) return Rect.zero;
    final scaleX = widgetSize.width / pdfNaturalSize.width;
    final scaleY = widgetSize.height / pdfNaturalSize.height;
    final top = (pdfNaturalSize.height - pdfRect.bottom) * scaleY;
    final bottom = (pdfNaturalSize.height - pdfRect.top) * scaleY;
    return Rect.fromLTRB(
      pdfRect.left * scaleX,
      top,
      pdfRect.right * scaleX,
      bottom,
    );
  }

  static Offset widgetToPdfCoordinates(
    Offset widgetPosition,
    Size widgetSize,
    Size pdfNaturalSize,
  ) {
    if (widgetSize.width == 0 || widgetSize.height == 0) return Offset.zero;

    final scaleX = pdfNaturalSize.width / widgetSize.width;
    final scaleY = pdfNaturalSize.height / widgetSize.height;

    final pdfX = widgetPosition.dx * scaleX;

    final scaledTouchY = widgetPosition.dy * scaleY;
    final pdfY = pdfNaturalSize.height - scaledTouchY;

    return Offset(pdfX, pdfY);
  }
}
