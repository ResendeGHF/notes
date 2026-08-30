// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';

/// Shows a Samsung Notes–style color picker as a floating modal **without**
/// dimming the canvas. Anchors near [context]'s render box when possible.
Future<Color?> showNotesColorPicker(
  BuildContext context, {
  required Color initialColor,
  bool recordRecent = true,
}) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    final result = await showGeneralDialog<Color>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss color picker',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return FadeTransition(
          opacity: animation,
          child: _NotesColorPickerHost(
            initialColor: initialColor,
            anchorRect: null,
          ),
        );
      },
    );
    if (result != null && recordRecent) _recordRecentColor(result);
    return result;
  }

  final box = context.findRenderObject() as RenderBox?;
  final overlayBox = overlay.context.findRenderObject() as RenderBox?;
  Rect? anchorRect;
  if (box != null && box.hasSize && overlayBox != null && overlayBox.hasSize) {
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    anchorRect = topLeft & box.size;
  }

  final completer = Completer<Color?>();
  late OverlayEntry entry;

  void finish(Color? color) {
    if (!completer.isCompleted) completer.complete(color);
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (ctx) {
      return _NotesColorPickerHost(
        initialColor: initialColor,
        anchorRect: anchorRect,
        onDismiss: () => finish(null),
        onDone: (c) => finish(c),
      );
    },
  );
  overlay.insert(entry);

  final result = await completer.future;
  if (result != null && recordRecent) _recordRecentColor(result);
  return result;
}

void _recordRecentColor(Color color) {
  final newColorString = color.toARGB32().toString();
  if (stows.pinnedColors.value.contains(newColorString)) return;

  if (stows.recentColorsChronological.value.length !=
      stows.recentColorsPositioned.value.length) {
    stows.recentColorsChronological.value = List.of(
      stows.recentColorsPositioned.value,
    );
  }

  if (stows.recentColorsPositioned.value.contains(newColorString)) {
    stows.recentColorsChronological.value.remove(newColorString);
    stows.recentColorsChronological.value.add(newColorString);
    stows.recentColorsChronological.notifyListeners();
    return;
  }

  if (stows.recentColorsPositioned.value.length >=
      stows.recentColorsLength.value) {
    final removedColorString = stows.recentColorsChronological.value.removeAt(
      0,
    );
    stows.recentColorsChronological.value.add(newColorString);
    final removedColorPosition = stows.recentColorsPositioned.value.indexOf(
      removedColorString,
    );
    if (removedColorPosition >= 0) {
      stows.recentColorsPositioned.value[removedColorPosition] = newColorString;
    }
  } else {
    stows.recentColorsChronological.value.add(newColorString);
    stows.recentColorsPositioned.value.insert(0, newColorString);
  }
  stows.recentColorsChronological.notifyListeners();
  stows.recentColorsPositioned.notifyListeners();
}

class _ScreenCapture {
  const _ScreenCapture({
    required this.image,
    required this.pixels,
    required this.globalRect,
  });

  final ui.Image image;
  final ByteData pixels;
  final Rect globalRect;

  void dispose() => image.dispose();
}

/// Editor registers its canvas [RepaintBoundary] key so the eyedropper captures
/// ink/PDF pixels instead of scanning (and hanging on) huge unrelated layers.
class NotesEyedropperTarget {
  NotesEyedropperTarget._();

  static GlobalKey? canvasRepaintKey;
}

Future<_ScreenCapture?> _captureBoundary(
  RenderRepaintBoundary target, {
  required double pixelRatio,
  Duration timeout = const Duration(seconds: 6),
}) async {
  if (!target.hasSize || target.debugNeedsPaint) {
    await SchedulerBinding.instance.endOfFrame;
  }
  if (!target.hasSize) return null;
  try {
    final image = await target
        .toImage(pixelRatio: pixelRatio)
        .timeout(timeout);
    final bytes = await image
        .toByteData(format: ui.ImageByteFormat.rawRgba)
        .timeout(const Duration(seconds: 2));
    if (bytes == null) {
      image.dispose();
      return null;
    }
    final topLeft = target.localToGlobal(Offset.zero);
    return _ScreenCapture(
      image: image,
      pixels: bytes,
      globalRect: topLeft & target.size,
    );
  } catch (_) {
    return null;
  }
}

/// Capture the editor canvas only. Avoids walking the full render tree and
/// calling [toImage] on giant layers (that is what froze the old eyedropper).
Future<_ScreenCapture?> _captureForEyedropper() async {
  final key = NotesEyedropperTarget.canvasRepaintKey;
  final object = key?.currentContext?.findRenderObject();
  if (object is RenderRepaintBoundary) {
    // Same boundary region-screenshot uses; lower DPR keeps eyedrop snappy.
    final capture = await _captureBoundary(object, pixelRatio: 0.45);
    if (capture != null) return capture;
    // One retry after a frame (mesh/PDF may still be painting).
    await SchedulerBinding.instance.endOfFrame;
    return _captureBoundary(object, pixelRatio: 0.35);
  }

  // Outside the editor: only try modest-sized boundaries.
  final views = RendererBinding.instance.renderViews;
  if (views.isEmpty) return null;
  final root = views.first.child;
  if (root == null) return null;

  final candidates = <RenderRepaintBoundary>[];
  void visit(RenderObject object) {
    if (object is RenderRepaintBoundary && object.hasSize) {
      final area = object.size.width * object.size.height;
      if (area >= 20_000 && area <= 400_000) {
        candidates.add(object);
      }
    }
    object.visitChildren(visit);
  }

  visit(root);
  candidates.sort((a, b) {
    final aa = a.size.width * a.size.height;
    final bb = b.size.width * b.size.height;
    return bb.compareTo(aa);
  });
  for (final target in candidates.take(2)) {
    final capture = await _captureBoundary(
      target,
      pixelRatio: 0.4,
      timeout: const Duration(milliseconds: 900),
    );
    if (capture != null) return capture;
  }
  return null;
}

Color? _sampleCapture(_ScreenCapture capture, Offset globalPosition) {
  final rect = capture.globalRect;
  if (rect.width <= 0 || rect.height <= 0) return null;
  if (!rect.contains(globalPosition)) return null;
  final local = globalPosition - rect.topLeft;
  final x = (local.dx / rect.width * capture.image.width)
      .floor()
      .clamp(0, capture.image.width - 1);
  final y = (local.dy / rect.height * capture.image.height)
      .floor()
      .clamp(0, capture.image.height - 1);
  final i = (y * capture.image.width + x) * 4;
  if (i + 2 >= capture.pixels.lengthInBytes) return null;
  return Color.fromARGB(
    255,
    capture.pixels.getUint8(i),
    capture.pixels.getUint8(i + 1),
    capture.pixels.getUint8(i + 2),
  );
}

class NotesColorPickerModal extends StatefulWidget {
  const NotesColorPickerModal({
    super.key,
    required this.initialColor,
    this.onCancel,
    this.onDone,
    this.onEyedropper,
  });

  final Color initialColor;
  final VoidCallback? onCancel;
  final ValueChanged<Color>? onDone;
  final VoidCallback? onEyedropper;

  @override
  State<NotesColorPickerModal> createState() => _NotesColorPickerModalState();
}

enum _PickerTab { swatches, spectrum }

class _NotesColorPickerModalState extends State<NotesColorPickerModal> {
  late Color _color;
  late HSVColor _hsv;
  _PickerTab _tab = _PickerTab.swatches;

  late final TextEditingController _hexController;
  late final TextEditingController _rController;
  late final TextEditingController _gController;
  late final TextEditingController _bController;

  static const int _swatchCols = 10;
  static const int _swatchRows = 8;

  @override
  void initState() {
    super.initState();
    _color = widget.initialColor.withValues(alpha: 1);
    _hsv = HSVColor.fromColor(_color);
    _hexController = TextEditingController(text: _hexOf(_color));
    _rController = TextEditingController(text: '${_channel(_color.r)}');
    _gController = TextEditingController(text: '${_channel(_color.g)}');
    _bController = TextEditingController(text: '${_channel(_color.b)}');
  }

  @override
  void dispose() {
    _hexController.dispose();
    _rController.dispose();
    _gController.dispose();
    _bController.dispose();
    super.dispose();
  }

  static int _channel(double c) => (c * 255).round().clamp(0, 255);

  static String _hexOf(Color c) =>
      '${_channel(c.r).toRadixString(16).padLeft(2, '0')}'
              '${_channel(c.g).toRadixString(16).padLeft(2, '0')}'
              '${_channel(c.b).toRadixString(16).padLeft(2, '0')}'
          .toUpperCase();

  static Color? _parseHex(String raw) {
    var hex = raw.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.length != 6) return null;
    final v = int.tryParse(hex, radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }

  void _setColor(Color color, {bool syncFields = true}) {
    final opaque = color.withValues(alpha: 1);
    setState(() {
      _color = opaque;
      _hsv = HSVColor.fromColor(opaque);
      if (syncFields) {
        _hexController.text = _hexOf(opaque);
        _rController.text = '${_channel(opaque.r)}';
        _gController.text = '${_channel(opaque.g)}';
        _bController.text = '${_channel(opaque.b)}';
      }
    });
  }

  void _setHsv(HSVColor hsv) => _setColor(hsv.toColor());

  void _onHexChanged(String value) {
    final c = _parseHex(value);
    if (c != null) _setColor(c, syncFields: false);
  }

  void _onRgbFieldChanged() {
    final r = int.tryParse(_rController.text);
    final g = int.tryParse(_gController.text);
    final b = int.tryParse(_bController.text);
    if (r == null || g == null || b == null) return;
    if (r < 0 || r > 255 || g < 0 || g > 255 || b < 0 || b > 255) return;
    _setColor(Color.fromARGB(255, r, g, b), syncFields: false);
    _hexController.text = _hexOf(_color);
  }

  /// Column 0–1 = grayscale; remaining columns = hues (Samsung-style grid).
  Color _swatchAt(int row, int col) {
    final t = _swatchRows <= 1 ? 0.0 : row / (_swatchRows - 1);
    if (col <= 1) {
      // Two gray columns with a slight offset so they aren't identical.
      final bias = col == 0 ? 0.0 : 0.04;
      final v = (1.0 - t - bias).clamp(0.0, 1.0);
      final c = (v * 255).round();
      return Color.fromARGB(255, c, c, c);
    }
    final hue = ((col - 2) / (_swatchCols - 2)) * 360.0;
    final value = (1.0 - t * 0.72).clamp(0.22, 1.0);
    final sat = (0.55 + t * 0.45).clamp(0.45, 1.0);
    return HSVColor.fromAHSV(1, hue, sat, value).toColor();
  }

  List<Color> get _recentColors {
    final length = stows.recentColorsLength.value.clamp(1, 12);
    final out = <Color>[];
    for (final s in stows.pinnedColors.value) {
      final v = int.tryParse(s);
      if (v != null) out.add(Color(v));
    }
    for (final s in stows.recentColorsPositioned.value) {
      final v = int.tryParse(s);
      if (v == null) continue;
      final c = Color(v);
      if (out.any((e) => e.toARGB32() == c.toARGB32())) continue;
      out.add(c);
    }
    return out.take(length).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF2C2C2E) : theme.colorScheme.surface;
    final onSurface = isDark ? Colors.white : theme.colorScheme.onSurface;
    final muted = isDark
        ? Colors.white.withValues(alpha: 0.55)
        : theme.colorScheme.onSurfaceVariant;

    return Material(
      color: surface,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TabBar(
                    tab: _tab,
                    onChanged: (t) => setState(() => _tab = t),
                    isDark: isDark,
                  ),
                  const SizedBox(height: 14),
                  if (_tab == _PickerTab.swatches)
                    _SwatchGrid(
                      cols: _swatchCols,
                      rows: _swatchRows,
                      colorAt: _swatchAt,
                      selected: _color,
                      onSelect: _setColor,
                    )
                  else
                    _SpectrumPane(hsv: _hsv, onChanged: _setHsv),
                  const SizedBox(height: 14),
                  _ValueRow(
                    color: _color,
                    hexController: _hexController,
                    rController: _rController,
                    gController: _gController,
                    bController: _bController,
                    muted: muted,
                    onSurface: onSurface,
                    onHexChanged: _onHexChanged,
                    onRgbChanged: _onRgbFieldChanged,
                  ),
                  const SizedBox(height: 12),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: muted.withValues(alpha: 0.25),
                  ),
                  const SizedBox(height: 12),
                  _RecentRow(
                    colors: _recentColors,
                    selected: _color,
                    muted: muted,
                    onSelect: _setColor,
                    onEyedropper: widget.onEyedropper ??
                        () => setState(() => _tab = _PickerTab.spectrum),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              thickness: 1,
              color: muted.withValues(alpha: 0.25),
            ),
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        if (widget.onCancel != null) {
                          widget.onCancel!();
                        } else {
                          Navigator.of(context).maybePop();
                        }
                      },
                      child: Text(
                        t.common.cancel,
                        style: TextStyle(
                          color: onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: double.infinity,
                    color: muted.withValues(alpha: 0.25),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        if (widget.onDone != null) {
                          widget.onDone!(_color);
                        } else {
                          Navigator.of(context).maybePop(_color);
                        }
                      },
                      child: Text(
                        t.common.done,
                        style: TextStyle(
                          color: onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Positions [NotesColorPickerModal] near [anchorRect] with no canvas dimming.
class _NotesColorPickerHost extends StatefulWidget {
  const _NotesColorPickerHost({
    required this.initialColor,
    required this.anchorRect,
    this.onDismiss,
    this.onDone,
  });

  final Color initialColor;
  final Rect? anchorRect;
  final VoidCallback? onDismiss;
  final ValueChanged<Color>? onDone;

  @override
  State<_NotesColorPickerHost> createState() => _NotesColorPickerHostState();
}

class _NotesColorPickerHostState extends State<_NotesColorPickerHost> {
  late Color _color = widget.initialColor;
  var _eyedropping = false;
  var _capturing = false;
  var _eyedropGen = 0;
  _ScreenCapture? _capture;

  @override
  void dispose() {
    _capture?.dispose();
    super.dispose();
  }

  void _cancel() {
    if (widget.onDismiss != null) {
      widget.onDismiss!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _done(Color c) {
    if (widget.onDone != null) {
      widget.onDone!(c);
    } else {
      Navigator.of(context).maybePop(c);
    }
  }

  void _abortCapture() {
    _eyedropGen++;
    setState(() => _capturing = false);
  }

  Future<void> _startEyedropper() async {
    if (_capturing || _eyedropping) return;
    final gen = ++_eyedropGen;
    // Hide the panel first so the capture is of the canvas, not the modal.
    setState(() => _capturing = true);
    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(Duration.zero);
    await SchedulerBinding.instance.endOfFrame;

    if (!mounted || gen != _eyedropGen) return;
    final capture = await _captureForEyedropper();
    if (!mounted || gen != _eyedropGen) {
      capture?.dispose();
      return;
    }
    if (capture == null) {
      setState(() => _capturing = false);
      return;
    }
    _capture?.dispose();
    setState(() {
      _capture = capture;
      _capturing = false;
      _eyedropping = true;
    });
  }

  void _finishEyedropper(Color? color) {
    _capture?.dispose();
    _capture = null;
    setState(() {
      _eyedropping = false;
      _capturing = false;
      if (color != null) _color = color;
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    const panelWidth = 340.0;
    const estimatedHeight = 520.0;

    double left;
    double top;
    if (widget.anchorRect != null) {
      left = (widget.anchorRect!.center.dx - panelWidth / 2).clamp(
        12.0,
        media.size.width - panelWidth - 12.0,
      );
      top = widget.anchorRect!.top - estimatedHeight - 8;
      if (top < media.padding.top + 8) {
        top = widget.anchorRect!.bottom + 8;
      }
      top = top.clamp(
        media.padding.top + 8,
        media.size.height - estimatedHeight - media.padding.bottom - 8,
      );
    } else {
      left = (media.size.width - panelWidth) / 2;
      top = media.size.height - estimatedHeight - media.padding.bottom - 24;
    }

    if (_eyedropping && _capture != null) {
      return _ScreenEyedropper(
        capture: _capture!,
        onCancel: () => _finishEyedropper(null),
        onPick: (c) => _finishEyedropper(c),
      );
    }

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _capturing ? null : _cancel,
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          if (!_capturing)
            Positioned(
              left: left,
              top: top,
              width: panelWidth,
              child: NotesColorPickerModal(
                initialColor: _color,
                onCancel: _cancel,
                onDone: _done,
                onEyedropper: _startEyedropper,
              ),
            ),
          if (_capturing)
            Positioned.fill(
              child: Material(
                color: Colors.black26,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Capturing canvas…',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.95),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _abortCapture,
                        child: Text(t.common.cancel),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ScreenEyedropper extends StatefulWidget {
  const _ScreenEyedropper({
    required this.capture,
    required this.onCancel,
    required this.onPick,
  });

  final _ScreenCapture capture;
  final VoidCallback onCancel;
  final ValueChanged<Color> onPick;

  @override
  State<_ScreenEyedropper> createState() => _ScreenEyedropperState();
}

class _ScreenEyedropperState extends State<_ScreenEyedropper> {
  Offset? _pointer;
  Color _preview = Colors.white;

  void _update(Offset global) {
    final c = _sampleCapture(widget.capture, global);
    if (c == null) return;
    setState(() {
      _pointer = global;
      _preview = c;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final onSurface = isDark ? Colors.white : Colors.black87;
    final size = MediaQuery.sizeOf(context);
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => _update(e.position),
              onPointerMove: (e) => _update(e.position),
              onPointerUp: (e) {
                _update(e.position);
                widget.onPick(_preview);
              },
              child: const ColoredBox(color: Color(0x22000000)),
            ),
          ),
          if (_pointer != null)
            Positioned(
              left: (_pointer!.dx - 36).clamp(8.0, size.width - 80),
              top: (_pointer!.dy - 96).clamp(8.0, size.height - 80),
              child: IgnorePointer(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _preview,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: MediaQuery.paddingOf(context).bottom + 20,
            child: Center(
              child: Material(
                color: surface,
                elevation: 6,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.colorize_rounded, size: 18, color: onSurface),
                      const SizedBox(width: 8),
                      Text(
                        'Drag to sample · release to pick',
                        style: TextStyle(
                          color: onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: widget.onCancel,
                        child: Text(t.common.cancel),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.tab,
    required this.onChanged,
    required this.isDark,
  });

  final _PickerTab tab;
  final ValueChanged<_PickerTab> onChanged;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE8E8ED),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabChip(
              label: 'Swatches',
              selected: tab == _PickerTab.swatches,
              isDark: isDark,
              onTap: () => onChanged(_PickerTab.swatches),
            ),
          ),
          Expanded(
            child: _TabChip(
              label: 'Spectrum',
              selected: tab == _PickerTab.spectrum,
              isDark: isDark,
              onTap: () => onChanged(_PickerTab.spectrum),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? (isDark ? const Color(0xFF3A3A3C) : Colors.white)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected
                  ? (isDark ? Colors.white : Colors.black87)
                  : (isDark
                        ? Colors.white.withValues(alpha: 0.55)
                        : Colors.black54),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwatchGrid extends StatelessWidget {
  const _SwatchGrid({
    required this.cols,
    required this.rows,
    required this.colorAt,
    required this.selected,
    required this.onSelect,
  });

  final int cols;
  final int rows;
  final Color Function(int row, int col) colorAt;
  final Color selected;
  final ValueChanged<Color> onSelect;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: cols / rows,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cellW = constraints.maxWidth / cols;
          final cellH = constraints.maxHeight / rows;
          var bestRow = 0;
          var bestCol = 0;
          var bestDist = double.infinity;
          for (var row = 0; row < rows; row++) {
            for (var col = 0; col < cols; col++) {
              final c = colorAt(row, col);
              final d =
                  (c.r - selected.r).abs() +
                  (c.g - selected.g).abs() +
                  (c.b - selected.b).abs();
              if (d < bestDist) {
                bestDist = d;
                bestRow = row;
                bestCol = col;
              }
            }
          }
          return Stack(
            children: [
              for (var row = 0; row < rows; row++)
                for (var col = 0; col < cols; col++)
                  Positioned(
                    left: col * cellW,
                    top: row * cellH,
                    width: cellW,
                    height: cellH,
                    child: Material(
                      color: colorAt(row, col),
                      child: InkWell(
                        onTap: () => onSelect(colorAt(row, col)),
                      ),
                    ),
                  ),
              if (bestDist <= 0.12)
                Positioned(
                  left: bestCol * cellW + 1,
                  top: bestRow * cellH + 1,
                  width: cellW - 2,
                  height: cellH - 2,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2.5),
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SpectrumPane extends StatelessWidget {
  const _SpectrumPane({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1.15,
          child: _SvSquare(
            hue: hsv.hue,
            saturation: hsv.saturation,
            value: hsv.value,
            onChanged: (s, v) =>
                onChanged(HSVColor.fromAHSV(1, hsv.hue, s, v)),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 28,
          child: _HueBar(
            hue: hsv.hue,
            onChanged: (h) => onChanged(
              HSVColor.fromAHSV(1, h, hsv.saturation, hsv.value),
            ),
          ),
        ),
      ],
    );
  }
}

class _SvSquare extends StatelessWidget {
  const _SvSquare({
    required this.hue,
    required this.saturation,
    required this.value,
    required this.onChanged,
  });

  final double hue;
  final double saturation;
  final double value;
  final void Function(double sat, double val) onChanged;

  void _update(Offset local, Size size) {
    final s = (local.dx / size.width).clamp(0.0, 1.0);
    final v = 1.0 - (local.dy / size.height).clamp(0.0, 1.0);
    onChanged(s, v);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onPanDown: (d) => _update(d.localPosition, size),
          onPanUpdate: (d) => _update(d.localPosition, size),
          child: CustomPaint(
            painter: _SvSquarePainter(hue: hue),
            child: Stack(
              children: [
                Positioned(
                  left: saturation * size.width - 10,
                  top: (1 - value) * size.height - 10,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 3,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SvSquarePainter extends CustomPainter {
  _SvSquarePainter({required this.hue});

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final hueColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    final sat = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(size.width, 0),
        [Colors.white, hueColor],
      );
    canvas.drawRect(Offset.zero & size, sat);
    final val = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, size.height),
        [Colors.transparent, Colors.black],
      );
    canvas.drawRect(Offset.zero & size, val);
  }

  @override
  bool shouldRepaint(covariant _SvSquarePainter oldDelegate) =>
      oldDelegate.hue != hue;
}

class _HueBar extends StatelessWidget {
  const _HueBar({required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return GestureDetector(
          onPanDown: (d) =>
              onChanged((d.localPosition.dx / w).clamp(0.0, 1.0) * 360),
          onPanUpdate: (d) =>
              onChanged((d.localPosition.dx / w).clamp(0.0, 1.0) * 360),
          child: CustomPaint(
            painter: const _HueBarPainter(),
            child: Align(
              alignment: Alignment((hue / 180) - 1, 0),
              child: Container(
                width: 6,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HueBarPainter extends CustomPainter {
  const _HueBarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final colors = <Color>[
      for (var i = 0; i <= 6; i++)
        HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor(),
    ];
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(size.width, 0),
        colors,
      );
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(6),
    );
    canvas.drawRRect(r, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.color,
    required this.hexController,
    required this.rController,
    required this.gController,
    required this.bController,
    required this.muted,
    required this.onSurface,
    required this.onHexChanged,
    required this.onRgbChanged,
  });

  final Color color;
  final TextEditingController hexController;
  final TextEditingController rController;
  final TextEditingController gController;
  final TextEditingController bController;
  final Color muted;
  final Color onSurface;
  final ValueChanged<String> onHexChanged;
  final VoidCallback onRgbChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: muted.withValues(alpha: 0.35)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: _LabeledField(
                  label: 'Hex',
                  controller: hexController,
                  muted: muted,
                  onSurface: onSurface,
                  maxLength: 6,
                  onChanged: onHexChanged,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _LabeledField(
                  label: 'Red',
                  controller: rController,
                  muted: muted,
                  onSurface: onSurface,
                  maxLength: 3,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => onRgbChanged(),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _LabeledField(
                  label: 'Green',
                  controller: gController,
                  muted: muted,
                  onSurface: onSurface,
                  maxLength: 3,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => onRgbChanged(),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _LabeledField(
                  label: 'Blue',
                  controller: bController,
                  muted: muted,
                  onSurface: onSurface,
                  maxLength: 3,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => onRgbChanged(),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    required this.muted,
    required this.onSurface,
    required this.onChanged,
    this.maxLength,
    this.keyboardType,
    this.inputFormatters,
  });

  final String label;
  final TextEditingController controller;
  final Color muted;
  final Color onSurface;
  final ValueChanged<String> onChanged;
  final int? maxLength;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: muted, height: 1),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLength: maxLength,
          inputFormatters: inputFormatters,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: onSurface,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          ),
          decoration: const InputDecoration(
            isDense: true,
            counterText: '',
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({
    required this.colors,
    required this.selected,
    required this.muted,
    required this.onSelect,
    required this.onEyedropper,
  });

  final List<Color> colors;
  final Color selected;
  final Color muted;
  final ValueChanged<Color> onSelect;
  final VoidCallback onEyedropper;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final c in colors) ...[
          _RecentDot(
            color: c,
            selected: c.toARGB32() == selected.toARGB32(),
            onTap: () => onSelect(c),
          ),
          const SizedBox(width: 10),
        ],
        const Spacer(),
        Material(
          color: muted.withValues(alpha: 0.12),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onEyedropper,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(Icons.colorize_rounded, size: 18, color: muted),
            ),
          ),
        ),
      ],
    );
  }
}

class _RecentDot extends StatelessWidget {
  const _RecentDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: CircleBorder(
        side: BorderSide(
          color: selected ? Colors.white : Colors.white24,
          width: selected ? 2.5 : 1,
        ),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(width: 28, height: 28),
      ),
    );
  }
}
