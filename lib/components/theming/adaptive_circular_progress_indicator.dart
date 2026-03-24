// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

class AdaptiveCircularProgressIndicator extends CircularProgressIndicator {
  const AdaptiveCircularProgressIndicator({
    super.key,
    super.value,
    super.backgroundColor,
    super.valueColor,
    super.strokeWidth,
    super.semanticsLabel,
    super.semanticsValue,
    super.strokeCap,
    super.strokeAlign,
    super.constraints,
    super.trackGap,
    super.year2023 = false,
    super.padding,
  }) : super();

  static Widget textStyled({double? value, double alpha = 1.0}) => Builder(
    builder: (context) {
      final textStyle = DefaultTextStyle.of(context).style;
      final textSize = textStyle.fontSize ?? 14;
      final textColor = textStyle.color ?? ColorScheme.of(context).onSurface;
      return SizedBox.square(
        dimension: textSize,
        child: AdaptiveCircularProgressIndicator(
          value: value,
          strokeWidth: textSize / 4,
          valueColor: AlwaysStoppedAnimation(
            textColor.withValues(alpha: alpha),
          ),
        ),
      );
    },
  );

}
