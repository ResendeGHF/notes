// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

class AdaptiveSwitch extends Switch {
  const AdaptiveSwitch({
    super.key,
    required super.value,
    required super.onChanged,
    super.thumbIcon,
    super.thumbColor,
    super.focusNode,
    super.autofocus = false,
    super.mouseCursor,
  }) : super();
}
