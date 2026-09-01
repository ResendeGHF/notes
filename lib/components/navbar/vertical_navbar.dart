// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/files/file_tree.dart';
import 'package:saber/components/navbar/home_shell_layout.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/services/background_operation_queue.dart';

class VerticalNavbar extends StatefulWidget {
  const VerticalNavbar({
    super.key,
    required this.destinations,
    this.selectedIndex = 0,
    this.onDestinationSelected,
  });

  /// Width when the file-tree rail is open.
  static const double expandedWidth = 320;

  /// Width when the rail is icons-only.
  static const double collapsedWidth = 72;

  /// Extra panel beside the icon rail when expanded.
  static const double panelWidth = expandedWidth - collapsedWidth;

  static const Duration expandDuration = Duration(milliseconds: 260);

  final List<NavigationRailDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int>? onDestinationSelected;

  @override
  State<VerticalNavbar> createState() => _VerticalNavbarState();
}

class _VerticalNavbarState extends State<VerticalNavbar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _expandController;
  late final Animation<double> _expand;

  /// Logical expanded flag used for body inset + chrome. Visual width follows
  /// [_expand] so the file tree keeps a stable 320px layout during the anim.
  var _expanded = true;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: VerticalNavbar.expandDuration,
      value: 1,
    );
    _expand = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    HomeShellLayout.verticalNavExpanded.value = true;
    HomeShellLayout.verticalNavExpandT.value = 1;
    _expandController.addListener(_publishExpandT);
  }

  void _publishExpandT() {
    HomeShellLayout.verticalNavExpandT.value = _expand.value;
  }

  @override
  void dispose() {
    _expandController.removeListener(_publishExpandT);
    _expandController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    final next = !_expanded;
    _expanded = next;
    if (next) {
      // Expand: reserve body space immediately, chrome grows into the gap.
      HomeShellLayout.verticalNavExpanded.value = true;
      _expandController.forward();
    } else {
      // Collapse: animate chrome first, then release body space once — so the
      // expensive home-grid relayout doesn't compete with the rail animation.
      _expandController.reverse().whenComplete(() {
        if (!mounted || _expanded) return;
        HomeShellLayout.verticalNavExpanded.value = false;
      });
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = colorScheme.surface;

    final rail = Theme(
      data: theme.copyWith(
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        hoverColor: Colors.transparent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _toggleExpanded,
                    style: ButtonStyle(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const WidgetStatePropertyAll(EdgeInsets.all(10)),
                      minimumSize:
                          const WidgetStatePropertyAll(Size.square(44)),
                      visualDensity: VisualDensity.compact,
                      overlayColor:
                          const WidgetStatePropertyAll(Colors.transparent),
                    ),
                    icon: AdaptiveIcon(
                      icon: _expanded ? Icons.menu_open : Icons.menu,
                      cupertinoIcon: _expanded
                          ? CupertinoIcons.sidebar_left
                          : CupertinoIcons.sidebar_right,
                    ),
                    tooltip:
                        _expanded ? 'Collapse sidebar' : 'Expand sidebar',
                  ),
                  FadeTransition(
                    opacity: _expand,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 8),
                        Text(
                          t.editor.navigation.title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (final entry in widget.destinations.asMap().entries)
            _DestinationRow(
              destination: entry.value,
              selected: entry.key == widget.selectedIndex,
              isDark: isDark,
              labelOpacity: _expand,
              onTap: () => widget.onDestinationSelected?.call(entry.key),
            ),
          Expanded(
            child: FadeTransition(
              opacity: _expand,
              child: TickerMode(
                enabled: _expanded || _expandController.isAnimating,
                child: IgnorePointer(
                  ignoring: !_expanded && !_expandController.isAnimating,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Divider(height: 1),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 8,
                        ),
                        child: Text(
                          'FILES',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            letterSpacing: 1.0,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Expanded(
                        child: RepaintBoundary(child: FileTree()),
                      ),
                      ValueListenableBuilder<BackgroundOperationUiState>(
                        valueListenable: BackgroundOperationQueue.uiState,
                        builder: (context, state, _) {
                          if (!state.isActive) {
                            return const SizedBox(height: 8);
                          }
                          return _TaskCard(state: state, showDetails: true);
                        },
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

    // Clip an always-320 layout down to the animated width. FileTree keeps
    // stable constraints for the whole animation (no per-frame relayout).
    return AnimatedBuilder(
      animation: _expand,
      builder: (context, child) {
        final width = VerticalNavbar.collapsedWidth +
            (VerticalNavbar.expandedWidth - VerticalNavbar.collapsedWidth) *
                _expand.value;
        return RepaintBoundary(
          child: Material(
            color: surfaceColor,
            elevation: 0,
            clipBehavior: Clip.hardEdge,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                bottomRight: Radius.circular(16),
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
              ),
              child: SizedBox(
                width: width,
                height: double.infinity,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: VerticalNavbar.expandedWidth,
                    maxWidth: VerticalNavbar.expandedWidth,
                    child: SizedBox(
                      width: VerticalNavbar.expandedWidth,
                      height: double.infinity,
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: rail,
    );
  }
}

class _DestinationRow extends StatelessWidget {
  const _DestinationRow({
    required this.destination,
    required this.selected,
    required this.isDark,
    required this.labelOpacity,
    required this.onTap,
  });

  final NavigationRailDestination destination;
  final bool selected;
  final bool isDark;
  final Animation<double> labelOpacity;
  final VoidCallback onTap;

  static const double _iconSlot = 48;
  /// Full-row highlight inside the expanded rail (320 - 24 side margins).
  static const double _expandedHighlight = 296;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;
    final icon =
        (selected ? destination.selectedIcon : null) ?? destination.icon;

    // Icon sits in the collapsed rail column (72) so its center matches the
    // accent square when clipped; label lives in the expanding panel.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: _iconSlot,
          child: AnimatedBuilder(
            animation: labelOpacity,
            builder: (context, child) {
              final t = labelOpacity.value.clamp(0.0, 1.0);
              final highlightWidth =
                  _iconSlot + (_expandedHighlight - _iconSlot) * t;
              // Keep the square centered on the icon; grow extra width to the
              // end (into the label) as the rail expands.
              final iconCenterX = VerticalNavbar.collapsedWidth / 2;
              final highlightLeft = iconCenterX - _iconSlot / 2;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  if (selected)
                    Positioned(
                      left: highlightLeft,
                      top: 0,
                      width: highlightWidth,
                      height: _iconSlot,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(100), // M3 Stadium shape
                        ),
                      ),
                    ),
                  child!,
                ],
              );
            },
            child: Row(
              children: [
                SizedBox(
                  width: VerticalNavbar.collapsedWidth,
                  child: Center(
                    child: SizedBox(
                      width: _iconSlot,
                      height: _iconSlot,
                      child: IconTheme(
                        data: IconThemeData(color: color, size: 24),
                        child: icon,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: FadeTransition(
                      opacity: labelOpacity,
                      child: DefaultTextStyle(
                        style: theme.textTheme.labelLarge!.copyWith(
                          color: color,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        child: destination.label,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.state, required this.showDetails});

  final BackgroundOperationUiState state;
  final bool showDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Card(
        elevation: 0,
        color: colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  switch (state.kind!) {
                    BackgroundOperationKind.importFile =>
                      Icons.download_rounded,
                    BackgroundOperationKind.exportFile => Icons.save_rounded,
                    BackgroundOperationKind.backup =>
                      Icons.cloud_upload_rounded,
                    BackgroundOperationKind.restoreBackup =>
                      Icons.cloud_download_rounded,
                  },
                  size: 18,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              if (showDetails) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        state.headline,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: state.indeterminate ? null : state.progress,
                          minHeight: 4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _VerticalNavbarTaskMarquee(
                        text: [
                          if (state.headline.isNotEmpty) state.headline,
                          if (state.detail.isNotEmpty) state.detail,
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                if (state.kind == BackgroundOperationKind.backup)
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: BackupManager.cancelBackup,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    color: colorScheme.onSurfaceVariant,
                    tooltip: 'Cancel backup',
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _VerticalNavbarTaskMarquee extends StatefulWidget {
  const _VerticalNavbarTaskMarquee({required this.text, required this.style});

  final String text;
  final TextStyle? style;

  @override
  State<_VerticalNavbarTaskMarquee> createState() =>
      _VerticalNavbarTaskMarqueeState();
}

class _VerticalNavbarTaskMarqueeState
    extends State<_VerticalNavbarTaskMarquee> {
  Timer? _timer;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 280), (_) {
      if (mounted) setState(() => _tick++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _line() {
    final t = widget.text.trim();
    if (t.isEmpty) return '…';
    const maxChars = 40;
    if (t.length <= maxChars) return t;
    final loop = '$t     ';
    final start = _tick % loop.length;
    final buf = StringBuffer();
    for (var i = 0; i < maxChars; i++) {
      buf.write(loop[(start + i) % loop.length]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _line(),
      maxLines: 1,
      overflow: TextOverflow.clip,
      style: widget.style,
    );
  }
}
