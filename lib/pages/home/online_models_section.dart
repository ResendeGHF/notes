// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/services/online/online_model_catalog.dart';
import 'package:saber/services/online/online_transcription_service.dart';

/// Rows for the settings "AI models" section covering online transcription
/// providers: backend switch, provider picker, API key, model/endpoint
/// overrides and the retention note. Accepts injected collaborators for tests.
class OnlineModelTiles extends StatefulWidget {
  const OnlineModelTiles({super.key, OnlineKeyStore? keyStore})
    : _keyStore = keyStore;

  final OnlineKeyStore? _keyStore;

  @override
  State<OnlineModelTiles> createState() => _OnlineModelTilesState();
}

class _OnlineModelTilesState extends State<OnlineModelTiles> {
  OnlineKeyStore get _keys => widget._keyStore ?? OnlineKeyStore();

  String? _keyLoadedFor;
  String? _keyLoadingFor;
  bool _hasKey = false;

  void _refreshKey(String providerId) {
    _keyLoadingFor = providerId;
    _keys.readKey(providerId).then((key) {
      if (!mounted) return;
      if (_keyLoadedFor == providerId) return;
      _keyLoadedFor = providerId;
      _keyLoadingFor = null;
      setState(() => _hasKey = key != null && key.trim().isNotEmpty);
    });
  }

  Future<void> _editKey(OnlineProviderPreset preset) async {
    final ctrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t.editor.onlineModels.editKeyTitle),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            hintText: t.editor.onlineModels.keyFieldHint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(t.common.save),
          ),
        ],
      ),
    );
    final value = ctrl.text.trim();
    // The exit transition still builds the field after pop; releasing the
    // controller only once it is certainly unmounted.
    Future.delayed(const Duration(milliseconds: 400), () {
      try {
        ctrl.dispose();
      } catch (_) {}
    });
    if (saved != true || !mounted) return;
    try {
      await _keys.writeKey(preset.id, value);
    } catch (_) {
      if (!mounted) return;
    }
    if (!mounted) return;
    _keyLoadedFor = null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.editor.onlineModels.keySaved)),
    );
    setState(() {});
  }

  Future<void> _clearKey(OnlineProviderPreset preset) async {
    await _keys.deleteKey(preset.id);
    if (!mounted) return;
    _keyLoadedFor = null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.editor.onlineModels.keyCleared)),
    );
    setState(() {});
  }

  Future<void> _editTextPref({
    required String title,
    required String hint,
    required String initial,
    required Future<void> Function(String value) onSave,
  }) async {
    final ctrl = TextEditingController(text: initial);
    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(t.common.save),
          ),
        ],
      ),
    );
    final value = ctrl.text.trim();
    Future.delayed(const Duration(milliseconds: 400), () {
      try {
        ctrl.dispose();
      } catch (_) {}
    });
    if (saved != true || !mounted) return;
    await onSave(value);
    if (mounted) setState(() {});
  }

  Future<void> _pickProvider(OnlineProviderPreset current) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t.editor.onlineModels.provider),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final preset in onlineProviderPresets)
                  RadioListTile<String>(
                    value: preset.id,
                    groupValue: current.id,
                    title: Text(preset.displayName),
                    subtitle: Text(preset.retentionNote),
                    onChanged: (value) => Navigator.pop(c, value),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(t.common.cancel),
          ),
        ],
      ),
    );
    if (picked != null && mounted) {
      stows.onlineProviderId.value = picked;
      _keyLoadedFor = null;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final tOnline = t.editor.onlineModels;
    return ValueListenableBuilder<String>(
      valueListenable: stows.latexBackend,
      builder: (context, backend, _) {
        return ValueListenableBuilder<String>(
          valueListenable: stows.onlineProviderId,
          builder: (context, providerId, _) {
            final preset = onlinePresetForId(providerId);
            final online = backend == 'online';
            if (_keyLoadedFor != preset.id &&
                _keyLoadingFor != preset.id &&
                preset.needsKey) {
              _refreshKey(preset.id);
            }
            final customModel = stows.onlineModel.value.trim();
            final customBase = stows.onlineBaseUrl.value.trim();
            return Column(
              children: [
                RadioListTile<String>(
                  value: 'ondevice',
                  groupValue: backend,
                  title: Text(tOnline.backendOnDevice),
                  subtitle: Text(tOnline.backendOnDeviceSubtitle),
                  onChanged: (value) {
                    if (value != null) stows.latexBackend.value = value;
                  },
                ),
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
                RadioListTile<String>(
                  value: 'online',
                  groupValue: backend,
                  title: Text(tOnline.backendOnline),
                  subtitle: Text(tOnline.backendOnlineSubtitle),
                  onChanged: (value) {
                    if (value != null) stows.latexBackend.value = value;
                  },
                ),
                if (online) ...[
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                  ListTile(
                    leading: const Icon(Icons.cloud_outlined),
                    title: Text(tOnline.provider),
                    subtitle: Text(preset.displayName),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _pickProvider(preset),
                  ),
                  if (preset.needsKey)
                    ListTile(
                      leading: const Icon(Icons.key_outlined),
                      title: Text(tOnline.apiKey),
                      subtitle: Text(
                        _hasKey ? tOnline.apiKeySet : tOnline.apiKeyMissing,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_hasKey)
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: t.common.delete,
                              onPressed: () => _clearKey(preset),
                            ),
                          FilledButton.tonal(
                            key: const ValueKey('online-key-edit'),
                            onPressed: () => _editKey(preset),
                            child: Text(
                              _hasKey ? tOnline.editKeyTitle : tOnline.apiKey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ListTile(
                    leading: const Icon(Icons.smart_toy_outlined),
                    title: Text(tOnline.model),
                    subtitle: Text(
                      customModel.isEmpty
                          ? preset.defaultModel.isEmpty
                                ? tOnline.modelHint
                                : preset.defaultModel
                          : customModel,
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => _editTextPref(
                      title: tOnline.model,
                      hint: tOnline.modelHint,
                      initial: customModel,
                      onSave: (value) async {
                        stows.onlineModel.value = value;
                      },
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.link_outlined),
                    title: Text(tOnline.baseUrl),
                    subtitle: Text(
                      customBase.isEmpty
                          ? (preset.baseUrl.isEmpty
                                ? tOnline.baseUrlHint
                                : preset.baseUrl)
                          : customBase,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => _editTextPref(
                      title: tOnline.baseUrl,
                      hint: tOnline.baseUrlHint,
                      initial: customBase,
                      onSave: (value) async {
                        stows.onlineBaseUrl.value = value;
                      },
                    ),
                  ),
                  if (preset.id == 'custom' && customBase.isEmpty)
                    ListTile(
                      leading: const Icon(
                        Icons.warning_amber_outlined,
                        color: Colors.orange,
                      ),
                      title: Text(tOnline.customUrlRequired),
                    ),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: Text(tOnline.retentionTitle),
                    subtitle: Text(preset.retentionNote),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}
