// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

/// Lightweight easing helpers for stroke width / taper curves.
abstract final class StrokeEasings {
  static double identity(double t) => t;

  static double easeInOut(double t) => t * (2 - t);

  static double easeOutCubic(double t) => --t * t * t + 1;

  static double easeInQuad(double t) => t * t;

  static double easeOutQuad(double t) => t * (2 - t);

  static double easeInCubic(double t) => t * t * t;

  static double easeInOutCubic(double t) {
    return t < 0.5 ? 4 * t * t * t : 1 - mathPow(-2 * t + 2, 3) / 2;
  }

  static double mathPow(double x, int e) {
    var r = 1.0;
    for (var i = 0; i < e; i++) {
      r *= x;
    }
    return r;
  }
}

/// Named easing catalog for Advanced pen prefs / presets.
abstract final class StrokeEasingCatalog {
  static const identity = 'identity';
  static const easeInOut = 'easeInOut';
  static const easeOutCubic = 'easeOutCubic';
  static const easeInQuad = 'easeInQuad';
  static const easeOutQuad = 'easeOutQuad';
  static const easeInCubic = 'easeInCubic';
  static const easeInOutCubic = 'easeInOutCubic';

  static const List<String> ids = [
    identity,
    easeInOut,
    easeOutCubic,
    easeInQuad,
    easeOutQuad,
    easeInCubic,
    easeInOutCubic,
  ];

  /// Reverse-lookup for isolate snapshots. Unknown closures map to [identity].
  static String idOf(double Function(double) easing) {
    if (identical(easing, StrokeEasings.easeInOut)) return easeInOut;
    if (identical(easing, StrokeEasings.easeOutCubic)) return easeOutCubic;
    if (identical(easing, StrokeEasings.easeInQuad)) return easeInQuad;
    if (identical(easing, StrokeEasings.easeOutQuad)) return easeOutQuad;
    if (identical(easing, StrokeEasings.easeInCubic)) return easeInCubic;
    if (identical(easing, StrokeEasings.easeInOutCubic)) return easeInOutCubic;
    if (identical(easing, StrokeEasings.identity)) return identity;
    return identity;
  }

  static double Function(double) byId(String? id) {
    switch (id) {
      case easeInOut:
        return StrokeEasings.easeInOut;
      case easeOutCubic:
        return StrokeEasings.easeOutCubic;
      case easeInQuad:
        return StrokeEasings.easeInQuad;
      case easeOutQuad:
        return StrokeEasings.easeOutQuad;
      case easeInCubic:
        return StrokeEasings.easeInCubic;
      case easeInOutCubic:
        return StrokeEasings.easeInOutCubic;
      case identity:
      default:
        return StrokeEasings.identity;
    }
  }

  static String label(String id) {
    switch (id) {
      case easeInOut:
        return 'Ease in-out';
      case easeOutCubic:
        return 'Ease out cubic';
      case easeInQuad:
        return 'Ease in quad';
      case easeOutQuad:
        return 'Ease out quad';
      case easeInCubic:
        return 'Ease in cubic';
      case easeInOutCubic:
        return 'Ease in-out cubic';
      case identity:
      default:
        return 'Linear';
    }
  }
}
