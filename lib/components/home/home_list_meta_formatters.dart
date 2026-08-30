// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String formatHomeListBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  var v = bytes / 1024.0;
  if (v < 1024) {
    return '${v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)} KB';
  }
  v /= 1024;
  if (v < 1024) {
    return '${v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)} MB';
  }
  v /= 1024;
  return '${v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)} GB';
}

String formatHomeListDate(BuildContext context, DateTime dt) {
  final locale = Localizations.localeOf(context).toString();
  final now = DateTime.now();
  final pattern = dt.year == now.year ? 'MMM d' : 'MMM d, y';
  return DateFormat(pattern, locale).format(dt);
}
