// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:saber/components/theming/font_fallbacks.dart';
import 'package:saber/data/prefs.dart';

const double kSaberContainerRadius = 12.0;

abstract class SaberTheme {
  /// Sentinel accent seed that selects a true Material 3 monochrome scheme
  /// (only grays, white and black — no hue). Pure black is not part of the
  /// regular accent palette, so it can never be picked by accident.
  static const monoAccentSeed = Color(0xFF000000);

  static bool isMonoSeed(Color seed) =>
      seed.toARGB32() == monoAccentSeed.toARGB32();

  static ThemeData createTheme(
    ColorScheme colorScheme,
    TargetPlatform platform, {
    bool pureBlack = false,
  }) {
    if (pureBlack && colorScheme.brightness == Brightness.dark) {
      colorScheme = _applyPureBlack(colorScheme);
    } else {
      colorScheme = _adjustColorScheme(colorScheme, platform);
    }

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
    bool pureBlack = false,
    @Deprecated(
      'High contrast is not implemented here. '
      'Use ColorScheme.withHighContrast() instead',
    )
    bool highContrast = false,
  }) {
    // Grayscale-only option: Material 3 monochrome variant has zero chroma,
    // so buttons/surfaces stay gray/white/black instead of picking up the
    // blue/green tint that `tonalSpot` derives even from neutral gray seeds.
    final ColorScheme colorScheme = isMonoSeed(seedColor)
        ? ColorScheme.fromSeed(
            brightness: brightness,
            seedColor: seedColor,
            dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
          )
        : ColorScheme.fromSeed(
            brightness: brightness,
            seedColor: seedColor,
          );
    return createTheme(colorScheme, platform, pureBlack: pureBlack);
  }

  /// AMOLED / pure black variant for the dark theme.
  ///
  /// Keeps the seeded accent ([primary], [secondary], etc.) untouched so any
  /// accent color — including neutrals/greys — stays legible, but replaces
  /// every dark surface with true black (or near-black for elevation levels)
  /// so pixels can turn off on OLED screens.
  static ColorScheme _applyPureBlack(ColorScheme colorScheme) {
    return colorScheme.copyWith(
      surface: Colors.black,
      surfaceDim: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: Colors.black,
      surfaceContainer: Colors.black,
      surfaceContainerHigh: const Color(0xFF0E0E0E),
      surfaceContainerHighest: const Color(0xFF141414),
      surfaceBright: const Color(0xFF3A3A3A),
      // Keep inverseSurface light so tooltips/snackbars still contrast.
      inverseSurface: const Color(0xFFE6E6E6),
      inversePrimary: colorScheme.primary,
      scrim: Colors.black,
    );
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
