// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

part of 'editor_image.dart';

class PngEditorImage extends EditorImage {
  static final log = Logger('PngEditorImage');

  int assetId;

  final ValueNotifier<ImageProvider?> imageProviderNotifier;

  ImageProvider? get imageProvider => imageProviderNotifier.value;

  Uint8List? thumbnailBytes;
  Size thumbnailSize = Size.zero;

  Size? maxSize;

  @override
  set isThumbnail(bool isThumbnail) {
    super.isThumbnail = isThumbnail;
    if (isThumbnail && thumbnailBytes != null) {

    }
  }

  PngEditorImage({
    required super.id,
    required super.assetCacheAll,
    required this.assetId,
    required super.extension,
    required this.imageProviderNotifier,
    required super.pageIndex,
    required super.pageSize,
    this.maxSize,
    super.invertible,
    super.backgroundFit,
    required super.onMoveImage,
    required super.onDeleteImage,
    required super.onMiscChange,
    super.onLoad,
    super.newImage,
    super.dstRect,
    super.srcRect,
    super.naturalSize,
    this.thumbnailBytes,
    super.isThumbnail,
  });

  factory PngEditorImage.fromJson(
    Map<String, dynamic> json, {
    required List<Uint8List>? inlineAssets,
    bool isThumbnail = false,
    required String sbnPath,
    required AssetCacheAll assetCacheAll,
  }) {
    final assetIndexJson = json['a'] as int?;
    final String? ext = json['e'] ?? '.jpg';
    Uint8List? bytes;
    final int? assetIndex;
    File? imageFile;
    if (assetIndexJson != null) {
      if (inlineAssets == null) {
        imageFile = FileManager.getFile(
          '$sbnPath${Editor.extension}.$assetIndexJson',
        );
      } else {
        bytes = inlineAssets[assetIndexJson];
      }
    } else if (json['b'] != null) {
      bytes = Uint8List.fromList((json['b'] as List<dynamic>).cast<int>());
    } else {
      if (kDebugMode) {
        throw Exception('EditorImage.fromJson: image bytes not found');
      }
      bytes = Uint8List(0);
    }
    assert(
      bytes != null || imageFile != null,
      'Either bytes or imageFile must be non-null',
    );

    if (imageFile != null) {
      assetIndex = assetCacheAll.addSync(
        imageFile,
        ext!,
        assetIndexJson!,
        json.containsKey('ainf') ? json['ainf'] : null,
        json.containsKey('aph') ? json['aph'].toInt() : null,
        json.containsKey('afs') ? json['afs'] : null,
        json.containsKey('ah') ? json['ah'].toInt() : null,
      );
    } else {
      final tempFile = assetCacheAll.createRuntimeFile(ext!, bytes!);
      assetIndex = assetCacheAll.addSync(
        tempFile,
        ext,
        assetIndexJson!,
        json.containsKey('ainf') ? json['ainf'] : null,
        json.containsKey('aph') ? json['aph'].toInt() : null,
        json.containsKey('afs') ? json['afs'] : null,
        json.containsKey('ah') ? json['ah'].toInt() : null,
      );
    }
    if (assetIndex < 0) {
      throw Exception('EditorImage.fromJson: image not in assets');
    }

    final image = PngEditorImage(

      id: json['id'] ?? -1,
      assetCacheAll: assetCacheAll,
      assetId: assetIndex,
      extension: ext,
      imageProviderNotifier: assetCacheAll.getImageProviderNotifier(assetIndex),
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
      srcRect: Rect.fromLTWH(
        json['sx'] ?? 0,
        json['sy'] ?? 0,
        json['sw'] ?? 0,
        json['sh'] ?? 0,
      ),
      naturalSize: Size(json['nw'] ?? 0, json['nh'] ?? 0),
      thumbnailBytes: json['t'] != null
          ? Uint8List.fromList((json['t'] as List<dynamic>).cast<int>())
          : null,
      isThumbnail: isThumbnail,
    );
    image.rotationDeg = json['rot'] ?? 0.0;
    image.locked = json['l'] ?? false;
    return image;
  }

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll({
      'a': assetCacheAll.getAssetIdOnSave(
        assetId,
      ),
      'aph': assetCacheAll.getAssetPreviewHash(assetId),
      'afs': assetCacheAll.getAssetFileSize(
        assetId,
      ),
      if (assetCacheAll.getAssetFileInfo(assetId) != '')
        'ainf': assetCacheAll.getAssetFileInfo(assetId),
      if (assetCacheAll.getAssetHash(assetId) != null)
        'ah': assetCacheAll.getAssetHash(
          assetId,
        ),
    });

  @override
  void writeBinary(BinaryWriter writer) {
    super.writeBinary(writer);
    // CRITICAL: Use assetIdOnSave instead of assetId
    final assetIdToSave = assetCacheAll.getAssetIdOnSave(assetId);
    if (assetIdToSave < 0) {
      PngEditorImage.log.warning(
        'Attempting to save image with unused assetId $assetId. Using -1.',
      );
    }
    writer.writeInt(ImageBinaryKeys.assetId, assetIdToSave);

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

  factory PngEditorImage.fromBinary(
    BinaryReader reader, {
    required Map<String, dynamic> imageInfo,
    required List<Uint8List>? inlineAssets,
    bool isThumbnail = false,
    required String sbnPath,
    required AssetCacheAll assetCacheAll,
  }) {
    int? assetId;

    int? previewHash;
    int? fileSize;
    int? fullHash;
    String? fileInfo;

    while (!reader.isEOF) {
      final peekKey = reader.peekKey();
      if (peekKey == ImageBinaryKeys.assetId) {
        reader.readKey();
        assetId = reader.readIntNoKey();
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

    if (assetId == null || assetId < 0) {

      return PngEditorImage(
        id: imageInfo['id'],
        assetCacheAll: assetCacheAll,
        extension: imageInfo['extension'],
        assetId: -1,
        imageProviderNotifier: ValueNotifier<ImageProvider?>(
          MemoryImage(Uint8List(0)),
        ),
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
        srcRect: imageInfo['srcRect'],
        naturalSize: imageInfo['naturalSize'],
        isThumbnail: isThumbnail,
      )..rotationDeg = imageInfo['rotation'] ?? 0;
    }

    final File imageFile = FileManager.getFile(
      '$sbnPath${Editor.extension}.$assetId',
    );
    if (!imageFile.existsSync()) {
      if (!stows.localEncryptionEnabled.value) {
        log.warning('Image asset file does not exist: ${imageFile.path}');
      }
    }

    assetCacheAll.addSync(
      imageFile,
      imageInfo['extension'],
      assetId,
      fileInfo,
      previewHash,
      fileSize,
      fullHash,
    );

    final image = PngEditorImage(
      id: imageInfo['id'],
      assetCacheAll: assetCacheAll,
      extension: imageInfo['extension'],
      assetId: assetId,
      imageProviderNotifier: assetCacheAll.getImageProviderNotifier(assetId),
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
      srcRect: imageInfo['srcRect'],
      naturalSize: imageInfo['naturalSize'],
      isThumbnail: isThumbnail,
    );
    image.rotationDeg = imageInfo['rotation'] ?? 0;
    image.locked = imageInfo['locked'] ?? false;
    return image;
  }

  @override
  Future<void> firstLoad() async {
    assert(Isolate.current.debugName == 'main');

    if (srcRect.shortestSide == 0 || dstRect.shortestSide == 0) {

      final Uint8List bytes;
      if (imageProvider is MemoryImage) {
        bytes = (imageProvider as MemoryImage).bytes;
      } else if (imageProvider is FileImage) {
        bytes = await (imageProvider as FileImage).file.readAsBytes();
      } else {
        throw Exception(
          'EditorImage.getImage: imageProvider is ${imageProvider.runtimeType}',
        );
      }

      naturalSize = await ui.ImmutableBuffer.fromUint8List(bytes)
          .then((buffer) => ui.ImageDescriptor.encoded(buffer))
          .then(
            (descriptor) =>
                Size(descriptor.width.toDouble(), descriptor.height.toDouble()),
          );

      if (maxSize == null) {
        await stows.maxImageSize.waitUntilRead();
        maxSize = Size.square(stows.maxImageSize.value);
      }
      final Size reducedSize = EditorImage.resize(naturalSize, maxSize!);
      if (naturalSize.width != reducedSize.width && !isThumbnail) {
        await null;

        final resizedByteData = await resizeImage(
          bytes,
          width: reducedSize.width.toInt(),
          height: reducedSize.height.toInt(),
        );
        if (resizedByteData != null) {

          final tempImageFile = assetCacheAll.createRuntimeFile(
            '.png',
            resizedByteData.buffer.asUint8List(),
          );

          assetCacheAll.replaceImage(tempImageFile, assetId);
        }

        naturalSize = reducedSize;
      }

      if (srcRect.shortestSide == 0) {
        srcRect = srcRect.topLeft & naturalSize;
      }
      if (dstRect.shortestSide == 0) {
        final Size dstSize = pageSize != null
            ? EditorImage.resize(naturalSize, pageSize!)
            : naturalSize;
        dstRect = dstRect.topLeft & dstSize;
      }
    }

    if (naturalSize.shortestSide == 0) {
      naturalSize = Size(srcRect.width, srcRect.height);
    }

    if (isThumbnail) {
      isThumbnail = true;
    }
  }

  @override
  Future<void> loadIn() async => await super.loadIn();
  @override
  Future<bool> loadOut() async => await super.loadOut();

  @override
  Future<void> precache(BuildContext context) async {
    final provider = imageProviderNotifier.value;
    if (provider != null) {
      await precacheImage(provider, context);
    }
  }

  @override
  Widget buildImageWidget({
    required BuildContext context,
    required BoxFit? overrideBoxFit,
    required bool isBackground,
    required bool invert,
    double renderScale = 1.0,
  }) {
    final BoxFit boxFit;
    if (overrideBoxFit != null) {
      boxFit = overrideBoxFit;
    } else if (isBackground) {
      boxFit = backgroundFit;
    } else {
      boxFit = BoxFit.fill;
    }

    return ValueListenableBuilder<ImageProvider?>(
      valueListenable: imageProviderNotifier,
      builder: (context, provider, _) {
        if (provider == null) {
          return const SizedBox.shrink();
        }

        return InvertWidget(
          invert: invert,
          child: Image(image: provider, fit: boxFit),
        );
      },
    );
  }

  @override
  PngEditorImage copy() {
    final copied = PngEditorImage(
      id: id,
      assetCacheAll: assetCacheAll,
      assetId: assetId,
      extension: extension,
      imageProviderNotifier: imageProviderNotifier,
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
      srcRect: srcRect,
      naturalSize: naturalSize,
      thumbnailBytes: thumbnailBytes,
      isThumbnail: isThumbnail,
    );
    copied.rotationDeg = rotationDeg;
    copied.locked = locked;
    return copied;
  }
}
