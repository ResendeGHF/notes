// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:saber/data/editor/canvas_background_pattern.dart';
import 'package:saber/components/canvas/_canvas_background_painter.dart';
import 'package:saber/components/canvas/canvas_image.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
import 'package:saber/data/extensions/color_extensions.dart';

class CanvasBackgroundPreview extends StatelessWidget {
  const CanvasBackgroundPreview({
    super.key,
    required this.selected,
    required this.invert,
    required this.backgroundColor,
    required this.backgroundPattern,
    required this.backgroundImage,
    this.overrideBoxFit,
    required this.pageSize,
  required this.lineHeight,
  required this.lineThickness,
  this.lineColor,
  this.width,
  this.marginLeft,
  this.marginRight,
  this.marginTop,
  this.marginBottom,
    this.borderColor,
    this.previewContentFit,
  });

  final bool selected;
  final bool invert;
  final Color? backgroundColor;
  final CanvasBackgroundPattern backgroundPattern;
  final EditorImage? backgroundImage;
  final BoxFit? overrideBoxFit;
  final Size pageSize;
  final int lineHeight;
  final int lineThickness;
  final Color? lineColor;

  final double? width;

  final double? marginLeft;
  final double? marginRight;
  final double? marginTop;
  final double? marginBottom;

  final Color? borderColor;

  /// When set (e.g. [BoxFit.fill]), scales the painted preview to fill the
  /// preview box without letterboxing. Defaults to [BoxFit.contain].
  final BoxFit? previewContentFit;

  static const double fixedWidth = 150;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final w = width ?? fixedWidth;
    final previewSize = Size(
      w,
      pageSize.height / pageSize.width * w,
    );
    final canvasSize = pageSize / 2;
    return Container(
      width: previewSize.width,
      height: previewSize.height,
      decoration: BoxDecoration(
        border: Border.all(
          color: colorScheme.primary
              .withSaturation(selected ? 1 : 0)
              .withValues(alpha: selected ? 1 : 0.1),
          width: 2,
        ),
        borderRadius: .circular(8),
      ),
      child: ClipRRect(
        borderRadius: .circular(8),
        child: Stack(
          children: [
            FittedBox(
              fit: previewContentFit ?? BoxFit.contain,
              child: CustomPaint(
                size: canvasSize,
                painter: CanvasBackgroundPainter(
                  invert: invert,
                  backgroundColor: () {
                    if (backgroundImage != null) {
                      return Colors.white;
                    } else {
                      return InnerCanvas.getBackgroundColor(context, backgroundColor);
                    }
                  }(),
                  backgroundPattern: () {
                    if (backgroundImage != null) {
                      return CanvasBackgroundPattern.none;
                    } else {
                      return backgroundPattern;
                    }
                  }(),
                  lineHeight: lineHeight,
                  lineThickness: lineThickness,
                  primaryColor: lineColor ?? colorScheme.primary
                      .withSaturation(selected ? 1 : 0)
                      .withValues(alpha: selected ? 1 : 0.5),
                  secondaryColor: (lineColor ?? colorScheme.secondary)
                      .withSaturation(selected ? 1 : 0)
                      .withValues(alpha: selected ? 1 : 0.5),
                  preview: true,
                  marginLeft: (marginLeft ?? 0) * (canvasSize.width / pageSize.width),
                  marginRight: (marginRight ?? 0) * (canvasSize.width / pageSize.width),
                  marginTop: (marginTop ?? 0) * (canvasSize.height / pageSize.height),
                  marginBottom: (marginBottom ?? 0) * (canvasSize.height / pageSize.height),
                  borderColor: borderColor,
                ),
              ),
            ),
            if (backgroundImage != null)
              CanvasImage(
                filePath: '',
                image: backgroundImage!,
                overrideBoxFit: overrideBoxFit,
                pageSize: previewSize,
                setAsBackground: null,
                isBackground: true,
                readOnly: true,
              ),
          ],
        ),
      ),
    );
  }
}
