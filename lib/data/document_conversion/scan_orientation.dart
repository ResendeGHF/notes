// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Scan orientation detection.
//
// Scanned books are sometimes stored with the page images turned 90°: the text
// runs bottom-to-top or top-to-bottom, and every viewer shows the page
// sideways unless the file's metadata says otherwise (DjVu has a rotation tag,
// EPUB scan images usually have nothing at all). This module scores a small
// "ink grid" sampled from the page and decides whether the text lines already
// run horizontally, and, when they do not, which way to turn the page.
//
// The primary signal is the classic projection profile: horizontal text
// produces alternating dark rows (the line bands) and near-constant columns,
// vertical text the other way around. The magnitude of the total variation of
// each projection separates the two by a wide margin on real scans.
//
// A second, weaker signal picks the direction of a 90° turn: left-aligned
// paragraphs leave a sharp left edge in the column profile, so of the two
// candidate rotations the one whose left margin is sharper is the readable
// one. Pages without that asymmetry (centered text, figures, blank pages)
// fall back to clockwise, which is what a sideways scan almost always needs.
//
// Everything here is pure Dart: it runs inside the conversion isolate for DjVu
// (on the decoded bitmaps) and on engine-decoded previews on the root isolate
// for EPUB (where `dart:ui` is required and only available there).

import 'dart:math' as math;
import 'dart:typed_data';

/// How a scanned page must be turned to be read.
enum ScanOrientation {
  /// No confident verdict (blank page, photo, too little contrast); leave the
  /// page as stored.
  unknown,

  /// Text lines already run horizontally.
  upright,

  /// Text runs vertically; turn the page 90° clockwise.
  rotateClockwise,

  /// Text runs vertically the other way; turn the page 90° counter-clockwise.
  rotateCounterClockwise,
}

/// Long side of the ink grid, in samples. Sized for speed: 160 px is enough
/// for the row/column projections to separate 20+ text lines.
const kScanInkGridMaxSide = 160;

/// Minimum p95−p5 spread of the ink grid for a verdict. Below this the page is
/// blank or flat (photo, solid colour) and the profile carries no signal.
const kScanMinContrast = 0.15;

/// How much stronger one projection must be than the other to count as text
/// lines. Real scans score 2–9× on the correct axis.
const kScanProfileRatio = 1.6;

/// Absolute floor for the winning projection. Guards near-blank pages whose
/// tiny noise can still be imbalanced.
const kScanProfileFloor = 0.5;

/// Darkness above which a sample counts as ink when cropping to the text
/// block. Scans separate ink (~0.8-1.0) from paper (~0.0-0.3) widely.
const _kInkThreshold = 0.35;

/// One sample of a page, downscaled to an ink-density grid.
///
/// Values are 0 (paper) to 1 (full ink), row-major from the top-left, in the
/// stored orientation of the page.
class ScanInkGrid {
  ScanInkGrid(this.rows, this.cols, this.values);

  /// Grid height, in samples.
  final int rows;

  /// Grid width, in samples.
  final int cols;

  /// `rows * cols` ink values, row-major.
  final Float32List values;

  /// Ink at ([row], [col]). No bounds checking.
  double at(int row, int col) => values[row * cols + col];

  /// Builds a grid by averaging up to 3x3 samples per cell of the source
  /// image described by [inkAt] (`x` right, `y` down, both in pixels).
  ///
  /// The grid is only ever downscaled: an image smaller than [maxSide] keeps
  /// its pixel size.
  static ScanInkGrid sample({
    required int width,
    required int height,
    required double Function(int x, int y) inkAt,
    int maxSide = kScanInkGridMaxSide,
  }) {
    assert(width > 0 && height > 0);
    final longest = math.max(width, height);
    final scale = math.min(1.0, maxSide / longest);
    final cols = math.max(1, (width * scale).round());
    final rows = math.max(1, (height * scale).round());
    final values = Float32List(rows * cols);
    const perAxis = 3;
    for (var row = 0; row < rows; row++) {
      final y0 = row * height ~/ rows;
      final y1 = math.max(y0 + 1, (row + 1) * height ~/ rows);
      for (var col = 0; col < cols; col++) {
        final x0 = col * width ~/ cols;
        final x1 = math.max(x0 + 1, (col + 1) * width ~/ cols);
        var sum = 0.0;
        for (var sy = 0; sy < perAxis; sy++) {
          final y = y0 + ((y1 - y0) * (2 * sy + 1)) ~/ (2 * perAxis);
          for (var sx = 0; sx < perAxis; sx++) {
            final x = x0 + ((x1 - x0) * (2 * sx + 1)) ~/ (2 * perAxis);
            sum += inkAt(x, y);
          }
        }
        values[row * cols + col] = sum / (perAxis * perAxis);
      }
    }
    return ScanInkGrid(rows, cols, values);
  }

  /// Builds a 1:1 grid from an already-small ink image.
  ///
  /// Used for previews that were decoded at grid resolution by the engine, so
  /// there is nothing left to average.
  static ScanInkGrid fromPixels(
    int width,
    int height,
    double Function(int x, int y) inkAt,
  ) {
    final values = Float32List(width * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        values[y * width + x] = inkAt(x, y);
      }
    }
    return ScanInkGrid(height, width, values);
  }
}

/// Whether a stored [width]x[height] image with [orientation] reads as a
/// landscape picture once corrected.
bool scanCorrectedIsLandscape(
  int width,
  int height,
  ScanOrientation orientation,
) {
  final rotated =
      orientation == ScanOrientation.rotateClockwise ||
      orientation == ScanOrientation.rotateCounterClockwise;
  return rotated ? height > width : width > height;
}

/// Scores [grid] and returns the turn needed to display it upright.
ScanOrientation scoreScanOrientation(ScanInkGrid grid) =>
    scoreScanOrientationDetailed(grid).orientation;

/// Detailed score of an ink grid: the verdict plus the signals behind it.
class ScanOrientationScore {
  const ScanOrientationScore({
    required this.orientation,
    required this.contrast,
    required this.rowSignal,
    required this.colSignal,
  });

  /// The verdict, or [ScanOrientation.unknown] when the projections did not
  /// separate text lines.
  final ScanOrientation orientation;

  /// p95−p5 spread of the ink values (0-1).
  final double contrast;

  /// Total variation of the row and column projections, the signal behind the
  /// verdict.
  final double rowSignal;
  final double colSignal;

  /// Whether the page carries ink but the projections stayed ambiguous.
  ///
  /// Two-column pages (indexes, tables) and sparse figures look like this.
  /// Callers that can see a whole document may adopt its majority rotation
  /// for such pages; nothing about the page itself says which way is up.
  bool get isInconclusive =>
      orientation == ScanOrientation.unknown && contrast >= kScanMinContrast;
}

/// Scores [grid] and reports the verdict together with its signals.
ScanOrientationScore scoreScanOrientationDetailed(ScanInkGrid grid) {
  final contrast = _contrastSpread(grid);
  final rowSignal = _profileVariation(grid, alongRows: true);
  final colSignal = _profileVariation(grid, alongRows: false);

  ScanOrientation orientation;
  if (contrast < kScanMinContrast) {
    orientation = ScanOrientation.unknown;
  } else if (colSignal > kScanProfileRatio * rowSignal &&
      colSignal > kScanProfileFloor) {
    // Text runs along the columns: the page is stored sideways. Pick the
    // readable direction by the sharper left margin of the two candidates.
    final clockwise = _rotated(grid, clockwise: true);
    final counter = _rotated(grid, clockwise: false);
    orientation = _leftMarginScore(clockwise) >= _leftMarginScore(counter)
        ? ScanOrientation.rotateClockwise
        : ScanOrientation.rotateCounterClockwise;
  } else if (rowSignal > kScanProfileRatio * colSignal &&
      rowSignal > kScanProfileFloor) {
    orientation = ScanOrientation.upright;
  } else {
    orientation = ScanOrientation.unknown;
  }

  return ScanOrientationScore(
    orientation: orientation,
    contrast: contrast,
    rowSignal: rowSignal,
    colSignal: colSignal,
  );
}

/// p95−p5 spread of the ink values, from a 256-bin histogram.
double _contrastSpread(ScanInkGrid grid) {
  final histogram = Int32List(256);
  for (final value in grid.values) {
    var bin = (value * 255).round();
    if (bin < 0) {
      bin = 0;
    } else if (bin > 255) {
      bin = 255;
    }
    histogram[bin]++;
  }
  final total = grid.values.length;
  final p5 = _histogramPercentile(histogram, total, 0.05);
  final p95 = _histogramPercentile(histogram, total, 0.95);
  return (p95 - p5) / 255.0;
}

int _histogramPercentile(Int32List histogram, int total, double fraction) {
  final target = (fraction * total).floor();
  var seen = 0;
  for (var bin = 0; bin < 256; bin++) {
    seen += histogram[bin];
    if (seen > target) return bin;
  }
  return 255;
}

/// Total variation of the row or column means: high when the projection
/// alternates between ink bands and paper.
double _profileVariation(ScanInkGrid grid, {required bool alongRows}) {
  final length = alongRows ? grid.rows : grid.cols;
  final other = alongRows ? grid.cols : grid.rows;
  var variation = 0.0;
  var previous = 0.0;
  for (var i = 0; i < length; i++) {
    var sum = 0.0;
    for (var j = 0; j < other; j++) {
      sum += alongRows ? grid.at(i, j) : grid.at(j, i);
    }
    final mean = sum / other;
    if (i > 0) variation += (mean - previous).abs();
    previous = mean;
  }
  return variation;
}

/// Returns [grid] turned 90° either way, as displayed.
ScanInkGrid _rotated(ScanInkGrid grid, {required bool clockwise}) {
  final rows = grid.cols;
  final cols = grid.rows;
  final values = Float32List(rows * cols);
  for (var y = 0; y < grid.rows; y++) {
    for (var x = 0; x < grid.cols; x++) {
      final value = grid.at(y, x);
      if (clockwise) {
        // (x, y) -> (x, rows - 1 - y)
        values[x * cols + (grid.rows - 1 - y)] = value;
      } else {
        // (x, y) -> (cols - 1 - x, y)
        values[(grid.cols - 1 - x) * cols + y] = value;
      }
    }
  }
  return ScanInkGrid(rows, cols, values);
}

/// How much sharper the left edge of the text block is than its right edge,
/// on a (possibly rotated) grid.
///
/// Left-aligned paragraphs start at the same x, so the column profile jumps
/// from paper to ink within a couple of samples on the left and trails off
/// raggedly on the right. The sign flips when the page is upside down, which
/// is what makes this usable to pick between the two 90° turns.
double _leftMarginScore(ScanInkGrid grid) {
  var minRow = grid.rows, maxRow = -1, minCol = grid.cols, maxCol = -1;
  for (var y = 0; y < grid.rows; y++) {
    for (var x = 0; x < grid.cols; x++) {
      if (grid.at(y, x) > _kInkThreshold) {
        if (y < minRow) minRow = y;
        if (y > maxRow) maxRow = y;
        if (x < minCol) minCol = x;
        if (x > maxCol) maxCol = x;
      }
    }
  }
  final height = maxRow - minRow + 1;
  final width = maxCol - minCol + 1;
  if (width < 4 || height < 4) return 0;

  final profile = Float32List(width);
  for (var x = 0; x < width; x++) {
    var sum = 0.0;
    for (var y = 0; y < height; y++) {
      sum += grid.at(minRow + y, minCol + x);
    }
    profile[x] = sum / height;
  }

  // A "text column" is one carrying at least 60% of the typical (p60) ink.
  final sorted = Float32List.fromList(profile)..sort();
  final typical = sorted[((width - 1) * 0.6).round()];
  final threshold = typical * 0.6;
  var first = -1;
  var last = -1;
  for (var x = 0; x < width; x++) {
    if (profile[x] > threshold) {
      if (first < 0) first = x;
      last = x;
    }
  }
  if (last <= first) return 0;

  final span = last - first + 1;
  final band = math.min(width, math.max(2, span ~/ 12));
  var left = 0.0;
  for (var x = first; x < first + band; x++) {
    left += profile[x];
  }
  var right = 0.0;
  for (var x = last - band + 1; x <= last; x++) {
    right += profile[x];
  }
  return (left - right) / band;
}
