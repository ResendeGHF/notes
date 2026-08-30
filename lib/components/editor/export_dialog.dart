// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/link_export_expander.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/data/editor/editor_exporter.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/prefs.dart';

enum ExportFormat { pdf, png, jpeg }

enum ExportPageRange { current, all, custom }

enum ExportResolution { dpi72, dpi150, dpi300 }

class _ImageArchiveFile {
  const _ImageArchiveFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

Uint8List _encodeImageArchive(List<_ImageArchiveFile> files) {
  final archive = Archive();
  for (final file in files) {
    archive.addFile(ArchiveFile(file.name, file.bytes.length, file.bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

extension ExportResolutionExt on ExportResolution {
  double get pixelRatio => switch (this) {
    ExportResolution.dpi72 => 1.0,
    ExportResolution.dpi150 => 150 / 72,
    ExportResolution.dpi300 => 300 / 72,
  };
}

class ExportDialog extends StatefulWidget {
  final EditorCoreInfo coreInfo;
  final int currentPageIndex;
  final ExportFormat initialFormat;

  final BuildContext? parentContext;

  const ExportDialog({
    super.key,
    required this.coreInfo,
    required this.currentPageIndex,
    this.initialFormat = ExportFormat.pdf,
    this.parentContext,
  });

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  late ExportFormat _format = widget.initialFormat;
  ExportPageRange _pageRange = ExportPageRange.all;
  ExportResolution _jpegResolution = ExportResolution.dpi150;
  final TextEditingController _customRangeController = TextEditingController();
  bool _isExporting = false;
  bool _invertColors = false;
  bool _shareLinks = false;

  @override
  void initState() {
    super.initState();
    if (widget.coreInfo.isInfinite) {
      _pageRange = ExportPageRange.current;
    }
    _invertColors = getEffectiveNoteInvertInDarkModeForFile(
      widget.coreInfo.filePath,
    );
  }

  @override
  void dispose() {
    _customRangeController.dispose();
    super.dispose();
  }

  List<int> _getSelectedPageIndices() {
    if (widget.coreInfo.isInfinite) {
      return widget.coreInfo.pages.isEmpty ? const [] : const [0];
    }
    switch (_pageRange) {
      case ExportPageRange.current:
        return [widget.currentPageIndex];
      case ExportPageRange.all:
        return List.generate(widget.coreInfo.pages.length, (index) => index);
      case ExportPageRange.custom:
        final rangeStr = _customRangeController.text;
        final indices = <int>[];
        final parts = rangeStr.split(',');
        for (final part in parts) {
          final rangeParts = part.trim().split('-');
          if (rangeParts.length == 1) {
            final index = int.tryParse(rangeParts[0]);
            if (index != null &&
                index > 0 &&
                index <= widget.coreInfo.pages.length) {
              indices.add(index - 1);
            }
          } else if (rangeParts.length == 2) {
            final start = int.tryParse(rangeParts[0]);
            final end = int.tryParse(rangeParts[1]);
            if (start != null &&
                end != null &&
                start > 0 &&
                end >= start &&
                end <= widget.coreInfo.pages.length) {
              for (int i = start; i <= end; i++) {
                indices.add(i - 1);
              }
            }
          }
        }
        return indices.toSet().toList()..sort();
    }
  }

  Future<void> _export() async {
    final indices = _getSelectedPageIndices();
    if (indices.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.export.noValidPagesSelected)));
      return;
    }

    if (_format == ExportFormat.pdf &&
        _shareLinks &&
        stows.defaultExportPath.value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.export.defaultExportPathRequired)),
      );
      return;
    }

    final saveToPath = stows.defaultExportPath.value.isNotEmpty
        ? stows.defaultExportPath.value
        : null;

    setState(() => _isExporting = true);
    WakelockPlus.enable();
    try {
      if (_format == ExportFormat.pdf) {
        if (saveToPath != null) {
          final messengerContext = widget.parentContext ?? context;
          Navigator.of(context).pop();
          await ExportManager.exportInBackground(t.export.exportingNote, (
            onProgress,
          ) async {
            onProgress(0.05, '${widget.coreInfo.fileName}.pdf');
            final data = await EditorExporter.generatePdfData(
              widget.coreInfo,
              messengerContext,
              pageIndices: indices,
              invert: _invertColors,
              shareLinks: _shareLinks,
              onProgress: (done, total) {
                onProgress(
                  0.05 + 0.75 * (done / total),
                  '${widget.coreInfo.fileName}.pdf',
                );
              },
            );
            await Future<void>.delayed(Duration.zero);
            onProgress(0.9, t.export.exportComplete);
            final outName = '${widget.coreInfo.fileName}.pdf';
            if (data.tempPdfPath != null) {
              await FileManager.exportPdfTempFile(
                data.tempPdfPath!,
                outName,
                saveToPath: saveToPath,
                context: messengerContext,
              );
            } else {
              await FileManager.exportFile(
                outName,
                data.bytes!,
                saveToPath: saveToPath,
                context: messengerContext,
              );
            }
          });
          if (messengerContext.mounted) {
            ScaffoldMessenger.of(
              messengerContext,
            ).showSnackBar(SnackBar(content: Text(t.export.exportComplete)));
          }
        } else {
          final data = await ExportManager.exportInBackground<PdfExportData>(
            t.export.exportingNote,
            (onProgress) async {
              onProgress(0.05, '${widget.coreInfo.fileName}.pdf');
              final pdf = await EditorExporter.generatePdfData(
                widget.coreInfo,
                context,
                pageIndices: indices,
                invert: _invertColors,
                shareLinks: _shareLinks,
                onProgress: (done, total) {
                  onProgress(
                    0.05 + 0.75 * (done / total),
                    '${widget.coreInfo.fileName}.pdf',
                  );
                },
              );
              await Future<void>.delayed(Duration.zero);
              onProgress(0.9, t.export.exportComplete);
              return pdf;
            },
          );
          if (!mounted) return;
          final outName = '${widget.coreInfo.fileName}.pdf';
          if (data.tempPdfPath != null) {
            await FileManager.exportPdfTempFile(
              data.tempPdfPath!,
              outName,
              context: context,
            );
          } else {
            await FileManager.exportFile(
              outName,
              data.bytes!,
              context: context,
            );
          }
        }
      } else {
        final ext = _format == ExportFormat.png ? 'png' : 'jpeg';
        final rasterPages =
            await ExportManager.exportInBackground<
              List<({Uint8List bytes, int pageIndex})>
            >(t.export.exportingNote, (onProgress) async {
              return EditorExporter.generateRasterPages(
                widget.coreInfo,
                context,
                pageIndices: indices,
                jpeg: _format == ExportFormat.jpeg,
                invert: _invertColors,
                pixelRatio: _jpegResolution.pixelRatio,
                onProgress: (done, total) {
                  onProgress(
                    0.05 + 0.85 * (done / total),
                    '${widget.coreInfo.fileName}.$ext',
                  );
                },
              );
            });
        if (!mounted) return;

        final Uint8List exportBytes;
        final String exportName;
        final bool isImage;
        if (indices.length == 1) {
          exportBytes = rasterPages.first.bytes;
          exportName = widget.coreInfo.isInfinite
              ? '${widget.coreInfo.fileName}.$ext'
              : '${widget.coreInfo.fileName}_page_${indices.first + 1}.$ext';
          isImage = true;
        } else {
          final archiveFiles = <_ImageArchiveFile>[];
          for (final page in rasterPages) {
            archiveFiles.add(
              _ImageArchiveFile(
                name:
                    '${widget.coreInfo.fileName}_page_${page.pageIndex + 1}.$ext',
                bytes: page.bytes,
              ),
            );
          }
          exportBytes = await compute(_encodeImageArchive, archiveFiles);
          exportName = '${widget.coreInfo.fileName}_pages.zip';
          isImage = false;
        }

        if (!mounted) return;
        await FileManager.exportFile(
          exportName,
          exportBytes,
          isImage: isImage,
          context: context,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.export.exportFailed(error: e))),
        );
      }
    } finally {
      WakelockPlus.disable();
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            width: 420,
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1C1C1E).withValues(alpha: 0.85)
                  : colorScheme.surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : colorScheme.outlineVariant.withValues(alpha: 0.4),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 32,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Text(
                    t.export.export,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RadioListTile<ExportFormat>(
                          title: Text(t.export.pdf),
                          subtitle: Text(
                            t.export.resolutionPdfVector,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          value: ExportFormat.pdf,
                          groupValue: _format,
                          onChanged: (v) => setState(() => _format = v!),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        RadioListTile<ExportFormat>(
                          title: Text(t.export.png),
                          subtitle: Text(
                            t.export.pngSubtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          value: ExportFormat.png,
                          groupValue: _format,
                          onChanged: (v) => setState(() => _format = v!),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        RadioListTile<ExportFormat>(
                          title: Text(t.export.jpeg),
                          subtitle: Text(
                            t.export.jpegSubtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          value: ExportFormat.jpeg,
                          groupValue: _format,
                          onChanged: (v) => setState(() => _format = v!),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        if (_format == ExportFormat.jpeg ||
                            _format == ExportFormat.png) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                            child: DropdownButtonFormField<ExportResolution>(
                              value: _jpegResolution,
                              decoration: InputDecoration(
                                labelText: t.export.resolution,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : colorScheme.surfaceContainerHighest
                                          .withValues(alpha: 0.5),
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: ExportResolution.dpi72,
                                  child: Text(t.export.resolution72),
                                ),
                                DropdownMenuItem(
                                  value: ExportResolution.dpi150,
                                  child: Text(t.export.resolution150),
                                ),
                                DropdownMenuItem(
                                  value: ExportResolution.dpi300,
                                  child: Text(t.export.resolution300),
                                ),
                              ],
                              onChanged: (v) =>
                                  setState(() => _jpegResolution = v!),
                            ),
                          ),
                        ],
                        if (!widget.coreInfo.isInfinite) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 16,
                            ),
                            child: Divider(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.1)
                                  : colorScheme.outlineVariant.withValues(
                                      alpha: 0.3,
                                    ),
                            ),
                          ),
                          RadioListTile<ExportPageRange>(
                            title: Text(t.export.currentPage),
                            value: ExportPageRange.current,
                            groupValue: _pageRange,
                            onChanged: (v) => setState(() => _pageRange = v!),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          RadioListTile<ExportPageRange>(
                            title: Text(t.export.allPages),
                            value: ExportPageRange.all,
                            groupValue: _pageRange,
                            onChanged: (v) => setState(() => _pageRange = v!),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          RadioListTile<ExportPageRange>(
                            title: Text(t.export.customRange),
                            value: ExportPageRange.custom,
                            groupValue: _pageRange,
                            onChanged: (v) => setState(() => _pageRange = v!),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOutCubic,
                            child: _pageRange == ExportPageRange.custom
                                ? Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      24,
                                      0,
                                      24,
                                      12,
                                    ),
                                    child: TextField(
                                      controller: _customRangeController,
                                      decoration: InputDecoration(
                                        hintText: t.export.customRangeHint,
                                        labelText: t.export.pageNumbers,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        filled: true,
                                        fillColor: isDark
                                            ? Colors.white.withValues(
                                                alpha: 0.05,
                                              )
                                            : colorScheme
                                                  .surfaceContainerHighest
                                                  .withValues(alpha: 0.5),
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 16,
                          ),
                          child: Divider(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : colorScheme.outlineVariant.withValues(
                                    alpha: 0.3,
                                  ),
                          ),
                        ),
                        SwitchListTile(
                          title: Text(t.export.invertColors),
                          subtitle: Text(
                            t.export.invertColorsSubtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          value: _invertColors,
                          onChanged: (v) {
                            setState(() => _invertColors = v);
                          },
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        if (_format == ExportFormat.pdf &&
                            widget.coreInfo.links.any(
                              (l) => isExternalNoteLink(
                                l,
                                widget.coreInfo.filePath,
                              ),
                            )) ...[
                          SwitchListTile(
                            title: Text(t.export.shareLinks),
                            subtitle: Text(
                              t.export.shareLinksSubtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            value: _shareLinks,
                            onChanged: (v) {
                              setState(() => _shareLinks = v);
                            },
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _isExporting
                            ? null
                            : () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(t.export.cancel),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: _isExporting ? null : _export,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isExporting
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.onPrimary,
                                ),
                              )
                            : Text(t.export.export),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
