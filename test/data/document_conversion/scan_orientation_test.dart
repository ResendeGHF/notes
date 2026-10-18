// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Orientation scorer tests. The grids are synthetic but shaped like the real
// thing: left-aligned bars with a ragged right edge standing in for text
// lines, on paper-white background.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/document_conversion/scan_orientation.dart';

/// Draws a text-like page: [lines] left-aligned dark bars with varying
/// lengths, all starting at the same left margin.
ScanInkGrid textGrid({
  int rows = 120,
  int cols = 90,
  int lines = 12,
  double leftMargin = 0.12,
}) {
  final values = Float32List(rows * cols);
  final margin = (cols * leftMargin).round();
  final first = rows ~/ (lines + 1);
  final bar = (rows / (lines * 3.0)).round().clamp(1, rows);
  final step = (rows - 2 * first) ~/ lines;
  for (var i = 0; i < lines; i++) {
    final y0 = first + i * step;
    // Ragged right edge, shrinking towards the bottom like a real paragraph.
    final length = margin + ((cols - margin) * (0.95 - 0.5 * i / lines)).round();
    for (var y = y0; y < y0 + bar && y < rows; y++) {
      for (var x = 0; x < length && x < cols; x++) {
        values[y * cols + x] = 1;
      }
    }
  }
  return ScanInkGrid(rows, cols, values);
}

/// A grid with the same ink density everywhere: no projection signal at all
/// (the checker texture stands in for two-column indexes and sparse figures).
///
/// Both sides are multiples of the texture period so every row and column
/// mean is exactly the same, which is what makes this the "no verdict" case
/// rather than a weak upright one.
ScanInkGrid textureGrid({int rows = 120, int cols = 88}) {
  final values = Float32List(rows * cols);
  for (var y = 0; y < rows; y++) {
    for (var x = 0; x < cols; x++) {
      if ((x + y) % 8 < 3) values[y * cols + x] = 1;
    }
  }
  return ScanInkGrid(rows, cols, values);
}

/// Rotates [grid] 90° the same way the scorer does, for building inputs.
ScanInkGrid rotateGrid(ScanInkGrid grid, {required bool clockwise}) {
  final rows = grid.cols;
  final cols = grid.rows;
  final values = Float32List(rows * cols);
  for (var y = 0; y < grid.rows; y++) {
    for (var x = 0; x < grid.cols; x++) {
      final value = grid.at(y, x);
      if (clockwise) {
        values[x * cols + (grid.rows - 1 - y)] = value;
      } else {
        values[(grid.cols - 1 - x) * cols + y] = value;
      }
    }
  }
  return ScanInkGrid(rows, cols, values);
}

void main() {
  group('ScanInkGrid', () {
    test('samples large images down to the grid resolution', () {
      final grid = ScanInkGrid.sample(
        width: 1000,
        height: 500,
        inkAt: (x, y) => 0,
      );
      expect(grid.cols, kScanInkGridMaxSide);
      expect(grid.rows, kScanInkGridMaxSide ~/ 2);
      expect(grid.values.length, grid.rows * grid.cols);
    });

    test('never upscales small images', () {
      final grid = ScanInkGrid.sample(
        width: 40,
        height: 20,
        inkAt: (x, y) => 0,
      );
      expect(grid.cols, 40);
      expect(grid.rows, 20);
    });

    test('averages ink over each block', () {
      // Total ink is preserved: half the page is ink.
      final grid = ScanInkGrid.sample(
        width: 200,
        height: 100,
        inkAt: (x, y) => x < 100 ? 1 : 0,
      );
      var total = 0.0;
      for (final value in grid.values) {
        total += value;
      }
      expect(total / (grid.rows * grid.cols), closeTo(0.5, 0.02));
    });

    test('fromPixels keeps the image size', () {
      final grid = ScanInkGrid.fromPixels(4, 3, (x, y) => x == y ? 1 : 0);
      expect(grid.rows, 3);
      expect(grid.cols, 4);
      expect(grid.at(1, 1), 1);
      expect(grid.at(1, 0), 0);
    });
  });

  group('scoreScanOrientation', () {
    test('horizontal text lines read as upright', () {
      expect(
        scoreScanOrientation(textGrid()),
        ScanOrientation.upright,
      );
    });

    test('a page stored clockwise is turned counter-clockwise', () {
      final stored = rotateGrid(textGrid(), clockwise: true);
      expect(
        scoreScanOrientation(stored),
        ScanOrientation.rotateCounterClockwise,
      );
    });

    test('a page stored counter-clockwise is turned clockwise', () {
      final stored = rotateGrid(textGrid(), clockwise: false);
      expect(
        scoreScanOrientation(stored),
        ScanOrientation.rotateClockwise,
      );
    });

    test('a page stored upside down still reads as horizontal', () {
      // 180° cannot be told apart from upright by line direction; the scorer
      // must not claim a 90° turn.
      final stored = rotateGrid(
        rotateGrid(textGrid(), clockwise: true),
        clockwise: true,
      );
      expect(
        scoreScanOrientation(stored),
        ScanOrientation.upright,
      );
    });

    test('a blank page has no verdict', () {
      final blank = ScanInkGrid(60, 40, Float32List(60 * 40));
      final score = scoreScanOrientationDetailed(blank);
      expect(score.orientation, ScanOrientation.unknown);
      expect(score.isInconclusive, isFalse);
    });

    test('flat grey stays below the contrast gate', () {
      final grey = ScanInkGrid(
        60,
        40,
        Float32List.fromList(List.filled(60 * 40, 0.5)),
      );
      expect(
        scoreScanOrientation(grey),
        ScanOrientation.unknown,
      );
    });

    test('projection-less ink is inconclusive, not upright', () {
      final score = scoreScanOrientationDetailed(textureGrid());
      expect(score.orientation, ScanOrientation.unknown);
      expect(score.contrast, greaterThanOrEqualTo(kScanMinContrast));
      expect(score.isInconclusive, isTrue);
    });

    test('reports the signals behind the verdict', () {
      final score = scoreScanOrientationDetailed(textGrid());
      expect(score.orientation, ScanOrientation.upright);
      expect(score.contrast, greaterThan(0.5));
      expect(score.rowSignal, greaterThan(kScanProfileFloor));
      expect(score.rowSignal, greaterThan(score.colSignal));
    });
  });

  group('scanCorrectedIsLandscape', () {
    test('keeps dimensions for upright pages', () {
      expect(
        scanCorrectedIsLandscape(500, 700, ScanOrientation.upright),
        isFalse,
      );
      expect(
        scanCorrectedIsLandscape(700, 500, ScanOrientation.upright),
        isTrue,
      );
    });

    test('swaps dimensions for rotated pages', () {
      final clockwise = ScanOrientation.rotateClockwise;
      expect(scanCorrectedIsLandscape(500, 700, clockwise), isTrue);
      expect(scanCorrectedIsLandscape(700, 500, clockwise), isFalse);
      expect(
        scanCorrectedIsLandscape(500, 700, ScanOrientation.rotateCounterClockwise),
        isTrue,
      );
    });

    test('unknown orientations are treated as stored', () {
      expect(
        scanCorrectedIsLandscape(500, 700, ScanOrientation.unknown),
        isFalse,
      );
    });
  });
}
