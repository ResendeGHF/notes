// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/list_extensions.dart';

class CanvasPreview extends StatelessWidget implements PreferredSizeWidget {
  CanvasPreview({
    super.key,
    this.pageIndex = 0,
    required this.height,
    required this.coreInfo,
    this.highQuality = false,
    this.overrideInvert,
  });

  final int pageIndex;
  final double? height;
  final EditorCoreInfo coreInfo;

  final bool? overrideInvert;

  final bool highQuality;

  late final pageSize =
      coreInfo.pages.getOrNull(pageIndex)?.size ?? EditorPage.defaultSize;
  @override
  late final preferredSize = Size(pageSize.width, height ?? pageSize.height);

  @override
  Widget build(BuildContext context) {
    return InnerCanvas(
      pageIndex: pageIndex,
      width: preferredSize.width,
      height: preferredSize.height,
      isPreview: true,
      coreInfo: coreInfo,
      currentStroke: null,
      currentStrokeDetectedShape: null,
      currentSelection: null,
      currentToolIsSelect: false,
      currentScale: highQuality ? double.maxFinite : 0.4,
      overrideInvert: overrideInvert,
    );
  }
}
