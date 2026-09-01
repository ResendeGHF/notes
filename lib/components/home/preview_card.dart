// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async' show Future, StreamSubscription, Timer;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
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
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/prefs.dart';
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
  bool _listRowStatsLoading = true;

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
    final stats = await FileManager.getNoteListRowStats(base);
    if (!mounted) return;
    setState(() {
      _listRowStatsLoading = false;
      _listRowStats = stats;
    });
  }

  

  void _toggleCardSelection() {
    final newSelected = !widget.selected;
    expanded.value = newSelected;
    widget.toggleSelection(widget.filePath, newSelected);
  }

  void _showContextMenu([Offset? globalPosition]) async {
    final isLink = widget.linkKey != null;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final RelativeRect position;
    if (globalPosition != null) {
      position = RelativeRect.fromRect(
        globalPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      );
    } else {
      final RenderBox button = context.findRenderObject() as RenderBox;
      position = RelativeRect.fromRect(
        Rect.fromPoints(
          button.localToGlobal(Offset.zero, ancestor: overlay),
          button.localToGlobal(
            button.size.bottomRight(Offset.zero),
            ancestor: overlay,
          ),
        ),
        Offset.zero & overlay.size,
      );
    }

    final cs = Theme.of(context).colorScheme;
    final String? action = await showMenu<String>(
      context: context,
      position: position,
      elevation: 3,
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
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
              const PopupMenuDivider(),
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

    if (action == null || !mounted) return;

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
        break;
      case 'duplicate':
        await FileManager.duplicateFile(widget.filePath);
        break;
      case 'move':
        showDialog(
          context: context,
          builder: (context) => MoveNoteDialog(
            filesToMove: [widget.filePath],
            unselectNotes: () {},
          ),
        );
        break;
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
        break;
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
        break;
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
        break;
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
    final thumbFade = Duration(milliseconds: disableAnimations ? 0 : 320);

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

    final isLink = widget.linkKey != null;
    final noteName = widget.linkKey ??
        widget.filePath.substring(widget.filePath.lastIndexOf('/') + 1);

    // MODO LISTA (Google Drive / Keep list view style)
    if (widget.listMode) {
      final isVault = stows.localEncryptionEnabled.value;
      final fl = t.home.fileList;
      
      return HomeListRowSurface(
        selected: widget.selected,
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.isAnythingSelected
              ? (isLink ? null : _toggleCardSelection)
              : openAction,
          onLongPress: isLink ? () => _showContextMenu() : _toggleCardSelection,
          onSecondaryTap: () => _showContextMenu(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Miniatura elegante
                Container(
                  width: 56,
                  height: 68,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InvertWidget(
                    invert: false,
                    child: _buildThumbnailFace(
                      colorScheme,
                      duration: thumbFade,
                      compact: true,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                
                // Nome da nota (Flex 4)
                Expanded(
                  flex: 4,
                  child: Text(
                    noteName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5,
                      color: widget.selected
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                    ),
                  ),
                ),
                
                if (widget.showListMetadata) ...[
                  // Data de modificação (Flex 2)
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _listRowStatsLoading 
                          ? const SizedBox.shrink()
                          : HomeListMetaChip(
                              icon: Icons.edit_calendar_outlined,
                              text: _listRowStats?.modified != null
                                  ? formatHomeListDate(context, _listRowStats!.modified!)
                                  : '—',
                              tooltip: fl.metaModified,
                            ),
                    ),
                  ),
                  
                  // Tamanho do arquivo (Flex 2)
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _listRowStatsLoading
                          ? const SizedBox.shrink()
                          : HomeListMetaChip(
                              icon: Icons.sd_storage_outlined,
                              text: _listRowStats != null ? formatHomeListBytes(_listRowStats!.sizeBytes) : '—',
                              tooltip: fl.metaSize,
                            ),
                    ),
                  ),
                  
                  // Modo de carregamento do PDF (Flex 2)
                  if (isVault)
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: HomeListMetaChip(
                          icon: Icons.security_outlined,
                          text: getEffectiveVaultPdfLoadMode(widget.targetPath ?? widget.filePath) == 'temp_file' ? 'Disk (Temp)' : 'RAM',
                          tooltip: 'Vault PDF Load Mode',
                        ),
                      ),
                    ),
                ],
                
                const SizedBox(width: 8),
                // Ações rápidas ou Checkmark
                if (widget.selected)
                  Icon(
                    Icons.check_circle_rounded,
                    color: colorScheme.primary,
                    size: 22,
                  )
                else
                  IconButton(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 20,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () => _showContextMenu(),
                    tooltip: 'More actions',
                  ),
              ],
            ),
          ),
        ),
      );
    }

    // MODO GRADE (Google Keep Card Style)
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: widget.selected
          ? colorScheme.secondaryContainer
          : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: widget.selected
              ? colorScheme.primary
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: widget.selected ? 2.0 : 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: widget.isAnythingSelected
            ? (isLink ? null : _toggleCardSelection)
            : openAction,
        onLongPress: isLink ? () => _showContextMenu() : _toggleCardSelection,
        onSecondaryTapUp: (details) =>
            _showContextMenu(details.globalPosition),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Imagem de Pré-visualização
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: colorScheme.surfaceContainerLowest,
                    child: InvertWidget(
                      invert: false,
                      child: _buildThumbnailFace(
                        colorScheme,
                        duration: thumbFade,
                        compact: false,
                      ),
                    ),
                  ),
                  // Seletor Checkmark no Topo Esquerdo (Material 3 standard)
                  if (widget.selected || widget.isAnythingSelected)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: GestureDetector(
                        onTap: _toggleCardSelection,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: widget.selected
                                ? colorScheme.primary
                                : colorScheme.surface.withValues(alpha: 0.85),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: widget.selected
                                  ? colorScheme.primary
                                  : colorScheme.outline.withValues(alpha: 0.5),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            widget.selected
                                ? Icons.check
                                : Icons.circle_outlined,
                            size: 16,
                            color: widget.selected
                                ? colorScheme.onPrimary
                                : Colors.transparent,
                          ),
                        ),
                      ),
                    ),
                  // Indicador de Atalho
                  if (widget.targetPath != null)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: colorScheme.surface.withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.shortcut_rounded,
                          size: 14,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Rodapé do Card
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      noteName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: widget.selected
                            ? colorScheme.onSecondaryContainer
                            : colorScheme.onSurface,
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
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surfaceContainerLowest,
      child: Center(
        child: Icon(
          Icons.notes_rounded,
          size: 36,
          color: cs.onSurfaceVariant.withValues(alpha: 0.25),
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
          size: compact ? 22 : 36,
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
      filterQuality: FilterQuality.medium,
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
    if (_bytes != null && _bytes!.length == bytes.length && listEquals(_bytes, bytes)) {
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