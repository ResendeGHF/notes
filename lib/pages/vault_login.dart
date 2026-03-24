// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:path/path.dart' as p;
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
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.lock, size: 64, color: colorScheme.primary),
              const SizedBox(height: 32),
              Text(
                t.vault.vaultLocked,
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                t.vault.vaultLockedMessage,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              ValueListenableBuilder<int>(
                valueListenable: App.pendingImportCount,
                builder: (context, count, _) {
                  if (count <= 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.file_download,
                            color: colorScheme.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              t.vault.filesWaitingToImport(count: count),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _passwordController,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: t.vault.password,
                  border: const OutlineInputBorder(),
                  errorText: _error,
                  suffixIcon: _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                ),
                onSubmitted: (_) => _unlock(),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isLoading ? null : _unlock,
                child: Text(t.vault.unlock),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
