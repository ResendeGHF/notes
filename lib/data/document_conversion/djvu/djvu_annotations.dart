// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// ANTa/ANTz annotation parser.
//
// Annotation chunks are S-expression text (plain in ANTa, BZZ-compressed in
// ANTz) holding page presentation hints and the clickable map areas:
//
//   (background #FFFFFF)
//   (zoom d100)
//   (mode color)
//   (maparea "url" "desc" (rect x y w h) (xor) (hilite #FFFF00))
//   (maparea (url "url" "_blank") "desc" (oval x y w h) (shadow_in 3))
//
// The forms the DjVu v3 spec types (background, numeric zoom, mode, maparea
// with rect/oval/poly/line/text shapes, border, hilite) are parsed into
// structures; everything else is kept as S-expression text in [extra], so a
// parse → print round trip loses nothing DjVuLibre reads.
//
// Ported from djvu-rs `src/annotation.rs` (MIT, https://github.com/matyushkin/djvu-rs).

import 'dart:typed_data';

import 'package:saber/data/document_conversion/djvu/djvu_color.dart';
import 'package:saber/data/document_conversion/djvu/djvu_iff.dart';
import 'package:saber/data/document_conversion/djvu/djvu_sexp.dart';
import 'package:saber/data/document_conversion/djvu/djvu_text.dart';

/// Page-level annotation data.
class DjvuAnnotation {
  const DjvuAnnotation({
    this.background,
    this.zoom,
    this.mode,
    this.extra = const [],
  });

  /// Background color for the page view.
  final DjvuColor? background;

  /// Zoom level (percentage, e.g. 100 = 100%).
  final int? zoom;

  /// Display mode string (e.g. `color`, `bw`, `fore`, `back`).
  final String? mode;

  /// Every other top-level form as S-expression text, in source order
  /// (`(metadata …)`, `(align center top)`, `(zoom page)`, …).
  final List<String> extra;
}

/// A map area: the shape of a clickable region.
sealed class DjvuShape {
  const DjvuShape();
}

/// A `(rect x y w h)` area.
class DjvuRectShape extends DjvuShape {
  const DjvuRectShape(this.x, this.y, this.width, this.height);

  final int x;
  final int y;
  final int width;
  final int height;
}

/// An `(oval x y w h)` area.
class DjvuOvalShape extends DjvuShape {
  const DjvuOvalShape(this.x, this.y, this.width, this.height);

  final int x;
  final int y;
  final int width;
  final int height;
}

/// A `(text x y w h)` area.
class DjvuTextShape extends DjvuShape {
  const DjvuTextShape(this.x, this.y, this.width, this.height);

  final int x;
  final int y;
  final int width;
  final int height;
}

/// A `(line x1 y1 x2 y2)` area.
class DjvuLineShape extends DjvuShape {
  const DjvuLineShape(this.x1, this.y1, this.x2, this.y2);

  final int x1;
  final int y1;
  final int x2;
  final int y2;
}

/// A `(poly x1 y1 x2 y2 …)` area.
class DjvuPolyShape extends DjvuShape {
  const DjvuPolyShape(this.points);

  final List<(int, int)> points;
}

/// Bounding box of [shape] in DjVu pixel space (bottom-left origin), or null
/// when the shape encloses no area.
///
/// One rule for the degenerate cases: a shape whose bounding box has zero
/// width or height (an empty polygon, a single repeated point, an
/// axis-aligned line, a zero-size rect) maps to null, matching the reference.
({int x, int y, int width, int height})? djvuShapeBbox(DjvuShape shape) {
  final (x, y, width, height) = switch (shape) {
    DjvuRectShape(:final x, :final y, :final width, :final height) ||
    DjvuOvalShape(:final x, :final y, :final width, :final height) ||
    DjvuTextShape(:final x, :final y, :final width, :final height) => (
      x,
      y,
      width,
      height,
    ),
    DjvuPolyShape(:final points) => _pointsBbox(points),
    DjvuLineShape(:final x1, :final y1, :final x2, :final y2) => (
      x1 < x2 ? x1 : x2,
      y1 < y2 ? y1 : y2,
      (x1 - x2).abs(),
      (y1 - y2).abs(),
    ),
  };
  if (width == 0 || height == 0) return null;
  return (x: x, y: y, width: width, height: height);
}

/// The point-cloud bounding box, or a zero-size box for an empty cloud.
(int, int, int, int) _pointsBbox(List<(int, int)> points) {
  if (points.isEmpty) return (0, 0, 0, 0);
  var (minX, minY) = points.first;
  var maxX = minX;
  var maxY = minY;
  for (final (px, py) in points.skip(1)) {
    if (px < minX) minX = px;
    if (py < minY) minY = py;
    if (px > maxX) maxX = px;
    if (py > maxY) maxY = py;
  }
  return (minX, minY, maxX - minX, maxY - minY);
}

/// A clickable map area (hyperlink or highlight region) in a DjVu page.
class DjvuMapArea {
  const DjvuMapArea({
    required this.url,
    this.target,
    required this.description,
    required this.shape,
    this.border,
    this.highlight,
    this.extra = const [],
  });

  /// Target URL (empty string if no link).
  final String url;

  /// Browser frame for the link, from the `(url "href" "target")` form; null
  /// for the plain `"href"` form.
  final String? target;

  /// Human-readable description.
  final String description;

  /// Shape of the area.
  final DjvuShape shape;

  /// Optional border option without its parentheses: `xor`, `border #RRGGBB`,
  /// `shadow_in 3`, …
  final String? border;

  /// Optional highlight color.
  final DjvuColor? highlight;

  /// Every other option of the area as S-expression text, in source order
  /// (`(border_avis)`, `(opacity 50)`, `(lineclr #FF0000)`, …).
  final List<String> extra;
}

/// Parses a decoded ANTa/ANTz payload.
///
/// Throws [DjvuFormatException] when a typed value is malformed; the reader
/// itself is lenient, so only values the caller is expected to understand can
/// fail the parse.
(DjvuAnnotation, List<DjvuMapArea>) parseDjvuAnnotations(Uint8List payload) =>
    parseDjvuAnnotationText(decodeDjvuText(payload));

/// Parses annotation S-expression [text].
(DjvuAnnotation, List<DjvuMapArea>) parseDjvuAnnotationText(String text) {
  if (text.trim().isEmpty) return (const DjvuAnnotation(), const []);

  final mapAreas = <DjvuMapArea>[];
  final extra = <String>[];
  DjvuColor? background;
  int? zoomLevel;
  String? mode;

  for (final expr in parseDjvuSexprs(text)) {
    final items = expr is DjvuSList ? expr.items : const <DjvuSExpr>[];
    final head = items.isNotEmpty ? items.first.text : null;
    final value = items.length > 1 ? items[1].text : null;
    final zoom = value == null ? null : _parseZoom(value);
    switch ((head, value)) {
      case ('background', final String color):
        background = _parseColor(color);
      case ('zoom', _) when zoom != null:
        zoomLevel = zoom;
      case ('mode', final String modeString):
        mode = modeString;
      case ('maparea', _):
        final area = _parseMapArea(items);
        if (area != null) mapAreas.add(area);
      default:
        extra.add(expr.toSexprText());
    }
  }

  return (
    DjvuAnnotation(
      background: background,
      zoom: zoomLevel,
      mode: mode,
      extra: extra,
    ),
    mapAreas,
  );
}

/// A numeric zoom: DjVuLibre's `d150`, or the bare `150` older djvu-rs
/// releases wrote. Symbolic zooms (`page`, `width`, …) return null and stay
/// in [DjvuAnnotation.extra].
int? _parseZoom(String value) =>
    _parseUint32(value.startsWith('d') ? value.substring(1) : value);

/// The DjVuLibre border options (the head of a maparea option list).
const _borderStyles = {
  'none',
  'xor',
  'border',
  'shadow_in',
  'shadow_out',
  'shadow_ein',
  'shadow_eout',
};

DjvuMapArea? _parseMapArea(List<DjvuSExpr> items) {
  // (maparea "url" "desc" (shape ...) [options...])
  // (maparea (url "url" "target") "desc" (shape ...) [options...])
  String url;
  String? target;
  final urlItem = items.length > 1 ? items[1] : null;
  if (urlItem is DjvuSList &&
      urlItem.items.isNotEmpty &&
      urlItem.items.first.text == 'url') {
    url = urlItem.items.length > 1 ? (urlItem.items[1].text ?? '') : '';
    target = urlItem.items.length > 2 ? (urlItem.items[2].text ?? '') : '';
  } else {
    url = urlItem?.text ?? '';
    target = null;
  }
  final description = items.length > 2 ? (items[2].text ?? '') : '';

  final shapeItem = items.length > 3 ? items[3] : null;
  if (shapeItem is! DjvuSList) return null;
  final shape = _parseShape(shapeItem.items);

  String? border;
  DjvuColor? highlight;
  final extra = <String>[];
  for (final item in items.skip(4)) {
    final options = item is DjvuSList ? item.items : const <DjvuSExpr>[];
    final head = options.isNotEmpty ? options.first.text : null;
    if (head == 'border' &&
        options.length == 2 &&
        options[1].text != null &&
        options[1].text != 'border' &&
        _borderStyles.contains(options[1].text)) {
      // `(border xor)`: the non-standard spelling older djvu-rs releases
      // wrote for `(xor)`. Read it as the border keyword it names.
      border = options[1].text;
    } else if (head != null && _borderStyles.contains(head)) {
      final printed = item.toSexprText();
      border = printed.substring(1, printed.length - 1);
    } else if (head == 'hilite' &&
        options.length > 1 &&
        options[1].text != null) {
      highlight = _parseColor(options[1].text!);
    } else {
      extra.add(item.toSexprText());
    }
  }

  return DjvuMapArea(
    url: url,
    target: target,
    description: description,
    shape: shape,
    border: border,
    highlight: highlight,
    extra: extra,
  );
}

DjvuShape _parseShape(List<DjvuSExpr> items) {
  final kind = items.isNotEmpty ? items.first.text : null;
  if (kind == null) {
    throw const DjvuFormatException('malformed s-expression: shape has no kind');
  }

  switch (kind) {
    case 'rect':
      return DjvuRectShape(
        _getUint(items, 1),
        _getUint(items, 2),
        _getUint(items, 3),
        _getUint(items, 4),
      );
    case 'oval':
      return DjvuOvalShape(
        _getUint(items, 1),
        _getUint(items, 2),
        _getUint(items, 3),
        _getUint(items, 4),
      );
    case 'text':
      return DjvuTextShape(
        _getUint(items, 1),
        _getUint(items, 2),
        _getUint(items, 3),
        _getUint(items, 4),
      );
    case 'line':
      return DjvuLineShape(
        _getUint(items, 1),
        _getUint(items, 2),
        _getUint(items, 3),
        _getUint(items, 4),
      );
    case 'poly':
      final points = <(int, int)>[];
      var i = 1;
      while (i + 1 < items.length) {
        points.add((_getUint(items, i), _getUint(items, i + 1)));
        i += 2;
      }
      return DjvuPolyShape(points);
    default:
      throw DjvuFormatException('malformed s-expression: unknown shape kind: $kind');
  }
}

int _getUint(List<DjvuSExpr> items, int index) {
  final item = index < items.length ? items[index] : null;
  final text = item is DjvuAtom ? item.value : null;
  if (text == null) {
    throw DjvuFormatException(
      'malformed s-expression: expected uint at position $index',
    );
  }
  final value = _parseUint32(text);
  if (value == null) {
    throw DjvuFormatException('invalid number: $text');
  }
  return value;
}

/// Strict u32 decimal parse, matching Rust's `str::parse::<u32>`: an optional
/// `+` followed by decimal digits, with overflows rejected.
int? _parseUint32(String s) {
  var i = 0;
  if (s.startsWith('+')) i = 1;
  if (i >= s.length) return null;
  var value = 0;
  for (; i < s.length; i++) {
    final digit = s.codeUnitAt(i) - 0x30;
    if (digit < 0 || digit > 9) return null;
    value = value * 10 + digit;
    if (value > 0xffffffff) return null;
  }
  return value;
}

DjvuColor _parseColor(String s) {
  final hex = s.startsWith('#') ? s.substring(1) : s;
  if (hex.length != 6) {
    throw DjvuFormatException('invalid color value: $s');
  }
  var value = 0;
  for (var i = 0; i < 6; i++) {
    final digit = _hexDigit(hex.codeUnitAt(i));
    if (digit < 0) throw DjvuFormatException('invalid color value: $s');
    value = (value << 4) | digit;
  }
  return DjvuColor((value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff);
}

int _hexDigit(int c) {
  if (c >= 0x30 && c <= 0x39) return c - 0x30;
  if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
  if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
  return -1;
}
