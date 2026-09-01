// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/data/editor/canvas_background_pattern.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/prefs.dart';

/// flex_color_picker defaults primary/accent to **true** if omitted — force wheel-only.
const Map<ColorPickerType, bool> _kEditorWheelPickerOnly = {
  ColorPickerType.wheel: true,
  ColorPickerType.primary: false,
  ColorPickerType.accent: false,
  ColorPickerType.both: false,
  ColorPickerType.bw: false,
  ColorPickerType.custom: false,
  ColorPickerType.customSecondary: false,
};

/// Minimal swatches for page / line / border color hints (light neutrals).
const List<Color> _kEditorSwatchLight = [
  Color(0xFFFFFFFF),
  Color(0xFFF8FAFC),
  Color(0xFFE2E8F0),
  Color(0xFFDCFCE7),
  Color(0xFFFFE4E6),
  Color(0xFFE9D5FF),
  Color(0xFFFEF3C7),
];

/// Minimal swatches (deep neutrals & muted accents).
const List<Color> _kEditorSwatchDark = [
  Color(0xFF09090B),
  Color(0xFF18181B),
  Color(0xFF1E293B),
  Color(0xFF14532D),
  Color(0xFF7F1D1D),
  Color(0xFF312E81),
  Color(0xFF0C4A6E),
];

/// Full-screen page appearance editor body (used by [EditorPageSettingsPage] in `editor_menu.dart`).
class EditorPageSettingsBody extends StatefulWidget {
  final EditorCoreInfo coreInfo;
  final int currentPageIndex;
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

  /// When true, edits sync global prefs for **new notes** instead of note metadata + file overrides.
  final bool configureGlobalNoteDefaults;

  const EditorPageSettingsBody({
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
    this.configureGlobalNoteDefaults = false,
  });

  @override
  State<EditorPageSettingsBody> createState() => EditorPageSettingsBodyState();
}

class EditorPageSettingsBodyState extends State<EditorPageSettingsBody> {
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
  late PageOrientation _panelOrientation;

  @override
  void initState() {
    super.initState();
    _hexController = TextEditingController();
    _hexLineController = TextEditingController();
    _hexBorderController = TextEditingController();
    if (widget.configureGlobalNoteDefaults) {
      _invertInDarkMode = stows.editorAutoInvert.value;
      _invertBackground = stows.editorAutoInvertBackground.value;
    } else {
      _invertInDarkMode = getEffectiveNoteInvertInDarkModeForFile(
        widget.coreInfo.filePath,
      );
      _invertBackground = getEffectiveNoteInvertBackgroundForFile(
        widget.coreInfo.filePath,
      );
    }
    _panelOrientation = widget.coreInfo.notePageOrientation;
    _syncFromMetadata();
  }

  @override
  void didUpdateWidget(covariant EditorPageSettingsBody oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.coreInfo != widget.coreInfo) {
      _syncFromMetadata();
    }
    if (oldWidget.coreInfo.notePageOrientation !=
        widget.coreInfo.notePageOrientation) {
      _panelOrientation = widget.coreInfo.notePageOrientation;
    }
  }

  void _syncFromMetadata() {
    if (widget.configureGlobalNoteDefaults) {
      final o =
          PageOrientation.values[stows.defaultNotePageOrientationIndex.value
              .clamp(0, PageOrientation.values.length - 1)];
      _pattern = stows.lastBackgroundPattern.value;
      _pageColor = Color(stows.defaultPageColor.value);
      _lineColor = Color(stows.defaultLineColor.value);
      _lineHeight = stows.lastLineHeight.value;
      _lineThickness = stows.lastLineThickness.value.toDouble();
      _marginLeft = stows.defaultMarginLeft.value;
      _marginRight = stows.defaultMarginRight.value;
      _marginTop = stows.defaultMarginTop.value;
      _marginBottom = stows.defaultMarginBottom.value;
      final hasMargins =
          _marginLeft > 0 ||
          _marginRight > 0 ||
          _marginTop > 0 ||
          _marginBottom > 0;
      _borderColor = hasMargins
          ? Color(stows.defaultMarginColor.value)
          : Colors.transparent;
      _panelOrientation = o;
      _pageSize = o.defaultSize;
      _invertInDarkMode = stows.editorAutoInvert.value;
      _invertBackground = stows.editorAutoInvertBackground.value;
      _hexBorderController.text =
          '#${_borderColor.value.toRadixString(16).substring(2).toUpperCase()}';
      _hexController.text =
          '#${_pageColor.value.toRadixString(16).substring(2).toUpperCase()}';
      _hexLineController.text =
          '#${_lineColor.value.toRadixString(16).substring(2).toUpperCase()}';
      return;
    }

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
    _panelOrientation = ci.notePageOrientation;
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


    Widget buildSectionTitle(String title) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 10, left: 2),
        child: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
            letterSpacing: -0.35,
          ),
        ),
      );
    }

    Widget compactToggleRow(
      String label,
      bool value,
      ValueChanged<bool> onChanged, {
      String? tooltip,
    }) {
      final row = Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      );
      if (tooltip != null && tooltip.isNotEmpty) {
        return Tooltip(message: tooltip, child: row);
      }
      return row;
    }

    Widget subtleCard({required Widget child}) {
      return Card(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(padding: const EdgeInsets.all(18), child: child),
      );
    }

    Widget marginTile(
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
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${value.toInt()}',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: value.clamp(0.0, 50.0),
              min: 0,
              max: 50,
              divisions: 50,
              onChanged: onChanged,
            ),
          ),
        ],
      );
    }

    Widget wheelHexEditor({
      required Color color,
      required TextEditingController hexCtrl,
      required ValueChanged<Color> onColorChanged,
      required void Function(Color) applyFromHex,
      double wheelSize = 148,
    }) {
      return LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth > 420;
          // flex_color_picker adds Padding(bottom: columnSpacing) below the wheel;
          // outer height must include it or Column overflows by that amount (~4dp).
          const wheelPickerColumnSpacing = 4.0;
          final wheel = SizedBox(
            width: wheelSize,
            height: wheelSize + wheelPickerColumnSpacing,
            child: ColorPicker(
              color: color,
              onColorChanged: onColorChanged,
              pickersEnabled: _kEditorWheelPickerOnly,
              enableShadesSelection: false,
              showColorName: false,
              showRecentColors: false,
              showColorCode: false,
              enableOpacity: false,
              hasBorder: false,
              wheelDiameter: wheelSize,
              wheelWidth: 14,
              padding: EdgeInsets.zero,
              columnSpacing: wheelPickerColumnSpacing,
            ),
          );
          final hexField = TextField(
            controller: hexCtrl,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              fontSize: 14,
            ),
            decoration: InputDecoration(
              labelText: 'HEX',
              hintText: '#RRGGBB',
              isDense: true,
              prefixIcon: const Icon(Icons.tag, size: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              filled: true,
              fillColor: colorScheme.surface,
            ),
            onChanged: (value) {
              if (value.startsWith('#') && value.length == 7) {
                try {
                  final parsed = Color(
                    int.parse(value.substring(1), radix: 16) + 0xFF000000,
                  );
                  applyFromHex(parsed);
                } catch (_) {}
              }
            },
          );
          Widget swatchChip(Color sw) {
            final isLight = sw.computeLuminance() > 0.55;
            return InkWell(
              onTap: () {
                hexCtrl.text =
                    '#${sw.value.toRadixString(16).substring(2).toUpperCase()}';
                onColorChanged(sw);
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: sw,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isLight
                        ? colorScheme.outline.withValues(alpha: 0.35)
                        : colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
              ),
            );
          }

          Widget swatchRow(List<Color> colors) {
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.start,
              children: [for (final c in colors) swatchChip(c)],
            );
          }

          final paletteColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              hexField,
              const SizedBox(height: 8),
              swatchRow(_kEditorSwatchLight),
              const SizedBox(height: 6),
              swatchRow(_kEditorSwatchDark),
            ],
          );
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                wheel,
                const SizedBox(width: 12),
                Expanded(child: paletteColumn),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: wheel),
              const SizedBox(height: 10),
              paletteColumn,
            ],
          );
        },
      );
    }

    final settingsContent = ListView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
      children: [
        buildSectionTitle('Display'),
        subtleCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              compactToggleRow(
                'Invert in dark mode',
                _invertInDarkMode,
                (value) {
                  setState(() => _invertInDarkMode = value);
                  if (widget.configureGlobalNoteDefaults) {
                    stows.editorAutoInvert.value = value;
                  } else {
                    setNoteInvertInDarkModeOverrideForFile(
                      widget.coreInfo.filePath,
                      value,
                    );
                  }
                },
                tooltip: widget.configureGlobalNoteDefaults
                    ? 'Default for notes when opened in dark mode'
                    : 'Override app setting for this note only',
              ),
              if (_invertInDarkMode) ...[
                const Divider(height: 26),
                compactToggleRow(
                  'Invert backgrounds',
                  _invertBackground,
                  (value) {
                    setState(() => _invertBackground = value);
                    if (widget.configureGlobalNoteDefaults) {
                      stows.editorAutoInvertBackground.value = value;
                    } else {
                      setNoteInvertBackgroundOverrideForFile(
                        widget.coreInfo.filePath,
                        value,
                      );
                      widget.onToggleGlobalBackgroundInversion(value);
                    }
                  },
                  tooltip: widget.configureGlobalNoteDefaults
                      ? 'Default inversion for note backgrounds in dark mode'
                      : 'Invert background images in dark mode',
                ),
              ],
              if (widget.onSetPageOrientation != null) ...[
                const Divider(height: 26),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Orientation',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<PageOrientation>(
                  showSelectedIcon: true,
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    selectedBackgroundColor: colorScheme.primaryContainer,
                    selectedForegroundColor: colorScheme.onPrimaryContainer,
                    backgroundColor: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.45),
                    foregroundColor: colorScheme.onSurface,
                    side: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  segments: const [
                    ButtonSegment<PageOrientation>(
                      value: PageOrientation.portrait,
                      icon: Icon(Icons.stay_current_portrait, size: 18),
                      label: Text('Portrait'),
                    ),
                    ButtonSegment<PageOrientation>(
                      value: PageOrientation.landscape,
                      icon: Icon(Icons.stay_current_landscape, size: 18),
                      label: Text('Landscape'),
                    ),
                  ],
                  selected: {_panelOrientation},
                  onSelectionChanged: (Set<PageOrientation> selected) {
                    final o = selected.single;
                    setState(() {
                      _panelOrientation = o;
                      _pageSize = o.defaultSize;
                    });
                    widget.onSetPageOrientation!(o);
                    if (widget.configureGlobalNoteDefaults) {
                      stows.defaultNotePageOrientationIndex.value = o.index;
                    }
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        buildSectionTitle('Background pattern'),
        subtleCard(
          child: DropdownButtonFormField<CanvasBackgroundPattern>(
            isExpanded: true,
            value: _pattern,
            decoration: InputDecoration(
              isDense: false,
              labelText: 'Pattern',
              prefixIcon: const Icon(Icons.grid_view_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: colorScheme.surface.withValues(alpha: 0.72),
            ),
            items: [
              for (final pattern in CanvasBackgroundPattern.values)
                DropdownMenuItem(
                  value: pattern,
                  child: Text(
                    CanvasBackgroundPattern.localizedName(pattern),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: widget.onSetPattern == null
                ? null
                : (CanvasBackgroundPattern? p) {
                    if (p == null) return;
                    setState(() => _pattern = p);
                    widget.onSetPattern!(p);
                  },
          ),
        ),
        const SizedBox(height: 24),
        buildSectionTitle('Page color'),
        subtleCard(
          child: wheelHexEditor(
            color: _pageColor,
            hexCtrl: _hexController,
            onColorChanged: (color) {
              setState(() {
                _pageColor = color;
                _hexController.text =
                    '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
              });
              widget.onSetColor(color);
            },
            applyFromHex: (color) {
              setState(() => _pageColor = color);
              widget.onSetColor(color);
            },
          ),
        ),
        if (_pattern != CanvasBackgroundPattern.none) ...[
          const SizedBox(height: 24),
          buildSectionTitle('Line spacing & thickness'),
          subtleCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Spacing',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${_lineHeight}px',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2.5,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 7,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 12,
                          ),
                        ),
                        child: Slider(
                          value: _lineHeight.toDouble(),
                          min: 20,
                          max: 100,
                          divisions: 80,
                          onChanged: (v) {
                            setState(() => _lineHeight = v.toInt());
                            widget.onSetLineHeight(_lineHeight);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Thickness',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${_lineThickness.toStringAsFixed(1)}px',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2.5,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 7,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 12,
                          ),
                        ),
                        child: Slider(
                          value: _lineThickness.clamp(1.0, 5.0),
                          min: 1,
                          max: 5,
                          divisions: 4,
                          onChanged: (v) {
                            setState(() => _lineThickness = v);
                            widget.onSetLineThickness(v);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          buildSectionTitle('Line color'),
          subtleCard(
            child: wheelHexEditor(
              color: _lineColor,
              hexCtrl: _hexLineController,
              onColorChanged: (color) {
                setState(() {
                  _lineColor = color;
                  _hexLineController.text =
                      '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
                });
                widget.onSetLineColor(color);
              },
              applyFromHex: (color) {
                setState(() => _lineColor = color);
                widget.onSetLineColor(color);
              },
            ),
          ),
        ],
        const SizedBox(height: 24),
        buildSectionTitle('Margins'),
        subtleCard(
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: marginTile('Left', _marginLeft, (v) {
                      setState(() => _marginLeft = v);
                      widget.onSetMargins?.call(
                        v,
                        _marginRight,
                        _marginTop,
                        _marginBottom,
                      );
                    }),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: marginTile('Right', _marginRight, (v) {
                      setState(() => _marginRight = v);
                      widget.onSetMargins?.call(
                        _marginLeft,
                        v,
                        _marginTop,
                        _marginBottom,
                      );
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: marginTile('Top', _marginTop, (v) {
                      setState(() => _marginTop = v);
                      widget.onSetMargins?.call(
                        _marginLeft,
                        _marginRight,
                        v,
                        _marginBottom,
                      );
                    }),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: marginTile('Bottom', _marginBottom, (v) {
                      setState(() => _marginBottom = v);
                      widget.onSetMargins?.call(
                        _marginLeft,
                        _marginRight,
                        _marginTop,
                        v,
                      );
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        buildSectionTitle('Border color'),
        subtleCard(
          child: wheelHexEditor(
            color: _borderColor,
            hexCtrl: _hexBorderController,
            onColorChanged: (color) {
              setState(() {
                _borderColor = color;
                _hexBorderController.text =
                    '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
              });
              widget.onSetBorderColor?.call(color);
            },
            applyFromHex: (color) {
              setState(() => _borderColor = color);
              widget.onSetBorderColor?.call(color);
            },
          ),
        ),
        const SizedBox(height: 12),
      ],
    );

    return settingsContent;
  }
}
