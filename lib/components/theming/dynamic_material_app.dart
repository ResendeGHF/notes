// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:go_router/go_router.dart';
import 'package:hux/hux.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/extensions/redirecting_localization_delegate.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:window_manager/window_manager.dart';

class DynamicMaterialApp extends StatefulWidget {
  const DynamicMaterialApp({
    super.key,
    required this.title,
    required this.router,
    this.defaultSwatch = Colors.grey,
  });

  final String title;
  final Color defaultSwatch;
  final GoRouter router;

  @override
  State<DynamicMaterialApp> createState() => DynamicMaterialAppState();

  static final ValueNotifier<bool> _isFullscreen = ValueNotifier(false);
  static bool get isFullscreen => _isFullscreen.value;

  static void setFullscreen(bool value, {required bool updateSystem}) {
    _isFullscreen.value = value;
    if (!updateSystem) return;

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.setFullScreen(value);
    } else if (Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  static void addFullscreenListener(void Function() listener) {
    _isFullscreen.addListener(listener);
  }

  static void removeFullscreenListener(void Function() listener) {
    _isFullscreen.removeListener(listener);
  }
}

class DynamicMaterialAppState extends State<DynamicMaterialApp>
    with WindowListener {
  @override
  void initState() {
    stows.appTheme.addListener(onChanged);
    stows.hyperlegibleFont.addListener(onChanged);

    windowManager.addListener(this);
    SystemChrome.setSystemUIChangeCallback(_onFullscreenChange);

    super.initState();
  }

  void onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void onWindowEnterFullScreen() {
    DynamicMaterialApp.setFullscreen(true, updateSystem: false);
  }

  @override
  void onWindowLeaveFullScreen() {
    DynamicMaterialApp.setFullscreen(false, updateSystem: false);
  }

  Future<void> _onFullscreenChange(bool systemOverlaysAreVisible) async {
    DynamicMaterialApp.setFullscreen(
      !systemOverlaysAreVisible,
      updateSystem: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lightTheme = HuxTheme.lightTheme;
    final darkTheme = HuxTheme.darkTheme;

    return ExplicitlyThemedApp(
      title: widget.title,
      router: widget.router,
      themeMode: stows.appTheme.value,
      theme: lightTheme.copyWith(
        colorScheme: lightTheme.colorScheme.copyWith(
          primary: Colors.grey,
          secondary: Colors.grey.shade600,
        ),
      ),
      darkTheme: darkTheme.copyWith(
        colorScheme: darkTheme.colorScheme.copyWith(
          primary: Colors.grey.shade300,
          secondary: Colors.grey.shade400,
        ),
      ),
    );
  }

  @override
  void dispose() {
    stows.appTheme.removeListener(onChanged);
    stows.hyperlegibleFont.removeListener(onChanged);

    windowManager.removeListener(this);
    SystemChrome.setSystemUIChangeCallback(null);

    super.dispose();
  }
}

@visibleForTesting
class ExplicitlyThemedApp extends StatelessWidget {
  @protected
  const ExplicitlyThemedApp({
    super.key,
    required this.title,
    required this.router,
    required this.themeMode,
    required this.theme,
    required this.darkTheme,
    this.highContrastTheme,
    this.highContrastDarkTheme,
  });

  final String title;
  final GoRouter router;
  final ThemeMode themeMode;
  final ThemeData theme, darkTheme;
  final ThemeData? highContrastTheme, highContrastDarkTheme;

  static final _materialAppKey = GlobalKey<State<MaterialApp>>();

  @override
  Widget build(BuildContext context) {
    final highContrastTheme =
        this.highContrastTheme ??
        theme.copyWith(colorScheme: theme.colorScheme.withHighContrast());
    final highContrastDarkTheme =
        this.highContrastDarkTheme ??
        darkTheme.copyWith(colorScheme: theme.colorScheme.withHighContrast());

    return MaterialApp.router(
      key: _materialAppKey,
      title: title,
      routeInformationProvider: router.routeInformationProvider,
      routeInformationParser: router.routeInformationParser,
      routerDelegate: router.routerDelegate,
      locale: TranslationProvider.of(context).flutterLocale,
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: const [
        RedirectingLocalizationDelegate<CupertinoLocalizations>(
          GlobalCupertinoLocalizations.delegate,
        ),
        RedirectingLocalizationDelegate<MaterialLocalizations>(
          GlobalMaterialLocalizations.delegate,
        ),
        RedirectingLocalizationDelegate<WidgetsLocalizations>(
          GlobalWidgetsLocalizations.delegate,
        ),
        RedirectingLocalizationDelegate<FlutterQuillLocalizations>(
          FlutterQuillLocalizations.delegate,
        ),
      ],
      themeMode: themeMode,
      theme: theme,
      darkTheme: darkTheme,
      highContrastTheme: highContrastTheme,
      highContrastDarkTheme: highContrastDarkTheme,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        Widget result = child ?? const SizedBox.shrink();
        if (Platform.isAndroid || Platform.isIOS) {
          final brightness = Theme.of(context).brightness;
          result = AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarContrastEnforced: false,
              statusBarIconBrightness: brightness == Brightness.dark
                  ? Brightness.light
                  : Brightness.dark,
              systemNavigationBarIconBrightness:
                  brightness == Brightness.dark
                      ? Brightness.light
                      : Brightness.dark,
            ),
            child: result,
          );
        }
        if (Platform.isWindows || Platform.isLinux) {
          result = _BorderedWindow(child: result);
        }
        return result;
      },
    );
  }
}

class _BorderedWindow extends StatefulWidget {
  const _BorderedWindow({required this.child});
  final Widget? child;
  @override
  State<_BorderedWindow> createState() => _BorderedWindowState();
}

class _BorderedWindowState extends State<_BorderedWindow> {
  static var _lastBorderColor = Colors.transparent;
  static final _childKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    DynamicMaterialApp.addFullscreenListener(_onFullscreenChanged);
  }

  @override
  void dispose() {
    DynamicMaterialApp.removeFullscreenListener(_onFullscreenChanged);
    super.dispose();
  }

  void _onFullscreenChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    final colorScheme = ColorScheme.of(context);
    final borderColor = Color.alphaBlend(
      (Theme.brightnessOf(context) == Brightness.light
          ? Colors.black.withValues(alpha: 0.1)
          : Colors.white.withValues(alpha: 0.06)),
      colorScheme.surface,
    );
    if (borderColor != _lastBorderColor) {
      _lastBorderColor = borderColor;
      windowManager.setBackgroundColor(borderColor).catchError((_) {});
    }
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {

    final keyedChild = KeyedSubtree(
      key: _childKey,
      child: widget.child ?? const SizedBox(),
    );

    final showBorder = !DynamicMaterialApp.isFullscreen;
    return showBorder
        ? ColoredBox(
            color: _lastBorderColor,
            child: Padding(padding: const EdgeInsets.all(1), child: keyedChild),
          )
        : keyedChild;
  }
}

extension _ColorSchemeContraster on ColorScheme {
  ColorScheme withHighContrast() => ColorScheme.fromSeed(
    brightness: brightness,
    seedColor: primary,
    surface: brightness == Brightness.light ? Colors.white : Colors.black,
    contrastLevel: 1,
  );
}
