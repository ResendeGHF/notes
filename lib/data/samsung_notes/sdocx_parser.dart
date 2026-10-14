// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:saber/data/samsung_notes/sdocx_binary_reader.dart';
import 'package:saber/data/samsung_notes/sdocx_models.dart';

/// Reverse-engineered parser for Samsung Notes `.sdocx` (ZIP) files.
///
/// Based on:
/// - twangodev/sdocx (Rust SDK, modern frame-based format, MIT/GPL-3.0)
/// - bxff/samsung-notes-format `render.py` / `RESEARCH.md`
///   (correct `magnitude = (word & 0x7FFF) / 32` delta decoding from
///   `libSPenModel.so` `SPen::ObjectStrokeBinaryHandler::sm_RestoreStroke`).
///
/// Scope (per requirements): pages, strokes (+ colors), images, PDFs.
/// Deliberately discarded: audio (Voice type 10 / `.m4a`), tables
/// (type 22 + rich-text tables), sticker sub-notes (nested `.sdocx`),
/// `.spi` painting data and all other object types.
class SdocxParser {
  /// Parse an already-unzipped archive: entry name -> bytes.
  /// Expects raw (uncompressed) bytes for each entry.
  static SdocxDocument parseArchive(Map<String, Uint8List> entries) {
    final mediaByBindId = <int, SdocxMediaEntry>{};
    final mediaByFileName = <String, SdocxMediaEntry>{};

    final mediaInfo = entries['media/mediaInfo.dat'];
    if (mediaInfo != null) {
      try {
        final parsed = parseMediaManifest(mediaInfo);
        for (final e in parsed) {
          mediaByBindId[e.bindId] = e;
          mediaByFileName['media/${e.fileName}'] = e;
        }
      } catch (_) {
        // Fall back to filename-prefix inference below.
      }
    }

    // Attach raw bytes for every media/* entry (except .dat manifests).
    for (final kv in entries.entries) {
      if (!kv.key.startsWith('media/')) continue;
      if (kv.key.endsWith('.dat')) continue;
      final fileName = kv.key.substring('media/'.length);
      final bindId = _mediaArchiveId(kv.key);
      SdocxMediaEntry? entry;
      if (bindId != null) entry = mediaByBindId[bindId];
      entry ??= mediaByFileName[kv.key];
      if (entry == null) {
        // No manifest entry (old files): synthesize one. Only images/PDFs
        // are kept later; audio/stickers/spi are still discarded.
        final synth = SdocxMediaEntry(bindId: bindId ?? -1, fileName: fileName);
        if (bindId != null) mediaByBindId[bindId] = synth;
        mediaByFileName[kv.key] = synth;
        entry = synth;
      }
      entry.bytes = kv.value;
    }

    // Note-level metadata (`note.note`): string table for pen-name
    // resolution plus the default page-template URI fallback.
    var stringTable = const <int, String>{};
    String? defaultTemplateUri;
    final noteBytes = entries['note.note'];
    if (noteBytes != null) {
      try {
        final meta = _parseNoteMetadata(noteBytes);
        stringTable = meta.stringTable;
        defaultTemplateUri = meta.templateUri;
      } catch (_) {
        // Fallback scan below still recovers pen names from raw bytes.
        final fallback = _scanPenStrings(noteBytes);
        if (fallback.isNotEmpty) stringTable = fallback;
      }
    }

    // Page order from pageIdInfo.dat, fallback to sorted .page names.
    List<String> orderedIds = [];
    final manifestBytes = entries['pageIdInfo.dat'];
    if (manifestBytes != null) {
      try {
        orderedIds = parsePageManifest(manifestBytes);
      } catch (_) {
        orderedIds = [];
      }
    }

    final pageEntries = entries.keys.where((k) => k.endsWith('.page')).toList()
      ..sort();
    // Map uuid -> entry name (filename stem should equal embedded uuid).
    final uuidToBytes = <String, Uint8List>{};
    final uuidToName = <String, String>{};
    for (final name in pageEntries) {
      final bytes = entries[name]!;
      try {
        final uuid = peekPageUuid(bytes);
        uuidToBytes[uuid] = bytes;
        uuidToName[uuid] = name;
      } catch (_) {
        // Fall back to filename stem.
        final stem = name.split('/').last.replaceAll('.page', '');
        uuidToBytes[stem] = bytes;
        uuidToName[stem] = name;
      }
    }

    final orderedPages = <SdocxPage>[];
    if (orderedIds.isNotEmpty) {
      for (final id in orderedIds) {
        final bytes = uuidToBytes[id];
        if (bytes == null) continue; // missing entry -> skip (Rust warns)
        try {
          orderedPages.add(parsePage(bytes, stringTable: stringTable));
        } catch (_) {
          // Corrupt page -> skip rather than failing whole import.
          continue;
        }
      }
      // Unlisted pages go last (same as Rust `order_page_records`).
      for (final kv in uuidToBytes.entries) {
        if (orderedIds.contains(kv.key)) continue;
        try {
          orderedPages.add(parsePage(kv.value, stringTable: stringTable));
        } catch (_) {
          continue;
        }
      }
    } else {
      for (final name in pageEntries) {
        try {
          orderedPages.add(parsePage(entries[name]!, stringTable: stringTable));
        } catch (_) {
          continue;
        }
      }
    }

    return SdocxDocument(
      pages: orderedPages,
      mediaByBindId: mediaByBindId,
      mediaByFileName: mediaByFileName,
      stringTable: stringTable,
      defaultTemplateUri: defaultTemplateUri,
    );
  }

  static int? _mediaArchiveId(String name) {
    final base = name.split('/').last;
    final prefix = base.split('@').first;
    return int.tryParse(prefix);
  }

  // ------------------------------------------------------------------
  // media/mediaInfo.dat (modern, format version > 3001)
  // ------------------------------------------------------------------

  static List<SdocxMediaEntry> parseMediaManifest(Uint8List data) {
    final r = SdocxReader(data);
    final formatVersion = r.readU32();
    if (formatVersion <= 3001) {
      throw FormatException('Legacy media manifest not supported');
    }
    final count = r.readU16();
    final out = <SdocxMediaEntry>[];
    for (var i = 0; i < count; i++) {
      final size = r.readU32();
      final recBytes = r.readBytes(size);
      final rec = SdocxReader(recBytes);
      final bindId = rec.readU32();
      final fileName = rec.readUtf16U16();
      // 2-byte hash prefix; 00 00 means no hash, otherwise 2 + 62 hex chars.
      if (rec.remaining < 2) {
        throw FormatException('Truncated media record hash prefix');
      }
      final prefix = rec.readBytes(2);
      if (!(prefix[0] == 0 && prefix[1] == 0)) {
        if (rec.remaining < 62) {
          throw FormatException('Truncated media record hash');
        }
        rec.skip(62);
      }
      if (rec.remaining < 2 + 8 + 1) {
        throw FormatException('Truncated media record tail');
      }
      rec.skip(2); // reference count u16
      rec.skip(8); // modified time i64
      rec.skip(1); // attached flag u8
      // trailing extension bytes are ignored (forward compatibility).
      out.add(SdocxMediaEntry(bindId: bindId, fileName: fileName));
    }
    // 4-byte EOFX marker.
    if (r.remaining < 4) {
      throw FormatException('Missing media manifest EOFX marker');
    }
    final marker = r.readBytes(4);
    if (!(marker[0] == 0x45 &&
        marker[1] == 0x4F &&
        marker[2] == 0x46 &&
        marker[3] == 0x58)) {
      throw FormatException('Invalid media manifest EOFX marker');
    }
    return out;
  }

  // ------------------------------------------------------------------
  // pageIdInfo.dat
  // ------------------------------------------------------------------

  static List<String> parsePageManifest(Uint8List data) {
    final r = SdocxReader(data);
    if (r.remaining < 32) {
      throw FormatException('Truncated page manifest header');
    }
    r.skip(32); // integrity header
    if (r.remaining < 2) return [];
    final count = r.readU16();
    final ids = <String>[];
    for (var i = 0; i < count; i++) {
      if (r.remaining < 2) break;
      String id;
      try {
        id = r.readUtf16U16();
      } catch (_) {
        break;
      }
      if (id.isNotEmpty) ids.add(id);
      if (r.remaining >= 32) {
        r.skip(32); // per-page integrity hash
      } else {
        break;
      }
    }
    return ids;
  }

  // ------------------------------------------------------------------
  // note.note flexible metadata: string table (bit 10) + default
  // page-template URI (bit 6). Mirrors Rust `NoteMetadataDecoder`
  // (bit order 0..fields.len()*8, stop at first unparsed field).
  // ------------------------------------------------------------------

  static _SdocxNoteMeta _parseNoteMetadata(Uint8List data) {
    final r = SdocxReader(data);
    final flexibleOffset = r.readU32();
    SdocxMask.read(r); // properties
    final fields = SdocxMask.read(r);
    r.skip(4); // format version
    r.readUtf16U16(); // note id (may be empty)
    r.skip(4 + 8 + 8 + 4 + 4 + 4 + 4 + 4); // rev, created, modified,
    // w, h, hPad, vPad, minVersion
    final titleSize = r.readU32();
    r.skip(titleSize);
    final bodySize = r.readU32();
    r.skip(bodySize);
    // Remaining fixed bytes up to flexibleOffset are trailing fixed data
    // (e.g. default page dimensions); the flexible block starts at the
    // recorded offset.
    final payloadEnd = data.length - 32; // 32-byte integrity trailer
    if (flexibleOffset < r.offset ||
        flexibleOffset > payloadEnd ||
        payloadEnd < 0) {
      throw FormatException('Note flexible data outside note payload');
    }
    final flex = SdocxReader(data.sublist(flexibleOffset, payloadEnd));

    final stringTable = <int, String>{};
    String? templateUri;
    for (var bit = 0; bit < fields.bytes.length * 8; bit++) {
      if (!fields.contains(bit)) continue;
      switch (bit) {
        case 0:
          flex.readUtf16U16(); // application name
        case 1:
          flex.skip(4 + 4); // version major/minor
          flex.readUtf16U16(); // patch name
        case 2:
          flex.readNullableUtf16U16(); // author name
          flex.readNullableUtf16U16(); // phone
          flex.readNullableUtf16U16(); // email
          flex.skip(4); // author image media id
        case 3:
          flex.skip(8 + 8); // lat/lon
        case 6:
          templateUri = flex.readUtf16U16();
        case 7:
          flex.skip(4); // last-edited page index
        case 9:
          flex.skip(4 + 8); // last-edited image media id + time
        case 10:
          final size = flex.readU32();
          final tableBytes = flex.readBytes(size);
          final tr = SdocxReader(tableBytes);
          final count = tr.readU16();
          for (var i = 0; i < count; i++) {
            final id = tr.readU32();
            final text = tr.readUtf16U16();
            stringTable[id] = text;
          }
        case 11:
          flex.skip(4); // body font size delta
        case 12:
          _skipNotePen(flex, modern: false);
        case 13:
          final count = flex.readU32();
          for (var i = 0; i < count; i++) {
            final recSize = flex.readU32();
            flex.skip(recSize);
          }
        case 14:
          final count = flex.readU16();
          for (var i = 0; i < count; i++) {
            flex.readUtf16U16(); // attachment name
            flex.skip(4); // media id
          }
        case 15:
          final size = flex.readU32();
          if (size < 4) {
            throw FormatException('Note pen block smaller than prefix');
          }
          flex.skip(size - 4);
        case 16:
          flex.skip(8); // server checkpoint
        case 17:
          flex.readUtf16U16(); // fixed font
        case 18:
          flex.skip(4); // fixed text direction
        case 19:
          flex.skip(4); // fixed background theme
        case 20:
          flex.readUtf16U16(); // text summarization
        case 21:
          flex.skip(4); // stroke group size
        case 22:
          flex.readUtf16U32(); // app custom data
        default:
          // Unknown extension field: same as Rust, stop here. A best-effort
          // pen-string scan below still recovers names for mapping.
          return _SdocxNoteMeta(stringTable, templateUri);
      }
    }
    return _SdocxNoteMeta(stringTable, templateUri);
  }

  static void _skipNotePen(SdocxReader flex, {required bool modern}) {
    flex.readUtf16U16(); // name
    flex.skip(4 + 4 + 4); // size, color, curvable
    flex.readUtf16U16(); // advanced setting
    flex.skip(4 + 4 + 4); // eraser, size level, particle density
    if (modern) flex.skip(4 + 4); // particle size, fixed width
    flex.skip(4 + 4 + 4 + 4); // hsv[3] + color UI info
  }

  /// Best-effort fallback: harvest `id -> pen-ish string` pairs straight
  /// from raw `note.note` bytes when the structured walk above stops early
  /// (unknown extension field) before reaching the string table.
  ///
  /// Only strings containing `pen.preload.` or exactly matching a known
  /// Samsung pen short name are collected, with small sane ids, so random
  /// binary cannot pollute the map.
  static Map<int, String> _scanPenStrings(Uint8List data) {
    const known = <String>{
      'DefaultPen',
      'AirBrushPen',
      'Beautify',
      'Brush',
      'BrushPen',
      'ChineseBrush',
      'Crayon',
      'Crayon2',
      'Eraser',
      'FadedPen',
      'FountainPen',
      'InkPen',
      'InkPen2',
      'MagicPen',
      'Marker',
      'Marker2',
      'Marker3',
      'Marker4',
      'MontblancCalligraphyPen',
      'MontblancFountainPen',
      'MosaicPen',
      'ObliquePen',
      'OilBrush3',
      'Pencil',
      'Pencil2',
      'Pencil3',
      'SelectPen',
      'SelectPen2',
      'Smudge',
      'ColoredPencil',
      'WaterColorBrush',
      'StraightHighlighter',
      'StraightMarker',
      'LaserPen',
      'GlowPen',
      'PatternImagePen',
      'StraightInkPen2',
      'StraightGlowPen',
      'BlurPen',
      'StraightMosaicPen',
      'StraightBlurPen',
      'MosaicPen2',
      'StraightMosaicPen2',
      'TapePen',
    };
    final out = <int, String>{};
    for (var i = 0; i + 6 < data.length; i++) {
      final id = data[i] |
          (data[i + 1] << 8) |
          (data[i + 2] << 16) |
          (data[i + 3] << 24);
      if (id < 0 || id > 10000) continue;
      final len = data[i + 4] | (data[i + 5] << 8);
      if (len < 2 || len > 120) continue;
      final end = i + 6 + len * 2;
      if (end > data.length) continue;
      var ok = true;
      final units = <int>[];
      for (var k = i + 6; k < end; k += 2) {
        final u = data[k] | (data[k + 1] << 8);
        if (u < 32 || u > 126) {
          ok = false;
          break;
        }
        units.add(u);
      }
      if (!ok) continue;
      final text = String.fromCharCodes(units);
      if (text.contains('pen.preload.') || known.contains(text)) {
        out.putIfAbsent(id, () => text);
      }
    }
    return out;
  }

  static String peekPageUuid(Uint8List data) {    final r = SdocxReader(data);
    final rawLayerOffset = r.readU32();
    final propertyOffset = r.readU32();
    final headerEnd = propertyOffset == 0 ? rawLayerOffset : propertyOffset;
    // Masks + orientation + dimensions + offsets, then UUID.
    SdocxMask.read(r); // properties
    SdocxMask.read(r); // fields
    r.skip(4 + 4 + 4 + 4 + 4); // orientation, w, h, ox, oy
    final uuid = r.readUtf16U16();
    if (headerEnd > data.length) {
      throw FormatException('Page header offsets outside page');
    }
    return uuid;
  }

  // ------------------------------------------------------------------
  // .page files
  // ------------------------------------------------------------------

  static SdocxPage parsePage(
    Uint8List data, {
    Map<int, String> stringTable = const {},
  }) {
    final r = SdocxReader(data);
    final rawLayerOffset = r.readU32();
    final propertyOffset = r.readU32();
    final headerEnd = (propertyOffset == 0 ? rawLayerOffset : propertyOffset)
        .toInt();
    if (headerEnd > rawLayerOffset || rawLayerOffset > data.length) {
      throw FormatException('Page header offsets outside page');
    }
    // Re-read header fields within headerEnd.
    final hr = SdocxReader(data.sublist(0, headerEnd), 8);
    SdocxMask.read(hr); // properties (text_only_flag legacy)
    final fieldsMask = SdocxMask.read(hr);
    final propertyMask = fieldsMask.lowU32;
    hr.skip(4); // orientation
    final width = hr.readU32().toDouble();
    final height = hr.readU32().toDouble();
    hr.skip(8); // offset_x, offset_y
    final uuid = hr.readUtf16U16();

    // Flexible page properties live between propertyOffset and rawLayerOffset.
    int? backgroundColorArgb;
    String? templateUri;
    int? templateType;
    int? backgroundImageId;
    int? backgroundImageMode;
    int? backgroundWidth;
    int? backgroundRotation;
    final pdfPapers = <SdocxPdfPaper>[];
    if (propertyOffset != 0) {
      final flexBytes = data.sublist(propertyOffset, rawLayerOffset.toInt());
      final flex = SdocxReader(flexBytes);
      // Bits 0..9 per Rust page.rs parse_page_properties.
      if ((propertyMask & (1 << 0)) != 0) {
        flex.skip(32); // content bbox (4 x f64)
      }
      if ((propertyMask & (1 << 1)) != 0) {
        final n = flex.readU16();
        for (var i = 0; i < n; i++) {
          flex.readUtf16U16();
        }
      }
      if ((propertyMask & (1 << 2)) != 0) {
        templateUri = flex.readUtf16U16();
      }
      if ((propertyMask & (1 << 3)) != 0) {
        backgroundImageId = flex.readU32();
      }
      if ((propertyMask & (1 << 4)) != 0) {
        backgroundImageMode = flex.readU32();
      }
      if ((propertyMask & (1 << 5)) != 0) {
        backgroundColorArgb = flex.readU32();
      }
      if ((propertyMask & (1 << 6)) != 0) {
        backgroundWidth = flex.readU32();
      }
      if ((propertyMask & (1 << 7)) != 0) {
        backgroundRotation = flex.readU32();
      }
      if ((propertyMask & (1 << 8)) != 0) {
        final n = flex.readU16();
        for (var i = 0; i < n; i++) {
          final mediaId = flex.readI32();
          final pageIndex = flex.readI32();
          final rectRaw = flex.readBytes(16);
          // Modern writers (>=2034) store integer rects; legacy stores
          // float bits. We interpret both as: left, top, right, bottom in
          // Samsung page pixels when they look like sane integers, else
          // fall back to full-page rect.
          Rect rect;
          try {
            final vals = [
              _leI32(rectRaw, 0),
              _leI32(rectRaw, 4),
              _leI32(rectRaw, 8),
              _leI32(rectRaw, 12),
            ];
            if (vals[2] > vals[0] &&
                vals[3] > vals[1] &&
                vals[2] <= width + 1 &&
                vals[3] <= height + 1) {
              rect = Rect.fromLTRB(
                vals[0].toDouble(),
                vals[1].toDouble(),
                vals[2].toDouble(),
                vals[3].toDouble(),
              );
            } else {
              rect = Rect.fromLTWH(0, 0, width, height);
            }
          } catch (_) {
            rect = Rect.fromLTWH(0, 0, width, height);
          }
          pdfPapers.add(
            SdocxPdfPaper(
              mediaId: mediaId,
              pageIndex: pageIndex,
              rect: rect,
            ),
          );
        }
      }
      if ((propertyMask & (1 << 9)) != 0) {
        templateType = flex.readU32();
      }
    }

    // Layers.
    final lr = SdocxReader(data, rawLayerOffset.toInt());
    final layerCount = lr.readU16();
    if (layerCount == 0) {
      throw FormatException('Page layer count is zero');
    }
    final currentLayer = lr.readU16();
    if (currentLayer >= layerCount) {
      throw FormatException('Current layer index out of range');
    }

    final allStrokes = <SdocxStroke>[];
    final allImages = <SdocxImage>[];
    for (var li = 0; li < layerCount; li++) {
      final layer = _parseLayer(lr, data, stringTable: stringTable);
      // Import every layer (Rust renders only the current one, but hidden
      // layers may still hold user content in older notes; importing all
      // is the lossless choice for a note-taking app).
      allStrokes.addAll(layer.strokes);
      allImages.addAll(layer.images);
    }

    return SdocxPage(
      uuid: uuid,
      width: width,
      height: height,
      backgroundColorArgb: backgroundColorArgb,
      pdfPapers: pdfPapers,
      strokes: allStrokes,
      images: allImages,
      templateUri: templateUri,
      templateType: templateType,
      backgroundImageId: backgroundImageId,
      backgroundImageMode: backgroundImageMode,
      backgroundWidth: backgroundWidth,
      backgroundRotation: backgroundRotation,
    );
  }

  static int _leI32(Uint8List b, int off) {
    final v = b[off] | (b[off + 1] << 8) | (b[off + 2] << 16) | (b[off + 3] << 24);
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }

  static _SdocxLayer _parseLayer(
    SdocxReader lr,
    Uint8List pageBytes, {
    Map<int, String> stringTable = const {},
  }) {
    final headerSize = lr.readU32();
    if (headerSize < 14 || headerSize > 16 * 1024) {
      throw FormatException('Invalid layer header size $headerSize');
    }
    // headerSize includes its own 4-byte size field.
    lr.skip(headerSize - 4);
    final objectCount = lr.readU32();
    final strokes = <SdocxStroke>[];
    final images = <SdocxImage>[];
    for (var i = 0; i < objectCount; i++) {
      _parseObject(lr, pageBytes, 0, strokes, images,
          stringTable: stringTable);
    }
    if (lr.remaining < 32) {
      throw FormatException('Truncated layer integrity trailer');
    }
    lr.skip(32);
    return _SdocxLayer(strokes, images);
  }

  /// Recursive object walk. Supported payloads append to [strokes]/[images];
  /// everything else (audio/voice type 10, video 16, tables 22, stickers via
  /// nested .sdocx, shapes, text, …) is skipped but children of containers
  /// (type 4) and stroke groups (type 100) are still traversed.
  static void _parseObject(
    SdocxReader lr,
    Uint8List pageBytes,
    int depth,
    List<SdocxStroke> strokes,
    List<SdocxImage> images, {
    Map<int, String> stringTable = const {},
  }) {
    if (depth >= 64) {
      throw FormatException('Object nesting too deep');
    }
    if (lr.remaining < 7) {
      throw FormatException('Truncated object header');
    }
    final type = lr.readU8();
    final childCount = lr.readU16();
    final declaredSize = lr.readU32();
    if (declaredSize < 32) {
      throw FormatException('Object size smaller than trailer');
    }
    final payloadSize = declaredSize - 32;
    if (lr.remaining < payloadSize + 32) {
      throw FormatException('Object payload outside page');
    }
    final payloadOffset = lr.offset;
    Uint8List? payload;
    try {
      payload = lr.readBytes(payloadSize);
    } catch (_) {
      throw FormatException('Object payload outside page');
    }
    lr.skip(32); // integrity trailer
    assert(payloadOffset >= 0);

    // Decode supported leaf types. Failures are non-fatal: skip the object.
    try {
      if (type == 1) {
        final s = decodeStroke(payload, stringTable: stringTable);
        if (s != null) strokes.add(s);
      } else if (type == 3) {
        final img = decodeImage(payload);
        if (img != null) images.add(img);
      }
      // All other types are discarded per requirements (audio, tables,
      // stickers, shapes, text, …). Containers fall through to child walk.
    } catch (_) {
      // Skip corrupt objects.
    }

    for (var c = 0; c < childCount; c++) {
      _parseObject(lr, pageBytes, depth + 1, strokes, images,
          stringTable: stringTable);
    }
  }

  // ------------------------------------------------------------------
  // Frames + ObjectMetadata (kinds 0/1/6/7/3)
  // ------------------------------------------------------------------

  static _SdocxFrame _readFrame(SdocxReader r) {
    final size = r.readU32();
    if (size < 12) throw FormatException('Invalid frame size $size');
    final start = r.offset;
    // size includes its own 4-byte size field; we already consumed it.
    final end = start - 4 + size;
    if (end > r.data.length) {
      throw FormatException('Frame outside payload');
    }
    final kind = r.readI16();
    final flexOffset = r.readU32();
    final properties = SdocxMask.read(r);
    final fields = SdocxMask.read(r);
    final headerEnd = r.offset;
    int fixedEnd;
    if (flexOffset == 0 && fields.isEmpty) {
      fixedEnd = end;
    } else {
      fixedEnd = (start - 4 + flexOffset.toInt()).toInt();
      if (fixedEnd < headerEnd + 4 || fixedEnd > end) {
        throw FormatException('Frame flexible offset outside frame');
      }
    }
    final fixed = r.data.sublist(headerEnd, fixedEnd);
    final flexible = r.data.sublist(fixedEnd, end);
    r.seek(end);
    return _SdocxFrame(kind, properties, fields, fixed, flexible);
  }

  static _SdocxObjectMeta? _readObjectMeta(Uint8List payload) {
    try {
      final r = SdocxReader(payload);
      final frame = _readFrame(r);
      if (frame.kind != 0) return null;
      final fixed = SdocxReader(frame.fixed);
      fixed.skip(4); // format version
      final uuid = fixed.readUtf8U16();
      fixed.skip(8); // modified time
      final left = fixed.readF64();
      final top = fixed.readF64();
      final right = fixed.readF64();
      final bottom = fixed.readF64();
      if (!left.isFinite || !top.isFinite || !right.isFinite || !bottom.isFinite) {
        return null;
      }
      fixed.skip(4 + 1); // replay timestamp + resize mode
      final visible = frame.properties.contains(3);
      double? rotation;
      if (frame.fields.contains(0)) {
        final flex = SdocxReader(frame.flexible);
        rotation = flex.readF32();
        if (!rotation.isFinite) return null;
      }
      return _SdocxObjectMeta(
        uuid: uuid,
        bbox: Rect.fromLTRB(left, top, right, bottom),
        visible: visible,
        rotationDegrees: rotation,
      );
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------
  // Strokes (type 1): modern compressed frame format.
  // ------------------------------------------------------------------

  static double _signedDelta(int raw, double divisor) {
    final mag = (raw & 0x7FFF) / divisor;
    return (raw & 0x8000) == 0 ? mag : -mag;
  }

  static SdocxStroke? decodeStroke(
    Uint8List payload, {
    Map<int, String> stringTable = const {},
  }) {
    final meta = _readObjectMeta(payload);
    if (meta == null || !meta.visible) return null;

    final r = SdocxReader(payload);
    // Skip base frame (kind 0) to reach stroke frame (kind 1).
    _readFrame(r);
    if (r.isEof) return null;
    final frame = _readFrame(r);
    if (frame.kind != 1) return null;

    // Samsung eraser marks are not ink: dropping them keeps erased content
    // erased instead of resurrecting it on import.
    if (frame.properties.contains(3)) return null;

    final fixed = SdocxReader(frame.fixed);
    if (fixed.remaining < 2) return null;
    final pointCount = fixed.readU16();
    if (pointCount == 0 || pointCount > 65535) return null;

    final compressed = frame.properties.contains(0);
    final stylus = frame.properties.contains(2);

    int channelBytes;
    if (pointCount == 0) {
      channelBytes = 0;
    } else if (compressed) {
      channelBytes =
          16 + (pointCount - 1) * 4 + (2 + (stylus ? 2 : 0)) * (4 + (pointCount - 1) * 2);
    } else {
      channelBytes = pointCount * (24 + (stylus ? 8 : 0));
    }
    if (fixed.remaining != channelBytes + 2) return null;
    final channelData = fixed.readBytes(channelBytes);
    final toolTypeRaw = fixed.readU16();

    final cd = SdocxReader(channelData);
    final points = <SdocxPoint>[];
    final pressures = <double>[];
    if (compressed) {
      var x = cd.readF64();
      var y = cd.readF64();
      if (!x.isFinite || !y.isFinite) return null;
      points.add(SdocxPoint(x, y));
      for (var i = 1; i < pointCount; i++) {
        final dxRaw = cd.readU16();
        final dyRaw = cd.readU16();
        x += _signedDelta(dxRaw, 32.0);
        y += _signedDelta(dyRaw, 32.0);
        if (!x.isFinite || !y.isFinite) return null;
        points.add(SdocxPoint(x, y));
      }
    } else {
      for (var i = 0; i < pointCount; i++) {
        final x = cd.readF64();
        final y = cd.readF64();
        if (!x.isFinite || !y.isFinite) return null;
        points.add(SdocxPoint(x, y));
      }
    }
    // Pressure channel: first f32 + /4096 deltas when compressed.
    if (pointCount > 0) {
      var p = cd.readF32();
      if (!p.isFinite) return null;
      pressures.add(_clamp01(p));
      for (var i = 1; i < pointCount; i++) {
        if (compressed) {
          final raw = cd.readU16();
          p += _signedDelta(raw, 4096.0);
        } else {
          p = cd.readF32();
        }
        if (!p.isFinite) return null;
        pressures.add(_clamp01(p));
      }
    }
    // Remaining channels (timestamps, tilts) are intentionally ignored:
    // Saber stores per-point pressure only.

    // Style (color + width + pen ids) from flexible fields.
    int? colorArgb;
    double penWidth = 4.5;
    int? penNameId;
    int? advancedSettingId;
    int? legacyPenNameId;
    try {
      final style = _readStrokeStyle(frame);
      colorArgb = style.colorArgb;
      if (style.penSize != null &&
          style.penSize!.isFinite &&
          style.penSize! > 0 &&
          style.penSize! < 200) {
        penWidth = style.penSize!;
      }
      penNameId = style.penNameId;
      advancedSettingId = style.advancedPenSettingId;
      legacyPenNameId = style.legacyPenNameId;
    } catch (_) {
      // Keep defaults.
    }

    if (points.length < 2) return null;
    return SdocxStroke(
      points: points,
      pressures: pressures,
      colorArgb: colorArgb,
      penWidth: penWidth,
      bbox: meta.bbox,
      penName: resolvePenName(
        stringTable,
        penNameId: penNameId,
        legacyPenNameId: legacyPenNameId,
      ),
      penNameId: penNameId ?? legacyPenNameId,
      advancedSettingId: advancedSettingId,
      toolTypeRaw: toolTypeRaw,
    );
  }

  /// Resolve a stroke's Samsung pen name via the `note.note` string table.
  /// Prefers the modern `pen_name_id` (unless -1), falls back to the legacy
  /// id, and strips the `…pen.preload.` package prefix (`InkPen2`,
  /// `FountainPen`, `Marker4`, …). Returns null when unresolvable.
  static String? resolvePenName(
    Map<int, String> stringTable, {
    int? penNameId,
    int? legacyPenNameId,
  }) {
    int? useId;
    if (penNameId != null && penNameId != -1) {
      useId = penNameId;
    } else {
      useId = legacyPenNameId;
    }
    if (useId == null || useId < 0) return null;
    final full = stringTable[useId];
    if (full == null || full.isEmpty) return null;
    const prefix = 'com.samsung.android.sdk.pen.pen.preload.';
    if (full.startsWith(prefix)) return full.substring(prefix.length);
    if (full.contains('.')) return full.split('.').last;
    return full;
  }

  static double _clamp01(double v) => v.isNaN
      ? 0.5
      : v < 0
          ? 0
          : v > 1
              ? 1
              : v;

  static _SdocxStrokeStyle _readStrokeStyle(_SdocxFrame frame) {
    int? colorArgb;
    double? penSize;
    int? legacyPenNameId;
    int? advancedPenSettingId;
    int? penNameId;
    final flex = SdocxReader(frame.flexible);
    if (frame.fields.contains(0)) {
      legacyPenNameId = flex.readI32();
    }
    if (frame.fields.contains(1)) {
      advancedPenSettingId = flex.readI32();
    }
    if (frame.fields.contains(2)) {
      colorArgb = flex.readU32();
    }
    if (frame.fields.contains(3)) {
      penSize = flex.readF32();
    }
    if (frame.fields.contains(4)) {
      flex.skip(1); // field_4_raw u8
    }
    // Bit 5 (legacy partial-rectangle data) is variable-length and needs the
    // base frame to size; when present the offsets of bit-7+ fields cannot be
    // located reliably, so penNameId is left unresolved (the legacy id above
    // still applies as fallback).
    if (!frame.fields.contains(5) && frame.fields.contains(7)) {
      penNameId = flex.readI32();
    }
    return _SdocxStrokeStyle(
      colorArgb,
      penSize,
      legacyPenNameId: legacyPenNameId,
      advancedPenSettingId: advancedPenSettingId,
      penNameId: penNameId,
    );
  }

  // ------------------------------------------------------------------
  // Images (type 3): bbox from base frame + media id from shape fill.
  // ------------------------------------------------------------------

  static SdocxImage? decodeImage(Uint8List payload) {
    final meta = _readObjectMeta(payload);
    if (meta == null || !meta.visible) return null;

    final r = SdocxReader(payload);
    _readFrame(r); // kind 0 base
    if (r.isEof) return null;
    final shapeBase = _readFrame(r);
    if (shapeBase.kind != 6) return null;
    if (r.isEof) return null;
    final shape = _readFrame(r);
    if (shape.kind != 7) return null;
    // Tail frame (kind 3) follows but carries only crop/border settings
    // that the basic importer ignores.

    // Shape fixed: type u32, bbox 4xf64, rotation f32, path, control points.
    int? mediaId;
    try {
      final flex = SdocxReader(shape.flexible);
      if (!shape.fields.contains(5)) return null;
      // Bit 5: fill (size u32 + kind u8 + fill payload).
      // Bits 0-4 may precede it; this file's images only set bit 5, but
      // handle the general prefix for robustness.
      if (shape.fields.contains(0)) {
        final n = flex.readU32();
        flex.skip(n);
      }
      if (shape.fields.contains(1)) {
        flex.skip(1);
      }
      if (shape.fields.contains(2)) {
        flex.skip(4);
      }
      if (shape.fields.contains(3)) {
        // Unknown field before fill: cannot reliably locate media id.
        return SdocxImage(bbox: meta.bbox, mediaId: null);
      }
      if (shape.fields.contains(4)) {
        flex.skip(4);
      }
      final fillSize = flex.readU32();
      final fillKind = flex.readU8();
      if (fillKind != 2) return SdocxImage(bbox: meta.bbox, mediaId: null);
      if (fillSize > flex.remaining + 1) {
        return SdocxImage(bbox: meta.bbox, mediaId: null);
      }
      final fill = SdocxReader(flex.readBytes(fillSize));
      fill.skip(1); // fill mode (0 = stretch)
      final rawId = fill.readI32();
      mediaId = rawId >= 0 ? rawId : null;
    } catch (_) {
      mediaId = null;
    }

    return SdocxImage(
      bbox: meta.bbox,
      mediaId: mediaId,
      rotationDegrees: meta.rotationDegrees,
    );
  }
}

class _SdocxLayer {
  _SdocxLayer(this.strokes, this.images);

  final List<SdocxStroke> strokes;
  final List<SdocxImage> images;
}

class _SdocxFrame {
  _SdocxFrame(this.kind, this.properties, this.fields, this.fixed, this.flexible);

  final int kind;
  final SdocxMask properties;
  final SdocxMask fields;
  final Uint8List fixed;
  final Uint8List flexible;
}

class _SdocxObjectMeta {
  _SdocxObjectMeta({
    required this.uuid,
    required this.bbox,
    required this.visible,
    this.rotationDegrees,
  });

  final String uuid;
  final Rect bbox;
  final bool visible;
  final double? rotationDegrees;
}

class _SdocxStrokeStyle {
  _SdocxStrokeStyle(
    this.colorArgb,
    this.penSize, {
    this.legacyPenNameId,
    this.advancedPenSettingId,
    this.penNameId,
  });

  final int? colorArgb;
  final double? penSize;
  final int? legacyPenNameId;
  final int? advancedPenSettingId;
  final int? penNameId;
}

class _SdocxNoteMeta {
  _SdocxNoteMeta(this.stringTable, this.templateUri);

  final Map<int, String> stringTable;
  final String? templateUri;
}
