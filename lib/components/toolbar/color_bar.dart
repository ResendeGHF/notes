// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
import 'package:saber/components/toolbar/color_option.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';

typedef NamedColor = ({String name, Color color});

class ColorBar extends StatefulWidget {
  const ColorBar({
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

  static List<NamedColor> get colorPresets =>
      stows.preferGreyscale.value ? greyScaleColorOptions : normalColorOptions;

  static final List<NamedColor> normalColorOptions = [
    (name: t.editor.colors.black, color: const Color(0xFF1A1A1A)),
    (name: t.editor.colors.red, color: const Color(0xFFB91C1C)),
    (name: t.editor.colors.orange, color: const Color(0xFFC2410C)),
    (name: t.editor.colors.yellow, color: const Color(0xFFA16207)),
    (name: t.editor.colors.green, color: const Color(0xFF15803D)),
    (name: t.editor.colors.cyan, color: const Color(0xFF0E7490)),
    (name: t.editor.colors.blue, color: const Color(0xFF1E3A5F)),
    (name: t.editor.colors.purple, color: const Color(0xFF4C1D95)),
    (name: t.editor.colors.pink, color: const Color(0xFF9D174D)),
    (name: t.editor.colors.white, color: const Color(0xFFF8F8F8)),
    ..._pastelColorOptions,
  ];

  static final List<NamedColor> _pastelColorOptions = [
    (name: t.editor.colors.pastelRed, color: const Color(0xFFFECACA)),
    (name: t.editor.colors.pastelOrange, color: const Color(0xFFFED7AA)),
    (name: t.editor.colors.pastelYellow, color: const Color(0xFFFEF08A)),
    (name: t.editor.colors.pastelGreen, color: const Color(0xFFBBF7D0)),
    (name: t.editor.colors.pastelCyan, color: const Color(0xFFA5F3FC)),
    (name: t.editor.colors.pastelBlue, color: const Color(0xFFBFDBFE)),
    (name: t.editor.colors.pastelPurple, color: const Color(0xFFDDD6FE)),
    (name: t.editor.colors.pastelPink, color: const Color(0xFFFBCFE8)),
  ];
  static final List<NamedColor> greyScaleColorOptions = [
    (name: t.editor.colors.black, color: Colors.black),
    (name: t.editor.colors.darkGrey, color: Colors.grey[800] ?? Colors.black54),
    (name: t.editor.colors.grey, color: Colors.grey),
    (
      name: t.editor.colors.lightGrey,
      color: Colors.grey[200] ?? Colors.black12,
    ),
    (name: t.editor.colors.white, color: Colors.white),
  ];
  static final List<NamedColor> _allColors = [
    ...normalColorOptions,
    ...greyScaleColorOptions,
  ];
  static String findColorName(Color searchColor) {
    for (final namedColor in _allColors) {
      if (namedColor.color == searchColor) {
        return namedColor.name;
      }
    }
    return describeColor(searchColor);
  }

  @visibleForTesting
  static String describeColor(Color color) {
    final hsl = HSLColor.fromColor(color);

    final String hueName;
    if (hsl.saturation < 0.1 || hsl.lightness < 0.05 || hsl.lightness > 0.95) {
      hueName = t.editor.colors.grey.toLowerCase();
    } else {
      hueName = switch (hsl.hue) {
        < 10 => t.editor.colors.red.toLowerCase(),
        < 35 => t.editor.colors.orange.toLowerCase(),
        < 70 => t.editor.colors.yellow.toLowerCase(),
        < 150 => t.editor.colors.green.toLowerCase(),
        < 200 => t.editor.colors.cyan.toLowerCase(),
        < 250 => t.editor.colors.blue.toLowerCase(),
        < 285 => t.editor.colors.purple.toLowerCase(),
        < 340 => t.editor.colors.pink.toLowerCase(),
        _ => t.editor.colors.red.toLowerCase(),
      };
    }

    final lightnessName = switch (hsl.lightness) {
      < 0.35 => t.editor.colors.dark,
      < 0.65 => null,
      _ => t.editor.colors.light,
    };

    if (lightnessName == null) {
      return t.editor.colors.customHue(h: hueName);
    } else {
      return t.editor.colors.customBrightnessHue(b: lightnessName, h: hueName);
    }
  }

  static bool toggleColorPinned(String colorString) {
    if (stows.pinnedColors.value.contains(colorString)) {
      stows.pinnedColors.value.remove(colorString);
      stows.recentColorsChronological.value.remove(colorString);
      stows.recentColorsPositioned.value.remove(colorString);
      if (stows.recentColorsChronological.value.length >=
          stows.recentColorsLength.value) {

        final oldestColor = stows.recentColorsChronological.value.removeAt(0);
        stows.recentColorsChronological.value.add(colorString);
        final int oldestColorPosition = stows.recentColorsPositioned.value
            .indexOf(oldestColor);
        stows.recentColorsPositioned.value[oldestColorPosition] = colorString;
      } else {

        stows.recentColorsChronological.value.add(colorString);
        stows.recentColorsPositioned.value.insert(0, colorString);
      }
      return false;
    } else {

      stows.pinnedColors.value.add(colorString);
      stows.recentColorsChronological.value.remove(colorString);
      stows.recentColorsPositioned.value.remove(colorString);
      return true;
    }
  }

  @override
  State<ColorBar> createState() => _ColorBarState();
}

class _ColorBarState extends State<ColorBar> {
  static var pickedColor = const Color.fromRGBO(255, 0, 0, 1);

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    final children = <Widget>[

      if (stows.pinnedColors.value.isNotEmpty) ...[
        const ColorOptionSeparatorIcon(icon: Icons.pin_drop),
        for (final colorString in stows.pinnedColors.value)
          ColorOption(
            isSelected:
                widget.currentColor?.withAlpha(255).toARGB32() ==
                int.parse(colorString),
            enabled: widget.currentColor != null,
            onTap: () => widget.setColor(Color(int.parse(colorString))),
            onLongPress: () =>
                setState(() => ColorBar.toggleColorPinned(colorString)),
            tooltip: ColorBar.findColorName(Color(int.parse(colorString))),
            child: Container(
              decoration: BoxDecoration(
                color: Color(
                  int.parse(colorString),
                ).withInversion(widget.invert),
                borderRadius: BorderRadius.circular(ColorOption.roundedSquareRadius - 1),
                border: Border.all(
                  color: colorScheme.onSurface.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
            ),
          ),
      ],

      const ColorOptionSeparatorIcon(icon: Icons.history),

      for (final colorString in stows.recentColorsPositioned.value.reversed)
        ColorOption(
          isSelected:
              widget.currentColor?.withAlpha(255).toARGB32() ==
              int.parse(colorString),
          enabled: widget.currentColor != null,
          onTap: () => widget.setColor(Color(int.parse(colorString))),
          onLongPress: () =>
              setState(() => ColorBar.toggleColorPinned(colorString)),
          tooltip: ColorBar.findColorName(Color(int.parse(colorString))),
          child: Container(
            decoration: BoxDecoration(
              color: Color(int.parse(colorString)).withInversion(widget.invert),
              borderRadius: BorderRadius.circular(ColorOption.roundedSquareRadius - 1),
              border: Border.all(
                color: colorScheme.onSurface.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
          ),
        ),

      for (
        int i = 0;
        i <
            stows.recentColorsLength.value -
                stows.recentColorsPositioned.value.length;
        ++i
      )
        ColorOption(
          isSelected: false,
          enabled: widget.currentColor != null,
          onTap: null,
          tooltip: null,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(ColorOption.roundedSquareRadius - 1),
              border: Border.all(
                color: colorScheme.onSurface.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
          ),
        ),

      const ColorOptionSeparatorIcon(icon: Icons.palette),

      ColorOption(
        isSelected:
            widget.currentColor?.withAlpha(255).toARGB32() ==
            pickedColor.toARGB32(),
        enabled: true,
        onTap: () => openColorPicker(context),
        tooltip: t.editor.colors.colorPicker,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(ColorOption.roundedSquareRadius - 1),
          ),
          child: const Center(child: FaIcon(FontAwesomeIcons.droplet, size: 16)),
        ),
      ),

      for (final namedColor in ColorBar.colorPresets)
        ColorOption(
          isSelected:
              widget.currentColor?.withAlpha(255).toARGB32() ==
              namedColor.color.toARGB32(),
          enabled: widget.currentColor != null,
          onTap: () => widget.setColor(namedColor.color),
          tooltip: namedColor.name,
          child: Container(
            decoration: BoxDecoration(
              color: namedColor.color.withInversion(widget.invert),
              borderRadius: BorderRadius.circular(ColorOption.roundedSquareRadius - 1),
              border: Border.all(
                color: colorScheme.onSurface.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
          ),
        ),
    ];

    return Center(
      child: Padding(
        padding: const .all(8),
        child: SingleChildScrollView(
          scrollDirection: widget.axis,
          child: Flex(direction: widget.axis, children: children),
        ),
      ),
    );
  }

  void openColorPicker(BuildContext context) async {
    final bool? confirmChange = await showDialog(
      context: context,
      builder: (BuildContext context) => _colorPickerDialog(context),
    );
    if (confirmChange ?? false) {
      widget.setColor(pickedColor.withInversion(widget.invert));
    }
  }

  Widget _colorPickerDialog(BuildContext context) => AdaptiveAlertDialog(
    title: Text(t.settings.accentColorPicker.pickAColor),
    content: SingleChildScrollView(
      child: ColorPicker(
        color: pickedColor,
        pickersEnabled: const {ColorPickerType.wheel: true},
        showColorCode: true,
        colorCodeHasColor: true,
        enableOpacity: false,
        onColorChanged: (Color color) {
          pickedColor = color;
        },
      ),
    ),
    actions: [
      CupertinoDialogAction(
        child: Text(MaterialLocalizations.of(context).saveButtonLabel),
        onPressed: () {
          Navigator.of(context).pop(true);
        },
      ),
    ],
  );
}
