// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';

/// Tracks tablet vertical navigation rail expansion so the status strip knows
/// when the navbar task card is hidden (icons-only / collapsed rail).
class HomeShellLayout {
  HomeShellLayout._();

  static final ValueNotifier<bool> verticalNavExpanded = ValueNotifier<bool>(
    true,
  );

  /// 0 = collapsed, 1 = expanded. Updated every rail animation tick so Recent
  /// can scale its inset smoothly without other home tabs relayouting.
  static final ValueNotifier<double> verticalNavExpandT = ValueNotifier<double>(
    1,
  );
}
