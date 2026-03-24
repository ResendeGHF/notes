// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf_combiner/pdf_combiner.dart';
import 'package:saber/components/editor/sba_export_dialog.dart';
import 'package:saber/components/navbar/horizontal_navbar.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:saber/services/vault_adapter.dart';

class NewNoteButton extends StatefulWidget {
  const NewNoteButton({super.key, required this.cupertino, this.path});

  final bool cupertino;
  final String? path;

  @override
  State<NewNoteButton> createState() => _NewNoteButtonState();
}

class _NewNoteButtonState extends State<NewNoteButton> {
  final ValueNotifier<bool> isDialOpen = ValueNotifier(false);

  Future<bool?> _showMergeDialog(BuildContext context, int count) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(t.home.importPdf),
        content: Text(t.home.pdfFilesSelected(count: count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.home.mergeIntoOne),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(t.home.separateNotes),
          ),
        ],
      ),
    );
  }

  Future<String?> _mergePdfsAndSave(List<String> paths) async {
    if (paths.isEmpty) return null;

    try {
      final outputDir = await getTemporaryDirectory();

      final outputPath =
          '${outputDir.path}/merged_${DateTime.now().millisecondsSinceEpoch}.pdf';

      final result = await PdfCombiner.mergeMultiplePDFs(
        inputPaths: paths,
        outputPath: outputPath,
      );

      final file = File(outputPath);
      if (await file.exists()) {
        return outputPath;
      } else {
        debugPrint('Merge failed: File not created or null response.: $result');
        return null;
      }
    } catch (e) {
      debugPrint('Error merging PDFs with pdf_combiner: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final materialBorderRadius = BorderRadius.circular(16);
    return SpeedDial(
      spacing: 3,
      mini: true,
      openCloseDial: isDialOpen,
      childPadding: const EdgeInsets.all(
        5,
      ),
      spaceBetweenChildren: 4,
      switchLabelPosition: Directionality.of(context) == TextDirection.rtl,
      shape: widget.cupertino
          ? const CircleBorder()
          : RoundedRectangleBorder(borderRadius: materialBorderRadius),
      dialRoot: (context, open, toggleChildren) {
        final platform = Theme.of(context).platform;
        return GlassyContainer(
          height: 56,
          borderRadius:
              platform == TargetPlatform.iOS || platform == TargetPlatform.macOS
              ? null
              : materialBorderRadius,
          child: AspectRatio(
            aspectRatio: 1,
            child: IconButton(
              onPressed: toggleChildren,
              tooltip: t.home.tooltips.newNote,
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                padding: EdgeInsets.zero,
                shape:
                    (platform == TargetPlatform.iOS ||
                        platform == TargetPlatform.macOS)
                    ? const CircleBorder()
                    : RoundedRectangleBorder(
                        borderRadius: materialBorderRadius,
                      ),
              ),
              icon: const Center(child: Icon(Icons.add)),
            ),
          ),
        );
      },
      children: [
        SpeedDialChild(
          child: const Icon(Icons.create),
          label: t.home.create.newNote,
          onTap: () async {
            isDialOpen.value = false;

            if (widget.path == null) {
              context.push(RoutePaths.edit);
            } else {
              final newFilePath = await FileManager.newFilePath(
                '${widget.path}/',
              );

              if (!context.mounted) return;
              context.push(RoutePaths.editFilePath(newFilePath));
            }
          },
        ),
        SpeedDialChild(
          child: const Icon(Icons.note_add),
          label: t.home.create.importNote,
          onTap: () async {
            if (ExportManager.status.value.isExporting) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(t.export.importAfterExportDone)),
                );
              }
              return;
            }
            VaultAdapter.preventLock = true;
            FilePickerResult? result;
            try {
              result = await FilePicker.platform.pickFiles(
                type: FileType.any,
                allowMultiple: true,
                withData: false,
                onFileLoading: (FilePickerStatus status) {
                  if (status == FilePickerStatus.picking) {
                    ImportManager.status.value = const ImportStatus(
                      isImporting: true,
                      isParsing: true,
                    );
                  }
                },
              );
            } finally {
              VaultAdapter.preventLock = false;
            }

            if (result == null || result.files.isEmpty) {
              ImportManager.status.value = const ImportStatus();
              return;
            }

            isDialOpen.value = false;

            ImportManager.status.value = const ImportStatus(
              isImporting: true,
              isParsing: true,
            );
            await Future.delayed(const Duration(milliseconds: 100));

            final files = result.files.where((f) => f.path != null).toList();
            if (files.isEmpty) {
              ImportManager.status.value = const ImportStatus();
              return;
            }

            final pdfFiles = files
                .where((f) => f.path!.toLowerCase().endsWith('.pdf'))
                .toList();
            final otherFiles = files
                .where((f) => !f.path!.toLowerCase().endsWith('.pdf'))
                .toList();

            final themeData = Theme.of(context);
            final mediaQueryData = MediaQuery.of(context);

            if (pdfFiles.isNotEmpty) {
              if (!Editor.canRasterPdf) {
                ImportManager.status.value = const ImportStatus();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(t.home.deviceNoPdfImport)),
                  );
                }
                return;
              }

              bool shouldMerge = false;
              bool isMultiple = pdfFiles.length > 1;

              if (isMultiple) {
                ImportManager.status.value =
                    const ImportStatus();
                if (!context.mounted) return;
                final bool? userChoice = await _showMergeDialog(
                  context,
                  pdfFiles.length,
                );
                if (userChoice == null) return;
                shouldMerge = userChoice;

                ImportManager.status.value = const ImportStatus(
                  isImporting: true,
                  isParsing: true,
                );
                await Future.delayed(const Duration(milliseconds: 100));
              }

              try {
                if (shouldMerge && isMultiple) {
                  ImportManager.status.value = const ImportStatus(
                    isImporting: true,
                    fileName: "Merging files...",
                    countText: "Processing",
                  );

                  final paths = pdfFiles.map((e) => e.path!).toList();
                  final mergedPdfPath = await _mergePdfsAndSave(paths);

                  if (mergedPdfPath != null) {
                    final firstFileName = pdfFiles.first.name;
                    final fileNameWithoutExtension = firstFileName.substring(
                      0,
                      firstFileName.length - '.pdf'.length,
                    );

                    final sbnFilePath =
                        await FileManager.suffixFilePathToMakeItUnique(
                          '${widget.path ?? ''}/$fileNameWithoutExtension (Merged)',
                        );

                    await FileManager.generateThumbnailFromPdf(
                      mergedPdfPath,
                      '$sbnFilePath${Editor.extension}.p',
                    );

                    ImportManager.status.value = const ImportStatus();
                    if (context.mounted) {
                      context.push(
                        RoutePaths.editImportPdf(sbnFilePath, mergedPdfPath),
                      );
                    }
                  } else {
                    ImportManager.status.value = const ImportStatus();
                  }
                } else if (isMultiple) {
                  int successCount = 0;
                  int total = pdfFiles.length;

                  for (int i = 0; i < total; i++) {
                    final file = pdfFiles[i];

                    ImportManager.status.value = ImportStatus(
                      isImporting: true,
                      fileName: file.name,
                      countText: "${i + 1}/$total",
                      progress: (i + 1) / total,
                    );
                    await Future.delayed(Duration.zero);

                    final name = file.name.substring(
                      0,
                      file.name.length - '.pdf'.length,
                    );
                    final sbnFilePath =
                        await FileManager.suffixFilePathToMakeItUnique(
                          '${widget.path ?? ''}/$name',
                        );

                    final success = await FileManager.createNoteFromPdf(
                      sbnFilePath,
                      file.path!,
                      theme: themeData,
                      mediaQuery: mediaQueryData,
                    );

                    if (success) successCount++;
                  }

                  ImportManager.status.value = const ImportStatus();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '$successCount notes imported successfully.',
                        ),
                      ),
                    );
                  }
                } else {
                  final file = pdfFiles.first;
                  final name = file.name.substring(
                    0,
                    file.name.length - '.pdf'.length,
                  );

                  ImportManager.status.value = ImportStatus(
                    isImporting: true,
                    fileName: file.name,
                    countText: "1/1",
                    progress: 1.0,
                  );
                  await Future.delayed(Duration.zero);

                  final sbnFilePath =
                      await FileManager.suffixFilePathToMakeItUnique(
                        '${widget.path ?? ''}/$name',
                      );

                  await FileManager.createNoteFromPdf(
                    sbnFilePath,
                    file.path!,
                    theme: themeData,
                    mediaQuery: mediaQueryData,
                  );

                  ImportManager.status.value = const ImportStatus();
                  if (context.mounted) {
                    context.push(RoutePaths.editFilePath(sbnFilePath));
                  }
                }
              } catch (e) {
                ImportManager.status.value = const ImportStatus();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(t.home.errorImporting(error: e))),
                  );
                }
              }
            }

            if (otherFiles.isNotEmpty) {
              int count = 0;
              String? lastImportedPath;

              for (int i = 0; i < otherFiles.length; i++) {
                final file = otherFiles[i];
                ImportManager.status.value = ImportStatus(
                  isImporting: true,
                  fileName: file.name,
                  countText: "${i + 1}/${otherFiles.length}",
                  progress: (i + 1) / otherFiles.length,
                );
                await Future.delayed(Duration.zero);

                final filePath = file.path!;
                if (filePath.toLowerCase().endsWith('.sbn') ||
                    filePath.toLowerCase().endsWith('.sbn2') ||
                    filePath.toLowerCase().endsWith('.sba')) {
                  final importedPath = await FileManager.importFile(
                    filePath,
                    '${widget.path ?? ''}/',
                    theme: themeData,
                    mediaQuery: mediaQueryData,
                    getEncryptionPassword:
                        filePath.toLowerCase().endsWith('.sba')
                        ? () async {
                            if (!context.mounted) return null;
                            return showSbaImportPasswordDialog(context);
                          }
                        : null,
                  );

                  if (importedPath != null) {
                    count++;
                    lastImportedPath = importedPath;
                  }
                }
              }

              ImportManager.status.value = const ImportStatus();

              if (otherFiles.length == 1 && lastImportedPath != null) {
                if (context.mounted) {
                  context.push(RoutePaths.editFilePath(lastImportedPath));
                }
              } else if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(t.home.filesImported(count: count))),
                );
              }
            }
          },
        ),
      ],
    );
  }
}

class ImportStatus {
  final bool isImporting;
  final String fileName;
  final String countText;
  final double? progress;
  final bool isParsing;

  const ImportStatus({
    this.isImporting = false,
    this.fileName = '',
    this.countText = '',
    this.progress,
    this.isParsing = false,
  });
}

class ImportManager {
  static final ValueNotifier<ImportStatus> status = ValueNotifier(
    const ImportStatus(),
  );
}
