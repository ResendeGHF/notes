// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io' show File;
import 'dart:isolate' show Isolate;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive_io.dart';
import 'package:saber/components/editor/sba_export_dialog.dart';
import 'package:saber/services/sba_encryption.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:saber/components/theming/adaptive_circular_progress_indicator.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/editor_exporter.dart';
import 'package:saber/data/editor/link_export_expander.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';

class _HomeExportFile {
  _HomeExportFile._({required this.name, this.bytes, this.tempPath})
      : assert(
          (bytes != null) ^ (tempPath != null),
          '_HomeExportFile: provide bytes or tempPath',
        );

  factory _HomeExportFile.bytes({required String name, required List<int> bytes}) =>
      _HomeExportFile._(name: name, bytes: bytes);

  factory _HomeExportFile.temp({required String name, required String tempPath}) =>
      _HomeExportFile._(name: name, tempPath: tempPath);

  final String name;
  final List<int>? bytes;
  final String? tempPath;
}

Uint8List _encodeHomeExportZip(List<_HomeExportFile> files) {
  final archive = Archive();
  for (final file in files) {
    final List<int> data;
    if (file.bytes != null) {
      data = file.bytes!;
    } else {
      data = File(file.tempPath!).readAsBytesSync();
    }
    archive.addFile(ArchiveFile(file.name, data.length, data));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Future<Uint8List> _encodeHomeExportZipAsync(List<_HomeExportFile> files) async {
  var total = 0;
  for (final f in files) {
    if (f.bytes != null) {
      total += f.bytes!.length;
    } else {
      total += await File(f.tempPath!).length();
    }
  }
  const threshold = 128 * 1024;
  if (total >= threshold) {
    return Isolate.run(() => _encodeHomeExportZip(files));
  }
  return compute(_encodeHomeExportZip, files);
}

class ExportNoteButton extends StatefulWidget {
  const ExportNoteButton({
    super.key,
    required this.selectedFiles,
    required this.exportHostContext,
    this.onExportStarted,
  });

  final List<String> selectedFiles;

  /// Must stay mounted after [onExportStarted] clears selection (e.g. page
  /// [State]'s [BuildContext], not this button's).
  final BuildContext exportHostContext;

  /// Called once export is committed (dialogs done, path valid) and background export begins.
  final VoidCallback? onExportStarted;

  @override
  State<ExportNoteButton> createState() => _ExportNoteButtonState();
}

class _ExportNoteButtonState extends State<ExportNoteButton> {
  var _currentlyExporting = false;

  Future exportFile(
    List<String> selectedFiles,
    bool exportPdf, {
    required BuildContext context,
  }) async {
    setState(() => _currentlyExporting = true);

    final files = <_HomeExportFile>[];
    String? sharedPassword;
    bool shareLinks = false;
    var includeExportMetadata = true;
    bool hasExternalLinks = false;
    if (selectedFiles.length == 1) {
      try {
        final first = await EditorCoreInfo.loadFromFilePath(
          selectedFiles.first,
        );
        hasExternalLinks = first.links.any(
          (l) => isExternalNoteLink(l, first.filePath),
        );
      } catch (_) {}
    }
    if (!exportPdf) {
      final mode = await showSbaExportModeDialog(
        context,
        hasExternalLinks: hasExternalLinks,
      );
      if (!mode.ok || !context.mounted) {
        if (mounted) setState(() => _currentlyExporting = false);
        return;
      }
      sharedPassword = mode.password;
      shareLinks = mode.shareLinks;
      includeExportMetadata = mode.includeExportMetadata;
    } else if (hasExternalLinks) {
      final mode = await showSbaExportModeDialog(
        context,
        hasExternalLinks: true,
        encryptionApplicable: false,
      );
      if (!mode.ok || !context.mounted) {
        if (mounted) setState(() => _currentlyExporting = false);
        return;
      }
      shareLinks = mode.shareLinks;
    }

    if (shareLinks && stows.defaultExportPath.value.isEmpty) {
      setState(() => _currentlyExporting = false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.export.defaultExportPathRequired)),
        );
      }
      return;
    }

    final saveToPath = stows.defaultExportPath.value.isNotEmpty
        ? stows.defaultExportPath.value
        : null;

    final screenshotContext = Navigator.of(
      context,
      rootNavigator: true,
    ).overlay?.context;

    Future<void> doExport(
      String? saveToPathArg,
      void Function(double progress, String message) onProgress,
    ) async {
      // Use [context] (host scaffold), not [State.mounted]: [onExportStarted]
      // clears selection and removes this widget while export still runs.
      if (!context.mounted) return;

      final filesToExport = List<String>.from(selectedFiles);
      for (var i = 0; i < filesToExport.length; i++) {
        final filePath = filesToExport[i];
        var coreInfo = await EditorCoreInfo.loadFromFilePath(filePath);
        if (!context.mounted) break;

        if (!exportPdf && shareLinks) {
          coreInfo = await expandLinksForShare(coreInfo, true);
          if (!context.mounted) break;
        }

        final fileNameWithoutExtension = coreInfo.filePath.substring(
          coreInfo.filePath.lastIndexOf('/') + 1,
        );

        if (exportPdf) {
          final ctxForPdf = screenshotContext ?? context;
          if (!ctxForPdf.mounted) break;
          final pdfData = await EditorExporter.generatePdfData(
            coreInfo,
            ctxForPdf,
            invert: getEffectiveNoteInvertInDarkModeForFile(coreInfo.filePath),
            shareLinks: shareLinks && hasExternalLinks,
            onProgress: (done, total) {
              final fileBase = i / filesToExport.length;
              final fileSpan = 0.8 / filesToExport.length;
              onProgress(
                0.05 + fileBase * 0.8 + fileSpan * (done / total),
                '$fileNameWithoutExtension.pdf',
              );
            },
          );
          await Future<void>.delayed(Duration.zero);
          if (pdfData.tempPdfPath != null) {
            files.add(
              _HomeExportFile.temp(
                name: '$fileNameWithoutExtension.pdf',
                tempPath: pdfData.tempPdfPath!,
              ),
            );
          } else {
            files.add(
              _HomeExportFile.bytes(
                name: '$fileNameWithoutExtension.pdf',
                bytes: pdfData.bytes!,
              ),
            );
          }
        } else {
          var sba = await coreInfo.saveToSba(
            currentPageIndex: null,
            omitLinksForExport: !shareLinks,
            includeExportMetadata: includeExportMetadata,
          );
          if (sharedPassword != null) {
            sba = await SbaEncryption.encryptForExport(
              Uint8List.fromList(sba),
              sharedPassword,
            );
          }
          files.add(
            _HomeExportFile.bytes(
              name: '$fileNameWithoutExtension.sba',
              bytes: sba,
            ),
          );
        }
        onProgress(
          0.05 + 0.85 * ((i + 1) / filesToExport.length),
          fileNameWithoutExtension,
        );
        await Future<void>.delayed(Duration.zero);
      }

      if (!context.mounted) return;
      if (files.length == 1) {
        final f = files.first;
        if (f.tempPath != null) {
          await FileManager.exportPdfTempFile(
            f.tempPath!,
            f.name,
            saveToPath: saveToPathArg,
            context: context,
          );
        } else {
          await FileManager.exportFile(
            f.name,
            f.bytes!,
            saveToPath: saveToPathArg,
            context: context,
          );
        }
      } else if (files.length > 1) {
        final zipFileName = '${files.first.name}.zip';
        try {
          final zipBytes = await _encodeHomeExportZipAsync(files);
          await FileManager.exportFile(
            zipFileName,
            zipBytes,
            saveToPath: saveToPathArg,
            context: context,
          );
        } finally {
          for (final f in files) {
            if (f.tempPath != null) {
              try {
                await File(f.tempPath!).delete();
              } catch (_) {}
            }
          }
        }
      }
    }

    try {
      widget.onExportStarted?.call();
      if (saveToPath != null) {
        await ExportManager.exportInBackground(t.export.exportingNote, (
          onProgress,
        ) async {
          onProgress(
            0.05,
            selectedFiles.length == 1
                ? (exportPdf ? '*.pdf' : '*.sba')
                : '*.zip',
          );
          await doExport(saveToPath, onProgress);
          onProgress(1.0, t.export.exportComplete);
        });
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(t.export.exportComplete)));
        }
      } else {
        await ExportManager.exportInBackground(t.export.exportingNote, (
          onProgress,
        ) async {
          await doExport(null, onProgress);
          onProgress(1.0, t.export.exportComplete);
        });
      }
    } finally {
      if (mounted) setState(() => _currentlyExporting = false);
    }
  }

  void _showExportOptions() {
    // Use [exportHostContext] so export survives [onExportStarted] removing this button.
    final hostContext = widget.exportHostContext;
    final theme = Theme.of(hostContext);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    showDialog(
      context: hostContext,
      builder: (ctx) => Dialog(
        backgroundColor: colorScheme.surfaceContainerHigh,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(24),
          child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t.home.tooltips.exportNote,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  _buildOptionBtn(
                    context: ctx,
                    icon: CupertinoIcons.doc_text,
                    label: 'Export as PDF',
                    onTap: () {
                      Navigator.pop(ctx);
                      exportFile(widget.selectedFiles, true, context: hostContext);
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildOptionBtn(
                    context: ctx,
                    icon: Icons.note,
                    label: 'Export as SBA',
                    onTap: () {
                      Navigator.pop(ctx);
                      exportFile(widget.selectedFiles, false, context: hostContext);
                    },
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(t.common.cancel),
                  ),
                ],
              ),
            ),
          ),
        );
  }

  Widget _buildOptionBtn({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: colorScheme.primary),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentlyExporting) {
      return AdaptiveCircularProgressIndicator.textStyled();
    }

    return IconButton(
      tooltip: t.home.tooltips.exportNote,
      icon: const Icon(Icons.share),
      onPressed: _showExportOptions,
    );
  }
}
