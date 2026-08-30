// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

// ignore_for_file: unused_element_parameter

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saber/components/navbar/responsive_navbar.dart';
import 'package:saber/components/settings/app_info.dart';
import 'package:saber/components/settings/settings_button.dart';
import 'package:saber/components/settings/settings_directory_selector.dart';
import 'package:saber/components/settings/settings_dropdown.dart';
import 'package:saber/components/settings/settings_selection.dart';
import 'package:saber/components/settings/settings_switch.dart';
import 'package:saber/components/settings/vault_pdf_load_settings.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
import 'package:saber/components/theming/adaptive_toggle_buttons.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'dart:math';
import 'package:saber/data/backup/incremental_backup_core.dart';
import 'package:saber/data/locales.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/services/sba_encryption.dart';
import 'package:saber/services/vault_adapter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:stow/stow.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

Future<bool> _isolateCheckBackupTypeTask(Map<String, dynamic> args) async {
  final path = args['path'] as String;
  final password = args['password'] as String;

  final stamp = DateTime.now().microsecondsSinceEpoch;
  final tmpZip = '$path.check_$stamp.zip';
  var zipPath = path;
  var ownsZip = false;

  try {
    final header = File(path).openSync(mode: FileMode.read);
    late final Uint8List peek;
    try {
      peek = Uint8List.fromList(header.readSync(32));
    } finally {
      header.closeSync();
    }

    if (SbaEncryption.isEncrypted(peek)) {
      if (password.isEmpty) {
        throw StateError('Backup is encrypted but no password was provided.');
      }
      SbaEncryption.decryptFile(path, tmpZip, password);
      zipPath = tmpZip;
      ownsZip = true;
    }

    final input = InputFileStream(zipPath);
    final archive = ZipDecoder().decodeStream(input);
    final manifestFiles = archive.files
        .where((f) => f.name == '_backup_manifest.json')
        .toList();
    input.closeSync();
    if (manifestFiles.isEmpty) return false;

    final content = manifestFiles.first.content;
    final List<int> manifestBytes;
    if (content is List<int>) {
      manifestBytes = content;
    } else {
      final output = OutputMemoryStream();
      manifestFiles.first.writeContent(output);
      manifestBytes = output.getBytes();
    }
    final manifestJson =
        jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
    return manifestJson['type'] == 'data';
  } finally {
    if (ownsZip) {
      try {
        final f = File(tmpZip);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();

  static Future<bool?> showResetDialog({
    required BuildContext context,
    required Stow pref,
    required String prefTitle,
  }) async {
    if (pref.value == pref.defaultValue) return null;
    return await showDialog(
      context: context,
      builder: (context) => AdaptiveAlertDialog(
        title: Text(t.settings.reset.title),
        content: Text(prefTitle),
        actions: [
          CupertinoDialogAction(
            onPressed: () {
              Navigator.of(context).pop(false);
            },
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              pref.value = pref.defaultValue;
              Navigator.of(context).pop(true);
            },
            child: Text(t.settings.reset.button),
          ),
        ],
      ),
    );
  }
}

abstract class _SettingsStows {
  static final appTheme = TransformedStow(
    stows.appTheme,
    (ThemeMode value) => value.index,
    (int value) => ThemeMode.values[value],
  );

  static final layoutSize = TransformedStow(
    stows.layoutSize,
    (LayoutSize value) => value.index,
    (int value) => LayoutSize.values[value],
  );

  static final editorToolbarAlignment = TransformedStow(
    stows.editorToolbarAlignment,
    (AxisDirection value) => value.index,
    (int value) => AxisDirection.values[value],
  );
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    stows.locale.addListener(onChanged);
    super.initState();
  }

  void onChanged() {
    setState(() {});
  }

  bool _incrementalBackupReady(BuildContext context) {
    if (stows.backupFilePath.value.isEmpty ||
        stows.backupPassword.value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select a target file and generate a key first.',
          ),
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _runIncrementalBackupNow(BuildContext context) async {
    if (!_incrementalBackupReady(context)) return;

    BackupManager.status.value = const BackupStatus(
      isRunning: true,
      progress: 0.01,
      currentFile: 'Preparing backup file...',
    );
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      transitionDuration: Duration.zero,
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          child,
      pageBuilder: (dialogContext, _, __) {
        return const _BackupProgressDialog();
      },
    );
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(Duration.zero);

    try {
      WakelockPlus.enable();
      await BackupManager.performIncrementalBackupForeground();
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Backup Complete!')));
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      WakelockPlus.disable();
    }
  }

  void _runIncrementalBackupBackground(BuildContext context) {
    if (!_incrementalBackupReady(context)) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Backup running in background.')),
    );
    unawaited(
      BackupManager.performIncrementalBackupBackground()
          .then((_) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Backup Complete!')));
          })
          .catchError((Object e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Error: $e')));
          }),
    );
  }

  String _formatBackupBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _verifyIncrementalBackup(BuildContext context) async {
    if (!_incrementalBackupReady(context)) return;

    BackupManager.status.value = const BackupStatus(
      isRunning: true,
      progress: 0.02,
      currentFile: 'Verifying backup...',
    );
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      transitionDuration: Duration.zero,
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          child,
      pageBuilder: (dialogContext, _, __) {
        return const _BackupProgressDialog();
      },
    );
    await WidgetsBinding.instance.endOfFrame;

    try {
      WakelockPlus.enable();
      final result = await BackupManager.verifyIncrementalBackup(
        stows.backupFilePath.value,
        stows.backupPassword.value,
      );
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      final sample = result.samplePaths.isEmpty
          ? '(none)'
          : result.samplePaths.take(8).join('\n');
      final errorBlock = result.errors.isEmpty
          ? ''
          : '\n\nIssues:\n${result.errors.take(12).join('\n')}';

      await showDialog<void>(
        context: context,
        builder: (context) => AdaptiveAlertDialog(
          title: Text(result.ok ? 'Backup looks consistent' : 'Backup check failed'),
          content: SingleChildScrollView(
            child: SelectableText(
              'Archive: ${_formatBackupBytes(result.archiveBytes)}\n'
              'Indexed files checked: ${result.checkedFileCount} / ${result.indexedFileCount}\n'
              'Folders in index: ${result.indexedFolderCount}\n'
              'Note bodies (.sbn / .sbn2): ${result.noteBodyCount}\n'
              'Payload size (uncompressed index): ${_formatBackupBytes(result.indexedPayloadBytes)}\n'
              'Sidecars: .idxoff=${result.hasIdxoff ? 'yes' : 'NO'}, '
              '.inc_state.json=${result.hasIncState ? 'yes' : 'no'}\n'
              'Mode: ${result.sourceMode}\n\n'
              'Sample paths:\n$sample'
              '$errorBlock\n\n'
              'Note: App storage is often much larger than the backup because '
              'thumbnails (.p), caches, and SQLite journals are not included. '
              'Seeing only the .nba plus .idxoff and .inc_state.json next to it '
              'is expected — all notes live inside the single archive.',
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t.common.done),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Verify failed: $e')));
    } finally {
      WakelockPlus.disable();
    }
  }

  Future<void> _showBackupKeyDialog() async {
    final ctrl = TextEditingController(text: stows.backupPassword.value);
    bool obscure = true;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AdaptiveAlertDialog(
          title: const Text('Backup Encryption Key'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Save this key securely! You will need it to restore your backups on another device.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'Key',
                  border: const OutlineInputBorder(),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () => setState(() => obscure = !obscure),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: ctrl.text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Key copied to clipboard!'),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.autorenew, size: 18),
                label: const Text('Generate New Key'),
                onPressed: () {
                  final random = Random.secure();
                  final bytes = List.generate(32, (_) => random.nextInt(256));
                  setState(() {
                    ctrl.text = base64UrlEncode(bytes);
                    obscure = false;
                  });
                },
              ),
            ],
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                stows.backupPassword.value = ctrl.text;
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  static const _directionIcons = [
    Icons.north,
    Icons.east,
    Icons.south,
    Icons.west,
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    Widget buildSection(String title, List<Widget> children) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (int i = 0; i < children.length; i++) ...[
                    children[i],
                    if (i < children.length - 1 && children[i] is! SizedBox)
                      Divider(
                        height: 1,
                        indent: 56,
                        endIndent: 16,
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.3,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 8),
            sliver: SliverAppBar(
              primary: false,
              collapsedHeight: kToolbarHeight,
              expandedHeight: 120,
              pinned: true,
              scrolledUnderElevation: 1,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  t.home.titles.settings,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                  ),
                ),
                centerTitle: false,
                titlePadding: const EdgeInsetsDirectional.only(
                  start: 24,
                  bottom: 16,
                ),
              ),
            ),
          ),
          SliverSafeArea(
            top: false,
            sliver: SliverList.list(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: AppInfo(),
                ),

                buildSection(t.settings.prefCategories.security, [
                  ValueListenableBuilder<bool>(
                    valueListenable: stows.localEncryptionEnabled,
                    builder: (context, encryptionEnabled, _) {
                      if (!encryptionEnabled) return const SizedBox.shrink();
                      return const _VaultSecurityStatus();
                    },
                  ),
                  _VaultEncryptionSwitch(),
                  ValueListenableBuilder<bool>(
                    valueListenable: stows.localEncryptionEnabled,
                    builder: (context, encryptionEnabled, _) {
                      if (!encryptionEnabled) return const SizedBox.shrink();
                      return SettingsSwitch(
                        title: 'Vault secure delete',
                        subtitle:
                            'Overwrite deleted file content with random data; index with zeros.',
                        icon: Icons.security,
                        pref: stows.vaultSecureDelete,
                      );
                    },
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: stows.localEncryptionEnabled,
                    builder: (context, encryptionEnabled, _) {
                      if (!encryptionEnabled) return const SizedBox.shrink();
                      return const VaultPdfLoadSettings();
                    },
                  ),
                ]),

                buildSection(t.export.defaultExportPath, [
                  ValueListenableBuilder(
                    valueListenable: stows.defaultExportPath,
                    builder: (context, path, _) {
                      return ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(t.export.defaultExportPath),
                        subtitle: Text(
                          path.toString().isEmpty ? 'Not Set' : path.toString(),
                        ),
                        onTap: () async {
                          VaultAdapter.preventLock = true;
                          try {
                            if (Platform.isAndroid) {
                              if (!await Permission
                                      .manageExternalStorage
                                      .isGranted &&
                                  !await Permission.storage.isGranted) {
                                await Permission.manageExternalStorage
                                    .request();
                                await Permission.storage.request();
                                if (!await Permission
                                        .manageExternalStorage
                                        .isGranted &&
                                    !await Permission.storage.isGranted) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Storage permission required for export path.',
                                        ),
                                        duration: const Duration(seconds: 4),
                                      ),
                                    );
                                  }
                                  return;
                                }
                              }
                            }
                            if (Platform.isAndroid || Platform.isIOS) {
                              final selectedDirectory = await FilePicker
                                  .platform
                                  .getDirectoryPath(
                                    dialogTitle: t.export.defaultExportPath,
                                  );
                              if (selectedDirectory != null) {
                                stows.defaultExportPath.value =
                                    selectedDirectory;
                              }
                            } else {
                              final selectedPath = await FilePicker.platform
                                  .saveFile(
                                    dialogTitle: t.export.defaultExportPath,
                                    fileName: 'export',
                                  );
                              if (selectedPath != null) {
                                stows.defaultExportPath.value = p.dirname(
                                  selectedPath,
                                );
                              }
                            }
                          } finally {
                            VaultAdapter.preventLock = false;
                          }
                        },
                      );
                    },
                  ),
                ]),

                buildSection('Secure Incremental Backup', [
                  ValueListenableBuilder(
                    valueListenable: stows.backupFilePath,
                    builder: (context, path, _) {
                      return ListTile(
                        leading: const Icon(Icons.file_upload),
                        title: const Text('Backup Target File'),
                        subtitle: Text(
                          path.toString().isEmpty ? 'Not Set' : path.toString(),
                        ),
                        onTap: () async {
                          VaultAdapter.preventLock = true;
                          try {
                            if (Platform.isAndroid) {
                              if (!await Permission
                                      .manageExternalStorage
                                      .isGranted &&
                                  !await Permission.storage.isGranted) {
                                await Permission.manageExternalStorage
                                    .request();
                                await Permission.storage.request();

                                if (!await Permission
                                        .manageExternalStorage
                                        .isGranted &&
                                    !await Permission.storage.isGranted) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Storage/All Files Access permission is required for background backups.',
                                        ),
                                        duration: Duration(seconds: 4),
                                      ),
                                    );
                                  }
                                  return;
                                }
                              }
                            }

                            if (Platform.isAndroid || Platform.isIOS) {
                              String? selectedDirectory = await FilePicker
                                  .platform
                                  .getDirectoryPath(
                                    dialogTitle: 'Select Backup Folder',
                                  );
                              if (selectedDirectory != null) {
                                final archivePath = p.join(
                                  selectedDirectory,
                                  'notes_backup_archive.nba',
                                );
                                try {
                                  prepareIncrementalBackupTarget(archivePath);
                                  stows.backupFilePath.value = archivePath;
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Cannot create backup file there: $e',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              }
                            } else {
                              String? selectedPath = await FilePicker.platform
                                  .saveFile(
                                    dialogTitle: 'Select Backup Location',
                                    fileName: 'notes_backup_archive.nba',
                                  );
                              if (selectedPath != null) {
                                try {
                                  prepareIncrementalBackupTarget(selectedPath);
                                  stows.backupFilePath.value = selectedPath;
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Cannot create backup file there: $e',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              }
                            }
                          } finally {
                            VaultAdapter.preventLock = false;
                          }
                        },
                      );
                    },
                  ),
                  ValueListenableBuilder(
                    valueListenable: stows.backupPassword,
                    builder: (context, pwd, _) {
                      return ListTile(
                        leading: const Icon(Icons.key),
                        title: const Text('Encryption Key'),
                        subtitle: Text(
                          pwd.toString().isEmpty
                              ? 'Not Set (Tap to configure)'
                              : 'Key is set (Tap to view/change)',
                        ),
                        onTap: _showBackupKeyDialog,
                      );
                    },
                  ),
                  ValueListenableBuilder(
                    valueListenable: stows.autoBackupIntervalMinutes,
                    builder: (context, interval, _) {
                      return ListTile(
                        leading: const Icon(Icons.update),
                        title: const Text('Auto-backup Interval'),
                        trailing: DropdownButton<int>(
                          value: interval,
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('Off')),
                            DropdownMenuItem(
                              value: 30,
                              child: Text('Every 30 Mins'),
                            ),
                            DropdownMenuItem(
                              value: 60,
                              child: Text('Every 1 Hour'),
                            ),
                            DropdownMenuItem(
                              value: 360,
                              child: Text('Every 6 Hours'),
                            ),
                            DropdownMenuItem(
                              value: 1440,
                              child: Text('Every 24 Hours'),
                            ),
                          ],
                          onChanged: (int? v) {
                            if (v != null)
                              stows.autoBackupIntervalMinutes.value = v;
                          },
                        ),
                      );
                    },
                  ),
                  ValueListenableBuilder(
                    valueListenable: stows.lastBackupTimestamp,
                    builder: (context, timestamp, _) {
                      final lastBackup = timestamp > 0
                          ? DateFormat.yMd().add_jms().format(
                              DateTime.fromMillisecondsSinceEpoch(timestamp),
                            )
                          : 'Never';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.history),
                            title: const Text('Last incremental backup'),
                            subtitle: Text(lastBackup),
                          ),
                          ListTile(
                            title: const Text(
                              'Backup now',
                              style: TextStyle(color: Colors.blue),
                            ),
                            subtitle: const Text(
                              'Runs immediately on this screen. Please wait until it finishes.',
                            ),
                            leading: const Icon(
                              Icons.backup,
                              color: Colors.blue,
                            ),
                            onTap: () => _runIncrementalBackupNow(context),
                          ),
                          ListTile(
                            title: const Text(
                              'Run in background',
                              style: TextStyle(color: Colors.blue),
                            ),
                            subtitle: const Text(
                              'Keep using the app while backup runs.',
                            ),
                            leading: const Icon(
                              Icons.schedule_send,
                              color: Colors.blue,
                            ),
                            onTap: () =>
                                _runIncrementalBackupBackground(context),
                          ),
                        ],
                      );
                    },
                  ),
                  ListTile(
                    title: const Text(
                      'Verify backup',
                      style: TextStyle(color: Colors.teal),
                    ),
                    subtitle: const Text(
                      'Decrypt the index and sample every file block without restoring.',
                    ),
                    leading: const Icon(
                      Icons.verified_user_outlined,
                      color: Colors.teal,
                    ),
                    onTap: () => _verifyIncrementalBackup(context),
                  ),
                  ListTile(
                    title: const Text(
                      'Restore Incremental Backup',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                    leading: const Icon(
                      Icons.cloud_download,
                      color: Colors.redAccent,
                    ),
                    onTap: () async {
                      if (stows.backupFilePath.value.isEmpty ||
                          stows.backupPassword.value.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Please select a target file and enter your key first.',
                            ),
                          ),
                        );
                        return;
                      }
                      try {
                        await BackupManager.restoreIncrementalBackup(
                          stows.backupFilePath.value,
                          stows.backupPassword.value,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Restore Complete!')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Restore failed: $e')),
                          );
                        }
                      }
                    },
                  ),
                  Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: const ExpansionTile(
                      leading: Icon(Icons.archive),
                      title: Text('Other Backup Options (Monolithic)'),
                      childrenPadding: EdgeInsets.zero,
                      children: [_VaultBackupTile()],
                    ),
                  ),
                ]),

                buildSection(t.settings.prefCategories.general, [
                  SettingsDropdown(
                    title: t.settings.prefLabels.locale,
                    icon: Icons.language,
                    pref: stows.locale,
                    options: [
                      ToggleButtonsOption('', Text(t.settings.systemLanguage)),
                      ...AppLocaleUtils.supportedLocales.map((locale) {
                        final localeCode = locale.toLanguageTag();
                        final localeName = localeNames[localeCode];
                        return ToggleButtonsOption(
                          localeCode,
                          Text(localeName ?? localeCode),
                        );
                      }),
                    ],
                  ),
                  SettingsSelection(
                    title: t.settings.prefLabels.appTheme,
                    iconBuilder: (i) {
                      if (i == ThemeMode.system.index)
                        return Icons.brightness_auto;
                      if (i == ThemeMode.light.index) return Icons.light_mode;
                      if (i == ThemeMode.dark.index) return Icons.dark_mode;
                      return null;
                    },
                    pref: _SettingsStows.appTheme,
                    optionsWidth: 60,
                    options: [
                      ToggleButtonsOption(
                        ThemeMode.system.index,
                        Icon(Icons.brightness_auto),
                      ),
                      ToggleButtonsOption(
                        ThemeMode.light.index,
                        Icon(Icons.light_mode),
                      ),
                      ToggleButtonsOption(
                        ThemeMode.dark.index,
                        Icon(Icons.dark_mode),
                      ),
                    ],
                  ),
                  SettingsSelection(
                    title: t.settings.prefLabels.layoutSize,
                    subtitle: switch (stows.layoutSize.value) {
                      LayoutSize.auto => t.settings.layoutSizes.auto,
                      LayoutSize.phone => t.settings.layoutSizes.phone,
                      LayoutSize.tablet => t.settings.layoutSizes.tablet,
                    },
                    afterChange: (_) => setState(() {}),
                    iconBuilder: (i) => switch (LayoutSize.values[i]) {
                      LayoutSize.auto => Icons.aspect_ratio,
                      LayoutSize.phone => Icons.smartphone,
                      LayoutSize.tablet => Icons.tablet,
                    },
                    pref: _SettingsStows.layoutSize,
                    optionsWidth: 60,
                    options: [
                      ToggleButtonsOption(
                        LayoutSize.auto.index,
                        Icon(Icons.aspect_ratio),
                      ),
                      ToggleButtonsOption(
                        LayoutSize.phone.index,
                        Icon(Icons.smartphone),
                      ),
                      ToggleButtonsOption(
                        LayoutSize.tablet.index,
                        Icon(Icons.tablet),
                      ),
                    ],
                  ),
                  if (Platform.isAndroid)
                    SettingsDirectorySelector(
                      title: t.settings.prefLabels.customDataDir,
                      icon: Icons.folder,
                    ),
                  if (Platform.isWindows ||
                      Platform.isLinux ||
                      Platform.isMacOS)
                    SettingsButton(
                      title: t.settings.openDataDir,
                      icon: Icons.folder_open,
                      onPressed: () {
                        if (Platform.isWindows) {
                          Process.run('explorer', [
                            FileManager.documentsDirectory,
                          ]);
                        } else if (Platform.isLinux) {
                          Process.run('xdg-open', [
                            FileManager.documentsDirectory,
                          ]);
                        } else if (Platform.isMacOS) {
                          Process.run('open', [FileManager.documentsDirectory]);
                        }
                      },
                    ),
                ]),

                buildSection(t.settings.prefCategories.writing, [
                  SettingsSwitch(
                    title: t.settings.prefLabels.disableEraserAfterUse,
                    subtitle: t.settings.prefDescriptions.disableEraserAfterUse,
                    icon: FontAwesomeIcons.eraser,
                    pref: stows.disableEraserAfterUse,
                  ),
                ]),

                buildSection(t.settings.noteInkDefaults.sectionTitle, [
                  SettingsButton(
                    title: t.settings.noteInkDefaults.changeNoteDefaults,
                    subtitle:
                        t.settings.noteInkDefaults.changeNoteDefaultsSubtitle,
                    icon: Icons.note_alt_outlined,
                    onPressed: () =>
                        context.push(RoutePaths.settingsNoteDefaults),
                  ),
                  SettingsButton(
                    title: t.settings.noteInkDefaults.changeInkDefaults,
                    subtitle:
                        t.settings.noteInkDefaults.changeInkDefaultsSubtitle,
                    icon: Icons.brush_outlined,
                    onPressed: () =>
                        context.push(RoutePaths.settingsInkDefaults),
                  ),
                ]),

                buildSection(t.settings.prefCategories.editor, [
                  SettingsSelection(
                    title: t.settings.prefLabels.editorToolbarAlignment,
                    subtitle:
                        t.settings.axisDirections[_SettingsStows
                            .editorToolbarAlignment
                            .value],
                    iconBuilder: (num i) {
                      if (i is! int || i >= _directionIcons.length) return null;
                      return _directionIcons[i];
                    },
                    pref: _SettingsStows.editorToolbarAlignment,
                    optionsWidth: 60,
                    options: [
                      for (final AxisDirection direction
                          in AxisDirection.values)
                        ToggleButtonsOption(
                          direction.index,
                          Icon(_directionIcons[direction.index]),
                        ),
                    ],
                    afterChange: (_) => setState(() {}),
                  ),
                  SettingsSwitch(
                    title: t.settings.prefLabels.editorAutoInvert,
                    iconBuilder: (b) =>
                        b ? Icons.invert_colors_on : Icons.invert_colors_off,
                    pref: stows.editorAutoInvert,
                  ),
                  SettingsSwitch(
                    title: t.settings.prefLabels.editorPromptRename,
                    subtitle: t.settings.prefDescriptions.editorPromptRename,
                    iconBuilder: (b) =>
                        b ? Icons.keyboard : Icons.keyboard_hide,
                    pref: stows.editorPromptRename,
                  ),
                  SettingsSwitch(
                    title: 'Thumbnail on autosave',
                    subtitle:
                        'Update note thumbnail when auto-saving. Turn off to reduce lag.',
                    icon: Icons.image,
                    pref: stows.thumbnailOnAutosave,
                  ),
                  SettingsSwitch(
                    title: t.settings.prefLabels.recentColorsDontSavePresets,
                    icon: Icons.palette,
                    pref: stows.recentColorsDontSavePresets,
                  ),
                  SettingsSelection(
                    title: t.settings.prefLabels.recentColorsLength,
                    icon: Icons.history,
                    pref: stows.recentColorsLength,
                    options: const [
                      ToggleButtonsOption(5, Text('5')),
                      ToggleButtonsOption(10, Text('10')),
                    ],
                  ),
                  SettingsSwitch(
                    title: t.settings.prefLabels.printPageIndicators,
                    subtitle: t.settings.prefDescriptions.printPageIndicators,
                    icon: Icons.numbers,
                    pref: stows.printPageIndicators,
                  ),
                ]),

                buildSection(t.settings.prefCategories.performance, [
                  SettingsSelection(
                    title: t.settings.prefLabels.maxImageSize,
                    subtitle: t.settings.prefDescriptions.maxImageSize,
                    icon: Icons.photo_size_select_large,
                    pref: stows.maxImageSize,
                    options: const [
                      ToggleButtonsOption(500.0, Text('500')),
                      ToggleButtonsOption(1000.0, Text('1000')),
                      ToggleButtonsOption(2000.0, Text('2000')),
                    ],
                  ),
                  SettingsSelection(
                    title: t.settings.prefLabels.shapeRecognitionDelay,
                    subtitle: t.settings.prefDescriptions.shapeRecognitionDelay,
                    icon: FontAwesomeIcons.shapes,
                    pref: stows.shapeRecognitionDelay,
                    options: [
                      const ToggleButtonsOption(500, Text('500ms')),
                      const ToggleButtonsOption(850, Text('850ms')),
                      const ToggleButtonsOption(1000, Text('1s')),
                      ToggleButtonsOption(
                        -1,
                        Text(t.settings.shapeRecognitionDisabled),
                      ),
                    ],
                  ),
                  SettingsSwitch(
                    title: 'Auto-solve Math',
                    subtitle: 'Automatically solve equations written with pen',
                    icon: Icons.calculate_outlined,
                    pref: stows.enableMathSolver,
                  ),
                  SettingsSwitch(
                    title: t.settings.prefLabels.strokeStabilization,
                    subtitle: t.settings.prefDescriptions.strokeStabilization,
                    icon: Icons.auto_fix_high,
                    pref: stows.strokeStabilization,
                  ),
                  ValueListenableBuilder(
                    valueListenable: stows.strokeStabilization,
                    builder: (context, enabled, _) {
                      if (!enabled) return const SizedBox.shrink();
                      return ValueListenableBuilder(
                        valueListenable: stows.strokeStabilizationAmount,
                        builder: (context, amount, _) {
                          return Column(
                            children: [
                              Divider(
                                height: 1,
                                indent: 56,
                                endIndent: 16,
                                color: colorScheme.outlineVariant.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 16,
                                  right: 16,
                                  top: 12,
                                  bottom: 12,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      t
                                          .settings
                                          .prefLabels
                                          .strokeStabilizationAmount,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Slider(
                                        value: amount,
                                        min: 0.0,
                                        max: 1.0,
                                        divisions: 20,
                                        label:
                                            '${(amount * 100).toStringAsFixed(0)}%',
                                        onChanged: (value) {
                                          stows
                                                  .strokeStabilizationAmount
                                                  .value =
                                              value;
                                        },
                                      ),
                                    ),
                                    SizedBox(
                                      width: 40,
                                      child: Text(
                                        '${(amount * 100).toStringAsFixed(0)}%',
                                        textAlign: TextAlign.right,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                  SettingsSwitch(
                    title: t.settings.prefLabels.strokePrediction,
                    subtitle: t.settings.prefDescriptions.strokePrediction,
                    icon: Icons.bolt_outlined,
                    pref: stows.strokePrediction,
                  ),
                  ValueListenableBuilder(
                    valueListenable: stows.strokePrediction,
                    builder: (context, predOn, _) {
                      if (!predOn) return const SizedBox.shrink();
                      return ValueListenableBuilder(
                        valueListenable: stows.strokePredictionAmount,
                        builder: (context, amount, _) {
                          return Column(
                            children: [
                              Divider(
                                height: 1,
                                indent: 56,
                                endIndent: 16,
                                color: colorScheme.outlineVariant.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 16,
                                  right: 16,
                                  top: 12,
                                  bottom: 12,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      t
                                          .settings
                                          .prefLabels
                                          .strokePredictionAmount,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Slider(
                                        value: amount,
                                        min: 0.0,
                                        max: 1.0,
                                        divisions: 20,
                                        label:
                                            '${(amount * 100).toStringAsFixed(0)}%',
                                        onChanged: (value) {
                                          stows.strokePredictionAmount.value =
                                              value;
                                        },
                                      ),
                                    ),
                                    SizedBox(
                                      width: 40,
                                      child: Text(
                                        '${(amount * 100).toStringAsFixed(0)}%',
                                        textAlign: TextAlign.right,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ]),

                buildSection(t.settings.prefCategories.advanced, [
                  SettingsButton(
                    title: t.logs.viewLogs,
                    subtitle: t.logs.debuggingInfo,
                    icon: Icons.receipt_long,
                    onPressed: () => context.push(RoutePaths.logs),
                  ),
                ]),

                const SizedBox(height: 60),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    stows.locale.removeListener(onChanged);
    super.dispose();
  }
}

class _VaultEncryptionSwitch extends StatefulWidget {
  @override
  State<_VaultEncryptionSwitch> createState() => _VaultEncryptionSwitchState();
}

class _VaultEncryptionSwitchState extends State<_VaultEncryptionSwitch> {
  bool _isMigrating = false;

  Future<void> _handleVaultToggle(bool newValue) async {
    if (_isMigrating) return;

    final wasEnabled = stows.localEncryptionEnabled.value;
    if (newValue == wasEnabled) return;

    setState(() {
      _isMigrating = true;
    });

    try {
      if (newValue) {
        await _enableEncryption();
      } else {
        await _disableEncryption();
      }
    } catch (e) {
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AdaptiveAlertDialog(
            title: Text(t.vault.migrationError),
            content: Text(t.vault.migrationErrorContent(error: e)),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context),
                child: Text(MaterialLocalizations.of(context).okButtonLabel),
              ),
            ],
          ),
        );

        stows.localEncryptionEnabled.value = wasEnabled;
      }
    } finally {
      if (mounted) {
        setState(() {
          _isMigrating = false;
        });
      }
    }
  }

  Future<void> _enableEncryption() async {
    final result = await showDialog<_VaultCredentials>(
      context: context,
      builder: (context) => const _VaultCreationDialog(),
    );

    if (result == null) {
      stows.localEncryptionEnabled.value = false;
      return;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _MigrationProgressDialog(),
    );

    try {
      final docDir = await FileManager.getDocumentsDirectory();
      final vaultRoot = p.join(docDir, 'saber_vault');

      final created = await VaultAdapter.instance.create(
        vaultRoot,
        result.password,
        kdfIter: result.kdfIter,
        pageSize: result.pageSize,
        scryptN: result.scryptN,
        scryptR: result.scryptR,
        scryptP: result.scryptP,
      );
      if (!created) {
        throw Exception('Failed to create vault');
      }

      final dir = Directory(docDir);
      if (dir.existsSync()) {
        await for (final entity in dir.list(recursive: true)) {
          if (entity is Directory) {
            final rel = p
                .relative(entity.path, from: dir.path)
                .replaceAll('\\', '/');
            if (rel.isNotEmpty && rel != '.')
              await VaultAdapter.instance.createFolder(rel);
          }
        }
      }

      final allFilesRaw = await FileManager.getAllFiles(
        includeExtensions: true,
        includeAssets: true,
      );
      final allFiles = allFilesRaw.where((f) {
        final name = p.basename(f);
        return !name.endsWith('.db') && !name.endsWith('.db-journal');
      }).toList();

      final success = await VaultAdapter.instance.migrateFromDisk(allFiles);
      if (!success) {
        throw Exception('Some files failed to migrate');
      }

      stows.localEncryptionEnabled.value = true;

      if (mounted) {
        Navigator.pop(context);
        await showDialog(
          context: context,
          builder: (context) => AdaptiveAlertDialog(
            title: Text(t.vault.vaultCreated),
            content: Text(t.vault.vaultCreatedContent),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context),
                child: Text(MaterialLocalizations.of(context).okButtonLabel),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        await VaultAdapter.instance.lock();
        rethrow;
      }
    }
  }

  Future<void> _disableEncryption() async {
    // SECURITY WARNING: Alert the user that disabling decrypts everything publicly.
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AdaptiveAlertDialog(
        title: const Text('Disable Encryption?'),
        content: const Text(
          'WARNING: Disabling the vault will extract all your notes and save them UNENCRYPTED on your device storage. Anyone with access to your device files will be able to read them.\n\nAre you sure you want to proceed?',
          style: TextStyle(color: Colors.redAccent),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Decrypt & Disable'),
          ),
        ],
      ),
    );

    if (confirm != true) {
      stows.localEncryptionEnabled.value = true;
      return;
    }

    if (!VaultAdapter.isUnlocked) {
      final creds = await showDialog<_VaultCredentials>(
        context: context,
        builder: (context) => const _VaultPasswordDialog(isCreating: false),
      );

      if (creds == null || creds.password.isEmpty) {
        stows.localEncryptionEnabled.value = true;
        return;
      }

      final docDir = await FileManager.getDocumentsDirectory();
      final vaultRoot = p.join(docDir, 'saber_vault');
      final unlocked = await VaultAdapter.instance.unlock(
        vaultRoot,
        creds.password,
      );
      if (!unlocked) {
        if (mounted) {
          await showDialog(
            context: context,
            builder: (context) => AdaptiveAlertDialog(
              title: Text(t.vault.incorrectPassword),
              content: Text(t.vault.incorrectPasswordMessage),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.pop(context),
                  child: Text(MaterialLocalizations.of(context).okButtonLabel),
                ),
              ],
            ),
          );
        }
        stows.localEncryptionEnabled.value = true;
        return;
      }
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _MigrationProgressDialog(),
    );

    try {
      final allFiles = await VaultAdapter.instance.getAllFiles();

      final folders = await VaultAdapter.instance.getFoldersByPrefix(
        '/',
        ensureTrailingSlash: true,
      );
      final docDir = await FileManager.getDocumentsDirectory();
      for (final folder in folders) {
        if (folder.isEmpty || folder == '/') continue;
        final relFolder = folder.startsWith('/') ? folder.substring(1) : folder;
        final dir = Directory(p.join(docDir, relFolder));
        if (!dir.existsSync()) dir.createSync(recursive: true);
      }

      final success = await VaultAdapter.instance.migrateToDisk(allFiles);
      if (!success) {
        throw Exception('Some files failed to migrate');
      }

      await VaultAdapter.instance.lock();

      final vaultDir = Directory(p.join(docDir, 'saber_vault'));
      if (vaultDir.existsSync()) {
        await vaultDir.delete(recursive: true);
      }

      stows.localEncryptionEnabled.value = false;

      if (mounted) {
        Navigator.pop(context);
        await showDialog(
          context: context,
          builder: (context) => AdaptiveAlertDialog(
            title: Text(t.vault.vaultDisabled),
            content: Text(t.vault.vaultDisabledContent),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context),
                child: Text(MaterialLocalizations.of(context).okButtonLabel),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        rethrow;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: stows.localEncryptionEnabled,
      builder: (context, isEnabled, _) {
        return GestureDetector(
          onLongPress: () {
            SettingsPage.showResetDialog(
              context: context,
              pref: stows.localEncryptionEnabled,
              prefTitle: 'Local Encryption (Vault)',
            );
          },
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              vertical: 4,
              horizontal: 16,
            ),
            leading: AnimatedSwitcher(
              duration: const Duration(milliseconds: 100),
              child: Icon(
                isEnabled ? Icons.lock : Icons.lock_open,
                key: ValueKey(isEnabled),
              ),
            ),
            title: Text(
              'Local Encryption (Vault)',
              style: TextStyle(
                fontSize: 18,
                fontStyle: isEnabled != false ? FontStyle.italic : null,
              ),
            ),
            subtitle: Text(
              isEnabled
                  ? 'Your notes are encrypted in a vault. Enter password on app start.'
                  : 'Encrypt all notes in a password-protected vault.',
              style: const TextStyle(fontSize: 13),
            ),
            onTap: _isMigrating ? null : () => _handleVaultToggle(!isEnabled),
            trailing: _isMigrating
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Switch.adaptive(
                    value: isEnabled,
                    onChanged: _handleVaultToggle,
                  ),
          ),
        );
      },
    );
  }
}

class _VaultCredentials {
  final String password;
  final int kdfIter;
  final int pageSize;
  final int scryptN;
  final int scryptR;
  final int scryptP;

  _VaultCredentials(
    this.password, {
    this.kdfIter = 256000,
    this.pageSize = 4096,
    this.scryptN = 16384,
    this.scryptR = 8,
    this.scryptP = 1,
  });
}

class _VaultCreationDialog extends StatefulWidget {
  const _VaultCreationDialog({super.key});

  @override
  State<_VaultCreationDialog> createState() => _VaultCreationDialogState();
}

class _VaultCreationDialogState extends State<_VaultCreationDialog> {
  final _controller = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscureText = true;
  bool _obscureConfirmText = true;
  bool _showAdvanced = false;

  int _kdfIter = 256000;
  int _pageSize = 4096;
  int _scryptN = 16384;

  @override
  void dispose() {
    _controller.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool _validatePassword() {
    if (_controller.text.isEmpty) return false;
    if (_controller.text != _confirmController.text) return false;
    if (_controller.text.length < 6) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveAlertDialog(
      title: Text(t.vault.createVault),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.vault.createVaultContent, style: TextStyle(fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              obscureText: _obscureText,
              autofocus: true,
              decoration: InputDecoration(
                labelText: t.vault.password,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureText ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscureText = !_obscureText),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirmController,
              obscureText: _obscureConfirmText,
              decoration: InputDecoration(
                labelText: t.vault.confirmPassword,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmText
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                  onPressed: () => setState(
                    () => _obscureConfirmText = !_obscureConfirmText,
                  ),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_controller.text.isNotEmpty &&
                _confirmController.text.isNotEmpty &&
                _controller.text != _confirmController.text)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  t.export.passwordsDoNotMatch,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            if (_controller.text.isNotEmpty && _controller.text.length < 6)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  t.vault.passwordMinLength,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () => setState(() => _showAdvanced = !_showAdvanced),
              child: Row(
                children: [
                  Icon(
                    _showAdvanced
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 20,
                  ),
                  Text(
                    t.vault.advancedSecurityOptions,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            if (_showAdvanced)
              _VaultAdvancedOptions(
                kdfIter: _kdfIter,
                pageSize: _pageSize,
                scryptN: _scryptN,
                onKdfChanged: (v) => setState(() => _kdfIter = v),
                onPageSizeChanged: (v) => setState(() => _pageSize = v),
                onScryptNChanged: (v) => setState(() => _scryptN = v),
              ),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context, null),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        CupertinoDialogAction(
          onPressed: _validatePassword()
              ? () {
                  Navigator.pop(
                    context,
                    _VaultCredentials(
                      _controller.text,
                      kdfIter: _kdfIter,
                      pageSize: _pageSize,
                      scryptN: _scryptN,
                    ),
                  );
                }
              : null,
          isDefaultAction: true,
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}

class _VaultAdvancedOptions extends StatelessWidget {
  final int kdfIter;
  final int pageSize;
  final int scryptN;
  final ValueChanged<int> onKdfChanged;
  final ValueChanged<int> onPageSizeChanged;
  final ValueChanged<int> onScryptNChanged;

  const _VaultAdvancedOptions({
    super.key,
    required this.kdfIter,
    required this.pageSize,
    required this.scryptN,
    required this.onKdfChanged,
    required this.onPageSizeChanged,
    required this.onScryptNChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text(
          'Scrypt N-Factor (Vault KDF Strength)',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        DropdownButton<int>(
          isExpanded: true,
          value: scryptN,
          items: [
            DropdownMenuItem(value: 16384, child: Text(t.vault.pbkdf16384)),
            DropdownMenuItem(value: 32768, child: Text(t.vault.pbkdf32768)),
            DropdownMenuItem(value: 65536, child: Text(t.vault.pbkdf65536)),
            DropdownMenuItem(value: 131072, child: Text(t.vault.pbkdf131072)),
          ],
          onChanged: (v) {
            if (v != null) onScryptNChanged(v);
          },
        ),
        const SizedBox(height: 8),
        const Text(
          'Index KDF Iterations (SQLCipher)',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        Text(
          'Current: $kdfIter',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        Slider(
          value: kdfIter.toDouble(),
          min: 64000,
          max: 600000,
          label: '$kdfIter',
          onChanged: (v) => onKdfChanged(v.toInt()),
        ),
        const SizedBox(height: 8),
        const Text(
          'Page Size (Performance)',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        DropdownButton<int>(
          isExpanded: true,
          value: pageSize,
          items: [
            DropdownMenuItem(value: 1024, child: Text(t.vault.block1024)),
            DropdownMenuItem(value: 4096, child: Text(t.vault.block4096)),
            DropdownMenuItem(value: 8192, child: Text(t.vault.block8192)),
            DropdownMenuItem(value: 65536, child: Text(t.vault.block65536)),
          ],
          onChanged: (v) {
            if (v != null) onPageSizeChanged(v);
          },
        ),
        const SizedBox(height: 4),
        const Text(
          'Cipher: AES-256-CBC (SQLCipher Standard)',
          style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }
}

class _VaultBackupTile extends StatefulWidget {
  const _VaultBackupTile({super.key});

  @override
  State<_VaultBackupTile> createState() => _VaultBackupTileState();
}

class _VaultBackupTileState extends State<_VaultBackupTile> {
  bool _isLoading = false;

  Future<String?> _pickBackupDestination(
    BuildContext context, {
    required bool isVault,
  }) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final tempDir = await getTemporaryDirectory();
      final fileName = isVault
          ? 'notes_vault_backup.nba'
          : 'notes_data_backup.nba';
      return p.join(tempDir.path, fileName);
    }

    VaultAdapter.preventLock = true;
    try {
      return await FilePicker.platform.saveFile(
        dialogTitle: isVault ? 'Backup Vault' : 'Backup Data',
        fileName: isVault ? 'notes_vault_backup.nba' : 'notes_data_backup.nba',
        type: FileType.custom,
        allowedExtensions: ['nba'],
      );
    } finally {
      VaultAdapter.preventLock = false;
    }
  }

  Future<String?> _askForBackupPassword(
    BuildContext context, {
    required bool isRestore,
  }) async {
    final passwordCtrl = TextEditingController();
    bool obscure = true;
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  width: 400,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.grey.withOpacity(0.3),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 40,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isRestore ? 'Decrypt Backup' : 'Encrypt Backup',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isRestore
                            ? 'Enter the password used to encrypt this backup file. Leave blank if it is unencrypted.'
                            : 'Create a password to securely encrypt this backup. Leave blank for an unencrypted backup.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: passwordCtrl,
                        obscureText: obscure,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'Password (Optional)',
                          filled: true,
                          fillColor: Colors.grey.withOpacity(0.1),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscure ? Icons.visibility : Icons.visibility_off,
                            ),
                            onPressed: () => setState(() => obscure = !obscure),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, null),
                            child: Text(
                              MaterialLocalizations.of(
                                context,
                              ).cancelButtonLabel,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey.shade800,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () =>
                                Navigator.pop(context, passwordCtrl.text),
                            child: Text(
                              isRestore ? 'Unlock / Continue' : 'Create Backup',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    passwordCtrl.dispose();
    return result;
  }

  Future<void> _backup(BuildContext context) async {
    final isVault = stows.localEncryptionEnabled.value;

    final destination = await _pickBackupDestination(context, isVault: isVault);
    if (destination == null) return;

    final password = await _askForBackupPassword(context, isRestore: false);
    if (password == null) return;

    setState(() => _isLoading = true);
    BackupManager.status.value = const BackupStatus(isRunning: true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _BackupProgressDialog(),
    );

    void reportMonolith(double progress, String message, {int totalNotes = 0}) {
      BackupManager.status.value = BackupStatus(
        isRunning: true,
        progress: progress,
        currentFile: message,
        totalNotes: totalNotes,
      );
    }

    WakelockPlus.enable();
    try {
      File backupFile;
      if (isVault) {
        backupFile = await VaultAdapter.instance.createBackupArchive(
          destination,
          password,
          onProgress: reportMonolith,
        );
      } else {
        backupFile = await FileManager.createDataBackupArchive(
          destination,
          password,
          onProgress: reportMonolith,
        );
      }

      if (mounted) Navigator.pop(context);

      if (Platform.isAndroid || Platform.isIOS) {
        final box = context.findRenderObject() as RenderBox?;
        await Share.shareXFiles(
          [XFile(backupFile.path)],
          sharePositionOrigin: box != null
              ? box.localToGlobal(Offset.zero) & box.size
              : null,
        );
      } else {
        if (mounted) {
          await showDialog(
            context: context,
            builder: (ctx) => AdaptiveAlertDialog(
              title: Text(t.vault.backupComplete),
              content: Text(
                isVault
                    ? t.vault.backupCompleteVault
                    : t.vault.backupCompleteData,
              ),
              actions: [
                CupertinoDialogAction(
                  child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) _showError(context, t.vault.backupFailed(error: e));
    } finally {
      WakelockPlus.disable();
      BackupManager.status.value = const BackupStatus(isRunning: false);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _restore(BuildContext context) async {
    VaultAdapter.preventLock = true;
    final result;
    try {
      result = await FilePicker.platform.pickFiles(
        dialogTitle: t.vault.restoreBackup,
        type: FileType.custom,
        allowedExtensions: ['nba'],
      );
    } finally {
      VaultAdapter.preventLock = false;
    }
    if (result == null || result.files.isEmpty) return;
    final backupPath = result.files.single.path!;

    final password = await _askForBackupPassword(context, isRestore: true);
    if (password == null) return;

    bool isDataBackup = false;
    try {
      isDataBackup = await _checkIfDataBackupWithPassword(backupPath, password);
    } catch (e) {
      if (mounted) _showError(context, 'Invalid Password or Corrupted Backup');
      return;
    }
    final confirmTitle = isDataBackup
        ? t.vault.restoreData
        : t.vault.restoreVault;
    final confirmMessage = isDataBackup
        ? t.vault.restoreDataConfirm
        : t.vault.restoreVaultConfirm;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AdaptiveAlertDialog(
        title: Text(confirmTitle),
        content: Text(confirmMessage),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isLoading = true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _MigrationProgressDialog(),
    );

    WakelockPlus.enable();
    try {
      if (isDataBackup) {
        await FileManager.restoreDataBackupArchive(backupPath, password);
        if (mounted) Navigator.pop(context);
        if (mounted) {
          await showDialog(
            context: context,
            builder: (ctx) => AdaptiveAlertDialog(
              title: Text(t.vault.restoreComplete),
              content: Text(t.vault.restoreCompleteData),
              actions: [
                CupertinoDialogAction(
                  child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
          );
        }
      } else {
        await VaultAdapter.instance.restoreBackupArchive(backupPath, password);
        stows.localEncryptionEnabled.value = true;
        if (mounted) Navigator.pop(context);
        if (mounted) {
          await showDialog(
            context: context,
            builder: (ctx) => AdaptiveAlertDialog(
              title: Text(t.vault.restoreComplete),
              content: Text(t.vault.restoreCompleteVault),
              actions: [
                CupertinoDialogAction(
                  child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
          );
          if (context.mounted) {
            context.go(RoutePaths.login);
          }
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) _showError(context, 'Restore Failed: $e');
    } finally {
      WakelockPlus.disable();
      BackupManager.status.value = const BackupStatus(isRunning: false);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _checkIfDataBackupWithPassword(
    String path,
    String password,
  ) async {
    return await compute(_isolateCheckBackupTypeTask, {
      'path': path,
      'password': password,
    });
  }

  void _showError(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AdaptiveAlertDialog(
        title: Text(t.vault.error),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isVault = stows.localEncryptionEnabled.value;
    return Column(
      children: [
        SettingsButton(
          title: isVault ? t.vault.backupVault : t.vault.backupData,
          subtitle: isVault
              ? t.vault.backupVaultSubtitle
              : t.vault.backupDataSubtitle,
          icon: Icons.archive_outlined,
          onPressed: _isLoading ? null : () => _backup(context),
        ),
        SettingsButton(
          title: isVault ? t.vault.restoreVault : t.vault.restoreData,
          subtitle: isVault
              ? t.vault.restoreVaultSubtitle
              : t.vault.restoreDataSubtitle,
          icon: Icons.restore,
          onPressed: _isLoading ? null : () => _restore(context),
        ),
      ],
    );
  }
}

class _VaultPasswordDialog extends StatefulWidget {
  final bool isCreating;
  final String? title;
  const _VaultPasswordDialog({required this.isCreating, this.title});
  @override
  State<_VaultPasswordDialog> createState() => _VaultPasswordDialogState();
}

class _VaultPasswordDialogState extends State<_VaultPasswordDialog> {
  final _controller = TextEditingController();
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    return AdaptiveAlertDialog(
      title: Text(widget.title ?? 'Unlock Vault'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your vault password.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              obscureText: _obscureText,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureText ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscureText = !_obscureText),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context, null),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        CupertinoDialogAction(
          onPressed: () =>
              Navigator.pop(context, _VaultCredentials(_controller.text)),
          isDefaultAction: true,
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}

class _VaultSecurityStatus extends StatelessWidget {
  const _VaultSecurityStatus({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: stows.localEncryptionEnabled,
      builder: (context, isEnabled, _) {
        if (!isEnabled || !VaultAdapter.isUnlocked) {
          return const SizedBox.shrink();
        }

        return FutureBuilder<Map<String, String>>(
          future: VaultAdapter.instance.getSecuritySettings(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();

            final data = snapshot.data!;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.security,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Encryption Status: ${data['Status'] ?? 'Unknown'}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildInfoRow('Cipher', data['Cipher']),
                  _buildInfoRow('KDF', data['KDF']),
                  _buildInfoRow('Salt Status', data['Salt Status']),
                  _buildInfoRow('Index Page Size', data['Index Page Size']),
                  _buildInfoRow(
                    'Index KDF Iterations',
                    data['Index KDF Iterations'],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(
            value ?? '-',
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupProgressDialog extends StatelessWidget {
  const _BackupProgressDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  child: ValueListenableBuilder<BackupStatus>(
                    valueListenable: BackupManager.status,
                    builder: (context, status, _) {
                      final percent = (status.progress * 100)
                          .clamp(0, 100)
                          .round();
                      final file = status.currentFile.trim().isEmpty
                          ? 'Preparing...'
                          : status.currentFile;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Content is being backed up. Please wait.',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (status.totalNotes > 0) ...[
                            const SizedBox(height: 8),
                            Text(
                              '${status.totalNotes} notes in this backup',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Text(
                            '$percent%',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(file, style: theme.textTheme.bodyMedium),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MigrationProgressDialog extends StatelessWidget {
  const _MigrationProgressDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AdaptiveAlertDialog(
      title: Text(t.vault.migratingFiles),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(t.vault.migratingFilesMessage),
        ],
      ),
      actions: [],
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({super.key});

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();
  bool _obscureText = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveAlertDialog(
      title: Text(t.vault.encryptionPassword),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Enter the password used to encrypt/decrypt your local notes. '
            'If this session key is lost, you will need to re-enter it to access your files.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            obscureText: _obscureText,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Password',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureText ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () {
                  setState(() {
                    _obscureText = !_obscureText;
                  });
                },
              ),
            ),
          ),
        ],
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context, null),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        CupertinoDialogAction(
          onPressed: () {
            Navigator.pop(context, _controller.text);
          },
          isDefaultAction: true,
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}
