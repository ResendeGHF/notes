// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

/// Canonical storage for toolbar pen-size presets: same internal units as [Pen.options.size]
/// (0.5–5 step 0.5). The pen modal displays [formatModalStrokeLabel] (= internal × 2, so 1.0–10.0).
abstract final class PenStrokePresetScaling {
  static const double internalMin = 0.5;
  static const double internalMax = 5.0;
  static const double internalStep = 0.5;

  /// Divisions between min and max for a Material slider (`min/max + divisions`).
  static const int sliderDivisions = 9;

  /// Snap **internal** width to nearest 0.5 in [internalMin], [internalMax].
  static double snapInternal(double v) {
    final n = ((v.clamp(internalMin, internalMax) - internalMin) / internalStep)
        .round();
    return internalMin + n * internalStep;
  }

  /// Pen modal slider label — matches [_SizeSlider] logic for ordinary pens:
  /// [SizePicker] shows **internal × 2** (approximately 1.0–10.0).
  static String formatModalStrokeLabel(double internal) =>
      (snapInternal(internal) * 2).toStringAsFixed(1);

  /// Parse a stored preset string into canonical internal size (with legacy remap).
  static double parseStored(String raw) {
    final parsed = double.tryParse(raw.trim());
    if (parsed == null) return snapInternal(2.0);

    // Historically sliders used ~0.5–24 (misleading "px"); treat clearly-out-of-range
    // legacy values linearly onto our internal stroke range.
    if (parsed <= internalMax + 1e-9) return snapInternal(parsed);

    final t = ((parsed.clamp(internalMin, 24.0) - internalMin) /
            (24.0 - internalMin))
        .clamp(0.0, 1.0);
    final mapped =
        internalMin + t * (internalMax - internalMin);
    return snapInternal(mapped);
  }

  /// Hyphen-preview stroke thickness inside toolbar chips (pixels).
  static double hyphenVisualThicknessPx(double internal) =>
      (1.3 + snapInternal(internal) * 2.4).clamp(2.2, 12.8);
}
