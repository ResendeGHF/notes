// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:saber/components/home/home_toolbar_chrome.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/data/prefs.dart';

class PathComponents extends StatelessWidget {
  PathComponents(
    String? path, {
    super.key,
    required this.onPathComponentTap,
    this.trailingSectionLabel,
  }) : components = _splitPath(path);

  final List<String> components;
  final void Function(String? path) onPathComponentTap;

  /// Optional label on the trailing edge (e.g. section title), same chrome as crumbs.
  final String? trailingSectionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: homeRuggedPanelDecoration(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: components.length + 1,
                  separatorBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.45,
                      ),
                    ),
                  ),
                  itemBuilder: (context, index) {
                    final isRoot = index == 0;
                    final String label = isRoot ? 'Notes' : components[index - 1];
                    final bool isLast = index == components.length;

                    final componentPath = isRoot
                        ? '/'
                        : '/${components.sublist(0, index).join('/')}';

                    return ValueListenableBuilder<Map<String, int>>(
                      valueListenable: stows.folderColors,
                      builder: (context, folderColors, _) {
                        Color itemColor;
                        if (isRoot) {
                          itemColor = colorScheme.primary;
                        } else {
                          final colorValue = folderColors[componentPath];

                          itemColor = colorValue != null
                              ? Color(colorValue)
                              : (isLast
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant);
                        }

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                if (isRoot) {
                                  onPathComponentTap(null);
                                } else {
                                  onPathComponentTap(componentPath);
                                }
                              },
                              borderRadius:
                                  BorderRadius.circular(kSaberContainerRadius),
                              hoverColor: Colors.transparent,
                              focusColor: Colors.transparent,
                              highlightColor: colorScheme.onSurface.withValues(
                                alpha: 0.06,
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                    kSaberContainerRadius,
                                  ),
                                  border: Border.all(
                                    color: colorScheme.outlineVariant.withValues(
                                      alpha: isLast ? 0.28 : 0.14,
                                    ),
                                  ),
                                  color: colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.35),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  child: Center(
                                    child: Text(
                                      label,
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                        color: itemColor,
                                        fontWeight: isLast
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            if (trailingSectionLabel != null) ...[
              const HomeToolbarDivider(),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 10, start: 4),
                child: Text(
                  trailingSectionLabel!,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static List<String> _splitPath(String? path) {
    return (path ?? '')
        .split(RegExp(r'[\\/]'))
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }
}
