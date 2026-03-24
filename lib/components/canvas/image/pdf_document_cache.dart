// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

class PdfDocumentCache {
  final Map<String, FutureOr<PdfDocument>> _cache = {};

  FutureOr<PdfDocument> load(String filePath, {Uint8List? pdfBytes}) {
    return _cache[filePath] ??= _loadCacheMiss(filePath, pdfBytes: pdfBytes);
  }

  Future<PdfDocument> _loadCacheMiss(
    String filePath, {
    Uint8List? pdfBytes,
  }) async {
    final document = pdfBytes == null
        ? PdfDocument.openFile(filePath)
        : PdfDocument.openData(pdfBytes);
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
