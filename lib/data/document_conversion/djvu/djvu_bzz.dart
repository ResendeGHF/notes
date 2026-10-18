// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// BZZ decompressor — pure Dart port.
//
// BZZ is the block-sorting compression used by DjVu for directory and
// annotation chunks (DIRM metadata, NAVM, ANTz, TXTz) and for FGbz index
// tables. It combines ZP adaptive arithmetic coding, a move-to-front
// transform and an inverse Burrows-Wheeler transform.
//
// Ported from djvu-rs (crates/djvu-bzz, MIT, https://github.com/matyushkin/djvu-rs),
// a clean-room implementation of the DjVu v3 specification
// (https://www.sndjvu.org/spec.html). Decoded bytes are identical to the
// reference, including its guards against decompression bombs.

import 'dart:typed_data';

import 'package:saber/data/document_conversion/djvu/djvu_zp.dart';
import 'package:saber/data/document_conversion/djvu/djvu_zp_tables.dart';

/// Thrown when a BZZ stream is malformed, truncated, or unreasonably large.
class BzzException implements Exception {
  const BzzException(this.message);
  final String message;
  @override
  String toString() => 'BzzException: $message';
}

/// Number of ZP contexts used by the MTF position hierarchy.
///
/// - 3 contexts for level 0 (MTF position 0)
/// - 3 contexts for level 1 (MTF position 1)
/// - 1 context + 1 sub-tree for level 2 (positions 2–3)
/// - … up to level 8; total 3 + 3 + 2 + 4 + 8 + 16 + 32 + 64 + 128 = 260,
///   plus the terminator context. 300 slots leave headroom, matching the
///   reference allocation and keeping indexing identical.
const _bzzCtxCount = 300;

/// Number of "frequency" slots tracked in the MTF order.
const _bzzFreqSlots = 4;

/// Number of context ids used for the first two MTF levels.
const _bzzLevelCtxIds = 3;

/// Maximum allowed block size (4 MB), matching DjVuLibre's MAXBLOCK.
const _bzzMaxBlockSize = 4 * 1024 * 1024;

/// Maximum allowed total decompressed output size (256 MB).
const _bzzMaxOutputSize = 256 * 1024 * 1024;

/// Post-EOF spin guard: byte overshoot tolerated before a block is declared
/// truncated (see the reference `ZP_EOF_SLACK_BYTES`).
const _bzzZpEofSlackBytes = 16;

/// How often the MTF hot loop checks the spin guard.
const _bzzSpinCheckInterval = 4096;

/// Decompresses a BZZ stream.
///
/// Throws [BzzException] on malformed or truncated input.
Uint8List bzzDecode(Uint8List data) {
  final zp = _zpDecoderFor(data);
  final out = BytesBuilder(copy: false);
  final ctx = Uint8List(_bzzCtxCount);
  var total = 0;

  while (true) {
    final blockSize = _decodeRawBits(zp, 24);
    if (blockSize == 0) break;
    if (blockSize > _bzzMaxBlockSize) {
      throw BzzException('BZZ block size $blockSize exceeds the 4 MB limit');
    }
    final block = _decodeOneBlock(zp, ctx, blockSize);
    total += block.length;
    if (total > _bzzMaxOutputSize) {
      throw const BzzException('BZZ output exceeds the 256 MB limit');
    }
    out.add(block);
  }
  return out.takeBytes();
}

/// Decodes a BZZ stream into its per-block BWT data and marker positions,
/// without applying the inverse BWT.
///
/// Exposed so parity tests can compare against the reference implementation at
/// the intermediate stage, where a mismatch is much easier to localise.
List<(Uint8List, int)> bzzDecodeBwtBlocks(Uint8List data) {
  final zp = _zpDecoderFor(data);
  final ctx = Uint8List(_bzzCtxCount);
  final blocks = <(Uint8List, int)>[];
  var total = 0;

  while (true) {
    final blockSize = _decodeRawBits(zp, 24);
    if (blockSize == 0) break;
    if (blockSize > _bzzMaxBlockSize) {
      throw BzzException('BZZ block size $blockSize exceeds the 4 MB limit');
    }
    total += blockSize;
    if (total > _bzzMaxOutputSize) {
      throw const BzzException('BZZ output exceeds the 256 MB limit');
    }
    blocks.add(_decodeMtfPhase(zp, ctx, blockSize));
  }
  return blocks;
}

/// Wraps [ZpDecoder] construction and maps its init error to [BzzException].
ZpDecoder _zpDecoderFor(Uint8List data) {
  try {
    return ZpDecoder(data);
  } on ZpInitException catch (e) {
    throw BzzException(e.message);
  }
}

/// Decodes `bitCount` raw bits from the ZP stream in passthrough mode,
/// MSB-first (arithmetic tree technique).
int _decodeRawBits(ZpDecoder zp, int bitCount) {
  final limit = 1 << bitCount;
  var n = 1;
  while (n < limit) {
    final bit = zp.decodePassthrough() ? 1 : 0;
    n = (n << 1) | bit;
  }
  return n - limit;
}

/// Decodes one BZZ block: ZP + inverse MTF, then inverse BWT.
///
/// The ZP contexts are shared across the whole stream; MTF and BWT state are
/// per block.
Uint8List _decodeOneBlock(ZpDecoder zp, Uint8List ctx, int blockSize) {
  final (bwtData, markerPos) = _decodeMtfPhase(zp, ctx, blockSize);
  return _inverseBwt(bwtData, markerPos);
}

/// ZP + MTF decode phase; returns the BWT-encoded bytes and the marker index.
///
/// The ZP state is snapshotted into locals at the top so the hot loop works on
/// plain integers, then written back — mirroring the reference implementation.
(Uint8List, int) _decodeMtfPhase(ZpDecoder zp, Uint8List ctx, int blockSize) {
  var a = zp.a;
  var c = zp.c;
  var fence = c < 0x7fff ? c : 0x7fff;
  var bitBuf = zp.bitBuf;
  var bitCount = zp.bitCount;
  final data = zp.data;
  var pos = zp.pos;

  int readByte() {
    final b = pos < data.length ? data[pos] : 0xff;
    pos++;
    return b;
  }

  void refill() {
    while (bitCount <= 24) {
      bitBuf = ((bitBuf << 8) | readByte()) & 0xffffffff;
      bitCount += 8;
    }
  }

  void renorm() {
    // Number of leading ones in the low 16 bits of `a`.
    final m = (~a) & 0xffff;
    final shift = m == 0 ? 16 : 15 - (m.bitLength - 1);
    bitCount -= shift;
    a = (a << shift) & 0xffff;
    final mask = (1 << (shift & 31)) - 1;
    c = ((c << shift) | ((bitBuf >> (bitCount & 31)) & mask)) & 0xffff;
    if (bitCount < 16) refill();
    fence = c < 0x7fff ? c : 0x7fff;
  }

  bool decodeBit(int ctxIndex) {
    final state = ctx[ctxIndex];
    final mps = state & 1;
    final z = a + kZpProb[state];
    if (z <= fence) {
      a = z;
      return mps != 0;
    }
    final boundary = 0x6000 + ((a + z) >> 2);
    final zClamped = z < boundary ? z : boundary;
    if (zClamped > c) {
      final complement = 0x10000 - zClamped;
      a = (a + complement) & 0xffff;
      c = (c + complement) & 0xffff;
      ctx[ctxIndex] = kZpLpsNext[state];
      renorm();
      return (1 - mps) != 0;
    } else {
      if (a >= kZpThreshold[state]) {
        ctx[ctxIndex] = kZpMpsNext[state];
      }
      bitCount -= 1;
      a = (zClamped << 1) & 0xffff;
      c = ((c << 1) | ((bitBuf >> (bitCount & 31)) & 1)) & 0xffff;
      if (bitCount < 16) refill();
      fence = c < 0x7fff ? c : 0x7fff;
      return mps != 0;
    }
  }

  bool decodePassthrough() {
    final z = 0x8000 + (a >> 1);
    if (z > c) {
      final complement = 0x10000 - z;
      a = (a + complement) & 0xffff;
      c = (c + complement) & 0xffff;
      renorm();
      return true;
    } else {
      bitCount -= 1;
      a = (z * 2) & 0xffff;
      c = ((c << 1) | ((bitBuf >> (bitCount & 31)) & 1)) & 0xffff;
      if (bitCount < 16) refill();
      fence = c < 0x7fff ? c : 0x7fff;
      return false;
    }
  }

  /// Decodes `nBits` bits from the context sub-tree rooted at `ctx[base - 1]`.
  int decodeCtxBits(int base, int nBits) {
    final subtreeOffset = base - 1;
    final limit = 1 << nBits;
    var nn = 1;
    while (nn < limit) {
      final bit = decodeBit(subtreeOffset + nn) ? 1 : 0;
      nn = (nn << 1) | bit;
    }
    return nn - limit;
  }

  // Frequency-shift parameter (0, 1 or 2).
  var freqShift = 0;
  if (decodePassthrough()) {
    freqShift += 1;
    if (decodePassthrough()) freqShift += 1;
  }

  // Per-block MTF state.
  final mtfOrder = Uint8List(256);
  for (var i = 0; i < 256; i++) {
    mtfOrder[i] = i;
  }
  final freqCounts = Uint32List(_bzzFreqSlots);
  var freqAdd = 4;
  var lastMtfPos = 3;
  var markerAt = -1;

  final bwtData = Uint8List(blockSize);

  for (var symIdx = 0; symIdx < blockSize; symIdx++) {
    // Spin guard: bail once the coder has been reading synthetic padding for
    // a while, instead of decoding megabytes out of a few real bytes.
    if (symIdx % _bzzSpinCheckInterval == 0 &&
        pos - data.length > _bzzZpEofSlackBytes) {
      throw const BzzException('BZZ stream is truncated');
    }

    final ctxId = lastMtfPos < _bzzLevelCtxIds ? lastMtfPos : _bzzLevelCtxIds - 1;

    int mtfPosition;
    var ctxOffset = 0;
    if (decodeBit(ctxOffset + ctxId)) {
      mtfPosition = 0;
    } else {
      ctxOffset += _bzzLevelCtxIds;
      if (decodeBit(ctxOffset + ctxId)) {
        mtfPosition = 1;
      } else {
        ctxOffset += _bzzLevelCtxIds;
        if (decodeBit(ctxOffset)) {
          mtfPosition = 2 + decodeCtxBits(ctxOffset + 1, 1);
        } else {
          ctxOffset += 2;
          if (decodeBit(ctxOffset)) {
            mtfPosition = 4 + decodeCtxBits(ctxOffset + 1, 2);
          } else {
            ctxOffset += 4;
            if (decodeBit(ctxOffset)) {
              mtfPosition = 8 + decodeCtxBits(ctxOffset + 1, 3);
            } else {
              ctxOffset += 8;
              if (decodeBit(ctxOffset)) {
                mtfPosition = 16 + decodeCtxBits(ctxOffset + 1, 4);
              } else {
                ctxOffset += 16;
                if (decodeBit(ctxOffset)) {
                  mtfPosition = 32 + decodeCtxBits(ctxOffset + 1, 5);
                } else {
                  ctxOffset += 32;
                  if (decodeBit(ctxOffset)) {
                    mtfPosition = 64 + decodeCtxBits(ctxOffset + 1, 6);
                  } else {
                    ctxOffset += 64;
                    if (decodeBit(ctxOffset)) {
                      mtfPosition = 128 + decodeCtxBits(ctxOffset + 1, 7);
                    } else {
                      mtfPosition = 256;
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    lastMtfPos = mtfPosition;

    if (mtfPosition == 256) {
      bwtData[symIdx] = 0;
      markerAt = symIdx;
      continue;
    }

    final sym = mtfOrder[mtfPosition];
    bwtData[symIdx] = sym;

    freqAdd = (freqAdd + (freqAdd >> freqShift)) & 0xffffffff;
    if (freqAdd > 0x10000000) {
      freqAdd >>= 24;
      for (var i = 0; i < _bzzFreqSlots; i++) {
        freqCounts[i] >>= 24;
      }
    }

    var combinedFreq = freqAdd;
    if (mtfPosition < _bzzFreqSlots) {
      combinedFreq += freqCounts[mtfPosition];
    }

    // Move the symbol to its frequency-ordered slot.
    var insertAt = mtfPosition;
    if (insertAt >= _bzzFreqSlots) {
      // Equivalent to Rust's `copy_within(3..insertAt, 4)`: shift elements
      // 3..insertAt-1 up by one. Dart's `setRange` end is exclusive, so the
      // destination must run to `insertAt + 1`.
      mtfOrder.setRange(
        _bzzFreqSlots,
        insertAt + 1,
        mtfOrder,
        _bzzFreqSlots - 1,
      );
      insertAt = _bzzFreqSlots - 1;
    }
    while (insertAt > 0) {
      final prevFreq = freqCounts[insertAt - 1];
      if (combinedFreq >= prevFreq) {
        mtfOrder[insertAt] = mtfOrder[insertAt - 1];
        freqCounts[insertAt] = prevFreq;
        insertAt -= 1;
      } else {
        break;
      }
    }
    mtfOrder[insertAt] = sym;
    freqCounts[insertAt] = combinedFreq;
  }

  // Write the ZP state back so the next block continues the same stream.
  zp.a = a;
  zp.c = c;
  zp.fence = fence;
  zp.bitBuf = bitBuf;
  zp.bitCount = bitCount;
  zp.pos = pos;

  if (markerAt < 0) {
    throw const BzzException('BZZ block is missing its end marker');
  }
  return (bwtData, markerAt);
}

/// Inverse Burrows-Wheeler transform.
///
/// `bwtData` is the BWT-encoded block; `markerPos` is the position of the
/// end-of-block marker. The output has length `bwtData.length - 1`.
Uint8List _inverseBwt(Uint8List bwtData, int markerPos) {
  final total = bwtData.length;
  if (total == 0) return Uint8List(0);

  // Count occurrences of each byte value (excluding the marker position) and
  // build the rank array, encoding (byteValue << 24) | occurrenceIndex.
  final byteCount = Uint32List(256);
  final rank = Uint32List(total);
  for (var i = 0; i < total; i++) {
    if (i == markerPos) continue;
    final byteVal = bwtData[i];
    rank[i] = (byteVal << 24) | (byteCount[byteVal] & 0x00ffffff);
    byteCount[byteVal] += 1;
  }

  // Sorted starting positions; position 0 is reserved for the marker.
  final sortedStart = Uint32List(256);
  var running = 1;
  for (var byteVal = 0; byteVal < 256; byteVal++) {
    sortedStart[byteVal] = running;
    running += byteCount[byteVal];
  }

  final outputLen = total - 1;
  final output = Uint8List(outputLen);
  var follow = 0;
  var remaining = outputLen;
  while (remaining > 0) {
    final encoded = rank[follow];
    final byteVal = (encoded >> 24) & 0xff;
    final occurrence = encoded & 0x00ffffff;
    remaining -= 1;
    output[remaining] = byteVal;
    follow = sortedStart[byteVal] + occurrence;
  }
  return output;
}
