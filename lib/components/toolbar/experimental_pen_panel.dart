// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/google_ink_brush.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/services/google_ink_channel.dart';

/// Test bench for the Google Ink experimental pen.
///
/// Exposes the native `androidx.ink` brush + input-model knobs so different
/// stroke feels can be A/B tested without touching the `perfect_freehand`
/// pens:
/// - `BrushFamily` (pressurePen / marker / highlighter / brush / calligraphy /
///   dashedLine) -> `StockBrushes.*`
/// - `size` / `epsilon` -> `Brush.size` / `Brush.epsilon`
/// - smoothing window -> `SlidingWindowModel`, prediction -> MotionEventPredictor
/// - pressure / tilt / velocity response -> tip mapping
///
/// Committed strokes snapshot this config per-stroke and render through the
/// same tiled Picture + temporary-raster LOD path as all other ink.
class ExperimentalPenPresets extends StatefulWidget {
  const ExperimentalPenPresets({
    super.key,
    required this.pen,
    required this.onChanged,
  });

  final Pen pen;
  final VoidCallback onChanged;

  @override
  State<ExperimentalPenPresets> createState() => _ExperimentalPenPresetsState();
}

class _ExperimentalPenPresetsState extends State<ExperimentalPenPresets> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  GoogleInkBrushConfig get _brush => widget.pen.inkBrush;

  void _persistBrush() {
    widget.pen.options.size = _brush.size;
    widget.pen.color = Color(_brush.colorArgb);
    stows.lastExperimentalInkBrush.value = _brush.copy();
    stows.lastExperimentalPenColor.value = _brush.colorArgb;
    GoogleInkNative.setBrush(_brush);
    widget.onChanged();
    setState(() {});
  }

  Map<String, dynamic> _payload(String name) => {
        'name': name,
        'brush': _brush.toJson(),
        'colorArgb': _brush.colorArgb,
      };

  void _apply(Map<String, dynamic> preset) {
    final raw = preset['brush'];
    if (raw is Map) {
      final loaded = GoogleInkBrushConfig.fromJson(
        Map<String, dynamic>.from(raw),
      );
      widget.pen.inkBrush
        ..family = loaded.family
        ..size = loaded.size
        ..colorArgb = loaded.colorArgb
        ..epsilon = loaded.epsilon
        ..smoothingWindowMs = loaded.smoothingWindowMs
        ..predictionEnabled = loaded.predictionEnabled
        ..predictionAmount = loaded.predictionAmount
        ..pressureSensitivity = loaded.pressureSensitivity
        ..tiltResponse = loaded.tiltResponse
        ..velocityResponse = loaded.velocityResponse
        ..useNativeView = loaded.useNativeView
        ..minSizeRatio = loaded.minSizeRatio
        ..maxSizeRatio = loaded.maxSizeRatio;
      final c = preset['colorArgb'];
      if (c is int) widget.pen.inkBrush.colorArgb = c;
    }
    _persistBrush();
  }

  Future<void> _save({int? replaceIndex}) async {
    final name = _nameController.text.trim().isEmpty
        ? 'Preset ${(stows.experimentalPenPresets.value.length + 1)}'
        : _nameController.text.trim();
    final list = List<Map<String, dynamic>>.from(
      stows.experimentalPenPresets.value,
    );
    final payload = _payload(name);
    if (replaceIndex != null &&
        replaceIndex >= 0 &&
        replaceIndex < list.length) {
      list[replaceIndex] = payload;
    } else {
      list.add(payload);
    }
    stows.experimentalPenPresets.value = list;
    _nameController.clear();
    setState(() {});
  }

  void _delete(int index) {
    final list = List<Map<String, dynamic>>.from(
      stows.experimentalPenPresets.value,
    );
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    stows.experimentalPenPresets.value = list;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final presets = stows.experimentalPenPresets.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(
            'Presets',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Preset name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Save preset',
              onPressed: () => _save(),
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
            onTap: () => _apply(presets[i]),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Update preset',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () {
                    _nameController.text = name;
                    _save(replaceIndex: i);
                  },
                ),
                IconButton(
                  tooltip: 'Delete preset',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => _delete(i),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class ExperimentalPenSettings extends StatefulWidget {
  const ExperimentalPenSettings({
    super.key,
    required this.pen,
    required this.onChanged,
  });

  final Pen pen;
  final VoidCallback onChanged;

  @override
  State<ExperimentalPenSettings> createState() =>
      _ExperimentalPenSettingsState();
}

class _ExperimentalPenSettingsState extends State<ExperimentalPenSettings> {
  GoogleInkBrushConfig get _b => widget.pen.inkBrush;

  void _persist() {
    widget.pen.options.size = _b.size;
    widget.pen.color = Color(_b.colorArgb);
    stows.lastExperimentalInkBrush.value = _b.copy();
    stows.lastExperimentalPenColor.value = _b.colorArgb;
    GoogleInkNative.setBrush(_b);
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget title(String t) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(
            t,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Experimental Pen Settings (Google Ink)',
            style: theme.textTheme.titleMedium),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            GoogleInkNative.isNativeSupported
                ? 'Live: native InProgressStrokesView (120Hz stylus, shaders). Committed ink uses the same tiled + temporary-raster LOD as all pens.'
                : 'Live: Dart stroke-modeler fallback (this device has no Android PlatformView). Committed ink still uses tiled + temporary-raster LOD.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        title('Brush family (StockBrushes)'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in GoogleInkBrushFamily.values)
              ChoiceChip(
                label: Text(f.label),
                selected: _b.family == f,
                onSelected: (_) {
                  _b.family = f;
                  _persist();
                },
              ),
          ],
        ),
        title('Brush size + fidelity'),
        _slider(
          label: 'Size (Brush.size)',
          value: _b.size,
          min: GoogleInkBrushConfig.minSize,
          max: GoogleInkBrushConfig.maxSize,
          onChanged: (v) {
            _b.size = v;
            _persist();
          },
        ),
        _slider(
          label: 'Epsilon (geometry fidelity)',
          value: _b.epsilon,
          min: GoogleInkBrushConfig.minEpsilon,
          max: GoogleInkBrushConfig.maxEpsilon,
          onChanged: (v) {
            _b.epsilon = v;
            _persist();
          },
        ),
        title('Input model (stroke-modeler)'),
        _slider(
          label: 'Smoothing window (ms)',
          value: _b.smoothingWindowMs,
          min: 0,
          max: 120,
          onChanged: (v) {
            _b.smoothingWindowMs = v;
            _persist();
          },
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('Prediction (MotionEventPredictor)',
              style: theme.textTheme.bodyMedium),
          value: _b.predictionEnabled,
          onChanged: (v) {
            _b.predictionEnabled = v;
            _persist();
          },
        ),
        _slider(
          label: 'Prediction amount',
          value: _b.predictionAmount,
          onChanged: (v) {
            _b.predictionAmount = v;
            _persist();
          },
        ),
        title('Tip response'),
        _slider(
          label: 'Pressure sensitivity',
          value: _b.pressureSensitivity,
          min: 0,
          max: 2,
          onChanged: (v) {
            _b.pressureSensitivity = v;
            _persist();
          },
        ),
        _slider(
          label: 'Tilt response',
          value: _b.tiltResponse,
          onChanged: (v) {
            _b.tiltResponse = v;
            _persist();
          },
        ),
        _slider(
          label: 'Velocity response',
          value: _b.velocityResponse,
          onChanged: (v) {
            _b.velocityResponse = v;
            _persist();
          },
        ),
        _slider(
          label: 'Min size ratio',
          value: _b.minSizeRatio,
          min: 0.02,
          max: 1.0,
          onChanged: (v) {
            _b.minSizeRatio = v;
            _persist();
          },
        ),
        _slider(
          label: 'Max size ratio',
          value: _b.maxSizeRatio,
          min: 0.2,
          max: 2.0,
          onChanged: (v) {
            _b.maxSizeRatio = v;
            _persist();
          },
        ),
        title('Engine'),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('Use native PlatformView when available',
              style: theme.textTheme.bodyMedium),
          subtitle: Text(
            GoogleInkNative.isNativeSupported
                ? 'Android: ${GoogleInkNative.viewType}\nLive nativo só para stylus; dedos/mouse/borracha e pan/zoom continuam no Flutter.'
                : 'Not available on this platform — Dart fallback active',
            style: theme.textTheme.bodySmall,
          ),
          value: _b.useNativeView && GoogleInkNative.isNativeSupported,
          onChanged: !GoogleInkNative.isNativeSupported
              ? null
              : (v) {
                  _b.useNativeView = v;
                  _persist();
                },
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
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
              ),
              Text(value.toStringAsFixed(2),
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
        ],
      ),
    );
  }
}
