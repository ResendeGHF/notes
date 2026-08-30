// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/navbar/responsive_navbar.dart';
import 'package:saber/components/theming/dynamic_material_app.dart';
import 'package:saber/data/home_data_cache.dart';
import 'package:saber/pages/home/browse.dart';
import 'package:saber/pages/home/graph.dart';
import 'package:saber/pages/home/recent_notes.dart';
import 'package:saber/pages/home/settings.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.subpage, required this.path});

  final String subpage;
  final String? path;

  @override
  State<HomePage> createState() => _HomePageState();

  static const recentSubpage = 'recent';
  static const browseSubpage = 'browse';
  static const graphSubpage = 'graph';
  static const settingsSubpage = 'settings';
  static const List<String> subpages = [
    recentSubpage,
    browseSubpage,
    graphSubpage,
    settingsSubpage,
  ];
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    DynamicMaterialApp.addFullscreenListener(_setState);
    HomeDataCache.instance.preload();
    _showDialogs();
  }

  void _showDialogs() async {
    await null;
    if (!mounted) return;
  }

  void _setState() {
    if (mounted) setState(() {});
  }

  Widget get body {
    var index = HomePage.subpages.indexOf(widget.subpage);
    if (index == -1) index = 0;

    return IndexedStack(
      index: index,
      sizing: StackFit.expand,
      children: [
        // RepaintBoundaries keep inactive tabs from repainting when the rail
        // snaps its inset (IndexedStack still keeps their state alive).
        RepaintBoundary(
          child: _TransitionPage(
            active: index == 0,
            child: RecentPage(isActive: index == 0),
          ),
        ),
        _TransitionPage(
          active: index == 1,
          child: KeyedSubtree(
            key: ValueKey('browse_${widget.path ?? "/"}'),
            child: BrowsePage(path: widget.path),
          ),
        ),
        _TransitionPage(active: index == 2, child: const GraphPage()),
        _TransitionPage(active: index == 3, child: const SettingsPage()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    var index = HomePage.subpages.indexOf(widget.subpage);
    if (index == -1) index = 0;

    return ResponsiveNavbar(selectedIndex: index, body: body);
  }

  @override
  void dispose() {
    DynamicMaterialApp.removeFullscreenListener(_setState);
    super.dispose();
  }
}

class _TransitionPage extends StatelessWidget {
  const _TransitionPage({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !active,
      child: AnimatedOpacity(
        opacity: active ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }
}
