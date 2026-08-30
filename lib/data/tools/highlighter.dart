// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/i18n/strings.g.dart';

class Highlighter extends Pen {
  static final ValueNotifier<bool> straightLine = ValueNotifier(false);

  Highlighter()
    : super(
        name: t.editor.pens.highlighter,
        sizeMin: 0.5,
        sizeMax: 50,
        sizeStep: 1,
        icon: highlighterIcon,
        options: stows.lastHighlighterOptions.value,
        pressureEnabled: false,
        color: Color(
          stows.lastHighlighterColor.value,
        ).withValues(alpha: stows.highlighterOpacity.value),
        toolId: .highlighter,
      );

  static double get alpha => 1.0;

  static Pen currentHighlighter = Highlighter();

  static const FaIconData highlighterIcon = FontAwesomeIcons.highlighter;
}
