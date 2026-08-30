// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

// ignore_for_file: invalid_use_of_protected_member

// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bson/bson.dart';
import 'package:collapsible/collapsible.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as flutter_quill;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:go_router/go_router.dart';
import 'package:keybinder/keybinder.dart';
import 'package:logging/logging.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:pdfrx/pdfrx.dart' hide PdfLink;
import 'package:saber/components/canvas/_asset_cache.dart';
import 'package:saber/components/canvas/_canvas_background_painter.dart';
import 'package:saber/components/canvas/_canvas_painter.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_shape_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/canvas.dart' show Canvas;
import 'package:saber/components/canvas/canvas_background_preview.dart';
import 'package:saber/components/canvas/canvas_context_menu_feel.dart';
import 'package:saber/components/canvas/canvas_gesture_detector.dart';
import 'package:saber/components/canvas/canvas_image.dart';
import 'package:saber/components/canvas/canvas_preview.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
import 'package:saber/components/canvas/page_raster_cache.dart';
import 'package:saber/components/canvas/selection_handles_layout.dart';
import 'package:saber/components/canvas/shape_control_points_overlay.dart';
import 'package:saber/components/canvas/interactive_canvas.dart';
import 'package:saber/components/canvas/save_indicator.dart';
import 'package:saber/components/home/home_toolbar_chrome.dart';
import 'package:saber/components/editor/export_dialog.dart';
import 'package:saber/components/editor/note_properties_dialog.dart';
import 'package:saber/components/editor/pdf_equation_preview.dart';
import 'package:saber/components/editor/pdf_link_detector.dart';
import 'package:saber/components/editor/pdf_page_picker_dialog.dart';
import 'package:saber/components/editor/region_screenshot_overlay.dart';
import 'package:saber/components/editor/sba_export_dialog.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/components/theming/glassmorphic_confirm_dialog.dart';
import 'package:saber/components/theming/throttled_listenable_builder.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/components/theming/dynamic_material_app.dart';
import 'package:saber/components/toolbar/color_bar.dart';
import 'package:saber/components/toolbar/editor_page_manager.dart';
import 'package:saber/components/toolbar/enhanced_toolbar.dart';
import 'package:saber/components/toolbar/notes_color_picker_modal.dart';
import 'package:saber/components/toolbar/floating_calculator.dart';
import 'package:saber/components/toolbar/plot_animation_metadata.dart';
import 'package:saber/data/editor/_color_change.dart';
import 'package:saber/data/editor/canvas_background_pattern.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/editor_recovery_journal.dart';
import 'package:saber/data/editor/link_export_expander.dart';
import 'package:saber/data/editor/editor_history.dart';
import 'package:saber/data/editor/note_tool_settings.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/editor/pdf_outline.dart';
import 'package:saber/data/extensions/change_notifier_extensions.dart';
import 'package:saber/data/extensions/dynamic_extensions.dart';
import 'package:saber/data/extensions/matrix4_extensions.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/home_data_cache.dart';
import 'package:saber/data/file_tree_cache.dart';
import 'package:saber/data/ink_preset_profiles.dart';
import 'package:saber/data/note_links_database.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/data/tags_database.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/laser_pointer.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/pen_size_preset_support.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/data/tools/shape_geometry.dart';
import 'package:saber/data/tools/shape_recognition.dart';
import 'package:saber/data/tools/shape_tool.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/custom_thumbnail_screen.dart';
import 'package:saber/pages/editor/editor_page_settings_body.dart';
import 'package:saber/pages/home/home.dart';
import 'package:saber/pages/home/note_and_ink_defaults_pages.dart';
import 'package:saber/services/display_ink_feel.dart';
import 'package:saber/services/math_solver_service.dart';
import 'package:saber/services/recognition_service.dart';
import 'package:saber/services/sba_encryption.dart';
import 'package:saber/services/thumbnail_cache.dart';
import 'package:saber/services/vault_adapter.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vector_math/vector_math_64.dart' as vmath;

part 'editor_menu.dart';
part 'editor_scrollbar.dart';
part 'editor_split_view.dart';

typedef _PhotoInfo = ({
  Uint8List bytes,
  String extension,
  String path,
  String? fileInfo,
  bool invertible,
});

typedef _LinkTargetCandidate = ({
  String path,
  String displayName,
  Set<String> tags,
});

class _ImageCropState {
  _ImageCropState({required this.image, required this.normalizedCrop});
  final PngEditorImage image;
  Rect normalizedCrop;
}

enum _CropHandle {
  topLeft,
  topCenter,
  topRight,
  centerLeft,
  centerRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
  inside,
}

enum _EditorDockedSidePanel { none, pages, settings }

class _NoteLinkHistoryEntry {
  const _NoteLinkHistoryEntry({required this.path, this.pageIndex});

  final String path;
  final int? pageIndex;
}

class Editor extends StatefulWidget {
  Editor({
    super.key,
    this.path,
    this.customTitle,
    this.pdfPath,
    this.embedded = false,
    this.showToolbar = true,
    this.onOpenSplitView,
    this.onCloseSplitView,
    this.onReopenSplitView,
    this.onSwapSplitView,
    this.onToggleSplitAxis,
    this.splitHasSecondary = false,
    this.splitAxis,
    this.splitPrimaryPath,
    this.viewportWidthOverride,
    this.viewportHeightOverride,
    this.initialPageIndexOverride,
    this.onEmbeddedChromeChanged,
  }) : initialPath = path != null
           ? Future.value(path)
           : FileManager.newFilePath('/'),
       needsNaming = path == null;

  final String? path;
  final Future<String> initialPath;
  final bool needsNaming;

  final String? customTitle;
  final String? pdfPath;
  final bool embedded;
  final bool showToolbar;
  final VoidCallback? onOpenSplitView;
  final VoidCallback? onCloseSplitView;
  final VoidCallback? onReopenSplitView;
  final VoidCallback? onSwapSplitView;
  final VoidCallback? onToggleSplitAxis;
  final bool splitHasSecondary;
  final Axis? splitAxis;

  final String? splitPrimaryPath;
  final double? viewportWidthOverride;
  final double? viewportHeightOverride;
  final int? initialPageIndexOverride;

  /// Split host should rebuild its chrome (app bar) when link-back stack changes.
  final VoidCallback? onEmbeddedChromeChanged;

  static const extension = '.sbn2';

  static const extensionOldJson = '.sbn';

  static const double gapBetweenPages = 16;

  static const double changePageThreshold = 50.0;

  static const Size infinitePageSize = Size(1600, 900);

  static final saberSelectionFormat = SimpleFileFormat(
    mimeTypes: ['application/vnd.saber.selection+bson'],
  );

  static bool isReservedPath(String path) {
    return _reservedFilePaths.any((regex) => regex.hasMatch(path));
  }

  static final _reservedFilePaths = <RegExp>[];

  static var canRasterPdf = true;

  @override
  State<Editor> createState() => EditorState();
}

class EditorState extends State<Editor>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final log = Logger('EditorState');

  late final AnimationController _keepAliveController;
  late final AnimationController _dockedSidePanelController;

  /// Docked Pages / ⋯ menus (non-modal; canvas resizes beside them).
  _EditorDockedSidePanel _dockedSidePanel = _EditorDockedSidePanel.none;
  int _pagesSidePanelIndexAtOpen = 0;
  bool _dockedSidePanelOcclusionActive = false;

  late var coreInfo = EditorCoreInfo(filePath: '');

  ThemeData? _cachedTheme;
  MediaQueryData? _cachedMediaQuery;

  final _canvasGestureDetectorKey = GlobalKey<CanvasGestureDetectorState>();
  final _transformationController = TransformationController();
  final _skipTransformClampForExpansion = ValueNotifier<bool>(false);
  final _suppressTransformClamp = ValueNotifier<bool>(false);
  bool _resizeAnchorApplyScheduled = false;
  double? _pendingResizeAnchorWidthOverride;
  double? _pendingResizeAnchorHeightOverride;
  bool _applyingResizeAnchor = false;
  /// True while [didChangeMetrics] owns the active resize-anchor session.
  bool _metricsOwnsResizeSession = false;
  /// Coalesces [didChangeMetrics] settle callbacks (orientation / window size).
  int _metricsSettleEpoch = 0;
  /// Last logical window size — ignore keyboard-only [didChangeMetrics].
  Size? _lastMetricsLogicalSize;

  /// Invalidates stale [AnimationController] completion callbacks when a newer
  /// open/close starts (prevents panel state getting stuck mid-animation).
  int _dockedSidePanelAnimEpoch = 0;
  bool _canvasGestureActive = false;

  final _scrollPhysicsStopNotifier = ValueNotifier<int>(0);
  late final PageRasterCacheManager _pageRasterCache = PageRasterCacheManager(
    onRepaintRequested: _onPageRasterRepaint,
  );
  int? _lastPageRasterBandStart;
  int? _lastPageRasterBandEnd;

  void _onPageRasterRepaint() {
    if (mounted) setState(() {});
  }

  double _canvasDevicePixelRatio() {
    final view = View.maybeOf(context);
    if (view != null) {
      return view.devicePixelRatio.clamp(1.0, 4.0);
    }
    return MediaQuery.devicePixelRatioOf(context).clamp(1.0, 4.0);
  }

  void _onPageRasterLodSettled() {
    if (!mounted || coreInfo.pages.isEmpty) return;
    final scale =
        PageRasterCacheManager.liveViewportScale ?? _quantizedCanvasScale;
    final dpr = _canvasDevicePixelRatio();
    _pageRasterCache.prepareForSettledScale(scale: scale, devicePixelRatio: dpr);
    final center = currentPageIndex.clamp(0, coreInfo.pages.length - 1);
    final radius = 2;
    final bandStart =
        _lastPageRasterBandStart ??
        (center - radius).clamp(0, coreInfo.pages.length - 1);
    final bandEnd =
        _lastPageRasterBandEnd ??
        (center + radius).clamp(0, coreInfo.pages.length - 1);
    _maintainPageRasterBand(
      bandStart,
      bandEnd,
      forceSchedule: true,
      scale: scale,
    );
    setState(() {});
  }

  void _maintainPageRasterBand(
    int bandStart,
    int bandEnd, {
    bool forceSchedule = false,
    double? scale,
  }) {
    if (coreInfo.pages.isEmpty) return;
    _lastPageRasterBandStart = bandStart;
    _lastPageRasterBandEnd = bandEnd;
    final theme = _cachedTheme ?? ThemeData.light();
    final invert = theme.brightness == Brightness.dark
        ? (stows.noteInvertInDarkModeOverrides.value[coreInfo.filePath] == 1)
        : false;
    _pageRasterCache.maintainVisibleBand(
      coreInfo: coreInfo,
      visibleStart: bandStart,
      visibleEnd: bandEnd,
      scale: scale ?? _quantizedCanvasScale,
      devicePixelRatio: _canvasDevicePixelRatio(),
      forceSchedule: forceSchedule,
      invert: invert,
      primaryColor: theme.colorScheme.primary,
      secondaryColor: theme.colorScheme.secondary,
      defaultTextStyle: theme.textTheme.bodyMedium ?? const TextStyle(),
      defaultLineHeight: coreInfo.lineHeight,
      defaultLineThickness: coreInfo.lineThickness.toDouble(),
      defaultPattern: coreInfo.backgroundPattern,
      defaultBackgroundColor:
          coreInfo.backgroundColor ?? InnerCanvas.defaultBackgroundColor,
    );
  }

  double get scrollY {
    final transformation = _transformationController.value;
    final scale = transformation.approxScale;
    final translation = transformation.getTranslation();
    final gestureDetector = _canvasGestureDetectorKey.currentState;

    if (gestureDetector == null) {
      return translation.y / scale;
    } else {
      final middle = gestureDetector.containerBounds.maxHeight / 2;
      return (translation.y - middle) / scale + middle;
    }
  }

  final GlobalKey<EnhancedToolbarState> _toolbarKey = GlobalKey();
  var history = EditorHistory();

  late bool needsNaming = widget.needsNaming && stows.editorPromptRename.value;

  late Tool _currentTool = () {
    switch (stows.lastPenType.value) {
      case ToolId.ballpointPen:
        Pen.currentPen = Pen.ballpointPen();
        break;
      case ToolId.calligraphyPen:
        Pen.currentPen = Pen.calligraphyPen();
        break;
      case ToolId.shapePen:
        Pen.currentPen = Pen.ballpointPen();
        break;
      case ToolId.advancedPen:
        Pen.currentPen = Pen.advancedPen();
        break;
      case ToolId.advancedPencil:
        Pen.currentPen = Pen.advancedPencil();
        break;
      case ToolId.experimentalPen:
        Pen.currentPen = Pen.advancedPen();
        break;
      case ToolId.fountainPen:
      default:
        Pen.currentPen = Pen.fountainPen();
        break;
    }

    switch (stows.lastTool.value) {
      case .fountainPen:
      case .ballpointPen:
      case .calligraphyPen:
      case .shapePen:
      case .advancedPen:
      case .advancedPencil:
      case .experimentalPen:
        return Pen.currentPen;
      case .highlighter:
        return Highlighter.currentHighlighter;
      case .shapeTool:
        return ShapeTool.currentShapeTool;
      case .eraser:
        return Eraser.currentEraser;
      case .select:
        return Select.currentSelect;
      case .textEditing:
        return Tool.textEditing;
      case .laserPointer:
        return LaserPointer.currentLaserPointer;
    }
  }();
  Tool get currentTool => _currentTool;
  set currentTool(Tool tool) {
    if (tool != Select.currentSelect && tool != ShapeTool.currentShapeTool) {
      _autoSwitchBackToShapeTool = false;
    }

    if ((tool is Select || tool is Eraser || tool is LaserPointer) &&
        _currentTool is Pen) {
      _lastPenTool = _currentTool;
    } else if (tool is Pen || tool is ShapeTool) {
      _lastPenTool = tool;
    }

    if (tool is Pen && tool is! Highlighter) {
      Pen.currentPen = tool;
      stows.lastPenType.value = tool.toolId;
    }

    _currentTool = tool;
    stows.lastTool.value = tool.toolId;

    if (tool is! Eraser) {
      eraserPosition = null;
      _eraserPositionRepaint.value = null;
      Eraser.isDragging = false;
      _rawPenSampleSeenThisStroke = false;
      _lastRawPenSampleTimestamp = null;
    }
    _bumpInteractionRepaint();
  }

  final ValueNotifier<int> _interactionRepaint = ValueNotifier(0);
  void _bumpInteractionRepaint() {
    _interactionRepaint.value++;
  }

  ValueNotifier<SavingState> savingState = ValueNotifier(SavingState.saved);

  Timer? _delayedSaveTimer;
  DateTime? _lastUserActivityForAutosave;

  DateTime _lastSaveTime = DateTime.now();
  DateTime _lastTimeSpentUpdate = DateTime.now();
  EditorRecoveryJournal? _recoveryJournal;

  bool _isDisposed = false;
  String _lastWrittenThumbnailHash = '';

  Future<void>? _pendingSaveFuture;

  static final Map<String, Future<void>> _pendingSavesByPath = {};

  /// Bumped when a note path is deleted so in-flight saves for a prior note
  /// identity cannot recreate the file after "New note" reuses the name.
  static final Map<String, int> _notePathEpoch = {};

  static String _normalizeNotePathKey(String path) {
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
    if (!normalized.startsWith('/')) normalized = '/$normalized';
    if (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static int notePathEpoch(String noteBasePath) {
    return _notePathEpoch[_normalizeNotePathKey(noteBasePath)] ?? 0;
  }

  static void invalidateDeletedNotePath(String noteBasePath) {
    final key = _normalizeNotePathKey(noteBasePath);
    _notePathEpoch[key] = (_notePathEpoch[key] ?? 0) + 1;
  }

  /// While [_pendingSaveFuture] runs, new edits must queue a follow-up save
  /// (-setting [savingState] to waiting would start a second concurrent
  /// [_runBackgroundSave] and corrupt the on-disk note).
  bool _saveFollowUpRequested = false;

  bool _isDeleted = false;
  bool _isUndoRedoInProgress = false;

  _ImageCropState? _imageCropState;
  _CropHandle? _activeCropHandle;

  void _appendRecoveryStroke(Stroke stroke) {
    if (coreInfo.readOnly || _isDeleted) return;
    final journal = _recoveryJournal ??= EditorRecoveryJournal(
      coreInfo.filePath,
      noteId: coreInfo.noteId,
    );
    unawaited(journal.appendDrawStroke(stroke.copy()));
  }

  Future<void> _flushRecoveryWrites() async {
    try {
      await _recoveryJournal?.flush();
    } catch (_) {}
  }

  PdfDocument? _previewPdfDocument;
  int? _previewPageIndex;
  Rect? _previewRegion;
  int? _lastPreviewGoToOriginPageIndex;
  bool _showGoBackAfterPreviewJump = false;

  /// Stack of notes replaced by tapping an internal note link. Popping restores
  /// the previous note in this same editor (single or split pane).
  final List<_NoteLinkHistoryEntry> _noteLinkBackStack = [];
  bool _noteLinkNavBusy = false;

  final _mathSolver = MathSolverService();
  final _recognitionService = RecognitionService();

  Timer? _selectionLongPressTimer;
  Offset _longPressStartPosition = Offset.zero;
  bool _ignoreDragForMenu = false;
  bool _isCanvasMenuOpen = false;
  static const double _longPressMoveThreshold = 10.0;
  static const List<double> _rotationSnapAngles = <double>[
    0,
    30,
    45,
    60,
    90,
    120,
    135,
    150,
    180,
    210,
    225,
    240,
    270,
    300,
    315,
    330,
  ];
  double? _activeRotationSnapAnchor;
  static const double _animationPlayButtonRadius = 14.0;
  static const double _animationPlayButtonInset = 12.0;

  Future<void> _handlePotentialPdfLinkTap(Offset globalPos) async {
    try {
      final pageIndex = onWhichPageIsFocalPoint(globalPos);
      if (pageIndex == null) return;

      final page = coreInfo.pages[pageIndex];

      if (page.backgroundImage is! PdfEditorImage) return;
      final pdfImg = page.backgroundImage as PdfEditorImage;

      final renderBox = page.renderBox;
      if (renderBox == null || !renderBox.attached) return;
      final localPos = renderBox.globalToLocal(globalPos);

      final pdfNotifier = coreInfo.assetCacheAll.getPdfNotifier(pdfImg.assetId);
      final pdfDocument = pdfNotifier.value;

      if (pdfDocument == null) {
        log.warning('PDF Document not yet loaded for link detection');
        return;
      }

      final pdfPageObj = pdfDocument.pages[pdfImg.pdfPage];
      final realNaturalSize = Size(pdfPageObj.width, pdfPageObj.height);

      final Size renderedSize = page.size;

      final pdfPosition = PdfLinkDetector.widgetToPdfCoordinates(
        localPos,
        renderedSize,
        realNaturalSize,
      );

      final link = await PdfLinkDetector.findLinkAtPosition(
        pdfDocument,
        pdfImg.pdfPage,
        pdfPosition,
      );

      if (link != null) {
        if (link.targetPageIndex != null) {
          Rect regionToShow;

          if (link.targetRegion != null) {
            regionToShow = link.targetRegion!;
          } else {
            final targetPageObj = pdfDocument.pages[link.targetPageIndex!];
            regionToShow = Rect.fromLTWH(
              0,
              targetPageObj.height - 300,
              targetPageObj.width,
              300,
            );
          }

          _showPdfEquationPreview(
            pdfDocument: pdfDocument,
            pageIndex: link.targetPageIndex!,
            region: regionToShow,
          );
        } else if (link.uri != null) {
          final Uri url = Uri.parse(link.uri!);
          if (await canLaunchUrl(url)) {
            await launchUrl(url, mode: LaunchMode.externalApplication);
          }
        }
      } else {}
    } catch (e, stackTrace) {
      log.warning('Error handling potential PDF link tap: $e', e, stackTrace);
    }
  }

  void _onPdfTap(
    Offset localPosition,
    PdfDocument pdfDocument,
    int pdfPage,
    Size pdfPageSize,
    Size pdfNaturalSize,
    File? pdfFile,
  ) async {
    try {
      final pdfPosition = PdfLinkDetector.widgetToPdfCoordinates(
        localPosition,
        pdfPageSize,
        pdfNaturalSize,
      );

      final link = await PdfLinkDetector.findLinkAtPosition(
        pdfDocument,
        pdfPage,
        pdfPosition,
      );

      if (link != null && link.targetPageIndex != null) {
        final targetRegion =
            link.targetRegion ??
            Rect.fromLTWH(
              0,
              pdfNaturalSize.height - 300,
              pdfNaturalSize.width,
              300,
            );

        _showPdfEquationPreview(
          pdfDocument: pdfDocument,
          pageIndex: link.targetPageIndex!,
          region: targetRegion,
        );
      } else {
        _hidePdfEquationPreview();
      }
    } catch (e) {
      log.warning('Error handling PDF tap: $e');
    }
  }

  void _showPdfEquationPreview({
    required PdfDocument pdfDocument,
    required int pageIndex,
    required Rect region,
  }) {
    setState(() {
      _previewPdfDocument = pdfDocument;
      _previewPageIndex = pageIndex;
      _previewRegion = region;
    });
  }

  void _hidePdfEquationPreview() {
    setState(() {
      _previewPdfDocument = null;
      _previewPageIndex = null;
      _previewRegion = null;
    });
  }

  void _goBackFromPreviewJump() {
    final target = _lastPreviewGoToOriginPageIndex;
    if (target == null) return;
    final screenWidth = _currentViewportWidth();
    CanvasGestureDetector.scrollToPage(
      pageIndex: target,
      pageOffsets: _generatePageOffsets(coreInfo.pages, screenWidth),
      transformationController: _transformationController,
    );
    setState(() {
      _showGoBackAfterPreviewJump = false;
      _lastPreviewGoToOriginPageIndex = null;
    });
  }

  void _cancelPreviewJumpHistory() {
    setState(() {
      _showGoBackAfterPreviewJump = false;
      _lastPreviewGoToOriginPageIndex = null;
    });
  }

  void _onPreviewLinkTapped(PdfLink link) {
    if (link.targetPageIndex != null && _previewPdfDocument != null) {
      Rect regionToShow;
      if (link.targetRegion != null) {
        regionToShow = link.targetRegion!;
      } else {
        final targetPageObj = _previewPdfDocument!.pages[link.targetPageIndex!];
        regionToShow = Rect.fromLTWH(
          0,
          targetPageObj.height - 250,
          targetPageObj.width,
          250,
        );
      }

      _showPdfEquationPreview(
        pdfDocument: _previewPdfDocument!,
        pageIndex: link.targetPageIndex!,
        region: regionToShow,
      );
    }
  }

  void _onGoToLocation(int pageIndex) {
    _lastPreviewGoToOriginPageIndex = currentPageIndex;
    _navigateToPage(pageIndex, neighborWindow: 1);
    setState(() {
      _showGoBackAfterPreviewJump = true;
    });
  }

  /// User-initiated page jump: hydrate landing window, prime assets, scroll,
  /// then unblock idle prefetch (outline / page list / PDF links).
  void _navigateToPage(int pageIndex, {int neighborWindow = 1}) {
    if (coreInfo.pages.isEmpty) return;
    final target = pageIndex.clamp(0, coreInfo.pages.length - 1);
    final from = (target - neighborWindow).clamp(0, coreInfo.pages.length - 1);
    final to = (target + neighborWindow).clamp(0, coreInfo.pages.length - 1);

    for (var i = from; i <= to; i++) {
      if (!coreInfo.isLazyShellPage(i)) {
        coreInfo.ensurePageHydrated(i);
        _wirePageImageCallbacks(i);
      }
    }
    _maintainPageRasterBand(from, to);

    final screenWidth = _currentViewportWidth();
    CanvasGestureDetector.scrollToPage(
      pageIndex: target,
      pageOffsets: _generatePageOffsets(coreInfo.pages, screenWidth),
      transformationController: _transformationController,
    );
    PageRasterCacheManager.endProgrammaticViewportJump();
    if (mounted) setState(() {});
  }

  void _startSelectionLongPressTimer(Offset globalPos) {
    _selectionLongPressTimer?.cancel();
    _longPressStartPosition = globalPos;

    // Match canvas long-press. Flutter's 500ms default feels sluggish.
    _selectionLongPressTimer = Timer(CanvasContextMenuFeel.longPressDuration, () {
      if (mounted) {
        _selectionLongPressTimer = null;

        _ignoreDragForMenu = true;
        HapticFeedback.selectionClick();
        unawaited(
          _showCanvasMenu(globalPos).whenComplete(() {
            if (!mounted) return;
            _ignoreDragForMenu = false;
          }),
        );

        setState(() {
          _isScaling = false;
          _isRotating = false;
          _isDraggingVertex = false;
        });
      }
    });
  }

  Future<void> _copySelectionToClipboard() async {
    final select = Select.currentSelect;
    if (!select.doneSelecting || select.selectResult.isEmpty) return;
    final strokes = select.selectResult.strokes;
    final images = select.selectResult.images;

    Rect bounds = select.selectResult.getBounds();
    if (bounds.isEmpty) return;
    const padding = 8.0;
    bounds = bounds.inflate(padding);
    final size = bounds.size;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.translate(-bounds.left, -bounds.top);

    for (final image in images) {
      ui.Image? uiImg;
      try {
        if (image is PngEditorImage && image.imageProvider != null) {
          final completer = Completer<ui.Image>();
          final stream = image.imageProvider!.resolve(ImageConfiguration.empty);
          ImageStreamListener? listener;
          listener = ImageStreamListener(
            (info, _) {
              if (!completer.isCompleted) completer.complete(info.image);
              stream.removeListener(listener!);
            },
            onError: (e, _) {
              if (!completer.isCompleted) completer.completeError(e);
              stream.removeListener(listener!);
            },
          );
          stream.addListener(listener);
          uiImg = await completer.future.timeout(const Duration(seconds: 2));
        }
      } catch (e) {
        log.warning('Failed to load image for clipboard: $e');
        uiImg = null;
      }

      if (uiImg != null) {
        final center = image.dstRect.center;
        final angleRad = (image.rotationDeg) * math.pi / 180.0;
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(angleRad);
        canvas.translate(-center.dx, -center.dy);
        paintImage(
          canvas: canvas,
          rect: image.dstRect,
          image: uiImg,
          fit: BoxFit.fill,
        );
        canvas.restore();
      }
    }

    for (final stroke in strokes) {
      final paint = Paint()
        ..color = stroke.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke.options.size;

      final path = stroke is ShapeStroke
          ? stroke.shapePath
          : stroke.highQualityPath;

      if (stroke is ShapeStroke && stroke.fill) {
        final fillPaint = Paint()
          ..color = stroke.fillColor
          ..style = PaintingStyle.fill;
        canvas.drawPath(path, fillPaint);
      }
      final outlinePath = stroke is ShapeStroke ? stroke.strokeDrawPath : path;
      canvas.drawPath(outlinePath, paint);
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(
      size.width.ceil().clamp(1, 4096),
      size.height.ceil().clamp(1, 4096),
    );
    final data = await img.toByteData(format: ui.ImageByteFormat.png);

    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return;

    final item = DataWriterItem();

    if (data != null) {
      item.add(Formats.png(data.buffer.asUint8List()));
    }

    final List<Map<String, dynamic>> strokesJson = strokes
        .map((s) => s.toJson())
        .toList();

    final assetsData = <Uint8List>[];
    final imagesJson = <Map<String, dynamic>>[];

    for (final img in images) {
      try {
        int assetId;
        if (img is PngEditorImage) {
          assetId = img.assetId;
        } else if (img is PdfEditorImage) {
          assetId = img.assetId;
        } else if (img is SvgEditorImage) {
          assetId = img.assetId;
        } else {
          log.warning('Unknown EditorImage type: ${img.runtimeType}');
          continue;
        }

        final file = coreInfo.assetCacheAll.getAssetFile(assetId);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          assetsData.add(bytes);

          final json = img.toJson();

          json['a'] = assetsData.length - 1;
          imagesJson.add(json);
        }
      } catch (e) {
        log.warning('Failed to copy image asset: $e');
      }
    }

    final Map<String, dynamic> saberData = {
      'v': 1,
      'sbnVersion': EditorCoreInfo.sbnVersion,
      'strokes': strokesJson,
      'images': imagesJson,
      'assets': assetsData.map((b) => BsonBinary.from(b)).toList(),
    };

    final bsonData = BsonCodec.serialize(saberData);
    item.add(Editor.saberSelectionFormat(bsonData.byteList));

    item.add(
      Formats.plainText(
        'Stroke Selection: ${strokes.length} strokes, ${images.length} images',
      ),
    );

    await clipboard.write([item]);
  }

  Future<void> _cutSelectionToClipboard() async {
    await _copySelectionToClipboard();
    deleteSelection();
  }

  Future<void> _shareSelection() async {
    final select = Select.currentSelect;
    if (!select.doneSelecting || select.selectResult.images.isEmpty || !mounted)
      return;

    final image = select.selectResult.images.first;
    List<int> bytes;
    String fileName;
    String ext = image.extension;

    try {
      switch (image) {
        case PngEditorImage():
          final provider = image.imageProvider;
          if (provider is MemoryImage) {
            bytes = provider.bytes;
          } else if (provider is FileImage) {
            bytes = await provider.file.readAsBytes();
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(t.editor.couldNotRecognizeText)),
              );
            }
            return;
          }
          if (ext != '.png' && ext != '.jpg' && ext != '.jpeg') ext = '.png';
          break;
        case PdfEditorImage():
          bytes = await image.assetCacheAll.getBytes(image.assetId);
          ext = '.pdf';
          break;
        case SvgEditorImage():
          bytes = switch (image.svgLoader) {
            (final SvgStringLoader loader) => utf8.encode(
              loader.provideSvg(null),
            ),
            (final SvgFileLoader loader) => await loader.file.readAsBytes(),
            (_) => <int>[],
          };
          if (bytes.isEmpty) return;
          ext = '.svg';
          break;
      }
    } catch (e) {
      log.warning('Failed to get image bytes for sharing: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to prepare image: $e')));
      }
      return;
    }

    if (bytes.isEmpty) return;

    fileName = 'image${image.id}$ext';
    if (!mounted) return;
    await FileManager.exportFile(
      fileName,
      bytes,
      isImage: false,
      context: context,
    );
  }

  Future<void> _shareSelectionAsSvg() async {
    final select = Select.currentSelect;
    if (!select.doneSelecting ||
        select.selectResult.strokes.isEmpty ||
        !mounted)
      return;

    final strokes = select.selectResult.strokes;
    final page = coreInfo.pages[select.selectResult.pageIndex];
    final pageHeight = page.size.height;

    final bounds = select.selectResult.getBounds();
    final svgWidth = math.max(1.0, bounds.width);
    final svgHeight = math.max(1.0, bounds.height);

    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" '
      'viewBox="0 0 $svgWidth $svgHeight" '
      'width="$svgWidth" height="$svgHeight">',
    );

    buffer.writeln(
      '<g transform="translate(${-bounds.left}, ${-bounds.top}) '
      'scale(1,-1) translate(0,-$pageHeight)">',
    );

    final isPolygonStroke = (Stroke s) =>
        s is! CircleStroke && s is! RectangleStroke && s is! ShapeStroke;

    for (final stroke in strokes) {
      final pathStr = stroke.toSvgPath();
      if (pathStr.isEmpty) continue;

      final shapeStroke = stroke is ShapeStroke ? stroke : null;
      if (isPolygonStroke(stroke)) {
        final c = stroke.color;
        buffer.writeln(
          '<path fill="rgb(${c.red},${c.green},${c.blue})" '
          'fill-opacity="${c.alpha / 255}" d="$pathStr"/>',
        );
      } else if (shapeStroke != null && shapeStroke.fill) {
        final fc = shapeStroke.fillColor;
        buffer.writeln(
          '<path fill="rgb(${fc.red},${fc.green},${fc.blue})" '
          'fill-opacity="${fc.alpha / 255}" d="$pathStr"/>',
        );
        final sc = stroke.color;
        buffer.writeln(
          '<path fill="none" stroke="rgb(${sc.red},${sc.green},${sc.blue})" '
          'stroke-opacity="${sc.alpha / 255}" '
          'stroke-width="${stroke.options.size}" d="$pathStr"/>',
        );
      } else {
        final c = stroke.color;
        buffer.writeln(
          '<path fill="none" stroke="rgb(${c.red},${c.green},${c.blue})" '
          'stroke-opacity="${c.alpha / 255}" '
          'stroke-width="${stroke.options.size}" d="$pathStr"/>',
        );
      }
    }

    buffer.writeln('</g>');
    buffer.writeln('</svg>');

    final svgBytes = utf8.encode(buffer.toString());
    final fileName = 'strokes_${DateTime.now().millisecondsSinceEpoch}.svg';
    if (!mounted) return;
    await FileManager.exportFile(
      fileName,
      svgBytes,
      isImage: false,
      context: context,
    );
  }

  void _toggleInvertibleSelection() {
    final select = Select.currentSelect;
    if (!select.doneSelecting || select.selectResult.isEmpty) return;

    setState(() {
      for (final image in select.selectResult.images) {
        image.invertible = !image.invertible;
        image.onMiscChange?.call();
      }
    });
    autosaveAfterDelay();
  }

  void _toggleLockSelection(bool lock) {
    final select = Select.currentSelect;
    if (!select.doneSelecting || select.selectResult.isEmpty) return;

    List<EditorImage> imagesToModify = select.selectResult.images;
    if (imagesToModify.isEmpty) return;

    history.recordChange(
      EditorHistoryItem(
        type: .move,
        pageIndex: imagesToModify.first.pageIndex,
        strokes: [],
        images: List.from(imagesToModify.map((e) => e.copy())),
      ),
    );

    setState(() {
      for (final image in imagesToModify) {
        image.locked = lock;
        image.onMiscChange?.call();
      }

      if (lock) {
        Select.currentSelect.unselect();
      }
    });
    autosaveAfterDelay();
  }

  void _setSelectionAsBackground() {
    final select = Select.currentSelect;

    if (!select.doneSelecting ||
        select.selectResult.images.length != 1 ||
        select.selectResult.strokes.isNotEmpty)
      return;

    final pageIndex = select.selectResult.pageIndex;
    final page = coreInfo.pages[pageIndex];
    final image = select.selectResult.images.first;

    if (image.locked) {
      image.locked = false;
    }

    setState(() {
      if (page.backgroundImage != null) {
        page.images.add(page.backgroundImage!);
      }

      page.images.remove(image);

      page.backgroundImage = image;

      select.unselect();

      if (_autoSwitchBackToShapeTool) {
        _autoSwitchBackToShapeTool = false;
        currentTool = ShapeTool.currentShapeTool;
      }
    });

    autosaveAfterDelay();

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.editor.imageSetAsBackground)));
    }
  }

  Future<void> _cropSingleSelectedImage() async {
    final select = Select.currentSelect;
    if (!select.doneSelecting ||
        select.selectResult.images.length != 1 ||
        select.selectResult.strokes.isNotEmpty) {
      return;
    }

    final selectedImage = select.selectResult.images.first;
    if (selectedImage is! PngEditorImage) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t.editor.cropBitmapOnly)));
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _imageCropState = _ImageCropState(
        image: selectedImage,
        normalizedCrop: const Rect.fromLTRB(0, 0, 1, 1),
      );
    });
  }

  Future<void> _applyImageCrop(
    PngEditorImage selectedImage,
    Rect normalizedCrop,
  ) async {
    const minSpan = 0.05;
    final left = normalizedCrop.left.clamp(0.0, 1.0 - minSpan);
    final top = normalizedCrop.top.clamp(0.0, 1.0 - minSpan);
    final right = normalizedCrop.right.clamp(left + minSpan, 1.0);
    final bottom = normalizedCrop.bottom.clamp(top + minSpan, 1.0);
    final clamped = Rect.fromLTRB(left, top, right, bottom);

    final imageBytes = await selectedImage.assetCacheAll.getBytes(
      selectedImage.assetId,
    );
    if (imageBytes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.editor.failedToLoadImageForCrop)),
        );
      }
      return;
    }

    final codec = await ui.instantiateImageCodec(
      Uint8List.fromList(imageBytes),
    );
    final frame = await codec.getNextFrame();
    final decodedImage = frame.image;

    try {
      final sourceWidth = decodedImage.width.toDouble();
      final sourceHeight = decodedImage.height.toDouble();

      final cropLeft = (clamped.left * sourceWidth).clamp(0.0, sourceWidth - 1);
      final cropTop = (clamped.top * sourceHeight).clamp(0.0, sourceHeight - 1);
      final cropRight = (clamped.right * sourceWidth).clamp(
        cropLeft + 1,
        sourceWidth,
      );
      final cropBottom = (clamped.bottom * sourceHeight).clamp(
        cropTop + 1,
        sourceHeight,
      );

      final cropRect = Rect.fromLTRB(cropLeft, cropTop, cropRight, cropBottom);
      final cropWidth = cropRect.width.toInt().clamp(1, decodedImage.width);
      final cropHeight = cropRect.height.toInt().clamp(1, decodedImage.height);

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        decodedImage,
        cropRect,
        Rect.fromLTWH(0, 0, cropWidth.toDouble(), cropHeight.toDouble()),
        Paint(),
      );

      final croppedImage = await recorder.endRecording().toImage(
        cropWidth,
        cropHeight,
      );
      final pngData = await croppedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      croppedImage.dispose();
      if (pngData == null) return;

      final croppedBytes = pngData.buffer.asUint8List();
      final croppedFile = selectedImage.assetCacheAll.createRuntimeFile(
        '.png',
        croppedBytes,
      );
      await selectedImage.assetCacheAll.replaceImage(
        croppedFile,
        selectedImage.assetId,
      );

      if (!mounted) return;
      final select = Select.currentSelect;
      setState(() {
        _imageCropState = null;
        final oldRect = selectedImage.dstRect;
        final newAspect = cropWidth / cropHeight;
        var newWidth = oldRect.width;
        var newHeight = newWidth / newAspect;

        if (newHeight < CanvasImage.minImageSize) {
          final scale = CanvasImage.minImageSize / newHeight;
          newHeight = CanvasImage.minImageSize;
          newWidth *= scale;
        }
        if (newWidth < CanvasImage.minImageSize) {
          final scale = CanvasImage.minImageSize / newWidth;
          newWidth = CanvasImage.minImageSize;
          newHeight *= scale;
        }

        selectedImage.naturalSize = Size(
          cropWidth.toDouble(),
          cropHeight.toDouble(),
        );
        selectedImage.srcRect = Rect.fromLTWH(
          0,
          0,
          cropWidth.toDouble(),
          cropHeight.toDouble(),
        );
        selectedImage.dstRect = Rect.fromCenter(
          center: oldRect.center,
          width: newWidth,
          height: newHeight,
        );
        selectedImage.onMiscChange?.call();

        final selectResult = select.selectResult;
        if (selectResult.images.length == 1 &&
            identical(selectResult.images.first, selectedImage)) {
          selectResult.path = Path()..addRect(selectedImage.dstRect);
          selectResult.displayBounds = selectedImage.dstRect;
        }
      });

      autosaveAfterDelay();
    } finally {
      decodedImage.dispose();
    }
  }

  void deleteSelection() {
    final select = Select.currentSelect;
    if (!select.doneSelecting || select.selectResult.isEmpty) return;
    final pageIndex = select.selectResult.pageIndex;
    final page = coreInfo.pages[pageIndex];

    history.recordChange(
      EditorHistoryItem(
        type: .erase,
        pageIndex: pageIndex,
        strokes: List<Stroke>.from(select.selectResult.strokes),
        images: List<EditorImage>.from(select.selectResult.images),
      ),
    );

    setState(() {
      for (final stroke in select.selectResult.strokes) {
        page.strokes.remove(stroke);
        page.strokeSpatialIndex?.remove(stroke);
      }
      for (final image in select.selectResult.images) {
        page.images.remove(image);
      }
      select.unselect();
      if (_autoSwitchBackToShapeTool) {
        _autoSwitchBackToShapeTool = false;
        currentTool = ShapeTool.currentShapeTool;
      }

      page.redrawStrokes();
    });
    if (coreInfo.isInfinite) {
      _trimInfiniteCanvasWhitespace(page);
    }
    autosaveAfterDelay();
  }

  void duplicateSelection() {
    final select = Select.currentSelect;
    if (!select.doneSelecting || select.selectResult.isEmpty) return;
    final pageIndex = select.selectResult.pageIndex;
    final page = coreInfo.pages[pageIndex];

    final newStrokes = <Stroke>[];
    final newImages = <EditorImage>[];

    const offset = Offset(20, 20);

    for (final stroke in select.selectResult.strokes) {
      final newStroke = stroke.copy();
      newStroke.shift(offset);
      newStrokes.add(newStroke);
    }
    for (final image in select.selectResult.images) {
      final newImage = image.copy();
      newImage.dstRect = newImage.dstRect.shift(offset);
      newImages.add(newImage);
    }

    history.recordChange(
      EditorHistoryItem(
        type: .draw,
        pageIndex: pageIndex,
        strokes: newStrokes,
        images: newImages,
      ),
    );

    setState(() {
      page.strokes.addAll(newStrokes);
      for (final s in newStrokes) {
        page.strokeSpatialIndex?.insert(s);
      }
      page.images.addAll(newImages);

      select.selectResult = select.selectResult.copyWith(
        strokes: newStrokes,
        images: newImages,
        path: select.selectResult.path.shift(offset),

        displayBounds: select.selectResult.displayBounds?.shift(offset),
      );
    });
    if (coreInfo.isInfinite) {
      _fitInfiniteCanvasToContent(page);
    }
    autosaveAfterDelay();
  }

  Timer? _watchServerTimer;

  var lastSeenPointerCount = 0;
  Timer? _lastSeenPointerCountTimer;

  ValueNotifier<QuillStruct?> quillFocus = ValueNotifier(null);

  Tool? tmpTool;

  Tool? _lastPenTool;
  bool _autoSwitchBackToShapeTool = false;

  var stylusButtonPressed = false;

  OverlayEntry? _calculatorOverlay;
  Offset _calculatorOffset = const Offset(40, 80);

  /// Drag-to-select region screenshot mode (toolbar crop_free button).
  bool _regionScreenshotMode = false;
  final GlobalKey _regionScreenshotBoundaryKey = GlobalKey();

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);

    _keepAliveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..addListener(() {});

    _dockedSidePanelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..addListener(_onDockedSidePanelAnimTick);

    _initAsync();
    _assignKeybindings();

    NotesEyedropperTarget.canvasRepaintKey = _regionScreenshotBoundaryKey;

    PageRasterCacheManager.addLodSettledListener(_onPageRasterLodSettled);

    if (coreInfo.pages.isNotEmpty) {
    } else {}

    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    try {
      final newTheme = Theme.of(context);
      if (_cachedTheme != null && _cachedTheme!.brightness != newTheme.brightness) {
        _pageRasterCache.invalidateForZoom();
        _bumpInteractionRepaint();
      }
      _cachedTheme = newTheme;
      _cachedMediaQuery = MediaQuery.of(context);
      final view = View.maybeOf(context);
      if (view != null) {
        _lastMetricsLogicalSize =
            view.physicalSize / view.devicePixelRatio;
        DisplayInkFeel.instance.updateFromView(view);
      }
    } catch (e) {
      log.warning('Failed to cache UI dependencies: $e');
    }
  }

  void _initAsync() async {
    coreInfo.filePath = await widget.initialPath;
    filenameTextEditingController.text = coreInfo.fileName;

    if (needsNaming) {
      filenameTextEditingController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: filenameTextEditingController.text.length,
      );
    }

    final hasPendingSave = _pendingSavesByPath[coreInfo.filePath] != null;
    if (!hasPendingSave) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    if (!mounted) return;

    _mathSolver.init().then((_) {});

    await _initStrokes();

    if (widget.pdfPath != null) {
      importPdfFromFilePath(widget.pdfPath!)
          .then((imported) {
            if (mounted) setState(() {});
            if (!imported) log.warning('PDF import failed or was cancelled');
          })
          .catchError((e, stackTrace) {
            log.severe(
              'Failed to import PDF during initialization: $e',
              e,
              stackTrace,
            );
            if (mounted) setState(() {});
          });
    }

    if (mounted) setState(() {});
  }

  Future _initStrokes() async {
    try {
      final pending = _pendingSavesByPath[coreInfo.filePath];
      if (pending != null) {
        log.info(
          'Awaiting previous session save before load: ${coreInfo.filePath}',
        );
        await pending;
      }
      coreInfo = await EditorCoreInfo.loadFromFilePath(coreInfo.filePath);
      coreInfo.ensureNoteId();
      _lastWrittenThumbnailHash = coreInfo.firstPageHash ?? '';
      _recoveryJournal = EditorRecoveryJournal(
        coreInfo.filePath,
        noteId: coreInfo.noteId,
      );
      final recovered = await _recoveryJournal!.replayInto(coreInfo);
      final shouldPersistId = coreInfo.noteIdWasAssigned;
      if ((recovered || shouldPersistId) && !coreInfo.readOnly) {
        savingState.value = SavingState.waitingToSave;
        unawaited(
          saveToFile(force: true, updateThumbnail: false).catchError((e) {
            log.warning('Recovery/noteId snapshot save failed: $e');
          }),
        );
      }
      // First paint with strokes as soon as the body is parsed (low-quality
      // paths). Opening chrome stays until this frame can schedule.
      if (mounted) setState(() {});
      await Future<void>.delayed(Duration.zero);
    } finally {
      // Setup complete
    }

    final int savedPageIndex = coreInfo.initialPageIndex ?? 0;
    // Força para 0 temporariamente para que a animação do Hero encaixe perfeitamente
    if (widget.initialPageIndexOverride == null) {
      coreInfo.initialPageIndex = 0;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_syncNoteLinksAfterOpen());
      unawaited(_repairTruncatedPdfBackedNoteIfNeeded());
    });
    if (widget.initialPageIndexOverride != null &&
        widget.initialPageIndexOverride! >= 0) {
      coreInfo.initialPageIndex = widget.initialPageIndexOverride!;
    }

    coreInfo.isInfinite = false;
    if (coreInfo.readOnly) {
      log.info('Loaded file as read-only');
    }

    if (coreInfo.pages.isNotEmpty) {
      final initIdx = (coreInfo.initialPageIndex ?? 0).clamp(
        0,
        coreInfo.pages.length - 1,
      );
      coreInfo.ensurePageHydrated(initIdx);
      listenToQuillChanges(coreInfo.pages[initIdx].quill, initIdx);
      _deferQuillListeners(coreInfo, initIdx, initIdx);
    }

    if (coreInfo.isEmpty) {
      createPage(-1);
    } else {
      if (coreInfo.pages.isNotEmpty) {
        for (int i = 0; i < coreInfo.pages.length; i++) {
          if (coreInfo.isInfinite) {
            coreInfo.pages[i].ensureMinimumSize(infinitePageSize);
          }

          final page = coreInfo.pages[i];
          page.backgroundImage?.onMoveImage = onMoveImage;
          page.backgroundImage?.onDeleteImage = onDeleteImage;
          page.backgroundImage?.onMiscChange = autosaveAfterDelay;
          for (final image in page.images) {
            image.onMoveImage = onMoveImage;
            image.onDeleteImage = onDeleteImage;
            image.onMiscChange = autosaveAfterDelay;
          }
        }
      }
    }

    if (currentTool == Tool.textEditing && coreInfo.pages.isNotEmpty) {
      final pageIndex = (coreInfo.initialPageIndex ?? 0).clamp(
        0,
        coreInfo.pages.length - 1,
      );
      quillFocus.value = coreInfo.pages[pageIndex].quill
        ..focusNode.requestFocus();
    }

    if (coreInfo.noteToolSettings != null) {
      applyNoteToolSettings(coreInfo.noteToolSettings!);
      _currentTool = _toolFromLastTool();
    } else {
      InkPresetLibrary.applyActive(stows);
    }

    if (mounted) {
      setState(() {});
    }

    if (savedPageIndex > 0 && widget.initialPageIndexOverride == null) {
      _scheduleSmoothScroll(savedPageIndex);
    }
  }

  AnimationController? _smoothScrollController;
  bool _isSmoothScrolling = false;

  void _scheduleSmoothScroll(int targetPage) {
    if (!mounted) return;
    final width = _currentViewportWidth();
    if (width < 10) {
      Future.delayed(const Duration(milliseconds: 200), () => _scheduleSmoothScroll(targetPage));
      return;
    }
    
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _animateScrollToPage(targetPage);
    });
  }


  void _animateScrollToPage(int targetPage) {
    if (!mounted || coreInfo.pages.isEmpty) return;
    
    final safeTargetPage = targetPage.clamp(0, coreInfo.pages.length - 1);
    final screenWidth = _currentViewportWidth();
    final targetOffsets = _generatePageOffsets(coreInfo.pages, screenWidth);
    final targetLayoutY = CanvasGestureDetector.getTopOfPage(
      pageIndex: safeTargetPage,
      pageOffsets: targetOffsets,
    );

    final currentMatrix = _transformationController.value;
    final scale = currentMatrix.getMaxScaleOnAxis();
    final targetY = -targetLayoutY * scale;

    final currentY = currentMatrix.getTranslation().y;

    if ((currentY - targetY).abs() < 1.0) {
      _lastCurrentPageIndex = safeTargetPage;
      return;
    }

    _isSmoothScrolling = true;
    _suppressTransformClamp.value = true;
    InteractiveCanvasViewer.isAutoPanningEnabled = false; 

    _smoothScrollController?.dispose();
    _smoothScrollController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );

    final startMatrix = currentMatrix.clone();
    final endMatrix = startMatrix.clone()..setTranslationRaw(startMatrix.getTranslation().x, targetY, startMatrix.getTranslation().z);

    final anim = Matrix4Tween(begin: startMatrix, end: endMatrix).animate(
      CurvedAnimation(parent: _smoothScrollController!, curve: Curves.easeInOutCubic),
    );

    anim.addListener(() {
      if (!mounted) return;
      _transformationController.value = anim.value;
    });

    _smoothScrollController!.forward().then((_) {
      if (mounted) {
        _isSmoothScrolling = false;
        _suppressTransformClamp.value = false;
        InteractiveCanvasViewer.isAutoPanningEnabled = true;
        _maintainPageRasterBand(safeTargetPage, safeTargetPage);
        _lastCurrentPageIndex = safeTargetPage;
        setState(() {});
      }
    });

    Future.microtask(() async {
      final from = (safeTargetPage - 1).clamp(0, coreInfo.pages.length - 1);
      final to = (safeTargetPage + 1).clamp(0, coreInfo.pages.length - 1);
      for (var i = from; i <= to; i++) {
         if (coreInfo.isLazyShellPage(i)) {
           await coreInfo.hydratePageAtIndexAsync(i);
           _wirePageImageCallbacks(i);
         }
      }
    });
  }

  Future<void> _syncNoteLinksAfterOpen() async {
    try {
      await NoteLinksDatabase.instance.setLinksForPath(
        coreInfo.filePath,
        coreInfo.links,
        rootDirectory: FileManager.documentsDirectory,
      );
    } catch (e) {
      log.warning('Failed to sync links metadata after load: $e');
    }
  }

  Future<PdfDocument?> _waitForPdfDocument(int assetId) async {
    final notifier = coreInfo.assetCacheAll.getPdfNotifier(assetId);
    if (notifier.value != null) return notifier.value;

    final completer = Completer<PdfDocument?>();
    Timer? timeout;
    late VoidCallback listener;

    void complete(PdfDocument? document) {
      if (completer.isCompleted) return;
      timeout?.cancel();
      notifier.removeListener(listener);
      completer.complete(document);
    }

    listener = () {
      final document = notifier.value;
      if (document != null) complete(document);
    };

    notifier.addListener(listener);
    timeout = Timer(const Duration(seconds: 10), () => complete(null));
    return completer.future;
  }

  Future<void> _repairTruncatedPdfBackedNoteIfNeeded() async {
    // A failed lazy save can leave only the first few imported PDF pages in the
    // note body while the original PDF asset (`.sbn2.0`) is still present.
    // Repair only catastrophic prefix truncation to avoid undoing intentional
    // page deletions in ordinary notes.
    const maxSuspiciousPrefixPages = 12;
    if (coreInfo.readOnly ||
        coreInfo.isInfinite ||
        coreInfo.pages.isEmpty ||
        coreInfo.pages.length > maxSuspiciousPrefixPages) {
      return;
    }

    final firstBackground = coreInfo.pages.first.backgroundImage;
    if (firstBackground is! PdfEditorImage || firstBackground.pdfPage != 0) {
      return;
    }

    final assetId = firstBackground.assetId;
    final pdfFile = firstBackground.pdfFile;
    for (var i = 0; i < coreInfo.pages.length; i++) {
      final background = coreInfo.pages[i].backgroundImage;
      if (background is! PdfEditorImage ||
          background.assetId != assetId ||
          background.pdfPage != i ||
          coreInfo.pages[i].allImagesInDrawOrder.isNotEmpty) {
        return;
      }
    }

    final pdfDocument = await _waitForPdfDocument(assetId);
    if (!mounted || pdfDocument == null) return;

    final totalPdfPages = pdfDocument.pages.length;
    if (totalPdfPages <= coreInfo.pages.length ||
        totalPdfPages < coreInfo.pages.length * 4) {
      return;
    }

    log.warning(
      'Repairing truncated PDF-backed note: ${coreInfo.pages.length} / '
      '$totalPdfPages pages present for ${coreInfo.filePath}',
    );

    for (var i = coreInfo.pages.length; i < totalPdfPages; i++) {
      final pdfPage = pdfDocument.pages[i];
      final naturalSize = Size(
        pdfPage.width.toDouble(),
        pdfPage.height.toDouble(),
      );
      final pageSize = Size(
        EditorPage.defaultWidth,
        EditorPage.defaultWidth * naturalSize.height / naturalSize.width,
      );
      final editorPage = EditorPage(
        id: coreInfo.allocatePageId(),
        width: pageSize.width,
        height: pageSize.height,
        // Prevent white edge artifacts around PDF background images
        hasLocalBorderColor: true,
        borderColor: Colors.transparent,
      );

      editorPage.backgroundImage = PdfEditorImage(
        id: coreInfo.nextImageId++,
        pdfFile: pdfFile,
        pdfPage: i,
        pageIndex: i,
        pageSize: pageSize,
        naturalSize: naturalSize,
        dstRect: Rect.fromLTWH(0, 0, pageSize.width, pageSize.height),
        onMoveImage: onMoveImage,
        onDeleteImage: onDeleteImage,
        onMiscChange: autosaveAfterDelay,
        onLoad: () {
          if (mounted) setState(() {});
        },
        assetCacheAll: coreInfo.assetCacheAll,
        assetId: assetId,
        onPdfTap: (localPosition, pdfDocument, pdfPage, pdfFile) {
          _onPdfTap(
            localPosition,
            pdfDocument,
            pdfPage,
            pageSize,
            naturalSize,
            pdfFile,
          );
        },
      );

      coreInfo.assetCacheAll.addUse(assetId);
      coreInfo.pages.add(editorPage);
    }

    coreInfo.invalidatePageBinaryEncodeCaches();
    autosaveAfterDelay();
    if (mounted) setState(() {});
  }

  void _primeVisibleCanvasAssets(
    EditorCoreInfo info,
    int centerPageIndex,
    int buildFrom,
    int buildTo,
  ) {
    final cache = info.assetCacheAll;
    for (var i = buildFrom; i <= buildTo; i++) {
      final distance = (i - centerPageIndex).abs();
      final imagePri =
          AssetCacheAll.kImageDecodePriorityVisible - distance * 8000;
      final page = info.pages[i];

      void consider(EditorImage? img) {
        if (img == null) return;
        if (img is PngEditorImage) {
          cache.prioritizeImageDecode(img.assetId, imagePri);
          cache.getImageProviderNotifier(img.assetId);
        } else if (img is PdfEditorImage) {
          cache.getPdfNotifier(img.assetId);
        }
      }

      consider(page.backgroundImage);
      for (final im in page.images) {
        consider(im);
      }
    }
  }

  void _buildDeferredSpatialIndices(
    EditorCoreInfo info,
    int excludeFrom,
    int excludeTo,
  ) {
    if (info.pages.length <= excludeTo - excludeFrom + 1) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      const batch = 8;
      for (int i = 0; i < info.pages.length; i++) {
        if (i >= excludeFrom && i <= excludeTo) continue;
        if (info.isLazyShellPage(i)) continue;
        final page = info.pages[i];
        if (page.strokeSpatialIndex == null && page.strokes.isNotEmpty) {
          page.buildSpatialIndex();
        }
        page.backgroundImage?.onMoveImage = onMoveImage;
        page.backgroundImage?.onDeleteImage = onDeleteImage;
        page.backgroundImage?.onMiscChange = autosaveAfterDelay;
        for (final image in page.images) {
          image.onMoveImage = onMoveImage;
          image.onDeleteImage = onDeleteImage;
          image.onMiscChange = autosaveAfterDelay;
        }
        if ((i + 1) % batch == 0) await Future<void>.delayed(Duration.zero);
        if (!mounted) return;
      }
    });
  }

  void _deferQuillListeners(EditorCoreInfo info, int doneFrom, int doneTo) {
    if (info.pages.length <= doneTo - doneFrom + 1) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !identical(info, coreInfo)) return;
      const batch = 16;
      for (int i = 0; i < info.pages.length; i++) {
        if (i >= doneFrom && i <= doneTo) continue;
        if (info.isLazyShellPage(i)) continue;
        if (!identical(info, coreInfo)) return;
        listenToQuillChanges(info.pages[i].quill, i);
        final page = info.pages[i];
        page.backgroundImage?.onMoveImage = onMoveImage;
        page.backgroundImage?.onDeleteImage = onDeleteImage;
        page.backgroundImage?.onMiscChange = autosaveAfterDelay;
        for (final image in page.images) {
          image.onMoveImage = onMoveImage;
          image.onDeleteImage = onDeleteImage;
          image.onMiscChange = autosaveAfterDelay;
        }
        if ((i + 1) % batch == 0) await Future<void>.delayed(Duration.zero);
        if (!mounted) return;
      }
    });
  }

  Tool _toolFromLastTool() {
    switch (stows.lastTool.value) {
      case ToolId.fountainPen:
      case ToolId.ballpointPen:
      case ToolId.calligraphyPen:
      case ToolId.shapePen:
      case ToolId.advancedPen:
        return Pen.currentPen;
      case ToolId.advancedPencil:
        return Pen.currentPen;
      case ToolId.experimentalPen:
        return Pen.currentPen;
      case ToolId.highlighter:
        return Highlighter.currentHighlighter;
      case ToolId.shapeTool:
        return ShapeTool.currentShapeTool;
      case ToolId.eraser:
        return Eraser.currentEraser;
      case ToolId.select:
        return Select.currentSelect;
      case ToolId.textEditing:
        return Tool.textEditing;
      case ToolId.laserPointer:
        return LaserPointer.currentLaserPointer;
    }
  }

  Keybinding? _ctrlZ, _ctrlY, _ctrlShiftZ, _ctrlV, _ctrlC, _ctrlX;
  void _assignKeybindings() {
    _ctrlZ = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyZ),
    ], inclusive: true);
    _ctrlY = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyY),
    ], inclusive: true);
    _ctrlShiftZ = Keybinding([
      KeyCode.ctrl,
      KeyCode.shift,
      KeyCode.from(LogicalKeyboardKey.keyZ),
    ], inclusive: true);
    _ctrlV = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyV),
    ], inclusive: true);
    _ctrlC = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyC),
    ], inclusive: true);
    _ctrlX = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyX),
    ], inclusive: true);

    Keybinder.bind(_ctrlZ!, undo);
    Keybinder.bind(_ctrlY!, redo);
    Keybinder.bind(_ctrlShiftZ!, redo);
    Keybinder.bind(_ctrlV!, paste);
    Keybinder.bind(_ctrlC!, _copySelectionToClipboard);
    Keybinder.bind(_ctrlX!, _cutSelectionToClipboard);
  }

  void _removeKeybindings() {
    if (_ctrlZ != null) Keybinder.remove(_ctrlZ!);
    if (_ctrlY != null) Keybinder.remove(_ctrlY!);
    if (_ctrlShiftZ != null) Keybinder.remove(_ctrlShiftZ!);
    if (_ctrlV != null) Keybinder.remove(_ctrlV!);
    if (_ctrlC != null) Keybinder.remove(_ctrlC!);
    if (_ctrlX != null) Keybinder.remove(_ctrlX!);
  }

  static const Size infinitePageSize = Size(1600, 900);

  Size _newPageSize() => coreInfo.isInfinite
      ? infinitePageSize
      : coreInfo.notePageOrientation.defaultSize;

  ({
    CanvasBackgroundPattern pattern,
    Color backgroundColor,
    Color lineColor,
    int lineHeight,
    double lineThickness,
    double marginLeft,
    double marginRight,
    double marginTop,
    double marginBottom,
    Color? borderColor,
  })
  _newPageDefaults() {
    coreInfo.ensureDocumentDefaultsFromGlobal();

    final pattern = coreInfo.noteDefaultPattern!;
    final backgroundColor = Color(coreInfo.noteDefaultPageColor!);
    final lineColor = Color(coreInfo.noteDefaultLineColor!);
    final lineHeight = coreInfo.noteDefaultLineHeight!;
    final lineThickness = coreInfo.noteDefaultLineThickness!;

    final effectivePattern =
        coreInfo.isInfinite &&
            pattern != CanvasBackgroundPattern.none &&
            pattern != CanvasBackgroundPattern.grid &&
            pattern != CanvasBackgroundPattern.dots
        ? CanvasBackgroundPattern.none
        : pattern;

    final ml = coreInfo.noteDefaultMarginLeft!;
    final mr = coreInfo.noteDefaultMarginRight!;
    final mt = coreInfo.noteDefaultMarginTop!;
    final mb = coreInfo.noteDefaultMarginBottom!;
    final borderColor = coreInfo.noteDefaultBorderColor != null
        ? Color(coreInfo.noteDefaultBorderColor!)
        : null;

    return (
      pattern: effectivePattern,
      backgroundColor: backgroundColor,
      lineColor: lineColor,
      lineHeight: lineHeight,
      lineThickness: lineThickness,
      marginLeft: ml,
      marginRight: mr,
      marginTop: mt,
      marginBottom: mb,
      borderColor: borderColor,
    );
  }

  void createPage(int pageIndex) {
    if (coreInfo.isInfinite) {
      coreInfo.enforceSinglePage();
      if (coreInfo.pages.isEmpty) {
        final d = _newPageDefaults();
        final hasMargins =
            d.marginLeft > 0 ||
            d.marginRight > 0 ||
            d.marginTop > 0 ||
            d.marginBottom > 0;
        final page = EditorPage(
          id: coreInfo.allocatePageId(),
          size: _newPageSize(),
          backgroundPattern: d.pattern,
          backgroundColor: d.backgroundColor,
          lineColor: d.lineColor,
          lineHeight: d.lineHeight,
          lineThickness: d.lineThickness,
          hasLocalPattern: true,
          hasLocalBackgroundColor: true,
          hasLocalLineColor: true,
          hasLocalLineHeight: true,
          hasLocalLineThickness: true,
          hasLocalMargins: hasMargins,
          hasLocalBorderColor: d.borderColor != null,
          marginLeft: d.marginLeft,
          marginRight: d.marginRight,
          marginTop: d.marginTop,
          marginBottom: d.marginBottom,
          borderColor: d.borderColor,
        );
        coreInfo.pages.add(page);
        listenToQuillChanges(page.quill, 0);
      }
      return;
    }

    if (coreInfo.pages.isEmpty && pageIndex < 0) pageIndex = 0;
    while (pageIndex >= coreInfo.pages.length) {
      final d = _newPageDefaults();
      final hasMargins =
          d.marginLeft > 0 ||
          d.marginRight > 0 ||
          d.marginTop > 0 ||
          d.marginBottom > 0;
      final page = EditorPage(
        id: coreInfo.allocatePageId(),
        size: _newPageSize(),
        backgroundPattern: d.pattern,
        backgroundColor: d.backgroundColor,
        lineColor: d.lineColor,
        lineHeight: d.lineHeight,
        lineThickness: d.lineThickness,
        hasLocalPattern: true,
        hasLocalBackgroundColor: true,
        hasLocalLineColor: true,
        hasLocalLineHeight: true,
        hasLocalLineThickness: true,
        hasLocalMargins: hasMargins,
        hasLocalBorderColor: d.borderColor != null,
        marginLeft: d.marginLeft,
        marginRight: d.marginRight,
        marginTop: d.marginTop,
        marginBottom: d.marginBottom,
        borderColor: d.borderColor,
      );
      coreInfo.pages.add(page);
      listenToQuillChanges(page.quill, coreInfo.pages.length - 1);
    }
  }

  static List<double> _generatePageOffsets(
    List<EditorPage> pages,
    double screenWidth,
  ) {
    final offsets = <double>[];
    double currentTop = Editor.gapBetweenPages * 2;
    for (final page in pages) {
      offsets.add(currentTop);
      final pageSize = page.size;
      final pageWidthFitted = math.min(pageSize.width, screenWidth);
      currentTop += Editor.gapBetweenPages;
      currentTop += pageSize.height * (pageWidthFitted / pageSize.width);
    }
    return offsets;
  }

  /// Total stacked height of [pages] in layout space. Must match
  /// [_PagesBuilderState._recalculateLayout] in canvas_gesture_detector.dart.
  static double totalPagedDocumentHeight(
    List<EditorPage> pages,
    double containerWidth,
  ) {
    if (pages.isEmpty) return 0.0;
    double currentTop = Editor.gapBetweenPages * 2;
    for (final page in pages) {
      final pageWidth = math.min(page.size.width, containerWidth);
      final pageHeight = (pageWidth / page.size.width) * page.size.height;
      currentTop += pageHeight + Editor.gapBetweenPages;
    }
    currentTop += Editor.gapBetweenPages;
    return currentTop;
  }

  void _fitInfiniteCanvasToContent(
    EditorPage page, {
    bool allowShrink = false,
    double buffer = 200,
  }) {
    if (!coreInfo.isInfinite || coreInfo.pages.isEmpty) return;
    coreInfo.enforceSinglePage();

    final targetPage = coreInfo.pages.first;
    if (!identical(page, targetPage)) return;

    final oldSize = targetPage.size;
    final containerWidth =
        _canvasGestureDetectorKey.currentState?.containerBounds.maxWidth ??
        _currentViewportWidth();
    final viewportScale = _transformationController.value.approxScale;
    final fittedScale = oldSize.width > 0 && containerWidth > 0
        ? math.min(oldSize.width, containerWidth) / oldSize.width
        : 1.0;
    final sceneScale = math.max(viewportScale * fittedScale, 0.01);
    final effectiveBuffer = math.max(24.0, math.min(buffer, 96.0 / sceneScale));
    final bounds = targetPage.getContentBounds();
    if (bounds == Rect.zero || bounds.isEmpty) {
      targetPage.ensureMinimumSize(infinitePageSize);
      if (targetPage.size != oldSize && mounted) {
        setState(() {});
      }
      return;
    }

    double windowLeft;
    double windowTop;
    double windowRight;
    double windowBottom;

    if (allowShrink) {
      windowLeft = bounds.left - effectiveBuffer;
      windowTop = bounds.top - effectiveBuffer;
      windowRight = bounds.right + effectiveBuffer;
      windowBottom = bounds.bottom + effectiveBuffer;
    } else {
      windowLeft = math.min(0, bounds.left - effectiveBuffer);
      windowTop = math.min(0, bounds.top - effectiveBuffer);
      windowRight = math.max(oldSize.width, bounds.right + effectiveBuffer);
      windowBottom = math.max(oldSize.height, bounds.bottom + effectiveBuffer);
    }

    var targetWidth = windowRight - windowLeft;
    var targetHeight = windowBottom - windowTop;

    if (targetWidth < infinitePageSize.width) {
      final extra = (infinitePageSize.width - targetWidth) / 2;
      windowLeft -= extra;
      windowRight += extra;
      targetWidth = infinitePageSize.width;
    }
    if (targetHeight < infinitePageSize.height) {
      final extra = (infinitePageSize.height - targetHeight) / 2;
      windowTop -= extra;
      windowBottom += extra;
      targetHeight = infinitePageSize.height;
    }

    if (!allowShrink) {
      windowLeft = math.min(windowLeft, 0);
      windowTop = math.min(windowTop, 0);
      windowRight = math.max(windowRight, oldSize.width);
      windowBottom = math.max(windowBottom, oldSize.height);
      targetWidth = windowRight - windowLeft;
      targetHeight = windowBottom - windowTop;
    }

    final deltaLeft = -windowLeft;
    final deltaTop = -windowTop;

    if ((targetWidth - oldSize.width).abs() < 1 &&
        (targetHeight - oldSize.height).abs() < 1 &&
        deltaLeft.abs() < 1 &&
        deltaTop.abs() < 1) {
      return;
    }

    targetPage.resizeInfiniteCanvas(
      Size(targetWidth, targetHeight),
      contentOffset: Offset(deltaLeft, deltaTop),
    );
    targetPage.buildSpatialIndex();

    if (mounted) {
      setState(() {});
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !coreInfo.isInfinite || coreInfo.pages.isEmpty) return;
      _applyInfiniteCanvasExpansionTransform(
        w: oldSize.width,
        h: oldSize.height,
        newWidth: targetPage.size.width,
        newHeight: targetPage.size.height,
        deltaLeft: deltaLeft,
        deltaTop: deltaTop,
      );
    });
  }

  void _trimInfiniteCanvasWhitespace(EditorPage page, {double buffer = 200}) {
    _fitInfiniteCanvasToContent(page, allowShrink: true, buffer: buffer);
  }

  void _applyInfiniteCanvasExpansionTransform({
    required double w,
    required double h,
    required double newWidth,
    required double newHeight,
    required double deltaLeft,
    required double deltaTop,
  }) {
    final containerWidth =
        _canvasGestureDetectorKey.currentState?.containerBounds.maxWidth ??
        _currentViewportWidth();
    const top = 0.0;

    final pageWidthFittedOld = math.min(w, containerWidth);
    final S_old = w > 0 ? pageWidthFittedOld / w : 1.0;
    final leftOffsetOld = (containerWidth - pageWidthFittedOld) / 2;

    final pageWidthFittedNew = math.min(newWidth, containerWidth);
    final S_new = newWidth > 0 ? pageWidthFittedNew / newWidth : 1.0;
    final leftOffsetNew = (containerWidth - pageWidthFittedNew) / 2;

    final m = _transformationController.value.clone();
    final tx = m.getTranslation().x;
    final ty = m.getTranslation().y;
    final scale = m.getMaxScaleOnAxis();

    final oldSceneX = -tx / scale;
    final oldSceneY = -ty / scale;

    final oldPageX = S_old > 0 ? (oldSceneX - leftOffsetOld) / S_old : 0.0;
    final oldPageY = S_old > 0 ? (oldSceneY - top) / S_old : 0.0;

    final newSceneX = leftOffsetNew + (oldPageX + deltaLeft) * S_new;
    final newSceneY = top + (oldPageY + deltaTop) * S_new;

    var newTx = -scale * newSceneX;
    var newTy = -scale * newSceneY;

    if (newTx.isNaN || newTx.isInfinite) newTx = tx;
    if (newTy.isNaN || newTy.isInfinite) newTy = ty;

    _skipTransformClampForExpansion.value = true;
    m.setTranslationRaw(newTx, newTy, m.getTranslation().z);
    _transformationController.value = m;
    if (mounted) setState(() {});
  }

  void removeExcessPages() {
    if (coreInfo.isInfinite) return;
    if (coreInfo.hasUnhydratedLazyPages) coreInfo.hydrateAllLazyPages();

    bool removedAPage = false;

    for (int i = coreInfo.pages.length - 1; i >= 1; --i) {
      final thisPage = coreInfo.pages[i];
      final prevPage = coreInfo.pages[i - 1];
      if (thisPage.isEmpty && prevPage.isEmpty) {
        final page = coreInfo.pages.removeAt(i);
        coreInfo.links = coreInfo.links
            .where(
              (l) =>
                  (l.sourcePageId != null && l.sourcePageId != page.id) ||
                  (l.sourcePageId == null && l.sourcePageIndex != i),
            )
            .toList();
        page.dispose();
        removedAPage = true;
      } else {
        break;
      }
    }

    if (removedAPage) {
      try {
        unawaited(
          NoteLinksDatabase.instance.setLinksForPath(
            coreInfo.filePath,
            coreInfo.links,
            rootDirectory: FileManager.documentsDirectory,
          ),
        );
      } catch (e) {
        log.warning('Failed to update note links metadata: $e');
      }

      final screenWidth = _currentViewportWidth();
      final offsets = _generatePageOffsets(coreInfo.pages, screenWidth);

      final scrollY = this.scrollY;
      late final topOfLastPage = -CanvasGestureDetector.getTopOfPage(
        pageIndex: coreInfo.pages.length - 1,
        pageOffsets: offsets,
      );
      final bottomOfLastPage = -CanvasGestureDetector.getTopOfPage(
        pageIndex: coreInfo.pages.length,
        pageOffsets: offsets,
      );

      if (scrollY < bottomOfLastPage) {
        _transformationController.value = Matrix4.translationValues(
          0,

          topOfLastPage + 50,
          0,
        );
      }
    }
  }

  void undo([EditorHistoryItem? item]) {
    if (coreInfo.hasUnhydratedLazyPages) coreInfo.hydrateAllLazyPages();
    if (item == null) {
      if (!history.canUndo) return;

      item = history.undo();
    }

    _isUndoRedoInProgress = true;
    _releaseAreaEraserQueueAndSessions();

    setState(() {
      switch (item!.type) {
        case .draw:
          final affectedPageIndices = <int>{};
          for (final stroke in item.strokes) {
            final page = coreInfo.pages[stroke.pageIndex];
            page.removeStrokeFromAnyLayer(stroke);
            page.strokeSpatialIndex?.remove(stroke);
            affectedPageIndices.add(stroke.pageIndex);
          }
          for (final image in item.images) {
            coreInfo.pages[image.pageIndex].removeImageFromAnyLayer(image);
            affectedPageIndices.add(image.pageIndex);
          }
          for (final i in affectedPageIndices) {
            coreInfo.pages[i].redrawStrokes();
          }
          removeExcessPages();

          final select = Select.currentSelect;
          if (select.doneSelecting &&
              (item.strokes.any(
                    (s) => select.selectResult.strokes.contains(s),
                  ) ||
                  item.images.any(
                    (i) => select.selectResult.images.contains(i),
                  ))) {
            select.unselect();
            if (_autoSwitchBackToShapeTool) {
              _autoSwitchBackToShapeTool = false;
              currentTool = ShapeTool.currentShapeTool;
            }
          }
          break;

        case .erase:
          final affectedPageIndices = <int>{};
          for (final stroke in item.strokes) {
            createPage(stroke.pageIndex);
            final idx = stroke.pageIndex.clamp(0, coreInfo.pages.length - 1);
            final page = coreInfo.pages[idx];
            if (coreInfo.isInfinite) stroke.pageIndex = 0;
            page.insertStroke(stroke);
            page.strokeSpatialIndex?.insert(stroke);
            affectedPageIndices.add(idx);
          }
          for (final image in item.images) {
            createPage(image.pageIndex);
            final idx = image.pageIndex.clamp(0, coreInfo.pages.length - 1);
            coreInfo.pages[idx].images.add(image);
            if (coreInfo.isInfinite) image.pageIndex = 0;
            image.newImage = true;
            affectedPageIndices.add(idx);
          }
          for (final i in affectedPageIndices) {
            coreInfo.pages[i].redrawStrokes();
          }
          break;

        case .areaErase:
        case .changeStrokeType:
          final affectedPageIndices = <int>{};
          final added = item.strokesAdded!;
          for (final stroke in added) {
            final idx = stroke.pageIndex.clamp(0, coreInfo.pages.length - 1);
            final page = coreInfo.pages[idx];
            page.removeStrokeFromAnyLayer(stroke);
            page.strokeSpatialIndex?.remove(stroke);
            affectedPageIndices.add(idx);
          }
          for (final stroke in item.strokes) {
            createPage(stroke.pageIndex);
            final idx = stroke.pageIndex.clamp(0, coreInfo.pages.length - 1);
            final page = coreInfo.pages[idx];
            if (coreInfo.isInfinite) stroke.pageIndex = 0;
            page.insertStroke(stroke);
            page.strokeSpatialIndex?.insert(stroke);
            affectedPageIndices.add(idx);
          }
          for (final image in item.images) {
            createPage(image.pageIndex);
            final idx = image.pageIndex.clamp(0, coreInfo.pages.length - 1);
            coreInfo.pages[idx].images.add(image);
            if (coreInfo.isInfinite) image.pageIndex = 0;
            image.newImage = true;
            affectedPageIndices.add(idx);
          }
          for (final i in affectedPageIndices) {
            coreInfo.pages[i].redrawStrokes();
          }
          break;

        case .deletePage:
          createPage(item.pageIndex - 1);

          if (item.pages != null) {
            coreInfo.pages.insertAll(item.pageIndex, item.pages!);
          } else {
            coreInfo.pages.insert(item.pageIndex, item.page!);
          }

          for (int i = item.pageIndex; i < coreInfo.pages.length; ++i) {
            final page = coreInfo.pages[i];
            for (final stroke in page.strokes) {
              stroke.pageIndex = i;
            }
            for (final image in page.images) {
              image.pageIndex = i;
            }
            page.backgroundImage?.pageIndex = i;
          }
          break;

        case .insertPage:
          if (item.pages != null) {
            coreInfo.pages.removeRange(
              item.pageIndex,
              item.pageIndex + item.pages!.length,
            );
          } else {
            coreInfo.pages.removeAt(item.pageIndex);
          }

          for (int i = item.pageIndex; i < coreInfo.pages.length; ++i) {
            final page = coreInfo.pages[i];
            for (final stroke in page.strokes) {
              stroke.pageIndex = i;
            }
            for (final image in page.images) {
              image.pageIndex = i;
            }
            page.backgroundImage?.pageIndex = i;
          }
          break;

        case .move:
          final select = Select.currentSelect;
          final isCurrentSelection =
              select.doneSelecting &&
              item.strokes.any((s) => select.selectResult.strokes.contains(s));

          final affectedPageIndices = <int>{};

          if (item.offset != null) {
            final shiftOffset = Offset(-item.offset!.left, -item.offset!.top);
            for (final stroke in item.strokes) {
              final page = coreInfo.pages[stroke.pageIndex];
              page.strokeSpatialIndex?.remove(stroke);
              stroke.shift(shiftOffset);
              if (item.pageIndex != item.pageIndexStart) {
                moveStrokeToPage(stroke, item.pageIndex, item.pageIndexStart!);
                affectedPageIndices.add(item.pageIndex);
                affectedPageIndices.add(item.pageIndexStart!);
                coreInfo.pages[item.pageIndexStart!].strokeSpatialIndex?.insert(
                  stroke,
                );
              } else {
                affectedPageIndices.add(stroke.pageIndex);
                page.strokeSpatialIndex?.insert(stroke);
              }
            }
            if (select.doneSelecting && isCurrentSelection) {
              select.selectResult.path = select.selectResult.path.shift(
                shiftOffset,
              );
              if (item.pageIndex != item.pageIndexStart) {
                select.selectResult.pageIndex = item.pageIndexStart!;
              }
            }
            for (final image in item.images) {
              image.dstRect = image.dstRect.shift(shiftOffset);
              if (item.pageIndex != item.pageIndexStart) {
                moveImageToPage(image, item.pageIndex, item.pageIndexStart!);
                affectedPageIndices.add(item.pageIndex);
                affectedPageIndices.add(item.pageIndexStart!);
              } else {
                affectedPageIndices.add(image.pageIndex);
              }
            }
          }

          if (item.rotation != null && item.centroid != null) {
            final rotationDeg = -item.rotation!;
            final rotationRad = rotationDeg * math.pi / 180.0;
            for (final stroke in item.strokes) {
              final page = coreInfo.pages[stroke.pageIndex];
              page.strokeSpatialIndex?.remove(stroke);
              stroke.rotate(rotationRad, item.centroid!);
              page.strokeSpatialIndex?.insert(stroke);
              affectedPageIndices.add(stroke.pageIndex);
            }
            for (final image in item.images) {
              image.rotate(rotationRad, item.centroid!);
              affectedPageIndices.add(image.pageIndex);
            }
            if (isCurrentSelection) {
              select.selectResult.path = select.selectResult.path.transform(
                (vmath.Matrix4.identity()
                      ..translate(item.centroid!.dx, item.centroid!.dy)
                      ..rotateZ(rotationRad)
                      ..translate(-item.centroid!.dx, -item.centroid!.dy))
                    .storage,
              );
              select.selectResult.rotationDeg =
                  (select.selectResult.rotationDeg + rotationDeg) % 360.0;
            }
          }

          if (item.scale != null && item.centroid != null) {
            final scale = 1.0 / item.scale!;
            for (int i = 0; i < item.strokes.length; i++) {
              final stroke = item.strokes[i];
              final page = coreInfo.pages[stroke.pageIndex];
              if (stroke is ShapeStroke) {
                final scaled = stroke.scaled(scale, item.centroid!);

                final idx = page.strokes.indexOf(stroke);
                if (idx >= 0) {
                  page.strokeSpatialIndex?.remove(stroke);
                  page.strokes[idx] = scaled;
                  page.strokeSpatialIndex?.insert(scaled);
                }

                if (isCurrentSelection) {
                  final sIdx = select.selectResult.strokes.indexOf(stroke);
                  if (sIdx >= 0) {
                    select.selectResult.strokes[sIdx] = scaled;
                  }
                }
              } else {
                page.strokeSpatialIndex?.remove(stroke);
                stroke.scale(scale, item.centroid!);
                page.strokeSpatialIndex?.insert(stroke);
              }
              affectedPageIndices.add(stroke.pageIndex);
            }
            for (final image in item.images) {
              image.scale(scale, item.centroid!);
              affectedPageIndices.add(image.pageIndex);
            }
            if (isCurrentSelection) {
              select.selectResult.path = select.selectResult.path.transform(
                (vmath.Matrix4.identity()
                      ..translate(item.centroid!.dx, item.centroid!.dy)
                      ..scale(scale, scale)
                      ..translate(-item.centroid!.dx, -item.centroid!.dy))
                    .storage,
              );
            }
          }

          if (isCurrentSelection) {
            select.selectResult.displayBounds = null;
          }

          for (final idx in affectedPageIndices) {
            coreInfo.pages[idx].redrawStrokes();
          }
          break;

        case .quillChange:
          final quill = coreInfo.pages[item.pageIndex].quill;
          quill.controller.undo();
          break;

        case .quillUndoneChange:
          final quill = coreInfo.pages[item.pageIndex].quill;
          quill.controller.redo();
          break;

        case .changeColor:
          for (final stroke in item.strokes) {
            stroke.color = item.colorChange![stroke]!.previous;
          }
          break;
      }

      Select.currentSelect.unselect();
    });

    _bumpInteractionRepaint();

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _isUndoRedoInProgress = false;
    });

    autosaveAfterDelay();
  }

  void redo() {
    if (!history.canRedo) return;
    if (coreInfo.hasUnhydratedLazyPages) coreInfo.hydrateAllLazyPages();
    final item = history.redo();

    _isUndoRedoInProgress = true;
    _releaseAreaEraserQueueAndSessions();

    setState(() {
      switch (item.type) {
        case .draw:
          final affectedPageIndices = <int>{};
          for (final stroke in item.strokes) {
            createPage(stroke.pageIndex);
            final idx = stroke.pageIndex.clamp(0, coreInfo.pages.length - 1);
            final page = coreInfo.pages[idx];
            if (coreInfo.isInfinite) stroke.pageIndex = 0;
            page.insertStroke(stroke);
            page.strokeSpatialIndex?.insert(stroke);
            affectedPageIndices.add(idx);
          }
          for (final image in item.images) {
            createPage(image.pageIndex);
            final idx = image.pageIndex.clamp(0, coreInfo.pages.length - 1);
            coreInfo.pages[idx].images.add(image);
            if (coreInfo.isInfinite) image.pageIndex = 0;
            image.newImage = true;
            affectedPageIndices.add(idx);
          }
          for (final i in affectedPageIndices) {
            coreInfo.pages[i].redrawStrokes();
          }
          break;

        case .erase:
          final affectedPageIndices = <int>{};
          for (final stroke in item.strokes) {
            final page = coreInfo.pages[stroke.pageIndex];
            page.removeStrokeFromAnyLayer(stroke);
            page.strokeSpatialIndex?.remove(stroke);
            affectedPageIndices.add(stroke.pageIndex);
          }
          for (final image in item.images) {
            coreInfo.pages[image.pageIndex].removeImageFromAnyLayer(image);
            affectedPageIndices.add(image.pageIndex);
          }
          for (final i in affectedPageIndices) {
            coreInfo.pages[i].redrawStrokes();
          }
          removeExcessPages();
          break;

        case .areaErase:
        case .changeStrokeType:
          final affectedPageIndices = <int>{};
          for (final stroke in item.strokes) {
            final idx = stroke.pageIndex.clamp(0, coreInfo.pages.length - 1);
            coreInfo.pages[idx].removeStrokeFromAnyLayer(stroke);
            coreInfo.pages[idx].strokeSpatialIndex?.remove(stroke);
            affectedPageIndices.add(idx);
          }
          for (final stroke in item.strokesAdded!) {
            createPage(stroke.pageIndex);
            final idx = stroke.pageIndex.clamp(0, coreInfo.pages.length - 1);
            final page = coreInfo.pages[idx];
            page.insertStroke(stroke);
            page.strokeSpatialIndex?.insert(stroke);
            affectedPageIndices.add(idx);
          }
          for (final i in affectedPageIndices) {
            coreInfo.pages[i].redrawStrokes();
          }
          break;

        case .deletePage:
          if (item.pageIndex >= 0 && item.pageIndex < coreInfo.pages.length) {
            final page = coreInfo.pages.removeAt(item.pageIndex);
            coreInfo.links = coreInfo.links
                .where(
                  (l) =>
                      (l.sourcePageId != null && l.sourcePageId != page.id) ||
                      (l.sourcePageId == null &&
                          l.sourcePageIndex != item.pageIndex),
                )
                .toList();
            createPage(item.pageIndex - 1);
            try {
              unawaited(
                NoteLinksDatabase.instance.setLinksForPath(
                  coreInfo.filePath,
                  coreInfo.links,
                  rootDirectory: FileManager.documentsDirectory,
                ),
              );
            } catch (e) {
              log.warning('Failed to update note links metadata: $e');
            }
          }
          break;

        case .insertPage:
          createPage(item.pageIndex - 1);
          if (item.pages != null) {
            coreInfo.pages.insertAll(item.pageIndex, item.pages!);
          } else {
            coreInfo.pages.insert(item.pageIndex, item.page!);
          }
          for (int i = item.pageIndex; i < coreInfo.pages.length; ++i) {
            final page = coreInfo.pages[i];
            for (final stroke in page.strokes) {
              stroke.pageIndex = i;
            }
            for (final image in page.images) {
              image.pageIndex = i;
            }
            page.backgroundImage?.pageIndex = i;
          }
          break;

        case .move:
          final select = Select.currentSelect;
          final isCurrentSelection =
              select.doneSelecting &&
              item.strokes.any((s) => select.selectResult.strokes.contains(s));
          final affectedPageIndices = <int>{};

          if (item.offset != null) {
            final shiftOffset = Offset(item.offset!.left, item.offset!.top);
            for (final stroke in item.strokes) {
              final page = coreInfo.pages[stroke.pageIndex];
              page.strokeSpatialIndex?.remove(stroke);
              stroke.shift(shiftOffset);
              if (item.pageIndexStart != item.pageIndex) {
                moveStrokeToPage(stroke, item.pageIndexStart!, item.pageIndex);
                affectedPageIndices.add(item.pageIndexStart!);
                affectedPageIndices.add(item.pageIndex);
                coreInfo.pages[item.pageIndex].strokeSpatialIndex?.insert(
                  stroke,
                );
              } else {
                affectedPageIndices.add(stroke.pageIndex);
                page.strokeSpatialIndex?.insert(stroke);
              }
            }
            if (select.doneSelecting && isCurrentSelection) {
              select.selectResult.path = select.selectResult.path.shift(
                shiftOffset,
              );
              if (item.pageIndexStart != item.pageIndex) {
                select.selectResult.pageIndex = item.pageIndex;
              }
            }
            for (final image in item.images) {
              image.dstRect = image.dstRect.shift(shiftOffset);
              if (item.pageIndexStart != item.pageIndex) {
                moveImageToPage(image, item.pageIndexStart!, item.pageIndex);
                affectedPageIndices.add(item.pageIndexStart!);
                affectedPageIndices.add(item.pageIndex);
              } else {
                affectedPageIndices.add(image.pageIndex);
              }
            }
          }

          if (item.rotation != null && item.centroid != null) {
            final rotationDeg = item.rotation!;
            final rotationRad = rotationDeg * math.pi / 180.0;
            for (final stroke in item.strokes) {
              final page = coreInfo.pages[stroke.pageIndex];
              page.strokeSpatialIndex?.remove(stroke);
              stroke.rotate(rotationRad, item.centroid!);
              page.strokeSpatialIndex?.insert(stroke);
              affectedPageIndices.add(stroke.pageIndex);
            }
            for (final image in item.images) {
              image.rotate(rotationRad, item.centroid!);
              affectedPageIndices.add(image.pageIndex);
            }
            if (isCurrentSelection) {
              select.selectResult.path = select.selectResult.path.transform(
                (vmath.Matrix4.identity()
                      ..translate(item.centroid!.dx, item.centroid!.dy)
                      ..rotateZ(rotationRad)
                      ..translate(-item.centroid!.dx, -item.centroid!.dy))
                    .storage,
              );
              select.selectResult.rotationDeg =
                  (select.selectResult.rotationDeg + rotationDeg) % 360.0;
            }
          }

          if (item.scale != null && item.centroid != null) {
            final scale = item.scale!;
            for (int i = 0; i < item.strokes.length; i++) {
              final stroke = item.strokes[i];
              final page = coreInfo.pages[stroke.pageIndex];
              if (stroke is ShapeStroke) {
                final scaled = stroke.scaled(scale, item.centroid!);
                final idx = page.strokes.indexOf(stroke);
                if (idx >= 0) {
                  page.strokeSpatialIndex?.remove(stroke);
                  page.strokes[idx] = scaled;
                  page.strokeSpatialIndex?.insert(scaled);
                }
                if (isCurrentSelection) {
                  final sIdx = select.selectResult.strokes.indexOf(stroke);
                  if (sIdx >= 0) select.selectResult.strokes[sIdx] = scaled;
                }
              } else {
                page.strokeSpatialIndex?.remove(stroke);
                stroke.scale(scale, item.centroid!);
                page.strokeSpatialIndex?.insert(stroke);
              }
              affectedPageIndices.add(stroke.pageIndex);
            }
            for (final image in item.images) {
              image.scale(scale, item.centroid!);
              affectedPageIndices.add(image.pageIndex);
            }
            if (isCurrentSelection) {
              select.selectResult.path = select.selectResult.path.transform(
                (vmath.Matrix4.identity()
                      ..translate(item.centroid!.dx, item.centroid!.dy)
                      ..scale(scale, scale)
                      ..translate(-item.centroid!.dx, -item.centroid!.dy))
                    .storage,
              );
            }
          }

          if (isCurrentSelection) {
            select.selectResult.displayBounds = null;
          }

          for (final idx in affectedPageIndices) {
            coreInfo.pages[idx].redrawStrokes();
          }
          break;

        case .quillChange:
        case .quillUndoneChange:
          final quill = coreInfo.pages[item.pageIndex].quill;
          quill.controller.redo();
          break;

        case .changeColor:
          for (final stroke in item.strokes) {
            stroke.color = item.colorChange![stroke]!.current;
          }
          break;
      }

      Select.currentSelect.unselect();
    });

    _bumpInteractionRepaint();

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _isUndoRedoInProgress = false;
    });

    autosaveAfterDelay();
  }

  Offset _safelyGetLocalPosition(int pageIndex, Offset globalPoint) {
    final page = coreInfo.pages[pageIndex];

    if (coreInfo.isInfinite && coreInfo.pages.isNotEmpty) {
      final infinitePage = coreInfo.pages.first;
      final box = infinitePage.renderBox;
      if (box != null && box.attached) {
        try {
          return box.globalToLocal(globalPoint);
        } catch (_) {}
      }

      try {
        final gestureState = _canvasGestureDetectorKey.currentState;
        final renderBox =
            _canvasGestureDetectorKey.currentContext?.findRenderObject()
                as RenderBox?;

        if (gestureState != null && renderBox != null && renderBox.attached) {
          final containerWidth = gestureState.containerBounds.maxWidth;
          final transform = _transformationController.value;
          final scale = transform.approxScale;
          final translation = transform.getTranslation();

          final viewportPoint = renderBox.globalToLocal(globalPoint);
          final canvasX = (viewportPoint.dx - translation.x) / scale;
          final canvasY = (viewportPoint.dy - translation.y) / scale;

          final pageWidthFitted = math.min(
            infinitePage.size.width,
            containerWidth,
          );
          final leftOffset = (containerWidth - pageWidthFitted) / 2;
          final fittedScale = pageWidthFitted / infinitePage.size.width;

          return Offset(
            (canvasX - leftOffset) / fittedScale,
            canvasY / fittedScale,
          );
        }
      } catch (e) {
        log.warning('Infinite local position fallback failed: $e');
      }
    }

    final box = page.renderBox;
    if (box != null && box.attached) {
      try {
        return box.globalToLocal(globalPoint);
      } catch (_) {}
    }

    try {
      final gestureState = _canvasGestureDetectorKey.currentState;

      final renderBox =
          _canvasGestureDetectorKey.currentContext?.findRenderObject()
              as RenderBox?;

      if (gestureState != null && renderBox != null && renderBox.attached) {
        final containerWidth = gestureState.containerBounds.maxWidth;
        final transform = _transformationController.value;
        final scale = transform.approxScale;
        final translation = transform.getTranslation();

        final viewportPoint = renderBox.globalToLocal(globalPoint);
        final canvasX = (viewportPoint.dx - translation.x) / scale;
        final canvasY = (viewportPoint.dy - translation.y) / scale;

        final offsets = _generatePageOffsets(coreInfo.pages, containerWidth);
        final pageOffsetY = CanvasGestureDetector.getTopOfPage(
          pageIndex: pageIndex,
          pageOffsets: offsets,
        );

        final pageWidthFitted = math.min(page.size.width, containerWidth);
        final leftOffset = (containerWidth - pageWidthFitted) / 2;
        final fittedScale = pageWidthFitted / page.size.width;

        return Offset(
          (canvasX - leftOffset) / fittedScale,
          (canvasY - pageOffsetY) / fittedScale,
        );
      }
    } catch (e) {
      log.warning('Fallback local position calculation failed: $e');
    }
    return Offset.zero;
  }

  int? onWhichPageIsFocalPoint(Offset focalPoint) {
    if (coreInfo.isInfinite) {
      return coreInfo.pages.isEmpty ? null : 0;
    }

    for (int i = 0; i < coreInfo.pages.length; ++i) {
      final box = coreInfo.pages[i].renderBox;
      if (box != null && box.attached) {
        try {
          final pageBounds = Offset.zero & coreInfo.pages[i].size;
          if (pageBounds.contains(box.globalToLocal(focalPoint))) return i;
        } catch (_) {
          continue;
        }
      }
    }

    try {
      final gestureState = _canvasGestureDetectorKey.currentState;
      if (gestureState == null) return null;

      final renderBox =
          _canvasGestureDetectorKey.currentContext?.findRenderObject()
              as RenderBox?;
      if (renderBox == null || !renderBox.attached) return null;

      final containerWidth = gestureState.containerBounds.maxWidth;
      if (containerWidth <= 0) return null;

      final viewportPoint = renderBox.globalToLocal(focalPoint);

      final transform = _transformationController.value;
      final scale = transform.approxScale;
      final translation = transform.getTranslation();

      final canvasX = (viewportPoint.dx - translation.x) / scale;
      final canvasY = (viewportPoint.dy - translation.y) / scale;

      double currentY = Editor.gapBetweenPages * 2;

      for (int i = 0; i < coreInfo.pages.length; ++i) {
        final page = coreInfo.pages[i];

        final pageWidthFitted = math.min(page.size.width, containerWidth);
        final pageHeightFitted =
            (pageWidthFitted / page.size.width) * page.size.height;

        if (canvasY >= currentY && canvasY <= currentY + pageHeightFitted) {
          final leftOffset = (containerWidth - pageWidthFitted) / 2;
          if (canvasX >= leftOffset &&
              canvasX <= leftOffset + pageWidthFitted) {
            return i;
          }
        }

        currentY += pageHeightFitted + Editor.gapBetweenPages;
      }
    } catch (e) {
      log.warning('Fallback hit test failed: $e');
    }

    return null;
  }

  Offset previousPosition = .zero;
  bool _isRotating = false;
  Offset? _rotationStartPosition;
  double _rotationStartAngle = 0.0;
  bool _isDraggingVertex = false;
  int? _draggedVertexIndex;
  ShapeStroke? _draggedTriangle;
  bool _isScaling = false;
  Offset? _scaleHandle;
  double _initialScaleRadius = 0.0;

  Offset? eraserPosition;
  final ValueNotifier<Offset?> _eraserPositionRepaint = ValueNotifier(null);

  List<Stroke>? _eraserDeltaRemoved;
  List<Stroke>? _eraserDeltaAdded;

  /// Soft per-apply yield for live area erase. Not a stroke-count cap —
  /// unfinished circle geometry continues on the next pointer sample / frame.
  static const int _kAreaEraserTimeBudgetMs = 7;

  bool _eraserAreaDragActive = false;
  int _areaEraserDrainGeneration = 0;
  bool _areaEraserPostFrameScheduled = false;
  EditorPage? _areaEraserWorkPage;
  Offset? _areaEraserWorkPos;

  Offset moveOffset = .zero;
  double totalRotation = 0.0;
  double totalScale = 1.0;
  final Set<int> _selectionDirtyPageIndices = {};
  SelectionTransformPreview? _selectionPreview;

  /// Selected strokes removed from the page for the duration of a move/scale/
  /// rotate so the base layer does not keep painting a stationary "ghost".
  var _selectionStrokesDetachedFromPage = false;

  SelectionHandlesInteractionMode _selectionHandlesInteractionMode =
      SelectionHandlesInteractionMode.resize;
  bool _selectionGestureBeganOnModeChip = false;
  Offset _selectionChipGestureOriginPage = Offset.zero;
  double _selectionChipGestureMaxMove = 0.0;
  DateTime? _selectionChipWallClockStart;

  var isHovering = true;
  int? dragPageIndex;
  PointerDeviceKind? currentPointerKind;
  double? currentPressure;
  Duration currentTimestamp = Duration.zero;

  Offset? _lastPenDragUpdatePosition;
  DateTime? _lastPenSignificantMoveAt;
  static const double _penHoldJitterThreshold = 12.0;

  static const double _rawDrawSampleMinDistSq = 0.25;
  static const double _rawDrawSampleMinDistSqLowRefresh = 0.09;
  bool _rawPenSampleSeenThisStroke = false;
  Duration? _lastRawPenSampleTimestamp;
  Timer? _penHoldRecognitionTimer;
  bool _penHoldSatisfied = false;
  RecognizedUnistroke? _penHoldDetectedShape;

  void _markCanvasInputActivity({bool cancelPendingAutosave = false}) {
    _lastUserActivityForAutosave = DateTime.now();
    if (cancelPendingAutosave &&
        savingState.value == SavingState.waitingToSave) {
      _delayedSaveTimer?.cancel();
      _delayedSaveTimer = null;
    }
  }

  bool _shouldUseHoldShapeRecognitionForCurrentTool() {
    if (currentTool is! Pen) return false;
    return stows.shapeRecognitionDelay.value >= 0;
  }

  void _restartPenHoldRecognitionTimer() {
    _penHoldRecognitionTimer?.cancel();
    _penHoldSatisfied = false;
    if (_penHoldDetectedShape != null) {
      _penHoldDetectedShape = null;
      clearDetectedShapePreviewCache();
    }
    if (!_shouldUseHoldShapeRecognitionForCurrentTool()) return;
    final delayMs = stows.shapeRecognitionDelay.value;
    final isHighlighter = currentTool is Highlighter;
    _penHoldRecognitionTimer = Timer(Duration(milliseconds: delayMs), () {
      _penHoldSatisfied = true;
      final liveStroke = Pen.currentStroke;
      if (liveStroke == null || liveStroke.length < 2) return;

      final detected = liveStroke.detectShape();
      final minScore = detected?.name == DefaultUnistrokeNames.infinity
          ? 0.45
          : (detected?.name == DefaultUnistrokeNames.line ? 0.5 : 0.55);
      if (detected != null && detected.score >= minScore) {
        final bool isLineOrArrow =
            detected.name == DefaultUnistrokeNames.line ||
            detected.name == DefaultUnistrokeNames.arrow;
        if (isHighlighter ? isLineOrArrow : true) {
          clearDetectedShapePreviewCache();
          _penHoldDetectedShape = detected;
          // Warm preview path once — paint must not rebuild ShapeStroke.
          buildDetectedShapePreviewPath(liveStroke, detected);
          if (mounted) setState(() {});
        }
      }
    });
  }

  void _scheduleLiveInkRepaint(EditorPage page) {
    // Paint this pointer event — waiting for the next frame left the mesh
    // one sample behind the stylus.
    page.redrawStrokes();
    _bumpInteractionRepaint();
  }

  void _recordLivePenSample(
    EditorPage page,
    Offset position,
    Duration timestamp, {
    required bool rawPointerSample,
  }) {
    _markCanvasInputActivity();
    (currentTool as Pen).onDragUpdate(position, currentPressure, timestamp);

    if (rawPointerSample) {
      _rawPenSampleSeenThisStroke = true;
      _lastRawPenSampleTimestamp = timestamp;
    }

    final lastPos = _lastPenDragUpdatePosition;
    // While a shape is suggested, any real draw gesture cancels it — the old
    // 12px threshold kept the expensive preview alive during continued inking.
    final moveThreshold = _penHoldDetectedShape != null
        ? 2.5
        : _penHoldJitterThreshold;
    if (lastPos == null || (position - lastPos).distance > moveThreshold) {
      _lastPenDragUpdatePosition = position;
      _lastPenSignificantMoveAt = DateTime.now();
      final hadPreview = _penHoldDetectedShape != null;
      _restartPenHoldRecognitionTimer();
      if (hadPreview && mounted) setState(() {});
    }

    _scheduleLiveInkRepaint(page);
  }

  bool _shouldSkipGesturePenSample(Duration timestamp) {
    final rawTimestamp = _lastRawPenSampleTimestamp;
    if (!_rawPenSampleSeenThisStroke || rawTimestamp == null) return false;
    return timestamp <= rawTimestamp;
  }

  bool isDrawGesture(ScaleStartDetails details) {
    // Any canvas scale/draw pointer — used so docked-panel resize anchoring
    // does not fight the gesture (which previously froze the sidebar anim).
    _canvasGestureActive = true;

    if (_regionScreenshotMode) return false;

    if (coreInfo.readOnly) return false;

    CanvasImage.activeListener.notifyListenersPlease();

    _lastSeenPointerCountTimer?.cancel();

    if (currentPointerKind == PointerDeviceKind.stylus ||
        currentPointerKind == PointerDeviceKind.invertedStylus ||
        (currentPressure != null && currentPressure! > 0)) {
      lastSeenPointerCount = 1;
    } else {
      if (details.pointerCount >= 2) {
        lastSeenPointerCount = details.pointerCount;
        return false;
      }
      if (lastSeenPointerCount >= 2) {
        lastSeenPointerCount = 1;
      } else {
        lastSeenPointerCount = details.pointerCount;
      }
    }

    dragPageIndex = onWhichPageIsFocalPoint(details.focalPoint);
    if (dragPageIndex == null) return false;
    if (coreInfo.isLazyShellPage(dragPageIndex!)) {
      coreInfo.ensurePageHydrated(dragPageIndex!);
      _wirePageImageCallbacks(dragPageIndex!);
      listenToQuillChanges(
        coreInfo.pages[dragPageIndex!].quill,
        dragPageIndex!,
      );
    }

    if (currentTool == Tool.textEditing) {
      return false;
    }

    if (_imageCropState != null) {
      final cropImage = _imageCropState!.image;
      int? cropPageIndex;
      for (int i = 0; i < coreInfo.pages.length; i++) {
        if (coreInfo.pages[i].allImagesInDrawOrder.toList().contains(
          cropImage,
        )) {
          cropPageIndex = i;
          break;
        }
      }
      if (cropPageIndex != null && cropPageIndex == dragPageIndex) {
        final position = _safelyGetLocalPosition(
          dragPageIndex!,
          details.focalPoint,
        );
        if (_hitTestCropHandles(cropImage, position) != null) {
          return true;
        }
      }
    }

    if (currentPointerKind == PointerDeviceKind.stylus ||
        currentPointerKind == PointerDeviceKind.invertedStylus) {
      return true;
    }

    if (stows.enableFingerDrawing.value) {
      return true;
    }

    if (currentTool is! Select) {
      if (_imageCropState != null) return false;
      return false;
    }

    final page = coreInfo.pages[dragPageIndex!];
    final box = page.renderBox;

    // [FIX] CRITICAL: Check if box is attached before accessing globalToLocal
    if (box == null || !box.attached) return false;

    final position = box.globalToLocal(details.focalPoint);

    final select = Select.currentSelect;
    if (select.doneSelecting &&
        select.selectResult.pageIndex == dragPageIndex!) {
      // While cropping an image, do not claim gestures for selection resize/rotate/move

      final isCroppingThisSelection =
          _imageCropState != null &&
          select.selectResult.images.length == 1 &&
          identical(select.selectResult.images.first, _imageCropState!.image);
      if (isCroppingThisSelection) return false;

      final bounds = select.selectResult.getBounds();
      if (!bounds.isEmpty) {
        final currentScale = _quantizedCanvasScale;

        if (_hitSelectionModeChip(
              position,
              select.selectResult,
              currentScale,
            ) ||
            _hitSelectionVertexIndex(
                  position,
                  select.selectResult,
                  currentScale,
                ) !=
                null ||
            _hitSelectionCornerIndex(
                  position,
                  select.selectResult,
                  currentScale,
                ) !=
                null) {
          return true;
        }

        if (select.selectResult.contains(position)) return true;
      }
    }

    // Check if on an image (do not claim gesture when cropping this image)
    for (final image in page.images.reversed) {
      if (image.contains(position)) {
        if (image.locked) {
          continue;
        }
        if (_imageCropState != null &&
            identical(image, _imageCropState!.image)) {
          return false;
        }
        return true;
      }
    }

    if (stows.enableFingerDrawing.value) {
      for (final stroke in page.strokes.reversed) {
        if (stroke.contains(position)) {
          return true;
        }
      }
    }

    log.fine('Non-stylus input rejected - stylus only mode');
    return false;
  }

  _CropHandle? _hitTestCropHandles(PngEditorImage image, Offset pagePosition) {
    if (_imageCropState == null) return null;

    final center = image.dstRect.center;
    final dx = pagePosition.dx - center.dx;
    final dy = pagePosition.dy - center.dy;
    final angleRad = -image.rotationDeg * math.pi / 180.0;
    final localPos = Offset(
      center.dx + dx * math.cos(angleRad) - dy * math.sin(angleRad),
      center.dy + dx * math.sin(angleRad) + dy * math.cos(angleRad),
    );

    if (!image.dstRect.contains(localPos)) return null;

    final rect = _imageCropState!.normalizedCrop;
    final imgRect = image.dstRect;
    final left = imgRect.left + rect.left * imgRect.width;
    final right = imgRect.left + rect.right * imgRect.width;
    final top = imgRect.top + rect.top * imgRect.height;
    final bottom = imgRect.top + rect.bottom * imgRect.height;
    final w = right - left;
    final h = bottom - top;

    final hitRadius =
        30.0 / _transformationController.value.getMaxScaleOnAxis();
    bool hit(double x, double y) =>
        (Offset(x, y) - localPos).distance <= hitRadius;

    if (hit(left, top)) return _CropHandle.topLeft;
    if (hit(right, top)) return _CropHandle.topRight;
    if (hit(left, bottom)) return _CropHandle.bottomLeft;
    if (hit(right, bottom)) return _CropHandle.bottomRight;
    if (hit(left + w / 2, top)) return _CropHandle.topCenter;
    if (hit(left + w / 2, bottom)) return _CropHandle.bottomCenter;
    if (hit(left, top + h / 2)) return _CropHandle.centerLeft;
    if (hit(right, top + h / 2)) return _CropHandle.centerRight;

    if (localPos.dx >= left &&
        localPos.dx <= right &&
        localPos.dy >= top &&
        localPos.dy <= bottom) {
      return _CropHandle.inside;
    }

    return null;
  }

  void _applyEraserResultToPage(EditorPage page, EraserResult result) {
    var insertAt = page.strokes.length;
    if (result.removed.isNotEmpty) {
      final removedSet = result.removed.toSet();
      for (final stroke in result.removed) {
        final index = page.strokes.indexOf(stroke);
        if (index >= 0 && index < insertAt) insertAt = index;
      }
      page.strokes.removeWhere(removedSet.contains);
      for (final stroke in removedSet) {
        page.strokeSpatialIndex?.remove(stroke);
      }
    }
    if (result.added.isNotEmpty) {
      page.strokes.insertAll(
        insertAt.clamp(0, page.strokes.length),
        result.added,
      );
      for (final stroke in result.added) {
        page.strokeSpatialIndex?.insert(stroke);
      }
    }
  }

  void _ensureActiveLayerEraserSpatialIndex(EditorPage page) {
    if (page.strokes.isEmpty) {
      page.strokeSpatialIndex = null;
      return;
    }
    if (!page.strokeSpatialIndexCoversActiveLayer) {
      page.buildSpatialIndex(activeLayerOnly: true);
    }
  }

  void _syncFlushAreaEraserWork(
    EditorPage page,
    Eraser eraser,
    Offset position,
  ) {
    if (eraser.mode != EraserMode.area) return;
    _ensureActiveLayerEraserSpatialIndex(page);
    // Unbounded apply: finish any deferred circle cuts before recording undo.
    final result = eraser.apply(
      position,
      page.strokes,
      spatialIndex: page.strokeSpatialIndex,
      scale: _transformationController.value.getMaxScaleOnAxis(),
      areaTimeBudgetMs: null,
    );
    _applyEraserResultToPage(page, result);
    page.redrawStrokes();
  }

  void _scheduleAreaEraserBackgroundDrain() {
    if (_areaEraserPostFrameScheduled) return;
    _areaEraserPostFrameScheduled = true;
    final gen = _areaEraserDrainGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _areaEraserPostFrameScheduled = false;
      if (!mounted || _isDisposed || gen != _areaEraserDrainGeneration) return;
      _runDeferredAreaEraserChunk();
    });
  }

  /// Continues unfinished area-erase geometry from the last pointer sample.
  /// Does not re-scan "refused" strokes — only soft time-budget leftovers.
  void _runDeferredAreaEraserChunk() {
    if (!mounted || _isDisposed || !_eraserAreaDragActive) return;
    final page = _areaEraserWorkPage;
    final pos = _areaEraserWorkPos;
    if (page == null || pos == null) return;
    if (currentTool is! Eraser) return;
    final eraser = currentTool as Eraser;
    if (eraser.mode != EraserMode.area) return;
    _ensureActiveLayerEraserSpatialIndex(page);

    final result = eraser.apply(
      pos,
      page.strokes,
      spatialIndex: page.strokeSpatialIndex,
      scale: _transformationController.value.getMaxScaleOnAxis(),
      areaTimeBudgetMs: _kAreaEraserTimeBudgetMs,
    );
    _applyEraserResultToPage(page, result);
    if (result.removed.isNotEmpty || result.added.isNotEmpty) {
      page.redrawStrokes();
    }

    if (result.areaWorkRemaining) {
      _scheduleAreaEraserBackgroundDrain();
    }
  }

  void _abortAreaEraserBackgroundWork() {
    _eraserAreaDragActive = false;
    Eraser.isDragging = false;
    _areaEraserDrainGeneration++;
    _areaEraserPostFrameScheduled = false;
    _areaEraserWorkPage = null;
    _areaEraserWorkPos = null;
    _eraserPositionRepaint.value = null;
  }

  /// Stops deferred area-erase chunks and drops in-memory erase sessions so we
  /// do not leak maps or keep scheduling after the editor is left or hidden.
  void _releaseAreaEraserQueueAndSessions() {
    _abortAreaEraserBackgroundWork();
    Eraser.currentEraser.clearState();
  }

  void _doEraserApply(EditorPage page, Offset position) {
    final eraser = currentTool as Eraser;
    if (!eraser.shouldApplyAt(position)) return;

    _ensureActiveLayerEraserSpatialIndex(page);
    final bool isAreaMode = eraser.mode == EraserMode.area;
    _areaEraserWorkPage = page;
    _areaEraserWorkPos = position;

    final result = eraser.apply(
      position,
      page.strokes,
      spatialIndex: page.strokeSpatialIndex,
      scale: _transformationController.value.getMaxScaleOnAxis(),
      areaTimeBudgetMs: isAreaMode ? _kAreaEraserTimeBudgetMs : null,
    );
    _applyEraserResultToPage(page, result);

    if (isAreaMode && result.areaWorkRemaining) {
      _scheduleAreaEraserBackgroundDrain();
    }

    if (result.removed.isNotEmpty || result.added.isNotEmpty) {
      page.redrawStrokes();
      if (!isAreaMode) removeExcessPages();
    }
  }

  void onDrawStart(ScaleStartDetails details) {
    _markCanvasInputActivity(cancelPendingAutosave: true);
    _canvasGestureActive = true;
    _keepAliveController.stop();

    InteractiveCanvasViewer.isAutoPanningEnabled = false;

    _toolbarKey.currentState?.hideAllCards();

    final page = coreInfo.pages[dragPageIndex!];

    var position = _safelyGetLocalPosition(dragPageIndex!, details.focalPoint);

    if (_imageCropState != null) {
      final handle = _hitTestCropHandles(_imageCropState!.image, position);
      if (handle != null) {
        setState(() {
          _activeCropHandle = handle;
        });
        return;
      }
    }

    if (!coreInfo.isInfinite &&
        (currentTool is Pen ||
            currentTool is ShapeTool ||
            currentTool is Eraser ||
            currentTool is Select ||
            currentTool is LaserPointer)) {
      position = Offset(
        position.dx.clamp(0.0, page.size.width),
        position.dy.clamp(0.0, page.size.height),
      );
    }

    previousPosition = position;
    moveOffset = .zero;
    totalRotation = 0.0;
    totalScale = 1.0;
    _clearSelectionPreview();
    _selectionGestureBeganOnModeChip = false;
    _selectionChipGestureMaxMove = 0.0;
    _selectionChipWallClockStart = null;

    final timestamp = details.sourceTimeStamp ?? currentTimestamp;

    if (currentTool is Pen) {
      _rawPenSampleSeenThisStroke = false;
      _lastRawPenSampleTimestamp = null;
      _lastPenDragUpdatePosition = position;
      _lastPenSignificantMoveAt = DateTime.now();
      _restartPenHoldRecognitionTimer();
      (currentTool as Pen).onDragStart(
        position,
        page,
        dragPageIndex!,
        currentPressure,
        timestamp,
      );
    } else if (currentTool is ShapeTool) {
      (currentTool as ShapeTool).onDragStart(position, page, dragPageIndex!);
      page.redrawStrokes();
    } else if (currentTool is Eraser) {
      final er = currentTool as Eraser;
      _eraserAreaDragActive = er.mode == EraserMode.area;
      Eraser.isDragging = true;
      eraserPosition = position;
      _eraserPositionRepaint.value = position;
      // One rebuild to mount the eraser overlay; hits after this do not
      // setState (that dropped FPS when ink was actually deleted).
      if (mounted) setState(() {});
      _doEraserApply(page, position);
    } else if (currentTool is Select) {
      final select = currentTool as Select;
      select.selectResult.clearAlignmentGuides();
      if (select.doneSelecting &&
          select.selectResult.pageIndex == dragPageIndex!) {
        // Do not start selection resize/rotate/move while cropping this image
        final isCroppingThisSelection =
            _imageCropState != null &&
            select.selectResult.images.length == 1 &&
            identical(select.selectResult.images.first, _imageCropState!.image);
        if (isCroppingThisSelection) return;

        final bounds = select.selectResult.getBounds();
        if (bounds.isEmpty) {
          select.onDragStart(position, dragPageIndex!);
          history.clearRedo();
          _selectionHandlesInteractionMode =
              SelectionHandlesInteractionMode.resize;
        } else {
          final currentScale = _quantizedCanvasScale;

          if (_hitSelectionModeChip(
            position,
            select.selectResult,
            currentScale,
          )) {
            _selectionGestureBeganOnModeChip = true;
            _selectionChipGestureOriginPage = position;
            _selectionChipGestureMaxMove = 0.0;
            _selectionChipWallClockStart = DateTime.now();
            _isDraggingVertex = false;
            _isScaling = false;
            _isRotating = false;
            return;
          }

          final editableShape = _singleVertexEditableShape(select.selectResult);
          if (editableShape != null) {
            final vertexIndex = _hitSelectionVertexIndex(
              position,
              select.selectResult,
              currentScale,
            );
            if (vertexIndex != null) {
              _isDraggingVertex = true;
              _draggedVertexIndex = vertexIndex;
              _draggedTriangle = editableShape;
              _isScaling = false;
              _isRotating = false;
              return;
            }
          }

          final cornerIndex = _hitSelectionCornerIndex(
            position,
            select.selectResult,
            currentScale,
          );

          if (cornerIndex != null) {
            final rect = _selectionRectForInteractions(select.selectResult);
            final corners = [
              rect.topLeft,
              rect.topRight,
              rect.bottomRight,
              rect.bottomLeft,
            ];
            final rotationRad =
                _selectionRotationDegForInteractions(select.selectResult) *
                math.pi /
                180.0;
            final centroid = rect.center;
            final c = corners[cornerIndex];
            final dx = c.dx - centroid.dx;
            final dy = c.dy - centroid.dy;
            final rotatedC = Offset(
              centroid.dx +
                  dx * math.cos(rotationRad) -
                  dy * math.sin(rotationRad),
              centroid.dy +
                  dx * math.sin(rotationRad) +
                  dy * math.cos(rotationRad),
            );

            if (_selectionHandlesInteractionMode ==
                SelectionHandlesInteractionMode.rotate) {
              _isRotating = true;
              _rotationStartPosition = position;
              _rotationStartAngle = select.selectResult.rotationDeg;
              _isScaling = false;
            } else {
              _isScaling = true;
              _scaleHandle = corners[cornerIndex];
              _initialScaleRadius = (rotatedC - centroid).distance;
              _isRotating = false;
            }
            _isDraggingVertex = false;
            _beginSelectionPreview(select.selectResult);
            return;
          }

          if (select.selectResult.contains(position)) {
            _startSelectionLongPressTimer(details.focalPoint);

            _isScaling = false;
            _isRotating = false;
            _isDraggingVertex = false;
            _beginSelectionPreview(select.selectResult);
            InteractiveCanvasViewer.isAutoPanningEnabled = true;
            return;
          }

          final page = coreInfo.pages[dragPageIndex!];

          for (final image in page.images.reversed) {
            if (!image.contains(position)) continue;
            final plotMetadata = _plotMetadataFromImage(image);
            if (plotMetadata != null &&
                _isTapOnAnimationPlayButton(image: image, position: position)) {
              _showPlotVisualizer(plotMetadata);
              return;
            }
          }
          EditorImage? clickedImage;
          for (final image in page.images.reversed) {
            if (image.locked) continue;
            if (image.contains(position)) {
              clickedImage = image;
              break;
            }
          }

          Stroke? clickedStroke;
          if (clickedImage == null) {
            for (final stroke in page.strokes.reversed) {
              if (stroke.contains(position)) {
                clickedStroke = stroke;
                break;
              }
            }
          }

          if (clickedImage != null) {
            select.selectResult = SelectResult(
              pageIndex: dragPageIndex!,
              strokes: [],
              images: [clickedImage],
              path: Path()..addRect(clickedImage.dstRect),
              pageIndexStart: dragPageIndex!,
              rotationDeg: clickedImage.rotationDeg,
            );
            select.doneSelecting = true;
            _selectionHandlesInteractionMode =
                SelectionHandlesInteractionMode.resize;
            _isScaling = false;
            _isRotating = false;
            _isDraggingVertex = false;
            InteractiveCanvasViewer.isAutoPanningEnabled = true;
            setState(() {});
            return;
          } else if (clickedStroke != null) {
            select.selectResult = SelectResult(
              pageIndex: dragPageIndex!,
              strokes: [clickedStroke],
              images: [],
              path: Path(),
              pageIndexStart: dragPageIndex!,
              rotationDeg: clickedStroke.rotationDeg,
            );
            select.doneSelecting = true;
            _selectionHandlesInteractionMode =
                SelectionHandlesInteractionMode.resize;
            _isScaling = false;
            _isRotating = false;
            _isDraggingVertex = false;
            InteractiveCanvasViewer.isAutoPanningEnabled = true;
            setState(() {});
            return;
          } else {
            _isScaling = false;
            _isRotating = false;
            _isDraggingVertex = false;
            select.onDragStart(position, dragPageIndex!);
            history.clearRedo();
            _selectionHandlesInteractionMode =
                SelectionHandlesInteractionMode.resize;
          }
        }
      } else {
        final page = coreInfo.pages[dragPageIndex!];

        for (final image in page.images.reversed) {
          if (!image.contains(position)) continue;
          final plotMetadata = _plotMetadataFromImage(image);
          if (plotMetadata != null &&
              _isTapOnAnimationPlayButton(image: image, position: position)) {
            _showPlotVisualizer(plotMetadata);
            return;
          }
        }
        EditorImage? clickedImage;
        for (final image in page.images.reversed) {
          if (image.locked) continue;
          if (image.contains(position)) {
            clickedImage = image;
            break;
          }
        }

        if (clickedImage != null) {
          select.selectResult = SelectResult(
            pageIndex: dragPageIndex!,
            strokes: [],
            images: [clickedImage],
            path: Path()..addRect(clickedImage.dstRect),
            pageIndexStart: dragPageIndex!,
            rotationDeg: clickedImage.rotationDeg,
          );
          select.doneSelecting = true;
          _selectionHandlesInteractionMode =
              SelectionHandlesInteractionMode.resize;
          _isScaling = false;
          _isRotating = false;
          _isDraggingVertex = false;
          InteractiveCanvasViewer.isAutoPanningEnabled = true;
          setState(() {});
          return;
        } else {
          _isScaling = false;
          _isRotating = false;
          _isDraggingVertex = false;
          select.onDragStart(position, dragPageIndex!);
          history.clearRedo();
          _selectionHandlesInteractionMode =
              SelectionHandlesInteractionMode.resize;
        }
      }
    } else if (currentTool is LaserPointer) {
      (currentTool as LaserPointer).onDragStart(position, page, dragPageIndex!);
    }

    previousPosition = position;
    moveOffset = .zero;

    if (currentTool is! Select) {
      Select.currentSelect.unselect();
    }

    _bumpInteractionRepaint();
  }

  void onDrawUpdate(ScaleUpdateDetails details) {
    if (_selectionLongPressTimer != null) {
      if ((details.focalPoint - _longPressStartPosition).distance >
          _longPressMoveThreshold) {
        _selectionLongPressTimer?.cancel();
        _selectionLongPressTimer = null;
      }
    }

    if (_ignoreDragForMenu) return;

    if (dragPageIndex == null) return;

    final page = coreInfo.pages[dragPageIndex!];

    var position = _safelyGetLocalPosition(dragPageIndex!, details.focalPoint);

    if (_imageCropState != null && _activeCropHandle != null) {
      final image = _imageCropState!.image;
      final angleRad = -image.rotationDeg * math.pi / 180.0;
      final center = image.dstRect.center;
      final dx = position.dx - center.dx;
      final dy = position.dy - center.dy;
      final localPos = Offset(
        center.dx + dx * math.cos(angleRad) - dy * math.sin(angleRad),
        center.dy + dx * math.sin(angleRad) + dy * math.cos(angleRad),
      );

      double nx = (localPos.dx - image.dstRect.left) / image.dstRect.width;
      double ny = (localPos.dy - image.dstRect.top) / image.dstRect.height;

      Rect c = _imageCropState!.normalizedCrop;
      const minS = 0.05;
      double newL = c.left, newT = c.top, newR = c.right, newB = c.bottom;

      switch (_activeCropHandle!) {
        case _CropHandle.topLeft:
          newL = math.min(nx, c.right - minS);
          newT = math.min(ny, c.bottom - minS);
          break;
        case _CropHandle.topRight:
          newR = math.max(nx, c.left + minS);
          newT = math.min(ny, c.bottom - minS);
          break;
        case _CropHandle.bottomLeft:
          newL = math.min(nx, c.right - minS);
          newB = math.max(ny, c.top + minS);
          break;
        case _CropHandle.bottomRight:
          newR = math.max(nx, c.left + minS);
          newB = math.max(ny, c.top + minS);
          break;
        case _CropHandle.topCenter:
          newT = math.min(ny, c.bottom - minS);
          break;
        case _CropHandle.bottomCenter:
          newB = math.max(ny, c.top + minS);
          break;
        case _CropHandle.centerLeft:
          newL = math.min(nx, c.right - minS);
          break;
        case _CropHandle.centerRight:
          newR = math.max(nx, c.left + minS);
          break;
        case _CropHandle.inside:
          final w = c.width;
          final h = c.height;
          final rawDelta = details.focalPointDelta;
          final scale = _transformationController.value.getMaxScaleOnAxis();
          final pageDelta = rawDelta / scale;
          final dX =
              pageDelta.dx * math.cos(angleRad) -
              pageDelta.dy * math.sin(angleRad);
          final dY =
              pageDelta.dx * math.sin(angleRad) +
              pageDelta.dy * math.cos(angleRad);
          final nDx = dX / image.dstRect.width;
          final nDy = dY / image.dstRect.height;
          newL = (newL + nDx).clamp(0.0, 1.0 - w);
          newR = newL + w;
          newT = (newT + nDy).clamp(0.0, 1.0 - h);
          newB = newT + h;
          break;
      }

      setState(() {
        _imageCropState!.normalizedCrop = Rect.fromLTRB(
          newL.clamp(0.0, 1.0),
          newT.clamp(0.0, 1.0),
          newR.clamp(0.0, 1.0),
          newB.clamp(0.0, 1.0),
        );
      });
      return;
    }

    if (_selectionGestureBeganOnModeChip) {
      if (currentTool is Select &&
          dragPageIndex != null &&
          !_isScaling &&
          !_isRotating) {
        final sel = currentTool as Select;
        if (sel.doneSelecting && sel.selectResult.pageIndex == dragPageIndex!) {
          var pos = _safelyGetLocalPosition(dragPageIndex!, details.focalPoint);
          if (!coreInfo.isInfinite) {
            pos = Offset(
              pos.dx.clamp(0.0, page.size.width),
              pos.dy.clamp(0.0, page.size.height),
            );
          }
          _selectionChipGestureMaxMove = math.max(
            _selectionChipGestureMaxMove,
            (pos - _selectionChipGestureOriginPage).distance,
          );
          previousPosition = pos;
          return;
        }
      }
    }

    if (!coreInfo.isInfinite &&
        (currentTool is Pen || currentTool is ShapeTool)) {
      position = Offset(
        position.dx.clamp(0.0, page.size.width),
        position.dy.clamp(0.0, page.size.height),
      );
    }

    final offset = position - previousPosition;
    Offset adjustedOffset = offset;

    final timestamp = details.sourceTimeStamp ?? currentTimestamp;

    if (currentTool is Pen) {
      if (!_shouldSkipGesturePenSample(timestamp)) {
        _recordLivePenSample(
          page,
          position,
          timestamp,
          rawPointerSample: false,
        );
        _bumpInteractionRepaint();
      }
    } else if (currentTool is ShapeTool) {
      (currentTool as ShapeTool).onDragUpdate(position, page, dragPageIndex!);
      page.redrawStrokes();
      _bumpInteractionRepaint();
    } else if (currentTool is Eraser) {
      eraserPosition = position;
      _eraserPositionRepaint.value = position;
      _doEraserApply(page, position);
    } else if (currentTool is Select) {
      final select = currentTool as Select;
      if (select.doneSelecting) {
        // Do not apply selection resize/rotate/move while cropping
        if (_imageCropState != null &&
            select.selectResult.images.length == 1 &&
            identical(
              select.selectResult.images.first,
              _imageCropState!.image,
            )) {
          return;
        }
        if (_isDraggingVertex &&
            _draggedTriangle != null &&
            _draggedVertexIndex != null) {
          final triangle = _draggedTriangle!;
          final vertices = List<Offset>.from(triangle.controlPoints);
          if (_draggedVertexIndex! < 0 ||
              _draggedVertexIndex! >= vertices.length) {
            return;
          }

          final idx = _draggedVertexIndex!;
          final ShapeConfig newConfig;
          if (triangle.config.kind == ShapeKind.ellipse) {
            newConfig = ShapeGeometry.moveEllipseControlPoint(
              triangle.config,
              idx,
              position,
            );
          } else if (triangle.config.kind == ShapeKind.circle) {
            newConfig = ShapeGeometry.moveCircleControlPoint(
              triangle.config,
              idx,
              position,
            );
          } else {
            vertices[idx] = position;
            newConfig = ShapeGeometry.withControlPoints(
              triangle.config,
              vertices,
            );
          }

          final triangleIndex = page.strokes.indexOf(triangle);
          if (triangleIndex >= 0) {
            _markSelectionPageDirty(select.selectResult.pageIndex);
            final newTriangle = ShapeStroke(
              color: triangle.color,
              pressureEnabled: triangle.pressureEnabled,
              options: triangle.options,
              pageIndex: triangle.pageIndex,
              page: triangle.page,
              toolId: triangle.toolId,
              config: newConfig,
              fill: triangle.fill,
              fillColor: triangle.fillColor,
              shapeVertices: newConfig.vertices,
            );
            page.strokes[triangleIndex] = newTriangle;
            select.selectResult.strokes[0] = newTriangle;
            select.selectResult.displayBounds = null;
            _draggedTriangle = newTriangle;
            newTriangle.markPolygonNeedsUpdating();
            page.redrawStrokes();
          }
        } else if (_isScaling &&
            _scaleHandle != null &&
            _initialScaleRadius > 0) {
          final preview =
              _selectionPreview ??
              SelectionTransformPreview.fromSelection(select.selectResult);
          _selectionPreview = preview;
          final centroid = preview.visualBounds.center;
          final currentRadius = (position - centroid).distance;
          if (currentRadius > 0) {
            final scale = (currentRadius / _initialScaleRadius).clamp(0.2, 5.0);
            totalScale *= scale;
            _selectionPreview = preview.copyWith(scale: preview.scale * scale);
            _initialScaleRadius = currentRadius;
            select.selectResult.clearAlignmentGuides();
          }
        } else if (_isRotating && _rotationStartPosition != null) {
          final preview =
              _selectionPreview ??
              SelectionTransformPreview.fromSelection(select.selectResult);
          _selectionPreview = preview;
          final centroid = preview.visualBounds.center;

          final startAngle = math.atan2(
            _rotationStartPosition!.dy - centroid.dy,
            _rotationStartPosition!.dx - centroid.dx,
          );
          final currentAngle = math.atan2(
            position.dy - centroid.dy,
            position.dx - centroid.dx,
          );
          final deltaAngle = currentAngle - startAngle;
          final rawAngleDeg =
              (_rotationStartAngle + deltaAngle * 180.0 / math.pi) % 360.0;
          final newAngleDeg = _snapRotationAngle(rawAngleDeg);

          _selectionPreview = preview.copyWith(
            rotationDeltaDeg: newAngleDeg - preview.baseRotationDeg,
          );
          totalRotation = newAngleDeg - preview.baseRotationDeg;

          select.selectResult.clearAlignmentGuides();
        } else {
          int pageOffset = 0;
          if (position.dy > page.size.height + Editor.changePageThreshold) {
            if (coreInfo.pages.length > select.selectResult.pageIndex + 1) {
              adjustedOffset = Offset(
                offset.dx,
                offset.dy - (page.size.height + Editor.changePageThreshold),
              );
              pageOffset = 1;
            }
          } else if (position.dy < -Editor.changePageThreshold) {
            if (select.selectResult.pageIndex > 0) {
              final prevPage =
                  coreInfo.pages[select.selectResult.pageIndex - 1];
              adjustedOffset = Offset(
                offset.dx,
                offset.dy + (prevPage.size.height + Editor.changePageThreshold),
              );
              pageOffset = -1;
            }
          }

          if (select.selectResult.images.any((img) => img.locked)) {
            pageOffset = 0;
            select.selectResult.clearAlignmentGuides();
          } else {
            var preview =
                _selectionPreview ??
                SelectionTransformPreview.fromSelection(select.selectResult);
            _selectionPreview = preview;

            if (pageOffset != 0) {
              _commitSelectionPreview(select.selectResult);
              adjustedOffset = offset;

              selectionOffsetPage(pageOffset);

              dragPageIndex = onWhichPageIsFocalPoint(details.focalPoint);
              if (dragPageIndex == null) return;

              final pageNew = coreInfo.pages[dragPageIndex!];

              if (pageNew.renderBox?.attached == true) {
                position = pageNew.renderBox!.globalToLocal(details.focalPoint);
              }

              final jumpHeight = pageOffset == 1
                  ? page.size.height
                  : pageNew.size.height;

              adjustedOffset = Offset(
                adjustedOffset.dx,
                adjustedOffset.dy -
                    pageOffset * (jumpHeight + Editor.gapBetweenPages),
              );
              preview = SelectionTransformPreview.fromSelection(
                select.selectResult,
              );
              _selectionPreview = preview;
              _detachSelectionStrokesFromPage(select.selectResult);
            }

            adjustedOffset = _snapSelectionOffset(
              offset: adjustedOffset,
              selection: select.selectResult,
              page: coreInfo.pages[select.selectResult.pageIndex],
              boundsOverride: preview.visualBounds,
            );
            _selectionPreview = preview.copyWith(
              translation: preview.translation + adjustedOffset,
            );
          }
        }
      } else {
        select.onDragUpdate(position);

        setState(() {});
      }
      if (select.doneSelecting) {
        setState(() {});
      }
      _bumpInteractionRepaint();
    } else if (currentTool is LaserPointer) {
      (currentTool as LaserPointer).onDragUpdate(position);
      page.redrawStrokes();
      _bumpInteractionRepaint();
    }
    previousPosition = position;
    moveOffset += adjustedOffset;

    bool hadSelection =
        Select.currentSelect.doneSelecting &&
        !Select.currentSelect.selectResult.isEmpty;
    if (currentTool is Select || hadSelection) {
      setState(() {});
    }
  }

  bool shouldInjectRawPointerSamplesForDraw() {
    return dragPageIndex != null &&
        currentTool is Pen &&
        Pen.currentStroke != null;
  }

  void onRawPointerMoveForDraw(PointerMoveEvent event) {
    if (_ignoreDragForMenu) return;
    if (dragPageIndex == null ||
        currentTool is! Pen ||
        Pen.currentStroke == null) {
      return;
    }
    if (_imageCropState != null && _activeCropHandle != null) return;

    final stroke = Pen.currentStroke!;
    if (stroke.points.isEmpty) return;

    final page = coreInfo.pages[dragPageIndex!];
    var position = _safelyGetLocalPosition(dragPageIndex!, event.position);
    if (!coreInfo.isInfinite) {
      position = Offset(
        position.dx.clamp(0.0, page.size.width),
        position.dy.clamp(0.0, page.size.height),
      );
    }

    final last = stroke.points.last;
    final dx = position.dx - last.x;
    final dy = position.dy - last.y;
    final minDistSq = DisplayInkFeel.instance.isLowRefresh
        ? _rawDrawSampleMinDistSqLowRefresh
        : _rawDrawSampleMinDistSq;
    if (dx * dx + dy * dy < minDistSq) return;

    final timestamp = event.timeStamp;
    _recordLivePenSample(page, position, timestamp, rawPointerSample: true);
    previousPosition = position;
  }

  double _normalizeAngle360(double angle) {
    final normalized = angle % 360.0;
    return normalized < 0 ? normalized + 360.0 : normalized;
  }

  double _snapRotationAngle(double angleDeg) {
    final normalized = _normalizeAngle360(angleDeg);
    const engageThreshold = 4.0;
    const releaseThreshold = 7.0;

    if (_activeRotationSnapAnchor != null) {
      final anchor = _activeRotationSnapAnchor!;
      final keepDistance = math.min(
        (normalized - anchor).abs(),
        (normalized - (anchor + 360)).abs(),
      );
      if (keepDistance <= releaseThreshold) {
        return anchor;
      }
      _activeRotationSnapAnchor = null;
    }

    double best = normalized;
    double bestDistance = double.infinity;
    for (final anchor in _rotationSnapAngles) {
      final d1 = (normalized - anchor).abs();
      final d2 = (normalized - (anchor + 360)).abs();
      final d = math.min(d1, d2);
      if (d < bestDistance) {
        bestDistance = d;
        best = anchor;
      }
    }
    if (bestDistance <= engageThreshold) {
      _activeRotationSnapAnchor = best;
      return best;
    }
    return normalized;
  }

  Offset _animationPlayButtonCenter(EditorImage image) {
    final rect = image.dstRect;
    final local = Offset(
      rect.right - _animationPlayButtonInset - _animationPlayButtonRadius,
      rect.top + _animationPlayButtonInset + _animationPlayButtonRadius,
    );
    if (image.rotationDeg == 0.0) return local;

    final center = rect.center;
    final rad = image.rotationDeg * math.pi / 180.0;
    final dx = local.dx - center.dx;
    final dy = local.dy - center.dy;
    return Offset(
      center.dx + dx * math.cos(rad) - dy * math.sin(rad),
      center.dy + dx * math.sin(rad) + dy * math.cos(rad),
    );
  }

  bool _isTapOnAnimationPlayButton({
    required EditorImage image,
    required Offset position,
  }) {
    final metadata = _plotMetadataFromImage(image);
    if (metadata == null || !metadata.hasAnimation) return false;
    final center = _animationPlayButtonCenter(image);
    return (position - center).distance <= _animationPlayButtonRadius + 6.0;
  }

  Offset _snapSelectionOffset({
    required Offset offset,
    required SelectResult selection,
    required EditorPage page,
    Rect? boundsOverride,
  }) {
    final bounds =
        boundsOverride ?? selection.displayBounds ?? selection.getBounds();
    if (bounds.isEmpty) {
      selection.clearAlignmentGuides();
      return offset;
    }

    final movedBounds = bounds.shift(offset);
    final pageCenter = Offset(page.size.width / 2, page.size.height / 2);
    final threshold = math.max(
      4.0,
      10.0 / _transformationController.value.getMaxScaleOnAxis(),
    );

    double dxAdjust = 0.0;
    double dyAdjust = 0.0;
    final guides = <SelectionGuideLine>[];

    final centerDx = movedBounds.center.dx;
    if ((centerDx - pageCenter.dx).abs() <= threshold) {
      dxAdjust = pageCenter.dx - centerDx;
      if (offset.dx != 0) {
        final maxCompensation = offset.dx.abs() * 0.8;
        dxAdjust = dxAdjust.clamp(-maxCompensation, maxCompensation);
      }
      guides.add(
        SelectionGuideLine(
          start: Offset(pageCenter.dx, 0),
          end: Offset(pageCenter.dx, page.size.height),
        ),
      );
    }

    final centerDy = movedBounds.center.dy;
    if ((centerDy - pageCenter.dy).abs() <= threshold) {
      dyAdjust = pageCenter.dy - centerDy;
      if (offset.dy != 0) {
        final maxCompensation = offset.dy.abs() * 0.8;
        dyAdjust = dyAdjust.clamp(-maxCompensation, maxCompensation);
      }
      guides.add(
        SelectionGuideLine(
          start: Offset(0, pageCenter.dy),
          end: Offset(page.size.width, pageCenter.dy),
        ),
      );
    }

    selection.alignmentGuides = guides;
    return offset.translate(dxAdjust, dyAdjust);
  }

  void onDrawEnd(ScaleEndDetails details) {
    _canvasGestureActive = false;
    void resetDrawSessionState() {
      dragPageIndex = null;
      _eraserAreaDragActive = false;
      eraserPosition = null;
      _eraserPositionRepaint.value = null;
      Eraser.isDragging = false;
    }

    _selectionLongPressTimer?.cancel();
    _selectionLongPressTimer = null;
    _penHoldRecognitionTimer?.cancel();
    _ignoreDragForMenu = false;
    Select.currentSelect.selectResult.clearAlignmentGuides();
    _activeRotationSnapAnchor = null;

    if (dragPageIndex == null) {
      resetDrawSessionState();
      return;
    }

    if (_activeCropHandle != null) {
      setState(() {
        _activeCropHandle = null;
      });
      resetDrawSessionState();
      return;
    }

    final page = coreInfo.pages[dragPageIndex!];
    bool shouldSave = true;
    bool shouldFitInfiniteCanvas = false;
    setState(() {
      if (currentTool is Pen) {
        var newStroke = (currentTool as Pen).onDragEnd();
        if (newStroke == null) return;
        if (newStroke.isEmpty) return;

        final delayMs = stows.shapeRecognitionDelay.value;
        final holdSatisfiedByElapsedTime =
            delayMs >= 0 &&
            _lastPenSignificantMoveAt != null &&
            DateTime.now()
                    .difference(_lastPenSignificantMoveAt!)
                    .inMilliseconds >=
                delayMs;
        if ((_penHoldSatisfied || holdSatisfiedByElapsedTime) &&
            newStroke.length >= 2) {
          final detected = _penHoldDetectedShape ?? newStroke.detectShape();
          final minScore = detected?.name == DefaultUnistrokeNames.infinity
              ? 0.45
              : (detected?.name == DefaultUnistrokeNames.line ? 0.5 : 0.55);
          if (detected != null && detected.score >= minScore) {
            final bool isHighlighter = currentTool is Highlighter;
            final bool isLineOrArrow =
                detected.name == DefaultUnistrokeNames.line ||
                detected.name == DefaultUnistrokeNames.arrow;
            if (isHighlighter ? isLineOrArrow : true) {
              newStroke = convertStrokeToShapeStroke(newStroke, detected);
            }
          }
        }

        _penHoldSatisfied = false;
        _penHoldDetectedShape = null;
        clearDetectedShapePreviewCache();

        createPage(newStroke.pageIndex);
        page.insertStroke(newStroke);

        if (dragPageIndex == coreInfo.pages.length - 1) {
          createPage(coreInfo.pages.length);
        }

        page.strokeSpatialIndex?.insert(newStroke);

        final pen = currentTool as Pen;
        switch (pen.toolId) {
          case ToolId.fountainPen:
            stows.lastFountainPenOptions.value = pen.options;
            stows.lastFountainPenColor.value = pen.color.toARGB32();
            break;
          case ToolId.ballpointPen:
            stows.lastBallpointPenOptions.value = pen.options;
            stows.lastBallpointPenColor.value = pen.color.toARGB32();
            break;
          case ToolId.calligraphyPen:
            stows.lastCalligraphyPenOptions.value = pen.options;
            stows.lastCalligraphyPenColor.value = pen.color.toARGB32();
            break;
          case ToolId.highlighter:
            stows.lastHighlighterOptions.value = pen.options;
            stows.lastHighlighterColor.value = pen.color.toARGB32();
            break;
          case ToolId.advancedPen:
            stows.lastAdvancedPenOptions.value = pen.options;
            stows.lastAdvancedPenColor.value = pen.color.toARGB32();
            break;
          case ToolId.advancedPencil:
            stows.lastAdvancedPencilOptions.value = pen.options;
            stows.lastAdvancedPencilColor.value = pen.color.toARGB32();
            stows.lastAdvancedPencilPaint.value = Map<String, dynamic>.from(
              pen.paint.toJson(embedBytes: false),
            );
            break;
          case ToolId.experimentalPen:
            stows.lastAdvancedPenOptions.value = pen.options;
            stows.lastAdvancedPenColor.value = pen.color.toARGB32();
            break;
          default:
            break;
        }

        history.recordChange(
          EditorHistoryItem(
            type: .draw,
            pageIndex: dragPageIndex!,
            strokes: [newStroke],
            images: [],
          ),
        );
        _appendRecoveryStroke(newStroke);

        if (stows.enableMathSolver.value) {
          _trySolveMath(newStroke, page).then((solved) {
            if (solved && mounted) {
              setState(() {});
              autosaveAfterDelay();
            }
          });
        }
        shouldFitInfiniteCanvas = true;
      } else if (currentTool is ShapeTool) {
        final newStroke = (currentTool as ShapeTool).onDragEnd(
          page,
          dragPageIndex!,
        );

        if (newStroke == null) {
          page.redrawStrokes();
          setState(() {});
          return;
        }

        if (!newStroke.isEmpty) {
          page.insertStroke(newStroke);

          if (dragPageIndex == coreInfo.pages.length - 1) {
            createPage(coreInfo.pages.length);
          }

          page.strokeSpatialIndex?.insert(newStroke);

          history.recordChange(
            EditorHistoryItem(
              type: .draw,
              pageIndex: dragPageIndex!,
              strokes: [newStroke],
              images: [],
            ),
          );

          currentTool = Select.currentSelect;
          _autoSwitchBackToShapeTool = true;
          Select.currentSelect.doneSelecting = true;
          Select.currentSelect.selectResult = SelectResult(
            pageIndex: dragPageIndex!,
            strokes: [newStroke],
            images: [],
            path: Path(),
            pageIndexStart: dragPageIndex!,
          );

          Select.currentSelect.selectResult.displayBounds = null;

          shouldFitInfiniteCanvas = true;
        }
      } else if (currentTool is Eraser) {
        final eraser = currentTool as Eraser;
        if (eraser.mode == EraserMode.area) {
          final flushPos = eraserPosition ?? _areaEraserWorkPos ?? Offset.zero;
          _syncFlushAreaEraserWork(page, eraser, flushPos);
        }
        _abortAreaEraserBackgroundWork();
        if (mounted) setState(() {});

        final (erased, added, toDispose) = eraser.onDragEnd();
        eraserPosition = null;
        _eraserPositionRepaint.value = null;
        _eraserDeltaRemoved = null;
        _eraserDeltaAdded = null;
        setState(() {});
        if (eraser.mode == EraserMode.area) {
          page.buildSpatialIndex(activeLayerOnly: true);
          page.redrawStrokes();
          removeExcessPages();
        }
        if (tmpTool != null &&
            (stylusButtonPressed || stows.disableEraserAfterUse.value)) {
          stylusButtonPressed = false;
          currentTool = tmpTool!;
          tmpTool = null;
        }
        if (erased.isEmpty && added.isEmpty) {
          for (final stroke in toDispose) {
            stroke.dispose();
          }
          return;
        }
        if (erased.isNotEmpty && added.isNotEmpty) {
          history.recordChange(
            EditorHistoryItem(
              type: .areaErase,
              pageIndex: dragPageIndex!,
              strokes: erased,
              images: [],
              strokesAdded: added,
            ),
          );
        } else if (erased.isNotEmpty) {
          history.recordChange(
            EditorHistoryItem(
              type: .erase,
              pageIndex: dragPageIndex!,
              strokes: erased,
              images: [],
            ),
          );
        } else if (added.isNotEmpty) {
          history.recordChange(
            EditorHistoryItem(
              type: .draw,
              pageIndex: dragPageIndex!,
              strokes: added,
              images: [],
            ),
          );
        }
        final keepForHistory = <Stroke>{...erased, ...added};
        for (final stroke in toDispose) {
          if (keepForHistory.contains(stroke)) continue;
          stroke.dispose();
        }
      } else if (currentTool is Select) {
        final select = currentTool as Select;
        if (select.doneSelecting) {
          final committedPreview = _selectionPreview;
          if (_imageCropState != null &&
              select.selectResult.images.length == 1 &&
              identical(
                select.selectResult.images.first,
                _imageCropState!.image,
              )) {
            return;
          }
          if (_selectionGestureBeganOnModeChip) {
            final viewportScale = _quantizedCanvasScale;
            final tol = SelectionHandlesLayout.chipTapMovementTolerance(
              viewportScale,
            );
            final started = _selectionChipWallClockStart;
            final durationOk =
                started == null ||
                DateTime.now().difference(started) <=
                    SelectionHandlesLayout.chipTapMaxDuration;
            if (_selectionChipGestureMaxMove <= tol && durationOk) {
              _selectionHandlesInteractionMode =
                  _selectionHandlesInteractionMode ==
                      SelectionHandlesInteractionMode.resize
                  ? SelectionHandlesInteractionMode.rotate
                  : SelectionHandlesInteractionMode.resize;
              HapticFeedback.selectionClick();
            }
            _selectionGestureBeganOnModeChip = false;
            _selectionChipWallClockStart = null;
            _clearSelectionPreview();
          } else if (_isDraggingVertex &&
              _draggedTriangle != null &&
              _draggedVertexIndex != null) {
            history.recordChange(
              EditorHistoryItem(
                type: .move,
                pageIndex: dragPageIndex!,
                strokes: [_draggedTriangle!],
                images: [],
                offset: .zero,
              ),
            );

            _isDraggingVertex = false;
            _draggedVertexIndex = null;
            _draggedTriangle = null;
            shouldFitInfiniteCanvas = true;
          } else if (_isScaling) {
            final centroid =
                committedPreview?.pivot ??
                select.selectResult.displayBounds?.center ??
                select.selectResult.getCentroid();
            _commitSelectionPreview(select.selectResult);
            _isScaling = false;
            _scaleHandle = null;
            _initialScaleRadius = 0.0;
            shouldFitInfiniteCanvas = true;

            history.recordChange(
              EditorHistoryItem(
                type: .move,
                pageIndex: dragPageIndex!,
                strokes: List.from(select.selectResult.strokes),
                images: List.from(select.selectResult.images),
                scale: totalScale,
                centroid: centroid,
              ),
            );
          } else if (_isRotating) {
            final centroid =
                committedPreview?.pivot ?? select.selectResult.getCentroid();
            _commitSelectionPreview(select.selectResult);

            history.recordChange(
              EditorHistoryItem(
                type: .move,
                pageIndex: dragPageIndex!,
                strokes: List.from(select.selectResult.strokes),
                images: List.from(select.selectResult.images),
                rotation: totalRotation,
                centroid: centroid,
              ),
            );

            _isRotating = false;
            _rotationStartPosition = null;
            _rotationStartAngle = 0.0;
            shouldFitInfiniteCanvas = true;
          } else if (moveOffset != .zero) {
            _commitSelectionPreview(select.selectResult);
            history.recordChange(
              EditorHistoryItem(
                type: .move,
                pageIndexStart: select.selectResult.pageIndexStart,
                pageIndex: select.selectResult.pageIndex,
                strokes: List.from(select.selectResult.strokes),
                images: List.from(select.selectResult.images),
                offset: Rect.fromLTRB(
                  moveOffset.dx,
                  moveOffset.dy,
                  moveOffset.dx,
                  moveOffset.dy,
                ),
              ),
            );
            select.selectResult.pageIndexStart = select.selectResult.pageIndex;
            shouldFitInfiniteCanvas = true;
          } else {
            _clearSelectionPreview();
          }
          _flushSelectionPageUpdates();
        } else {
          shouldSave = false;
          select.onDragEnd(page.strokes, page.images);

          if (select.selectResult.isEmpty) {
            Select.currentSelect.unselect();
            _selectionHandlesInteractionMode =
                SelectionHandlesInteractionMode.resize;
            if (_autoSwitchBackToShapeTool) {
              _autoSwitchBackToShapeTool = false;
              currentTool = ShapeTool.currentShapeTool;
              setState(() {});
            }
          } else {
            select.selectResult.displayBounds = select.selectResult.getBounds();
          }
        }
      } else if (currentTool is LaserPointer) {
        shouldSave = false;
        final newStroke = (currentTool as LaserPointer).onDragEnd(
          page.redrawStrokes,
          (Stroke stroke) {
            page.laserStrokes.remove(stroke);
          },
        );
        if (newStroke != null) page.laserStrokes.add(newStroke);
      }
    });

    if (coreInfo.isInfinite) {
      coreInfo.enforceSinglePage();
      if (shouldFitInfiniteCanvas && coreInfo.pages.isNotEmpty) {
        _fitInfiniteCanvasToContent(coreInfo.pages.first);
      }
      if (mounted) setState(() {});
    }

    _keepAliveController.forward(from: 0);

    _bumpInteractionRepaint();
    if (shouldSave) {
      if (dragPageIndex != null) {
        _pageRasterCache.invalidateInk(dragPageIndex!);
        _maintainPageRasterBand(dragPageIndex!, dragPageIndex!, forceSchedule: true);
      }
      autosaveAfterDelay();
    }
    resetDrawSessionState();
  }

  void _finishActivePenStrokeFromPointerEnd(PointerEvent event) {
    if (Pen.currentStroke == null || dragPageIndex == null) return;
    onDrawEnd(
      ScaleEndDetails(
        velocity: event is PointerUpEvent
            ? Velocity(pixelsPerSecond: event.delta)
            : Velocity.zero,
      ),
    );
  }

  Future<bool> _trySolveMath(Stroke lastStroke, EditorPage page) async {
    if (coreInfo.readOnly) return false;

    if (lastStroke.points.isEmpty) return false;

    final lastCenterY =
        lastStroke.points.map((p) => p.y).reduce((a, b) => a + b) /
        lastStroke.points.length;
    final lineHeight = 100.0;

    final candidateStrokes = page.strokes.where((s) {
      if (s.points.isEmpty) return false;
      final centerY =
          s.points.map((p) => p.y).reduce((a, b) => a + b) / s.points.length;
      return (centerY - lastCenterY).abs() < lineHeight;
    }).toList();

    candidateStrokes.sort((a, b) {
      if (a.points.isEmpty || b.points.isEmpty) return 0;
      final aLeft = a.points.map((p) => p.x).reduce((x, y) => x < y ? x : y);
      final bLeft = b.points.map((p) => p.x).reduce((x, y) => x < y ? x : y);
      return aLeft.compareTo(bLeft);
    });

    if (candidateStrokes.isEmpty) return false;

    final resultStrokes = await _mathSolver.processStrokes(
      candidateStrokes,
      page,
      dragPageIndex!,
    );

    if (resultStrokes != null && resultStrokes.isNotEmpty) {
      page.strokes.addAll(resultStrokes);

      if (page.strokeSpatialIndex != null) {
        for (final s in resultStrokes) {
          page.strokeSpatialIndex!.insert(s);
        }
      }

      history.recordChange(
        EditorHistoryItem(
          type: .draw,
          pageIndex: dragPageIndex!,
          strokes: resultStrokes,
          images: [],
        ),
      );

      if (coreInfo.isInfinite) {
        _fitInfiniteCanvasToContent(page);
      }

      return true;
    }

    return false;
  }

  bool moveStrokeToPage(Stroke stroke, int pageIndexOrig, int pageIndexDest) {
    if (coreInfo.isInfinite) return false;

    if (pageIndexOrig == pageIndexDest ||
        pageIndexOrig == -1 ||
        pageIndexDest == -1) {
      return false;
    }
    if (pageIndexOrig < 0 || pageIndexOrig > coreInfo.pages.length - 1) {
      return false;
    }
    if (pageIndexDest < 0 || pageIndexDest > coreInfo.pages.length - 1) {
      return false;
    }
    final pageOrig = coreInfo.pages[pageIndexOrig];
    final pageDest = coreInfo.pages[pageIndexDest];

    pageOrig.strokes.remove(stroke);

    pageDest.strokes.add(stroke);
    stroke.pageIndex = pageIndexDest;
    return true;
  }

  bool moveImageToPage(
    EditorImage image,
    int pageIndexOrig,
    int pageIndexDest,
  ) {
    if (coreInfo.isInfinite) return false;

    if (pageIndexOrig == pageIndexDest ||
        pageIndexOrig == -1 ||
        pageIndexDest == -1) {
      return false;
    }
    if (pageIndexOrig < 0 || pageIndexOrig > coreInfo.pages.length - 1) {
      return false;
    }
    if (pageIndexDest < 0 || pageIndexDest > coreInfo.pages.length - 1) {
      return false;
    }
    final pageOrig = coreInfo.pages[pageIndexOrig];
    final pageDest = coreInfo.pages[pageIndexDest];

    pageOrig.images.remove(image);

    pageDest.images.add(image);
    image.pageIndex = pageIndexDest;
    return true;
  }

  void _markSelectionPageDirty(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= coreInfo.pages.length) return;
    _selectionDirtyPageIndices.add(pageIndex);
  }

  Rect _selectionRectForInteractions(SelectResult selection) {
    final preview =
        _selectionPreview ?? SelectionTransformPreview.fromSelection(selection);
    return preview.visualBounds;
  }

  double _selectionRotationDegForInteractions(SelectResult selection) {
    final preview =
        _selectionPreview ?? SelectionTransformPreview.fromSelection(selection);
    return preview.effectiveRotationDeg;
  }

  bool _hitSelectionModeChip(
    Offset pagePosition,
    SelectResult selection,
    double viewportScale,
  ) {
    final rect = _selectionRectForInteractions(selection);
    final rot = _selectionRotationDegForInteractions(selection);
    final center = SelectionHandlesLayout.chipCenter(rect, rot, viewportScale);
    return (pagePosition - center).distance <=
        SelectionHandlesLayout.chipHitRadius(rect, viewportScale);
  }

  ShapeStroke? _singleVertexEditableShape(SelectResult selection) {
    if (selection.images.isNotEmpty) return null;
    if (selection.strokes.length != 1) return null;
    final stroke = selection.strokes.first;
    if (stroke is! ShapeStroke) return null;
    if (!stroke.isVertexEditable) return null;
    return stroke;
  }

  int? _hitSelectionVertexIndex(
    Offset pagePosition,
    SelectResult selection,
    double viewportScale,
  ) {
    final shape = _singleVertexEditableShape(selection);
    if (shape == null) return null;
    final stylus =
        currentPointerKind == PointerDeviceKind.stylus ||
        currentPointerKind == PointerDeviceKind.invertedStylus;
    return ShapeControlPointsOverlay.hitTest(
      shape: shape,
      pagePosition: pagePosition,
      viewportScale: viewportScale,
      stylus: stylus,
    );
  }

  /// Corner index matching [SelectionHandlesOverlay] handle order:
  /// 0 TL, 1 TR, 2 BR, 3 BL.
  int? _hitSelectionCornerIndex(
    Offset pagePosition,
    SelectResult selection,
    double viewportScale,
  ) {
    final stylus =
        currentPointerKind == PointerDeviceKind.stylus ||
        currentPointerKind == PointerDeviceKind.invertedStylus;
    final rect = _selectionRectForInteractions(selection);
    final rotationRad =
        _selectionRotationDegForInteractions(selection) * math.pi / 180.0;
    final centroid = rect.center;
    final hitR = SelectionHandlesLayout.cornerHitRadius(
      rect,
      viewportScale,
      stylus: stylus,
    );
    final corners = [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ];
    for (var i = 0; i < corners.length; i++) {
      final c = corners[i];
      final dx = c.dx - centroid.dx;
      final dy = c.dy - centroid.dy;
      final rotatedC = Offset(
        centroid.dx + dx * math.cos(rotationRad) - dy * math.sin(rotationRad),
        centroid.dy + dx * math.sin(rotationRad) + dy * math.cos(rotationRad),
      );
      if ((pagePosition - rotatedC).distance <= hitR) return i;
    }
    return null;
  }

  SelectionTransformPreview? _selectionPreviewForPage(int pageIndex) {
    final preview = _selectionPreview;
    if (preview == null || currentTool is! Select) return null;
    final select = currentTool as Select;
    if (!select.doneSelecting || select.selectResult.pageIndex != pageIndex) {
      return null;
    }
    return preview;
  }

  void _beginSelectionPreview(SelectResult selection) {
    _selectionPreview = SelectionTransformPreview.fromSelection(selection);
    totalRotation = 0.0;
    totalScale = 1.0;
    _detachSelectionStrokesFromPage(selection);
  }

  void _clearSelectionPreview() {
    final select = currentTool is Select ? currentTool as Select : null;
    if (_selectionStrokesDetachedFromPage && select != null) {
      _reattachSelectionStrokesToPage(select.selectResult);
    }
    _selectionPreview = null;
  }

  void _detachSelectionStrokesFromPage(SelectResult selection) {
    if (_selectionStrokesDetachedFromPage) return;
    if (selection.strokes.isEmpty) return;
    final pageIndex = selection.pageIndex;
    if (pageIndex < 0 || pageIndex >= coreInfo.pages.length) return;
    final page = coreInfo.pages[pageIndex];
    for (final stroke in selection.strokes) {
      page.strokeSpatialIndex?.remove(stroke);
      page.strokes.remove(stroke);
    }
    _selectionStrokesDetachedFromPage = true;
    _markSelectionPageDirty(pageIndex);
    page.redrawStrokes();
  }

  void _reattachSelectionStrokesToPage(SelectResult selection) {
    if (!_selectionStrokesDetachedFromPage) return;
    final pageIndex = selection.pageIndex;
    if (pageIndex < 0 || pageIndex >= coreInfo.pages.length) {
      _selectionStrokesDetachedFromPage = false;
      return;
    }
    final page = coreInfo.pages[pageIndex];
    for (final stroke in selection.strokes) {
      if (!page.strokes.contains(stroke)) {
        page.strokes.add(stroke);
        page.strokeSpatialIndex?.insert(stroke);
      }
    }
    _selectionStrokesDetachedFromPage = false;
    _markSelectionPageDirty(pageIndex);
    page.redrawStrokes();
  }

  void _commitSelectionPreview(SelectResult selection) {
    final preview = _selectionPreview;
    if (preview == null || preview.isIdentity) {
      if (_selectionStrokesDetachedFromPage) {
        _reattachSelectionStrokesToPage(selection);
      }
      _selectionPreview = null;
      return;
    }

    final pageIndex = selection.pageIndex;
    if (pageIndex < 0 || pageIndex >= coreInfo.pages.length) {
      _selectionPreview = null;
      _selectionStrokesDetachedFromPage = false;
      return;
    }

    final page = coreInfo.pages[pageIndex];
    final pivot = preview.pivot;
    final scale = preview.scale;
    final rotationRad = preview.rotationDeltaDeg * math.pi / 180.0;
    final translation = preview.translation;

    _markSelectionPageDirty(pageIndex);

    if (scale != 1.0) {
      for (int i = 0; i < selection.strokes.length; i++) {
        final stroke = selection.strokes[i];
        if (stroke is ShapeStroke) {
          final scaled = stroke.scaled(scale, pivot);
          final idx = page.strokes.indexOf(stroke);
          if (idx >= 0) {
            page.strokeSpatialIndex?.remove(stroke);
            page.strokes[idx] = scaled;
            page.strokeSpatialIndex?.insert(scaled);
          }
          selection.strokes[i] = scaled;
        } else {
          stroke.scale(scale, pivot);
        }
      }
      for (final image in selection.images) {
        image.scale(scale, pivot);
      }
    }

    if (rotationRad != 0.0) {
      for (final stroke in selection.strokes) {
        stroke.rotate(rotationRad, pivot);
      }
      for (final image in selection.images) {
        image.rotate(rotationRad, pivot);
      }
      selection.rotationDeg = preview.effectiveRotationDeg;
    }

    if (translation != Offset.zero) {
      for (final stroke in selection.strokes) {
        stroke.shift(translation);
      }
      for (final image in selection.images) {
        image.dstRect = image.dstRect.shift(translation);
      }
    }

    if (!selection.path.getBounds().isEmpty) {
      selection.path = selection.path.transform(
        preview.transformMatrix.storage,
      );
    }
    // Recompute from committed geometry so min-size clamps stay inside the box.
    selection.displayBounds = null;
    selection.displayBounds = selection.getBounds();
    _selectionPreview = null;
    // Strokes were removed at drag start; put the transformed ones back.
    _reattachSelectionStrokesToPage(selection);
  }

  void _flushSelectionPageUpdates() {
    if (_selectionDirtyPageIndices.isEmpty) return;
    final dirtyPages = _selectionDirtyPageIndices.toList()..sort();
    _selectionDirtyPageIndices.clear();
    for (final pageIndex in dirtyPages) {
      final page = coreInfo.pages[pageIndex];
      page.buildSpatialIndex();
      page.redrawStrokes();
    }
  }

  void selectionOffsetPage(int pageOffset) {
    if (coreInfo.isInfinite) return;

    final select = currentTool as Select;

    final int oldPage = select.selectResult.pageIndex;
    final int newPage = select.selectResult.pageIndex + pageOffset;
    if (oldPage < 0 || oldPage > coreInfo.pages.length - 1) {
      return;
    }
    if (newPage < 0 || newPage > coreInfo.pages.length - 1) {
      return;
    }
    final strokes = select.selectResult.strokes;
    final images = select.selectResult.images;

    setState(() {
      for (final stroke in strokes) {
        moveStrokeToPage(stroke, oldPage, newPage);
      }
      for (final image in images) {
        moveImageToPage(image, oldPage, newPage);
      }

      select.selectResult.pageIndex += pageOffset;
    });
    _markSelectionPageDirty(oldPage);
    _markSelectionPageDirty(newPage);
    _flushSelectionPageUpdates();
  }

  void onInteractionEnd(ScaleEndDetails details) {
    _canvasGestureActive = false;
    _lastSeenPointerCountTimer?.cancel();
    _lastSeenPointerCountTimer = Timer(const Duration(milliseconds: 10), () {
      lastSeenPointerCount = 0;
    });
  }

  double get _quantizedCanvasScale {
    final scale = _transformationController.value.approxScale;
    return (scale * 20).roundToDouble() / 20;
  }

  void updatePointerData(
    PointerDeviceKind kind,
    double? pressure,
    Duration timestamp,
  ) {
    currentPointerKind = kind;
    currentPressure = pressure;
    currentTimestamp = timestamp;
  }

  void onHovering() {
    isHovering = true;
  }

  void onHoveringEnd() {
    isHovering = false;
  }

  void onStylusButtonChanged(bool buttonPressed) {
    stylusButtonPressed = buttonPressed;

    if (!stows.eraserOnStylusButtonPressAndRelease.value) return;

    if (buttonPressed) {
      _finishActivePenStrokeFromPointerEnd(
        PointerCancelEvent(timeStamp: currentTimestamp),
      );
      if (currentTool is Eraser) return;
      tmpTool = currentTool;
      currentTool = Eraser.currentEraser;
      setState(() {});
    } else {
      if (tmpTool != null && currentTool is Eraser) {
        if (dragPageIndex != null) {
          // Defer switching back to Pen until onDrawEnd
          return;
        }
        currentTool = tmpTool!;
        tmpTool = null;
        setState(() {});
      }
    }
  }

  void onMoveImage(EditorImage image, Rect offset) {
    if (coreInfo.isInfinite &&
        image.pageIndex >= 0 &&
        image.pageIndex < coreInfo.pages.length) {
      _fitInfiniteCanvasToContent(coreInfo.pages[image.pageIndex]);
    }
    history.recordChange(
      EditorHistoryItem(
        type: .move,
        pageIndex: image.pageIndex,
        strokes: [],
        images: [image],
        offset: offset,
      ),
    );

    _pageRasterCache.invalidateInk(image.pageIndex);
    setState(() {});
    autosaveAfterDelay();
  }

  void onDeleteImage(EditorImage image) {
    history.recordChange(
      EditorHistoryItem(
        type: .erase,
        pageIndex: image.pageIndex,
        strokes: [],
        images: [image],
      ),
    );
    setState(() {
      coreInfo.pages[image.pageIndex].removeImageFromAnyLayer(image);
    });
    if (coreInfo.isInfinite &&
        image.pageIndex >= 0 &&
        image.pageIndex < coreInfo.pages.length) {
      _trimInfiniteCanvasWhitespace(coreInfo.pages[image.pageIndex]);
    }
    autosaveAfterDelay();
  }

  void listenToQuillChanges(QuillStruct quill, int pageIndex) {
    quill.changeSubscription?.cancel();
    quill.changeSubscription = quill.controller.changes.listen((event) {
      final undoRedoButtonsNeedUpdating = !history.canUndo || history.canRedo;
      _addQuillChangeToHistory(
        quill: quill,
        pageIndex: pageIndex,
        event: event,
      );
      createPage(pageIndex);
      if (pageIndex >= 0 && pageIndex < coreInfo.pages.length) {
        coreInfo.pages[pageIndex].markSaveBinaryDirty();
      }
      if (coreInfo.isInfinite &&
          pageIndex >= 0 &&
          pageIndex < coreInfo.pages.length) {
        _fitInfiniteCanvasToContent(coreInfo.pages[pageIndex]);
      }
      if (undoRedoButtonsNeedUpdating) {
        setState(() {});
      }
      autosaveAfterDelay();
    });
    quill.focusNode.addListener(_onQuillFocusChange);
  }

  void _onQuillFocusChange() {
    for (final page in coreInfo.pages) {
      if (!page.quill.focusNode.hasFocus) continue;
      quillFocus.value = page.quill;
    }
  }

  void _addQuillChangeToHistory({
    required QuillStruct quill,
    required int pageIndex,
    required flutter_quill.DocChange event,
  }) {
    if (_isUndoRedoInProgress) return;
    if (currentTool != Tool.textEditing) return;

    final eventWasUndo = quill.controller.hasRedo;
    if (eventWasUndo) return;

    if (history.canUndo && !history.canRedo) {
      final lastChange = history.peekUndo();
      if (lastChange.type == .quillChange &&
          lastChange.pageIndex == pageIndex &&
          lastChange.quillChange!.before == event.before) {
        history.undo();
      }
    }

    history.recordChange(
      EditorHistoryItem(
        type: .quillChange,
        pageIndex: pageIndex,
        strokes: const [],
        images: const [],
        quillChange: event,
      ),
    );
  }

  void autosaveAfterDelay() {
    _lastUserActivityForAutosave = DateTime.now();
    late final void Function() callback;

    void startTimer([int? delayMs]) {
      _delayedSaveTimer?.cancel();
      final configuredDelay = stows.autosaveDelay.value;
      final ms = delayMs ?? (configuredDelay < 0 ? 300 : configuredDelay);
      _delayedSaveTimer = Timer(Duration(milliseconds: ms), callback);
    }

    callback = () {
      if (Pen.currentStroke != null) {
        startTimer();
        return;
      }

      final last = _lastUserActivityForAutosave;
      if (last != null) {
        final elapsed = DateTime.now().difference(last).inMilliseconds;
        final idleMs = _autosaveIdleMs;
        if (elapsed < idleMs) {
          startTimer(idleMs - elapsed);
          return;
        }
      }
      saveToFile(updateThumbnail: false);
    };

    if (savingState.value == SavingState.saving) {
      _saveFollowUpRequested = true;
      return;
    }

    if (savingState.value == SavingState.saved) {
      _lastSaveTime = DateTime.now();
    }

    savingState.value = SavingState.waitingToSave;
    startTimer();
  }

  void cancelAutosaveAndMarkSaved() {
    _delayedSaveTimer?.cancel();
    _saveFollowUpRequested = false;
    savingState.value = SavingState.saved;
  }

  Future<void> saveToFile({
    bool force = false,
    bool updateThumbnail = true,
    bool awaitVaultCommit = false,
  }) async {
    if (_isDeleted) return;

    // CRITICAL: Check if disposed before proceeding
    if (_isDisposed) {
      log.warning('saveToFile() called after dispose() - aborting');
      return;
    }

    if (coreInfo.readOnly) return;

    ThemeData? themeToUse = _cachedTheme;
    MediaQueryData? mediaQueryToUse = _cachedMediaQuery;
    bool needsThumbnail = false;
    Uint8List? preCapturedThumbnailBytes;
    final String thumbnailPath = '${coreInfo.filePath}${Editor.extension}.p';

    final currentFirstPageHash = coreInfo.calculateFirstPageHash();

    final allowThumbnail =
        !coreInfo.isInfinite &&
        (updateThumbnail || (!force && stows.thumbnailOnAutosave.value));
    if (coreInfo.pages.isNotEmpty && allowThumbnail) {
      try {
        final thumbnailFile = File(thumbnailPath);
        bool thumbnailExists = false;
        try {
          thumbnailExists = thumbnailFile.existsSync();
        } catch (_) {}

        if (currentFirstPageHash != _lastWrittenThumbnailHash ||
            !thumbnailExists) {
          final isCanvasMounted =
              coreInfo.pages[0].innerCanvasKey.currentState != null;

          if (themeToUse != null &&
              mediaQueryToUse != null &&
              isCanvasMounted) {
            needsThumbnail = true;
          } else if (!isCanvasMounted) {
            log.fine('Skipping thumbnail: Canvas not mounted yet.');
          }
        }
      } catch (e) {
        log.warning('Thumbnail logic skipped: $e');
      }
    }
    if (needsThumbnail) {
      final hasBgImage =
          coreInfo.pages.isNotEmpty &&
          coreInfo.pages.first.backgroundImage != null;
      if (!hasBgImage) {
        preCapturedThumbnailBytes = await _captureThumbnailBytesFromFirstPage();
      }
    }

    final bool hasEdits = savingState.value != SavingState.saved;

    while (true) {
      if (savingState.value == SavingState.saving) {
        if (!force) {
          _saveFollowUpRequested = true;
          log.fine('saveToFile: coalesced behind in-flight save');
          return;
        }
        final existing = _pendingSaveFuture;
        if (existing != null) {
          log.info('saveToFile: awaiting in-flight save before forced flush');
          await existing;
        } else {
          log.warning(
            'saveToFile: state was saving without _pendingSaveFuture; resetting',
          );
          savingState.value = SavingState.waitingToSave;
        }
        if (_isDisposed || _isDeleted) return;
        continue;
      }

      if (savingState.value == SavingState.saved && !force) {
        return;
      }

      if (savingState.value == SavingState.waitingToSave) {
        _delayedSaveTimer?.cancel();
      }

      savingState.value = SavingState.saving;
      break;
    }

    final future = _runBackgroundSave(
      needsThumbnail: needsThumbnail,
      thumbnailPath: thumbnailPath,
      preCapturedThumbnailBytes: preCapturedThumbnailBytes,
      themeToUse: themeToUse,
      mediaQueryToUse: mediaQueryToUse,
      hasEdits: hasEdits,
      awaitVaultCommit: awaitVaultCommit,
    );
    _pendingSaveFuture = future;
    _pendingSavesByPath[coreInfo.filePath] = future;
    future.whenComplete(() {
      _pendingSaveFuture = null;
      _pendingSavesByPath.remove(coreInfo.filePath);
      if (_saveFollowUpRequested &&
          !_isDisposed &&
          !_isDeleted &&
          !coreInfo.readOnly) {
        _saveFollowUpRequested = false;
        savingState.value = SavingState.waitingToSave;
        unawaited(
          saveToFile(
            force: false,
            updateThumbnail: stows.thumbnailOnAutosave.value,
          ),
        );
      }
    });
    if (awaitVaultCommit) {
      await future;
    }

    return future;
  }

  static const int _autosaveMinIdleMs = 2000;
  int get _autosaveIdleMs => _autosaveMinIdleMs;

  Future<void> _runBackgroundSave({
    required bool needsThumbnail,
    required String thumbnailPath,
    Uint8List? preCapturedThumbnailBytes,
    ThemeData? themeToUse,
    MediaQueryData? mediaQueryToUse,
    bool hasEdits = false,
    bool awaitVaultCommit = false,
  }) async {
    VaultAdapter.preventLock = true;
    final saveEpoch = notePathEpoch(coreInfo.filePath);
    final saveNoteId = coreInfo.noteId;
    try {
      await _flushRecoveryWrites();
      await _renameFileNow();
      if (_isDisposed) {
        log.warning(
          '_runBackgroundSave aborted - editor disposed during rename',
        );
        return;
      }
      if (_isDeleted || notePathEpoch(coreInfo.filePath) != saveEpoch) {
        log.warning(
          '_runBackgroundSave aborted - note deleted or path invalidated',
        );
        return;
      }
      await Future.delayed(Duration.zero);

      final filePath = coreInfo.filePath + Editor.extension;
      final currentFirstPageHash = coreInfo.calculateFirstPageHash();
      final currentPageIndex = this.currentPageIndex;
      Uint8List? bson;

      /// Wait for ciphertext on disk before marking saved. All encrypt/zlib work
      /// runs off the UI isolate / native IO pool — this await must not do CPU
      /// on the root isolate. Index commits stay debounced unless forced.
      const awaitPersist = true;
      final awaitDbCommit = awaitVaultCommit;

      try {
        final now = DateTime.now();

        int editingDeltaMs = 0;
        if (hasEdits) {
          editingDeltaMs = now.difference(_lastSaveTime).inMilliseconds;
        }
        _lastSaveTime = now;

        final openDeltaMs = now.difference(_lastTimeSpentUpdate).inMilliseconds;
        _lastTimeSpentUpdate = now;

        String? updatedLocation = coreInfo.location;

        if (updatedLocation == null ||
            updatedLocation.length <= 3 ||
            updatedLocation.startsWith(RegExp(r'[+-]')) ||
            updatedLocation.startsWith('GMT')) {
          try {
            final tzInfo = await FlutterTimezone.getLocalTimezone();
            updatedLocation = tzInfo.identifier;
          } catch (_) {
            updatedLocation = now.timeZoneName;
          }
        }

        coreInfo = coreInfo.copyWith(
          totalTimeSpentEditing:
              coreInfo.totalTimeSpentEditing + editingDeltaMs,
          totalTimeSpent: coreInfo.totalTimeSpent + openDeltaMs,
          lastModification: now.millisecondsSinceEpoch,
          lastAccess: now.millisecondsSinceEpoch,
          location: updatedLocation,
        );

        coreInfo.assetCacheAll.allowRemovingAssets = false;
        final fullPath = FileManager.fixFileNameDelimiters(
          FileManager.getFilePath(filePath),
        );
        final didLayoutTouch = await coreInfo.assetCacheAll.renumberBeforeSave(
          fullPath,
          awaitWrite: awaitPersist,
          awaitDbCommit: awaitDbCommit,
          hasLazyPages: coreInfo.hasUnhydratedLazyPages,
        );
        if (didLayoutTouch) {
          coreInfo.invalidatePageBinaryEncodeCaches();
        }
        if (_isDisposed) {
          coreInfo.assetCacheAll.allowRemovingAssets = true;
          return;
        }
        await Future.delayed(Duration.zero);

        final assetFiles = <File>[];
        int maxAssetId = -1;
        final cacheLength = coreInfo.assetCacheAll.length;
        for (int i = 0; i < cacheLength; ++i) {
          final idSave = coreInfo.assetCacheAll.getAssetIdOnSave(i);
          if (idSave >= 0) {
            if (idSave > maxAssetId) maxAssetId = idSave;
            try {
              assetFiles.add(coreInfo.assetCacheAll.getAssetFile(i));
            } catch (_) {}
          }
        }

        if (currentFirstPageHash.isNotEmpty) {
          coreInfo.firstPageHash = currentFirstPageHash;
        }
        if (coreInfo.isInfinite && coreInfo.pages.isNotEmpty) {
          coreInfo.enforceSinglePage();
          _trimInfiniteCanvasWhitespace(coreInfo.pages.first);
        }
        coreInfo.noteToolSettings = captureNoteToolSettings(
          lastToolId: stows.lastTool.value,
          lastPenTypeId: stows.lastPenType.value,
        );
        bson = await coreInfo.saveToBinaryAsync(
          currentPageIndex: currentPageIndex,
          precomputedHash: currentFirstPageHash,
        );
        if (_isDisposed) {
          coreInfo.assetCacheAll.allowRemovingAssets = true;
          return;
        }
        await Future.delayed(Duration.zero);

        if (_isDeleted ||
            notePathEpoch(coreInfo.filePath) != saveEpoch ||
            coreInfo.noteId != saveNoteId) {
          log.warning(
            '[Editor.saveToFile] Aborting write; note deleted or superseded: $filePath',
          );
          coreInfo.assetCacheAll.allowRemovingAssets = true;
          return;
        }

        log.info(
          '[Editor.saveToFile] Writing ${bson.length} bytes to: $filePath',
        );
        try {
          await FileManager.writeFile(
            filePath,
            bson,
            awaitWrite: awaitPersist,
            awaitDbCommit: awaitDbCommit,
          );
          log.info(
            '[Editor.saveToFile] FileManager.writeFile completed for: $filePath',
          );
          if (_isDeleted ||
              notePathEpoch(coreInfo.filePath) != saveEpoch ||
              coreInfo.noteId != saveNoteId) {
            log.warning(
              '[Editor.saveToFile] Save raced with delete; removing resurrected file: $filePath',
            );
            try {
              await FileManager.deleteFile(filePath);
            } catch (_) {}
            coreInfo.assetCacheAll.allowRemovingAssets = true;
            return;
          }
          if (_isDisposed) return;
          try {
            unawaited(
              NoteLinksDatabase.instance.setLinksForPath(
                coreInfo.filePath,
                coreInfo.links,
                rootDirectory: FileManager.documentsDirectory,
              ),
            );
          } catch (e) {
            log.warning('Failed to update note links metadata: $e');
          }
        } catch (e, stack) {
          log.severe(
            '[Editor.saveToFile] FileManager.writeFile FAILED for: $filePath',
            e,
            stack,
          );
          savingState.value = SavingState.waitingToSave;
          coreInfo.assetCacheAll.allowRemovingAssets = true;
          return;
        }
        log.fine('[Editor.saveToFile] Successfully saved file: $filePath');
        HomeDataCache.instance.invalidate();

        for (final assetFile in assetFiles) {
          try {
            await FileManager.markFileAsSaved(assetFile);
          } catch (_) {}
        }
        final numAssetsToKeep = maxAssetId >= 0 ? maxAssetId + 1 : 0;
        if (numAssetsToKeep > 0 || (maxAssetId < 0 && assetFiles.isEmpty)) {
          await FileManager.removeUnusedAssets(
            filePath,
            numAssets: numAssetsToKeep,
          );
        }

        if (!_saveFollowUpRequested) {
          await _recoveryJournal?.clear();
        }
        savingState.value = SavingState.saved;
      } catch (e, stack) {
        log.severe('Failed to save file: $e', e, stack);
        savingState.value = SavingState.waitingToSave;
      } finally {
        coreInfo.assetCacheAll.allowRemovingAssets = true;
      }

      if (needsThumbnail && themeToUse != null && mediaQueryToUse != null) {
        try {
          final hasBgImage =
              coreInfo.pages.isNotEmpty &&
              coreInfo.pages.first.backgroundImage != null;
          if (hasBgImage) {
            await FileManager.generateThumbnailForNote(
              coreInfo: coreInfo,
              theme: themeToUse,
              mediaQuery: mediaQueryToUse,
              path: thumbnailPath,
            );
            _markThumbnailWritten(currentFirstPageHash);
          } else if (preCapturedThumbnailBytes != null &&
              preCapturedThumbnailBytes.isNotEmpty) {
            await FileManager.writeFile(
              thumbnailPath,
              preCapturedThumbnailBytes,
              awaitWrite: false,
            );
            log.info(
              'Thumbnail saved from pre-captured frame: ${preCapturedThumbnailBytes.length} bytes',
            );
            _markThumbnailWritten(currentFirstPageHash);
          } else {
            final saved = await _generateAndSaveThumbnail(
              theme: themeToUse,
              mediaQuery: mediaQueryToUse,
              destinationPath: thumbnailPath,
            );
            if (!saved) {
              await FileManager.generateThumbnailForNote(
                coreInfo: coreInfo,
                theme: themeToUse,
                mediaQuery: mediaQueryToUse,
                path: thumbnailPath,
              );
            }
            _markThumbnailWritten(currentFirstPageHash);
          }
        } catch (e) {
          log.warning('Thumbnail generation failed: $e');
        }
      }

      if (coreInfo.isInfinite &&
          coreInfo.infiniteThumbnailMode == 'jdenticon') {
        try {
          final thumbFile = File(thumbnailPath);
          if (!thumbFile.existsSync()) {
            await FileManager.generateJdenticonThumbnail(
              coreInfo.filePath,
              thumbnailPath,
            );
          }
        } catch (e) {
          log.warning('Infinite jdenticon thumbnail failed: $e');
        }
      }
    } finally {
      VaultAdapter.preventLock = false;
    }
  }

  late final _filenameFormKey = GlobalKey<FormState>();
  late final filenameTextEditingController = TextEditingController();
  Timer? _renameTimer;
  void renameFile([String? _]) {
    _renameTimer?.cancel();
    _renameTimer = Timer(const Duration(seconds: 5), _renameFileNow);
  }

  Future<void> _renameFileNow() async {
    final newName = filenameTextEditingController.text.trim();
    if (newName.isEmpty || newName == coreInfo.fileName) return;

    if (_filenameFormKey.currentState?.validate() ??
        _validateFilenameTextField(newName) == null) {
      final extPath = coreInfo.filePath + Editor.extension;
      final newExtPath = newName + Editor.extension;
      final exists = await FileManager.doesFileExist(extPath);
      if (!exists) {
        final idx = coreInfo.filePath.lastIndexOf('/');
        final dir = idx >= 0 ? coreInfo.filePath.substring(0, idx + 1) : '';
        coreInfo.filePath = dir + newName;
        needsNaming = false;
        return;
      }
      coreInfo.filePath = await FileManager.moveFile(extPath, newExtPath);
      coreInfo.filePath = coreInfo.filePath.substring(
        0,
        coreInfo.filePath.lastIndexOf(Editor.extension),
      );
      needsNaming = false;
    }

    final actualName = coreInfo.fileName;
    if (actualName != newName) {
      filenameTextEditingController.value = filenameTextEditingController.value
          .copyWith(
            text: actualName,
            selection: TextSelection.fromPosition(
              TextPosition(offset: actualName.length),
            ),
            composing: TextRange.empty,
          );
    }
  }

  String? _validateFilenameTextField(String? newName) {
    if (newName == null) return null;
    if (newName.isEmpty) return t.home.renameNote.noteNameEmpty;
    if (newName.contains('/')) return t.home.renameNote.noteNameContainsSlash;
    return null;
  }

  Tool _resolveToolForPenSizePresetFallback() {
    Tool? pick(Tool? candidate) {
      if (candidate != null && toolSupportsPenSizePresets(candidate)) {
        return candidate;
      }
      return null;
    }

    return pick(_lastPenTool) ??
        pick(Pen.currentPen) ??
        pick(Highlighter.currentHighlighter) ??
        pick(LaserPointer.currentLaserPointer) ??
        pick(ShapeTool.currentShapeTool) ??
        pick(_toolFromLastTool()) ??
        Pen.ballpointPen();
  }

  /// Writes pen/highlighter stroke options touched by presets into [stows].
  /// Deferred from [_applyPenPresetStrokeWidth] so preset taps repaint before
  /// pref serialization / listener churn blocks the UI isolate.
  void _persistStrokeToolPrefsAfterPresetTap() {
    final t = currentTool;
    if (t is Highlighter) {
      stows.lastHighlighterOptions.value = t.options;
      return;
    }
    if (t is Pen) {
      final pen = t;
      switch (pen.toolId) {
        case ToolId.fountainPen:
          stows.lastFountainPenOptions.value = pen.options;
          break;
        case ToolId.ballpointPen:
          stows.lastBallpointPenOptions.value = pen.options;
          break;
          break;
        case ToolId.calligraphyPen:
          stows.lastCalligraphyPenOptions.value = pen.options;
          break;
        case ToolId.advancedPen:
        case ToolId.experimentalPen:
          stows.lastAdvancedPenOptions.value = pen.options;
          break;
        case ToolId.advancedPencil:
          stows.lastAdvancedPencilOptions.value = pen.options;
          stows.lastAdvancedPencilPaint.value = Map<String, dynamic>.from(
            pen.paint.toJson(embedBytes: false),
          );
          break;
        default:
          break;
      }
    }
  }

  /// Applies preset stroke width to the active tool immediately (in-memory).
  /// Pen/highlighter option prefs are flushed after this frame via
  /// [_persistStrokeToolPrefsAfterPresetTap] so UI can repaint before pref I/O.
  /// Laser width updates [stows] synchronously because [LaserPointer.size] reads prefs.
  void _applyPenPresetStrokeWidth(double rawSize) {
    if (!toolSupportsPenSizePresets(currentTool)) {
      final next = _resolveToolForPenSizePresetFallback();
      setState(() {
        currentTool = next;
        if (next is Highlighter) {
          Highlighter.currentHighlighter = next;
        } else if (next is Pen) {
          Pen.currentPen = next;
        }
      });
    }

    final t = currentTool;
    if (t is Highlighter) {
      final h = t;
      final v = rawSize.clamp(h.sizeMin, h.sizeMax);
      h.options = h.options.copyWith(size: v);
    } else if (t is Pen) {
      final pen = t;
      final v = rawSize.clamp(pen.sizeMin, pen.sizeMax);
      pen.options = pen.options.copyWith(size: v);
    } else if (t is ShapeTool) {
      final st = ShapeTool.currentShapeTool;
      final v = rawSize.clamp(1.0, 20.0);
      st.config = st.config.copyWith(strokeWidth: v);
    } else if (t.toolId == ToolId.laserPointer) {
      // [LaserPointer.size] reads from stows — keep this write synchronous.
      stows.laserPointerSize.value = rawSize.clamp(4.0, LaserPointer.maxSize);
    }

    _bumpInteractionRepaint();

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _persistStrokeToolPrefsAfterPresetTap();
      autosaveAfterDelay();
    });
  }

  /// Persist live tool/color prefs into this note only (never upserts ink presets).
  void _captureNoteToolSettingsLocally() {
    if (!mounted || coreInfo.readOnly) return;
    coreInfo.noteToolSettings = captureNoteToolSettings(
      lastToolId: stows.lastTool.value,
      lastPenTypeId: stows.lastPenType.value,
    );
    autosaveAfterDelay();
  }

  void updateColorBar(Color color) {
    if (stows.recentColorsDontSavePresets.value) {
      if (ColorBar.colorPresets.any(
        (colorPreset) => colorPreset.color == color,
      )) {
        return;
      }
    }

    final newColorString = color.toARGB32().toString();

    if (stows.recentColorsChronological.value.length !=
        stows.recentColorsPositioned.value.length) {
      log.info(
        'MIGRATING recentColors: ${stows.recentColorsChronological.value.length} vs ${stows.recentColorsPositioned.value.length}',
      );
      stows.recentColorsChronological.value = List.of(
        stows.recentColorsPositioned.value,
      );
    }

    if (stows.pinnedColors.value.contains(newColorString)) {
    } else if (stows.recentColorsPositioned.value.contains(newColorString)) {
      stows.recentColorsChronological.value.remove(newColorString);
      stows.recentColorsChronological.value.add(newColorString);
      stows.recentColorsChronological.notifyListeners();
    } else {
      if (stows.recentColorsPositioned.value.length >=
          stows.recentColorsLength.value) {
        final removedColorString = stows.recentColorsChronological.value
            .removeAt(0);
        stows.recentColorsChronological.value.add(newColorString);
        final int removedColorPosition = stows.recentColorsPositioned.value
            .indexOf(removedColorString);
        stows.recentColorsPositioned.value[removedColorPosition] =
            newColorString;
      } else {
        stows.recentColorsChronological.value.add(newColorString);
        stows.recentColorsPositioned.value.insert(0, newColorString);
      }
      stows.recentColorsChronological.notifyListeners();
      stows.recentColorsPositioned.notifyListeners();
    }
  }

  Future<int> _pickPhotos({
    List<_PhotoInfo>? photoInfos,
    Offset? dropPosition,
  }) async {
    if (coreInfo.readOnly) return 0;

    photoInfos ??= await _pickPhotosWithFilePicker();
    if (photoInfos.isEmpty) {
      log.info('[ImageImport] Nenhuma imagem selecionada');
      return 0;
    }

    log.info(
      '[ImageImport] Iniciando importação de ${photoInfos.length} imagem(ns)',
    );

    currentTool = Select.currentSelect;

    final int targetPageIndex = dropPosition != null
        ? (onWhichPageIsFocalPoint(dropPosition) ?? currentPageIndex)
        : currentPageIndex;

    log.info('[ImageImport] Página alvo: $targetPageIndex');

    createPage(targetPageIndex);
    final page = coreInfo.pages[targetPageIndex];
    final pageSize = page.size;

    int successCount = 0;
    final List<EditorImage> newImages = [];

    for (int i = 0; i < photoInfos.length; i++) {
      final info = photoInfos[i];
      final String importId = 'IMG-${DateTime.now().microsecondsSinceEpoch}-$i';

      log.info(
        '[$importId] Processando imagem ${i + 1}/${photoInfos.length} (${info.extension}, ${info.bytes.length} bytes)',
      );

      try {
        if (info.extension == '.svg') {
          log.info('[$importId] Tipo SVG detectado');

          final now = DateTime.now();
          final r = math.Random();
          final randomId1 = r.nextInt(1 << 32);
          final randomId2 = r.nextInt(1 << 32);
          final String uniqueName =
              'svg_${now.microsecondsSinceEpoch}_${randomId1}_${randomId2}.svg';
          log.info('[$importId] Criando arquivo SVG: $uniqueName');

          final file = coreInfo.assetCacheAll.createRuntimeFile(
            uniqueName,
            info.bytes,
          );
          await file.writeAsBytes(info.bytes);
          log.info('[$importId] Arquivo SVG gravado: ${file.path}');

          final assetId = await coreInfo.assetCacheAll.add(
            file,
            fileInfo: info.fileInfo,
          );
          log.info('[$importId] SVG registrado no cache com assetId: $assetId');

          final image = SvgEditorImage(
            id: coreInfo.nextImageId++,
            assetCacheAll: coreInfo.assetCacheAll,
            assetId: assetId,
            pageIndex: targetPageIndex,
            pageSize: pageSize,
            onMoveImage: onMoveImage,
            onDeleteImage: onDeleteImage,
            onMiscChange: autosaveAfterDelay,
            onLoad: () => setState(() {}),
            dstRect: Rect.fromLTWH(0, 0, 300, 300),
          );
          newImages.add(image);
          log.info('[$importId] SVG criado com sucesso (id: ${image.id})');
        } else {
          log.info('[$importId] Tipo BITMAP detectado');

          final now = DateTime.now();
          final r = math.Random();
          final randomId1 = r.nextInt(1 << 32);
          final randomId2 = r.nextInt(1 << 32);
          final String uniqueName =
              'img_${now.microsecondsSinceEpoch}_${randomId1}_${randomId2}${info.extension}';
          log.info(
            '[$importId] Nome único gerado (alta entropia): $uniqueName',
          );

          log.info('[$importId] Criando arquivo físico...');
          final file = coreInfo.assetCacheAll.createRuntimeFile(
            uniqueName,
            info.bytes,
          );
          await file.writeAsBytes(info.bytes);
          log.info(
            '[$importId] Arquivo físico criado: ${file.path} (${info.bytes.length} bytes)',
          );

          log.info(
            '[$importId] Registrando no AssetCache com forceNew: true...',
          );
          final assetId = await coreInfo.assetCacheAll.add(
            file,
            copyFromSource: false,
            forceNew: true,
            fileInfo: info.fileInfo,
          );
          log.info(
            '[$importId] Registrado no cache com assetId: $assetId (único garantido)',
          );

          log.info(
            '[$importId] Injetando MemoryImage diretamente no CacheItem...',
          );
          coreInfo.assetCacheAll.setImageProvider(
            assetId,
            MemoryImage(info.bytes),
          );
          log.info(
            '[$importId] MemoryImage injetado (exibição instantânea garantida)',
          );

          log.info(
            '[$importId] Obtendo imageProviderNotifier (já com MemoryImage)...',
          );
          final providerNotifier = coreInfo.assetCacheAll
              .getImageProviderNotifier(assetId);
          log.info(
            '[$importId] Notifier obtido. Provider atual: ${providerNotifier.value.runtimeType}',
          );

          log.info('[$importId] Decodificando dimensões da imagem...');
          Size imageSize = const Size(300, 300);
          try {
            final buffer = await ui.ImmutableBuffer.fromUint8List(info.bytes);
            final descriptor = await ui.ImageDescriptor.encoded(buffer);
            imageSize = Size(
              descriptor.width.toDouble(),
              descriptor.height.toDouble(),
            );
            descriptor.dispose();
            buffer.dispose();
            log.info(
              '[$importId] Dimensões decodificadas: ${imageSize.width}x${imageSize.height}',
            );
          } catch (e) {
            log.warning(
              '[$importId] Falha ao decodificar dimensões, usando padrão: $e',
            );
          }

          if (imageSize.width > pageSize.width * 0.8) {
            final scale = (pageSize.width * 0.8) / imageSize.width;
            imageSize = imageSize * scale;
            log.info(
              '[$importId] Imagem redimensionada para caber na página: ${imageSize.width}x${imageSize.height}',
            );
          }

          Offset pos =
              dropPosition ?? Offset(pageSize.width / 2, pageSize.height / 2);

          if (successCount > 0) {
            pos += Offset(successCount * 20.0, successCount * 20.0);
            log.info(
              '[$importId] Posição ajustada para múltiplas imagens: $pos',
            );
          }

          log.info('[$importId] Criando PngEditorImage...');
          final image = PngEditorImage(
            id: coreInfo.nextImageId++,
            assetCacheAll: coreInfo.assetCacheAll,
            assetId: assetId,
            extension: info.extension,
            imageProviderNotifier: providerNotifier,
            pageIndex: targetPageIndex,
            pageSize: pageSize,
            dstRect: Rect.fromCenter(
              center: pos,
              width: imageSize.width,
              height: imageSize.height,
            ),
            naturalSize: imageSize,
            onMoveImage: onMoveImage,
            onDeleteImage: onDeleteImage,
            onMiscChange: autosaveAfterDelay,
            onLoad: () {
              log.info(
                '[$importId] onLoad callback chamado - forçando rebuild',
              );
              if (mounted) setState(() {});
            },
          );
          image.invertible = info.invertible;

          newImages.add(image);
          // CRITICAL: Add image to page IMMEDIATELY so it can be rendered

          page.images.add(image);
          log.info(
            '[$importId] PngEditorImage criado e adicionado à página (id: ${image.id})',
          );

          // CRITICAL: Force immediate UI update to display MemoryImage

          if (mounted) {
            setState(() {});
            log.info(
              '[$importId] setState() chamado imediatamente após criar imagem',
            );
          }
        }
        successCount++;
        log.info('[$importId] >>> IMAGEM ${i + 1} IMPORTADA COM SUCESSO <<<');
      } catch (e, s) {
        log.severe('[$importId] ERRO ao importar imagem: $e', e, s);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                t.editor.errorImportingImageIndex(index: i + 1, error: e),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }

    if (newImages.isNotEmpty) {
      log.info(
        '[ImageImport] Finalizando importação de ${newImages.length} imagem(ns)...',
      );

      setState(() {
        final selectionBounds = newImages
            .map((i) => i.dstRect)
            .reduce((a, b) => a.expandToInclude(b));

        Select.currentSelect.unselect();
        Select.currentSelect.selectResult = SelectResult(
          pageIndex: targetPageIndex,
          pageIndexStart: targetPageIndex,
          strokes: [],
          images: List.from(newImages),
          path: Path()..addRect(selectionBounds),
          displayBounds: selectionBounds,
        );
        Select.currentSelect.doneSelecting = true;
      });

      history.recordChange(
        EditorHistoryItem(
          type: .draw,
          pageIndex: targetPageIndex,
          strokes: [],
          images: newImages,
        ),
      );

      if (coreInfo.isInfinite &&
          targetPageIndex >= 0 &&
          targetPageIndex < coreInfo.pages.length) {
        _fitInfiniteCanvasToContent(coreInfo.pages[targetPageIndex]);
      }

      log.info('[ImageImport] Estado atualizado. Disparando autosave...');
      autosaveAfterDelay();
      log.info(
        '[ImageImport] >>> IMPORTAÇÃO CONCLUÍDA: $successCount/$photoInfos.length sucesso(s) <<<',
      );
    } else {
      log.warning('[ImageImport] Nenhuma imagem foi adicionada com sucesso');
    }

    return successCount;
  }

  void _showCalculator({
    PlotAnimationMetadata? visualizerMetadata,
    bool readOnlyVisualizer = false,
  }) {
    if (_calculatorOverlay != null) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    _calculatorOverlay = OverlayEntry(
      maintainState: true,
      opaque: false,
      builder: (overlayEntryContext) => Positioned(
        left: _calculatorOffset.dx,
        top: _calculatorOffset.dy,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: FloatingCalculator(
            onClose: _hideCalculator,
            onDrag: (details) {
              _calculatorOffset += details.delta;
              _calculatorOverlay?.markNeedsBuild();
            },
            visualizerMetadata: visualizerMetadata,
            readOnlyVisualizer: readOnlyVisualizer,
            initialWorkspaceMetadata: coreInfo.floatingCalculatorMetadata,
            onWorkspaceMetadataChanged: (metadata) {
              if (coreInfo.floatingCalculatorMetadata == metadata) return;
              coreInfo.floatingCalculatorMetadata = metadata;
              autosaveAfterDelay();
            },

            menuOverlayContext: overlayEntryContext,

            onInsertImage:
                (
                  Uint8List bytes, {
                  String? assetFileInfo,
                  bool invertible = false,
                }) {
                  _insertImageBytes(
                    bytes,
                    extension: '.png',
                    assetFileInfo: assetFileInfo,
                    invertible: invertible,
                  );
                },
          ),
        ),
      ),
    );
    overlay.insert(_calculatorOverlay!);
  }

  void _hideCalculator() {
    _calculatorOverlay?.remove();
    _calculatorOverlay = null;
  }

  void _toggleRegionScreenshotMode() {
    setState(() {
      _regionScreenshotMode = !_regionScreenshotMode;
    });
  }

  void _cancelRegionScreenshotMode() {
    if (!_regionScreenshotMode) return;
    setState(() => _regionScreenshotMode = false);
  }

  Future<void> _captureRegionScreenshot(Rect localRect) async {
    if (!mounted) return;
    setState(() => _regionScreenshotMode = false);

    // Let the overlay leave the tree before reading pixels (not required for
    // correctness since it sits outside the RepaintBoundary, but avoids races).
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final boundary =
        _regionScreenshotBoundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null || !boundary.hasSize) {
      _showRegionScreenshotMessage(t.editor.toolbar.regionScreenshotFailed);
      return;
    }

    final pixelRatio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
    late final ui.Image fullImage;
    try {
      fullImage = await boundary.toImage(pixelRatio: pixelRatio);
    } catch (e, st) {
      log.warning('Region screenshot capture failed: $e', e, st);
      _showRegionScreenshotMessage(t.editor.toolbar.regionScreenshotFailed);
      return;
    }

    final left = (localRect.left * pixelRatio).floor().clamp(
      0,
      fullImage.width,
    );
    final top = (localRect.top * pixelRatio).floor().clamp(0, fullImage.height);
    final right = (localRect.right * pixelRatio).ceil().clamp(
      left + 1,
      fullImage.width,
    );
    final bottom = (localRect.bottom * pixelRatio).ceil().clamp(
      top + 1,
      fullImage.height,
    );
    final cropW = right - left;
    final cropH = bottom - top;
    if (cropW < 2 || cropH < 2) {
      fullImage.dispose();
      _showRegionScreenshotMessage(t.editor.toolbar.regionScreenshotTooSmall);
      return;
    }

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      fullImage,
      Rect.fromLTWH(
        left.toDouble(),
        top.toDouble(),
        cropW.toDouble(),
        cropH.toDouble(),
      ),
      Rect.fromLTWH(0, 0, cropW.toDouble(), cropH.toDouble()),
      ui.Paint(),
    );
    fullImage.dispose();

    final cropped = await recorder.endRecording().toImage(cropW, cropH);
    final byteData = await cropped.toByteData(format: ui.ImageByteFormat.png);
    cropped.dispose();
    if (byteData == null) {
      _showRegionScreenshotMessage(t.editor.toolbar.regionScreenshotFailed);
      return;
    }
    final pngBytes = byteData.buffer.asUint8List();
    if (!mounted) return;
    await _promptRegionScreenshotAction(pngBytes);
  }

  void _showRegionScreenshotMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _promptRegionScreenshotAction(Uint8List pngBytes) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AdaptiveAlertDialog(
        title: Text(t.editor.toolbar.regionScreenshotTitle),
        content: Text(t.editor.toolbar.regionScreenshotBody),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop('copy'),
            child: Text(t.editor.toolbar.regionScreenshotCopy),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop('share'),
            child: Text(t.editor.toolbar.regionScreenshotShare),
          ),
        ],
      ),
    );
    if (!mounted || choice == null || choice == 'cancel') return;

    if (choice == 'copy') {
      try {
        final clipboard = SystemClipboard.instance;
        await clipboard?.write([DataWriterItem()..add(Formats.png(pngBytes))]);
      } catch (e, st) {
        log.warning('Region screenshot clipboard failed: $e', e, st);
        _showRegionScreenshotMessage(t.editor.toolbar.regionScreenshotFailed);
      }
      return;
    }

    if (choice == 'share') {
      try {
        final tempDir = Directory.systemTemp;
        final path =
            '${tempDir.path}${Platform.pathSeparator}notes_region_${DateTime.now().millisecondsSinceEpoch}.png';
        final file = File(path);
        await file.writeAsBytes(pngBytes, flush: true);
        if (!mounted) {
          await FileManager.secureDelete(file);
          return;
        }
        await FileManager.exportTempFile(
          file.path,
          'region_screenshot.png',
          context: context,
        );
      } catch (e, st) {
        log.warning('Region screenshot share failed: $e', e, st);
        _showRegionScreenshotMessage(t.editor.toolbar.regionScreenshotFailed);
      }
    }
  }

  PlotAnimationMetadata? _plotMetadataFromImage(EditorImage image) {
    if (image is! PngEditorImage) return null;
    final fileInfo = image.assetCacheAll.getAssetFileInfo(image.assetId);
    return PlotAnimationMetadata.tryDecodeFromAssetInfo(fileInfo);
  }

  void _showPlotVisualizer(PlotAnimationMetadata metadata) {
    if (_calculatorOverlay != null) {
      _hideCalculator();
    }
    _showCalculator(visualizerMetadata: metadata, readOnlyVisualizer: true);
  }

  String _normalizeLinkableNotePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return '';
    final fileName = trimmed.split('/').last;
    if (RegExp(r'.+\.(p|\d+|sbn2|sbn)$').hasMatch(fileName)) {
      return trimmed.replaceFirst(RegExp(r'\.(p|\d+|sbn2|sbn)$'), '');
    }
    return trimmed;
  }

  Future<List<_LinkTargetCandidate>> _loadLinkTargetCandidates() async {
    final allFiles = await FileManager.getAllFiles(includeExtensions: true);
    final normalized = <String>{};
    for (final raw in allFiles) {
      final path = _normalizeLinkableNotePath(raw);
      if (path.isEmpty || path == coreInfo.filePath) continue;
      // Do not show any path whose filename has an extension (e.g. .pdf, .sbn2)
      if (path.split('/').last.contains('.')) continue;
      normalized.add(path);
    }
    final pathList = normalized.toList();
    final tagsByPath = await TagDatabase.instance.getTagsForPaths(pathList);
    final candidates = <_LinkTargetCandidate>[
      for (final path in pathList)
        (
          path: path,
          displayName: path.split('/').last,
          tags: (tagsByPath[TagDatabase.normalizePath(path)] ?? {})
              .map((t) => t.toLowerCase())
              .toSet(),
        ),
    ];
    candidates.sort((a, b) => a.displayName.compareTo(b.displayName));
    return candidates;
  }

  void _notifyEmbeddedChromeChanged() {
    widget.onEmbeddedChromeChanged?.call();
  }

  Future<void> _navigateToNoteReplacingCurrent(
    String path, {
    int? pageIndex,
    required bool pushCurrentToHistory,
  }) async {
    if (_noteLinkNavBusy) return;
    final target = path.trim();
    if (target.isEmpty) return;
    if (target == coreInfo.filePath) {
      if (pageIndex != null && pageIndex >= 0) {
        _onGoToLocation(pageIndex);
      }
      return;
    }

    _noteLinkNavBusy = true;
    try {
      if (pushCurrentToHistory) {
        final current = coreInfo.filePath;
        if (current.isNotEmpty) {
          _noteLinkBackStack.add(
            _NoteLinkHistoryEntry(path: current, pageIndex: currentPageIndex),
          );
          _notifyEmbeddedChromeChanged();
          if (mounted) setState(() {});
        }
      }

      await saveToFile(force: true);
      if (!mounted) return;
      await _replaceLoadedNote(target, pageIndex: pageIndex);
    } finally {
      _noteLinkNavBusy = false;
    }
  }

  Future<void> _popNoteLinkHistory() async {
    if (_noteLinkBackStack.isEmpty || _noteLinkNavBusy) return;
    final prev = _noteLinkBackStack.removeLast();
    _notifyEmbeddedChromeChanged();
    if (mounted) setState(() {});
    await _navigateToNoteReplacingCurrent(
      prev.path,
      pageIndex: prev.pageIndex,
      pushCurrentToHistory: false,
    );
  }

  Future<void> _replaceLoadedNote(String path, {int? pageIndex}) async {
    Pen.currentStroke = null;
    try {
      Select.currentSelect.unselect();
    } catch (_) {}
    history = EditorHistory();
    _delayedSaveTimer?.cancel();
    _delayedSaveTimer = null;
    _renameTimer?.cancel();
    _selectionLongPressTimer?.cancel();
    _clearSelectionPreview();
    _cancelPreviewJumpHistory();
    if (_isDockedSidePanelVisible) {
      _closeDockedSidePanel();
    }

    try {
      await _recoveryJournal?.flush();
    } catch (_) {}
    _recoveryJournal = null;

    _pageRasterCache.invalidateForZoom();
    _lastPageRasterBandStart = null;
    _lastPageRasterBandEnd = null;

    final previous = coreInfo;
    quillFocus.value = null;
    for (final page in previous.pages) {
      try {
        page.quill.focusNode.removeListener(_onQuillFocusChange);
        page.quill.changeSubscription?.cancel();
      } catch (_) {}
    }

    coreInfo = EditorCoreInfo(filePath: path);
    if (pageIndex != null && pageIndex >= 0) {
      coreInfo.initialPageIndex = pageIndex;
    }
    filenameTextEditingController.text = coreInfo.fileName;
    _transformationController.value = Matrix4.identity();
    _lastCurrentPageIndex = pageIndex ?? 0;

    try {
      previous.dispose();
    } catch (e) {
      log.warning('Failed to dispose previous note during link nav: $e');
    }

    await _initStrokes();
    if (!mounted) return;
    setState(() {});
    _notifyEmbeddedChromeChanged();
  }

  void _openLinkedNote(NoteLink link) {
    if (!mounted) return;
    if (link.targetPath.isEmpty) {
      _onGoToLocation(link.targetPageIndex);
      return;
    }
    unawaited(
      _navigateToNoteReplacingCurrent(
        link.targetPath,
        pageIndex: link.targetPageIndex,
        pushCurrentToHistory: true,
      ),
    );
  }

  void _onCanvasNoteLinkTap(NoteLink link) {
    _openLinkedNote(link);
  }

  Future<void> _showTagsAndLinksDialog() async {
    if (!mounted) return;
    final tagInputController = TextEditingController();
    final currentPage = coreInfo.pages[currentPageIndex];
    final linksForPage = coreInfo.linksForPage(currentPage, currentPageIndex);

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          Future<void> addLink() async {
            final candidates = await _loadLinkTargetCandidates();
            if (!mounted) return;
            _LinkTargetCandidate? selectedCandidate;
            final pageController = TextEditingController(text: '1');
            final labelController = TextEditingController();
            final searchController = TextEditingController();
            String search = '';

            final created = await showDialog<bool>(
              context: context,
              barrierColor: Colors.black.withOpacity(0.4),
              builder: (context) => StatefulBuilder(
                builder: (context, setLocalState) => Dialog(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  insetPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 24,
                  ),
                  child: RuggedDialogShell(
                    maxWidth: 500,
                    child: Material(
                      color: Colors.transparent,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          t.editor.addInternalLink,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.4,
                              ),
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: searchController,
                          onChanged: (value) {
                            setLocalState(() {
                              search = value.trim().toLowerCase();
                            });
                          },
                          decoration: InputDecoration(
                            labelText: 'Search note by name or tag',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey.withOpacity(0.1),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 180,
                          child: Builder(
                            builder: (context) {
                              final filtered = candidates.where((candidate) {
                                if (search.isEmpty) return true;
                                final name = candidate.displayName
                                    .toLowerCase();
                                if (name.contains(search)) return true;
                                return candidate.tags.any(
                                  (tag) => tag.contains(search),
                                );
                              }).toList();
                              if (filtered.isEmpty) {
                                return Center(
                                  child: Text(t.editor.noNotesMatchQuery),
                                );
                              }
                              return ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final candidate = filtered[index];
                                  final selected =
                                      selectedCandidate?.path == candidate.path;
                                  return ListTile(
                                    dense: true,
                                    selected: selected,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    selectedTileColor: Colors.grey.withOpacity(
                                      0.2,
                                    ),
                                    title: Text(
                                      candidate.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: candidate.tags.isEmpty
                                        ? null
                                        : Text(
                                            candidate.tags.take(4).join(', '),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                    onTap: () {
                                      setLocalState(() {
                                        selectedCandidate = candidate;
                                      });
                                    },
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: pageController,
                          decoration: InputDecoration(
                            labelText: 'Page or range (e.g. 1 or 1-5)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey.withOpacity(0.1),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: labelController,
                          decoration: InputDecoration(
                            labelText: 'Label (optional)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey.withOpacity(0.1),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 12),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: selectedCandidate == null
                                  ? null
                                  : () => Navigator.pop(context, true),
                              child: const Text('Add'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              ),
            );

            if (created != true || selectedCandidate == null) {
              searchController.dispose();
              pageController.dispose();
              labelController.dispose();
              return;
            }
            final pageText = pageController.text.trim();
            int pageStart = 1;
            int? pageEnd;
            if (pageText.contains('-')) {
              final parts = pageText.split('-');
              if (parts.length == 2) {
                pageStart = int.tryParse(parts[0].trim()) ?? 1;
                final endParsed = int.tryParse(parts[1].trim());
                if (endParsed != null && endParsed >= pageStart) {
                  pageEnd = endParsed;
                }
              }
            } else {
              pageStart = int.tryParse(pageText) ?? 1;
            }
            try {
              final targetInfo = await EditorCoreInfo.loadFromFilePath(
                selectedCandidate!.path,
                readOnly: true,
                onlyFirstPage: false,
              );
              final pageCount = targetInfo.pages.length;
              if (pageCount <= 0) {
                pageStart = 1;
                pageEnd = null;
              } else {
                pageStart = pageStart.clamp(1, pageCount);
                pageEnd = pageEnd != null
                    ? pageEnd.clamp(pageStart, pageCount)
                    : null;
              }
            } catch (_) {
              pageStart = pageStart.clamp(1, 9999);
              pageEnd = pageEnd != null ? pageEnd.clamp(pageStart, 9999) : null;
            }
            final currentPage = coreInfo.pages[currentPageIndex];
            final link = NoteLink(
              sourcePageId: currentPage.id,
              sourcePageIndex: currentPageIndex,
              targetPath: selectedCandidate!.path,
              targetPageIndex: pageStart - 1,
              targetPageIndexEnd: pageEnd != null ? pageEnd - 1 : null,
              label: labelController.text.trim().isEmpty
                  ? null
                  : labelController.text.trim(),
            );
            coreInfo.links = [...coreInfo.links, link];
            linksForPage.add(link);
            autosaveAfterDelay();
            setStateDialog(() {});
            if (mounted) setState(() {});
            try {
              unawaited(
                NoteLinksDatabase.instance.setLinksForPath(
                  coreInfo.filePath,
                  coreInfo.links,
                  rootDirectory: FileManager.documentsDirectory,
                ),
              );
            } catch (e) {
              log.warning('Failed to update note links metadata: $e');
            }
            searchController.dispose();
            pageController.dispose();
            labelController.dispose();
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
              child: DecoratedBox(
                decoration: homeRuggedPanelDecoration(context),
                child: Material(
                  color: Colors.transparent,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          t.editor.tagsAndLinks,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: tagInputController,
                                decoration: InputDecoration(
                                  labelText: 'Add tag',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey.withOpacity(0.1),
                                  suffixIcon: IconButton(
                                    icon: const Icon(Icons.add),
                                    onPressed: () {
                                      final tag = tagInputController.text
                                          .trim()
                                          .toLowerCase();
                                      if (tag.isEmpty) return;
                                      final updated = {
                                        ...coreInfo.tags,
                                        tag,
                                      }.toList()..sort();
                                      coreInfo.tags = updated;
                                      tagInputController.clear();
                                      TagDatabase.instance.setTagsForPath(
                                        coreInfo.filePath,
                                        coreInfo.tags,
                                      );
                                      autosaveAfterDelay();
                                      setStateDialog(() {});
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final tag in coreInfo.tags)
                                    Chip(
                                      label: Text(tag),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      onDeleted: () {
                                        coreInfo.tags = coreInfo.tags
                                            .where((t) => t != tag)
                                            .toList();
                                        TagDatabase.instance.setTagsForPath(
                                          coreInfo.filePath,
                                          coreInfo.tags,
                                        );
                                        autosaveAfterDelay();
                                        setStateDialog(() {});
                                      },
                                    ),
                                ],
                              ),
                              const SizedBox(height: 32),
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Page links',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: addLink,
                                    icon: const Icon(Icons.add_link),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (linksForPage.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8.0,
                                  ),
                                  child: Text(
                                    t.editor.noLinksOnPage,
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                )
                              else
                                ...linksForPage.map(
                                  (link) => ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    leading: const Icon(Icons.link),
                                    title: Text(
                                      link.label ??
                                          (link.targetPath.isEmpty
                                              ? 'Current Note'
                                              : link.targetPath
                                                    .split('/')
                                                    .last),
                                    ),
                                    subtitle: Text(
                                      link.isRange
                                          ? '${link.targetPath.isEmpty ? 'Internal' : link.targetPath} (pages ${link.targetPageIndex + 1}-${link.targetPageIndexEnd! + 1})'
                                          : '${link.targetPath.isEmpty ? 'Internal' : link.targetPath} (page ${link.targetPageIndex + 1})',
                                    ),
                                    onTap: () {
                                      if (link.targetPath.isEmpty) {
                                        Navigator.pop(
                                          context,
                                        ); // Close the dialog
                                        _onGoToLocation(link.targetPageIndex);
                                      } else {
                                        Navigator.pop(context);
                                        _openLinkedNote(link);
                                      }
                                    },
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () {
                                        coreInfo.links = coreInfo.links
                                            .where((item) => item != link)
                                            .toList();
                                        linksForPage.remove(link);
                                        autosaveAfterDelay();
                                        setStateDialog(() {});
                                        if (mounted) setState(() {});
                                        try {
                                          unawaited(
                                            NoteLinksDatabase.instance
                                                .setLinksForPath(
                                                  coreInfo.filePath,
                                                  coreInfo.links,
                                                  rootDirectory: FileManager
                                                      .documentsDirectory,
                                                ),
                                          );
                                        } catch (e) {
                                          log.warning(
                                            'Failed to update note links metadata: $e',
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          );
        },
      ),
    );
    tagInputController.dispose();
  }

  Future<void> _insertImageBytes(
    Uint8List rawBytes, {
    required String extension,
    Offset? position,
    String? assetFileInfo,
    bool invertible = false,
  }) async {
    if (coreInfo.readOnly) return;

    final String processId = 'IMG-${math.Random().nextInt(99999)}';
    log.info('[$processId] >>> INICIANDO INSERÇÃO DE BYTES <<<');

    try {
      final photoInfo = (
        bytes: rawBytes,
        extension: extension,
        path: 'generated_$processId',
        fileInfo: assetFileInfo,
        invertible: invertible,
      );

      log.info(
        '[$processId] Delegando para _pickPhotos (implementação unificada)...',
      );
      await _pickPhotos(photoInfos: [photoInfo], dropPosition: position);
      log.info('[$processId] >>> INSERÇÃO CONCLUÍDA <<<');
    } catch (e, stack) {
      log.severe('[$processId] FALHA NA INSERÇÃO: $e', e, stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.editor.errorInsertingImage(error: e)),
            backgroundColor: Colors.red,
          ),
        );
      }
      rethrow;
    }
  }

  Future<List<_PhotoInfo>> _pickPhotosWithFilePicker() async {
    VaultAdapter.preventLock = true;
    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,

        allowedExtensions: [
          'jpg',
          'jpeg',
          'png',
          'gif',
          'tiff',
          'bmp',
          'tga',
          'ico',
          'pvrtc',
          'svg',
          'webp',
          'psd',
          'exr',
        ],
        allowMultiple: true,
        withData: true,
      );
    } finally {
      VaultAdapter.preventLock = false;
    }

    if (result == null) return const [];

    return [
      for (final PlatformFile file in result.files)
        if (file.bytes != null && file.extension != null)
          (
            bytes: file.bytes!,
            extension: '.${file.extension!}',
            path: file.path!,
            fileInfo: null,
            invertible: false,
          ),
    ];
  }

  Future<bool> importPdf() async {
    if (coreInfo.readOnly) return false;
    if (!Editor.canRasterPdf) return false;

    VaultAdapter.preventLock = true;
    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
        withData: false,
      );
    } finally {
      VaultAdapter.preventLock = false;
    }

    if (result == null) return false;

    final PlatformFile file = result.files.single;
    final path = file.path!;

    if (coreInfo.isInfinite) {
      return _importPdfAsImageForInfiniteNote(path);
    }

    return importPdfFromFilePath(path);
  }

  Future<bool> _importPdfAsImageForInfiniteNote(String path) async {
    final pdfFile = File(path);

    final assetIndex = await coreInfo.assetCacheAll.addPdfFast(pdfFile);
    final pdfNotifier = coreInfo.assetCacheAll.getPdfNotifier(assetIndex);
    PdfDocument? pdfDocument = pdfNotifier.value;
    if (pdfDocument == null) {
      final completer = Completer<PdfDocument>();
      late VoidCallback listener;
      listener = () {
        if (pdfNotifier.value != null) {
          completer.complete(pdfNotifier.value!);
          pdfNotifier.removeListener(listener);
        }
      };
      pdfNotifier.addListener(listener);
      pdfDocument = await completer.future;
    }

    if (!mounted) return false;
    if (pdfDocument.pages.isEmpty) return false;

    final invert = stows.noteInvertInDarkModeOverrides.value[coreInfo.filePath] == 1;
    final selected = await PdfPagePickerDialog.show(
      context,
      pdfDocument: pdfDocument,
      pdfFile: pdfFile,
      invert: invert,
    );

    if (selected == null || selected.isEmpty) return false;

    coreInfo.assetCacheAll.addUse(assetIndex);

    final viewportSize =
        _canvasGestureDetectorKey.currentState?.containerBounds.biggest ??
        MediaQuery.sizeOf(context);
    final transform = _transformationController.value;
    final scale = transform.getMaxScaleOnAxis();
    final tx = transform.getTranslation().x;
    final ty = transform.getTranslation().y;

    final visibleLeft = -tx / scale;
    final visibleTop = -ty / scale;
    final visibleRight = (viewportSize.width - tx) / scale;
    final visibleBottom = (viewportSize.height - ty) / scale;
    final visibleCenter = Offset(
      (visibleLeft + visibleRight) / 2,
      (visibleTop + visibleBottom) / 2,
    );

    final page = coreInfo.pages[0];
    final pageSize = page.size;
    const baseWidth = 400.0;

    for (int i = 0; i < selected.length; i++) {
      final pdfPageIdx = selected[i];
      final pdfPage = pdfDocument.pages[pdfPageIdx];
      final naturalSize = Size(
        pdfPage.width.toDouble(),
        pdfPage.height.toDouble(),
      );

      final imageWidth = math.min(baseWidth, naturalSize.width);
      final imageHeight = imageWidth * naturalSize.height / naturalSize.width;

      final offset = Offset(
        (i - (selected.length - 1) / 2) * (imageWidth + 24),
        0,
      );
      final center = visibleCenter + offset;
      final dstRect = Rect.fromCenter(
        center: center,
        width: imageWidth,
        height: imageHeight,
      );

      final pdfImage = PdfEditorImage(
        id: coreInfo.nextImageId++,
        pdfFile: pdfFile,
        pdfPage: pdfPageIdx,
        assetId: assetIndex,
        assetCacheAll: coreInfo.assetCacheAll,
        pageIndex: 0,
        pageSize: pageSize,
        naturalSize: naturalSize,
        dstRect: dstRect,
        onMoveImage: onMoveImage,
        onDeleteImage: onDeleteImage,
        onMiscChange: autosaveAfterDelay,
        onLoad: () {
          if (mounted) setState(() {});
        },
        onPdfTap: (localPosition, doc, pIdx, _) {
          _onPdfTap(
            localPosition,
            doc,
            pIdx,
            Size(imageWidth, imageHeight),
            naturalSize,
            pdfFile,
          );
        },
      );

      page.layerAt(0).addImage(pdfImage);
      history.recordChange(
        EditorHistoryItem(
          type: EditorHistoryItemType.draw,
          pageIndex: 0,
          strokes: const [],
          images: [pdfImage],
          page: page,
        ),
      );
    }

    _fitInfiniteCanvasToContent(page);
    if (mounted) setState(() {});
    currentTool = Select.currentSelect;
    autosaveAfterDelay();
    return true;
  }

  Future<bool> importPdfFromFilePath(String path) async {
    if (coreInfo.isInfinite) {
      return _importPdfAsImageForInfiniteNote(path);
    }

    final pdfFile = File(path);

    final assetIndex = await coreInfo.assetCacheAll.addPdfFast(pdfFile);

    final pdfNotifier = coreInfo.assetCacheAll.getPdfNotifier(assetIndex);

    PdfDocument? pdfDocument;
    pdfDocument = pdfNotifier.value;
    if (pdfDocument == null) {
      final completer = Completer<PdfDocument>();
      late VoidCallback listener;
      listener = () {
        if (pdfNotifier.value != null) {
          completer.complete(pdfNotifier.value!);
          pdfNotifier.removeListener(listener);
        }
      };
      pdfNotifier.addListener(listener);
      pdfDocument = await completer.future;
    }

    if (!mounted) return false;

    final totalPages = pdfDocument.pages.length;
    if (totalPages == 0) {
      log.severe('PDF has no pages');
      return false;
    }
    log.info('PDF loaded with $totalPages pages');

    final emptyPage = coreInfo.pages.removeLast();
    assert(emptyPage.isEmpty);

    final Completer<void> firstPageRendered = Completer<void>();

    final newPages = <EditorPage>[];
    for (int i = 0; i < totalPages; i++) {
      final pdfPage = pdfDocument.pages[i];
      final naturalSize = Size(
        pdfPage.width.toDouble(),
        pdfPage.height.toDouble(),
      );

      final pageSize = Size(
        EditorPage.defaultWidth,
        EditorPage.defaultWidth * naturalSize.height / naturalSize.width,
      );

      final editorPage = EditorPage(
        id: coreInfo.allocatePageId(),
        width: pageSize.width,
        height: pageSize.height,
        // Prevent white edge artifacts around PDF background images
        hasLocalBorderColor: true,
        borderColor: Colors.transparent,
      );

      final pageIndex = i;
      editorPage.backgroundImage = PdfEditorImage(
        id: coreInfo.nextImageId++,
        pdfFile: pdfFile,
        pdfPage: i,
        pageIndex: pageIndex,
        pageSize: pageSize,
        naturalSize: naturalSize,
        dstRect: Rect.fromLTWH(0, 0, pageSize.width, pageSize.height),
        onMoveImage: onMoveImage,
        onDeleteImage: onDeleteImage,
        onMiscChange: autosaveAfterDelay,
        onLoad: () {
          if (mounted) setState(() {});
          if (pageIndex == 0 && !firstPageRendered.isCompleted) {
            firstPageRendered.complete();
            log.info('First PDF page loaded visually.');
          }
        },
        assetCacheAll: coreInfo.assetCacheAll,
        assetId: assetIndex,
        onPdfTap: (localPosition, pdfDocument, pdfPage, pdfFile) {
          _onPdfTap(
            localPosition,
            pdfDocument,
            pdfPage,
            pageSize,
            naturalSize,
            pdfFile,
          );
        },
      );

      newPages.add(editorPage);
      if (i % 8 == 7) await Future.delayed(Duration.zero);
    }

    for (int i = 0; i < newPages.length; i++) {
      coreInfo.assetCacheAll.addUse(assetIndex);
      coreInfo.pages.add(newPages[i]);
      history.recordChange(
        EditorHistoryItem(
          type: EditorHistoryItemType.insertPage,
          pageIndex: coreInfo.pages.length - 1,
          strokes: const [],
          images: const [],
          page: newPages[i],
        ),
      );
    }

    coreInfo.pages.add(emptyPage);
    if (mounted) setState(() {});

    if (mounted) {
      try {
        _cachedTheme = Theme.of(context);
        _cachedMediaQuery = MediaQuery.of(context);
      } catch (e) {
        log.warning(
          'Failed to update cached UI dependencies after PDF import: $e',
        );
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        final path = '${coreInfo.filePath}${Editor.extension}.p';

        if (File(path).existsSync()) {
          log.info('PDF thumbnail already exists. Skipping generation.');
          _markThumbnailWritten(coreInfo.calculateFirstPageHash());
          return;
        }

        log.info('Waiting for PDF content to render before thumbnail...');

        try {
          await firstPageRendered.future.timeout(const Duration(seconds: 4));
        } catch (_) {
          log.warning(
            'Timeout waiting for PDF onLoad. Trying to capture anyway.',
          );
        }

        await Future.delayed(const Duration(milliseconds: 300));

        if (!mounted) return;

        log.info('Generating PDF thumbnail via PostFrameCallback (Ready)');
        final theme = _cachedTheme ?? Theme.of(context);
        final mediaQuery = _cachedMediaQuery ?? MediaQuery.of(context);

        await _generateAndSaveThumbnail(
          theme: theme,
          mediaQuery: mediaQuery,
          destinationPath: path,
        );

        _markThumbnailWritten(coreInfo.calculateFirstPageHash());
      } catch (e, stackTrace) {
        log.warning('Failed to generate PDF thumbnail: $e', e, stackTrace);
      }
    });

    unawaited(
      saveToFile(force: true, updateThumbnail: false).catchError((e) {
        log.warning('Background save after PDF import failed: $e');
      }),
    );

    return true;
  }

  Future<Uint8List?> _captureThumbnailBytesFromFirstPage() async {
    if (coreInfo.pages.isEmpty) return null;
    try {
      final state = coreInfo.pages.first.innerCanvasKey.currentState;
      if (state is! InnerCanvasState) return null;
      final bytes = await state.captureThumbnail();
      return (bytes != null && bytes.isNotEmpty) ? bytes : null;
    } catch (e) {
      log.fine('Pre-capturing thumbnail failed: $e');
      return null;
    }
  }

  Future<bool> _generateAndSaveThumbnail({
    required ThemeData theme,
    required MediaQueryData mediaQuery,
    required String destinationPath,
  }) async {
    if (coreInfo.pages.isEmpty) return false;

    try {
      final page = coreInfo.pages.first;
      final state = page.innerCanvasKey.currentState;

      if (state is InnerCanvasState) {
        final bytes = await state.captureThumbnail();

        if (bytes != null && bytes.isNotEmpty) {
          await FileManager.writeFile(
            destinationPath,
            bytes,
            awaitWrite: false,
          );
          log.info(
            'Thumbnail saved via InnerCanvas capture: ${bytes.length} bytes',
          );
          return true;
        }
      } else {
        log.fine(
          'InnerCanvas not mounted for first page, using headless fallback',
        );
      }
    } catch (e) {
      log.warning('Thumbnail generation failed: $e');
    }
    return false;
  }

  Future paste() async => pasteAt();

  Future pasteAt({Offset? position}) async {
    final reader = await SystemClipboard.instance?.read();
    if (reader == null) return;

    if (reader.canProvide(Editor.saberSelectionFormat)) {
      final completer = Completer<Uint8List?>();
      reader.getFile(Editor.saberSelectionFormat, (file) async {
        try {
          completer.complete(await file.readAll());
        } catch (e) {
          log.severe('Failed to read saber selection format: $e');
          completer.complete(null);
        }
      });

      final bsonData = await completer.future;
      if (bsonData != null) {
        final Map<String, dynamic> saberData = BsonCodec.deserialize(
          BsonBinary.from(bsonData),
        );
        if (toIntSafe(saberData['v']) == 1) {
          final int sbnVersion =
              toIntSafe(saberData['sbnVersion']) ?? EditorCoreInfo.sbnVersion;
          final List<Uint8List> inlineAssets =
              (saberData['assets'] as List<dynamic>?)
                  ?.map((a) => (a as BsonBinary).byteList)
                  .toList() ??
              [];

          final List<dynamic> strokesJson = saberData['strokes'] ?? [];
          final List<dynamic> imagesJson = saberData['images'] ?? [];

          final List<Stroke> pastedStrokes = [];
          final List<EditorImage> pastedImages = [];

          final pageIndex =
              onWhichPageIsFocalPoint(position ?? Offset.zero) ??
              currentPageIndex;
          final page = coreInfo.pages[pageIndex];

          for (final json in strokesJson) {
            pastedStrokes.add(
              Stroke.fromJson(
                Map<String, dynamic>.from(json),
                fileVersion: sbnVersion,
                pageIndex: pageIndex,
                page: page,
              ),
            );
          }

          for (final json in imagesJson) {
            try {
              final assetIndexJson = json['a'] as int?;
              if (assetIndexJson != null && inlineAssets.isNotEmpty) {
                if (assetIndexJson < 0 ||
                    assetIndexJson >= inlineAssets.length) {
                  log.warning(
                    'Invalid asset index $assetIndexJson for inlineAssets of length ${inlineAssets.length}',
                  );
                  continue;
                }
              }

              final img = EditorImage.fromJson(
                Map<String, dynamic>.from(json),
                inlineAssets: inlineAssets.isEmpty ? null : inlineAssets,
                sbnPath: coreInfo.filePath,
                assetCacheAll: coreInfo.assetCacheAll,
              );
              img.pageIndex = pageIndex;
              img.onMoveImage = onMoveImage;
              img.onDeleteImage = onDeleteImage;
              img.onMiscChange = autosaveAfterDelay;
              pastedImages.add(img);
            } catch (e) {
              log.severe('Failed to parse pasted image: $e');
            }
          }

          if (pastedStrokes.isNotEmpty || pastedImages.isNotEmpty) {
            if (position != null) {
              final localPos = _safelyGetLocalPosition(pageIndex, position);
              final selectResult = SelectResult(
                pageIndex: pageIndex,
                strokes: pastedStrokes,
                images: pastedImages,
                path: Path(),
                pageIndexStart: pageIndex,
              );
              final bounds = selectResult.getBounds();
              final delta = localPos - bounds.center;
              for (final s in pastedStrokes) {
                s.shift(delta);
              }
              for (final i in pastedImages) {
                i.dstRect = i.dstRect.shift(delta);
              }
            }

            createPage(pageIndex);

            history.recordChange(
              EditorHistoryItem(
                type: .draw,
                pageIndex: pageIndex,
                strokes: pastedStrokes,
                images: pastedImages,
              ),
            );

            final allItems = <Object>[];
            allItems.addAll(pastedStrokes);
            allItems.addAll(pastedImages);

            Rect? newBounds;
            if (allItems.isNotEmpty) {
              double minX = double.infinity;
              double maxX = double.negativeInfinity;
              double minY = double.infinity;
              double maxY = double.negativeInfinity;

              for (final stroke in pastedStrokes) {
                final polygon = stroke.highQualityPolygon;
                if (polygon.isNotEmpty) {
                  for (final pt in polygon) {
                    minX = math.min(minX, pt.dx);
                    maxX = math.max(maxX, pt.dx);
                    minY = math.min(minY, pt.dy);
                    maxY = math.max(maxY, pt.dy);
                  }
                }
              }

              for (final image in pastedImages) {
                final imgBounds = image.dstRect;
                minX = math.min(minX, imgBounds.left);
                maxX = math.max(maxX, imgBounds.right);
                minY = math.min(minY, imgBounds.top);
                maxY = math.max(maxY, imgBounds.bottom);
              }

              if (minX.isFinite &&
                  maxX.isFinite &&
                  minY.isFinite &&
                  maxY.isFinite) {
                newBounds = Rect.fromLTRB(minX, minY, maxX, maxY);
              }
            }

            final newSelectResult = SelectResult(
              pageIndex: pageIndex,
              pageIndexStart: pageIndex,
              strokes: List.from(pastedStrokes),
              images: List.from(pastedImages),
              path: (newBounds != null && !newBounds.isEmpty)
                  ? (Path()..addRect(newBounds))
                  : Path(),
              displayBounds: newBounds,
            );

            setState(() {
              page.strokes.addAll(pastedStrokes);

              if (page.strokeSpatialIndex != null) {
                for (final s in pastedStrokes) {
                  page.strokeSpatialIndex!.insert(s);
                }
              }

              page.images.addAll(pastedImages);

              Select.currentSelect.unselect();
              Select.currentSelect.selectResult = newSelectResult;
              Select.currentSelect.doneSelecting = true;
              currentTool = Select.currentSelect;
            });
            if (coreInfo.isInfinite) {
              _fitInfiniteCanvasToContent(page);
            }
            autosaveAfterDelay();
            return;
          }
        }
      }
    }

    log.info('[Paste] Verificando clipboard para imagens...');
    const Map<SimpleFileFormat, String> formats = {
      Formats.jpeg: '.jpeg',
      Formats.png: '.png',
      Formats.gif: '.gif',
      Formats.tiff: '.tiff',
      Formats.bmp: '.bmp',
      Formats.ico: '.ico',
      Formats.svg: '.svg',
      Formats.webp: '.webp',
    };

    final List<_PhotoInfo> photoInfos = [];
    final List<ReadProgress> progresses = [];

    for (final format in formats.keys) {
      if (!reader.canProvide(format)) continue;

      log.info('[Paste] Formato detectado no clipboard: ${formats[format]}');

      final progress = reader.getFile(format, (file) async {
        try {
          log.info('[Paste] Lendo bytes do arquivo do clipboard...');
          final stream = file.getStream();
          final List<int> bytes = [];
          await for (final chunk in stream) {
            bytes.addAll(chunk);
          }

          if (bytes.isEmpty) {
            log.warning(
              '[Paste] Arquivo vazio no clipboard: $file (${formats[format]})',
            );
            return;
          }

          String extension;
          if (file.fileName != null && file.fileName!.contains('.')) {
            extension = file.fileName!.substring(
              file.fileName!.lastIndexOf('.'),
            );
          } else {
            extension = formats[format]!;
          }

          log.info(
            '[Paste] Imagem extraída: ${bytes.length} bytes, extensão: $extension',
          );
          photoInfos.add((
            bytes: Uint8List.fromList(bytes),
            extension: extension,
            path: file.fileName ?? 'clipboard',
            fileInfo: null,
            invertible: false,
          ));
        } catch (e) {
          log.severe('[Paste] Erro ao ler imagem do clipboard: $e');
        }
      });

      if (progress != null) progresses.add(progress);
    }

    log.info(
      '[Paste] Aguardando carregamento de ${progresses.length} arquivo(s)...',
    );
    while (progresses.isNotEmpty) {
      progresses.removeWhere((progress) => progress.fraction.value == 1);
      await Future.delayed(const Duration(milliseconds: 50));
    }

    if (photoInfos.isNotEmpty) {
      log.info(
        '[Paste] ${photoInfos.length} imagem(ns) encontrada(s). Iniciando importação...',
      );

      await _pickPhotos(photoInfos: photoInfos, dropPosition: position);
      return;
    } else {
      log.info('[Paste] Nenhuma imagem encontrada no clipboard');
    }

    if (reader.canProvide(Formats.plainText)) {
      final textCompleter = Completer<String?>();
      reader.getValue(Formats.plainText, (value) {
        try {
          textCompleter.complete(value);
        } catch (e) {
          log.warning('Failed to read text clipboard: $e');
          textCompleter.complete(null);
        }
      });

      final text = await textCompleter.future;
      if (text != null && text.isNotEmpty) {
        _insertTextOnPage(text, position);
        return;
      }
    }
  }

  void _insertTextOnPage(String text, Offset? position) {
    if (coreInfo.readOnly) return;

    final pageIndex = position != null
        ? (onWhichPageIsFocalPoint(position) ?? currentPageIndex)
        : currentPageIndex;

    final page = coreInfo.pages[pageIndex];
    final quillController = page.quill.controller;

    final index = quillController.selection.baseOffset >= 0
        ? quillController.selection.baseOffset
        : quillController.document.length;

    final currentDelta = quillController.document.toDelta();

    final insertDelta = currentDelta
      ..retain(index)
      ..insert('$text\n');
    final newDelta = currentDelta.compose(insertDelta);
    quillController.document = flutter_quill.Document.fromDelta(newDelta);

    quillController.updateSelection(
      TextSelection.collapsed(offset: index + text.length + 1),
      flutter_quill.ChangeSource.local,
    );

    autosaveAfterDelay();

    if (currentTool != Tool.textEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          page.quill.focusNode.unfocus();

          SystemChannels.textInput.invokeMethod('TextInput.hide');
        }
      });
    }
  }

  Future _showExportDialog(
    BuildContext context, {
    ExportFormat initialFormat = ExportFormat.pdf,
  }) async {
    final editorContext = context;
    await showDialog(
      context: context,
      builder: (dialogContext) => ExportDialog(
        coreInfo: coreInfo,
        currentPageIndex: currentPageIndex,
        initialFormat: initialFormat,
        parentContext: editorContext,
      ),
    );
  }

  Future exportAsPng(BuildContext context) async {
    await _showExportDialog(context, initialFormat: ExportFormat.png);
  }

  Future exportAsPdf(BuildContext context) async {
    await _showExportDialog(context, initialFormat: ExportFormat.pdf);
  }

  Future exportAsSba(BuildContext context) async {
    final selfPath = coreInfo.filePath;
    final hasExternalLinks =
        coreInfo.links.isNotEmpty &&
        coreInfo.links.any((l) => isExternalNoteLink(l, selfPath));
    final mode = await showSbaExportModeDialog(
      context,
      hasExternalLinks: hasExternalLinks,
    );
    if (!mode.ok || !context.mounted) return;
    if (mode.shareLinks && stows.defaultExportPath.value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.export.defaultExportPathRequired)),
      );
      return;
    }
    var infoToSave = coreInfo;
    if (mode.shareLinks) {
      infoToSave = await expandLinksForShare(coreInfo, true);
      if (!context.mounted) return;
    }
    final saveToPath = stows.defaultExportPath.value.isNotEmpty
        ? stows.defaultExportPath.value
        : null;
    final fileName = '${coreInfo.fileName}.sba';
    Future<void> doExport() async {
      final sba = await infoToSave.saveToSba(
        currentPageIndex: currentPageIndex,
        omitLinksForExport: !mode.shareLinks,
        includeExportMetadata: mode.includeExportMetadata,
      );
      if (!context.mounted) return;
      List<int> bytes = sba;
      if (mode.password != null) {
        bytes = await SbaEncryption.encryptForExport(
          Uint8List.fromList(sba),
          mode.password!,
        );
      }
      await FileManager.exportFile(
        fileName,
        bytes,
        saveToPath: saveToPath,
        context: context,
      );
    }

    if (saveToPath != null) {
      await ExportManager.exportInBackground(t.export.exportingNote, (
        onProgress,
      ) async {
        onProgress(0.5, fileName);
        await doExport();
        onProgress(1.0, t.export.exportComplete);
      });
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t.export.exportComplete)));
      }
    } else {
      await ExportManager.exportInBackground(t.export.exportingNote, (
        onProgress,
      ) async {
        onProgress(0.5, fileName);
        await doExport();
        onProgress(1.0, t.export.exportComplete);
      });
    }
  }

  Future<void> _showCanvasMenu(Offset globalPos) async {
    if (_isCanvasMenuOpen) return;
    _isCanvasMenuOpen = true;

    _toolbarKey.currentState?.hideAllCards();

    String? menuSelected;
    var tempSelection = false;

    try {
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) return;

      final pageIndex = onWhichPageIsFocalPoint(globalPos) ?? currentPageIndex;
      final page = coreInfo.pages[pageIndex];

      final pagePos = _safelyGetLocalPosition(pageIndex, globalPos);

      final select = Select.currentSelect;

      EditorImage? pressedImage;
      for (final image in page.images.reversed) {
        if (image.contains(pagePos)) {
          pressedImage = image;
          break;
        }
      }

      tempSelection = false;
      final hasSingleSameImageSelection =
          select.doneSelecting &&
          select.selectResult.pageIndex == pageIndex &&
          select.selectResult.strokes.isEmpty &&
          select.selectResult.images.length == 1 &&
          identical(select.selectResult.images.first, pressedImage);

      if (pressedImage != null && !hasSingleSameImageSelection) {
        final targetImage = pressedImage;
        // Mutate selection without setState first so the menu can open on this
        // frame; paint selection chrome on the next frame.
        currentTool = Select.currentSelect;
        select.selectResult = SelectResult(
          pageIndex: pageIndex,
          pageIndexStart: pageIndex,
          strokes: [],
          images: [targetImage],
          path: Path()..addRect(targetImage.dstRect),
          displayBounds: targetImage.dstRect,
        );
        select.doneSelecting = true;
        tempSelection = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }

      final hasSelection =
          select.doneSelecting &&
          !select.selectResult.isEmpty &&
          select.selectResult.pageIndex == pageIndex;

      final menuItems = <Map<String, dynamic>>[];

      if (hasSelection) {
        if (select.selectResult.strokes.isNotEmpty) {
          menuItems.add({
            'value': 'to_text',
            'icon': Icons.text_fields_rounded,
            'label': t.editor.strokeToText,
          });
          menuItems.add({
            'value': 'selection_to_latex',
            'icon': Icons.text_snippet_rounded,
            'label': t.editor.selectionToLatex,
          });
          menuItems.add({
            'value': 'calculate',
            'icon': Icons.calculate_outlined,
            'label': 'Calculate',
          });
          menuItems.add({
            'value': 'change_color',
            'icon': Icons.palette_outlined,
            'label': t.editor.selectionBar.changeColor,
          });
          if (select.selectResult.strokes.any((s) => s.canConvertStrokeType)) {
            menuItems.add({
              'value': 'change_stroke_type',
              'icon': Icons.gesture_rounded,
              'label': t.editor.selectionBar.changeStrokeType,
            });
          }
          menuItems.add({'divider': true});
        }

        if (select.selectResult.images.isNotEmpty) {
          final anyUnlocked = select.selectResult.images.any(
            (img) => !img.locked,
          );

          if (anyUnlocked) {
            menuItems.add({
              'value': 'lock',
              'icon': Icons.lock_outline_rounded,
              'label': 'Lock Image',
            });
          } else {
            menuItems.add({
              'value': 'unlock',
              'icon': Icons.lock_open_rounded,
              'label': 'Unlock Image',
              'primary': true,
            });
          }
          menuItems.add({'divider': true});
          if (select.selectResult.images.length == 1 &&
              select.selectResult.strokes.isEmpty) {
            final image = select.selectResult.images.first;
            if (image is PngEditorImage) {
              menuItems.add({
                'value': 'crop_image',
                'icon': Icons.crop_rounded,
                'label': 'Crop image',
              });
            }
            menuItems.add({
              'value': 'set_background',
              'icon': Icons.wallpaper_rounded,
              'label': 'Set as background',
            });
            menuItems.add({'divider': true});
          }
        }

        if (select.selectResult.images.isNotEmpty) {
          menuItems.add({
            'value': 'share',
            'icon': Icons.share_rounded,
            'label': t.editor.selectionBar.share,
          });
        }
        if (select.selectResult.strokes.isNotEmpty) {
          menuItems.add({
            'value': 'share_as_svg',
            'icon': Icons.share_rounded,
            'label': t.editor.selectionBar.shareAsSvg,
          });
        }
        if (select.selectResult.images.isNotEmpty ||
            select.selectResult.strokes.isNotEmpty) {
          menuItems.add({'divider': true});
        }
        menuItems.add({
          'value': 'copy',
          'icon': Icons.copy_rounded,
          'label': t.editor.selectionBar.copy,
        });
        menuItems.add({
          'value': 'cut',
          'icon': Icons.cut_rounded,
          'label': t.editor.selectionBar.cut,
        });
        menuItems.add({
          'value': 'duplicate',
          'icon': Icons.control_point_duplicate_rounded,
          'label': t.editor.selectionBar.duplicate,
        });

        if (select.selectResult.images.isNotEmpty) {
          menuItems.add({
            'value': 'invert',
            'icon': Icons.invert_colors_rounded,
            'label': t.editor.imageOptions.invertible,
          });
        }

        menuItems.add({'divider': true});
        menuItems.add({
          'value': 'delete',
          'icon': Icons.delete_outline_rounded,
          'label': t.editor.selectionBar.delete,
          'destructive': true,
        });
      }

      if (hasSelection) menuItems.add({'divider': true});
      menuItems.add({
        'value': 'paste',
        'icon': Icons.paste_rounded,
        'label': t.editor.selectionBar.paste,
        'primary': !hasSelection,
      });

      menuSelected = await showGeneralDialog<String>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Close Menu',
        barrierColor: Colors.transparent,
        transitionDuration: CanvasContextMenuFeel.openDuration,
        pageBuilder: (context, animation, secondaryAnimation) {
          final size = MediaQuery.sizeOf(context);

          double estHeight = 16;
          for (var item in menuItems) {
            if (item['divider'] == true)
              estHeight += 17;
            else
              estHeight += 48;
          }

          double left = globalPos.dx;
          double top = globalPos.dy;

          if (left + 230 > size.width - 16) left = size.width - 230 - 16;
          if (top + estHeight > size.height - 16) {
            top = globalPos.dy - estHeight - 8;
            if (top < 16) top = 16;
          }

          final isDark = Theme.of(context).brightness == Brightness.dark;
          final scheme = Theme.of(context).colorScheme;

          return Stack(
            children: [
              Positioned(
                left: left,
                top: top,
                child: Material(
                  color: Colors.transparent,
                  elevation: 0,
                  child: Container(
                    width: 230,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      // Solid surface: avoid BackdropFilter blur on open.
                      color: isDark
                          ? const Color(0xF02C2C2E)
                          : scheme.surface.withValues(alpha: 0.97),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.10),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: menuItems.map((item) {
                        if (item['divider'] == true) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                            ),
                            child: Divider(
                              height: 1,
                              color: (isDark ? Colors.white : Colors.black)
                                  .withValues(alpha: 0.1),
                            ),
                          );
                        }

                        final isDestructive = item['destructive'] == true;
                        final isPrimary = item['primary'] == true;

                        Color contentColor = scheme.onSurface;
                        if (isDestructive)
                          contentColor = scheme.error;
                        else if (isPrimary)
                          contentColor = scheme.primary;

                        return InkWell(
                          onTap: () =>
                              Navigator.pop(context, item['value']),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  item['icon'],
                                  size: 22,
                                  color: contentColor,
                                ),
                                const SizedBox(width: 14),
                                Text(
                                  item['label'],
                                  style: TextStyle(
                                    color: contentColor,
                                    fontWeight: isPrimary
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          final flipY =
              (globalPos.dy + (menuItems.length * 48)) >
              MediaQuery.sizeOf(context).height - 16;
          return CanvasContextMenuFeel.buildOpenTransition(
            animation: animation,
            alignment: flipY ? Alignment.bottomLeft : Alignment.topLeft,
            child: child,
          );
        },
      );
    } finally {
      _ignoreDragForMenu = false;
      _isCanvasMenuOpen = false;
    }

    if (!mounted) return;

    if (menuSelected == 'change_color') {
      await _showSelectionColorPicker();
    } else if (menuSelected == 'change_stroke_type') {
      await _showSelectionStrokeTypePicker();
    } else if (menuSelected == 'to_text') {
      await _exportSelectionStrokesToText();
    } else if (menuSelected == 'selection_to_latex') {
      await _exportSelectionStrokesToLatex();
    } else if (menuSelected == 'calculate') {
      await _solveSelectionMath();
    } else if (menuSelected == 'lock') {
      _toggleLockSelection(true);
    } else if (menuSelected == 'unlock') {
      _toggleLockSelection(false);
    } else if (menuSelected == 'crop_image') {
      await _cropSingleSelectedImage();
    } else if (menuSelected == 'set_background') {
      _setSelectionAsBackground();
    } else if (menuSelected == 'paste') {
      await pasteAt(position: globalPos);
    } else if (menuSelected == 'copy') {
      await _copySelectionToClipboard();
    } else if (menuSelected == 'cut') {
      await _cutSelectionToClipboard();
    } else if (menuSelected == 'delete') {
      deleteSelection();
    } else if (menuSelected == 'duplicate') {
      duplicateSelection();
    } else if (menuSelected == 'invert') {
      _toggleInvertibleSelection();
    } else if (menuSelected == 'share') {
      await _shareSelection();
    } else if (menuSelected == 'share_as_svg') {
      await _shareSelectionAsSvg();
    }

    if (menuSelected == null && tempSelection) {
      setState(() {
        Select.currentSelect.unselect();
      });
    }
  }

  Future<void> _solveSelectionMath() async {
    final select = Select.currentSelect;
    if (!select.doneSelecting || select.selectResult.strokes.isEmpty) return;
    if (coreInfo.readOnly) return;

    final page = coreInfo.pages[select.selectResult.pageIndex];

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final resultStrokes = await _mathSolver.processStrokes(
        select.selectResult.strokes,
        page,
        select.selectResult.pageIndex,
      );

      if (mounted) Navigator.pop(context);

      if (resultStrokes != null && resultStrokes.isNotEmpty) {
        setState(() {
          page.strokes.addAll(resultStrokes);
        });
        history.recordChange(
          EditorHistoryItem(
            type: .draw,
            pageIndex: select.selectResult.pageIndex,
            strokes: resultStrokes,
            images: [],
          ),
        );
        autosaveAfterDelay();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'It was not possible to solve the equation. Be sure to include the equal sign "=".',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.editor.failedToResolveEquation(error: e))),
        );
      }
    }
  }

  /// BCP-47 tag for ML Kit digital ink text models (matches app UI language).
  String _digitalInkLanguageCodeForAppLocale() {
    switch (LocaleSettings.currentLocale) {
      case AppLocale.ptBr:
        return 'pt-BR';
      case AppLocale.en:
        return 'en-US';
    }
  }

  Future<void> _presentHandwritingLatexExport({
    required Future<String?> Function() compute,
    String? dialogTitle,
  }) async {
    if (coreInfo.readOnly) return;
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final result = await compute();
      if (mounted) Navigator.pop(context);
      if (result == null || result.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t.editor.couldNotRecognizeText)),
          );
        }
        return;
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          final textCtrl = TextEditingController(text: result);
          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                width: 520,
                constraints: const BoxConstraints(maxHeight: 620),
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Theme.of(
                    dialogContext,
                  ).colorScheme.surface.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.grey.withOpacity(0.3),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 40,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      dialogTitle ?? t.editor.recognizedLatexTitle,
                      style: Theme.of(dialogContext).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: textCtrl,
                      maxLines: null,
                      autofocus: true,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey.withOpacity(0.1),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            if (mounted) Navigator.pop(dialogContext);
                          },
                          child: Text(t.common.cancel),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: textCtrl.text),
                            );
                            if (mounted) {
                              Navigator.pop(dialogContext);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(t.editor.copyToClipboard),
                                ),
                              );
                            }
                          },
                          child: Text(t.editor.copy),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.editor.recognitionError(error: e))),
        );
      }
    }
  }

  Future<void> _exportSelectionStrokesToText() async {
    final select = Select.currentSelect;
    if (!select.doneSelecting || select.selectResult.strokes.isEmpty) return;
    if (coreInfo.readOnly) return;
    final strokes = List<Stroke>.from(select.selectResult.strokes);
    await _presentHandwritingLatexExport(
      dialogTitle: t.editor.strokeToText,
      compute: () => _recognitionService.recognizeTextStrokes(
        strokes,
        languageCode: _digitalInkLanguageCodeForAppLocale(),
      ),
    );
  }

  Future<void> _exportSelectionStrokesToLatex() async {
    final select = Select.currentSelect;
    if (!select.doneSelecting || select.selectResult.strokes.isEmpty) return;
    if (coreInfo.readOnly) return;
    final strokes = List<Stroke>.from(select.selectResult.strokes);
    await _presentHandwritingLatexExport(
      compute: () => _recognitionService.strokesToCombinedLatexText(
        strokes: strokes,
        textLanguageCode: _digitalInkLanguageCodeForAppLocale(),
      ),
    );
  }

  Future<void> _exportNoteHandwritingToLatex() async {
    if (coreInfo.readOnly) return;
    await _presentHandwritingLatexExport(
      compute: () async {
        final lang = _digitalInkLanguageCodeForAppLocale();
        final parts = <String>[];
        for (var i = 0; i < coreInfo.pages.length; i++) {
          final page = coreInfo.pages[i];
          if (page.strokes.isEmpty) continue;
          final chunk = await _recognitionService.strokesToCombinedLatexText(
            strokes: page.strokes,
            textLanguageCode: lang,
          );
          if (chunk != null && chunk.trim().isNotEmpty) {
            parts.add('% Page ${i + 1}\n$chunk');
          }
        }
        if (parts.isEmpty) return null;
        return parts.join('\n\n');
      },
    );
  }

  List<Widget> _buildNoteLinkBackActions() {
    if (_noteLinkBackStack.isEmpty) return const [];
    return [
      IconButton(
        icon: const AdaptiveIcon(
          icon: Icons.arrow_back_rounded,
          cupertinoIcon: CupertinoIcons.back,
        ),
        tooltip: _noteLinkBackStack.length == 1
            ? 'Back to previous note'
            : 'Back (${_noteLinkBackStack.length})',
        onPressed: _noteLinkNavBusy ? null : () => unawaited(_popNoteLinkHistory()),
      ),
    ];
  }

  PreferredSizeWidget _buildEditorAppBar(
    BuildContext context, {
    ValueNotifier<SavingState>? savingStateOverride,
    Future<void> Function({bool force})? triggerSaveOverride,
    List<Widget> extraActions = const [],
    VoidCallback? onBackOverride,
  }) {
    final effectiveSavingState = savingStateOverride ?? savingState;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final actions = <Widget>[
      ..._buildNoteLinkBackActions(),
      
      if (!coreInfo.isInfinite)
        PopupMenuButton<String>(
          icon: const Icon(Icons.add_outlined),
          tooltip: "Insert page",
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          offset: const Offset(0, 48),
          onSelected: (value) {
            final currentIdx = currentPageIndex;
            if (value == 'above') {
              insertPageBefore(currentIdx);
              CanvasGestureDetector.scrollToPage(
                pageIndex: currentIdx,
                pageOffsets: _generatePageOffsets(coreInfo.pages, _currentViewportWidth()),
                transformationController: _transformationController,
              );
            } else if (value == 'below') {
              insertPageAfter(currentIdx);
              CanvasGestureDetector.scrollToPage(
                pageIndex: currentIdx + 1,
                pageOffsets: _generatePageOffsets(coreInfo.pages, _currentViewportWidth()),
                transformationController: _transformationController,
              );
            }
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              value: 'above',
              child: Row(
                children: [
                  Icon(CupertinoIcons.arrow_up_circle, color: colorScheme.onSurface),
                  const SizedBox(width: 12),
                  const Text('Page above'),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'below',
              child: Row(
                children: [
                  Icon(CupertinoIcons.arrow_down_circle, color: colorScheme.onSurface),
                  const SizedBox(width: 12),
                  const Text('Page below'),
                ],
              ),
            ),
          ],
        ),

      // Botão Pages na AppBar visível APENAS no modo Split View (embedded == true)
      if (!coreInfo.isInfinite && widget.embedded)
        IconButton(
          icon: const Icon(Icons.article_outlined), 
          tooltip: 'Pages',
          isSelected: _dockedSidePanel == _EditorDockedSidePanel.pages,
          onPressed: () => _toggleDockedSidePanel(_EditorDockedSidePanel.pages),
        ),

      IconButton(
        icon: const Icon(Icons.more_vert_rounded),
        tooltip: t.home.tabs.settings,
        isSelected: _dockedSidePanel == _EditorDockedSidePanel.settings,
        onPressed: () => _toggleDockedSidePanel(_EditorDockedSidePanel.settings),
      ),
    ];

    if (extraActions.isNotEmpty) {
      actions.addAll(extraActions);
    }

    return AppBar(
      primary: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : colorScheme.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 64,
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: onBackOverride ?? () {
          if (mounted) _goToHome(this.context);
        },
      ),
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Form(
            key: _filenameFormKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: TextFormField(
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w400,
                  fontSize: 18,
                ),
                controller: filenameTextEditingController,
                onChanged: renameFile,
                autofocus: needsNaming,
                validator: _validateFilenameTextField,
              ),
            ),
          ),
          ValueListenableBuilder<SavingState>(
            valueListenable: effectiveSavingState,
            builder: (context, state, _) {
              String statusText;
              IconData? statusIcon;
              switch (state) {
                case SavingState.saving:
                  statusText = 'Saving...';
                  statusIcon = Icons.cloud_upload_outlined;
                  break;
                case SavingState.waitingToSave:
                  statusText = 'Pending changes';
                  statusIcon = Icons.edit_note_rounded;
                  break;
                case SavingState.saved:
                default:
                  statusText = 'All changes saved';
                  statusIcon = Icons.cloud_done_outlined;
                  break;
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(statusIcon, size: 12, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    statusText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      actions: actions,
    );
  }

  Widget _buildEditorBody({
    required Widget canvas,
    required Widget toolbar,
    required Widget? readonlyBanner,
    required bool isToolbarVertical,
    required bool showToolbar,
  }) {
    if (!showToolbar) {
      return Column(
        children: [
          Expanded(child: canvas),
          if (readonlyBanner != null) readonlyBanner,
        ],
      );
    }

    if (isToolbarVertical) {
      return Row(
        textDirection: stows.editorToolbarAlignment.value == AxisDirection.left
            ? TextDirection.ltr
            : TextDirection.rtl,
        children: [
          toolbar,
          Expanded(
            child: Column(
              children: [
                Expanded(child: canvas),
                if (readonlyBanner != null) readonlyBanner,
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      verticalDirection: stows.editorToolbarAlignment.value == AxisDirection.up
          ? VerticalDirection.up
          : VerticalDirection.down,
      children: [
        Expanded(child: canvas),
        toolbar,
        if (readonlyBanner != null) readonlyBanner,
      ],
    );
  }

  Widget _buildSplitGlobalToolbar(
    BuildContext context, {
    VoidCallback? onHostToolbarChanged,
  }) {
    final isToolbarVertical =
        stows.editorToolbarAlignment.value == AxisDirection.left ||
        stows.editorToolbarAlignment.value == AxisDirection.right;
    final brightness = Theme.brightnessOf(context);
    final invert = brightness == Brightness.dark
        ? (stows.noteInvertInDarkModeOverrides.value[coreInfo.filePath] == 1)
        : false;
    void notifyHostToolbarChanged() {
      onHostToolbarChanged?.call();
    }

    return Collapsible(
      axis: isToolbarVertical
          ? CollapsibleAxis.horizontal
          : CollapsibleAxis.vertical,
      collapsed: false,
      maintainState: true,
      child: SafeArea(
        bottom: stows.editorToolbarAlignment.value != AxisDirection.up,
        child: EnhancedToolbar(
          key: _toolbarKey,
          readOnly: coreInfo.readOnly,
          setTool: (tool) {
            setState(() {
              if (tool is Eraser) {
                if (currentTool is! Eraser) {
                  tmpTool = currentTool;
                }
              } else if (tool is Select && currentTool is Pen) {
                _lastPenTool = currentTool;
              }

              currentTool = tool;

              if (currentTool is Highlighter) {
                Highlighter.currentHighlighter = currentTool as Highlighter;
              } else if (currentTool is Pen) {
                Pen.currentPen = currentTool as Pen;
              }
            });
            notifyHostToolbarChanged();
          },
          currentTool: currentTool,
          undo: undo,
          isUndoPossible: history.canUndo,
          redo: redo,
          isRedoPossible: history.canRedo,
          paste: paste,
          duplicateSelection: duplicateSelection,
          deleteSelection: deleteSelection,
          copyToClipboard: _copySelectionToClipboard,
          cutToClipboard: _cutSelectionToClipboard,
          toggleInvertible: _toggleInvertibleSelection,
          exportAsSba: (_) => exportAsSba(context),
          exportAsPdf: (_) => exportAsPdf(context),
          exportAsPng: (_) => exportAsPng(context),
          onToggleCalculator: () {
            if (_calculatorOverlay == null) {
              _showCalculator();
            } else {
              _hideCalculator();
            }
          },
          onManageTagsAndLinks: _showTagsAndLinksDialog,
          onRegionScreenshot: _toggleRegionScreenshotMode,
          regionScreenshotActive: _regionScreenshotMode,
          quillFocus: quillFocus,
          applyPenPresetStrokeWidth: coreInfo.readOnly
              ? (_) {}
              : _applyPenPresetStrokeWidth,
          onPenPresetNoteDirty: coreInfo.readOnly ? () {} : autosaveAfterDelay,
          setColor: (color) {
            setState(() {
              updateColorBar(color);

              if (currentTool is Highlighter) {
                final h = currentTool as Highlighter;
                h.color = color.withValues(
                  alpha: stows.highlighterOpacity.value,
                );
                stows.lastHighlighterColor.value = h.color.toARGB32();
              } else if (currentTool is ShapeTool) {
                final tool = currentTool as ShapeTool;
                tool.color = color;
                tool.fillColor = color.withOpacity(0.7);
              } else if (currentTool is Pen) {
                final pen = currentTool as Pen;
                pen.color = color;
                switch (pen.toolId) {
                  case ToolId.fountainPen:
                    stows.lastFountainPenColor.value = color.toARGB32();
                    break;
                  case ToolId.ballpointPen:
                    stows.lastBallpointPenColor.value = color.toARGB32();
                    break;
                  case ToolId.calligraphyPen:
                    stows.lastCalligraphyPenColor.value = color.toARGB32();
                    break;
                  case ToolId.advancedPen:
                    stows.lastAdvancedPenColor.value = color.toARGB32();
                  case ToolId.advancedPencil:
                    stows.lastAdvancedPencilColor.value = color.toARGB32();
                    break;
                  default:
                    break;
                }
              } else if (currentTool is Select) {
                final select = currentTool as Select;
                if (select.doneSelecting) {
                  final strokes = select.selectResult.strokes;
                  final colorChange = <Stroke, ColorChange>{};
                  for (final stroke in strokes) {
                    final newColor = stroke.toolId == ToolId.highlighter
                        ? color
                        : color;
                    colorChange[stroke] = ColorChange(
                      previous: stroke.color,
                      current: newColor,
                    );
                    stroke.color = newColor;
                  }

                  history.recordChange(
                    EditorHistoryItem(
                      type: EditorHistoryItemType.changeColor,
                      pageIndex: strokes.first.pageIndex,
                      strokes: strokes,
                      colorChange: colorChange,
                      images: [],
                    ),
                  );
                  autosaveAfterDelay();
                }

                if (_lastPenTool != null) {
                  currentTool = _lastPenTool!;
                  if (currentTool is Pen) {
                    (currentTool as Pen).color = color;
                    final pen = currentTool as Pen;
                    switch (pen.toolId) {
                      case ToolId.fountainPen:
                        stows.lastFountainPenColor.value = color.toARGB32();
                        break;
                      case ToolId.ballpointPen:
                        stows.lastBallpointPenColor.value = color.toARGB32();
                        break;
                      case ToolId.calligraphyPen:
                        stows.lastCalligraphyPenColor.value = color.toARGB32();
                        break;
                      default:
                        break;
                    }
                  } else if (currentTool is Highlighter) {
                    (currentTool as Highlighter).color = color;
                  }
                }
              } else if (currentTool is Eraser || currentTool is LaserPointer) {
                if (_lastPenTool != null) {
                  currentTool = _lastPenTool!;
                  if (currentTool is Pen) {
                    (currentTool as Pen).color = color;
                    final pen = currentTool as Pen;
                    switch (pen.toolId) {
                      case ToolId.fountainPen:
                        stows.lastFountainPenColor.value = color.toARGB32();
                        break;
                      case ToolId.ballpointPen:
                        stows.lastBallpointPenColor.value = color.toARGB32();
                        break;
                      case ToolId.calligraphyPen:
                        stows.lastCalligraphyPenColor.value = color.toARGB32();
                        break;
                      case ToolId.advancedPen:
                        stows.lastAdvancedPenColor.value = color.toARGB32();
                      case ToolId.advancedPencil:
                        stows.lastAdvancedPencilColor.value = color.toARGB32();
                        break;
                      default:
                        break;
                    }
                  } else if (currentTool is Highlighter) {
                    (currentTool as Highlighter).color = color;
                  }
                }
              }
            });
            _captureNoteToolSettingsLocally();
            notifyHostToolbarChanged();
          },
          onColorChanged: updateColorBar,
          onToolbarSlotsChanged: _captureNoteToolSettingsLocally,
          invert: invert,
          axis: isToolbarVertical ? Axis.vertical : Axis.horizontal,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ColorScheme.of(context);
    final isToolbarVertical =
        stows.editorToolbarAlignment.value == AxisDirection.left ||
        stows.editorToolbarAlignment.value == AxisDirection.right;

    final Widget canvas = Stack(
      children: [
        RepaintBoundary(
          key: _regionScreenshotBoundaryKey,
          child: CanvasGestureDetector(
            key: _canvasGestureDetectorKey,
            filePath: coreInfo.filePath,
            isInfinite: coreInfo.isInfinite,
            skipTransformClampForExpansion: _skipTransformClampForExpansion,
            suppressTransformClamp: _suppressTransformClamp,
            onContainerBoundsChanged: _onCanvasContainerBoundsChanged,
            isDrawGesture: isDrawGesture,
            onInteractionEnd: onInteractionEnd,
            onDrawStart: onDrawStart,
            onDrawUpdate: onDrawUpdate,
            onDrawEnd: onDrawEnd,
            shouldInjectRawPointerSamplesForDraw:
                shouldInjectRawPointerSamplesForDraw,
            onRawPointerMoveForDraw: onRawPointerMoveForDraw,
            onPointerUpOrCancel: _finishActivePenStrokeFromPointerEnd,
            onHovering: onHovering,
            onHoveringEnd: onHoveringEnd,
            onStylusButtonChanged: onStylusButtonChanged,
            onLongPress: _showCanvasMenu,
            onSecondaryTapDown: _showCanvasMenu,
            onTapDown: (globalPos) async {
              _toolbarKey.currentState?.hideAllCards();

              final primaryFocus = FocusManager.instance.primaryFocus;
              final isTextEditingActive = currentTool == Tool.textEditing;

              bool isTextFieldFocused = false;
              if (primaryFocus != null && primaryFocus.context != null) {
                try {
                  final widget = primaryFocus.context!.widget;

                  isTextFieldFocused = widget is EditableText;
                } catch (e) {
                  isTextFieldFocused = false;
                }
              }

              if (!isTextEditingActive && !isTextFieldFocused) {
                primaryFocus?.unfocus();

                SystemChannels.textInput.invokeMethod('TextInput.hide');
              }

              if (_previewPdfDocument != null) {
                _hidePdfEquationPreview();
                return;
              }

              if (_imageCropState != null) {
                final cropPageIndex = coreInfo.pages.indexWhere(
                  (p) => p.images.contains(_imageCropState!.image),
                );
                if (cropPageIndex >= 0) {
                  final position = _safelyGetLocalPosition(
                    cropPageIndex,
                    globalPos,
                  );
                  if (!_imageCropState!.image.dstRect.contains(position)) {
                    await _applyImageCrop(
                      _imageCropState!.image,
                      _imageCropState!.normalizedCrop,
                    );
                    return;
                  }
                }
              }

              if (lastSeenPointerCount > 1) {
                if (currentTool is Select ||
                    currentTool is LaserPointer ||
                    currentTool == Tool.textEditing ||
                    !stows.enableFingerDrawing.value) {
                  await _handlePotentialPdfLinkTap(globalPos);
                }
                return;
              }

              final tapPageIndex = onWhichPageIsFocalPoint(globalPos);
              if (tapPageIndex != null &&
                  tapPageIndex >= 0 &&
                  tapPageIndex < coreInfo.pages.length) {
                final page = coreInfo.pages[tapPageIndex];
                final position = _safelyGetLocalPosition(
                  tapPageIndex,
                  globalPos,
                );
                for (final image in page.images.reversed) {
                  if (!image.contains(position)) continue;
                  final plotMetadata = _plotMetadataFromImage(image);
                  if (plotMetadata != null &&
                      _isTapOnAnimationPlayButton(
                        image: image,
                        position: position,
                      )) {
                    _showPlotVisualizer(plotMetadata);
                    return;
                  }
                }
              }

              final select = Select.currentSelect;
              if (select.doneSelecting && !select.selectResult.isEmpty) {
                final pageIndex = dragPageIndex ?? currentPageIndex;
                if (select.selectResult.pageIndex == pageIndex) {
                  final page = coreInfo.pages[pageIndex];
                  final box = page.renderBox;
                  if (box != null && box.attached) {
                    final localPos = box.globalToLocal(globalPos);
                    if (select.selectResult.contains(localPos)) {
                      return;
                    } else {
                      Select.currentSelect.unselect();
                      setState(() {
                        _selectionHandlesInteractionMode =
                            SelectionHandlesInteractionMode.resize;
                      });
                      if (currentTool is Select ||
                          currentTool is LaserPointer ||
                          currentTool == Tool.textEditing ||
                          !stows.enableFingerDrawing.value) {
                        await _handlePotentialPdfLinkTap(globalPos);
                      }
                      return;
                    }
                  }
                }
              }

              if (currentTool is Select ||
                  currentTool is LaserPointer ||
                  currentTool == Tool.textEditing ||
                  !stows.enableFingerDrawing.value) {
                await _handlePotentialPdfLinkTap(globalPos);
              }
            },
            updatePointerData: updatePointerData,
            onPointerDown: (event) {
              _markCanvasInputActivity(cancelPendingAutosave: true);
              _toolbarKey.currentState?.hideAllCards();
              _scrollPhysicsStopNotifier.value++;
            },
            undo: undo,
            redo: redo,
            pages: coreInfo.pages,
            initialPageIndex: coreInfo.initialPageIndex,

            pageBuilder: pageBuilder,
            isTextEditing: _isEditorTextEditingMode,
            placeholderPageBuilder: _editorPlaceholderPageBuilder,
            tryHydratePage: _tryIdleHydratePage,
            onMaintainPageRasterBand: _maintainPageRasterBand,
            transformationController: _transformationController,
            scrollPhysicsStopNotifier: _scrollPhysicsStopNotifier,
            pageLayoutWidthOverride: _pageLayoutWidthOverride,
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            return ThrottledListenableBuilder(
              listenable: _transformationController,
              builder: (context, child) {
                return Stack(
                  children: [
                    _AdaptiveScrollbar(
                      direction: Axis.vertical,
                      controller: _transformationController,
                      pages: coreInfo.pages,
                      screenHeight: constraints.maxHeight,
                      screenWidth: constraints.maxWidth,
                      isInfinite: coreInfo.isInfinite,
                      scrollPhysicsStopNotifier: _scrollPhysicsStopNotifier,
                    ),

                    if (coreInfo.isInfinite)
                      _AdaptiveScrollbar(
                        direction: Axis.horizontal,
                        controller: _transformationController,
                        pages: coreInfo.pages,
                        screenHeight: constraints.maxHeight,
                        screenWidth: constraints.maxWidth,
                        isInfinite: coreInfo.isInfinite,
                        scrollPhysicsStopNotifier: _scrollPhysicsStopNotifier,
                      ),
                  ],
                );
              },
            );
          },
        ),
        if (_regionScreenshotMode)
          Positioned.fill(
            child: RegionScreenshotOverlay(
              onCancel: _cancelRegionScreenshotMode,
              onSelected: _captureRegionScreenshot,
            ),
          ),
      ],
    );

    final Widget? readonlyBanner = coreInfo.readOnlyBecauseOfVersion
        ? Collapsible(
            collapsed:
                !(coreInfo.readOnly && coreInfo.readOnlyBecauseOfVersion),
            axis: CollapsibleAxis.vertical,
            child: SafeArea(
              child: ListTile(
                onTap: askUserToDisableReadOnly,
                title: Text(t.editor.newerFileFormat.readOnlyMode),
                subtitle: Text(t.editor.newerFileFormat.title),
                trailing: const Icon(Icons.edit_off),
              ),
            ),
          )
        : null;

    final Widget toolbar = _buildSplitGlobalToolbar(context);

    final Widget layeredCanvas = _wrapWithDockedSidePanel(
      Stack(
        children: [
          canvas,

          if (_previewPdfDocument != null &&
              _previewPageIndex != null &&
              _previewRegion != null)
            LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth =
                    widget.embedded &&
                        constraints.maxWidth.isFinite &&
                        constraints.maxWidth > 0
                    ? constraints.maxWidth
                    : null;
                return PdfEquationPreview(
                  pdfDocument: _previewPdfDocument!,
                  pageIndex: _previewPageIndex!,
                  region: _previewRegion!,
                  onDismiss: _hidePdfEquationPreview,
                  onLinkTapped: _onPreviewLinkTapped,
                  onGoToLocation: _onGoToLocation,
                  maxWidth: maxWidth,
                  invert: Theme.of(context).brightness == Brightness.dark
                      ? (stows.noteInvertInDarkModeOverrides.value[coreInfo.filePath] == 1)
                      : false,
                );
              },
            ),
          if (_showGoBackAfterPreviewJump &&
              _lastPreviewGoToOriginPageIndex != null)
            Positioned(
              right: 12,
              bottom: 12,
              child: Opacity(
                opacity: 0.85,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.tonal(
                      onPressed: _goBackFromPreviewJump,
                      child: Text(t.editor.goBack),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _cancelPreviewJumpHistory,
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );

    final Widget body = _buildEditorBody(
      canvas: layeredCanvas,
      toolbar: toolbar,
      readonlyBanner: readonlyBanner,
      isToolbarVertical: isToolbarVertical,
      showToolbar: widget.showToolbar,
    );

    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: stows.noteInvertInDarkModeOverrides,
      builder: (context, _, __) {
        return ValueListenableBuilder(
          valueListenable: savingState,
          builder: (context, savingState, child) {
            return PopScope(
              canPop: widget.embedded && !_isDockedSidePanelVisible,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop && _isDockedSidePanelVisible) {
                  _closeDockedSidePanel();
                  return;
                }
                if (!didPop && !widget.embedded && mounted) {
                  _goToHome(this.context);
                  return;
                }
                if (didPop &&
                    (savingState == .waitingToSave ||
                        savingState == .saving ||
                        _saveFollowUpRequested)) {
                  log.info(
                    'Exit triggered — note has pending save; dispose will flush (${coreInfo.pages.length} pages)',
                  );
                }
              },
              child: WillPopScope(
                onWillPop: () async {
                  if (_isDockedSidePanelVisible) {
                    _closeDockedSidePanel();
                    return false;
                  }
                  if (widget.embedded) return true;
                  if (mounted) _goToHome(this.context);
                  return false;
                },
                child: child!,
              ),
            );
          },
          child: widget.embedded
                  ? body
                  : Builder(
                      builder: (context) {
                    return Hero(
                      tag: widget.path != null ? 'note_hero_${widget.path}' : 'note_hero_new_note',
                      flightShuttleBuilder: (flightContext, animation, flightDirection, fromHeroContext, toHeroContext) {
                        final size = MediaQuery.sizeOf(flightContext);
                        final isPush = flightDirection == HeroFlightDirection.push;
                        final cardWidget = isPush ? fromHeroContext.widget : toHeroContext.widget;
                        final editorWidget = isPush ? toHeroContext.widget : fromHeroContext.widget;
                        final cardSize = isPush ? fromHeroContext.size : toHeroContext.size;

                        return AnimatedBuilder(
                          animation: animation,
                          builder: (context, child) {
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                Opacity(
                                  opacity: (1.0 - animation.value).clamp(0.0, 1.0),
                                  child: FittedBox(
                                    fit: BoxFit.cover,
                                    alignment: Alignment.topCenter,
                                    child: SizedBox(
                                      width: cardSize?.width,
                                      height: cardSize?.height,
                                      child: cardWidget,
                                    ),
                                  ),
                                ),
                                Opacity(
                                  opacity: animation.value.clamp(0.0, 1.0),
                                  child: ClipRect(
                                    child: OverflowBox(
                                      alignment: Alignment.topCenter,
                                      minWidth: size.width,
                                      minHeight: size.height,
                                      maxWidth: size.width,
                                      maxHeight: size.height,
                                      child: editorWidget,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                      child: Scaffold(
                        backgroundColor:
                            Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF1E1E1E)
                            : Theme.of(
                                context,
                              ).colorScheme.surfaceContainerLow,
                        resizeToAvoidBottomInset: false,
                        // Oculta o FAB se o painel de Pages estiver aberto OU se for tela infinita OU se estiver no SplitView (embedded)
                        floatingActionButton: ((_dockedSidePanel != _EditorDockedSidePanel.pages) && !coreInfo.isInfinite && !widget.embedded)
                            ? FloatingActionButton.extended(
                                elevation: 4,
                                backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                                foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
                                onPressed: () => _toggleDockedSidePanel(_EditorDockedSidePanel.pages),
                                icon: const Icon(Icons.article_outlined),
                                label: const Text('Pages'),
                              )
                            : null,
                        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
                        // AppBar só é oculta quando a ABA PAGES está aberta. Settings e Split View a mantêm visível!
                        appBar: (_dockedSidePanel == _EditorDockedSidePanel.pages) ? null : _buildEditorAppBar(context),
                        body: body,
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  void snackBarNeedsToSaveBeforeExiting() {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(t.editor.needsToSaveBeforeExiting)));
  }

  Future<void> _setCustomThumbnail() async {
    VaultAdapter.preventLock = true;
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp'],
        withData: true,
      );
    } finally {
      VaultAdapter.preventLock = false;
    }

    if (result == null || result.files.isEmpty) return;

    Uint8List? bytes = result.files.first.bytes;
    if (bytes == null && result.files.first.path != null) {
      bytes = await File(result.files.first.path!).readAsBytes();
    }
    if (bytes == null) return;

    if (!mounted) return;

    final croppedBytes = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(
        builder: (context) => CustomThumbnailScreen(imageBytes: bytes!),
      ),
    );

    if (croppedBytes != null) {
      final thumbPath = '${coreInfo.filePath}${Editor.extension}.p';
      if (coreInfo.isInfinite) {
        await FileManager.writeInfiniteCoverThumbnail(croppedBytes, thumbPath);
        coreInfo.infiniteThumbnailMode = 'cover';
      } else {
        await FileManager.writeFile(thumbPath, croppedBytes, awaitWrite: true);

        coreInfo.firstPageHash =
            'custom_thumbnail_${DateTime.now().millisecondsSinceEpoch}';
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Custom thumbnail set!')));
      }
    }
  }

  Future<void> _deleteNote() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => GlassmorphicConfirmDialog(
        title: t.editor.selectionBar.delete,
        subtitle:
            'Are you sure you want to delete this note? This action cannot be undone.',
        confirmText: t.common.delete,
        cancelText: t.common.cancel,
        isDestructive: true,
        onCancel: () => Navigator.pop(context, false),
        onConfirm: () => Navigator.pop(context, true),
      ),
    );

    if (confirmed == true) {
      _isDeleted = true;
      _delayedSaveTimer?.cancel();

      try {
        await _recoveryJournal?.clear();
        await FileManager.deleteFile(coreInfo.filePath + Editor.extension);

        try {
          await FileManager.deleteFile(
            '${coreInfo.filePath}${Editor.extension}.p',
          );
        } catch (_) {}

        if (mounted) {
          Navigator.of(context).pop();
        }
      } catch (e) {
        log.severe("Failed to delete note", e);
        _isDeleted = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t.editor.failedToDeleteNote(error: e))),
          );
        }
      }
    }
  }

  Future<void> _openSplitView() async {
    final currentPath = coreInfo.filePath;
    final selected = await _pickNotePath(context, excludePaths: {currentPath});
    if (!mounted || selected == null) return;

    context.pushReplacement(
      RoutePaths.editSplit(currentPath, selected, axis: Axis.horizontal),
    );
  }

  void _forceRefreshPageStrokes(EditorPage page) {
    for (final stroke in page.allStrokesInDrawOrder) {
      stroke.markPolygonNeedsUpdating();
    }
    page.redrawStrokes();
  }

  void _toggleGlobalBackgroundInversion(bool invert) {
    // Update the stows override so the setting persists across canvas interactions
    final currentOverrides = Map<String, int>.from(stows.noteInvertInDarkModeOverrides.value);
    currentOverrides[coreInfo.filePath] = invert ? 1 : 0;
    stows.noteInvertInDarkModeOverrides.value = currentOverrides;

    setState(() {
      for (int i = 0; i < coreInfo.pages.length; i++) {
        final page = coreInfo.pages[i];
        if (page.backgroundImage != null) {
          page.backgroundImage!.invertible = invert;
          page.backgroundImage!.onMiscChange?.call();
        }
        _forceRefreshPageStrokes(page);
        _pageRasterCache.invalidatePage(i);
      }
      
      final center = currentPageIndex.clamp(0, coreInfo.pages.length - 1);
      final radius = 2;
      final bandStart = (center - radius).clamp(0, coreInfo.pages.length - 1);
      final bandEnd = (center + radius).clamp(0, coreInfo.pages.length - 1);
      _maintainPageRasterBand(
        bandStart,
        bandEnd,
        forceSchedule: true,
        scale: _quantizedCanvasScale,
      );
      
      _bumpInteractionRepaint();
    });
    autosaveAfterDelay();
  }

  Widget bottomSheet(BuildContext context) {
    final Brightness brightness = Theme.brightnessOf(context);
    final invert = brightness == Brightness.dark
        ? (stows.noteInvertInDarkModeOverrides.value[coreInfo.filePath] == 1)
        : false;
    final int currentPageIndex = this.currentPageIndex;

    final page = coreInfo.pages[currentPageIndex];

    EditorImage? bgImage = page.backgroundImage;
    bool isFakeBackground = false;

    if (bgImage == null && page.images.isNotEmpty) {
      final potentialBg = page.images.first;

      if (potentialBg.locked) {
        bgImage = potentialBg;
        isFakeBackground = true;
      }
    }

    final bool hasBackground = bgImage != null;

    BoxFit currentFit = BoxFit.contain;
    if (hasBackground) {
      final img = bgImage;
      final pSize = page.size;
      final dRect = img.dstRect;
      const double eps = 2.0;

      final bool widthMatch = (dRect.width - pSize.width).abs() < eps;
      final bool heightMatch = (dRect.height - pSize.height).abs() < eps;

      if (widthMatch && heightMatch) {
        currentFit = BoxFit.fill;
      } else if (dRect.width >= pSize.width - eps &&
          dRect.height >= pSize.height - eps) {
        currentFit = BoxFit.cover;
      } else {
        currentFit = BoxFit.contain;
      }
    }

    return ModernEditorMenu(
      coreInfo: coreInfo,
      currentPageIndex: currentPageIndex,
      invert: invert,
      onClose: _closeDockedSidePanel,
      onOpenSplitView: widget.onOpenSplitView ?? _openSplitView,
      onCloseSplitView: widget.onCloseSplitView,
      onReopenSplitView: widget.onReopenSplitView,
      onSwapSplitView: widget.onSwapSplitView,
      onToggleSplitAxis: widget.onToggleSplitAxis,
      splitHasSecondary: widget.splitHasSecondary,
      splitAxis: widget.splitAxis ?? Axis.horizontal,
      onLayersChanged: () {
        setState(() {});
        _pageRasterCache.invalidatePage(currentPageIndex);
        autosaveAfterDelay();
      },
      onInkDefaultsChanged: () {
        coreInfo.noteToolSettings = captureNoteToolSettings(
          lastToolId: stows.lastTool.value,
          lastPenTypeId: stows.lastPenType.value,
        );
        setState(() {});
        _pageRasterCache.invalidateInk(currentPageIndex);
        autosaveAfterDelay();
      },
      captureNoteToolSettingsForInk: () => captureNoteToolSettings(
        lastToolId: stows.lastTool.value,
        lastPenTypeId: stows.lastPenType.value,
      ),

      hasBackground: hasBackground,
      isBackgroundInverted: hasBackground ? (bgImage.invertible) : false,
      currentBackgroundFit: currentFit,

      onSetBackgroundFit: (BoxFit fit) async {
        if (coreInfo.readOnly || bgImage == null) return;
        final img = bgImage;
        final pageSize = page.size;

        Size originalSize = img.naturalSize;
        if (img is! PdfEditorImage && img is PngEditorImage) {
          final notifier = coreInfo.assetCacheAll.getImageProviderNotifier(
            img.assetId,
          );
          final provider = notifier.value;
          if (provider != null) {
            final completer = Completer<Size>();
            final stream = provider.resolve(ImageConfiguration.empty);
            late ImageStreamListener listener;
            listener = ImageStreamListener(
              (ImageInfo info, bool _) {
                if (!completer.isCompleted) {
                  completer.complete(
                    Size(
                      info.image.width.toDouble(),
                      info.image.height.toDouble(),
                    ),
                  );
                }
              },
              onError: (e, s) {
                if (!completer.isCompleted) completer.complete(img.naturalSize);
              },
            );
            stream.addListener(listener);
            originalSize = await completer.future.timeout(
              const Duration(milliseconds: 150),
              onTimeout: () => img.naturalSize,
            );
            stream.removeListener(listener);
          }
        }
        if (!mounted) return;

        setState(() {
          if (originalSize.isEmpty) return;
          Rect newRect;
          switch (fit) {
            case BoxFit.fill:
              newRect = Offset.zero & pageSize;
              break;
            case BoxFit.contain:
              final fittedSizes = applyBoxFit(
                BoxFit.contain,
                originalSize,
                pageSize,
              );
              newRect = Alignment.center.inscribe(
                fittedSizes.destination,
                Offset.zero & pageSize,
              );
              break;
            case BoxFit.cover:
              final double scale = math.max(
                pageSize.width / originalSize.width,
                pageSize.height / originalSize.height,
              );
              final Size coverSize = originalSize * scale;
              newRect = Alignment.center.inscribe(
                coverSize,
                Offset.zero & pageSize,
              );
              break;
            default:
              newRect = Offset.zero & pageSize;
          }
          final newImg = img.copy();
          newImg.dstRect = newRect;
          newImg.naturalSize = originalSize;
          newImg.pageSize = pageSize;
          newImg.onMoveImage = img.onMoveImage;
          newImg.onDeleteImage = img.onDeleteImage;
          newImg.onMiscChange = autosaveAfterDelay;

          if (fit == BoxFit.contain) {
            page.images.remove(img);
            page.backgroundImage = newImg;
            newImg.locked = false;
          } else {
            page.backgroundImage = null;
            page.images.remove(img);
            page.images.insert(0, newImg);
            newImg.locked = true;
          }
          page.redrawStrokes();
          _pageRasterCache.invalidatePage(currentPageIndex);
          autosaveAfterDelay();
        });
      },

      onToggleBackgroundInvert: () => setState(() {
        if (coreInfo.readOnly || bgImage == null) return;
        if (isFakeBackground) {
          final img = page.images.first;
          img.invertible = !img.invertible;
        } else {
          page.backgroundImage!.invertible = !page.backgroundImage!.invertible;
        }
        _pageRasterCache.invalidatePage(currentPageIndex);
        autosaveAfterDelay();
      }),

      onRemoveBackground: () => setState(() {
        if (coreInfo.readOnly || bgImage == null) return;
        final img = bgImage;
        page.backgroundImage = null;
        page.images.remove(img);

        final floatImg = img.copy();
        floatImg.locked = false;

        floatImg.onMoveImage = onMoveImage;
        floatImg.onDeleteImage = onDeleteImage;
        floatImg.onMiscChange = autosaveAfterDelay;

        page.images.add(floatImg);

        currentTool = Select.currentSelect;
        Select.currentSelect.selectResult = SelectResult(
          pageIndex: currentPageIndex,
          pageIndexStart: currentPageIndex,
          strokes: [],
          images: [floatImg],
          path: Path()..addRect(floatImg.dstRect),
        );
        Select.currentSelect.doneSelecting = true;

        _pageRasterCache.invalidatePage(currentPageIndex);
        autosaveAfterDelay();
        _closeDockedSidePanel();
      }),

      onDeleteBackground: () => setState(() {
        if (coreInfo.readOnly) return;
        page.backgroundImage = null;
        if (isFakeBackground) {
          page.images.remove(bgImage);
        }
        _pageRasterCache.invalidatePage(currentPageIndex);
        autosaveAfterDelay();
        _closeDockedSidePanel();
      }),

      onSetPagePattern: (pattern) => setState(() {
        if (coreInfo.readOnly) return;
        coreInfo.ensureDocumentDefaultsFromGlobal();
        coreInfo.noteDefaultPattern = pattern;
        final page = coreInfo.pages[currentPageIndex];
        page.hasLocalPattern = true;
        page.backgroundPattern = pattern;
        page.markSaveBinaryDirty();
        _forceRefreshPageStrokes(page);
        _pageRasterCache.invalidateBg(currentPageIndex);
        _bumpInteractionRepaint();
        autosaveAfterDelay();
      }),

      onSetPageLineHeight: (height) => setState(() {
        if (coreInfo.readOnly) return;
        coreInfo.ensureDocumentDefaultsFromGlobal();
        coreInfo.noteDefaultLineHeight = height;
        final page = coreInfo.pages[currentPageIndex];
        page.hasLocalLineHeight = true;
        page.lineHeight = height;
        page.markSaveBinaryDirty();
        _forceRefreshPageStrokes(page);
        _pageRasterCache.invalidatePage(currentPageIndex);
        _bumpInteractionRepaint();
        autosaveAfterDelay();
      }),

      onSetPageLineThickness: (thick) => setState(() {
        if (coreInfo.readOnly) return;
        coreInfo.ensureDocumentDefaultsFromGlobal();
        coreInfo.noteDefaultLineThickness = thick;
        final page = coreInfo.pages[currentPageIndex];
        page.hasLocalLineThickness = true;
        page.lineThickness = thick.toDouble();
        page.markSaveBinaryDirty();
        _forceRefreshPageStrokes(page);
        _pageRasterCache.invalidatePage(currentPageIndex);
        _bumpInteractionRepaint();
        autosaveAfterDelay();
      }),

      onSetPageColor: (color) => setState(() {
        if (coreInfo.readOnly) return;
        coreInfo.ensureDocumentDefaultsFromGlobal();
        coreInfo.noteDefaultPageColor = color.value;
        final page = coreInfo.pages[currentPageIndex];
        page.hasLocalBackgroundColor = true;
        page.backgroundColor = color;
        page.markSaveBinaryDirty();
        _forceRefreshPageStrokes(page);
        _pageRasterCache.invalidateBg(currentPageIndex);
        _bumpInteractionRepaint();
        autosaveAfterDelay();
      }),

      onSetPageLineColor: (color) => setState(() {
        if (coreInfo.readOnly) return;
        coreInfo.ensureDocumentDefaultsFromGlobal();
        coreInfo.noteDefaultLineColor = color.value;
        final page = coreInfo.pages[currentPageIndex];
        page.hasLocalLineColor = true;
        page.lineColor = color;
        page.markSaveBinaryDirty();
        _forceRefreshPageStrokes(page);
        _pageRasterCache.invalidatePage(currentPageIndex);
        _bumpInteractionRepaint();
        autosaveAfterDelay();
      }),

      onSetMargins: (left, right, top, bottom) => setState(() {
        if (coreInfo.readOnly) return;
        coreInfo.ensureDocumentDefaultsFromGlobal();
        coreInfo.noteDefaultMarginLeft = left;
        coreInfo.noteDefaultMarginRight = right;
        coreInfo.noteDefaultMarginTop = top;
        coreInfo.noteDefaultMarginBottom = bottom;
        if (left > 0 || right > 0 || top > 0 || bottom > 0) {
          coreInfo.noteDefaultBorderColor ??= stows.defaultMarginColor.value;
        } else {
          coreInfo.noteDefaultBorderColor = null;
        }
        final page = coreInfo.pages[currentPageIndex];
        page.hasLocalMargins = true;
        page.marginLeft = left;
        page.marginRight = right;
        page.marginTop = top;
        page.marginBottom = bottom;
        if (coreInfo.noteDefaultBorderColor != null) {
          page.hasLocalBorderColor = true;
          page.borderColor = Color(coreInfo.noteDefaultBorderColor!);
        }
        page.markSaveBinaryDirty();
        _forceRefreshPageStrokes(page);
        _pageRasterCache.invalidateBg(currentPageIndex);
        _bumpInteractionRepaint();
        autosaveAfterDelay();
      }),

      onSetBorderColor: (color) => setState(() {
        if (coreInfo.readOnly) return;
        coreInfo.ensureDocumentDefaultsFromGlobal();
        coreInfo.noteDefaultBorderColor = color.value;
        final page = coreInfo.pages[currentPageIndex];
        page.hasLocalBorderColor = true;
        page.borderColor = color;
        page.markSaveBinaryDirty();
        _forceRefreshPageStrokes(page);
        _pageRasterCache.invalidateBg(currentPageIndex);
        _bumpInteractionRepaint();
        autosaveAfterDelay();
      }),

      onSetPageOrientation: (orientation) => setState(() {
        if (coreInfo.readOnly) return;
        coreInfo.notePageOrientation = orientation;
        final oldPage = coreInfo.pages[currentPageIndex];
        final newSize = _newPageSize();
        final sameSize =
            oldPage.size.width == newSize.width &&
            oldPage.size.height == newSize.height;
        if (sameSize) {
          coreInfo.notifyListeners();
          return;
        }
        oldPage.quill.changeSubscription?.cancel();
        oldPage.quill.focusNode.removeListener(_onQuillFocusChange);
        final d = _newPageDefaults();
        final newPage = EditorPage(
          id: oldPage.id,
          size: newSize,
          strokes: List<Stroke>.from(oldPage.allStrokesInDrawOrder),
          images: List<EditorImage>.from(oldPage.allImagesInDrawOrder),
          quill: oldPage.quill,
          backgroundImage: oldPage.backgroundImage,
          backgroundPattern: oldPage.backgroundPattern ?? d.pattern,
          backgroundColor: oldPage.backgroundColor,
          lineColor: oldPage.lineColor,
          lineHeight: oldPage.lineHeight,
          lineThickness: oldPage.lineThickness,
          hasLocalPattern: oldPage.hasLocalPattern || true,
          hasLocalBackgroundColor: oldPage.hasLocalBackgroundColor || true,
          hasLocalLineColor: oldPage.hasLocalLineColor || true,
          hasLocalLineHeight: oldPage.hasLocalLineHeight || true,
          hasLocalLineThickness: oldPage.hasLocalLineThickness || true,
          hasLocalMargins: oldPage.hasLocalMargins,
          marginLeft: oldPage.marginLeft,
          marginRight: oldPage.marginRight,
          marginTop: oldPage.marginTop,
          marginBottom: oldPage.marginBottom,
          hasLocalBorderColor: oldPage.hasLocalBorderColor,
          borderColor: oldPage.hasLocalBorderColor ? oldPage.borderColor : null,
        );
        coreInfo.pages[currentPageIndex] = newPage;
        listenToQuillChanges(newPage.quill, currentPageIndex);
        newPage.buildSpatialIndex();
        coreInfo.notifyListeners();
        _pageRasterCache.invalidatePage(currentPageIndex);
        autosaveAfterDelay();
      }),

      onClearPage: () {
        _closeDockedSidePanel();
        clearPage(currentPageIndex);
      },
      onClearAll: () {
        _closeDockedSidePanel();
        clearAllPages();
      },
      onPickImage: () async {
        final photosPicked = await _pickPhotos();
        if (photosPicked > 0 && mounted) {
          _closeDockedSidePanel();
        }
      },
      onImportPdf: () async {
        final pdfImported = await importPdf();
        if (mounted && pdfImported) {
          _closeDockedSidePanel();
        }
        return pdfImported;
      },
      onToggleCalculator: () {},
      onNoteHandwritingToLatex: coreInfo.readOnly
          ? null
          : () async {
              await _exportNoteHandwritingToLatex();
            },
      onManageTagsAndLinks: _showTagsAndLinksDialog,

      onExportSba: (ctx) {
        if (mounted) {
          Navigator.pop(ctx);
          exportAsSba(this.context);
        }
      },
      onExportPdf: (ctx) {
        if (mounted) {
          Navigator.pop(ctx);
          exportAsPdf(this.context);
        }
      },
      onExportPng: (ctx) {
        if (mounted) {
          Navigator.pop(ctx);
          exportAsPng(this.context);
        }
      },
      onSetCustomThumbnail: _setCustomThumbnail,
      onDeleteNote: _deleteNote,
      onShowProperties: () async {
        await saveToFile(force: true);
        if (mounted) {
          showNotePropertiesDialog(context, coreInfo);
        }
      },
      onToggleGlobalBackgroundInversion: _toggleGlobalBackgroundInversion,
    );
  }

  bool _isEditorTextEditingMode() => currentTool == Tool.textEditing;

  /// Stable page/placeholder builder identity for [_PagesBuilder] — avoid a new
  /// closure each [EditorState.build] so didUpdateWidget does not treat the
  /// builder as changed and reset prewarm offsets / layout unnecessarily.
  Widget _editorPlaceholderPageBuilder(BuildContext context, int pageIndex) {
    final page = coreInfo.pages[pageIndex];

    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: stows.noteInvertInDarkModeOverrides,
      builder: (context, overrides, _) {
        final theme = _cachedTheme ?? Theme.of(context);
        final invert = theme.brightness == Brightness.dark
            ? (overrides[coreInfo.filePath] == 1)
            : false;

        return Canvas(
          key: ValueKey('placeholder_${invert}_$pageIndex'),
          overrideInvert: invert,
          path: coreInfo.filePath,
          page: page,
          pageIndex: 0,
          textEditing: false,
          coreInfo: EditorCoreInfo.empty,
          currentStroke: null,
          currentStrokeDetectedShape: null,
          currentSelection: null,
          placeholder: true,
          setAsBackground: null,
          currentTool: currentTool,
          currentScale: double.minPositive,
          eraserPosition: null,
          eraserSize: null,
          onNoteLinkTap: null,
          lineHeight: page.hasLocalLineHeight
              ? page.lineHeight
              : coreInfo.lineHeight,
          lineThickness: page.hasLocalLineThickness
          ? page.lineThickness.toInt()
          : coreInfo.lineThickness.toInt(),
      lineColor: page.lineColor,
        );
      },
    );
  }

  void _wirePageImageCallbacks(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= coreInfo.pages.length) return;
    final page = coreInfo.pages[pageIndex];
    page.backgroundImage?.onMoveImage = onMoveImage;
    page.backgroundImage?.onDeleteImage = onDeleteImage;
    page.backgroundImage?.onMiscChange = () {
      _pageRasterCache.invalidatePage(pageIndex, ink: false, bg: true);
      autosaveAfterDelay();
    };
    for (final image in page.images) {
      image.onMoveImage = onMoveImage;
      image.onDeleteImage = onDeleteImage;
      image.onMiscChange = () {
        _pageRasterCache.invalidateInk(pageIndex);
        autosaveAfterDelay();
      };
    }
  }

  /// Idle BSON hydrate for upcoming shells. Must not run inside [pageBuilder].
  bool _tryIdleHydratePage(int index) {
    if (!coreInfo.isLazyShellPage(index)) return false;
    final hydrated = coreInfo.tryHydratePageAtIndex(index);
    if (hydrated) {
      _wirePageImageCallbacks(index);
      listenToQuillChanges(coreInfo.pages[index].quill, index);
      _primeVisibleCanvasAssets(coreInfo, index, index, index);
    }
    return hydrated;
  }

  Widget pageBuilder(BuildContext context, int pageIndex) {
    _wirePageImageCallbacks(pageIndex);
    final page = coreInfo.pages[pageIndex];

    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: stows.noteInvertInDarkModeOverrides,
      builder: (context, overrides, _) {
        final theme = _cachedTheme ?? Theme.of(context);
        final invert = theme.brightness == Brightness.dark
            ? (overrides[coreInfo.filePath] == 1)
            : false;

        final isCroppingThisPage =
            _imageCropState != null && page.images.contains(_imageCropState!.image);
        final Widget? cropOverlay = isCroppingThisPage
            ? Positioned(
                left: _imageCropState!.image.dstRect.left,
                top: _imageCropState!.image.dstRect.top,
                width: _imageCropState!.image.dstRect.width,
                height: _imageCropState!.image.dstRect.height,
                child: Transform.rotate(
                  angle: _imageCropState!.image.rotationDeg * math.pi / 180,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: _imageCropState!.image.dstRect.width,
                    height: _imageCropState!.image.dstRect.height,
                    child: CustomPaint(
                      painter: _CropOverlayPainter(
                        cropRect: _imageCropState!.normalizedCrop,
                        scale: _transformationController.value.getMaxScaleOnAxis(),
                        accentColor: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              )
            : null;

        return ValueListenableBuilder<int>(
          valueListenable: _interactionRepaint,
          builder: (context, _, __) {
            Stroke? currentStroke = Pen.currentStroke?.pageIndex == pageIndex
                ? Pen.currentStroke
                : null;
            final shapePreview = ShapeTool.currentShapeTool.preview;
            if (shapePreview != null && shapePreview.pageIndex == pageIndex) {
              currentStroke = shapePreview;
            }

            return Stack(
              children: [
                Canvas(
                  key: ValueKey(
                    'canvas_${invert}_${pageIndex}_${page.backgroundPattern?.index}_${page.backgroundColor.value}_${page.lineHeight}_${page.lineThickness}_${page.lineColor.value}_${page.size.width}_${page.size.height}',
                  ),
                  overrideInvert: invert,
                  path: coreInfo.filePath,
              page: page,
              pageIndex: pageIndex,

              lineHeight: page.hasLocalLineHeight
                  ? page.lineHeight
                  : coreInfo.lineHeight,

              lineThickness: page.hasLocalLineThickness
                  ? page.lineThickness.toInt()
                  : coreInfo.lineThickness.toInt(),
              lineColor: page.lineColor,
              textEditing: currentTool == Tool.textEditing,
              coreInfo: coreInfo,
              currentStroke: currentStroke,
              currentStrokeDetectedShape:
                  currentStroke != null &&
                      currentTool is Pen &&
                      currentTool is! Highlighter
                  ? _penHoldDetectedShape
                  : null,
              currentSelection: () {
                if (currentTool is! Select) return null;
                final selectResult = (currentTool as Select).selectResult;
                if (selectResult.pageIndex != pageIndex) return null;
                if (_imageCropState != null &&
                    selectResult.images.length == 1 &&
                    identical(
                      selectResult.images.first,
                      _imageCropState!.image,
                    )) {
                  return null;
                }
                return selectResult;
              }(),
              selectionPreview: _selectionPreviewForPage(pageIndex),
              selectionHandlesInteractionMode: currentTool is Select
                  ? _selectionHandlesInteractionMode
                  : SelectionHandlesInteractionMode.resize,
              setAsBackground: (EditorImage image) {
                final rect = image.dstRect;
                final natSize = image.naturalSize;

                if (page.backgroundImage != null) {
                  page.images.add(page.backgroundImage!);
                }
                page.images.remove(image);

                page.backgroundImage = image;

                page.backgroundImage!.dstRect = rect;
                page.backgroundImage!.naturalSize = natSize;

                _pageRasterCache.invalidatePage(pageIndex, ink: true, bg: true);

                CanvasImage.activeListener.notifyListenersPlease();

                autosaveAfterDelay();
                setState(() {});
              },
              onNoteLinkTap: _onCanvasNoteLinkTap,
              currentTool: currentTool,
              interactionRepaintListenable: _interactionRepaint,
              currentScale: _quantizedCanvasScale,
              eraserPositionListenable: pageIndex == dragPageIndex
                  ? _eraserPositionRepaint
                  : null,
              eraserPosition:
                  currentTool is Eraser &&
                      eraserPosition != null &&
                      pageIndex == dragPageIndex
                  ? eraserPosition
                  : null,
              eraserSize: currentTool is Eraser
                  ? (currentTool as Eraser).size
                  : null,
              eraserDeltaRemoved: pageIndex == dragPageIndex
                  ? _eraserDeltaRemoved
                  : null,
              eraserDeltaAdded: pageIndex == dragPageIndex
                  ? _eraserDeltaAdded
                  : null,
              doneSelecting: currentTool is Select
                  ? (currentTool as Select).doneSelecting
                  : true,

              pageRasterCache: _pageRasterCache,
              imageCropState: null,
              onCropRectChanged: null,
            ),
            if (cropOverlay != null) cropOverlay,
          ],
        );
      },
    );
      },
    );
  }

  Widget pageBuilderForScreenshot(
    BuildContext context, {
    required int pageIndex,
    double? previewHeight,
  }) {
    final page = coreInfo.pages[pageIndex];
    previewHeight ??= page.previewHeight();
    return CanvasPreview(
      pageIndex: pageIndex,
      height: previewHeight,
      coreInfo: coreInfo,
      highQuality: true,
    );
  }

  void _onDockedSidePanelAnimTick() {
    if (_resizeViewportAnchor == null) return;
    // Apply immediately from the ticker (not during layout). Prefer the
    // predicted canvas width so we stay aligned before LayoutBuilder runs.
    final predictedW = _predictCanvasWidthForDockAnim();
    if (_canvasGestureActive) {
      // Keep horizontal centering while the user draws/pans; skip vertical
      // re-anchoring so we do not fight the active gesture.
      _applyResizeViewportAnchor(
        viewportWidthOverride: predictedW,
        horizontalOnly: true,
      );
      return;
    }
    _applyResizeViewportAnchor(viewportWidthOverride: predictedW);
  }

  void _onCanvasContainerBoundsChanged(Size size) {
    if (_isSmoothScrolling) return; // Evita que a âncora de resize interrompa a animação de scroll
    if (_resizeViewportAnchor == null) return;
    // Never write the transform synchronously from LayoutBuilder — that races
    // with canvas gestures and can freeze the docked-panel animation mid-way.
    _scheduleResizeViewportAnchorApply(
      viewportWidthOverride: size.width,
      viewportHeightOverride: size.height,
    );
  }

  /// Mirrors [_wrapWithDockedSidePanel] width math for the current anim value.
  double? _predictCanvasWidthForDockAnim() {
    if (!mounted) return null;
    final box = context.findRenderObject() as RenderBox?;
    final available = box?.hasSize == true
        ? box!.size.width
        : MediaQuery.sizeOf(context).width;
    if (available <= 0) return null;
    final ideal = editorSidePanelDesktopWidth(context);
    final isPages = _dockedSidePanel == _EditorDockedSidePanel.pages;
    final panelWidth = isPages 
        ? ideal.clamp(280.0, 360.0).toDouble() 
        : ideal.clamp(340.0, 460.0).toDouble();
    const spacing = 16.0;
    final totalPanelSpace = panelWidth + spacing * 2;
    
    final tAnim = Curves.easeOutCubic.transform(
      _dockedSidePanelController.value,
    );
    return available - totalPanelSpace * tAnim;
  }

  void _beginViewportResizeStabilization({bool freezePageLayout = true}) {
    // Explicit sidebar/split sessions take over from orientation settle.
    _metricsOwnsResizeSession = false;
    _suppressTransformClamp.value = true;
    if (_viewportStablePageIndex == null && coreInfo.pages.isNotEmpty) {
      final resolved = coreInfo.isInfinite || coreInfo.pages.length <= 1
          ? 0
          : getPageIndexFromScrollPosition(
              scrollY: -scrollY,
              screenWidth: _currentViewportWidth(),
              pages: coreInfo.pages,
            );
      _viewportStablePageIndex = resolved.clamp(0, coreInfo.pages.length - 1);
      _lastCurrentPageIndex = _viewportStablePageIndex!;
    } else {
      _viewportStablePageIndex ??= _lastCurrentPageIndex;
    }
    // Keep the first locked anchor for the whole resize/sidebar session.
    _resizeViewportAnchor ??= _captureResizeViewportAnchor();
    PageRasterCacheManager.beginLayoutResizeSession();
    if (!freezePageLayout) {
      // Live FittedBox rescale with the docked panel; raster LOD covers ink.
      if (_pageLayoutWidthOverride != null) {
        setState(() => _pageLayoutWidthOverride = null);
      }
      return;
    }
    final w = _currentViewportWidth();
    if (w > 0 && _pageLayoutWidthOverride == null) {
      setState(() => _pageLayoutWidthOverride = w);
    }
  }

  void _endViewportResizeStabilization({
    double? viewportWidthOverride,
    double? viewportHeightOverride,
  }) {
    if (!mounted) return;
    _metricsOwnsResizeSession = false;
    final gesture = _canvasGestureDetectorKey.currentState;
    final laidOutW = gesture?.containerBounds.maxWidth;
    final laidOutH = gesture?.containerBounds.maxHeight;
    final wOverride =
        viewportWidthOverride ??
        (laidOutW != null && laidOutW > 0 ? laidOutW : null);
    final hOverride =
        viewportHeightOverride ??
        (laidOutH != null && laidOutH > 0 ? laidOutH : null);
    final anchor = _resizeViewportAnchor;
    final hadLayoutOverride = _pageLayoutWidthOverride != null;

    // Re-anchor using the final page layout width so scrollY still targets the
    // same page after fitted heights/offsets change.
    _pageLayoutWidthOverride = null;
    _applyResizeViewportAnchor(
      viewportWidthOverride: wOverride,
      viewportHeightOverride: hOverride,
    );
    if (anchor != null && coreInfo.pages.isNotEmpty) {
      _lastCurrentPageIndex = anchor.pageIndex.clamp(
        0,
        coreInfo.pages.length - 1,
      );
    }
    _unlockResizeViewportAnchor();
    _viewportStablePageIndex = null;
    _suppressTransformClamp.value = false;
    PageRasterCacheManager.endLayoutResizeSession();
    if (hadLayoutOverride && mounted) {
      setState(() {});
    }
    gesture?.reclampTransform();
    _transformationController.notifyListenersPlease();
  }

  void _lockResizeViewportAnchor() {
    _resizeViewportAnchor = _captureResizeViewportAnchor();
  }

  void _scheduleResizeViewportAnchorApply({
    double? viewportWidthOverride,
    double? viewportHeightOverride,
  }) {
    if (_resizeViewportAnchor == null) return;
    if (_resizeAnchorApplyScheduled) {
      _pendingResizeAnchorWidthOverride = viewportWidthOverride;
      _pendingResizeAnchorHeightOverride = viewportHeightOverride;
      return;
    }
    _resizeAnchorApplyScheduled = true;
    _pendingResizeAnchorWidthOverride = viewportWidthOverride;
    _pendingResizeAnchorHeightOverride = viewportHeightOverride;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resizeAnchorApplyScheduled = false;
      if (!mounted || _resizeViewportAnchor == null) return;
      if (_canvasGestureActive && _dockedSidePanelController.isAnimating) {
        _applyResizeViewportAnchor(
          viewportWidthOverride: _pendingResizeAnchorWidthOverride,
          viewportHeightOverride: _pendingResizeAnchorHeightOverride,
          horizontalOnly: true,
        );
      } else {
        _applyResizeViewportAnchor(
          viewportWidthOverride: _pendingResizeAnchorWidthOverride,
          viewportHeightOverride: _pendingResizeAnchorHeightOverride,
        );
      }
      _pendingResizeAnchorWidthOverride = null;
      _pendingResizeAnchorHeightOverride = null;
    });
  }

  bool get _isDockedSidePanelVisible =>
      _dockedSidePanel != _EditorDockedSidePanel.none ||
      _dockedSidePanelController.value > 0;

  void _toggleDockedSidePanel(_EditorDockedSidePanel panel) {
    if (panel == _EditorDockedSidePanel.none) {
      _closeDockedSidePanel();
      return;
    }

    final controller = _dockedSidePanelController;
    final isThisPanel = _dockedSidePanel == panel;
    final visible = controller.value > 0.01;

    // Mid-close of this panel → reopen (do not stack another reverse).
    if (isThisPanel &&
        controller.isAnimating &&
        controller.status == AnimationStatus.reverse) {
      _openDockedSidePanel(panel);
      return;
    }

    // Already open (or opening) → close.
    if (isThisPanel && visible) {
      _closeDockedSidePanel();
      return;
    }

    final switching =
        _dockedSidePanel != _EditorDockedSidePanel.none &&
        _dockedSidePanel != panel &&
        visible;

    if (switching) {
      // Swap content in place; keep whatever open/close animation is running.
      if (panel == _EditorDockedSidePanel.pages) {
        _pagesSidePanelIndexAtOpen = currentPageIndex;
      }
      setState(() => _dockedSidePanel = panel);
      if (controller.status == AnimationStatus.reverse ||
          controller.isDismissed) {
        _openDockedSidePanel(panel);
      }
      return;
    }

    if (panel == _EditorDockedSidePanel.pages) {
      _pagesSidePanelIndexAtOpen = currentPageIndex;
    }
    _openDockedSidePanel(panel);
  }

  void _openDockedSidePanel(_EditorDockedSidePanel panel) {
    final epoch = ++_dockedSidePanelAnimEpoch;
    if (!_dockedSidePanelOcclusionActive) {
      PageRasterCacheManager.pushLayoutOcclusion();
      _dockedSidePanelOcclusionActive = true;
    }
    _beginViewportResizeStabilization(freezePageLayout: false);
    if (_dockedSidePanel != panel) {
      setState(() => _dockedSidePanel = panel);
    }
    final future = _dockedSidePanelController.forward();
    future.whenComplete(() {
      if (!mounted || epoch != _dockedSidePanelAnimEpoch) return;
      if (!_dockedSidePanelController.isCompleted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || epoch != _dockedSidePanelAnimEpoch) return;
        _endViewportResizeStabilization();
      });
    });
  }

  void _closeDockedSidePanel() {
    if (_dockedSidePanel == _EditorDockedSidePanel.none &&
        _dockedSidePanelController.isDismissed) {
      return;
    }
    final epoch = ++_dockedSidePanelAnimEpoch;
    _beginViewportResizeStabilization(freezePageLayout: false);
    final future = _dockedSidePanelController.reverse();
    future.whenComplete(() {
      if (!mounted || epoch != _dockedSidePanelAnimEpoch) return;
      if (!_dockedSidePanelController.isDismissed) return;
      setState(() => _dockedSidePanel = _EditorDockedSidePanel.none);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || epoch != _dockedSidePanelAnimEpoch) return;
        _endViewportResizeStabilization();
        if (_dockedSidePanelOcclusionActive) {
          PageRasterCacheManager.popLayoutOcclusion();
          _dockedSidePanelOcclusionActive = false;
        }
      });
    });
  }

  Widget _buildDockedSidePanelBody() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    // Cor pura e minimalista, perfeitamente adaptada a luz/escuro.
    final uniformColor = colorScheme.surface;

    // Override rígido: força os fundos rebeldes do 'pageManager' e 'outlines' 
    // a ficarem invisíveis, mostrando apenas o uniformColor do painel base.
    final unifiedTheme = theme.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      dialogBackgroundColor: Colors.transparent,
      cardColor: Colors.transparent,
      colorScheme: colorScheme.copyWith(
        surfaceContainer: Colors.transparent,
        surfaceContainerLow: Colors.transparent,
        surfaceContainerHigh: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        selectedTileColor: colorScheme.secondaryContainer,
        iconColor: colorScheme.onSurfaceVariant,
        selectedColor: colorScheme.onSecondaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      tabBarTheme: theme.tabBarTheme.copyWith(
        dividerColor: colorScheme.outlineVariant.withValues(alpha: 0.3),
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
      ),
    );

    switch (_dockedSidePanel) {
      case _EditorDockedSidePanel.pages:
        return EditorFlatSidePanel(
          title: "Document tabs",
          onClose: _closeDockedSidePanel,
          backgroundColor: uniformColor,
          body: Theme(
            data: unifiedTheme,
            child: pageManager(
              context,
              pageIndexAtOpen: _pagesSidePanelIndexAtOpen,
            ),
          ),
        );
      case _EditorDockedSidePanel.settings:
        return EditorFlatSidePanel(
          title: t.home.tabs.settings,
          onClose: _closeDockedSidePanel,
          backgroundColor: uniformColor,
          body: Theme(
            data: unifiedTheme,
            child: bottomSheet(context),
          ),
        );
      case _EditorDockedSidePanel.none:
        return const SizedBox.shrink();
    }
  }

  Widget _wrapWithDockedSidePanel(Widget child) {
    final panelBody = _dockedSidePanel == _EditorDockedSidePanel.none
        ? null
        : _buildDockedSidePanelBody();

    return AnimatedBuilder(
      animation: _dockedSidePanelController,
      child: child,
      builder: (context, cachedChild) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final ideal = editorSidePanelDesktopWidth(context);
            final isPages = _dockedSidePanel == _EditorDockedSidePanel.pages;
            final panelWidth = isPages 
                ? ideal.clamp(280.0, 360.0).toDouble() 
                : ideal.clamp(340.0, 460.0).toDouble();
            final tAnim = Curves.easeOutCubic.transform(
              _dockedSidePanelController.value,
            );
            const double spacing = 16.0;
            final totalPanelSpace = panelWidth + spacing * 2;
            final visibleSpace = totalPanelSpace * tAnim;

            return Stack(
              children: [
                // O canvas é empurrado de acordo com a aba selecionada. A Toolbar se mantém fixa.
                Positioned.fill(
                  left: isPages ? visibleSpace : 0,
                  right: (!isPages && _dockedSidePanel == _EditorDockedSidePanel.settings) ? visibleSpace : 0,
                  child: cachedChild!,
                ),
                
                // Sidebar Card do Material 3 Flutuante (porém fixada ao lado)
                if (panelBody != null && tAnim > 0)
                  Positioned(
                    top: spacing,
                    bottom: spacing,
                    left: isPages ? -panelWidth * (1 - tAnim) + spacing : null,
                    right: !isPages ? -panelWidth * (1 - tAnim) + spacing : null,
                    width: panelWidth,
                    child: Opacity(
                      opacity: tAnim.clamp(0.0, 1.0),
                      child: panelBody,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }


  Widget pageManager(BuildContext context, {int? pageIndexAtOpen}) {
    return EditorPageManager(
      coreInfo: coreInfo,
      currentPageIndex: pageIndexAtOpen ?? currentPageIndex,
      redrawAndSave: () => setState(() {
        if (coreInfo.readOnly) return;
        autosaveAfterDelay();
      }),
      pdfOutlines: coreInfo.pdfOutlines ?? const [],
      onOutlinePageSelected: (int pageIndex) {
        _navigateToPage(pageIndex, neighborWindow: 1);
      },
      onNavigateToPage: (int pageIndex) {
        _navigateToPage(pageIndex, neighborWindow: 1);
      },
      onAddOutline: () {
        if (coreInfo.readOnly) return;
        final pageIndex = (pageIndexAtOpen ?? currentPageIndex ?? 0).clamp(
          0,
          coreInfo.pages.length - 1,
        );
        final page = coreInfo.pages[pageIndex];
        final titleController = TextEditingController(
          text: 'Page ${pageIndex + 1}',
        );
        showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: Text(t.editor.navigation.addOutlineForPage),
              content: TextField(
                controller: titleController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: t.editor.navigation.outlineTitle,
                ),
                onSubmitted: (_) => Navigator.pop(dialogContext, true),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(t.common.cancel),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(t.common.done),
                ),
              ],
            );
          },
        ).then((confirmed) {
          final title = titleController.text.trim();
          titleController.dispose();
          if (confirmed != true || title.isEmpty) return;
          setState(() {
            coreInfo.pdfOutlines ??= <PdfOutlineItem>[];
            coreInfo.pdfOutlines!.add(
              PdfOutlineItem(
                title: title,
                pageIndex: pageIndex,
                pageId: page.id,
              ),
            );
            autosaveAfterDelay();
          });
        });
      },
      onRenameOutline: (item, newTitle) {
        if (coreInfo.readOnly) return;
        setState(() {
          item.title = newTitle;
          autosaveAfterDelay();
        });
      },
      onDeleteOutline: (item) {
        if (coreInfo.readOnly) return;
        setState(() {
          final roots = coreInfo.pdfOutlines;
          if (roots == null) return;
          removePdfOutlineItem(roots, item);
          if (roots.isEmpty) coreInfo.pdfOutlines = null;
          autosaveAfterDelay();
        });
      },
      insertPageAfter: insertPageAfter,
      insertPageBefore: insertPageBefore,
      duplicatePage: (int pageIndex) => setState(() {
        if (coreInfo.readOnly) return;
        if (coreInfo.isInfinite) return;
        final page = coreInfo.pages[pageIndex];
        final newPage = page.copyWith(
          id: coreInfo.allocatePageId(),
          strokes: page.strokes
              .map((stroke) => stroke.copy()..pageIndex += 1)
              .toList(),
          images: page.images
              .map((image) => image.copy()..pageIndex += 1)
              .toList(),
          quill: QuillStruct(
            controller: flutter_quill.QuillController(
              document: flutter_quill.Document.fromDelta(
                page.quill.controller.document.toDelta(),
              ),
              selection: const TextSelection.collapsed(offset: 0),
            ),
            focusNode: FocusNode(debugLabel: 'Quill Focus Node'),
          ),
          backgroundImage: page.backgroundImage?.copy()?..pageIndex += 1,
        );
        coreInfo.pages.insert(pageIndex + 1, newPage);
        listenToQuillChanges(newPage.quill, pageIndex + 1);
        syncPdfOutlinesWithPages(coreInfo.pdfOutlines, coreInfo.pages);
        history.recordChange(
          EditorHistoryItem(
            type: .insertPage,
            pageIndex: pageIndex,
            strokes: const [],
            images: const [],
            page: newPage,
          ),
        );
        autosaveAfterDelay();
      }),
      clearPage: clearPage,
      deletePage: (int pageIndex) => setState(() {
        if (coreInfo.readOnly) return;
        if (coreInfo.isInfinite) return;
        final page = coreInfo.pages.removeAt(pageIndex);
        coreInfo.links = coreInfo.links
            .where(
              (l) =>
                  (l.sourcePageId != null && l.sourcePageId != page.id) ||
                  (l.sourcePageId == null && l.sourcePageIndex != pageIndex),
            )
            .toList();
        syncPdfOutlinesWithPages(coreInfo.pdfOutlines, coreInfo.pages);
        if (coreInfo.pdfOutlines != null && coreInfo.pdfOutlines!.isEmpty) {
          coreInfo.pdfOutlines = null;
        }
        createPage(pageIndex - 1);
        try {
          unawaited(
            NoteLinksDatabase.instance.setLinksForPath(
              coreInfo.filePath,
              coreInfo.links,
              rootDirectory: FileManager.documentsDirectory,
            ),
          );
        } catch (e) {
          log.warning('Failed to update note links metadata: $e');
        }
        history.recordChange(
          EditorHistoryItem(
            type: .deletePage,
            pageIndex: pageIndex,
            strokes: const [],
            images: const [],
            page: page,
          ),
        );
        autosaveAfterDelay();
      }),
      transformationController: _transformationController,
    );
  }

  void insertPageAfter(int pageIndex) => setState(() {
    if (coreInfo.readOnly) return;
    if (coreInfo.isInfinite) return;
    if (coreInfo.hasUnhydratedLazyPages) coreInfo.hydrateAllLazyPages();
    final d = _newPageDefaults();
    final hasMargins =
        d.marginLeft > 0 ||
        d.marginRight > 0 ||
        d.marginTop > 0 ||
        d.marginBottom > 0;
    final page = EditorPage(
      id: coreInfo.allocatePageId(),
      size: _newPageSize(),
      backgroundPattern: d.pattern,
      backgroundColor: d.backgroundColor,
      lineColor: d.lineColor,
      lineHeight: d.lineHeight,
      lineThickness: d.lineThickness,
      hasLocalPattern: true,
      hasLocalBackgroundColor: true,
      hasLocalLineColor: true,
      hasLocalLineHeight: true,
      hasLocalLineThickness: true,
      hasLocalMargins: hasMargins,
      hasLocalBorderColor: d.borderColor != null,
      marginLeft: d.marginLeft,
      marginRight: d.marginRight,
      marginTop: d.marginTop,
      marginBottom: d.marginBottom,
      borderColor: d.borderColor,
    );

    coreInfo.pages.insert(pageIndex + 1, page);
    listenToQuillChanges(page.quill, pageIndex + 1);
    syncPdfOutlinesWithPages(coreInfo.pdfOutlines, coreInfo.pages);
    history.recordChange(
      EditorHistoryItem(
        type: .insertPage,
        pageIndex: pageIndex + 1,
        strokes: const [],
        images: const [],
        page: page,
      ),
    );
    autosaveAfterDelay();
  });

  void insertPageBefore(int pageIndex) => setState(() {
    if (coreInfo.readOnly) return;
    if (coreInfo.isInfinite) return;
    if (coreInfo.hasUnhydratedLazyPages) coreInfo.hydrateAllLazyPages();
    final d = _newPageDefaults();
    final hasMargins =
        d.marginLeft > 0 ||
        d.marginRight > 0 ||
        d.marginTop > 0 ||
        d.marginBottom > 0;
    final page = EditorPage(
      id: coreInfo.allocatePageId(),
      size: _newPageSize(),
      backgroundPattern: d.pattern,
      backgroundColor: d.backgroundColor,
      lineColor: d.lineColor,
      lineHeight: d.lineHeight,
      lineThickness: d.lineThickness,
      hasLocalPattern: true,
      hasLocalBackgroundColor: true,
      hasLocalLineColor: true,
      hasLocalLineHeight: true,
      hasLocalLineThickness: true,
      hasLocalMargins: hasMargins,
      hasLocalBorderColor: d.borderColor != null,
      marginLeft: d.marginLeft,
      marginRight: d.marginRight,
      marginTop: d.marginTop,
      marginBottom: d.marginBottom,
      borderColor: d.borderColor,
    );

    coreInfo.pages.insert(pageIndex, page);
    listenToQuillChanges(page.quill, pageIndex);
    syncPdfOutlinesWithPages(coreInfo.pdfOutlines, coreInfo.pages);
    history.recordChange(
      EditorHistoryItem(
        type: .insertPage,
        pageIndex: pageIndex,
        strokes: const [],
        images: const [],
        page: page,
      ),
    );
    autosaveAfterDelay();
  });

  void clearPage(int pageIndex) {
    if (coreInfo.readOnly) return;
    if (coreInfo.hasUnhydratedLazyPages) coreInfo.hydrateAllLazyPages();
    final page = coreInfo.pages[pageIndex];
    setState(() {
      final removedStrokes = page.strokes.toList();
      final removedImages = page.images.toList();
      page.strokes.clear();
      page.images.clear();
      removeExcessPages();
      history.recordChange(
        EditorHistoryItem(
          type: .erase,
          pageIndex: pageIndex,
          strokes: removedStrokes,
          images: removedImages,
        ),
      );
      autosaveAfterDelay();
    });
  }

  void clearAllPages() {
    if (coreInfo.readOnly) return;
    if (coreInfo.hasUnhydratedLazyPages) coreInfo.hydrateAllLazyPages();
    setState(() {
      final removedStrokes = <Stroke>[];
      final removedImages = <EditorImage>[];
      for (final page in coreInfo.pages) {
        removedStrokes.addAll(page.strokes);
        removedImages.addAll(page.images);
        page.strokes.clear();
        page.images.clear();
      }
      removeExcessPages();
      history.recordChange(
        EditorHistoryItem(
          type: .erase,
          pageIndex: 0,
          strokes: removedStrokes,
          images: removedImages,
        ),
      );
    });
    autosaveAfterDelay();
  }

  Future askUserToDisableReadOnly() async {
    final disableReadOnly =
        await showDialog(
          context: context,
          builder: (context) => AdaptiveAlertDialog(
            title: Text(t.editor.newerFileFormat.title),
            content: Text(t.editor.newerFileFormat.subtitle),
            actions: [
              CupertinoDialogAction(
                child: Text(t.common.cancel),
                onPressed: () => Navigator.pop(context, false),
              ),
              CupertinoDialogAction(
                child: Text(t.editor.newerFileFormat.allowEditing),
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        ) ??
        false;

    if (!mounted) return;
    if (!disableReadOnly) return;

    setState(() {
      coreInfo.readOnly = false;
    });
  }

  late int _lastCurrentPageIndex = coreInfo.initialPageIndex ?? 0;
  _ResizeViewportAnchor? _resizeViewportAnchor;
  double? _pageLayoutWidthOverride;
  int? _viewportStablePageIndex;

  double _currentViewportWidth() {
    if (!mounted) return 0;
    final canvasWidth =
        _canvasGestureDetectorKey.currentState?.containerBounds.maxWidth;
    if (canvasWidth != null && canvasWidth > 0 && canvasWidth.isFinite) {
      return canvasWidth;
    }
    final override = widget.viewportWidthOverride;
    if (override != null && override > 0) return override;
    if (!widget.embedded) {
      return MediaQuery.sizeOf(context).width;
    }
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 0;
    return width > 0 ? width : MediaQuery.sizeOf(context).width;
  }

  double _fittedPageHeight(int pageIndex, double screenWidth) {
    if (coreInfo.pages.isEmpty) return 0;
    final clamped = pageIndex.clamp(0, coreInfo.pages.length - 1);
    final pageSize = coreInfo.pages[clamped].size;
    if (pageSize.width <= 0 || pageSize.height <= 0) return 0;
    final pageWidthFitted = math.min(pageSize.width, screenWidth);
    return pageSize.height * (pageWidthFitted / pageSize.width);
  }

  _ResizeViewportAnchor? _captureResizeViewportAnchor() {
    if (!mounted || coreInfo.pages.isEmpty) return null;
    if (coreInfo.isInfinite) {
      return const _ResizeViewportAnchor(
        pageIndex: 0,
        relativePositionInPage: 0,
      );
    }
    final screenWidth = _currentViewportWidth();
    if (screenWidth <= 0) return null;

    final pageIndex = (_viewportStablePageIndex ?? _lastCurrentPageIndex).clamp(
      0,
      coreInfo.pages.length - 1,
    );
    final pageOffsets = _generatePageOffsets(coreInfo.pages, screenWidth);
    if (pageOffsets.isEmpty) return null;

    final pageTop = CanvasGestureDetector.getTopOfPage(
      pageIndex: pageIndex,
      pageOffsets: pageOffsets,
    );
    final pageHeight = _fittedPageHeight(pageIndex, screenWidth);
    if (pageHeight <= 0) return null;

    final documentScrollY = -scrollY;
    final relativePosition = (documentScrollY - pageTop) / pageHeight;

    return _ResizeViewportAnchor(
      pageIndex: pageIndex,
      relativePositionInPage: relativePosition,
    );
  }

  void _applyResizeViewportAnchor({
    double? viewportWidthOverride,
    double? viewportHeightOverride,
    bool horizontalOnly = false,
  }) {
    final anchor = _resizeViewportAnchor;
    if (anchor == null || !mounted || coreInfo.pages.isEmpty) return;
    if (_applyingResizeAnchor) return;
    _applyingResizeAnchor = true;
    try {
      final pageIndex = anchor.pageIndex.clamp(0, coreInfo.pages.length - 1);

      final laidOutWidth =
          _canvasGestureDetectorKey.currentState?.containerBounds.maxWidth;
      final viewportWidth =
          (viewportWidthOverride != null &&
              viewportWidthOverride > 0 &&
              viewportWidthOverride.isFinite)
          ? viewportWidthOverride
          : ((laidOutWidth != null && laidOutWidth > 0 && laidOutWidth.isFinite)
                ? laidOutWidth
                : (widget.viewportWidthOverride ?? _currentViewportWidth()));
      if (viewportWidth <= 0) return;

      // Frozen width for split-pane drags; live viewport width while a
      // docked sidebar animates so pages rescale with the panel.
      final layoutWidth =
          (_pageLayoutWidthOverride != null && _pageLayoutWidthOverride! > 0)
          ? _pageLayoutWidthOverride!
          : viewportWidth;

      final transformation = _transformationController.value;
      final scale = transformation.approxScale;
      final translation = transformation.getTranslation();

      // Horizontally center in the live viewport at any zoom (HUD stays put).
      final targetTranslationX = viewportWidth * (1 - scale) / 2;

      double targetTranslationY = translation.y;
      if (!horizontalOnly) {
        final pageOffsets = _generatePageOffsets(coreInfo.pages, layoutWidth);
        if (pageOffsets.isEmpty) return;

        final pageTop = CanvasGestureDetector.getTopOfPage(
          pageIndex: pageIndex,
          pageOffsets: pageOffsets,
        );
        final pageHeight = _fittedPageHeight(pageIndex, layoutWidth);
        if (pageHeight <= 0) return;

        final targetDocumentScrollY =
            pageTop + (anchor.relativePositionInPage * pageHeight);
        final gestureDetector = _canvasGestureDetectorKey.currentState;
        final laidOutHeight = gestureDetector?.containerBounds.maxHeight;
        final middle =
            (viewportHeightOverride != null && viewportHeightOverride > 0)
            ? viewportHeightOverride / 2
            : ((laidOutHeight != null && laidOutHeight > 0)
                  ? laidOutHeight / 2
                  : ((widget.viewportHeightOverride) != null
                        ? widget.viewportHeightOverride! / 2
                        : MediaQuery.sizeOf(context).height / 2));

        final targetScrollY = -targetDocumentScrollY;
        targetTranslationY = (targetScrollY - middle) * scale + middle;
      }

      if ((targetTranslationY - translation.y).abs() < 0.05 &&
          (targetTranslationX - translation.x).abs() < 0.05) {
        return;
      }

      final nextTransformation = transformation.clone()
        ..setTranslationRaw(
          targetTranslationX,
          targetTranslationY,
          translation.z,
        );
      _transformationController.value = nextTransformation;
    } finally {
      _applyingResizeAnchor = false;
    }
  }

  void _unlockResizeViewportAnchor() {
    _resizeViewportAnchor = null;
  }

  /// Returns to home after the first-page thumbnail is on disk/cache so the
  /// preview card can crossfade immediately.
  void _goToHome(BuildContext context) {
    _releaseAreaEraserQueueAndSessions();
    unawaited(_goToHomeAfterThumbnail(context));
  }

  Future<void> _goToHomeAfterThumbnail(BuildContext context) async {
    await _flushThumbnailBeforeExit();
    // Empty notes are auto-deleted on dispose — do not seed them into Recent.
    if (!_isEmptyNote()) {
      HomeDataCache.instance.rememberRecentPaths([coreInfo.filePath]);
    } else {
      HomeDataCache.instance.forgetRecentPaths([coreInfo.filePath]);
    }
    if (!context.mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('${RoutePaths.prefixOfHome}/${HomePage.recentSubpage}');
    }
  }

  void _markThumbnailWritten(String hash) {
    if (hash.isEmpty) return;
    _lastWrittenThumbnailHash = hash;
    coreInfo.firstPageHash = hash;
    coreInfo.notifyThumbnailGenerated();
  }

  Future<void> _flushThumbnailBeforeExit() async {
    if (coreInfo.readOnly || coreInfo.isInfinite || coreInfo.pages.isEmpty) {
      return;
    }
    final hash = coreInfo.calculateFirstPageHash();
    if (hash.isEmpty || hash == _lastWrittenThumbnailHash) return;
    try {
      final bytes = await _captureThumbnailBytesFromFirstPage();
      if (bytes == null || bytes.isEmpty) return;
      final path = '${coreInfo.filePath}${Editor.extension}.p';
      ThumbnailCache.instance.put(coreInfo.filePath, bytes);
      await FileManager.writeFile(path, bytes, awaitWrite: true);
      _markThumbnailWritten(hash);
    } catch (e) {
      log.fine('Exit thumbnail flush failed: $e');
    }
  }

  int get currentPageIndex {
    if (!mounted) return _lastCurrentPageIndex;
    if (_viewportStablePageIndex != null) {
      return _viewportStablePageIndex!.clamp(
        0,
        math.max(0, coreInfo.pages.length - 1),
      );
    }
    if (coreInfo.isInfinite || coreInfo.pages.length <= 1) {
      return _lastCurrentPageIndex = 0;
    }

    final screenWidth = _currentViewportWidth();

    return _lastCurrentPageIndex = getPageIndexFromScrollPosition(
      scrollY: -scrollY,
      screenWidth: screenWidth,
      pages: coreInfo.pages,
    );
  }

  @visibleForTesting
  static int getPageIndexFromScrollPosition({
    required double scrollY,
    required double screenWidth,
    required List<EditorPage> pages,
  }) {
    if (pages.length <= 1) return 0;

    final offsets = _generatePageOffsets(pages, screenWidth);

    return CanvasGestureDetector.getPageIndex(
      scrollY: scrollY,
      pageOffsets: offsets,
    );
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;

    final view = View.maybeOf(context);
    // Battery saver often flips refresh rate without a layout size change.
    DisplayInkFeel.instance.updateFromView(view);

    if (coreInfo.pages.isEmpty || coreInfo.isInfinite) return;
    if (view == null) return;
    final logical = view.physicalSize / view.devicePixelRatio;
    final last = _lastMetricsLogicalSize;
    _lastMetricsLogicalSize = logical;
    // Soft keyboard / system UI often fires metrics without a real size flip.
    if (last != null &&
        (last.width - logical.width).abs() < 1.0 &&
        (last.height - logical.height).abs() < 1.0) {
      return;
    }

    // Sidebar / split-divider sessions own the anchor; do not steal or end them.
    if (_resizeViewportAnchor != null ||
        _dockedSidePanelController.isAnimating) {
      return;
    }

    // Capture page from the still-current layout, then re-apply after the
    // orientation (or window) size change has laid out.
    _beginViewportResizeStabilization(freezePageLayout: false);
    _metricsOwnsResizeSession = true;
    final epoch = ++_metricsSettleEpoch;
    void settle() {
      if (!mounted || epoch != _metricsSettleEpoch) return;
      if (!_metricsOwnsResizeSession) return;
      _metricsOwnsResizeSession = false;
      if (_resizeViewportAnchor == null) return;
      _endViewportResizeStabilization();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _metricsSettleEpoch) return;
      // Second frame: canvas containerBounds usually match the new size.
      WidgetsBinding.instance.addPostFrameCallback((_) => settle());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (VaultAdapter.preventLock) return;
      // Do not release on [inactive] alone (keyboard, transient overlays); only
      // when the app is not expected to keep drawing (paused/hidden/detached).
      if (state != AppLifecycleState.inactive) {
        _releaseAreaEraserQueueAndSessions();
      }
      unawaited(
        saveToFile(force: true, awaitVaultCommit: true).catchError((e, st) {
          log.warning('Save on lifecycle pause failed: $e', e, st);
        }),
      );
    } else if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      _lastSaveTime = now;
      _lastTimeSpentUpdate = now;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    if (identical(
      NotesEyedropperTarget.canvasRepaintKey,
      _regionScreenshotBoundaryKey,
    )) {
      NotesEyedropperTarget.canvasRepaintKey = null;
    }

    if (_dockedSidePanelOcclusionActive) {
      TiledStrokePictureCache.popLayoutOcclusion();
      _dockedSidePanelOcclusionActive = false;
    }

    _pageRasterCache.dispose();
    PageRasterCacheManager.removeLodSettledListener(_onPageRasterLodSettled);

    _keepAliveController.dispose();
    _dockedSidePanelController
      ..removeListener(_onDockedSidePanelAnimTick)
      ..dispose();
    _skipTransformClampForExpansion.dispose();
    _suppressTransformClamp.dispose();

    _cleanUpAsync();

    _delayedSaveTimer?.cancel();
    _watchServerTimer?.cancel();
    _lastSeenPointerCountTimer?.cancel();
    _selectionLongPressTimer?.cancel();
    _penHoldRecognitionTimer?.cancel();
    _hideCalculator();

    _releaseAreaEraserQueueAndSessions();

    _removeKeybindings();

    stows.lastFountainPenOptions.notifyListeners();
    stows.lastBallpointPenOptions.notifyListeners();
    stows.lastHighlighterOptions.notifyListeners();

    _interactionRepaint.dispose();
    _eraserPositionRepaint.dispose();

    super.dispose();
  }

  void _cleanUpAsync() {
    final totalPages = coreInfo.pages.length;
    var disposed = false;

    void doDispose() {
      if (disposed) return;
      disposed = true;
      _isDisposed = true;
      // Restore global ink defaults so the next new note / home ink screen
      // sees the active preset — not this note's local toolbar edits.
      InkPresetLibrary.applyActive(stows);
      coreInfo.dispose();
    }

    if (_renameTimer?.isActive ?? false) {
      _renameTimer!.cancel();
      _renameFileNow()
          .then((_) {
            if (!_isDisposed) {
              filenameTextEditingController.dispose();
            }
          })
          .catchError((e) {
            log.warning('Rename in cleanup failed: $e');
            if (!_isDisposed) {
              filenameTextEditingController.dispose();
            }
          });
    } else {
      filenameTextEditingController.dispose();
    }

    if (_isDeleted) {
      unawaited(
        EditorRecoveryJournal.purgeAllForNote(
          noteBasePath: coreInfo.filePath,
          noteId: coreInfo.noteId,
        ),
      );
      doDispose();
      return;
    }

    if (_isEmptyNote()) {
      log.info('Note is empty on exit. Deleting automatically...');
      _isDeleted = true;
      HomeDataCache.instance.forgetRecentPaths([coreInfo.filePath]);

      FileManager.deleteFile(coreInfo.filePath + Editor.extension)
          .then((_) {
            return FileManager.deleteFile(
              '${coreInfo.filePath}${Editor.extension}.p',
            );
          })
          .then((_) {
            if (!_isDisposed) {
              _mathSolver.dispose();
              doDispose();
            }
          })
          .catchError((e) {
            log.warning('Failed to auto-delete empty note: $e');
            if (!_isDisposed) {
              _mathSolver.dispose();
              doDispose();
            }
          });
      return;
    }

    if (savingState.value == SavingState.saved &&
        !_saveFollowUpRequested &&
        !(_renameTimer?.isActive ?? false)) {
      // Leaving a saved editor must not leave recovery strokes behind for the
      // next note that reuses this display name.
      unawaited(_recoveryJournal?.clear() ?? Future<void>.value());
      log.fine(
        'Document ($totalPages pages) already persisted — dispose without redundant save',
      );
      _mathSolver.dispose();
      doDispose();
      return;
    }

    log.info('Document ($totalPages pages) - saving before dispose');

    saveToFile(force: true, updateThumbnail: true, awaitVaultCommit: true)
        .then((_) {
          if (!disposed) {
            log.info('Save completed, now disposing');

            _mathSolver.dispose();
            doDispose();
          }
        })
        .catchError((e) {
          log.severe('Save during cleanup failed: $e', e);
          if (!disposed) {
            _mathSolver.dispose();
            doDispose();
          }
        });
  }

  /// True when leaving the editor would auto-delete this note (no ink / media).
  bool get wouldAutoDeleteOnExit => _isEmptyNote();

  bool _isEmptyNote() {
    if (coreInfo.readOnly) return false;
    // Unhydrated shells still hold real content on disk — never auto-delete.
    if (coreInfo.hasUnhydratedLazyPages) return false;
    for (final page in coreInfo.pages) {
      if (page.isLazyShell) return false;

      if (page.allStrokesInDrawOrder.isNotEmpty) return false;
      if (page.allImagesInDrawOrder.isNotEmpty) return false;
      if (page.backgroundImage != null) return false;

      if (page.quill.controller.document.length > 1) return false;
    }
    return true;
  }

  Future<void> _showSelectionColorPicker() async {
    final select = Select.currentSelect;
    if (!select.doneSelecting || select.selectResult.strokes.isEmpty) return;

    final initialColor = select.selectResult.strokes.first.color;
    Color selectedColor = initialColor;

    final result = await showGeneralDialog<Color>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black.withValues(alpha: 0.4),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                width: 340,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Change Stroke Color',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ColorPicker(
                      color: selectedColor,
                      onColorChanged: (c) => selectedColor = c,
                      pickersEnabled: const <ColorPickerType, bool>{
                        ColorPickerType.primary: false,
                        ColorPickerType.accent: false,
                        ColorPickerType.wheel: true,
                        ColorPickerType.custom: false,
                      },
                      showColorCode: true,
                      colorCodeHasColor: true,
                      enableOpacity: false,
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 12,
                      children: stows.recentColorsPositioned.value.take(5).map((
                        hexString,
                      ) {
                        final c = Color(int.parse(hexString));
                        return InkWell(
                          onTap: () => Navigator.pop(context, c),
                          borderRadius: BorderRadius.circular(16),
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: CustomPaint(
                              painter: _SmoothCirclePainter(
                                color: c,
                                borderColor: Colors.white,
                                borderWidth: 2.0,
                                hasShadow: true,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () =>
                              Navigator.pop(context, selectedColor),
                          child: const Text('Apply'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );

    if (result != null && mounted) {
      setState(() {
        final colorChange = <Stroke, ColorChange>{};
        for (final stroke in select.selectResult.strokes) {
          colorChange[stroke] = ColorChange(
            previous: stroke.color,
            current: result,
          );
          stroke.color = result;
        }
        history.recordChange(
          EditorHistoryItem(
            type: EditorHistoryItemType.changeColor,
            pageIndex: select.selectResult.pageIndex,
            strokes: select.selectResult.strokes,
            colorChange: colorChange,
            images: [],
          ),
        );
      });
      autosaveAfterDelay();
    }
  }

  Future<void> _showSelectionStrokeTypePicker() async {
    final select = Select.currentSelect;
    if (!select.doneSelecting || select.selectResult.strokes.isEmpty) return;
    if (coreInfo.readOnly) return;

    final convertible = select.selectResult.strokes
        .where((s) => s.canConvertStrokeType)
        .toList(growable: false);
    if (convertible.isEmpty) return;

    final currentIds = convertible.map((s) => s.toolId).toSet();
    final initialId = currentIds.length == 1
        ? currentIds.single
        : convertible.first.toolId;

    final result = await showGeneralDialog<ToolId>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black.withValues(alpha: 0.4),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        final scheme = Theme.of(context).colorScheme;
        return Center(
          child: Material(
            color: Colors.transparent,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                width: 340,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      t.editor.selectionBar.changeStrokeTypeTitle,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t.editor.selectionBar.changeStrokeTypeHint,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...Pen.convertibleInkToolIds.map((id) {
                      final selected =
                          id == initialId && currentIds.length == 1;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Material(
                          color: selected
                              ? scheme.primary.withValues(alpha: 0.14)
                              : scheme.surfaceContainerHighest.withValues(
                                  alpha: 0.35,
                                ),
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => Navigator.pop(context, id),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  FaIcon(
                                    Pen.iconForTool(id),
                                    size: 18,
                                    color: selected
                                        ? scheme.primary
                                        : scheme.onSurface,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      Pen.displayNameForTool(id),
                                      style: TextStyle(
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        color: selected
                                            ? scheme.primary
                                            : scheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  if (selected)
                                    Icon(
                                      Icons.check_rounded,
                                      size: 20,
                                      color: scheme.primary,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(t.common.cancel),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );

    if (result == null || !mounted) return;
    _applySelectionStrokeType(result);
  }

  void _applySelectionStrokeType(ToolId newToolId) {
    final select = Select.currentSelect;
    if (!select.doneSelecting || select.selectResult.strokes.isEmpty) return;
    if (coreInfo.readOnly) return;

    final oldStrokes = <Stroke>[];
    final newStrokes = <Stroke>[];
    final selectionReplacement = <Stroke>[];

    for (final stroke in select.selectResult.strokes) {
      if (!stroke.canConvertStrokeType || stroke.toolId == newToolId) {
        selectionReplacement.add(stroke);
        continue;
      }
      final converted = Pen.convertStroke(stroke, newToolId);
      oldStrokes.add(stroke);
      newStrokes.add(converted);
      selectionReplacement.add(converted);
    }

    if (oldStrokes.isEmpty) return;

    setState(() {
      final pageIndices = <int>{};
      for (var i = 0; i < oldStrokes.length; i++) {
        final oldStroke = oldStrokes[i];
        final newStroke = newStrokes[i];
        final page = coreInfo.pages[oldStroke.pageIndex];
        page.removeStrokeFromAnyLayer(oldStroke);
        page.strokeSpatialIndex?.remove(oldStroke);
        page.insertStroke(newStroke);
        page.strokeSpatialIndex?.insert(newStroke);
        pageIndices.add(oldStroke.pageIndex);
      }
      for (final idx in pageIndices) {
        coreInfo.pages[idx].redrawStrokes();
      }

      select.selectResult = select.selectResult.copyWith(
        strokes: selectionReplacement,
        displayBounds: null,
      );

      history.recordChange(
        EditorHistoryItem(
          type: EditorHistoryItemType.changeStrokeType,
          pageIndex: select.selectResult.pageIndex,
          strokes: oldStrokes,
          strokesAdded: newStrokes,
          images: const [],
        ),
      );
    });
    _bumpInteractionRepaint();
    autosaveAfterDelay();
  }
}

class _ResizeViewportAnchor {
  const _ResizeViewportAnchor({
    required this.pageIndex,
    required this.relativePositionInPage,
  });

  final int pageIndex;
  final double relativePositionInPage;
}

class _CropOverlayPainter extends CustomPainter {
  _CropOverlayPainter({
    required this.cropRect,
    required this.scale,
    required this.accentColor,
  });

  final Rect cropRect;
  final double scale;
  final Color accentColor;

  @override
  void paint(ui.Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Rect.fromLTRB(
      cropRect.left * w,
      cropRect.top * h,
      cropRect.right * w,
      cropRect.bottom * h,
    );

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, w, h))
      ..addRect(rect);
    canvas.drawPath(
      path..fillType = PathFillType.evenOdd,
      Paint()..color = Colors.black.withOpacity(0.5),
    );

    final borderPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / scale;
    canvas.drawRect(rect, borderPaint);

    final thinPaint = Paint()
      ..color = accentColor.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 / scale;
    canvas.drawLine(
      Offset(rect.left + rect.width / 3, rect.top),
      Offset(rect.left + rect.width / 3, rect.bottom),
      thinPaint,
    );
    canvas.drawLine(
      Offset(rect.left + 2 * rect.width / 3, rect.top),
      Offset(rect.left + 2 * rect.width / 3, rect.bottom),
      thinPaint,
    );
    canvas.drawLine(
      Offset(rect.left, rect.top + rect.height / 3),
      Offset(rect.right, rect.top + rect.height / 3),
      thinPaint,
    );
    canvas.drawLine(
      Offset(rect.left, rect.top + 2 * rect.height / 3),
      Offset(rect.right, rect.top + 2 * rect.height / 3),
      thinPaint,
    );

    final handleRadius = 8.0 / scale;
    final handlePaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    void drawHandle(double x, double y) {
      canvas.drawCircle(Offset(x, y), handleRadius, handlePaint);
    }

    drawHandle(rect.left, rect.top);
    drawHandle(rect.right, rect.top);
    drawHandle(rect.left, rect.bottom);
    drawHandle(rect.right, rect.bottom);
    drawHandle(rect.center.dx, rect.top);
    drawHandle(rect.center.dx, rect.bottom);
    drawHandle(rect.left, rect.center.dy);
    drawHandle(rect.right, rect.center.dy);
  }

  @override
  bool shouldRepaint(_CropOverlayPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect ||
        oldDelegate.scale != scale ||
        oldDelegate.accentColor != accentColor;
  }
}

class _SmoothCirclePainter extends CustomPainter {
  _SmoothCirclePainter({
    required this.color,
    required this.borderColor,
    this.borderWidth = 2.0,
    this.hasShadow = false,
  });

  final Color color;
  final Color borderColor;
  final double borderWidth;
  final bool hasShadow;

  @override
  void paint(ui.Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final fillRadius = radius - borderWidth;
    final strokeRadius = radius - borderWidth / 2;

    if (hasShadow) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = Colors.black.withOpacity(0.26)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    canvas.drawCircle(
      center,
      fillRadius,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );

    if (borderWidth > 0 && borderColor != Colors.transparent) {
      canvas.drawCircle(
        center,
        strokeRadius,
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth
          ..isAntiAlias = true,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SmoothCirclePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.hasShadow != hasShadow;
  }
}

class EditorFlatSidePanel extends StatelessWidget {
  const EditorFlatSidePanel({
    super.key,
    required this.title,
    required this.body,
    required this.onClose,
    this.backgroundColor,
  });

  final String title;
  final Widget body;
  final VoidCallback onClose;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    final panelColor = backgroundColor ?? colorScheme.surface;

    return Material(
      color: panelColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: onClose,
                  tooltip: 'Close',
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(36, 36),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              child: body,
            ),
          ),
        ],
      ),
    );
  }
}