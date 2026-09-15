// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:saber/services/math_engine/math_engine.dart';

String normalizePlotMathInput(String input) {
  return input
      .trim()
      .replaceAll('×', '*')
      .replaceAll('÷', '/')
      .replaceAll('π', 'pi')
      .replaceAll('√', 'sqrt');
}

double? parsePlotRealExpression(
  ComplexParser parser,
  String input, {
  Map<String, Complex> variables = const {},
}) {
  final normalized = normalizePlotMathInput(input);
  if (normalized.isEmpty) return null;
  try {
    final value = parser.evaluate(normalized, variables: variables);
    if (!value.real.isFinite || value.imag.abs() > 1e-8) {
      return null;
    }
    return value.real;
  } catch (_) {
    return null;
  }
}

double parsePlotRealExpressionOrFallback(
  ComplexParser parser,
  String input,
  double fallback, {
  Map<String, Complex> variables = const {},
}) {
  return parsePlotRealExpression(parser, input, variables: variables) ??
      fallback;
}

double? parsePlotOptionalBound(ComplexParser parser, String input) {
  return parsePlotRealExpression(parser, input);
}
