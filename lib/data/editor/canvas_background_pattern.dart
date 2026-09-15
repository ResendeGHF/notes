// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:saber/i18n/strings.g.dart';
import 'package:stow_codecs/stow_codecs.dart';

enum CanvasBackgroundPattern {

  none(''),

  collegeLtr('college'),

  collegeRtl('college-rtl'),

  lined('lined'),

  grid('grid', requiresClipping: true),

  dots('dots', requiresClipping: true),

  staffs('staffs'),

  tablature('tablature'),

  cornell('cornell'),

  calligraphy('calligraphy', requiresClipping: true),

  calligraphyRegular('calligraphy-regular');

  const CanvasBackgroundPattern(this.name, {this.requiresClipping = false});

  final String name;

  final bool requiresClipping;

  static String localizedName(CanvasBackgroundPattern pattern) {
    switch (pattern) {
      case .none:
        return t.editor.menu.bgPatterns.none;
      case .collegeLtr:
        return t.editor.menu.bgPatterns.college;
      case .collegeRtl:
        return t.editor.menu.bgPatterns.collegeRtl;
      case .lined:
        return t.editor.menu.bgPatterns.lined;
      case .grid:
        return t.editor.menu.bgPatterns.grid;
      case .dots:
        return t.editor.menu.bgPatterns.dots;
      case .staffs:
        return t.editor.menu.bgPatterns.staffs;
      case .tablature:
        return t.editor.menu.bgPatterns.tablature;
      case .cornell:
        return t.editor.menu.bgPatterns.cornell;
      case .calligraphy:
        return 'Calligraphy';
      case .calligraphyRegular:
        return 'Calligraphy (Regular)';
    }
  }

  static const codec = EnumCodec(values);
}
