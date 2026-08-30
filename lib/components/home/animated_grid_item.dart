// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

/// Minimal grid-cell motion: soft fade (± tiny scale). No slot sliding —
/// reflows jump to place so Recent feels calm when lists change.
class AnimatedGridItem extends StatefulWidget {
  const AnimatedGridItem({
    super.key,
    required this.child,
    required this.animateExit,
    this.animateEnter = false,
    this.onExitComplete,
  });

  final Widget child;
  final bool animateExit;
  final bool animateEnter;
  final VoidCallback? onExitComplete;

  @override
  State<AnimatedGridItem> createState() => _AnimatedGridItemState();
}

class _AnimatedGridItemState extends State<AnimatedGridItem>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 180);

  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  bool _animationsDisabled(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: _duration, vsync: this);
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _opacity = curve;
    _scale = Tween<double>(begin: 0.98, end: 1.0).animate(curve);

    if (widget.animateExit) {
      _controller.value = 1.0;
      WidgetsBinding.instance.addPostFrameCallback((_) => _runExit());
    } else if (widget.animateEnter) {
      _controller.value = 0.0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_animationsDisabled(context)) {
          _controller.value = 1.0;
          return;
        }
        _controller.forward();
      });
    } else {
      _controller.value = 1.0;
    }
  }

  void _runExit() {
    if (!mounted) return;
    if (_animationsDisabled(context)) {
      _controller.value = 0.0;
      widget.onExitComplete?.call();
      return;
    }
    _controller.reverse().then((_) {
      if (mounted) widget.onExitComplete?.call();
    });
  }

  @override
  void didUpdateWidget(AnimatedGridItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animateExit && !oldWidget.animateExit) {
      _runExit();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_animationsDisabled(context)) {
      return widget.child;
    }

    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        alignment: Alignment.center,
        child: widget.child,
      ),
    );
  }
}
