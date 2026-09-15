// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:saber/i18n/strings.g.dart';

class PdfImportProgressDialog extends StatefulWidget {
  const PdfImportProgressDialog({
    super.key,
    required this.totalPages,
    required this.onCancel,
    required this.progressNotifier,
  });

  final int totalPages;
  final VoidCallback onCancel;
  final ValueNotifier<({int current, int total, String status})> progressNotifier;

  @override
  State<PdfImportProgressDialog> createState() => _PdfImportProgressDialogState();
}

class _PdfImportProgressDialogState extends State<PdfImportProgressDialog> {
  @override
  void initState() {
    super.initState();
    widget.progressNotifier.addListener(_onProgressUpdate);
  }
  
  @override
  void dispose() {
    widget.progressNotifier.removeListener(_onProgressUpdate);
    super.dispose();
  }
  
  void _onProgressUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final progressData = widget.progressNotifier.value;
    final progress = progressData.total > 0 
        ? progressData.current / progressData.total 
        : 0.0;
    
    return WillPopScope(
      onWillPop: () async {
        widget.onCancel();
        return false;
      },
      child: AlertDialog(
        title: Text(t.editor.menu.import),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (progressData.status.isNotEmpty) ...[
              Text(progressData.status),
              const SizedBox(height: 16),
            ],
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text(
              '${progressData.current} / ${progressData.total}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (widget.totalPages > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${widget.totalPages} ${t.editor.pages.toLowerCase()}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: widget.onCancel,
            child: Text(t.common.cancel),
          ),
        ],
      ),
    );
  }
}
