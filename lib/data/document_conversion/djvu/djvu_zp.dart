// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// ZP (Z-Prime) adaptive binary arithmetic decoder — pure Dart port.
//
// Ported from djvu-rs (crates/djvu-zp, MIT, https://github.com/matyushkin/djvu-rs),
// a clean-room implementation of the DjVu v3 specification
// (https://www.sndjvu.org/spec.html). Behaviour, including the treatment of
// reads past the end of the input (synthetic 0xFF padding) and the exact
// `syntheticBytes` accounting, matches the reference so that decoded JB2 and
// IW44 streams are bit-identical.

import 'dart:typed_data';

import 'package:saber/data/document_conversion/djvu/djvu_zp_tables.dart';

/// Error thrown when a ZP stream cannot be initialised.
class ZpInitException implements Exception {
  const ZpInitException(this.message);
  final String message;
  @override
  String toString() => 'ZpInitException: $message';
}

/// ZP adaptive binary arithmetic decoder.
///
/// The decoder maintains a probability model per context. A context is a single
/// mutable byte that encodes both the probability state index and the current
/// MPS (most probable symbol) value: the low bit is the MPS, the remaining bits
/// are the state index.
///
/// The `a`/`c`/`fence`/`bitBuf`/`bitCount`/`pos` fields are public so codec
/// hot loops (JB2 row decoders, IW44 coefficient passes) can snapshot them into
/// locals and write them back — exactly like the reference implementation,
/// which extracts them from the struct to keep them in registers.
class ZpDecoder {
  /// Current interval width register (16-bit value in the low 16 bits).
  var a = 0;

  /// Current code register (16-bit value in the low 16 bits).
  var c = 0;

  /// Cached upper bound for the fast decode path (`min(c, 0x7fff)`).
  var fence = 0;

  /// Bit buffer feeding the code register.
  var bitBuf = 0;

  /// Number of valid bits remaining in [bitBuf].
  var bitCount = 0;

  /// Compressed input bytes.
  final Uint8List data;

  /// Current read position within [data].
  ///
  /// Advances by one for every byte the coder consumes, **including synthetic
  /// `0xFF` padding read past the end of [data]**. The overshoot
  /// `pos - data.length` is therefore the number of synthetic bytes read so
  /// far; see [syntheticBytes].
  var pos = 0;

  ZpDecoder(this.data) {
    if (data.length < 2) {
      throw const ZpInitException('ZP input is too short (need at least 2 bytes)');
    }
    // Load the initial code register from the first two bytes.
    final high = _readByte();
    final low = _readByte();
    c = (high << 8) | low;

    // Pre-fill the bit buffer.
    _refillBuffer();

    // Initialise the fence.
    fence = c < 0x7fff ? c : 0x7fff;
  }

  /// Read the next byte from the input stream, returning `0xFF` on exhaustion.
  ///
  /// [pos] advances on every call, even past the end of [data], so that the
  /// overshoot counts synthetic padding (see [syntheticBytes]).
  int _readByte() {
    final b = pos < data.length ? data[pos] : 0xff;
    pos++;
    return b;
  }

  /// Fill [bitBuf] with fresh bytes until it holds at least 24 bits.
  void _refillBuffer() {
    while (bitCount <= 24) {
      bitBuf = ((bitBuf << 8) | _readByte()) & 0xffffffff;
      bitCount += 8;
    }
  }

  /// Number of leading one bits in the low 16 bits of [v].
  static int _leadingOnes16(int v) {
    final m = (~v) & 0xffff;
    return m == 0 ? 16 : 15 - (m.bitLength - 1);
  }

  /// Decode one bit using the adaptive context byte at `ctx[index]`.
  ///
  /// The context is updated in place. Returns `true` if the decoded bit is 1.
  bool decodeBitAt(Uint8List ctx, int index) {
    final state = ctx[index];
    final mpsBit = state & 1;
    final z = a + kZpProb[state];

    // Fast path: interval stays within the fence — no renormalization needed.
    if (z <= fence) {
      a = z;
      return mpsBit != 0;
    }

    // Clamp to the decision boundary.
    final boundary = 0x6000 + ((a + z) >> 2);
    final zClamped = z < boundary ? z : boundary;

    if (zClamped > c) {
      // LPS event: decoded bit is opposite of MPS.
      final lpsBit = 1 - mpsBit;
      final complement = 0x10000 - zClamped;
      a = (a + complement) & 0xffff;
      c = (c + complement) & 0xffff;
      ctx[index] = kZpLpsNext[state];
      _renormalize();
      return lpsBit != 0;
    } else {
      // MPS event: decoded bit matches MPS.
      if (a >= kZpThreshold[state]) {
        ctx[index] = kZpMpsNext[state];
      }
      bitCount -= 1;
      a = (zClamped << 1) & 0xffff;
      c = ((c << 1) | ((bitBuf >> (bitCount & 31)) & 1)) & 0xffff;
      if (bitCount < 16) {
        _refillBuffer();
      }
      fence = c < 0x7fff ? c : 0x7fff;
      return mpsBit != 0;
    }
  }

  /// Renormalize after an LPS event: shift the interval register left until
  /// `a >= 0x8000`, pulling fresh bits into `c` from the bit buffer.
  void _renormalize() {
    final shift = _leadingOnes16(a);
    bitCount -= shift;
    a = (a << shift) & 0xffff;
    final mask = (1 << (shift & 31)) - 1;
    c = ((c << shift) | ((bitBuf >> (bitCount & 31)) & mask)) & 0xffff;
    if (bitCount < 16) {
      _refillBuffer();
    }
    fence = c < 0x7fff ? c : 0x7fff;
  }

  /// Decode one bit in passthrough (context-free) mode.
  ///
  /// Used by BZZ to decode raw integer values. Threshold is
  /// `z = 0x8000 + (a >> 1)`.
  bool decodePassthrough() =>
      _passthroughWithThreshold(0x8000 + (a >> 1));

  /// Decode one bit in IW44 passthrough mode.
  ///
  /// Threshold is `z = 0x8000 + (3 * a / 8)`.
  bool decodePassthroughIw44() =>
      _passthroughWithThreshold(0x8000 + (3 * a) ~/ 8);

  /// Internal passthrough decode with an explicit threshold `z`.
  bool _passthroughWithThreshold(int z) {
    if (z > c) {
      // Bit is 1.
      final complement = 0x10000 - z;
      a = (a + complement) & 0xffff;
      c = (c + complement) & 0xffff;
      _renormalize();
      return true;
    } else {
      // Bit is 0.
      bitCount -= 1;
      a = (z * 2) & 0xffff;
      c = ((c << 1) | ((bitBuf >> (bitCount & 31)) & 1)) & 0xffff;
      if (bitCount < 16) {
        _refillBuffer();
      }
      fence = c < 0x7fff ? c : 0x7fff;
      return false;
    }
  }

  /// Whether all real input bytes have been consumed.
  ///
  /// After exhaustion the coder returns `0xFF` bytes indefinitely, producing
  /// deterministic but meaningless bits.
  bool get isExhausted => pos >= data.length;

  /// Number of synthetic `0xFF` bytes read past the end of the real input.
  ///
  /// Unlike [isExhausted], which flips as soon as the byte buffer drains —
  /// several bytes before the logical end of the arithmetic stream, because
  /// the decoder buffers up to 32 bits of look-ahead — this counts only
  /// genuine post-EOF padding reads. It lets a caller tell "finishing the last
  /// buffered bits of a valid stream" (a handful of synthetic bytes) apart
  /// from "spinning on exhausted input" (unbounded).
  int get syntheticBytes => pos > data.length ? pos - data.length : 0;
}
