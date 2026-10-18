// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// EPUB scan orientation pre-pass.
//
// Scanned EPUBs store every page image sideways, with no metadata saying so
// (unlike DjVu, which at least carries a rotation tag). To correct that, the
// import pipeline decodes a small preview of each raster entry and scores it
// with [scoreScanOrientation] before conversion; the converter then rotates
// the images it was told about.
//
// The pre-pass uses the engine's image codecs (`dart:ui`), which are native —
// the platform's own libjpeg-turbo/Skia decoders — and decode straight to the
// preview size, so a 500x670 scan costs well under a millisecond. Codecs are
// **not** available in background isolates ("Failed to access the internal
// image decoder registry"), so this runs on the root isolate; the work yields
// to the event loop between images and never blocks the UI.
//
// The ZIP is read through a file stream: only the image entries are
// decompressed, one at a time, and the EPUB itself never sits in memory.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:saber/data/document_conversion/scan_orientation.dart';

/// Raster extensions the pre-pass reviews. Matches what the engine can decode.
const _rasterExtensions = {
  '.jpg',
  '.jpeg',
  '.jpe',
  '.png',
  '.gif',
  '.bmp',
  '.webp',
};

/// Returns the orientation corrections for every raster entry of the EPUB at
/// [path], keyed by archive entry name (`ArchiveFile.name`).
///
/// Only confident verdicts are included. Best effort: a file that cannot be
/// opened or a damaged image is skipped rather than failing the import (the
/// converter reports its own errors).
///
/// [onProgress] receives `(done, total)` after every reviewed entry.
Future<Map<String, ScanOrientation>> detectEpubScanOrientations(
  String path, {
  int concurrency = 6,
  void Function(int done, int total)? onProgress,
}) async {
  InputFileStream? input;
  try {
    input = InputFileStream(path);
    final archive = ZipDecoder().decodeStream(input);
    final entries = [
      for (final file in archive.files)
        if (file.isFile && _isRasterName(file.name)) file,
    ];

    final scores = <String, ScanOrientationScore>{};
    var done = 0;
    var pending = <Future<void>>[];
    for (final entry in entries) {
      pending.add(
        _probeEntry(entry).then((score) {
          if (score != null) {
            scores[entry.name] = score;
          }
          done++;
          onProgress?.call(done, entries.length);
        }),
      );
      if (pending.length >= concurrency) {
        await Future.wait(pending);
        pending = [];
      }
    }
    await Future.wait(pending);
    return _consolidate(scores);
  } on Exception catch (_) {
    return const {};
  } finally {
    input?.closeSync();
  }
}

/// Turns per-image scores into the corrections handed to the converter.
///
/// Confident verdicts are kept as they are, with one document-level repair: a
/// scan batch stores every page the same way, so when the pages that clearly
/// read sideways overwhelmingly agree on which way they need turning, the
/// handful of pages whose per-page cue picked the other turn are noise (a
/// justified page leaves little for the cue to read) and are aligned with the
/// majority. Pages whose projections stayed inconclusive (two-column indexes,
/// sparse figures) adopt the majority rotation under the same rule: in a book
/// scanned sideways cover to cover those pages are sideways too, they just do
/// not look like single-column text.
Map<String, ScanOrientation> _consolidate(
  Map<String, ScanOrientationScore> scores,
) {
  final orientations = <String, ScanOrientation>{};
  for (final entry in scores.entries) {
    final orientation = entry.value.orientation;
    if (orientation != ScanOrientation.unknown) {
      orientations[entry.key] = orientation;
    }
  }

  final majority = _majorityRotation(scores.values);
  if (majority != null) {
    for (final entry in scores.entries) {
      final orientation = entry.value.orientation;
      if (orientation == ScanOrientation.rotateClockwise ||
          orientation == ScanOrientation.rotateCounterClockwise ||
          entry.value.isInconclusive) {
        orientations[entry.key] = majority;
      }
    }
  }
  return orientations;
}

/// The rotation shared by at least 80% of the confidently rotated pages, when
/// at least four pages were rotated at all. Upright pages do not veto it (a
/// cover or a photo section is not evidence about the text pages).
ScanOrientation? _majorityRotation(Iterable<ScanOrientationScore> scores) {
  var clockwise = 0;
  var counter = 0;
  for (final score in scores) {
    switch (score.orientation) {
      case ScanOrientation.rotateClockwise:
        clockwise++;
      case ScanOrientation.rotateCounterClockwise:
        counter++;
      case ScanOrientation.unknown || ScanOrientation.upright:
        break;
    }
  }
  final rotated = clockwise + counter;
  if (rotated < 4) return null;
  final threshold = (rotated * 0.8).ceil();
  if (clockwise >= threshold) return ScanOrientation.rotateClockwise;
  if (counter >= threshold) return ScanOrientation.rotateCounterClockwise;
  return null;
}

bool _isRasterName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return false;
  return _rasterExtensions.contains(name.substring(dot).toLowerCase());
}

Future<ScanOrientationScore?> _probeEntry(ArchiveFile entry) async {
  // Reads (and decompresses) one ZIP entry; entry data is only ever touched
  // here, from the single root isolate, so the shared file stream is safe.
  final bytes = entry.readBytes();
  if (bytes == null || bytes.isEmpty) return null;
  return probeEncodedImageOrientation(bytes);
}

/// Scores one encoded image ([jpeg], [png], ...) by decoding a small preview.
///
/// Must run on the root isolate: background isolates cannot access the image
/// decoder registry. Returns null for anything the engine cannot decode.
Future<ScanOrientationScore?> probeEncodedImageOrientation(
  Uint8List bytes,
) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width;
    final height = descriptor.height;
    if (width <= 0 || height <= 0) return null;

    // Scale so the long side lands on the ink grid resolution. The engine
    // decodes directly to this size, so cost is independent of the source
    // resolution.
    final longest = math.max(width, height);
    final scale = math.min(1.0, kScanInkGridMaxSide / longest);
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (width * scale).round()),
      targetHeight: math.max(1, (height * scale).round()),
    );
    final frame = await codec.getNextFrame();
    image = frame.image;
    final previewWidth = image.width;
    final previewHeight = image.height;
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (data == null) return null;

    final rgba = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final grid = ScanInkGrid.fromPixels(previewWidth, previewHeight, (x, y) {
      final i = (y * previewWidth + x) * 4;
      final alpha = rgba[i + 3] / 255.0;
      final r = rgba[i] * alpha + 255 * (1 - alpha);
      final g = rgba[i + 1] * alpha + 255 * (1 - alpha);
      final b = rgba[i + 2] * alpha + 255 * (1 - alpha);
      final luma = 0.299 * r + 0.587 * g + 0.114 * b;
      return 1.0 - luma / 255.0;
    });
    return scoreScanOrientationDetailed(grid);
  } on Exception catch (_) {
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}
