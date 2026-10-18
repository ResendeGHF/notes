// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// FGbz foreground-palette parser.
//
// The FGbz chunk pairs the JB2 foreground mask with a small palette and a
// per-blit color index for layered (compound) DjVu images: the mask's blit
// records index into this table instead of painting plain black.
//
// Ported from djvu-rs `src/fgbz.rs` (MIT, https://github.com/matyushkin/djvu-rs).

import 'dart:typed_data';

import 'package:saber/data/document_conversion/djvu/djvu_bzz.dart';
import 'package:saber/data/document_conversion/djvu/djvu_color.dart';

/// Parsed FGbz data: palette colors and optional per-blit color indices.
class DjvuFgbzPalette {
  const DjvuFgbzPalette(this.colors, this.indices);

  const DjvuFgbzPalette.empty() : colors = const [], indices = const [];

  /// Palette entries, in chunk order.
  final List<DjvuColor> colors;

  /// Per-blit color index: `indices[blitIdx]` selects from [colors]. Empty
  /// when the chunk has no index table (version bit 7 unset).
  final List<int> indices;
}

/// Parses an FGbz chunk payload.
///
/// Format:
/// - byte 0: version (bit 7 = has index table, bits 6–0 normally 0)
/// - bytes 1–2: big-endian u16 palette size (number of colors)
/// - next `paletteSize * 3` bytes: BGR triples (truncated entries become
///   black, matching the reference)
/// - if bit 7: 3-byte big-endian count + BZZ-compressed big-endian i16 index
///   table
///
/// Throws [BzzException] when the index table is not a valid BZZ stream.
DjvuFgbzPalette parseFgbzPalette(Uint8List data) {
  if (data.length < 3) return const DjvuFgbzPalette.empty();
  final version = data[0];
  final hasIndices = (version & 0x80) != 0;
  final colorCount = (data[1] << 8) | data[2];
  if (colorCount == 0) return const DjvuFgbzPalette.empty();

  final colorBytes = colorCount * 3;
  final availableColors = data.length - 3 < colorBytes
      ? data.length - 3
      : colorBytes;
  final colors = <DjvuColor>[];
  for (var i = 0; i < colorCount; i++) {
    final base = 3 + i * 3;
    if (i * 3 + 2 < availableColors) {
      // Stored BGR, exposed RGB.
      colors.add(DjvuColor(data[base + 2], data[base + 1], data[base]));
    } else {
      colors.add(const DjvuColor(0, 0, 0));
    }
  }

  var indices = const <int>[];
  if (hasIndices) {
    final indexStart = 3 + colorBytes;
    if (indexStart + 3 <= data.length) {
      final count =
          (data[indexStart] << 16) |
          (data[indexStart + 1] << 8) |
          data[indexStart + 2];
      final decoded = bzzDecode(Uint8List.sublistView(data, indexStart + 3));
      // The count is a raw 24-bit field; the payload bounds the real number.
      final maxEntries = decoded.length >> 1;
      final n = count < maxEntries ? count : maxEntries;
      indices = List<int>.generate(n, (i) {
        final v = (decoded[i * 2] << 8) | decoded[i * 2 + 1];
        return v >= 0x8000 ? v - 0x10000 : v;
      });
    }
  }

  return DjvuFgbzPalette(colors, indices);
}
