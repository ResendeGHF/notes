// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/data/editor/pdf_outline.dart';
import 'package:saber/i18n/strings.g.dart';

class PdfOutlineNavigator extends StatelessWidget {
  const PdfOutlineNavigator({
    super.key,
    required this.outlines,
    required this.onPageSelected,
  });

  final List<PdfOutlineItem> outlines;
  final void Function(int pageIndex) onPageSelected;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const AdaptiveIcon(
        icon: Icons
            .account_tree_outlined,
        cupertinoIcon: CupertinoIcons.list_bullet_indent,
      ),
      tooltip: t.editor.navigation.pdfOutlines,
      onPressed: () => _showOutlineDialog(context),
    );
  }

  void _showOutlineDialog(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final colorScheme = Theme.of(context).colorScheme;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: isMobile ? Alignment.center : Alignment.centerRight,
          child: Material(
            color: colorScheme.surface,
            surfaceTintColor:
                Colors.transparent,
            elevation: 16,
            borderRadius: isMobile
                ? BorderRadius.zero
                : const BorderRadius.horizontal(left: Radius.circular(24)),
            child: SizedBox(
              width: isMobile ? double.infinity : 400,
              height: double.infinity,
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [

                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              t.editor.navigation.pdfOutlines,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),

                    Expanded(
                      child: outlines.isEmpty
                          ? Center(
                              child: Text(
                                'No outline found',
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : Scrollbar(
                              thumbVisibility: true,
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                itemCount: outlines.length,
                                itemBuilder: (context, index) {
                                  return _buildOutlineItem(
                                    context,
                                    outlines[index],
                                    0,
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        if (isMobile) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          );
        }
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
          child: child,
        );
      },
    );
  }

  Widget _buildOutlineItem(
    BuildContext context,
    PdfOutlineItem item,
    int indent,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            Navigator.of(context).pop();
            onPageSelected(item.pageIndex);
          },

          child: Container(
            padding: EdgeInsets.only(
              left: 16.0 + (indent * 16.0),
              right: 16.0,
              top: 8.0,
              bottom: 8.0,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(
                    alpha: 0.3,
                  ),
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [

                if (indent > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Icon(
                      Icons.subdirectory_arrow_right,
                      size: 14,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.6,
                      ),
                    ),
                  ),

                Expanded(
                  child: Text(
                    item.title,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: indent == 0
                          ? FontWeight.w600
                          : FontWeight.normal,
                      fontSize: indent == 0 ? 15 : 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                const SizedBox(width: 8),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    (item.pageIndex + 1).toString(),
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        if (item.children != null)
          for (final child in item.children!)
            _buildOutlineItem(context, child, indent + 1),
      ],
    );
  }
}
