// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
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
  });

  final Axis axis;
  final ValueChanged<Color> setColor;
  final Color? currentColor;
  final bool invert;

  @override
  State<ColorToolbar> createState() => _ColorToolbarState();
}

class _ColorToolbarState extends State<ColorToolbar> {
  static var _pickedColor = const Color.fromRGBO(255, 0, 0, 1);

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
      setState(() {});
    }
  }

  void _showColorPickerForSlot(BuildContext context, int index) async {
    final currentSlotColor = _colorSlots[index];
    _pickedColor = currentSlotColor;

    final bool? confirmChange = await showDialog(
      context: context,
      builder: (BuildContext context) => AdaptiveAlertDialog(
        title: Text(t.editor.colors.colorPicker),
        content: SingleChildScrollView(
          child: ColorPicker(
            color: _pickedColor,
            pickersEnabled: const {ColorPickerType.wheel: true},
            showColorCode: true,
            colorCodeHasColor: true,
            enableOpacity: false,
            onColorChanged: (Color color) {
              _pickedColor = color;
            },
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            onPressed: () {
              Navigator.of(context).pop(false);
            },
          ),
          CupertinoDialogAction(
            child: Text(MaterialLocalizations.of(context).saveButtonLabel),
            onPressed: () {
              Navigator.of(context).pop(true);
            },
          ),
        ],
      ),
    );

    if (confirmChange ?? false) {
      _updateColorSlot(index, _pickedColor);
    }
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
                  final isSelected =
                      widget.currentColor?.withAlpha(255).toARGB32() ==
                      currentSlots[i].withAlpha(255).toARGB32();
                  return _ColorSlot(
                    color: currentSlots[i].withInversion(widget.invert),
                    isSelected: isSelected,
                    onTap: () {
                      if (isSelected) {

                        _showColorPickerForSlot(context, i);
                      } else {

                        widget.setColor(currentSlots[i]);
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
              size: const Size(16, 16),
              painter: _CircleColorPainter(
                color: color,
                borderColor: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurface.withValues(alpha: 0.3),
                borderWidth: isSelected ? 3.0 : 2.0,
                hasGlow: isSelected,
                glowColor: colorScheme.primary,
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
    required this.borderColor,
    this.borderWidth = 2.0,
    this.hasGlow = false,
    this.glowColor = const Color(0xFF000000),
  });

  final Color color;
  final Color borderColor;
  final double borderWidth;
  final bool hasGlow;
  final Color glowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final fillRadius = r - borderWidth;
    final strokeRadius = r - borderWidth / 2;

    if (hasGlow) {
      canvas.drawCircle(
        center,
        r + 1,
        Paint()
          ..color = glowColor.withValues(alpha: 0.3)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(center, fillRadius, fillPaint);

    final strokePaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..isAntiAlias = true;
    canvas.drawCircle(center, strokeRadius, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _CircleColorPainter oldDelegate) {
    return color != oldDelegate.color ||
        borderColor != oldDelegate.borderColor ||
        borderWidth != oldDelegate.borderWidth ||
        hasGlow != oldDelegate.hasGlow;
  }
}
