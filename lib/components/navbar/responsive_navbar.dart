// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:saber/components/navbar/home_shell_layout.dart';
import 'package:saber/components/navbar/horizontal_navbar.dart';
import 'package:saber/components/navbar/vertical_navbar.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/routes.dart';
import 'package:stow_codecs/stow_codecs.dart';

class ResponsiveNavbar extends StatefulWidget {
  const ResponsiveNavbar({
    super.key,
    required this.body,
    this.selectedIndex = 0,
  });

  final Widget body;
  final int selectedIndex;

  @override
  State<ResponsiveNavbar> createState() => _ResponsiveNavbarState();

  static var isLargeScreen = true;
}

class _ResponsiveNavbarState extends State<ResponsiveNavbar> {
  @override
  void initState() {
    stows.locale.addListener(onChange);
    stows.layoutSize.addListener(onChange);
    super.initState();
  }

  void onChange() {
    setState(() {});
  }

  void onDestinationSelected(int index) {
    if (index == widget.selectedIndex) return;

    context.go(HomeRoutes.getRoute(index));
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    ResponsiveNavbar.isLargeScreen = switch (stows.layoutSize.value) {
      .auto => mediaQuery.size.width >= 600,
      .phone => false,
      .tablet => true,
    };

    if (ResponsiveNavbar.isLargeScreen) {
      // All home tabs follow expandT so content scales with the rail.
      return Scaffold(
        body: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: ValueListenableBuilder<double>(
                valueListenable: HomeShellLayout.verticalNavExpandT,
                builder: (context, t, child) {
                  final inset = VerticalNavbar.collapsedWidth +
                      VerticalNavbar.panelWidth * t.clamp(0.0, 1.0);
                  return Padding(
                    padding: EdgeInsetsDirectional.only(start: inset),
                    child: child,
                  );
                },
                child: RepaintBoundary(child: widget.body),
              ),
            ),
            PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              child: VerticalNavbar(
                destinations: HomeRoutes.navigationRailDestinations,
                selectedIndex: widget.selectedIndex,
                onDestinationSelected: onDestinationSelected,
              ),
            ),
          ],
        ),
      );
    }

    final navbarClearance = HorizontalNavbar.clearanceHeightOf(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          MediaQuery(
            data: mediaQuery.copyWith(
              padding: mediaQuery.padding + .only(bottom: navbarClearance),
              viewPadding:
                  mediaQuery.viewPadding + .only(bottom: navbarClearance),
            ),
            child: widget.body,
          ),
          PositionedDirectional(
            bottom: 0,
            start: 0,
            end: 0,
            child: HorizontalNavbar(
              destinations: HomeRoutes.navigationDestinations,
              selectedIndex: widget.selectedIndex,
              onDestinationSelected: onDestinationSelected,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    stows.locale.removeListener(onChange);
    stows.layoutSize.removeListener(onChange);
    super.dispose();
  }
}

enum LayoutSize {
  auto,
  phone,
  tablet;

  static const codec = EnumCodec(values);
}
