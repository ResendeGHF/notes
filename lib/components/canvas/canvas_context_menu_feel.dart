// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

/// Shared timing for canvas / image / selection long-press menus.
///
/// Tuned for a Samsung Notes–like feel: recognize quickly, then open with a
/// short fade (no heavy scale/blur) so the card doesn't feel laggy.
abstract final class CanvasContextMenuFeel {
  static const Duration longPressDuration = Duration(milliseconds: 400);

  /// Dialog / overlay open animation.
  static const Duration openDuration = Duration(milliseconds: 70);

  static Widget buildOpenTransition({
    required Animation<double> animation,
    required Widget child,
    Alignment alignment = Alignment.topLeft,
  }) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    // Fade only — ScaleTransition on a tall menu was the heavy hitch.
    return FadeTransition(opacity: curved, child: child);
  }
}
