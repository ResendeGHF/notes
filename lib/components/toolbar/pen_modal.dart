// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:saber/components/toolbar/size_picker.dart';
import 'package:saber/data/extensions/axis_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/i18n/strings.g.dart';

class PenModal extends StatefulWidget {
  const PenModal({super.key, required this.getTool, required this.setTool});

  final Tool Function() getTool;
  final void Function(Pen) setTool;

  @override
  State<PenModal> createState() => _PenModalState();
}

class _PenModalState extends State<PenModal> {
  @override
  Widget build(BuildContext context) {
    final axis = stows.editorToolbarAlignment.value.axis.opposite;
    final Tool currentTool = widget.getTool();
    final Pen currentPen;
    if (currentTool is Pen) {
      currentPen = currentTool;
    } else {
      return const SizedBox();
    }

    return Flex(
      direction: axis,
      mainAxisAlignment: .center,
      children: [
        SizePicker(axis: axis, pen: currentPen),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Flex(
            direction: axis == Axis.horizontal
                ? Axis.vertical
                : Axis.horizontal,
            mainAxisSize: MainAxisSize.min,
            children: [

              ValueListenableBuilder(
                valueListenable: stows.strokeStabilization,
                builder: (context, enabled, _) {
                  return IconButton(
                    onPressed: () {
                      stows.strokeStabilization.value =
                          !stows.strokeStabilization.value;
                    },
                    tooltip: t.settings.prefLabels.strokeStabilization,
                    icon: Icon(
                      enabled ? Icons.auto_fix_high : Icons.auto_fix_off,
                      color: enabled
                          ? ColorScheme.of(context).primary
                          : ColorScheme.of(
                              context,
                            ).onSurface.withValues(alpha: 0.5),
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: enabled
                          ? ColorScheme.of(
                              context,
                            ).primary.withValues(alpha: 0.1)
                          : Colors.transparent,
                    ),
                  );
                },
              ),

              SizedBox(
                width: axis == Axis.horizontal ? 120 : null,
                height: axis == Axis.vertical ? 120 : null,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t.settings.prefLabels.strokeStabilizationAmount,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Expanded(
                      child: ValueListenableBuilder(
                        valueListenable: stows.strokeStabilizationAmount,
                        builder: (context, amount, _) {
                          return axis == Axis.horizontal
                              ? Slider(
                                  value: amount,
                                  min: 0.0,
                                  max: 1.0,
                                  divisions: 20,
                                  label: amount > 0
                                      ? '${(amount * 100).toStringAsFixed(0)}%'
                                      : 'Off',
                                  onChanged: (value) {
                                    stows.strokeStabilizationAmount.value =
                                        value;

                                    if (value > 0 &&
                                        !stows.strokeStabilization.value) {
                                      stows.strokeStabilization.value = true;
                                    } else if (value == 0 &&
                                        stows.strokeStabilization.value) {
                                      stows.strokeStabilization.value = false;
                                    }
                                  },
                                )
                              : RotatedBox(
                                  quarterTurns: 3,
                                  child: Slider(
                                    value: amount,
                                    min: 0.0,
                                    max: 1.0,
                                    divisions: 20,
                                    label: amount > 0
                                        ? '${(amount * 100).toStringAsFixed(0)}%'
                                        : 'Off',
                                    onChanged: (value) {
                                      stows.strokeStabilizationAmount.value =
                                          value;

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
                    ),
                    ValueListenableBuilder(
                      valueListenable: stows.strokeStabilizationAmount,
                      builder: (context, amount, _) {
                        return Text(
                          amount > 0
                              ? '${(amount * 100).toStringAsFixed(0)}%'
                              : 'Off',
                          style: Theme.of(context).textTheme.labelSmall,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Flex(
            direction: axis == Axis.horizontal
                ? Axis.vertical
                : Axis.horizontal,
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder(
                valueListenable: stows.strokePrediction,
                builder: (context, enabled, _) {
                  return IconButton(
                    onPressed: () {
                      stows.strokePrediction.value =
                          !stows.strokePrediction.value;
                    },
                    tooltip: t.settings.prefLabels.strokePrediction,
                    icon: Icon(
                      enabled ? Icons.bolt : Icons.bolt_outlined,
                      color: enabled
                          ? ColorScheme.of(context).primary
                          : ColorScheme.of(
                              context,
                            ).onSurface.withValues(alpha: 0.5),
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: enabled
                          ? ColorScheme.of(
                              context,
                            ).primary.withValues(alpha: 0.1)
                          : Colors.transparent,
                    ),
                  );
                },
              ),
              SizedBox(
                width: axis == Axis.horizontal ? 120 : null,
                height: axis == Axis.vertical ? 120 : null,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t.settings.prefLabels.strokePredictionAmount,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Expanded(
                      child: ValueListenableBuilder(
                        valueListenable: stows.strokePredictionAmount,
                        builder: (context, amount, _) {
                          return axis == Axis.horizontal
                              ? Slider(
                                  value: amount,
                                  min: 0.0,
                                  max: 1.0,
                                  divisions: 20,
                                  label: '${(amount * 100).toStringAsFixed(0)}%',
                                  onChanged: (value) {
                                    stows.strokePredictionAmount.value =
                                        value;
                                    if (value > 0 &&
                                        !stows.strokePrediction.value) {
                                      stows.strokePrediction.value = true;
                                    } else if (value == 0 &&
                                        stows.strokePrediction.value) {
                                      stows.strokePrediction.value = false;
                                    }
                                  },
                                )
                              : RotatedBox(
                                  quarterTurns: 3,
                                  child: Slider(
                                    value: amount,
                                    min: 0.0,
                                    max: 1.0,
                                    divisions: 20,
                                    label:
                                        '${(amount * 100).toStringAsFixed(0)}%',
                                    onChanged: (value) {
                                      stows.strokePredictionAmount.value =
                                          value;
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
                    ),
                    ValueListenableBuilder(
                      valueListenable: stows.strokePredictionAmount,
                      builder: (context, amount, _) {
                        return Text(
                          '${(amount * 100).toStringAsFixed(0)}%',
                          style: Theme.of(context).textTheme.labelSmall,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        if (currentPen is Highlighter) ...[
          const SizedBox.square(dimension: 8),
          ValueListenableBuilder(
            valueListenable: stows.highlighterFlatEdge,
            builder: (context, enabled, _) {
              return IconButton(
                onPressed: () {
                  stows.highlighterFlatEdge.value =
                      !stows.highlighterFlatEdge.value;
                },
                tooltip: t.settings.prefLabels.flatEdge,
                icon: Icon(
                  enabled ? Icons.square : Icons.square_outlined,
                  color: enabled
                      ? ColorScheme.of(context).primary
                      : ColorScheme.of(
                          context,
                        ).onSurface.withValues(alpha: 0.5),
                ),
                style: IconButton.styleFrom(
                  backgroundColor: enabled
                      ? ColorScheme.of(context).primary.withValues(alpha: 0.1)
                      : Colors.transparent,
                ),
              );
            },
          ),
        ],
        if (currentPen is! Highlighter) ...[
          const SizedBox.square(dimension: 8),
          IconButton(
            onPressed: () => setState(() {
              widget.setTool(Pen.fountainPen());
            }),
            style: TextButton.styleFrom(
              foregroundColor: Pen.currentPen.icon == Pen.fountainPenIcon
                  ? ColorScheme.of(context).secondary
                  : ColorScheme.of(context).onSurface,
              backgroundColor: Pen.currentPen.icon == Pen.fountainPenIcon
                  ? Theme.of(
                      context,
                    ).colorScheme.secondary.withValues(alpha: 0.1)
                  : Colors.transparent,
              shape: const CircleBorder(),
            ),
            tooltip: t.editor.pens.fountainPen,
            icon: SvgPicture.asset(
              'assets/images/scribble_fountain.svg',
              width: 32,
              height: 32 / 508 * 374,
              theme: SvgTheme(
                currentColor: Pen.currentPen.icon == Pen.fountainPenIcon
                    ? ColorScheme.of(context).secondary
                    : ColorScheme.of(context).onSurface,
              ),
            ),
          ),
          const SizedBox.square(dimension: 8),
          IconButton(
            onPressed: () => setState(() {
              widget.setTool(Pen.ballpointPen());
            }),
            style: TextButton.styleFrom(
              foregroundColor: Pen.currentPen.icon == Pen.ballpointPenIcon
                  ? ColorScheme.of(context).secondary
                  : ColorScheme.of(context).onSurface,
              backgroundColor: Pen.currentPen.icon == Pen.ballpointPenIcon
                  ? Theme.of(
                      context,
                    ).colorScheme.secondary.withValues(alpha: 0.1)
                  : Colors.transparent,
              shape: const CircleBorder(),
            ),
            tooltip: t.editor.pens.ballpointPen,
            icon: SvgPicture.asset(
              'assets/images/scribble_ballpoint.svg',
              width: 32,
              height: 32 / 508 * 374,
              theme: SvgTheme(
                currentColor: Pen.currentPen.icon == Pen.ballpointPenIcon
                    ? ColorScheme.of(context).secondary
                    : ColorScheme.of(context).onSurface,
              ),
            ),
          ),
          const SizedBox.square(dimension: 8),
          IconButton(
            onPressed: () => setState(() {
              widget.setTool(Pen.calligraphyPen());
            }),
            style: TextButton.styleFrom(
              foregroundColor: Pen.currentPen.icon == Pen.calligraphyPenIcon
                  ? ColorScheme.of(context).secondary
                  : ColorScheme.of(context).onSurface,
              backgroundColor: Pen.currentPen.icon == Pen.calligraphyPenIcon
                  ? Theme.of(
                      context,
                    ).colorScheme.secondary.withValues(alpha: 0.1)
                  : Colors.transparent,
              shape: const CircleBorder(),
            ),
            tooltip: t.editor.pens.calligraphyPen,
            icon: SvgPicture.asset(
              'assets/images/scribble_calligraphy.svg',
              width: 32,
              height: 32 / 508 * 374,
              theme: SvgTheme(
                currentColor: Pen.currentPen.icon == Pen.calligraphyPenIcon
                    ? ColorScheme.of(context).secondary
                    : ColorScheme.of(context).onSurface,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
