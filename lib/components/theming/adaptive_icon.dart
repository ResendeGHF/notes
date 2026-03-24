// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

class AdaptiveIcon extends StatelessWidget {
  const AdaptiveIcon({
    super.key,
    required this.icon,
    this.cupertinoIcon,
    this.size,
    this.color,
  });

  final IconData icon;
  final IconData? cupertinoIcon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Icon(icon, size: size, color: color);
  }
}
