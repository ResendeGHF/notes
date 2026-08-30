// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

class InvertWidget extends StatelessWidget {
  const InvertWidget({super.key, this.invert = true, required this.child});

  final bool invert;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!invert) return child;
    return ColorFiltered(colorFilter: filter, child: child);
  }

  /// Same invert used by the canvas; keeps alpha so baked blits stay punched-out.
  static const filter = ColorFilter.matrix(_invertMatrix);
  static const _invertMatrix = <double>[
    1 - 2 * 0.213,
    -2 * 0.715,
    -2 * 0.072,
    0,
    255,
    -2 * 0.213,
    1 - 2 * 0.715,
    -2 * 0.072,
    0,
    255,
    -2 * 0.213,
    -2 * 0.715,
    1 - 2 * 0.072,
    0,
    255,
    0,
    0,
    0,
    1,
    0,
  ];
}
