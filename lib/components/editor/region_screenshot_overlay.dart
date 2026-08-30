// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:saber/i18n/strings.g.dart';

/// Full-area overlay that lets the user drag a rectangular region to capture.
class RegionScreenshotOverlay extends StatefulWidget {
  const RegionScreenshotOverlay({
    super.key,
    required this.onCancel,
    required this.onSelected,
  });

  final VoidCallback onCancel;
  final ValueChanged<Rect> onSelected;

  @override
  State<RegionScreenshotOverlay> createState() =>
      _RegionScreenshotOverlayState();
}

class _RegionScreenshotOverlayState extends State<RegionScreenshotOverlay> {
  Offset? _start;
  Offset? _current;

  static const double _minEdge = 8;

  Rect? get _selection {
    final a = _start;
    final b = _current;
    if (a == null || b == null) return null;
    return Rect.fromPoints(a, b);
  }

  void _finish() {
    final rect = _selection?.normalize();
    if (rect == null ||
        rect.width < _minEdge ||
        rect.height < _minEdge) {
      setState(() {
        _start = null;
        _current = null;
      });
      return;
    }
    widget.onSelected(rect);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selection = _selection?.normalize();

    return Stack(
      fit: StackFit.expand,
      children: [
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            setState(() {
              _start = event.localPosition;
              _current = event.localPosition;
            });
          },
          onPointerMove: (event) {
            if (_start == null) return;
            setState(() => _current = event.localPosition);
          },
          onPointerUp: (_) => _finish(),
          onPointerCancel: (_) {
            setState(() {
              _start = null;
              _current = null;
            });
          },
          child: CustomPaint(
            painter: _RegionScreenshotPainter(
              selection: selection,
              dimColor: Colors.black.withValues(alpha: 0.45),
              borderColor: colorScheme.primary,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: SafeArea(
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(10),
              color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.95),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.crop_free,
                      size: 18,
                      color: colorScheme.onSurface,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.editor.toolbar.regionScreenshotHint,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: widget.onCancel,
                      child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

extension on Rect {
  Rect normalize() => Rect.fromLTRB(
        left < right ? left : right,
        top < bottom ? top : bottom,
        left < right ? right : left,
        top < bottom ? bottom : top,
      );
}

class _RegionScreenshotPainter extends CustomPainter {
  const _RegionScreenshotPainter({
    required this.selection,
    required this.dimColor,
    required this.borderColor,
  });

  final Rect? selection;
  final Color dimColor;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    if (selection == null || selection!.isEmpty) {
      canvas.drawRect(full, Paint()..color = dimColor);
      return;
    }

    final hole = selection!;
    final dimPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(full)
      ..addRect(hole);
    canvas.drawPath(dimPath, Paint()..color = dimColor);

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = borderColor;
    canvas.drawRect(hole, border);

    // Corner accents for clearer region feedback.
    final accent = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.square
      ..color = borderColor;
    const len = 14.0;
    void corner(Offset o, double dx, double dy) {
      canvas.drawLine(o, o.translate(dx * len, 0), accent);
      canvas.drawLine(o, o.translate(0, dy * len), accent);
    }

    corner(hole.topLeft, 1, 1);
    corner(hole.topRight, -1, 1);
    corner(hole.bottomLeft, 1, -1);
    corner(hole.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(covariant _RegionScreenshotPainter oldDelegate) {
    return oldDelegate.selection != selection ||
        oldDelegate.dimColor != dimColor ||
        oldDelegate.borderColor != borderColor;
  }
}
