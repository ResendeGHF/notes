// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

part of 'editor_image.dart';

class SvgEditorImage extends EditorImage {
  late SvgLoader svgLoader;
  int assetId;

  static final log = Logger('SvgEditorImage');

  SvgEditorImage({
    required super.id,
    required super.assetCacheAll,
    required this.assetId,
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
    super.srcRect,
    super.naturalSize,
    super.isThumbnail,
  })  : assert(assetId >-1 ,
            'assetId must be set'),
        super(
          extension: '.svg',
        ) {
    svgLoader = SvgFileLoader(assetCacheAll.getAssetFile(assetId));
  }

  factory SvgEditorImage.fromJson(
    Map<String, dynamic> json, {
    required List<Uint8List>? inlineAssets,
    bool isThumbnail = false,
    required String sbnPath,
    required AssetCacheAll assetCacheAll,
  }) {
    String? extension = json['e'] as String?;
    assert(extension == null || extension == '.svg');

    final assetIndexJson = json['a'] as int?;
    Uint8List? svgBytes;
    final int? assetIndex;
    File? svgFile;
    if (assetIndexJson != null) {
      if (inlineAssets == null) {
        svgFile =
            FileManager.getFile('$sbnPath${Editor.extension}.$assetIndexJson');
      } else {
        svgBytes=inlineAssets[assetIndexJson];
        svgFile=assetCacheAll.createRuntimeFile(json['e'] ?? '.svg',svgBytes);
      }
    } else if (json['b'] != null) {
      svgBytes = json['b'];
      svgFile=assetCacheAll.createRuntimeFile(json['e'] ?? '.svg',svgBytes!);
    } else {
      log.warning('SvgEditorImage.fromJson: no svg string found');
    }
    if (svgFile != null) {
      assetIndex = assetCacheAll.addSync(
        svgFile,'.svg',assetIndexJson!,
        json.containsKey('ainf') ? json['ainf'] : null,
        json.containsKey('aph') ? json['aph'].toInt() : null,
        json.containsKey('afs') ? json['afs'] : null,
        json.containsKey('ah') ? json['ah'].toInt() : null,
      );
    }
    else {
      throw Exception('EditorImage.fromJson: svg image not in assets');
    }
    if (assetIndex<0){
      throw Exception('EditorImage.fromJson: svg image not in assets');
    }

    final image = SvgEditorImage(
      id: json['id'] ??
          -1,
      assetCacheAll: assetCacheAll,
      assetId: assetIndex,
      pageIndex: json['i'] ?? 0,
      pageSize: Size.infinite,
      invertible: json['v'] ?? true,
      backgroundFit:
          json['f'] != null ? BoxFit.values[json['f']] : BoxFit.contain,
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
      naturalSize: Size(
        json['nw'] ?? 0,
        json['nh'] ?? 0,
      ),
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
    final assetIdToSave = assetCacheAll.getAssetIdOnSave(assetId);
    writer.writeInt(ImageBinaryKeys.assetId, assetIdToSave != -1 ? assetIdToSave : -1);

    if (assetIdToSave != -1) {
      writer.writeInt(ImageBinaryKeys.previewHash, assetCacheAll.getAssetPreviewHash(assetId));
      writer.writeInt(ImageBinaryKeys.fileSize, assetCacheAll.getAssetFileSize(assetId));
      
      final fullHash = assetCacheAll.getAssetHash(assetId);
      if (fullHash != null) {
        writer.writeInt(ImageBinaryKeys.fullHash, fullHash);
      }
      
      final fileInfo = assetCacheAll.getAssetFileInfo(assetId);
      if (fileInfo.isNotEmpty) {
        writer.writeString(ImageBinaryKeys.fileInfo, fileInfo);
      }
    }
  }

  factory SvgEditorImage.fromBinary(
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
      } else if (peekKey == 104) {
         reader.readKey();
         reader.readDoubleNoKey();
      } else {
        break;
      }
    }
    
    if (assetId == null || assetId < 0) {
      assetId = -1;
    }
    
    if (assetId != -1) {
       final File svgFile = FileManager.getFile('$sbnPath${Editor.extension}.$assetId');
       if (svgFile.existsSync()) {
         assetCacheAll.addSync(svgFile, '.svg', assetId, fileInfo, previewHash, fileSize, fullHash);
       }
    }
    
    final image = SvgEditorImage(
      id: imageInfo['id'],
      assetCacheAll: assetCacheAll,
      assetId: assetId,
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
    if (srcRect.shortestSide == 0 || dstRect.shortestSide == 0) {
      final pictureInfo = await vg.loadPicture(svgLoader, null);
      naturalSize = pictureInfo.size;
      pictureInfo.picture.dispose();

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

    if (naturalSize == Size.zero) {
      naturalSize = Size(srcRect.width, srcRect.height);
    }
  }

  @override
  Future<void> loadIn() async => await super.loadIn();

  @override
  Future<bool> loadOut() async => await super.loadOut();

  @override
  Future<void> precache(BuildContext context) async {
    final pictureInfo = await vg.loadPicture(svgLoader, null);
    pictureInfo.picture.dispose();
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

    return InvertWidget(
      invert: invert,
      child: SvgPicture(
        svgLoader,
        fit: boxFit,
      ),
    );
  }

  @override
  SvgEditorImage copy() {

    final copied = SvgEditorImage(
      id: id,

      assetCacheAll: assetCacheAll,
      assetId: assetId,
      pageIndex: pageIndex,
      pageSize: Size.infinite,
      invertible: invertible,
      backgroundFit: backgroundFit,
      onMoveImage: onMoveImage,
      onDeleteImage: onDeleteImage,
      onMiscChange: onMiscChange,
      onLoad: onLoad,
      newImage: newImage,
      dstRect: dstRect,
      srcRect: srcRect,
      naturalSize: naturalSize,
      isThumbnail: isThumbnail,
    );
    copied.rotationDeg = rotationDeg;
    copied.locked = locked;
    return copied;
  }
}
