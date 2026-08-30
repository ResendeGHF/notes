// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:saber/data/stroke_geometry/stroke_geometry.dart';

extension StrokeOptionsExtension on StrokeOptions {
  static void setDefaults() {
    StrokeOptions.defaultSize = 2;
    StrokeOptions.defaultThinning = 0.5;
    StrokeOptions.defaultSmoothing = 0;
    StrokeOptions.defaultStreamline = 0.5;
    StrokeEndOptions.defaultTaperEnabled = false;
    StrokeEndOptions.defaultCap = true;
    StrokeOptions.defaultSimulatePressure = true;
  }
}
