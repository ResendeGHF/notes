// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

extension StringExtensions on String {

  Future<String> replaceAllMappedAsync(
    Pattern exp,
    Future<String> Function(Match match) replace,
  ) async {
    final buffer = StringBuffer();
    final matches = exp.allMatches(this).toList();

    final replacements = await Future.wait([
      for (final match in matches) replace(match),
    ]);

    int stringIndex = 0;
    for (int matchIndex = 0; matchIndex < matches.length; matchIndex++) {
      final match = matches[matchIndex];
      final prefix = substring(stringIndex, match.start);

      buffer
        ..write(prefix)
        ..write(replacements[matchIndex]);

      stringIndex = match.end;
    }

    buffer.write(substring(stringIndex));
    return buffer.toString();
  }

  String? get ifNotEmpty => isEmpty ? null : this;
}
