// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

class MapStringIntCodec extends Codec<Map<String, int>, Object?> {
  const MapStringIntCodec();

  @override
  Converter<Map<String, int>, Object?> get encoder =>
      const _MapStringIntEncoder();

  @override
  Converter<Object?, Map<String, int>> get decoder =>
      const _MapStringIntDecoder();
}

class _MapStringIntEncoder extends Converter<Map<String, int>, Object?> {
  const _MapStringIntEncoder();

  @override
  Object? convert(Map<String, int> input) => input;
}

class _MapStringIntDecoder extends Converter<Object?, Map<String, int>> {
  const _MapStringIntDecoder();

  @override
  Map<String, int> convert(Object? input) {
    if (input is! Map) return {};
    return input.map((key, val) => MapEntry(key.toString(), val as int));
  }
}

