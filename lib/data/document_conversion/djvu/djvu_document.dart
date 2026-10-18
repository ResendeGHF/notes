// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// DjVu document model: single-page `FORM:DJVU`, legacy `FORM:BM44`/`PM44`
// photo pages, bundled `FORM:DJVM` catalogs (DIRM offset table) and indirect
// catalogs whose components are resolved by name.
//
// Ported from djvu-rs (`src/djvu_document/{parse,document,assembly}.rs`, MIT,
// https://github.com/matyushkin/djvu-rs) with the same assembly semantics:
//
// - bundled catalogs index their `FORM` children positionally, in DIRM order;
// - shared components are indexed by their `Djbz` dictionary, and a page's
//   first `INCL` target that names one of them is its dictionary;
// - a page whose `INCL` names a shared component that appears later in DIRM is
//   built after the catalog has been indexed (writers put shared components
//   first, so this is rare);
// - a shared component that cannot be supplied or parsed is skipped; pages
//   that need its dictionary fail when their mask is decoded;
// - the data is kept zero-copy: pages hold sub-list views of the input bytes.
//
// The page-level decode accessors (mask, background, foreground, links) are
// shared by the DjVu → PDF converter and mirror the reference page API.

import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:saber/data/document_conversion/djvu/djvu_annotations.dart';
import 'package:saber/data/document_conversion/djvu/djvu_bitmap.dart';
import 'package:saber/data/document_conversion/djvu/djvu_bzz.dart';
import 'package:saber/data/document_conversion/djvu/djvu_iff.dart';
import 'package:saber/data/document_conversion/djvu/djvu_iw44.dart';
import 'package:saber/data/document_conversion/djvu/djvu_jb2.dart';
import 'package:saber/data/document_conversion/djvu/djvu_navm.dart';

/// Thrown when a DjVu file cannot be opened as a document.
class DjvuDocumentException implements Exception {
  const DjvuDocumentException(this.message);

  /// Human-readable failure description.
  final String message;

  @override
  String toString() => 'DjvuDocumentException: $message';
}

/// Resolves an indirect (`DIRM`-referenced) DJVM component by name.
///
/// Returns the component file's bytes, or null when the component cannot be
/// supplied. Missing pages fail the open; missing shared components are
/// skipped (their dictionaries are optional until a mask needs them).
typedef DjvuComponentResolver = Uint8List? Function(String name);

/// A `FORM:DJVI` shared JB2 symbol dictionary (`Djbz`).
///
/// All pages whose `INCL` chunk names the component share one instance, and
/// the raw bytes are decoded at most once: a bundled scan with many pages over
/// one or two dictionaries pays one ZP arithmetic decode per dictionary
/// instead of one per page. A failed decode is cached as null, mirroring the
/// reference's `OnceLock<Option<Jb2Dict>>`.
class DjvuSharedDict {
  DjvuSharedDict(this.data);

  /// Raw `Djbz` payload of the shared component.
  final Uint8List data;

  Jb2Dict? _decoded;
  var _decodeAttempted = false;

  /// The decoded dictionary, or null when the bytes are not a valid stream.
  Jb2Dict? get decoded {
    if (!_decodeAttempted) {
      _decodeAttempted = true;
      try {
        _decoded = jb2DecodeDict(data);
      } on Jb2Exception {
        _decoded = null;
      }
    }
    return _decoded;
  }
}

/// An opened DjVu document.
class DjvuDocument {
  DjvuDocument._(this.pages, this.bookmarks, this.globalChunks);

  /// Parses a DjVu [data] buffer.
  ///
  /// [resolver] is required for indirect `FORM:DJVM` catalogs (component files
  /// referenced by name); bundled documents and single-page files never call
  /// it.
  ///
  /// Throws [DjvuFormatException] for a malformed container and
  /// [DjvuDocumentException] for a well-formed container that is not a
  /// supported document (a missing DIRM, an unresolvable page component, a
  /// non-DjVu form type).
  static DjvuDocument parse(
    Uint8List data, {
    DjvuComponentResolver? resolver,
  }) {
    final form = parseIffFile(data);
    switch (form.formType) {
      case 'DJVU':
        return DjvuDocument._(
          [_pageFromChunks(form.chunks, 0, null)],
          const [],
          form.chunks,
        );
      case 'BM44':
      case 'PM44':
        return DjvuDocument._(
          [_legacyIw44Page(form.formType, form.chunks, 0)],
          const [],
          const [],
        );
      case 'DJVM':
        return _parseDjvm(form, resolver);
      default:
        throw DjvuDocumentException(
          'FORM:${form.formType} is not a DjVu document',
        );
    }
  }

  /// Pages in document order.
  final List<DjvuPage> pages;

  /// The NAVM table of contents; empty when the chunk is absent, malformed or
  /// too deeply nested.
  ///
  /// The reference fails the whole open on a malformed NAVM; degrading to "no
  /// bookmarks" is friendlier for an import pipeline and cannot lose page
  /// data.
  final List<DjvuBookmark> bookmarks;

  /// Document-level chunks: every top-level chunk of a single-page
  /// `FORM:DJVU`, or the non-`FORM` chunks (`DIRM`, `NAVM`, …) of a
  /// `FORM:DJVM`.
  final List<IffChunk> globalChunks;

  /// Number of pages.
  int get pageCount => pages.length;

  /// The page at [index].
  DjvuPage page(int index) {
    if (index < 0 || index >= pages.length) {
      throw RangeError.index(index, pages, 'index');
    }
    return pages[index];
  }

  // -------------------------------------------------------------------------
  // DJVM assembly
  // -------------------------------------------------------------------------

  static DjvuDocument _parseDjvm(IffForm form, DjvuComponentResolver? resolver) {
    final dirm = form.find('DIRM');
    if (dirm == null) {
      throw const DjvuDocumentException('FORM:DJVM has no DIRM chunk');
    }
    final payload = parseDirmPayload(dirm.data);
    final entries = payload.components(bzzDecode);
    final bookmarks = _tryParseBookmarks(form.chunks);
    final globalChunks = [
      for (final chunk in form.chunks)
        if (chunk.id != 'FORM') chunk,
    ];

    if (payload.isBundled) {
      // Bundled: the FORM children follow DIRM positionally.
      final subForms = [
        for (final chunk in form.chunks)
          if (chunk.id == 'FORM') chunk,
      ];
      return _assembleCatalog(
        entries: entries,
        bookmarks: bookmarks,
        globalChunks: globalChunks,
        fetch: (index, entry) {
          if (index >= subForms.length) return null;
          return _ComponentBody(subForms[index].data);
        },
      );
    }

    final resolve = resolver;
    if (resolve == null) {
      throw const DjvuDocumentException(
        'indirect FORM:DJVM requires a component resolver',
      );
    }
    return _assembleCatalog(
      entries: entries,
      bookmarks: bookmarks,
      globalChunks: globalChunks,
      fetch: (index, entry) {
        switch (entry.kind) {
          case DirmKind.page:
            final bytes = resolve(entry.id);
            if (bytes == null) {
              throw DjvuDocumentException(
                'cannot resolve page component "${entry.id}"',
              );
            }
            return _ComponentFile(bytes);
          case DirmKind.shared:
          case DirmKind.sharedAnnotation:
            final bytes = resolve(entry.id);
            return bytes == null ? null : _ComponentFile(bytes);
          case DirmKind.thumbnail:
            return null;
        }
      },
    );
  }

  /// Builds the pages of a DIRM catalog from [fetch].
  ///
  /// [fetch] supplies component [index] (or null when unavailable): sub-form
  /// bodies for bundled catalogs, whole component files for indirect ones.
  /// It may throw to fail the open (an unresolvable indirect page).
  static DjvuDocument _assembleCatalog({
    required List<DirmComponent> entries,
    required List<DjvuBookmark> bookmarks,
    required List<IffChunk> globalChunks,
    required _Component? Function(int index, DirmComponent entry) fetch,
  }) {
    // DIRM position of every shared component, to tell whether a page's INCL
    // target is still ahead in the catalog.
    final includePos = <String, int>{};
    for (var i = 0; i < entries.length; i++) {
      final kind = entries[i].kind;
      if (kind == DirmKind.shared || kind == DirmKind.sharedAnnotation) {
        includePos[entries[i].id] = i;
      }
    }

    final dicts = <String, DjvuSharedDict>{};
    final pages = <DjvuPage?>[];
    // Pages whose INCL names a shared component later in DIRM wait until the
    // whole catalog is indexed. Writers put shared components first, so this
    // is empty for real documents and pages are built as they stream by.
    final deferred = <(int, IffForm)>[];

    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final component = fetch(index, entry);
      switch (entry.kind) {
        case DirmKind.page:
          if (component == null) {
            throw const DjvuDocumentException(
              'DIRM lists more components than the document holds',
            );
          }
          // A page component must parse; a corrupt one fails the open.
          final pageForm = component.parse();
          final pageIndex = pages.length;
          final waits = _inclTargets(pageForm.chunks).any((name) {
            final pos = includePos[name];
            return pos != null && pos > index;
          });
          if (waits) {
            pages.add(null);
            deferred.add((pageIndex, pageForm));
          } else {
            pages.add(_buildPage(pageIndex, pageForm, dicts));
          }
        case DirmKind.shared:
        case DirmKind.sharedAnnotation:
          // Shared components are optional: skip unparseable or absent ones.
          final sharedForm = component?.tryParse();
          if (sharedForm == null) continue;
          final djbz = sharedForm.find('Djbz');
          if (djbz != null) {
            dicts[entry.id] = DjvuSharedDict(djbz.data);
          }
        case DirmKind.thumbnail:
          continue;
      }
    }

    for (final (pageIndex, pageForm) in deferred) {
      pages[pageIndex] = _buildPage(pageIndex, pageForm, dicts);
    }

    return DjvuDocument._(
      [for (final page in pages) page!],
      bookmarks,
      globalChunks,
    );
  }

  /// Builds page [index] from its parsed component form, attaching the first
  /// `INCL`-named dictionary it needs.
  static DjvuPage _buildPage(
    int index,
    IffForm form,
    Map<String, DjvuSharedDict> dicts,
  ) {
    switch (form.formType) {
      case 'BM44':
      case 'PM44':
        return _legacyIw44Page(form.formType, form.chunks, index);
    }
    DjvuSharedDict? shared;
    for (final name in _inclTargets(form.chunks)) {
      final dict = dicts[name];
      if (dict != null) {
        shared = dict;
        break;
      }
    }
    return _pageFromChunks(form.chunks, index, shared);
  }

  /// Builds a `FORM:DJVU` page from its chunk list.
  static DjvuPage _pageFromChunks(
    List<IffChunk> chunks,
    int index,
    DjvuSharedDict? sharedDict,
  ) {
    IffChunk? infoChunk;
    for (final chunk in chunks) {
      if (chunk.id == 'INFO') {
        infoChunk = chunk;
        break;
      }
    }
    if (infoChunk == null) {
      throw const DjvuDocumentException('page has no INFO chunk');
    }
    return DjvuPage._(
      index: index,
      formType: 'DJVU',
      info: parseDjvuPageInfo(infoChunk.data),
      chunks: chunks,
      sharedDict: sharedDict,
    );
  }

  /// Builds a legacy `FORM:BM44` (grayscale) / `FORM:PM44` (colour) page.
  ///
  /// These carry a bare IW44 bitstream and no INFO chunk; DjVuLibre reports
  /// 100 dpi for them.
  static DjvuPage _legacyIw44Page(
    String formType,
    List<IffChunk> chunks,
    int index,
  ) {
    if (chunks.isEmpty) {
      throw DjvuDocumentException('$formType page has no image chunks');
    }
    for (final chunk in chunks) {
      if (chunk.id != formType) {
        throw const DjvuDocumentException(
          'legacy IW44 form contains an unexpected chunk',
        );
      }
    }
    return DjvuPage._(
      index: index,
      formType: formType,
      info: _legacyIw44PageInfo(formType, chunks.first.data),
      chunks: chunks,
      sharedDict: null,
    );
  }

  /// Synthesizes [DjvuPageInfo] from a legacy IW44 first chunk header.
  static DjvuPageInfo _legacyIw44PageInfo(
    String formType,
    Uint8List payload,
  ) {
    if (payload.length < 9) {
      throw const DjvuDocumentException(
        'legacy IW44 first chunk header is truncated',
      );
    }
    if (payload[0] != 0) {
      throw const DjvuDocumentException(
        'legacy IW44 first chunk must have serial 0',
      );
    }
    final isGrayscale = (payload[2] & 0x80) != 0;
    if (formType == 'BM44' && !isGrayscale) {
      throw const DjvuDocumentException(
        'FORM:BM44 requires a grayscale IW44 bitstream',
      );
    }
    if (formType == 'PM44' && isGrayscale) {
      throw const DjvuDocumentException(
        'FORM:PM44 requires a colour IW44 bitstream',
      );
    }
    final width = (payload[4] << 8) | payload[5];
    final height = (payload[6] << 8) | payload[7];
    if (width == 0 || height == 0) {
      throw const DjvuDocumentException('legacy IW44 image has zero dimension');
    }
    if (width * height > 64 * 1024 * 1024) {
      throw const DjvuDocumentException('legacy IW44 image is too large');
    }
    return DjvuPageInfo(
      width: width,
      height: height,
      dpi: 100,
      gamma: 2.2,
      rotation: DjvuRotation.none,
    );
  }

  /// Parses the NAVM chunk of [chunks], tolerating a malformed one.
  static List<DjvuBookmark> _tryParseBookmarks(List<IffChunk> chunks) {
    for (final chunk in chunks) {
      if (chunk.id != 'NAVM') continue;
      try {
        return parseNavmBookmarks(chunk.data);
      } on BzzException {
        return const [];
      } on DjvuFormatException {
        return const [];
      }
    }
    return const [];
  }

  /// The `INCL` target names of a component, in chunk order.
  static Iterable<String> _inclTargets(List<IffChunk> chunks) sync* {
    for (final chunk in chunks) {
      if (chunk.id != 'INCL') continue;
      final target = inclTarget(chunk.data);
      if (target != null) yield target;
    }
  }
}

/// One page of a DjVu document: its metadata and raw chunk views.
class DjvuPage {
  DjvuPage._({
    required this.index,
    required this.formType,
    required this.info,
    required this.chunks,
    required this.sharedDict,
  });

  /// 0-based page index within the document.
  final int index;

  /// The page FORM's secondary type: `DJVU`, `BM44` or `PM44`.
  final String formType;

  /// Metadata from the INFO chunk (synthesized for legacy pages).
  final DjvuPageInfo info;

  /// The page's chunks, in file order (zero-copy views into the document
  /// bytes).
  final List<IffChunk> chunks;

  /// The shared `Djbz` dictionary this page `INCL`s, if any.
  final DjvuSharedDict? sharedDict;

  /// Page width in pixels.
  int get width => info.width;

  /// Page height in pixels.
  int get height => info.height;

  /// Resolution in dots per inch, never below 1.
  int get dpi {
    final value = info.dpi;
    return value < 1 ? 1 : value;
  }

  /// Page rotation from INFO.
  DjvuRotation get rotation => info.rotation;

  /// The first chunk with [id], or null.
  IffChunk? findChunk(String id) {
    for (final chunk in chunks) {
      if (chunk.id == id) return chunk;
    }
    return null;
  }

  /// All chunks with [id], in order.
  List<IffChunk> findChunks(String id) {
    final out = <IffChunk>[];
    for (final chunk in chunks) {
      if (chunk.id == id) out.add(chunk);
    }
    return out;
  }

  /// The payload of the first chunk with [id], or null.
  Uint8List? rawChunk(String id) => findChunk(id)?.data;

  /// Decodes a paired `*z` (BZZ-compressed) / `*a` (plain) payload, preferring
  /// the compressed chunk; a present-but-empty chunk means "no payload".
  ///
  /// Throws [BzzException] when the `*z` chunk is not a valid BZZ stream.
  Uint8List? chunkPayload(String idZ, String idA) {
    final z = rawChunk(idZ);
    if (z != null) return z.isEmpty ? null : bzzDecode(z);
    final a = rawChunk(idA);
    if (a != null) return a.isEmpty ? null : a;
    return null;
  }

  /// IW44 background chunks: `BG44`, or the legacy `BM44`/`PM44` chunk ids.
  List<Uint8List> bg44Chunks() {
    final bg44 = findChunks('BG44');
    if (bg44.isNotEmpty) return [for (final c in bg44) c.data];
    final bm44 = findChunks('BM44');
    if (bm44.isNotEmpty) return [for (final c in bm44) c.data];
    return [for (final c in findChunks('PM44')) c.data];
  }

  /// IW44 continuous-tone foreground chunks (`FG44`), in order.
  List<Uint8List> fg44Chunks() => [for (final c in findChunks('FG44')) c.data];

  /// The page's hyperlinks: annotation map areas with a non-empty URL.
  ///
  /// Throws [BzzException]/[DjvuFormatException] when the ANTz/ANTa chunk is
  /// malformed; callers that want graceful degradation should catch.
  List<DjvuMapArea> hyperlinks() {
    final payload = chunkPayload('ANTz', 'ANTa');
    if (payload == null) return const [];
    final (_, areas) = parseDjvuAnnotations(payload);
    return [
      for (final area in areas)
        if (area.url.isNotEmpty) area,
    ];
  }

  /// Decodes the JB2 foreground mask (`Sjbz`) to a packed 1-bit bitmap.
  ///
  /// Returns null when the page has no JB2 mask. G4/MMR (`Smmr`) masks are not
  /// supported and count as "no mask".
  ///
  /// Throws [Jb2Exception] when the stream is malformed or a referenced shared
  /// dictionary is unavailable; callers that want to render gracefully (like
  /// the reference converter) should catch that and treat it as "no mask".
  DjvuBitmap? decodeMask() {
    final sjbz = rawChunk('Sjbz');
    if (sjbz == null) return null;
    return jb2Decode(sjbz, sharedDict: _dictionary());
  }

  /// Like [decodeMask], but also returns the per-pixel blit record index map
  /// (`-1` for background pixels) that `FGbz` pages index their palette with.
  (DjvuBitmap, Int32List)? decodeMaskIndexed() {
    final sjbz = rawChunk('Sjbz');
    if (sjbz == null) return null;
    return jb2DecodeIndexed(sjbz, sharedDict: _dictionary());
  }

  /// Decodes the IW44 background layer (`BG44`/`BM44`/`PM44` chunks) ready for
  /// [Iw44Image.toRgb] / [Iw44Image.toGray8], or null when the page has none.
  ///
  /// Throws [Iw44Exception] when the stream is malformed.
  Iw44Image? decodeBackground() {
    final chunks = bg44Chunks();
    if (chunks.isEmpty) return null;
    final image = Iw44Image();
    for (final chunk in chunks) {
      image.decodeChunk(chunk);
    }
    return image;
  }

  /// Decodes the continuous-tone foreground layer: `FG44` IW44 chunks, or the
  /// `FGjp` JPEG. Returns null when the page has neither.
  ///
  /// Throws [Iw44Exception] for a malformed IW44 stream; undecodable `FGjp`
  /// JPEG data also yields null.
  RgbaImage? extractForeground() {
    final chunks = fg44Chunks();
    if (chunks.isNotEmpty) {
      final image = Iw44Image();
      for (final chunk in chunks) {
        image.decodeChunk(chunk);
      }
      return image.toRgb();
    }
    final fgjp = rawChunk('FGjp');
    if (fgjp == null || fgjp.isEmpty) return null;
    return decodeJpegToRgbaImage(fgjp);
  }

  /// The symbol dictionary mask streams are decoded with: the page's inline
  /// `Djbz` if present (decoded fresh), else the shared component's dictionary
  /// (decoded once per document).
  Jb2Dict? _dictionary() {
    final inline = findChunk('Djbz');
    if (inline != null) return jb2DecodeDict(inline.data);
    return sharedDict?.decoded;
  }
}

/// Decodes JPEG bytes into an [RgbaImage] (top-to-bottom rows), or null when
/// the data is not a decodable JPEG.
///
/// Used for the `BGjp`/`FGjp` JPEG-encoded layers.
RgbaImage? decodeJpegToRgbaImage(Uint8List jpeg) {
  final decoded = img.decodeJpg(jpeg);
  if (decoded == null || decoded.width == 0 || decoded.height == 0) {
    return null;
  }
  final rgba = decoded.getBytes(order: img.ChannelOrder.rgba);
  final expected = decoded.width * decoded.height * 4;
  if (rgba.length != expected) return null;
  return RgbaImage.fromData(decoded.width, decoded.height, rgba);
}

/// Which byte range of the catalog a component was fetched from.
///
/// Bundled components are sub-form bodies (`FORM` secondary type plus
/// chunks); indirect components are complete files (`AT&T` magic including).
sealed class _Component {
  /// Parses the component into a form.
  ///
  /// Throws [DjvuFormatException] when the bytes are malformed.
  IffForm parse();

  /// Parses the component, or null when it is malformed.
  IffForm? tryParse() {
    try {
      return parse();
    } on DjvuFormatException {
      return null;
    }
  }
}

class _ComponentBody extends _Component {
  _ComponentBody(this.body);

  final Uint8List body;

  @override
  IffForm parse() => parseIffSubForm(body);
}

class _ComponentFile extends _Component {
  _ComponentFile(this.bytes);

  final Uint8List bytes;

  @override
  IffForm parse() => parseIffFile(bytes);
}
