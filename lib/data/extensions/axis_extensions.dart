// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

extension AxisExtensions on Axis {
  Axis get opposite => switch (this) {
    Axis.horizontal => Axis.vertical,
    Axis.vertical => Axis.horizontal,
  };
}

extension AxisDirectionExtensions on AxisDirection {
  Axis get axis => switch (this) {
    AxisDirection.up || AxisDirection.down => Axis.vertical,
    AxisDirection.left || AxisDirection.right => Axis.horizontal,
  };
}
