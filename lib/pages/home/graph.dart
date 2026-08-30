// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' show max, min;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:graphview/GraphView.dart';
import 'package:saber/components/home/home_toolbar_chrome.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/home_data_cache.dart';
import 'package:saber/data/note_links_database.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/data/tags_database.dart';
import 'package:saber/i18n/strings.g.dart';

class GraphPage extends StatefulWidget {
  const GraphPage({super.key});

  @override
  State<GraphPage> createState() => _GraphPageState();
}

class _GraphPageState extends State<GraphPage> {
  StreamSubscription? _fileSystemSubscription;
  final Set<String> _notes = {};
  final Map<String, List<String>> _edges = {};
  final Map<Node, String> _nodeToPath = {};
  final Map<String, Set<String>> _tagsByPath = {};
  var _graph = Graph()..isTree = false;
  String? _rootPath;

  bool _showFullGraph = false;
  bool _useTreeView = false;
  var _loading = true;
  String? _error;
  final _graphController = GraphViewController();
  int _totalVisibleNodeCount = 0;

  static const int _maxNodesToShow = 600;

  static final _treeConfig = BuchheimWalkerConfiguration()
    ..siblingSeparation = 80
    ..levelSeparation = 120
    ..subtreeSeparation = 80
    ..orientation = BuchheimWalkerConfiguration.ORIENTATION_TOP_BOTTOM
    ..useCurvedConnections = true;
  static final _treeAlgorithm = BuchheimWalkerAlgorithm(
    _treeConfig,
    TreeEdgeRenderer(_treeConfig),
  );

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadGraph();
    });

    _fileSystemSubscription = FileManager.fileWriteStream.stream.listen((
      event,
    ) {
      if (mounted && !_loading) {
        _loadGraph();
      }
    });
  }

  @override
  void dispose() {
    _fileSystemSubscription?.cancel();
    _notes.clear();
    _edges.clear();
    _nodeToPath.clear();
    super.dispose();
  }

  Future<void> _loadGraph() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _notes.clear();
      _edges.clear();
      _nodeToPath.clear();
      _graph = Graph()..isTree = false;

      final files = await FileManager.getAllFiles();
      final pathsToLoad = <String>[];
      for (final sourcePath in files) {
        final path = _normalizeNotePath(sourcePath);
        if (path != null)
          pathsToLoad.add(NoteLinksDatabase.normalizePath(path));
      }
      _notes.addAll(pathsToLoad);

      _tagsByPath.clear();
      _tagsByPath.addAll(
        await TagDatabase.instance.getTagsForPaths(_notes.toList()),
      );

      final known = _notes.toSet();
      final linksBySource = await NoteLinksDatabase.instance
          .getTargetPathsForSources(
            _notes.toList(),
            rootDirectory: FileManager.documentsDirectory,
          );
      for (final sourcePath in _notes) {
        final links = <String>[];
        for (final targetPath
            in linksBySource[sourcePath] ?? const <String>[]) {
          final normalized = NoteLinksDatabase.normalizePath(targetPath);
          if (known.contains(normalized)) {
            links.add(normalized);
          }
        }
        _edges[sourcePath] = links.toSet().toList();
      }
      if (_rootPath != null && !_notes.contains(_rootPath)) {
        _rootPath = null;
      }
      _rebuildGraph();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String? _normalizeNotePath(String path) {
    final cleaned = path.trim();
    if (cleaned.isEmpty) return null;

    final ignoredAssetSuffix = RegExp(r'\.(p|\d+|sbn2|sbn)$');
    if (ignoredAssetSuffix.hasMatch(cleaned.split('/').last)) {
      final base = cleaned.replaceFirst(ignoredAssetSuffix, '');
      if (base.isEmpty) return null;
      return NoteLinksDatabase.normalizePath(base);
    }
    // Do not show any path whose filename has an extension (e.g. .pdf, .sbn2)
    if (cleaned.split('/').last.contains('.')) return null;
    return NoteLinksDatabase.normalizePath(cleaned);
  }

  void _rebuildGraph() {
    final useTree =
        _useTreeView && _rootPath != null && _notes.contains(_rootPath);
    final allVisible = useTree ? _visibleNodesForTree() : _visibleNodes();
    final totalCount = allVisible.length;
    final visibleList = totalCount > _maxNodesToShow
        ? allVisible.take(_maxNodesToShow).toList()
        : allVisible;
    final visible = visibleList.toSet();
    _nodeToPath.clear();
    final graph = Graph()..isTree = useTree;
    final nodeByPath = <String, Node>{};
    for (final path in visible) {
      final node = Node.Id(path);
      nodeByPath[path] = node;
      _nodeToPath[node] = path;
      graph.addNode(node);
    }
    if (useTree) {
      for (final (from, to) in _treeEdges(visible)) {
        final fromNode = nodeByPath[from];
        final toNode = nodeByPath[to];
        if (fromNode != null && toNode != null) {
          graph.addEdge(fromNode, toNode);
        }
      }
    } else {
      for (final (from, to) in _visibleEdges(visible)) {
        final fromNode = nodeByPath[from];
        final toNode = nodeByPath[to];
        if (fromNode == null || toNode == null) continue;
        graph.addEdge(fromNode, toNode);
      }
    }
    _graph = graph;
    _totalVisibleNodeCount = totalCount;
    if (mounted) setState(() {});
  }

  String _labelForPath(String path) {
    final idx = path.lastIndexOf('/');
    return idx >= 0 ? path.substring(idx + 1) : path;
  }

  List<String> _rootSearchOptions(String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) {

      final recents = HomeDataCache.instance.recentCached ?? [];
      return recents.where((p) => _notes.contains(p)).take(5).toList();
    }
    final notePaths =
        _notes.where((path) => !path.split('/').last.contains('.')).toList()
          ..sort();
    return notePaths.where((path) {
      if (path.toLowerCase().contains(q)) return true;
      final tags = _tagsByPath[path] ?? const {};
      return tags.any((tag) => tag.contains(q));
    }).toList();
  }

  List<String> _visibleNodes() {
    if (_rootPath == null) {
      if (!_showFullGraph) return [];
      return _notes.toList()..sort();
    }
    if (!_notes.contains(_rootPath)) {
      return _notes.toList()..sort();
    }
    final root = _rootPath!;
    final visited = <String>{root};
    final queue = <String>[root];
    while (queue.isNotEmpty) {
      final from = queue.removeAt(0);
      for (final to in _edges[from] ?? const <String>[]) {
        if (_notes.contains(to) && visited.add(to)) {
          queue.add(to);
        }
      }
    }
    final list = visited.toList()..sort();
    return list;
  }

  List<String> _visibleNodesForTree() {
    if (_rootPath == null || !_notes.contains(_rootPath)) {
      return _visibleNodes();
    }
    final root = _rootPath!;
    final visited = <String>{root};
    final queue = <String>[root];
    while (queue.isNotEmpty) {
      final from = queue.removeAt(0);
      for (final to in _edges[from] ?? const <String>[]) {
        if (_notes.contains(to) && visited.add(to)) {
          queue.add(to);
        }
      }
    }
    final list = visited.toList()..sort();
    return list;
  }

  List<(String, String)> _treeEdges(Set<String> visible) {
    if (_rootPath == null || !visible.contains(_rootPath)) return [];
    final root = _rootPath!;
    final result = <(String, String)>[];
    final visited = <String>{root};
    final queue = <String>[root];
    while (queue.isNotEmpty) {
      final from = queue.removeAt(0);
      for (final to in _edges[from] ?? const <String>[]) {
        if (visible.contains(to) && visited.add(to)) {
          result.add((from, to));
          queue.add(to);
        }
      }
    }
    return result;
  }

  List<(String, String)> _visibleEdges(Set<String> visible) {
    final result = <(String, String)>[];
    for (final from in visible) {
      final tos = _edges[from] ?? const <String>[];
      for (final to in tos) {
        if (visible.contains(to)) {
          result.add((from, to));
        }
      }
    }
    return result;
  }

  void _openNote(String path) {
    context.push(RoutePaths.editFilePath(path));
  }

  Widget _buildLoadingState(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 20),
            Text(
              'Graph',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _buildLoadingState(context);
    }
    if (_error != null) {
      return Scaffold(
        body: Center(child: Text(t.home.failedToLoadGraph(error: _error!))),
      );
    }
    if (_notes.isEmpty) {
      return Scaffold(body: Center(child: Text(t.home.noNotesToGraph)));
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      key: const ValueKey('graph-content'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: homeAppBarBackgroundColor(context),
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.15),
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: DecoratedBox(
                  decoration: homeRuggedPanelDecoration(context),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      10,
                      8,
                      10,
                      8,
                    ),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Autocomplete<String>(
                              key: ValueKey('$_rootPath-$_showFullGraph'),
                              initialValue: TextEditingValue(
                                text: _rootPath != null
                                    ? _labelForPath(_rootPath!)
                                    : '',
                              ),
                              displayStringForOption: _labelForPath,
                              optionsBuilder: (text) =>
                                  _rootSearchOptions(text.text),
                              onSelected: (path) {
                                setState(() {
                                  _rootPath = path;
                                  _rebuildGraph();
                                });
                              },
                              fieldViewBuilder:
                                  (context, controller, focusNode, onSubmitted) {
                                return TextField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: colorScheme.onSurface,
                                    fontSize: 15,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: t.home.graph.rootSearchHint,
                                    hintStyle: theme.textTheme.bodyLarge
                                        ?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: 15,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    prefixIcon: Icon(
                                      Icons.search,
                                      color: colorScheme.onSurfaceVariant,
                                      size: 22,
                                    ),
                                    suffixIcon: _rootPath != null ||
                                            _showFullGraph
                                        ? IconButton(
                                            style:
                                                homeToolbarCompactIconStyle(
                                              context,
                                            ),
                                            icon: const Icon(
                                              Icons.clear,
                                              size: 22,
                                            ),
                                            tooltip: _rootPath != null
                                                ? t.home.graph.clearRoot
                                                : t.home.graph.selectRoot,
                                            onPressed: () {
                                              setState(() {
                                                _rootPath = null;
                                                _useTreeView = false;
                                                _showFullGraph = true;
                                                _rebuildGraph();
                                              });
                                              controller.clear();
                                            },
                                          )
                                        : null,
                                  ),
                                );
                              },
                              optionsViewBuilder: (context, onSelected, options) {
                                final mq = MediaQuery.sizeOf(context);
                                return Align(
                                  alignment: Alignment.topLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Material(
                                      color: Colors.transparent,
                                      elevation: 0,
                                      child: DecoratedBox(
                                        decoration:
                                            homeRuggedPanelDecoration(context),
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxHeight: 380,
                                            maxWidth: min(
                                              520,
                                              max(240, mq.width - 32),
                                            ),
                                          ),
                                          child: ListView.builder(
                                            padding: EdgeInsets.zero,
                                            shrinkWrap: true,
                                            itemCount: options.length,
                                            itemBuilder: (context, index) {
                                              final path =
                                                  options.elementAt(index);
                                              return ListTile(
                                                dense: true,
                                                title: Text(
                                                  _labelForPath(path),
                                                  style: theme.textTheme
                                                      .titleSmall?.copyWith(
                                                    color: colorScheme
                                                        .onSurface,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                subtitle: path.contains('/')
                                                    ? Text(
                                                        path,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: theme
                                                            .textTheme.bodySmall
                                                            ?.copyWith(
                                                          color: colorScheme
                                                              .onSurfaceVariant,
                                                        ),
                                                      )
                                                    : null,
                                                onTap: () => onSelected(path),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          HomeGlassIconStrip(
                            children: [
                              IconButton(
                                style: homeToolbarCompactIconStyle(context)
                                    .copyWith(
                                  foregroundColor: WidgetStatePropertyAll(
                                    _showFullGraph && _rootPath == null
                                        ? colorScheme.primary
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                tooltip: 'Show All Notes',
                                icon: Icon(
                                  _showFullGraph && _rootPath == null
                                      ? Icons.blur_on
                                      : Icons.blur_circular,
                                  size: 22,
                                ),
                                onPressed: () {
                                  setState(() {
                                    if (_showFullGraph && _rootPath == null) {
                                      _showFullGraph = false;
                                    } else {
                                      _showFullGraph = true;
                                      _rootPath = null;
                                    }
                                    _rebuildGraph();
                                  });
                                },
                              ),
                              const HomeToolbarDivider(),
                              IconButton(
                                style: homeToolbarCompactIconStyle(context)
                                    .copyWith(
                                  foregroundColor: WidgetStateProperty
                                      .resolveWith((states) {
                                    if (states
                                        .contains(WidgetState.disabled)) {
                                      return colorScheme.onSurface.withValues(
                                        alpha: 0.38,
                                      );
                                    }
                                    return _useTreeView
                                        ? colorScheme.primary
                                        : colorScheme.onSurfaceVariant;
                                  }),
                                ),
                                tooltip: t.home.tooltips.treeView,
                                icon: Icon(
                                  _useTreeView
                                      ? Icons.account_tree
                                      : Icons.hub,
                                  size: 22,
                                ),
                                onPressed: _rootPath == null
                                    ? null
                                    : () {
                                        setState(() {
                                          _useTreeView = !_useTreeView;
                                          _rebuildGraph();
                                        });
                                      },
                              ),
                              const HomeToolbarDivider(),
                              IconButton(
                                style: homeToolbarCompactIconStyle(context),
                                tooltip: 'Zoom to fit',
                                onPressed: () => _graphController.zoomToFit(),
                                icon: const Icon(Icons.fit_screen, size: 22),
                              ),
                              const HomeToolbarDivider(),
                              IconButton(
                                style: homeToolbarCompactIconStyle(context),
                                tooltip: 'Refresh',
                                onPressed: _loadGraph,
                                icon: const Icon(Icons.refresh, size: 22),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _rootPath == null && !_showFullGraph
                      ? Center(
                          child: Text(
                            t.home.graph.selectRoot,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final w = constraints.maxWidth;
                            final h = constraints.maxHeight;
                            if (w <= 0 || h <= 0) {
                              return const SizedBox.shrink();
                            }
                            if (_graph.nodes.isEmpty) {
                              return Center(
                                child: Text(
                                  'No notes to show',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              );
                            }
                            final useTree = _useTreeView &&
                                _rootPath != null &&
                                _notes.contains(_rootPath);
                            final nodeCount = _graph.nodes.length.clamp(
                              1,
                              _maxNodesToShow,
                            );
                            final hasEdges = _graph.edges.isNotEmpty;

                            final Algorithm algorithm;
                            if (useTree) {
                              algorithm = _treeAlgorithm;
                            } else if (hasEdges) {
                              algorithm = FruchtermanReingoldAlgorithm(
                                FruchtermanReingoldConfiguration(
                                  iterations:
                                      (650 - (nodeCount * 0.4).toInt()).clamp(
                                    80,
                                    700,
                                  ),
                                  attractionRate: 0.1,
                                  repulsionRate: 0.32,
                                  repulsionPercentage: 0.7,
                                  clusterPadding: 26,
                                  shuffleNodes: true,
                                ),
                              )..setDimensions(w, h);
                            } else {
                              algorithm = CircleLayoutAlgorithm(
                                CircleLayoutConfiguration(),
                                null,
                              )..setDimensions(w, h);
                            }
                            final paint = Paint()
                              ..color = const Color(0xFF90A4AE)
                              ..strokeWidth = 1.1
                              ..style = PaintingStyle.stroke;

                            return SizedBox(
                              width: w,
                              height: h,
                              child: GraphView.builder(
                                key: ValueKey('${_rootPath}_$useTree'),
                                graph: _graph,
                                algorithm: algorithm,
                                controller: _graphController,
                                autoZoomToFit: true,
                                paint: paint,
                                builder: (Node node) {
                                  final path = _nodeToPath[node];
                                  final isRoot =
                                      path != null && path == _rootPath;
                                  final label = path == null
                                      ? 'note'
                                      : _labelForPath(path);
                                  return RepaintBoundary(
                                    child: GestureDetector(
                                      onTap: path == null
                                          ? null
                                          : () => _openNote(path),
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isRoot
                                              ? colorScheme.primaryContainer
                                              : colorScheme
                                                  .surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: isRoot
                                                ? colorScheme.primary
                                                    .withValues(alpha: 0.5)
                                                : colorScheme.outlineVariant,
                                            width: 1,
                                          ),
                                        ),
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 120,
                                          ),
                                          child: Text(
                                            label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: isRoot
                                                  ? colorScheme
                                                      .onPrimaryContainer
                                                  : colorScheme
                                                      .onSurfaceVariant,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: -0.3,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                ),
                if (_totalVisibleNodeCount > _maxNodesToShow)
                  Positioned(
                    bottom: 32,
                    left: 32,
                    right: 32,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer.withValues(
                            alpha: 0.95,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: colorScheme.error.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          t.home.graph.showingNotes(
                            shown: _maxNodesToShow.toString(),
                            total: _totalVisibleNodeCount.toString(),
                          ),
                          style: TextStyle(
                            color: colorScheme.onErrorContainer,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
