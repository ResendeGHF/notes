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
        final tempFile = assetCacheAll.createRuntimeFile(
          '.pdf',
          pdfBytes,
        );
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
      id:
          json['id'] ??
          -1,
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

    json['a'] = assetCacheAll.getAssetIdOnSave(
      assetId,
    );
    json['pdfi'] = pdfPage;
    json['aph'] = assetCacheAll.getAssetPreviewHash(
      assetId,
    );
    json['afs'] = assetCacheAll.getAssetFileSize(
      assetId,
    );
    if (assetCacheAll.getAssetFileInfo(assetId) != '')
      json['ainf'] = assetCacheAll.getAssetFileInfo(assetId);
    if (assetCacheAll.getAssetHash(assetId) != null)
      json['ah'] = assetCacheAll.getAssetHash(
        assetId,
      );

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

    writer.writeInt(
      ImageBinaryKeys.previewHash,
      assetCacheAll.getAssetPreviewHash(assetId),
    );
    writer.writeInt(
      ImageBinaryKeys.fileSize,
      assetCacheAll.getAssetFileSize(assetId),
    );

    final fullHash = assetCacheAll.getAssetHash(assetId);
    if (fullHash != null) {
      writer.writeInt(ImageBinaryKeys.fullHash, fullHash);
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
        previewHash = reader.readIntNoKey();
      } else if (peekKey == ImageBinaryKeys.fileSize) {
        reader.readKey();
        fileSize = reader.readIntNoKey();
      } else if (peekKey == ImageBinaryKeys.fullHash) {
        reader.readKey();
        fullHash = reader.readIntNoKey();
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
        if (pdfDocument == null) {
          return _PdfLoadingPlaceholder(size: srcRect.size);
        }

        return _PdfPageRenderer(
          pdfDocument: pdfDocument,
          pageIndex: pdfPage,
          pdfFile: pdfFile,
          naturalSize: naturalSize,
          invert: invert,
          onPdfTap: onPdfTap,
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

class _PdfLoadingPlaceholder extends StatelessWidget {
  final Size size;

  const _PdfLoadingPlaceholder({required this.size});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF4F4F4);
    return ColoredBox(
      color: color,
      child: SizedBox.fromSize(size: size),
    );
  }
}

class _PdfPageRenderer extends StatefulWidget {
  final PdfDocument pdfDocument;
  final int pageIndex;
  final File? pdfFile;
  final Size naturalSize;
  final bool invert;
  final void Function(Offset, PdfDocument, int, File?)? onPdfTap;

  const _PdfPageRenderer({
    required this.pdfDocument,
    required this.pageIndex,
    required this.pdfFile,
    required this.naturalSize,
    required this.invert,
    this.onPdfTap,
  });

  @override
  State<_PdfPageRenderer> createState() => _PdfPageRendererState();
}

class _PdfPageRendererState extends State<_PdfPageRenderer> {
  var _links = <link_detector.PdfLink>[];
  var _linksLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadLinks();
  }

  @override
  void didUpdateWidget(_PdfPageRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pdfDocument != oldWidget.pdfDocument ||
        widget.pageIndex != oldWidget.pageIndex) {
      _linksLoaded = false;
      _links = [];
      _loadLinks();
    }
  }

  Future<void> _loadLinks() async {
    if (!mounted) return;
    final links = await link_detector.PdfLinkDetector.detectLinksOnPage(
      widget.pdfDocument,
      widget.pageIndex,
    );

    if (mounted) {
      setState(() {
        _links = links;
        _linksLoaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      fit: StackFit.passthrough,
      children: [
        InvertWidget(
          invert: widget.invert,
          child: PdfPageView(
            document: widget.pdfDocument,
            pageNumber: widget.pageIndex + 1,
            decoration: const BoxDecoration(),
          ),
        ),

        if (_linksLoaded && _links.isNotEmpty)
          Positioned.fill(
            child: CustomPaint(
              painter: _LinkHighlightPainter(
                links: _links,
                pdfNaturalSize: widget.naturalSize,
                color: colorScheme.primary,
              ),
            ),
          ),

        if (widget.onPdfTap != null)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: (details) {
                widget.onPdfTap?.call(
                  details.localPosition,
                  widget.pdfDocument,
                  widget.pageIndex,
                  widget.pdfFile,
                );
              },
            ),
          ),
      ],
    );
  }
}

class _LinkHighlightPainter extends CustomPainter {
  final List<link_detector.PdfLink> links;
  final Size pdfNaturalSize;
  final Color color;

  _LinkHighlightPainter({
    required this.links,
    required this.pdfNaturalSize,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (pdfNaturalSize.width == 0 || pdfNaturalSize.height == 0) return;

    final double scaleX = size.width / pdfNaturalSize.width;
    final double scaleY = size.height / pdfNaturalSize.height;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (final link in links) {
      final rect = link.rect;

      final double left = rect.left * scaleX;
      final double right = rect.right * scaleX;

      final double topFlutter = size.height - (rect.top * scaleY);
      final double bottomFlutter = size.height - (rect.bottom * scaleY);

      final double top = topFlutter < bottomFlutter
          ? topFlutter
          : bottomFlutter;
      final double bottom = topFlutter < bottomFlutter
          ? bottomFlutter
          : topFlutter;

      final visualRect = Rect.fromLTRB(left, top, right, bottom);

      canvas.drawRect(visualRect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LinkHighlightPainter oldDelegate) {
    return oldDelegate.links != links ||
        oldDelegate.color != color ||
        oldDelegate.pdfNaturalSize != pdfNaturalSize;
  }
}
