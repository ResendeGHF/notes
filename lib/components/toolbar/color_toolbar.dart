// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:saber/components/toolbar/notes_color_picker_modal.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';

class ColorToolbar extends StatefulWidget {
  const ColorToolbar({
    super.key,
    required this.axis,
    required this.setColor,
    required this.currentColor,
    required this.invert,
    this.onSlotsChanged,
  });

  final Axis axis;
  final ValueChanged<Color> setColor;
  final Color? currentColor;
  final bool invert;

  /// Fired when a toolbar slot color is edited (note-local; must not upsert
  /// ink presets).
  final VoidCallback? onSlotsChanged;

  @override
  State<ColorToolbar> createState() => _ColorToolbarState();
}

class _ColorToolbarState extends State<ColorToolbar> {
  List<Color> get _colorSlots {
    final count = stows.toolbarColorSlotsCount.value;
    final storedStrings = List<String>.from(stows.toolbarColorSlots.value);
    var stored = storedStrings.map((s) => Color(int.parse(s))).toList();

    while (stored.length < count) {
      final defaultColors = _getDefaultColors();
      stored.add(defaultColors[stored.length % defaultColors.length]);
    }
    while (stored.length > count) {
      stored.removeLast();
    }

    if (storedStrings.length != stored.length) {
      stows.toolbarColorSlots.value = stored
          .map((c) => c.toARGB32().toString())
          .toList();
    }

    return stored;
  }

  List<Color> _getDefaultColors() {
    return const [
      Color(0xFF1A1A1A),
      Color(0xFF1E3A5F),
      Color(0xFF374151),
      Color(0xFF15803D),
      Color(0xFF0E7490),
      Color(0xFFB91C1C),
      Color(0xFF4C1D95),
      Color(0xFF9D174D),
      Color(0xFF607D8B),
      Color(0xFF6B7280),
      Color(0xFFF8F8F8),
      Color(0xFF134E4A),
      Color(0xFF312E81),
      Color(0xFFA16207),
    ];
  }

  void _updateColorSlot(int index, Color color) {
    final slots = _colorSlots;
    if (index >= 0 && index < slots.length) {
      slots[index] = color;
      stows.toolbarColorSlots.value = slots
          .map((c) => c.toARGB32().toString())
          .toList();
      // Note-local only: never write these slots back into the active ink preset.
      widget.onSlotsChanged?.call();
      setState(() {});
    }
  }

  Future<void> _showColorPickerForSlot(BuildContext context, int index) async {
    final picked = await showNotesColorPicker(
      context,
      initialColor: _colorSlots[index],
    );
    if (picked == null || !mounted) return;
    _updateColorSlot(index, picked);
    widget.setColor(picked);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    return ValueListenableBuilder(
      valueListenable: stows.toolbarColorSlotsCount,
      builder: (context, count, _) {
        final currentSlots = _colorSlots;

        return Flex(
          direction: widget.axis,
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
          children: [
            for (int i = 0; i < currentSlots.length; i++)
              Builder(
                builder: (context) {
                  final slotColor = currentSlots[i];
                  final isSelected =
                      widget.currentColor?.withAlpha(255).toARGB32() ==
                      slotColor.withAlpha(255).toARGB32();
                  return _ColorSlot(
                    color: slotColor.withInversion(widget.invert),
                    isSelected: isSelected,
                    onTap: () {
                      if (isSelected) {
                        _showColorPickerForSlot(context, i);
                      } else {
                        widget.setColor(slotColor);
                      }
                    },
                    onLongPress: () => _showColorPickerForSlot(context, i),
                    colorScheme: colorScheme,
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

class _ColorSlot extends StatelessWidget {
  const _ColorSlot({
    required this.color,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    required this.colorScheme,
  });

  final Color color;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final luminance = color.computeLuminance();
    final outlineColor = colorScheme.onSurface.withValues(
      alpha: luminance < 0.18 ? 0.5 : 0.28,
    );
    return Tooltip(
      message: isSelected
          ? t.editor.colors.colorPicker
          : t.editor.toolbar.toggleColors,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            child: CustomPaint(
              size: const Size(20, 20),
              painter: _CircleColorPainter(
                color: color,
                outlineColor: outlineColor,
                // Selection ring matches the swatch color (not accent/white).
                selectedRingColor: color,
                gapColor: colorScheme.surface,
                wellLight: colorScheme.surfaceContainerHighest,
                wellDark: colorScheme.surfaceContainerLowest,
                selected: isSelected,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleColorPainter extends CustomPainter {
  _CircleColorPainter({
    required this.color,
    required this.outlineColor,
    required this.selectedRingColor,
    required this.gapColor,
    required this.wellLight,
    required this.wellDark,
    required this.selected,
  });

  final Color color;
  final Color outlineColor;
  final Color selectedRingColor;
  final Color gapColor;
  final Color wellLight;
  final Color wellDark;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final fillRadius = radius - (selected ? 3.6 : 1.3);

    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: fillRadius)),
    );
    canvas.drawCircle(
      center,
      fillRadius,
      Paint()
        ..color = wellLight
        ..isAntiAlias = true,
    );
    const cell = 3.0;
    final wellPaint = Paint()..isAntiAlias = false;
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        if (((x / cell).floor() + (y / cell).floor()).isEven) continue;
        wellPaint.color = wellDark;
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), wellPaint);
      }
    }
    canvas.drawCircle(
      center,
      fillRadius,
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
    canvas.restore();

    canvas.drawCircle(
      center,
      fillRadius,
      Paint()
        ..color = outlineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15
        ..isAntiAlias = true,
    );

    if (!selected) return;
    canvas.drawCircle(
      center,
      fillRadius + 1.25,
      Paint()
        ..color = gapColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7
        ..isAntiAlias = true,
    );
    canvas.drawCircle(
      center,
      radius - 1.0,
      Paint()
        ..color = selectedRingColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _CircleColorPainter oldDelegate) {
    return color != oldDelegate.color ||
        outlineColor != oldDelegate.outlineColor ||
        selectedRingColor != oldDelegate.selectedRingColor ||
        gapColor != oldDelegate.gapColor ||
        wellLight != oldDelegate.wellLight ||
        wellDark != oldDelegate.wellDark ||
        selected != oldDelegate.selected;
  }
}
