// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:path_to_regexp/path_to_regexp.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:saber/components/editor/sba_export_dialog.dart';
import 'package:saber/components/theming/dynamic_material_app.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/data/tools/stroke_properties.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:saber/pages/home/home.dart';
import 'package:saber/pages/home/vault_pdf_load_overrides_page.dart';
import 'package:saber/pages/logs.dart';
import 'package:saber/pages/vault_login.dart';
import 'package:saber/services/vault_adapter.dart';
import 'package:window_manager/window_manager.dart';
import 'package:worker_manager/worker_manager.dart';
import 'package:workmanager/workmanager.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {

    Stows.markAsOnMainIsolate();
    await Future.wait([
      stows.backupDirectoryPath.waitUntilRead(),
      stows.autoBackupIntervalHours.waitUntilRead(),
      stows.lastBackupTimestamp.waitUntilRead(),
      stows.localEncryptionEnabled.waitUntilRead(),
      stows.customDataDir.waitUntilRead(),
    ]);

    final docsDir =
        stows.customDataDir.value ??
        await FileManager.getDefaultDocumentsDirectory();
    await FileManager.init(
      documentsDirectory: docsDir,
      shouldWatchRootDirectory: false,
    );

    await BackupManager.initNotifications();

    switch (task) {
      case 'incremental_backup':
        await BackupManager.performIncrementalBackup();
        break;
      default:
        break;
    }
    return true;
  });
}

Future<void> main(List<String> args) async {

  FlavorConfig.setupFromEnvironment();

  await appRunner(args);
}

Future<void> appRunner(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final parser = ArgParser()..addFlag('verbose', abbr: 'v', negatable: false);
  final parsedArgs = parser.parse(args);

  Logger.root.level = (kDebugMode || parsedArgs.flag('verbose'))
      ? Level.INFO
      : Level.WARNING;
  Logger.root.onRecord.listen((record) {
    logsHistory.add(record);

    print('${record.level.name}: ${record.loggerName}: ${record.message}');
  });

  if (!kDebugMode) {
    final errorLogger = Logger('ErrorLogger');
    FlutterError.onError = (details) {
      errorLogger.severe(
        details.exceptionAsString(),
        details.exception,
        details.stack,
      );
      FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      errorLogger.severe(error, stackTrace);

      return !kDebugMode;
    };
  }

  StrokeOptionsExtension.setDefaults();
  Stows.markAsOnMainIsolate();

  pdfrxFlutterInitialize(dismissPdfiumWasmWarnings: true);

  await Future.wait([
    stows.customDataDir.waitUntilRead().then((_) => FileManager.init()),
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
      windowManager.ensureInitialized(),
    workerManager.init(),
    stows.locale.waitUntilRead(),
    Printing.info().then((info) {
      Editor.canRasterPdf = info.canRaster;
    }),
  ]);

  Workmanager().initialize(callbackDispatcher, isInDebugMode: kDebugMode);

  setLocale();
  stows.locale.addListener(setLocale);
  stows.customDataDir.addListener(FileManager.migrateDataDir);

  LicenseRegistry.addLicense(() async* {
    for (final licenseFile in const [
      'assets/google_fonts/Atkinson_Hyperlegible_Next/OFL.txt',
      'assets/google_fonts/Dekko/OFL.txt',
      'assets/google_fonts/Fira_Mono/OFL.txt',
      'assets/google_fonts/Neucha/OFL.txt',
    ]) {
      final license = await rootBundle.loadString(licenseFile);
      yield LicenseEntryWithLineBreaks(const ['google_fonts'], license);
    }
  });

  runApp(TranslationProvider(child: const App()));
}

void setLocale() {
  if (stows.locale.value.isNotEmpty &&
      AppLocaleUtils.supportedLocalesRaw.contains(stows.locale.value)) {
    LocaleSettings.setLocaleRaw(stows.locale.value);
  } else {
    LocaleSettings.useDeviceLocale();
  }
}

class App extends StatefulWidget {
  const App({super.key});

  static final log = Logger('App');

  static String initialLocation = pathToFunction(RoutePaths.home)({
    'subpage': HomePage.recentSubpage,
  });

  static final _rootNavigatorKey = GlobalKey<NavigatorState>();
  static final _router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: initialLocation,
    refreshListenable: Listenable.merge([
      stows.localEncryptionEnabled,
      VaultAdapter.unlockListenable,
    ]),

    redirect: (context, state) {
      final encryptionEnabled = stows.localEncryptionEnabled.value;
      final isVaultUnlocked = VaultAdapter.isUnlocked;
      final isGoingToLogin = state.matchedLocation == RoutePaths.login;
      final isSettings =
          state.matchedLocation.startsWith(RoutePaths.prefixOfHome) &&
          state.pathParameters['subpage'] == HomePage.settingsSubpage;

      if (encryptionEnabled && !isVaultUnlocked) {

        if (isGoingToLogin || isSettings) return null;
        return RoutePaths.login;
      }

      if (isVaultUnlocked && isGoingToLogin) {
        return initialLocation;
      }

      return null;
    },
    routes: <GoRoute>[
      GoRoute(path: '/', redirect: (context, state) => initialLocation),
      GoRoute(
        path: RoutePaths.home,
        builder: (context, state) => HomePage(
          subpage: state.pathParameters['subpage'] ?? HomePage.recentSubpage,
          path: state.uri.queryParameters['path'],
        ),
      ),
      GoRoute(
        path: RoutePaths.edit,
        pageBuilder: (context, state) {
          final path = state.uri.queryParameters['path'];
          final pageParam = state.uri.queryParameters['page'];
          final initialPageIndexOverride = int.tryParse(pageParam ?? '');
          final pdfPath = state.uri.queryParameters['pdfPath'];
          final splitPath = state.uri.queryParameters['splitPath'];
          final splitAxis = state.uri.queryParameters['splitAxis'];
          final splitPageParam = state.uri.queryParameters['splitPage'];
          final secondaryInitialPageIndex = int.tryParse(splitPageParam ?? '');
          final Widget child = splitPath != null
              ? SplitEditorPage(
                  primaryPath: path,
                  secondaryPath: splitPath,
                  primaryPdfPath: pdfPath,
                  initialAxis: splitAxis == 'vertical'
                      ? Axis.vertical
                      : Axis.horizontal,
                  secondaryInitialPageIndex: secondaryInitialPageIndex,
                )
              : Editor(
                  path: path,
                  pdfPath: pdfPath,
                  initialPageIndexOverride: initialPageIndexOverride,
                );
          return CustomTransitionPage(
            key: state.pageKey,
            child: child,
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) =>
                    FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 250),
          );
        },
      ),

      GoRoute(
        path: RoutePaths.login,
        builder: (context, state) => const VaultLoginPage(),
      ),
      GoRoute(
        path: RoutePaths.logs,
        builder: (context, state) => const LogsPage(),
      ),
      GoRoute(
        path: RoutePaths.vaultPdfLoadOverrides,
        builder: (context, state) => const VaultPdfLoadOverridesPage(),
      ),
    ],
  );

  static final List<SharedMediaFile> pendingImports = [];
  static final ValueNotifier<int> pendingImportCount = ValueNotifier(0);

  static Future<void> processPendingImports() async {
    if (pendingImports.isEmpty) return;

    log.info('Processing ${pendingImports.length} pending imports');
    final filesToProcess = List<SharedMediaFile>.from(pendingImports);
    pendingImports.clear();
    pendingImportCount.value = 0;

    for (final file in filesToProcess) {
      await openFile(file);
    }
  }

  static Future<void> openFile(SharedMediaFile file) async {
    log.info('Opening file: (${file.type}) ${file.path}');

    // SECURITY CHECK: If encryption is enabled and vault is locked, queue the file.
    if (stows.localEncryptionEnabled.value && !VaultAdapter.isUnlocked) {
      log.info(
        'Vault is locked. Queueing file for import after unlock: ${file.path}',
      );
      pendingImports.add(file);
      pendingImportCount.value = pendingImports.length;

      _router.go(RoutePaths.login);
      _router.refresh();
      return;
    }

    if (file.type != SharedMediaType.file) return;

    final String extension;
    if (file.path.contains('.')) {
      extension = file.path.split('.').last.toLowerCase();
    } else {
      extension = 'sbn2';
    }

    try {
      if (extension == 'sbn' || extension == 'sbn2' || extension == 'sba') {
        final path = await FileManager.importFile(
          file.path,
          null,
          extension: '.$extension',
          getEncryptionPassword: extension == 'sba'
              ? () async {
                  final ctx = App._rootNavigatorKey.currentContext;
                  if (ctx == null || !ctx.mounted) return null;
                  return showSbaImportPasswordDialog(ctx);
                }
              : null,
        );
        if (path == null) return;

        await Future.delayed(const Duration(milliseconds: 100));

        _router.push(RoutePaths.editFilePath(path));
      } else if (extension == 'pdf' && Editor.canRasterPdf) {
        final fileName = file.path.split(RegExp(r'[\\/]')).last;
        final fileNameWithoutExtension = fileName.toLowerCase().endsWith('.pdf')
            ? fileName.substring(0, fileName.length - 4)
            : fileName;
        final sbnFilePath = await FileManager.suffixFilePathToMakeItUnique(
          '/$fileNameWithoutExtension',
        );
        _router.push(RoutePaths.editImportPdf(sbnFilePath, file.path));
      } else {
        log.warning('openFile: Unsupported file type: $extension');
      }
    } catch (e, stack) {
      log.severe('Error opening file: $e', e, stack);

    }
  }

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  StreamSubscription? _intentDataStreamSubscription;

  void _checkAutoBackup() {
    final interval = stows.autoBackupIntervalMinutes.value;
    if (interval <= 0) return;
    final last = stows.lastBackupTimestamp.value;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now - last > interval * 60 * 1000) {
      BackupManager.performIncrementalBackup();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    setupSharingIntent();
    _checkAutoBackup();
    Timer.periodic(const Duration(minutes: 5), (timer) {
      _checkAutoBackup();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // SECURITY: Lock vault when app is paused or closed (unless file picker/share is open)
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (VaultAdapter.preventLock) {
        VaultAdapter.log.info(
          'Vault auto-lock prevented due to active file operation',
        );
        return;
      }
      if (stows.localEncryptionEnabled.value && VaultAdapter.isUnlocked) {
        VaultAdapter.instance.lock();
      }
    }
  }

  void setupSharingIntent() {
    if (Platform.isAndroid || Platform.isIOS) {

      ReceiveSharingIntent.instance.getInitialMedia().then((
        List<SharedMediaFile> files,
      ) {
        for (final file in files) {
          App.openFile(file);
        }
      });

      final stream = ReceiveSharingIntent.instance.getMediaStream();
      _intentDataStreamSubscription = stream.listen((
        List<SharedMediaFile> files,
      ) {
        for (final file in files) {
          App.openFile(file);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DynamicMaterialApp(title: 'Notes', router: App._router);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _intentDataStreamSubscription?.cancel();
    super.dispose();
  }
}
