// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:stow_codecs/stow_codecs.dart';

enum ThemeVariant {

  material,
  

  amoled,
}

extension ThemeVariantCodec on ThemeVariant {
  static const codec = EnumCodec(ThemeVariant.values);
}

