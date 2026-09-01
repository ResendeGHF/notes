// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/home/animated_grid_item.dart';
import 'package:saber/components/home/home_list_row_chrome.dart';
import 'package:saber/components/home/preview_card.dart';
import 'package:saber/data/extensions/change_notifier_extensions.dart';

class _DisplayEntry {
  _DisplayEntry({required this.filePath, this.linkKey, this.targetPath});

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
    this.animateMutations = true,
    this.addAutomaticKeepAlives = true,
    this.showListMetadata = true,
  });

  final List<String> files;
  final Map<String, String> linkedFiles;
  final int crossAxisCount;
  final ValueNotifier<List<String>> selectedFiles;
  final Future<void> Function(String)? onDeleteLink;

  final bool animateMutations;
  final bool addAutomaticKeepAlives;
  final bool showListMetadata;

  @override
  State<MasonryFiles> createState() => _MasonryFilesState();
}

class _MasonryFilesState extends State<MasonryFiles> {
  final ValueNotifier<bool> isAnythingSelected = ValueNotifier(false);

  List<_DisplayEntry> _displayEntries = [];
  final Set<String> _removingKeys = {};
  final Set<String> _enteringKeys = {};
  var _initialized = false;

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
    if (filesChanged || linksChanged) {
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

    if (!_initialized || !widget.animateMutations) {
      _displayEntries = newEntries;
      _removingKeys.clear();
      _enteringKeys.clear();
      _initialized = true;
      return;
    }

    final oldOrder = _displayEntries.map((e) => e.key).toList();
    final oldKeys = oldOrder.toSet();
    final newKeys = newEntries.map((e) => e.key).toSet();
    final removedKeys = oldKeys.difference(newKeys);
    final addedKeys = newKeys.difference(oldKeys);

    _removingKeys
      ..removeWhere((k) => newKeys.contains(k))
      ..addAll(removedKeys);
    _enteringKeys
      ..removeWhere((k) => !newKeys.contains(k) || _removingKeys.contains(k))
      ..addAll(addedKeys);
    if (addedKeys.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _enteringKeys.removeAll(addedKeys);
      });
    }

    final oldIndices = <String, int>{};
    for (var i = 0; i < _displayEntries.length; i++) {
      oldIndices[_displayEntries[i].key] = i;
    }

    final removingEntries = _displayEntries
        .where((e) => _removingKeys.contains(e.key))
        .toList();

    if (removingEntries.isEmpty) {
      _displayEntries = newEntries;
      return;
    }

    final pairedSwap = addedKeys.isNotEmpty && removingEntries.isNotEmpty;

    if (pairedSwap) {
      final exitCount = removingEntries.length.clamp(1, newEntries.length);
      final keepNew = newEntries.sublist(0, newEntries.length - exitCount);
      _displayEntries = [...keepNew, ...removingEntries.take(exitCount)];
      return;
    }

    final survivors = newEntries
        .where((e) => !_removingKeys.contains(e.key))
        .toList();
    final merged = <_DisplayEntry>[];
    var survivorIndex = 0;
    final maxLen = survivors.length + removingEntries.length;
    for (var i = 0; i < maxLen; i++) {
      final removingHere = removingEntries
          .where((e) => (oldIndices[e.key] ?? -1) == i)
          .toList();
      if (removingHere.isNotEmpty) {
        merged.addAll(removingHere);
      } else if (survivorIndex < survivors.length) {
        merged.add(survivors[survivorIndex++]);
      }
    }
    while (survivorIndex < survivors.length) {
      merged.add(survivors[survivorIndex++]);
    }
    _displayEntries = merged;
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
      if (fp.endsWith('.sbn2')) {
        fp = fp.substring(0, fp.length - 5);
      } else if (fp.endsWith('.sbn')) {
        fp = fp.substring(0, fp.length - 4);
      }
      entries.add(_DisplayEntry(filePath: fp, linkKey: mapKey, targetPath: fp));
    }
    return entries;
  }

  void _onExitComplete(String key) {
    if (!mounted) return;
    setState(() {
      _removingKeys.remove(key);
      _displayEntries = _buildEntries(widget.files, widget.linkedFiles);
    });
  }

  Widget itemBuilder(BuildContext context, int index) {
    if (index >= _displayEntries.length) {
      return const SizedBox.shrink();
    }

    final entry = _displayEntries[index];
    final animateExit = _removingKeys.contains(entry.key);
    final animateEnter = !animateExit && _enteringKeys.contains(entry.key);

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
            showListMetadata: widget.showListMetadata,
          );
        },
      ),
    );

    if (!widget.animateMutations) {
      return KeyedSubtree(key: ValueKey(entry.key), child: card);
    }

    return KeyedSubtree(
      key: ValueKey(entry.key),
      child: AnimatedGridItem(
        animateExit: animateExit,
        animateEnter: animateEnter,
        onExitComplete: animateExit ? () => _onExitComplete(entry.key) : null,
        child: card,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    isAnythingSelected.value = widget.selectedFiles.value.isNotEmpty;

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          const spacing = 12.0;
          final n = widget.crossAxisCount;
          final crossAxisExtent = constraints.crossAxisExtent;

          final childAspectRatio = n == 1
              ? crossAxisExtent /
                  (widget.showListMetadata
                      ? kHomeListRowGridExtent
                      : kHomeListRowCompactExtent)
              : 0.72; // Proporção refinada para cards verticais estilo Google Keep

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
              addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
              findChildIndexCallback: (Key key) {
                if (key is ValueKey<String>) {
                  final i = _displayEntries.indexWhere(
                    (e) => e.key == key.value,
                  );
                  return i >= 0 ? i : null;
                }
                return null;
              },
            ),
          );
        },
      ),
    );
  }
}