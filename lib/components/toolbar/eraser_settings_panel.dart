// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/i18n/strings.g.dart';

/// Compact eraser size/mode controls (shared by toolbar overlay and Settings).
class EraserSettingsPanel extends StatefulWidget {
  const EraserSettingsPanel({super.key, this.setTool});

  final ValueChanged<Tool>? setTool;

  @override
  State<EraserSettingsPanel> createState() => _EraserSettingsPanelState();
}

class _EraserSettingsPanelState extends State<EraserSettingsPanel> {
  late double _size = Eraser.currentEraser.size;
  late EraserMode _mode = Eraser.currentEraser.mode;

  void _notifyTool() {
    widget.setTool?.call(Eraser.currentEraser);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '${t.editor.penOptions.size}: ',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(
              width: 42,
              child: Text(
                _size.toStringAsFixed(1),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove, size: 18),
              onPressed: () {
                setState(() {
                  _size = (_size - 0.5).clamp(0.5, 25);
                  Eraser.currentEraser.updateSize = _size;
                  _notifyTool();
                });
              },
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add, size: 18),
              onPressed: () {
                setState(() {
                  _size = (_size + 0.5).clamp(0.5, 25);
                  Eraser.currentEraser.updateSize = _size;
                  _notifyTool();
                });
              },
            ),
          ],
        ),
        Slider(
          value: _size.clamp(0.5, 25),
          min: 0.5,
          max: 25,
          divisions: 49,
          onChanged: (value) {
            setState(() {
              _size = value;
              Eraser.currentEraser.updateSize = value;
              _notifyTool();
            });
          },
        ),
        const SizedBox(height: 12),
        Text(
          'Mode',
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _InkChipOption(
                label: 'Erase stroke',
                selected: _mode == EraserMode.stroke,
                onTap: () {
                  setState(() {
                    _mode = EraserMode.stroke;
                    Eraser.currentEraser.updateMode = _mode;
                    _notifyTool();
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _InkChipOption(
                label: 'Erase area',
                selected: _mode == EraserMode.area,
                onTap: () {
                  setState(() {
                    _mode = EraserMode.area;
                    Eraser.currentEraser.updateMode = _mode;
                    _notifyTool();
                  });
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InkChipOption extends StatelessWidget {
  const _InkChipOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.55)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
                ),
          ),
        ),
      ),
    );
  }
}
