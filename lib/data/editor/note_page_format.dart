// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' show Size;

/// Named page formats (sheet proportions) for notes.
///
/// Sizes are expressed in Saber page units — the same coordinate system as
/// `EditorPage.defaultWidth`/`EditorPage.defaultHeight` — where A4 keeps the
/// app's historical 1000-unit width. Every format keeps its true physical
/// proportion (mm), so a bigger sheet (A3, tabloid) also has bigger page
/// units: ink drawn at a given size covers proportionally less of it, exactly
/// like on real paper.
///
/// The enum order is persisted (prefs store the index): keep [a4] first, as
/// the app-wide default.
enum NotePageFormat {
  /// ISO A4 (210 × 297 mm) — the app's default page format.
  a4(210, 297),

  /// ISO A3 (297 × 420 mm).
  a3(297, 420),

  /// ISO A5 (148 × 210 mm).
  a5(148, 210),

  /// ISO B5 (176 × 250 mm).
  b5(176, 250),

  /// US Letter (8.5 × 11 in).
  letter(215.9, 279.4),

  /// US Legal (8.5 × 14 in).
  legal(215.9, 355.6),

  /// US Tabloid / Ledger (11 × 17 in).
  tabloid(279.4, 431.8),

  /// Samsung Notes' native page, measured from real `.sdocx` documents
  /// (1440 × 2036 page units = 302.4 × 427.56 mm).
  ///
  /// Used as the default for imported Samsung notes so pages added later
  /// match the imported ones.
  samsungNotes(302.4, 427.56);

  const NotePageFormat(this.widthMm, this.heightMm);

  /// Physical portrait width in millimetres.
  final double widthMm;

  /// Physical portrait height in millimetres.
  final double heightMm;

  /// Page units per millimetre: A4 (210 mm) maps to the historical 1000-unit
  /// page width, keeping all existing notes and stroke sizes consistent.
  static const double unitsPerMm = 1000 / 210;

  static double _units(double mm) => (mm * unitsPerMm * 100).roundToDouble() / 100;

  /// Portrait size in page units.
  Size get portraitSize => Size(_units(widthMm), _units(heightMm));

  /// Size in page units for the given orientation.
  Size sizeFor({bool landscape = false}) {
    final s = portraitSize;
    return landscape ? Size(s.height, s.width) : s;
  }

  /// Human-readable label for the settings UI.
  String get label => switch (this) {
    NotePageFormat.a4 => 'A4',
    NotePageFormat.a3 => 'A3',
    NotePageFormat.a5 => 'A5',
    NotePageFormat.b5 => 'B5',
    NotePageFormat.letter => 'Letter',
    NotePageFormat.legal => 'Legal',
    NotePageFormat.tabloid => 'Tabloid',
    NotePageFormat.samsungNotes => 'Samsung Notes',
  };
}

/// Resolves a persisted [NotePageFormat] name, falling back to [NotePageFormat.a4]
/// for unknown names (newer files opened by an older build).
NotePageFormat notePageFormatFromName(String name) {
  for (final format in NotePageFormat.values) {
    if (format.name == name) return format;
  }
  return NotePageFormat.a4;
}
