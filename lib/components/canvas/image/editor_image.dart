// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fast_image_resizer/fast_image_resizer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:saber/components/canvas/_asset_cache.dart';
import 'package:saber/data/editor/binary_writer.dart';
import 'package:saber/components/canvas/canvas_image.dart';
import 'package:saber/components/canvas/invert_widget.dart';
import 'package:saber/components/editor/pdf_link_detector.dart'
    as link_detector;
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

part 'png_editor_image.dart';
part 'pdf_editor_image.dart';
part 'svg_editor_image.dart';

sealed class EditorImage extends ChangeNotifier {

  int id;

  final String extension;

  final AssetCacheAll assetCacheAll;

  bool _isThumbnail = false;
  bool get isThumbnail => _isThumbnail;
  @mustCallSuper
  set isThumbnail(bool isThumbnail) {
    _isThumbnail = isThumbnail;
  }

  int pageIndex;
  void Function(EditorImage, Rect)? onMoveImage;
  void Function(EditorImage)? onDeleteImage;
  void Function()? onMiscChange;
  final VoidCallback? onLoad;

  Rect srcRect = Rect.zero;

  late Rect _dstRect = Rect.fromLTWH(
    0,
    0,
    CanvasImage.minImageSize,
    CanvasImage.minImageSize,
  );
  Rect get dstRect => _dstRect;
  set dstRect(Rect dstRect) {

    if (locked && _dstRect != Rect.zero) {

      if (dstRect.left != _dstRect.left || dstRect.top != _dstRect.top) {
        return;
      }
    }
    _dstRect = dstRect;
    if (_dstRect.width < CanvasImage.minImageSize ||
        _dstRect.height < CanvasImage.minImageSize) {
      final scale = math.max(
        CanvasImage.minImageSize / _dstRect.width,
        CanvasImage.minImageSize / _dstRect.height,
      );
      _dstRect = Rect.fromLTWH(
        _dstRect.left,
        _dstRect.top,
        _dstRect.width * scale,
        _dstRect.height * scale,
      );
    }
    notifyListeners();
  }

  Size naturalSize;

  Size? pageSize;

  bool newImage = false;

  bool invertible;

  BoxFit backgroundFit;

  double rotationDeg = 0.0;

  bool locked = false;

  bool contains(Offset position) {
    return dstRect.contains(position);
  }

  void rotate(double angleRad, Offset center) {
    if (locked || angleRad == 0.0) return;
    final imageCenter = dstRect.center;
    final dx = imageCenter.dx - center.dx;
    final dy = imageCenter.dy - center.dy;
    final cos = math.cos(angleRad);
    final sin = math.sin(angleRad);
    final rotatedCenter = Offset(
      center.dx + dx * cos - dy * sin,
      center.dy + dx * sin + dy * cos,
    );

    dstRect = Rect.fromCenter(
      center: rotatedCenter,
      width: dstRect.width,
      height: dstRect.height,
    );
    rotationDeg = (rotationDeg + angleRad * 180.0 / math.pi) % 360.0;
  }

  void scale(double factor, Offset center) {
    if (locked || factor == 1.0) return;
    final newWidth = dstRect.width * factor;
    final newHeight = dstRect.height * factor;
    final newLeft = center.dx - (center.dx - dstRect.left) * factor;
    final newTop = center.dy - (center.dy - dstRect.top) * factor;
    dstRect = Rect.fromLTWH(newLeft, newTop, newWidth, newHeight);
  }

  @protected
  EditorImage({
    required this.id,
    required this.assetCacheAll,
    required this.extension,
    required this.pageIndex,
    required this.pageSize,
    this.naturalSize = Size.zero,
    this.invertible = true,
    this.backgroundFit = BoxFit.contain,
    required this.onMoveImage,
    required this.onDeleteImage,
    required this.onMiscChange,
    this.onLoad,
    this.newImage = true,
    Rect dstRect = Rect.zero,
    this.srcRect = Rect.zero,
    bool isThumbnail = false,
  }) : assert(extension.startsWith('.')),
       _dstRect = dstRect,
       _isThumbnail = isThumbnail;

  factory EditorImage.fromJson(
    Map<String, dynamic> json, {
    required List<Uint8List>? inlineAssets,
    bool isThumbnail = false,
    required String sbnPath,
    required AssetCacheAll assetCacheAll,
  }) {
    String? extension = json['e'];
    if (extension == '.svg') {
      return SvgEditorImage.fromJson(
        json,
        inlineAssets: inlineAssets,
        isThumbnail: isThumbnail,
        sbnPath: sbnPath,
        assetCacheAll: assetCacheAll,
      );
    } else if (extension == '.pdf') {
      return PdfEditorImage.fromJson(
        json,
        inlineAssets: inlineAssets,
        isThumbnail: isThumbnail,
        sbnPath: sbnPath,
        assetCacheAll: assetCacheAll,
      );
    } else {
      return PngEditorImage.fromJson(
        json,
        inlineAssets: inlineAssets,
        isThumbnail: isThumbnail,
        sbnPath: sbnPath,
        assetCacheAll: assetCacheAll,
      );
    }
  }

  @mustBeOverridden
  @mustCallSuper
  Map<String, dynamic> toJson() => {
    'id': id,
    'e': extension,
    'i': pageIndex,
    'v': invertible,
    'f': backgroundFit.index,
    'x': dstRect.left,
    'y': dstRect.top,
    'w': dstRect.width,
    'h': dstRect.height,
    'rot': rotationDeg,
    if (locked) 'l': true,
    if (srcRect.left != 0) 'sx': srcRect.left,
    if (srcRect.top != 0) 'sy': srcRect.top,
    if (srcRect.width != 0) 'sw': srcRect.width,
    if (srcRect.height != 0) 'sh': srcRect.height,
    if (naturalSize.width != 0) 'nw': naturalSize.width,
    if (naturalSize.height != 0) 'nh': naturalSize.height,
  };

  @protected
  @mustCallSuper
  void writeBinary(BinaryWriter writer) {

    writer.writeInt(ImageBinaryKeys.version, 1);
    writer.writeString(ImageBinaryKeys.extension, extension);
    writer.writeInt(ImageBinaryKeys.pageIndex, pageIndex);
    writer.writeInt(ImageBinaryKeys.id, id);
    writer.writeBool(ImageBinaryKeys.invertible, invertible);
    writer.writeEnum(ImageBinaryKeys.backgroundFit, backgroundFit);

    writer.writeScaledFloat(ImageBinaryKeys.dstLeft, dstRect.left);
    writer.writeScaledFloatNoKey(dstRect.top);
    writer.writeScaledFloatNoKey(dstRect.width);
    writer.writeScaledFloatNoKey(dstRect.height);

    writer.writeScaledFloat(ImageBinaryKeys.srcLeft, srcRect.left);
    writer.writeScaledFloatNoKey(srcRect.top);
    writer.writeScaledFloatNoKey(srcRect.width);
    writer.writeScaledFloatNoKey(srcRect.height);

    writer.writeScaledFloat(ImageBinaryKeys.naturalWidth, naturalSize.width);
    writer.writeScaledFloatNoKey(naturalSize.height);

    writer.writeDouble(104, rotationDeg);
    writer.writeBool(ImageBinaryKeys.locked, locked);
  }

  void toBinary(BinaryWriter writer) {
    writeBinary(writer);
  }

  static Map<String, dynamic> readBinary(BinaryReader reader) {

    int key;
    final int version;
    key = reader.readKey();
    if (key == ImageBinaryKeys.version) {
      version = reader.readIntNoKey();
    } else {
      version = 0;
    }

    final String extension;
    key = reader.readKey();
    if (key != ImageBinaryKeys.extension) {
      throw Exception('EditorImage.fromBinary: extension not set');
    }
    extension = reader.readStringNoKey();

    final int pageIndex;
    key = reader.readKey();
    if (key != ImageBinaryKeys.pageIndex) {
      throw Exception('EditorImage.fromBinary: pageImage not set');
    }
    pageIndex = reader.readIntNoKey();

    final int id;
    key = reader.readKey();
    if (key != ImageBinaryKeys.id) {
      throw Exception('EditorImage.fromBinary: id not set');
    }
    id = reader.readIntNoKey();

    final bool invertible;
    key = reader.readKey();
    if (key != ImageBinaryKeys.invertible) {
      throw Exception('EditorImage.fromBinary: invertible not set');
    }
    invertible = reader.readBoolNoKey();

    final BoxFit backgroundFit;
    key = reader.readKey();
    if (key != ImageBinaryKeys.backgroundFit) {
      throw Exception('EditorImage.fromBinary: backgroundFit not set');
    }
    backgroundFit = reader.readEnum(BoxFit.values) as BoxFit;

    double left;
    double top;
    double width;
    double height;
    final Rect dstRect;
    key = reader.readKey();
    if (key != ImageBinaryKeys.dstLeft) {
      throw Exception('EditorImage.fromBinary: dstleft not set');
    }
    left = reader.readScaledFloat();
    top = reader.readScaledFloat();
    width = reader.readScaledFloat();
    height = reader.readScaledFloat();
    dstRect = Rect.fromLTWH(left, top, width, height);

    final Rect srcRect;
    key = reader.readKey();
    if (key != ImageBinaryKeys.srcLeft) {
      throw Exception('EditorImage.fromBinary: srcleft not set');
    }
    left = reader.readScaledFloat();
    top = reader.readScaledFloat();
    width = reader.readScaledFloat();
    height = reader.readScaledFloat();
    srcRect = Rect.fromLTWH(left, top, width, height);

    final Size naturalSize;
    key = reader.readKey();
    if (key != ImageBinaryKeys.naturalWidth) {
      throw Exception('EditorImage.fromBinary: size not set');
    }
    width = reader.readScaledFloat();
    height = reader.readScaledFloat();
    naturalSize = Size(width, height);

    double rotation = 0;
    bool locked = false;
    if (!reader.isEOF) {
      final peekKey = reader.peekKey();
      if (peekKey == 104) {

        reader.readKey();
        rotation = reader
            .readDoubleNoKey();
      }

      if (!reader.isEOF) {
        final peekKey2 = reader.peekKey();
        if (peekKey2 == ImageBinaryKeys.locked) {
          reader.readKey();
          locked = reader.readBoolNoKey();
        }
      }

    }

    return {
      'version': version,
      'extension': extension,
      'pageIndex': pageIndex,
      'id': id,
      'invertible': invertible,
      'backgroundFit': backgroundFit,
      'dstRect': dstRect,
      'srcRect': srcRect,
      'naturalSize': naturalSize,
      'rotation': rotation,
      'locked': locked,
    };
  }

  factory EditorImage.fromBinary(
    BinaryReader reader, {
    required Map<String, dynamic> imageInfo,
    required List<Uint8List>? inlineAssets,
    bool isThumbnail = false,
    required String sbnPath,
    required AssetCacheAll assetCacheAll,
  }) {
    if (imageInfo['extension'] == '.svg') {
      return SvgEditorImage.fromBinary(
        reader,
        imageInfo: imageInfo,
        inlineAssets: inlineAssets,
        isThumbnail: isThumbnail,
        sbnPath: sbnPath,
        assetCacheAll: assetCacheAll,
      );
    } else if (imageInfo['extension'] == '.pdf') {
      return PdfEditorImage.fromBinary(
        reader,
        imageInfo: imageInfo,
        inlineAssets: inlineAssets,
        isThumbnail: isThumbnail,
        sbnPath: sbnPath,
        assetCacheAll: assetCacheAll,
      );
    } else {
      return PngEditorImage.fromBinary(
        reader,
        imageInfo: imageInfo,
        inlineAssets: inlineAssets,
        isThumbnail: isThumbnail,
        sbnPath: sbnPath,
        assetCacheAll: assetCacheAll,
      );
    }
  }

  @visibleForTesting
  static bool shouldLoadOutImmediately = false;

  Completer? _firstLoadStatus;
  Completer<bool>? _shouldLoadOut;
  bool _loadedIn = false;
  bool get loadedIn => _loadedIn;

  Future<void> firstLoad();

  @mustBeOverridden
  @mustCallSuper
  Future<void> loadIn() async {
    _firstLoadStatus ??= Completer()..complete(firstLoad());
    if (!_firstLoadStatus!.isCompleted) {
      await _firstLoadStatus!.future;
    }

    _loadedIn = true;
    if (_shouldLoadOut?.isCompleted == false) _shouldLoadOut?.complete(false);
  }

  @mustBeOverridden
  @mustCallSuper
  Future<bool> loadOut() async {
    if (_shouldLoadOut == null) {
      _shouldLoadOut = Completer();
      if (shouldLoadOutImmediately) {
        _shouldLoadOut!.complete(true);
      } else {
        Future.delayed(const Duration(seconds: 5)).then((_) {

          if (_shouldLoadOut == null) return;
          if (_shouldLoadOut!.isCompleted) return;
          _shouldLoadOut!.complete(true);
        });
      }
    }

    final shouldLoadOut = await _shouldLoadOut!.future;
    _shouldLoadOut = null;
    if (shouldLoadOut) {
      _loadedIn = false;
    }
    return shouldLoadOut;
  }

  Future<void> precache(BuildContext context);

  Widget buildImageWidget({
    required BuildContext context,
    required BoxFit? overrideBoxFit,
    required bool isBackground,
    required bool invert,
    double renderScale = 1.0,
  });

  EditorImage copy();

  @visibleForTesting
  static Size resize(final Size before, final Size max) {
    double width = before.width,
        height = before.height,
        aspectRatio = width / height;

    if (width > max.width) {
      width = max.width;
      height = width / aspectRatio;
    }
    if (height > max.height) {
      height = max.height;
      width = height * aspectRatio;
    }

    return Size(width, height);
  }
}
