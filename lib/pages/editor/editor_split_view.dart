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
  final ValueNotifier<int> _activePane = ValueNotifier(0);
  final ValueNotifier<int> _chromeEpoch = ValueNotifier(0);
  int? _pendingActivePaneIndex;
  Listenable? _chromeListenable;

  int get _activePaneIndex => _activePane.value;

  final ValueNotifier<SavingState> _combinedSavingState = ValueNotifier(
    SavingState.saved,
  );
  ValueNotifier<SavingState>? _primarySavingNotifier;
  ValueNotifier<SavingState>? _secondarySavingNotifier;
  bool _attachScheduled = false;
  bool _activeEditorReadyRefreshScheduled = false;

  void _bumpChrome() {
    if (!mounted) return;
    _chromeEpoch.value++;
  }

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
      // Focus the newly opened second note so its title + toolbar show.
      _activePane.value = 1;
    }
    _splitAxis = widget.initialAxis;
    _chromeListenable = Listenable.merge([_activePane, _chromeEpoch]);
    _scheduleSavingStateAttach();
    _scheduleActiveEditorReadyRefresh();
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
          final primary = _primary.key.currentState;
          primary?._beginViewportResizeStabilization(freezePageLayout: false);
          setState(() {
            _secondary = null;
            _activePane.value = 0;
          });
          _scheduleSavingStateAttach();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              primary?._endViewportResizeStabilization();
            });
          });
        }
      } else {
        final closingState = _secondary?.key.currentState;
        if (closingState != null) {
          unawaited(closingState.saveToFile(force: true));
        }
        final hadSecondary = _secondary != null;
        final primary = _primary.key.currentState;
        // Primary canvas shrinks when a second pane appears for the first time.
        if (!hadSecondary) {
          primary?._beginViewportResizeStabilization(freezePageLayout: false);
        }
        setState(() {
          _secondary = _EditorSlot(
            path: widget.secondaryPath,
            key: GlobalKey<EditorState>(),
            initialPageIndex: widget.secondaryInitialPageIndex,
          );
          _activePane.value = 1;
        });
        _scheduleSavingStateAttach();
        _scheduleActiveEditorReadyRefresh();
        if (!hadSecondary) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              primary?._endViewportResizeStabilization();
            });
          });
        }
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
      _scheduleActiveEditorReadyRefresh();
    }
    if (widget.initialAxis != oldWidget.initialAxis) {
      _splitAxis = widget.initialAxis;
    }
  }

  @override
  void dispose() {
    _detachSavingStateListeners();
    _combinedSavingState.dispose();
    _activePane.dispose();
    _chromeEpoch.dispose();
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

  EditorState? get _activeEditorState {
    if (_activePaneIndex == 0) return _primary.key.currentState;
    return _secondary?.key.currentState;
  }

  _EditorSlot get _activeEditorSlot {
    if (_activePaneIndex == 0 || _secondary == null) return _primary;
    return _secondary!;
  }

  /// Parent does not rebuild when an embedded [Editor] mounts, so app bar /
  /// toolbar can stay on the empty "Editor" placeholder. Refresh once ready.
  void _scheduleActiveEditorReadyRefresh() {
    if (_activeEditorReadyRefreshScheduled) return;
    _activeEditorReadyRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _activeEditorReadyRefreshScheduled = false;
      if (!mounted) return;
      _attachSavingStateListeners();
      if (_activeEditorState == null) {
        _scheduleActiveEditorReadyRefresh();
        return;
      }
      _bumpChrome();
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
    if (_activePane.value == index) return;
    // Chrome only (app bar, toolbar, focus ring). Rebuilding the host
    // Scaffold used to rebuild both [Editor]s mid-stroke and flash ink.
    _activePane.value = index;
  }

  void _setActivePaneAfterPointer(int index) {
    _pendingActivePaneIndex = index;
  }

  void _flushPendingActivePane() {
    final targetIndex = _pendingActivePaneIndex;
    _pendingActivePaneIndex = null;
    if (!mounted || targetIndex == null) return;
    _setActivePane(targetIndex);
  }

  Future<void> _openSecondNote() async {
    if (_secondary != null) return;
    final primaryPath =
        _primary.key.currentState?.coreInfo.filePath ?? _primary.path ?? '';
    final selected = await _pickNotePath(context, excludePaths: {primaryPath});
    if (!mounted || selected == null) return;

    // Capture the primary page before its canvas width halves.
    final primary = _primary.key.currentState;
    primary?._beginViewportResizeStabilization(freezePageLayout: false);

    setState(() {
      _secondary = _EditorSlot(path: selected, key: GlobalKey<EditorState>());
      _activePane.value = 1;
      _splitFraction = 0.5;
    });
    _scheduleSavingStateAttach();
    _scheduleActiveEditorReadyRefresh();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        primary?._endViewportResizeStabilization();
      });
    });
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
    // Focused pane is replaced; keep the other note open.
    final focusedPath = _activePaneIndex == 0 ? primaryPath : secondaryPath;
    final otherPath = _activePaneIndex == 0 ? secondaryPath : primaryPath;
    final selected = await _pickNotePath(
      context,
      excludePaths: {
        if (otherPath.isNotEmpty) otherPath,
        if (focusedPath.isNotEmpty) focusedPath,
      },
    );
    if (!mounted || selected == null || selected.isEmpty) return;

    final activeState = _activePaneIndex == 0
        ? _primary.key.currentState
        : _secondary?.key.currentState;
    if (activeState != null) {
      unawaited(activeState.saveToFile(force: true));
    }
    if (!mounted) return;

    // Replace the focused slot in place — context.go() was crashing by
    // tearing down both editors while a save/picker frame was still active.
    setState(() {
      final replacement = _EditorSlot(
        path: selected,
        key: GlobalKey<EditorState>(),
      );
      if (_activePaneIndex == 0) {
        _primary = replacement;
      } else {
        _secondary = replacement;
      }
    });
    _scheduleSavingStateAttach();
    _scheduleActiveEditorReadyRefresh();
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
    _primary.key.currentState?._beginViewportResizeStabilization();
    _secondary?.key.currentState?._beginViewportResizeStabilization();
    setState(() {
      final temp = _primary;
      _primary = _secondary!;
      _secondary = temp;
      _activePane.value = _activePane.value == 0 ? 1 : 0;
    });
    _scheduleSavingStateAttach();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _primary.key.currentState?._endViewportResizeStabilization();
      _secondary?.key.currentState?._endViewportResizeStabilization();
    });
  }

  void _toggleSplitAxis() {
    if (_secondary == null) return;
    _primary.key.currentState?._beginViewportResizeStabilization();
    _secondary?.key.currentState?._beginViewportResizeStabilization();
    setState(() {
      _splitAxis = _splitAxis == Axis.horizontal
          ? Axis.vertical
          : Axis.horizontal;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _primary.key.currentState?._endViewportResizeStabilization();
      _secondary?.key.currentState?._endViewportResizeStabilization();
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
      _primary.key.currentState?._endViewportResizeStabilization();
      _secondary?.key.currentState?._endViewportResizeStabilization();
      _collapseToSingle(keepPrimary: false);
      return;
    }
    if (nextFraction > 1 - _minFraction) {
      _primary.key.currentState?._endViewportResizeStabilization();
      _secondary?.key.currentState?._endViewportResizeStabilization();
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
    _primary.key.currentState?._beginViewportResizeStabilization();
    _secondary?.key.currentState?._beginViewportResizeStabilization();
  }

  void _handleResizeEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _primary.key.currentState?._endViewportResizeStabilization();
      _secondary?.key.currentState?._endViewportResizeStabilization();
    });
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
    final editor = RepaintBoundary(
      child: Editor(
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
        onEmbeddedChromeChanged: _bumpChrome,
      ),
    );
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _setActivePaneAfterPointer(index),
      onPointerUp: (_) => _flushPendingActivePane(),
      onPointerCancel: (_) => _flushPendingActivePane(),
      child: ListenableBuilder(
        listenable: _activePane,
        child: editor,
        builder: (context, editorChild) {
          final isActive = _activePane.value == index;
          return Stack(
            fit: StackFit.expand,
            children: [
              editorChild!,
              if (isActive)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: .78),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _goToHome(BuildContext context) {
    unawaited(_goToHomeAfterThumbnails(context));
  }

  Future<void> _goToHomeAfterThumbnails(BuildContext context) async {
    await Future.wait([
      _primary.key.currentState?._flushThumbnailBeforeExit() ??
          Future<void>.value(),
      _secondary?.key.currentState?._flushThumbnailBeforeExit() ??
          Future<void>.value(),
    ]);
    // Seed Recent for notes that will persist; drop empty ones that dispose
    // will auto-delete so their preview cards do not linger on Home.
    final remember = <String>[];
    final forget = <String>[];
    void consider(EditorState? state, String? fallbackPath) {
      final path = state?.coreInfo.filePath ?? fallbackPath;
      if (path == null || path.isEmpty) return;
      if (state != null && state.wouldAutoDeleteOnExit) {
        forget.add(path);
      } else {
        remember.add(path);
      }
    }

    consider(_primary.key.currentState, _primary.path);
    consider(_secondary?.key.currentState, _secondary?.path);
    if (forget.isNotEmpty) {
      HomeDataCache.instance.forgetRecentPaths(forget);
    }
    if (remember.isNotEmpty) {
      HomeDataCache.instance.rememberRecentPaths(remember);
    }
    if (!context.mounted) return;
    context.go('${RoutePaths.prefixOfHome}/${HomePage.recentSubpage}');
  }

  String _fallbackTitleForSlot(_EditorSlot slot) {
    final path = slot.key.currentState?.coreInfo.filePath ?? slot.path ?? '';
    if (path.isEmpty) return 'Editor';
    final name = path.split('/').last;
    return name
        .replaceAll(RegExp(r'\.sbn2?$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\.sba$', caseSensitive: false), '');
  }

  PreferredSizeWidget? _buildAppBar(BuildContext context) {
    if (DynamicMaterialApp.isFullscreen &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return null;
    }
    final activeState = _activeEditorState;
    if (activeState == null) {
      return AppBar(
        primary: false,
        title: Text(_fallbackTitleForSlot(_activeEditorSlot)),
      );
    }

    return activeState._buildEditorAppBar(
      context,
      savingStateOverride: _combinedSavingState,
      triggerSaveOverride: ({bool force = false}) =>
          _saveAllAsync(force: force),
      extraActions: _buildSplitAppBarActions(),
      onBackOverride: () => _goToHome(context),
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
          color: colorScheme.surfaceContainerHighest.withValues(alpha: .45),
          alignment: Alignment.center,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withValues(alpha: .22),
              borderRadius: BorderRadius.circular(999),
            ),
            child: SizedBox(
              width: _splitAxis == Axis.horizontal ? 4 : 44,
              height: _splitAxis == Axis.horizontal ? 44 : 4,
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
    final splitBody = LayoutBuilder(
      builder: (context, constraints) => _buildSplitBody(constraints),
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _goToHome(context);
        }
      },
      child: ListenableBuilder(
        listenable: _chromeListenable!,
        child: splitBody,
        builder: (context, canvases) {
          final activeState = _activeEditorState;
          if (activeState == null) {
            _scheduleActiveEditorReadyRefresh();
          }
          final axisDir = stows.editorToolbarAlignment.value;
          final globalToolbar = activeState == null
              ? null
              : activeState._buildSplitGlobalToolbar(
                  context,
                  onHostToolbarChanged: _bumpChrome,
                );
          Widget body;
          if (globalToolbar == null) {
            body = canvases!;
          } else {
            final isToolbarVertical =
                axisDir == AxisDirection.left ||
                axisDir == AxisDirection.right;
            if (isToolbarVertical) {
              body = Row(
                textDirection: axisDir == AxisDirection.left
                    ? TextDirection.ltr
                    : TextDirection.rtl,
                children: [
                  globalToolbar,
                  Expanded(child: canvases!),
                ],
              );
            } else {
              body = Column(
                verticalDirection: axisDir == AxisDirection.up
                    ? VerticalDirection.up
                    : VerticalDirection.down,
                children: [
                  Expanded(child: canvases!),
                  SizedBox(width: double.infinity, child: globalToolbar),
                ],
              );
            }
          }
          return Scaffold(
            resizeToAvoidBottomInset: false,
            appBar: _buildAppBar(context),
            body: body,
          );
        },
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

class _NotePickerEntry {
  const _NotePickerEntry({
    required this.path,
    required this.name,
    required this.tags,
  });

  final String path;
  final String name;
  final Set<String> tags;
}

class _NotePickerDialogState extends State<_NotePickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  late Future<DirectoryChildren?> _childrenFuture;
  late Future<List<_NotePickerEntry>> _allNotesFuture;
  String _search = '';
  String _currentDirectory = '/';

  @override
  void initState() {
    super.initState();
    _childrenFuture = _loadChildren(_currentDirectory);
    _allNotesFuture = _loadAllNotes();
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

  String _normalizeNotePath(String path) {
    var normalized = path.replaceAll('\\', '/');
    if (normalized.endsWith(Editor.extension)) {
      normalized = normalized.substring(
        0,
        normalized.length - Editor.extension.length,
      );
    } else if (normalized.endsWith(Editor.extensionOldJson)) {
      normalized = normalized.substring(
        0,
        normalized.length - Editor.extensionOldJson.length,
      );
    }
    if (!normalized.startsWith('/') && !normalized.contains('://')) {
      normalized = '/$normalized';
    }
    return normalized;
  }

  Set<String> get _excludedNormalized =>
      widget.excludePaths.map(_normalizeNotePath).toSet();

  String _joinDirectory(String parent, String child) {
    final base = parent.endsWith('/') ? parent : '$parent/';
    return _normalizeDirectoryPath('$base$child/');
  }

  String _joinFile(String parent, String child) {
    final base = parent.endsWith('/') ? parent : '$parent/';
    return _normalizeNotePath('$base$child');
  }

  String _normalizeDirectoryPath(String path) {
    var normalized = path.replaceAll('\\', '/');
    if (!normalized.startsWith('/')) normalized = '/$normalized';
    if (!normalized.endsWith('/')) normalized = '$normalized/';
    return normalized;
  }

  String _displayName(String path) {
    final normalized = _normalizeNotePath(path);
    final withoutSlash = normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    final name = withoutSlash.split('/').last;
    return name.isEmpty ? 'Untitled' : name;
  }

  List<String> _breadcrumbs(String directory) {
    final clean = directory
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    return clean;
  }

  Future<DirectoryChildren?> _loadChildren(String directory) async {
    final children = await FileTreeCache.instance.getChildren(directory);
    if (children == null) return null;

    final directories =
        children.directories.where((name) => !name.startsWith('.')).toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final files = children.files.where((name) {
      if (name.startsWith('.')) return false;
      final path = _joinFile(directory, name);
      return !_excludedNormalized.contains(path);
    }).toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return DirectoryChildren(
      directories,
      files,
      linkedDirectories: children.linkedDirectories,
      linkedFiles: children.linkedFiles,
    );
  }

  Future<List<_NotePickerEntry>> _loadAllNotes() async {
    final files = await FileManager.getAllFiles();
    final normalized =
        files
            .map(_normalizeNotePath)
            .where((path) => !_excludedNormalized.contains(path))
            .where((path) => !Editor.isReservedPath(path))
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final tagsByPath = await TagDatabase.instance.getTagsForPaths(normalized);
    return [
      for (final path in normalized)
        _NotePickerEntry(
          path: path,
          name: _displayName(path),
          tags: tagsByPath[TagDatabase.normalizePath(path)] ?? const <String>{},
        ),
    ];
  }

  void _openDirectory(String directory) {
    final normalized = _normalizeDirectoryPath(directory);
    setState(() {
      _currentDirectory = normalized;
      _childrenFuture = _loadChildren(normalized);
    });
  }

  void _goUp() {
    if (_currentDirectory == '/') return;
    final parts = _breadcrumbs(_currentDirectory);
    parts.removeLast();
    _openDirectory(parts.isEmpty ? '/' : '/${parts.join('/')}/');
  }

  Future<void> _createNewNote() async {
    final path = await FileManager.newFilePath(_currentDirectory);
    if (!mounted) return;
    Navigator.pop(context, path);
  }

  List<_NotePickerEntry> _filterSearch(List<_NotePickerEntry> entries) {
    final query = _search;
    if (query.isEmpty) return entries;
    return entries.where((entry) {
      final path = entry.path.toLowerCase();
      final name = entry.name.toLowerCase();
      final tagMatch = entry.tags.any((tag) {
        final normalizedTag = tag.toLowerCase();
        return normalizedTag.contains(query) ||
            '#$normalizedTag'.contains(query);
      });
      return name.contains(query) || path.contains(query) || tagMatch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final maxDialogHeight = MediaQuery.of(context).size.height * 0.86;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            width: 820,
            height: maxDialogHeight,
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
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 14),
                  child: Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(Icons.view_week_outlined),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Open Second Note',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.35,
                              ),
                            ),
                            Text(
                              'Browse folders, search names or tags, or create a note for split view.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).closeButtonTooltip,
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search all notes by name, folder, or tag...',
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: _createNewNote,
                        icon: const Icon(Icons.add),
                        label: const Text('Create a New Note'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final selected = await _pickNoteFromFilePicker();
                          if (!context.mounted || selected == null) return;
                          Navigator.pop(context, selected);
                        },
                        icon: const Icon(Icons.folder_open_outlined),
                        label: const Text('Pick File'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _search.isEmpty
                        ? _buildBrowser(context, theme, colorScheme, isDark)
                        : _buildSearch(context, theme, colorScheme, isDark),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _search.isEmpty
                              ? 'Current folder: $_currentDirectory'
                              : 'Searching the full note library',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          MaterialLocalizations.of(context).cancelButtonLabel,
                        ),
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

  Widget _buildBrowser(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    return FutureBuilder<DirectoryChildren?>(
      future: _childrenFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        final children = snapshot.data;
        if (children == null) {
          return _emptyState(
            context,
            icon: Icons.folder_off_outlined,
            title: 'Could not open this folder',
            subtitle: 'Try another folder or use search.',
          );
        }

        final rows = <Widget>[
          _breadcrumbBar(context, theme, colorScheme),
          const SizedBox(height: 12),
          if (_currentDirectory != '/')
            _pickerRow(
              context,
              icon: Icons.arrow_upward,
              title: 'Parent folder',
              subtitle: 'Go up one level',
              onTap: _goUp,
              isDark: isDark,
            ),
          for (final folder in children.directories)
            _pickerRow(
              context,
              icon: Icons.folder_outlined,
              title: folder,
              subtitle: _joinDirectory(_currentDirectory, folder),
              onTap: () =>
                  _openDirectory(_joinDirectory(_currentDirectory, folder)),
              isDark: isDark,
            ),
          for (final linkedFolder in children.linkedDirectories.entries)
            _pickerRow(
              context,
              icon: Icons.folder_special_outlined,
              title: linkedFolder.key,
              subtitle: linkedFolder.value,
              onTap: () => _openDirectory(linkedFolder.value),
              isDark: isDark,
            ),
          for (final file in children.files)
            _noteRow(
              context,
              path: _joinFile(_currentDirectory, file),
              name: file,
              tags: const {},
              isDark: isDark,
            ),
          for (final linkedFile in children.linkedFiles.entries)
            _noteRow(
              context,
              path: _normalizeNotePath(linkedFile.value),
              name: linkedFile.key,
              tags: const {},
              isDark: isDark,
            ),
        ];

        if (rows.length == 2 && children.isEmpty) {
          return _emptyState(
            context,
            icon: Icons.note_add_outlined,
            title: 'This folder has no notes yet',
            subtitle: 'Create a new note here or choose another folder.',
          );
        }

        return ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, index) =>
              index == 0 ? const SizedBox.shrink() : const SizedBox(height: 8),
          itemBuilder: (context, index) => rows[index],
        );
      },
    );
  }

  Widget _buildSearch(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    return FutureBuilder<List<_NotePickerEntry>>(
      future: _allNotesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        final results = _filterSearch(snapshot.data ?? const []);
        if (results.isEmpty) {
          return _emptyState(
            context,
            icon: Icons.search_off,
            title: 'No notes match this search',
            subtitle: 'Search by note name, folder path, or tag.',
          );
        }
        return ListView.separated(
          itemCount: results.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final entry = results[index];
            return _noteRow(
              context,
              path: entry.path,
              name: entry.name,
              tags: entry.tags,
              isDark: isDark,
            );
          },
        );
      },
    );
  }

  Widget _breadcrumbBar(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final parts = _breadcrumbs(_currentDirectory);
    final chips = <Widget>[
      ActionChip(
        avatar: const Icon(Icons.home_outlined, size: 18),
        label: const Text('All notes'),
        onPressed: () => _openDirectory('/'),
      ),
    ];
    final pathBuffer = StringBuffer();
    for (final part in parts) {
      pathBuffer.write('/$part');
      final target = '${pathBuffer.toString()}/';
      chips.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Icon(
            Icons.chevron_right,
            size: 18,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
      chips.add(
        ActionChip(label: Text(part), onPressed: () => _openDirectory(target)),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: .26),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: .22),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: chips),
        ),
      ),
    );
  }

  Widget _pickerRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(icon, color: colorScheme.primary),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noteRow(
    BuildContext context, {
    required String path,
    required String name,
    required Set<String> tags,
    required bool isDark,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.pop(context, path),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _NoteThumbnail(filePath: path),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      path,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final tag in tags.take(4))
                            Chip(
                              label: Text('#$tag'),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.open_in_new, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
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
