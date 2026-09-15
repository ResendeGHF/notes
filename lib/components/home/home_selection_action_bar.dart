// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:saber/components/home/home_toolbar_chrome.dart';

/// Full-width docked bar for multi-select actions (same shell language as the rail / headers).
class HomeSelectionActionBar extends StatelessWidget {
  const HomeSelectionActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return BottomAppBar(
      color: cs.surfaceContainer,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Theme(
        data: theme.copyWith(
          iconTheme: IconThemeData(color: cs.primary),
        ),
        child: child,
      ),
    );
  }
}
