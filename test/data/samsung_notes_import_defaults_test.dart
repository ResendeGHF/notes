// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later

// After a Samsung Notes import, pages the user adds later must look exactly
// like the imported ones: colors, background pattern, line spacing/thickness
// and margins all come from the note defaults (EditorCoreInfo.noteDefault*),
// which the importer adopts from the imported pages — not from the user's
// global prefs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_asset_cache.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/editor/canvas_background_pattern.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/note_page_format.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/samsung_notes/sdocx_importer.dart';

/// Pages imported from a `.sdocx` keep Samsung's 1440×2036 geometry; the
/// importer scales the global metrics to it by this factor.
final Size _samsungSize = NotePageFormat.samsungNotes.sizeFor();
final double _samsungScale = _samsungSize.width / EditorPage.defaultWidth;

/// Global prefs that clearly differ from the imported pages, so a new page
/// following them instead of the import stands out.
void _useDifferentGlobalDefaults() {
  stows.lastBackgroundPattern.value = CanvasBackgroundPattern.lined;
  stows.defaultPageColor.value = 0xFFFFE0E0;
  stows.defaultLineColor.value = 0xFF7B1FA2;
  stows.lastLineHeight.value = 30;
  stows.lastLineThickness.value = 2;
  stows.defaultMarginLeft.value = 40.0;
  stows.defaultMarginRight.value = 25.0;
  stows.defaultMarginTop.value = 15.0;
  stows.defaultMarginBottom.value = 50.0;
  stows.defaultMarginColor.value = 0xFF000000;
}

EditorCoreInfo _importedSamsungNote() => EditorCoreInfo(
  filePath: '/tmp/samsung-import-defaults-test',
  readOnly: false,
)..notePageFormat = NotePageFormat.samsungNotes
 ..notePageOrientation = PageOrientation.portrait;

/// A page as the importer leaves it: Samsung geometry, global metrics scaled
/// to it, and a pattern/ink color taken from the document itself.
EditorPage _importedPage({
  CanvasBackgroundPattern pattern = CanvasBackgroundPattern.grid,
  int lineColor = 0xFF8D3B1E,
}) {
  return EditorPage(
    size: _samsungSize,
    backgroundPattern: pattern,
    hasLocalPattern: true,
    backgroundColor: const Color(0xFFFDF6E3),
    hasLocalBackgroundColor: true,
    lineColor: Color(lineColor),
    hasLocalLineColor: true,
    lineHeight: (stows.lastLineHeight.value * _samsungScale).round(),
    hasLocalLineHeight: true,
    lineThickness: stows.lastLineThickness.value * _samsungScale,
    hasLocalLineThickness: true,
    marginLeft: stows.defaultMarginLeft.value * _samsungScale,
    marginRight: stows.defaultMarginRight.value * _samsungScale,
    marginTop: stows.defaultMarginTop.value * _samsungScale,
    marginBottom: stows.defaultMarginBottom.value * _samsungScale,
    hasLocalMargins: true,
  );
}

Size _newPageSize(EditorCoreInfo coreInfo) =>
    coreInfo.notePageFormat.sizeForOrientation(coreInfo.notePageOrientation);

/// A real [PngEditorImage] is enough to mark a page as carrying a PDF/artwork
/// background; it is never painted or loaded in these tests.
EditorImage _backgroundImage() => PngEditorImage(
  id: 0,
  assetCacheAll: AssetCacheAll(),
  assetId: 0,
  extension: '.png',
  imageProviderNotifier: ValueNotifier<ImageProvider?>(null),
  pageIndex: 0,
  pageSize: _samsungSize,
  onMoveImage: null,
  onDeleteImage: null,
  onMiscChange: null,
);

void main() {
  setUp(_useDifferentGlobalDefaults);

  group('Samsung import note defaults', () {
    test('new pages match the imported page, not the global defaults', () {
      final coreInfo = _importedSamsungNote();
      final imported = _importedPage();
      coreInfo.pages.add(imported);

      SamsungNotesImporter.applyImportedPageDefaults(coreInfo);

      final added = coreInfo.createPageWithDefaults(
        size: _newPageSize(coreInfo),
      );
      expect(added.size, _samsungSize);
      expect(added.backgroundPattern, CanvasBackgroundPattern.grid);
      expect(
        added.backgroundColor.toARGB32(),
        imported.backgroundColor.toARGB32(),
      );
      expect(added.lineColor.toARGB32(), imported.lineColor.toARGB32());
      expect(added.lineHeight, imported.lineHeight);
      expect(added.lineThickness, imported.lineThickness);
      expect(added.marginLeft, imported.marginLeft);
      expect(added.marginRight, imported.marginRight);
      expect(added.marginTop, imported.marginTop);
      expect(added.marginBottom, imported.marginBottom);
      expect(added.borderColor.toARGB32(), imported.borderColor.toARGB32());
    });

    test('a blank Samsung note keeps new pages blank', () {
      final coreInfo = _importedSamsungNote();
      coreInfo.pages.add(_importedPage(pattern: CanvasBackgroundPattern.none));

      SamsungNotesImporter.applyImportedPageDefaults(coreInfo);

      final added = coreInfo.createPageWithDefaults(
        size: _newPageSize(coreInfo),
      );
      expect(added.backgroundPattern, CanvasBackgroundPattern.none);
    });

    test('pattern and colors follow the paper pages, not PDF/artwork pages', () {
      final coreInfo = _importedSamsungNote();
      // A PDF/artwork page in front: its pattern/color are hidden behind the
      // background image and must not become the note defaults.
      coreInfo.pages.add(
        _importedPage(pattern: CanvasBackgroundPattern.dots, lineColor: 0xFF000000)
          ..backgroundImage = _backgroundImage(),
      );
      // Blank cover page, then the paper the note is actually written on.
      coreInfo.pages.add(_importedPage(pattern: CanvasBackgroundPattern.none));
      coreInfo.pages.add(_importedPage(pattern: CanvasBackgroundPattern.grid));

      SamsungNotesImporter.applyImportedPageDefaults(coreInfo);

      final added = coreInfo.createPageWithDefaults(
        size: _newPageSize(coreInfo),
      );
      expect(added.backgroundPattern, CanvasBackgroundPattern.grid);
      expect(added.lineColor.toARGB32(), 0xFF8D3B1E);
    });

    test('all-PDF imports keep the global pattern for new pages', () {
      // The pattern is hidden behind the PDFs either way, so new pages fall
      // back to the global default.
      final coreInfo = _importedSamsungNote();
      coreInfo.pages.add(
        _importedPage(pattern: CanvasBackgroundPattern.lined)
          ..backgroundImage = _backgroundImage(),
      );

      SamsungNotesImporter.applyImportedPageDefaults(coreInfo);

      final added = coreInfo.createPageWithDefaults(
        size: _newPageSize(coreInfo),
      );
      expect(added.backgroundPattern, CanvasBackgroundPattern.lined);
    });

    test('imported defaults survive saving and reloading', () async {
      final coreInfo = _importedSamsungNote();
      final imported = _importedPage();
      coreInfo.pages.add(imported);

      SamsungNotesImporter.applyImportedPageDefaults(coreInfo);

      final bytes = coreInfo.saveToBinary(currentPageIndex: 0);
      final loadedSync = EditorCoreInfo.fromBinary(
        buffer: bytes,
        filePath: coreInfo.filePath,
        readOnly: false,
        onlyFirstPage: false,
      );
      final loadedAsync = await EditorCoreInfo.fromBinaryAsync(
        buffer: bytes,
        filePath: coreInfo.filePath,
        readOnly: false,
        onlyFirstPage: false,
      );

      for (final loaded in [loadedSync, loadedAsync]) {
        expect(loaded.notePageFormat, NotePageFormat.samsungNotes);
        final added = loaded.createPageWithDefaults(
          size: _newPageSize(loaded),
        );
        expect(added.backgroundPattern, CanvasBackgroundPattern.grid);
        expect(
          added.backgroundColor.toARGB32(),
          imported.backgroundColor.toARGB32(),
        );
        expect(added.lineColor.toARGB32(), imported.lineColor.toARGB32());
        expect(added.lineHeight, imported.lineHeight);
        expect(added.lineThickness, imported.lineThickness);
        expect(added.marginLeft, imported.marginLeft);
        expect(added.marginTop, imported.marginTop);
      }

      for (final page in [
        ...coreInfo.pages,
        ...loadedSync.pages,
        ...loadedAsync.pages,
      ]) {
        page.dispose();
      }
    });
  });
}
