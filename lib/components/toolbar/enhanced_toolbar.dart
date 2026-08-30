// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:saber/components/toolbar/advanced_pen_panel.dart';
import 'package:saber/components/toolbar/advanced_pencil_panel.dart';
import 'package:saber/components/toolbar/color_toolbar.dart';
import 'package:saber/components/toolbar/notes_color_picker_modal.dart';
import 'package:saber/components/toolbar/pen_size_preset_toolbar.dart';
import 'package:saber/components/toolbar/size_picker.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/laser_pointer.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/pen_size_preset_support.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/data/tools/shape_tool.dart';
import 'package:saber/i18n/strings.g.dart';

class EnhancedToolbar extends StatefulWidget {
  const EnhancedToolbar({
    super.key,
    required this.readOnly,
    required this.setTool,
    required this.currentTool,
    required this.setColor,
    required this.invert,
    required this.axis,
    this.onColorChanged,
    this.onToolbarSlotsChanged,
    required this.undo,
    required this.isUndoPossible,
    required this.redo,
    required this.isRedoPossible,
    this.duplicateSelection,
    this.deleteSelection,
    this.paste,
    this.copyToClipboard,
    this.cutToClipboard,
    this.toggleInvertible,
    this.exportAsSba,
    this.exportAsPdf,
    this.exportAsPng,
    this.onToggleCalculator,
    this.onOpenMatrixCalculator,
    this.onManageTagsAndLinks,
    this.onRegionScreenshot,
    this.regionScreenshotActive = false,
    required this.quillFocus,
    required this.applyPenPresetStrokeWidth,
    required this.onPenPresetNoteDirty,
  });

  final bool readOnly;
  final ValueChanged<Tool> setTool;
  final Tool currentTool;
  final ValueChanged<Color> setColor;
  final bool invert;
  final Axis axis;
  final ValueChanged<Color>? onColorChanged;
  /// Note-local toolbar slot edits (must not mutate ink presets).
  final VoidCallback? onToolbarSlotsChanged;
  final VoidCallback undo;
  final bool isUndoPossible;
  final VoidCallback redo;
  final bool isRedoPossible;
  final VoidCallback? paste;
  final VoidCallback? duplicateSelection;
  final VoidCallback? deleteSelection;
  final VoidCallback? copyToClipboard;
  final VoidCallback? cutToClipboard;
  final VoidCallback? toggleInvertible;
  final Future Function(BuildContext)? exportAsSba;
  final Future Function(BuildContext)? exportAsPdf;
  final Future Function(BuildContext)? exportAsPng;
  final VoidCallback? onToggleCalculator;
  final VoidCallback? onOpenMatrixCalculator;
  final VoidCallback? onManageTagsAndLinks;
  /// Starts (or cancels) drag-to-select region screenshot mode.
  final VoidCallback? onRegionScreenshot;
  final bool regionScreenshotActive;
  final ValueNotifier<QuillStruct?> quillFocus;
  final ValueChanged<double> applyPenPresetStrokeWidth;
  final VoidCallback onPenPresetNoteDirty;

  @override
  State<EnhancedToolbar> createState() => EnhancedToolbarState();
}

class EnhancedToolbarState extends State<EnhancedToolbar> {
  OverlayEntry? _penCardOverlay;
  OverlayEntry? _highlighterCardOverlay;
  OverlayEntry? _eraserCardOverlay;
  OverlayEntry? _shapeCardOverlay;
  OverlayEntry? _exportCardOverlay;
  OverlayEntry? _laserCardOverlay;

  final ValueNotifier<int?> _penPresetSelectionIndex = ValueNotifier(null);

  final GlobalKey _penButtonKey = GlobalKey();
  final GlobalKey _highlighterButtonKey = GlobalKey();
  final GlobalKey _eraserButtonKey = GlobalKey();
  final GlobalKey _shapeButtonKey = GlobalKey();
  final GlobalKey _exportButtonKey = GlobalKey();
  final GlobalKey _textButtonKey = GlobalKey();
  final GlobalKey _laserButtonKey = GlobalKey();

  void hideAllCards({bool notify = true}) {
    _hidePenCard();
    _hideHighlighterCard();
    _hideEraserCard();
    _hideShapeCard();
    _hideExportCard();
    _hideLaserCard();
    if (notify && mounted) setState(() {});
  }

  OverlayEntry _buildPopover({
    required GlobalKey buttonKey,
    required Widget Function() childBuilder,
    required VoidCallback onClose,
    String? title,
    double maxWidth = 480,
    double maxHeight = 640,
  }) {
    return OverlayEntry(
      builder: (context) {
        return _PopoverOverlay(
          buttonKey: buttonKey,
          onClose: onClose,
          title: title,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          child: childBuilder(),
        );
      },
    );
  }

  @override
  void didUpdateWidget(covariant EnhancedToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldT = oldWidget.currentTool;
    final newT = widget.currentTool;
    if (!_sameDrawingToolIdentity(oldT, newT)) {
      final keepPenPresetSelection =
          newT is Eraser ||
          (oldT is Eraser && toolSupportsPenSizePresets(newT));
      if (!keepPenPresetSelection) {
        _penPresetSelectionIndex.value = null;
      }
    }
    for (final overlay in [
      _penCardOverlay,
      _highlighterCardOverlay,
      _eraserCardOverlay,
      _shapeCardOverlay,
      _exportCardOverlay,
      _laserCardOverlay,
    ]) {
      overlay?.markNeedsBuild();
    }
  }

  Color? get currentColor {
    return switch (widget.currentTool) {
      final Pen pen => pen.color,
      final Select select => select.getDominantStrokeColor(),
      _ => null,
    };
  }

  bool get _isPenTool =>
      widget.currentTool is Pen && widget.currentTool is! Highlighter;

  bool _sameDrawingToolIdentity(Tool a, Tool b) {
    if (identical(a, b)) return true;
    return a.toolId == b.toolId;
  }

  void _showPenCard() {
    if (_penCardOverlay != null) return;
    _penCardOverlay = _buildPopover(
      buttonKey: _penButtonKey,
      maxWidth: 480,
      maxHeight: 720,
      title: 'Pens',
      onClose: _hidePenCard,
      childBuilder: () => _PenSelectionCard(
        axis: widget.axis,
        currentTool: widget.currentTool,
        currentColor: currentColor,
        setTool: widget.setTool,
        setColor: (color) {
          widget.setColor(color);
          widget.onColorChanged?.call(color);
        },
        invert: widget.invert,
        onClose: _hidePenCard,
      ),
    );
    Overlay.of(context).insert(_penCardOverlay!);
  }

  void _hidePenCard() {
    _penCardOverlay?.remove();
    _penCardOverlay = null;
  }

  void _showHighlighterCard() {
    if (_highlighterCardOverlay != null) return;
    _highlighterCardOverlay = _buildPopover(
      buttonKey: _highlighterButtonKey,
      maxWidth: 360,
      maxHeight: 560,
      title: t.editor.pens.highlighter,
      onClose: _hideHighlighterCard,
      childBuilder: () => _HighlighterSelectionCard(
        axis: widget.axis,
        currentTool: widget.currentTool,
        currentColor: currentColor,
        setTool: widget.setTool,
        setColor: (color) {
          widget.setColor(color);
          widget.onColorChanged?.call(color);
        },
        invert: widget.invert,
        onClose: _hideHighlighterCard,
      ),
    );
    Overlay.of(context).insert(_highlighterCardOverlay!);
  }

  void _hideHighlighterCard() {
    _highlighterCardOverlay?.remove();
    _highlighterCardOverlay = null;
  }

  void _showShapeCard() {
    if (_shapeCardOverlay != null) return;
    _shapeCardOverlay = _buildPopover(
      buttonKey: _shapeButtonKey,
      maxWidth: 520,
      maxHeight: 680,
      title: 'Shape tool',
      onClose: _hideShapeCard,
      childBuilder: () => _ShapeSelectionCard(
        axis: widget.axis,
        currentTool: widget.currentTool,
        currentColor: currentColor,
        setTool: widget.setTool,
        setColor: (color) {
          widget.setColor(color);
          widget.onColorChanged?.call(color);
        },
        invert: widget.invert,
        onClose: _hideShapeCard,
      ),
    );
    Overlay.of(context).insert(_shapeCardOverlay!);
  }

  void _hideShapeCard() {
    _shapeCardOverlay?.remove();
    _shapeCardOverlay = null;
  }

  void _showEraserCard() {
    if (_eraserCardOverlay != null) return;
    _eraserCardOverlay = _buildPopover(
      buttonKey: _eraserButtonKey,
      maxWidth: 340,
      maxHeight: 360,
      title: t.editor.toolbar.toggleEraser,
      onClose: _hideEraserCard,
      childBuilder: () => _EraserSelectionCard(
        axis: widget.axis,
        onClose: _hideEraserCard,
        setTool: widget.setTool,
      ),
    );
    Overlay.of(context).insert(_eraserCardOverlay!);
  }

  void _hideEraserCard() {
    _eraserCardOverlay?.remove();
    _eraserCardOverlay = null;
  }

  void _showExportCard() {
    if (_exportCardOverlay != null) return;
    _exportCardOverlay = _buildPopover(
      buttonKey: _exportButtonKey,
      maxWidth: 320,
      maxHeight: 280,
      title: t.editor.toolbar.export,
      onClose: _hideExportCard,
      childBuilder: () => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ExportOptionTile(
            icon: Icons.save_as_outlined,
            label: 'Note Archive (.sba)',
            onTap: () {
              _hideExportCard();
              if (widget.exportAsSba != null) widget.exportAsSba!(context);
            },
          ),
          const SizedBox(height: 8),
          _ExportOptionTile(
            icon: Icons.picture_as_pdf_outlined,
            label: 'PDF Document',
            onTap: () {
              _hideExportCard();
              if (widget.exportAsPdf != null) widget.exportAsPdf!(context);
            },
          ),
          const SizedBox(height: 8),
          _ExportOptionTile(
            icon: Icons.image_outlined,
            label: 'Image (PNG / JPEG)',
            onTap: () {
              _hideExportCard();
              if (widget.exportAsPng != null) widget.exportAsPng!(context);
            },
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_exportCardOverlay!);
  }

  void _hideExportCard() {
    _exportCardOverlay?.remove();
    _exportCardOverlay = null;
  }

  void _showLaserCard() {
    if (_laserCardOverlay != null) return;
    _laserCardOverlay = _buildPopover(
      buttonKey: _laserButtonKey,
      maxWidth: 360,
      maxHeight: 320,
      title: t.editor.pens.laserPointer,
      onClose: _hideLaserCard,
      childBuilder: () => _LaserOptionsCard(onClose: _hideLaserCard),
    );
    Overlay.of(context).insert(_laserCardOverlay!);
  }

  void _hideLaserCard() {
    _laserCardOverlay?.remove();
    _laserCardOverlay = null;
  }

  @override
  void dispose() {
    hideAllCards(notify: false);
    _penPresetSelectionIndex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final axisDir = stows.editorToolbarAlignment.value;

    final isHorizontal = widget.axis == Axis.horizontal;

    Widget mainToolbar = Container(
      width: widget.axis == Axis.vertical ? 56 : double.infinity,
      height: widget.axis == Axis.horizontal ? 56 : double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : colorScheme.surfaceContainerHigh,
        border: Border(
          top: axisDir == AxisDirection.down
              ? BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3), width: 1)
              : BorderSide.none,
          bottom: axisDir == AxisDirection.up
              ? BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3), width: 1)
              : BorderSide.none,
          left: axisDir == AxisDirection.right
              ? BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3), width: 1)
              : BorderSide.none,
          right: axisDir == AxisDirection.left
              ? BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3), width: 1)
              : BorderSide.none,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Center(
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            scrollDirection: widget.axis,
            physics: const BouncingScrollPhysics(),
            child: ValueListenableBuilder<int?>(
              valueListenable: _penPresetSelectionIndex,
              builder: (context, presetIdx, _) {
                final presetIndexForUi = widget.currentTool is Eraser ? null : presetIdx;
                
                Widget verticalDivider = Container(
                  width: widget.axis == Axis.horizontal ? 1 : 24,
                  height: widget.axis == Axis.horizontal ? 24 : 1,
                  margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
                );

                return Flex(
                  direction: widget.axis,
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _ToolIconButton(
                      key: _penButtonKey,
                      icon: _getPenIcon(),
                      tooltip: _isPenTool ? (widget.currentTool as Pen).name : t.editor.pens.ballpointPen,
                      isSelected: _isPenTool && presetIdx == null,
                      onTap: () {
                        if (_isPenTool) {
                          _penPresetSelectionIndex.value = null;
                          if (_penCardOverlay != null) {
                            _hidePenCard();
                          } else {
                            hideAllCards();
                            _showPenCard();
                          }
                        } else {
                          hideAllCards();
                          _penPresetSelectionIndex.value = null;
                          widget.setTool(Pen.currentPen);
                        }
                      },
                      readOnly: widget.readOnly,
                    ),
                    
                    _ToolIconButton(
                      key: _highlighterButtonKey,
                      icon: const FaIcon(Highlighter.highlighterIcon, size: 18),
                      tooltip: t.editor.pens.highlighter,
                      isSelected: widget.currentTool is Highlighter && presetIdx == null,
                      onTap: () {
                        if (widget.currentTool is Highlighter) {
                          _penPresetSelectionIndex.value = null;
                          if (_highlighterCardOverlay != null) {
                            _hideHighlighterCard();
                          } else {
                            hideAllCards();
                            _showHighlighterCard();
                          }
                        } else {
                          hideAllCards();
                          _penPresetSelectionIndex.value = null;
                          widget.setTool(Highlighter.currentHighlighter);
                        }
                      },
                      readOnly: widget.readOnly,
                    ),

                    _ToolIconButton(
                      key: _eraserButtonKey,
                      icon: const FaIcon(FontAwesomeIcons.eraser, size: 18),
                      tooltip: t.editor.toolbar.toggleEraser,
                      isSelected: widget.currentTool is Eraser,
                      onTap: () {
                        if (widget.currentTool is Eraser) {
                          if (_eraserCardOverlay != null) {
                            _hideEraserCard();
                          } else {
                            hideAllCards();
                            _showEraserCard();
                          }
                        } else {
                          hideAllCards();
                          widget.setTool(Eraser.currentEraser);
                        }
                      },
                      readOnly: widget.readOnly,
                    ),
                    
                    verticalDivider,

                    PenSizePresetToolbar(
                      axis: widget.axis,
                      readOnly: widget.readOnly,
                      selectedPresetIndex: presetIndexForUi,
                      onPresetSelected: (i) {
                        _penPresetSelectionIndex.value = i;
                      },
                      applyStrokeWidthFromPreset: widget.applyPenPresetStrokeWidth,
                      onPresetSizesChangedForNote: widget.onPenPresetNoteDirty,
                    ),
                    
                    ColorToolbar(
                      axis: widget.axis,
                      setColor: (color) {
                        widget.setColor(color);
                        widget.onColorChanged?.call(color);
                      },
                      currentColor: currentColor,
                      invert: widget.invert,
                      onSlotsChanged: widget.onToolbarSlotsChanged,
                    ),

                    verticalDivider,

                    _ToolIconButton(
                      icon: const Icon(CupertinoIcons.lasso, size: 20),
                      tooltip: t.editor.toolbar.select,
                      isSelected: widget.currentTool is Select,
                      onTap: () {
                        hideAllCards();
                        widget.setTool(Select.currentSelect);
                      },
                      readOnly: widget.readOnly,
                    ),

                    _ToolIconButton(
                      key: _textButtonKey,
                      icon: const Icon(Icons.text_fields, size: 20),
                      tooltip: t.editor.toolbar.text,
                      isSelected: widget.currentTool == Tool.textEditing,
                      onTap: () {
                        hideAllCards();
                        if (widget.currentTool != Tool.textEditing) {
                          widget.setTool(Tool.textEditing);
                        }
                      },
                      readOnly: widget.readOnly,
                    ),

                    _ToolIconButton(
                      key: _shapeButtonKey,
                      icon: const FaIcon(FontAwesomeIcons.shapes, size: 18),
                      tooltip: 'Shape tool',
                      isSelected: widget.currentTool is ShapeTool && presetIdx == null,
                      onTap: () {
                        if (widget.currentTool is ShapeTool) {
                          _penPresetSelectionIndex.value = null;
                          if (_shapeCardOverlay != null) {
                            _hideShapeCard();
                          } else {
                            hideAllCards();
                            _showShapeCard();
                          }
                        } else {
                          hideAllCards();
                          _penPresetSelectionIndex.value = null;
                          widget.setTool(ShapeTool.currentShapeTool);
                        }
                      },
                      readOnly: widget.readOnly,
                    ),
                    
                    verticalDivider,

                    _ToolIconButton(
                      icon: const Icon(Icons.undo, size: 20),
                      tooltip: t.editor.toolbar.undo,
                      isSelected: false,
                      onTap: widget.undo,
                      readOnly: widget.readOnly || !widget.isUndoPossible,
                    ),
                    _ToolIconButton(
                      icon: const Icon(Icons.redo, size: 20),
                      tooltip: t.editor.toolbar.redo,
                      isSelected: false,
                      onTap: widget.redo,
                      readOnly: widget.readOnly || !widget.isRedoPossible,
                    ),

                    verticalDivider,

                    _ToolIconButton(
                      key: _exportButtonKey,
                      icon: const Icon(Icons.ios_share_rounded, size: 20),
                      tooltip: t.editor.toolbar.export,
                      isSelected: false,
                      onTap: () {
                        if (_exportCardOverlay != null) {
                          _hideExportCard();
                        } else {
                          hideAllCards();
                          _showExportCard();
                        }
                      },
                      readOnly: false,
                    ),
                    
                    if (widget.onToggleCalculator != null || widget.onOpenMatrixCalculator != null || widget.onRegionScreenshot != null) ...[
                       verticalDivider,
                       if (widget.onToggleCalculator != null)
                        _ToolIconButton(
                          icon: const Icon(Icons.calculate_outlined, size: 20),
                          tooltip: 'Calculator',
                          isSelected: false,
                          onTap: () {
                            hideAllCards();
                            widget.onToggleCalculator!();
                          },
                          readOnly: false,
                        ),
                      if (widget.onOpenMatrixCalculator != null)
                        _ToolIconButton(
                          icon: const Icon(Icons.data_array, size: 20),
                          tooltip: 'Matrix Calculator',
                          isSelected: false,
                          onTap: () {
                            hideAllCards();
                            widget.onOpenMatrixCalculator!();
                          },
                          readOnly: false,
                        ),
                      if (widget.onRegionScreenshot != null)
                        _ToolIconButton(
                          icon: const Icon(Icons.crop_free, size: 20),
                          tooltip: t.editor.toolbar.regionScreenshot,
                          isSelected: widget.regionScreenshotActive,
                          onTap: () {
                            hideAllCards();
                            widget.onRegionScreenshot!();
                          },
                          readOnly: false,
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    if (widget.currentTool == Tool.textEditing) {
      return Flex(
        direction: isHorizontal ? Axis.vertical : Axis.horizontal,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          mainToolbar,
          Container(
            height: isHorizontal ? 1 : null,
            width: isHorizontal ? null : 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
          _InlineTextToolbar(quillFocus: widget.quillFocus, axis: widget.axis),
        ],
      );
    }

    return mainToolbar;
  }

  Widget _getPenIcon() {
    final pen =
        (widget.currentTool is Pen && widget.currentTool is! Highlighter)
        ? widget.currentTool as Pen
        : Pen.currentPen;

    if (pen.toolId == ToolId.fountainPen) {
      return const FaIcon(FontAwesomeIcons.penFancy, size: 18);
    } else if (pen.toolId == ToolId.calligraphyPen) {
      return const FaIcon(FontAwesomeIcons.penNib, size: 18);
    } else {
      return const FaIcon(FontAwesomeIcons.pen, size: 18);
    }
  }
}

class _ToolIconButton extends StatelessWidget {
  const _ToolIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.isSelected,
    required this.onTap,
    required this.readOnly,
  });

  final Widget icon;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onTap;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: readOnly ? null : onTap,
          borderRadius: BorderRadius.circular(24), // Circular/Pílula
          child: Opacity(
            opacity: readOnly ? 0.4 : 1.0,
            child: Container(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              decoration: BoxDecoration(
                color: isSelected
                    ? (isDark ? colorScheme.primary.withOpacity(0.15) : colorScheme.primaryContainer)
                    : Colors.transparent, // Fundo invisível se não selecionado
                borderRadius: BorderRadius.circular(24),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Center(
                child: IconTheme(
                  data: IconThemeData(
                    color: isSelected 
                      ? colorScheme.primary 
                      : colorScheme.onSurfaceVariant,
                  ),
                  child: icon,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
class _PenSelectionCard extends StatefulWidget {
  const _PenSelectionCard({
    required this.axis,
    required this.currentTool,
    required this.currentColor,
    required this.setTool,
    required this.setColor,
    required this.invert,
    required this.onClose,
  });

  final Axis axis;
  final Tool currentTool;
  final Color? currentColor;
  final ValueChanged<Tool> setTool;
  final ValueChanged<Color> setColor;
  final bool invert;
  final VoidCallback onClose;

  @override
  State<_PenSelectionCard> createState() => _PenSelectionCardState();
}

class _PenSelectionCardState extends State<_PenSelectionCard> {
  Pen? _selectedPen;

  @override
  void initState() {
    super.initState();
    if (widget.currentTool is Pen && widget.currentTool is! Highlighter) {
      _selectedPen = widget.currentTool as Pen;
    } else {
      final lastPenId = stows.lastPenType.value;
      switch (lastPenId) {
        case ToolId.ballpointPen:
          _selectedPen = Pen.ballpointPen();
          break;
        case ToolId.calligraphyPen:
          _selectedPen = Pen.calligraphyPen();
          break;
        case ToolId.fountainPen:
          _selectedPen = Pen.fountainPen();
          break;
        case ToolId.shapePen:
          _selectedPen = Pen.ballpointPen();
          break;
        case ToolId.advancedPen:
        case ToolId.experimentalPen:
          _selectedPen = Pen.advancedPen();
          break;
        case ToolId.advancedPencil:
          _selectedPen = Pen.advancedPencil();
          break;
        default:
          _selectedPen = Pen.ballpointPen();
          break;
      }
    }
  }

  @override
  void didUpdateWidget(_PenSelectionCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.currentTool is Pen &&
        widget.currentTool is! Highlighter &&
        !identical(_selectedPen, widget.currentTool)) {
      _selectedPen = widget.currentTool as Pen;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activePen = _selectedPen ?? Pen.currentPen;

    Widget sectionTitle(String title) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.labelMedium?.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sectionTitle("Pen Style"),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildPenCard(Pen.ballpointPen(), const Icon(Symbols.ink_pen, size: 18), t.editor.pens.ballpointPen),
            _buildPenCard(Pen.calligraphyPen(), const Icon(Symbols.brush, size: 18), t.editor.pens.calligraphyPen),
            _buildPenCard(Pen.fountainPen(), const Icon(Symbols.stylus_note, size: 18), t.editor.pens.fountainPen),
            _buildPenCard(Pen.advancedPencil(), const FaIcon(FontAwesomeIcons.pencil, size: 16), t.editor.pens.advancedPencil),
            _buildPenCard(Pen.advancedPen(), const FaIcon(FontAwesomeIcons.sliders, size: 16), t.editor.pens.advancedPen),
          ],
        ),
        const Divider(height: 32),

        if (_penHasFavoriteColors(activePen)) ...[
          sectionTitle("Color"),
          _buildPenColorSwatches(context, activePen, colorScheme),
          const Divider(height: 32),
        ],

        sectionTitle("Size"),
        SizePicker(axis: Axis.horizontal, pen: activePen),
        const Divider(height: 32),

        if (activePen.toolId == ToolId.advancedPen) ...[
          AdvancedPenPresets(
            pen: activePen,
            onChanged: () {
              stows.lastAdvancedPenOptions.value = activePen.options.copyWith();
              setState(() {});
            },
          ),
          const Divider(height: 32),
        ],
        if (activePen.toolId == ToolId.advancedPencil) ...[
          AdvancedPencilPresets(
            pen: activePen,
            onChanged: () {
              stows.lastAdvancedPencilOptions.value = activePen.options.copyWith();
              stows.lastAdvancedPencilPaint.value = Map<String, dynamic>.from(activePen.paint.toJson(embedBytes: false));
              setState(() {});
            },
          ),
          const Divider(height: 32),
        ],

        sectionTitle("Drawing Assist"),
        ValueListenableBuilder(
          valueListenable: stows.strokeStabilization,
          builder: (context, enabled, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(t.settings.prefLabels.strokeStabilization, style: theme.textTheme.bodyMedium),
                  value: enabled,
                  onChanged: (v) => stows.strokeStabilization.value = v,
                ),
                if (enabled)
                  ValueListenableBuilder(
                    valueListenable: stows.strokeStabilizationAmount,
                    builder: (context, amount, _) => Slider(
                      value: amount,
                      onChanged: (v) => stows.strokeStabilizationAmount.value = v,
                    ),
                  ),
              ],
            );
          },
        ),

        ValueListenableBuilder(
          valueListenable: stows.strokePrediction,
          builder: (context, enabled, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(t.settings.prefLabels.strokePrediction, style: theme.textTheme.bodyMedium),
                  value: enabled,
                  onChanged: (v) => stows.strokePrediction.value = v,
                ),
                if (enabled)
                  ValueListenableBuilder(
                    valueListenable: stows.strokePredictionAmount,
                    builder: (context, amount, _) => Slider(
                      value: amount,
                      onChanged: (v) => stows.strokePredictionAmount.value = v,
                    ),
                  ),
              ],
            );
          },
        ),

        if (_supportsNeonInk(activePen.toolId))
          ValueListenableBuilder(
            valueListenable: _neonStowFor(activePen.toolId),
            builder: (context, enabled, _) {
              return SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(t.editor.penOptions.neonStroke, style: theme.textTheme.bodyMedium),
                value: enabled,
                onChanged: (val) {
                  Pen.setNeonEnabledForTool(activePen.toolId, val);
                  setState((){});
                }
              );
            },
          ),

        if (activePen.toolId == ToolId.advancedPen) ...[
          const Divider(height: 32),
          AdvancedPenSettings(
            pen: activePen,
            onChanged: () {
              stows.lastAdvancedPenOptions.value = activePen.options.copyWith();
              setState(() {});
            },
          ),
        ],
        if (activePen.toolId == ToolId.advancedPencil) ...[
          const Divider(height: 32),
          AdvancedPencilSettings(
            pen: activePen,
            onChanged: () {
              stows.lastAdvancedPencilOptions.value = activePen.options.copyWith();
              stows.lastAdvancedPencilPaint.value = Map<String, dynamic>.from(activePen.paint.toJson(embedBytes: false));
              setState(() {});
            },
          ),
        ],
      ],
    );
  }

  static bool _supportsNeonInk(ToolId id) => id == ToolId.ballpointPen;

  static ValueNotifier<bool> _neonStowFor(ToolId id) =>
      stows.lastBallpointPenNeon;

  Widget _buildPenCard(Pen pen, Widget icon, String label) {
    final isActive = _selectedPen?.toolId == pen.toolId;
    return ChoiceChip(
      label: Text(label),
      avatar: isActive ? null : icon,
      selected: isActive,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedPen = pen;
            Pen.currentPen = pen;
            widget.setTool(pen);
          });
        }
      },
      showCheckmark: true,
    );
  }

  static bool _penHasFavoriteColors(Pen pen) {
    switch (pen.toolId) {
      case ToolId.ballpointPen:
      case ToolId.calligraphyPen:
      case ToolId.fountainPen:
      case ToolId.advancedPen:
      case ToolId.advancedPencil:
      case ToolId.shapePen:
        return true;
      default:
        return false;
    }
  }

  /// Advanced Pen/Pencil share Ballpoint's ink row so suggestions follow
  /// the selected color preset.
  static String _favoriteColorsKey(ToolId id) {
    switch (id) {
      case ToolId.advancedPen:
      case ToolId.advancedPencil:
        return ToolId.ballpointPen.id;
      default:
        return id.id;
    }
  }

  Widget _buildPenColorSwatches(
    BuildContext context,
    Pen activePen,
    ColorScheme colorScheme,
  ) {
    final favKey = _favoriteColorsKey(activePen.toolId);
    final favorites =
        stows.penFavoriteColors.value[favKey] ??
        stows.penFavoriteColors.value[ToolId.ballpointPen.id];
    final list = favorites ?? <int>[];
    final defaultBorderColor = colorScheme.onSurface.withValues(alpha: 0.5);
    return ValueListenableBuilder<Map<String, List<int>>>(
      valueListenable: stows.penFavoriteColors,
      builder: (context, value, child) {
        final fav =
            value[favKey] ?? value[ToolId.ballpointPen.id] ?? list;
        final currentArgb = activePen.color.toARGB32();

        int selectedIndex = 0;
        for (int i = 0; i < 10 && i < fav.length; i++) {
          if (fav[i] == currentArgb) {
            selectedIndex = i + 1;
            break;
          }
        }
        return Row(
          children: [
            _colorSwatch(
              context,
              activePen.color.withInversion(widget.invert),
              onTap: () => _openColorPickerForCurrent(context, activePen),
              borderColor: selectedIndex == 0
                  ? activePen.color.withInversion(widget.invert)
                  : defaultBorderColor,
            ),
            ...List.generate(10, (i) {
              final colorValue = i < fav.length ? fav[i] : 0xFF000000;
              final color = Color(colorValue).withInversion(widget.invert);
              final isSelected = selectedIndex == i + 1;
              return Padding(
                padding: const EdgeInsets.only(left: 6),
                child: _colorSwatch(
                  context,
                  color,
                  onTap: () => _applyFavoriteColor(activePen, colorValue),
                  onDoubleTap: () =>
                      _openColorPickerForFavoriteSlot(context, activePen, i),
                  borderColor: isSelected ? color : defaultBorderColor,
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _colorSwatch(
    BuildContext context,
    Color color, {
    required VoidCallback onTap,
    VoidCallback? onDoubleTap,
    required Color borderColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: SizedBox(
        width: 28,
        height: 28,
        child: CustomPaint(
          painter: _SmoothCirclePainter(
            color: color,
            borderColor: borderColor,
            borderWidth: 2.0,
            hasShadow: false,
          ),
        ),
      ),
    );
  }

  void _applyFavoriteColor(Pen activePen, int colorValue) {
    final color = Color(colorValue);
    setState(() {
      activePen.color = color;
    });
    Future.delayed(Duration.zero, () {
      if (!mounted) return;
      widget.setColor(color);
      widget.setTool(activePen);
      _persistPenColor(activePen.toolId, colorValue);
    });
  }

  void _persistPenColor(ToolId toolId, int colorValue) {
    switch (toolId) {
      case ToolId.ballpointPen:
        stows.lastBallpointPenColor.value = colorValue;
      case ToolId.calligraphyPen:
        stows.lastCalligraphyPenColor.value = colorValue;
      case ToolId.fountainPen:
        stows.lastFountainPenColor.value = colorValue;
      case ToolId.advancedPen:
        stows.lastAdvancedPenColor.value = colorValue;
      case ToolId.advancedPencil:
        stows.lastAdvancedPencilColor.value = colorValue;
      default:
    }
  }

  Future<void> _openColorPickerForCurrent(
    BuildContext context,
    Pen activePen,
  ) async {
    widget.onClose();
    final pickedColor = await showNotesColorPicker(
      context,
      initialColor: activePen.color,
    );
    if (pickedColor == null) return;
    activePen.color = pickedColor;
    widget.setColor(pickedColor);
    Pen.currentPen = activePen;
    widget.setTool(activePen);
    _persistPenColor(activePen.toolId, pickedColor.toARGB32());
  }

  Future<void> _openColorPickerForFavoriteSlot(
    BuildContext context,
    Pen activePen,
    int slotIndex,
  ) async {
    final favKey = _favoriteColorsKey(activePen.toolId);
    final favorites = List<int>.from(
      stows.penFavoriteColors.value[favKey] ??
          stows.penFavoriteColors.value[ToolId.ballpointPen.id]!,
    );
    while (favorites.length < 10) {
      favorites.add(0xFF000000);
    }
    final initial = Color(
      slotIndex < favorites.length ? favorites[slotIndex] : 0xFF000000,
    );
    widget.onClose();
    final pickedColor = await showNotesColorPicker(
      context,
      initialColor: initial,
    );
    if (pickedColor == null || slotIndex >= 10) return;
    favorites[slotIndex] = pickedColor.toARGB32();
    final updated = Map<String, List<int>>.from(stows.penFavoriteColors.value);
    updated[favKey] = favorites;
    if (activePen.toolId == ToolId.advancedPen ||
        activePen.toolId == ToolId.advancedPencil) {
      updated[activePen.toolId.id] = List<int>.from(favorites);
    }
    stows.penFavoriteColors.value = updated;
  }
}

class _HighlighterSelectionCard extends StatefulWidget {
  const _HighlighterSelectionCard({
    required this.axis,
    required this.currentTool,
    required this.currentColor,
    required this.setTool,
    required this.setColor,
    required this.invert,
    required this.onClose,
  });

  final Axis axis;
  final Tool currentTool;
  final Color? currentColor;
  final ValueChanged<Tool> setTool;
  final ValueChanged<Color> setColor;
  final bool invert;
  final VoidCallback onClose;

  @override
  State<_HighlighterSelectionCard> createState() =>
      _HighlighterSelectionCardState();
}

class _HighlighterSelectionCardState extends State<_HighlighterSelectionCard> {
  static const int _favoritesCount = 8;

  late double _currentOpacity;

  @override
  void initState() {
    super.initState();
    _currentOpacity = stows.highlighterOpacity.value;
    if (widget.currentTool is Highlighter) {
      _currentOpacity = (widget.currentTool as Highlighter).color.a;
    }
  }

  void _updateOpacity(double value) {
    setState(() => _currentOpacity = value);
    final h = widget.currentTool is Highlighter
        ? widget.currentTool as Highlighter
        : Highlighter.currentHighlighter;
    final newColor = h.color.withValues(alpha: value);
    h.color = newColor;
    widget.setColor(newColor);
    stows.highlighterOpacity.value = value;
  }

  void _applyFavoriteColor(int colorValue) {
    final color = Color(
      colorValue,
    ).withValues(alpha: stows.highlighterOpacity.value);
    final h = widget.currentTool is Highlighter
        ? widget.currentTool as Highlighter
        : Highlighter.currentHighlighter;
    h.color = color;
    widget.setColor(color);
    stows.lastHighlighterColor.value = color.toARGB32();
    setState(() {});
  }

  Future<void> _openColorPickerForSlot(int slotIndex) async {
    final favorites = List<int>.from(
      stows.penFavoriteColors.value[ToolId.highlighter.id] ??
          stows.penFavoriteColors.value[ToolId.ballpointPen.id]!,
    );
    while (favorites.length < _favoritesCount) {
      favorites.add(0xFFFDE047);
    }
    final initial = Color(
      slotIndex < favorites.length ? favorites[slotIndex] : 0xFFFDE047,
    );
    final pickedColor = await showNotesColorPicker(
      context,
      initialColor: initial,
    );
    if (pickedColor == null || !mounted) return;
    final updated = Map<String, List<int>>.from(stows.penFavoriteColors.value);
    final list = List<int>.from(
      updated[ToolId.highlighter.id] ?? updated[ToolId.ballpointPen.id]!,
    );
    while (list.length < _favoritesCount) list.add(0xFFFDE047);
    if (slotIndex < list.length) {
      list[slotIndex] = pickedColor.toARGB32();
    } else {
      list.add(pickedColor.toARGB32());
    }
    updated[ToolId.highlighter.id] = list;
    stows.penFavoriteColors.value = updated;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final highlighter = widget.currentTool is Highlighter
        ? widget.currentTool as Highlighter
        : Highlighter.currentHighlighter;
    final currentRgb = highlighter.color.toARGB32() & 0x00FFFFFF;

    Widget sectionTitle(String title) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.labelMedium?.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    return ValueListenableBuilder(
      valueListenable: stows.penFavoriteColors,
      builder: (context, _, __) {
        final fav = List<int>.from(
          stows.penFavoriteColors.value[ToolId.highlighter.id] ??
              stows.penFavoriteColors.value[ToolId.ballpointPen.id]!,
        );
        while (fav.length < _favoritesCount) fav.add(0xFFFDE047);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            sectionTitle("Color"),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(_favoritesCount, (i) {
                final colorValue = i < fav.length ? fav[i] : 0xFFFDE047;
                final isSelected = (colorValue & 0x00FFFFFF) == currentRgb;
                return Tooltip(
                  message: t.editor.colors.colorPicker,
                  child: GestureDetector(
                    onTap: () => _applyFavoriteColor(colorValue),
                    onDoubleTap: () => _openColorPickerForSlot(i),
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CustomPaint(
                        painter: _SmoothCirclePainter(
                          color: Color(colorValue),
                          borderColor: isSelected
                              ? Color(colorValue)
                              : colorScheme.onSurface.withValues(alpha: 0.5),
                          borderWidth: 2.0,
                          hasShadow: false,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const Divider(height: 32),

            sectionTitle("Size & Opacity"),
            SizePicker(axis: Axis.horizontal, pen: highlighter),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(t.editor.penOptions.opacity, style: theme.textTheme.bodyMedium),
                Expanded(
                  child: Slider(
                    value: _currentOpacity,
                    min: 0.1,
                    max: 1.0,
                    divisions: 18,
                    onChanged: _updateOpacity,
                    onChangeEnd: (v) => stows.highlighterOpacity.value = v,
                  ),
                ),
                Text('${(_currentOpacity * 100).toInt()}%', style: theme.textTheme.bodySmall),
              ],
            ),
            const Divider(height: 32),

            sectionTitle("Tip Style"),
            ValueListenableBuilder(
              valueListenable: stows.highlighterFlatEdge,
              builder: (context, flat, _) {
                return SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text(t.settings.prefLabels.highlighterCapRound)),
                    ButtonSegment(value: true, label: Text(t.settings.prefLabels.highlighterCapFlat)),
                  ],
                  selected: {flat},
                  onSelectionChanged: (s) => stows.highlighterFlatEdge.value = s.first,
                );
              },
            ),
            const Divider(height: 32),

            sectionTitle("Drawing Assist"),
            ValueListenableBuilder(
              valueListenable: Highlighter.straightLine,
              builder: (context, straight, _) {
                return SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Freehand')),
                    ButtonSegment(value: true, label: Text('Straight Line')),
                  ],
                  selected: {straight},
                  onSelectionChanged: (s) => Highlighter.straightLine.value = s.first,
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _ChipOption extends StatelessWidget {
  const _ChipOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    return Material(
      color: selected
          ? (isDark
                ? Colors.white.withValues(alpha: 0.12)
                : colorScheme.surfaceContainerHighest)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? (isDark
                        ? Colors.white.withValues(alpha: 0.2)
                        : colorScheme.outlineVariant)
                  : (isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : colorScheme.outlineVariant.withValues(alpha: 0.3)),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: selected
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LaserOptionsCard extends StatefulWidget {
  const _LaserOptionsCard({required this.onClose});

  final VoidCallback onClose;

  @override
  State<_LaserOptionsCard> createState() => _LaserOptionsCardState();
}

class _LaserOptionsCardState extends State<_LaserOptionsCard> {
  static const int _laserFavoritesCount = 9;

  Future<void> _openColorPickerForCurrent() async {
    final pickedColor = await showNotesColorPicker(
      context,
      initialColor: stows.laserPointerColor.value,
    );
    if (pickedColor == null || !mounted) return;
    setState(() {
      stows.laserPointerColor.value = pickedColor;
    });
  }

  void _applyLaserFavoriteColor(int colorValue) {
    stows.laserPointerColor.value = Color(colorValue);
    setState(() {});
  }

  Future<void> _openColorPickerForFavoriteSlot(int slotIndex) async {
    final favorites = List<int>.from(
      stows.penFavoriteColors.value[ToolId.laserPointer.id] ??
          stows.penFavoriteColors.value[ToolId.ballpointPen.id]!,
    );
    while (favorites.length < _laserFavoritesCount) {
      favorites.add(0xFFDC2626);
    }
    final initial = Color(
      slotIndex < favorites.length ? favorites[slotIndex] : 0xFFDC2626,
    );
    final pickedColor = await showNotesColorPicker(
      context,
      initialColor: initial,
    );
    if (pickedColor == null || !mounted) return;
    if (slotIndex < favorites.length) {
      favorites[slotIndex] = pickedColor.toARGB32();
    } else {
      favorites.add(pickedColor.toARGB32());
    }
    final updated = Map<String, List<int>>.from(stows.penFavoriteColors.value);
    updated[ToolId.laserPointer.id] = favorites;
    stows.penFavoriteColors.value = updated;
    setState(() {});
  }

  Widget _laserColorSwatch(
    BuildContext context,
    Color color, {
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    required Color borderColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: 28,
        height: 28,
        child: CustomPaint(
          painter: _SmoothCirclePainter(
            color: color,
            borderColor: borderColor,
            borderWidth: 2.0,
            hasShadow: false,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final defaultBorderColor = colorScheme.onSurface.withValues(alpha: 0.5);

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueListenableBuilder<Color>(
            valueListenable: stows.laserPointerColor,
            builder: (context, currentColor, _) {
              return ValueListenableBuilder<Map<String, List<int>>>(
                valueListenable: stows.penFavoriteColors,
                builder: (context, favMap, _) {
                  final fav =
                      favMap[ToolId.laserPointer.id] ??
                      favMap[ToolId.ballpointPen.id] ??
                      <int>[];
                  int selectedIndex = 0;
                  for (
                    int i = 0;
                    i < _laserFavoritesCount && i < fav.length;
                    i++
                  ) {
                    if (fav[i] == currentColor.toARGB32()) {
                      selectedIndex = i + 1;
                      break;
                    }
                  }
                  return Row(
                    children: [
                      _laserColorSwatch(
                        context,
                        currentColor,
                        onTap: _openColorPickerForCurrent,
                        borderColor: selectedIndex == 0
                            ? currentColor
                            : defaultBorderColor,
                      ),
                      ...List.generate(_laserFavoritesCount, (i) {
                        final colorValue = i < fav.length ? fav[i] : 0xFFDC2626;
                        final color = Color(colorValue);
                        final isSelected = selectedIndex == i + 1;
                        return Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: _laserColorSwatch(
                            context,
                            color,
                            onTap: () => _applyLaserFavoriteColor(colorValue),
                            onLongPress: () =>
                                _openColorPickerForFavoriteSlot(i),
                            borderColor: isSelected
                                ? color
                                : defaultBorderColor,
                          ),
                        );
                      }),
                    ],
                  );
                },
              );
            },
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<double>(
            valueListenable: stows.laserPointerSize,
            builder: (context, sizeValue, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        t.editor.penOptions.size,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const Spacer(),
                      SizedBox(
                        width: 42,
                        child: Text(
                          sizeValue.toStringAsFixed(1),
                          textAlign: TextAlign.right,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontFeatures: const [
                                  ui.FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: sizeValue.clamp(4.0, 10.0),
                    min: 4.0,
                    max: 10.0,
                    divisions: 6,
                    onChanged: (value) {
                      stows.laserPointerSize.value = value.clamp(4.0, 10.0);
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ExportOptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ExportOptionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: colorScheme.primary),
              const SizedBox(width: 14),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShapeSelectionCard extends StatefulWidget {
  const _ShapeSelectionCard({
    required this.axis,
    required this.currentTool,
    required this.currentColor,
    required this.setTool,
    required this.setColor,
    required this.invert,
    required this.onClose,
  });

  final Axis axis;
  final Tool currentTool;
  final Color? currentColor;
  final ValueChanged<Tool> setTool;
  final ValueChanged<Color> setColor;
  final bool invert;
  final VoidCallback onClose;

  @override
  State<_ShapeSelectionCard> createState() => _ShapeSelectionCardState();
}

class _ShapeSelectionCardState extends State<_ShapeSelectionCard> {
  late ShapeConfig _config = ShapeTool.currentShapeTool.config;
  late bool _fill = ShapeTool.currentShapeTool.config.fill;
  late Color _strokeColor =
      widget.currentColor ?? ShapeTool.currentShapeTool.color;

  final TextEditingController _searchController = TextEditingController();
  List<ShapeKind> _filteredShapes = ShapeKind.values
      .where((k) => k.isToolSelectable)
      .toList();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterShapes);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterShapes() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredShapes = ShapeKind.values
          .where(
            (k) =>
                k.isToolSelectable &&
                _shapeLabel(k).toLowerCase().contains(query),
          )
          .toList();
    });
  }

  void _apply() {
    ShapeTool.currentShapeTool
      ..config = _config.copyWith(fill: _fill)
      ..color = _strokeColor
      ..fillColor = _strokeColor.withOpacity(0.7);
    widget.setTool(ShapeTool.currentShapeTool);
    widget.setColor(_strokeColor);
  }

  void _showColorPicker() async {
    widget.onClose();
    final pickedColor = await showNotesColorPicker(
      context,
      initialColor: _strokeColor,
    );
    if (pickedColor == null) return;
    setState(() {
      _strokeColor = pickedColor;
      _apply();
    });
  }

  @override
  void didUpdateWidget(_ShapeSelectionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentColor != oldWidget.currentColor &&
        widget.currentColor != null) {
      _strokeColor = widget.currentColor!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    Widget sectionTitle(String title) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.labelMedium?.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sectionTitle("Stroke & Fill"),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _config.strokeWidth,
                min: 1,
                max: 20,
                onChanged: (v) {
                  setState(() {
                    _config = _config.copyWith(strokeWidth: v);
                    _apply();
                  });
                },
              ),
            ),
            SizedBox(
              width: 32,
              child: Text(
                '${_config.strokeWidth.toStringAsFixed(1)}px',
                style: theme.textTheme.bodySmall?.copyWith(fontFeatures: const [ui.FontFeature.tabularFigures()]),
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('Fill Shape', style: theme.textTheme.bodyMedium),
                value: _fill,
                onChanged: (v) {
                  setState(() {
                    _fill = v;
                    _apply();
                  });
                },
              ),
            ),
            const SizedBox(width: 16),
            GestureDetector(
              onTap: _showColorPicker,
              child: SizedBox(
                width: 28,
                height: 28,
                child: CustomPaint(
                  painter: _SmoothCirclePainter(
                    color: _strokeColor.withInversion(widget.invert),
                    borderColor: colorScheme.onSurface.withValues(alpha: 0.5),
                    borderWidth: 2.0,
                    hasShadow: false,
                  ),
                ),
              ),
            ),
          ],
        ),
        const Divider(height: 32),

        sectionTitle("Line Style"),
        SegmentedButton<ShapeStrokeStyle>(
          segments: const [
            ButtonSegment(value: ShapeStrokeStyle.solid, label: Text('Solid')),
            ButtonSegment(value: ShapeStrokeStyle.dashed, label: Text('Dashed')),
            ButtonSegment(value: ShapeStrokeStyle.dotted, label: Text('Dotted')),
          ],
          selected: {_config.strokeStyle},
          onSelectionChanged: (s) {
            setState(() {
              _config = _config.copyWith(strokeStyle: s.first);
              _apply();
            });
          },
        ),
        const Divider(height: 32),

        if (_config.kind == ShapeKind.polygon) ...[
          sectionTitle("Polygon Detail"),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _config.detail.clamp(3, 12).toDouble(),
                  min: 3,
                  max: 12,
                  divisions: 9,
                  onChanged: (v) {
                    setState(() {
                      _config = _config.copyWith(detail: v.round());
                      _apply();
                    });
                  },
                ),
              ),
              SizedBox(
                width: 32,
                child: Text(
                  '${_config.detail.clamp(3, 12)}',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          const Divider(height: 32),
        ],

        sectionTitle("Shape"),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search shapes...',
            prefixIcon: const Icon(Icons.search, size: 18),
            isDense: true,
            filled: true,
            fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            contentPadding: const EdgeInsets.all(8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 240,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 1.0,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _filteredShapes.length,
            itemBuilder: (context, index) {
              final kind = _filteredShapes[index];
              final isSelected = _config.kind == kind;

              return InkWell(
                onTap: () => setState(() {
                  _config = _config.copyWith(
                    kind: kind,
                    detail: kind == ShapeKind.polygon ? (_config.detail < 3 ? 6 : _config.detail) : _config.detail,
                  );
                  _apply();
                }),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected ? colorScheme.primaryContainer : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Tooltip(
                    message: _shapeLabel(kind),
                    child: Center(
                      child: _buildShapeIcon(
                        kind,
                        isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildShapeIcon(ShapeKind kind, Color color) {
    switch (kind) {
      case ShapeKind.ellipse:
        // Achatamos um circulo horizontalmente para criar uma elipse visual
        return Transform.scale(
          scaleX: 1.3,
          child: Icon(CupertinoIcons.circle, color: color, size: 20),
        );
      case ShapeKind.triangleRight:
        // O ícone de sinal 0 do celular desenha perfeitamente um triângulo retângulo
        return Icon(Icons.signal_cellular_0_bar, color: color, size: 24);
      case ShapeKind.rectangle:
        return Icon(CupertinoIcons.rectangle, color: color, size: 24);
      case ShapeKind.circle:
        return Icon(CupertinoIcons.circle, color: color, size: 24);
      case ShapeKind.polygon:
        return Icon(CupertinoIcons.hexagon, color: color, size: 24);
      case ShapeKind.line:
        return Icon(Icons.horizontal_rule, color: color, size: 24);
      case ShapeKind.arrow:
        return Icon(CupertinoIcons.arrow_right, color: color, size: 24);
      case ShapeKind.doubleArrow:
        return Icon(CupertinoIcons.arrow_left_right, color: color, size: 24);
      case ShapeKind.triangleIsosceles:
        return Icon(CupertinoIcons.triangle, color: color, size: 24);
      case ShapeKind.cube:
        return Icon(CupertinoIcons.cube_box, color: color, size: 24);
      case ShapeKind.cylinder:
        return Icon(Icons.inventory_2_outlined, color: color, size: 24);
      case ShapeKind.sphere:
        return Icon(Symbols.language, color: color, size: 24);
      case ShapeKind.halfSphere:
        return Icon(Icons.wifi_tethering, color: color, size: 24);
      case ShapeKind.parabola:
        return Icon(Symbols.trending_up, color: color, size: 24);
      case ShapeKind.pendulum:
        return Icon(Symbols.vibration, color: color, size: 24);
      case ShapeKind.spring:
        return Icon(Symbols.water, color: color, size: 24);
      case ShapeKind.fixedEnd:
        return Icon(Symbols.publish, color: color, size: 24);
      case ShapeKind.harmonicOscillator:
        return Icon(Symbols.graphic_eq, color: color, size: 24);
      case ShapeKind.coordinateSystem:
        return Icon(Symbols.polyline, color: color, size: 24);
      default:
        return Icon(Icons.category_outlined, color: color, size: 24);
    }
  }
  String _shapeLabel(ShapeKind kind) {
    switch (kind) {
      case ShapeKind.infinity:
        return 'Infinity';
      case ShapeKind.star:
        return 'Star';
      case ShapeKind.nabla:
        return 'Nabla';
      case ShapeKind.summatory:
        return 'Summatory';
      case ShapeKind.productory:
        return 'Productory';
      case ShapeKind.leftBracket:
        return 'Left Bracket';
      case ShapeKind.rightBracket:
        return 'Right Bracket';
      case ShapeKind.leftAngleBracket:
        return 'Left Angle Bracket';
      case ShapeKind.rightAngleBracket:
        return 'Right Angle Bracket';
      case ShapeKind.leftBrace:
        return 'Left Brace';
      case ShapeKind.rightBrace:
        return 'Right Brace';
      case ShapeKind.rectangle:
        return 'Rectangle';
      case ShapeKind.circle:
        return 'Circle';
      case ShapeKind.ellipse:
        return 'Ellipse';
      case ShapeKind.polygon:
        return 'Polygon';
      case ShapeKind.line:
        return 'Line';
      case ShapeKind.arrow:
        return 'Arrow';
      case ShapeKind.doubleArrow:
        return 'Double Arrow';
      case ShapeKind.triangleIsosceles:
        return 'Isosceles Triangle';
      case ShapeKind.triangleRight:
        return 'Right Triangle';
      case ShapeKind.cube:
        return 'Cube';
      case ShapeKind.cylinder:
        return 'Cylinder';
      case ShapeKind.sphere:
        return 'Sphere';
      case ShapeKind.halfSphere:
        return 'Half Sphere';
      case ShapeKind.parabola:
        return 'Parabola';
      case ShapeKind.pendulum:
        return 'Pendulum';
      case ShapeKind.spring:
        return 'Spring';
      case ShapeKind.fixedEnd:
        return 'Fixed End';
      case ShapeKind.harmonicOscillator:
        return 'Harmonic Oscillator';
      case ShapeKind.coordinateSystem:
        return 'Coordinate System';
      case ShapeKind.coordinateSystem3D:
        return 'Coordinate System 3D';
    }
  }
}

class _EraserSelectionCard extends StatefulWidget {
  const _EraserSelectionCard({
    required this.axis,
    required this.onClose,
    required this.setTool,
  });

  final Axis axis;
  final VoidCallback onClose;
  final ValueChanged<Tool> setTool;

  @override
  State<_EraserSelectionCard> createState() => _EraserSelectionCardState();
}

class _EraserSelectionCardState extends State<_EraserSelectionCard> {
  late double _size = Eraser.currentEraser.size;
  late EraserMode _mode = Eraser.currentEraser.mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget sectionTitle(String title) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.labelMedium?.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sectionTitle("Mode"),
        SegmentedButton<EraserMode>(
          segments: const [
            ButtonSegment(value: EraserMode.stroke, label: Text('Erase Stroke')),
            ButtonSegment(value: EraserMode.area, label: Text('Erase Area')),
          ],
          selected: {_mode},
          onSelectionChanged: (s) {
            setState(() {
              _mode = s.first;
              Eraser.currentEraser.updateMode = _mode;
              widget.setTool(Eraser.currentEraser);
            });
          },
        ),
        const Divider(height: 32),

        sectionTitle("Size"),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _size.clamp(0.5, 25),
                min: 0.5,
                max: 25,
                divisions: 49,
                onChanged: (value) {
                  setState(() {
                    _size = value;
                    Eraser.currentEraser.updateSize = value;
                    widget.setTool(Eraser.currentEraser);
                  });
                },
              ),
            ),
            SizedBox(
              width: 42,
              child: Text(
                _size.toStringAsFixed(1),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InlineTextToolbar extends StatelessWidget {
  const _InlineTextToolbar({required this.quillFocus, required this.axis});

  final ValueNotifier<QuillStruct?> quillFocus;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return ValueListenableBuilder(
      valueListenable: quillFocus,
      builder: (context, quill, _) {
        if (quill == null) {
          return const SizedBox.shrink();
        }

        final baseButtonStyle = IconButtonTheme.of(context).style ?? const ButtonStyle();
        final iconTheme = QuillIconTheme(
          iconButtonUnselectedData: IconButtonData(
            style: baseButtonStyle.copyWith(
              backgroundColor: WidgetStateProperty.all(Colors.transparent),
              foregroundColor: WidgetStateProperty.all(colorScheme.onSurfaceVariant),
            ),
          ),
          iconButtonSelectedData: IconButtonData(
            style: baseButtonStyle.copyWith(
              backgroundColor: WidgetStateProperty.all(isDark ? Colors.white.withValues(alpha: 0.12) : colorScheme.surfaceContainerHighest),
              foregroundColor: WidgetStateProperty.all(colorScheme.onSurface),
            ),
          ),
        );

        return Container(
          width: axis == Axis.vertical ? 56 : double.infinity,
          height: axis == Axis.horizontal ? 56 : double.infinity,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : colorScheme.surfaceContainerHigh,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          // Removido o SingleChildScrollView e o Center! O Quill cuidará do Scroll Nativo corretamente.
          child: QuillSimpleToolbar(
            controller: quill.controller,
            config: QuillSimpleToolbarConfig(
              multiRowsDisplay: false, 
              axis: axis,
              buttonOptions: QuillSimpleToolbarButtonOptions(
                base: QuillToolbarBaseButtonOptions(iconTheme: iconTheme),
              ),
              showBoldButton: true,
              showItalicButton: true,
              showUnderLineButton: true,
              showStrikeThrough: true,
              showInlineCode: false,
              showSubscript: false,
              showSuperscript: false,
              showColorButton: true,
              showBackgroundColorButton: true,
              showHeaderStyle: true,
              showListNumbers: true,
              showListBullets: true,
              showListCheck: true,
              showCodeBlock: false,
              showQuote: true,
              showIndent: true,
              showLink: true,
              showSearchButton: false,
              showUndo: false,
              showRedo: false,
              showFontSize: false,
              showFontFamily: false,
              showClearFormat: true,
            ),
          ),
        );
      },
    );
  }
}

class _PopoverOverlay extends StatefulWidget {
  final GlobalKey buttonKey;
  final Widget child;
  final VoidCallback onClose;
  final String? title;
  final double maxWidth;
  final double maxHeight;

  const _PopoverOverlay({
    required this.buttonKey,
    required this.child,
    required this.onClose,
    this.title,
    required this.maxWidth,
    required this.maxHeight,
  });

  @override
  State<_PopoverOverlay> createState() => _PopoverOverlayState();
}

class _PopoverOverlayState extends State<_PopoverOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _scaleAnimation = Tween<double>(
      begin: 0.95,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    final RenderBox? buttonBox =
        widget.buttonKey.currentContext?.findRenderObject() as RenderBox?;
    final buttonPos = buttonBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final buttonSize = buttonBox?.size ?? Size.zero;

    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              widget.onClose();
            },
            child: const SizedBox(),
          ),
        ),
        CustomSingleChildLayout(
          delegate: _PopoverLayoutDelegate(
            leaderGlobalPos: buttonPos,
            leaderSize: buttonSize,
            toolbarAlignment: stows.editorToolbarAlignment.value,
            safeAreaPadding: media.padding,
            screenSize: media.size,
          ),
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Material(
                elevation: 4,
                shadowColor: Colors.black.withValues(alpha: 0.2),
                color: isDark ? const Color(0xFF1E1E22) : colorScheme.surfaceContainerHigh,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: widget.maxWidth,
                        maxHeight: widget.maxHeight,
                        minWidth: 260,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.title != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : colorScheme.outlineVariant.withValues(
                                            alpha: 0.2,
                                          ),
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    widget.title!,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: widget.onClose,
                                    child: Icon(
                                      Icons.close,
                                      size: 18,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Flexible(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: widget.child,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class _PopoverLayoutDelegate extends SingleChildLayoutDelegate {
  final Offset leaderGlobalPos;
  final Size leaderSize;
  final AxisDirection toolbarAlignment;
  final EdgeInsets safeAreaPadding;
  final Size screenSize;

  static const double _margin = 12.0;
  static const double _gap = 8.0;

  _PopoverLayoutDelegate({
    required this.leaderGlobalPos,
    required this.leaderSize,
    required this.toolbarAlignment,
    required this.safeAreaPadding,
    required this.screenSize,
  });

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double x = 0;
    double y = 0;

    switch (toolbarAlignment) {
      case AxisDirection.up:
        x = leaderGlobalPos.dx + leaderSize.width / 2 - childSize.width / 2;
        y = leaderGlobalPos.dy + leaderSize.height + _gap;
      case AxisDirection.down:
        x = leaderGlobalPos.dx + leaderSize.width / 2 - childSize.width / 2;
        y = leaderGlobalPos.dy - childSize.height - _gap;
      case AxisDirection.left:
        x = leaderGlobalPos.dx + leaderSize.width + _gap;
        y = leaderGlobalPos.dy + leaderSize.height / 2 - childSize.height / 2;
      case AxisDirection.right:
        x = leaderGlobalPos.dx - childSize.width - _gap;
        y = leaderGlobalPos.dy + leaderSize.height / 2 - childSize.height / 2;
    }

    final leftLimit = safeAreaPadding.left + _margin;
    final rightLimit = screenSize.width - safeAreaPadding.right - _margin;
    final topLimit = safeAreaPadding.top + _margin;
    final bottomLimit = screenSize.height - safeAreaPadding.bottom - _margin;

    x = x.clamp(leftLimit, math.max(leftLimit, rightLimit - childSize.width));
    y = y.clamp(topLimit, math.max(topLimit, bottomLimit - childSize.height));

    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_PopoverLayoutDelegate oldDelegate) {
    return leaderGlobalPos != oldDelegate.leaderGlobalPos ||
        leaderSize != oldDelegate.leaderSize ||
        toolbarAlignment != oldDelegate.toolbarAlignment ||
        screenSize != oldDelegate.screenSize;
  }
}

class _SmoothCirclePainter extends CustomPainter {
  _SmoothCirclePainter({
    required this.color,
    required this.borderColor,
    this.borderWidth = 2.0,
    this.hasShadow = false,
  });

  final Color color;
  final Color borderColor;
  final double borderWidth;
  final bool hasShadow;

  @override
  void paint(ui.Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final fillRadius = radius - borderWidth;
    final strokeRadius = radius - borderWidth / 2;

    if (hasShadow) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.26)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    canvas.drawCircle(
      center,
      fillRadius,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );

    if (borderWidth > 0 && borderColor != Colors.transparent) {
      canvas.drawCircle(
        center,
        strokeRadius,
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth
          ..isAntiAlias = true,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SmoothCirclePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.hasShadow != hasShadow;
  }
}
