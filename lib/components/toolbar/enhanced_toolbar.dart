// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
import 'package:saber/components/toolbar/color_toolbar.dart';
import 'package:saber/components/toolbar/size_picker.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/laser_pointer.dart';
import 'package:saber/data/tools/pen.dart';
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
    required this.quillFocus,
  });

  final bool readOnly;
  final ValueChanged<Tool> setTool;
  final Tool currentTool;
  final ValueChanged<Color> setColor;
  final bool invert;
  final Axis axis;
  final ValueChanged<Color>? onColorChanged;
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
  final ValueNotifier<QuillStruct?> quillFocus;

  @override
  State<EnhancedToolbar> createState() => EnhancedToolbarState();
}

class EnhancedToolbarState extends State<EnhancedToolbar> {
  OverlayEntry? _penCardOverlay;
  OverlayEntry? _highlighterCardOverlay;
  OverlayEntry? _eraserCardOverlay;
  OverlayEntry? _shapeCardOverlay;
  OverlayEntry? _exportCardOverlay;
  OverlayEntry? _textCardOverlay;
  OverlayEntry? _laserCardOverlay;

  final GlobalKey _penButtonKey = GlobalKey();
  final GlobalKey _highlighterButtonKey = GlobalKey();
  final GlobalKey _eraserButtonKey = GlobalKey();
  final GlobalKey _shapeButtonKey = GlobalKey();
  final GlobalKey _exportButtonKey = GlobalKey();
  final GlobalKey _textButtonKey = GlobalKey();
  final GlobalKey _laserButtonKey = GlobalKey();

  void hideAllCards() {
    _hidePenCard();
    _hideHighlighterCard();
    _hideEraserCard();
    _hideShapeCard();
    _hideExportCard();
    _hideTextCard();
    _hideLaserCard();
    if (mounted) setState(() {});
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
    for (final overlay in [
      _penCardOverlay,
      _highlighterCardOverlay,
      _eraserCardOverlay,
      _shapeCardOverlay,
      _exportCardOverlay,
      _textCardOverlay,
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

  void _showPenCard() {
    if (_penCardOverlay != null) return;
    _penCardOverlay = _buildPopover(
      buttonKey: _penButtonKey,
      maxWidth: 480,
      maxHeight: 560,
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
      maxHeight: 520,
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

  void _showTextCard() {
    if (_textCardOverlay != null) return;
    _textCardOverlay = _buildPopover(
      buttonKey: _textButtonKey,
      maxWidth: 400,
      maxHeight: 500,
      title: t.editor.toolbar.text,
      onClose: _hideTextCard,
      childBuilder: () => _TextFormattingCard(
        quillFocus: widget.quillFocus,
        onClose: _hideTextCard,
      ),
    );
    Overlay.of(context).insert(_textCardOverlay!);
  }

  void _hideTextCard() {
    _textCardOverlay?.remove();
    _textCardOverlay = null;
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
    hideAllCards();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final axisDir = stows.editorToolbarAlignment.value;

    final isHorizontal = widget.axis == Axis.horizontal;

    return Container(
      width: widget.axis == Axis.vertical ? 56 : double.infinity,
      height: widget.axis == Axis.horizontal ? 56 : double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: isHorizontal ? Alignment.topCenter : Alignment.centerLeft,
          end: isHorizontal ? Alignment.bottomCenter : Alignment.centerRight,
          colors: [
            (isDark ? const Color(0xFF1A1A1A) : colorScheme.surface).withValues(
              alpha: 0.95,
            ),
            (isDark ? const Color(0xFF111111) : colorScheme.surface),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: isHorizontal ? const Offset(0, 2) : const Offset(2, 0),
          ),
        ],
        border: Border(
          top: axisDir == AxisDirection.down
              ? BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: 1,
                )
              : BorderSide.none,
          bottom: axisDir == AxisDirection.up
              ? BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: 1,
                )
              : BorderSide.none,
          left: axisDir == AxisDirection.right
              ? BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: 1,
                )
              : BorderSide.none,
          right: axisDir == AxisDirection.left
              ? BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: 1,
                )
              : BorderSide.none,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Center(
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            scrollDirection: widget.axis,
            physics: const BouncingScrollPhysics(),
            padding: widget.axis == Axis.horizontal
                ? const EdgeInsets.symmetric(horizontal: 4)
                : const EdgeInsets.symmetric(vertical: 4),
            child: Flex(
              direction: widget.axis,
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 4,
              children: [

                _ToolIconButton(
                  key: _penButtonKey,
                  icon: _getPenIcon(),
                  tooltip: _isPenTool
                      ? (widget.currentTool as Pen).name
                      : t.editor.pens.ballpointPen,
                  isSelected: _isPenTool,
                  onTap: () {
                    if (_isPenTool) {
                      if (_penCardOverlay != null) {
                        _hidePenCard();
                      } else {
                        hideAllCards();
                        _showPenCard();
                      }
                    } else {
                      hideAllCards();
                      widget.setTool(Pen.currentPen);
                    }
                  },
                  readOnly: widget.readOnly,
                ),

                _ToolIconButton(
                  key: _shapeButtonKey,
                  icon: const FaIcon(FontAwesomeIcons.shapes, size: 18),
                  tooltip: 'Shape tool',
                  isSelected: widget.currentTool is ShapeTool,
                  onTap: () {
                    if (widget.currentTool is ShapeTool) {
                      if (_shapeCardOverlay != null) {
                        _hideShapeCard();
                      } else {
                        hideAllCards();
                        _showShapeCard();
                      }
                    } else {
                      hideAllCards();
                      widget.setTool(ShapeTool.currentShapeTool);
                    }
                  },
                  readOnly: widget.readOnly,
                ),
                _ToolIconButton(
                  key: _highlighterButtonKey,
                  icon: const FaIcon(Highlighter.highlighterIcon, size: 18),
                  tooltip: t.editor.pens.highlighter,
                  isSelected: widget.currentTool is Highlighter,
                  onTap: () {
                    if (widget.currentTool is Highlighter) {
                      if (_highlighterCardOverlay != null) {
                        _hideHighlighterCard();
                      } else {
                        hideAllCards();
                        _showHighlighterCard();
                      }
                    } else {
                      hideAllCards();
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
                  key: _laserButtonKey,
                  icon: Icon(Symbols.stylus_laser_pointer, size: 20),
                  tooltip: t.editor.pens.laserPointer,
                  isSelected:
                      widget.currentTool == LaserPointer.currentLaserPointer,
                  onTap: () {
                    if (widget.currentTool ==
                        LaserPointer.currentLaserPointer) {
                      if (_laserCardOverlay != null) {
                        _hideLaserCard();
                      } else {
                        hideAllCards();
                        _showLaserCard();
                      }
                    } else {
                      hideAllCards();
                      widget.setTool(LaserPointer.currentLaserPointer);
                    }
                  },
                  readOnly: false,
                ),
                _ToolIconButton(
                  key: _textButtonKey,
                  icon: const Icon(Icons.text_fields, size: 20),
                  tooltip: t.editor.toolbar.text,
                  isSelected: widget.currentTool == Tool.textEditing,
                  onTap: () {
                    if (widget.currentTool == Tool.textEditing) {
                      if (_textCardOverlay != null) {
                        _hideTextCard();
                      } else {
                        hideAllCards();
                        _showTextCard();
                      }
                    } else {
                      hideAllCards();
                      widget.setTool(Tool.textEditing);
                    }
                  },
                  readOnly: widget.readOnly,
                ),
                _ToolIconButton(
                  icon: const Icon(Icons.undo, size: 18),
                  tooltip: t.editor.toolbar.undo,
                  isSelected: false,
                  onTap: widget.undo,
                  readOnly: widget.readOnly || !widget.isUndoPossible,
                ),
                _ToolIconButton(
                  icon: const Icon(Icons.redo, size: 18),
                  tooltip: t.editor.toolbar.redo,
                  isSelected: false,
                  onTap: widget.redo,
                  readOnly: widget.readOnly || !widget.isRedoPossible,
                ),

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
                if (widget.onManageTagsAndLinks != null)
                  _ToolIconButton(
                    icon: const Icon(Icons.link_outlined, size: 20),
                    tooltip: 'Tags & Links',
                    isSelected: false,
                    onTap: () {
                      hideAllCards();
                      widget.onManageTagsAndLinks?.call();
                    },
                    readOnly: false,
                  ),
                _ToolIconButton(
                  key: _exportButtonKey,
                  icon: const Icon(Icons.share, size: 18),
                  tooltip: t.editor.toolbar.export,
                  isSelected: _exportCardOverlay != null,
                  onTap: _showExportCard,
                  readOnly: widget.readOnly,
                ),
                ColorToolbar(
                  axis: widget.axis,
                  setColor: (color) {
                    widget.setColor(color);
                    widget.onColorChanged?.call(color);
                  },
                  currentColor: currentColor,
                  invert: widget.invert,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _getPenIcon() {
    final pen =
        (widget.currentTool is Pen && widget.currentTool is! Highlighter)
        ? widget.currentTool as Pen
        : Pen.currentPen;

    if (pen.toolId == ToolId.verticalSpacePen) {
      return const FaIcon(Pen.verticalSpacePenIcon, size: 18);
    }
    if (pen.toolId == ToolId.horizontalSpacePen) {
      return const FaIcon(Pen.horizontalSpacePenIcon, size: 18);
    } else if (pen.toolId == ToolId.fountainPen) {
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
    ColorScheme.of(context);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: readOnly ? null : onTap,
          borderRadius: BorderRadius.circular(6),
          child: Opacity(
            opacity: readOnly ? 0.5 : 1.0,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? Theme.of(context).colorScheme.surfaceContainerHighest
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.all(8),
              child: icon,
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
        case ToolId.verticalSpacePen:
          _selectedPen = Pen.verticalSpacePen();
          break;
        case ToolId.horizontalSpacePen:
          _selectedPen = Pen.horizontalSpacePen();
          break;
        case ToolId.advancedPen:
          _selectedPen = AdvancedPen();
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
    final isDark = theme.brightness == Brightness.dark;
    final activePen = _selectedPen ?? Pen.currentPen;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildPenCard(
              Pen.ballpointPen(),
              const Icon(Symbols.ink_pen, size: 18),
              t.editor.pens.ballpointPen,
            ),
            _buildPenCard(
              Pen.calligraphyPen(),
              const Icon(Symbols.brush, size: 18),
              t.editor.pens.calligraphyPen,
            ),
            _buildPenCard(
              Pen.fountainPen(),
              const Icon(Symbols.stylus_note, size: 18),
              t.editor.pens.fountainPen,
            ),
            _buildPenCard(
              AdvancedPen(),
              const Icon(AdvancedPen.advancedPenIcon, size: 18),
              'Advanced',
            ),
            _buildPenCard(
              Pen.verticalSpacePen(),
              const Icon(FontAwesomeIcons.arrowsUpDown, size: 16),
              'V-Space',
            ),
            _buildPenCard(
              Pen.horizontalSpacePen(),
              const Icon(FontAwesomeIcons.arrowsLeftRight, size: 16),
              'H-Space',
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Divider(
            height: 1,
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
        if (activePen.toolId == ToolId.advancedPen)
          _AdvancedPenOptionsPanel(
            pen: activePen as AdvancedPen,
            setTool: widget.setTool,
            setColor: widget.setColor,
            invert: widget.invert,
            onClose: widget.onClose,
            colorSwatches: _buildPenColorSwatches(
              context,
              activePen,
              colorScheme,
            ),
          )
        else ...[
          SizePicker(axis: Axis.horizontal, pen: activePen),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.settings.prefLabels.strokeStabilization,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    ValueListenableBuilder(
                      valueListenable: stows.strokeStabilizationAmount,
                      builder: (context, amount, _) {
                        return SizedBox(
                          height: 24,
                          child: Slider(
                            value: amount,
                            min: 0.0,
                            max: 1.0,
                            divisions: 20,
                            onChanged: (value) {
                              stows.strokeStabilizationAmount.value = value;
                              if (value > 0 &&
                                  !stows.strokeStabilization.value) {
                                stows.strokeStabilization.value = true;
                              } else if (value == 0 &&
                                  stows.strokeStabilization.value) {
                                stows.strokeStabilization.value = false;
                              }
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              ValueListenableBuilder(
                valueListenable: stows.strokeStabilization,
                builder: (context, enabled, _) {
                  return Switch(
                    value: enabled,
                    onChanged: (value) =>
                        stows.strokeStabilization.value = value,
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.settings.prefLabels.strokePrediction,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    ValueListenableBuilder(
                      valueListenable: stows.strokePredictionAmount,
                      builder: (context, amount, _) {
                        return SizedBox(
                          height: 24,
                          child: Slider(
                            value: amount,
                            min: 0.0,
                            max: 1.0,
                            divisions: 20,
                            onChanged: (value) {
                              stows.strokePredictionAmount.value = value;
                              if (value > 0 &&
                                  !stows.strokePrediction.value) {
                                stows.strokePrediction.value = true;
                              } else if (value == 0 &&
                                  stows.strokePrediction.value) {
                                stows.strokePrediction.value = false;
                              }
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              ValueListenableBuilder(
                valueListenable: stows.strokePrediction,
                builder: (context, enabled, _) {
                  return Switch(
                    value: enabled,
                    onChanged: (value) =>
                        stows.strokePrediction.value = value,
                  );
                },
              ),
            ],
          ),
          if (_penHasFavoriteColors(activePen)) ...[
            const SizedBox(height: 16),
            _buildPenColorSwatches(context, activePen, colorScheme),
          ],
        ],
      ],
    );
  }

  Widget _buildPenCard(Pen pen, Widget icon, String label) {
    final isActive = _selectedPen?.toolId == pen.toolId;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedPen = pen;
          widget.setTool(pen);
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isActive
              ? (isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : colorScheme.surfaceContainerHighest)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive
                ? (isDark
                      ? Colors.white.withValues(alpha: 0.2)
                      : colorScheme.outlineVariant)
                : (isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : colorScheme.outlineVariant.withValues(alpha: 0.3)),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTheme(
              data: IconThemeData(
                color: isActive
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
                size: 16,
              ),
              child: icon,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color: isActive
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static bool _penHasFavoriteColors(Pen pen) {
    switch (pen.toolId) {
      case ToolId.ballpointPen:
      case ToolId.calligraphyPen:
      case ToolId.fountainPen:
      case ToolId.shapePen:
      case ToolId.advancedPen:
        return true;
      default:
        return false;
    }
  }

  Widget _buildPenColorSwatches(
    BuildContext context,
    Pen activePen,
    ColorScheme colorScheme,
  ) {
    final favorites = stows.penFavoriteColors.value[activePen.toolId.id];
    final list = favorites ?? <int>[];
    final defaultBorderColor = colorScheme.onSurface.withValues(alpha: 0.5);
    final selectedBorderColor = colorScheme.primary;
    return ValueListenableBuilder<Map<String, List<int>>>(
      valueListenable: stows.penFavoriteColors,
      builder: (context, value, child) {
        final fav = value[activePen.toolId.id] ?? list;
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
                  ? selectedBorderColor
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
                  borderColor: isSelected
                      ? selectedBorderColor
                      : defaultBorderColor,
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
      default:
    }
  }

  Future<void> _openColorPickerForCurrent(
    BuildContext context,
    Pen activePen,
  ) async {
    Color pickedColor = activePen.color;
    widget.onClose();
    final bool? confirmChange = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AdaptiveAlertDialog(
        title: Text(t.editor.colors.colorPicker),
        content: _ToolbarColorPickerContent(
          initialColor: pickedColor,
          onColorChanged: (Color color) {
            pickedColor = color;
          },
        ),
        actions: [
          CupertinoDialogAction(
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          CupertinoDialogAction(
            child: Text(MaterialLocalizations.of(context).saveButtonLabel),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmChange ?? false) {
      activePen.color = pickedColor;
      widget.setColor(pickedColor);
      widget.setTool(activePen);
      _persistPenColor(activePen.toolId, pickedColor.toARGB32());
    }
  }

  Future<void> _openColorPickerForFavoriteSlot(
    BuildContext context,
    Pen activePen,
    int slotIndex,
  ) async {
    final favorites = List<int>.from(
      stows.penFavoriteColors.value[activePen.toolId.id] ??
          stows.penFavoriteColors.value[ToolId.ballpointPen.id]!,
    );
    while (favorites.length < 10) {
      favorites.add(0xFF000000);
    }
    Color pickedColor = Color(
      slotIndex < favorites.length ? favorites[slotIndex] : 0xFF000000,
    );
    widget.onClose();
    final bool? confirmChange = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AdaptiveAlertDialog(
        title: Text(t.editor.colors.colorPicker),
        content: _ToolbarColorPickerContent(
          initialColor: pickedColor,
          onColorChanged: (Color color) {
            pickedColor = color;
          },
        ),
        actions: [
          CupertinoDialogAction(
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          CupertinoDialogAction(
            child: Text(MaterialLocalizations.of(context).saveButtonLabel),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if ((confirmChange ?? false) && slotIndex < 10) {
      favorites[slotIndex] = pickedColor.toARGB32();
      final updated = Map<String, List<int>>.from(
        stows.penFavoriteColors.value,
      );
      updated[activePen.toolId.id] = favorites;
      stows.penFavoriteColors.value = updated;
    }
  }
}

double Function(double) _easingFromId(String id) {
  switch (id) {
    case 'easeInOut':
      return StrokeEasings.easeInOut;
    case 'easeOutCubic':
      return StrokeEasings.easeOutCubic;
    default:
      return StrokeEasings.identity;
  }
}

class _AdvancedPenOptionsPanel extends StatefulWidget {
  const _AdvancedPenOptionsPanel({
    required this.pen,
    required this.setTool,
    required this.setColor,
    required this.invert,
    required this.onClose,
    this.colorSwatches,
  });

  final AdvancedPen pen;
  final ValueChanged<Tool> setTool;
  final ValueChanged<Color> setColor;
  final bool invert;
  final VoidCallback onClose;
  final Widget? colorSwatches;

  @override
  State<_AdvancedPenOptionsPanel> createState() =>
      _AdvancedPenOptionsPanelState();
}

class _AdvancedPenOptionsPanelState extends State<_AdvancedPenOptionsPanel> {
  int _selectedPresetIndex = -1;
  late String _mainEasingId;
  late String _startEasingId;
  late String _endEasingId;
  bool _isPresetListExpanded = false;
  bool _isCreatingPreset = false;
  final TextEditingController _newPresetNameController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _mainEasingId = stows.lastAdvancedPenMainEasingId.value;
    _startEasingId = stows.lastAdvancedPenStartEasingId.value;
    _endEasingId = stows.lastAdvancedPenEndEasingId.value;
    _applyEasingToPen();
  }

  @override
  void dispose() {
    _newPresetNameController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _AdvancedPenOptionsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.pen, widget.pen)) {
      _mainEasingId = stows.lastAdvancedPenMainEasingId.value;
      _startEasingId = stows.lastAdvancedPenStartEasingId.value;
      _endEasingId = stows.lastAdvancedPenEndEasingId.value;
      _selectedPresetIndex = -1;
      _applyEasingToPen();
    }
  }

  void _applyEasingToPen() {
    final opts = widget.pen.options;
    opts.easing = _easingFromId(_mainEasingId);
    opts.start = StrokeEndOptions.start(
      taperEnabled: opts.start.taperEnabled,
      customTaper: opts.start.customTaper,
      cap: opts.start.cap,
      easing: _easingFromId(_startEasingId),
    );
    opts.end = StrokeEndOptions.end(
      taperEnabled: opts.end.taperEnabled,
      customTaper: opts.end.customTaper,
      cap: opts.end.cap,
      easing: _easingFromId(_endEasingId),
    );
    widget.setTool(widget.pen);
  }

  void _syncOptionsToStow() {
    stows.lastAdvancedPenOptions.value = widget.pen.options;
    stows.lastAdvancedPenColor.value = widget.pen.color.toARGB32();
  }

  int _indexOfMatchingPreset(List<Map<String, dynamic>> presets) {
    final optsJson = widget.pen.options.toJson();
    final colorArgb = widget.pen.color.toARGB32();
    const eq = DeepCollectionEquality();
    for (int i = 0; i < presets.length; i++) {
      final p = presets[i];
      final presetOpts = p['options'] as Map<String, dynamic>? ?? {};
      if (!eq.equals(presetOpts, optsJson)) continue;
      if ((p['colorArgb'] as int?) != colorArgb) continue;
      if ((p['easingId'] as String?) != _mainEasingId) continue;
      if ((p['startEasingId'] as String?) != _startEasingId) continue;
      if ((p['endEasingId'] as String?) != _endEasingId) continue;
      return i;
    }
    return -1;
  }

  void _saveNewPreset(String name, List<Map<String, dynamic>> presets) {
    final preset = {
      'name': name,
      'options': widget.pen.options.toJson(),
      'colorArgb': widget.pen.color.toARGB32(),
      'easingId': _mainEasingId,
      'startEasingId': _startEasingId,
      'endEasingId': _endEasingId,
    };
    setState(() {
      stows.advancedPenPresets.value = [...presets, preset];
      _selectedPresetIndex = stows.advancedPenPresets.value.length - 1;
      _isCreatingPreset = false;
      _newPresetNameController.clear();
    });
  }

  void _applyOptionsFromPreset(Map<String, dynamic> preset) {
    final optionsJson = preset['options'] as Map<String, dynamic>? ?? {};
    final easing = _easingFromId(preset['easingId'] as String? ?? 'identity');
    final startEasing = _easingFromId(
      preset['startEasingId'] as String? ?? 'easeInOut',
    );
    final endEasing = _easingFromId(
      preset['endEasingId'] as String? ?? 'easeOutCubic',
    );
    widget.pen.options = StrokeOptions.fromJson(
      optionsJson,
      easing: easing,
      startEasing: startEasing,
      endEasing: endEasing,
    );
    final colorArgb = preset['colorArgb'] as int? ?? 0xFF000000;
    widget.pen.color = Color(colorArgb);
    widget.setColor(widget.pen.color);
    widget.setTool(widget.pen);
    setState(() {
      _mainEasingId = preset['easingId'] as String? ?? 'identity';
      _startEasingId = preset['startEasingId'] as String? ?? 'easeInOut';
      _endEasingId = preset['endEasingId'] as String? ?? 'easeOutCubic';
    });
    _syncOptionsToStow();
  }

  @override
  Widget build(BuildContext context) {
    final opts = widget.pen.options;

    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: stows.advancedPenPresets,
      builder: (context, presets, _) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPresetSelector(presets),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.settings.prefLabels.strokeStabilization,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        ValueListenableBuilder(
                          valueListenable: stows.strokeStabilizationAmount,
                          builder: (context, amount, _) {
                            return SizedBox(
                              height: 24,
                              child: Slider(
                                value: amount,
                                min: 0.0,
                                max: 1.0,
                                divisions: 20,
                                onChanged: (value) {
                                  stows.strokeStabilizationAmount.value = value;
                                  if (value > 0 &&
                                      !stows.strokeStabilization.value) {
                                    stows.strokeStabilization.value = true;
                                  } else if (value == 0 &&
                                      stows.strokeStabilization.value) {
                                    stows.strokeStabilization.value = false;
                                  }
                                  setState(() {});
                                },
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  ValueListenableBuilder(
                    valueListenable: stows.strokeStabilization,
                    builder: (context, enabled, _) {
                      return Switch(
                        value: enabled,
                        onChanged: (value) {
                          stows.strokeStabilization.value = value;
                          setState(() {});
                        },
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.settings.prefLabels.strokePrediction,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        ValueListenableBuilder(
                          valueListenable: stows.strokePredictionAmount,
                          builder: (context, amount, _) {
                            return SizedBox(
                              height: 24,
                              child: Slider(
                                value: amount,
                                min: 0.0,
                                max: 1.0,
                                divisions: 20,
                                onChanged: (value) {
                                  stows.strokePredictionAmount.value = value;
                                  if (value > 0 &&
                                      !stows.strokePrediction.value) {
                                    stows.strokePrediction.value = true;
                                  } else if (value == 0 &&
                                      stows.strokePrediction.value) {
                                    stows.strokePrediction.value = false;
                                  }
                                  setState(() {});
                                },
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  ValueListenableBuilder(
                    valueListenable: stows.strokePrediction,
                    builder: (context, enabled, _) {
                      return Switch(
                        value: enabled,
                        onChanged: (value) {
                          stows.strokePrediction.value = value;
                          setState(() {});
                        },
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (widget.colorSwatches != null) ...[
                widget.colorSwatches!,
                const SizedBox(height: 12),
              ],

              _labelSlider('Size', opts.size * 2, 1, 10, (v) {
                opts.size = v / 2;
                _syncOptionsToStow();
                widget.setTool(widget.pen);
              }),
              _labelSlider('Thinning', opts.thinning, 0, 1, (v) {
                opts.thinning = v;
                _syncOptionsToStow();
                widget.setTool(widget.pen);
              }),
              _labelSlider('Streamline', opts.streamline, 0, 1, (v) {
                opts.streamline = v;
                _syncOptionsToStow();
                widget.setTool(widget.pen);
              }),
              _labelSlider('Smoothing', opts.smoothing, 0, 1, (v) {
                opts.smoothing = v;
                _syncOptionsToStow();
                widget.setTool(widget.pen);
              }),

              _buildEasingSelector('Main easing', _mainEasingId, (v) {
                setState(() => _mainEasingId = v);
                stows.lastAdvancedPenMainEasingId.value = v;
                opts.easing = _easingFromId(v);
                _syncOptionsToStow();
                widget.setTool(widget.pen);
              }),
              const SizedBox(height: 8),
              Text('Start', style: Theme.of(context).textTheme.labelMedium),
              _labelSlider('Start taper', opts.start.customTaper ?? 0, 0, 30, (
                v,
              ) {
                opts.start = StrokeEndOptions.start(
                  taperEnabled: v > 0,
                  customTaper: v > 0 ? v : null,
                  cap: opts.start.cap,
                  easing: _easingFromId(_startEasingId),
                );
                _syncOptionsToStow();
                widget.setTool(widget.pen);
              }),
              CheckboxListTile(
                title: const Text('Start cap'),
                value: opts.start.cap,
                onChanged: (v) {
                  opts.start = StrokeEndOptions.start(
                    taperEnabled: opts.start.taperEnabled,
                    customTaper: opts.start.customTaper,
                    cap: v ?? true,
                    easing: _easingFromId(_startEasingId),
                  );
                  _syncOptionsToStow();
                  widget.setTool(widget.pen);
                  setState(() {});
                },
              ),
              _buildEasingSelector('Start easing', _startEasingId, (v) {
                setState(() => _startEasingId = v);
                stows.lastAdvancedPenStartEasingId.value = v;
                opts.start = StrokeEndOptions.start(
                  taperEnabled: opts.start.taperEnabled,
                  customTaper: opts.start.customTaper,
                  cap: opts.start.cap,
                  easing: _easingFromId(v),
                );
                _syncOptionsToStow();
                widget.setTool(widget.pen);
              }),
              const SizedBox(height: 8),
              Text('End', style: Theme.of(context).textTheme.labelMedium),
              _labelSlider('End taper', opts.end.customTaper ?? 0, 0, 30, (v) {
                opts.end = StrokeEndOptions.end(
                  taperEnabled: v > 0,
                  customTaper: v > 0 ? v : null,
                  cap: opts.end.cap,
                  easing: _easingFromId(_endEasingId),
                );
                _syncOptionsToStow();
                widget.setTool(widget.pen);
              }),
              CheckboxListTile(
                title: const Text('End cap'),
                value: opts.end.cap,
                onChanged: (v) {
                  opts.end = StrokeEndOptions.end(
                    taperEnabled: opts.end.taperEnabled,
                    customTaper: opts.end.customTaper,
                    cap: v ?? true,
                    easing: _easingFromId(_endEasingId),
                  );
                  _syncOptionsToStow();
                  widget.setTool(widget.pen);
                  setState(() {});
                },
              ),
              _buildEasingSelector('End easing', _endEasingId, (v) {
                setState(() => _endEasingId = v);
                stows.lastAdvancedPenEndEasingId.value = v;
                opts.end = StrokeEndOptions.end(
                  taperEnabled: opts.end.taperEnabled,
                  customTaper: opts.end.customTaper,
                  cap: opts.end.cap,
                  easing: _easingFromId(v),
                );
                _syncOptionsToStow();
                widget.setTool(widget.pen);
              }),
              CheckboxListTile(
                title: const Text('Simulate pressure'),
                value: opts.simulatePressure,
                onChanged: (v) {
                  opts.simulatePressure = v ?? false;
                  _syncOptionsToStow();
                  widget.setTool(widget.pen);
                  setState(() {});
                },
              ),
              CheckboxListTile(
                title: const Text('Complete'),
                value: opts.isComplete,
                onChanged: (v) {
                  opts.isComplete = v ?? true;
                  _syncOptionsToStow();
                  widget.setTool(widget.pen);
                  setState(() {});
                },
              ),
              const SizedBox(height: 12),
              if (_isCreatingPreset) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newPresetNameController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Preset name',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (name) {
                          final n = name.trim();
                          if (n.isNotEmpty) _saveNewPreset(n, presets);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        final n = _newPresetNameController.text.trim();
                        if (n.isNotEmpty) _saveNewPreset(n, presets);
                      },
                      child: Text(
                        MaterialLocalizations.of(context).saveButtonLabel,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isCreatingPreset = false;
                          _newPresetNameController.clear();
                        });
                      },
                      child: Text(
                        MaterialLocalizations.of(context).cancelButtonLabel,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        setState(() => _isCreatingPreset = true);
                      },
                      icon: const Icon(Icons.save, size: 18),
                      label: const Text('Save preset'),
                    ),
                    if (_selectedPresetIndex >= 0 &&
                        _selectedPresetIndex < presets.length) ...[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () {
                          final list = List<Map<String, dynamic>>.from(presets);
                          list.removeAt(_selectedPresetIndex);
                          stows.advancedPenPresets.value = list;
                          setState(() => _selectedPresetIndex = -1);
                        },
                        icon: const Icon(Icons.delete, size: 18),
                        label: const Text('Delete preset'),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _labelSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: (v) {
                onChanged(v);
                setState(() {});
              },
            ),
          ),
          SizedBox(
            width: 42,
            child: Text(
              value.toStringAsFixed(1),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFeatures: [ui.FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetSelector(List<Map<String, dynamic>> presets) {

    final matchingIndex = _indexOfMatchingPreset(presets);
    if (matchingIndex != _selectedPresetIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedPresetIndex = matchingIndex);
      });
    }
    final effectiveIndex = matchingIndex;

    final currentName = (effectiveIndex >= 0 && effectiveIndex < presets.length)
        ? (presets[effectiveIndex]['name'] as String? ?? 'Preset')
        : 'No preset';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () =>
              setState(() => _isPresetListExpanded = !_isPresetListExpanded),
          borderRadius: BorderRadius.circular(4),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Preset',
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              suffixIcon: Icon(
                _isPresetListExpanded
                    ? Icons.arrow_drop_up
                    : Icons.arrow_drop_down,
              ),
            ),
            child: Text(currentName),
          ),
        ),
        if (_isPresetListExpanded)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(4),
              color: Theme.of(context).cardColor,
            ),
            margin: const EdgeInsets.only(top: 4),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                ListTile(
                  title: const Text(
                    'No preset',
                    style: TextStyle(fontSize: 14),
                  ),
                  dense: true,
                  selected: effectiveIndex == -1,
                  onTap: () {
                    setState(() {
                      _selectedPresetIndex = -1;
                      _isPresetListExpanded = false;
                    });
                  },
                ),
                ...List.generate(presets.length, (i) {
                  final name =
                      presets[i]['name'] as String? ?? 'Preset ${i + 1}';
                  return ListTile(
                    title: Text(name, style: const TextStyle(fontSize: 14)),
                    dense: true,
                    selected: effectiveIndex == i,
                    onTap: () {
                      setState(() {
                        _selectedPresetIndex = i;
                        _isPresetListExpanded = false;
                        _applyOptionsFromPreset(presets[i]);
                      });
                    },
                  );
                }),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildEasingSelector(
    String label,
    String currentId,
    ValueChanged<String> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                _easingChip('Identity', 'identity', currentId, onChanged),
                _easingChip('EaseInOut', 'easeInOut', currentId, onChanged),
                _easingChip('Cubic', 'easeOutCubic', currentId, onChanged),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _easingChip(
    String label,
    String id,
    String currentId,
    ValueChanged<String> onChanged,
  ) {
    final selected = id == currentId;
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => onChanged(id),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? colorScheme.primary : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
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
    Color pickedColor = Color(
      slotIndex < favorites.length ? favorites[slotIndex] : 0xFFFDE047,
    );
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AdaptiveAlertDialog(
        title: Text(t.editor.colors.colorPicker),
        content: _ToolbarColorPickerContent(
          initialColor: pickedColor,
          onColorChanged: (Color c) => pickedColor = c,
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(MaterialLocalizations.of(ctx).saveButtonLabel),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final updated = Map<String, List<int>>.from(
        stows.penFavoriteColors.value,
      );
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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final highlighter = widget.currentTool is Highlighter
        ? widget.currentTool as Highlighter
        : Highlighter.currentHighlighter;
    final currentRgb = highlighter.color.toARGB32() & 0x00FFFFFF;

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
            SizePicker(axis: Axis.horizontal, pen: highlighter),
            const SizedBox(height: 16),
            Text(
              t.editor.penOptions.opacity,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            Slider(
              value: _currentOpacity,
              min: 0.1,
              max: 1.0,
              divisions: 18,
              onChanged: _updateOpacity,
              onChangeEnd: (v) => stows.highlighterOpacity.value = v,
            ),
            Text(
              '${(_currentOpacity * 100).toInt()}%',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Divider(
                height: 1,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : colorScheme.outlineVariant.withValues(alpha: 0.2),
              ),
            ),
            Text(
              t.settings.prefLabels.flatEdge,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            ValueListenableBuilder(
              valueListenable: stows.highlighterFlatEdge,
              builder: (context, flat, _) {
                return Row(
                  children: [
                    Expanded(
                      child: _ChipOption(
                        label: t.settings.prefLabels.highlighterCapRound,
                        selected: !flat,
                        onTap: () => stows.highlighterFlatEdge.value = false,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ChipOption(
                        label: t.settings.prefLabels.highlighterCapFlat,
                        selected: flat,
                        onTap: () => stows.highlighterFlatEdge.value = true,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Drawing Assist',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            ValueListenableBuilder(
              valueListenable: Highlighter.straightLine,
              builder: (context, straight, _) {
                return Row(
                  children: [
                    Expanded(
                      child: _ChipOption(
                        label: 'Freehand',
                        selected: !straight,
                        onTap: () => Highlighter.straightLine.value = false,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ChipOption(
                        label: 'Straight Line',
                        selected: straight,
                        onTap: () => Highlighter.straightLine.value = true,
                      ),
                    ),
                  ],
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Divider(
                height: 1,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : colorScheme.outlineVariant.withValues(alpha: 0.2),
              ),
            ),
            Text(
              t.editor.colors.colorPicker,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
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
                              ? colorScheme.primary
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
    Color pickedColor = stows.laserPointerColor.value;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AdaptiveAlertDialog(
        title: Text(t.editor.colors.colorPicker),
        content: _ToolbarColorPickerContent(
          initialColor: pickedColor,
          onColorChanged: (Color color) {
            pickedColor = color;
          },
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(MaterialLocalizations.of(context).saveButtonLabel),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        stows.laserPointerColor.value = pickedColor;
      });
    }
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
    Color pickedColor = Color(
      slotIndex < favorites.length ? favorites[slotIndex] : 0xFFDC2626,
    );
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AdaptiveAlertDialog(
        title: Text(t.editor.colors.colorPicker),
        content: _ToolbarColorPickerContent(
          initialColor: pickedColor,
          onColorChanged: (Color color) {
            pickedColor = color;
          },
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(MaterialLocalizations.of(context).saveButtonLabel),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      if (slotIndex < favorites.length) {
        favorites[slotIndex] = pickedColor.toARGB32();
      } else {
        favorites.add(pickedColor.toARGB32());
      }
      final updated = Map<String, List<int>>.from(
        stows.penFavoriteColors.value,
      );
      updated[ToolId.laserPointer.id] = favorites;
      stows.penFavoriteColors.value = updated;
      setState(() {});
    }
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
    final selectedBorderColor = colorScheme.primary;

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
                            ? selectedBorderColor
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
                                ? selectedBorderColor
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
    Color pickedColor = _strokeColor;
    widget.onClose();

    final bool? confirmChange = await showDialog(
      context: context,
      builder: (BuildContext context) => AdaptiveAlertDialog(
        title: Text(t.editor.colors.colorPicker),
        content: _ToolbarColorPickerContent(
          initialColor: pickedColor,
          onColorChanged: (Color color) {
            pickedColor = color;
          },
        ),
        actions: [
          CupertinoDialogAction(
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            onPressed: () {
              Navigator.of(context).pop(false);
            },
          ),
          CupertinoDialogAction(
            child: Text(MaterialLocalizations.of(context).saveButtonLabel),
            onPressed: () {
              Navigator.of(context).pop(true);
            },
          ),
        ],
      ),
    );

    if (confirmChange ?? false) {
      setState(() {
        _strokeColor = pickedColor;
        _apply();
      });
    }
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${t.editor.penOptions.size}: ${_config.strokeWidth.toStringAsFixed(1)}px',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                    ),
                  ),
                  SizedBox(
                    height: 24,
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
                ],
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Color',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: _showColorPicker,
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CustomPaint(
                      painter: _SmoothCirclePainter(
                        color: _strokeColor.withInversion(widget.invert),
                        borderColor: colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                        borderWidth: 2.0,
                        hasShadow: false,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Line style',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 6),
        SegmentedButton<ShapeStrokeStyle>(
          segments: const [
            ButtonSegment<ShapeStrokeStyle>(
              value: ShapeStrokeStyle.solid,
              label: Text('Solid'),
            ),
            ButtonSegment<ShapeStrokeStyle>(
              value: ShapeStrokeStyle.dashed,
              label: Text('Dashed'),
            ),
            ButtonSegment<ShapeStrokeStyle>(
              value: ShapeStrokeStyle.dotted,
              label: Text('Dotted'),
            ),
          ],
          selected: {_config.strokeStyle},
          onSelectionChanged: (Set<ShapeStrokeStyle> selection) {
            if (selection.isEmpty) return;
            setState(() {
              _config = _config.copyWith(strokeStyle: selection.first);
              _apply();
            });
          },
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Fill Shape',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            Switch(
              value: _fill,
              onChanged: (v) {
                setState(() {
                  _fill = v;
                  _apply();
                });
              },
            ),
          ],
        ),
        if (_config.kind == ShapeKind.polygon) ...[
          const SizedBox(height: 8),
          Text(
            'Sides: ${_config.detail.clamp(3, 12)}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(
            height: 24,
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
        ],
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Divider(
            height: 1,
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search shapes...',
            prefixIcon: const Icon(Icons.search, size: 18),
            isDense: true,
            filled: true,
            fillColor: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            contentPadding: const EdgeInsets.all(8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 240,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1.4,
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
                    detail: kind == ShapeKind.polygon
                        ? (_config.detail < 3 ? 6 : _config.detail)
                        : _config.detail,
                  );
                  _apply();
                }),
                borderRadius: BorderRadius.circular(10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : colorScheme.surfaceContainerHighest)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? (isDark
                                ? Colors.white.withValues(alpha: 0.2)
                                : colorScheme.outlineVariant)
                          : (isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : colorScheme.outlineVariant.withValues(
                                    alpha: 0.3,
                                  )),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _getIconForShape(kind),
                        color: isSelected
                            ? colorScheme.onSurface
                            : colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _shapeLabel(kind),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isSelected
                              ? colorScheme.onSurface
                              : colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  IconData _getIconForShape(ShapeKind kind) {
    switch (kind) {
      case ShapeKind.rectangle:
        return CupertinoIcons.rectangle;
      case ShapeKind.circle:
        return CupertinoIcons.circle;
      case ShapeKind.ellipse:
        return Icons.radio_button_unchecked;
      case ShapeKind.polygon:
        return CupertinoIcons.hexagon;
      case ShapeKind.line:
        return Icons.horizontal_rule;
      case ShapeKind.arrow:
        return CupertinoIcons.arrow_right;
      case ShapeKind.doubleArrow:
        return CupertinoIcons.arrow_left_right;
      case ShapeKind.triangleIsosceles:
      case ShapeKind.triangleRight:
        return CupertinoIcons.triangle;
      case ShapeKind.cube:
        return CupertinoIcons.cube_box;
      case ShapeKind.cylinder:
        return Icons.inventory_2_outlined;
      case ShapeKind.sphere:
        return Symbols.language;
      case ShapeKind.halfSphere:
        return Icons.wifi_tethering;
      case ShapeKind.parabola:
        return Symbols.trending_up;
      case ShapeKind.pendulum:
        return Symbols.vibration;
      case ShapeKind.spring:
        return Symbols.water;
      case ShapeKind.fixedEnd:
        return Symbols.publish;
      case ShapeKind.harmonicOscillator:
        return Symbols.graphic_eq;
      case ShapeKind.coordinateSystem:
        return Symbols.polyline;
      default:
        return Icons.category_outlined;
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '${t.editor.penOptions.size}: ',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(
              width: 42,
              child: Text(
                _size.toStringAsFixed(1),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove, size: 18),
              onPressed: () {
                setState(() {
                  _size = (_size - 0.5).clamp(0.5, 25);
                  Eraser.currentEraser.updateSize = _size;
                  widget.setTool(Eraser.currentEraser);
                });
              },
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add, size: 18),
              onPressed: () {
                setState(() {
                  _size = (_size + 0.5).clamp(0.5, 25);
                  Eraser.currentEraser.updateSize = _size;
                  widget.setTool(Eraser.currentEraser);
                });
              },
            ),
          ],
        ),
        Slider(
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
        const SizedBox(height: 12),
        Text(
          'Mode',
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ChipOption(
                label: 'Erase stroke',
                selected: _mode == EraserMode.stroke,
                onTap: () {
                  setState(() {
                    _mode = EraserMode.stroke;
                    Eraser.currentEraser.updateMode = _mode;
                    widget.setTool(Eraser.currentEraser);
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ChipOption(
                label: 'Erase area',
                selected: _mode == EraserMode.area,
                onTap: () {
                  setState(() {
                    _mode = EraserMode.area;
                    Eraser.currentEraser.updateMode = _mode;
                    widget.setTool(Eraser.currentEraser);
                  });
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TextFormattingCard extends StatelessWidget {
  const _TextFormattingCard({required this.quillFocus, required this.onClose});

  final ValueNotifier<QuillStruct?> quillFocus;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return ValueListenableBuilder(
      valueListenable: quillFocus,
      builder: (context, quill, _) {
        if (quill == null) {
          return Center(
            child: Text(
              'Select a text box to view formatting options.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          );
        }

        final baseButtonStyle =
            IconButtonTheme.of(context).style ?? const ButtonStyle();
        final iconTheme = QuillIconTheme(
          iconButtonUnselectedData: IconButtonData(
            style: baseButtonStyle.copyWith(
              backgroundColor: WidgetStateProperty.all(Colors.transparent),
              foregroundColor: WidgetStateProperty.all(
                colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          iconButtonSelectedData: IconButtonData(
            style: baseButtonStyle.copyWith(
              backgroundColor: WidgetStateProperty.all(
                isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : colorScheme.surfaceContainerHighest,
              ),
              foregroundColor: WidgetStateProperty.all(colorScheme.onSurface),
            ),
          ),
        );

        return QuillSimpleToolbar(
          controller: quill.controller,
          config: QuillSimpleToolbarConfig(
            multiRowsDisplay: true,
            axis: Axis.horizontal,
            buttonOptions: QuillSimpleToolbarButtonOptions(
              base: QuillToolbarBaseButtonOptions(iconTheme: iconTheme),
            ),
            showBoldButton: true,
            showItalicButton: true,
            showUnderLineButton: true,
            showStrikeThrough: true,
            showInlineCode: true,
            showSubscript: true,
            showSuperscript: true,
            showColorButton: true,
            showBackgroundColorButton: true,
            showHeaderStyle: true,
            showListNumbers: true,
            showListBullets: true,
            showListCheck: true,
            showCodeBlock: true,
            showQuote: true,
            showIndent: true,
            showLink: true,
            showSearchButton: true,

            showUndo: false,
            showRedo: false,
            showFontSize: false,
            showFontFamily: false,
            showClearFormat: true,
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Material(
                    elevation: isDark ? 0 : 8,
                    color:
                        (isDark ? const Color(0xFF1E1E1E) : colorScheme.surface)
                            .withValues(alpha: 0.75),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.15)
                            : colorScheme.outlineVariant.withValues(alpha: 0.4),
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

class _ToolbarColorPickerContent extends StatefulWidget {
  const _ToolbarColorPickerContent({
    required this.initialColor,
    required this.onColorChanged,
  });

  final Color initialColor;
  final ValueChanged<Color> onColorChanged;

  @override
  State<_ToolbarColorPickerContent> createState() =>
      _ToolbarColorPickerContentState();
}

class _ToolbarColorPickerContentState
    extends State<_ToolbarColorPickerContent> {
  late Color _color;
  late TextEditingController _hexController;

  static String _colorToHex(Color c) {
    return '#${(c.r * 255).toInt().toRadixString(16).padLeft(2, '0')}'
            '${(c.g * 255).toInt().toRadixString(16).padLeft(2, '0')}'
            '${(c.b * 255).toInt().toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }

  static Color? _hexToColor(String hex) {
    hex = hex.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.length != 6) return null;
    final r = int.tryParse(hex.substring(0, 2), radix: 16);
    final g = int.tryParse(hex.substring(2, 4), radix: 16);
    final b = int.tryParse(hex.substring(4, 6), radix: 16);
    if (r == null || g == null || b == null) return null;
    return Color.fromARGB(255, r, g, b);
  }

  void _onHexChanged(String value) {
    final v = value.trim();
    if (v.startsWith('#')) {
      if (v.length == 7) _applyHex(v);
    } else if (v.length == 6) {
      _applyHex('#$v');
    }
  }

  @override
  void initState() {
    super.initState();
    _color = widget.initialColor;
    _hexController = TextEditingController(text: _colorToHex(_color));
  }

  @override
  void didUpdateWidget(covariant _ToolbarColorPickerContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialColor != widget.initialColor) {
      _color = widget.initialColor;
      _hexController.text = _colorToHex(_color);
    }
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _applyHex(String value) {
    final c = _hexToColor(value);
    if (c != null && c != _color) {
      setState(() => _color = c);
      _hexController.text = _colorToHex(c);
      widget.onColorChanged(c);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColorPicker(
            color: _color,
            onColorChanged: (Color c) {
              setState(() {
                _color = c;
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
            enableOpacity: false,
            width: 40,
            height: 40,
            borderRadius: 12,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _hexController,
            decoration: const InputDecoration(
              labelText: 'HEX',
              hintText: '#RRGGBB',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.tag, size: 20),
            ),
            maxLength: 7,
            onChanged: _onHexChanged,
            onSubmitted: _applyHex,
          ),
        ],
      ),
    );
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
          ..color = Colors.black.withOpacity(0.26)
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
