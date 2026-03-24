// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/painting.dart';

class BinaryWriter {

  static const double _scale = 1000.0;

  final BytesBuilder _buffer = BytesBuilder();
  final ByteData _scratch4 = ByteData(4);
  final ByteData _scratch8 = ByteData(8);

  void clear() {
    _buffer.clear();
  }

  void writeKey(int key) {
    _buffer.addByte(key);
  }

  void writeInt(int key, int val) {
    _scratch4.setInt32(0, val, Endian.little);
    _buffer.addByte(key);
    _buffer.add(_scratch4.buffer.asUint8List());
  }

  void writeFloat(int key, double val) {
    _scratch4.setFloat32(0, val, Endian.little);
    _buffer.addByte(key);
    _buffer.add(_scratch4.buffer.asUint8List());
  }

  void writeScaledFloat(int key, double val) {

    int scaledVal = (val * _scale).round();
    _scratch4.setInt32(0, scaledVal, Endian.little);
    _buffer.addByte(key);
    _buffer.add(_scratch4.buffer.asUint8List());
  }

  void writeDouble(int key, double value) {
    _scratch8.setFloat64(0, value, Endian.little);
    _buffer.addByte(key);
    _buffer.add(_scratch8.buffer.asUint8List());
  }

  void writeBool(int key, bool val) {
    _buffer.addByte(key);
    _buffer.addByte(val ? 1 : 0);
  }

  void writeColor(int key, Color? color) {
    if (color == null) return;
    writeInt(key, color.toARGB32());
  }

  void writeString(int key, String value) {
    final bytes = utf8.encode(value);
    _scratch4.setUint32(0, bytes.length, Endian.little);
    _buffer.addByte(key);
    _buffer.add(_scratch4.buffer.asUint8List());
    _buffer.add(bytes);
  }

  void writeEnum(int key, Enum value) {
    _buffer.addByte(key);
    _buffer.addByte(value.index);
  }

  void writeFloatNoKey(double val) {
    _scratch4.setFloat32(0, val, Endian.little);
    _buffer.add(_scratch4.buffer.asUint8List());
  }

  void writeScaledFloatNoKey(double val) {

    int scaledVal = (val * _scale).round();
    _scratch4.setInt32(0, scaledVal, Endian.little);
    _buffer.add(_scratch4.buffer.asUint8List());
  }

  void writeDoubleNoKey(double value) {
    _scratch8.setFloat64(0, value, Endian.little);
    _buffer.add(_scratch8.buffer.asUint8List());
  }

  void writeIntNoKey(int val) {
    _scratch4.setInt32(0, val, Endian.little);
    _buffer.add(_scratch4.buffer.asUint8List());
  }

  void writeBoolNoKey(bool val) {
    _buffer.addByte(val ? 1 : 0);
  }

  void writeStringNoKey(String value) {
    final bytes = utf8.encode(value);
    _scratch4.setUint32(0, bytes.length, Endian.little);
    _buffer.add(_scratch4.buffer.asUint8List());
    _buffer.add(bytes);
  }

  void writeBytes(Uint8List bytes) {
    _buffer.add(bytes);
  }

  Uint8List toBytes() => _buffer.toBytes();
}

class BinaryReader {
  late ByteData _data;
  int _offset = 0;

  BinaryReader(Uint8List buffer) {
    _data = ByteData.sublistView(buffer);
  }

  bool get isEOF => _offset >= _data.lengthInBytes;

  int readKey() => _data.getUint8(_offset++);

  int peekKey() {
    if (isEOF) return -1;
    return _data.getUint8(_offset);
  }

  int readInt() {
    final val = _data.getInt32(_offset, Endian.little);
    _offset += 4;
    return val;
  }

  double readFloat() {
    final val = _data.getFloat32(_offset, Endian.little);
    _offset += 4;
    return val;
  }

  double readScaledFloat() {
    final val = _data.getInt32(_offset, Endian.little);
    _offset += 4;
    return val / BinaryWriter._scale;
  }

  bool readBool() => _data.getUint8(_offset++) != 0;

  String readString() {
    final length = _data.getUint32(_offset, Endian.little);
    _offset += 4;

    if (_offset + length > _data.lengthInBytes) {
      throw RangeError(
        'BinaryReader: String length $length exceeds buffer at $_offset',
      );
    }

    final bytes = _data.buffer.asUint8List(
      _data.offsetInBytes + _offset,
      length,
    );
    final str = utf8.decode(bytes);
    _offset += length;
    return str;
  }

  Enum readEnum(List<Enum> values) {
    final index = _data.getUint8(_offset++);
    return values[index];
  }

  int readIntNoKey() => readInt();
  double readFloatNoKey() => readFloat();
  double readDoubleNoKey() {
    final val = _data.getFloat64(_offset, Endian.little);
    _offset += 8;
    return val;
  }

  bool readBoolNoKey() => readBool();
  String readStringNoKey() => readString();

  Color readColor() => Color(readInt());
}

abstract class SBNBinaryKeys {
  static const int version = 1;
  static const int nextImageId = 2;
  static const int backgroundColor = 3;
  static const int backgroundPattern = 4;
  static const int lineHeight = 5;
  static const int lineThickness = 6;
  static const int pages = 122;
  static const int pageCount = 123;
  static const int initialPageIndex = 7;
  static const int firstPageHash = 8;
  static const int pdfOutlines = 9;
  static const int noteTags = 10;
  static const int noteLinks = 11;

  static const int replaceDefaultWithPageSettings = 12;
  static const int noteDefaultPattern = 13;
  static const int noteDefaultPageColor = 14;
  static const int noteDefaultLineColor = 15;
  static const int noteDefaultLineHeight = 16;
  static const int noteDefaultLineThickness = 17;
  static const int noteDefaultMarginLeft = 22;
  static const int noteDefaultMarginRight = 23;
  static const int noteDefaultMarginTop = 24;
  static const int noteDefaultMarginBottom = 25;
  static const int noteDefaultBorderColor = 26;
  static const int notePageOrientation = 18;

  static const int noteToolSettings = 19;

  static const int isInfinite = 20;

  static const int infiniteThumbnailMode = 21;

  static const int creationDate = 109;
  static const int lastModification = 110;
  static const int lastAccess = 111;
  static const int totalTimeSpentEditing = 112;
  static const int totalTimeSpent = 113;
  static const int location = 114;
}

abstract class PageBinaryKeys {
  static const int version = 1;
  static const int width = 2;
  static const int height = 3;
  static const int strokes = 4;
  static const int images = 5;
  static const int quill = 6;
  static const int backgroundImage = 7;
  static const int backgroundPattern = 8;
  static const int lineColor = 9;
  static const int backgroundColor = 10;
  static const int lineHeight = 11;
  static const int lineThickness = 12;
  static const int localFlags = 13;
  static const int pageId = 14;
  static const int layers =
      15;
  static const int activeLayer =
      16;
  static const int marginLeft = 17;
  static const int marginRight = 18;
  static const int marginTop = 19;
  static const int marginBottom = 20;
  static const int borderColor = 21;
}

abstract class ImageBinaryKeys {
  static const int version = 1;
  static const int id = 2;
  static const int extension = 3;
  static const int pageIndex = 4;
  static const int invertible = 5;
  static const int backgroundFit = 6;

  static const int dstLeft = 7;
  static const int dstTop = 8;
  static const int dstWidth = 9;
  static const int dstHeight = 10;

  static const int srcLeft = 11;
  static const int srcTop = 12;
  static const int srcWidth = 13;
  static const int srcHeight = 14;

  static const int naturalWidth = 15;
  static const int naturalHeight = 16;
  static const int locked = 17;

  static const int imageBytes = 101;
  static const int assetId = 102;
  static const int pdfi = 103;
  static const int rotation = 104;

  static const int previewHash = 105;
  static const int fileSize = 106;
  static const int fullHash = 107;
  static const int fileInfo = 108;
}

abstract class StrokeBinaryKeys {
  static const int version = 1;
  static const int shape = 2;
  static const int pointCount = 3;
  static const int pageIndex = 4;
  static const int penType = 5;
  static const int pressureEnabled = 6;
  static const int color = 7;
  static const int pencilTextureIndex = 15;
  static const int cx = 8;
  static const int cy = 9;
  static const int r = 10;
  static const int left = 11;
  static const int top = 12;
  static const int width = 13;
  static const int height = 14;

  static const int size = 101;
  static const int thinning = 102;
  static const int smoothing = 103;
  static const int streamline = 104;
  static const int startTaperEnabled = 105;
  static const int startCustomTaper = 106;
  static const int endTaperEnabled = 107;
  static const int endCustomTaper = 108;
  static const int startCap = 109;
  static const int endCap = 110;
  static const int simulatePressure = 111;
  static const int isComplete = 112;
  static const int endOptions = 130;
  static const int flatEdge = 42;
}
