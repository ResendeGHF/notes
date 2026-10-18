// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Fonts for EPUB -> PDF conversion.
//
// Atkinson Hyperlegible Next is bundled as an asset (see pubspec.yaml) and is
// loaded once per app run. Callers hand the bytes to `convertEpubToPdf` so the
// converter itself stays pure Dart and isolate-safe; when the assets are
// missing the conversion still works with the built-in Helvetica family.

import 'package:flutter/services.dart';
import 'package:saber/data/document_conversion/epub/epub_converter.dart';

const _fontDir = 'assets/google_fonts/Atkinson_Hyperlegible_Next';

Future<EpubPdfOptions>? _cached;

/// Loads the bundled EPUB fonts, caching the result for later imports.
Future<EpubPdfOptions> loadEpubPdfOptions() => _cached ??= _load();

Future<EpubPdfOptions> _load() async {
  Future<ByteData?> load(String name) async {
    try {
      return await rootBundle.load('$_fontDir/$name');
    } catch (_) {
      // Missing assets are not fatal: the converter falls back to Helvetica.
      return null;
    }
  }

  final regular = await load('AtkinsonHyperlegibleNext-Regular.ttf');
  if (regular == null) return const EpubPdfOptions();

  final candidates = await Future.wait([
    load('AtkinsonHyperlegibleNext-SemiBold.ttf'),
    load('AtkinsonHyperlegibleNext-Italic.ttf'),
    load('AtkinsonHyperlegibleNext-SemiBoldItalic.ttf'),
  ]);
  return EpubPdfOptions(
    regularFont: regular,
    boldFont: candidates[0] ?? regular,
    italicFont: candidates[1] ?? regular,
    boldItalicFont: candidates[2] ?? regular,
  );
}
