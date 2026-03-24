// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

enum ColorOptionShape { circle, roundedSquare }

class ColorOption extends StatelessWidget {
  const ColorOption({
    super.key,
    required this.isSelected,
    this.enabled = true,
    this.onTap,
    this.onLongPress,
    required this.tooltip,
    required this.child,
    this.shape = ColorOptionShape.roundedSquare,
  });

  final bool isSelected;
  final bool enabled;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? tooltip;
  final Widget child;
  final ColorOptionShape shape;

  static const double diameter = 25;
  static const double roundedSquareRadius = 6;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final borderRadius = shape == ColorOptionShape.roundedSquare
        ? BorderRadius.circular(roundedSquareRadius)
        : BorderRadius.circular(diameter / 2);
    return Tooltip(
      message: tooltip ?? '',
      child: Padding(
        padding: const .symmetric(horizontal: 4),
        child: InkWell(
          borderRadius: borderRadius,
          onTap: enabled ? onTap : null,
          onLongPress: enabled ? onLongPress : null,
          onSecondaryTap: enabled ? onLongPress : null,
          child: Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              border: Border.all(
                color: isSelected ? colorScheme.onSurface : Colors.transparent,
                width: 2,
              ),
            ),
            child: Padding(
              padding: const .all(3),
              child: AnimatedOpacity(
                opacity: enabled ? 1 : 0.5,
                duration: const Duration(milliseconds: 200),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ColorOptionSeparatorIcon extends StatelessWidget {
  const ColorOptionSeparatorIcon({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Padding(
      padding: const .symmetric(horizontal: 8, vertical: 4),
      child: Icon(
        icon,
        size: 16,
        color: Color.lerp(
          colorScheme.onSurface,
          colorScheme.primary,
          0.2,
        )!.withValues(alpha: 0.7),
      ),
    );
  }
}
