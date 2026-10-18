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
import 'package:saber/data/document_conversion/djvu/djvu_iff.dart';

/// Root directory of the DjVu fixture corpus (relative to the repo root).
const djvuFixtureRoot = 'test/data/document_conversion/fixtures/djvu';

/// A fixture name (the `.djvu` basename, also the `refs/` directory name).
const djvuFixtures = [
  'bilevel',
  'layered',
  'archival',
  'photo',
  'gray',
  'grayscale',
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
/// Fixture masks are 1-bit grayscale PNGs holding the raw packed mask bits: a
/// *set* mask bit is written as sample 1 (white). The threshold is expressed
/// against the channel maximum so it also works if the decoder scales 1-bit
/// samples to 0/255 instead of 0/1.
DjvuBitmap readMaskFixture(String name, int page) {
  final image = readPngFixture('refs/$name/p$page.mask.png');
  final bitmap = DjvuBitmap(image.width, image.height);
  final half = image.maxChannelValue / 2;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (image.getPixel(x, y).r > half) bitmap.setBlack(x, y);
    }
  }
  return bitmap;
}

Uint8List _u32be(int value) => Uint8List.fromList([
  (value >> 24) & 0xff,
  (value >> 16) & 0xff,
  (value >> 8) & 0xff,
  value & 0xff,
]);

/// Builds a complete DjVu file (`AT&T FORM`) from [chunks].
///
/// Each entry is a 4-byte chunk id and its payload; odd payloads are padded to
/// even length, as IFF requires. [formType] becomes the FORM's secondary type.
/// Used to fabricate containers (INFO-only pages, legacy IW44 forms, indirect
/// catalogs) around byte-exact fixture chunks.
Uint8List buildDjvuForm(String formType, List<(String, List<int>)> chunks) {
  final body = BytesBuilder(copy: false);
  for (final (id, data) in chunks) {
    if (id.length != 4) throw ArgumentError.value(id, 'id', 'must be 4 bytes');
    body.add(id.codeUnits);
    body.add(_u32be(data.length));
    body.add(data);
    if (data.length.isOdd) body.addByte(0);
  }
  final payload = body.takeBytes();
  final file = BytesBuilder(copy: false)
    ..add('AT&T'.codeUnits)
    ..add('FORM'.codeUnits)
    // The FORM length covers the secondary type plus all sub-chunks.
    ..add(_u32be(payload.length + 4))
    ..add(formType.codeUnits)
    ..add(payload);
  return file.takeBytes();
}

/// Re-wraps a `FORM` child chunk (see [parseIffFile]) as a standalone
/// component file, as an indirect `FORM:DJVM` catalog would reference it.
Uint8List buildDjvuComponent(IffChunk formChunk) {
  if (formChunk.id != 'FORM') {
    throw ArgumentError.value(formChunk.id, 'formChunk', 'must be a FORM');
  }
  // `data` already holds the secondary type and the sub-chunks.
  final file = BytesBuilder(copy: false)
    ..add('AT&T'.codeUnits)
    ..add('FORM'.codeUnits)
    ..add(_u32be(formChunk.data.length))
    ..add(formChunk.data);
  return file.takeBytes();
}
