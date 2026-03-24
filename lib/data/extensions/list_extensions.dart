// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

extension ListExtensions<T> on List<T> {
  T? getOrNull(int index) {
    if (index < 0 || index >= length) {
      return null;
    } else {
      return this[index];
    }
  }
}

extension OffsetListExtensions on List<Offset> {
  void shift(Offset offset) {
    for (int i = 0; i < length; i++) {
      this[i] += offset;
    }
  }
}
