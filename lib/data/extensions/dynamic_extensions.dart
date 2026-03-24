// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:fixnum/fixnum.dart';

extension SafeCastExtensions on Object? {
  int? toIntSafeExt() {
    final value = this;
    if (value == null) return null;
    if (value is int) return value;
    if (value is Int64) return value.toInt();
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  double? toDoubleSafeExt() {
    final value = this;
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is Int64) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

int? toIntSafe(dynamic value) => SafeCastExtensions(value).toIntSafeExt();
double? toDoubleSafe(dynamic value) => SafeCastExtensions(value).toDoubleSafeExt();

