// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:saber/components/home/home_toolbar_chrome.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/pages/editor/editor.dart';

Future<void> showPropertiesForFile(
  BuildContext context,
  String filePath,
) async {

  final coreInfo = await EditorCoreInfo.loadFromFilePath(
    filePath,
    readOnly: true,
    onlyFirstPage: true,
  );
  if (!context.mounted) return;
  await showNotePropertiesDialog(context, coreInfo);
}

String _formatDuration(int milliseconds) {
  final duration = Duration(milliseconds: milliseconds);
  return duration.inHours > 0
      ? '${duration.inHours}h ${duration.inMinutes.remainder(60)}m'
      : '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
}

Future<void> showNotePropertiesDialog(
  BuildContext context,
  EditorCoreInfo coreInfo,
) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  final dateFormat = DateFormat('MMM dd, yyyy - HH:mm');
  final creation = coreInfo.creationDate > 0
      ? dateFormat.format(
          DateTime.fromMillisecondsSinceEpoch(coreInfo.creationDate),
        )
      : 'Unknown';
  final modified = coreInfo.lastModification > 0
      ? dateFormat.format(
          DateTime.fromMillisecondsSinceEpoch(coreInfo.lastModification),
        )
      : 'Unknown';
  final accessed = coreInfo.lastAccess > 0
      ? dateFormat.format(
          DateTime.fromMillisecondsSinceEpoch(coreInfo.lastAccess),
        )
      : 'Unknown';
  final timeSpentStr = _formatDuration(coreInfo.totalTimeSpent);
  final timeSpentEditingStr = _formatDuration(coreInfo.totalTimeSpentEditing);
  final locationStr = coreInfo.location ?? 'Unknown';

  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _NotePropertiesDialogContent(
            coreInfo: coreInfo,
            creation: creation,
            modified: modified,
            accessed: accessed,
            timeSpentStr: timeSpentStr,
            timeSpentEditingStr: timeSpentEditingStr,
            locationStr: locationStr,
            isDark: isDark,
          ),
        ),
      ),
    ),
  );
}

class _NotePropertiesDialogContent extends StatefulWidget {
  final EditorCoreInfo coreInfo;
  final String creation;
  final String modified;
  final String accessed;
  final String timeSpentStr;
  final String timeSpentEditingStr;
  final String locationStr;
  final bool isDark;

  const _NotePropertiesDialogContent({
    required this.coreInfo,
    required this.creation,
    required this.modified,
    required this.accessed,
    required this.timeSpentStr,
    required this.timeSpentEditingStr,
    required this.locationStr,
    required this.isDark,
  });

  @override
  State<_NotePropertiesDialogContent> createState() =>
      _NotePropertiesDialogContentState();
}

class _NotePropertiesDialogContentState
    extends State<_NotePropertiesDialogContent> {
  String? _basePath;
  int? _fileSize;

  @override
  void initState() {
    super.initState();
    _loadAsync();
  }

  Future<void> _loadAsync() async {
    final ext = await FileManager.doesFileExist(
          widget.coreInfo.filePath + Editor.extensionOldJson,
        )
        ? Editor.extensionOldJson
        : Editor.extension;
    final basePath = widget.coreInfo.filePath + ext;

    if (!mounted) return;
    setState(() => _basePath = basePath);

    final fileSize = await FileManager.getNoteBundleSizeBytes(
      widget.coreInfo.filePath,
    );

    if (mounted) setState(() => _fileSize = fileSize);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sizeStr = _fileSize != null
        ? (_fileSize! > 1024 * 1024
            ? '${(_fileSize! / (1024 * 1024)).toStringAsFixed(2)} MB'
            : '${(_fileSize! / 1024).toStringAsFixed(2)} KB')
        : '...';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Note Properties',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
              style: IconButton.styleFrom(
                backgroundColor: widget.isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : colorScheme.surfaceContainerHighest,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _PropRow(
          icon: Icons.calendar_today,
          label: 'Created',
          value: widget.creation,
        ),
        _PropRow(
          icon: Icons.edit_note,
          label: 'Modified',
          value: widget.modified,
        ),
        _PropRow(
          icon: Icons.visibility,
          label: 'Accessed',
          value: widget.accessed,
        ),
        _PropRow(
          icon: Icons.location_on_outlined,
          label: 'Location',
          value: widget.locationStr,
        ),
        _PropRow(
          icon: Icons.menu_book_outlined,
          label: 'Type',
          value: 'Paged note',
        ),
        _PropRow(
          icon: Icons.schedule,
          label: 'Time Spent',
          value: widget.timeSpentStr,
        ),
        _PropRow(
          icon: Icons.timer_outlined,
          label: 'Time Editing',
          value: widget.timeSpentEditingStr,
        ),
        _PropRow(
          icon: Icons.sd_storage,
          label: 'Total Size',
          value: sizeStr,
        ),
        if (stows.localEncryptionEnabled.value && _basePath != null)
          _PdfLoadModeRow(basePath: _basePath!),
      ],
    );
  }
}

class _PropRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _PropRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _PdfLoadModeRow extends StatefulWidget {
  final String basePath;

  const _PdfLoadModeRow({required this.basePath});

  @override
  State<_PdfLoadModeRow> createState() => _PdfLoadModeRowState();
}

class _PdfLoadModeRowState extends State<_PdfLoadModeRow> {

  String? _localModeOverride;

  @override
  void initState() {
    super.initState();
    stows.vaultPdfLoadOverrides.addListener(_onOverridesChanged);
    _syncFromStow();
  }

  @override
  void dispose() {
    stows.vaultPdfLoadOverrides.removeListener(_onOverridesChanged);
    super.dispose();
  }

  void _onOverridesChanged() {
    if (mounted) _syncFromStow();
  }

  void _syncFromStow() {
    final mode = getStoredVaultPdfLoadOverrideForPath(widget.basePath);
    if (mounted && _localModeOverride != mode) {
      setState(() => _localModeOverride = mode);
    }
  }

  String get _effectiveMode =>
      _localModeOverride ?? getStoredVaultPdfLoadOverrideForPath(widget.basePath);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentMode = _effectiveMode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(Icons.picture_as_pdf, size: 20, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'PDF loading',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SegmentedButton<String>(
            key: ValueKey(currentMode),
            segments: const [
              ButtonSegment(
                value: 'ram_only',
                icon: Icon(Icons.memory, size: 16),
                label: Text('RAM'),
              ),
              ButtonSegment(
                value: 'temp_file',
                icon: Icon(Icons.speed, size: 16),
                label: Text('Temp'),
              ),
              ButtonSegment(
                value: 'default',
                icon: Icon(Icons.settings, size: 16),
                label: Text('Default'),
              ),
            ],
            selected: {currentMode},
            onSelectionChanged: (selection) {
              final mode = selection.first;

              setState(() => _localModeOverride = mode);
              setVaultPdfLoadOverrideForFile(
                widget.basePath,
                mode == 'default' ? null : mode,
              );
            },
          ),
        ],
      ),
    );
  }
}
