// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/data/home_data_cache.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tags_database.dart';
import 'package:saber/pages/editor/editor.dart';

class VaultPdfLoadOverridesPage extends StatefulWidget {
  const VaultPdfLoadOverridesPage({super.key});

  @override
  State<VaultPdfLoadOverridesPage> createState() =>
      _VaultPdfLoadOverridesPageState();
}

class _VaultPdfLoadOverridesPageState extends State<VaultPdfLoadOverridesPage> {
  final TextEditingController _searchController = TextEditingController();
  List<String> _allNotes = [];
  List<String> _filteredNotes = [];
  Map<String, Set<String>> _tagsByFile = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadNotes();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    setState(() => _loading = true);
    final list = await HomeDataCache.instance.getAllOrLoad();
    final tags = await HomeDataCache.instance.getAllTagsOrLoad();
    if (mounted) {
      _allNotes = list;
      _tagsByFile = tags;
      _filterNotes(_searchController.text);
      setState(() => _loading = false);
    }
  }

  void _onSearchChanged() {
    _filterNotes(_searchController.text);
  }

  void _filterNotes(String search) {
    if (search.isEmpty) {
      _filteredNotes = List.from(_allNotes);
    } else {
      final q = search.toLowerCase().trim();
      _filteredNotes = _allNotes.where((file) {
        if (file.toLowerCase().contains(q)) return true;
        final normPath = TagDatabase.normalizePath(file);
        final tags = _tagsByFile[normPath] ?? const <String>{};
        return tags.any((tag) => tag.contains(q));
      }).toList();
    }
    if (mounted) setState(() {});
  }

  static String _toBasePath(String notePath) {
    final norm = notePath.replaceAll('\\', '/').replaceFirst(RegExp(r'^/'), '');
    return '$norm${Editor.extension}';
  }

  void _showAddNoteDialog(String notePath) {
    final basePath = _toBasePath(notePath);
    final overrides = stows.vaultPdfLoadOverrides.value;
    final currentMode = overrides[basePath] ?? 'default';
    final displayName = notePath.split('/').last;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'PDF loading mode for "$displayName"',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'ram_only',
                    icon: Icon(Icons.memory, size: 18),
                    label: Text('RAM only'),
                  ),
                  ButtonSegment(
                    value: 'temp_file',
                    icon: Icon(Icons.speed, size: 18),
                    label: Text('Temp file'),
                  ),
                  ButtonSegment(
                    value: 'default',
                    icon: Icon(Icons.settings, size: 18),
                    label: Text('Default'),
                  ),
                ],
                selected: {currentMode},
                onSelectionChanged: (selection) {
                  final mode = selection.first;
                  setVaultPdfLoadOverrideForFile(
                    basePath,
                    mode == 'default' ? null : mode,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const AdaptiveIcon(
            icon: Icons.arrow_back,
            cupertinoIcon: CupertinoIcons.back,
          ),
          onPressed: () => context.pop(),
        ),
        title: const Text('Per-file loading mode'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search notes to add...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
              onSubmitted: (_) {},
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<Map<String, String>>(
              valueListenable: stows.vaultPdfLoadOverrides,
              builder: (context, overrides, _) {
                if (_loading) {
                  return const Center(child: CircularProgressIndicator());
                }

                return CustomScrollView(
                  slivers: [
                    if (overrides.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: Text(
                            'Notes with custom mode (${overrides.length})',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    if (overrides.isNotEmpty)
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final entry =
                                overrides.entries.elementAt(index);
                            final path = entry.key;
                            final mode = entry.value;
                            final displayPath = path.length > 45
                                ? '...${path.substring(path.length - 42)}'
                                : path;

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              child: ListTile(
                                leading: Icon(
                                  mode == 'ram_only'
                                      ? Icons.memory
                                      : Icons.speed,
                                  color: colorScheme.primary,
                                ),
                                title: Text(
                                  displayPath,
                                  style: theme.textTheme.bodyMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  mode == 'ram_only'
                                      ? 'RAM only'
                                      : 'Temp file',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    setVaultPdfLoadOverrideForFile(path, null);
                                  },
                                ),
                              ),
                            );
                          },
                          childCount: overrides.length,
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text(
                          'Search results – tap to set loading mode',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    if (_filteredNotes.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                            child: Text(
                              _searchController.text.isEmpty
                                  ? 'Type to search for notes'
                                  : 'No notes match your search',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final notePath = _filteredNotes[index];
                            final basePath = _toBasePath(notePath);
                            final existingMode = overrides[basePath];
                            final displayName = notePath.split('/').last;

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              child: ListTile(
                                leading: Icon(
                                  existingMode != null
                                      ? (existingMode == 'ram_only'
                                          ? Icons.memory
                                          : Icons.speed)
                                      : Icons.description_outlined,
                                  color: existingMode != null
                                      ? colorScheme.primary
                                      : colorScheme.onSurfaceVariant,
                                ),
                                title: Text(
                                  displayName,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  existingMode != null
                                      ? (existingMode == 'ram_only'
                                          ? 'RAM only'
                                          : 'Temp file')
                                      : 'Default',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                trailing: const Icon(Icons.add_circle_outline),
                                onTap: () => _showAddNoteDialog(notePath),
                              ),
                            );
                          },
                          childCount: _filteredNotes.length,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
