// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart' hide TransformationController;

class CanvasZoomIndicator extends StatelessWidget {
  const CanvasZoomIndicator({
    super.key,
    required this.scale,
    required this.resetZoom,
  });

  final double scale;
  final VoidCallback? resetZoom;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return InkWell(
      onTap: resetZoom,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.5),
          borderRadius: .circular(15),
        ),
        padding: const .all(5),
        child: Text(
          '${scale.toStringAsFixed(1)}x',
          style: TextStyle(color: colorScheme.onSurface),
        ),
      ),
    );
  }
}
