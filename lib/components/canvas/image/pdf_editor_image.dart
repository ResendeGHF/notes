// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

part of 'editor_image.dart';

class PdfEditorImage extends EditorImage {
  int assetId;

  final int pdfPage;

  final File? pdfFile;

  final void Function(
    Offset localPosition,
    PdfDocument pdfDocument,
    int pdfPage,
    File? pdfFile,
  )?
  onPdfTap;

  static final log = Logger('PdfEditorImage');

  PdfEditorImage({
    required super.id,
    required super.assetCacheAll,
    required this.assetId,
    required this.pdfFile,
    required this.pdfPage,
    required super.pageIndex,
    required super.pageSize,
    super.invertible,
    super.backgroundFit,
    required super.onMoveImage,
    required super.onDeleteImage,
    required super.onMiscChange,
    super.onLoad,
    super.newImage,
    super.dstRect,
    required super.naturalSize,
    super.isThumbnail,
    this.onPdfTap,
  }) : assert(
         !naturalSize.isEmpty,
         'naturalSize must be set for PdfEditorImage',
       ),
       assert(pdfFile != null, 'pdfFile must be set'),
       super(extension: '.pdf', srcRect: Rect.zero);

  factory PdfEditorImage.fromJson(
    Map<String, dynamic> json, {
    required List<Uint8List>? inlineAssets,
    bool isThumbnail = false,
    required String sbnPath,
    required AssetCacheAll assetCacheAll,
  }) {
    final String? extension = json['e'] as String?;
    assert(extension == null || extension == '.pdf');

    final assetIndexJson = json['a'] as int?;

    int? assetIndex;
    File? pdfFile;
    if (assetIndexJson != null) {
      if (inlineAssets == null) {
        pdfFile = FileManager.getFile(
          '$sbnPath${Editor.extension}.$assetIndexJson',
        );
        assetIndex = assetCacheAll.addSync(
          pdfFile,
          '.pdf',
          assetIndexJson,
          json.containsKey('ainf') ? json['ainf'] : null,
          json.containsKey('aph') ? json['aph'].toInt() : null,
          json.containsKey('afs') ? json['afs'] : null,
          json.containsKey('ah') ? json['ah'].toInt() : null,
        );
      } else {
        final pdfBytes = inlineAssets[assetIndexJson];
        final tempFile = assetCacheAll.createRuntimeFile('.pdf', pdfBytes);
        assetIndex = assetCacheAll.addSync(
          tempFile,
          '.pdf',
          assetIndexJson,
          json.containsKey('ainf') ? json['ainf'] : null,
          json.containsKey('aph') ? json['aph'].toInt() : null,
          json.containsKey('afs') ? json['afs'] : null,
          json.containsKey('ah') ? json['ah'].toInt() : null,
        );
      }
    } else {
      if (kDebugMode) {
        throw Exception('PdfEditorImage.fromJson: pdf bytes not found');
      }
      assetIndex = -1;
    }

    assert(assetIndex >= 0, 'Either pdfBytes or pdfFile must be non-null');

    if (assetIndex < 0) {
      throw Exception('EditorImage.fromJson: pdf image not in assets');
    }

    final image = PdfEditorImage(
      id: json['id'] ?? -1,
      assetCacheAll: assetCacheAll,
      assetId: assetIndex,
      pdfFile: pdfFile,
      pdfPage: json['pdfi'],
      pageIndex: json['i'] ?? 0,
      pageSize: Size.infinite,
      invertible: json['v'] ?? true,
      backgroundFit: json['f'] != null
          ? BoxFit.values[json['f']]
          : BoxFit.contain,
      onMoveImage: null,
      onDeleteImage: null,
      onMiscChange: null,
      onLoad: null,
      newImage: false,
      dstRect: Rect.fromLTWH(
        json['x'] ?? 0,
        json['y'] ?? 0,
        json['w'] ?? 0,
        json['h'] ?? 0,
      ),
      naturalSize: Size(json['nw'] ?? 0, json['nh'] ?? 0),
      isThumbnail: isThumbnail,
    );
    image.rotationDeg = json['rot'] ?? 0.0;
    image.locked = json['l'] ?? false;
    return image;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();

    json.remove('t');
    assert(!json.containsKey('a'));
    assert(!json.containsKey('b'));

    json['a'] = assetCacheAll.getAssetIdOnSave(assetId);
    json['pdfi'] = pdfPage;
    json['aph'] = assetCacheAll.getAssetPreviewHash(assetId);
    json['afs'] = assetCacheAll.getAssetFileSize(assetId);
    if (assetCacheAll.getAssetFileInfo(assetId) != '')
      json['ainf'] = assetCacheAll.getAssetFileInfo(assetId);
    if (assetCacheAll.getAssetHash(assetId) != null)
      json['ah'] = assetCacheAll.getAssetHash(assetId);

    return json;
  }

  @override
  void writeBinary(BinaryWriter writer) {
    super.writeBinary(writer);
    // CRITICAL: Use assetIdOnSave instead of assetId

    final assetIdToSave = assetCacheAll.getAssetIdOnSave(assetId);
    if (assetIdToSave < 0) {
      PdfEditorImage.log.warning(
        'Attempting to save PDF with unused assetId $assetId. Using -1.',
      );
    }
    writer.writeInt(ImageBinaryKeys.assetId, assetIdToSave);
    writer.writeInt(ImageBinaryKeys.pdfi, pdfPage);

    writer.writeUint32(
      ImageBinaryKeys.previewHash,
      assetCacheAll.getAssetPreviewHash(assetId),
    );
    writer.writeUint32(
      ImageBinaryKeys.fileSize,
      assetCacheAll.getAssetFileSize(assetId),
    );

    final fullHash = assetCacheAll.getAssetHash(assetId);
    if (fullHash != null) {
      writer.writeUint32(ImageBinaryKeys.fullHash, fullHash);
    }

    final fileInfo = assetCacheAll.getAssetFileInfo(assetId);
    if (fileInfo.isNotEmpty) {
      writer.writeString(ImageBinaryKeys.fileInfo, fileInfo);
    }
  }

  factory PdfEditorImage.fromBinary(
    BinaryReader reader, {
    required Map<String, dynamic> imageInfo,
    required List<Uint8List>? inlineAssets,
    bool isThumbnail = false,
    required String sbnPath,
    required AssetCacheAll assetCacheAll,
  }) {
    int? assetId;
    int? pdfPage;

    int? previewHash;
    int? fileSize;
    int? fullHash;
    String? fileInfo;

    while (!reader.isEOF) {
      final peekKey = reader.peekKey();

      if (peekKey == ImageBinaryKeys.assetId) {
        reader.readKey();
        assetId = reader.readIntNoKey();
      } else if (peekKey == ImageBinaryKeys.pdfi) {
        reader.readKey();
        pdfPage = reader.readIntNoKey();
      } else if (peekKey == 104) {
        reader.readKey();
        reader.readDoubleNoKey();
      } else if (peekKey == ImageBinaryKeys.previewHash) {
        reader.readKey();
        previewHash = reader.readUint32();
      } else if (peekKey == ImageBinaryKeys.fileSize) {
        reader.readKey();
        fileSize = reader.readUint32();
      } else if (peekKey == ImageBinaryKeys.fullHash) {
        reader.readKey();
        fullHash = reader.readUint32();
      } else if (peekKey == ImageBinaryKeys.fileInfo) {
        reader.readKey();
        fileInfo = reader.readStringNoKey();
      } else {
        break;
      }
    }

    if (assetId == null)
      throw Exception('PdfEditorImage.fromBinary: no assetId');
    if (pdfPage == null)
      throw Exception('PdfEditorImage.fromBinary: no pdfPage');

    final File pdfFile = FileManager.getFile(
      '$sbnPath${Editor.extension}.$assetId',
    );
    if (!pdfFile.existsSync()) {
      if (!stows.localEncryptionEnabled.value) {
        log.warning('PDF asset file does not exist: ${pdfFile.path}');
      }
    }

    assetCacheAll.addSync(
      pdfFile,
      '.pdf',
      assetId,
      fileInfo,
      previewHash,
      fileSize,
      fullHash,
    );

    final image = PdfEditorImage(
      id: imageInfo['id'],
      assetCacheAll: assetCacheAll,
      assetId: assetId,
      pdfFile: pdfFile,
      pdfPage: pdfPage,
      pageIndex: imageInfo['pageIndex'],
      pageSize: Size.infinite,
      invertible: imageInfo['invertible'],
      backgroundFit: imageInfo['backgroundFit'],
      onMoveImage: null,
      onDeleteImage: null,
      onMiscChange: null,
      onLoad: null,
      newImage: false,
      dstRect: imageInfo['dstRect'],
      naturalSize: imageInfo['naturalSize'],
      isThumbnail: isThumbnail,
    );
    image.rotationDeg = imageInfo['rotation'] ?? 0;
    image.locked = imageInfo['locked'] ?? false;
    return image;
  }

  @override
  Future<void> firstLoad() async {
    assert(srcRect.isEmpty);
    assert(!naturalSize.isEmpty);

    if (dstRect.isEmpty) {
      final dstSize = pageSize != null
          ? EditorImage.resize(naturalSize, pageSize!)
          : naturalSize;
      dstRect = dstRect.topLeft & dstSize;
    }
  }

  @override
  Future<void> loadIn() async => await super.loadIn();

  @override
  Future<bool> loadOut() async => await super.loadOut();

  @override
  Future<void> precache(BuildContext context) async {}

  @override
  Widget buildImageWidget({
    required BuildContext context,
    required BoxFit? overrideBoxFit,
    required bool isBackground,
    required bool invert,
    double renderScale = 1.0,
  }) {
    final pdfNotifier = assetCacheAll.getPdfNotifier(assetId);
    return ValueListenableBuilder(
      valueListenable: pdfNotifier,
      builder: (context, pdfDocument, child) {
        // Frame-1 mount: the renderer shows the cached JPEG tile and/or the
        // native hardware texture immediately (both need only the file path,
        // never pdfrx state). The pdfrx document streams in behind them and
        // arrives via this same builder WITHOUT remounting (stable key), so
        // first paint never waits on PdfDocument.openFile().
        final resolvedPath =
            assetCacheAll.getResolvedPdfPath(assetId) ?? pdfFile?.path;
        return _PdfPageRenderer(
          // Stable per note asset page: ancestor rebuilds and the late
          // pdfrx arrival must never remount this (remount drops textures).
          key: ValueKey('pdfpage_${assetId}_$pdfPage'),
          pdfDocument: pdfDocument,
          pageIndex: pdfPage,
          pdfFile: resolvedPath != null ? File(resolvedPath) : pdfFile,
          naturalSize: naturalSize,
          renderScale: renderScale,
          invert: invert,
          isThumbnail: isThumbnail,
          onPdfTap: onPdfTap,
          // First full paint signals the asset cache to start background
          // page-metadata streaming (deferred so the visible render wins
          // the single pdfrx worker queue).
          onFirstPaint: isThumbnail
              ? null
              : () => assetCacheAll.kickProgressiveLoad(assetId),
          // Phase-1 parse of just this page's window (see AssetCacheAll).
          onEnsureVisibleWindow: isThumbnail
              ? null
              : () => assetCacheAll.ensureVisiblePagesLoaded(assetId, pdfPage),
          tileIdentity: (
            size: assetCacheAll.getAssetFileSize(assetId),
            hash: assetCacheAll.getAssetPreviewHash(assetId),
          ),
        );
      },
    );
  }

  @override
  PdfEditorImage copy() {
    final copied = PdfEditorImage(
      id: id,
      assetCacheAll: assetCacheAll,
      assetId: assetId,
      pdfPage: pdfPage,
      pdfFile: pdfFile,
      pageIndex: pageIndex,
      pageSize: Size.infinite,
      invertible: invertible,
      backgroundFit: backgroundFit,
      onMoveImage: onMoveImage,
      onDeleteImage: onDeleteImage,
      onMiscChange: onMiscChange,
      onLoad: onLoad,
      newImage: true,
      dstRect: dstRect,
      naturalSize: naturalSize,
      isThumbnail: isThumbnail,
      onPdfTap: onPdfTap,
    );
    copied.rotationDeg = rotationDeg;
    copied.locked = locked;
    return copied;
  }
}

class _PdfBlankPage extends StatelessWidget {
  final Size size;

  const _PdfBlankPage({required this.size});

  @override
  Widget build(BuildContext context) {
    // Blank page base color: NO spinner, NO progress, NO skeleton. The page
    // number stays hidden until the texture arrives (see the InnerCanvas
    // indicator gate), so a loading page never shows the half-rendered
    // dark-page artifact. Content paints over this imminently (tile, then
    // raster); chrome would only train waiting.
    return SizedBox.fromSize(size: size);
  }
}

class _PdfPageRenderer extends StatefulWidget {
  /// The pdfrx document, or null while it opens. Tile cache and native
  /// textures need only [pdfFile] and mount before this arrives.
  final PdfDocument? pdfDocument;
  final int pageIndex;
  final File? pdfFile;
  final Size naturalSize;
  final double renderScale;
  final bool invert;
  final bool isThumbnail;
  final void Function(Offset, PdfDocument, int, File?)? onPdfTap;

  /// Fired once, shortly after the first full-resolution paint mounts, so
  /// background page-metadata streaming starts only when the visible render
  /// already owns the worker queue. Null for thumbnails (the main renderer
  /// owns the kick).
  final VoidCallback? onFirstPaint;

  /// Phase-1 parse trigger: loads just the visible window (this page ±2)
  /// from here outward, so deep pages never wait for 0..N streaming.
  /// Null for thumbnails.
  final VoidCallback? onEnsureVisibleWindow;

  /// Asset identity for tile cache keys (size + content hash from note
  /// metadata): stable across mtime churn, needs zero filesystem I/O.
  /// Null/absent falls back to stat keying inside the cache helper.
  final ({int size, int hash})? tileIdentity;

  const _PdfPageRenderer({
    super.key,
    required this.pdfDocument,
    required this.pageIndex,
    required this.pdfFile,
    required this.naturalSize,
    required this.renderScale,
    required this.invert,
    this.isThumbnail = false,
    this.onPdfTap,
    this.onFirstPaint,
    this.onEnsureVisibleWindow,
    this.tileIdentity,
  });

  @override
  State<_PdfPageRenderer> createState() => _PdfPageRendererState();
}

class _PdfPageRendererState extends State<_PdfPageRenderer> {
  StreamSubscription? _pageStatusSub;

  /// True once this page finished progressive loading. PdfPageView is only
  /// mounted when ready: mounting earlier renders blank, and the status flip
  /// later disposes the texture and re-renders (a visible blink seconds
  /// after opening). Thumbnails render offscreen and stay ungated.
  bool _pageReady = false;
  Timer? _readyFallbackTimer;

  /// Safety net if a page status event is ever missed: fall back to mounting
  /// anyway rather than spinning forever.
  static const _readyFallbackTimeout = Duration(seconds: 8);

  /// Instant first paint: low-res JPEG from the background tile cache,
  /// probed synchronously (no PDFium, no FFI). Shown under the live render.
  File? _thumbFile;
  Uint8List? _thumbMemory;
  String? _thumbCacheKey;

  /// Native GPU texture failed for this page (unsupported/encrypted/evicted):
  /// stick to pdfrx for the rest of this mount instead of retrying per build.
  bool _nativeFailed = false;

  /// Big-surface mode. `full` renders the whole page; `tiled` renders only
  /// the visible rect at native zoom resolution (deep zoom stays sharp);
  /// `released` holds no big surface (offscreen VRAM discipline) and shows
  /// the cached tile until the page re-enters the viewport.
  // Released until the post-frame retile proves visibility: band
  // members outside the viewport never mount full surfaces (no wasted
  // parses/renders ahead of the visible page). Thumbnails keep full.
  _PdfSurfaceMode _mode = _PdfSurfaceMode.released;

  /// Identity of the mounted big surface (`full` or `t:<clip>:<w>x<h>`).
  /// Retiling skips work when the key is unchanged.
  String? _surfaceKey;

  /// Viewport tick debounce (pan/zoom retile). Fires only; the rect compare
  /// inside [_retile] early-outs when nothing moved enough to matter.
  Timer? _viewportTimer;

  /// First-paint kick armed (background streaming + deferred links +
  /// neighbor prefetch). Fired exactly once per mount from render events —
  /// never timers — so queue order on the single pdfrx worker is provable:
  /// the visible render job always precedes streaming/text jobs.
  bool _kickArmed = false;
  bool _kickDone = false;
  bool _surfaceMountLogged = false;


  /// Native 512px fast-first-frame painted: upgrades the base texture to
  /// full size in place (ping-pong, old frame persists until the new one).
  bool _firstNativeFramePainted = false;


  @override
  void initState() {
    super.initState();
    Logger('PDFTIMING').info('PDFTIMING renderer.initState page=${widget.pageIndex} doc=${widget.pdfDocument == null ? "null" : "ready"}');
    _probeThumbnail();
    // Armed here; fired only from render events (native first frame, or
    // 400ms after pdfrx readiness). Arming alone queues nothing.
    _armKick();
    _watchPageAndLoadLinks();
    _ensureVisibleWindow();
    _renderTileOnMiss();
    if (!widget.isThumbnail) {
      PdfViewportBus.epoch.addListener(_onViewportTick);
      PdfViewportBus.settleEpoch.addListener(_onViewportSettle);
      PageRasterCacheManager.lodEpoch.addListener(_onLodEpoch);
      // Initial mode once layout exists (sizes needed for the rect math).
      WidgetsBinding.instance.addPostFrameCallback((_) => _retile());
      // One-shot safety net: if the first retile landed mid route-transition
      // (page genuinely offscreen then, no later tick), re-evaluate once the
      // transition settled. Cheap: no-op when the mode is already right.
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        if (mounted) _retile();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _PdfPageRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageIndex != widget.pageIndex ||
        oldWidget.isThumbnail != widget.isThumbnail ||
        oldWidget.pdfFile?.path != widget.pdfFile?.path ||
        (oldWidget.pdfDocument != null &&
            !identical(oldWidget.pdfDocument, widget.pdfDocument))) {
      _nativeFailed = false;
      _mode = widget.isThumbnail
          ? _PdfSurfaceMode.full
          : _PdfSurfaceMode.released;
      _surfaceKey = null;
      _nativeTiled = null;
      _tiledClip = null;
      _tiledBitmap = null;
      _firstNativeFramePainted = false;
      _kickArmed = false;
      _kickDone = false;
      _surfaceMountLogged = false;
      _clearTilePending();
      _probeThumbnail();
      _watchPageAndLoadLinks();
      if (!widget.isThumbnail) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _retile());
      }
      return;
    }
    if (oldWidget.pdfDocument == null && widget.pdfDocument != null) {
      // Late pdfrx arrival after frame-1 mount: wire page/links without
      // resetting the mounted native texture or re-probing disk.
      _watchPageAndLoadLinks();
      _ensureVisibleWindow();
      _renderTileOnMiss();
      return;
    }
    // Zoom bucket crossed (or rotation/invert irrelevant): retile soon so
    // deep zoom sharpens without per-frame re-renders.
    if (oldWidget.renderScale != widget.renderScale && !widget.isThumbnail) {
      _viewportTimer?.cancel();
      _viewportTimer = Timer(
        const Duration(milliseconds: 150),
        () => _retile(),
      );
    }
  }

  @override
  void dispose() {
    _clearTilePending();
    _pageStatusSub?.cancel();
    _pageStatusSub = null;
    _readyFallbackTimer?.cancel();
    _readyFallbackTimer = null;
    _viewportTimer?.cancel();
    _viewportTimer = null;
    try {
      PdfViewportBus.epoch.removeListener(_onViewportTick);
    } catch (_) {}
    try {
      PdfViewportBus.settleEpoch.removeListener(_onViewportSettle);
    } catch (_) {}
    try {
      PageRasterCacheManager.lodEpoch.removeListener(_onLodEpoch);
    } catch (_) {}
    super.dispose();
  }

  void _onViewportTick() {
    if (widget.isThumbnail || !mounted) return;
    _viewportTimer?.cancel();
    _viewportTimer = Timer(const Duration(milliseconds: 250), () => _retile());
  }

  /// Gesture settle: finger lifted — cancel the motion debounce and retile
  /// immediately instead of making the user sit out the remaining interval.
  void _onViewportSettle() {
    if (widget.isThumbnail || !mounted) return;
    _viewportTimer?.cancel();
    _viewportTimer = null;
    _retile();
  }

  /// LOD settle transitions (gesture end, programmatic jumps, motion clear):
  /// re-evaluate once the viewport is genuinely still. Combined with the
  /// motion gate in [_retile], tiles only ever render for a settled viewport.
  void _onLodEpoch() {
    if (widget.isThumbnail || !mounted) return;
    if (PageRasterCacheManager.viewportMoving) return;
    _retile();
  }

  void _watchPageAndLoadLinks() {
    _pageStatusSub?.cancel();
    _pageStatusSub = null;
    _readyFallbackTimer?.cancel();
    _readyFallbackTimer = null;

    if (widget.isThumbnail) {
      _pageReady = true;
      _ensureOwnTile();
      return;
    }

    final doc = widget.pdfDocument;
    // Document still opening (frame-1 mount): tile cache and native texture
    // paint from the file path meanwhile; arrival re-runs this via
    // didUpdateWidget.
    if (doc == null) {
      _pageReady = false;
      return;
    }

    final pages = doc.pages;
    if (widget.pageIndex < 0 || widget.pageIndex >= pages.length) {
      return;
    }

    final pdfPage = pages[widget.pageIndex];
    if (pdfPage.isLoaded) {
      _pageReady = true;
      _armKick();
      if (mounted) setState(() {});
      // Native-first-paint may have kicked before pdfrx readiness (empty
      // links, no tiles/prefetch): reload deferred work now that the page
      // (and its rotation) is known.
      if (_kickDone) {
        _ensureOwnTile();
        _prefetchNeighbors();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _retile());
      return;
    }

    // Page still streaming in: jump-start exactly this page (one worker job)
    // instead of waiting for the deferred progressive chunks to reach it,
    // and hold the tile until it is ready so the full-res texture mounts
    // exactly once and never blanks afterwards.
    _pageReady = false;
    unawaited(pdfPage.ensureLoaded().catchError((Object _) => pdfPage));
    // If progressive load finishes after our first attempt (or ensureLoaded
    // misses a status race), reload highlights when the page becomes ready.
    _pageStatusSub = pdfPage.events.listen((change) {
      if (change.page.isLoaded) {
        _pageReady = true;
        _readyFallbackTimer?.cancel();
        _readyFallbackTimer = null;
        _armKick();
        if (mounted) setState(() {});
        if (_kickDone) {
          _ensureOwnTile();
          _prefetchNeighbors();
        }
        WidgetsBinding.instance.addPostFrameCallback((_) => _retile());
      }
    });
    _readyFallbackTimer = Timer(_readyFallbackTimeout, () {
      _readyFallbackTimer = null;
      if (!_pageReady && mounted) {
        _pageReady = true;
        _armKick();
        setState(() {});
      }
    });
  }

  void _ensureVisibleWindow() {
    try {
      widget.onEnsureVisibleWindow?.call();
    } catch (_) {}
  }

  /// Arms the one-shot post-paint kick. The kick itself fires from render
  /// events — the native first frame, or 400ms after pdfrx readiness (by
  /// then the mount-queued full render strictly precedes anything the kick
  /// enqueues on the single pdfrx worker).
  void _armKick() {
    _kickArmed = true;
  }


  /// Event-bound kick: background page streaming, deferred link detection,
  /// own-tile caching and neighbor tile prefetch. All queue strictly after
  /// the visible render that triggered this call.
  void _doKick() {
    if (_kickDone || !_kickArmed) return;
    if (!mounted || widget.isThumbnail) return;
    _kickDone = true;
    Logger('PDFTIMING').info('PDFTIMING renderer.doKick page=${widget.pageIndex}');
    try {
      widget.onFirstPaint?.call();
    } catch (_) {}
    // Own tile for the next cold open + neighbors. (Link detection lives
    // in the editor sweep, scoped and ordered post-paint.)
    _ensureOwnTile();
    _prefetchNeighbors();
  }

  /// Neighbor tile prefetch, strictly post-paint: the current page's full
  /// render already owns the worker queue, so warming the next pages cannot
  /// delay first paint. Vault-safe (memory-only when unlocked).
  void _prefetchNeighbors() {
    try {
      final doc = widget.pdfDocument;
      if (doc == null) return;
      final path = widget.pdfFile?.path;
      if (path == null || path.isEmpty) return;
      final ident = widget.tileIdentity;
      final n = doc.pages.length;
      final upcoming = <int>[];
      for (var i = widget.pageIndex + 1; i < n && upcoming.length < 3; i++) {
        upcoming.add(i);
      }
      if (upcoming.isEmpty) return;
      PdfPageThumbnailCache.prefetch(
        doc: doc,
        pageIndices: upcoming,
        targetWidth: _policyPreviewWidth,
        jpegQuality: _policyPreviewQuality,
        // Same identity-first scheme as the probe: keys agree by
        // construction, no stat I/O, stable across mtime churn. Null keys
        // (no identity, no stat) are skipped inside prefetch.
        cacheKeyForPage: (i) => PdfPageThumbnailCache.keyForPage(
          fileSize: ident?.size,
          identityHash: ident?.hash,
          filePath: path,
          pageIndex: i,
          targetWidth: _policyPreviewWidth,
        ),
      );
    } catch (_) {}
  }

  /// Ensures this page's own low-res tile exists for the next cold open.
  /// Called for thumbnails (which never kick) and as the blur-up completion.
  /// Cold-open blur-up: when the probe MISSED (nothing to show), render
  /// one 360px tile immediately. It queues a single tiny job ahead of the
  /// full rasters and typically paints content ~seconds earlier on cold
  /// opens; warm opens skip it (probe hit, zero jobs). The kick still runs
  /// strictly after (streaming/text/prefetch unchanged).
  void _renderTileOnMiss() {
    if (widget.isThumbnail) return;
    final doc = widget.pdfDocument;
    if (doc == null) return;
    final key = _thumbCacheKey;
    if (key == null || _thumbFile != null || _thumbMemory != null) return;
    final pageIndex = widget.pageIndex;
    unawaited(
      PdfPageThumbnailCache.getOrRender(
        doc: doc,
        pageIndex: pageIndex,
        cacheKey: key,
        targetWidth: _policyPreviewWidth,
        jpegQuality: _policyPreviewQuality,
        stillNeeded: () =>
            mounted &&
            identical(widget.pdfDocument, doc) &&
            widget.pageIndex == pageIndex,
      ).then((_) {
        if (!mounted) return;
        if (!identical(widget.pdfDocument, doc) ||
            widget.pageIndex != pageIndex) {
          return;
        }
        final mem = PdfPageThumbnailCache.tryGetMemory(key);
        if (mem != null && mem.isNotEmpty) {
          setState(() => _thumbMemory = mem);
          return;
        }
        final f = PdfPageThumbnailCache.tryGetDiskFileSync(key);
        if (f != null) setState(() => _thumbFile = f);
      }).catchError((Object _) {}),
    );
  }

  void _ensureOwnTile() {
    final key = _thumbCacheKey;
    final doc = widget.pdfDocument;
    if (key == null || doc == null) return;
    if (_thumbFile != null || _thumbMemory != null) return;
    final pageIndex = widget.pageIndex;
    unawaited(
      PdfPageThumbnailCache.getOrRender(
        doc: doc,
        pageIndex: pageIndex,
        cacheKey: key,
        targetWidth: _policyPreviewWidth,
        jpegQuality: _policyPreviewQuality,
        // Still relevant when the encode finishes (page may have scrolled
        // away or the doc swapped meanwhile).
        stillNeeded: () =>
            mounted &&
            identical(widget.pdfDocument, doc) &&
            widget.pageIndex == pageIndex,
      ),
    );
  }


  /// Synchronous probe of the background tile cache: disk JPEG (or vault
  /// memory LRU) shown instantly while PDFium warms up. No async gap, no
  /// PDFium init on the first-paint path.
  void _probeThumbnail() {
    _thumbFile = null;
    _thumbMemory = null;
    _thumbCacheKey = null;
    try {
      final path = widget.pdfFile?.path;
      if (path == null || path.isEmpty) return;
      final ident = widget.tileIdentity;
      final key = PdfPageThumbnailCache.keyForPage(
        fileSize: ident?.size,
        identityHash: ident?.hash,
        filePath: path,
        pageIndex: widget.pageIndex,
        targetWidth: _policyPreviewWidth,
      );
      if (key == null) return;
      _thumbCacheKey = key;
      final mem = PdfPageThumbnailCache.tryGetMemory(key);
      if (mem != null && mem.isNotEmpty) {
        _thumbMemory = mem;
        Logger('PDFTIMING').info('PDFTIMING renderer.tileProbe MEM-HIT page=${widget.pageIndex}');
        return;
      }
      _thumbFile = PdfPageThumbnailCache.tryGetDiskFileSync(key);
      Logger('PDFTIMING').info('PDFTIMING renderer.tileProbe ${_thumbFile != null ? "DISK-HIT" : "MISS"} page=${widget.pageIndex}');
    } catch (_) {
      _thumbFile = null;
      _thumbMemory = null;
    }
  }


  int _pageRotationIndex() {
    try {
      final doc = widget.pdfDocument;
      if (doc == null) return 0;
      final pages = doc.pages;
      if (widget.pageIndex < 0 || widget.pageIndex >= pages.length) return 0;
      return pages[widget.pageIndex].rotation.index;
    } catch (_) {
      return 0;
    }
  }

  /// Recomputes this page's surface mode from the live viewport:
  /// - fully offscreen -> release the big surface (VRAM discipline), tile only;
  /// - deep zoom on a small visible fraction -> clipped tile at native
  ///   vector resolution (razor sharp at 400-800%);
  /// - otherwise -> full-page surface.
  /// Skips work when the surface key is unchanged. Disposes the previous
  /// big surface synchronously inside setState so two big surfaces are
  /// never resident at once.
  void _retile() {
    if (!mounted || widget.isThumbnail) return;
    // Native-eligible pages retile without pdfrx readiness (the OS renderer
    // never waits on pdfPage.isLoaded); pdfrx surfaces still need the page.
    final nativeOk = _nativeEligible();
    if (!_pageReady && !nativeOk) return;
    RenderBox? box;
    try {
      final ro = context.findRenderObject();
      if (ro is! RenderBox) return;
      box = ro;
    } catch (_) {
      return;
    }
    Size screen;
    double dpr;
    try {
      screen = MediaQuery.sizeOf(context);
      dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 4.0);
    } catch (_) {
      return;
    }
    final rotation = _pageRotationIndex();
    final displaySize = PdfTileMath.displaySize(widget.naturalSize, rotation);
    if (displaySize.isEmpty) return;
    final region = PdfTileMath.computeVisible(
      box: box,
      screenSize: screen,
      pageSizePt: displaySize,
    );

    final zoom = math.max(
      widget.renderScale,
      PdfTileMath.liveScaleOf(box, widget.renderScale),
    );
    // Hysteresis: enter tiled above threshold, leave below exit, so hovering
    // never flaps modes (each flap re-renders the base layer).
    final zoomIn = _mode == _PdfSurfaceMode.tiled
        ? zoom > PdfTileMath.tiledZoomExit
        : zoom > PdfTileMath.tiledZoomThreshold;
    final zoomWantsTile =
        zoomIn &&
        PdfTileMath.supportsTiling(rotation) &&
        !region.fullyOffscreen &&
        region.fraction < PdfTileMath.fullPageFractionThreshold &&
        !region.clip.isEmpty;
    // Backend: the native clip texture carries its page size, so the
    // renderer maps display space exactly (no pdfrx state needed); the
    // pdfrx sub-rect needs the loaded page.
    final useNative = zoomWantsTile && _nativeEligible();
    final tiling = zoomWantsTile && (useNative || _pageIsLoaded());

    if (region.fullyOffscreen) {
      if (_mode == _PdfSurfaceMode.released && _surfaceKey == null) return;
      _clearTilePending();
      setState(() {
        _mode = _PdfSurfaceMode.released;
        _surfaceKey = null;
      });
      return;
    }

    if (!tiling) {
      if (_mode == _PdfSurfaceMode.full && _surfaceKey == 'full') {
        _clearTilePending();
        return;
      }
      _clearTilePending();
      setState(() {
        _mode = _PdfSurfaceMode.full;
        _surfaceKey = 'full';
      });
      return;
    }

    // Tiled via the shared sampling grid: clip snapped to base-grid
    // multiples, density an integer multiple of the base density, bitmap
    // exact. Same key (clip+size at coarse granularity) across pan frames
    // would thrash; quantize the request to 8pt so small pans reuse the
    // mounted tile and only settle retiles re-render.
    final q = _quantizeRect(region.clip, 8.0);
    final need = _visiblePhysicalSize(box, screen, dpr);
    final basePxNow =
        PdfTileMath.baseBitmap(boxSize: box.size, devicePixelRatio: dpr);
    final baseDensity = displaySize.width > 0
        ? (basePxNow.width / displaySize.width)
        : dpr;
    // Tile budget from the performance profile: a 3072px tile costs
    // ~36MB + UI-thread decode (~hundreds of ms frozen) per settled zoom,
    // which reads as the app hanging on deep zoom. Balanced caps at 2048px
    // (still ~2x supersampling: sharpness preserved, jank collapsed).
    final plan = PdfTileMath.tilePlan(
      want: q,
      pageSize: displaySize,
      needPhysical: need,
      baseDensity: baseDensity.isFinite && baseDensity > 0
          ? baseDensity
          : dpr,
      cap: _policyTileEdge,
    );
    if (plan.clip.isEmpty) return;
    final bmp = (width: plan.width, height: plan.height);
    if (PageRasterCacheManager.viewportMoving) return;
    final key =
        '${useNative ? 'n' : 'p'}:'
        '${plan.clip.left.toStringAsFixed(1)},${plan.clip.top.toStringAsFixed(1)},'
        '${plan.clip.width.toStringAsFixed(1)},${plan.clip.height.toStringAsFixed(1)}:'
        '${bmp.width}x${bmp.height}';
    if (_mode == _PdfSurfaceMode.tiled &&
        _surfaceKey == key &&
        _nativeTiled == useNative) {
      _clearTilePending();
      return;
    }
    // Stability gate: commit only a re-requested key, i.e. two consecutive
    // evaluations agreeing the viewport settled here. A fresh request just
    // arms a re-check; the GPU keeps gliding committed surfaces meanwhile.
    // This collapses settle storms (bus debounce + settle flush + lodEpoch +
    // clamp corrections) into a single render per pause — no mid-gesture
    // churn, no back-and-forth swaps.
    if (key == _pendingTileKey) {
      _clearTilePending();
      setState(() {
        _mode = _PdfSurfaceMode.tiled;
        _surfaceKey = key;
        _nativeTiled = useNative;
        _tiledClip = plan.clip;
        _tiledBitmap = bmp;
      });
      return;
    }
    _pendingTileKey = key;
    _pendingTimer?.cancel();
    _pendingTimer = Timer(_policySettleConfirm, () {
      _pendingTimer = null;
      if (mounted) _retile();
    });
  }

  void _clearTilePending() {
    _pendingTileKey = null;
    _pendingTimer?.cancel();
    _pendingTimer = null;
  }

  /// Prefer the native clip texture (carries its page size for exact
  /// mapping). Set during [_retile]; part of the surface key so backend
  /// swaps remount the overlay (the base underneath never moves).
  bool? _nativeTiled;

  bool _pageIsLoaded() {
    try {
      final doc = widget.pdfDocument;
      if (doc == null) return false;
      final pages = doc.pages;
      if (widget.pageIndex < 0 || widget.pageIndex >= pages.length) {
        return false;
      }
      return pages[widget.pageIndex].isLoaded;
    } catch (_) {
      return false;
    }
  }

  Rect _quantizeRect(Rect r, double step) {
    double q(double v) => (v / step).round() * step;
    return Rect.fromLTWH(
      q(r.left),
      q(r.top),
      (q(r.width).clamp(step, double.infinity)).toDouble(),
      (q(r.height).clamp(step, double.infinity)).toDouble(),
    );
  }

  /// Physical pixels the widget's visible part occupies on screen.
  /// Uses the full transform (see [PdfTileMath.computeVisible]): the naive
  /// `localToGlobal(origin) & box.size` drops canvas zoom and sizes tiles
  /// at 1x logical resolution (fuzzy on OLED).
  Size _visiblePhysicalSize(RenderBox box, Size screen, double dpr) {
    try {
      final global = MatrixUtils.transformRect(
        box.getTransformTo(null),
        Offset.zero & box.size,
      );
      final vis = global.intersect(Offset.zero & screen);
      if (vis.isEmpty) return Size.zero;
      return Size(vis.width * dpr, vis.height * dpr);
    } catch (_) {
      return Size.zero;
    }
  }

  Rect? _tiledClip;
  ({int width, int height})? _tiledBitmap;

  /// Live PDF policy from Settings → Performance → Canvas (applies
  /// instantly, no restart). Keys embed widths, so a profile switch just
  /// cold-misses once and re-renders at the new tier.
  int get _policyTileEdge => DisplayInkFeel.instance.pdfTileMaxEdge;
  int get _policyBaseEdge => DisplayInkFeel.instance.pdfBaseMaxEdge;
  int get _policyPreviewWidth => DisplayInkFeel.instance.pdfPreviewWidthPx;
  int get _policyPreviewQuality =>
      DisplayInkFeel.instance.pdfPreviewJpegQuality;
  Duration get _policySettleConfirm =>
      DisplayInkFeel.instance.pdfSettleConfirm;

  /// Stability gate for tile commits (xnotes parity): a freshly computed
  /// tile key renders ONLY if an identical key was already requested by a
  /// previous evaluation — i.e. the viewport actually settled there.
  /// Back-to-back evaluations with different keys (gesture in flight,
  /// clamp corrections, snap-zoom) just refresh the pending key; nothing
  /// renders mid-motion, so swaps never chase the gesture (no flicker).
  /// The GPU glides the committed surfaces meanwhile.
  String? _pendingTileKey;
  Timer? _pendingTimer;

  bool _nativeEligible() {
    return !_nativeFailed &&
        !widget.isThumbnail &&
        PdfNativeTexture.shouldAttemptFor(
          widget.pdfFile?.path,
          vaultUnlocked: VaultAdapter.isUnlocked,
        );
  }

  // Note on surface release: child surface views self-release on unmount
  // (PdfNativeTextureView closes texture + document handle in dispose;
  // _PdfTiledRawView disposes its ui.Image; PdfPageView disposes its own).
  // Switching [_mode]/[_surfaceKey] therefore drops the old big surface
  // synchronously with the swap — VRAM never waits on GC.

  @override
  Widget build(BuildContext context) {
    // Native-first-paint: the OS renderer reads its own fd and never waits
    // on pdfrx page state, so an eligible page mounts its base texture on
    // frame 1. pdfrx surfaces still gate on _pageReady (mounting one early
    // renders blank and blinks on the status flip).
    final nativeEligible = _nativeEligible();
    final pdfrxReady = widget.isThumbnail || _pageReady;
    if ((!pdfrxReady && !nativeEligible) ||
        _mode == _PdfSurfaceMode.released) {
      return Stack(
        fit: StackFit.passthrough,
        children: [_thumbOrPlaceholder(), _tapOverlay()],
      );
    }
    final useNative = nativeEligible;

    // Event-bound kick: schedule it post-frame once a big surface mounts.
    // The render job is sent synchronously during the surface's build, so by
    // post-frame it strictly precedes anything this kick enqueues. No timers.
    if (_mode != _PdfSurfaceMode.released && !_surfaceMountLogged) {
      _surfaceMountLogged = true;
      Logger('PDFTIMING').info('PDFTIMING renderer.surface-mounted mode=$_mode page=${widget.pageIndex}');
    }
    // Kick strictly after mount: a big surface is present in THIS build, so
    // its render job was just sent and anything the kick enqueues queues
    // behind it (provable order, no timers). Native first-frame kicks via
    // onFirstFrame independently; whichever fires first wins (guarded once).
    if (_kickArmed && !_kickDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _doKick();
      });
    }

    // Geometry hoist: the overlay views return Positioned directly
    // (atomic box+pixel swaps), so they must sit directly under this Stack
    // — the page box is measured here once and passed down as props.
    return LayoutBuilder(
      builder: (context, constraints) {
        final displaySize = PdfTileMath.displaySize(
          widget.naturalSize,
          _pageRotationIndex(),
        );
        final boxSize = Size(
          constraints.maxWidth.isFinite && constraints.maxWidth > 0
              ? constraints.maxWidth
              : displaySize.width,
          constraints.maxHeight.isFinite && constraints.maxHeight > 0
              ? constraints.maxHeight
              : displaySize.height,
        );
        return Stack(
          fit: StackFit.passthrough,
          children: [
            // Instant tile under the live render: covers the raster gap with
            // an exact-aspect JPEG until the surface arrives (and after
            // release).
            _thumbOrPlaceholder(),
            // Base layer, IDENTICAL in full and tiled modes: same tree, same
            // keys, same resolution policy. Mode switches only add/remove
            // the overlay — the base never remounts, downgrades, or flashes.
            _baseSurface(useNative, boxSize),
            // Hi-res viewport tile over the base (deep zoom only). Positioned
            // in DOCUMENT space at its committed sourceRect: it glides with
            // the page instead of snapping to the live viewport.
            if (_mode == _PdfSurfaceMode.tiled &&
                _tiledClip != null &&
                _tiledBitmap != null)
              _tiledOverlay(boxSize, displaySize),
            _tapOverlay(),
          ],
        );
      },
    );
  }

  /// Full-page base surface, identical in every mode: zero-copy native
  /// texture when eligible (layout x DPR, capped at 2048px for seam VRAM),
  /// pdfrx [PdfPageView] otherwise (no pageSizeCallback: the old min() math
  /// neutered maximumDpi and could shrink the page box; 300 DPI never binds
  /// so the bitmap is exactly layout x DPR — sharp at rest, bounded).
  /// Same tree and keys across mode switches: entering tiled mode only
  /// adds the overlay, never remounts or re-renders the base.
  Widget _baseSurface(bool useNative, Size boxSize) {
    final path = widget.pdfFile?.path;
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 4.0);
    // Single source of truth with tilePlan (see below): both backends
    // rasterize this exact bitmap, so tiles refine (never phase-drift
    // from) the base sampling grid. Edge from the performance profile
    // (Performance 2048 / Balanced 2048 / Battery 1536).
    final basePx = PdfTileMath.baseBitmap(
      boxSize: boxSize,
      devicePixelRatio: dpr,
      edgeCap: _policyBaseEdge,
    );
    if (useNative && path != null) {
      // Until the first frame lands — and no cached tile covers the gap —
      // render a fast 512px frame (~20ms), then upgrade in place via the
      // ping-pong slot (old frame persists). Tiles always plan against the
      // FINAL grid below (upgrades land ~50ms after mount, long before any
      // settled tile renders).
      final hasThumb = _thumbFile != null || _thumbMemory != null;
      final firstPx = (_firstNativeFramePainted || hasThumb)
          ? basePx
          : PdfTileMath.baseBitmap(
              boxSize: boxSize,
              devicePixelRatio: dpr,
              edgeCap: 512,
            );
      final edge = _policyBaseEdge;
      final rw = firstPx.width.round().clamp(1, edge);
      final rh = firstPx.height.round().clamp(1, edge);
      return PdfNativeTextureView(
          // Stable per document page: res changes flow in place via
          // updatePageTexture (old frame persists until the new arrives).
          key: ValueKey(
            'pdftex_${widget.pdfFile?.path}_${widget.pageIndex}',
          ),
          filePath: path,
          pageIndex: widget.pageIndex,
          widthPx: rw,
          heightPx: rh,
          invert: widget.invert,
          fallback: _thumbOrPlaceholder(),
          onFirstFrame: () {
            if (!mounted) return;
            if (!_firstNativeFramePainted) {
              setState(() => _firstNativeFramePainted = true);
            }
            _doKick();
          },
          onFallback: () {
            if (mounted && !_nativeFailed) {
              setState(() => _nativeFailed = true);
            }
          },
        );
    }
    final doc = widget.pdfDocument;
    // Unreachable when the build gate passed with a pending document, except
    // thumbnails mounted pre-open: hold the tile until arrival (no remount).
    if (doc == null) return _thumbOrPlaceholder();
    return InvertWidget(
      invert: widget.invert,
      child: PdfPageView(
        document: doc,
        pageNumber: widget.pageIndex + 1,
        maximumDpi: 300,
        decoration: const BoxDecoration(),
        // Cap-only: the shared base bitmap (never DPI math — the old min()
        // neutered maximumDpi and could shrink the page box). Identical
        // bitmap to the native base: one sampling grid app-wide.
        pageSizeCallback: (_, __, ___) => basePx,
      ),
    );
  }

  /// Hi-res viewport tile over the base layer (deep zoom only): only the
  /// visible rect renders, at native vector resolution for the current zoom.
  /// Native clip texture when verified, pdfrx sub-rect raster otherwise.
  ///
  /// The overlay views position THEMSELVES from their committed pixels (see
  /// [PdfNativeTextureView], [_PdfTiledRawView]): box and pixels swap
  /// atomically, so pans glide the old tile along the document instead of
  /// teleporting stale pixels into the new box. Therefore the returned view
  /// must sit directly under the page Stack — no wrapper in between.
  Widget _tiledOverlay(Size boxSize, Size displaySize) {
    final clip = _tiledClip!;
    final bmp = _tiledBitmap!;
    final useNative =
        _nativeTiled == true &&
        _nativeEligible() &&
        widget.pdfFile?.path != null;
    if (useNative) {
      // Own texture/session: the base layer's texture stays untouched
      // underneath while this tile renders (no blanks, no base churn).
      // No InvertWidget wrapper: the view returns Positioned itself and
      // must sit directly under the page Stack (inversion is inside it).
      return PdfNativeTextureView(
        key: ValueKey(
          'pdftile_${widget.pdfFile?.path}_${widget.pageIndex}',
        ),
        filePath: widget.pdfFile!.path,
        pageIndex: widget.pageIndex,
        widthPx: bmp.width,
        heightPx: bmp.height,
        clip: PdfClip(clip, pageSize: displaySize),
        boxSize: boxSize,
        invert: widget.invert,
        // Transparent while opening: the base layer underneath covers.
        fallback: const SizedBox.shrink(),
        onFallback: () {
          if (mounted && !_nativeFailed) {
            setState(() => _nativeFailed = true);
          }
        },
      );
    }
    final doc = widget.pdfDocument;
    if (doc == null) return _thumbOrPlaceholder();
    // No InvertWidget wrapper: the raw view returns Positioned itself and
    // must sit directly under the page Stack (inversion is inside it).
    return _PdfTiledRawView(
      key: ValueKey(
        'pdftileraw_${widget.pdfFile?.path}_${widget.pageIndex}',
      ),
      document: doc,
      pageIndex: widget.pageIndex,
      clip: clip,
      displaySize: displaySize,
      boxSize: boxSize,
      invert: widget.invert,
      bitmapWidth: bmp.width,
      bitmapHeight: bmp.height,
    );
  }

  /// Cached low-res tile when available, else a blank page box. Same box
  /// as the page so the swap to the live render never reflows layout.
  /// Deliberately NO spinner/progress UI on PDF paths: the tile (when warm)
  /// or the first raster paints imminently, and a loading indicator trains
  /// users to wait instead of reading. Blank-then-content, never chrome.
  Widget _thumbOrPlaceholder() {
    final mem = _thumbMemory;
    if (mem != null && mem.isNotEmpty) {
      return Image.memory(
        mem,
        width: widget.naturalSize.width,
        height: widget.naturalSize.height,
        fit: BoxFit.fill,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
      );
    }
    final f = _thumbFile;
    if (f != null) {
      return Image.file(
        f,
        width: widget.naturalSize.width,
        height: widget.naturalSize.height,
        fit: BoxFit.fill,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, _, _) =>
            _PdfBlankPage(size: widget.naturalSize),
      );
    }
    return _PdfBlankPage(size: widget.naturalSize);
  }

  Widget _tapOverlay() {
    final doc = widget.pdfDocument;
    if (widget.onPdfTap == null || doc == null) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: (details) {
          widget.onPdfTap?.call(
            details.localPosition,
            doc,
            widget.pageIndex,
            widget.pdfFile,
          );
        },
      ),
    );
  }
}


/// Big-surface mode for [_PdfPageRendererState].
enum _PdfSurfaceMode {
  /// Whole-page surface (native texture or pdfrx PdfPageView).
  full,

  /// Viewport-clipped tile at native zoom resolution (native clip texture
  /// or pdfrx sub-rect raster).
  tiled,

  /// No big surface (offscreen VRAM discipline): cached tile only.
  released,
}

/// pdfrx sub-rect raster for tiled deep-zoom mode.
///
/// Renders only [clip] (displayed page points) at [bitmapWidth]x[bitmapHeight]
/// and paints the resulting [RawImage] at its natural pixel size; the parent
/// positions it over the page at the clip offset. One job on the pdfrx worker,
/// cancellable when a retile supersedes it, disposed synchronously on unmount
/// so tiled swaps never stack VRAM.
///
/// Rotation is intentionally unsupported (the parent only mounts this for
/// unrotated pages): sub-rect/render-rotation interaction is backend-defined,
/// and a wrongly-oriented tile is worse than a full-page fallback.
class _PdfTiledRawView extends StatefulWidget {
  const _PdfTiledRawView({
    super.key,
    required this.document,
    required this.pageIndex,
    required this.clip,
    required this.displaySize,
    required this.boxSize,
    this.invert = false,
    required this.bitmapWidth,
    required this.bitmapHeight,
  });

  final PdfDocument document;
  final int pageIndex;

  /// Visible rect in displayed page points.
  final Rect clip;

  /// Full displayed page size in points.
  final Size displaySize;

  /// Page box in local units, for mapping the committed clip to a
  /// [Positioned] rect (same contract as the native tile overlay).
  final Size boxSize;

  /// Dark-mode inversion, applied INSIDE the positioned box (a wrapper
  /// above the [Positioned] would break Stack parent-data).
  final bool invert;
  final int bitmapWidth;
  final int bitmapHeight;

  @override
  State<_PdfTiledRawView> createState() => _PdfTiledRawViewState();
}

class _PdfTiledRawViewState extends State<_PdfTiledRawView> {
  ui.Image? _image;

  /// Clip the displayed pixels were rendered for. Updated atomically with
  /// [_image]: the box never moves ahead of its pixels (no teleport).
  Rect? _committedClip;
  PdfPageRenderCancellationToken? _token;
  Object? _job;

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void didUpdateWidget(covariant _PdfTiledRawView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Document/page change: drop stale pixels SYNCHRONOUSLY. Showing the
    // previous document's tile for even one frame (until the new render
    // arrives) is a cross-PDF content leak — the tile underlay covers.
    if (!identical(oldWidget.document, widget.document) ||
        oldWidget.pageIndex != widget.pageIndex) {
      _job = null;
      _token?.cancel();
      _token = null;
      _image?.dispose();
      _image = null;
      _committedClip = null;
      _render();
      return;
    }
    // Reuse (no remount flash): the previous tile stays painted at its
    // committed sourceRect until the new clip finishes rendering. The
    // cancellation token aborts the superseded worker job.
    if (oldWidget.clip != widget.clip ||
        oldWidget.bitmapWidth != widget.bitmapWidth ||
        oldWidget.bitmapHeight != widget.bitmapHeight ||
        oldWidget.displaySize != widget.displaySize) {
      _render();
    } else if (oldWidget.boxSize != widget.boxSize) {
      // Layout-only change: reposition the committed box without
      // re-rendering (pixels are unchanged).
      setState(() {});
    }
  }

  @override
  void dispose() {
    _job = null;
    _token?.cancel();
    _token = null;
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  Future<void> _render() async {
    final job = Object();
    _job = job;
    final reqClip = widget.clip;
    final reqW = widget.bitmapWidth;
    final reqH = widget.bitmapHeight;
    try {
      final pages = widget.document.pages;
      if (widget.pageIndex < 0 || widget.pageIndex >= pages.length) return;
      final page = pages[widget.pageIndex];
      if (!page.isLoaded) {
        try {
          await page.ensureLoaded();
        } catch (_) {
          return;
        }
      }
      if (!mounted || !identical(_job, job)) return;
      // Independent per-axis densities: the requested bitmap is integer
      // pixels while the clip is floating point, so a single shared density
      // leaves X/Y up to half a pixel asymmetric — stretched under fill.
      // Pre-distorting each axis exactly cancels the rounding instead.
      final sx = reqClip.width > 0 ? reqW / reqClip.width : 1.0;
      final sy = reqClip.height > 0 ? reqH / reqClip.height : 1.0;
      if (!sx.isFinite || sx <= 0 || !sy.isFinite || sy <= 0) return;
      final fullW = widget.displaySize.width * sx;
      final fullH = widget.displaySize.height * sy;
      if (!fullW.isFinite || !fullH.isFinite || fullW <= 0 || fullH <= 0) {
        return;
      }
      _token?.cancel();
      _token = page.createCancellationToken();
      // Request EXACTLY the snapped bitmap size (see bitmapSizeFor's aspect
      // lock): recomputing dimensions here could differ by a pixel and
      // reintroduce the skew the snap removes.
      final pdfImage = await page.render(
        x: (reqClip.left * sx).round(),
        y: (reqClip.top * sy).round(),
        width: reqW,
        height: reqH,
        fullWidth: fullW,
        fullHeight: fullH,
        backgroundColor: 0xffffffff,
        cancellationToken: _token,
      );
      if (pdfImage == null) return;
      try {
        final img = await pdfImage.createImage();
        if (!mounted || !identical(_job, job)) {
          img.dispose();
          return;
        }
        // Atomic commit: image and clip swap together so the box never
        // moves ahead of its pixels (no teleport/displacement flicker).
        // A newer request supersedes this one via didUpdateWidget.
        if (widget.clip != reqClip ||
            widget.bitmapWidth != reqW ||
            widget.bitmapHeight != reqH) {
          img.dispose();
          return;
        }
        _image?.dispose();
        _image = img;
        _committedClip = reqClip;
        if (mounted) setState(() {});
      } finally {
        pdfImage.dispose();
      }
    } catch (_) {
      // Cancellation and worker races land here; the tile underlay covers.
    }
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    final committed = _committedClip;
    if (img == null || committed == null) return const SizedBox.shrink();
    // Document-space box for the committed pixels (same contract as the
    // native tile overlay). Must stay a direct child of a Stack.
    final pos = PdfTileMath.tileBox(
      clipPt: committed,
      boxSize: widget.boxSize,
      pageSizePt: widget.displaySize,
    );
    if (pos.isEmpty) return const SizedBox.shrink();
    // Atomic swap, no dissolve (see native overlay): with the stability
    // gate, arrivals are rare and settled, so a fade would only add a soft
    // flash between two correct frames.
    return Positioned.fromRect(
      rect: pos,
      // Bitmap aspect matches the clip aspect: fill is exact, no distortion.
      child: InvertWidget(
        invert: widget.invert,
        child: RawImage(
          image: img,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
