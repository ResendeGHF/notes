// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';
import 'package:saber/services/pdf_open_helper.dart';

class PdfDocumentCache {
  final Map<String, FutureOr<PdfDocument>> _cache = {};

  FutureOr<PdfDocument> load(String filePath, {Uint8List? pdfBytes}) {
    return _cache[filePath] ??= _loadCacheMiss(filePath, pdfBytes: pdfBytes);
  }

  Future<PdfDocument> _loadCacheMiss(
    String filePath, {
    Uint8List? pdfBytes,
  }) async {
    // mmap first: when the file exists on disk the OS streams pages on
    // demand with zero Dart-side copy. `openData` is only for genuinely
    // in-memory bytes (spilled to a temp mmap when disk is allowed).
    if (filePath.isNotEmpty) {
      try {
        if (File(filePath).existsSync()) {
          final document = await PdfOpenHelper.openFileProgressive(filePath);
          _cache[filePath] = document;
          return document;
        }
      } catch (_) {}
    }
    final document = await PdfOpenHelper.openMmapPreferred(
      filePath: filePath.isEmpty ? null : filePath,
      bytes: pdfBytes,
      sourceName: filePath.isEmpty ? 'memory_pdf' : filePath,
    );
    _cache[filePath] = document;
    return document;
  }

  void dispose() {
    for (final documentFuture in _cache.values) {
      Future.value(documentFuture).then((document) => document.dispose());
    }
    _cache.clear();
  }
}
