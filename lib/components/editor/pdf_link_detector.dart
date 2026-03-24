// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui';

import 'package:logging/logging.dart';
import 'package:pdfrx/pdfrx.dart';

class PdfLink {
  final Rect rect;
  final int? targetPageIndex;
  final Rect? targetRegion;
  final String? uri;

  PdfLink({
    required this.rect,
    this.targetPageIndex,
    this.targetRegion,
    this.uri,
  });
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

      final page = pdfDocument.pages[pageIndex];
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

              const double contextHeight =
                  150.0;
              const double contextAbove =
                  50.0;

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

        Rect linkRect = Rect.zero;
        if (link.rects.isNotEmpty) {
          final r = link.rects.first;
          linkRect = Rect.fromLTRB(
            r.left < r.right ? r.left : r.right,
            r.top < r.bottom ? r.top : r.bottom,
            r.left < r.right ? r.right : r.left,
            r.top < r.bottom ? r.bottom : r.top,
          );
        }

        return PdfLink(
          rect: linkRect,
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
      if (link.rect.contains(position)) {
        return link;
      }
    }
    return null;
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
