// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:saber/i18n/strings.g.dart';

extension BoxFitLocalized on BoxFit {
  String get localizedName {
    if (this == .fill) {
      return t.editor.menu.boxFits.fill;
    } else if (this == .cover) {
      return t.editor.menu.boxFits.cover;
    } else if (this == .contain) {
      return t.editor.menu.boxFits.contain;
    } else {
      if (kDebugMode) throw Exception('Untranslated box fit: $this');
      return '';
    }
  }
}
