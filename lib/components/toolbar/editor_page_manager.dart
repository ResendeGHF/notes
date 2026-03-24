// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:saber/components/canvas/canvas_gesture_detector.dart';
import 'package:saber/components/canvas/canvas_preview.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/i18n/strings.g.dart';

class EditorPageManager extends StatefulWidget {
  const EditorPageManager({
    super.key,
    required this.coreInfo,
    required this.currentPageIndex,
    required this.redrawAndSave,
    required this.insertPageAfter,
    required this.insertPageBefore,
    required this.duplicatePage,
    required this.clearPage,
    required this.deletePage,
    required this.transformationController,
    this.pageBuilder,
  });

  final EditorCoreInfo coreInfo;
  final int? currentPageIndex;
  final VoidCallback redrawAndSave;

  final void Function(int) insertPageAfter;
  final void Function(int) insertPageBefore;
  final void Function(int) duplicatePage;
  final void Function(int) clearPage;
  final void Function(int) deletePage;

  final TransformationController transformationController;
  final IndexedWidgetBuilder? pageBuilder;

  @override
  State<EditorPageManager> createState() => _EditorPageManagerState();
}

const double _kFixedCardHeight = 420;

class _LazyPagePreview extends StatefulWidget {
  const _LazyPagePreview({
    required this.pageIndex,
    required this.priorityPageIndex,
    required this.coreInfo,
    required this.cupertino,
    this.pageBuilder,
  });

  final int pageIndex;
  final int priorityPageIndex;
  final EditorCoreInfo coreInfo;
  final bool cupertino;
  final IndexedWidgetBuilder? pageBuilder;

  @override
  State<_LazyPagePreview> createState() => _LazyPagePreviewState();
}

class _LazyPagePreviewState extends State<_LazyPagePreview> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // Stagger heavy InnerCanvas builds across frames so opening the pages
    // panel does not synchronously construct every preview at once.
    void load() {
      if (mounted) setState(() => _loaded = true);
    }

    final distFromPriority =
        (widget.pageIndex - widget.priorityPageIndex).abs();
    if (distFromPriority == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => load());
    } else {
      Future<void>.delayed(
        Duration(milliseconds: 12 * distFromPriority),
        load,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Text(
            '${widget.pageIndex + 1}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }
    if (widget.pageBuilder != null) {
      return widget.pageBuilder!(context, widget.pageIndex);
    }
    return FittedBox(
      child: CanvasPreview(
        pageIndex: widget.pageIndex,
        height: null,
        coreInfo: widget.coreInfo,
      ),
    );
  }
}

class _EditorPageManagerState extends State<EditorPageManager> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    final idx = widget.currentPageIndex ?? 0;

    final offset = (idx * _kFixedCardHeight).clamp(0.0, double.infinity);
    _scrollController = ScrollController(initialScrollOffset: offset);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void scrollToPage(int pageIndex) {

    final screenWidth = MediaQuery.sizeOf(context).width;
    final offsets = <double>[];
    double currentTop = 0;

    for (final page in widget.coreInfo.pages) {
      offsets.add(currentTop);
      final pageSize = page.size;
      final pageWidthFitted = math.min(pageSize.width, screenWidth);

      currentTop += 16;
      currentTop += pageSize.height * (pageWidthFitted / pageSize.width);
    }

    CanvasGestureDetector.scrollToPage(
      pageIndex: pageIndex,
      pageOffsets: offsets,
      transformationController: widget.transformationController,
    );
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final cupertino = platform.isCupertino;
    final priorityPageIndex =
        (widget.currentPageIndex ?? 0).clamp(0, widget.coreInfo.pages.length - 1);
    return ReorderableListView.builder(
      scrollController: _scrollController,
      buildDefaultDragHandles: false,
      itemExtent: _kFixedCardHeight,
      itemCount: widget.coreInfo.pages.length,
      itemBuilder: (context, pageIndex) {
        final isEmptyLastPage =
            pageIndex == widget.coreInfo.pages.length - 1 &&
            widget.coreInfo.pages[pageIndex].isEmpty;
        return InkWell(
          key: ValueKey(pageIndex),
          onTap: () => scrollToPage(pageIndex),
          child: KeyedSubtree(
            key: ValueKey('page_$pageIndex'),
            child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).dividerColor,
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Text(
                        '${pageIndex + 1} / ${widget.coreInfo.pages.length}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    MouseRegion(
                      cursor: SystemMouseCursors.resizeUpDown,
                      child: ReorderableDragStartListener(
                        index: pageIndex,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Icon(
                            Icons.drag_handle,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: cupertino ? 100 : 150,
                    maxHeight: 250,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).dividerColor,
                        width: 2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _LazyPagePreview(
                        pageIndex: pageIndex,
                        priorityPageIndex: priorityPageIndex,
                        coreInfo: widget.coreInfo,
                        cupertino: cupertino,
                        pageBuilder: widget.pageBuilder,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: "Insert page above",
                      icon: const AdaptiveIcon(
                        icon: Icons.arrow_circle_up_outlined,
                        cupertinoIcon: CupertinoIcons.arrow_up_circle,
                      ),
                      onPressed: () => setState(() {
                        widget.insertPageBefore(pageIndex);
                        scrollToPage(pageIndex);
                      }),
                    ),
                    IconButton(
                      tooltip: t.editor.menu.insertPage,
                      icon: const AdaptiveIcon(
                        icon: Icons.arrow_circle_down_outlined,
                        cupertinoIcon: CupertinoIcons.arrow_down_circle,
                      ),
                      onPressed: () => setState(() {
                        widget.insertPageAfter(pageIndex);
                        scrollToPage(pageIndex + 1);
                      }),
                    ),
                    IconButton(
                      tooltip: t.editor.menu.duplicatePage,
                      icon: const AdaptiveIcon(
                        icon: Icons.content_copy,
                        cupertinoIcon: CupertinoIcons.doc_on_clipboard,
                      ),
                      onPressed: () => setState(() {
                        widget.duplicatePage(pageIndex);
                        scrollToPage(pageIndex + 1);
                      }),
                    ),
                    IconButton(
                      tooltip: t.editor.menu.clearPage(
                        page: pageIndex + 1,
                        totalPages: widget.coreInfo.pages.length,
                      ),
                      icon: const Icon(Icons.cleaning_services),
                      onPressed: isEmptyLastPage
                          ? null
                          : () => setState(() {
                              widget.clearPage(pageIndex);
                              scrollToPage(pageIndex);
                            }),
                    ),
                    IconButton(
                      tooltip: t.editor.menu.deletePage,
                      icon: const AdaptiveIcon(
                        icon: Icons.delete,
                        cupertinoIcon: CupertinoIcons.delete,
                      ),
                      onPressed: isEmptyLastPage
                          ? null
                          : () => setState(() {
                              widget.deletePage(pageIndex);
                              scrollToPage(pageIndex);
                            }),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      },
      onReorder: (oldIndex, newIndex) {
        if (oldIndex == newIndex) return;
        if (oldIndex < newIndex) {
          newIndex -= 1;
        }
        widget.coreInfo.pages.insert(
          newIndex,
          widget.coreInfo.pages.removeAt(oldIndex),
        );

        for (int i = 0; i < widget.coreInfo.pages.length; i++) {
          for (final stroke in widget.coreInfo.pages[i].allStrokesInDrawOrder) {
            stroke.pageIndex = i;
          }
          for (final image in widget.coreInfo.pages[i].allImagesInDrawOrder) {
            image.pageIndex = i;
          }
        }

        widget.redrawAndSave();
      },
    );
  }
}
