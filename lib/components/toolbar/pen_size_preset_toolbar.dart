// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
import 'package:saber/data/pen_stroke_preset_scaling.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';

/// Tap-to-select pen stroke-width presets shown next to drawing tools.
class PenSizePresetToolbar extends StatefulWidget {
  const PenSizePresetToolbar({
    super.key,
    required this.axis,
    required this.readOnly,
    required this.selectedPresetIndex,
    required this.onPresetSelected,
    required this.applyStrokeWidthFromPreset,
    required this.onPresetSizesChangedForNote,
  });

  final Axis axis;
  final bool readOnly;
  final int? selectedPresetIndex;
  final ValueChanged<int> onPresetSelected;
  final ValueChanged<double> applyStrokeWidthFromPreset;
  final VoidCallback onPresetSizesChangedForNote;

  @override
  State<PenSizePresetToolbar> createState() => _PenSizePresetToolbarState();
}

class _PenSizePresetToolbarState extends State<PenSizePresetToolbar> {
  Future<void> _showEditPresetDialog(BuildContext context, int index) async {
    stows.normalizePenSizePresetList();
    final slots = stows.penSizePresetSizesAsDoubles();
    if (index < 0 || index >= slots.length) return;

    var internal = PenStrokePresetScaling.snapInternal(slots[index]);

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return AdaptiveAlertDialog(
            title: Text(t.editor.penSizePresets.editTitle(n: index + 1)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t.editor.penSizePresets.editSubtitle,
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  PenStrokePresetScaling.formatModalStrokeLabel(internal),
                  style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  t.editor.penSizePresets.sameAsPenSlider,
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
                Slider(
                  value: internal,
                  min: PenStrokePresetScaling.internalMin,
                  max: PenStrokePresetScaling.internalMax,
                  divisions: PenStrokePresetScaling.sliderDivisions,
                  label: PenStrokePresetScaling.formatModalStrokeLabel(
                    internal,
                  ),
                  onChanged: (v) => setLocal(
                    () => internal = PenStrokePresetScaling.snapInternal(v),
                  ),
                ),
              ],
            ),
            actions: [
              CupertinoDialogAction(
                child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
                onPressed: () => Navigator.of(ctx).pop(false),
              ),
              CupertinoDialogAction(
                child: Text(MaterialLocalizations.of(ctx).saveButtonLabel),
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
            ],
          );
        },
      ),
    );

    if (ok != true || !context.mounted) return;

    final list = List<String>.from(stows.penSizePresetSizes.value);
    if (index >= list.length) return;
    list[index] = PenStrokePresetScaling.snapInternal(internal).toString();
    stows.penSizePresetSizes.value = list;
    widget.onPresetSizesChangedForNote();
    if (!mounted) return;
    setState(() {});
  }

  bool _isSlotSelected(int i) =>
      widget.selectedPresetIndex != null && widget.selectedPresetIndex == i;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ValueListenableBuilder<int>(
      valueListenable: stows.penSizePresetCount,
      builder: (context, _, __) {
        stows.normalizePenSizePresetList();
        return ValueListenableBuilder<List<String>>(
          valueListenable: stows.penSizePresetSizes,
          builder: (context, _, __) {
            final sizes = stows.penSizePresetSizesAsDoubles();

            return Flex(
              direction: widget.axis,
              mainAxisSize: MainAxisSize.min,
              spacing: 2,
              children: [
                for (var i = 0; i < sizes.length; i++)
                  _PenSizePresetSlot(
                    size: sizes[i],
                    axis: widget.axis,
                    isSelected: _isSlotSelected(i),
                    readOnly: widget.readOnly,
                    colorScheme: colorScheme,
                    onTap: () {
                      if (widget.readOnly) return;
                      widget.onPresetSelected(i);
                      widget.applyStrokeWidthFromPreset(sizes[i]);
                    },
                    onDoubleTap: () {
                      if (widget.readOnly) return;
                      _showEditPresetDialog(context, i);
                    },
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _PenSizePresetSlot extends StatelessWidget {
  const _PenSizePresetSlot({
    required this.size,
    required this.axis,
    required this.isSelected,
    required this.readOnly,
    required this.colorScheme,
    required this.onTap,
    required this.onDoubleTap,
  });

  final double size;
  final Axis axis;
  final bool isSelected;
  final bool readOnly;
  final ColorScheme colorScheme;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  double get _lineThicknessPx =>
      PenStrokePresetScaling.hyphenVisualThicknessPx(size);

  @override
  Widget build(BuildContext context) {
    final opacity = readOnly ? 0.35 : 1.0;

    Widget inner = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isSelected
            ? colorScheme.surfaceContainerHighest
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(10),
      child: CustomPaint(
        painter: _HyphenStrokePainter(
          thicknessPx: _lineThicknessPx,
          color: colorScheme.onSurface.withValues(alpha: 0.85),
        ),
      ),
    );

    inner = Opacity(opacity: opacity, child: inner);

    inner = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: readOnly ? null : onTap,
      onDoubleTap: readOnly ? null : onDoubleTap,
      child: inner,
    );

    return inner;
  }
}

class _HyphenStrokePainter extends CustomPainter {
  _HyphenStrokePainter({required this.thicknessPx, required this.color});

  final double thicknessPx;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = thicknessPx
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawLine(Offset(2, y), Offset(size.width - 2, y), paint);
  }

  @override
  bool shouldRepaint(covariant _HyphenStrokePainter oldDelegate) {
    return thicknessPx != oldDelegate.thicknessPx || color != oldDelegate.color;
  }
}
