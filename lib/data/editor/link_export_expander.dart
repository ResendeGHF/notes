// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

// ignore_for_file: avoid_dynamic_calls

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:path/path.dart' as p;
import 'package:saber/components/canvas/_asset_cache.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/note_layer.dart';
import 'package:saber/data/editor/page.dart';

String _resolveTargetPath(String sourcePath, String targetPath) {
  final target = targetPath.trim();
  if (target.isEmpty) return '';
  if (target.startsWith('/')) {
    var norm = target.replaceAll(r'\', '/').trim();
    if (!norm.startsWith('/')) norm = '/$norm';
    return p.posix.normalize(norm).replaceAll(RegExp(r'/+'), '/');
  }
  final sourceDir = p.posix.dirname(sourcePath);
  return p.posix.normalize(p.posix.join(sourceDir, target)).replaceAll(RegExp(r'/+'), '/');
}

String formatLinkDisplayLabel(NoteLink link) {
  final name =
      link.label?.trim().isNotEmpty == true
          ? link.label!
          : (link.targetPath.isNotEmpty ? link.targetPath.split('/').last : '');
  if (link.isRange) {
    return 'p:${link.targetPageIndex + 1}-${link.targetPageIndexEnd! + 1} $name';
  }
  return 'p:${link.targetPageIndex + 1} $name';
}

bool isExternalNoteLink(NoteLink link, String selfFilePath) {
  if (link.targetPath.isEmpty) return false;
  final resolved = _resolveTargetPath(selfFilePath, link.targetPath);
  final selfNorm = _resolveTargetPath(selfFilePath, selfFilePath);
  return resolved != selfNorm;
}

String formatLinkLabelForPdf(NoteLink link) {
  if (link.label?.trim().isNotEmpty == true) return link.label!;
  final name = link.targetPath.isEmpty
      ? 'Page ${link.targetPageIndex + 1}'
      : link.targetPath.split('/').last;
  if (link.targetPageIndexEnd != null &&
      link.targetPageIndexEnd != link.targetPageIndex) {
    return 'p:${link.targetPageIndex + 1}-${link.targetPageIndexEnd! + 1} $name';
  }
  return 'p:${link.targetPageIndex + 1} $name';
}

Future<EditorImage?> _copyImageWithMergedAsset(
  EditorImage source,
  AssetCacheAll targetCache,
  Map<int, int> assetIdMap,
  int pageIndex,
) async {
  final oldId = source is PdfEditorImage
      ? source.assetId
      : (source is PngEditorImage
          ? source.assetId
          : (source is SvgEditorImage ? source.assetId : -1));
  if (oldId < 0) return null;

  int newId;
  if (assetIdMap.containsKey(oldId)) {
    newId = assetIdMap[oldId]!;
  } else {
    final ext = source.extension;
    final bytes = await source.assetCacheAll.getBytes(oldId);
    if (bytes.isEmpty) return null;
    final tempFile = targetCache.createRuntimeFile(ext, Uint8List.fromList(bytes));
    newId = targetCache.length;
    targetCache.addSync(tempFile, ext, newId, null, null, null, null);
    assetIdMap[oldId] = newId;
  }

  if (source is PdfEditorImage) {
    final file = targetCache.getAssetFile(newId);
    return PdfEditorImage(
      id: source.id,
      assetCacheAll: targetCache,
      assetId: newId,
      pdfFile: file,
      pdfPage: source.pdfPage,
      pageIndex: pageIndex,
      pageSize: source.pageSize,
      invertible: source.invertible,
      backgroundFit: source.backgroundFit,
      onMoveImage: null,
      onDeleteImage: null,
      onMiscChange: null,
      dstRect: source.dstRect,
      naturalSize: source.naturalSize,
      isThumbnail: source.isThumbnail,
    )
      ..rotationDeg = source.rotationDeg
      ..locked = source.locked;
  }
  if (source is PngEditorImage) {
    return PngEditorImage(
      id: source.id,
      assetCacheAll: targetCache,
      assetId: newId,
      extension: source.extension,
      imageProviderNotifier: ValueNotifier(null),
      pageIndex: pageIndex,
      pageSize: source.pageSize,
      invertible: source.invertible,
      backgroundFit: source.backgroundFit,
      onMoveImage: null,
      onDeleteImage: null,
      onMiscChange: null,
      dstRect: source.dstRect,
      srcRect: source.srcRect,
      naturalSize: source.naturalSize,
      thumbnailBytes: source.thumbnailBytes,
      isThumbnail: source.isThumbnail,
    )
      ..rotationDeg = source.rotationDeg
      ..locked = source.locked;
  }
  if (source is SvgEditorImage) {
    return SvgEditorImage(
      id: source.id,
      assetCacheAll: targetCache,
      assetId: newId,
      pageIndex: pageIndex,
      pageSize: source.pageSize,
      invertible: source.invertible,
      backgroundFit: source.backgroundFit,
      onMoveImage: null,
      onDeleteImage: null,
      onMiscChange: null,
      dstRect: source.dstRect,
      srcRect: source.srcRect,
      naturalSize: source.naturalSize,
      isThumbnail: source.isThumbnail,
    )
      ..rotationDeg = source.rotationDeg
      ..locked = source.locked;
  }
  return null;
}

Future<EditorPage> _copyPageForExport(
  EditorPage source,
  EditorCoreInfo externalCoreInfo,
  EditorCoreInfo targetCoreInfo,
  Map<int, int> assetIdMap,
  int pageIndex,
) async {
  final layers = <NoteLayer>[];
  final layerOrder = <int>[];

  for (var i = 0; i < source.layerCount; i++) {
    final layer = source.layerAt(i);
    final newStrokes = layer.strokes.map((s) => s.copy()).toList();
    final newImages = <EditorImage>[];
    for (final img in layer.images) {
      final copied = await _copyImageWithMergedAsset(
        img,
        targetCoreInfo.assetCacheAll,
        assetIdMap,
        pageIndex,
      );
      if (copied != null) newImages.add(copied);
    }
    layers.add(NoteLayer(name: layer.name, strokes: newStrokes, images: newImages));
    layerOrder.add(i);
  }

  EditorImage? newBgImage;
  if (source.backgroundImage != null) {
    newBgImage = await _copyImageWithMergedAsset(
      source.backgroundImage!,
      targetCoreInfo.assetCacheAll,
      assetIdMap,
      pageIndex,
    );
  }

  final newQuill = QuillStruct(
    controller: QuillController(
      document: Document.fromDelta(source.quill.controller.document.toDelta()),
      selection: const TextSelection.collapsed(offset: 0),
    ),
    focusNode: FocusNode(debugLabel: 'Quill Focus Node'),
  );

  final newPage = EditorPage(
    size: source.size,
    id: null,
    quill: newQuill,
    backgroundImage: newBgImage,
    backgroundPattern: source.backgroundPattern,
    lineColor: source.lineColor,
    backgroundColor: source.backgroundColor,
    lineHeight: source.lineHeight,
    lineThickness: source.lineThickness,
    hasLocalPattern: source.hasLocalPattern,
    hasLocalBackgroundColor: source.hasLocalBackgroundColor,
    hasLocalLineColor: source.hasLocalLineColor,
    hasLocalLineHeight: source.hasLocalLineHeight,
    hasLocalLineThickness: source.hasLocalLineThickness,
    hasLocalMargins: source.hasLocalMargins,
    hasLocalBorderColor: source.hasLocalBorderColor,
    borderColor: source.borderColor,
    marginLeft: source.marginLeft,
    marginRight: source.marginRight,
    marginTop: source.marginTop,
    marginBottom: source.marginBottom,
  );
  newPage.replaceLayersFromBinary(layers, layerOrder);
  newPage.activeLayerIndex = source.activeLayerIndex.clamp(0, layers.length - 1);
  return newPage;
}

Future<EditorCoreInfo> expandLinksForShare(
  EditorCoreInfo source,
  bool shareLinks,
) async {
  if (!shareLinks || source.links.isEmpty) {
    return source;
  }

  final selfPath = source.filePath;
  final hasExternal = source.links.any((l) => isExternalNoteLink(l, selfPath));
  if (!hasExternal) return source;

  final newPages = <EditorPage>[];
  final newLinks = <NoteLink>[];
  final newCache = AssetCacheAll();

  final targetCoreInfo = source.copyWith(
    assetCacheAll: newCache,
    pages: [],
    links: [],
    readOnly: true,
  );

  final assetIdMap = <int, int>{};
  for (var i = 0; i < source.assetCacheAll.length; i++) {
    assetIdMap[i] = i;
  }
  for (var i = 0; i < source.assetCacheAll.length; i++) {
    final bytes = await source.assetCacheAll.getBytes(i);
    if (bytes.isNotEmpty) {
      final ext = source.assetCacheAll.getAssetExtension(i);
      final tempFile = newCache.createRuntimeFile(ext, Uint8List.fromList(bytes));
      newCache.addSync(tempFile, ext, i, null, null, null, null);
    }
  }

  var currentPageNewIndex = 0;

  for (var origPageIdx = 0; origPageIdx < source.pages.length; origPageIdx++) {
    final origPage = source.pages[origPageIdx];
    final linksOnPage = source.linksForPage(origPage, origPageIdx);

    final pageCopy = await _copyPageForExport(
      origPage,
      source,
      targetCoreInfo,
      assetIdMap,
      newPages.length,
    );
    pageCopy.id = targetCoreInfo.allocatePageId();
    newPages.add(pageCopy);
    currentPageNewIndex = newPages.length - 1;

    for (final link in linksOnPage) {
      if (!isExternalNoteLink(link, selfPath)) {
        newLinks.add(link);
        continue;
      }

      final resolvedPath = _resolveTargetPath(selfPath, link.targetPath);
      if (resolvedPath.isEmpty) {
        newLinks.add(link);
        continue;
      }

      EditorCoreInfo? externalInfo;
      try {
        externalInfo = await EditorCoreInfo.loadFromFilePath(resolvedPath, readOnly: true);
      } catch (_) {
        newLinks.add(link);
        continue;
      }

      if (externalInfo.pages.isEmpty) {
        newLinks.add(link);
        continue;
      }

      final start = link.targetPageIndex;
      final end = link.targetPageIndexEnd ?? link.targetPageIndex;
      final maxIdx = externalInfo.pages.length - 1;
      final from = start.clamp(0, maxIdx);
      final to = end.clamp(from, maxIdx);

      final sourcePageIdx = currentPageNewIndex;
      final firstAppendedIndex = newPages.length;
      final externalAssetMap = <int, int>{};

      for (var k = from; k <= to; k++) {
        final extPage = externalInfo.pages[k];
        final appendedPageIndex = currentPageNewIndex + 1 + (k - from);
        final copied = await _copyPageForExport(
          extPage,
          externalInfo,
          targetCoreInfo,
          externalAssetMap,
          appendedPageIndex,
        );
        copied.id = targetCoreInfo.allocatePageId();
        newPages.add(copied);
        currentPageNewIndex = newPages.length - 1;
      }

      final lastAppendedIndex = currentPageNewIndex;
      final displayName =
          link.label?.trim().isNotEmpty == true
              ? link.label!
              : resolvedPath.split('/').last;
      final displayLabel = from == to
          ? 'p:${from + 1} $displayName'
          : 'p:${from + 1}-${to + 1} $displayName';
      final mutatedLink = NoteLink(
        sourcePageId: pageCopy.id,
        sourcePageIndex: sourcePageIdx,
        targetPath: '',
        targetPageIndex: firstAppendedIndex,
        targetPageIndexEnd: lastAppendedIndex,
        label: displayLabel,
      );
      newLinks.add(mutatedLink);
    }
  }

  targetCoreInfo.pages.clear();
  targetCoreInfo.pages.addAll(newPages);
  targetCoreInfo.links = newLinks;
  targetCoreInfo.nextImageId = targetCoreInfo.assetCacheAll.length;

  targetCoreInfo.normalizePagesAfterLoad(sortStrokes: false, fixImageIds: true);
  return targetCoreInfo;
}
