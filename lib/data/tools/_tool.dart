// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:stow_codecs/stow_codecs.dart';

abstract class Tool {
  @protected
  @visibleForTesting
  const Tool();

  ToolId get toolId;

  static const Tool textEditing = _TextEditingTool();
}

class _TextEditingTool extends Tool {
  const _TextEditingTool();

  @override
  ToolId get toolId => .textEditing;
}

enum ToolId {
  highlighter('Highlighter'),
  fountainPen('fountainPen'),
  ballpointPen('ballpointPen'),
  calligraphyPen('calligraphyPen'),
  shapePen('ShapePen'),
  advancedPen('advancedPen'),
  experimentalPen('experimentalPen'),
  shapeTool('ShapeTool'),
  eraser('Eraser'),
  select('Select'),
  textEditing('TextEditingTool'),
  laserPointer('LaserPointer'),

  /// Procedural-noise pencil (geometry like Advanced Pen; separate presets).
  advancedPencil('advancedPencil');

  final String id;
  const ToolId(this.id);

  static const codec = EnumCodec(values);

  static final prefCodec = _ToolIdPrefCodec();

  static final _log = Logger('ToolId');

  static ToolId parsePenType(String? penType, {required ToolId fallback}) {
    if (penType == null) {
      return fallback;
    }
    if (penType == 'Pen') {
      return .ballpointPen;
    }

    // Legacy pencil tool removed; treat as ballpoint.
    if (penType == 'Pencil' || penType == 'pencilPen') {
      return .ballpointPen;
    }

    // Legacy V-Space / H-Space / InsertPen tools removed.
    if (penType == 'InsertPen' ||
        penType == 'VerticalSpacePen' ||
        penType == 'HorizontalSpacePen') {
      return .ballpointPen;
    }
    // Legacy experimental pen maps to Advanced.
    if (penType == ToolId.experimentalPen.id) {
      return .advancedPen;
    }
    for (final toolId in ToolId.values) {
      if (penType == toolId.id) {
        return toolId;
      }
    }
    if (kDebugMode) {
      throw ArgumentError.value(
        penType,
        'penType',
        'Unknown pen type: `$penType`.',
      );
    }
    _log.warning(
      'Unknown pen type: `$penType`, using fallback `${fallback.id}`.',
    );
    return fallback;
  }
}

class _ToolIdPrefCodec extends AbstractCodec<ToolId, Object?> {
  const _ToolIdPrefCodec();

  @override
  Object? encode(ToolId input) => input.id;

  @override
  ToolId decode(Object? input) {
    if (input is String) {
      return ToolId.parsePenType(input, fallback: ToolId.ballpointPen);
    }
    // Legacy int indices from before V/H-space removal (and pencil).
    // Order matches ToolId.values when verticalSpacePen=5, horizontalSpacePen=6.
    const legacyByIndex = <ToolId>[
      ToolId.highlighter, // 0
      ToolId.fountainPen, // 1
      ToolId.ballpointPen, // 2
      ToolId.calligraphyPen, // 3
      ToolId.shapePen, // 4
      ToolId.ballpointPen, // 5 was verticalSpacePen
      ToolId.ballpointPen, // 6 was horizontalSpacePen
      ToolId.advancedPen, // 7
      ToolId.advancedPen, // 8 experimental → advanced
      ToolId.shapeTool, // 9
      ToolId.eraser, // 10
      ToolId.select, // 11
      ToolId.textEditing, // 12
      ToolId.laserPointer, // 13
      ToolId.advancedPencil, // 14
    ];
    final i = input is int
        ? input
        : (input is num ? input.toInt() : -1);
    if (i >= 0 && i < legacyByIndex.length) return legacyByIndex[i];
    return ToolId.ballpointPen;
  }
}
