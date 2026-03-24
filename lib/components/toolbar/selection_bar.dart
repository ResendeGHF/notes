// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/i18n/strings.g.dart';

class SelectionBar extends StatelessWidget {
  final Axis axis;
  final VoidCallback duplicateSelection;
  final VoidCallback deleteSelection;
  final VoidCallback? copyToClipboard;
  final VoidCallback? cutToClipboard;
  final VoidCallback? toggleInvertible;
  final bool showInvertOption;

  const SelectionBar({
    super.key,
    required this.axis,
    required this.duplicateSelection,
    required this.deleteSelection,
    this.copyToClipboard,
    this.cutToClipboard,
    this.toggleInvertible,
    this.showInvertOption = false,
  });

  @override
  Widget build(BuildContext context) {
    final children = [
      if (copyToClipboard != null)
        _SelectionIconButton(
          onTap: copyToClipboard!,
          tooltip: t.editor.selectionBar.copy,
          icon: const AdaptiveIcon(
            icon: Icons.copy,
            cupertinoIcon: CupertinoIcons.doc_on_doc,
          ),
        ),
      if (cutToClipboard != null)
        _SelectionIconButton(
          onTap: cutToClipboard!,
          tooltip: t.editor.selectionBar.cut,
          icon: const AdaptiveIcon(
            icon: Icons.cut,
            cupertinoIcon: CupertinoIcons.scissors,
          ),
        ),
      _SelectionIconButton(
        onTap: duplicateSelection,
        tooltip: t.editor.selectionBar.duplicate,
        icon: const AdaptiveIcon(
          icon: Icons.content_copy,
          cupertinoIcon: CupertinoIcons.doc_on_clipboard,
        ),
      ),
      if (showInvertOption && toggleInvertible != null)
        _SelectionIconButton(
          onTap: toggleInvertible!,
          tooltip: t.editor.imageOptions.invertible,
          icon: const AdaptiveIcon(
            icon: Icons.invert_colors,
            cupertinoIcon: CupertinoIcons.brightness,
          ),
        ),
      _SelectionIconButton(
        onTap: deleteSelection,
        tooltip: t.editor.selectionBar.delete,
        icon: const AdaptiveIcon(
          icon: Icons.delete,
          cupertinoIcon: CupertinoIcons.delete,
        ),
      ),
    ];

    return Flex(
      direction: axis,
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: children,
    );
  }
}

class _SelectionIconButton extends StatelessWidget {
  const _SelectionIconButton({
    required this.onTap,
    required this.tooltip,
    required this.icon,
  });

  final VoidCallback onTap;
  final String tooltip;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 40,
            height: 40,
            padding: const EdgeInsets.all(8),
            child: icon,
          ),
        ),
      ),
    );
  }
}

