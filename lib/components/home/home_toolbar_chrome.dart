// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:saber/components/navbar/horizontal_navbar.dart';
import 'package:saber/components/theming/saber_theme.dart';

/// Same surface as [VerticalNavbar] / [GlassyContainer] for home subpage headers.
Color homeAppBarBackgroundColor(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.dark
      ? const Color(0xFF111111)
      : theme.colorScheme.surface;
}

/// Width for docked editor side panels (pages, PDF outlines, ⋯ menu).
/// Leaves canvas space so notes stay visible/editable while the panel is open.
double editorSidePanelDesktopWidth(BuildContext context) {
  final sw = MediaQuery.sizeOf(context).width;
  if (sw <= 0) return 0;
  final reservedForCanvas = (sw * 0.28).clamp(96.0, 200.0);
  final ideal = sw < 600 ? sw * 0.55 : (sw * 0.42).clamp(320.0, 680.0);
  final maxPanel = (sw - reservedForCanvas).clamp(0.0, sw);
  return ideal.clamp(0.0, maxPanel);
}

/// Shell for full-height editor drawers (pages, PDF outlines, ⋯ menu) — aligns
/// with [homeRuggedPanelDecoration] / home rail surfaces.
BoxDecoration editorSidePanelShellDecoration(
  BuildContext context, {
  required bool isMobile,
}) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final isDark = theme.brightness == Brightness.dark;
  return BoxDecoration(
    color: homeAppBarBackgroundColor(context),
    borderRadius: isMobile
        ? BorderRadius.zero
        : const BorderRadius.horizontal(
            left: Radius.circular(kSaberContainerRadius),
          ),
    border: Border.all(
      color: cs.outlineVariant.withValues(alpha: isMobile ? 0.14 : 0.2),
      width: 1,
    ),
    boxShadow: isMobile
        ? null
        : [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
              blurRadius: 18,
              offset: const Offset(-4, 0),
            ),
          ],
  );
}

/// Header + divider + body for editor side drawers (matches editor_menu density).
class EditorRuggedSidePanel extends StatelessWidget {
  const EditorRuggedSidePanel({
    super.key,
    required this.title,
    required this.onClose,
    required this.body,
  });

  final String title;
  final VoidCallback onClose;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 2, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.25,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                  style: IconButton.styleFrom(
                    foregroundColor: cs.onSurfaceVariant,
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 22),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: cs.outlineVariant.withValues(alpha: 0.22),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Shared “rugged” panel: rail surface, hairline border, light shadow.
BoxDecoration homeRuggedPanelDecoration(
  BuildContext context, {
  double borderAlpha = 0.18,
}) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final isDark = theme.brightness == Brightness.dark;
  return BoxDecoration(
    color: homeAppBarBackgroundColor(context),
    borderRadius: BorderRadius.circular(kSaberContainerRadius),
    border: Border.all(
      color: cs.outlineVariant.withValues(alpha: borderAlpha),
      width: 1,
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.06),
        blurRadius: 10,
        offset: const Offset(0, 2),
      ),
    ],
  );
}

/// Opaque “rugged” surface for [Dialog]s — replaces glass / blur shells.
class RuggedDialogShell extends StatelessWidget {
  const RuggedDialogShell({
    super.key,
    required this.child,
    this.maxWidth = 520,
    this.padding = const EdgeInsets.all(24),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: DecoratedBox(
          decoration: homeRuggedPanelDecoration(context),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Taller browse header; recent/graph stay on [kToolbarHeight].
const double kBrowseAppBarToolbarHeight = 64;

/// Compact icon buttons used inside glass strips (matches rail density).
ButtonStyle homeToolbarCompactIconStyle(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return IconButton.styleFrom(
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.all(8),
    minimumSize: const Size(40, 40),
    foregroundColor: cs.onSurfaceVariant,
  );
}

/// Vertical rule between toolbar icon groups.
class HomeToolbarDivider extends StatelessWidget {
  const HomeToolbarDivider({super.key, this.alpha = 0.18});

  final double alpha;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(
      context,
    ).colorScheme.outlineVariant.withValues(alpha: alpha);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        width: 1,
        height: 24,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(0.5),
          ),
        ),
      ),
    );
  }
}

/// Pill-shaped cluster of actions (same shell as the floating navbar capsule).
class HomeGlassIconStrip extends StatelessWidget {
  const HomeGlassIconStrip({
    super.key,
    required this.children,
    this.height = 48,
  });

  final List<Widget> children;
  final double height;

  @override
  Widget build(BuildContext context) {
    return GlassyContainer(
      height: height,
      borderRadius: BorderRadius.circular(16),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }
}
