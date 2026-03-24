// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

class CanvasGestureLockBtn extends StatelessWidget {

  const CanvasGestureLockBtn({
    super.key,
    required this.lock,
    required this.setLock,
    required this.tooltip,
    this.icon,
    this.child,
  }) : assert(icon != null || child != null);

  final bool lock;
  final ValueChanged<bool> setLock;
  final String tooltip;
  final IconData? icon;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return GestureDetector(
      onTap: () => setLock(!lock),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.5),
          borderRadius: .circular(15),
        ),
        padding: const .all(5),
        child: Tooltip(
          message: tooltip,
          child:
              child ??
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(icon, color: colorScheme.onSurface),
              ),
        ),
      ),
    );
  }
}
