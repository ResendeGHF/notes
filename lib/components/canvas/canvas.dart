// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/canvas/page_raster_cache.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
import 'package:saber/components/canvas/selection_handles_layout.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/select.dart';

class ImageCropState {
  const ImageCropState({required this.image, required this.normalizedCrop});
  final EditorImage image;
  final Rect normalizedCrop;
}

class Canvas extends StatelessWidget {
  const Canvas({
    super.key,
    this.overrideInvert,
    required this.path,
    required this.page,
    required this.pageIndex,
    required this.textEditing,
    required this.coreInfo,
    required this.currentStroke,
    required this.currentStrokeDetectedShape,
    required this.currentSelection,
    this.selectionPreview,
    required this.setAsBackground,
    required this.currentTool,
    this.interactionRepaintListenable,
    required this.currentScale,
    this.onNoteLinkTap,
    this.placeholder = false,
    this.eraserPosition,
    this.eraserPositionListenable,
    this.eraserSize,
    this.eraserDeltaRemoved,
    this.eraserDeltaAdded,
    this.doneSelecting = false,
    this.lineHeight,
    this.lineThickness,
    this.lineColor,
    this.imageCropState,
    this.onCropRectChanged,
    this.selectionHandlesInteractionMode = SelectionHandlesInteractionMode.resize,
    this.pageRasterCache,
  });

  final int? lineHeight;
  final int? lineThickness;
  final Color? lineColor;

  final String path;
  final EditorPage page;
  final int pageIndex;

  final bool textEditing;
  final EditorCoreInfo coreInfo;
  final Stroke? currentStroke;
  final RecognizedUnistroke? currentStrokeDetectedShape;
  final SelectResult? currentSelection;
  final SelectionTransformPreview? selectionPreview;

  final void Function(EditorImage image)? setAsBackground;

  final Tool currentTool;
  final ValueListenable<int>? interactionRepaintListenable;
  final double currentScale;
  final bool placeholder;
  final Offset? eraserPosition;
  final ValueListenable<Offset?>? eraserPositionListenable;
  final double? eraserSize;
  final List<Stroke>? eraserDeltaRemoved;
  final List<Stroke>? eraserDeltaAdded;
  final bool doneSelecting;
  final void Function(NoteLink link)? onNoteLinkTap;

  final bool? overrideInvert;
  final ImageCropState? imageCropState;
  final void Function(Rect normalizedCrop)? onCropRectChanged;
  final SelectionHandlesInteractionMode selectionHandlesInteractionMode;
  final PageRasterCacheManager? pageRasterCache;

  Color getOnyxColor() {
    if (currentTool is Pen) {
      return (currentTool as Pen).color;
    } else {
      return Colors.black;
    }
  }

  double getOnyxWidth() {
    if (currentTool is Pen) {
      final baseSize = (currentTool as Pen).options.size * currentScale;
      if ((currentTool as Pen).pressureEnabled) {
        return baseSize;
      } else {
        return baseSize * 2;
      }
    } else {
      return 3;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        child: DecoratedBox(
          decoration: const BoxDecoration(),
          child: !placeholder
              ? SizedBox(
                  width: page.size.width,
                  height: page.size.height,
                  child: SizedBox(
                    child: RepaintBoundary(
                      child: InnerCanvas(
                        key: page.innerCanvasKey,
                        pageIndex: pageIndex,
                        redrawPageListenable: page,
                        width: page.size.width,
                        height: page.size.height,
                        textEditing: textEditing,
                        coreInfo: coreInfo,
                        overrideInvert: overrideInvert,
                        currentStroke: currentStroke,
                        currentStrokeDetectedShape: currentStrokeDetectedShape,
                        currentSelection: currentSelection,
                        selectionPreview: selectionPreview,
                        setAsBackground: setAsBackground,
                        currentToolIsSelect:
                            currentTool.toolId == ToolId.select,
                        interactionRepaintListenable:
                            interactionRepaintListenable,
                        currentScale: currentScale,
                        eraserPosition: eraserPosition,
                        eraserPositionListenable: eraserPositionListenable,
                        eraserSize: eraserSize,
                        eraserDeltaRemoved: eraserDeltaRemoved,
                        eraserDeltaAdded: eraserDeltaAdded,
                        doneSelecting: doneSelecting,
                        onNoteLinkTap: onNoteLinkTap,
                        lineHeight: lineHeight,
                        lineThickness: lineThickness,
                        lineColor: lineColor,
                        imageCropState: imageCropState != null
                            ? (
                                image: imageCropState!.image,
                                normalizedCrop: imageCropState!.normalizedCrop,
                              )
                            : null,
                        onCropRectChanged: onCropRectChanged,
                        selectionHandlesInteractionMode:
                            selectionHandlesInteractionMode,
                        pageRasterCache: pageRasterCache,
                      ),
                    ),
                  ),
                )
              : SizedBox(width: page.size.width, height: page.size.height),
        ),
      ),
    );
  }
}
