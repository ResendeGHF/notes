// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Bitmap and pixmap primitives for the DjVu decoders.
//
// Ported from djvu-rs (crates/djvu-bitmap and crates/djvu-pixmap, MIT,
// https://github.com/matyushkin/djvu-rs). Pixel conventions match the
// reference exactly:
//
// - [DjvuBitmap] is 1 bit per pixel, packed 8-per-byte, MSB first, each row
//   padded to a byte boundary. A set bit (1) means black/marked.
// - [RgbaImage] is 4 bytes per pixel, row-major, top-to-bottom.
// - [Gray8Image] is 1 byte per pixel.

import 'dart:typed_data';

/// A 1-bit-per-pixel packed bitmap (MSB first, rows padded to bytes).
class DjvuBitmap {
  DjvuBitmap(this.width, this.height)
    : stride = (width + 7) >> 3,
      data = Uint8List(((width + 7) >> 3) * height);

  /// Creates a bitmap taking ownership of [data].
  ///
  /// [data] must be exactly `ceil(width / 8) * height` bytes long.
  DjvuBitmap.fromPacked(this.width, this.height, this.data)
    : stride = (width + 7) >> 3;

  final int width;
  final int height;

  /// Bytes per row (`ceil(width / 8)`).
  final int stride;

  /// Packed pixel data, row-major.
  final Uint8List data;

  /// Whether the pixel at (x, y) is black (1). No bounds checking.
  bool get(int x, int y) {
    final byte = y * stride + (x >> 3);
    return (data[byte] >> (7 - (x & 7))) & 1 == 1;
  }

  /// Sets the pixel at (x, y) to [value] (true = black). No bounds checking.
  void set(int x, int y, bool value) {
    final byte = y * stride + (x >> 3);
    final mask = 0x80 >> (x & 7);
    if (value) {
      data[byte] |= mask;
    } else {
      data[byte] &= ~mask & 0xff;
    }
  }

  /// Sets the pixel at (x, y) to black. No bounds checking.
  void setBlack(int x, int y) {
    data[y * stride + (x >> 3)] |= 0x80 >> (x & 7);
  }

  /// A new bitmap that is the AND-reduction of `2^shift` × `2^shift` blocks
  /// (used by low-resolution thumbnail paths). Not needed by the PDF writer.
  DjvuBitmap downsampleAnd(int shift) {
    if (shift == 0) return this;
    final nw = (width + (1 << shift) - 1) >> shift;
    final nh = (height + (1 << shift) - 1) >> shift;
    final out = DjvuBitmap(nw, nh);
    for (var y = 0; y < nh; y++) {
      for (var x = 0; x < nw; x++) {
        var all = true;
        for (var sy = 0; sy < (1 << shift) && all; sy++) {
          for (var sx = 0; sx < (1 << shift); sx++) {
            final px = (x << shift) + sx;
            final py = (y << shift) + sy;
            if (px >= width || py >= height || !get(px, py)) {
              all = false;
              break;
            }
          }
        }
        if (all) out.setBlack(x, y);
      }
    }
    return out;
  }
}

/// An RGBA pixel image, 4 bytes per pixel, row-major, top-to-bottom.
class RgbaImage {
  RgbaImage(this.width, this.height)
    : data = Uint8List(width * height * 4) {
    // Alpha is always 255 for DjVu pages (matching djvu-pixmap).
    for (var i = 3; i < data.length; i += 4) {
      data[i] = 0xff;
    }
  }

  /// Creates an image taking ownership of [data] (length `w * h * 4`).
  RgbaImage.fromData(this.width, this.height, this.data);

  /// A solid white image.
  RgbaImage.white(this.width, this.height)
    : data = Uint8List(width * height * 4) {
    data.fillRange(0, data.length, 0xff);
  }

  final int width;
  final int height;
  final Uint8List data;

  /// Reads the RGB triple at (x, y). No bounds checking.
  (int, int, int) getRgb(int x, int y) {
    final i = (y * width + x) * 4;
    return (data[i], data[i + 1], data[i + 2]);
  }

  /// Writes the RGB triple at (x, y) (alpha untouched). No bounds checking.
  void setRgb(int x, int y, int r, int g, int b) {
    final i = (y * width + x) * 4;
    data[i] = r;
    data[i + 1] = g;
    data[i + 2] = b;
  }

  /// Fills every pixel with the same colour (alpha forced opaque).
  void fill(int r, int g, int b) {
    for (var i = 0; i < data.length; i += 4) {
      data[i] = r;
      data[i + 1] = g;
      data[i + 2] = b;
      data[i + 3] = 0xff;
    }
  }

  /// Packed RGB bytes (3 per pixel), as expected by the PDF writer.
  Uint8List toRgbBytes() {
    final out = Uint8List(width * height * 3);
    for (var i = 0, j = 0; i < data.length; i += 4, j += 3) {
      out[j] = data[i];
      out[j + 1] = data[i + 1];
      out[j + 2] = data[i + 2];
    }
    return out;
  }
}

/// An 8-bit grayscale image, 1 byte per pixel, row-major, top-to-bottom.
class Gray8Image {
  Gray8Image(this.width, this.height) : data = Uint8List(width * height);

  /// Creates an image taking ownership of [data] (length `w * h`).
  Gray8Image.fromData(this.width, this.height, this.data);

  final int width;
  final int height;
  final Uint8List data;
}
