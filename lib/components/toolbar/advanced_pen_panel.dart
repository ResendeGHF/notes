// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/i18n/strings.g.dart';

/// Tunable Advanced pen brush + named presets.
///
/// The Advanced pen smooths input with a spring-mass model (a pure-Dart port
/// of Rnote's `PenPathModeledBuilder` / ink-stroke-modeler) and draws a
/// variable-width ribbon. Width comes from the shared pen size slider;
/// everything else is tuned here.
class AdvancedPenPresets extends StatefulWidget {
  const AdvancedPenPresets({
    super.key,
    required this.pen,
    required this.onChanged,
  });

  final Pen pen;
  final VoidCallback onChanged;

  @override
  State<AdvancedPenPresets> createState() => _AdvancedPenPresetsState();
}

class _AdvancedPenPresetsState extends State<AdvancedPenPresets> {
  late final TextEditingController _presetNameController;

  @override
  void initState() {
    super.initState();
    _presetNameController = TextEditingController();
  }

  @override
  void dispose() {
    _presetNameController.dispose();
    super.dispose();
  }

  void _persist() {
    stows.lastAdvancedPenOptions.value = widget.pen.options.copyWith();
    stows.lastAdvancedPenBrushOptions.value =
        widget.pen.brushOptions.copyWith();
    stows.lastAdvancedPenColor.value = widget.pen.color.toARGB32();
    widget.onChanged();
    setState(() {});
  }

  Map<String, dynamic> _presetPayload(String name) => {
        'name': name,
        'options': widget.pen.options.toJson(),
        'colorArgb': widget.pen.color.toARGB32(),
        'brush': widget.pen.brushOptions.toJson(),
      };

  void _applyPreset(Map<String, dynamic> preset) {
    final raw = preset['options'];
    if (raw is Map) {
      final size = (Map<String, dynamic>.from(raw)['s'] as num?)?.toDouble();
      if (size != null) widget.pen.options.size = size;
    }
    // Old presets (easing ids) carry no brush style: keep the current one.
    final brushRaw = preset['brush'];
    if (brushRaw is Map) {
      try {
        widget.pen.brushOptions = AdvancedPenOptions.fromJson(
          Map<String, dynamic>.from(brushRaw),
        );
      } catch (_) {
        // Keep the current brush style when the payload is invalid.
      }
    }
    final colorArgb = preset['colorArgb'];
    if (colorArgb is int) {
      widget.pen.color = Color(colorArgb);
    }
    _persist();
  }

  Future<void> _savePreset({int? replaceIndex}) async {
    final name = _presetNameController.text.trim().isEmpty
        ? 'Preset ${(stows.advancedPenPresets.value.length + 1)}'
        : _presetNameController.text.trim();
    final list = List<Map<String, dynamic>>.from(
      stows.advancedPenPresets.value,
    );
    final payload = _presetPayload(name);
    if (replaceIndex != null &&
        replaceIndex >= 0 &&
        replaceIndex < list.length) {
      list[replaceIndex] = payload;
    } else {
      list.add(payload);
    }
    stows.advancedPenPresets.value = list;
    _presetNameController.clear();
    setState(() {});
  }

  void _deletePreset(int index) {
    final list = List<Map<String, dynamic>>.from(
      stows.advancedPenPresets.value,
    );
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    stows.advancedPenPresets.value = list;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final presets = stows.advancedPenPresets.value;

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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sectionTitle('Presets'),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _presetNameController,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: t.editor.penOptions.presetNameHint,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: t.toolbar.savePreset,
              onPressed: () => _savePreset(),
              icon: const Icon(Icons.save_outlined),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...List.generate(presets.length, (i) {
          final name = (presets[i]['name'] as String?) ?? 'Preset ${i + 1}';
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(name),
            onTap: () => _applyPreset(presets[i]),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: t.toolbar.updatePreset,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () {
                    _presetNameController.text = name;
                    _savePreset(replaceIndex: i);
                  },
                ),
                IconButton(
                  tooltip: t.toolbar.deletePreset,
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => _deletePreset(i),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

/// Advanced pen settings: brush style + all modeler parameters.
class AdvancedPenSettings extends StatefulWidget {
  const AdvancedPenSettings({
    super.key,
    required this.pen,
    required this.onChanged,
  });

  final Pen pen;
  final VoidCallback onChanged;

  @override
  State<AdvancedPenSettings> createState() => _AdvancedPenSettingsState();
}

class _AdvancedPenSettingsState extends State<AdvancedPenSettings> {
  AdvancedPenOptions get _opts => widget.pen.brushOptions;
  AdvancedPenModelerParams get _modeler => _opts.modeler;

  void _persist() {
    stows.lastAdvancedPenOptions.value = widget.pen.options.copyWith();
    stows.lastAdvancedPenBrushOptions.value = _opts.copyWith();
    stows.lastAdvancedPenColor.value = widget.pen.color.toARGB32();
    widget.onChanged();
    setState(() {});
  }

  void _setModeler(AdvancedPenModelerParams next) {
    final err = next.validate();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err)),
      );
      return;
    }
    _opts.modeler = next;
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget sectionTitle(String title) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Advanced Pen Settings', style: theme.textTheme.titleMedium),
        Text(
          'Spring-mass smoothing + variable-width ribbon. '
          'Width comes from the pen size slider.',
          style: theme.textTheme.bodySmall,
        ),
        sectionTitle('Brush Style'),
        _OverlayDropdown<AdvancedPenBuilderType>(
          label: 'Builder',
          value: _opts.builderType,
          values: AdvancedPenBuilderType.values,
          labelOf: (v) => v.id,
          onChanged: (v) {
            _opts.builderType = v;
            _persist();
          },
        ),
        _OverlayDropdown<AdvancedPenPressureCurve>(
          label: 'Pressure curve',
          value: _opts.pressureCurve,
          values: AdvancedPenPressureCurve.values,
          labelOf: (v) => v.id,
          onChanged: (v) {
            _opts.pressureCurve = v;
            _persist();
          },
        ),
        _OverlayDropdown<AdvancedPenLineCap>(
          label: 'Line cap',
          value: _opts.lineCap,
          values: AdvancedPenLineCap.values,
          labelOf: (v) => v.id,
          onChanged: (v) {
            _opts.lineCap = v;
            _persist();
          },
        ),
        sectionTitle('Dynamics & Shape'),
        _slider(
          label: 'Velocity Thinning',
          value: _opts.velocityThinning,
          min: -1.0,
          max: 1.0,
          onChanged: (v) { _opts.velocityThinning = v; _persist(); },
        ),
        _slider(
          label: 'Tip Ratio (Squash)',
          value: _opts.tipRatio,
          min: 0.05,
          max: 1.0,
          onChanged: (v) { _opts.tipRatio = v; _persist(); },
        ),
        _slider(
          label: 'Tip Angle (rad)',
          value: _opts.tipAngle,
          min: -math.pi,
          max: math.pi,
          onChanged: (v) { _opts.tipAngle = v; _persist(); },
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('Tip Follows Path (Tilt)', style: theme.textTheme.bodyMedium),
          value: _opts.useTilt,
          onChanged: (v) { _opts.useTilt = v; _persist(); },
        ),
        sectionTitle('Physics & Feeling'),
        _slider(
          label: 'Tip Torsion (Angle Lag)',
          value: _opts.angleLag,
          min: 0.0,
          max: 1.0,
          onChanged: (v) { _opts.angleLag = v; _persist(); },
        ),
        _slider(
          label: 'Bristle Stiffness (Pressure Inertia)',
          value: _opts.pressureInertia,
          min: 0.0,
          max: 1.0,
          onChanged: (v) { _opts.pressureInertia = v; _persist(); },
        ),
        _slider(
          label: 'Ink Pooling (Rest Bleed)',
          value: _opts.inkPooling,
          min: 0.0,
          max: 1.0,
          onChanged: (v) { _opts.inkPooling = v; _persist(); },
        ),
        _slider(
          label: 'Rope Pull (Leash)',
          value: _opts.ropePull,
          min: 0.0,
          max: 100.0,
          onChanged: (v) { _opts.ropePull = v; _persist(); },
        ),
        _slider(
          label: 'Surface Friction (Jitter)',
          value: _opts.surfaceFriction,
          min: 0.0,
          max: 1.0,
          onChanged: (v) { _opts.surfaceFriction = v; _persist(); },
        ),
        sectionTitle('Topology (Dash)'),
        _slider(
          label: 'Dash Length',
          value: _opts.dashLength,
          min: 0.0,
          max: 100.0,
          onChanged: (v) { _opts.dashLength = v; _persist(); },
        ),
        _slider(
          label: 'Dash Gap',
          value: _opts.dashGap,
          min: 0.0,
          max: 100.0,
          onChanged: (v) { _opts.dashGap = v; _persist(); },
        ),
        sectionTitle('Custom Tapers'),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('Start Taper', style: theme.textTheme.bodyMedium),
          value: widget.pen.options.start.taperEnabled,
          onChanged: (v) { 
            widget.pen.options.start.taperEnabled = v; 
            if (v && widget.pen.options.start.customTaper == null) {
              widget.pen.options.start.customTaper = 20.0;
            }
            _persist(); 
          },
        ),
        if (widget.pen.options.start.taperEnabled)
          _slider(
            label: 'Start Taper Length',
            value: widget.pen.options.start.customTaper ?? 20.0,
            min: 5.0,
            max: 100.0,
            onChanged: (v) { widget.pen.options.start.customTaper = v; _persist(); },
          ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('End Taper', style: theme.textTheme.bodyMedium),
          value: widget.pen.options.end.taperEnabled,
          onChanged: (v) { 
            widget.pen.options.end.taperEnabled = v; 
            if (v && widget.pen.options.end.customTaper == null) {
              widget.pen.options.end.customTaper = 20.0;
            }
            _persist(); 
          },
        ),
        if (widget.pen.options.end.taperEnabled)
          _slider(
            label: 'End Taper Length',
            value: widget.pen.options.end.customTaper ?? 20.0,
            min: 5.0,
            max: 100.0,
            onChanged: (v) { widget.pen.options.end.customTaper = v; _persist(); },
          ),
        sectionTitle('Wobble Smoother'),
        _slider(
          label: 'Timeout',
          value: _modeler.wobbleTimeout,
          min: 0.005,
          max: 0.2,
          onChanged: (v) => _setModeler(_modeler.copyWith(wobbleTimeout: v)),
        ),
        _slider(
          label: 'Speed floor',
          value: _modeler.wobbleSpeedFloor,
          min: 0.1,
          max: 8,
          onChanged: (v) =>
              _setModeler(_modeler.copyWith(wobbleSpeedFloor: v)),
        ),
        _slider(
          label: 'Speed ceiling',
          value: _modeler.wobbleSpeedCeiling,
          min: 0.2,
          max: 10,
          onChanged: (v) =>
              _setModeler(_modeler.copyWith(wobbleSpeedCeiling: v)),
        ),
        sectionTitle('Tip Physics (spring-mass)'),
        _slider(
          label: 'Spring-mass',
          value: _modeler.springMassConstant,
          min: 0.00005,
          max: 0.005,
          onChanged: (v) =>
              _setModeler(_modeler.copyWith(springMassConstant: v)),
        ),
        _slider(
          label: 'Drag',
          value: _modeler.dragConstant,
          min: 1,
          max: 200,
          onChanged: (v) => _setModeler(_modeler.copyWith(dragConstant: v)),
        ),
        sectionTitle('Sampling'),
        _slider(
          label: 'Min output rate',
          value: _modeler.minOutputRate,
          min: 30,
          max: 360,
          onChanged: (v) => _setModeler(_modeler.copyWith(minOutputRate: v)),
        ),
        _slider(
          label: 'End-of-stroke stop dist',
          value: _modeler.endOfStrokeStoppingDistance,
          min: 0.0005,
          max: 0.1,
          onChanged: (v) => _setModeler(
            _modeler.copyWith(endOfStrokeStoppingDistance: v),
          ),
        ),
        _slider(
          label: 'End-of-stroke iterations',
          value: _modeler.endOfStrokeMaxIterations.toDouble(),
          min: 1,
          max: 100,
          onChanged: (v) => _setModeler(
            _modeler.copyWith(endOfStrokeMaxIterations: v.round()),
          ),
        ),
        _slider(
          label: 'Max outputs / call',
          value: _modeler.maxOutputsPerCall.toDouble(),
          min: 5,
          max: 1000,
          onChanged: (v) => _setModeler(
            _modeler.copyWith(maxOutputsPerCall: v.round()),
          ),
        ),
        _slider(
          label: 'Stylus window',
          value: _modeler.maxInputSamples.toDouble(),
          min: 1,
          max: 60,
          onChanged: (v) => _setModeler(
            _modeler.copyWith(maxInputSamples: v.round()),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            widget.pen.brushOptions = Pen.advancedBrushDefaults;
            _persist();
          },
          icon: const Icon(Icons.restart_alt_outlined, size: 18),
          label: const Text('Reset defaults'),
        ),
      ],
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    double min = 0,
    double max = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                value.toStringAsFixed(value < 0.01 ? 5 : 2),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Dropdown that inserts its menu [OverlayEntry] above the parent pen
/// popover. [DropdownButton] menus use the navigator overlay and end up
/// behind the pen card, so taps dismiss the modal instead of selecting.
class _OverlayDropdown<T> extends StatefulWidget {
  const _OverlayDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  State<_OverlayDropdown<T>> createState() => _OverlayDropdownState<T>();
}

class _OverlayDropdownState<T> extends State<_OverlayDropdown<T>> {
  final _layerLink = LayerLink();
  final _fieldKey = GlobalKey();
  OverlayEntry? _menuEntry;
  bool _isOpen = false;

  void _toggle() {
    if (_isOpen) {
      _close();
    } else {
      _open();
    }
  }

  void _open() {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final fieldBox =
        _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final fieldWidth = fieldBox?.size.width ?? 220;
    final fieldHeight = fieldBox?.size.height ?? 40;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    _menuEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _close(),
                child: const SizedBox.expand(),
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: Offset(0, fieldHeight + 4),
              child: Material(
                elevation: 12,
                borderRadius: BorderRadius.circular(12),
                color: scheme.surfaceContainerHigh,
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: fieldWidth,
                    maxWidth: math.max(fieldWidth, 240),
                    maxHeight: 280,
                  ),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    shrinkWrap: true,
                    children: [
                      for (final v in widget.values)
                        ListTile(
                          dense: true,
                          selected: v == widget.value,
                          title: Text(widget.labelOf(v)),
                          trailing: v == widget.value
                              ? Icon(
                                  Icons.check,
                                  size: 18,
                                  color: scheme.primary,
                                )
                              : null,
                          onTap: () {
                            widget.onChanged(v);
                            _close();
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_menuEntry!);
    setState(() => _isOpen = true);
  }

  void _close() {
    _menuEntry?.remove();
    _menuEntry = null;
    if (mounted) setState(() => _isOpen = false);
  }

  @override
  void didUpdateWidget(covariant _OverlayDropdown<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isOpen) {
      _menuEntry?.markNeedsBuild();
    }
  }

  @override
  void dispose() {
    _menuEntry?.remove();
    _menuEntry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CompositedTransformTarget(
        link: _layerLink,
        child: Material(
          key: _fieldKey,
          color: Colors.transparent,
          child: InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              isFocused: _isOpen,
              decoration: InputDecoration(
                labelText: widget.label,
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                suffixIcon: Icon(
                  _isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                ),
              ),
              child: Text(
                widget.labelOf(widget.value),
                style: theme.textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
