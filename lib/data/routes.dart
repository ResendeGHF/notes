// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path_to_regexp/path_to_regexp.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/home/home.dart';

abstract class RoutePaths {
  static const home = '$prefixOfHome/:subpage';
  static const edit = '/edit';
  static const login = '/login';
  static const logs = '/logs';
  static const vaultPdfLoadOverrides = '/settings/vault-pdf-load-overrides';
  static const settingsNoteDefaults = '/settings/note-defaults';
  static const settingsInkDefaults = '/settings/ink-defaults';

  static const prefixOfHome = '/home';

  static String editFilePath(
    String filePath, {
    int? pageIndex,
  }) {
    var route = '$edit?path=${Uri.encodeQueryComponent(filePath)}';
    if (pageIndex != null && pageIndex >= 0) {
      route += '&page=${Uri.encodeQueryComponent(pageIndex.toString())}';
    }
    return route;
  }

  static String editImportPdf(String filePath, String pdfPath) {
    return '$edit'
        '?path=${Uri.encodeQueryComponent(filePath)}'
        '&pdfPath=${Uri.encodeQueryComponent(pdfPath)}';
  }

  static String editSplit(
    String primaryPath,
    String secondaryPath, {
    Axis axis = Axis.horizontal,
    int? secondaryPageIndex,
  }) {
    final axisValue = axis == Axis.vertical ? 'vertical' : 'horizontal';
    var route =
        '$edit'
        '?path=${Uri.encodeQueryComponent(primaryPath)}'
        '&splitPath=${Uri.encodeQueryComponent(secondaryPath)}'
        '&splitAxis=$axisValue';
    if (secondaryPageIndex != null && secondaryPageIndex >= 0) {
      route +=
          '&splitPage=${Uri.encodeQueryComponent(secondaryPageIndex.toString())}';
    }
    return route;
  }
}

abstract class HomeRoutes {
  static String browseFilePath(String? filePath) {
    var path = getRoute(1);
    if (filePath != '/' && filePath != '' && filePath != null) {
      path += '?path=${Uri.encodeQueryComponent(filePath)}';
    }
    return path;
  }

  static final PathFunction _homeFunction = pathToFunction(RoutePaths.home);

  static List<_Route> get _routes => <_Route>[
    _Route(
      routePath: _homeFunction({'subpage': HomePage.recentSubpage}),
      label: t.home.tabs.home,
      icon: const AdaptiveIcon(
        icon: Icons.home,
        cupertinoIcon: CupertinoIcons.house_fill,
      ),
    ),
    _Route(
      routePath: _homeFunction({'subpage': HomePage.browseSubpage}),
      label: t.home.tabs.browse,
      icon: const AdaptiveIcon(
        icon: Icons.folder,
        cupertinoIcon: CupertinoIcons.folder_fill,
      ),
    ),
    _Route(
      routePath: _homeFunction({'subpage': HomePage.graphSubpage}),
      label: 'Graph',
      icon: const AdaptiveIcon(
        icon: Icons.hub,
        cupertinoIcon: CupertinoIcons.circle_grid_3x3_fill,
      ),
    ),
    _Route(
      routePath: _homeFunction({'subpage': HomePage.settingsSubpage}),
      label: t.home.tabs.settings,
      icon: const AdaptiveIcon(
        icon: Icons.settings,
        cupertinoIcon: CupertinoIcons.settings_solid,
      ),
    ),
  ];

  static String getRoute(int index) {
    return _routes[index].routePath;
  }

  static List<NavigationDestination> get navigationDestinations =>
      _routes.map((e) => e.toNavigationDestination()).toList(growable: false);
  static List<NavigationRailDestination> get navigationRailDestinations =>
      _routes
          .map((e) => e.toNavigationRailDestination())
          .toList(growable: false);
}

class _Route {
  final String routePath;
  final String label;
  final Widget icon;

  _Route({required this.routePath, required this.label, required this.icon});

  NavigationDestination toNavigationDestination() =>
      NavigationDestination(label: label, icon: icon);
  NavigationRailDestination toNavigationRailDestination() =>
      NavigationRailDestination(label: Text(label), icon: icon);
}
