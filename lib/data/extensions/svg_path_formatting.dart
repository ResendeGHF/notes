// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

/// Formats a number for SVG path `d` data passed to [package:path_parsing] /
/// [package:pdf]'s path lexer.
///
/// Raw [double.toString] can use scientific notation (`1e-57`). In path data,
/// `e` starts an exponent token; [package:path_parsing] also rejects exponent
/// magnitudes outside `[-37, 38]`, which triggers `Invalid exponent`.
String formatSvgPathDouble(double value) {
  if (!value.isFinite) return '0';
  var s = value.toStringAsFixed(6);
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '');
    s = s.replaceAll(RegExp(r'\.$'), '');
  }
  if (s == '-0') return '0';
  return s;
}
