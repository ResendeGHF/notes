// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

part of 'editor.dart';

class SplitEditorPage extends StatefulWidget {
  const SplitEditorPage({
    super.key,
    this.primaryPath,
    this.secondaryPath,
    this.primaryPdfPath,
    this.secondaryInitialPageIndex,
    this.initialAxis = Axis.horizontal,
  });

  final String? primaryPath;
  final String? secondaryPath;
  final String? primaryPdfPath;
  final int? secondaryInitialPageIndex;
  final Axis initialAxis;

  @override
  State<SplitEditorPage> createState() => _SplitEditorPageState();
}

class _EditorSlot {
  _EditorSlot({
    required this.path,
    required this.key,
    this.pdfPath,
    this.initialPageIndex,
  });

  final String? path;
  final String? pdfPath;
  final int? initialPageIndex;
  final GlobalKey<EditorState> key;
}

class _SplitEditorPageState extends State<SplitEditorPage> {
  static const double _dividerThickness = 16;
  static const double _minFraction = 0.16;

  late _EditorSlot _primary;
  _EditorSlot? _secondary;
  Axis _splitAxis = Axis.horizontal;
  double _splitFraction = 0.5;
  int _activePaneIndex = 0;
  int? _pendingActivePaneIndex;

  final ValueNotifier<SavingState> _combinedSavingState = ValueNotifier(
    SavingState.saved,
  );
  ValueNotifier<SavingState>? _primarySavingNotifier;
  ValueNotifier<SavingState>? _secondarySavingNotifier;
  bool _attachScheduled = false;

  @override
  void initState() {
    super.initState();
    _primary = _EditorSlot(
      path: widget.primaryPath,
      pdfPath: widget.primaryPdfPath,
      key: GlobalKey<EditorState>(),
    );
    if (widget.secondaryPath != null) {
      _secondary = _EditorSlot(
        path: widget.secondaryPath,
        key: GlobalKey<EditorState>(),
        initialPageIndex: widget.secondaryInitialPageIndex,
      );
    }
    _splitAxis = widget.initialAxis;
    _scheduleSavingStateAttach();
  }

  @override
  void didUpdateWidget(covariant SplitEditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    final secondaryPathChanged =
        widget.secondaryPath != oldWidget.secondaryPath;
    final secondaryPageIndexChanged =
        widget.secondaryInitialPageIndex != oldWidget.secondaryInitialPageIndex;
    if (secondaryPathChanged || secondaryPageIndexChanged) {
      if (widget.secondaryPath == null || widget.secondaryPath!.isEmpty) {
        if (_secondary != null) {
          final closingState = _secondary!.key.currentState;
          if (closingState != null) {
            unawaited(closingState.saveToFile(force: true));
          }
          setState(() {
            _secondary = null;
            _activePaneIndex = 0;
          });
          _scheduleSavingStateAttach();
        }
      } else {
        final closingState = _secondary?.key.currentState;
        if (closingState != null) {
          unawaited(closingState.saveToFile(force: true));
        }
        setState(() {
          _secondary = _EditorSlot(
            path: widget.secondaryPath,
            key: GlobalKey<EditorState>(),
            initialPageIndex: widget.secondaryInitialPageIndex,
          );
          _activePaneIndex = 0;
        });
        _scheduleSavingStateAttach();
      }
    }
    if (widget.primaryPath != oldWidget.primaryPath ||
        widget.primaryPdfPath != oldWidget.primaryPdfPath) {
      final closingState = _primary.key.currentState;
      if (closingState != null) {
        unawaited(closingState.saveToFile(force: true));
      }
      setState(() {
        _primary = _EditorSlot(
          path: widget.primaryPath,
          pdfPath: widget.primaryPdfPath,
          key: GlobalKey<EditorState>(),
        );
      });
      _scheduleSavingStateAttach();
    }
    if (widget.initialAxis != oldWidget.initialAxis) {
      _splitAxis = widget.initialAxis;
    }
  }

  @override
  void dispose() {
    _detachSavingStateListeners();
    _combinedSavingState.dispose();
    super.dispose();
  }

  void _scheduleSavingStateAttach() {
    if (_attachScheduled) return;
    _attachScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attachScheduled = false;
      _attachSavingStateListeners();
    });
  }

  void _detachSavingStateListeners() {
    _primarySavingNotifier?.removeListener(_updateCombinedSavingState);
    _secondarySavingNotifier?.removeListener(_updateCombinedSavingState);
    _primarySavingNotifier = null;
    _secondarySavingNotifier = null;
  }

  void _attachSavingStateListeners() {
    final nextPrimary = _primary.key.currentState?.savingState;
    final nextSecondary = _secondary?.key.currentState?.savingState;

    if (_primarySavingNotifier != nextPrimary) {
      _primarySavingNotifier?.removeListener(_updateCombinedSavingState);
      _primarySavingNotifier = nextPrimary;
      _primarySavingNotifier?.addListener(_updateCombinedSavingState);
    }

    if (_secondarySavingNotifier != nextSecondary) {
      _secondarySavingNotifier?.removeListener(_updateCombinedSavingState);
      _secondarySavingNotifier = nextSecondary;
      _secondarySavingNotifier?.addListener(_updateCombinedSavingState);
    }

    _updateCombinedSavingState();
  }

  void _updateCombinedSavingState() {
    final states = <SavingState?>[
      _primarySavingNotifier?.value,
      _secondarySavingNotifier?.value,
    ];
    if (states.any((state) => state == SavingState.saving)) {
      _combinedSavingState.value = SavingState.saving;
    } else if (states.any((state) => state == SavingState.waitingToSave)) {
      _combinedSavingState.value = SavingState.waitingToSave;
    } else {
      _combinedSavingState.value = SavingState.saved;
    }
  }

  Future<void> _saveAllAsync({bool force = false}) async {
    final futures = <Future<void>>[];
    final primaryState = _primary.key.currentState;
    final secondaryState = _secondary?.key.currentState;
    if (primaryState != null)
      futures.add(primaryState.saveToFile(force: force));
    if (secondaryState != null)
      futures.add(secondaryState.saveToFile(force: force));
    await Future.wait(futures);
  }

  void _setActivePane(int index) {
    if (_activePaneIndex == index) return;
    setState(() {
      _activePaneIndex = index;
    });
  }

  void _setActivePaneAfterPointer(int index) {
    if (_activePaneIndex == index) return;
    _pendingActivePaneIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targetIndex = _pendingActivePaneIndex;
      _pendingActivePaneIndex = null;
      if (targetIndex == null || targetIndex == _activePaneIndex) return;
      _setActivePane(targetIndex);
    });
  }

  Future<void> _openSecondNote() async {
    if (_secondary != null) return;
    final primaryPath =
        _primary.key.currentState?.coreInfo.filePath ?? _primary.path ?? '';
    final selected = await _pickNotePath(context, excludePaths: {primaryPath});
    if (!mounted || selected == null) return;

    setState(() {
      _secondary = _EditorSlot(path: selected, key: GlobalKey<EditorState>());
      _activePaneIndex =
          0;
      _splitFraction = 0.5;
    });
    _scheduleSavingStateAttach();
  }

  void _closeSplitView() {
    if (_secondary == null) return;

    _collapseToSingle(keepPrimary: _activePaneIndex != 0);
  }

  Future<void> _reopenSplitView() async {
    if (_secondary == null) return;
    final primaryPath =
        _primary.key.currentState?.coreInfo.filePath ?? _primary.path ?? '';
    final secondaryPath =
        _secondary!.key.currentState?.coreInfo.filePath ??
        _secondary!.path ??
        '';
    final otherPath = _activePaneIndex == 0 ? secondaryPath : primaryPath;
    final selected = await _pickNotePath(context, excludePaths: {otherPath});
    if (!mounted || selected == null) return;
    final activeState = _activePaneIndex == 0
        ? _primary.key.currentState
        : _secondary?.key.currentState;
    if (activeState != null) {
      unawaited(activeState.saveToFile(force: true));
    }
    if (!mounted) return;
    final newPrimary = _activePaneIndex == 0 ? selected : primaryPath;
    final newSecondary = _activePaneIndex == 0 ? secondaryPath : selected;
    context.go(
      RoutePaths.editSplit(newPrimary, newSecondary, axis: _splitAxis),
    );
  }

  void _collapseToSingle({required bool keepPrimary}) {
    if (_secondary == null) return;

    final closingSlot = keepPrimary ? _secondary : _primary;
    final keepSlot = keepPrimary ? _primary : _secondary!;
    if (closingSlot != null) {
      final closingState = closingSlot.key.currentState;
      if (closingState != null) {
        unawaited(closingState.saveToFile(force: true));
      }
    }
    final keepPath =
        keepSlot.key.currentState?.coreInfo.filePath ?? keepSlot.path;
    if (!mounted) return;
    if (keepPath == null || keepPath.isEmpty) {
      _goToHome(context);
      return;
    }
    context.go(RoutePaths.editFilePath(keepPath));
  }

  void _swapNotes() {
    if (_secondary == null) return;
    setState(() {
      final temp = _primary;
      _primary = _secondary!;
      _secondary = temp;
      _activePaneIndex = _activePaneIndex == 0 ? 1 : 0;
    });
    _scheduleSavingStateAttach();
  }

  void _toggleSplitAxis() {
    if (_secondary == null) return;
    setState(() {
      _splitAxis = _splitAxis == Axis.horizontal
          ? Axis.vertical
          : Axis.horizontal;
    });
  }

  void _handleResize(DragUpdateDetails details, double availableExtent) {
    if (_secondary == null || availableExtent <= 0) return;

    final delta = _splitAxis == Axis.horizontal
        ? details.delta.dx
        : details.delta.dy;
    final nextFraction = (_splitFraction + delta / availableExtent).clamp(
      0.02,
      0.98,
    );
    if (nextFraction < _minFraction) {
      _collapseToSingle(keepPrimary: false);
      return;
    }
    if (nextFraction > 1 - _minFraction) {
      _collapseToSingle(keepPrimary: true);
      return;
    }
    final primaryExtent = availableExtent * nextFraction;
    final secondaryExtent = availableExtent - primaryExtent;
    if (_splitAxis == Axis.horizontal) {
      _primary.key.currentState?._applyResizeViewportAnchor(
        viewportWidthOverride: primaryExtent,
      );
      _secondary?.key.currentState?._applyResizeViewportAnchor(
        viewportWidthOverride: secondaryExtent,
      );
    } else {
      _primary.key.currentState?._applyResizeViewportAnchor(
        viewportHeightOverride: primaryExtent,
      );
      _secondary?.key.currentState?._applyResizeViewportAnchor(
        viewportHeightOverride: secondaryExtent,
      );
    }
    setState(() {
      _splitFraction = nextFraction;
    });
  }

  void _handleResizeStart() {
    _primary.key.currentState?._lockResizeViewportAnchor();
    _secondary?.key.currentState?._lockResizeViewportAnchor();
  }

  void _handleResizeEnd() {
    _primary.key.currentState?._applyResizeViewportAnchor();
    _secondary?.key.currentState?._applyResizeViewportAnchor();
    _primary.key.currentState?._unlockResizeViewportAnchor();
    _secondary?.key.currentState?._unlockResizeViewportAnchor();
  }

  List<Widget> _buildSplitAppBarActions() {
    if (_secondary == null) return const [];
    return [
      IconButton(
        icon: const Icon(Icons.folder_open),
        tooltip: "Reopen split view",
        onPressed: _reopenSplitView,
      ),
      IconButton(
        icon: Icon(
          _splitAxis == Axis.horizontal ? Icons.view_day : Icons.view_week,
        ),
        tooltip: _splitAxis == Axis.horizontal
            ? "Switch to Top/Bottom"
            : "Switch to Left/Right",
        onPressed: _toggleSplitAxis,
      ),
      IconButton(
        icon: const Icon(Icons.swap_horiz),
        tooltip: "Swap Notes",
        onPressed: _swapNotes,
      ),
      IconButton(
        icon: const Icon(Icons.close),
        tooltip: "Close Split View",
        onPressed: _closeSplitView,
      ),
    ];
  }

  Widget _buildPane(
    _EditorSlot slot,
    int index, {
    double? viewportWidthOverride,
    double? viewportHeightOverride,
  }) {
    final isActive = _activePaneIndex == index;
    final editor = Editor(
      key: slot.key,
      path: slot.path,
      pdfPath: slot.pdfPath,
      initialPageIndexOverride: slot.initialPageIndex,
      embedded: true,
      viewportWidthOverride: viewportWidthOverride,
      viewportHeightOverride: viewportHeightOverride,

      showToolbar: false,
      onOpenSplitView: _openSecondNote,
      onCloseSplitView: _closeSplitView,
      onReopenSplitView: _reopenSplitView,
      onSwapSplitView: _swapNotes,
      onToggleSplitAxis: _toggleSplitAxis,
      splitHasSecondary: _secondary != null,
      splitAxis: _splitAxis,
      splitPrimaryPath: widget.primaryPath,
    );
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _setActivePaneAfterPointer(index),
      child: Stack(
        fit: StackFit.expand,
        children: [
          editor,

          if (isActive)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _goToHome(BuildContext context) {
    context.go('${RoutePaths.prefixOfHome}/${HomePage.recentSubpage}');
  }

  PreferredSizeWidget? _buildAppBar(BuildContext context) {
    if (DynamicMaterialApp.isFullscreen) return null;
    final activeState = _activePaneIndex == 0
        ? _primary.key.currentState
        : _secondary?.key.currentState;
    if (activeState == null) {
      return AppBar(title: const Text('Editor'));
    }

    final baseAppBar = activeState._buildEditorAppBar(
      context,
      savingStateOverride: _combinedSavingState,
      triggerSaveOverride: ({bool force = false}) =>
          _saveAllAsync(force: force),
      extraActions: _buildSplitAppBarActions(),
      onBackOverride: () => _goToHome(context),
    );

    return _SplitViewAppBarWithPdfProgress(
      baseAppBar: baseAppBar,
      pdfLoadingState:
          activeState.coreInfo.assetCacheAll.pdfLoadingState,
    );
  }

  Widget _buildSplitBody(BoxConstraints constraints) {
    if (_secondary == null) {
      return _buildPane(_primary, 0);
    }

    final maxExtent = _splitAxis == Axis.horizontal
        ? constraints.maxWidth
        : constraints.maxHeight;
    final availableExtent = (maxExtent - _dividerThickness)
        .clamp(0.0, maxExtent)
        .toDouble();
    final primaryExtent = availableExtent * _splitFraction;
    final secondaryExtent = availableExtent - primaryExtent;

    final colorScheme = Theme.of(context).colorScheme;
    final divider = MouseRegion(
      cursor: _splitAxis == Axis.horizontal
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => _handleResizeStart(),
        onPanUpdate: (details) => _handleResize(details, availableExtent),
        onPanEnd: (_) => _handleResizeEnd(),
        onPanCancel: _handleResizeEnd,
        child: Container(
          width: _splitAxis == Axis.horizontal ? _dividerThickness : null,
          height: _splitAxis == Axis.vertical ? _dividerThickness : null,
          color: colorScheme.surface,
          alignment: Alignment.center,
          child: RotatedBox(
            quarterTurns: _splitAxis == Axis.horizontal ? 0 : 1,
            child: Icon(
              Icons.drag_handle,
              size: 16,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );

    if (_splitAxis == Axis.horizontal) {
      return Row(
        children: [
          SizedBox(
            width: primaryExtent,
            child: _buildPane(
              _primary,
              0,
              viewportWidthOverride: primaryExtent,
            ),
          ),
          divider,
          SizedBox(
            width: secondaryExtent,
            child: _buildPane(
              _secondary!,
              1,
              viewportWidthOverride: secondaryExtent,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        SizedBox(
          height: primaryExtent,
          child: _buildPane(_primary, 0, viewportHeightOverride: primaryExtent),
        ),
        divider,
        SizedBox(
          height: secondaryExtent,
          child: _buildPane(
            _secondary!,
            1,
            viewportHeightOverride: secondaryExtent,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _scheduleSavingStateAttach();
    final activeState = _activePaneIndex == 0
        ? _primary.key.currentState
        : _secondary?.key.currentState;
    final axisDir = stows.editorToolbarAlignment.value;
    final globalToolbar = activeState == null
        ? null
        : activeState._buildSplitGlobalToolbar(
            context,
            onHostToolbarChanged: () {
              if (!mounted) return;
              setState(() {});
            },
          );
    final splitBody = LayoutBuilder(
      builder: (context, constraints) => _buildSplitBody(constraints),
    );
    Widget body;
    if (globalToolbar == null) {
      body = splitBody;
    } else {
      final isToolbarVertical =
          axisDir == AxisDirection.left || axisDir == AxisDirection.right;
      if (isToolbarVertical) {
        body = Row(
          textDirection: axisDir == AxisDirection.left
              ? TextDirection.ltr
              : TextDirection.rtl,
          children: [
            globalToolbar,
            Expanded(child: splitBody),
          ],
        );
      } else {
        body = Column(
          verticalDirection: axisDir == AxisDirection.up
              ? VerticalDirection.up
              : VerticalDirection.down,
          children: [
            Expanded(child: splitBody),
            SizedBox(width: double.infinity, child: globalToolbar),
          ],
        );
      }
    }

    if (activeState != null && axisDir == AxisDirection.up) {
      final pdfLoadingState =
          activeState.coreInfo.assetCacheAll.pdfLoadingState;
      final bodyWithoutProgress = body;
      body = ValueListenableBuilder<
          ({double progress, String label})?>(
        valueListenable: pdfLoadingState,
        builder: (context, pdfLoading, _) {
          if (pdfLoading != null) {
            return Column(
              children: [
                Expanded(child: bodyWithoutProgress),
                _PdfDecryptProgressBar(
                  progress: pdfLoading.progress,
                  label: pdfLoading.label,
                ),
              ],
            );
          }
          return bodyWithoutProgress;
        },
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _goToHome(context);
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: _buildAppBar(context),
        body: body,
      ),
    );
  }
}

Future<String?> _pickNotePath(
  BuildContext context, {
  required Set<String> excludePaths,
}) async {
  return showDialog<String>(
    context: context,
    builder: (context) => _NotePickerDialog(excludePaths: excludePaths),
  );
}

class _NotePickerDialog extends StatefulWidget {
  const _NotePickerDialog({required this.excludePaths});

  final Set<String> excludePaths;

  @override
  State<_NotePickerDialog> createState() => _NotePickerDialogState();
}

class _NotePickerDialogState extends State<_NotePickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  final Future<List<String>> _futureRecent = FileManager.getRecentlyAccessed();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (!mounted) return;
      setState(() {
        _search = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            width: 720,
            height: MediaQuery.of(context).size.height * 0.8,
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1C1C1E).withValues(alpha: 0.85)
                  : colorScheme.surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : colorScheme.outlineVariant.withValues(alpha: 0.4),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 32,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Text(
                    'Open Second Note',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search notes...',
                      filled: true,
                      fillColor: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : colorScheme.surfaceContainerHighest.withValues(
                              alpha: 0.5,
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: _search.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => _searchController.clear(),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: FutureBuilder<List<String>>(
                      future: _futureRecent,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final files = snapshot.data ?? const <String>[];
                        final filtered = files.where((file) {
                          if (widget.excludePaths.contains(file)) return false;
                          final name = file.split('/').last;
                          if (name.startsWith('.') ||
                              name.startsWith('TmPmP_') ||
                              name.contains('.sbn2.')) {
                            return false;
                          }
                          if (_search.isEmpty) return true;
                          return name.toLowerCase().contains(_search) ||
                              file.toLowerCase().contains(_search);
                        }).toList();

                        if (filtered.isEmpty) {
                          return const Center(
                            child: Text('No notes match this search.'),
                          );
                        }

                        return ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final path = filtered[index];
                            final name = path.split('/').last;
                            return ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.1)
                                      : colorScheme.outlineVariant.withValues(
                                          alpha: 0.3,
                                        ),
                                  width: 1,
                                ),
                              ),
                              tileColor: isDark
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : colorScheme.surfaceContainerHighest
                                        .withValues(alpha: 0.3),
                              leading: _NoteThumbnail(filePath: path),
                              title: Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                path,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => Navigator.pop(context, path),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          MaterialLocalizations.of(context).cancelButtonLabel,
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.tonal(
                        onPressed: () async {
                          final selected = await _pickNoteFromFilePicker();
                          if (!context.mounted || selected == null) return;
                          Navigator.pop(context, selected);
                        },
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Pick File'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoteThumbnail extends StatefulWidget {
  const _NoteThumbnail({required this.filePath});

  final String filePath;

  @override
  State<_NoteThumbnail> createState() => _NoteThumbnailState();
}

class _NoteThumbnailState extends State<_NoteThumbnail> {
  MemoryImage? _thumb;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _NoteThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _thumb = null;
      _load();
    }
  }

  Future<void> _load() async {
    final bytes = await FileManager.readFile(
      '${widget.filePath}${Editor.extension}.p',
      retries: 0,
      suppressLogs: true,
      allowMissing: true,
    );
    if (!mounted || bytes == null || bytes.isEmpty) return;
    setState(() {
      _thumb = MemoryImage(bytes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surface;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 56,
        height: 72,
        child: _thumb != null
            ? Image(image: _thumb!, fit: BoxFit.cover)
            : ColoredBox(
                color: color,
                child: const Icon(Icons.description_outlined, size: 20),
              ),
      ),
    );
  }
}

Future<String?> _pickNoteFromFilePicker() async {
  VaultAdapter.preventLock = true;
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['sbn2', 'sbn'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.first.path;
  } finally {
    VaultAdapter.preventLock = false;
  }
}
