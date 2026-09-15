// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/pages/editor/editor.dart';

class CanvasScrollbar extends StatefulWidget {
  const CanvasScrollbar({
    super.key,
    required this.transformationController,
    required this.pages,
    required this.screenWidth,
    required this.screenHeight,
  });

  final TransformationController transformationController;
  final List<EditorPage> pages;
  final double screenWidth;
  final double screenHeight;

  static double getScrollbarPosition(
    TransformationController controller,
    List<EditorPage> pages,
    double screenWidth,
    double screenHeight,
  ) {
    double totalHeight = Editor.gapBetweenPages * 2;
    for (final page in pages) {
      final pageWidthFitted = math.min(page.size.width, screenWidth);
      final pageHeight = page.size.height * (pageWidthFitted / page.size.width);
      totalHeight += pageHeight + Editor.gapBetweenPages;
    }
    if (totalHeight <= screenHeight) return 0;

    final translation = controller.value.getTranslation();
    final currentScrollY = -translation.y;
    final maxScrollY = totalHeight - screenHeight;
    final scrollRatio = (currentScrollY / maxScrollY).clamp(0.0, 1.0);

    final scrollbarHeight = _getScrollbarHeightStatic(
      totalHeight,
      screenHeight,
    );
    final availableHeight = screenHeight - scrollbarHeight;

    return scrollRatio * availableHeight;
  }

  static double _getScrollbarHeightStatic(
    double totalHeight,
    double screenHeight,
  ) {
    if (totalHeight <= screenHeight) return screenHeight;

    final viewportRatio = screenHeight / totalHeight;
    final scrollbarHeight = screenHeight * viewportRatio;
    return math.max(scrollbarHeight, 20.0);
  }

  @override
  State<CanvasScrollbar> createState() => _CanvasScrollbarState();
}

class _CanvasScrollbarState extends State<CanvasScrollbar> {
  bool _isDragging = false;
  double? _dragStartPosition;

  @override
  void initState() {
    super.initState();
    widget.transformationController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    widget.transformationController.removeListener(_onTransformChanged);
    super.dispose();
  }

  void _onTransformChanged() {
    if (!_isDragging && mounted) {
      setState(() {});
    }
  }

  double _getTotalHeight() {
    double total = Editor.gapBetweenPages * 2;
    for (final page in widget.pages) {
      final pageWidthFitted = math.min(page.size.width, widget.screenWidth);
      final pageHeight = page.size.height * (pageWidthFitted / page.size.width);
      total += pageHeight + Editor.gapBetweenPages;
    }
    return total;
  }

  double _getCurrentScrollY() {
    final translation = widget.transformationController.value.getTranslation();
    return -translation.y;
  }

  double _getScrollbarPosition() {
    final totalHeight = _getTotalHeight();
    if (totalHeight <= widget.screenHeight) return 0;

    final currentScrollY = _getCurrentScrollY();
    final maxScrollY = totalHeight - widget.screenHeight;
    final scrollRatio = (currentScrollY / maxScrollY).clamp(0.0, 1.0);

    final scrollbarHeight = _getScrollbarHeight();
    final availableHeight = widget.screenHeight - scrollbarHeight;

    return scrollRatio * availableHeight;
  }

  double _getScrollbarHeight() {
    final totalHeight = _getTotalHeight();
    if (totalHeight <= widget.screenHeight) return widget.screenHeight;

    final viewportRatio = widget.screenHeight / totalHeight;
    final scrollbarHeight = widget.screenHeight * viewportRatio;
    return math.max(scrollbarHeight, 20.0);
  }

  void _onScrollbarDragStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
      _dragStartPosition = details.localPosition.dy;
    });
  }

  void _onScrollbarDragUpdate(DragUpdateDetails details) {
    if (_dragStartPosition == null) return;

    final scrollbarHeight = _getScrollbarHeight();
    final availableHeight = widget.screenHeight - scrollbarHeight;
    final delta = details.localPosition.dy - _dragStartPosition!;

    final totalHeight = _getTotalHeight();
    final maxScrollY = totalHeight - widget.screenHeight;

    final currentPosition = _getScrollbarPosition();
    final newPosition = (currentPosition + delta).clamp(0.0, availableHeight);
    final scrollRatio = newPosition / availableHeight;

    final newScrollY = scrollRatio * maxScrollY;
    final topOfPage = -newScrollY;

    widget.transformationController.value = Matrix4.translationValues(
      0,
      topOfPage + 50,
      0,
    );

    _dragStartPosition = details.localPosition.dy;
  }

  void _onScrollbarDragEnd(DragEndDetails details) {
    setState(() {
      _isDragging = false;
      _dragStartPosition = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalHeight = _getTotalHeight();
    if (totalHeight <= widget.screenHeight) {
      return const SizedBox.shrink();
    }

    final scrollbarHeight = _getScrollbarHeight();
    _getScrollbarPosition();
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onVerticalDragStart: _onScrollbarDragStart,
      onVerticalDragUpdate: _onScrollbarDragUpdate,
      onVerticalDragEnd: _onScrollbarDragEnd,
      child: Container(
        width: 8,
        height: scrollbarHeight,
        decoration: BoxDecoration(
          color: colorScheme.onSurface.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(4),
        ),
        child: _isDragging
            ? Container(
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
              )
            : null,
      ),
    );
  }
}
