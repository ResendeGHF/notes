// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/services/vlm/page_latex_vlm_service.dart';
import 'package:saber/services/vlm/vlm_model_catalog.dart';

/// Rows for the settings "AI models" section: install, uninstall, download
/// progress and default-model selection for on-device vision transcription.
/// Accepts an injected [service] for tests; production uses the real one.
class VlmModelTiles extends StatefulWidget {
  const VlmModelTiles({super.key, PageLatexVlmService? service})
    : _service = service;

  final PageLatexVlmService? _service;

  @override
  State<VlmModelTiles> createState() => _VlmModelTilesState();
}

class _EntryState {
  _EntryState({required this.installed, required this.unsupported});

  bool installed;
  bool unsupported;
  bool downloading = false;
  int progress = 0;
  String? error;
}

class _VlmModelTilesState extends State<VlmModelTiles> {
  late final PageLatexVlmService _service =
      widget._service ?? PageLatexVlmService();

  final Map<String, _EntryState> _states = {
    for (final entry in vlmTranscriptionModels)
      entry.id: _EntryState(installed: false, unsupported: false),
  };
  final Map<String, VlmDownloadHandle> _downloads = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    for (final handle in _downloads.values) {
      handle.cancel();
    }
    super.dispose();
  }

  Future<void> _refresh() async {
    for (final entry in vlmTranscriptionModels) {
      final state = _states[entry.id]!;
      if (state.downloading) continue;
      try {
        final readiness = await _service.readiness(entry);
        if (!mounted) return;
        setState(() {
          state.installed = readiness == VlmReadiness.ready;
          state.unsupported = readiness == VlmReadiness.unsupported;
          state.error = null;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => state.installed = false);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _download(VlmModelEntry entry) async {
    final state = _states[entry.id]!;
    setState(() {
      state.downloading = true;
      state.progress = 0;
      state.error = null;
    });
    final handle = _service.downloadModel(
      entry,
      onProgress: (p) {
        if (mounted) setState(() => state.progress = p.clamp(0, 100));
      },
    );
    _downloads[entry.id] = handle;
    try {
      await handle.done;
      if (!mounted) return;
      setState(() {
        state.downloading = false;
        state.installed = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        state.downloading = false;
        if (!isVlmDownloadCancelled(e)) {
          state.error = t.editor.vlmModels.downloadFailed(error: e);
        }
      });
    } finally {
      _downloads.remove(entry.id);
    }
  }

  void _cancelDownload(VlmModelEntry entry) {
    _downloads.remove(entry.id)?.cancel();
    if (mounted) {
      setState(() {
        final state = _states[entry.id]!;
        state.downloading = false;
        state.progress = 0;
      });
    }
  }

  Future<void> _uninstall(VlmModelEntry entry) async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t.editor.vlmModels.uninstallTitle),
        content: Text(
          t.editor.vlmModels.uninstallMessage(name: entry.displayName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(t.editor.vlmModels.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.uninstallModel(entry);
      if (stows.vlmPreferredModelId.value == entry.id) {
        stows.vlmPreferredModelId.value = smolVlm2.id;
      }
      if (!mounted) return;
      setState(() => _states[entry.id]!.installed = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ListTile(
        leading: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: null,
      );
    }
    return ValueListenableBuilder<String>(
      valueListenable: stows.vlmPreferredModelId,
      builder: (context, preferredId, _) {
        return Column(
          children: [
            for (var i = 0; i < vlmTranscriptionModels.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              _tile(vlmTranscriptionModels[i], preferredId),
            ],
          ],
        );
      },
    );
  }

  Widget _tile(VlmModelEntry entry, String preferredId) {
    final tModels = t.editor.vlmModels;
    final state = _states[entry.id]!;
    final isDefault = preferredId == entry.id;

    final String subtitle;
    if (state.unsupported) {
      subtitle = tModels.unsupported;
    } else if (state.error != null) {
      subtitle = state.error!;
    } else if (state.downloading) {
      subtitle = tModels.downloading(progress: state.progress);
    } else if (state.installed) {
      subtitle = tModels.installed(size: entry.sizeLabel);
    } else {
      subtitle = tModels.notInstalled(size: entry.sizeLabel);
    }

    return ListTile(
      leading: const Icon(Icons.smart_toy_outlined),
      title: Text(
        isDefault
            ? '${entry.displayName} · ${tModels.isDefault}'
            : entry.displayName,
      ),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.downloading) ...[
            Text('${state.progress}%'),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: t.common.cancel,
              onPressed: () => _cancelDownload(entry),
            ),
          ] else if (state.installed && !state.unsupported) ...[
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: tModels.uninstall,
              onPressed: () => _uninstall(entry),
            ),
            Radio<String>(
              value: entry.id,
              groupValue: preferredId,
              onChanged: (value) {
                if (value != null) stows.vlmPreferredModelId.value = value;
              },
            ),
          ] else if (!state.unsupported) ...[
            FilledButton.tonal(
              onPressed: () => _download(entry),
              child: Text(tModels.download),
            ),
          ],
        ],
      ),
    );
  }
}
