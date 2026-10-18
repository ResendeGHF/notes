// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Shared RGB color value for DjVu palettes (FGbz) and annotations (ANTa/ANTz).

/// An RGB color with 8-bit components.
class DjvuColor {
  const DjvuColor(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;

  /// The `#RRGGBB` spelling DjVuLibre uses.
  @override
  String toString() =>
      '#${r.toRadixString(16).padLeft(2, '0')}'
      '${g.toRadixString(16).padLeft(2, '0')}'
      '${b.toRadixString(16).padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is DjvuColor && other.r == r && other.g == g && other.b == b;

  @override
  int get hashCode => Object.hash(r, g, b);
}
