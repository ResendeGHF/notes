// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/document_conversion/djvu/djvu_bzz.dart';
import 'package:saber/data/document_conversion/djvu/djvu_iff.dart';
import 'package:saber/data/document_conversion/djvu/djvu_zp.dart';

import 'djvu/djvu_fixture.dart';

/// Reference MTF phase re-implemented on top of the public [ZpDecoder] API,
/// with a full trace, to compare against the Rust/Python reference per call.
(Uint8List, int) mtfWithPublicApi(
  Uint8List data,
  int blockSize, {
  List<List<Object>>? trace,
}) {
  final zp = ZpDecoder(data);
  final ctx = Uint8List(300);

  int decodeRawBits(int bitCount) {
    final limit = 1 << bitCount;
    var n = 1;
    while (n < limit) {
      final bit = zp.decodePassthrough() ? 1 : 0;
      trace?.add(['pt', zp.a, zp.c, zp.fence, zp.bitCount, zp.pos]);
      n = (n << 1) | bit;
    }
    return n - limit;
  }

  int decodeBit(int index) {
    trace?.add([
      'bit',
      index,
      ctx[index],
      zp.a,
      zp.c,
      zp.fence,
      zp.bitCount,
      zp.pos,
    ]);
    return zp.decodeBitAt(ctx, index) ? 1 : 0;
  }

  int decodeCtxBits(int base, int nBits) {
    final subtreeOffset = base - 1;
    final limit = 1 << nBits;
    var nn = 1;
    while (nn < limit) {
      final bit = decodeBit(subtreeOffset + nn);
      nn = (nn << 1) | bit;
    }
    return nn - limit;
  }

  final gotBlockSize = decodeRawBits(24);
  expect(gotBlockSize, blockSize);
  trace?.add(['blocksize', blockSize]);

  var freqShift = 0;
  if (zp.decodePassthrough()) {
    trace?.add(['pt', zp.a, zp.c, zp.fence, zp.bitCount, zp.pos]);
    freqShift += 1;
    if (zp.decodePassthrough()) {
      trace?.add(['pt', zp.a, zp.c, zp.fence, zp.bitCount, zp.pos]);
      freqShift += 1;
    }
  } else {
    trace?.add(['pt', zp.a, zp.c, zp.fence, zp.bitCount, zp.pos]);
  }
  trace?.add(['freq_shift', freqShift]);

  final mtfOrder = Uint8List(256);
  for (var i = 0; i < 256; i++) {
    mtfOrder[i] = i;
  }
  final freqCounts = Uint32List(4);
  var freqAdd = 4;
  var lastMtfPos = 3;
  var markerAt = -1;
  final bwtData = Uint8List(blockSize);

  for (var symIdx = 0; symIdx < blockSize; symIdx++) {
    final ctxId = lastMtfPos < 3 ? lastMtfPos : 2;
    int mtfPosition;
    var ctxOffset = 0;
    if (decodeBit(ctxOffset + ctxId) != 0) {
      mtfPosition = 0;
    } else {
      ctxOffset += 3;
      if (decodeBit(ctxOffset + ctxId) != 0) {
        mtfPosition = 1;
      } else {
        ctxOffset += 3;
        if (decodeBit(ctxOffset) != 0) {
          mtfPosition = 2 + decodeCtxBits(ctxOffset + 1, 1);
        } else {
          ctxOffset += 2;
          if (decodeBit(ctxOffset) != 0) {
            mtfPosition = 4 + decodeCtxBits(ctxOffset + 1, 2);
          } else {
            ctxOffset += 4;
            if (decodeBit(ctxOffset) != 0) {
              mtfPosition = 8 + decodeCtxBits(ctxOffset + 1, 3);
            } else {
              ctxOffset += 8;
              if (decodeBit(ctxOffset) != 0) {
                mtfPosition = 16 + decodeCtxBits(ctxOffset + 1, 4);
              } else {
                ctxOffset += 16;
                if (decodeBit(ctxOffset) != 0) {
                  mtfPosition = 32 + decodeCtxBits(ctxOffset + 1, 5);
                } else {
                  ctxOffset += 32;
                  if (decodeBit(ctxOffset) != 0) {
                    mtfPosition = 64 + decodeCtxBits(ctxOffset + 1, 6);
                  } else {
                    ctxOffset += 64;
                    if (decodeBit(ctxOffset) != 0) {
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
    trace?.add([
      'mtf',
      symIdx,
      mtfPosition,
      mtfOrder[mtfPosition == 256 ? 0 : mtfPosition],
    ]);
    trace?.add([
      'order',
      ...mtfOrder.sublist(0, 16),
      ...freqCounts,
    ]);
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
      for (var i = 0; i < 4; i++) {
        freqCounts[i] >>= 24;
      }
    }
    var combinedFreq = freqAdd;
    if (mtfPosition < 4) combinedFreq += freqCounts[mtfPosition];
    var insertAt = mtfPosition;
    if (insertAt >= 4) {
      mtfOrder.setRange(4, insertAt, mtfOrder, 3);
      insertAt = 3;
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
  return (bwtData, markerAt);
}

void main() {
  test('debug dump', () {
    final raw = readDjvuRef('bilevel', 'root.DIRM.bin');
    final dirm = parseDirmPayload(raw);

    final blocks = bzzDecodeBwtBlocks(dirm.metadata);
    for (var i = 0; i < blocks.length; i++) {
      final (bwt, marker) = blocks[i];
      File('/tmp/opencode/dirm.dart.bwt$i.bin').writeAsBytesSync(bwt);
      File('/tmp/opencode/dirm.dart.marker$i').writeAsStringSync('$marker');
    }

    final trace = <List<Object>>[];
    final (pubBwt, pubMarker) = mtfWithPublicApi(
      dirm.metadata,
      115,
      trace: trace,
    );
    File('/tmp/opencode/dirm.pubapi.bwt.bin').writeAsBytesSync(pubBwt);
    File('/tmp/opencode/dirm.pubapi.marker').writeAsStringSync('$pubMarker');
    File(
      '/tmp/opencode/dirm.dart.trace.txt',
    ).writeAsStringSync(trace.map((t) => t.join(' ')).join('\n'));

    // ignore: avoid_print
    print('blocks: ${blocks.length}, first ${blocks.first.$1.length}');
  });
}
