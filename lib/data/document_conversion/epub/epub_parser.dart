// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// EPUB container parsing: ZIP archive -> `META-INF/container.xml` -> OPF
// package (metadata/manifest/spine) plus the EPUB3 navigation document or the
// EPUB2 NCX. Only the subset needed to lay an EPUB out as PDF is modelled.
// Individual broken spine documents, manifest items and TOC entries are
// skipped; a broken ZIP/container/package aborts the conversion.

// html/xml are pulled in through the pdf package rather than declared directly.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

/// Thrown when an EPUB cannot be converted to PDF.
class EpubConversionException implements Exception {
  const EpubConversionException(this.message);
  final String message;

  @override
  String toString() => 'EpubConversionException: $message';
}

/// Read-only view over an EPUB ZIP with tolerant path lookup.
///
/// EPUB producers are inconsistent about entry names (`./` prefixes, percent
/// escapes, Windows separators, letter case), so lookups fall back to a
/// normalised and case-insensitive match before giving up.
class EpubArchive {
  EpubArchive(this.archive) {
    for (final file in archive.files) {
      if (file.isFile) {
        _byName[_normalizeZipName(file.name)] = file;
      }
    }
  }

  final Archive archive;
  final _byName = <String, ArchiveFile>{};
  final _lookupCache = <String, ArchiveFile?>{};

  static String _normalizeZipName(String name) {
    var out = name.replaceAll(r'\', '/');
    while (out.startsWith('./')) {
      out = out.substring(2);
    }
    return out;
  }

  /// Returns the archive entry for [path], or null when it does not exist.
  ArchiveFile? findFile(String path) {
    final cached = _lookupCache[path];
    if (cached != null || _lookupCache.containsKey(path)) return cached;

    final normalized = _normalizeZipName(path);
    var file = _byName[normalized];
    if (file == null) {
      final decoded = decodeHref(normalized);
      if (decoded != normalized) file = _byName[_normalizeZipName(decoded)];
    }
    if (file == null && normalized.isNotEmpty) {
      final lower = normalized.toLowerCase();
      for (final entry in _byName.entries) {
        if (entry.key.toLowerCase() == lower) {
          file = entry.value;
          break;
        }
      }
    }
    _lookupCache[path] = file;
    return file;
  }

  /// Reads the bytes of [path], or null when the entry is missing.
  Uint8List? readFile(String path) => findFile(path)?.readBytes();
}

/// A manifest item of the OPF package.
class EpubManifestItem {
  const EpubManifestItem({
    required this.id,
    required this.rawHref,
    required this.href,
    required this.mediaType,
    required this.properties,
    required this.title,
  });

  final String id;
  final String rawHref;

  /// ZIP-relative, percent-decoded path, or null when [rawHref] escapes the
  /// archive root or points at an absolute URL.
  final String? href;

  final String mediaType;
  final Set<String> properties;
  final String? title;
}

/// One top-level document in the spine, in reading order.
class EpubSpineItem {
  const EpubSpineItem({
    required this.index,
    required this.idref,
    required this.item,
    required this.linear,
  });

  /// Position in the spine (also used for anchor names, so it stays stable
  /// even when neighbouring items are skipped).
  final int index;

  final String idref;

  /// Resolved manifest entry, or null when the spine references a missing id.
  final EpubManifestItem? item;

  final bool linear;
}

/// A navigation entry (EPUB3 nav or EPUB2 NCX).
class EpubTocEntry {
  const EpubTocEntry({
    required this.title,
    required this.href,
    required this.children,
  });

  final String title;

  /// Raw href as written in the navigation document (may be relative and may
  /// carry a fragment).
  final String href;

  final List<EpubTocEntry> children;
}

/// A parsed EPUB package ready for rendering.
class EpubBook {
  EpubBook({
    required this.archive,
    required this.opfPath,
    required this.title,
    required this.author,
    required this.language,
    required this.manifest,
    required this.spine,
    required this.tocBasePath,
    required this.toc,
  }) : manifestById = {
         for (final item in manifest)
           if (item.id.isNotEmpty) item.id: item,
       };

  final EpubArchive archive;
  final String opfPath;
  final String title;
  final String author;
  final String language;
  final List<EpubManifestItem> manifest;
  final List<EpubSpineItem> spine;

  /// ZIP directory of the navigation document; TOC hrefs are relative to it.
  final String tocBasePath;

  final List<EpubTocEntry> toc;

  final Map<String, EpubManifestItem> manifestById;
}

/// Media types treated as renderable XHTML documents.
bool isXhtmlMediaType(String mediaType) {
  switch (mediaType.trim().toLowerCase()) {
    case 'application/xhtml+xml':
    case 'text/html':
    case 'application/xml':
    case 'text/xml':
      return true;
    default:
      return false;
  }
}

/// Parses an EPUB file into a [EpubBook].
///
/// Throws [EpubConversionException] when the file is not a ZIP archive, when
/// the container/package document is missing or unreadable, or when the OPF
/// has no manifest/spine at all.
EpubBook parseEpub(Uint8List bytes) {
  if (bytes.isEmpty) {
    throw const EpubConversionException('EPUB file is empty');
  }

  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (e) {
    throw EpubConversionException('Not a readable ZIP archive: $e');
  }
  final archive = EpubArchive(zip);

  final containerEntry = archive.findFile('META-INF/container.xml');
  if (containerEntry == null) {
    throw const EpubConversionException('Missing META-INF/container.xml');
  }
  final containerXml = _decodeText(containerEntry.readBytes());
  final container = _tryParseXml(containerXml);
  if (container == null) {
    throw const EpubConversionException('Malformed META-INF/container.xml');
  }

  final rootfile = _firstDescendant(
    container.rootElement,
    'rootfile',
  );
  final opfRaw = rootfile?.getAttribute('full-path');
  if (opfRaw == null || opfRaw.trim().isEmpty) {
    throw const EpubConversionException(
      'META-INF/container.xml has no rootfile',
    );
  }
  final opfPath = resolveArchivePath('', opfRaw.trim());
  if (opfPath == null) {
    throw EpubConversionException('Invalid OPF path: $opfRaw');
  }

  final opfEntry = archive.findFile(opfPath);
  if (opfEntry == null) {
    throw EpubConversionException('Missing package document: $opfPath');
  }
  final opf = _tryParseXml(_decodeText(opfEntry.readBytes()));
  if (opf == null) {
    throw EpubConversionException('Malformed package document: $opfPath');
  }

  final metadata = _firstDescendant(opf.rootElement, 'metadata');
  final title = _metadataValue(metadata, 'title');
  final author = _metadataValue(metadata, 'creator');
  final language = _metadataValue(metadata, 'language');

  final manifest = <EpubManifestItem>[];
  final manifestElement = _firstDescendant(opf.rootElement, 'manifest');
  if (manifestElement != null) {
    for (final element in manifestElement.childElements) {
      if (element.name.local != 'item') continue;
      final id = element.getAttribute('id')?.trim() ?? '';
      final hrefRaw = element.getAttribute('href')?.trim() ?? '';
      if (id.isEmpty || hrefRaw.isEmpty) continue;
      final mediaType = element.getAttribute('media-type')?.trim() ?? '';
      final properties = <String>{
        for (final value in (element.getAttribute('properties') ?? '').split(','))
          if (value.trim().isNotEmpty) value.trim().toLowerCase(),
      };
      manifest.add(
        EpubManifestItem(
          id: id,
          rawHref: hrefRaw,
          href: resolveArchivePath(opfPath, hrefRaw),
          mediaType: mediaType,
          properties: properties,
          title: element.getAttribute('title')?.trim(),
        ),
      );
    }
  }

  final spine = <EpubSpineItem>[];
  var spineTocId = '';
  final manifestById = {
    for (final item in manifest) item.id: item,
  };
  final spineElement = _firstDescendant(opf.rootElement, 'spine');
  if (spineElement != null) {
    spineTocId = spineElement.getAttribute('toc')?.trim() ?? '';
    for (final element in spineElement.childElements) {
      if (element.name.local != 'itemref') continue;
      final idref = element.getAttribute('idref')?.trim() ?? '';
      if (idref.isEmpty) continue;
      spine.add(
        EpubSpineItem(
          index: spine.length,
          idref: idref,
          item: manifestById[idref],
          linear: (element.getAttribute('linear') ?? 'yes').toLowerCase() != 'no',
        ),
      );
    }
  }

  if (manifest.isEmpty && spine.isEmpty) {
    throw EpubConversionException(
      'Package document has no manifest or spine: $opfPath',
    );
  }

  final toc = _parseTableOfContents(
    archive: archive,
    manifest: manifest,
    spineTocId: spineTocId,
  );

  return EpubBook(
    archive: archive,
    opfPath: opfPath,
    title: title,
    author: author,
    language: language,
    manifest: manifest,
    spine: spine,
    tocBasePath: toc.basePath,
    toc: toc.entries,
  );
}

typedef _ParsedToc = ({String basePath, List<EpubTocEntry> entries});

_ParsedToc _parseTableOfContents({
  required EpubArchive archive,
  required List<EpubManifestItem> manifest,
  required String spineTocId,
}) {
  // EPUB3 navigation document.
  for (final item in manifest) {
    final isNav =
        item.properties.contains('nav') ||
        item.properties.contains('navigation');
    if (!isNav || item.href == null) continue;
    if (!isXhtmlMediaType(item.mediaType) && item.mediaType.isNotEmpty) {
      continue;
    }
    final bytes = archive.readFile(item.href!);
    if (bytes == null) continue;
    final document = parseEpubHtml(_decodeText(bytes));
    if (document == null) continue;
    final entries = _parseNavDocument(document);
    if (entries.isNotEmpty) {
      return (basePath: item.href!, entries: entries);
    }
  }

  // EPUB2 NCX.
  EpubManifestItem? ncx;
  if (spineTocId.isNotEmpty) {
    for (final item in manifest) {
      if (item.id == spineTocId) {
        ncx = item;
        break;
      }
    }
  }
  if (ncx == null) {
    for (final item in manifest) {
      if (item.mediaType.trim().toLowerCase() == 'application/x-dtbncx+xml') {
        ncx = item;
        break;
      }
    }
  }
  if (ncx?.href != null) {
    final bytes = archive.readFile(ncx!.href!);
    if (bytes != null) {
      final document = _tryParseXml(_decodeText(bytes));
      if (document != null) {
        final entries = _parseNcx(document);
        if (entries.isNotEmpty) {
          return (basePath: ncx.href!, entries: entries);
        }
      }
    }
  }

  return (basePath: '', entries: const <EpubTocEntry>[]);
}

List<EpubTocEntry> _parseNavDocument(dom.Document document) {
  final navs = document.querySelectorAll('nav').toList();
  dom.Element? tocNav;
  for (final nav in navs) {
    final type = (nav.attributes['epub:type'] ??
            nav.attributes['type'] ??
            '')
        .toLowerCase();
    final role = (nav.attributes['role'] ?? '').toLowerCase();
    if (type.contains('toc') || role.contains('doc-toc')) {
      tocNav = nav;
      break;
    }
  }
  tocNav ??= navs.isEmpty ? null : navs.first;
  if (tocNav == null) return const <EpubTocEntry>[];
  final list = tocNav.querySelector('ol') ?? tocNav.querySelector('ul');
  if (list == null) return const <EpubTocEntry>[];
  return _parseNavList(list);
}

/// Deepest table-of-contents nesting that is parsed; deeper lists are dropped.
///
/// Real TOCs are a handful of levels deep; an unbounded recursion over a
/// malformed document could exhaust the stack.
const kEpubMaxTocDepth = 12;

List<EpubTocEntry> _parseNavList(dom.Element list, [int depth = 0]) {
  if (depth >= kEpubMaxTocDepth) return const <EpubTocEntry>[];
  final out = <EpubTocEntry>[];
  for (final child in list.children) {
    if (child.localName != 'li') continue;
    dom.Element? anchor;
    dom.Element? span;
    for (final element in child.children) {
      if (element.localName == 'a' && anchor == null) anchor = element;
      if ((element.localName == 'span' || element.localName == 'b') &&
          span == null) {
        span = element;
      }
    }
    anchor ??= child.querySelector('a');
    span ??= child.querySelector('span');
    final title = (anchor?.text ?? span?.text ?? '').trim();
    final href = anchor?.attributes['href']?.trim();
    final children = <EpubTocEntry>[];
    for (final element in child.children) {
      if (element.localName == 'ol' || element.localName == 'ul') {
        children.addAll(_parseNavList(element, depth + 1));
      }
    }
    if (href == null || href.isEmpty) {
      // Container entry without a target: promote its children.
      out.addAll(children);
      continue;
    }
    if (title.isEmpty) {
      out.addAll(children);
      continue;
    }
    out.add(EpubTocEntry(title: title, href: href, children: children));
  }
  return out;
}

List<EpubTocEntry> _parseNcx(XmlDocument document) {
  final navMap = _firstDescendant(document.rootElement, 'navMap');
  if (navMap == null) return const <EpubTocEntry>[];
  return _parseNcxPoints(navMap);
}

List<EpubTocEntry> _parseNcxPoints(XmlElement parent, [int depth = 0]) {
  if (depth >= kEpubMaxTocDepth) return const <EpubTocEntry>[];
  final out = <EpubTocEntry>[];
  for (final element in parent.childElements) {
    if (element.name.local != 'navPoint') continue;
    final label = _firstChild(element, 'navLabel');
    final text = label == null
        ? ''
        : (_firstChild(label, 'text')?.innerText ?? '').trim();
    final content = _firstChild(element, 'content');
    final src = content?.getAttribute('src')?.trim() ?? '';
    final children = _parseNcxPoints(element, depth + 1);
    if (text.isEmpty || src.isEmpty) {
      out.addAll(children);
      continue;
    }
    out.add(EpubTocEntry(title: text, href: src, children: children));
  }
  return out;
}

XmlElement? _firstChild(XmlElement parent, String localName) {
  for (final element in parent.childElements) {
    if (element.name.local == localName) return element;
  }
  return null;
}

XmlElement? _firstDescendant(XmlNode? root, String localName) {
  if (root == null) return null;
  for (final node in root.descendants) {
    if (node is XmlElement && node.name.local == localName) return node;
  }
  return null;
}

String _metadataValue(XmlElement? metadata, String localName) {
  if (metadata == null) return '';
  for (final element in metadata.descendants) {
    if (element is XmlElement && element.name.local == localName) {
      final text = element.innerText.trim();
      if (text.isNotEmpty) return text;
    }
  }
  return '';
}

XmlDocument? _tryParseXml(String text) {
  if (text.trim().isEmpty) return null;
  try {
    return XmlDocument.parse(text);
  } catch (_) {
    return null;
  }
}

/// Parses [text] as HTML/XHTML; null when it is empty or malformed.
///
/// Used for spine documents, the navigation document and inline NCX content.
dom.Document? parseEpubHtml(String text) {
  if (text.trim().isEmpty) return null;
  try {
    return html_parser.parse(text);
  } catch (_) {
    return null;
  }
}

String _decodeText(Uint8List? bytes) {
  if (bytes == null || bytes.isEmpty) return '';
  var data = bytes;
  if (data.length >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF) {
    data = Uint8List.sublistView(data, 3);
  }
  return utf8.decode(data, allowMalformed: true);
}

/// Splits an href into its path and fragment parts (no percent decoding).
({String path, String fragment}) splitHref(String href) {
  final hash = href.indexOf('#');
  if (hash < 0) return (path: href, fragment: '');
  return (path: href.substring(0, hash), fragment: href.substring(hash + 1));
}

/// Percent-decodes [value], returning it unchanged when it is malformed.
String decodeHref(String value) {
  if (!value.contains('%')) return value;
  try {
    return Uri.decodeComponent(value);
  } catch (_) {
    return value;
  }
}

final _schemePattern = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]*):');

/// Whether [href] names an absolute URL with a scheme.
bool hrefHasScheme(String href) => _schemePattern.hasMatch(href);

/// Resolves [href] relative to the ZIP directory of [basePath] (the containing
/// document). Returns null for absolute URLs, empty targets and paths that
/// escape the archive root.
String? resolveArchivePath(String basePath, String href) {
  final raw = href.trim();
  if (raw.isEmpty) return null;
  if (hrefHasScheme(raw)) return null;

  var path = splitHref(raw).path;
  final query = path.indexOf('?');
  if (query >= 0) path = path.substring(0, query);
  if (path.isEmpty) return null;

  final segments = <String>[];
  if (!path.startsWith('/')) {
    final baseDir = dirname(basePath);
    if (baseDir.isNotEmpty) segments.addAll(baseDir.split('/'));
  }
  for (final part in path.split('/')) {
    if (part.isEmpty || part == '.') continue;
    final decoded = decodeHref(part);
    if (decoded == '..') {
      if (segments.isEmpty) return null;
      segments.removeLast();
      continue;
    }
    segments.add(decoded);
  }
  if (segments.isEmpty) return null;
  return segments.join('/');
}

/// The ZIP directory part of [path] ('' when it has none).
String dirname(String path) {
  final slash = path.lastIndexOf('/');
  if (slash <= 0) return '';
  return path.substring(0, slash);
}
