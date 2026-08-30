// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async' show Future, StreamSubscription, Timer;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
import 'package:saber/components/canvas/invert_widget.dart';
import 'package:saber/components/editor/export_dialog.dart';
import 'package:saber/components/home/home_list_meta_formatters.dart';
import 'package:saber/components/home/home_list_row_chrome.dart';
import 'package:saber/components/home/home_toolbar_chrome.dart';
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
    this.showListMetadata = true,
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

  /// When false, list rows show only thumbnail and name (Recent Notes).
  final bool showListMetadata;
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
  NoteListRowStats? _listRowStats;
  bool _listRowStatsLoading = false;

  @override
  void initState() {
    super.initState();
    fileWriteSubscription = FileManager.fileWriteStream.stream.listen(
      fileWriteListener,
    );
    expanded.value = widget.selected;
    _primeThumbnailFromCache();
    _loadThumbnailWithRetry();
    if (widget.listMode && widget.showListMetadata) {
      _loadListRowStats();
    }
  }

  @override
  void didUpdateWidget(PreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.selected != widget.selected) {
      expanded.value = widget.selected;
    }

    if (oldWidget.filePath != widget.filePath) {
      _primeThumbnailFromCache();
      _loadThumbnailWithRetry();
    }

    if (widget.listMode &&
        widget.showListMetadata &&
        (oldWidget.listMode != widget.listMode ||
            oldWidget.showListMetadata != widget.showListMetadata ||
            oldWidget.filePath != widget.filePath ||
            oldWidget.targetPath != widget.targetPath)) {
      _loadListRowStats();
    }
    if ((!widget.listMode || !widget.showListMetadata) &&
        (oldWidget.listMode || oldWidget.showListMetadata)) {
      _listRowStats = null;
      _listRowStatsLoading = false;
    }
  }

  void _primeThumbnailFromCache() {
    final cached = ThumbnailCache.instance.get(widget.filePath);
    if (cached != null && cached.isNotEmpty) {
      thumbnail.setBytes(cached);
    }
  }

  Future<void> _loadThumbnailWithRetry({int retryCount = 0}) async {
    final thumbnailPath = '${widget.filePath}${Editor.extension}.p';

    final bytes = await ThumbnailCache.instance.load(widget.filePath, () {
      return FileManager.readFile(
        thumbnailPath,
        retries: 0,
        suppressLogs: true,
        allowMissing: true,
      );
    });

    if (bytes != null && bytes.isNotEmpty) {
      if (mounted) {
        thumbnail.setBytes(bytes);
      }
      return;
    }

    if (retryCount < 3 && mounted) {
      Future.delayed(Duration(milliseconds: 500 * (retryCount + 1)), () {
        if (mounted) _loadThumbnailWithRetry(retryCount: retryCount + 1);
      });
    }
  }

  StreamSubscription? fileWriteSubscription;
  void fileWriteListener(FileOperation event) {
    if (event.filePath != widget.filePath) return;
    if (event.type == FileOperationType.delete) {
      // Watcher delete (removal == null) is often a rewrite. Do not flash
      // delete chrome or drop the cached thumbnail.
      if (event.removal == null) return;
      ThumbnailCache.instance.invalidate(widget.filePath);
      switch (event.removal) {
        case FileRemovalCause.renamed:
          thumbnail.chrome = _ThumbChrome.renaming;
        case FileRemovalCause.moved:
          thumbnail.chrome = _ThumbChrome.moving;
        case FileRemovalCause.deleted:
        case null:
          thumbnail.chrome = _ThumbChrome.deleting;
      }
    } else if (event.isThumbnail) {
      thumbnail.chrome = _ThumbChrome.none;
      _loadThumbnailWithRetry();
      if (widget.listMode && widget.showListMetadata) {
        _loadListRowStats();
      }
    } else if (event.type == FileOperationType.write) {
      thumbnail.chrome = _ThumbChrome.none;
      if (widget.listMode && widget.showListMetadata) {
        _loadListRowStats();
      }
    }
  }

  Future<void> _loadListRowStats() async {
    if (!widget.listMode || !widget.showListMetadata || !mounted) return;
    final base = widget.targetPath ?? widget.filePath;
    setState(() {
      _listRowStatsLoading = true;
    });
    final stats = await FileManager.getNoteListRowStats(base);
    if (!mounted) return;
    setState(() {
      _listRowStatsLoading = false;
      _listRowStats = stats;
    });
  }

  Widget _buildListStatsMeta(ThemeData theme, ColorScheme colorScheme) {
    final fl = t.home.fileList;

    if (_listRowStatsLoading) {
      return SizedBox(
        height: 26,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary.withValues(alpha: 0.85),
            ),
          ),
        ),
      );
    }
    final s = _listRowStats;
    if (s == null) {
      return const HomeListMetaChip(
        icon: Icons.info_outline_rounded,
        text: 'Metadata unavailable',
        tooltip: 'Metadata unavailable',
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        HomeListMetaChip(
          icon: Icons.sd_storage_outlined,
          text: formatHomeListBytes(s.sizeBytes),
          tooltip: fl.metaSize,
        ),
        HomeListMetaChip(
          icon: Icons.event_note_outlined,
          text: s.created != null
              ? formatHomeListDate(context, s.created!)
              : '—',
          tooltip: 'Created',
        ),
        HomeListMetaChip(
          icon: Icons.edit_calendar_outlined,
          text: s.modified != null
              ? formatHomeListDate(context, s.modified!)
              : '—',
          tooltip: fl.metaModified,
        ),
      ],
    );
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

    final cs = Theme.of(context).colorScheme;
    final String? action = await showMenu<String>(
      context: context,
      position: position,
      elevation: 4,
      color: homeAppBarBackgroundColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kSaberContainerRadius),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.18)),
      ),
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
          builder: (context) => Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.all(24),
            child: RuggedDialogShell(
              maxWidth: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t.home.properties,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText('Path: ${widget.filePath}'),
                  const SizedBox(height: 8),
                  SelectableText(
                    'Last modified: ${lastModified.toString().split('.')[0]}',
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    'Size: ${(size / 1024).toStringAsFixed(2)} KB',
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonal(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(t.home.close),
                    ),
                  ),
                ],
              ),
            ),
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

  Widget _buildThumbnailFace(
    ColorScheme colorScheme, {
    required Duration duration,
    required bool compact,
  }) {
    return ListenableBuilder(
      listenable: thumbnail,
      builder: (context, _) {
        return _ThumbnailFace(
          image: thumbnail.image,
          chrome: thumbnail.chrome,
          duration: duration,
          compact: compact,
        );
      },
    );
  }

  Timer? _refreshThumbnailTimer;
  void _refreshThumbnailAfterDelay() {
    _refreshThumbnailTimer?.cancel();
    _refreshThumbnailTimer = Timer(const Duration(milliseconds: 500), () {
      _loadThumbnailWithRetry();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final transitionDuration = Duration(
      milliseconds: disableAnimations ? 0 : 100,
    );
    final thumbFade = Duration(milliseconds: disableAnimations ? 0 : 320);

    const invert = false;

    final borderColor = widget.listMode
        ? Colors.transparent
        : widget.selected
        ? colorScheme.primary
        : colorScheme.outlineVariant.withValues(alpha: 0.5);

    final borderWidth = widget.listMode ? 0.0 : 2.0;

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
              ? HomeListRowSurface(
                  selected: widget.selected,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 68,
                        height: 84,
                        child: ListenableBuilder(
                          listenable: thumbnail,
                          builder: (context, _) => DecoratedBox(
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(
                                color: colorScheme.outlineVariant.withValues(
                                  alpha: 0.32,
                                ),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: theme.brightness == Brightness.dark
                                        ? 0.22
                                        : 0.06,
                                  ),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: InvertWidget(
                                invert: invert,
                                child: _buildThumbnailFace(
                                  colorScheme,
                                  duration: thumbFade,
                                  compact: true,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.linkKey ??
                                  widget.filePath.substring(
                                    widget.filePath.lastIndexOf('/') + 1,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                letterSpacing: -0.25,
                                color: widget.selected
                                    ? colorScheme.primary
                                    : colorScheme.onSurface,
                              ),
                            ),
                            if (widget.showListMetadata) ...[
                              const SizedBox(height: 8),
                              _buildListStatsMeta(theme, colorScheme),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 100),
                        transitionBuilder: (child, anim) =>
                            ScaleTransition(scale: anim, child: child),
                        child: widget.selected
                            ? Icon(
                                Icons.check_circle_rounded,
                                key: const ValueKey('check'),
                                color: colorScheme.primary,
                                size: 24,
                              )
                            : Icon(
                                Icons.chevron_right_rounded,
                                key: const ValueKey('chevron'),
                                color: colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.48,
                                ),
                                size: 24,
                              ),
                      ),
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
                                  child: _buildThumbnailFace(
                                    colorScheme,
                                    duration: thumbFade,
                                    compact: false,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: AnimatedOpacity(
                                opacity: widget.selected ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 100),
                                curve: Curves.easeOut,
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
                                            milliseconds: 140,
                                          ),
                                          curve: Curves.easeOutCubic,
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
                        // Removed the buggy Border() property entirely
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.shadow.withValues(alpha: 0.035),
                            offset: const Offset(0, -1),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          // Independent Top Border Line
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 1,
                              color: colorScheme.outlineVariant.withValues(
                                alpha: 0.1,
                              ),
                            ),
                          ),
                          // Text Content with static padding
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 10.0,
                            ),
                            child: SizedBox(
                              width: double.infinity,
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
                          ),
                        ],
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
      child: Hero(
        tag: 'note_hero_$editPath',
        child: AnimatedContainer(
          duration: transitionDuration,
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(
            widget.listMode ? 14 : kSaberContainerRadius / 1.5,
          ),
          border: Border.all(
            color: borderColor,
            width: borderWidth,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
          boxShadow: widget.selected && !widget.listMode
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

enum _ThumbChrome { none, deleting, renaming, moving }

class _ThumbnailChrome extends StatelessWidget {
  const _ThumbnailChrome({required this.chrome, required this.compact});

  final _ThumbChrome chrome;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = (isDark ? cs.surfaceContainerHigh : cs.surfaceContainerHighest)
        .withValues(alpha: 0.78);
    final icon = switch (chrome) {
      _ThumbChrome.deleting => Icons.delete_outline_rounded,
      _ThumbChrome.renaming => Icons.drive_file_rename_outline,
      _ThumbChrome.moving => Icons.drive_file_move_outlined,
      _ThumbChrome.none => Icons.delete_outline_rounded,
    };
    return ColoredBox(
      color: bg,
      child: Center(
        child: Icon(
          icon,
          size: compact ? 26 : 40,
          color: cs.onSurfaceVariant.withValues(alpha: 0.88),
        ),
      ),
    );
  }
}

class _ThumbnailFace extends StatefulWidget {
  const _ThumbnailFace({
    required this.image,
    required this.chrome,
    required this.duration,
    required this.compact,
  });

  final ImageProvider? image;
  final _ThumbChrome chrome;
  final Duration duration;
  final bool compact;

  @override
  State<_ThumbnailFace> createState() => _ThumbnailFaceState();
}

class _ThumbnailFaceState extends State<_ThumbnailFace>
    with SingleTickerProviderStateMixin {
  ImageProvider? _bottom;
  ImageProvider? _top;
  _ThumbChrome _overlayChrome = _ThumbChrome.none;
  late final AnimationController _crossfade;

  @override
  void initState() {
    super.initState();
    _bottom = widget.image;
    _overlayChrome = widget.chrome;
    _crossfade = AnimationController(vsync: this, duration: widget.duration)
      ..value = 1;
    _crossfade.addStatusListener(_onCrossfadeStatus);
  }

  void _onCrossfadeStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _top == null || !mounted) {
      return;
    }
    setState(() {
      _bottom = _top;
      _top = null;
    });
  }

  @override
  void didUpdateWidget(_ThumbnailFace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _crossfade.duration = widget.duration;
    }
    if (widget.chrome != _ThumbChrome.none) {
      _overlayChrome = widget.chrome;
    }
    if (widget.image == oldWidget.image) return;
    if (widget.image == null) {
      _bottom = oldWidget.image ?? _bottom;
      _top = null;
      if (widget.duration == Duration.zero) {
        _crossfade.value = 1;
      } else {
        _crossfade.forward(from: 0);
      }
    } else if (_bottom == null || widget.duration == Duration.zero) {
      _bottom = widget.image;
      _top = null;
      _crossfade.value = 1;
    } else {
      _bottom = oldWidget.image ?? _bottom;
      _top = widget.image;
      _crossfade.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _crossfade.dispose();
    super.dispose();
  }

  Widget _imageLayer(ImageProvider image) {
    return Image(
      image: image,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
      width: double.infinity,
      height: double.infinity,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _crossfade,
      builder: (context, _) {
        final t = Curves.easeInOutCubic.transform(_crossfade.value);
        final bottom = _bottom;
        final top = _top;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (bottom != null)
              _imageLayer(bottom)
            else
              const _FallbackThumbnail(),
            if (top != null) Opacity(opacity: t, child: _imageLayer(top)),
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: widget.chrome == _ThumbChrome.none ? 0 : 1,
                duration: widget.duration,
                curve: Curves.easeInOutCubic,
                child: _overlayChrome == _ThumbChrome.none
                    ? const SizedBox.expand()
                    : _ThumbnailChrome(
                        chrome: _overlayChrome,
                        compact: widget.compact,
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ThumbnailState extends ChangeNotifier {
  ImageProvider? _image;
  Uint8List? _bytes;
  _ThumbChrome _chrome = _ThumbChrome.none;

  _ThumbChrome get chrome => _chrome;
  set chrome(_ThumbChrome value) {
    if (_chrome == value) return;
    _chrome = value;
    notifyListeners();
  }

  ImageProvider? get image => _image;

  void setBytes(Uint8List bytes) {
    if (_bytes != null && _bytes!.length == bytes.length && _bytes == bytes) {
      if (_chrome != _ThumbChrome.none) {
        _chrome = _ThumbChrome.none;
        notifyListeners();
      }
      return;
    }
    _bytes = bytes;
    _image = MemoryImage(bytes);
    _chrome = _ThumbChrome.none;
    notifyListeners();
  }
}
