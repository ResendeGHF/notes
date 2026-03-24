// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
import 'package:saber/components/canvas/invert_widget.dart';
import 'package:saber/components/editor/export_dialog.dart';
import 'package:saber/components/home/move_note_button.dart';
import 'package:saber/components/home/rename_note_button.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:saber/services/thumbnail_cache.dart';

class PreviewCard extends StatefulWidget {
  PreviewCard({
    required this.filePath,
    required this.toggleSelection,
    required this.selected,
    required this.isAnythingSelected,
    this.listMode = false,
    this.targetPath,
    this.linkKey,
    this.onDeleteLink,
  }) : super(
         key: ValueKey(
           'PreviewCard${linkKey != null ? "link_$linkKey" : filePath}',
         ),
       );

  final String filePath;
  final bool selected;
  final bool isAnythingSelected;
  final bool listMode;
  final String? targetPath;
  final String? linkKey;
  final Future<void> Function(String)? onDeleteLink;
  final void Function(String, bool) toggleSelection;

  @override
  State<PreviewCard> createState() => _PreviewCardState();
}

class _PreviewCardState extends State<PreviewCard> {
  final expanded = ValueNotifier(false);
  final thumbnail = _ThumbnailState();

  @override
  void initState() {
    fileWriteSubscription = FileManager.fileWriteStream.stream.listen(
      fileWriteListener,
    );

    expanded.value = widget.selected;
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadThumbnailWithRetry();
  }

  @override
  void didUpdateWidget(PreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.selected != widget.selected) {
      expanded.value = widget.selected;
    }

    if (oldWidget.filePath != widget.filePath) {
      _loadThumbnailWithRetry();
    }
  }

  Future<void> _loadThumbnailWithRetry({int retryCount = 0}) async {
    final cache = ThumbnailCache.instance;
    final thumbnailPath = '${widget.filePath}${Editor.extension}.p';

    var bytes = cache.get(widget.filePath);
    if (bytes == null) {
      final read = await FileManager.readFile(
        thumbnailPath,
        retries: 0,
        suppressLogs: true,
        allowMissing: true,
      );
      if (read != null && read.isNotEmpty) {
        cache.put(widget.filePath, read);
      }
      bytes = read;
    }

    if (bytes != null && bytes.isNotEmpty) {
      if (mounted) {
        thumbnail.image = MemoryImage(bytes);
      }
      return;
    }

    if (retryCount < 3 && mounted) {
      Future.delayed(Duration(milliseconds: 500 * (retryCount + 1)), () {
        if (mounted) _loadThumbnailWithRetry(retryCount: retryCount + 1);
      });
    } else if (mounted) {
      thumbnail.image = null;
    }
  }

  StreamSubscription? fileWriteSubscription;
  void fileWriteListener(FileOperation event) {
    if (event.filePath != widget.filePath) return;
    if (event.type == FileOperationType.delete) {
      ThumbnailCache.instance.invalidate(widget.filePath);
      thumbnail.image = null;
    } else if (event.type == FileOperationType.write) {
      thumbnail.image?.evict();
      ThumbnailCache.instance.invalidate(widget.filePath);
      _loadThumbnailWithRetry();
    } else {

    }
  }

  void _toggleCardSelection() {
    final newSelected = !widget.selected;
    expanded.value = newSelected;
    widget.toggleSelection(widget.filePath, newSelected);
  }

  void _showContextMenu() async {
    final isLink = widget.linkKey != null;
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    final String? action = await showMenu<String>(
      context: context,
      position: position,
      items: isLink
          ? [
              const PopupMenuItem(
                value: 'go_to_file',
                child: ListTile(
                  leading: Icon(Icons.folder_open_outlined),
                  title: Text('Go to file'),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'remove_link',
                child: ListTile(
                  leading: Icon(Icons.link_off, color: Colors.red),
                  title: Text(
                    'Remove link',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ),
            ]
          : [
              PopupMenuItem(
                value: 'rename',
                child: ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(t.home.renameNote.rename),
                ),
              ),
              PopupMenuItem(
                value: 'duplicate',
                child: ListTile(
                  leading: const Icon(Icons.copy_outlined),
                  title: Text(t.editor.selectionBar.duplicate),
                ),
              ),
              PopupMenuItem(
                value: 'move',
                child: ListTile(
                  leading: const Icon(Icons.drive_file_move_outlined),
                  title: Text(t.home.moveNote.moveNote),
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: Text(t.editor.toolbar.export),
                ),
              ),
              PopupMenuItem(
                value: 'properties',
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(t.home.properties),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: Text(
                    t.home.deleteNote,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
            ],
    );

    if (action == null) return;

    if (!mounted) return;
    switch (action) {
      case 'go_to_file':
        final targetDir = widget.filePath.substring(
          0,
          widget.filePath.lastIndexOf('/'),
        );
        context.go(
          HomeRoutes.browseFilePath(targetDir.isEmpty ? '/' : targetDir),
        );
        break;
      case 'remove_link':
        if (widget.onDeleteLink != null && widget.linkKey != null) {
          await widget.onDeleteLink!(widget.linkKey!);
        }
        break;
      case 'rename':
        showDialog(
          context: context,
          builder: (context) => RenameNoteDialog(
            existingPath: widget.filePath,
            unselectNotes: () {},
          ),
        );
      case 'duplicate':
        await FileManager.duplicateFile(widget.filePath);
      case 'move':
        showDialog(
          context: context,
          builder: (context) => MoveNoteDialog(
            filesToMove: [widget.filePath],
            unselectNotes: () {},
          ),
        );
      case 'export':
        final coreInfo = await EditorCoreInfo.loadFromFilePath(widget.filePath);
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (dialogContext) => ExportDialog(
            coreInfo: coreInfo,
            currentPageIndex: 0,
            parentContext: context,
          ),
        );
      case 'properties':
        final ext =
            (await FileManager.doesFileExist(
              widget.filePath + Editor.extensionOldJson,
            ))
            ? Editor.extensionOldJson
            : Editor.extension;
        final lastModified = await FileManager.lastModified(
          widget.filePath + ext,
        );
        final size = await FileManager.getFileSize(widget.filePath + ext);
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(t.home.properties),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Path: ${widget.filePath}'),
                const SizedBox(height: 8),
                Text('Last Modified: ${lastModified.toString().split('.')[0]}'),
                const SizedBox(height: 8),
                Text('Size: ${(size / 1024).toStringAsFixed(2)} KB'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(t.home.close),
              ),
            ],
          ),
        );
      case 'delete':
        if (isLink && widget.onDeleteLink != null) {
          await widget.onDeleteLink!(widget.linkKey!);
          return;
        }

        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AdaptiveAlertDialog(
            title: Text(t.home.deleteNote),
            content: Text(t.home.deleteNoteConfirm),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(t.common.cancel),
              ),
              CupertinoDialogAction(
                isDestructiveAction: true,
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(t.common.delete),
              ),
            ],
          ),
        );

        if (confirmed ?? false) {
          final ext =
              await FileManager.doesFileExist(
                widget.filePath + Editor.extensionOldJson,
              )
              ? Editor.extensionOldJson
              : Editor.extension;
          await FileManager.deleteFile(widget.filePath + ext);
        }
    }
  }

  Timer? _refreshThumbnailTimer;
  void _refreshThumbnailAfterDelay() {
    _refreshThumbnailTimer?.cancel();
    _refreshThumbnailTimer = Timer(const Duration(milliseconds: 500), () {
      thumbnail.image?.evict();
      thumbnail.markAsChanged();

      _loadThumbnailWithRetry();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final transitionDuration = Duration(
      milliseconds: disableAnimations ? 0 : 300,
    );

    const invert = false;

    final borderColor = widget.selected
        ? colorScheme.primary
        : colorScheme.outlineVariant.withValues(alpha: 0.5);

    const borderWidth = 2.0;

    Widget buildCardContent(VoidCallback openAction) {
      final isLink = widget.linkKey != null;
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.isAnythingSelected
              ? (isLink ? null : _toggleCardSelection)
              : () async {
                  if (widget.targetPath != null) {
                    final target = widget.targetPath!;
                    bool exists =
                        await FileManager.doesFileExist(
                          target + Editor.extension,
                        ) ||
                        await FileManager.doesFileExist(
                          target + Editor.extensionOldJson,
                        );
                    if (!exists) {
                      await FolderLinkManager.showBrokenLinkDialog(context);
                      if (widget.linkKey != null &&
                          widget.onDeleteLink != null) {
                        await widget.onDeleteLink!(widget.linkKey!);
                      }
                      return;
                    }
                  }
                  openAction();
                },
          onSecondaryTap: widget.isAnythingSelected
              ? (isLink ? null : _toggleCardSelection)
              : _showContextMenu,
          onLongPress: isLink ? _showContextMenu : _toggleCardSelection,
          child: widget.listMode
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 44,
                        height: 56,
                        child: ListenableBuilder(
                          listenable: thumbnail,
                          builder: (context, _) => Container(
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: colorScheme.outlineVariant.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InvertWidget(
                              invert: invert,
                              child: AnimatedSwitcher(
                                duration: Duration(
                                  milliseconds: disableAnimations ? 0 : 250,
                                ),
                                switchInCurve: Curves.easeIn,
                                switchOutCurve: Curves.easeOut,
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                                child: thumbnail.doesImageExist
                                    ? Image(
                                        key: ValueKey(
                                          'img_${thumbnail.updateCount}',
                                        ),
                                        image: thumbnail.image!,
                                        fit: BoxFit.cover,
                                      )
                                    : KeyedSubtree(
                                        key: ValueKey(
                                          'fb_${thumbnail.updateCount}',
                                        ),
                                        child: const _FallbackThumbnail(),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          widget.linkKey ??
                              widget.filePath.substring(
                                widget.filePath.lastIndexOf('/') + 1,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(

                            fontWeight: FontWeight.normal,
                            fontSize: 14,

                            color: widget.selected ? colorScheme.primary : null,
                          ),
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, anim) =>
                            ScaleTransition(scale: anim, child: child),
                        child: widget.selected
                            ? Icon(
                                Icons.check_circle,
                                key: const ValueKey('check'),
                                color: colorScheme.primary,
                                size: 20,
                              )
                            : const SizedBox(width: 20, key: ValueKey('empty')),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AspectRatio(
                      aspectRatio: 1 / 1.4,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ListenableBuilder(
                            listenable: thumbnail,
                            builder: (context, _) => DecoratedBox(
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerLowest,
                              ),
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(
                                    kSaberContainerRadius / 1.5,
                                  ),
                                ),
                                child: InvertWidget(
                                  invert: invert,
                                  child: AnimatedSwitcher(
                                    duration: Duration(
                                      milliseconds:
                                          disableAnimations ? 0 : 250,
                                    ),
                                    switchInCurve: Curves.easeIn,
                                    switchOutCurve: Curves.easeOut,
                                    transitionBuilder: (child, animation) =>
                                        FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    ),
                                    child: thumbnail.doesImageExist
                                        ? Image(
                                            key: ValueKey(
                                              'img_${thumbnail.updateCount}',
                                            ),
                                            image: thumbnail.image!,
                                            fit: BoxFit.cover,
                                          )
                                        : KeyedSubtree(
                                            key: ValueKey(
                                              'fb_${thumbnail.updateCount}',
                                            ),
                                            child: const _FallbackThumbnail(),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: AnimatedOpacity(
                                opacity: widget.selected ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutCubic,
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(
                                      kSaberContainerRadius / 1.5,
                                    ),
                                  ),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(
                                      sigmaX: 6,
                                      sigmaY: 6,
                                    ),
                                    child: ColoredBox(
                                      color: colorScheme.surface.withValues(
                                        alpha: 0.3,
                                      ),
                                      child: Center(
                                        child: TweenAnimationBuilder<double>(
                                          tween: Tween<double>(
                                            begin: 0.0,
                                            end: widget.selected ? 1.0 : 0.0,
                                          ),
                                          duration: const Duration(
                                            milliseconds: 400,
                                          ),
                                          curve: Curves.elasticOut,
                                          builder: (context, value, child) {
                                            return Transform.scale(
                                              scale: value,
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: colorScheme.primary,
                                                  shape: BoxShape.circle,
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: colorScheme.primary
                                                          .withValues(
                                                            alpha: 0.4,
                                                          ),
                                                      blurRadius: 12,
                                                      spreadRadius: 2,
                                                    ),
                                                  ],
                                                ),
                                                padding: const EdgeInsets.all(
                                                  8,
                                                ),
                                                child: Icon(
                                                  Icons.check,
                                                  color: colorScheme.onPrimary,
                                                  size: 24,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color.lerp(
                              colorScheme.surfaceContainerLow,
                              colorScheme.surface,
                              0.08,
                            )!,
                            colorScheme.surfaceContainerLow,
                          ],
                        ),
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(kSaberContainerRadius / 1.5),
                        ),
                        border: Border(
                          top: BorderSide(
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.1,
                            ),
                            width: 1,
                          ),
                          left: widget.selected
                              ? BorderSide(
                                  color: colorScheme.primary,
                                  width: 2.5,
                                )
                              : BorderSide.none,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.shadow.withValues(alpha: 0.035),
                            offset: const Offset(0, -1),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                      child: Text(
                        widget.linkKey ??
                            widget.filePath.substring(
                              widget.filePath.lastIndexOf('/') + 1,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          fontSize: 11,
                          letterSpacing: 0.2,
                          height: 1.3,
                          color: widget.selected
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.9,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      );
    }

    String editPath = widget.targetPath ?? widget.filePath;
    if (editPath.endsWith('.sbn2')) {
      editPath = editPath.substring(0, editPath.length - 5);
    } else if (editPath.endsWith('.sbn')) {
      editPath = editPath.substring(0, editPath.length - 4);
    }

    void openAction() async {
      await context.push(RoutePaths.editFilePath(editPath));
      if (mounted) _refreshThumbnailAfterDelay();
    }

    return RepaintBoundary(
      child: AnimatedContainer(
        duration: transitionDuration,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(
            widget.listMode ? 12 : kSaberContainerRadius / 1.5,
          ),
          border: Border.all(
            color: borderColor,
            width: borderWidth,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
          boxShadow: widget.selected
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.25),
                    blurRadius: 16,
                    spreadRadius: 0,
                  ),
                ]
              : [],
        ),
        child: widget.targetPath != null
            ? Stack(
                children: [
                  buildCardContent(openAction),
                  Positioned(
                    bottom: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: colorScheme.surface.withValues(alpha: 0.8),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.shortcut,
                        size: 16,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              )
            : buildCardContent(openAction),
      ),
    );
  }

  @override
  void dispose() {
    _refreshThumbnailTimer?.cancel();
    fileWriteSubscription?.cancel();
    super.dispose();
  }
}

class _FallbackThumbnail extends StatelessWidget {
  const _FallbackThumbnail();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: InnerCanvas.defaultBackgroundColor,
      child: Center(
        child: Text(
          t.home.noPreviewAvailable,
          style: TextTheme.of(context).bodyMedium?.copyWith(
            color: Stroke.defaultColor.withValues(alpha: 0.7),
            fontStyle: FontStyle.italic,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ThumbnailState extends ChangeNotifier {
  var updateCount = 0;
  ImageProvider? _image;

  void markAsChanged() {
    ++updateCount;
    notifyListeners();
  }

  ImageProvider? get image => _image;
  set image(ImageProvider? image) {
    _image = image;
    markAsChanged();
  }

  bool get doesImageExist => _image != null;
}
