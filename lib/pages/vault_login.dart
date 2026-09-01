// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/main.dart';
import 'package:saber/services/vault_adapter.dart';

class VaultLoginPage extends StatefulWidget {
  const VaultLoginPage({super.key});

  @override
  State<VaultLoginPage> createState() => _VaultLoginPageState();
}

class _VaultLoginPageState extends State<VaultLoginPage> {
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final password = _passwordController.text;
    if (password.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    bool success = false;
    try {

      final docDir = await FileManager.getDocumentsDirectory();
      final vaultPath = p.join(docDir, 'saber_vault');

      success = await VaultAdapter.instance.unlock(vaultPath, password);
    } catch (e) {

      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = t.vault.failedToInit;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      if (success) {

        context.go(RoutePaths.home);

        if (App.pendingImports.isNotEmpty) {

          Future.delayed(const Duration(milliseconds: 100), () {
            App.processPendingImports();
          });
        }
      } else {
        setState(() {
          _error = t.vault.incorrectOrCorrupted;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              elevation: 0,
              color: colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.lock_rounded,
                          size: 36,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      t.vault.vaultLocked,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t.vault.vaultLockedMessage,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable: App.pendingImportCount,
                      builder: (context, count, _) {
                        if (count <= 0) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.download_rounded,
                                  color: colorScheme.onSecondaryContainer,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    t.vault.filesWaitingToImport(count: count),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSecondaryContainer,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: t.vault.password,
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        errorText: _error,
                        suffixIcon: _isLoading
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : null,
                      ),
                      onSubmitted: (_) => _unlock(),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _isLoading ? null : _unlock,
                      child: Text(t.vault.unlock),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
