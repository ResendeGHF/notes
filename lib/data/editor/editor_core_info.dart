// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member

import 'dart:async';
import 'dart:convert';

import 'package:archive/archive_io.dart';
import 'package:bson/bson.dart';
import 'package:crypto/crypto.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:logging/logging.dart';
import 'package:saber/components/canvas/_asset_cache.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/editor/binary_writer.dart';
import 'package:saber/data/editor/canvas_background_pattern.dart';
import 'package:saber/data/editor/note_tool_settings.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/editor/pdf_outline.dart';
import 'package:saber/data/extensions/dynamic_extensions.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tags_database.dart';
import 'package:saber/data/tools/stroke_properties.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:saber/services/vault_adapter.dart';
import 'package:worker_manager/worker_manager.dart';

class NoteLink {

  final int? sourcePageId;
  final int sourcePageIndex;
  final String targetPath;

  final int targetPageIndex;

  final int? targetPageIndexEnd;
  final String? label;

  const NoteLink({
    this.sourcePageId,
    required this.sourcePageIndex,
    required this.targetPath,
    required this.targetPageIndex,
    this.targetPageIndexEnd,
    this.label,
  });

  int get firstPageToOpen => targetPageIndex;

  bool get isRange =>
      targetPageIndexEnd != null && targetPageIndexEnd != targetPageIndex;

  Map<String, dynamic> toJson() => {
    if (sourcePageId != null) 'sid': sourcePageId,
    'sp': sourcePageIndex,
    'tp': targetPath,
    'ti': targetPageIndex,
    if (targetPageIndexEnd != null) 'tie': targetPageIndexEnd,
    if (label != null && label!.isNotEmpty) 'l': label,
  };

  factory NoteLink.fromJson(Map<String, dynamic> json) {
    return NoteLink(
      sourcePageId: (json['sid'] as num?)?.toInt(),
      sourcePageIndex: (json['sp'] as num?)?.toInt() ?? 0,
      targetPath: (json['tp'] as String? ?? '').trim(),
      targetPageIndex: (json['ti'] as num?)?.toInt() ?? 0,
      targetPageIndexEnd: (json['tie'] as num?)?.toInt(),
      label: (json['l'] as String?)?.trim(),
    );
  }
}

class EditorCoreInfo extends ChangeNotifier {
  static final log = Logger('EditorCoreInfo');

  static const int sbnVersion = 19;

  var readOnly = false;
  var readOnlyBecauseOfVersion = false;
  var readOnlyBecauseWatchingServer = false;

  var creationDate = 0;
  var lastModification = 0;
  var lastAccess = 0;
  var totalTimeSpentEditing = 0;
  var totalTimeSpent = 0;
  String? location;

  String filePath;

  String get fileName => filePath.substring(filePath.lastIndexOf('/') + 1);

  AssetCacheAll assetCacheAll;
  int nextImageId;

  int nextPageId;
  Color? backgroundColor;
  CanvasBackgroundPattern backgroundPattern;
  int lineHeight;
  int lineThickness;
  List<EditorPage> pages;

  int? initialPageIndex;

  String? firstPageHash;

  List<PdfOutlineItem>? pdfOutlines;
  List<String> tags;
  List<NoteLink> links;

  CanvasBackgroundPattern? noteDefaultPattern;
  int? noteDefaultPageColor;
  int? noteDefaultLineColor;
  int? noteDefaultLineHeight;
  double? noteDefaultLineThickness;
  double? noteDefaultMarginLeft;
  double? noteDefaultMarginRight;
  double? noteDefaultMarginTop;
  double? noteDefaultMarginBottom;
  int? noteDefaultBorderColor;

  PageOrientation notePageOrientation = PageOrientation.portrait;

  bool isInfinite = false;

  String infiniteThumbnailMode = 'jdenticon';

  NoteToolSettings? noteToolSettings;

  String? _lastGeneratedThumbnailHash;

  bool get shouldGenerateThumbnail {

    if (firstPageHash == null || firstPageHash!.isEmpty) return true;

    return firstPageHash != _lastGeneratedThumbnailHash;
  }

  void notifyThumbnailGenerated() {
    _lastGeneratedThumbnailHash = firstPageHash;
  }

  static final empty =
      EditorCoreInfo._(
        filePath: '',
        readOnly: true,
        readOnlyBecauseOfVersion: false,
        nextImageId: 0,
        nextPageId: 0,
        backgroundColor: null,
        backgroundPattern: CanvasBackgroundPattern.none,
        lineHeight: stows.lastLineHeight.value,
        lineThickness: stows.lastLineThickness.value,
        pages: [],
        initialPageIndex: null,
        assetCacheAll: null,
        firstPageHash: null,
        pdfOutlines: null,
        tags: const [],
        links: const [],
        creationDate: 0,
        lastModification: 0,
        lastAccess: 0,
        totalTimeSpentEditing: 0,
        totalTimeSpent: 0,
        location: null,
      ).._migrateOldStrokesAndImages(
        fileVersion: sbnVersion,
        strokesJson: null,
        imagesJson: null,
        inlineAssets: null,
        onlyFirstPage: true,
      );

  bool get isEmpty => pages.every((EditorPage page) => page.isEmpty);
  bool get isNotEmpty => !isEmpty;

  EditorCoreInfo({
    required this.filePath,
    this.readOnly =
        true,
  }) : nextImageId = 0,
       nextPageId = 0,
       backgroundPattern = stows.lastBackgroundPattern.value,
       lineHeight = stows.lastLineHeight.value,
       lineThickness = stows.lastLineThickness.value,
       pages = [],
       assetCacheAll = AssetCacheAll(),
       tags = [],
       links = [];

  EditorCoreInfo._({
    required this.filePath,
    required this.readOnly,
    required this.readOnlyBecauseOfVersion,
    required this.nextImageId,
    required this.nextPageId,
    this.backgroundColor,
    required this.backgroundPattern,
    required this.lineHeight,
    required this.lineThickness,
    required this.pages,
    required this.initialPageIndex,
    required AssetCacheAll? assetCacheAll,
    this.firstPageHash,
    this.pdfOutlines,
    List<String>? tags,
    List<NoteLink>? links,
    this.isInfinite = false,
    this.infiniteThumbnailMode = 'jdenticon',
    this.creationDate = 0,
    this.lastModification = 0,
    this.lastAccess = 0,
    this.totalTimeSpentEditing = 0,
    this.totalTimeSpent = 0,
    this.location,
  }) : assetCacheAll = assetCacheAll ?? AssetCacheAll(),
       tags = tags ?? <String>[],
       links = links ?? <NoteLink>[] {

    _lastGeneratedThumbnailHash = firstPageHash;
  }

  factory EditorCoreInfo.fromJson(
    Map<String, dynamic> json, {
    required String filePath,
    required bool readOnly,
    required bool onlyFirstPage,
  }) {
    final fileVersion = toIntSafe(json['v']) ?? 0;
    final readOnlyBecauseOfVersion = fileVersion > sbnVersion;
    readOnly = readOnly || readOnlyBecauseOfVersion;

    final List<Uint8List>? inlineAssets = (json['a'] as List?)
        ?.map(
          (asset) => switch (asset) {
            (String base64) => base64Decode(base64),
            (Uint8List bytes) => bytes,
            (List<dynamic> bytes) => Uint8List.fromList(bytes.cast<int>()),
            (BsonBinary bsonBinary) => bsonBinary.byteList,
            _ => () {
              log.severe('Invalid asset type: ${asset.runtimeType}');
              return Uint8List(0);
            }(),
          },
        )
        .toList();

    final Color? backgroundColor;
    switch (json['b']) {
      case (int value):
        backgroundColor = Color(value);
      case (Int64 value):
        backgroundColor = Color(value.toInt());
      case null:
        backgroundColor = null;
      default:
        throw Exception(
          'Invalid color value: (${json['b'].runtimeType}) ${json['b']}',
        );
    }

    final assetCacheAll = AssetCacheAll();

    return EditorCoreInfo._(
        filePath: filePath,
        readOnly: readOnly,
        readOnlyBecauseOfVersion: readOnlyBecauseOfVersion,
        nextImageId: toIntSafe(json['ni']) ?? 0,
        nextPageId: 0,
        backgroundColor: backgroundColor,
        backgroundPattern: () {
          final String? pattern = json['p'] as String?;
          for (final p in CanvasBackgroundPattern.values) {
            if (p.name == pattern) return p;
          }
          return CanvasBackgroundPattern.none;
        }(),
        lineHeight: toIntSafe(json['l']) ?? stows.lastLineHeight.value,
        lineThickness: toIntSafe(json['lt']) ?? stows.lastLineThickness.value,
        pages: _parsePagesJson(
          json['z'] as List?,
          inlineAssets: inlineAssets,
          readOnly: readOnly,
          onlyFirstPage: onlyFirstPage,
          fileVersion: fileVersion,
          sbnPath: filePath,
          assetCacheAll: assetCacheAll,
        ),
        initialPageIndex: toIntSafe(json['c']),
        assetCacheAll: assetCacheAll,
        firstPageHash: json['fh'] as String?,
        pdfOutlines: json['po'] != null
            ? (json['po'] as List)
                  .map(
                    (o) => PdfOutlineItem.fromJson(o as Map<String, dynamic>),
                  )
                  .toList()
            : null,
        tags: ((json['tags'] as List?) ?? const [])
            .whereType<String>()
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList(),
        links: ((json['links'] as List?) ?? const [])
            .whereType<Map>()
            .map(
              (item) => NoteLink.fromJson(
                item.map((key, value) => MapEntry(key.toString(), value)),
              ),
            )
            .toList(),
        isInfinite: json['inf'] == true,
        infiniteThumbnailMode: json['itm'] as String? ?? 'jdenticon',
        creationDate: toIntSafe(json['crd']) ?? 0,
        lastModification: toIntSafe(json['lmd']) ?? 0,
        lastAccess: toIntSafe(json['lad']) ?? 0,
        totalTimeSpentEditing: toIntSafe(json['tts']) ?? 0,
        totalTimeSpent: toIntSafe(json['tso']) ?? toIntSafe(json['tts']) ?? 0,
        location: json['loc']?.toString(),
      )
      .._migrateOldStrokesAndImages(
        fileVersion: fileVersion,
        strokesJson: json['s'] as List?,
        imagesJson: json['i'] as List?,
        inlineAssets: inlineAssets,
        fallbackPageSize: json['w'] != null && json['h'] != null
            ? Size(toDoubleSafe(json['w'])!, toDoubleSafe(json['h'])!)
            : null,
        onlyFirstPage: onlyFirstPage,
      )
      ..enforceSinglePage()
      .._normalizePagesAfterLoad(sortStrokes: true, fixImageIds: true);
  }

  EditorCoreInfo.fromOldJson(
    List<dynamic> json, {
    required this.filePath,
    this.readOnly = false,
    required bool onlyFirstPage,
  }) : nextImageId = 0,
       nextPageId = 0,
       backgroundPattern = CanvasBackgroundPattern.none,
       lineHeight = stows.lastLineHeight.value,
       lineThickness = stows.lastLineThickness.value,
       pages = [],
       assetCacheAll = AssetCacheAll(),
       tags = [],
       links = [] {
    _migrateOldStrokesAndImages(
      fileVersion: 0,
      strokesJson: json,
      imagesJson: null,
      inlineAssets: null,
      onlyFirstPage: onlyFirstPage,
    );
    _normalizePagesAfterLoad(sortStrokes: true, fixImageIds: true);
  }

  static List<EditorPage> _parsePagesJson(
    List<dynamic>? pages, {
    required List<Uint8List>? inlineAssets,
    required bool readOnly,
    required bool onlyFirstPage,
    required int fileVersion,
    required String sbnPath,
    required AssetCacheAll assetCacheAll,
  }) {
    if (pages == null || pages.isEmpty) return [];
    if (pages[0] is List) {

      return pages
          .take(onlyFirstPage ? 1 : pages.length)
          .map(
            (dynamic page) => EditorPage(
              width: toDoubleSafe(page[0]),
              height: toDoubleSafe(page[1]),
            ),
          )
          .toList();
    } else {
      return pages
          .take(onlyFirstPage ? 1 : pages.length)
          .map(
            (dynamic page) => EditorPage.fromJson(
              page as Map<String, dynamic>,
              inlineAssets: inlineAssets,
              readOnly: readOnly,
              fileVersion: fileVersion,
              sbnPath: sbnPath,
              assetCacheAll: assetCacheAll,
            ),
          )
          .toList();
    }
  }

  static const _kInfiniteCanvasMinSize = Size(1600, 900);

  void enforceSinglePage() {
    if (!isInfinite) return;
    if (pages.length > 1) _collapseInfiniteToSinglePage();
    if (pages.isEmpty) return;
    final p = pages.first;
    if (p.size.width < _kInfiniteCanvasMinSize.width ||
        p.size.height < _kInfiniteCanvasMinSize.height) {
      p.resizeInfiniteCanvas(_kInfiniteCanvasMinSize);
      p.buildSpatialIndex();
    }
  }

  void _collapseInfiniteToSinglePage() {
    if (!isInfinite || pages.length <= 1) return;
    final first = pages.first;
    double offsetY = first.size.height;
    for (int i = 1; i < pages.length; i++) {
      final p = pages[i];
      final shift = Offset(0, offsetY);
      for (final stroke in p.allStrokesInDrawOrder.toList()) {
        stroke.shift(shift);
        stroke.pageIndex = 0;
        stroke.page = first;
        first.layerAt(0).insertStroke(stroke);
      }
      for (final img in p.allImagesInDrawOrder.toList()) {
        img.dstRect = img.dstRect.shift(shift);
        img.pageIndex = 0;
        first.layerAt(0).addImage(img);
      }
      offsetY += p.size.height;
      p.dispose();
    }
    pages.removeRange(1, pages.length);
    first.buildSpatialIndex();
    first.notifyListeners();
  }

  void _normalizePagesAfterLoad({
    required bool sortStrokes,
    required bool fixImageIds,
  }) {
    for (final page in pages) {
      if (sortStrokes) {
        page.sortStrokes();
      }
      if (fixImageIds) {
        for (final image in page.allImagesInDrawOrder) {
          if (image.id == -1) image.id = nextImageId++;
        }
      }
      if (page.id == null) {
        page.id = nextPageId++;
      } else if (page.id! >= nextPageId) {
        nextPageId = page.id! + 1;
      }
    }
    links = links.map((l) {
      if (l.sourcePageId != null) return l;
      final i = l.sourcePageIndex;
      if (i < 0 || i >= pages.length) return l;
      final pageId = pages[i].id;
      if (pageId == null) return l;
      return NoteLink(
        sourcePageId: pageId,
        sourcePageIndex: l.sourcePageIndex,
        targetPath: l.targetPath,
        targetPageIndex: l.targetPageIndex,
        targetPageIndexEnd: l.targetPageIndexEnd,
        label: l.label,
      );
    }).toList();
  }

  int allocatePageId() => nextPageId++;

  List<NoteLink> linksForPage(EditorPage page, int pageIndex) {
    return links
        .where(
          (l) =>
              (l.sourcePageId != null && l.sourcePageId == page.id) ||
              (l.sourcePageId == null && l.sourcePageIndex == pageIndex),
        )
        .toList();
  }

  void ensureDocumentDefaultsFromGlobal() {
    if (noteDefaultPattern != null) return;
    noteDefaultPattern = stows.lastBackgroundPattern.value;
    noteDefaultPageColor = stows.defaultPageColor.value;
    noteDefaultLineColor = stows.defaultLineColor.value;
    noteDefaultLineHeight = stows.lastLineHeight.value;
    noteDefaultLineThickness = stows.lastLineThickness.value.toDouble();
    noteDefaultMarginLeft = stows.defaultMarginLeft.value;
    noteDefaultMarginRight = stows.defaultMarginRight.value;
    noteDefaultMarginTop = stows.defaultMarginTop.value;
    noteDefaultMarginBottom = stows.defaultMarginBottom.value;
    final hasMargins =
        noteDefaultMarginLeft! > 0 ||
        noteDefaultMarginRight! > 0 ||
        noteDefaultMarginTop! > 0 ||
        noteDefaultMarginBottom! > 0;
    noteDefaultBorderColor = hasMargins ? stows.defaultMarginColor.value : null;
  }

  EditorPage createPageWithDefaults({Size? size}) {
    final s = size ?? EditorPage.defaultSize;

    ensureDocumentDefaultsFromGlobal();

    final pattern = noteDefaultPattern!;
    final backgroundColor = Color(noteDefaultPageColor!);
    final lineColor = Color(noteDefaultLineColor!);
    final lineHeight = noteDefaultLineHeight!;
    final lineThickness = noteDefaultLineThickness!;

    final effectivePattern =
        isInfinite &&
            pattern != CanvasBackgroundPattern.none &&
            pattern != CanvasBackgroundPattern.grid &&
            pattern != CanvasBackgroundPattern.dots
        ? CanvasBackgroundPattern.none
        : pattern;

    final ml = noteDefaultMarginLeft!;
    final mr = noteDefaultMarginRight!;
    final mt = noteDefaultMarginTop!;
    final mb = noteDefaultMarginBottom!;
    final borderColor = noteDefaultBorderColor != null
        ? Color(noteDefaultBorderColor!)
        : null;

    final hasMargins = ml > 0 || mr > 0 || mt > 0 || mb > 0;

    return EditorPage(
      size: s,
      backgroundPattern: effectivePattern,
      backgroundColor: backgroundColor,
      lineColor: lineColor,
      lineHeight: lineHeight,
      lineThickness: lineThickness,
      hasLocalPattern: true,
      hasLocalBackgroundColor: true,
      hasLocalLineColor: true,
      hasLocalLineHeight: true,
      hasLocalLineThickness: true,
      hasLocalMargins: hasMargins,
      hasLocalBorderColor: borderColor != null,
      marginLeft: ml,
      marginRight: mr,
      marginTop: mt,
      marginBottom: mb,
      borderColor: borderColor,
    );
  }

  EditorPage _createPageWithDefaults(Size size) =>
      createPageWithDefaults(size: size);

  void _migrateOldStrokesAndImages({
    required int fileVersion,
    required List<dynamic>? strokesJson,
    required List<dynamic>? imagesJson,
    required List<Uint8List>? inlineAssets,
    Size? fallbackPageSize,
    required bool onlyFirstPage,
  }) {
    final pageSize = fallbackPageSize ?? EditorPage.defaultSize;
    if (strokesJson != null) {
      final hasSize = HasSize(pageSize);
      final strokes = EditorPage.parseStrokesJson(
        strokesJson,
        page: hasSize,
        onlyFirstPage: onlyFirstPage,
        fileVersion: fileVersion,
      );
      for (final stroke in strokes) {
        if (onlyFirstPage) assert(stroke.pageIndex == 0);
        while (stroke.pageIndex >= pages.length) {
          pages.add(_createPageWithDefaults(pageSize));
        }
        pages[stroke.pageIndex].insertStroke(stroke);
      }
    }

    if (imagesJson != null) {
      final images = EditorPage.parseImagesJson(
        imagesJson,
        inlineAssets: inlineAssets,
        isThumbnail: readOnly,
        onlyFirstPage: onlyFirstPage,
        sbnPath: filePath,
        assetCacheAll: assetCacheAll,
      );
      for (final image in images) {
        if (onlyFirstPage) assert(image.pageIndex == 0);
        while (image.pageIndex >= pages.length) {
          pages.add(_createPageWithDefaults(pageSize));
        }
        pages[image.pageIndex].layerAt(0).addImage(image);
      }
    }

    if (pages.isEmpty || pages.last.isNotEmpty && !onlyFirstPage) {
      pages.add(_createPageWithDefaults(pageSize));
    }

    if (fileVersion < 12) {
      for (final page in pages) {
        for (final stroke in page.allStrokesInDrawOrder) {
          stroke.optimisePoints();
        }
      }
    }
  }

  String calculateFirstPageHash() {

    if (readOnly && firstPageHash != null && firstPageHash!.isNotEmpty) {
      return firstPageHash!;
    }

    try {
      if (pages.isEmpty) return '';

      final firstPage = pages.first;
      final writer = BinaryWriter();

      writer.writeDoubleNoKey(firstPage.size.width);
      writer.writeDoubleNoKey(firstPage.size.height);
      writer.writeIntNoKey(firstPage.backgroundPattern?.index ?? -1);
      writer.writeIntNoKey(firstPage.lineColor.toARGB32());
      writer.writeIntNoKey(firstPage.backgroundColor.toARGB32());

      if (firstPage.backgroundImage != null) {
        final bg = firstPage.backgroundImage!;
        writer.writeIntNoKey(bg.id);
        writer.writeDoubleNoKey(bg.dstRect.left);
        writer.writeDoubleNoKey(bg.dstRect.top);
        writer.writeDoubleNoKey(bg.dstRect.width);
        writer.writeDoubleNoKey(bg.dstRect.height);
      } else {
        writer.writeIntNoKey(-1);
      }

      writer.writeIntNoKey(firstPage.allImagesInDrawOrder.toList().length);
      for (final img in firstPage.allImagesInDrawOrder) {
        writer.writeIntNoKey(img.id);
        writer.writeDoubleNoKey(img.dstRect.left);
        writer.writeDoubleNoKey(img.dstRect.top);
        writer.writeDoubleNoKey(img.dstRect.width);
        writer.writeDoubleNoKey(img.dstRect.height);
        writer.writeDoubleNoKey(img.rotationDeg);
      }

      writer.writeIntNoKey(firstPage.allStrokesInDrawOrder.toList().length);
      for (final stroke in firstPage.allStrokesInDrawOrder) {
        writer.writeIntNoKey(stroke.color.toARGB32());
        writer.writeFloatNoKey(stroke.options.size);
        writer.writeIntNoKey(stroke.points.length);
        if (stroke.points.isNotEmpty) {

          writer.writeFloatNoKey(stroke.points.first.x);
          writer.writeFloatNoKey(stroke.points.first.y);
          writer.writeFloatNoKey(stroke.points.last.x);
          writer.writeFloatNoKey(stroke.points.last.y);

          final mid = stroke.points[stroke.points.length ~/ 2];
          writer.writeFloatNoKey(mid.x);
          writer.writeFloatNoKey(mid.y);
        }
      }

      if (!firstPage.quill.controller.document.isEmpty()) {
        final plainText = firstPage.quill.controller.document.toPlainText();
        writer.writeStringNoKey(plainText);
      }

      final bytes = writer.toBytes();
      final hash = sha256.convert(bytes);
      return hash.toString();
    } catch (e) {
      log.severe('Failed to calculate first page hash: $e', e);
      return '';
    }
  }

  static Future<EditorCoreInfo> loadFromFilePath(
    String path, {
    bool readOnly = false,
    bool onlyFirstPage = false,
  }) async {
    log.info(
      '[EditorCoreInfo.loadFromFilePath] Loading file: $path (readOnly: $readOnly)',
    );

    final bsonBytes = await FileManager.readFile(path + Editor.extension);

    final String? jsonString;
    if (bsonBytes != null) {
      log.fine(
        '[EditorCoreInfo.loadFromFilePath] Found binary file: ${path + Editor.extension}',
      );
      jsonString = null;
    } else {
      log.fine(
        '[EditorCoreInfo.loadFromFilePath] Binary file not found, trying JSON: ${path + Editor.extensionOldJson}',
      );
      final jsonBytes = await FileManager.readFile(
        path + Editor.extensionOldJson,
      );
      jsonString = jsonBytes != null ? utf8.decode(jsonBytes) : null;
      if (jsonString != null) {
        log.fine(
          '[EditorCoreInfo.loadFromFilePath] Found JSON file: ${path + Editor.extensionOldJson}',
        );
      }
    }

    if (bsonBytes == null && jsonString == null) {

      if (stows.localEncryptionEnabled.value && VaultAdapter.isUnlocked) {
        final relPath = FileManager.toRelativePath(path + Editor.extension);
        try {
          final exists = await VaultAdapter.instance.fileExists(relPath);
          if (exists) {
            throw Exception(
              'ABORT: File exists in Vault but read failed. Preventing overwrite of data.',
            );
          }
        } catch (e) {
          log.severe('Error verifying file existence in vault: $e');
          if (VaultAdapter.isUnlocked) rethrow;
        }
      }

      log.warning(
        '[EditorCoreInfo.loadFromFilePath] File not found, creating empty: $path',
      );
      final info = EditorCoreInfo(filePath: path, readOnly: readOnly);
      info.ensureDocumentDefaultsFromGlobal();
      return info;
    }

    try {
      final coreInfo = await loadFromFileContents(
        jsonString: jsonString,
        bsonBytes: bsonBytes,
        path: path,
        readOnly: readOnly,
        onlyFirstPage: onlyFirstPage,
      );

      coreInfo._prefetchLikelyVisiblePdfAssets();
      coreInfo.tags = await TagDatabase.instance.mergeTagsFromNote(
        path,
        coreInfo.tags,
      );
      return coreInfo;
    } catch (e, stack) {
      log.severe(
        '[EditorCoreInfo.loadFromFilePath] Error loading file: $path',
        e,
        stack,
      );
      rethrow;
    }
  }

  void _prefetchLikelyVisiblePdfAssets() {

    assetCacheAll.prefetchAllPdfAssets();
  }

  @visibleForTesting
  static Future<EditorCoreInfo> loadFromFileContents({
    String? jsonString,
    Uint8List? bsonBytes,
    required String path,
    required bool readOnly,
    required bool onlyFirstPage,
    bool alwaysUseIsolate = false,
  }) async {
    EditorCoreInfo coreInfo;
    try {
      EditorCoreInfo isolate() => _loadFromFileIsolate(
        jsonString,
        bsonBytes,
        path,
        readOnly,
        onlyFirstPage,
      );

      final length = jsonString?.length ?? bsonBytes!.length;

      // CRITICAL: When vault is enabled, do NOT use isolate - causes "UI actions only on root isolate".

      final canUseIsolate = !stows.localEncryptionEnabled.value;

      if ((alwaysUseIsolate || length > 2 * 1024 * 1024) && canUseIsolate) {

        final documentsDirectory = FileManager.documentsDirectory;
        coreInfo = await workerManager.execute(
          () async {

            FlavorConfig.setupFromEnvironment();
            await FileManager.init(
              documentsDirectory: documentsDirectory,
              shouldWatchRootDirectory: false,
            );
            StrokeOptionsExtension.setDefaults();
            return isolate();
          },

          priority: WorkPriority.veryHigh,
        );
      } else {

        coreInfo = isolate();
      }
    } catch (e) {
      log.severe('Failed to load file: $e', e);
      if (kDebugMode) {
        rethrow;
      } else {
        coreInfo = EditorCoreInfo(filePath: path, readOnly: readOnly);
      }
    }

    return coreInfo;
  }

  static EditorCoreInfo _loadFromFileIsolate(
    String? jsonString,
    Uint8List? bsonBytes,
    String path,
    bool readOnly,
    bool onlyFirstPage,
  ) {
    final dynamic json;
    final bool isBinaryFile;
    try {
      if (bsonBytes != null) {
        isBinaryFile =
            bsonBytes.length >= 4 &&
            bsonBytes[0] == 0xFF &&
            bsonBytes[1] == 0xFF &&
            bsonBytes[2] == 0xFF &&
            bsonBytes[3] == 0xFF;
        if (!isBinaryFile) {

          final bsonBinary = BsonBinary.from(bsonBytes);
          json = BsonCodec.deserialize(bsonBinary);
        } else {
          json = [];
        }
      } else if (jsonString != null) {
        json = jsonDecode(jsonString);
        isBinaryFile = false;
      } else {
        throw ArgumentError('Both bsonBytes and jsonString are null');
      }
    } catch (e) {
      log.severe('Failed to parse file from $path: $e', e);
      rethrow;
    }
    if (!isBinaryFile) {

      if (json == null) {
        throw Exception('Failed to parse json from $path');
      } else if (json is List) {

        return EditorCoreInfo.fromOldJson(
          json,
          filePath: path,
          readOnly: readOnly,
          onlyFirstPage: onlyFirstPage,
        );
      } else {
        return EditorCoreInfo.fromJson(
          json as Map<String, dynamic>,
          filePath: path,
          readOnly: readOnly,
          onlyFirstPage: onlyFirstPage,
        );
      }
    } else {

      return EditorCoreInfo.fromBinary(
        buffer: bsonBytes!,
        filePath: path,
        readOnly: readOnly,
        onlyFirstPage: onlyFirstPage,
      );
    }
  }

  factory EditorCoreInfo.fromBinary({
    required Uint8List buffer,
    required String filePath,
    required bool readOnly,
    required bool onlyFirstPage,
  }) {
    final reader = BinaryReader(buffer);

    reader.readIntNoKey();
    int key;
    final int fileVersion;
    key = reader.readKey();
    if (key == SBNBinaryKeys.version) {
      fileVersion = reader.readIntNoKey();
    } else {
      fileVersion = 0;
    }
    final readOnlyBecauseOfVersion = fileVersion > sbnVersion;
    readOnly = readOnly || readOnlyBecauseOfVersion;

    final int nextImageId;
    final Color? backgroundColor;
    final String pattern;
    final int lineHeight;
    final int lineThickness;
    final int initialPageIndex;

    key = reader.readKey();
    if (key != SBNBinaryKeys.nextImageId) {
      throw Exception('Editor.fromBinary: nextImageId not set');
    }
    nextImageId = reader.readIntNoKey();

    key = reader.readKey();
    if (key == SBNBinaryKeys.backgroundColor) {

      backgroundColor = reader.readColor();

      key = reader.readKey();
    } else {

      backgroundColor = null;
    }

    if (key != SBNBinaryKeys.backgroundPattern) {
      throw Exception('Editor.fromBinary: backgroundPattern not set');
    }

    pattern = reader.readStringNoKey();

    key = reader.readKey();
    if (key != SBNBinaryKeys.lineHeight) {
      throw Exception('Editor.fromBinary: lineHeight not set');
    }
    lineHeight = reader.readIntNoKey();

    key = reader.readKey();
    if (key != SBNBinaryKeys.lineThickness) {
      throw Exception('Editor.fromBinary: lineThickness not set');
    }
    lineThickness = reader.readIntNoKey();

    key = reader.readKey();
    if (key != SBNBinaryKeys.initialPageIndex) {
      throw Exception('Editor.fromBinary: initialPageIndex not set');
    }
    initialPageIndex = reader.readIntNoKey();

    key = reader.readKey();
    if (key != SBNBinaryKeys.pageCount) {
      throw Exception('Editor.fromBinary: pageCount not set');
    }
    reader.readIntNoKey();

    String? firstPageHash;
    if (!reader.isEOF) {
      final nextKey = reader.peekKey();
      if (nextKey == SBNBinaryKeys.firstPageHash) {
        reader.readKey();
        firstPageHash = reader.readStringNoKey();
      }
    }

    List<PdfOutlineItem>? pdfOutlines;
    if (!reader.isEOF) {
      final nextKey = reader.peekKey();
      if (nextKey == SBNBinaryKeys.pdfOutlines) {
        reader.readKey();
        final count = reader.readIntNoKey();
        pdfOutlines = [];
        for (int i = 0; i < count; i++) {
          pdfOutlines.add(_readOutlineStatic(reader));
        }
      }
    }

    List<String> tags = const [];
    if (!reader.isEOF) {
      final nextKey = reader.peekKey();
      if (nextKey == SBNBinaryKeys.noteTags) {
        reader.readKey();
        final count = reader.readIntNoKey();
        final loaded = <String>[];
        for (int i = 0; i < count; i++) {
          final tag = reader.readStringNoKey().trim();
          if (tag.isNotEmpty) loaded.add(tag);
        }
        tags = loaded.toSet().toList();
      }
    }

    List<NoteLink> links = const [];
    if (!reader.isEOF) {
      final nextKey = reader.peekKey();
      if (nextKey == SBNBinaryKeys.noteLinks) {
        reader.readKey();
        final linkFormatVersion = reader.readIntNoKey();
        final count = reader.readIntNoKey();
        final loaded = <NoteLink>[];
        for (int i = 0; i < count; i++) {
          final int? sourcePageId;
          final int sourcePageIndex;
          if (linkFormatVersion >= 2) {
            final sid = reader.readIntNoKey();
            sourcePageId = sid >= 0 ? sid : null;
            sourcePageIndex = reader.readIntNoKey();
          } else {
            sourcePageId = null;
            sourcePageIndex = reader.readIntNoKey();
          }
          final targetPath = reader.readStringNoKey().trim();
          final targetPageIndex = reader.readIntNoKey();
          int? targetPageIndexEnd;
          if (linkFormatVersion >= 3) {
            final hasRange = reader.readBoolNoKey();
            if (hasRange) {
              final tie = reader.readIntNoKey();
              if (tie >= 0 && tie != targetPageIndex) targetPageIndexEnd = tie;
            }
          }
          final hasLabel = reader.readBoolNoKey();
          final label = hasLabel ? reader.readStringNoKey() : null;
          loaded.add(
            NoteLink(
              sourcePageId: sourcePageId,
              sourcePageIndex: sourcePageIndex,
              targetPath: targetPath,
              targetPageIndex: targetPageIndex,
              targetPageIndexEnd:
                  targetPageIndexEnd != null &&
                      targetPageIndexEnd >= 0 &&
                      targetPageIndexEnd != targetPageIndex
                  ? targetPageIndexEnd
                  : null,
              label: label,
            ),
          );
        }
        links = loaded;
      }
    }

    bool replaceDefaultLoaded = false;
    bool isInfiniteLoaded = false;
    String infiniteThumbnailModeLoaded = 'jdenticon';
    int creationDateLoaded = 0;
    int lastModificationLoaded = 0;
    int lastAccessLoaded = 0;
    int totalTimeSpentEditingLoaded = 0;
    int totalTimeSpentLoaded = 0;
    String? locationLoaded;
    CanvasBackgroundPattern? noteDefaultPatternLoaded;
    int? noteDefaultPageColorLoaded;
    int? noteDefaultLineColorLoaded;
    int? noteDefaultLineHeightLoaded;
    double? noteDefaultLineThicknessLoaded;
    double? noteDefaultMarginLeftLoaded;
    double? noteDefaultMarginRightLoaded;
    double? noteDefaultMarginTopLoaded;
    double? noteDefaultMarginBottomLoaded;
    int? noteDefaultBorderColorLoaded;
    PageOrientation notePageOrientationLoaded = PageOrientation.portrait;
    NoteToolSettings? noteToolSettingsLoaded;

    while (!reader.isEOF) {
      final nextKey = reader.peekKey();
      if (nextKey == SBNBinaryKeys.pages) break;
      reader.readKey();
      if (nextKey == SBNBinaryKeys.replaceDefaultWithPageSettings) {
        replaceDefaultLoaded = reader.readBoolNoKey();

        final k13 = reader.readKey();
        if (k13 == SBNBinaryKeys.noteDefaultPattern) {
          final patternName = reader.readStringNoKey();
          for (final p in CanvasBackgroundPattern.values) {
            if (p.name == patternName) {
              noteDefaultPatternLoaded = p;
              break;
            }
          }
          noteDefaultPatternLoaded ??= CanvasBackgroundPattern.none;
        }
        while (!reader.isEOF) {
          final pk = reader.peekKey();
          if (pk == SBNBinaryKeys.noteDefaultPageColor) {
            reader.readKey();
            noteDefaultPageColorLoaded = reader.readIntNoKey();
          } else if (pk == SBNBinaryKeys.noteDefaultLineColor) {
            reader.readKey();
            noteDefaultLineColorLoaded = reader.readIntNoKey();
          } else if (pk == SBNBinaryKeys.noteDefaultLineHeight) {
            reader.readKey();
            noteDefaultLineHeightLoaded = reader.readIntNoKey();
          } else if (pk == SBNBinaryKeys.noteDefaultLineThickness) {
            reader.readKey();
            noteDefaultLineThicknessLoaded = reader.readDoubleNoKey();
          } else if (pk == SBNBinaryKeys.noteDefaultMarginLeft) {
            reader.readKey();
            noteDefaultMarginLeftLoaded = reader.readDoubleNoKey();
          } else if (pk == SBNBinaryKeys.noteDefaultMarginRight) {
            reader.readKey();
            noteDefaultMarginRightLoaded = reader.readDoubleNoKey();
          } else if (pk == SBNBinaryKeys.noteDefaultMarginTop) {
            reader.readKey();
            noteDefaultMarginTopLoaded = reader.readDoubleNoKey();
          } else if (pk == SBNBinaryKeys.noteDefaultMarginBottom) {
            reader.readKey();
            noteDefaultMarginBottomLoaded = reader.readDoubleNoKey();
          } else if (pk == SBNBinaryKeys.noteDefaultBorderColor) {
            reader.readKey();
            noteDefaultBorderColorLoaded = reader.readIntNoKey();
          } else {
            break;
          }
        }
      } else if (nextKey == SBNBinaryKeys.notePageOrientation) {
        notePageOrientationLoaded =
            PageOrientation.values[reader.readIntNoKey()];
      } else if (nextKey == SBNBinaryKeys.noteToolSettings) {
        noteToolSettingsLoaded = NoteToolSettings.fromJsonString(
          reader.readStringNoKey(),
        );
      } else if (nextKey == SBNBinaryKeys.isInfinite) {
        isInfiniteLoaded = reader.readBoolNoKey();
      } else if (nextKey == SBNBinaryKeys.infiniteThumbnailMode) {
        infiniteThumbnailModeLoaded = reader.readStringNoKey();
      } else if (nextKey == SBNBinaryKeys.creationDate) {
        creationDateLoaded = reader.readDoubleNoKey().toInt();
      } else if (nextKey == SBNBinaryKeys.lastModification) {
        lastModificationLoaded = reader.readDoubleNoKey().toInt();
      } else if (nextKey == SBNBinaryKeys.lastAccess) {
        lastAccessLoaded = reader.readDoubleNoKey().toInt();
      } else if (nextKey == SBNBinaryKeys.totalTimeSpentEditing) {
        totalTimeSpentEditingLoaded = reader.readDoubleNoKey().toInt();
      } else if (nextKey == SBNBinaryKeys.totalTimeSpent) {
        totalTimeSpentLoaded = reader.readDoubleNoKey().toInt();
      } else if (nextKey == SBNBinaryKeys.location) {
        locationLoaded = reader.readStringNoKey();
      }
    }

    final assetCache = AssetCacheAll();

    if (nextImageId > 0) {

      final cleanPath = FileManager.fixFileNameDelimiters(
        FileManager.getFilePath(filePath + Editor.extension),
      );
      assetCache.ensureCapacity(nextImageId, cleanPath);
    }

    final List<EditorPage> pages = [];
    key = reader.readKey();
    if (key == SBNBinaryKeys.pages) {
      final int count = reader.readIntNoKey();
      for (int i = 0; i < count; i++) {
        pages.add(
          EditorPage.fromBinary(
            reader,
            readOnly: readOnly,
            fileVersion: fileVersion,
            sbnPath: filePath,
            assetCacheAll: assetCache,
          ),
        );
      }
    }

    final info = EditorCoreInfo._(
      filePath: filePath,
      readOnly: readOnly,
      readOnlyBecauseOfVersion: readOnlyBecauseOfVersion,
      nextImageId: nextImageId,
      nextPageId: 0,
      backgroundColor: backgroundColor,
      backgroundPattern: () {
        for (final p in CanvasBackgroundPattern.values) {
          if (p.name == pattern) return p;
        }
        return CanvasBackgroundPattern.none;
      }(),
      lineHeight: lineHeight,
      lineThickness: lineThickness,
      pages: pages,
      initialPageIndex: initialPageIndex,
      assetCacheAll: assetCache,
      firstPageHash: firstPageHash,
      pdfOutlines: pdfOutlines,
      tags: tags,
      links: links,
      creationDate: creationDateLoaded,
      lastModification: lastModificationLoaded,
      lastAccess: lastAccessLoaded,
      totalTimeSpentEditing: totalTimeSpentEditingLoaded,
      totalTimeSpent: totalTimeSpentLoaded > 0
          ? totalTimeSpentLoaded
          : totalTimeSpentEditingLoaded,
      location: locationLoaded,
    );

    if (replaceDefaultLoaded) {
      info.noteDefaultPattern = noteDefaultPatternLoaded;
      info.noteDefaultPageColor = noteDefaultPageColorLoaded;
      info.noteDefaultLineColor = noteDefaultLineColorLoaded;
      info.noteDefaultLineHeight = noteDefaultLineHeightLoaded;
      info.noteDefaultLineThickness = noteDefaultLineThicknessLoaded;
      info.noteDefaultMarginLeft = noteDefaultMarginLeftLoaded;
      info.noteDefaultMarginRight = noteDefaultMarginRightLoaded;
      info.noteDefaultMarginTop = noteDefaultMarginTopLoaded;
      info.noteDefaultMarginBottom = noteDefaultMarginBottomLoaded;
      info.noteDefaultBorderColor = noteDefaultBorderColorLoaded;
    } else {

      info.ensureDocumentDefaultsFromGlobal();
    }
    info.notePageOrientation = notePageOrientationLoaded;
    info.noteToolSettings = noteToolSettingsLoaded;
    info.isInfinite = false;
    info.infiniteThumbnailMode = infiniteThumbnailModeLoaded;

    if (info.isInfinite && info.pages.length > 1) {
      info._collapseInfiniteToSinglePage();
    }

    if (info.isInfinite && info.pages.isNotEmpty) {
      final p = info.pages.first;
      if (p.size.width < _kInfiniteCanvasMinSize.width ||
          p.size.height < _kInfiniteCanvasMinSize.height) {
        p.resizeInfiniteCanvas(_kInfiniteCanvasMinSize);
        p.buildSpatialIndex();
      }
    }
    info._normalizePagesAfterLoad(sortStrokes: false, fixImageIds: true);
    return info;
  }

  static void _writeOutlineStatic(BinaryWriter writer, PdfOutlineItem outline) {
    writer.writeStringNoKey(outline.title);
    writer.writeIntNoKey(outline.pageIndex);
    if (outline.children != null && outline.children!.isNotEmpty) {
      writer.writeIntNoKey(outline.children!.length);
      for (final child in outline.children!) {
        _writeOutlineStatic(writer, child);
      }
    } else {
      writer.writeIntNoKey(0);
    }
  }

  static PdfOutlineItem _readOutlineStatic(BinaryReader reader) {
    final title = reader.readStringNoKey();
    final pageIndex = reader.readIntNoKey();
    final childCount = reader.readIntNoKey();
    List<PdfOutlineItem>? children;
    if (childCount > 0) {
      children = [];
      for (int i = 0; i < childCount; i++) {
        children.add(_readOutlineStatic(reader));
      }
    }
    return PdfOutlineItem(
      title: title,
      pageIndex: pageIndex,
      children: children,
    );
  }

  Map<String, dynamic> toJson() {

    final json = {
      'v': sbnVersion,
      'ni': nextImageId,
      'b': backgroundColor?.toARGB32(),
      'p': backgroundPattern.name,
      'l': lineHeight,
      'lt': lineThickness,
      if (isInfinite) 'inf': true,
      if (isInfinite) 'itm': infiniteThumbnailMode,
      'z': pages.map((EditorPage page) => page.toJson()).toList(),
      'c': initialPageIndex,
      if (firstPageHash != null) 'fh': firstPageHash,
      if (pdfOutlines != null)
        'po': pdfOutlines!.map((o) => o.toJson()).toList(),

      if (links.isNotEmpty) 'links': links.map((l) => l.toJson()).toList(),
    };

    return (json);
  }

  static Uint8List encodeSnapshotToBinary(Map<String, dynamic> jsonMap) {
    throw UnimplementedError('Use saveToBinary() directly');
  }

  Future<List<int>> saveToSba({
    required int? currentPageIndex,
    bool omitLinksForExport = false,
    bool includeExportMetadata = true,
  }) async {
    // CRITICAL: We need to renumber assets before saving to ensure

    const filePath = 'main${Editor.extension}';
    final fullPath = FileManager.fixFileNameDelimiters(
      FileManager.getFilePath(filePath),
    );
    await assetCacheAll.renumberBeforeSave(fullPath);

    final bson = saveToBinary(
      currentPageIndex: currentPageIndex,
      omitLinksForExport: omitLinksForExport,
      includeExportMetadata: includeExportMetadata,
    );

    final archive = Archive();
    archive.addFile(ArchiveFile(filePath, bson.length, bson));

    // CRITICAL: Export only assets that are actually used (refCount > 0)

    final usedAssets =
        <int?>[];

    for (int i = 0; i < assetCacheAll.length; ++i) {
      final assetIdOnSave = assetCacheAll.getAssetIdOnSave(i);
      if (assetIdOnSave >= 0) {
        if (assetIdOnSave >= usedAssets.length) {
          usedAssets.length = assetIdOnSave + 1;
        }
        usedAssets[assetIdOnSave] = i;
      }
    }

    await Future.wait([
      for (
        int assetIdOnSave = 0;
        assetIdOnSave < usedAssets.length;
        ++assetIdOnSave
      )
        if (usedAssets[assetIdOnSave] != null)
          assetCacheAll
              .getBytes(usedAssets[assetIdOnSave]!)
              .then(
                (bytes) => archive.addFile(
                  ArchiveFile('$filePath.$assetIdOnSave', bytes.length, bytes),
                ),
              ),
    ]);

    return ZipEncoder().encode(archive);
  }

  Uint8List saveToBinary({
    required int? currentPageIndex,
    String? precomputedHash,

    bool omitLinksForExport = false,
    bool includeExportMetadata = true,
  }) {
    initialPageIndex = currentPageIndex ?? initialPageIndex;

    final writer = BinaryWriter();

    writer.writeIntNoKey(0xFFFFFFFF);
    writer.writeKey(SBNBinaryKeys.version);
    writer.writeIntNoKey(sbnVersion);

    writer.writeKey(SBNBinaryKeys.nextImageId);
    writer.writeIntNoKey(nextImageId);

    if (backgroundColor != null) {
      writer.writeColor(SBNBinaryKeys.backgroundColor, backgroundColor);
    }

    writer.writeString(SBNBinaryKeys.backgroundPattern, backgroundPattern.name);
    writer.writeKey(SBNBinaryKeys.lineHeight);
    writer.writeIntNoKey(lineHeight);
    writer.writeKey(SBNBinaryKeys.lineThickness);
    writer.writeIntNoKey(lineThickness);
    writer.writeKey(SBNBinaryKeys.initialPageIndex);
    writer.writeIntNoKey(initialPageIndex ?? 0);
    writer.writeKey(SBNBinaryKeys.pageCount);
    writer.writeIntNoKey(pages.length);

    if (includeExportMetadata) {
      String hashToWrite = precomputedHash ?? '';
      if (hashToWrite.isEmpty) {
        if (readOnly && firstPageHash != null) {
          hashToWrite = firstPageHash!;
        } else {
          hashToWrite = calculateFirstPageHash();
        }
      }

      if (hashToWrite.isNotEmpty) {
        writer.writeString(SBNBinaryKeys.firstPageHash, hashToWrite);
        firstPageHash = hashToWrite;
      }
    }

    if (pdfOutlines != null && pdfOutlines!.isNotEmpty) {
      writer.writeKey(SBNBinaryKeys.pdfOutlines);
      writer.writeIntNoKey(pdfOutlines!.length);
      for (final outline in pdfOutlines!) {
        _writeOutlineStatic(writer, outline);
      }
    }

    if (!omitLinksForExport && links.isNotEmpty) {
      writer.writeKey(SBNBinaryKeys.noteLinks);
      writer.writeIntNoKey(
        3,
      );
      writer.writeIntNoKey(links.length);
      for (final link in links) {
        writer.writeIntNoKey(link.sourcePageId ?? -1);
        writer.writeIntNoKey(link.sourcePageIndex);
        writer.writeStringNoKey(link.targetPath);
        writer.writeIntNoKey(link.targetPageIndex);
        writer.writeBoolNoKey(link.targetPageIndexEnd != null);
        if (link.targetPageIndexEnd != null) {
          writer.writeIntNoKey(link.targetPageIndexEnd!);
        }
        final hasLabel = link.label != null && link.label!.isNotEmpty;
        writer.writeBoolNoKey(hasLabel);
        if (hasLabel) writer.writeStringNoKey(link.label!);
      }
    }

    if (noteDefaultPattern != null) {

      writer.writeKey(SBNBinaryKeys.replaceDefaultWithPageSettings);
      writer.writeBoolNoKey(true);
      writer.writeString(
        SBNBinaryKeys.noteDefaultPattern,
        noteDefaultPattern!.name,
      );
      if (noteDefaultPageColor != null) {
        writer.writeKey(SBNBinaryKeys.noteDefaultPageColor);
        writer.writeIntNoKey(noteDefaultPageColor!);
      }
      if (noteDefaultLineColor != null) {
        writer.writeKey(SBNBinaryKeys.noteDefaultLineColor);
        writer.writeIntNoKey(noteDefaultLineColor!);
      }
      if (noteDefaultLineHeight != null) {
        writer.writeKey(SBNBinaryKeys.noteDefaultLineHeight);
        writer.writeIntNoKey(noteDefaultLineHeight!);
      }
      if (noteDefaultLineThickness != null) {
        writer.writeKey(SBNBinaryKeys.noteDefaultLineThickness);
        writer.writeDoubleNoKey(noteDefaultLineThickness!);
      }
      if (noteDefaultMarginLeft != null) {
        writer.writeKey(SBNBinaryKeys.noteDefaultMarginLeft);
        writer.writeDoubleNoKey(noteDefaultMarginLeft!);
      }
      if (noteDefaultMarginRight != null) {
        writer.writeKey(SBNBinaryKeys.noteDefaultMarginRight);
        writer.writeDoubleNoKey(noteDefaultMarginRight!);
      }
      if (noteDefaultMarginTop != null) {
        writer.writeKey(SBNBinaryKeys.noteDefaultMarginTop);
        writer.writeDoubleNoKey(noteDefaultMarginTop!);
      }
      if (noteDefaultMarginBottom != null) {
        writer.writeKey(SBNBinaryKeys.noteDefaultMarginBottom);
        writer.writeDoubleNoKey(noteDefaultMarginBottom!);
      }
      if (noteDefaultBorderColor != null) {
        writer.writeKey(SBNBinaryKeys.noteDefaultBorderColor);
        writer.writeIntNoKey(noteDefaultBorderColor!);
      }
    }
    writer.writeKey(SBNBinaryKeys.notePageOrientation);
    writer.writeIntNoKey(notePageOrientation.index);

    if (noteToolSettings != null) {
      writer.writeKey(SBNBinaryKeys.noteToolSettings);
      writer.writeStringNoKey(noteToolSettings!.toJsonString());
    }
    if (isInfinite) {
      writer.writeKey(SBNBinaryKeys.isInfinite);
      writer.writeBoolNoKey(true);
      writer.writeKey(SBNBinaryKeys.infiniteThumbnailMode);
      writer.writeStringNoKey(infiniteThumbnailMode);
    }

    if (includeExportMetadata) {
      if (creationDate == 0) {
        creationDate = DateTime.now().millisecondsSinceEpoch;
      }

      writer.writeKey(SBNBinaryKeys.creationDate);
      writer.writeDoubleNoKey(creationDate.toDouble());

      writer.writeKey(SBNBinaryKeys.lastModification);
      writer.writeDoubleNoKey(lastModification.toDouble());

      writer.writeKey(SBNBinaryKeys.lastAccess);
      writer.writeDoubleNoKey(lastAccess.toDouble());

      writer.writeKey(SBNBinaryKeys.totalTimeSpentEditing);
      writer.writeDoubleNoKey(totalTimeSpentEditing.toDouble());

      writer.writeKey(SBNBinaryKeys.totalTimeSpent);
      writer.writeDoubleNoKey(totalTimeSpent.toDouble());

      if (location != null) {
        writer.writeKey(SBNBinaryKeys.location);
        writer.writeStringNoKey(location!);
      }
    }

    writer.writeKey(SBNBinaryKeys.pages);
    writer.writeIntNoKey(pages.length);
    for (final page in pages) {

      page.toBinary(writer);
    }

    return writer.toBytes();
  }

  @override
  void dispose() {
    for (final page in pages) {
      page.dispose();
    }
    assetCacheAll.dispose();
    super.dispose();
  }

  void normalizePagesAfterLoad({
    required bool sortStrokes,
    required bool fixImageIds,
  }) {
    _normalizePagesAfterLoad(
      sortStrokes: sortStrokes,
      fixImageIds: fixImageIds,
    );
  }

  EditorCoreInfo copyWith({
    String? filePath,
    bool? readOnly,
    bool? readOnlyBecauseOfVersion,
    int? nextImageId,
    int? nextPageId,
    Color? backgroundColor,
    CanvasBackgroundPattern? backgroundPattern,
    int? lineHeight,
    int? lineThickness,
    QuillController? quillController,
    List<EditorPage>? pages,
    List<String>? tags,
    List<NoteLink>? links,
    AssetCacheAll? assetCacheAll,
    int? creationDate,
    int? lastModification,
    int? lastAccess,
    int? totalTimeSpentEditing,
    int? totalTimeSpent,
    String? location,
  }) {
    final info = EditorCoreInfo._(
      filePath: filePath ?? this.filePath,
      readOnly: readOnly ?? this.readOnly,
      readOnlyBecauseOfVersion:
          readOnlyBecauseOfVersion ?? this.readOnlyBecauseOfVersion,
      nextImageId: nextImageId ?? this.nextImageId,
      nextPageId: nextPageId ?? this.nextPageId,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      backgroundPattern: backgroundPattern ?? this.backgroundPattern,
      lineHeight: lineHeight ?? this.lineHeight,
      lineThickness: lineThickness ?? this.lineThickness,
      pages: pages ?? this.pages,
      initialPageIndex: initialPageIndex,
      assetCacheAll: assetCacheAll ?? this.assetCacheAll,
      firstPageHash: firstPageHash,
      pdfOutlines: pdfOutlines ?? this.pdfOutlines,
      tags: tags ?? this.tags,
      links: links ?? this.links,
      isInfinite: isInfinite,
      infiniteThumbnailMode: infiniteThumbnailMode,
      creationDate: creationDate ?? this.creationDate,
      lastModification: lastModification ?? this.lastModification,
      lastAccess: lastAccess ?? this.lastAccess,
      totalTimeSpentEditing:
          totalTimeSpentEditing ?? this.totalTimeSpentEditing,
      totalTimeSpent: totalTimeSpent ?? this.totalTimeSpent,
      location: location ?? this.location,
    );
    info.noteDefaultPattern = noteDefaultPattern;
    info.noteDefaultPageColor = noteDefaultPageColor;
    info.noteDefaultLineColor = noteDefaultLineColor;
    info.noteDefaultLineHeight = noteDefaultLineHeight;
    info.noteDefaultLineThickness = noteDefaultLineThickness;
    info.noteDefaultMarginLeft = noteDefaultMarginLeft;
    info.noteDefaultMarginRight = noteDefaultMarginRight;
    info.noteDefaultMarginTop = noteDefaultMarginTop;
    info.noteDefaultMarginBottom = noteDefaultMarginBottom;
    info.noteDefaultBorderColor = noteDefaultBorderColor;
    info.notePageOrientation = notePageOrientation;
    info.noteToolSettings = noteToolSettings;
    return info;
  }
}
