// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

extension ColorExtensions on Color {

  Color withInversion([bool invert = true]) {
    if (!invert) return this;

    final HSLColor hsl = HSLColor.fromColor(this);
    return hsl.withLightness(1 - hsl.lightness).toColor();
  }

  Color withSaturation(double saturationMultiplier) {
    final HSLColor hsl = HSLColor.fromColor(this);
    return hsl.withSaturation(hsl.saturation * saturationMultiplier).toColor();
  }
}
