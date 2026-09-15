// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/i18n/strings.g.dart';

class PageNavigationButtons extends StatelessWidget {
  const PageNavigationButtons({
    super.key,
    required this.currentPageIndex,
    required this.totalPages,
    required this.onFirstPage,
    required this.onLastPage,
    required this.onGoToPage,
  });

  final int currentPageIndex;
  final int totalPages;
  final VoidCallback onFirstPage;
  final VoidCallback onLastPage;
  final void Function(int pageIndex) onGoToPage;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const AdaptiveIcon(
            icon: Icons.first_page,
            cupertinoIcon: CupertinoIcons.arrow_left_to_line,
          ),
          tooltip: t.editor.navigation.firstPage,
          onPressed: currentPageIndex > 0 ? onFirstPage : null,
        ),
        IconButton(
          icon: const AdaptiveIcon(
            icon: Icons.last_page,
            cupertinoIcon: CupertinoIcons.arrow_right_to_line,
          ),
          tooltip: t.editor.navigation.lastPage,
          onPressed: currentPageIndex < totalPages - 1 ? onLastPage : null,
        ),
        IconButton(
          icon: const AdaptiveIcon(
            icon: Icons.pageview,
            cupertinoIcon: CupertinoIcons.number,
          ),
          tooltip: t.editor.navigation.goToPage,
          onPressed: () => _showGoToPageDialog(context),
        ),
      ],
    );
  }

  void _showGoToPageDialog(BuildContext context) {
    final controller = TextEditingController(
      text: '${currentPageIndex + 1}',
    );
    
    showDialog(
      context: context,
      builder: (context) => AdaptiveAlertDialog(
        title: Text(t.editor.navigation.goToPage),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: t.editor.navigation.pageNumber,
            hintText: '1-$totalPages',
            helperText: t.editor.navigation.pageNumberHint(total: totalPages),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: Text(t.common.cancel),
            onPressed: () => Navigator.of(context).pop(),
          ),
          CupertinoDialogAction(
            child: Text(t.common.done),
            onPressed: () {
              final text = controller.text.trim();
              final pageNumber = int.tryParse(text);
              if (pageNumber != null && pageNumber >= 1 && pageNumber <= totalPages) {
                Navigator.of(context).pop();
                onGoToPage(pageNumber - 1);
              }
            },
          ),
        ],
      ),
    );
  }
}

