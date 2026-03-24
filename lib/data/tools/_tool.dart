// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:saber/data/prefs.dart';
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
  verticalSpacePen('VerticalSpacePen'),
  horizontalSpacePen('HorizontalSpacePen'),
  advancedPen('advancedPen'),
  shapeTool('ShapeTool'),
  eraser('Eraser'),
  select('Select'),
  textEditing('TextEditingTool'),
  laserPointer('LaserPointer');

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

    if (penType == 'Pencil' || penType == 'pencilPen') {
      return .ballpointPen;
    }

    if (penType == 'InsertPen') {
      return .verticalSpacePen;
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
  Object? encode(ToolId input) => ToolId.codec.encode(input);

  @override
  ToolId decode(Object? input) {
    if (input == 'pencilPen' || input == 'Pencil') return ToolId.ballpointPen;
    final i = input is int
        ? input
        : (input is num ? input.toInt() : (input == null ? 0 : 0));
    return ToolId.codec.decode(i);
  }
}
