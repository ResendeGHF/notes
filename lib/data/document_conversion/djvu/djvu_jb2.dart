// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// JB2 bilevel image decoder — pure Dart port.
//
// Ported from djvu-rs (`crates/djvu-jb2`, MIT, https://github.com/matyushkin/djvu-rs),
// a clean-room implementation of the DjVu v3 specification
// (https://www.sndjvu.org/spec.html). The reference's behaviour is preserved
// exactly:
//
// - record types 0..11 and their dictionary/blit side effects,
// - `NumContext`, the lazy binary-tree context store used by the ZP-based
//   variable-length integer coder,
// - direct (10-bit context) and refinement (11-bit context, centre-aligned to
//   the matched symbol) bitmap decoding,
// - symbol placement: the rolling median-of-3 baseline and the first/last
//   record coordinate rules,
// - content cropping of symbols stored in the dictionary (blitted symbols keep
//   their decoded dimensions),
// - the shared/inherited dictionary mechanics (`Djbz` + type-9 preamble), and
// - the safety budgets that bound hostile input (16 MP per symbol, 64 MP of
//   symbol work per page, 256 MP of blit work, 65536 records per stream and the
//   ZP end-of-stream slack).
//
// Working symbols (`_Jbm`) are packed 1 bit/pixel, MSB first, with row 0 at the
// *bottom* of the image (DjVu convention), exactly like the reference's `Jbm`.
// The page canvas keeps the same orientation while records are applied and is
// flipped into the top-down [DjvuBitmap] convention once at the end — the
// reference converts its byte-per-pixel canvas the same way.

import 'dart:typed_data';

import 'package:saber/data/document_conversion/djvu/djvu_bitmap.dart';
import 'package:saber/data/document_conversion/djvu/djvu_zp.dart';
import 'package:saber/data/document_conversion/djvu/djvu_zp_tables.dart';

// ────────────────────────────────────────────────────────────────────────────
// Safety budgets (see the reference `direct.rs`)
// ────────────────────────────────────────────────────────────────────────────

/// Largest symbol that may be decoded: 16 MP per symbol — allows large
/// connected components while bounding hostile input.
const _maxSymbolPixels = 16 * 1024 * 1024;

/// Cumulative decoded-symbol work for a dictionary stream (256 MP).
///
/// The higher ceiling is needed for cross-page shared dictionaries, which may
/// legitimately hold a lot of glyphs.
const _maxTotalSymbolPixels = 256 * 1024 * 1024;

/// Cumulative decoded-symbol work for a single page stream (64 MP, counted in
/// work units: a direct pixel costs 1, a refinement pixel [_refinePixelWork]).
const _maxPageSymbolWork = 64 * 1024 * 1024;

/// Work units per decoded refinement pixel.
const _refinePixelWork = 4;

/// Cumulative blit work for a stream (256 MP) — prevents type-7 DoS via
/// repeated blitting of a large dictionary symbol.
const _maxTotalBlitPixels = 256 * 1024 * 1024;

/// Record count per stream (64 K) — prevents DoS via record-loop spin on
/// exhausted ZP input.
const _maxRecords = 65536;

/// Post-EOF spin guard: number of synthetic `0xFF` bytes the ZP coder may read
/// past the end of the real input before the stream is declared truncated.
///
/// The coder buffers up to 32 bits of look-ahead, so its byte buffer drains a
/// few bytes before the logical end of a valid stream; a valid stream reaches
/// its type-11 record while this stays within the slack.
const _zpEofSlackBytes = 16;

/// Page canvas limit (64 MP), mirroring the reference's `MAX_PIXELS`.
const _maxPagePixels = 64 * 1024 * 1024;

// ────────────────────────────────────────────────────────────────────────────
// Public API
// ────────────────────────────────────────────────────────────────────────────

/// Thrown when a JB2 stream is malformed, truncated or exceeds a safety budget.
class Jb2Exception implements Exception {
  const Jb2Exception(this.message);
  final String message;
  @override
  String toString() => 'Jb2Exception: $message';
}

/// Shared JB2 symbol dictionary decoded from a Djbz chunk.
///
/// Pass this to [jb2Decode] when the Sjbz stream references an external
/// dictionary via a "required-dict-or-reset" (type 9) record.
class Jb2Dict {
  Jb2Dict._(this._symbols);

  final List<_Jbm> _symbols;
}

/// Decodes an Sjbz image stream into a packed 1bpp mask.
///
/// [sharedDict] must be provided when the stream begins with a
/// "required-dict-or-reset" record that references an external dictionary.
///
/// Throws [Jb2Exception] on malformed input, a missing dictionary or an
/// oversized image.
DjvuBitmap jb2Decode(Uint8List data, {Jb2Dict? sharedDict}) =>
    _decodeImage(data, sharedDict, indexed: false).$1;

/// Decodes an Sjbz image stream plus a per-pixel blit record index map.
///
/// `blitMap[y * width + x]` is the 0-based blit record index for foreground
/// pixels, or -1 for background pixels.
(DjvuBitmap, Int32List) jb2DecodeIndexed(Uint8List data, {Jb2Dict? sharedDict}) {
  final (bitmap, blitMap) = _decodeImage(data, sharedDict, indexed: true);
  return (bitmap, blitMap!);
}

/// Decodes a Djbz dictionary stream (from FORM:DJVI), optionally inheriting
/// another dictionary.
///
/// Throws [Jb2Exception] on malformed input.
Jb2Dict jb2DecodeDict(Uint8List data, {Jb2Dict? inherited}) {
  final zp = _newZpDecoder(data);

  final recordTypeCtx = _NumContext();
  final imageSizeCtx = _NumContext();
  final symbolWidthCtx = _NumContext();
  final symbolHeightCtx = _NumContext();
  final inheritDictSizeCtx = _NumContext();
  final symbolIndexCtx = _NumContext();
  final symbolWidthDiffCtx = _NumContext();
  final symbolHeightDiffCtx = _NumContext();
  final commentLengthCtx = _NumContext();
  final commentOctetCtx = _NumContext();

  final directBitmapCtx = Uint8List(1024);
  final refinementBitmapCtx = Uint8List(2048);
  final budgets = _Budgets();

  // Preamble: optional "required-dict-or-reset" (type 9) followed by the
  // start-of-image record (type 0); its value is ignored.
  var rtype = _decodeNum(zp, recordTypeCtx, 0, 11);
  var initialDictLength = 0;
  if (rtype == 9) {
    initialDictLength = _decodeNum(zp, inheritDictSizeCtx, 0, 262142);
    rtype = _decodeNum(zp, recordTypeCtx, 0, 11);
  }

  // Dimensions: present in the header but unused for dictionary streams.
  _decodeNum(zp, imageSizeCtx, 0, 262142);
  _decodeNum(zp, imageSizeCtx, 0, 262142);

  // Reserved flag bit — must be 0.
  final flagCtx = Uint8List(1);
  if (zp.decodeBitAt(flagCtx, 0)) {
    throw const Jb2Exception('JB2: bad flag bit in header');
  }

  final dict = _initialDict(inherited, initialDictLength);

  // Dictionary streams only accept types 2, 5, 9, 10 and 11.
  const maxSymPx = _maxTotalSymbolPixels;
  var recordCount = 0;
  outer:
  while (true) {
    if (zp.syntheticBytes > _zpEofSlackBytes) {
      throw const Jb2Exception('JB2 stream is truncated');
    }
    if (recordCount >= _maxRecords) {
      throw const Jb2Exception('JB2: record count exceeds safety limit');
    }
    recordCount++;
    final type = _decodeNum(zp, recordTypeCtx, 0, 11);
    switch (type) {
      // New symbol, direct decode → add to the dictionary.
      case 2: {
        final w = _decodeNum(zp, symbolWidthCtx, 0, 262142);
        final h = _decodeNum(zp, symbolHeightCtx, 0, 262142);
        _checkSymbolDecodeBudget(zp, w, h, 1, budgets, maxSymPx);
        final bm = _decodeBitmapDirect(zp, directBitmapCtx, w, h);
        dict.push(_cropToContent(bm));
      }

      // Matched refinement → add to the dictionary.
      case 5: {
        if (dict.isEmpty) {
          throw const Jb2Exception('JB2: dict reference with empty dict');
        }
        final index = _decodeNum(zp, symbolIndexCtx, 0, dict.length - 1);
        if (index >= dict.length) {
          throw const Jb2Exception(
            'JB2: decoded symbol index out of dictionary range',
          );
        }
        final wdiff = _decodeNum(zp, symbolWidthDiffCtx, -262143, 262142);
        final hdiff = _decodeNum(zp, symbolHeightDiffCtx, -262143, 262142);
        final matched = dict[index];
        final cbmW = matched.width + wdiff;
        final cbmH = matched.height + hdiff;
        _checkSymbolDecodeBudget(
          zp,
          cbmW,
          cbmH,
          _refinePixelWork,
          budgets,
          maxSymPx,
        );
        final cbm = _decodeBitmapRef(zp, refinementBitmapCtx, cbmW, cbmH, matched);
        dict.push(_cropToContent(cbm));
      }

      // Required-dict-or-reset — already consumed in the preamble; ignore.
      case 9:

      // Comment: consume every octet (`decodeNum` is ZP-stateful, so skipping
      // any of them desynchronises the arithmetic coder).
      case 10: {
        final length = _decodeNum(zp, commentLengthCtx, 0, 262142);
        for (var i = 0; i < length; i++) {
          _decodeNum(zp, commentOctetCtx, 0, 255);
        }
      }

      // End-of-data.
      case 11:
        break outer;

      default:
        throw const Jb2Exception('JB2: unexpected record type in dict stream');
    }
  }

  return Jb2Dict._(dict.intoSymbols());
}

// ────────────────────────────────────────────────────────────────────────────
// Image (Sjbz) decode
// ────────────────────────────────────────────────────────────────────────────

/// Core Sjbz record loop.
///
/// When [indexed] is set the returned map holds the blit record index for every
/// foreground pixel (-1 elsewhere); its length is `width * height`.
(DjvuBitmap, Int32List?) _decodeImage(
  Uint8List data,
  Jb2Dict? sharedDict, {
  required bool indexed,
}) {
  final zp = _newZpDecoder(data);

  final recordTypeCtx = _NumContext();
  final imageSizeCtx = _NumContext();
  final symbolWidthCtx = _NumContext();
  final symbolHeightCtx = _NumContext();
  final inheritDictSizeCtx = _NumContext();
  final coordCtx = _CoordContexts();
  final symbolIndexCtx = _NumContext();
  final symbolWidthDiffCtx = _NumContext();
  final symbolHeightDiffCtx = _NumContext();
  final horizAbsLocCtx = _NumContext();
  final vertAbsLocCtx = _NumContext();
  final commentLengthCtx = _NumContext();
  final commentOctetCtx = _NumContext();

  final directBitmapCtx = Uint8List(1024);
  final refinementBitmapCtx = Uint8List(2048);
  final budgets = _Budgets();

  // Preamble: optional "required-dict-or-reset" (type 9) followed by the
  // start-of-image record (type 0); its value is ignored.
  var rtype = _decodeNum(zp, recordTypeCtx, 0, 11);
  var initialDictLength = 0;
  if (rtype == 9) {
    initialDictLength = _decodeNum(zp, inheritDictSizeCtx, 0, 262142);
    rtype = _decodeNum(zp, recordTypeCtx, 0, 11);
  }

  // Image dimensions (`0` means "use the default 200×200").
  var imageWidth = _decodeNum(zp, imageSizeCtx, 0, 262142);
  if (imageWidth == 0) imageWidth = 200;
  var imageHeight = _decodeNum(zp, imageSizeCtx, 0, 262142);
  if (imageHeight == 0) imageHeight = 200;

  // Reserved flag bit — must be 0.
  final flagCtx = Uint8List(1);
  if (zp.decodeBitAt(flagCtx, 0)) {
    throw const Jb2Exception('JB2: bad flag bit in header');
  }

  // Populate the initial dictionary from the shared dictionary.
  final dict = _initialDict(sharedDict, initialDictLength);

  final pagePixels = imageWidth * imageHeight;
  if (pagePixels > _maxPagePixels) {
    throw const Jb2Exception('JB2: image dimensions too large');
  }
  final page = _Page(
    imageWidth,
    imageHeight,
    indexed ? (Int32List(pagePixels)..fillRange(0, pagePixels, -1)) : null,
  );
  final layout = _LayoutState(imageHeight);

  const maxSymPx = _maxPageSymbolWork;
  var recordCount = 0;
  outer:
  while (true) {
    // Bail once the ZP input is exhausted and the record loop is spinning on
    // synthetic `0xFF` fill: everything decoded past this point is padding.
    if (zp.syntheticBytes > _zpEofSlackBytes) {
      throw const Jb2Exception('JB2 stream is truncated');
    }
    if (recordCount >= _maxRecords) {
      throw const Jb2Exception('JB2: record count exceeds safety limit');
    }
    recordCount++;
    final type = _decodeNum(zp, recordTypeCtx, 0, 11);
    switch (type) {
      // New symbol, direct decode → add to the dictionary AND blit.
      case 1: {
        final w = _decodeNum(zp, symbolWidthCtx, 0, 262142);
        final h = _decodeNum(zp, symbolHeightCtx, 0, 262142);
        _checkSymbolDecodeBudget(zp, w, h, 1, budgets, maxSymPx);
        final bm = _decodeBitmapDirect(zp, directBitmapCtx, w, h);
        final (x, y) = _decodeSymbolCoords(
          zp,
          coordCtx,
          layout,
          bm.width,
          bm.height,
        );
        _checkBlitBudget(bm, budgets);
        page.blit(bm, x, y);
        dict.push(_cropToContent(bm));
      }

      // New symbol, direct decode → add to the dictionary only.
      case 2: {
        final w = _decodeNum(zp, symbolWidthCtx, 0, 262142);
        final h = _decodeNum(zp, symbolHeightCtx, 0, 262142);
        _checkSymbolDecodeBudget(zp, w, h, 1, budgets, maxSymPx);
        final bm = _decodeBitmapDirect(zp, directBitmapCtx, w, h);
        dict.push(_cropToContent(bm));
      }

      // New symbol, direct decode → blit only (not stored in the dictionary).
      case 3: {
        final w = _decodeNum(zp, symbolWidthCtx, 0, 262142);
        final h = _decodeNum(zp, symbolHeightCtx, 0, 262142);
        _checkSymbolDecodeBudget(zp, w, h, 1, budgets, maxSymPx);
        final bm = _decodeBitmapDirect(zp, directBitmapCtx, w, h);
        final (x, y) = _decodeSymbolCoords(
          zp,
          coordCtx,
          layout,
          bm.width,
          bm.height,
        );
        _checkBlitBudget(bm, budgets);
        page.blit(bm, x, y);
      }

      // Matched refinement → add to the dictionary AND blit.
      case 4: {
        if (dict.isEmpty) {
          throw const Jb2Exception('JB2: dict reference with empty dict');
        }
        final index = _decodeNum(zp, symbolIndexCtx, 0, dict.length - 1);
        if (index >= dict.length) {
          throw const Jb2Exception(
            'JB2: decoded symbol index out of dictionary range',
          );
        }
        final wdiff = _decodeNum(zp, symbolWidthDiffCtx, -262143, 262142);
        final hdiff = _decodeNum(zp, symbolHeightDiffCtx, -262143, 262142);
        final matched = dict[index];
        final cbmW = matched.width + wdiff;
        final cbmH = matched.height + hdiff;
        _checkSymbolDecodeBudget(
          zp,
          cbmW,
          cbmH,
          _refinePixelWork,
          budgets,
          maxSymPx,
        );
        final cbm = _decodeBitmapRef(zp, refinementBitmapCtx, cbmW, cbmH, matched);
        final (x, y) = _decodeSymbolCoords(
          zp,
          coordCtx,
          layout,
          cbm.width,
          cbm.height,
        );
        _checkBlitBudget(cbm, budgets);
        page.blit(cbm, x, y);
        dict.push(_cropToContent(cbm));
      }

      // Matched refinement → add to the dictionary only.
      case 5: {
        if (dict.isEmpty) {
          throw const Jb2Exception('JB2: dict reference with empty dict');
        }
        final index = _decodeNum(zp, symbolIndexCtx, 0, dict.length - 1);
        if (index >= dict.length) {
          throw const Jb2Exception(
            'JB2: decoded symbol index out of dictionary range',
          );
        }
        final wdiff = _decodeNum(zp, symbolWidthDiffCtx, -262143, 262142);
        final hdiff = _decodeNum(zp, symbolHeightDiffCtx, -262143, 262142);
        final matched = dict[index];
        final cbmW = matched.width + wdiff;
        final cbmH = matched.height + hdiff;
        _checkSymbolDecodeBudget(
          zp,
          cbmW,
          cbmH,
          _refinePixelWork,
          budgets,
          maxSymPx,
        );
        final cbm = _decodeBitmapRef(zp, refinementBitmapCtx, cbmW, cbmH, matched);
        dict.push(_cropToContent(cbm));
      }

      // Matched refinement → blit only.
      case 6: {
        if (dict.isEmpty) {
          throw const Jb2Exception('JB2: dict reference with empty dict');
        }
        final index = _decodeNum(zp, symbolIndexCtx, 0, dict.length - 1);
        if (index >= dict.length) {
          throw const Jb2Exception(
            'JB2: decoded symbol index out of dictionary range',
          );
        }
        final wdiff = _decodeNum(zp, symbolWidthDiffCtx, -262143, 262142);
        final hdiff = _decodeNum(zp, symbolHeightDiffCtx, -262143, 262142);
        final matched = dict[index];
        final cbmW = matched.width + wdiff;
        final cbmH = matched.height + hdiff;
        _checkSymbolDecodeBudget(
          zp,
          cbmW,
          cbmH,
          _refinePixelWork,
          budgets,
          maxSymPx,
        );
        final cbm = _decodeBitmapRef(zp, refinementBitmapCtx, cbmW, cbmH, matched);
        final (x, y) = _decodeSymbolCoords(
          zp,
          coordCtx,
          layout,
          cbm.width,
          cbm.height,
        );
        _checkBlitBudget(cbm, budgets);
        page.blit(cbm, x, y);
      }

      // Matched copy, no refinement → blit only.
      case 7: {
        if (dict.isEmpty) {
          throw const Jb2Exception('JB2: dict reference with empty dict');
        }
        final index = _decodeNum(zp, symbolIndexCtx, 0, dict.length - 1);
        if (index >= dict.length) {
          throw const Jb2Exception(
            'JB2: decoded symbol index out of dictionary range',
          );
        }
        final sym = dict[index];
        final (x, y) = _decodeSymbolCoords(
          zp,
          coordCtx,
          layout,
          sym.width,
          sym.height,
        );
        _checkBlitBudget(sym, budgets);
        page.blit(sym, x, y);
      }

      // Non-symbol (halftone block), absolute coordinates.
      case 8: {
        final w = _decodeNum(zp, symbolWidthCtx, 0, 262142);
        final h = _decodeNum(zp, symbolHeightCtx, 0, 262142);
        _checkSymbolDecodeBudget(zp, w, h, 1, budgets, maxSymPx);
        final bm = _decodeBitmapDirect(zp, directBitmapCtx, w, h);
        final left = _decodeNum(zp, horizAbsLocCtx, 1, imageWidth);
        final top = _decodeNum(zp, vertAbsLocCtx, 1, imageHeight);
        _checkBlitBudget(bm, budgets);
        page.blit(bm, left - 1, top - h);
      }

      // Required-dict-or-reset — already consumed in the preamble; ignore.
      case 9:

      // Comment: consume every octet (`decodeNum` is ZP-stateful, so skipping
      // any of them desynchronises the arithmetic coder).
      case 10: {
        final length = _decodeNum(zp, commentLengthCtx, 0, 262142);
        for (var i = 0; i < length; i++) {
          _decodeNum(zp, commentOctetCtx, 0, 255);
        }
      }

      // End-of-data.
      case 11:
        break outer;

      default:
        throw const Jb2Exception('JB2: unknown record type');
    }
  }

  final bitmap = _pageToBitmap(page);
  final blitMap = page.blitMap;
  if (blitMap != null) {
    // The canvas is bottom-up; flip the map to match the bitmap's top-down
    // convention (the bitmap itself is flipped by `_pageToBitmap`).
    _flipBlitMap(blitMap, imageWidth, imageHeight);
  }
  return (bitmap, blitMap);
}

// ────────────────────────────────────────────────────────────────────────────
// Variable-length integers (NumContext)
// ────────────────────────────────────────────────────────────────────────────

/// Binary-tree context store used to decode variable-length integers with ZP.
///
/// Each node holds one adaptive ZP context byte; nodes are allocated lazily as
/// the coder traverses the tree. Index 0 is an unused sentinel, index 1 the
/// root.
class _NumContext {
  var _ctx = Uint8List(8);
  var _left = Int32List(8);
  var _right = Int32List(8);
  var _count = 2;

  /// The live context byte array (rooted at index 1).
  Uint8List get ctx => _ctx;

  int left(int node) {
    var child = _left[node];
    if (child == 0) {
      child = _append();
      _left[node] = child;
    }
    return child;
  }

  int right(int node) {
    var child = _right[node];
    if (child == 0) {
      child = _append();
      _right[node] = child;
    }
    return child;
  }

  int _append() {
    if (_count == _ctx.length) {
      final cap = _count * 2;
      _ctx = Uint8List(cap)..setRange(0, _count, _ctx);
      _left = Int32List(cap)..setRange(0, _count, _left);
      _right = Int32List(cap)..setRange(0, _count, _right);
    }
    return _count++;
  }
}

/// Decodes a variable-length integer in `[low, high]` using ZP.
int _decodeNum(ZpDecoder zp, _NumContext ctx, int low, int high) {
  var lo = low;
  var hi = high;
  var negative = false;
  var cutoff = 0;
  var phase = 1;
  var range = 0xffffffff;
  var node = 1; // ctx.root

  while (range != 1) {
    final bool decision;
    if (lo >= cutoff) {
      decision = true;
    } else if (hi >= cutoff) {
      decision = zp.decodeBitAt(ctx.ctx, node);
    } else {
      decision = false;
    }

    node = decision ? ctx.right(node) : ctx.left(node);

    switch (phase) {
      case 1:
        negative = !decision;
        if (negative) {
          final temp = -lo - 1;
          lo = -hi - 1;
          hi = temp;
        }
        phase = 2;
        cutoff = 1;
      case 2:
        if (!decision) {
          phase = 3;
          range = (cutoff + 1) ~/ 2;
          if (range == 1) {
            // `range` is already 1; set `cutoff` to 0 to terminate the loop.
            cutoff = 0;
          } else {
            cutoff -= range ~/ 2;
          }
        } else {
          cutoff = cutoff * 2 + 1;
        }
      case 3:
        range ~/= 2;
        if (range == 0) {
          range = 1;
        }
        if (range != 1) {
          if (!decision) {
            cutoff -= range ~/ 2;
          } else {
            cutoff += range ~/ 2;
          }
        } else if (!decision) {
          cutoff -= 1;
        }
      default:
        // Unreachable: `phase` cycles through 1, 2 and 3 only.
        if (range > 0) range -= 1;
    }
  }

  return negative ? -cutoff - 1 : cutoff;
}

// ────────────────────────────────────────────────────────────────────────────
// Symbol placement
// ────────────────────────────────────────────────────────────────────────────

/// Rolling median-of-3 used for vertical symbol positioning.
class _Baseline {
  final _arr = [0, 0, 0];
  var _index = -1;

  void fill(int val) {
    _arr[0] = val;
    _arr[1] = val;
    _arr[2] = val;
  }

  void add(int val) {
    _index++;
    if (_index == 3) _index = 0;
    _arr[_index] = val;
  }

  int get value {
    final a = _arr[0];
    final b = _arr[1];
    final c = _arr[2];
    if ((a >= b && a <= c) || (a <= b && a >= c)) {
      return a;
    } else if ((b >= a && b <= c) || (b <= a && b >= c)) {
      return b;
    } else {
      return c;
    }
  }
}

/// ZP coder contexts used exclusively for symbol coordinate decoding.
class _CoordContexts {
  final offsetType = Uint8List(1);
  final hoff = _NumContext();
  final voff = _NumContext();
  final shoff = _NumContext();
  final svoff = _NumContext();
}

/// Running layout state for symbol positioning within a JB2 image.
class _LayoutState {
  _LayoutState(int imageHeight)
    : firstLeft = -1,
      firstBottom = imageHeight - 1,
      lastRight = 0;

  int firstLeft;
  int firstBottom;
  int lastRight;
  final baseline = _Baseline();
}

/// Decodes the position of the next symbol.
///
/// On a "new line" record the coordinates are relative to the first symbol of
/// the previous line; otherwise they are relative to the right edge of the last
/// symbol on the current line and the rolling baseline.
(int, int) _decodeSymbolCoords(
  ZpDecoder zp,
  _CoordContexts ctx,
  _LayoutState layout,
  int symWidth,
  int symHeight,
) {
  final newLine = zp.decodeBitAt(ctx.offsetType, 0);

  final int x;
  final int y;
  if (newLine) {
    final hoff = _decodeNum(zp, ctx.hoff, -262143, 262142);
    final voff = _decodeNum(zp, ctx.voff, -262143, 262142);
    x = layout.firstLeft + hoff;
    y = layout.firstBottom + voff - symHeight + 1;
    layout.firstLeft = x;
    layout.firstBottom = y;
    layout.baseline.fill(y);
  } else {
    final hoff = _decodeNum(zp, ctx.shoff, -262143, 262142);
    final voff = _decodeNum(zp, ctx.svoff, -262143, 262142);
    x = layout.lastRight + hoff;
    y = layout.baseline.value + voff;
  }

  layout.baseline.add(y);
  layout.lastRight = x + symWidth - 1;
  return (x, y);
}

// ────────────────────────────────────────────────────────────────────────────
// Working bitmaps
// ────────────────────────────────────────────────────────────────────────────

/// Internal working bitmap: 1 bit per pixel, MSB first, rows padded to bytes.
///
/// Row 0 is the **bottom** of the image (DjVu convention).
class _Jbm {
  _Jbm(this.width, this.height)
    : stride = ((width > 0 ? width : 0) + 7) >> 3,
      data = Uint8List(
        (((width > 0 ? width : 0) + 7) >> 3) * (height > 0 ? height : 0),
      );

  final int width;
  final int height;
  final int stride;
  final Uint8List data;

  /// The pixel at (row, col); out-of-bounds reads as 0.
  int get(int row, int col) {
    if (row < 0 || row >= height || col < 0 || col >= width) return 0;
    return (data[row * stride + (col >> 3)] >> (7 - (col & 7))) & 1;
  }

  /// Sets the pixel at (row, col) to black. Caller ensures it is in bounds.
  void setBlack(int row, int col) {
    data[row * stride + (col >> 3)] |= 0x80 >> (col & 7);
  }
}

/// Two-part symbol table used during image/dictionary decode.
class _JbmDict {
  _JbmDict(this.shared, this.sharedCount);

  /// The inherited dictionary's symbols; only the first [sharedCount] are
  /// visible to this stream.
  final List<_Jbm> shared;
  final int sharedCount;
  final local = <_Jbm>[];

  int get length => sharedCount + local.length;
  bool get isEmpty => length == 0;

  _Jbm operator [](int index) =>
      index < sharedCount ? shared[index] : local[index - sharedCount];

  void push(_Jbm sym) => local.add(sym);

  /// The complete symbol list (inherited prefix followed by local symbols).
  List<_Jbm> intoSymbols() {
    final out = <_Jbm>[];
    for (var i = 0; i < sharedCount; i++) {
      out.add(shared[i]);
    }
    out.addAll(local);
    return out;
  }
}

/// Builds the initial dictionary state, honouring a type-9 preamble.
_JbmDict _initialDict(Jb2Dict? shared, int initialLength) {
  if (initialLength <= 0) return _JbmDict(const <_Jbm>[], 0);
  final sd = shared;
  if (sd == null) {
    throw const Jb2Exception('JB2: stream requires shared dict but none provided');
  }
  final symbols = sd._symbols;
  if (initialLength > symbols.length) {
    throw const Jb2Exception(
      'JB2: inherited dict length exceeds shared dict size',
    );
  }
  return _JbmDict(symbols, initialLength);
}

/// An empty row: reads as all-zero through [_pixRow].
final _noRow = Uint8List(0);

/// Reads `row[col]`, or 0 when `col` is negative or past the end.
///
/// Mirrors the reference's `pix_row` helpers, which make missing bitmap rows
/// (empty slices there) read as all-zero.
int _pixRow(Uint8List row, int col) =>
    col < 0 || col >= row.length ? 0 : row[col];

/// Packs a row of 0/1 bytes into packed MSB-first storage at `dstOff`.
void _packRowInto(Uint8List src, int width, Uint8List dst, int dstOff) {
  final fullBytes = width >> 3;
  var i = 0;
  for (var b = 0; b < fullBytes; b++) {
    var byteVal = 0;
    for (var j = 0; j < 8; j++) {
      if (src[i++] != 0) byteVal |= 0x80 >> j;
    }
    dst[dstOff + b] = byteVal;
  }
  final rem = width & 7;
  if (rem > 0) {
    var byteVal = 0;
    for (var j = 0; j < rem; j++) {
      if (src[i++] != 0) byteVal |= 0x80 >> j;
    }
    dst[dstOff + fullBytes] = byteVal;
  }
}

/// Unpacks one packed MSB-first row into 0/1 bytes (`dst.length` pixels).
void _unpackRowInto(Uint8List src, int srcOff, Uint8List dst) {
  final width = dst.length;
  final fullBytes = width >> 3;
  var di = 0;
  for (var b = 0; b < fullBytes; b++) {
    final byte = src[srcOff + b];
    dst[di++] = (byte >> 7) & 1;
    dst[di++] = (byte >> 6) & 1;
    dst[di++] = (byte >> 5) & 1;
    dst[di++] = (byte >> 4) & 1;
    dst[di++] = (byte >> 3) & 1;
    dst[di++] = (byte >> 2) & 1;
    dst[di++] = (byte >> 1) & 1;
    dst[di++] = byte & 1;
  }
  final rem = width & 7;
  if (rem > 0) {
    final byte = src[srcOff + fullBytes];
    for (var j = 0; j < rem; j++) {
      dst[di++] = (byte >> (7 - j)) & 1;
    }
  }
}

/// Number of leading one bits in the low 16 bits of [v].
int _leadingOnes16(int v) {
  final m = (~v) & 0xffff;
  return m == 0 ? 16 : 15 - (m.bitLength - 1);
}

// ────────────────────────────────────────────────────────────────────────────
// Direct (10-bit context) bitmap decode
// ────────────────────────────────────────────────────────────────────────────

/// Decodes one row of a direct-mode bitmap with the inlined ZP arithmetic.
///
/// The five hot ZP coder fields are copied into locals for the duration of the
/// row and written back at the end, mirroring the reference's register trick.
void _decodeDirectRow(
  ZpDecoder zp,
  Uint8List ctx,
  Uint8List out,
  Uint8List rp1,
  Uint8List rp2,
) {
  var a = zp.a;
  var c = zp.c;
  var fence = zp.fence;
  var bitBuf = zp.bitBuf;
  var bitCount = zp.bitCount;
  final data = zp.data;
  var pos = zp.pos;

  final w = out.length;
  var r2 = (_pixRow(rp2, 0) << 1) | _pixRow(rp2, 1);
  var r1 = (_pixRow(rp1, 0) << 2) | (_pixRow(rp1, 1) << 1) | _pixRow(rp1, 2);
  var r0 = 0;

  for (var col = 0; col < w; col++) {
    final idx = ((r2 << 7) | (r1 << 2) | r0) & 1023;
    final state = ctx[idx];
    final mpsBit = state & 1;
    final z = a + kZpProb[state];

    final int bit;
    if (z <= fence) {
      a = z;
      bit = mpsBit;
    } else {
      final boundary = 0x6000 + ((a + z) >> 2);
      final zClamped = z < boundary ? z : boundary;
      if (zClamped > c) {
        // LPS event: decoded bit is opposite of MPS.
        final complement = 0x10000 - zClamped;
        a = (a + complement) & 0xffff;
        c = (c + complement) & 0xffff;
        ctx[idx] = kZpLpsNext[state];
        final shift = _leadingOnes16(a);
        bitCount -= shift;
        a = (a << shift) & 0xffff;
        final mask = (1 << (shift & 31)) - 1;
        c = ((c << shift) | ((bitBuf >> (bitCount & 31)) & mask)) & 0xffff;
        if (bitCount < 16) {
          while (bitCount <= 24) {
            bitBuf =
                ((bitBuf << 8) | (pos < data.length ? data[pos] : 0xff)) &
                0xffffffff;
            pos++;
            bitCount += 8;
          }
        }
        fence = c < 0x7fff ? c : 0x7fff;
        bit = 1 - mpsBit;
      } else {
        // MPS event: decoded bit matches MPS.
        if (a >= kZpThreshold[state]) {
          ctx[idx] = kZpMpsNext[state];
        }
        bitCount -= 1;
        a = (zClamped << 1) & 0xffff;
        c = ((c << 1) | ((bitBuf >> (bitCount & 31)) & 1)) & 0xffff;
        if (bitCount < 16) {
          while (bitCount <= 24) {
            bitBuf =
                ((bitBuf << 8) | (pos < data.length ? data[pos] : 0xff)) &
                0xffffffff;
            pos++;
            bitCount += 8;
          }
        }
        fence = c < 0x7fff ? c : 0x7fff;
        bit = mpsBit;
      }
    }

    out[col] = bit;
    final p2 = col + 2;
    r2 = ((r2 << 1) & 0x7) | (p2 < w ? rp2[p2] : 0);
    final p1 = col + 3;
    r1 = ((r1 << 1) & 0x1f) | (p1 < w ? rp1[p1] : 0);
    r0 = ((r0 << 1) & 0x3) | bit;
  }

  zp.a = a;
  zp.c = c;
  zp.fence = fence;
  zp.bitBuf = bitBuf;
  zp.bitCount = bitCount;
  zp.pos = pos;
}

/// Decodes a bitmap using the direct (10-pixel context) method.
///
/// Rows are decoded bottom-up; row `row` is stored at `row * stride`, and each
/// row's 10-bit context window is fed by the two previously decoded rows.
_Jbm _decodeBitmapDirect(
  ZpDecoder zp,
  Uint8List ctx,
  int width,
  int height,
) {
  final pixels = (width > 0 ? width : 0) * (height > 0 ? height : 0);
  if (pixels > _maxSymbolPixels) {
    throw const Jb2Exception('JB2: image dimensions too large');
  }
  if (width <= 0 || height <= 0) return _Jbm(width, height);

  final bm = _Jbm(width, height);
  final w = width;
  final h = height;
  final stride = bm.stride;

  // Scratch rows, 1 byte per pixel, rotated each iteration so the decoder can
  // read the two previously decoded rows without unpacking from storage.
  var sCurr = Uint8List(w);
  var sPrev1 = Uint8List(w);
  var sPrev2 = Uint8List(w);

  for (var row = h - 1; row >= 0; row--) {
    sCurr.fillRange(0, w, 0);
    _decodeDirectRow(zp, ctx, sCurr, sPrev1, sPrev2);
    _packRowInto(sCurr, w, bm.data, row * stride);
    // Rotate: prev2 ← prev1, prev1 ← curr, curr ← (old prev2, reused).
    final t = sPrev2;
    sPrev2 = sPrev1;
    sPrev1 = sCurr;
    sCurr = t;
  }
  return bm;
}

// ────────────────────────────────────────────────────────────────────────────
// Refinement (11-bit context) bitmap decode
// ────────────────────────────────────────────────────────────────────────────

/// Decodes one row of a refinement-mode bitmap with the inlined ZP arithmetic.
///
/// The 11-bit context combines three pixels of the previous child row, the
/// current child pixel and five pixels of the matched bitmap.
///
/// `cbmR1`, `mbmR2`, `mbmR1` and `mbmR0` may be empty (missing rows), which
/// [_pixRow] reads as all-zero.
void _decodeRefRow(
  ZpDecoder zp,
  Uint8List ctx,
  Uint8List row,
  Uint8List cbmR1,
  Uint8List mbmR2,
  Uint8List mbmR1,
  Uint8List mbmR0,
  int colShift,
  int initCR1,
  int initMR1,
  int initMR0,
) {
  var a = zp.a;
  var c = zp.c;
  var fence = zp.fence;
  var bitBuf = zp.bitBuf;
  var bitCount = zp.bitCount;
  final data = zp.data;
  var pos = zp.pos;

  var cR0 = 0;
  var cR1 = initCR1;
  var mR1 = initMR1;
  var mR0 = initMR0;

  final w = row.length;
  for (var col = 0; col < w; col++) {
    final mR2 = _pixRow(mbmR2, col + colShift);
    // idx ≤ 2047: cR1 < 8, cR0 < 2, mR2 < 2, mR1 < 8, mR0 < 8.
    final idx =
        ((cR1 << 8) | (cR0 << 7) | (mR2 << 6) | (mR1 << 3) | mR0) & 2047;
    final state = ctx[idx];
    final mpsBit = state & 1;
    final z = a + kZpProb[state];

    final int bit;
    if (z <= fence) {
      a = z;
      bit = mpsBit;
    } else {
      final boundary = 0x6000 + ((a + z) >> 2);
      final zClamped = z < boundary ? z : boundary;
      if (zClamped > c) {
        final complement = 0x10000 - zClamped;
        a = (a + complement) & 0xffff;
        c = (c + complement) & 0xffff;
        ctx[idx] = kZpLpsNext[state];
        final shift = _leadingOnes16(a);
        bitCount -= shift;
        a = (a << shift) & 0xffff;
        final mask = (1 << (shift & 31)) - 1;
        c = ((c << shift) | ((bitBuf >> (bitCount & 31)) & mask)) & 0xffff;
        if (bitCount < 16) {
          while (bitCount <= 24) {
            bitBuf =
                ((bitBuf << 8) | (pos < data.length ? data[pos] : 0xff)) &
                0xffffffff;
            pos++;
            bitCount += 8;
          }
        }
        fence = c < 0x7fff ? c : 0x7fff;
        bit = 1 - mpsBit;
      } else {
        if (a >= kZpThreshold[state]) {
          ctx[idx] = kZpMpsNext[state];
        }
        bitCount -= 1;
        a = (zClamped << 1) & 0xffff;
        c = ((c << 1) | ((bitBuf >> (bitCount & 31)) & 1)) & 0xffff;
        if (bitCount < 16) {
          while (bitCount <= 24) {
            bitBuf =
                ((bitBuf << 8) | (pos < data.length ? data[pos] : 0xff)) &
                0xffffffff;
            pos++;
            bitCount += 8;
          }
        }
        fence = c < 0x7fff ? c : 0x7fff;
        bit = mpsBit;
      }
    }

    if (bit != 0) row[col] = 1;

    cR1 = ((cR1 << 1) & 0x7) | _pixRow(cbmR1, col + 2);
    cR0 = bit;
    mR1 = ((mR1 << 1) & 0x7) | _pixRow(mbmR1, col + colShift + 2);
    mR0 = ((mR0 << 1) & 0x7) | _pixRow(mbmR0, col + colShift + 2);
  }

  zp.a = a;
  zp.c = c;
  zp.fence = fence;
  zp.bitBuf = bitBuf;
  zp.bitCount = bitCount;
  zp.pos = pos;
}

/// Unpacks matched-bitmap row [r] into [buf]; false when the row is missing.
bool _unpackMbmRow(_Jbm mbm, int r, Uint8List buf) {
  if (r < 0 || r >= mbm.height || buf.isEmpty) return false;
  _unpackRowInto(mbm.data, r * mbm.stride, buf);
  return true;
}

/// Decodes a bitmap using the refinement (11-pixel context) method.
///
/// The new (child) bitmap is decoded relative to a reference (matched) bitmap,
/// centre-aligned as per the DjVu spec.
_Jbm _decodeBitmapRef(
  ZpDecoder zp,
  Uint8List ctx,
  int width,
  int height,
  _Jbm mbm,
) {
  final pixels = (width > 0 ? width : 0) * (height > 0 ? height : 0);
  if (pixels > _maxSymbolPixels) {
    throw const Jb2Exception('JB2: image dimensions too large');
  }
  if (width <= 0 || height <= 0) return _Jbm(width, height);
  final cbm = _Jbm(width, height);

  // Centre alignment: anchor the reference bitmap at the centre of the child.
  final crow = (height - 1) >> 1;
  final ccol = (width - 1) >> 1;
  final mrow = (mbm.height - 1) >> 1;
  final mcol = (mbm.width - 1) >> 1;
  final rowShift = mrow - crow;
  final colShift = mcol - ccol;

  final cw = width;
  final cstride = cbm.stride;
  final mw = mbm.width > 0 ? mbm.width : 0;

  // Rolling scratch (1 byte/pixel) for the three matched-bitmap rows. Each slot
  // holds the unpacked content of rows `mr+1`, `mr`, `mr-1` relative to the
  // current iteration's `mr = row + rowShift`; empty when out of bounds.
  var sMbmR2 = Uint8List(mw);
  var sMbmR1 = Uint8List(mw);
  var sMbmR0 = Uint8List(mw);

  // Scratch for the child bitmap: current row and previously decoded row.
  var sCbmCurr = Uint8List(cw);
  var sCbmPrev1 = Uint8List(cw);

  // Prime the rolling matched scratch before the first iteration
  // (row = height-1): mbmR2 = mbm[mr+1], mbmR1 = mbm[mr], mbmR0 = mbm[mr-1].
  final firstMr = (height - 1) + rowShift;
  var haveR2 = _unpackMbmRow(mbm, firstMr + 1, sMbmR2);
  var haveR1 = _unpackMbmRow(mbm, firstMr, sMbmR1);
  var haveR0 = _unpackMbmRow(mbm, firstMr - 1, sMbmR0);

  for (var row = height - 1; row >= 0; row--) {
    final mr = row + rowShift;

    final mbmR2 = haveR2 ? sMbmR2 : _noRow;
    final mbmR1 = haveR1 ? sMbmR1 : _noRow;
    final mbmR0 = haveR0 ? sMbmR0 : _noRow;
    final cbmR1 = row + 1 < height ? sCbmPrev1 : _noRow;

    sCbmCurr.fillRange(0, cw, 0);

    final initCR1 = (_pixRow(cbmR1, 0) << 1) | _pixRow(cbmR1, 1);
    final initMR1 =
        (_pixRow(mbmR1, colShift - 1) << 2) |
        (_pixRow(mbmR1, colShift) << 1) |
        _pixRow(mbmR1, colShift + 1);
    final initMR0 =
        (_pixRow(mbmR0, colShift - 1) << 2) |
        (_pixRow(mbmR0, colShift) << 1) |
        _pixRow(mbmR0, colShift + 1);

    _decodeRefRow(
      zp,
      ctx,
      sCbmCurr,
      cbmR1,
      mbmR2,
      mbmR1,
      mbmR0,
      colShift,
      initCR1,
      initMR1,
      initMR0,
    );

    _packRowInto(sCbmCurr, cw, cbm.data, row * cstride);

    // Rotate child scratch: prev1 ← curr, curr ← (old prev1, reused).
    final t = sCbmPrev1;
    sCbmPrev1 = sCbmCurr;
    sCbmCurr = t;

    // Rotate matched scratch: r2 ← r1, r1 ← r0, r0 ← freshly unpacked mr-2.
    var tmp = sMbmR2;
    sMbmR2 = sMbmR1;
    sMbmR1 = tmp;
    haveR2 = haveR1;
    tmp = sMbmR1;
    sMbmR1 = sMbmR0;
    sMbmR0 = tmp;
    haveR1 = haveR0;
    haveR0 = _unpackMbmRow(mbm, mr - 2, sMbmR0);
  }
  return cbm;
}

/// Returns [bm] with surrounding empty rows and columns removed.
_Jbm _cropToContent(_Jbm bm) {
  if (bm.width <= 0 || bm.height <= 0) return _Jbm(0, 0);
  final stride = bm.stride;
  var minRow = bm.height;
  var maxRow = -1;
  var minCol = bm.width;
  var maxCol = -1;

  for (var row = 0; row < bm.height; row++) {
    final off = row * stride;
    // Find the first and last nonzero byte in the row, then refine to columns.
    var byteMin = -1;
    var byteMax = -1;
    for (var i = 0; i < stride; i++) {
      if (bm.data[off + i] != 0) {
        if (byteMin < 0) byteMin = i;
        byteMax = i;
      }
    }
    if (byteMin >= 0) {
      // Position of the first set bit in the byte (`leading_zeros`), and of
      // the last one (`7 - trailing_zeros`).
      final first = bm.data[off + byteMin];
      final last = bm.data[off + byteMax];
      var colHi = (byteMax << 3) + (7 - ((last & -last).bitLength - 1));
      if (colHi > bm.width - 1) colHi = bm.width - 1;
      final colLo = (byteMin << 3) + (8 - first.bitLength);
      if (row < minRow) minRow = row;
      if (row > maxRow) maxRow = row;
      if (colLo < minCol) minCol = colLo;
      if (colHi > maxCol) maxCol = colHi;
    }
  }

  if (maxRow < 0) return _Jbm(0, 0);

  final nw = maxCol - minCol + 1;
  final nh = maxRow - minRow + 1;
  final out = _Jbm(nw, nh);
  for (var row = minRow; row <= maxRow; row++) {
    final off = row * stride;
    for (var col = minCol; col <= maxCol; col++) {
      if ((bm.data[off + (col >> 3)] >> (7 - (col & 7))) & 1 != 0) {
        out.setBlack(row - minRow, col - minCol);
      }
    }
  }
  return out;
}

// ────────────────────────────────────────────────────────────────────────────
// Page canvas and blitting
// ────────────────────────────────────────────────────────────────────────────

/// The page canvas: packed 1bpp, row 0 = bottom, with an optional per-pixel
/// blit record index map (`blitMap[y * width + x]`, -1 for background).
class _Page {
  _Page(this.width, this.height, this.blitMap)
    : stride = (width + 7) >> 3,
      data = Uint8List(((width + 7) >> 3) * height);

  final int width;
  final int height;
  final int stride;
  final Uint8List data;
  final Int32List? blitMap;

  /// Number of blit records applied so far (the index of the next one).
  var blitCount = 0;

  /// Blits [sym] at (x, y), recording the blit index when tracking is on.
  void blit(_Jbm sym, int x, int y) {
    final map = blitMap;
    if (map != null) {
      _blitIndexed(sym, x, y, map, blitCount);
      blitCount++;
    } else {
      _blit(sym, x, y);
    }
  }

  /// OR-composites [sym] onto the page (symbol row 0 = page bottom).
  void _blit(_Jbm sym, int x, int y) {
    final sw = sym.width;
    final sh = sym.height;
    if (sw <= 0 || sh <= 0) return;
    final symStride = sym.stride;
    final full = sw >> 3;
    final rem = sw & 7;

    if (x >= 0 && y >= 0 && x + sw <= width && y + sh <= height) {
      // Fast path: symbol completely within bounds — byte-wise OR with a shift
      // for non-byte-aligned x. Padding bits of the symbol's last byte are
      // zero by construction, so OR-ing the whole byte is correct.
      final shift = x & 7;
      final lshift = 8 - shift;
      final dstByte = x >> 3;
      for (var row = 0; row < sh; row++) {
        final srcOff = row * symStride;
        final dstOff = (y + row) * stride;
        if (shift == 0) {
          for (var i = 0; i < full; i++) {
            data[dstOff + dstByte + i] |= sym.data[srcOff + i];
          }
          if (rem > 0) {
            data[dstOff + dstByte + full] |= sym.data[srcOff + full];
          }
        } else {
          for (var i = 0; i < full; i++) {
            final s = sym.data[srcOff + i];
            data[dstOff + dstByte + i] |= s >> shift;
            data[dstOff + dstByte + i + 1] |= (s << lshift) & 0xff;
          }
          if (rem > 0) {
            final s = sym.data[srcOff + full];
            data[dstOff + dstByte + full] |= s >> shift;
            // The shifted spill byte is only in-row when the symbol's last
            // byte actually crosses the destination byte boundary; when it
            // does not, `s << lshift` is zero and may fall past the buffer
            // end, so guard it like the reference does.
            final overflow = dstOff + dstByte + full + 1;
            if (overflow < data.length) {
              data[overflow] |= (s << lshift) & 0xff;
            }
          }
        }
      }
    } else {
      // Slow path: clipped blit, per-pixel bounds checks.
      for (var row = 0; row < sh; row++) {
        final py = y + row;
        if (py < 0 || py >= height) continue;
        final srcOff = row * symStride;
        final dstOff = py * stride;
        for (var col = 0; col < sw; col++) {
          if ((sym.data[srcOff + (col >> 3)] >> (7 - (col & 7))) & 1 != 0) {
            final px = x + col;
            if (px >= 0 && px < width) {
              data[dstOff + (px >> 3)] |= 0x80 >> (px & 7);
            }
          }
        }
      }
    }
  }

  /// OR-composites [sym] and records [blitIdx] for every marked pixel.
  void _blitIndexed(_Jbm sym, int x, int y, Int32List map, int blitIdx) {
    final sw = sym.width;
    final sh = sym.height;
    if (sw <= 0 || sh <= 0) return;
    final symStride = sym.stride;

    if (x >= 0 && y >= 0 && x + sw <= width && y + sh <= height) {
      final full = sw >> 3;
      final rem = sw & 7;
      for (var row = 0; row < sh; row++) {
        final srcOff = row * symStride;
        final dstOff = (y + row) * stride;
        final mapOff = (y + row) * width;
        for (var b = 0; b < full; b++) {
          final bits = sym.data[srcOff + b];
          if (bits == 0) continue;
          final baseCol = b << 3;
          for (var j = 0; j < 8; j++) {
            if ((bits >> (7 - j)) & 1 != 0) {
              final px = x + baseCol + j;
              data[dstOff + (px >> 3)] |= 0x80 >> (px & 7);
              map[mapOff + px] = blitIdx;
            }
          }
        }
        if (rem > 0) {
          final bits = sym.data[srcOff + full];
          if (bits != 0) {
            final baseCol = full << 3;
            for (var j = 0; j < rem; j++) {
              if ((bits >> (7 - j)) & 1 != 0) {
                final px = x + baseCol + j;
                data[dstOff + (px >> 3)] |= 0x80 >> (px & 7);
                map[mapOff + px] = blitIdx;
              }
            }
          }
        }
      }
    } else {
      for (var row = 0; row < sh; row++) {
        final py = y + row;
        if (py < 0 || py >= height) continue;
        final mapOff = py * width;
        for (var col = 0; col < sw; col++) {
          if (sym.get(row, col) != 0) {
            final px = x + col;
            if (px >= 0 && px < width) {
              data[py * stride + (px >> 3)] |= 0x80 >> (px & 7);
              map[mapOff + px] = blitIdx;
            }
          }
        }
      }
    }
  }
}

/// Converts the bottom-up page canvas into a top-down [DjvuBitmap].
DjvuBitmap _pageToBitmap(_Page page) {
  final bm = DjvuBitmap(page.width, page.height);
  final stride = page.stride;
  for (var row = 0; row < page.height; row++) {
    final srcOff = row * stride;
    final dstOff = (page.height - 1 - row) * stride;
    bm.data.setRange(dstOff, dstOff + stride, page.data, srcOff);
  }
  return bm;
}

/// Flips the blit map vertically to match the bitmap coordinate system.
void _flipBlitMap(Int32List map, int width, int height) {
  for (var row = 0; row < height >> 1; row++) {
    final mirror = height - 1 - row;
    var a = row * width;
    var b = mirror * width;
    for (var col = 0; col < width; col++) {
      final tmp = map[a];
      map[a] = map[b];
      map[b] = tmp;
      a++;
      b++;
    }
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Budgets
// ────────────────────────────────────────────────────────────────────────────

/// Mutable running totals for the decode budgets.
class _Budgets {
  var symPixels = 0;
  var blitPixels = 0;
}

/// ZP decoder factory mapping short input to a [Jb2Exception].
ZpDecoder _newZpDecoder(Uint8List data) {
  if (data.length < 2) {
    throw const Jb2Exception('JB2: insufficient data to initialize ZP coder');
  }
  return ZpDecoder(data);
}

/// Checks that decoding a `w × h` symbol won't exceed the per-symbol or
/// stream-total budget, and that the ZP input is not exhausted.
void _checkSymbolDecodeBudget(
  ZpDecoder zp,
  int w,
  int h,
  int work,
  _Budgets budgets,
  int maxTotal,
) {
  _checkPixelBudget(w, h, work, budgets, maxTotal);
  // Once the ZP coder has emitted more synthetic `0xFF` padding than the
  // look-ahead slack, every remaining bit is provably fill: real input is
  // exhausted and we are spinning. Bail immediately.
  if (zp.syntheticBytes > _zpEofSlackBytes) {
    throw const Jb2Exception('JB2 stream is truncated');
  }
}

/// Adds `w × h × work` to the decoded-symbol total, rejecting overruns before
/// the caller decodes the bitmap so the running total is a hard ceiling.
void _checkPixelBudget(
  int w,
  int h,
  int work,
  _Budgets budgets,
  int maxTotal,
) {
  final pixels = (w > 0 ? w : 0) * (h > 0 ? h : 0);
  if (pixels > _maxSymbolPixels) {
    throw const Jb2Exception('JB2: image dimensions too large');
  }
  budgets.symPixels += pixels * work;
  if (budgets.symPixels > maxTotal) {
    throw const Jb2Exception('JB2: image dimensions too large');
  }
}

/// Checks that blitting [sym] won't exceed the total blit-work budget.
void _checkBlitBudget(_Jbm sym, _Budgets budgets) {
  final pixels = (sym.width > 0 ? sym.width : 0) * (sym.height > 0 ? sym.height : 0);
  budgets.blitPixels += pixels;
  if (budgets.blitPixels > _maxTotalBlitPixels) {
    throw const Jb2Exception('JB2: image dimensions too large');
  }
}
