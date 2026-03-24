// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class PdfPagePickerDialog extends StatefulWidget {
  const PdfPagePickerDialog({
    super.key,
    required this.pdfDocument,
    required this.pdfFile,
    this.invert = false,
  });

  final PdfDocument pdfDocument;
  final File pdfFile;
  final bool invert;

  static Future<List<int>?> show(
    BuildContext context, {
    required PdfDocument pdfDocument,
    required File pdfFile,
    bool invert = false,
  }) async {
    return showDialog<List<int>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PdfPagePickerDialog(
        pdfDocument: pdfDocument,
        pdfFile: pdfFile,
        invert: invert,
      ),
    );
  }

  @override
  State<PdfPagePickerDialog> createState() => _PdfPagePickerDialogState();
}

class _PdfPagePickerDialogState extends State<PdfPagePickerDialog> {
  final Set<int> _selectedPages = {};

  void _selectAll() {
    setState(() {
      for (var i = 0; i < widget.pdfDocument.pages.length; i++) {
        _selectedPages.add(i);
      }
    });
  }

  void _deselectAll() {
    setState(() => _selectedPages.clear());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totalPages = widget.pdfDocument.pages.length;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Material(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        elevation: 0,
        shadowColor: Colors.black38,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 12, 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.picture_as_pdf_rounded,
                        color: colorScheme.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Import PDF pages',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _selectedPages.isEmpty
                                ? 'Select pages to add to your canvas'
                                : '${_selectedPages.length} page${_selectedPages.length == 1 ? '' : 's'} selected',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (totalPages > 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: _selectAll,
                        child: Text('Select all'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _selectedPages.isEmpty ? null : _deselectAll,
                        child: Text('Deselect all'),
                      ),
                    ],
                  ),
                ),

              const Divider(height: 1),
              const SizedBox(height: 8),

              Flexible(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const spacing = 14.0;
                    const padding = 20.0;
                    const columns = 3;
                    final availableWidth = constraints.maxWidth -
                        padding * 2 -
                        spacing * (columns - 1);
                    final cellWidth = availableWidth / columns;
                    final cellHeight = cellWidth * (297 / 210);

                    return GridView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: padding,
                        vertical: padding - 8,
                      ),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: spacing,
                        crossAxisSpacing: spacing,
                        childAspectRatio: cellWidth / cellHeight,
                      ),
                      itemCount: totalPages,
                      itemBuilder: (context, index) {
                        final isSelected = _selectedPages.contains(index);
                        return _PageThumbnail(
                          pdfDocument: widget.pdfDocument,
                          pageIndex: index,
                          invert: widget.invert,
                          isSelected: isSelected,
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedPages.remove(index);
                              } else {
                                _selectedPages.add(index);
                              }
                            });
                          },
                        );
                      },
                    );
                  },
                ),
              ),

              const Divider(height: 1),

              Padding(
                padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _selectedPages.isEmpty
                          ? null
                          : () {
                              Navigator.of(context).pop(
                                _selectedPages.toList()..sort(),
                              );
                            },
                      icon: Icon(
                        Icons.add_rounded,
                        size: 18,
                        color: _selectedPages.isEmpty
                            ? colorScheme.onSurface.withValues(alpha: 0.38)
                            : colorScheme.onPrimary,
                      ),
                      label: Text(
                        _selectedPages.isEmpty
                            ? 'Select pages'
                            : 'Import ${_selectedPages.length} page${_selectedPages.length == 1 ? '' : 's'}',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageThumbnail extends StatelessWidget {
  const _PageThumbnail({
    required this.pdfDocument,
    required this.pageIndex,
    required this.invert,
    required this.isSelected,
    required this.onTap,
  });

  final PdfDocument pdfDocument;
  final int pageIndex;
  final bool invert;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant.withValues(alpha: 0.6),
              width: isSelected ? 2.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [

              Padding(
                padding: const EdgeInsets.all(8),
                child: ColorFiltered(
                  colorFilter: invert
                      ? const ColorFilter.matrix([
                          -1, 0, 0, 0, 255,
                          0, -1, 0, 0, 255,
                          0, 0, -1, 0, 255,
                          0, 0, 0, 1, 0,
                        ])
                      : const ColorFilter.matrix([
                          1, 0, 0, 0, 0,
                          0, 1, 0, 0, 0,
                          0, 0, 1, 0, 0,
                          0, 0, 0, 1, 0,
                        ]),
                  child: PdfPageView(
                    document: pdfDocument,
                    pageNumber: pageIndex + 1,
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),

              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    '${pageIndex + 1}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              if (isSelected)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
