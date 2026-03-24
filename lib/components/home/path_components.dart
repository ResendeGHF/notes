// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:saber/data/prefs.dart';

class PathComponents extends StatelessWidget {
  PathComponents(String? path, {super.key, required this.onPathComponentTap})
    : components = _splitPath(path);

  final List<String> components;
  final void Function(String? path) onPathComponentTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    return Container(
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: components.length + 1,
        separatorBuilder: (context, index) => Icon(
          Icons.chevron_right,
          size: 16,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
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
                itemColor =
                    colorScheme.primary;
              } else {
                final colorValue = folderColors[componentPath];

                itemColor = colorValue != null
                    ? Color(colorValue)
                    : (isLast
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant);
              }

              return InkWell(
                onTap: () {
                  if (isRoot) {
                    onPathComponentTap(null);
                  } else {
                    onPathComponentTap(componentPath);
                  }
                },
                borderRadius: BorderRadius.circular(16),
                hoverColor: Colors.transparent,
                focusColor: Colors.transparent,
                highlightColor: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: itemColor,
                        fontWeight: isLast
                            ? FontWeight.bold
                            : FontWeight.normal,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
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
