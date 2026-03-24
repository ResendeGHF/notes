// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/navbar/responsive_navbar.dart';
import 'package:saber/components/theming/saber_theme.dart';

class HorizontalNavbar extends StatelessWidget {
  const HorizontalNavbar({
    super.key,
    required this.destinations,
    this.selectedIndex = 0,
    this.onDestinationSelected,
  });

  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int>? onDestinationSelected;

  static double clearanceHeightOf(BuildContext context) {
    if (ResponsiveNavbar.isLargeScreen) return 0;
    final platform = Theme.of(context).platform;
    return _heightForPlatform(platform) + 32;
  }

  static double _heightForPlatform(TargetPlatform platform) {
    return 64.0;
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;

    return SafeArea(
      child: Padding(
        padding: const .all(16),
        child: Align(
          alignment: AlignmentDirectional.bottomEnd,
          child: GlassyContainer(
            child: Padding(
              padding: platform.isCupertino ? const .all(4) : const .all(8),
              child: Semantics(
                role: SemanticsRole.tabBar,
                explicitChildNodes: true,
                container: true,
                child: Row(
                  mainAxisSize: .min,
                  spacing: platform.isCupertino ? 0 : 4,
                  children: [
                    for (int i = 0; i < destinations.length; i++)
                      MergeSemantics(
                        child: Semantics(
                          role: SemanticsRole.tab,
                          selected: i == selectedIndex,
                          child: _ToolbarButton(
                            destination: destinations[i],
                            selected: i == selectedIndex,
                            select: () {
                              onDestinationSelected?.call(i);
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GlassyContainer extends StatelessWidget {
  const GlassyContainer({
    super.key,
    required this.child,
    this.height,
    this.borderRadius,
  });
  final Widget child;
  final double? height;
  final BorderRadius? borderRadius;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final platform = theme.platform;
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final height = this.height ?? HorizontalNavbar._heightForPlatform(platform);
    final borderRadius =
        this.borderRadius ?? BorderRadius.circular(height / 2.5);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111111) : colorScheme.surface,
        borderRadius: borderRadius,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.destination,
    required this.selected,
    this.select,
  });

  final NavigationDestination destination;
  final bool selected;
  final VoidCallback? select;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(16);

    final selectedBgColor = Colors.blueGrey.withValues(alpha: 0.25);
    final bgColor = selected ? selectedBgColor : Colors.transparent;
    final fgColor = selected
        ? (isDark ? Colors.white : Colors.black)
        : colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: InkWell(
        onTap: select,
        borderRadius: borderRadius,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: bgColor, borderRadius: borderRadius),
          child: Column(
            mainAxisAlignment: .center,
            children: [
              IconTheme.merge(
                data: IconThemeData(color: fgColor, size: 24),
                child: destination.icon,
              ),
              const SizedBox(height: 2),
              Text(
                destination.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: fgColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
