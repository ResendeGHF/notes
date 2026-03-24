// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

class AnimatedGridItem extends StatefulWidget {
  const AnimatedGridItem({
    super.key,
    required this.child,
    required this.animateEntrance,
    required this.animateExit,
    this.onExitComplete,
    this.onEntranceComplete,
  });

  final Widget child;
  final bool animateEntrance;
  final bool animateExit;
  final VoidCallback? onExitComplete;
  final VoidCallback? onEntranceComplete;

  @override
  State<AnimatedGridItem> createState() => _AnimatedGridItemState();
}

class _AnimatedGridItemState extends State<AnimatedGridItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _entranceAnimation;
  late Animation<double> _exitAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _entranceAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    _exitAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInCubic,
      ),
    );

    if (widget.animateEntrance) {
      _controller.forward().then((_) {
        widget.onEntranceComplete?.call();
      });
    } else if (widget.animateExit) {
      _controller.value = 1.0;
      _controller.reverse().then((_) {
        widget.onExitComplete?.call();
      });
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(AnimatedGridItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animateExit && !oldWidget.animateExit) {
      _controller.reverse().then((_) {
        widget.onExitComplete?.call();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.animateExit) {
      return AnimatedBuilder(
        animation: _exitAnimation,
        builder: (context, child) {
          return Opacity(
            opacity: _exitAnimation.value,
            child: child,
          );
        },
        child: widget.child,
      );
    }

    if (widget.animateEntrance) {
      return AnimatedBuilder(
        animation: _entranceAnimation,
        builder: (context, child) {
          return Opacity(
            opacity: _entranceAnimation.value,
            child: child,
          );
        },
        child: widget.child,
      );
    }

    return widget.child;
  }
}
