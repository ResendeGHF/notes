// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:saber/components/home/home_toolbar_chrome.dart';
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
  final String? trailingSectionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: components.length + 1,
              separatorBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
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
                      itemColor = isLast ? colorScheme.onSurface : colorScheme.onSurfaceVariant;
                    } else {
                      final colorValue = folderColors[componentPath];
                      itemColor = colorValue != null
                          ? Color(colorValue)
                          : (isLast
                              ? colorScheme.onSurface
                              : colorScheme.onSurfaceVariant);
                    }

                    return Center(
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
                          borderRadius: BorderRadius.circular(6),
                          hoverColor: colorScheme.onSurface.withValues(alpha: 0.04),
                          highlightColor: colorScheme.onSurface.withValues(alpha: 0.08),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Text(
                              label,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: itemColor,
                                fontWeight: isLast ? FontWeight.w600 : FontWeight.w500,
                                letterSpacing: -0.2,
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
          if (trailingSectionLabel != null) ...[
            const HomeToolbarDivider(),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 10, start: 8),
              child: Text(
                trailingSectionLabel!,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ],
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