// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:saber/data/editor/stroke_paint.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/i18n/strings.g.dart';

/// Advanced Pencil: Advanced-pen geometry + procedural noise (not image tiles).
/// Presets are stored separately from [AdvancedPenPanel].
/// Advanced Pencil Presets Section
class AdvancedPencilPresets extends StatefulWidget {
  const AdvancedPencilPresets({
    super.key,
    required this.pen,
    required this.onChanged,
  });

  final Pen pen;
  final VoidCallback onChanged;

  @override
  State<AdvancedPencilPresets> createState() => _AdvancedPencilPresetsState();
}

class _AdvancedPencilPresetsState extends State<AdvancedPencilPresets> {
  late final TextEditingController _presetNameController;

  @override
  void initState() {
    super.initState();
    _presetNameController = TextEditingController();
    _ensureDefaultPreset();
  }

  @override
  void dispose() {
    _presetNameController.dispose();
    super.dispose();
  }

  StrokeOptions get _opts => widget.pen.options;
  StrokePaint get _paint => widget.pen.paint;

  void _ensureDefaultPreset() {
    if (stows.advancedPencilPresets.value.isNotEmpty) return;
    stows.advancedPencilPresets.value = [
      Pen.defaultAdvancedPencilPresetPayload(),
    ];
  }

  void _persist() {
    stows.lastAdvancedPencilOptions.value = _opts.copyWith();
    stows.lastAdvancedPencilPaint.value = Map<String, dynamic>.from(
      _paint.toJson(embedBytes: false),
    );
    widget.onChanged();
    setState(() {});
  }

  Map<String, dynamic> _presetPayload(String name) => {
    'name': name,
    'options': _opts.toJson(),
    'colorArgb': widget.pen.color.toARGB32(),
    'easingId': stows.lastAdvancedPencilMainEasingId.value,
    'startEasingId': stows.lastAdvancedPencilStartEasingId.value,
    'endEasingId': stows.lastAdvancedPencilEndEasingId.value,
    'paint': _paint.toJson(embedBytes: false),
  };

  void _applyPreset(Map<String, dynamic> preset) {
    final raw = preset['options'];
    if (raw is! Map) return;
    final opts = StrokeOptions.fromJson(
      Map<String, dynamic>.from(raw),
      easing: StrokeEasingCatalog.byId(preset['easingId'] as String?),
      startEasing: StrokeEasingCatalog.byId(preset['startEasingId'] as String?),
      endEasing: StrokeEasingCatalog.byId(preset['endEasingId'] as String?),
    );
    widget.pen.options
      ..size = opts.size
      ..thinning = opts.thinning
      ..smoothing = opts.smoothing
      ..streamline = opts.streamline
      ..simulatePressure = opts.simulatePressure
      ..pressureSensitivity = opts.pressureSensitivity
      ..velocityThinning = opts.velocityThinning
      ..minSizeRatio = opts.minSizeRatio
      ..maxSizeRatio = opts.maxSizeRatio
      ..easing = opts.easing
      ..start = opts.start
      ..end = opts.end;
    stows.lastAdvancedPencilMainEasingId.value =
        (preset['easingId'] as String?) ?? StrokeEasingCatalog.identity;
    stows.lastAdvancedPencilStartEasingId.value =
        (preset['startEasingId'] as String?) ?? StrokeEasingCatalog.easeInOut;
    stows.lastAdvancedPencilEndEasingId.value =
        (preset['endEasingId'] as String?) ?? StrokeEasingCatalog.easeOutCubic;
    final colorArgb = preset['colorArgb'];
    if (colorArgb is int) {
      widget.pen.color = Color(colorArgb);
      stows.lastAdvancedPencilColor.value = colorArgb;
    }
    final paintRaw = preset['paint'];
    if (paintRaw is Map) {
      widget.pen.paint = StrokePaint.fromJson(
        Map<String, dynamic>.from(paintRaw),
      ).copyWith(mode: StrokePaintMode.pencilNoise);
    } else {
      widget.pen.paint = StrokePaint.pencilNoiseDefault();
    }
    _persist();
  }

  Future<void> _savePreset({int? replaceIndex}) async {
    final name = _presetNameController.text.trim().isEmpty
        ? 'Preset ${(stows.advancedPencilPresets.value.length + 1)}'
        : _presetNameController.text.trim();
    final list = List<Map<String, dynamic>>.from(
      stows.advancedPencilPresets.value,
    );
    final payload = _presetPayload(name);
    if (replaceIndex != null &&
        replaceIndex >= 0 &&
        replaceIndex < list.length) {
      list[replaceIndex] = payload;
    } else {
      list.add(payload);
    }
    stows.advancedPencilPresets.value = list;
    _presetNameController.clear();
    setState(() {});
  }

  void _deletePreset(int index) {
    final list = List<Map<String, dynamic>>.from(
      stows.advancedPencilPresets.value,
    );
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    stows.advancedPencilPresets.value = list;
    _ensureDefaultPreset();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final presets = stows.advancedPencilPresets.value;

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
        sectionTitle("Presets"),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _presetNameController,
                decoration: InputDecoration(
                  isDense: true, 
                  hintText: t.editor.penOptions.presetNameHint, 
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
                  onPressed: () { _presetNameController.text = name; _savePreset(replaceIndex: i); }
                ),
                IconButton(
                  tooltip: t.toolbar.deletePreset,
                  icon: const Icon(Icons.delete_outline, size: 20), 
                  onPressed: () => _deletePreset(i)
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

/// Advanced Pencil Settings Section
class AdvancedPencilSettings extends StatefulWidget {
  const AdvancedPencilSettings({
    super.key,
    required this.pen,
    required this.onChanged,
  });

  final Pen pen;
  final VoidCallback onChanged;

  @override
  State<AdvancedPencilSettings> createState() => _AdvancedPencilSettingsState();
}

class _AdvancedPencilSettingsState extends State<AdvancedPencilSettings> {
  StrokeOptions get _opts => widget.pen.options;
  StrokePaint get _paint => widget.pen.paint;

  void _persist() {
    stows.lastAdvancedPencilOptions.value = _opts.copyWith();
    stows.lastAdvancedPencilPaint.value = Map<String, dynamic>.from(
      _paint.toJson(embedBytes: false),
    );
    widget.onChanged();
    setState(() {});
  }

  void _setMainEasing(String id) {
    stows.lastAdvancedPencilMainEasingId.value = id;
    widget.pen.options.easing = StrokeEasingCatalog.byId(id);
    _persist();
  }

  void _setStartEasing(String id) {
    stows.lastAdvancedPencilStartEasingId.value = id;
    widget.pen.options.start.easing = StrokeEasingCatalog.byId(id);
    _persist();
  }

  void _setEndEasing(String id) {
    stows.lastAdvancedPencilEndEasingId.value = id;
    widget.pen.options.end.easing = StrokeEasingCatalog.byId(id);
    _persist();
  }

  void _resetNoiseDefaults() {
    widget.pen.paint = StrokePaint.pencilNoiseDefault().copyWith(
      pressureMapsToCoverage: _paint.pressureMapsToCoverage,
      pencilShadow: _paint.pencilShadow,
    );
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
        Text("Advanced Pencil Settings", style: theme.textTheme.titleMedium),
        
        sectionTitle("Stroke Dynamics"),
        _slider(label: "Thinning", value: _opts.thinning, min: -0.5, max: 1.0, onChanged: _paint.pressureMapsToCoverage ? null : (v) { _opts.thinning = v; _persist(); }),
        _slider(label: "Smoothing", value: _opts.smoothing, onChanged: (v) { _opts.smoothing = v; _persist(); }),
        _slider(label: "Streamline", value: _opts.streamline, onChanged: (v) { _opts.streamline = v; _persist(); }),
        
        sectionTitle("Pressure"),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(t.toolbar.simulatePressure, style: theme.textTheme.bodyMedium),
          value: _opts.simulatePressure,
          onChanged: (v) { _opts.simulatePressure = v; _persist(); },
        ),
        _slider(label: "Sensitivity", value: _opts.pressureSensitivity, min: 0.0, max: 2.0, onChanged: (v) { _opts.pressureSensitivity = v; _persist(); }),
        _slider(label: "Velocity Thinning", value: _opts.velocityThinning, onChanged: (v) { _opts.velocityThinning = v; _persist(); }),
        _slider(label: "Min Size Ratio", value: _opts.minSizeRatio, min: 0.02, max: 1.0, onChanged: (v) { _opts.minSizeRatio = v; _persist(); }),
        _slider(label: "Max Size Ratio", value: _opts.maxSizeRatio, min: 0.2, max: 2.0, onChanged: (v) { _opts.maxSizeRatio = v; _persist(); }),

        sectionTitle("Tapering & Caps"),
        _slider(label: "Start Taper", value: (_opts.start.customTaper ?? 0).clamp(0, 40), min: 0, max: 40, onChanged: (v) { _opts.start.customTaper = v <= 0 ? null : v; _opts.start.taperEnabled = v > 0; _persist(); }),
        SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, dense: true, title: Text("Start Cap", style: theme.textTheme.bodyMedium), value: _opts.start.cap, onChanged: (v) { _opts.start.cap = v; _persist(); }),
        _slider(label: "End Taper", value: (_opts.end.customTaper ?? 0).clamp(0, 40), min: 0, max: 40, onChanged: (v) { _opts.end.customTaper = v <= 0 ? null : v; _opts.end.taperEnabled = v > 0; _persist(); }),
        SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, dense: true, title: Text("End Cap", style: theme.textTheme.bodyMedium), value: _opts.end.cap, onChanged: (v) { _opts.end.cap = v; _persist(); }),

        sectionTitle("Easing"),
        _easingDropdown(label: "Main Easing", value: stows.lastAdvancedPencilMainEasingId.value, onChanged: _setMainEasing),
        _easingDropdown(label: "Start Easing", value: stows.lastAdvancedPencilStartEasingId.value, onChanged: _setStartEasing),
        _easingDropdown(label: "End Easing", value: stows.lastAdvancedPencilEndEasingId.value, onChanged: _setEndEasing),

        const Divider(height: 24),
        Row(
          children: [
            Expanded(
              child: Text("Pencil Noise Options", style: theme.textTheme.labelMedium?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.w600)),
            ),
            TextButton(onPressed: _resetNoiseDefaults, child: Text(t.editor.penOptions.resetNoiseDefaults)),
          ],
        ),
        const SizedBox(height: 4),
        _slider(label: "Grain Scale", value: _paint.noiseGrainScale.clamp(0.01, 0.25), min: 0.01, max: 0.25, onChanged: (v) { widget.pen.paint = _paint.copyWith(mode: StrokePaintMode.pencilNoise, noiseGrainScale: v); _persist(); }),
        _slider(label: "Threshold", value: _paint.noiseThreshold.clamp(0.15, 0.9), min: 0.15, max: 0.9, onChanged: (v) { widget.pen.paint = _paint.copyWith(mode: StrokePaintMode.pencilNoise, noiseThreshold: v); _persist(); }),
        _slider(label: "Contrast", value: _paint.noiseContrast.clamp(0.4, 2.5), min: 0.4, max: 2.5, onChanged: (v) { widget.pen.paint = _paint.copyWith(mode: StrokePaintMode.pencilNoise, noiseContrast: v); _persist(); }),
        _slider(label: "Fine Mix", value: _paint.noiseFineMix.clamp(0.0, 1.0), min: 0.0, max: 1.0, onChanged: (v) { widget.pen.paint = _paint.copyWith(mode: StrokePaintMode.pencilNoise, noiseFineMix: v); _persist(); }),
        
        const SizedBox(height: 12),
        Text(t.editor.penOptions.pressureMapsTo, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('Thickness')),
            ButtonSegment(value: true, label: Text('Coverage')),
          ],
          selected: {_paint.pressureMapsToCoverage},
          onSelectionChanged: (s) { widget.pen.paint = _paint.copyWith(mode: StrokePaintMode.pencilNoise, pressureMapsToCoverage: s.first); _persist(); },
        ),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(t.editor.penOptions.pencilShadow, style: theme.textTheme.bodyMedium),
          value: _paint.pencilShadow,
          onChanged: (v) { widget.pen.paint = _paint.copyWith(mode: StrokePaintMode.pencilNoise, pencilShadow: v); _persist(); },
        ),
      ],
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required ValueChanged<double>? onChanged,
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
              Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
              Text(value.toStringAsFixed(2), style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _easingDropdown({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    final safe = StrokeEasingCatalog.ids.contains(value)
        ? value
        : StrokeEasingCatalog.identity;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _OverlayEasingDropdown(
        label: label,
        value: safe,
        onChanged: onChanged,
      ),
    );
  }
}

/// Same overlay dropdown pattern as Advanced Pen (menus above pen popover).
class _OverlayEasingDropdown extends StatefulWidget {
  const _OverlayEasingDropdown({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_OverlayEasingDropdown> createState() => _OverlayEasingDropdownState();
}

class _OverlayEasingDropdownState extends State<_OverlayEasingDropdown> {
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
                      for (final id in StrokeEasingCatalog.ids)
                        ListTile(
                          dense: true,
                          selected: id == widget.value,
                          title: Text(StrokeEasingCatalog.label(id)),
                          trailing: id == widget.value
                              ? Icon(
                                  Icons.check,
                                  size: 18,
                                  color: scheme.primary,
                                )
                              : null,
                          onTap: () {
                            widget.onChanged(id);
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
  void didUpdateWidget(covariant _OverlayEasingDropdown oldWidget) {
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
    return CompositedTransformTarget(
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
              StrokeEasingCatalog.label(widget.value),
              style: theme.textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}
