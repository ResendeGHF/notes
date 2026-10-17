// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Helpers for the DjVu conversion test corpus.
//
// The fixtures were generated with the `djvu` reference encoder and the
// `oracle` tool (see the README next to the fixtures). `refs/<name>/` holds
// reference chunks and planes decoded by the Rust implementation, which the
// pure-Dart ports are tested against bit for bit.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:saber/data/document_conversion/djvu/djvu_bitmap.dart';

/// Root directory of the DjVu fixture corpus (relative to the repo root).
const djvuFixtureRoot = 'test/data/document_conversion/fixtures/djvu';

/// A fixture name (the `.djvu` basename, also the `refs/` directory name).
const djvuFixtures = [
  'bilevel',
  'layered',
  'archival',
  'photo',
  'gray',
  'bgjp',
  'annotated',
];

/// Reads `<name>.djvu` as bytes.
Uint8List readDjvuFile(String name) =>
    File('$djvuFixtureRoot/$name.djvu').readAsBytesSync();

/// Reads a file from `refs/<name>/`.
Uint8List readDjvuRef(String name, String file) =>
    File('$djvuFixtureRoot/refs/$name/$file').readAsBytesSync();

/// Parses `refs/<name>/manifest.json`.
Map<String, dynamic> readDjvuManifest(String name) {
  final text =
      File('$djvuFixtureRoot/refs/$name/manifest.json').readAsStringSync();
  return jsonDecode(text) as Map<String, dynamic>;
}

/// Parses `refs/<name>/p<index>.links.json`, or null when absent.
Map<String, dynamic>? readDjvuLinks(String name, int index) {
  final file = File('$djvuFixtureRoot/refs/$name/p$index.links.json');
  if (!file.existsSync()) return null;
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// Parses `refs/<name>/p<index>.fgbz.json`, or null when absent.
Map<String, dynamic>? readDjvuFgbz(String name, int index) {
  final file = File('$djvuFixtureRoot/refs/$name/p$index.fgbz.json');
  if (!file.existsSync()) return null;
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// Decodes a PNG fixture into an [img.Image].
img.Image readPngFixture(String path) {
  final bytes = File('$djvuFixtureRoot/$path').readAsBytesSync();
  final image = img.decodePng(bytes);
  if (image == null) throw StateError('failed to decode PNG fixture $path');
  return image;
}

/// Loads a reference mask PNG into a [DjvuBitmap].
///
/// The oracle writes masks as 1-bit grayscale PNGs where a *zero* sample means
/// "marked" (the DjVu mask bit is set), so the comparison is inverted.
DjvuBitmap readMaskFixture(String name, int page) {
  final image = readPngFixture('refs/$name/p$page.mask.png');
  final bitmap = DjvuBitmap(image.width, image.height);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      if (pixel.r < 128) bitmap.setBlack(x, y);
    }
  }
  return bitmap;
}
