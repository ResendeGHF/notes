// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:saber/data/editor/canvas_background_pattern.dart';
import 'package:saber/data/extensions/color_extensions.dart';

class CanvasBackgroundPainter extends CustomPainter {
  const CanvasBackgroundPainter({
    required this.invert,
    required this.backgroundColor,
    this.backgroundPattern = .none,
    required this.lineHeight,
    required this.lineThickness,
    this.primaryColor = Colors.blue,
    this.secondaryColor = Colors.red,
    this.preview = false,
    this.marginLeft = 0,
    this.marginRight = 0,
    this.marginTop = 0,
    this.marginBottom = 0,
    this.borderColor,
  });

  final bool invert;
  final Color backgroundColor;

  final Color? borderColor;

  final CanvasBackgroundPattern backgroundPattern;

  final int lineHeight;
  final int lineThickness;
  final Color primaryColor, secondaryColor;

  final bool preview;

  final double marginLeft;
  final double marginRight;
  final double marginTop;
  final double marginBottom;

  @override
  void paint(Canvas canvas, Size size) {
    final canvasRect = Offset.zero & size;
    final paint = Paint();

    final innerLeft = marginLeft.clamp(0.0, size.width - 1);
    final innerRight = (size.width - marginRight).clamp(
      innerLeft + 1,
      size.width,
    );
    final innerTop = marginTop.clamp(0.0, size.height - 1);
    final innerBottom = (size.height - marginBottom).clamp(
      innerTop + 1,
      size.height,
    );
    final hasMargins =
        innerLeft > 0 ||
        innerRight < size.width ||
        innerTop > 0 ||
        innerBottom < size.height;

    if (hasMargins) {
      final borderCol = (borderColor ?? backgroundColor).withInversion(invert);
      paint.color = borderCol;
      canvas.drawRect(canvasRect, paint);
    }

    paint.color = backgroundColor.withInversion(invert);
    if (hasMargins) {
      canvas.drawRect(
        Rect.fromLTRB(innerLeft, innerTop, innerRight, innerBottom),
        paint,
      );
    } else {
      canvas.drawRect(canvasRect, paint);
    }

    paint.strokeWidth = lineThickness.toDouble();
    final innerSize = Size(innerRight - innerLeft, innerBottom - innerTop);
    final innerOffset = Offset(innerLeft, innerTop);

    if (innerSize.width > 0 && innerSize.height > 0) {
      canvas.save();
      canvas.translate(innerOffset.dx, innerOffset.dy);

      if (backgroundPattern.requiresClipping) {
        canvas.save();
        canvas.clipRect(Offset.zero & innerSize);
      }

      for (final element in getPatternElements(
        pattern: backgroundPattern,
        size: innerSize,
        lineHeight: lineHeight,
      )) {
        final baseColor = element.secondaryColor
            ? secondaryColor
            : primaryColor;
        paint.color = baseColor
            .withInversion(invert)
            .withValues(alpha: preview ? 0.5 : 0.2);

        if (element.isLine) {
          canvas.drawLine(element.start, element.end, paint);
        } else {
          canvas.drawCircle(element.start, paint.strokeWidth * 4 / 3, paint);
        }
      }

      if (backgroundPattern.requiresClipping) {
        canvas.restore();
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(CanvasBackgroundPainter oldDelegate) =>
      kDebugMode ||
      oldDelegate.invert != invert ||
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.backgroundPattern != backgroundPattern ||
      oldDelegate.lineHeight != lineHeight ||
      oldDelegate.lineThickness != lineThickness ||
      oldDelegate.marginLeft != marginLeft ||
      oldDelegate.marginRight != marginRight ||
      oldDelegate.marginTop != marginTop ||
      oldDelegate.marginBottom != marginBottom ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.primaryColor != primaryColor ||
      oldDelegate.secondaryColor != secondaryColor;

  static Iterable<PatternElement> getPatternElements({
    required CanvasBackgroundPattern pattern,
    required Size size,
    required int lineHeight,
  }) sync* {
    switch (pattern) {
      case .none:
        return;
      case .collegeLtr:
      case .collegeRtl:
      case .lined:
        for (double y = lineHeight * 2; y < size.height; y += lineHeight) {
          yield PatternElement(
            Offset(0, y),
            Offset(size.width, y),
            isLine: true,
          );
        }

        if (pattern == .collegeLtr) {
          yield PatternElement(
            Offset(lineHeight * 2, 0),
            Offset(lineHeight * 2, size.height),
            isLine: true,
            secondaryColor: true,
          );
        } else if (pattern == .collegeRtl) {
          yield PatternElement(
            Offset(size.width - lineHeight * 2, 0),
            Offset(size.width - lineHeight * 2, size.height),
            isLine: true,
            secondaryColor: true,
          );
        }
      case .grid:
        for (double y = 0; y < size.height; y += lineHeight) {
          yield PatternElement(
            Offset(0, y),
            Offset(size.width, y),
            isLine: true,
          );
        }

        for (double x = 0; x < size.width; x += lineHeight) {
          yield PatternElement(
            Offset(x, 0),
            Offset(x, size.height),
            isLine: true,
          );
        }
      case .dots:
        for (double y = lineHeight * 2; y <= size.height; y += lineHeight) {
          for (double x = 0; x <= size.width; x += lineHeight) {
            yield PatternElement(Offset(x, y), Offset(x, y), isLine: false);
          }
        }
      case .staffs:
      case .tablature:
        final staffSpaces = pattern == .staffs ? 4 : 5;
        final staffHeight = lineHeight * staffSpaces;
        final staffSpacing = lineHeight * 3;

        for (
          double topOfStaff = staffSpacing.toDouble() - lineHeight;
          topOfStaff + staffHeight < size.height;
          topOfStaff += staffHeight + staffSpacing
        ) {
          for (int line = 0; line < staffSpaces + 1; line++) {
            yield PatternElement(
              Offset(lineHeight.toDouble(), topOfStaff + lineHeight * line),
              Offset(size.width - lineHeight, topOfStaff + lineHeight * line),
              isLine: true,
            );
          }

          yield PatternElement(
            Offset(lineHeight.toDouble(), topOfStaff),
            Offset(lineHeight.toDouble(), topOfStaff + staffHeight),
            isLine: true,
          );
          yield PatternElement(
            Offset(size.width - lineHeight, topOfStaff),
            Offset(size.width - lineHeight, topOfStaff + staffHeight),
            isLine: true,
          );
        }
      case .cornell:
        yield PatternElement(
          Offset(lineHeight.toDouble(), lineHeight * 2),
          Offset(size.width / 2 - lineHeight / 2, lineHeight * 2),
          isLine: true,
        );

        yield PatternElement(
          Offset(size.width / 2 + lineHeight / 2, lineHeight * 2),
          Offset(size.width - lineHeight, lineHeight * 2),
          isLine: true,
        );

        yield PatternElement(
          Offset(lineHeight.toDouble(), lineHeight * 3),
          Offset(size.width - lineHeight, lineHeight * 3),
          isLine: true,
        );

        final left = size.width * 0.35;
        final bottom = size.height * 0.7;
        for (double y = lineHeight * 5; y < bottom; y += lineHeight) {
          yield PatternElement(
            Offset(left, y),
            Offset(size.width - lineHeight, y),
            isLine: true,
          );
        }
      case .calligraphy:
        const double tan55 = 1.428;
        final double slantOffset = size.height / tan55;
        final double slantSpacing = lineHeight * 2.0;

        for (double x = -slantOffset; x < size.width; x += slantSpacing) {
          yield PatternElement(
            Offset(x + slantOffset, 0),
            Offset(x, size.height),
            isLine: true,
            secondaryColor: true,
          );
        }

        final double h = lineHeight.toDouble();
        final double blockHeight = h * 3;

        for (double y = h * 2; y < size.height; y += blockHeight) {
          yield PatternElement(
            Offset(0, y),
            Offset(size.width, y),
            isLine: true,
            secondaryColor: true,
          );

          yield PatternElement(
            Offset(0, y + h),
            Offset(size.width, y + h),
            isLine: true,
            secondaryColor: true,
          );

          yield PatternElement(
            Offset(0, y + h * 2),
            Offset(size.width, y + h * 2),
            isLine: true,
            secondaryColor: false,
          );

          yield PatternElement(
            Offset(0, y + h * 3),
            Offset(size.width, y + h * 3),
            isLine: true,
            secondaryColor: true,
          );
        }

      case .calligraphyRegular:
        final double h = lineHeight.toDouble();

        // Increased blockHeight to 2.5 to provide a distinct gap between the blocks,
        // mimicking standard handwriting practice paper.
        final double blockHeight = h * 2.5;

        for (double y = h; y < size.height; y += blockHeight) {
          // Top solid line
          yield PatternElement(
            Offset(0, y),
            Offset(size.width, y),
            isLine: true,
            secondaryColor: false,
          );

          // First middle dashed line
          for (double x = 0; x < size.width; x += h * 0.4) {
            double endX = x + h * 0.2;
            if (endX > size.width) endX = size.width;
            yield PatternElement(
              Offset(x, y + h * 0.5),
              Offset(endX, y + h * 0.5),
              isLine: true,
              secondaryColor: true,
            );
          }

          // Second middle dashed line
          for (double x = 0; x < size.width; x += h * 0.4) {
            double endX = x + h * 0.2;
            if (endX > size.width) endX = size.width;
            yield PatternElement(
              Offset(x, y + h * 1.0),
              Offset(endX, y + h * 1.0),
              isLine: true,
              secondaryColor: true,
            );
          }

          // Bottom solid line
          yield PatternElement(
            Offset(0, y + h * 1.5),
            Offset(size.width, y + h * 1.5),
            isLine: true,
            secondaryColor: false,
          );
        }
    }
  }
}

class PatternElement {
  final Offset start, end;
  final bool isLine;
  final bool secondaryColor;

  PatternElement(
    this.start,
    this.end, {
    this.isLine = true,
    this.secondaryColor = false,
  });
}
