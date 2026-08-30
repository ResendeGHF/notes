// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:saber/components/home/home_toolbar_chrome.dart';

const double kHomeListRowHeight = 104;
const double kHomeListRowGridExtent = 112;

/// Recent Notes list rows are thumbnail + name only.
const double kHomeListRowCompactExtent = 96;

class HomeListRowSurface extends StatelessWidget {
  const HomeListRowSurface({
    super.key,
    required this.child,
    this.selected = false,
    this.padding = const EdgeInsets.fromLTRB(12, 10, 10, 10),
  });

  final Widget child;
  final bool selected;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final baseColor = homeAppBarBackgroundColor(context);
    final selectedColor = Color.lerp(
      baseColor,
      colorScheme.primaryContainer,
      isDark ? 0.18 : 0.24,
    )!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? selectedColor : baseColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.62)
                : colorScheme.outlineVariant.withValues(
                    alpha: isDark ? 0.26 : 0.20,
                  ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.045),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kHomeListRowHeight),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class HomeListMetaChip extends StatelessWidget {
  const HomeListMetaChip({
    super.key,
    required this.icon,
    required this.text,
    required this.tooltip,
  });

  final IconData icon;
  final String text;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(
            alpha: isDark ? 0.28 : 0.46,
          ),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(
              alpha: isDark ? 0.18 : 0.14,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.86),
              ),
              const SizedBox(width: 4),
              Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 11.5,
                  height: 1.1,
                  letterSpacing: 0.08,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
