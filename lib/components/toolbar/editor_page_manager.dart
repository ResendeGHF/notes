// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:saber/components/canvas/canvas_gesture_detector.dart';
import 'package:saber/components/canvas/page_sidebar_preview.dart';
import 'package:saber/components/editor/pdf_outline_navigator.dart';
import 'package:saber/components/home/home_toolbar_chrome.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/pdf_outline.dart';
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
    this.pdfOutlines,
    this.onOutlinePageSelected,
    this.onNavigateToPage,
    this.onAddOutline,
    this.onRenameOutline,
    this.onDeleteOutline,
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

  /// Outline tree for the Outlines tab (may be empty).
  final List<PdfOutlineItem>? pdfOutlines;
  final void Function(int pageIndex)? onOutlinePageSelected;

  /// Hydrate + scroll (preferred over raw [scrollToPage] for lazy shells).
  final void Function(int pageIndex)? onNavigateToPage;
  final VoidCallback? onAddOutline;
  final void Function(PdfOutlineItem item, String newTitle)? onRenameOutline;
  final void Function(PdfOutlineItem item)? onDeleteOutline;

  @override
  State<EditorPageManager> createState() => _EditorPageManagerState();
}

const double _kFixedCardHeight = 420;

class _LazyPagePreview extends StatefulWidget {
  const _LazyPagePreview({
    required this.pageIndex,
    required this.priorityPageIndex,
    required this.coreInfo,
    required this.displaySize,
    required this.cupertino,
    this.pageBuilder,
  });

  final int pageIndex;
  final int priorityPageIndex;
  final EditorCoreInfo coreInfo;
  final Size displaySize;
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.42),
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
    return PageSidebarPreview(
      pageIndex: widget.pageIndex,
      coreInfo: widget.coreInfo,
      displaySize: widget.displaySize,
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
    final navigate = widget.onNavigateToPage;
    if (navigate != null) {
      navigate(pageIndex);
      return;
    }

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

  bool get _hasOutlines =>
      widget.pdfOutlines != null && widget.pdfOutlines!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final pagesList = _buildPagesList(context);
    final cs = Theme.of(context).colorScheme;
    final outlines = widget.pdfOutlines ?? const <PdfOutlineItem>[];
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: TabBar(
              labelColor: cs.primary,
              unselectedLabelColor: cs.onSurfaceVariant,
              indicatorColor: cs.primary,
              dividerColor: cs.outlineVariant.withValues(alpha: 0.22),
              labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                  ),
              unselectedLabelStyle: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w500),
              tabs: [
                Tab(text: t.editor.pages),
                Tab(
                  text: _hasOutlines
                      ? '${t.editor.navigation.pdfOutlines} (${_outlineCount(outlines)})'
                      : t.editor.navigation.pdfOutlines,
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                pagesList,
                PdfOutlineListView(
                  outlines: outlines,
                  readOnly: widget.coreInfo.readOnly,
                  onAddOutline: widget.onAddOutline,
                  onRenameOutline: widget.onRenameOutline,
                  onDeleteOutline: widget.onDeleteOutline,
                  onPageSelected: (pageIndex) {
                    final navigate = widget.onNavigateToPage;
                    if (navigate != null) {
                      navigate(pageIndex);
                      return;
                    }
                    final cb = widget.onOutlinePageSelected;
                    if (cb != null) {
                      cb(pageIndex);
                    } else {
                      scrollToPage(pageIndex);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static int _outlineCount(List<PdfOutlineItem> roots) {
    var n = 0;
    void visit(PdfOutlineItem item) {
      n++;
      for (final c in item.children ?? const []) {
        visit(c);
      }
    }
    for (final r in roots) {
      visit(r);
    }
    return n;
  }

  Widget _buildPagesList(BuildContext context) {
    final platform = Theme.of(context).platform;
    final cupertino = platform.isCupertino;
    final priorityPageIndex = (widget.currentPageIndex ?? 0).clamp(
      0,
      widget.coreInfo.pages.length - 1,
    );
    return ReorderableListView.builder(
      scrollController: _scrollController,
      buildDefaultDragHandles: false,
      itemExtent: _kFixedCardHeight,
      itemCount: widget.coreInfo.pages.length,
      itemBuilder: (context, pageIndex) {
        final isEmptyLastPage =
            pageIndex == widget.coreInfo.pages.length - 1 &&
            widget.coreInfo.pages[pageIndex].isEmpty;
        final btnStyle = IconButton.styleFrom(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.all(6),
        );
        return InkWell(
          key: ValueKey(pageIndex),
          onTap: () => scrollToPage(pageIndex),
          child: KeyedSubtree(
            key: ValueKey('page_$pageIndex'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: DecoratedBox(
                decoration: homeRuggedPanelDecoration(context, borderAlpha: 0.16),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 32,
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Text(
                                '${pageIndex + 1} / ${widget.coreInfo.pages.length}',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.2,
                                    ),
                              ),
                            ),
                            const Spacer(),
                            MouseRegion(
                              cursor: SystemMouseCursors.resizeUpDown,
                              child: ReorderableDragStartListener(
                                index: pageIndex,
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.drag_handle,
                                    size: 20,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Preview fills remaining card height/width (was capped
                      // at ~150×250 inside a mostly empty 420px card).
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final pageSize =
                                  widget.coreInfo.pages[pageIndex].size;
                              final aspect = (pageSize.width > 0 &&
                                      pageSize.height > 0)
                                  ? pageSize.width / pageSize.height
                                  : 1 / math.sqrt(2);
                              var w = constraints.maxWidth;
                              var h = w / aspect;
                              if (h > constraints.maxHeight) {
                                h = constraints.maxHeight;
                                w = h * aspect;
                              }
                              return Center(
                                child: SizedBox(
                                  width: w,
                                  height: h,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                        kSaberContainerRadius * 0.5,
                                      ),
                                      border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outlineVariant
                                            .withValues(alpha: 0.28),
                                        width: 1,
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(
                                        kSaberContainerRadius * 0.5,
                                      ),
                                      child: _LazyPagePreview(
                                        pageIndex: pageIndex,
                                        priorityPageIndex: priorityPageIndex,
                                        coreInfo: widget.coreInfo,
                                        displaySize: Size(w, h),
                                        cupertino: cupertino,
                                        pageBuilder: widget.pageBuilder,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 40,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              style: btnStyle,
                              tooltip: 'Insert page above',
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
                              style: btnStyle,
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
                              style: btnStyle,
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
                              style: btnStyle,
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
                              style: btnStyle,
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
                      ),
                    ],
                  ),
                ),
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

        syncPdfOutlinesWithPages(
          widget.coreInfo.pdfOutlines,
          widget.coreInfo.pages,
        );

        widget.redrawAndSave();
      },
    );
  }
}
