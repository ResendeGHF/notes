// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/components/theming/adaptive_switch.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:super_clipboard/super_clipboard.dart';

class CanvasImageDialog extends StatefulWidget {
  const CanvasImageDialog({
    super.key,
    required this.filePath,
    required this.image,
    required this.redrawImage,
    required this.isBackground,
    required this.toggleAsBackground,
    this.singleRow = false,
  });

  final String filePath;
  final EditorImage image;
  final VoidCallback redrawImage;

  final bool isBackground;
  final VoidCallback? toggleAsBackground;

  final bool singleRow;

  @override
  State<CanvasImageDialog> createState() => _CanvasImageDialogState();
}

class _CanvasImageDialogState extends State<CanvasImageDialog> {
  void setInvertible([bool? value]) => setState(() {
    widget.image.invertible = value ?? !widget.image.invertible;
    widget.image.onMiscChange?.call();
    widget.redrawImage();
  });

  Future<void> _copyImageToClipboard(EditorImage image) async {
    Uint8List? imageBytes;

    switch (image) {
      case final image when image.extension == '.pdf':

        final pdfBytes = (image as dynamic).pdfBytes;
        final pdfFile = (image as dynamic).pdfFile;
        imageBytes = pdfBytes ?? await pdfFile?.readAsBytes();
        break;
      case final image when image.extension == '.svg':

        final svgLoader = (image as dynamic).svgLoader;
        imageBytes = switch (svgLoader) {
          (final SvgStringLoader loader) => Uint8List.fromList(
            utf8.encode(loader.provideSvg(null)),
          ),
          (final SvgFileLoader loader) => await loader.file.readAsBytes(),
          (_) => null,
        };
        break;
      default:

        final imageProvider = (image as dynamic).imageProvider;
        if (imageProvider is MemoryImage) {
          imageBytes = imageProvider.bytes;
        } else if (imageProvider is FileImage) {
          try {
            imageBytes = await imageProvider.file.readAsBytes();
          } catch (e) {
            return;
          }
        }
        break;
    }

    if (imageBytes == null || imageBytes.isEmpty) return;

    try {
      if (image.extension == '.png' ||
          image.extension == '.jpg' ||
          image.extension == '.jpeg') {

        final buffer = await ui.ImmutableBuffer.fromUint8List(imageBytes);
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        final codec = await descriptor.instantiateCodec();
        final frame = await codec.getNextFrame();
        final decodedImage = frame.image;

        final byteData = await decodedImage.toByteData(
          format: ui.ImageByteFormat.png,
        );
        decodedImage.dispose();

        if (byteData == null) return;
        imageBytes = byteData.buffer.asUint8List();
      }

      if (imageBytes.isNotEmpty) {
        final clipboard = await SystemClipboard.instance;
        await clipboard?.write([
          DataWriterItem()..add(Formats.png(imageBytes)),
        ]);
      }
    } catch (e) {

      if (imageBytes != null && imageBytes.isNotEmpty) {
        final clipboard = await SystemClipboard.instance;
        await clipboard?.write([
          DataWriterItem()..add(Formats.png(imageBytes)),
        ]);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final children = <Widget>[
      MergeSemantics(
        child: _CanvasImageDialogItem(
          onTap: stows.editorAutoInvert.value ? setInvertible : null,
          title: t.editor.imageOptions.invertible,
          child: AdaptiveSwitch(
            value: widget.image.invertible,
            onChanged: stows.editorAutoInvert.value ? setInvertible : null,
            thumbIcon: WidgetStateProperty.all(
              widget.image.invertible
                  ? const Icon(Icons.invert_colors)
                  : const Icon(Icons.invert_colors_off),
            ),
          ),
        ),
      ),
      _CanvasImageDialogItem(
        onTap: () async {
          final filePathSanitized = widget.filePath.replaceAll(
            RegExp(r'[^a-zA-Z\d]'),
            '_',
          );
          final imageFileName =
              'image$filePathSanitized${widget.image.id}${widget.image.extension}';
          final List<int> bytes;
          switch (widget.image) {
            case final PdfEditorImage image:
              bytes = await image.assetCacheAll.getBytes(image.assetId);
            case final SvgEditorImage image:
              bytes = switch (image.svgLoader) {
                (final SvgStringLoader loader) => utf8.encode(
                  loader.provideSvg(null),
                ),
                (final SvgFileLoader loader) => await loader.file.readAsBytes(),
                (_) => throw ArgumentError.value(
                  image.svgLoader,
                  'svgLoader',
                  'Unknown SVG loader type',
                ),
              };
            case final PngEditorImage image:
              if (image.imageProvider is MemoryImage) {
                bytes = (image.imageProvider as MemoryImage).bytes;
              } else if (image.imageProvider is FileImage) {
                bytes = await (image.imageProvider as FileImage).file
                    .readAsBytes();
              } else {
                throw ArgumentError.value(
                  image.imageProvider,
                  'imageProvider',
                  'Unknown image provider type',
                );
              }
          }
          if (!context.mounted) return;
          FileManager.exportFile(
            imageFileName,
            bytes,
            isImage: true,
            context: context,
          );
          Navigator.of(context).pop();
        },
        title: t.editor.imageOptions.download,
        child: const AdaptiveIcon(
          icon: Icons.download,
          cupertinoIcon: CupertinoIcons.arrow_down_circle_fill,
        ),
      ),
      _CanvasImageDialogItem(
        onTap: () async {
          await _copyImageToClipboard(widget.image);
          if (!context.mounted) return;
          Navigator.of(context).pop();
        },
        title: 'Copy to clipboard',
        child: const AdaptiveIcon(
          icon: Icons.copy,
          cupertinoIcon: CupertinoIcons.doc_on_clipboard_fill,
        ),
      ),
      _CanvasImageDialogItem(
        onTap: () {
          widget.toggleAsBackground?.call();
          Navigator.of(context).pop();
        },
        title: widget.isBackground
            ? t.editor.imageOptions.removeAsBackground
            : t.editor.imageOptions.setAsBackground,
        child: const AdaptiveIcon(
          icon: Icons.wallpaper,
          cupertinoIcon: CupertinoIcons.photo_fill_on_rectangle_fill,
        ),
      ),
      _CanvasImageDialogItem(
        onTap: () {
          widget.image.onDeleteImage?.call(widget.image);
          widget.redrawImage();
          Navigator.of(context).pop();
        },
        title: t.editor.imageOptions.delete,
        child: const AdaptiveIcon(
          icon: Icons.delete,
          cupertinoIcon: CupertinoIcons.trash_fill,
        ),
      ),
    ];

    final gridView = GridView.count(
      crossAxisCount: widget.singleRow ? children.length : 2,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      shrinkWrap: true,
      children: children,
    );

    if (platform.isCupertino) {
      return AspectRatio(
        aspectRatio: widget.singleRow ? children.length / 1 : 2,
        child: gridView,
      );
    } else {
      return SizedBox(width: 250, child: gridView);
    }
  }
}

class _CanvasImageDialogItem extends StatelessWidget {
  const _CanvasImageDialogItem({

    super.key,
    required this.onTap,
    required this.title,
    required this.child,
  });

  final VoidCallback? onTap;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Material(
      color: colorScheme.primary.withValues(alpha: 0.05),
      borderRadius: .circular(8),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const .symmetric(horizontal: 8, vertical: 16),
          child: Column(
            children: [
              Expanded(child: child),
              Text(title, textAlign: .center),
            ],
          ),
        ),
      ),
    );
  }
}
