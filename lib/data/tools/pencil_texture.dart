// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

enum PencilTexturePreset {
  hb(
    id: 'hb',
    label: 'HB',
    toneLift: 0.42,
    grainSpacing: 5,
    grainDensityBase: 0.22,
    grainDensityPressure: 0.18,
    grainSizeFactor: 0.10,
    grainJitterFactor: 0.26,
    darkGrainAlpha: 0.20,
    lightGrainAlpha: 0.14,
    blotchAlpha: 0.02,
  ),
  graphite2b(
    id: '2b',
    label: '2B',
    toneLift: 0.28,
    grainSpacing: 3,
    grainDensityBase: 0.34,
    grainDensityPressure: 0.22,
    grainSizeFactor: 0.14,
    grainJitterFactor: 0.34,
    darkGrainAlpha: 0.28,
    lightGrainAlpha: 0.10,
    blotchAlpha: 0.04,
  ),
  rough6b(
    id: '6b',
    label: '6B',
    toneLift: 0.16,
    grainSpacing: 2,
    grainDensityBase: 0.46,
    grainDensityPressure: 0.26,
    grainSizeFactor: 0.18,
    grainJitterFactor: 0.42,
    darkGrainAlpha: 0.34,
    lightGrainAlpha: 0.07,
    blotchAlpha: 0.06,
  );

  const PencilTexturePreset({
    required this.id,
    required this.label,
    required this.toneLift,
    required this.grainSpacing,
    required this.grainDensityBase,
    required this.grainDensityPressure,
    required this.grainSizeFactor,
    required this.grainJitterFactor,
    required this.darkGrainAlpha,
    required this.lightGrainAlpha,
    required this.blotchAlpha,
  });

  final String id;
  final String label;
  final double toneLift;
  final int grainSpacing;
  final double grainDensityBase;
  final double grainDensityPressure;
  final double grainSizeFactor;
  final double grainJitterFactor;
  final double darkGrainAlpha;
  final double lightGrainAlpha;
  final double blotchAlpha;
}

extension PencilTexturePresetX on PencilTexturePreset {
  static PencilTexturePreset fromIndex(int index) {
    if (index < 0 || index >= PencilTexturePreset.values.length) {
      return PencilTexturePreset.hb;
    }
    return PencilTexturePreset.values[index];
  }
}
