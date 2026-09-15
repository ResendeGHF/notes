// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf_combiner/models/merge_input.dart';
import 'package:pdf_combiner/pdf_combiner.dart';
import 'package:saber/components/editor/sba_export_dialog.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:saber/services/background_operation_queue.dart';
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

  Future<void> _closeDialBeforeNavigation() async {
    isDialOpen.value = false;
    await WidgetsBinding.instance.endOfFrame;
    // flutter_speed_dial removes its touch-catching overlay asynchronously.
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

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
        inputs: paths.map((p) => MergeInput.path(p)).toList(),
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
    final originalTheme = Theme.of(context);

    return Theme(
      data: originalTheme.copyWith(
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        focusColor: Colors.transparent,
      ),
     child: Padding(
        padding: const EdgeInsets.only(right: 16.0, bottom: 16.0),
        child: SpeedDial(
          spacing: 12,
          spaceBetweenChildren: 8,
          renderOverlay: false,
          elevation: 0,
          openCloseDial: isDialOpen,
          switchLabelPosition: Directionality.of(context) == TextDirection.rtl,
          childrenButtonSize: Size.zero,
          dialRoot: (context, open, toggleChildren) {
            final colorScheme = Theme.of(context).colorScheme;

            final double size = open ? 56.0 : 72.0;
            final double borderRadius = open ? 16.0 : 22.0;

            return Theme(
              data: originalTheme,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                height: size,
                width: size,
                decoration: BoxDecoration(
                  color: open
                      ? colorScheme.surfaceContainerHigh
                      : colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(borderRadius),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withValues(alpha: open ? 0.1 : 0.15),
                      blurRadius: open ? 4 : 8,
                      offset: Offset(0, open ? 2 : 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: toggleChildren,
                    borderRadius: BorderRadius.circular(borderRadius),
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        switchInCurve: Curves.easeOutBack,
                        switchOutCurve: Curves.easeInBack,
                        transitionBuilder: (Widget child, Animation<double> animation) {
                          return RotationTransition(
                            turns: Tween<double>(begin: 0.5, end: 1.0).animate(animation),
                            child: ScaleTransition(scale: animation, child: child),
                          );
                        },
                        child: open
                            ? Icon(
                                Icons.close,
                                key: const ValueKey('close'),
                                size: 24.0,
                                color: colorScheme.onSurfaceVariant,
                              )
                            : Icon(
                                Icons.add_rounded,
                                key: const ValueKey('add'),
                                size: 36.0,
                                color: colorScheme.onPrimaryContainer,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
          children: [
            SpeedDialChild(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: const Offstage(),
              labelWidget: Theme(
                data: originalTheme,
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: Material(
                    elevation: 1,
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    shadowColor: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.2),
                    shape: const StadiumBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () async {
                        await _closeDialBeforeNavigation();
                        if (!context.mounted) return;

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
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.edit_outlined,
                              size: 20,
                              color: Theme.of(context).colorScheme.onSecondaryContainer,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              t.home.create.newNote,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Theme.of(context).colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              onTap: () async {
                await _closeDialBeforeNavigation();
                if (!context.mounted) return;

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
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: const Offstage(),
              labelWidget: Theme(
                data: originalTheme,
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: Material(
                    elevation: 1,
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    shadowColor: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.2),
                    shape: const StadiumBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () async {
                        VaultAdapter.preventLock = true;
                        List<PlatformFile>? filesResult;
                        try {
                          filesResult = await FilePicker.pickFiles(
                            type: FileType.any,
                          );
                        } finally {
                          VaultAdapter.preventLock = false;
                        }

                        if (filesResult == null || filesResult.isEmpty) return;

                        isDialOpen.value = false;

                        final files = filesResult.where((f) => f.path != null).toList();
                        if (files.isEmpty) return;

                        if (!context.mounted) return;
                        final scaffoldCtx = context;
                        final router = GoRouter.of(scaffoldCtx);
                        final themeData = Theme.of(scaffoldCtx);
                        final mediaQueryData = MediaQuery.of(scaffoldCtx);

                        await BackgroundOperationQueue.instance.enqueue<void>(
                          kind: BackgroundOperationKind.importFile,
                          headline: t.home.create.importNote,
                          initialDetail: t.home.create.importNote,
                          work: (onProgress) async {
                            final pdfFiles = files
                                .where((f) => f.path!.toLowerCase().endsWith('.pdf'))
                                .toList();
                            final otherFiles = files
                                .where((f) => !f.path!.toLowerCase().endsWith('.pdf'))
                                .toList();

                            if (pdfFiles.isNotEmpty) {
                              if (!Editor.canRasterPdf) {
                                if (scaffoldCtx.mounted) {
                                  ScaffoldMessenger.of(scaffoldCtx).showSnackBar(
                                    SnackBar(content: Text(t.home.deviceNoPdfImport)),
                                  );
                                }
                                return;
                              }

                              bool shouldMerge = false;
                              final bool isMultiple = pdfFiles.length > 1;

                              if (isMultiple) {
                                onProgress(0, t.home.importPdf, indeterminate: true);
                                if (!scaffoldCtx.mounted) return;
                                final bool? userChoice = await _showMergeDialog(
                                  scaffoldCtx,
                                  pdfFiles.length,
                                );
                                if (userChoice == null) return;
                                shouldMerge = userChoice;

                                onProgress(0, t.home.importPdf, indeterminate: true);
                                await Future<void>.delayed(
                                  const Duration(milliseconds: 100),
                                );
                              }

                              try {
                                if (shouldMerge && isMultiple) {
                                  onProgress(0, 'Merging PDFs', indeterminate: true);

                                  final paths = pdfFiles.map((e) => e.path!).toList();
                                  final mergedPdfPath = await _mergePdfsAndSave(paths);

                                  if (mergedPdfPath != null) {
                                    final firstFileName = pdfFiles.first.name;
                                    final fileNameWithoutExtension = firstFileName
                                        .substring(0, firstFileName.length - '.pdf'.length);

                                    final sbnFilePath =
                                        await FileManager.suffixFilePathToMakeItUnique(
                                          '${widget.path ?? ''}/$fileNameWithoutExtension (Merged)',
                                        );

                                    await FileManager.generateThumbnailFromPdf(
                                      mergedPdfPath,
                                      '$sbnFilePath${Editor.extension}.p',
                                    );

                                    onProgress(1, firstFileName, indeterminate: false);
                                    if (scaffoldCtx.mounted) {
                                      router.push(
                                        RoutePaths.editImportPdf(
                                          sbnFilePath,
                                          mergedPdfPath,
                                        ),
                                      );
                                    }
                                  }
                                } else if (isMultiple) {
                                  int successCount = 0;
                                  final int total = pdfFiles.length;

                                  for (int i = 0; i < total; i++) {
                                    final file = pdfFiles[i];

                                    onProgress(
                                      (i + 1) / total,
                                      '${i + 1}/$total · ${file.name}',
                                    );
                                    await Future<void>.delayed(Duration.zero);

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
                                      onImportProgress: (p, status) {
                                        onProgress(
                                          (i + p) / total,
                                          '${i + 1}/$total · $status',
                                        );
                                      },
                                    );

                                    if (success) successCount++;
                                  }

                                  if (scaffoldCtx.mounted) {
                                    ScaffoldMessenger.of(scaffoldCtx).showSnackBar(
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

                                  final sbnFilePath =
                                      await FileManager.suffixFilePathToMakeItUnique(
                                        '${widget.path ?? ''}/$name',
                                      );

                                  await FileManager.createNoteFromPdf(
                                    sbnFilePath,
                                    file.path!,
                                    theme: themeData,
                                    mediaQuery: mediaQueryData,
                                    onImportProgress: onProgress,
                                  );

                                  if (scaffoldCtx.mounted) {
                                    router.push(RoutePaths.editFilePath(sbnFilePath));
                                  }
                                }
                              } catch (e) {
                                if (scaffoldCtx.mounted) {
                                  ScaffoldMessenger.of(scaffoldCtx).showSnackBar(
                                    SnackBar(
                                      content: Text(t.home.errorImporting(error: e)),
                                    ),
                                  );
                                }
                              }
                            }

                            if (otherFiles.isNotEmpty) {
                              int count = 0;
                              String? lastImportedPath;

                              for (int i = 0; i < otherFiles.length; i++) {
                                final file = otherFiles[i];
                                onProgress(
                                  (i + 1) / otherFiles.length,
                                  '${i + 1}/${otherFiles.length} · ${file.name}',
                                );
                                await Future<void>.delayed(Duration.zero);

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
                                            if (!scaffoldCtx.mounted) return null;
                                            return showSbaImportPasswordDialog(scaffoldCtx);
                                          }
                                        : null,
                                  );

                                  if (importedPath != null) {
                                    count++;
                                    lastImportedPath = importedPath;
                                  }
                                }
                              }

                              if (otherFiles.length == 1 && lastImportedPath != null) {
                                if (scaffoldCtx.mounted) {
                                  router.push(RoutePaths.editFilePath(lastImportedPath!));
                                }
                              } else if (scaffoldCtx.mounted) {
                                ScaffoldMessenger.of(scaffoldCtx).showSnackBar(
                                  SnackBar(
                                    content: Text(t.home.filesImported(count: count)),
                                  ),
                                );
                              }
                            }
                          },
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.upload_file_rounded,
                              size: 20,
                              color: Theme.of(context).colorScheme.onSecondaryContainer,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              t.home.create.importNote,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Theme.of(context).colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              onTap: () async {
                VaultAdapter.preventLock = true;
                List<PlatformFile>? filesResult;
                try {
                  filesResult = await FilePicker.pickFiles(
                    type: FileType.any,
                  );
                } finally {
                  VaultAdapter.preventLock = false;
                }

                if (filesResult == null || filesResult.isEmpty) return;

                isDialOpen.value = false;

                final files = filesResult.where((f) => f.path != null).toList();
                if (files.isEmpty) return;

                if (!context.mounted) return;
                final scaffoldCtx = context;
                final router = GoRouter.of(scaffoldCtx);
                final themeData = Theme.of(scaffoldCtx);
                final mediaQueryData = MediaQuery.of(scaffoldCtx);

                await BackgroundOperationQueue.instance.enqueue<void>(
                  kind: BackgroundOperationKind.importFile,
                  headline: t.home.create.importNote,
                  initialDetail: t.home.create.importNote,
                  work: (onProgress) async {
                    final pdfFiles = files
                        .where((f) => f.path!.toLowerCase().endsWith('.pdf'))
                        .toList();
                    final otherFiles = files
                        .where((f) => !f.path!.toLowerCase().endsWith('.pdf'))
                        .toList();

                    if (pdfFiles.isNotEmpty) {
                      if (!Editor.canRasterPdf) {
                        if (scaffoldCtx.mounted) {
                          ScaffoldMessenger.of(scaffoldCtx).showSnackBar(
                            SnackBar(content: Text(t.home.deviceNoPdfImport)),
                          );
                        }
                        return;
                      }

                      bool shouldMerge = false;
                      final bool isMultiple = pdfFiles.length > 1;

                      if (isMultiple) {
                        onProgress(0, t.home.importPdf, indeterminate: true);
                        if (!scaffoldCtx.mounted) return;
                        final bool? userChoice = await _showMergeDialog(
                          scaffoldCtx,
                          pdfFiles.length,
                        );
                        if (userChoice == null) return;
                        shouldMerge = userChoice;

                        onProgress(0, t.home.importPdf, indeterminate: true);
                        await Future<void>.delayed(
                          const Duration(milliseconds: 100),
                        );
                      }

                      try {
                        if (shouldMerge && isMultiple) {
                          onProgress(0, 'Merging PDFs', indeterminate: true);

                          final paths = pdfFiles.map((e) => e.path!).toList();
                          final mergedPdfPath = await _mergePdfsAndSave(paths);

                          if (mergedPdfPath != null) {
                            final firstFileName = pdfFiles.first.name;
                            final fileNameWithoutExtension = firstFileName
                                .substring(0, firstFileName.length - '.pdf'.length);

                            final sbnFilePath =
                                await FileManager.suffixFilePathToMakeItUnique(
                                  '${widget.path ?? ''}/$fileNameWithoutExtension (Merged)',
                                );

                            await FileManager.generateThumbnailFromPdf(
                              mergedPdfPath,
                              '$sbnFilePath${Editor.extension}.p',
                            );

                            onProgress(1, firstFileName, indeterminate: false);
                            if (scaffoldCtx.mounted) {
                              router.push(
                                RoutePaths.editImportPdf(
                                  sbnFilePath,
                                  mergedPdfPath,
                                ),
                              );
                            }
                          }
                        } else if (isMultiple) {
                          int successCount = 0;
                          final int total = pdfFiles.length;

                          for (int i = 0; i < total; i++) {
                            final file = pdfFiles[i];

                            onProgress(
                              (i + 1) / total,
                              '${i + 1}/$total · ${file.name}',
                            );
                            await Future<void>.delayed(Duration.zero);

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
                              onImportProgress: (p, status) {
                                onProgress(
                                  (i + p) / total,
                                  '${i + 1}/$total · $status',
                                );
                              },
                            );

                            if (success) successCount++;
                          }

                          if (scaffoldCtx.mounted) {
                            ScaffoldMessenger.of(scaffoldCtx).showSnackBar(
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

                          final sbnFilePath =
                              await FileManager.suffixFilePathToMakeItUnique(
                                '${widget.path ?? ''}/$name',
                              );

                          await FileManager.createNoteFromPdf(
                            sbnFilePath,
                            file.path!,
                            theme: themeData,
                            mediaQuery: mediaQueryData,
                            onImportProgress: onProgress,
                          );

                          if (scaffoldCtx.mounted) {
                            router.push(RoutePaths.editFilePath(sbnFilePath));
                          }
                        }
                      } catch (e) {
                        if (scaffoldCtx.mounted) {
                          ScaffoldMessenger.of(scaffoldCtx).showSnackBar(
                            SnackBar(
                              content: Text(t.home.errorImporting(error: e)),
                            ),
                          );
                        }
                      }
                    }

                    if (otherFiles.isNotEmpty) {
                      int count = 0;
                      String? lastImportedPath;

                      for (int i = 0; i < otherFiles.length; i++) {
                        final file = otherFiles[i];
                        onProgress(
                          (i + 1) / otherFiles.length,
                          '${i + 1}/${otherFiles.length} · ${file.name}',
                        );
                        await Future<void>.delayed(Duration.zero);

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
                                    if (!scaffoldCtx.mounted) return null;
                                    return showSbaImportPasswordDialog(scaffoldCtx);
                                  }
                                : null,
                          );

                          if (importedPath != null) {
                            count++;
                            lastImportedPath = importedPath;
                          }
                        }
                      }

                      if (otherFiles.length == 1 && lastImportedPath != null) {
                        if (scaffoldCtx.mounted) {
                          router.push(RoutePaths.editFilePath(lastImportedPath!));
                        }
                      } else if (scaffoldCtx.mounted) {
                        ScaffoldMessenger.of(scaffoldCtx).showSnackBar(
                          SnackBar(
                            content: Text(t.home.filesImported(count: count)),
                          ),
                        );
                      }
                    }
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}