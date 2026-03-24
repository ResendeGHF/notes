// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

class RedirectingLocalizationDelegate<T> extends LocalizationsDelegate<T> {

  const RedirectingLocalizationDelegate(this._parent);

  final LocalizationsDelegate<T> _parent;

  static const _englishLocale = Locale('en');

  @override
  bool isSupported(Locale locale) {
    return locale.isEsperanto || _parent.isSupported(locale);
  }

  @override
  Future<T> load(Locale locale) {
    assert(
      T != dynamic,
      'You must specify a type for RedirectingLocalizationDelegate.',
    );
    if (locale.isEsperanto) {
      return _parent.load(_englishLocale);
    }
    return _parent.load(locale);
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<T> old) =>
      old is! RedirectingLocalizationDelegate<T> ||
      _parent.shouldReload(old._parent);
}

extension on Locale {
  bool get isEsperanto => languageCode == 'eo';
}
