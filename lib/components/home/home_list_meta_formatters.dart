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

/// Unified home timestamp formatter: single source for list rows, folder
/// rows and the properties dialog. Relative labels keep recent notes
/// scannable (Today/Yesterday/weekday) while older notes fall back to
/// locale date patterns. Times use the device locale HH:mm form.
String formatHomeListDate(BuildContext context, DateTime dt) {
  final locale = Localizations.localeOf(context).toString();
  final isPt = locale.toLowerCase().startsWith('pt');
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final thatDay = DateTime(dt.year, dt.month, dt.day);
  final dayDiff = today.difference(thatDay).inDays;
  final time = DateFormat.Hm(locale).format(dt);

  if (dayDiff == 0) return isPt ? 'Hoje $time' : 'Today $time';
  if (dayDiff == 1) return isPt ? 'Ontem $time' : 'Yesterday $time';
  if (dayDiff > 1 && dayDiff < 7) {
    // Weekday + time, e.g. "seg 14:32" / "Mon 2:32 PM".
    return '${DateFormat.E(locale).format(dt)} $time';
  }
  final pattern = dt.year == now.year ? 'MMM d' : 'MMM d, y';
  return DateFormat(pattern, locale).format(dt);
}

/// Full timestamp for tooltips and the properties dialog, e.g.
/// "Today 14:32 · 14 Oct 2026" / "Hoje 14:32 · 14 out 2026".
String formatHomeListDateFull(BuildContext context, DateTime dt) {
  final locale = Localizations.localeOf(context).toString();
  final now = DateTime.now();
  final pattern = dt.year == now.year ? 'd MMM' : 'd MMM y';
  return '${formatHomeListDate(context, dt)} · ${DateFormat(pattern, locale).format(dt)}';
}
