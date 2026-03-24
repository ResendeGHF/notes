// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class FileTreeSkeletonRow extends StatefulWidget {
  const FileTreeSkeletonRow({
    super.key,
    required this.indent,
    this.labelWidth = 0.7,
    this.isFolder = true,
  });

  final double indent;
  final double labelWidth;
  final bool isFolder;

  @override
  State<FileTreeSkeletonRow> createState() => _FileTreeSkeletonRowState();
}

class _FileTreeSkeletonRowState extends State<FileTreeSkeletonRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseColor = colorScheme.surfaceContainerHighest;
    final highlightColor = colorScheme.surfaceContainerLow;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final t = _animation.value;
        final gradient = LinearGradient(
          begin: Alignment(-2 + t * 2, 0),
          end: Alignment(-1 + t * 2, 0),
          colors: [baseColor, highlightColor, baseColor],
          stops: const [0.0, 0.5, 1.0],
        );

        return Padding(
          padding: EdgeInsets.only(
            left: widget.indent,
            right: 8,
            top: 6,
            bottom: 6,
          ),
          child: Row(
            children: [

              if (widget.isFolder) ...[
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
              ],

              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),

              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Container(
                      width: constraints.maxWidth * widget.labelWidth,
                      height: 13,
                      decoration: BoxDecoration(
                        gradient: gradient,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class FileTreeSkeleton extends StatelessWidget {
  const FileTreeSkeleton({
    super.key,
    this.rowCount = 7,
  });

  final int rowCount;

  @override
  Widget build(BuildContext context) {

    const skeletonRows = [
      (12.0, true, 0.65),
      (28.0, true, 0.55),
      (50.0, false, 0.7),
      (12.0, true, 0.5),
      (34.0, false, 0.85),
      (34.0, false, 0.45),
      (12.0, true, 0.6),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rowCount; i++)
            FileTreeSkeletonRow(
              indent: skeletonRows[i % skeletonRows.length].$1,
              labelWidth: skeletonRows[i % skeletonRows.length].$3,
              isFolder: skeletonRows[i % skeletonRows.length].$2,
            ),
        ],
      ),
    );
  }
}

class FileTreeFolderSkeleton extends StatelessWidget {
  const FileTreeFolderSkeleton({
    super.key,
    required this.parentLevel,
    this.rowCount = 4,
  });

  final int parentLevel;

  final int rowCount;

  @override
  Widget build(BuildContext context) {

    final childLevel = parentLevel + 1;
    final folderIndent = 12.0 + (childLevel * 16.0);
    final fileIndent = 12.0 + 22.0 + (childLevel * 16.0);

    const rows = [
      (true, 0.6),
      (false, 0.75),
      (true, 0.5),
      (false, 0.85),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rowCount; i++)
          FileTreeSkeletonRow(
            indent: rows[i % rows.length].$1 ? folderIndent : fileIndent,
            labelWidth: rows[i % rows.length].$2,
            isFolder: rows[i % rows.length].$1,
          ),
      ],
    );
  }
}
