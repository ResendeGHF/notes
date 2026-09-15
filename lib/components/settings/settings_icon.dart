// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Leading icon for settings tiles; supports Material and Font Awesome icons.
Widget settingsLeadingIcon(Object? icon, {Key? key}) {
  return switch (icon) {
    FaIconData fa => FaIcon(fa, key: key),
    IconData data => Icon(data, key: key),
    _ => Icon(Icons.settings, key: key),
  };
}
