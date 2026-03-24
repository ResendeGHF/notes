// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive_io.dart';
import 'package:saber/components/editor/sba_export_dialog.dart';
import 'package:saber/services/sba_encryption.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/theming/adaptive_circular_progress_indicator.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/editor_exporter.dart';
import 'package:saber/data/editor/link_export_expander.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';

class ExportNoteButton extends StatefulWidget {
  const ExportNoteButton({super.key, required this.selectedFiles});

  final List<String> selectedFiles;

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

    final files = <ArchiveFile>[];
    String? sharedPassword;
    bool shareLinks = false;
    var includeExportMetadata = true;
    bool hasExternalLinks = false;
    if (selectedFiles.length == 1) {
      try {
        final first = await EditorCoreInfo.loadFromFilePath(selectedFiles.first);
        hasExternalLinks =
            first.links.any((l) => isExternalNoteLink(l, first.filePath));
      } catch (_) {}
    }
    if (!exportPdf) {
      final mode = await showSbaExportModeDialog(
        context,
        hasExternalLinks: hasExternalLinks,
      );
      if (!mode.ok || !mounted) {
        setState(() => _currentlyExporting = false);
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
      if (!mode.ok || !mounted) {
        setState(() => _currentlyExporting = false);
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

    final screenshotContext = Navigator.of(context, rootNavigator: true)
        .overlay
        ?.context;

    Future<void> doExport(String? saveToPathArg) async {
      final filesToExport = List<String>.from(selectedFiles);
      for (final filePath in filesToExport) {
        var coreInfo = await EditorCoreInfo.loadFromFilePath(filePath);
        if (!mounted) break;

        if (!exportPdf && shareLinks) {
          coreInfo = await expandLinksForShare(coreInfo, true);
          if (!mounted) break;
        }

        final fileNameWithoutExtension = coreInfo.filePath.substring(
          coreInfo.filePath.lastIndexOf('/') + 1,
        );

        if (exportPdf) {

          final ctxForPdf = screenshotContext ?? context;
          if (!ctxForPdf.mounted) break;
          final pdfDoc = await EditorExporter.generatePdf(
            coreInfo,
            ctxForPdf,
            shareLinks: shareLinks && hasExternalLinks,
          );
          final pdfBytes = await pdfDoc.save();
          files.add(
            ArchiveFile(
              '$fileNameWithoutExtension.pdf',
              pdfBytes.length,
              pdfBytes,
            ),
          );
        } else {
          var sba = await coreInfo.saveToSba(
            currentPageIndex: null,
            omitLinksForExport: !shareLinks,
            includeExportMetadata: includeExportMetadata,
          );
          if (sharedPassword != null) {
            sba = SbaEncryption.encrypt(Uint8List.fromList(sba), sharedPassword);
          }
          files.add(
            ArchiveFile('$fileNameWithoutExtension.sba', sba.length, sba),
          );
        }
      }

      if (!mounted) return;
      if (selectedFiles.length == 1) {
        await FileManager.exportFile(
          files.single.name,
          files.single.content,
          saveToPath: saveToPathArg,
          context: context,
        );
      } else if (selectedFiles.length > 1) {
        final archive = Archive();
        for (final archiveFile in files) {
          archive.addFile(archiveFile);
        }
        final zipFileName = '${files.first.name}.zip';
        await FileManager.exportFile(
          zipFileName,
          Uint8List.fromList(ZipEncoder().encode(archive)),
          saveToPath: saveToPathArg,
          context: context,
        );
      }
    }

    try {
      if (saveToPath != null) {
        await ExportManager.exportInBackground(
          t.export.exportingNote,
          (onProgress) async {
            onProgress(0.5, selectedFiles.length == 1
                ? (exportPdf ? '*.pdf' : '*.sba')
                : '*.zip');
            await doExport(saveToPath);
            onProgress(1.0, t.export.exportComplete);
          },
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t.export.exportComplete)),
          );
        }
      } else {
        await doExport(null);
      }
    } finally {
      if (mounted) setState(() => _currentlyExporting = false);
    }
  }

  void _showExportOptions(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              width: 320,
              padding: const EdgeInsets.all(24),
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
              ),
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
                      exportFile(widget.selectedFiles, true, context: context);
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildOptionBtn(
                    context: ctx,
                    icon: Icons.note,
                    label: 'Export as SBA',
                    onTap: () {
                      Navigator.pop(ctx);
                      exportFile(widget.selectedFiles, false, context: context);
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
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
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
      onPressed: () => _showExportOptions(context),
    );
  }
}
