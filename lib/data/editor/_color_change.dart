// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/painting.dart';

class ColorChange {
  final Color previous;
  final Color current;

  const ColorChange({required this.previous, required this.current});

  ColorChange swap() {
    return ColorChange(previous: current, current: previous);
  }
}
