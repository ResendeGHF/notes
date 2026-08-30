// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/i18n/strings.g.dart';

class SizePicker extends StatefulWidget {
  const SizePicker({super.key, required this.axis, required this.pen});

  final Axis axis;
  final Pen pen;

  @override
  State<SizePicker> createState() => _SizePickerState();

  static const double smallLength = 25;
  static const double largeLength = 150;
}

String _prettyNum(double num) {
  return num.toStringAsFixed(1);
}

class _SizePickerState extends State<SizePicker> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    final displaySize = widget.pen is Highlighter
        ? widget.pen.options.size
        : widget.pen.options.size * 2;

    return Flex(
      direction: widget.axis,
      mainAxisSize: .min,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t.editor.penOptions.size,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.8),
                fontSize: 10,
                height: 1,
              ),
            ),
            SizedBox(
              width: 42,
              child: Text(
                _prettyNum(displaySize),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFeatures: [ui.FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: _SizeSlider(
            pen: widget.pen,
            axis: widget.axis,
            setState: setState,
          ),
        ),
        const SizedBox(width: 8),

        Column(
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () {
                setState(() {
                  widget.pen.options.size =
                      (widget.pen.options.size + widget.pen.sizeStep / 2).clamp(
                        widget.pen.sizeMin,
                        widget.pen.sizeMax,
                      );
                });
              },
              icon: const Icon(Icons.add, size: 18),
              tooltip: t.editor.penOptions.size,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () {
                setState(() {
                  widget.pen.options.size =
                      (widget.pen.options.size - widget.pen.sizeStep / 2).clamp(
                        widget.pen.sizeMin,
                        widget.pen.sizeMax,
                      );
                });
              },
              icon: const Icon(Icons.remove, size: 18),
              tooltip: t.editor.penOptions.size,
            ),
          ],
        ),
      ],
    );
  }
}

class _SizeSlider extends StatelessWidget {
  const _SizeSlider({
    required this.pen,
    required this.axis,
    required this.setState,
  });

  final Pen pen;
  final Axis axis;
  final void Function(void Function()) setState;

  double _sliderToSize(double value) {
    final curved = value.clamp(0.0, 1.0);
    final size = pen.sizeMin + curved * (pen.sizeMax - pen.sizeMin);

    final stepsFromMin = ((size - pen.sizeMin) / pen.sizeStep).round();
    return (pen.sizeMin + stepsFromMin * pen.sizeStep).clamp(
      pen.sizeMin,
      pen.sizeMax,
    );
  }

  double _sizeToSlider(double size) {
    final clampedSize = size.clamp(pen.sizeMin, pen.sizeMax);
    return ((clampedSize - pen.sizeMin) / (pen.sizeMax - pen.sizeMin)).clamp(
      0.0,
      1.0,
    );
  }

  double _getValue() => _sizeToSlider(pen.options.size);

  void _onChanged(double value) {
    final newSize = _sliderToSize(value);
    if (newSize == pen.options.size) return;
    setState(() {
      pen.options.size = newSize;
    });
  }

  @override
  Widget build(BuildContext context) {
    final slider = Slider(
      value: _getValue(),
      onChanged: _onChanged,
      min: 0.0,
      max: 1.0,

      divisions: 100,
    );

    if (axis == Axis.vertical) {
      return SizedBox(
        width: SizePicker.smallLength,
        height: SizePicker.largeLength,
        child: RotatedBox(quarterTurns: 3, child: slider),
      );
    } else {
      return SizedBox(
        width: SizePicker.largeLength,
        height: SizePicker.smallLength,
        child: slider,
      );
    }
  }
}
