// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/home/animated_grid_item.dart';
import 'package:saber/components/home/preview_card.dart';
import 'package:saber/data/extensions/change_notifier_extensions.dart';

class _DisplayEntry {
  _DisplayEntry({
    required this.filePath,
    this.linkKey,
    this.targetPath,
  });

  final String filePath;
  final String? linkKey;
  final String? targetPath;

  String get key => linkKey != null ? 'link_$linkKey' : filePath;
}

class MasonryFiles extends StatefulWidget {
  const MasonryFiles({
    super.key,
    required this.files,
    this.linkedFiles = const {},
    required this.selectedFiles,
    required this.crossAxisCount,
    this.onDeleteLink,
  });

  final List<String> files;
  final Map<String, String> linkedFiles;
  final int crossAxisCount;
  final ValueNotifier<List<String>> selectedFiles;
  final Future<void> Function(String)? onDeleteLink;

  @override
  State<MasonryFiles> createState() => _MasonryFilesState();
}

class _MasonryFilesState extends State<MasonryFiles> {
  final ValueNotifier<bool> isAnythingSelected = ValueNotifier(false);

  List<_DisplayEntry> _displayEntries = [];
  final Set<String> _removingKeys = {};
  final Set<String> _newKeys = {};
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _syncDisplayList();
  }

  @override
  void didUpdateWidget(MasonryFiles oldWidget) {
    super.didUpdateWidget(oldWidget);
    final filesChanged = !listEquals(oldWidget.files, widget.files);
    final linksChanged = !mapEquals(oldWidget.linkedFiles, widget.linkedFiles);
    final crossAxisChanged = oldWidget.crossAxisCount != widget.crossAxisCount;
    if (filesChanged || linksChanged || crossAxisChanged) {
      _syncDisplayList();
    }
  }

  void toggleSelection(String filePath, bool selected) {
    if (selected) {
      widget.selectedFiles.value.add(filePath);
    } else {
      widget.selectedFiles.value.remove(filePath);
    }
    isAnythingSelected.value = widget.selectedFiles.value.isNotEmpty;
    widget.selectedFiles.notifyListenersPlease();
  }

  void _syncDisplayList() {
    final newFiles = widget.files;
    final newLinks = widget.linkedFiles;
    final newEntries = _buildEntries(newFiles, newLinks);

    if (!_initialized) {
      _displayEntries = newEntries;
      _initialized = true;
      return;
    }

    final oldKeys = _displayEntries.map((e) => e.key).toSet();
    final newKeys = newEntries.map((e) => e.key).toSet();

    final removedKeys = oldKeys.difference(newKeys);
    final addedKeys = newKeys.difference(oldKeys);

    _removingKeys.addAll(removedKeys);
    _newKeys.addAll(addedKeys);

    final oldIndices = <String, int>{};
    for (var i = 0; i < _displayEntries.length; i++) {
      oldIndices[_displayEntries[i].key] = i;
    }

    final removingEntries =
        _displayEntries.where((e) => _removingKeys.contains(e.key)).toList();

    if (removingEntries.isEmpty) {
      _displayEntries = newEntries;
      return;
    }

    final entriesWithPositions = <({_DisplayEntry entry, double position})>[];
    for (var i = 0; i < newEntries.length; i++) {
      entriesWithPositions.add((
        entry: newEntries[i],
        position: i + 0.5,
      ));
    }
    for (final e in removingEntries) {
      entriesWithPositions.add((
        entry: e,
        position: (oldIndices[e.key] ?? 0).toDouble(),
      ));
    }
    entriesWithPositions.sort((a, b) => a.position.compareTo(b.position));
    _displayEntries = entriesWithPositions.map((e) => e.entry).toList();
  }

  List<_DisplayEntry> _buildEntries(
    List<String> files,
    Map<String, String> linkedFiles,
  ) {
    final entries = <_DisplayEntry>[];
    for (final f in files) {
      entries.add(_DisplayEntry(filePath: f));
    }
    for (final mapKey in linkedFiles.keys) {
      var fp = linkedFiles[mapKey]!;
      if (fp.endsWith('.sbn2')) fp = fp.substring(0, fp.length - 5);
      else if (fp.endsWith('.sbn')) fp = fp.substring(0, fp.length - 4);
      entries.add(_DisplayEntry(
        filePath: fp,
        linkKey: mapKey,
        targetPath: fp,
      ));
    }
    return entries;
  }

  void _onExitComplete(String key) {
    if (!mounted) return;
    setState(() {
      _removingKeys.remove(key);
      _displayEntries = _displayEntries.where((e) => e.key != key).toList();
    });
  }

  void _onEntranceComplete(String key) {
    if (!mounted) return;
    setState(() {
      _newKeys.remove(key);
    });
  }

  Widget itemBuilder(BuildContext context, int index) {
    if (index >= _displayEntries.length) {
      return const SizedBox.shrink();
    }

    final entry = _displayEntries[index];
    final animateEntrance = _newKeys.contains(entry.key);
    final animateExit = _removingKeys.contains(entry.key);

    final card = RepaintBoundary(
      child: ValueListenableBuilder(
        valueListenable: isAnythingSelected,
        builder: (context, isAnythingSelected, _) {
          return PreviewCard(
            filePath: entry.filePath,
            targetPath: entry.targetPath,
            linkKey: entry.linkKey,
            onDeleteLink: widget.onDeleteLink,
            toggleSelection: toggleSelection,
            selected: widget.selectedFiles.value.contains(entry.filePath),
            isAnythingSelected: isAnythingSelected,
            listMode: widget.crossAxisCount == 1,
          );
        },
      ),
    );

    return ClipRect(
      clipBehavior: Clip.hardEdge,
      child: AnimatedGridItem(
        key: ValueKey(entry.key),
        animateEntrance: animateEntrance,
        animateExit: animateExit,
        onExitComplete:
            animateExit ? () => _onExitComplete(entry.key) : null,
        onEntranceComplete:
            animateEntrance ? () => _onEntranceComplete(entry.key) : null,
        child: card,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    isAnythingSelected.value = widget.selectedFiles.value.isNotEmpty;

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          const spacing = 8.0;
          final n = widget.crossAxisCount;
          final crossAxisExtent = constraints.crossAxisExtent;

          final childAspectRatio = n == 1
              ? crossAxisExtent / 80
              : () {
                  final cellWidth =
                      (crossAxisExtent - (n - 1) * spacing) / n;
                  final thumbnailHeight = cellWidth * 1.4;
                  final cardHeight = thumbnailHeight + 36;
                  return cellWidth / cardHeight;
                }();
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: n,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              childAspectRatio: childAspectRatio,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => itemBuilder(context, index),
              childCount: _displayEntries.length,
            ),
          );
        },
      ),
    );
  }
}
