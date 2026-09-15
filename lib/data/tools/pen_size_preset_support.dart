// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/shape_tool.dart';

/// Stroke tools whose width can be driven by toolbar pen-size presets.
bool toolSupportsPenSizePresets(Tool t) {
  if (t is Highlighter) return true;
  if (t.toolId == ToolId.laserPointer) return true;
  if (t is ShapeTool) return true;
  if (t is Pen) {
    switch (t.toolId) {
      case ToolId.ballpointPen:
      case ToolId.calligraphyPen:
      case ToolId.fountainPen:
      case ToolId.advancedPen:
      case ToolId.advancedPencil:
        return true;
      default:
        return false;
    }
  }
  return false;
}
