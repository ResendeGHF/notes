// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Lenient decoding for non-structural DjVu strings (bookmark titles, text
// layers, metadata values).
//
// DjVu itself never validated text encoding, and DjVuLibre writes whatever
// the OS handed it — on Windows that is typically CP1252, so real bundled
// documents carry bytes like 0x96/0x97 (en/em dash) in NAVM bookmark titles.
// Decoding those strictly as UTF-8 would reject files whose every page decodes
// fine. Policy (ported from djvu-rs `src/lenient_text.rs`, MIT): valid UTF-8
// passes through untouched; anything else is decoded as Windows-1252, which
// recovers the intended characters for the overwhelmingly common legacy case
// instead of scattering U+FFFD.
//
// The exact recovery behavior mirrors Rust's `str::from_utf8` error split:
// invalid runs are consumed up to the byte that failed (its position within
// the attempted sequence), and a sequence truncated by end-of-input consumes
// the remaining bytes. See the parity test next to this file.

import 'dart:convert';
import 'dart:typed_data';

/// Decodes [bytes] as UTF-8, decoding invalid byte runs as Windows-1252.
///
/// Works like `utf8.decode(bytes, allowMalformed: true)`, except invalid runs
/// become their CP1252 characters instead of U+FFFD. Valid UTF-8 input is
/// decoded unchanged, and mixed input (UTF-8 text with stray CP1252 bytes —
/// the common "DjVuLibre on Windows edited a UTF-8 file" shape) keeps the
/// UTF-8 parts intact. Never throws.
String decodeDjvuText(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    // Fall through to the lenient scanner; only malformed input pays for it.
  }
  return _decodeMixed(bytes);
}

/// Decodes input known to be invalid UTF-8: valid runs are decoded normally,
/// invalid runs are mapped byte-by-byte through CP1252.
String _decodeMixed(Uint8List bytes) {
  final out = StringBuffer();
  var pos = 0;
  while (pos < bytes.length) {
    final runStart = pos;
    while (pos < bytes.length) {
      final len = _utf8SequenceLength(bytes, pos);
      if (len <= 0) break;
      pos += len;
    }
    if (pos > runStart) {
      out.write(utf8.decode(Uint8List.sublistView(bytes, runStart, pos)));
    }
    if (pos >= bytes.length) break;

    final err = _utf8SequenceLength(bytes, pos);
    if (err == 0) {
      // Sequence truncated by end of input: consume everything that is left.
      for (var i = pos; i < bytes.length; i++) {
        out.writeCharCode(_cp1252CodePoint(bytes[i]));
      }
      break;
    }
    final badLen = -err;
    for (var i = pos; i < pos + badLen; i++) {
      out.writeCharCode(_cp1252CodePoint(bytes[i]));
    }
    pos += badLen;
  }
  return out.toString();
}

/// Scans one UTF-8 sequence at [pos].
///
/// Returns its length (1–4) when valid, `0` when the input ends before the
/// sequence completes, or the negated number of bytes to hand to the CP1252
/// fallback when the sequence is invalid (matching Rust's
/// `Utf8Error::error_len`).
int _utf8SequenceLength(Uint8List bytes, int pos) {
  final b0 = bytes[pos];
  if (b0 < 0x80) return 1;
  // Rejects continuation bytes and the overlong C0/C1 leads, plus F5..FF.
  if (b0 < 0xc2 || b0 > 0xf4) return -1;

  final need = b0 < 0xe0 ? 2 : (b0 < 0xf0 ? 3 : 4);

  if (pos + 1 >= bytes.length) return 0;
  final b1 = bytes[pos + 1];
  if (b1 < 0x80 || b1 > 0xbf) return -1;
  // Overlong / surrogate / out-of-range leads constrain their second byte.
  if (b0 == 0xe0 && b1 < 0xa0) return -1;
  if (b0 == 0xed && b1 > 0x9f) return -1;
  if (b0 == 0xf0 && b1 < 0x90) return -1;
  if (b0 == 0xf4 && b1 > 0x8f) return -1;
  if (need == 2) return 2;

  if (pos + 2 >= bytes.length) return 0;
  final b2 = bytes[pos + 2];
  if (b2 < 0x80 || b2 > 0xbf) return -2;
  if (need == 3) return 3;

  if (pos + 3 >= bytes.length) return 0;
  final b3 = bytes[pos + 3];
  if (b3 < 0x80 || b3 > 0xbf) return -3;
  return 4;
}

/// Maps one Windows-1252 byte to its Unicode code point.
///
/// `0x00..=0x7F` is ASCII and `0xA0..=0xFF` coincides with Latin-1 (= the
/// first 256 Unicode code points); only `0x80..=0x9F` needs the table below.
/// The five bytes CP1252 leaves undefined pass through as their C1 control
/// code points, so the mapping is total (matching the WHATWG index browsers'
/// `TextDecoder` uses).
int _cp1252CodePoint(int byte) =>
    byte < 0x80 || byte >= 0xa0 ? byte : _cp1252C1[byte - 0x80];

/// The `0x80..=0x9F` row of the WHATWG Windows-1252 index.
const _cp1252C1 = [
  0x20ac, // 0x80 €
  0x0081, // 0x81 (undefined in CP1252 — C1 pass-through)
  0x201a, // 0x82 ‚
  0x0192, // 0x83 ƒ
  0x201e, // 0x84 „
  0x2026, // 0x85 …
  0x2020, // 0x86 †
  0x2021, // 0x87 ‡
  0x02c6, // 0x88 ˆ
  0x2030, // 0x89 ‰
  0x0160, // 0x8a Š
  0x2039, // 0x8b ‹
  0x0152, // 0x8c Œ
  0x008d, // 0x8d (undefined — C1 pass-through)
  0x017d, // 0x8e Ž
  0x008f, // 0x8f (undefined — C1 pass-through)
  0x0090, // 0x90 (undefined — C1 pass-through)
  0x2018, // 0x91 '
  0x2019, // 0x92 '
  0x201c, // 0x93 "
  0x201d, // 0x94 "
  0x2022, // 0x95 •
  0x2013, // 0x96 –
  0x2014, // 0x97 —
  0x02dc, // 0x98 ˜
  0x2122, // 0x99 ™
  0x0161, // 0x9a š
  0x203a, // 0x9b ›
  0x0153, // 0x9c œ
  0x009d, // 0x9d (undefined — C1 pass-through)
  0x017e, // 0x9e ž
  0x0178, // 0x9f Ÿ
];
