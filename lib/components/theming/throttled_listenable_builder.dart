// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:saber/services/display_ink_feel.dart';

/// [ListenableBuilder] that coalesces rapid [listenable] notifications while
/// the viewport is busy, so chrome (zoom %, scrollbars, page index) does not
/// steal frame time from pan/zoom at ~60 Hz.
class ThrottledListenableBuilder extends StatefulWidget {
  const ThrottledListenableBuilder({
    super.key,
    required this.listenable,
    required this.builder,
    this.child,
    this.forceImmediate,
  });

  final Listenable listenable;
  final TransitionBuilder builder;
  final Widget? child;

  /// When true, rebuild on every notification (e.g. while chrome is hidden).
  final ValueGetter<bool>? forceImmediate;

  @override
  State<ThrottledListenableBuilder> createState() =>
      _ThrottledListenableBuilderState();
}

class _ThrottledListenableBuilderState extends State<ThrottledListenableBuilder> {
  var _scheduled = false;
  Duration _lastBuildStamp = Duration.zero;
  Timer? _coalesceTimer;

  /// Safe off-frame; [SchedulerBinding.currentFrameTimeStamp] asserts that a
  /// frame is in progress and crashes from [Timer]/[Future.delayed] callbacks.
  Duration _now() => SchedulerBinding.instance.currentSystemFrameTimeStamp;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_onNotify);
  }

  @override
  void didUpdateWidget(covariant ThrottledListenableBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_onNotify);
      widget.listenable.addListener(_onNotify);
    }
  }

  @override
  void dispose() {
    _coalesceTimer?.cancel();
    widget.listenable.removeListener(_onNotify);
    super.dispose();
  }

  void _onNotify() {
    if (!mounted) return;
    if (widget.forceImmediate?.call() == true) {
      setState(() {});
      return;
    }

    final now = _now();
    final minGap = DisplayInkFeel.instance.chromeThrottleInterval;
    if (now - _lastBuildStamp >= minGap) {
      _lastBuildStamp = now;
      setState(() {});
      return;
    }
    if (_scheduled) return;
    _scheduled = true;
    var wait = minGap - (now - _lastBuildStamp);
    if (wait < Duration.zero) wait = Duration.zero;
    _coalesceTimer?.cancel();
    _coalesceTimer = Timer(wait, () {
      _scheduled = false;
      if (!mounted) return;
      _lastBuildStamp = _now();
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, widget.child);
  }
}
