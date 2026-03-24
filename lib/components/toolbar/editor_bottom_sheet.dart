// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/canvas/canvas_background_preview.dart';
import 'package:saber/components/canvas/canvas_image_dialog.dart';
import 'package:saber/data/editor/canvas_background_pattern.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/list_extensions.dart';
import 'package:saber/i18n/extensions/box_fit_localized.dart';
import 'package:saber/i18n/strings.g.dart';

class EditorBottomSheet extends StatefulWidget {
  const EditorBottomSheet({
    super.key,
    required this.invert,
    required this.coreInfo,
    required this.currentPageIndex,
    required this.setBackgroundPattern,
    required this.setLocalBackgroundPattern,
    required this.setLineHeight,
    required this.setLineThickness,
    required this.removeBackgroundImage,
    required this.redrawImage,
    required this.clearPage,
    required this.clearAllPages,
    required this.redrawAndSave,
    required this.pickPhotos,
    required this.importPdf,
    required this.canRasterPdf,
    required this.getIsWatchingServer,
    required this.setIsWatchingServer,
    required this.plotFunction,
    required this.toggleCalculator,
    required this.insertTable,
    required this.plotSurface,
    required this.exportAsSba,
    required this.exportAsPdf,
    required this.exportAsPng,
  });

  final bool invert;
  final EditorCoreInfo coreInfo;
  final int? currentPageIndex;
  final void Function(CanvasBackgroundPattern) setBackgroundPattern;
  final void Function(CanvasBackgroundPattern?) setLocalBackgroundPattern;
  final void Function(int) setLineHeight;
  final void Function(int) setLineThickness;
  final VoidCallback removeBackgroundImage;
  final VoidCallback redrawImage;
  final VoidCallback clearPage;
  final VoidCallback clearAllPages;
  final VoidCallback redrawAndSave;
  final Future<int> Function() pickPhotos;
  final Future<bool> Function() importPdf;
  final bool canRasterPdf;
  final bool Function() getIsWatchingServer;
  final void Function(bool) setIsWatchingServer;
  final Future<void> Function() plotFunction;
  final VoidCallback toggleCalculator;
  final Future<void> Function(int rows, int cols) insertTable;
  final Future<void> Function() plotSurface;
  final Future Function(BuildContext) exportAsSba;
  final Future Function(BuildContext) exportAsPdf;
  final Future Function(BuildContext) exportAsPng;

  @override
  State<EditorBottomSheet> createState() => _EditorBottomSheetState();
}

class _EditorBottomSheetState extends State<EditorBottomSheet> {
  static const imageBoxFits = <BoxFit>[.fill, .cover, .contain];

  @override
  Widget build(BuildContext context) {
    final page = widget.coreInfo.pages.getOrNull(widget.currentPageIndex ?? -1);
    final pageSize = page?.size ?? EditorPage.defaultSize;
    final backgroundImage = page?.backgroundImage;

    final previewSize = Size(
      CanvasBackgroundPreview.fixedWidth,
      pageSize.height / pageSize.width * CanvasBackgroundPreview.fixedWidth,
    );

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(

        dragDevices: PointerDeviceKind.values.toSet(),
      ),
      child: Padding(
        padding: const .symmetric(horizontal: 16),
        child: ListView(
          shrinkWrap: true,
          children: [
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton(
                  onPressed: widget.coreInfo.isNotEmpty
                      ? () {
                          widget.clearPage();
                          Navigator.pop(context);
                        }
                      : null,
                  child: Wrap(
                    children: [
                      const Icon(Icons.cleaning_services),
                      const SizedBox(width: 8),
                      Text(
                        t.editor.menu.clearPage(
                          page: widget.currentPageIndex == null
                              ? '?'
                              : widget.currentPageIndex! + 1,
                          totalPages: widget.coreInfo.pages.length,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: widget.coreInfo.isNotEmpty
                      ? () {
                          widget.clearAllPages();
                          Navigator.pop(context);
                        }
                      : null,
                  child: Wrap(
                    children: [
                      const Icon(Icons.cleaning_services),
                      const SizedBox(width: 8),
                      Text(t.editor.menu.clearAllPages),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (backgroundImage != null) ...[
              Text(
                t.editor.menu.backgroundImageFit,
                style: TextTheme.of(context).titleMedium,
              ),
              SizedBox(
                height: previewSize.height,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: imageBoxFits.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final boxFit = imageBoxFits[index];
                    return InkWell(
                      borderRadius: .circular(8),
                      onTap: () => setState(() {
                        backgroundImage.backgroundFit = boxFit;
                        widget.redrawAndSave();
                      }),
                      child: Stack(
                        children: [
                          CanvasBackgroundPreview(
                            selected: backgroundImage.backgroundFit == boxFit,
                            invert: widget.invert,
                            backgroundColor: widget.coreInfo.backgroundColor,
                            backgroundPattern:
                                widget.coreInfo.backgroundPattern,
                            backgroundImage: backgroundImage,
                            overrideBoxFit: boxFit,
                            pageSize: pageSize,
                            lineHeight: widget.coreInfo.lineHeight,
                            lineThickness: widget.coreInfo.lineThickness,
                          ),
                          Positioned(
                            bottom: previewSize.height * 0.1,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: _PermanentTooltip(
                                text: boxFit.localizedName,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              CanvasImageDialog(
                filePath: widget.coreInfo.filePath,
                image: backgroundImage,
                redrawImage: () => setState(() {
                  widget.redrawImage();
                }),
                isBackground: true,
                toggleAsBackground: widget.removeBackgroundImage,
                singleRow: true,
              ),
              const SizedBox(height: 16),
            ],
            Text(
              'Global ${t.editor.menu.backgroundPattern}',
              style: TextTheme.of(context).titleMedium,
            ),
            SizedBox(
              height: previewSize.height,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: CanvasBackgroundPattern.values.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final backgroundPattern =
                      CanvasBackgroundPattern.values[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() {
                      widget.setBackgroundPattern(backgroundPattern);
                    }),
                    child: Stack(
                      children: [
                        CanvasBackgroundPreview(
                          selected:
                              widget.coreInfo.backgroundPattern ==
                              backgroundPattern,
                          invert: widget.invert,
                          backgroundColor: widget.coreInfo.backgroundColor,
                          backgroundPattern: backgroundPattern,
                          backgroundImage: null,
                          pageSize: pageSize,
                          lineHeight: widget.coreInfo.lineHeight,
                          lineThickness: widget.coreInfo.lineThickness,
                        ),
                        Positioned(
                          bottom: previewSize.height * 0.1,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: _PermanentTooltip(
                              text: CanvasBackgroundPattern.localizedName(
                                backgroundPattern,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            if (widget.currentPageIndex != null) ...[
              Text(
                'Local ${t.editor.menu.backgroundPattern} (Current page)',
                style: TextTheme.of(context).titleMedium,
              ),
              SizedBox(
                height: previewSize.height,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: CanvasBackgroundPattern.values.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final isDefault = index == 0;
                    final backgroundPattern = isDefault
                        ? null
                        : CanvasBackgroundPattern.values[index - 1];
                    final page =
                        widget.coreInfo.pages[widget.currentPageIndex!];

                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() {
                        widget.setLocalBackgroundPattern(backgroundPattern);
                      }),
                      child: Stack(
                        children: [
                          CanvasBackgroundPreview(
                            selected:
                                page.backgroundPattern == backgroundPattern,
                            invert: widget.invert,
                            backgroundColor: widget.coreInfo.backgroundColor,
                            backgroundPattern:
                                backgroundPattern ??
                                widget.coreInfo.backgroundPattern,
                            backgroundImage: null,
                            pageSize: pageSize,
                            lineHeight: widget.coreInfo.lineHeight,
                            lineThickness: widget.coreInfo.lineThickness,
                          ),
                          Positioned(
                            bottom: previewSize.height * 0.1,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: _PermanentTooltip(
                                text: isDefault
                                    ? 'Global'
                                    : CanvasBackgroundPattern.localizedName(
                                        backgroundPattern!,
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              t.editor.menu.lineHeight,
              style: TextTheme.of(context).titleMedium,
            ),
            Text(
              t.editor.menu.lineHeightDescription,
              style: TextTheme.of(context).bodyMedium,
            ),
            Row(
              children: [
                Text(widget.coreInfo.lineHeight.toString()),
                Expanded(
                  child: Slider(
                    value: widget.coreInfo.lineHeight.toDouble(),
                    min: 20,
                    max: 100,
                    divisions: 8,
                    onChanged: (double value) => setState(() {
                      widget.setLineHeight(value.toInt());
                    }),
                  ),
                ),
              ],
            ),
            Text(
              t.editor.menu.lineThickness,
              style: TextTheme.of(context).titleMedium,
            ),
            Text(
              t.editor.menu.lineThicknessDescription,
              style: TextTheme.of(context).bodyMedium,
            ),
            Row(
              children: [
                Text(widget.coreInfo.lineThickness.toString()),
                Expanded(
                  child: Slider(
                    value: widget.coreInfo.lineThickness.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    onChanged: (double value) => setState(() {
                      widget.setLineThickness(value.toInt());
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              t.editor.menu.import,
              style: TextTheme.of(context).titleMedium,
            ),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton(
                  onPressed: () async {
                    final photosPicked = await widget.pickPhotos();
                    if (photosPicked > 0) {
                      if (!context.mounted) return;
                      Navigator.pop(context);
                    }
                  },
                  child: Text(t.editor.toolbar.photo),
                ),
                if (widget.canRasterPdf)
                  ElevatedButton(
                    onPressed: () async {
                      final pdfImported = await widget.importPdf();
                      if (pdfImported) {
                        if (!context.mounted) return;
                        Navigator.pop(context);
                      }
                    },
                    child: const Text('PDF'),
                  ),
                ElevatedButton.icon(
                  onPressed: () async {
                    await widget.plotFunction();
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.show_chart),
                  label: const Text('Plot Function'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    widget.toggleCalculator();
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.calculate),
                  label: const Text('Calculator'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final rowsCols = await _TableDialog.show(context);
                    if (rowsCols != null) {
                      await widget.insertTable(rowsCols.$1, rowsCols.$2);
                    }
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.table_chart),
                  label: const Text('Insert Table'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    await widget.plotSurface();
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.terrain),
                  label: const Text('Plot 3D'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              t.editor.toolbar.export,
              style: TextTheme.of(context).titleMedium,
            ),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton(
                  onPressed: () {
                    widget.exportAsSba(context);
                    Navigator.pop(context);
                  },
                  child: const Text('SBA'),
                ),
                ElevatedButton(
                  onPressed: () {
                    widget.exportAsPdf(context);
                    Navigator.pop(context);
                  },
                  child: const Text('PDF'),
                ),
                ElevatedButton(
                  onPressed: () {
                    widget.exportAsPng(context);
                    Navigator.pop(context);
                  },
                  child: const Text('Image'),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _TableDialog extends StatefulWidget {
  const _TableDialog();

  static Future<(int, int)?> show(BuildContext context) {
    return showDialog<(int, int)>(
      context: context,
      builder: (_) => const _TableDialog(),
    );
  }

  @override
  State<_TableDialog> createState() => _TableDialogState();
}

class _TableDialogState extends State<_TableDialog> {
  final _rowsCtrl = TextEditingController(text: '3');
  final _colsCtrl = TextEditingController(text: '3');

  @override
  void dispose() {
    _rowsCtrl.dispose();
    _colsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create table'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _rowsCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Rows',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _colsCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Columns',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        ElevatedButton(
          onPressed: () {
            final rows = int.tryParse(_rowsCtrl.text) ?? 0;
            final cols = int.tryParse(_colsCtrl.text) ?? 0;
            if (rows < 1 || cols < 1) {
              Navigator.of(context).pop();
              return;
            }
            Navigator.of(context).pop((rows, cols));
          },
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}

class _PermanentTooltip extends StatelessWidget {
  const _PermanentTooltip({

    super.key,
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: .circular(8),
        color: colorScheme.surface.withValues(alpha: 0.8),
      ),
      child: Padding(
        padding: const .symmetric(horizontal: 8),
        child: Text(
          text,
          textAlign: .center,
          textWidthBasis: TextWidthBasis.longestLine,
          style: TextStyle(color: colorScheme.onSurface),
        ),
      ),
    );
  }
}
