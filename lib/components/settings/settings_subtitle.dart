// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

class SettingsSubtitle extends StatelessWidget {
  const SettingsSubtitle({super.key, required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Padding(
      padding: const .only(top: 32, left: 16, right: 16, bottom: 0),
      child: Text(
        subtitle,
        style: TextStyle(color: colorScheme.primary, fontWeight: .w500),
      ),
    );
  }
}
