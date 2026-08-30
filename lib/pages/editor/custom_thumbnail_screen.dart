// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:hux/hux.dart';

class CustomThumbnailScreen extends StatefulWidget {
  final Uint8List imageBytes;

  const CustomThumbnailScreen({super.key, required this.imageBytes});

  @override
  State<CustomThumbnailScreen> createState() => _CustomThumbnailScreenState();
}

class _CustomThumbnailScreenState extends State<CustomThumbnailScreen> {
  ui.Image? _image;
  double _scale = 1.0;
  Offset _offset = Offset.zero;

  double _baseScale = 1.0;
  Offset _baseOffset = Offset.zero;
  bool _initializedScale = false;

  final GlobalKey _cropperKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    setState(() {
      _image = frame.image;
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    _baseScale = _scale;
    _baseOffset = _offset;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      _scale = (_baseScale * details.scale).clamp(0.1, 10.0);
      _offset = _baseOffset + details.focalPointDelta;
    });
  }

  Future<void> _cropAndSave() async {
    if (_image == null) return;

    final RenderBox renderBox =
        _cropperKey.currentContext!.findRenderObject() as RenderBox;
    final size = renderBox.size;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      Rect.fromLTWH(0, 0, size.width, size.height),
    );

    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.translate(size.width / 2 + _offset.dx, size.height / 2 + _offset.dy);
    canvas.scale(_scale);

    final srcRect = Rect.fromLTWH(
      0,
      0,
      _image!.width.toDouble(),
      _image!.height.toDouble(),
    );
    final dstRect = Rect.fromCenter(
      center: Offset.zero,
      width: _image!.width.toDouble(),
      height: _image!.height.toDouble(),
    );
    canvas.drawImageRect(_image!, srcRect, dstRect, Paint());

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.width.toInt(), size.height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

    if (byteData != null) {
      Navigator.pop(context, byteData.buffer.asUint8List());
    } else {
      Navigator.pop(context, null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuxTokens.surfacePrimary(context),
      appBar: AppBar(
        primary: false,
        title: Text(
          'Adjust Thumbnail',
          style: TextStyle(
            color: HuxTokens.textPrimary(context),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: HuxTokens.surfacePrimary(context),
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: HuxTokens.textPrimary(context)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0, top: 8.0, bottom: 8.0),
            child: HuxButton(
              onPressed: _image == null ? null : _cropAndSave,
              variant: HuxButtonVariant.primary,
              size: HuxButtonSize.small,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: _image == null
          ? const Center(child: HuxLoading(size: HuxLoadingSize.medium))
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: AspectRatio(
                        aspectRatio: 3 / 4,
                        child: LayoutBuilder(
                          builder: (context, constraints) {

                            if (_image != null && !_initializedScale) {
                              final boxAspect =
                                  constraints.maxWidth / constraints.maxHeight;
                              final imageAspect =
                                  _image!.width / _image!.height;
                              if (imageAspect > boxAspect) {
                                _scale = constraints.maxHeight / _image!.height;
                              } else {
                                _scale = constraints.maxWidth / _image!.width;
                              }
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted)
                                  setState(() {
                                    _initializedScale = true;
                                  });
                              });
                            }

                            return Container(
                              key: _cropperKey,
                              decoration: BoxDecoration(
                                color: HuxTokens.surfaceElevated(context),
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 24,
                                    spreadRadius: 4,
                                  ),
                                ],
                                border: Border.all(
                                  color: HuxTokens.borderPrimary(context),
                                  width: 1.5,
                                ),
                              ),
                              clipBehavior: Clip.hardEdge,
                              child: Stack(
                                children: [
                                  GestureDetector(
                                    onScaleStart: _onScaleStart,
                                    onScaleUpdate: _onScaleUpdate,
                                    child: Container(
                                      color: Colors
                                          .transparent,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Transform.translate(
                                            offset: _offset,
                                            child: Transform.scale(
                                              scale: _scale,
                                              child: FittedBox(
                                                fit: BoxFit.none,
                                                child: RawImage(image: _image),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
                  child: Text(
                    'Pinch to zoom and drag to move the image.\nWhat you see inside the box will be your thumbnail.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: HuxTokens.textSecondary(context),
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
