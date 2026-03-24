// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

class AdaptiveToggleButtons<T extends Object> extends StatelessWidget {
  const AdaptiveToggleButtons({
    super.key,
    required this.value,
    required this.options,
    required this.onChange,
    this.optionsWidth = 72,
    this.optionsHeight = 40,
  })  : assert(optionsWidth > 0),
        assert(optionsHeight > 0);

  final T value;
  final List<ToggleButtonsOption<T>> options;
  final ValueChanged<T?> onChange;

  final double optionsWidth, optionsHeight;

  @override
  Widget build(BuildContext context) {
    return ToggleButtons(
      borderRadius: BorderRadius.circular(1000),
      constraints: BoxConstraints(
        minWidth: optionsWidth,
        minHeight: optionsHeight,
      ),
      onPressed: (int index) {
        onChange(options[index].value);
      },
      isSelected: [
        for (final ToggleButtonsOption option in options) value == option.value,
      ],
      children: [
        for (final ToggleButtonsOption option in options) option.widget,
      ],
    );
  }
}

class ToggleButtonsOption<T> {
  final T value;
  final Widget widget;

  const ToggleButtonsOption(this.value, this.widget);
}
