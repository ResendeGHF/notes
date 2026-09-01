// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart' hide PdfLink;
import 'package:saber/components/editor/pdf_link_detector.dart';
import 'package:saber/components/canvas/invert_widget.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:url_launcher/url_launcher.dart';

class PdfEquationPreview extends StatelessWidget {
  const PdfEquationPreview({
    super.key,
    required this.pdfDocument,
    required this.pageIndex,
    required this.region,
    required this.onDismiss,
    required this.onGoToLocation,
    required this.onLinkTapped,
    this.maxWidth,
    this.invert = false,
  });

  final PdfDocument pdfDocument;
  final int pageIndex;
  final Rect region;
  final VoidCallback onDismiss;
  final ValueChanged<int> onGoToLocation;
  final Function(PdfLink) onLinkTapped;

  final double? maxWidth;
  final bool invert;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;

    final page = pdfDocument.pages[pageIndex];
    final double pageHeight = page.height;
    final double pageWidth = page.width;

    final double verticalPadding = region.height * 0.5;
    final double cropHeight = region.height + (verticalPadding * 2);

    final double pdfCenterY = region.center.dy;
    final double flutterCenterY = pageHeight - pdfCenterY;

    double cropTop = flutterCenterY - (cropHeight / 2);

    if (cropTop < 0) cropTop = 0;
    if (cropTop + cropHeight > pageHeight) cropTop = pageHeight - cropHeight;

    final double availableWidth = maxWidth != null ? maxWidth! : size.width;
    final double targetWidth = availableWidth * 0.95;
    double scale = targetWidth / pageWidth;

    final Size renderedFullPageSize = Size(
      pageWidth * scale,
      pageHeight * scale,
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.opaque,
            child: Container(color: Colors.black.withValues(alpha: 0.5)),
          ),
        ),
        Center(
          child: Container(
            width: targetWidth,
            constraints: BoxConstraints(
              maxHeight: size.height * 0.85,
              minHeight: 100,
            ),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(28),
            ),
            clipBehavior: Clip.hardEdge,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.8,
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.3,
                        ),
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.preview_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Page ${pageIndex + 1}',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () {
                              onGoToLocation(pageIndex);
                              onDismiss();
                            },
                            icon: const AdaptiveIcon(
                              icon: Icons.arrow_forward,
                              cupertinoIcon: CupertinoIcons.arrow_right,
                              size: 16,
                            ),
                            label: const Text('Go to'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              minimumSize: const Size(0, 36),
                              backgroundColor: colorScheme.primaryContainer,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: onDismiss,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor:
                                  colorScheme.surfaceContainerHighest,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: InvertWidget(
                    invert: invert,
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      controller: ScrollController(
                        initialScrollOffset: cropTop * scale,
                      ),
                      child: GestureDetector(
                        onTapUp: (details) {
                          final localTap = details.localPosition;
                          final effectiveTapOnPage = localTap;

                          final pdfPosition =
                              PdfLinkDetector.widgetToPdfCoordinates(
                                effectiveTapOnPage,
                                renderedFullPageSize,
                                Size(page.width, page.height),
                              );

                          PdfLinkDetector.findLinkAtPosition(
                            pdfDocument,
                            pageIndex,
                            pdfPosition,
                          ).then((link) async {
                            if (link != null) {
                              if (link.uri != null) {
                                final url = Uri.parse(link.uri!);
                                if (await canLaunchUrl(url)) {
                                  await launchUrl(
                                    url,
                                    mode: LaunchMode.externalApplication,
                                  );
                                }
                              } else {
                                onLinkTapped(link);
                              }
                            }
                          });
                        },
                        child: PdfPageView(
                          document: pdfDocument,
                          pageNumber: pageIndex + 1,
                          alignment: Alignment.topCenter,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
