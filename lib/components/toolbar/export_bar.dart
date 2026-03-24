// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/theming/adaptive_circular_progress_indicator.dart';
import 'package:saber/i18n/strings.g.dart';

class ExportBar extends StatefulWidget {
  const ExportBar({
    super.key,
    required this.axis,
    required this.toggleExportBar,
    required this.exportAsSba,
    required this.exportAsPdf,
    required this.exportAsPng,
  });

  final Axis axis;

  final VoidCallback toggleExportBar;

  final Future Function(BuildContext)? exportAsSba;
  final Future Function(BuildContext)? exportAsPdf;
  final Future Function(BuildContext)? exportAsPng;

  @override
  State<ExportBar> createState() => _ExportBarState();
}

class _ExportBarState extends State<ExportBar> {

  Future Function(BuildContext)? _currentlyExporting;

  void Function()? _onPressed(
    Future Function(BuildContext)? exportFunction,
    BuildContext context,
  ) {
    if (_currentlyExporting != null) return null;
    if (exportFunction == null) return null;
    return () {
      setState(() => _currentlyExporting = exportFunction);

      widget.toggleExportBar();
      exportFunction(context).then((_) {
        setState(() => _currentlyExporting = null);
      });
    };
  }

  Widget _buttonChild(
    Future Function(BuildContext)? exportFunction,
    String text,
  ) {
    if (exportFunction == null || _currentlyExporting != exportFunction) {
      return Text(text);
    } else {

      return AdaptiveCircularProgressIndicator.textStyled(alpha: 0.4);
    }
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Text(t.editor.toolbar.exportAs),
      const SizedBox.square(dimension: 8),
      Builder(
        builder: (context) {
          return TextButton(
            onPressed: _onPressed(widget.exportAsSba, context),
            child: _buttonChild(widget.exportAsSba, 'SBA'),
          );
        },
      ),
      Builder(
        builder: (context) {
          return TextButton(
            onPressed: _onPressed(widget.exportAsPdf, context),
            child: _buttonChild(widget.exportAsPdf, 'PDF...'),
          );
        },
      ),
      Builder(
        builder: (context) {
          return TextButton(
            onPressed: _onPressed(widget.exportAsPng, context),
            child: _buttonChild(widget.exportAsPng, 'Image...'),
          );
        },
      ),
    ];

    return Center(
      child: Padding(
        padding: const .symmetric(horizontal: 4, vertical: 4),
        child: SingleChildScrollView(
          scrollDirection: widget.axis,
          child: Flex(
            direction: widget.axis,
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: children,
          ),
        ),
      ),
    );
  }
}
