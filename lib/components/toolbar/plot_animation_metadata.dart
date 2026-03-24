// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:flutter/material.dart';

const String kPlotAnimationMetadataPrefix = 'saber_plot_meta_v1:';

enum PlotAnimationKind { plot2d, surface3d, scalar3d, vector3d, ode }

class PlotAnimationItemMetadata {
  final Map<String, String> expressions;
  final double tMin;
  final double tMax;
  final int durationMs;
  final int? colorArgb;

  const PlotAnimationItemMetadata({
    required this.expressions,
    required this.tMin,
    required this.tMax,
    required this.durationMs,
    this.colorArgb,
  });

  bool get hasAnimation => tMax > tMin && durationMs > 0;

  Map<String, dynamic> toJson() => {
    'expr': expressions,
    'tMin': tMin,
    'tMax': tMax,
    'durMs': durationMs,
    if (colorArgb != null) 'color': colorArgb,
  };

  factory PlotAnimationItemMetadata.fromJson(Map<String, dynamic> json) {
    final rawExpr = (json['expr'] as Map?) ?? <String, dynamic>{};
    return PlotAnimationItemMetadata(
      expressions: rawExpr.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
      tMin: (json['tMin'] as num?)?.toDouble() ?? 0,
      tMax: (json['tMax'] as num?)?.toDouble() ?? 0,
      durationMs: (json['durMs'] as num?)?.toInt() ?? 0,
      colorArgb: (json['color'] as num?)?.toInt(),
    );
  }
}

class PlotAnimationMetadata {
  final PlotAnimationKind kind;
  final List<PlotAnimationItemMetadata> items;
  final bool isComplex;

  const PlotAnimationMetadata({
    required this.kind,
    required this.items,
    this.isComplex = false,
  });

  bool get hasAnimation => items.any((item) => item.hasAnimation);

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'items': items.map((item) => item.toJson()).toList(),
    'isComplex': isComplex,
  };

  factory PlotAnimationMetadata.fromJson(Map<String, dynamic> json) {
    final kindName =
        (json['kind'] as String?) ?? PlotAnimationKind.surface3d.name;
    final kind = PlotAnimationKind.values.firstWhere(
      (value) => value.name == kindName,
      orElse: () => PlotAnimationKind.surface3d,
    );
    final rawItems = (json['items'] as List?) ?? const [];
    return PlotAnimationMetadata(
      kind: kind,
      items: rawItems
          .whereType<Map>()
          .map(
            (item) => PlotAnimationItemMetadata.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList(),
      isComplex: json['isComplex'] == true,
    );
  }

  String encodeForAssetInfo() =>
      '$kPlotAnimationMetadataPrefix${jsonEncode(toJson())}';

  static PlotAnimationMetadata? tryDecodeFromAssetInfo(String? fileInfo) {
    if (fileInfo == null || fileInfo.isEmpty) return null;
    if (!fileInfo.startsWith(kPlotAnimationMetadataPrefix)) return null;
    final jsonRaw = fileInfo.substring(kPlotAnimationMetadataPrefix.length);
    try {
      final decoded = jsonDecode(jsonRaw);
      if (decoded is! Map) return null;
      return PlotAnimationMetadata.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    } catch (_) {
      return null;
    }
  }
}

Color colorFromArgbOrDefault(int? argb, Color fallback) {
  if (argb == null) return fallback;
  return Color(argb);
}
