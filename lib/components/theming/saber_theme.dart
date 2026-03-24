// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:saber/components/theming/font_fallbacks.dart';
import 'package:saber/data/prefs.dart';

const double kSaberContainerRadius = 12.0;

abstract class SaberTheme {
  static ThemeData createTheme(
    ColorScheme colorScheme,
    TargetPlatform platform,
  ) {
    colorScheme = _adjustColorScheme(colorScheme, platform);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: _Components.textTheme(colorScheme.brightness),
      platform: platform,
      progressIndicatorTheme: _Components.progressIndicatorTheme,
      cardColor: colorScheme.surface,
      cardTheme: _Components.cardTheme(colorScheme),
      appBarTheme: _Components.appBarTheme,
    );
  }

  static ThemeData createThemeFromSeed(
    Color seedColor,
    Brightness brightness,
    TargetPlatform platform, {
    @Deprecated(
      'High contrast is not implemented here. '
      'Use ColorScheme.withHighContrast() instead',
    )
    bool highContrast = false,
  }) {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      brightness: brightness,
      seedColor: seedColor,
    );
    return createTheme(colorScheme, platform);
  }

  static ColorScheme _adjustColorScheme(
    ColorScheme colorScheme,
    TargetPlatform platform,
  ) {
    return colorScheme.copyWith(

      surfaceContainer: Color.lerp(
        colorScheme.surface,
        colorScheme.surfaceTint,
        0.02,
      )!,
    );
  }
}

abstract class _Components {
  static TextTheme? textTheme(Brightness brightness) {
    if (stows.hyperlegibleFont.value) {
      return ThemeData(brightness: brightness).textTheme.withFont(
        fontFamily: 'AtkinsonHyperlegibleNext',
        fontFamilyFallback: saberSansSerifFontFallbacks,
      );
    } else {
      return null;
    }
  }

  static const progressIndicatorTheme = ProgressIndicatorThemeData(

    year2023: false,
    stopIndicatorColor: Colors.transparent,
  );

  static CardThemeData cardTheme(ColorScheme colorScheme) {
    return CardThemeData(
      elevation: 0,
      color: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kSaberContainerRadius),
        side: BorderSide(
          color: colorScheme.onSurface.withValues(alpha: 0.12),
          width: 2,
        ),
      ),
    );
  }

  static const appBarTheme = AppBarTheme(centerTitle: false);
}

extension SaberThemePlatform on TargetPlatform {

  bool get isCupertino => false;

  bool get usesYaruColors => false;
}
