// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

part of 'editor.dart';

enum _MenuPage { main, pageSettings, backgroundSettings, layers }

const List<Color> _pageColorPresets = [

  Color(0xFFFFFFFF),
  Color(0xFFFFFBF5),
  Color(0xFFF8F8F8),
  Color(0xFFF0F4F8),
  Color(0xFFF5F0FF),
  Color(0xFFF8F6F0),
  Color(0xFFEDEAE6),
  Color(0xFFE8ECF0),
  Color(0xFFF5E6E8),
  Color(0xFFE8F4F0),
  Color(0xFFF5F5F0),
  Color(0xFFEEEEF2),

  Color(0xFF1A1A1A),
  Color(0xFF2D2D2D),
  Color(0xFF37474F),
  Color(0xFF263238),
  Color(0xFF3E2723),
  Color(0xFF1B2838),
  Color(0xFF2C1810),
  Color(0xFF1E2A2A),
  Color(0xFF2D2432),
  Color(0xFF252525),
  Color(0xFF2A2A2E),
  Color(0xFF1C1C1C),
];

const List<Color> _lineColorPresets = [

  Color(0xFFBDBDBD),
  Color(0xFF9E9E9E),
  Color(0xFF90A4AE),
  Color(0xFF78909C),
  Color(0xFFB0BEC5),
  Color(0xFFA0A0A0),
  Color(0xFF8D8D8D),
  Color(0xFF9CA3AF),
  Color(0xFF94A3B8),
  Color(0xFFADB5BD),
  Color(0xFF6B7280),
  Color(0xFF6B6B6B),

  Color(0xFF616161),
  Color(0xFF546E7A),
  Color(0xFF607D8B),
  Color(0xFF37474F),
  Color(0xFF455A64),
  Color(0xFF4A5568),
  Color(0xFF525252),
  Color(0xFF424242),
  Color(0xFF3D3D3D),
  Color(0xFF2D3748),
  Color(0xFF374151),
  Color(0xFF1F2937),
];

class ModernEditorMenu extends StatefulWidget {
  final EditorCoreInfo coreInfo;
  final int currentPageIndex;
  final bool invert;
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
  final Future<void> Function() onPlotFunction;
  final Future<void> Function() onPlotSurface;
  final Future<void> Function(int rows, int cols) onInsertTable;
  final Future<void> Function(Uint8List imageBytes)? onInsertMatrixImage;
  final VoidCallback onToggleCalculator;
  final VoidCallback onManageTagsAndLinks;

  /// Runs ML Kit on all handwritten strokes in the note (per page) for copyable LaTeX.
  final Future<void> Function()? onNoteHandwritingToLatex;

  final Function(BuildContext) onExportSba;
  final Function(BuildContext) onExportPdf;
  final Function(BuildContext) onExportPng;

  final Future<void> Function()? onSetCustomThumbnail;

  final Future<void> Function() onDeleteNote;
  final Future<void> Function()? onShowProperties;
  final VoidCallback? onOpenSplitView;
  final VoidCallback? onCloseSplitView;
  final VoidCallback? onReopenSplitView;
  final VoidCallback? onSwapSplitView;
  final VoidCallback? onToggleSplitAxis;
  final bool splitHasSecondary;
  final Axis? splitAxis;

  final VoidCallback? onLayersChanged;

  final ValueChanged<bool> onToggleGlobalBackgroundInversion;

  const ModernEditorMenu({
    super.key,
    required this.coreInfo,
    required this.currentPageIndex,
    required this.invert,
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
    required this.onPlotFunction,
    required this.onPlotSurface,
    required this.onInsertTable,
    this.onInsertMatrixImage,
    required this.onToggleCalculator,
    required this.onManageTagsAndLinks,
    this.onNoteHandwritingToLatex,
    required this.onExportSba,
    required this.onExportPdf,
    required this.onExportPng,
    this.onSetCustomThumbnail,
    required this.onDeleteNote,
    this.onShowProperties,
    this.onOpenSplitView,
    this.onCloseSplitView,
    this.onReopenSplitView,
    this.onSwapSplitView,
    this.onToggleSplitAxis,
    this.splitHasSecondary = false,
    this.splitAxis,
    this.onLayersChanged,
    required this.onToggleGlobalBackgroundInversion,
  });

  @override
  State<ModernEditorMenu> createState() => _ModernEditorMenuState();
}

class _ModernEditorMenuState extends State<ModernEditorMenu> {
  _MenuPage _page = _MenuPage.main;
  late bool _localBackgroundInverted;
  late BoxFit _currentFit;

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
      constraints: const BoxConstraints(maxHeight: 600),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: switch (_page) {
          _MenuPage.main => _buildMainMenu(context, colorScheme),
          _MenuPage.pageSettings => _StyleSettingsView(
            key: const ValueKey('pageSettings'),
            title: 'Page Settings (Page ${widget.currentPageIndex + 1})',
            coreInfo: widget.coreInfo,
            currentPageIndex: widget.currentPageIndex,
            invert: widget.invert,
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
            pageSize: widget.coreInfo.pages[widget.currentPageIndex].size,
            backgroundImage:
                widget.coreInfo.pages[widget.currentPageIndex].backgroundImage,
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
        },
      ),
    );
  }

  Widget _buildMainMenu(BuildContext context, ColorScheme colors) {

    IconData bgIcon = Icons.image;
    if (widget.hasBackground && widget.coreInfo.pages.isNotEmpty) {
      final img =
          widget.coreInfo.pages[widget.currentPageIndex].backgroundImage;
      if (img is PdfEditorImage) {
        bgIcon = Icons.picture_as_pdf;
      }
    }

    return ListView(
      key: const ValueKey('main'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        const SizedBox(height: 8),
        if (widget.onSetCustomThumbnail != null) ...[
          _MenuLargeCard(
            icon: Icons.image_outlined,
            title: 'Set Custom Thumbnail',
            subtitle: 'Choose an image for the note preview',
            color: colors.surfaceContainerHighest,
            onTap: () {
              widget.onClose();
              Future.delayed(const Duration(milliseconds: 300), () {
                widget.onSetCustomThumbnail?.call();
              });
            },
          ),
          const SizedBox(height: 12),
        ],
        _MenuLargeCard(
          icon: Icons.tune,
          title: 'Page Settings',
          subtitle: 'Adjust page style (Pattern, Colors, Lines)',
          color: colors.surfaceContainerHighest,
          onTap: () => setState(() => _page = _MenuPage.pageSettings),
        ),

        const SizedBox(height: 12),
        _MenuLargeCard(
          icon: Icons.layers,
          title: "Layers",
          subtitle: "Add layers, reorder, choose where to draw",
          color: colors.surfaceContainerHighest,
          onTap: () => setState(() => _page = _MenuPage.layers),
        ),

        if (widget.hasBackground) ...[
          const SizedBox(height: 12),
          _MenuLargeCard(
            icon: bgIcon,
            title: "Background Settings",
            subtitle: "Image & Fit Options",
            color: colors.surfaceContainerHighest,
            onTap: () => setState(() => _page = _MenuPage.backgroundSettings),
          ),
        ],

        const SizedBox(height: 24),
        if (widget.onOpenSplitView != null ||
            widget.onCloseSplitView != null ||
            widget.onReopenSplitView != null ||
            widget.onSwapSplitView != null ||
            widget.onToggleSplitAxis != null) ...[
          Text("Split View", style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _MenuSection(
            children: [
              if (!widget.splitHasSecondary && widget.onOpenSplitView != null)
                _MenuTile(
                  icon: Icons.view_week,
                  title: "Open Second Note",
                  onTap: () {
                    widget.onClose();
                    widget.onOpenSplitView?.call();
                  },
                ),
              if (widget.splitHasSecondary && widget.onReopenSplitView != null)
                _MenuTile(
                  icon: Icons.folder_open,
                  title: "Reopen split view",
                  onTap: () {
                    widget.onClose();
                    widget.onReopenSplitView?.call();
                  },
                ),
              if (widget.splitHasSecondary && widget.onSwapSplitView != null)
                _MenuTile(
                  icon: Icons.swap_horiz,
                  title: "Swap Notes",
                  onTap: () {
                    widget.onClose();
                    widget.onSwapSplitView?.call();
                  },
                ),
              if (widget.splitHasSecondary && widget.onToggleSplitAxis != null)
                _MenuTile(
                  icon: widget.splitAxis == Axis.vertical
                      ? Icons.view_week
                      : Icons.view_day,
                  title: widget.splitAxis == Axis.vertical
                      ? "Switch to Left/Right"
                      : "Switch to Top/Bottom",
                  onTap: () {
                    widget.onClose();
                    widget.onToggleSplitAxis?.call();
                  },
                ),
              if (widget.splitHasSecondary && widget.onCloseSplitView != null)
                _MenuTile(
                  icon: Icons.close,
                  title: "Close Split View",
                  onTap: () {
                    widget.onClose();
                    widget.onCloseSplitView?.call();
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        Text("Data & Tools", style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _MenuSection(
          children: [
            _MenuTile(
              icon: Icons.show_chart,
              title: "Plot Function",
              onTap: () async {

                await widget.onPlotFunction();
                widget.onClose();
              },
            ),
            _MenuTile(
              icon: Icons.table_chart_outlined,
              title: "Insert Table",
              onTap: () async {

                final rowsCols = await _TableDialog.show(context);
                if (rowsCols != null) {
                  widget.onClose();
                  await widget.onInsertTable(rowsCols.$1, rowsCols.$2);
                }
              },
            ),
            if (widget.onInsertMatrixImage != null)
              _MenuTile(
                icon: Icons.data_array,
                title: "Matrix Calculator",
                onTap: () async {

                  final result = await _MatrixCalculatorDialog.show(context);
                  if (result != null) {
                    widget.onClose();
                    await widget.onInsertMatrixImage!(result);
                  }
                },
              ),
            _MenuTile(
              icon: Icons.link,
              title: "Tags & Links",
              onTap: () {
                widget.onClose();
                widget.onManageTagsAndLinks();
              },
            ),
            if (widget.onNoteHandwritingToLatex != null)
              _MenuTile(
                icon: Icons.functions_outlined,
                title: t.editor.noteHandwritingToLatex,
                onTap: () async {
                  widget.onClose();
                  await widget.onNoteHandwritingToLatex!();
                },
              ),
            ValueListenableBuilder(
              valueListenable: stows.enableFingerDrawing,
              builder: (context, enabled, _) {
                return _MenuTile(
                  icon: enabled ? Icons.touch_app : Icons.do_not_touch,
                  title: "Finger Drawing",
                  iconColor: enabled ? colors.primary : null,
                  textColor: enabled ? colors.primary : null,
                  onTap: () {
                    stows.enableFingerDrawing.value = !enabled;
                  },
                );
              },
            ),
          ],
        ),

        const SizedBox(height: 16),
        Text("Insert", style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _MenuSection(
          children: [
            _MenuTile(
              icon: Icons.image_outlined,
              title: "Image",
              onTap: () {
                widget.onPickImage();
              },
            ),
            _MenuTile(
              icon: Icons.picture_as_pdf_outlined,
              title: "PDF",
              onTap: () async {
                await widget.onImportPdf();
              },
            ),
          ],
        ),

        const SizedBox(height: 16),
        Text("Export", style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _MenuSection(
          children: [
            _MenuTile(
              icon: Icons.save_as_outlined,
              title: "Note Archive (.sba)",
              onTap: () => widget.onExportSba(context),
            ),
            _MenuTile(
              icon: Icons.picture_as_pdf,
              title: "PDF Document",
              onTap: () => widget.onExportPdf(context),
            ),
            _MenuTile(
              icon: Icons.image,
              title: "Image (PNG / JPEG)",
              onTap: () => widget.onExportPng(context),
            ),
          ],
        ),

        const SizedBox(height: 16),
        Text("Actions", style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _MenuSection(
          children: [
            _MenuTile(
              icon: Icons.cleaning_services_outlined,
              title: "Clear Current Page",
              textColor: colors.error,
              iconColor: colors.error,
              onTap: () {
                widget.onClose();
                widget.onClearPage();
              },
            ),
            _MenuTile(
              icon: Icons.delete_forever_outlined,
              title: "Clear All Pages",
              textColor: colors.error,
              iconColor: colors.error,
              onTap: () {
                widget.onClose();
                widget.onClearAll();
              },
            ),
            _MenuTile(
              icon: Icons.delete_outline,
              title: "Delete Note",
              textColor: colors.error,
              iconColor: colors.error,
              onTap: () async {
                widget.onClose();
                await widget.onDeleteNote();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        _MenuLargeCard(
          icon: Icons.info_outline,
          title: "Properties",
          subtitle: "Note size, dates, and time spent",
          color: colors.surfaceContainerHighest,
          onTap: () async {
            widget.onClose();
            if (widget.onShowProperties != null) {
              await widget.onShowProperties!();
            } else {
              showNotePropertiesDialog(context, widget.coreInfo);
            }
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _MenuSection extends StatelessWidget {
  final List<Widget> children;
  const _MenuSection({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
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
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(
        icon,
        color: iconColor ?? Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: textColor ?? Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w500,
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
  final Color color;
  final VoidCallback onTap;

  const _MenuLargeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 24,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
}

class _StyleSettingsView extends StatefulWidget {
  final String title;
  final EditorCoreInfo coreInfo;
  final int currentPageIndex;
  final bool invert;
  final VoidCallback onBack;
  final ValueChanged<CanvasBackgroundPattern>? onSetPattern;
  final ValueChanged<int> onSetLineHeight;
  final ValueChanged<double> onSetLineThickness;
  final ValueChanged<Color> onSetColor;
  final ValueChanged<Color> onSetLineColor;
  final ValueChanged<PageOrientation>? onSetPageOrientation;
  final ValueChanged<bool> onToggleGlobalBackgroundInversion;
  final void Function(double left, double right, double top, double bottom)?
  onSetMargins;
  final ValueChanged<Color>? onSetBorderColor;

  const _StyleSettingsView({
    super.key,
    required this.title,
    required this.coreInfo,
    required this.currentPageIndex,
    required this.invert,
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

  @override
  State<_StyleSettingsView> createState() => _StyleSettingsViewState();
}

class _StyleSettingsViewState extends State<_StyleSettingsView> {
  late CanvasBackgroundPattern _pattern;
  late int _lineHeight;
  late double _lineThickness;
  late Color _pageColor;
  late Color _lineColor;
  late TextEditingController _hexController;
  late TextEditingController _hexLineController;
  late Size _pageSize;
  late bool _invertInDarkMode;
  late bool _invertBackground;
  late double _marginLeft;
  late double _marginRight;
  late double _marginTop;
  late double _marginBottom;
  late Color _borderColor;
  late TextEditingController _hexBorderController;
  @override
  void initState() {
    super.initState();
    _hexController = TextEditingController();
    _hexLineController = TextEditingController();
    _hexBorderController = TextEditingController();
    _invertInDarkMode = getEffectiveNoteInvertInDarkModeForFile(
      widget.coreInfo.filePath,
    );
    _invertBackground = getEffectiveNoteInvertBackgroundForFile(
      widget.coreInfo.filePath,
    );
    _syncFromMetadata();
  }

  @override
  void didUpdateWidget(covariant _StyleSettingsView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.coreInfo != widget.coreInfo) {
      _syncFromMetadata();
    }
  }

  void _syncFromMetadata() {
    final ci = widget.coreInfo;
    ci.ensureDocumentDefaultsFromGlobal();
    _pattern = ci.noteDefaultPattern!;
    _lineHeight = ci.noteDefaultLineHeight!;
    _lineThickness = ci.noteDefaultLineThickness!;
    _pageColor = Color(ci.noteDefaultPageColor!);
    _lineColor = Color(ci.noteDefaultLineColor!);
    _marginLeft = ci.noteDefaultMarginLeft!;
    _marginRight = ci.noteDefaultMarginRight!;
    _marginTop = ci.noteDefaultMarginTop!;
    _marginBottom = ci.noteDefaultMarginBottom!;
    _borderColor = ci.noteDefaultBorderColor != null
        ? Color(ci.noteDefaultBorderColor!)
        : Colors.transparent;

    final page = ci.pages[widget.currentPageIndex];
    _pageSize = page.size;

    _hexBorderController.text =
        '#${_borderColor.value.toRadixString(16).substring(2).toUpperCase()}';
    _hexController.text =
        '#${_pageColor.value.toRadixString(16).substring(2).toUpperCase()}';
    _hexLineController.text =
        '#${_lineColor.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  @override
  void dispose() {
    _hexController.dispose();
    _hexLineController.dispose();
    _hexBorderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final previewWidget = LayoutBuilder(
      builder: (context, constraints) {
        final pageAspect = _pageSize.width / _pageSize.height;
        final maxW = (constraints.maxWidth - 48).clamp(50.0, double.infinity);
        final maxH = (constraints.maxHeight - 48).clamp(50.0, double.infinity);
        double w = maxW;
        double h = w / pageAspect;
        if (h > maxH) {
          h = maxH;
          w = h * pageAspect;
        }
        final previewWidth = w.clamp(50.0, double.infinity);
        final previewHeight = previewWidth / pageAspect;

        final paintWidth = previewWidth;
        final content = Container(
          decoration: BoxDecoration(
            color: _pageColor,
            border: Border.all(color: colorScheme.outlineVariant, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: CanvasBackgroundPreview(
            selected: true,
            invert: _invertInDarkMode,
            backgroundColor: _pageColor,
            backgroundPattern: _pattern,
            backgroundImage: null,
            pageSize: _pageSize,
            lineHeight: _lineHeight,
            lineThickness: _lineThickness.toInt(),
            lineColor: _lineColor,
            width: paintWidth,
            marginLeft: _marginLeft,
            marginRight: _marginRight,
            marginTop: _marginTop,
            marginBottom: _marginBottom,
            borderColor: _borderColor,
            key: ValueKey(
              'preview_${_pattern.index}_$_lineHeight'
              '_${_lineThickness}_${_lineColor.value}_${_pageColor.value}'
              '_${_marginLeft}_${_marginRight}_${_marginTop}_${_marginBottom}_${_borderColor.value}',
            ),
          ),
        );

        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: SizedBox(
              width: previewWidth,
              height: previewHeight,
              child: content,
            ),
          ),
        );
      },
    );

    Widget buildModernSwitch({
      required String title,
      required String subtitle,
      required bool value,
      required ValueChanged<bool> onChanged,
    }) {
      return Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
          value: value,
          onChanged: onChanged,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }

    Widget buildSectionTitle(String title) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 8),
        child: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colorScheme.primary,
            letterSpacing: 0.3,
          ),
        ),
      );
    }

    Widget _marginSlider(
      String label,
      double value,
      ValueChanged<double> onChanged,
    ) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                '${value.toInt()}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Slider(
            value: value.clamp(0.0, 50.0),
            min: 0,
            max: 50,
            divisions: 50,
            onChanged: onChanged,
          ),
          const SizedBox(height: 12),
        ],
      );
    }

    Widget buildColorPresets(
      List<Color> presets,
      Color selected,
      ValueChanged<Color> onSelect,
    ) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(
          children: presets.map((color) {
            final isSelected = selected.value == color.value;
            return GestureDetector(
              onTap: () => onSelect(color),
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.outlineVariant.withOpacity(0.5),
                    width: isSelected ? 3 : 1,
                  ),
                  boxShadow: [
                    if (isSelected)
                      BoxShadow(
                        color: colorScheme.primary.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    else
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      );
    }

    final settingsContent = ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      children: [
        buildSectionTitle('General Settings'),
        buildModernSwitch(
          title: 'Invert in dark mode',
          subtitle: 'Override app setting just for this note',
          value: _invertInDarkMode,
          onChanged: (value) {
            setState(() => _invertInDarkMode = value);
            setNoteInvertInDarkModeOverrideForFile(
              widget.coreInfo.filePath,
              value,
            );
          },
        ),
        if (_invertInDarkMode) ...[
          const SizedBox(height: 12),
          buildModernSwitch(
            title: 'Invert Background',
            subtitle: 'Apply dark mode inversion to background images',
            value: _invertBackground,
            onChanged: (value) {
              setState(() => _invertBackground = value);
              setNoteInvertBackgroundOverrideForFile(
                widget.coreInfo.filePath,
                value,
              );
              widget.onToggleGlobalBackgroundInversion(value);
            },
          ),
        ],
        if (widget.onSetPageOrientation != null) ...[
          const SizedBox(height: 24),
          buildSectionTitle('Orientation'),
          SegmentedButton<PageOrientation>(
            style: SegmentedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            segments: const [
              ButtonSegment<PageOrientation>(
                value: PageOrientation.portrait,
                icon: Icon(Icons.stay_current_portrait),
                label: Text('Portrait'),
              ),
              ButtonSegment<PageOrientation>(
                value: PageOrientation.landscape,
                icon: Icon(Icons.stay_current_landscape),
                label: Text('Landscape'),
              ),
            ],
            selected: {widget.coreInfo.notePageOrientation},
            onSelectionChanged: (Set<PageOrientation> selected) {
              widget.onSetPageOrientation!(selected.single);
              setState(() {});
            },
          ),
        ],

        const SizedBox(height: 32),
        buildSectionTitle('Background Pattern'),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 3.5,
          children: CanvasBackgroundPattern.values.map((pattern) {
            final isSelected = _pattern == pattern;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  if (widget.onSetPattern != null) {
                    setState(() => _pattern = pattern);
                    widget.onSetPattern!(pattern);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceContainerHighest.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? colorScheme.primary
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    CanvasBackgroundPattern.localizedName(pattern),
                    textAlign: TextAlign.center,
                    maxLines:
                        1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: isSelected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 32),
        buildSectionTitle('Page Color'),
        buildColorPresets(_pageColorPresets, _pageColor, (color) {
          setState(() {
            _pageColor = color;
            _hexController.text =
                '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
          });
          widget.onSetColor(color);
        }),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            children: [
              ColorPicker(
                color: _pageColor,
                onColorChanged: (color) {
                  setState(() {
                    _pageColor = color;
                    _hexController.text =
                        '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
                  });
                  widget.onSetColor(color);
                },
                pickersEnabled: const {ColorPickerType.wheel: true},
                enableShadesSelection: false,
                showColorName: false,
                showRecentColors: false,
                showColorCode: false,
                enableOpacity: false,
                hasBorder: false,
                wheelDiameter: 200,
                wheelWidth: 16,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _hexController,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
                decoration: InputDecoration(
                  labelText: 'HEX Code',
                  hintText: '#FFFFFF',
                  prefixIcon: const Icon(Icons.tag, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: colorScheme.surface,
                  isDense: true,
                ),
                onChanged: (value) {
                  if (value.startsWith('#') && value.length == 7) {
                    try {
                      final color = Color(
                        int.parse(value.substring(1), radix: 16) + 0xFF000000,
                      );
                      setState(() => _pageColor = color);
                      widget.onSetColor(color);
                    } catch (_) {}
                  }
                },
              ),
            ],
          ),
        ),

        if (_pattern != CanvasBackgroundPattern.none) ...[
          const SizedBox(height: 32),
          buildSectionTitle('Line Settings'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Spacing',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${_lineHeight}px',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Slider(
                  value: _lineHeight.toDouble(),
                  min: 20,
                  max: 100,
                  divisions: 80,
                  onChanged: (v) {
                    setState(() => _lineHeight = v.toInt());
                    widget.onSetLineHeight(_lineHeight);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Thickness',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${_lineThickness.toStringAsFixed(1)}px',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Slider(
                  value: _lineThickness.clamp(1.0, 5.0),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  onChanged: (v) {
                    setState(() => _lineThickness = v);
                    widget.onSetLineThickness(v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          buildSectionTitle('Line Color'),
          buildColorPresets(_lineColorPresets, _lineColor, (color) {
            setState(() {
              _lineColor = color;
              _hexLineController.text =
                  '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
            });
            widget.onSetLineColor(color);
          }),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              children: [
                ColorPicker(
                  color: _lineColor,
                  onColorChanged: (color) {
                    setState(() {
                      _lineColor = color;
                      _hexLineController.text =
                          '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
                    });
                    widget.onSetLineColor(color);
                  },
                  pickersEnabled: const {ColorPickerType.wheel: true},
                  enableShadesSelection: false,
                  showColorName: false,
                  showRecentColors: false,
                  showColorCode: false,
                  enableOpacity: false,
                  hasBorder: false,
                  wheelDiameter: 200,
                  wheelWidth: 16,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _hexLineController,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                  decoration: InputDecoration(
                    labelText: 'HEX Code',
                    hintText: '#808080',
                    prefixIcon: const Icon(Icons.tag, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: colorScheme.surface,
                    isDense: true,
                  ),
                  onChanged: (value) {
                    if (value.startsWith('#') && value.length == 7) {
                      try {
                        final color = Color(
                          int.parse(value.substring(1), radix: 16) + 0xFF000000,
                        );
                        setState(() => _lineColor = color);
                        widget.onSetLineColor(color);
                      } catch (_) {}
                    }
                  },
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 32),
        buildSectionTitle('Margins'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _marginSlider('Left', _marginLeft, (v) {
                setState(() => _marginLeft = v);
                widget.onSetMargins?.call(
                  v,
                  _marginRight,
                  _marginTop,
                  _marginBottom,
                );
              }),
              _marginSlider('Right', _marginRight, (v) {
                setState(() => _marginRight = v);
                widget.onSetMargins?.call(
                  _marginLeft,
                  v,
                  _marginTop,
                  _marginBottom,
                );
              }),
              _marginSlider('Top', _marginTop, (v) {
                setState(() => _marginTop = v);
                widget.onSetMargins?.call(
                  _marginLeft,
                  _marginRight,
                  v,
                  _marginBottom,
                );
              }),
              _marginSlider('Bottom', _marginBottom, (v) {
                setState(() => _marginBottom = v);
                widget.onSetMargins?.call(
                  _marginLeft,
                  _marginRight,
                  _marginTop,
                  v,
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 32),
        buildSectionTitle('Border Color'),
        buildColorPresets(_pageColorPresets, _borderColor, (color) {
          setState(() {
            _borderColor = color;
            _hexBorderController.text =
                '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
          });
          widget.onSetBorderColor?.call(color);
        }),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            children: [
              ColorPicker(
                color: _borderColor,
                onColorChanged: (color) {
                  setState(() {
                    _borderColor = color;
                    _hexBorderController.text =
                        '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
                  });
                  widget.onSetBorderColor?.call(color);
                },
                pickersEnabled: const {ColorPickerType.wheel: true},
                enableShadesSelection: false,
                showColorName: false,
                showRecentColors: false,
                showColorCode: false,
                enableOpacity: false,
                hasBorder: false,
                wheelDiameter: 200,
                wheelWidth: 16,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _hexBorderController,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
                decoration: InputDecoration(
                  labelText: 'HEX Code',
                  hintText: '#FFFFFF',
                  prefixIcon: const Icon(Icons.tag, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: colorScheme.surface,
                  isDense: true,
                ),
                onChanged: (value) {
                  if (value.startsWith('#') && value.length == 7) {
                    try {
                      final color = Color(
                        int.parse(value.substring(1), radix: 16) + 0xFF000000,
                      );
                      setState(() => _borderColor = color);
                      widget.onSetBorderColor?.call(color);
                    } catch (_) {}
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
      ],
    );

    return Column(
      key: const ValueKey('pageSettings'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [

        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.title, style: theme.textTheme.titleMedium),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 600) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: settingsContent),
                    const VerticalDivider(width: 1),
                    Expanded(flex: 4, child: previewWidget),
                  ],
                );
              } else {
                return Column(
                  children: [
                    SizedBox(height: 250, child: previewWidget),
                    const Divider(height: 1),
                    Expanded(child: settingsContent),
                  ],
                );
              }
            },
          ),
        ),
      ],
    );
  }
}

class _InlineColorPicker extends StatefulWidget {
  const _InlineColorPicker({required this.color, required this.onColorChanged});

  final Color color;
  final ValueChanged<Color> onColorChanged;

  @override
  State<_InlineColorPicker> createState() => _InlineColorPickerState();
}

class _InlineColorPickerState extends State<_InlineColorPicker> {
  late TextEditingController _hexController;
  late Color _currentColor;

  @override
  void initState() {
    super.initState();
    _currentColor = widget.color;
    _hexController = TextEditingController(text: _colorToHex(widget.color));
  }

  @override
  void didUpdateWidget(covariant _InlineColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color) {
      _currentColor = widget.color;
      _hexController.text = _colorToHex(widget.color);
    }
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  String _colorToHex(Color c) {
    return '#${c.red.toRadixString(16).padLeft(2, '0')}'
        '${c.green.toRadixString(16).padLeft(2, '0')}'
        '${c.blue.toRadixString(16).padLeft(2, '0')}';
  }

  void _applyHex(String hex) {
    hex = hex.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.length == 6) {
      final r = int.tryParse(hex.substring(0, 2), radix: 16);
      final g = int.tryParse(hex.substring(2, 4), radix: 16);
      final b = int.tryParse(hex.substring(4, 6), radix: 16);
      if (r != null && g != null && b != null) {
        final color = Color.fromARGB(255, r, g, b);
        _currentColor = color;
        widget.onColorChanged(color);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColorPicker(
          color: _currentColor,
          onColorChanged: (c) {
            setState(() {
              _currentColor = c;
              _hexController.text = _colorToHex(c);
            });
            widget.onColorChanged(c);
          },
          pickersEnabled: const <ColorPickerType, bool>{
            ColorPickerType.primary: false,
            ColorPickerType.accent: false,
            ColorPickerType.bw: false,
            ColorPickerType.custom: false,
            ColorPickerType.wheel: true,
          },
          showColorCode: false,
          width: 36,
          height: 36,
          borderRadius: 6,
          enableOpacity: false,
          crossAxisAlignment: CrossAxisAlignment.start,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _hexController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '#RRGGBB',
            isDense: true,
          ),
          maxLength: 7,
          onSubmitted: _applyHex,
          onChanged: (s) {
            if (s.length == 7 && s.startsWith('#')) {
              _applyHex(s);
            }
          },
        ),
      ],
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
  final Size pageSize;
  final EditorImage? backgroundImage;
  final VoidCallback onBack;
  final ValueChanged<BoxFit> onSetFit;
  final VoidCallback? onToggleInvert;
  final VoidCallback? onRemoveBackground;
  final VoidCallback? onDeleteBackground;

  const _BackgroundSettingsView({
    super.key,
    required this.currentFit,
    required this.isInverted,
    required this.pageSize,
    required this.backgroundImage,
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

    final previewWidget = Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: AspectRatio(
          aspectRatio: pageSize.width / pageSize.height,
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              border: Border.all(color: colorScheme.outlineVariant, width: 2),
              borderRadius: BorderRadius.circular(12),

            ),
            clipBehavior: Clip.antiAlias,
            child: CanvasBackgroundPreview(
              selected: true,
              invert: isInverted,
              backgroundColor: Colors.transparent,
              backgroundPattern: CanvasBackgroundPattern.none,
              backgroundImage: backgroundImage,
              pageSize: pageSize,
              lineHeight: 0,
              lineThickness: 0,
              lineColor: Colors.transparent,
            ),
          ),
        ),
      ),
    );

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

        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 600) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: settingsContent),
                    const VerticalDivider(width: 1),
                    Expanded(flex: 4, child: previewWidget),
                  ],
                );
              } else {
                return Column(
                  children: [
                    SizedBox(height: 250, child: previewWidget),
                    const Divider(height: 1),
                    Expanded(child: settingsContent),
                  ],
                );
              }
            },
          ),
        ),
      ],
    );
  }
}

class _TableDialog extends StatefulWidget {
  static Future<(int, int)?> show(BuildContext context) async {
    final result = await showDialog<(int, int)>(
      context: context,
      builder: (context) => const _TableDialog(),
    );
    return result;
  }

  const _TableDialog();

  @override
  State<_TableDialog> createState() => _TableDialogState();
}

class _TableDialogState extends State<_TableDialog> {
  final _rowsCtrl = TextEditingController(text: '3');
  final _colsCtrl = TextEditingController(text: '3');

  @override
  void dispose() {
    _rowsCtrl.dispose();
    _colsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.65),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.grey.withOpacity(0.3), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 40,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Create table',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _rowsCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Rows',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.withOpacity(0.1),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _colsCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Columns',
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
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      backgroundColor: Colors.grey.shade800,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () {
                      final rows = int.tryParse(_rowsCtrl.text) ?? 0;
                      final cols = int.tryParse(_colsCtrl.text) ?? 0;
                      if (rows < 1 || cols < 1) {
                        Navigator.of(context).pop();
                        return;
                      }
                      Navigator.of(context).pop((rows, cols));
                    },
                    child: Text(
                      MaterialLocalizations.of(context).okButtonLabel,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: 700,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.65),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.grey.withOpacity(0.3), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 40,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Matrix Calculator',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
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
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        backgroundColor: Colors.grey.shade800,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _renderAndReturn,
                      child: const Text('Render Equation'),
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
