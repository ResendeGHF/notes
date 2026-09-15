// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

part of 'editor.dart';

enum _MenuPage { main, backgroundSettings, layers, pageSettings, inkDefaults, tagsAndLinks, properties }


class ModernEditorMenu extends StatefulWidget {
  final EditorCoreInfo coreInfo;
  final int currentPageIndex;
  final bool invert;
  final bool hasPdfLinks;
  final ValueNotifier<bool> showPdfLinkBoxes;
  final VoidCallback onClose;

  final bool hasBackground;
  final bool isBackgroundInverted;
  final BoxFit currentBackgroundFit;
  final ValueChanged<BoxFit>? onSetBackgroundFit;
  final VoidCallback? onToggleBackgroundInvert;
  final VoidCallback? onRemoveBackground;
  final VoidCallback? onDeleteBackground;

  final ValueChanged<CanvasBackgroundPattern> onSetPagePattern;
  final ValueChanged<int> onSetPageLineHeight;
  final ValueChanged<double> onSetPageLineThickness;
  final ValueChanged<Color> onSetPageColor;
  final ValueChanged<Color> onSetPageLineColor;

  final ValueChanged<PageOrientation>? onSetPageOrientation;
  final void Function(double left, double right, double top, double bottom)?
  onSetMargins;
  final ValueChanged<Color>? onSetBorderColor;

  final VoidCallback onClearPage;
  final VoidCallback onClearAll;
  final VoidCallback onPickImage;
  final Future<bool> Function() onImportPdf;
  final Future<void> Function(Uint8List imageBytes)? onInsertMatrixImage;
  final VoidCallback onToggleCalculator;
  
  final void Function(int) onGoToLocation;
  final void Function(NoteLink) onOpenLinkedNote;
  final Future<List<_LinkTargetCandidate>> Function() onLoadLinkTargetCandidates;
  final VoidCallback onSaveTagsAndLinks;

  /// Runs ML Kit on all handwritten strokes in the note (per page) for copyable LaTeX.
  final Future<void> Function()? onNoteHandwritingToLatex;

  final Function(BuildContext) onExportSba;
  final Function(BuildContext) onExportPdf;
  final Function(BuildContext) onExportPng;

  final Future<void> Function()? onSetCustomThumbnail;

  final Future<void> Function() onDeleteNote;
  final Future<void> Function()? onSaveBeforeProperties;
  final VoidCallback? onOpenSplitView;
  final VoidCallback? onCloseSplitView;
  final VoidCallback? onReopenSplitView;
  final VoidCallback? onSwapSplitView;
  final VoidCallback? onToggleSplitAxis;
  final bool splitHasSecondary;
  final Axis? splitAxis;

  final VoidCallback? onLayersChanged;

  final ValueChanged<bool> onToggleGlobalBackgroundInversion;
  final VoidCallback? onInkDefaultsChanged;
  /// Snapshot open-note tool prefs before ink-settings overwrites live stows
  /// with the active preset (restored on cancel).
  final NoteToolSettings? Function()? captureNoteToolSettingsForInk;

  const ModernEditorMenu({
    super.key,
    required this.coreInfo,
    required this.currentPageIndex,
    required this.invert,
    required this.hasPdfLinks,
    required this.showPdfLinkBoxes,
    required this.onClose,

    this.hasBackground = false,
    this.isBackgroundInverted = false,
    this.currentBackgroundFit = BoxFit.fill,
    this.onSetBackgroundFit,
    this.onToggleBackgroundInvert,
    this.onRemoveBackground,
    this.onDeleteBackground,

    required this.onSetPagePattern,
    required this.onSetPageLineHeight,
    required this.onSetPageLineThickness,
    required this.onSetPageColor,
    required this.onSetPageLineColor,
    this.onSetPageOrientation,
    this.onSetMargins,
    this.onSetBorderColor,
    required this.onClearPage,
    required this.onClearAll,
    required this.onPickImage,
    required this.onImportPdf,
    this.onInsertMatrixImage,
    required this.onToggleCalculator,
    required this.onGoToLocation,
    required this.onOpenLinkedNote,
    required this.onLoadLinkTargetCandidates,
    required this.onSaveTagsAndLinks,
    this.onNoteHandwritingToLatex,
    required this.onExportSba,
    required this.onExportPdf,
    required this.onExportPng,
    this.onSetCustomThumbnail,
    required this.onDeleteNote,
    this.onSaveBeforeProperties,
    this.onOpenSplitView,
    this.onCloseSplitView,
    this.onReopenSplitView,
    this.onSwapSplitView,
    this.onToggleSplitAxis,
    this.splitHasSecondary = false,
    this.splitAxis,
    this.onLayersChanged,
    required this.onToggleGlobalBackgroundInversion,
    this.onInkDefaultsChanged,
    this.captureNoteToolSettingsForInk,
  });

  @override
  State<ModernEditorMenu> createState() => _ModernEditorMenuState();
}

class _ModernEditorMenuState extends State<ModernEditorMenu> {
  _MenuPage _page = _MenuPage.main;
  late bool _localBackgroundInverted;
  late BoxFit _currentFit;
  NoteToolSettings? _inkSessionBackup;

  @override
  void initState() {
    super.initState();
    _localBackgroundInverted = widget.isBackgroundInverted;
    _currentFit = widget.currentBackgroundFit;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      constraints: const BoxConstraints(),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: switch (_page) {
          _MenuPage.main => _buildMainMenu(context, colorScheme),
          _MenuPage.layers => _LayersSettingsView(
            key: const ValueKey('layers'),
            coreInfo: widget.coreInfo,
            currentPageIndex: widget.currentPageIndex,
            onBack: () => setState(() => _page = _MenuPage.main),
            onLayersChanged: widget.onLayersChanged,
          ),
          _MenuPage.backgroundSettings => _BackgroundSettingsView(
            key: const ValueKey('background'),
            currentFit: _currentFit,
            isInverted: _localBackgroundInverted,
            onBack: () => setState(() => _page = _MenuPage.main),
            onSetFit: (fit) {
              setState(() => _currentFit = fit);
              widget.onSetBackgroundFit?.call(fit);
            },
            onToggleInvert: () {
              setState(() {
                _localBackgroundInverted = !_localBackgroundInverted;
              });
              widget.onToggleBackgroundInvert?.call();
            },
            onRemoveBackground: widget.onRemoveBackground,
            onDeleteBackground: widget.onDeleteBackground,
          ),
          _MenuPage.pageSettings => _PageSettingsSidebarView(
            key: const ValueKey('pageSettings'),
            coreInfo: widget.coreInfo,
            currentPageIndex: widget.currentPageIndex,
            onBack: () => setState(() => _page = _MenuPage.main),
            onSetPattern: widget.onSetPagePattern,
            onSetLineHeight: widget.onSetPageLineHeight,
            onSetLineThickness: widget.onSetPageLineThickness,
            onSetColor: widget.onSetPageColor,
            onSetLineColor: widget.onSetPageLineColor,
            onSetPageOrientation: widget.onSetPageOrientation,
            onSetMargins: widget.onSetMargins,
            onSetBorderColor: widget.onSetBorderColor,
            onToggleGlobalBackgroundInversion:
                widget.onToggleGlobalBackgroundInversion,
          ),
          _MenuPage.inkDefaults => _InkDefaultsSidebarView(
            key: const ValueKey('inkDefaults'),
            noteSessionBackup: _inkSessionBackup,
            onChanged: widget.onInkDefaultsChanged,
            onBack: () => setState(() => _page = _MenuPage.main),
          ),
          _MenuPage.tagsAndLinks => _TagsAndLinksSidebarView(
            key: const ValueKey('tagsAndLinks'),
            coreInfo: widget.coreInfo,
            currentPageIndex: widget.currentPageIndex,
            onBack: () => setState(() => _page = _MenuPage.main),
            onGoToLocation: widget.onGoToLocation,
            onOpenLinkedNote: widget.onOpenLinkedNote,
            onLoadLinkTargetCandidates: widget.onLoadLinkTargetCandidates,
            onSaveTagsAndLinks: widget.onSaveTagsAndLinks,
            onClose: widget.onClose,
          ),
          _MenuPage.properties => _PropertiesSidebarView(
            key: const ValueKey('properties'),
            coreInfo: widget.coreInfo,
            onBack: () => setState(() => _page = _MenuPage.main),
          ),
        },
      ),
    );
  }

  Widget _buildMainMenu(BuildContext context, ColorScheme colors) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    IconData bgIcon = Icons.image_outlined;
    if (widget.hasBackground && widget.coreInfo.pages.isNotEmpty) {
      final img = widget.coreInfo.pages[widget.currentPageIndex].backgroundImage;
      if (img is PdfEditorImage) {
        bgIcon = Icons.picture_as_pdf_outlined;
      }
    }

    Widget subHeader(String text) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        child: Text(
          text,
          style: textTheme.labelLarge?.copyWith(
            color: colors.primary,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return ListView(
      key: const ValueKey('main'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (widget.onSetCustomThumbnail != null) ...[
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: const Icon(Icons.image_outlined),
            title: const Text('Set custom thumbnail'),
            onTap: () {
              widget.onClose();
              Future.delayed(const Duration(milliseconds: 300), () {
                widget.onSetCustomThumbnail?.call();
              });
            },
          ),
          const Divider(height: 1),
        ],

        subHeader('Appearance'),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: const Icon(Icons.layers_outlined),
          title: const Text('Layers'),
          onTap: () => setState(() => _page = _MenuPage.layers),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: const Icon(Icons.tune_rounded),
          title: const Text('Page setup'),
          onTap: () => setState(() => _page = _MenuPage.pageSettings),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: const Icon(Icons.brush_outlined),
          title: Text(t.settings.noteInkDefaults.changeInkDefaults),
          onTap: () {
            _inkSessionBackup = widget.captureNoteToolSettingsForInk?.call();
            setState(() => _page = _MenuPage.inkDefaults);
          },
        ),
        if (widget.hasBackground)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: Icon(bgIcon),
            title: const Text('Background image'),
            onTap: () => setState(() => _page = _MenuPage.backgroundSettings),
          ),

        if (widget.onOpenSplitView != null || widget.onReopenSplitView != null) ...[
          const Divider(height: 16),
          subHeader('Split view'),
          if (!widget.splitHasSecondary && widget.onOpenSplitView != null)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: const Icon(Icons.splitscreen_outlined),
              title: const Text('Open second note'),
              onTap: () {
                widget.onClose();
                widget.onOpenSplitView?.call();
              },
            ),
          if (widget.splitHasSecondary && widget.onReopenSplitView != null)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('Open different note'),
              onTap: () {
                widget.onClose();
                widget.onReopenSplitView?.call();
              },
            ),
          if (widget.splitHasSecondary && widget.onSwapSplitView != null)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: const Icon(Icons.swap_horiz_rounded),
              title: const Text('Swap notes'),
              onTap: () {
                widget.onClose();
                widget.onSwapSplitView?.call();
              },
            ),
          if (widget.splitHasSecondary && widget.onToggleSplitAxis != null)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: Icon(widget.splitAxis == Axis.vertical ? Icons.vertical_split_outlined : Icons.horizontal_split_outlined),
              title: Text(widget.splitAxis == Axis.vertical ? 'Vertical split' : 'Horizontal split'),
              onTap: () {
                widget.onClose();
                widget.onToggleSplitAxis?.call();
              },
            ),
          if (widget.splitHasSecondary && widget.onCloseSplitView != null)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: const Icon(Icons.close_fullscreen_rounded),
              title: const Text('Close split view'),
              onTap: () {
                widget.onClose();
                widget.onCloseSplitView?.call();
              },
            ),
        ],

        const Divider(height: 16),
        subHeader('Insert'),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: const Icon(Icons.add_photo_alternate_outlined),
          title: const Text('Image'),
          onTap: () => widget.onPickImage(),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: const Text('PDF document'),
          onTap: () async => await widget.onImportPdf(),
        ),
        if (widget.onInsertMatrixImage != null)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: const Icon(Icons.calculate_outlined),
            title: const Text('Matrix calculator'),
            onTap: () async {
              final result = await _MatrixCalculatorDialog.show(context);
              if (result != null) {
                widget.onClose();
                await widget.onInsertMatrixImage!(result);
              }
            },
          ),
        
        const Divider(height: 16),
        subHeader('Tools'),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: const Icon(Icons.link_rounded),
          title: const Text('Tags & links'),
          onTap: () => setState(() => _page = _MenuPage.tagsAndLinks),
        ),
        if (widget.onNoteHandwritingToLatex != null)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: const Icon(Icons.functions_outlined),
            title: Text(t.editor.noteHandwritingToLatex),
            onTap: () async {
              widget.onClose();
              await widget.onNoteHandwritingToLatex!();
            },
          ),
        ValueListenableBuilder(
          valueListenable: stows.enableFingerDrawing,
          builder: (context, enabled, _) {
            return SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              secondary: const Icon(Icons.touch_app_outlined),
              title: const Text('Finger drawing'),
              value: enabled,
              onChanged: (val) => stows.enableFingerDrawing.value = val,
            );
          },
        ),
        if (widget.hasPdfLinks)
          ValueListenableBuilder<bool>(
            valueListenable: widget.showPdfLinkBoxes,
            builder: (context, enabled, _) {
              return SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                secondary: const Icon(Icons.picture_in_picture_alt_outlined),
                title: const Text('Link boxes'),
                value: enabled,
                onChanged: (val) => widget.showPdfLinkBoxes.value = val,
              );
            },
          ),

        const Divider(height: 16),
        subHeader('Share & export'),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: const Icon(Icons.archive_outlined),
          title: const Text('Save as .sba'),
          onTap: () => widget.onExportSba(context),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: const Text('Save as PDF'),
          onTap: () => widget.onExportPdf(context),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: const Icon(Icons.image_outlined),
          title: const Text('Save as Image'),
          onTap: () => widget.onExportPng(context),
        ),

        const Divider(height: 16),
        subHeader('Danger zone'),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: Icon(Icons.layers_clear_outlined, color: colors.error),
          title: Text('Clear current page', style: TextStyle(color: colors.error)),
          onTap: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AdaptiveAlertDialog(
                title: const Text('Clear current page'),
                content: const Text('Are you sure you want to clear the current page? This action cannot be undone.'),
                actions: [
                  CupertinoDialogAction(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
                  ),
                  CupertinoDialogAction(
                    isDestructiveAction: true,
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            );
            if (confirmed == true) {
              widget.onClose();
              widget.onClearPage();
            }
          },
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: Icon(Icons.delete_sweep_outlined, color: colors.error),
          title: Text('Clear all pages', style: TextStyle(color: colors.error)),
          onTap: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AdaptiveAlertDialog(
                title: const Text('Clear all pages'),
                content: const Text('Are you sure you want to clear all pages? This action cannot be undone.'),
                actions: [
                  CupertinoDialogAction(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
                  ),
                  CupertinoDialogAction(
                    isDestructiveAction: true,
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Clear All'),
                  ),
                ],
              ),
            );
            if (confirmed == true) {
              widget.onClose();
              widget.onClearAll();
            }
          },
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: Icon(Icons.delete_outline, color: colors.error),
          title: Text('Delete note', style: TextStyle(color: colors.error)),
          onTap: () async {
            widget.onClose();
            await widget.onDeleteNote();
          },
        ),

        const Divider(height: 16),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: const Icon(Icons.info_outline),
          title: const Text('Properties'),
          onTap: () async {
            if (widget.onSaveBeforeProperties != null) {
              await widget.onSaveBeforeProperties!();
            }
            setState(() => _page = _MenuPage.properties);
          },
        ),
      ],
    );
  }
}

class _TagsAndLinksSidebarView extends StatefulWidget {
  final EditorCoreInfo coreInfo;
  final int currentPageIndex;
  final VoidCallback onBack;
  final void Function(int) onGoToLocation;
  final void Function(NoteLink) onOpenLinkedNote;
  final Future<List<_LinkTargetCandidate>> Function() onLoadLinkTargetCandidates;
  final VoidCallback onSaveTagsAndLinks;
  final VoidCallback onClose;

  const _TagsAndLinksSidebarView({
    super.key,
    required this.coreInfo,
    required this.currentPageIndex,
    required this.onBack,
    required this.onGoToLocation,
    required this.onOpenLinkedNote,
    required this.onLoadLinkTargetCandidates,
    required this.onSaveTagsAndLinks,
    required this.onClose,
  });

  @override
  State<_TagsAndLinksSidebarView> createState() => _TagsAndLinksSidebarViewState();
}

class _TagsAndLinksSidebarViewState extends State<_TagsAndLinksSidebarView> {
  final TextEditingController _tagInputController = TextEditingController();

  @override
  void dispose() {
    _tagInputController.dispose();
    super.dispose();
  }

  Future<void> _addLink() async {
    final candidates = await widget.onLoadLinkTargetCandidates();
    if (!mounted) return;
    _LinkTargetCandidate? selectedCandidate;
    final pageController = TextEditingController(text: '1');
    final labelController = TextEditingController();
    final searchController = TextEditingController();
    String search = '';

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => Dialog(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t.editor.addInternalLink,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.4,
                        ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: searchController,
                    onChanged: (value) {
                      setLocalState(() {
                        search = value.trim().toLowerCase();
                      });
                    },
                    decoration: InputDecoration(
                      labelText: 'Search note by name or tag',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.withOpacity(0.1),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: Builder(
                      builder: (context) {
                        final filtered = candidates.where((candidate) {
                          if (search.isEmpty) return true;
                          final name = candidate.displayName.toLowerCase();
                          if (name.contains(search)) return true;
                          return candidate.tags.any((tag) => tag.contains(search));
                        }).toList();
                        if (filtered.isEmpty) {
                          return Center(
                            child: Text(t.editor.noNotesMatchQuery),
                          );
                        }
                        return ListView.separated(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final candidate = filtered[index];
                            final selected = selectedCandidate?.path == candidate.path;
                            return ListTile(
                              dense: true,
                              selected: selected,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              selectedTileColor: Colors.grey.withOpacity(0.2),
                              title: Text(
                                candidate.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: candidate.tags.isEmpty
                                  ? null
                                  : Text(
                                      candidate.tags.take(4).join(', '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              onTap: () {
                                setLocalState(() {
                                  selectedCandidate = candidate;
                                });
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: pageController,
                    decoration: InputDecoration(
                      labelText: 'Page or range (e.g. 1 or 1-5)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.withOpacity(0.1),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: labelController,
                    decoration: InputDecoration(
                      labelText: 'Label (optional)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.withOpacity(0.1),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: selectedCandidate == null
                            ? null
                            : () => Navigator.pop(context, true),
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (created != true || selectedCandidate == null) {
      searchController.dispose();
      pageController.dispose();
      labelController.dispose();
      return;
    }
    
    final pageText = pageController.text.trim();
    int pageStart = 1;
    int? pageEnd;
    if (pageText.contains('-')) {
      final parts = pageText.split('-');
      if (parts.length == 2) {
        pageStart = int.tryParse(parts[0].trim()) ?? 1;
        final endParsed = int.tryParse(parts[1].trim());
        if (endParsed != null && endParsed >= pageStart) {
          pageEnd = endParsed;
        }
      }
    } else {
      pageStart = int.tryParse(pageText) ?? 1;
    }
    
    try {
      final targetInfo = await EditorCoreInfo.loadFromFilePath(
        selectedCandidate!.path,
        readOnly: true,
        onlyFirstPage: false,
      );
      final pageCount = targetInfo.pages.length;
      if (pageCount <= 0) {
        pageStart = 1;
        pageEnd = null;
      } else {
        pageStart = pageStart.clamp(1, pageCount);
        pageEnd = pageEnd != null ? pageEnd.clamp(pageStart, pageCount) : null;
      }
    } catch (_) {
      pageStart = pageStart.clamp(1, 9999);
      pageEnd = pageEnd != null ? pageEnd.clamp(pageStart, 9999) : null;
    }
    
    final currentPage = widget.coreInfo.pages[widget.currentPageIndex];
    final link = NoteLink(
      sourcePageId: currentPage.id,
      sourcePageIndex: widget.currentPageIndex,
      targetPath: selectedCandidate!.path,
      targetPageIndex: pageStart - 1,
      targetPageIndexEnd: pageEnd != null ? pageEnd - 1 : null,
      label: labelController.text.trim().isEmpty ? null : labelController.text.trim(),
    );
    
    widget.coreInfo.links = [...widget.coreInfo.links, link];
    widget.onSaveTagsAndLinks();
    if (mounted) setState(() {});
    
    try {
      unawaited(
        NoteLinksDatabase.instance.setLinksForPath(
          widget.coreInfo.filePath,
          widget.coreInfo.links,
          rootDirectory: FileManager.documentsDirectory,
        ),
      );
    } catch (e) {
      // ignore
    }
    
    searchController.dispose();
    pageController.dispose();
    labelController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentPage = widget.coreInfo.pages[widget.currentPageIndex];
    final linksForPage = widget.coreInfo.linksForPage(currentPage, widget.currentPageIndex);

    return Column(
      key: const ValueKey('tagsAndLinksSidebar'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Tags & links', style: theme.textTheme.titleMedium),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            children: [
              TextField(
                controller: _tagInputController,
                decoration: InputDecoration(
                  labelText: 'Add tag',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.withOpacity(0.1),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      final tag = _tagInputController.text.trim().toLowerCase();
                      if (tag.isEmpty) return;
                      final updated = {
                        ...widget.coreInfo.tags,
                        tag,
                      }.toList()..sort();
                      widget.coreInfo.tags = updated;
                      _tagInputController.clear();
                      TagDatabase.instance.setTagsForPath(
                        widget.coreInfo.filePath,
                        widget.coreInfo.tags,
                      );
                      widget.onSaveTagsAndLinks();
                      setState(() {});
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in widget.coreInfo.tags)
                    Chip(
                      label: Text(tag),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      onDeleted: () {
                        widget.coreInfo.tags = widget.coreInfo.tags
                            .where((t) => t != tag)
                            .toList();
                        TagDatabase.instance.setTagsForPath(
                          widget.coreInfo.filePath,
                          widget.coreInfo.tags,
                        );
                        widget.onSaveTagsAndLinks();
                        setState(() {});
                      },
                    ),
                ],
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Page links',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _addLink,
                    icon: const Icon(Icons.add_link),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (linksForPage.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    t.editor.noLinksOnPage,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              else
                ...linksForPage.map(
                  (link) => ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: const Icon(Icons.link),
                    title: Text(
                      link.label ??
                          (link.targetPath.isEmpty
                              ? 'Current Note'
                              : link.targetPath.split('/').last),
                    ),
                    subtitle: Text(
                      link.isRange
                          ? '${link.targetPath.isEmpty ? 'Internal' : link.targetPath} (pages ${link.targetPageIndex + 1}-${link.targetPageIndexEnd! + 1})'
                          : '${link.targetPath.isEmpty ? 'Internal' : link.targetPath} (page ${link.targetPageIndex + 1})',
                    ),
                    onTap: () {
                      widget.onClose();
                      if (link.targetPath.isEmpty) {
                        widget.onGoToLocation(link.targetPageIndex);
                      } else {
                        widget.onOpenLinkedNote(link);
                      }
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        widget.coreInfo.links = widget.coreInfo.links
                            .where((item) => item != link)
                            .toList();
                        widget.onSaveTagsAndLinks();
                        setState(() {});
                        try {
                          unawaited(
                            NoteLinksDatabase.instance.setLinksForPath(
                              widget.coreInfo.filePath,
                              widget.coreInfo.links,
                              rootDirectory: FileManager.documentsDirectory,
                            ),
                          );
                        } catch (e) {
                          // ignore
                        }
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PropertiesSidebarView extends StatefulWidget {
  final EditorCoreInfo coreInfo;
  final VoidCallback onBack;

  const _PropertiesSidebarView({
    super.key,
    required this.coreInfo,
    required this.onBack,
  });

  @override
  State<_PropertiesSidebarView> createState() => _PropertiesSidebarViewState();
}

class _PropertiesSidebarViewState extends State<_PropertiesSidebarView> {
  String? _basePath;
  int? _fileSize;

  @override
  void initState() {
    super.initState();
    _loadAsync();
  }

  Future<void> _loadAsync() async {
    final ext = await FileManager.doesFileExist(
          widget.coreInfo.filePath + Editor.extensionOldJson,
        )
        ? Editor.extensionOldJson
        : Editor.extension;
    final basePath = widget.coreInfo.filePath + ext;

    if (!mounted) return;
    setState(() => _basePath = basePath);

    final fileSize = await FileManager.getNoteBundleSizeBytes(
      widget.coreInfo.filePath,
    );

    if (mounted) setState(() => _fileSize = fileSize);
  }

  String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    return duration.inHours > 0
        ? '${duration.inHours}h ${duration.inMinutes.remainder(60)}m'
        : '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    final dateFormat = DateFormat('MMM dd, yyyy - HH:mm');
    final creation = widget.coreInfo.creationDate > 0
        ? dateFormat.format(
            DateTime.fromMillisecondsSinceEpoch(widget.coreInfo.creationDate),
          )
        : 'Unknown';
    final modified = widget.coreInfo.lastModification > 0
        ? dateFormat.format(
            DateTime.fromMillisecondsSinceEpoch(widget.coreInfo.lastModification),
          )
        : 'Unknown';
    final accessed = widget.coreInfo.lastAccess > 0
        ? dateFormat.format(
            DateTime.fromMillisecondsSinceEpoch(widget.coreInfo.lastAccess),
          )
        : 'Unknown';
    final timeSpentStr = _formatDuration(widget.coreInfo.totalTimeSpent);
    final timeSpentEditingStr = _formatDuration(widget.coreInfo.totalTimeSpentEditing);
    final locationStr = widget.coreInfo.location ?? 'Unknown';

    final sizeStr = _fileSize != null
        ? (_fileSize! > 1024 * 1024
            ? '${(_fileSize! / (1024 * 1024)).toStringAsFixed(2)} MB'
            : '${(_fileSize! / 1024).toStringAsFixed(2)} KB')
        : '...';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Properties', style: theme.textTheme.titleMedium),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            children: [
              _PropRow(icon: Icons.calendar_today, label: 'Created', value: creation),
              _PropRow(icon: Icons.edit_note, label: 'Modified', value: modified),
              _PropRow(icon: Icons.visibility, label: 'Accessed', value: accessed),
              _PropRow(icon: Icons.location_on_outlined, label: 'Location', value: locationStr),
              _PropRow(icon: Icons.menu_book_outlined, label: 'Type', value: 'Paged note'),
              _PropRow(icon: Icons.schedule, label: 'Time Spent', value: timeSpentStr),
              _PropRow(icon: Icons.timer_outlined, label: 'Time Editing', value: timeSpentEditingStr),
              _PropRow(icon: Icons.sd_storage, label: 'Total Size', value: sizeStr),
              if (stows.localEncryptionEnabled.value && _basePath != null)
                _PdfLoadModeRow(basePath: _basePath!),
            ],
          ),
        ),
      ],
    );
  }
}

class _PropRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _PropRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _PdfLoadModeRow extends StatefulWidget {
  final String basePath;

  const _PdfLoadModeRow({required this.basePath});

  @override
  State<_PdfLoadModeRow> createState() => _PdfLoadModeRowState();
}

class _PdfLoadModeRowState extends State<_PdfLoadModeRow> {
  String? _localModeOverride;

  @override
  void initState() {
    super.initState();
    stows.vaultPdfLoadOverrides.addListener(_onOverridesChanged);
    _syncFromStow();
  }

  @override
  void dispose() {
    stows.vaultPdfLoadOverrides.removeListener(_onOverridesChanged);
    super.dispose();
  }

  void _onOverridesChanged() {
    if (mounted) _syncFromStow();
  }

  void _syncFromStow() {
    final mode = getStoredVaultPdfLoadOverrideForPath(widget.basePath);
    if (mounted && _localModeOverride != mode) {
      setState(() => _localModeOverride = mode);
    }
  }

  String get _effectiveMode =>
      _localModeOverride ?? getStoredVaultPdfLoadOverrideForPath(widget.basePath);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentMode = _effectiveMode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(Icons.picture_as_pdf, size: 20, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'PDF loading',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SegmentedButton<String>(
            key: ValueKey(currentMode),
            segments: const [
              ButtonSegment(
                value: 'ram_only',
                icon: Icon(Icons.memory, size: 16),
                label: Text('RAM'),
              ),
              ButtonSegment(
                value: 'temp_file',
                icon: Icon(Icons.speed, size: 16),
                label: Text('Temp'),
              ),
              ButtonSegment(
                value: 'default',
                icon: Icon(Icons.settings, size: 16),
                label: Text('Default'),
              ),
            ],
            selected: {currentMode},
            onSelectionChanged: (selection) {
              final mode = selection.first;

              setState(() => _localModeOverride = mode);
              setVaultPdfLoadOverrideForFile(
                widget.basePath,
                mode == 'default' ? null : mode,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MenuSection extends StatelessWidget {
  final List<Widget> children;
  const _MenuSection({required this.children});

  @override
  Widget build(BuildContext context) {
    // Minimalista: Sem caixas coloridas redundantes.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? textColor;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.iconColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(
        icon,
        color: iconColor ?? colorScheme.onSurfaceVariant,
        size: 22,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: textColor ?? colorScheme.onSurface,
          fontWeight: FontWeight.w400,
          fontSize: 15,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _MenuLargeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuLargeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Converte o "Card Grande com Fundo Escuro" do KDE 
    // em um ListTile amigável com botão de ícone destacado Material 3.
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 20,
          color: colorScheme.onSecondaryContainer,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 15,
          color: colorScheme.onSurface,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// Full-screen page appearance (still used from Settings note-defaults if needed).
/// Editor sidebar uses [_PageSettingsSidebarView] instead.
class EditorPageSettingsPage extends StatelessWidget {
  const EditorPageSettingsPage({
    super.key,
    required this.coreInfo,
    required this.currentPageIndex,
    required this.onSetPattern,
    required this.onSetLineHeight,
    required this.onSetLineThickness,
    required this.onSetColor,
    required this.onSetLineColor,
    this.onSetPageOrientation,
    required this.onToggleGlobalBackgroundInversion,
    this.onSetMargins,
    this.onSetBorderColor,
  });

  final EditorCoreInfo coreInfo;
  final int currentPageIndex;
  final ValueChanged<CanvasBackgroundPattern> onSetPattern;
  final ValueChanged<int> onSetLineHeight;
  final ValueChanged<double> onSetLineThickness;
  final ValueChanged<Color> onSetColor;
  final ValueChanged<Color> onSetLineColor;
  final ValueChanged<PageOrientation>? onSetPageOrientation;
  final ValueChanged<bool> onToggleGlobalBackgroundInversion;
  final void Function(double left, double right, double top, double bottom)?
      onSetMargins;
  final ValueChanged<Color>? onSetBorderColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: homeAppBarBackgroundColor(context),
      appBar: AppBar(
        backgroundColor: homeAppBarBackgroundColor(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Page appearance',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: -0.35,
              ),
            ),
            Text(
              'Page ${currentPageIndex + 1} · pattern, colors, margins',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: EditorPageSettingsBody(
          coreInfo: coreInfo,
          currentPageIndex: currentPageIndex,
          onSetPattern: onSetPattern,
          onSetLineHeight: onSetLineHeight,
          onSetLineThickness: onSetLineThickness,
          onSetColor: onSetColor,
          onSetLineColor: onSetLineColor,
          onSetPageOrientation: onSetPageOrientation,
          onToggleGlobalBackgroundInversion: onToggleGlobalBackgroundInversion,
          onSetMargins: onSetMargins,
          onSetBorderColor: onSetBorderColor,
        ),
      ),
    );
  }
}


class _LayersSettingsView extends StatelessWidget {
  final EditorCoreInfo coreInfo;
  final int currentPageIndex;
  final VoidCallback onBack;
  final VoidCallback? onLayersChanged;

  const _LayersSettingsView({
    super.key,
    required this.coreInfo,
    required this.currentPageIndex,
    required this.onBack,
    this.onLayersChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final page = coreInfo.pages[currentPageIndex];

    return ListenableBuilder(
      listenable: page,
      builder: (context, _) => _buildContent(context, theme, colorScheme, page),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    EditorPage page,
  ) {
    final ListView listContent = ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      children: [
        Text(
          'Layers (Page ${currentPageIndex + 1})',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Bottom layer is drawn first. Tap a layer to draw on it.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        ...page.layerOrderIndices.asMap().entries.map((e) {
          final orderIdx = e.key;
          final layerIdx = e.value;
          final layer = page.layerAt(layerIdx);
          final isActive = page.activeLayerIndex == layerIdx;
          final isBase = layerIdx == 0;
          return ListTile(
            leading: Icon(
              isActive ? Icons.edit : Icons.layers,
              color: isActive ? colorScheme.primary : null,
            ),
            title: Text(
              layer.name ?? 'Layer ${layerIdx + 1}',
              style: TextStyle(
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color: isActive ? colorScheme.primary : null,
              ),
            ),
            subtitle: Text(
              '${layer.strokes.length} strokes, ${layer.images.length} images',
              style: theme.textTheme.bodySmall,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (page.layerCount > 1) ...[
                  IconButton(
                    icon: const Icon(Icons.arrow_downward, size: 18),
                    onPressed: orderIdx < page.layerCount - 1
                        ? () {
                            page.moveLayerDown(orderIdx);
                            onLayersChanged?.call();
                          }
                        : null,
                    tooltip: 'Move down',
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_upward, size: 18),
                    onPressed: orderIdx > 0
                        ? () {
                            page.moveLayerUp(orderIdx);
                            onLayersChanged?.call();
                          }
                        : null,
                    tooltip: 'Move up',
                  ),
                ],
                if (!isBase && page.layerCount > 1)
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: colorScheme.error,
                    ),
                    onPressed: () {
                      page.removeLayer(layerIdx);
                      onLayersChanged?.call();
                    },
                    tooltip: 'Remove layer',
                  ),
                IconButton(
                  icon: Icon(
                    Icons.check_circle,
                    size: 20,
                    color: isActive ? colorScheme.primary : colorScheme.outline,
                  ),
                  onPressed: () {
                    page.activeLayerIndex = layerIdx;
                    onLayersChanged?.call();
                  },
                  tooltip: 'Draw on this layer',
                ),
              ],
            ),
            onTap: () {
              page.activeLayerIndex = layerIdx;
              onLayersChanged?.call();
            },
          );
        }),
        const SizedBox(height: 16),
        if (page.layerCount < 4)
          FilledButton.icon(
            onPressed: coreInfo.readOnly
                ? null
                : () {
                    page.addLayer();
                    onLayersChanged?.call();
                  },
            icon: const Icon(Icons.add),
            label: const Text('Add Layer'),
          ),
        const SizedBox(height: 16),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Layers', style: theme.textTheme.titleMedium),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: listContent),
      ],
    );
  }
}

class _BackgroundSettingsView extends StatelessWidget {
  final BoxFit currentFit;
  final bool isInverted;
  final VoidCallback onBack;
  final ValueChanged<BoxFit> onSetFit;
  final VoidCallback? onToggleInvert;
  final VoidCallback? onRemoveBackground;
  final VoidCallback? onDeleteBackground;

  const _BackgroundSettingsView({
    super.key,
    required this.currentFit,
    required this.isInverted,
    required this.onBack,
    required this.onSetFit,
    this.onToggleInvert,
    this.onRemoveBackground,
    this.onDeleteBackground,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final settingsContent = ListView(
      key: const ValueKey('backgroundSettingsContent'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      children: [
        Text(
          'Background Fit',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<BoxFit>(
          segments: const [
            ButtonSegment<BoxFit>(
              value: BoxFit.fill,
              label: Text('Stretch'),
              icon: Icon(Icons.aspect_ratio, size: 18),
            ),
            ButtonSegment<BoxFit>(
              value: BoxFit.cover,
              label: Text('Cover'),
              icon: Icon(Icons.crop, size: 18),
            ),
            ButtonSegment<BoxFit>(
              value: BoxFit.contain,
              label: Text('Contain'),
              icon: Icon(Icons.fit_screen, size: 18),
            ),
          ],
          selected: {currentFit},
          onSelectionChanged: (Set<BoxFit> selection) {
            onSetFit(selection.single);
          },
        ),
        const SizedBox(height: 24),
        Text(
          'Display Options',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Invert Colors'),
          subtitle: const Text('Ideal for dark mode'),
          secondary: Icon(
            isInverted ? Icons.invert_colors : Icons.invert_colors_off,
            color: colorScheme.onSurface,
          ),
          value: isInverted,
          onChanged: (_) => onToggleInvert?.call(),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Actions',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        _MenuSection(
          children: [
            _MenuTile(
              icon: Icons.layers_clear,
              title: 'Remove as background',
              onTap: () => onRemoveBackground?.call(),
            ),
            _MenuTile(
              icon: Icons.delete_forever_outlined,
              title: 'Delete Background',
              textColor: colorScheme.error,
              iconColor: colorScheme.error,
              onTap: () => onDeleteBackground?.call(),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );

    return Column(
      key: const ValueKey('backgroundSettings'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Background Settings',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: settingsContent),
      ],
    );
  }
}

class _PageSettingsSidebarView extends StatelessWidget {
  const _PageSettingsSidebarView({
    super.key,
    required this.coreInfo,
    required this.currentPageIndex,
    required this.onBack,
    required this.onSetPattern,
    required this.onSetLineHeight,
    required this.onSetLineThickness,
    required this.onSetColor,
    required this.onSetLineColor,
    this.onSetPageOrientation,
    required this.onToggleGlobalBackgroundInversion,
    this.onSetMargins,
    this.onSetBorderColor,
  });

  final EditorCoreInfo coreInfo;
  final int currentPageIndex;
  final VoidCallback onBack;
  final ValueChanged<CanvasBackgroundPattern> onSetPattern;
  final ValueChanged<int> onSetLineHeight;
  final ValueChanged<double> onSetLineThickness;
  final ValueChanged<Color> onSetColor;
  final ValueChanged<Color> onSetLineColor;
  final ValueChanged<PageOrientation>? onSetPageOrientation;
  final ValueChanged<bool> onToggleGlobalBackgroundInversion;
  final void Function(double left, double right, double top, double bottom)?
      onSetMargins;
  final ValueChanged<Color>? onSetBorderColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('pageSettingsSidebar'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Page Settings', style: theme.textTheme.titleMedium),
                    Text(
                      'Page ${currentPageIndex + 1} · pattern, colors, margins',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: EditorPageSettingsBody(
            coreInfo: coreInfo,
            currentPageIndex: currentPageIndex,
            onSetPattern: onSetPattern,
            onSetLineHeight: onSetLineHeight,
            onSetLineThickness: onSetLineThickness,
            onSetColor: onSetColor,
            onSetLineColor: onSetLineColor,
            onSetPageOrientation: onSetPageOrientation,
            onToggleGlobalBackgroundInversion: onToggleGlobalBackgroundInversion,
            onSetMargins: onSetMargins,
            onSetBorderColor: onSetBorderColor,
          ),
        ),
      ],
    );
  }
}

class _InkDefaultsSidebarView extends StatefulWidget {
  const _InkDefaultsSidebarView({
    super.key,
    required this.onBack,
    this.onChanged,
    this.noteSessionBackup,
  });

  final VoidCallback onBack;
  final VoidCallback? onChanged;
  final NoteToolSettings? noteSessionBackup;

  @override
  State<_InkDefaultsSidebarView> createState() => _InkDefaultsSidebarViewState();
}

class _InkDefaultsSidebarViewState extends State<_InkDefaultsSidebarView> {
  var _dirty = false;

  @override
  void initState() {
    super.initState();
    InkPresetLibrary.applyActive(stows);
  }

  void _onChanged() {
    _dirty = true;
    widget.onChanged?.call();
  }

  void _handleBack() {
    final backup = widget.noteSessionBackup;
    if (!_dirty && backup != null) {
      applyNoteToolSettings(backup);
    }
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('inkDefaultsSidebar'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _handleBack,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.settings.noteInkDefaults.inkDefaultsTitle,
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      t.settings.noteInkDefaults.inkDefaultsSubtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: InkDefaultsSettingsBody(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            onChanged: _onChanged,
          ),
        ),
      ],
    );
  }
}

class _MatrixCalculatorDialog extends StatefulWidget {
  static Future<Uint8List?> show(BuildContext context) async {
    return await showDialog<Uint8List>(
      context: context,
      builder: (context) => const _MatrixCalculatorDialog(),
    );
  }

  const _MatrixCalculatorDialog();
  @override
  State<_MatrixCalculatorDialog> createState() =>
      _MatrixCalculatorDialogState();
}

class _MatrixCalculatorDialogState extends State<_MatrixCalculatorDialog> {
  String _op = '+';
  int _rowsA = 2;
  int _colsA = 2;
  int _rowsB = 2;
  int _colsB = 2;

  List<List<TextEditingController>> _matrixA = [];
  List<List<TextEditingController>> _matrixB = [];

  @override
  void initState() {
    super.initState();
    _initMatrix(true);
    _initMatrix(false);
  }

  void _initMatrix(bool isA) {
    final rows = isA ? _rowsA : _rowsB;
    final cols = isA ? _colsA : _colsB;
    final m = List.generate(
      rows,
      (r) => List.generate(cols, (c) => TextEditingController(text: '0')),
    );
    if (isA)
      _matrixA = m;
    else
      _matrixB = m;
  }

  Future<void> _renderAndReturn() async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;

    final textStyle = ui.TextStyle(
      color: textColor,
      fontSize: 24,
      fontFamily: 'monospace',
      fontWeight: ui.FontWeight.w600,
    );
    final builder =
        ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
          ..pushStyle(textStyle)
          ..addText('Generated Matrix Operation:\n\n[A]\n');

    for (int r = 0; r < _rowsA; r++) {
      builder.addText('[ ');
      for (int c = 0; c < _colsA; c++) {
        builder.addText('${_matrixA[r][c].text} ');
      }
      builder.addText(']\n');
    }

    if (_op == '+' || _op == '-' || _op == '*') {
      builder.addText('\n$_op\n\n[B]\n');
      for (int r = 0; r < _rowsB; r++) {
        builder.addText('[ ');
        for (int c = 0; c < _colsB; c++) {
          builder.addText('${_matrixB[r][c].text} ');
        }
        builder.addText(']\n');
      }
    }

    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 500));
    canvas.drawParagraph(paragraph, const Offset(0, 0));

    final img = await recorder.endRecording().toImage(
      500,
      (paragraph.height + 40).toInt(),
    );
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null && mounted) {
      Navigator.of(context).pop(byteData.buffer.asUint8List());
    }
  }

  Widget _buildMatrixInput(bool isA) {
    final rows = isA ? _rowsA : _rowsB;
    final cols = isA ? _colsA : _colsB;
    final matrix = isA ? _matrixA : _matrixB;
    return Column(
      children: [
        Text(
          isA ? 'Matrix A' : 'Matrix B',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        for (int r = 0; r < rows; r++) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int c = 0; c < cols; c++) ...[
                Container(
                  width: 50,
                  height: 40,
                  margin: const EdgeInsets.all(4),
                  child: TextField(
                    controller: matrix[r][c],
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey.withOpacity(0.1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUnary = _op == 'T' || _op == 'RREF' || _op == 'INV';
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: cs.surfaceContainerHigh,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Matrix calculator',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Define matrices and an operation, then render as an image.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  value: _op,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.withOpacity(0.1),
                  ),
                  items: const [
                    DropdownMenuItem(value: '+', child: Text('Addition (+)')),
                    DropdownMenuItem(
                      value: '-',
                      child: Text('Subtraction (-)'),
                    ),
                    DropdownMenuItem(
                      value: '*',
                      child: Text('Multiplication (*)'),
                    ),
                    DropdownMenuItem(
                      value: 'T',
                      child: Text('Transpose (A^T)'),
                    ),
                    DropdownMenuItem(
                      value: 'RREF',
                      child: Text('Row Echelon Form (RREF)'),
                    ),
                    DropdownMenuItem(
                      value: 'INV',
                      child: Text('Inverse (A^-1)'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _op = v);
                  },
                ),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('Dim: '),
                              SizedBox(
                                width: 50,
                                child: TextField(
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  onChanged: (v) => setState(() {
                                    _rowsA = int.tryParse(v) ?? 2;
                                    _initMatrix(true);
                                  }),
                                  decoration: const InputDecoration(
                                    hintText: 'R',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const Text(' x '),
                              SizedBox(
                                width: 50,
                                child: TextField(
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  onChanged: (v) => setState(() {
                                    _colsA = int.tryParse(v) ?? 2;
                                    _initMatrix(true);
                                  }),
                                  decoration: const InputDecoration(
                                    hintText: 'C',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildMatrixInput(true),
                        ],
                      ),
                    ),
                    if (!isUnary) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 40,
                        ),
                        child: Icon(Icons.compare_arrows),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('Dim: '),
                                SizedBox(
                                  width: 50,
                                  child: TextField(
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    onChanged: (v) => setState(() {
                                      _rowsB = int.tryParse(v) ?? 2;
                                      _initMatrix(false);
                                    }),
                                    decoration: const InputDecoration(
                                      hintText: 'R',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const Text(' x '),
                                SizedBox(
                                  width: 50,
                                  child: TextField(
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    onChanged: (v) => setState(() {
                                      _colsB = int.tryParse(v) ?? 2;
                                      _initMatrix(false);
                                    }),
                                    decoration: const InputDecoration(
                                      hintText: 'C',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildMatrixInput(false),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        MaterialLocalizations.of(context).cancelButtonLabel,
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _renderAndReturn,
                      child: const Text('Render equation'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
