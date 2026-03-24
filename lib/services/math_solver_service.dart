// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart'
    as ml;
import 'package:logging/logging.dart';
import 'package:math_expressions/math_expressions.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/services/stroke_ink_clusters.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

class MathSolverService {
  final _recognizer = ml.DigitalInkRecognizer(languageCode: 'en-US');
  final _modelManager = ml.DigitalInkRecognizerModelManager();
  static final log = Logger('MathSolverService');

  Future<void> init() async {
    try {
      final isDownloaded = await _modelManager.isModelDownloaded('en-US');
      if (!isDownloaded) {
        log.info('Downloading Math Solver model (en-US)...');
        await _modelManager.downloadModel('en-US');
      }
    } catch (e) {
      log.warning(
        'Failed to download Math Solver model (Device might be offline): $e',
      );
    }
  }

  Future<void> dispose() async {
    await _recognizer.close();
  }

  ml.Ink _buildInk(List<Stroke> strokes) {
    final ink = ml.Ink();
    for (final stroke in strokes) {
      final mlStroke = ml.Stroke();
      final points = stroke.points;
      for (int i = 0; i < points.length; i++) {
        final p = points[i];
        final t = i * 20;
        mlStroke.points.add(ml.StrokePoint(x: p.x, y: p.y, t: t));
      }
      ink.strokes.add(mlStroke);
    }
    return ink;
  }

  String _normalizeForParser(String expressionPart) {
    return expressionPart
        .replaceAll('−', '-')
        .replaceAll('x', '*')
        .replaceAll('×', '*')
        .replaceAll('÷', '/')
        .replaceAll('π', 'pi')
        .replaceAll(' ', '');
  }

  double _evaluateExpression(String expressionPart) {
    final normalizedExpr = _normalizeForParser(expressionPart);
    if (normalizedExpr.isEmpty) {
      throw FormatException('empty expression');
    }
    final parser = Parser();
    final exp = parser.parse(normalizedExpr);
    final cm = ContextModel();
    cm.bindVariable(Variable('pi'), Number(math.pi));
    cm.bindVariable(Variable('e'), Number(math.e));
    return exp.evaluate(EvaluationType.REAL, cm);
  }

  /// Fixes common OCR quirks: invisible chars, fullwidth digits/operators, stray spaces.
  String _normalizeOcrMath(String raw) {
    var s = raw.trim();
    s = s.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
    const fw = '０１２３４５６７８９＋－×÷＝';
    const asc = '0123456789+-*/=';
    for (var i = 0; i < fw.length; i++) {
      s = s.replaceAll(fw[i], asc[i]);
    }
    s = s.replaceAll('−', '-');
    s = s.replaceAll('⋅', '*').replaceAll('·', '*');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s.trim();
  }

  /// Evaluates [raw] like `2+2=4*2=` left-to-right: each non-empty segment
  /// between `=` is a full expression; trailing `=` requests the last value.
  double? _solveChainedEquals(String raw) {
    final trimmed = _normalizeOcrMath(raw);
    if (!trimmed.contains('=')) return null;

    if (!trimmed.endsWith('=')) {
      return null;
    }

    final parts = trimmed.split('=');
    if (parts.length < 2) return null;

    double? last;
    for (var i = 0; i < parts.length; i++) {
      final seg = parts[i].trim();
      if (seg.isEmpty) {
        if (i == parts.length - 1 && last != null) {
          return last;
        }
        continue;
      }
      try {
        last = _evaluateExpression(seg);
      } catch (e, st) {
        log.fine('Eval failed for "$seg": $e\n$st');
        return null;
      }
    }
    return last;
  }

  String _formatResult(double eval) {
    var resultString = eval.toString();
    if (resultString.endsWith('.0')) {
      resultString = resultString.substring(0, resultString.length - 2);
    }

    if (resultString.length > 8 && resultString.contains('.')) {
      try {
        final val = double.parse(resultString);
        resultString = val.toStringAsFixed(4);
        resultString = resultString
            .replaceAll(RegExp(r'0*$'), '')
            .replaceAll(RegExp(r'\.$'), '');
      } catch (_) {}
    }
    return resultString;
  }

  List<Stroke>? _strokesForSolvedLine(
    List<Stroke> lineStrokes,
    String recognizedText,
    EditorPage page,
    int pageIndex,
  ) {
    final solved = _solveChainedEquals(recognizedText);
    if (solved == null) return null;

    final resultString = _formatResult(solved);
    final bounds = _getCombinedBounds(lineStrokes);
    final fontSize = (bounds.height * 0.8).clamp(30.0, 80.0);

    final startOffset = Offset(
      bounds.right + 25,
      bounds.center.dy + (fontSize * 0.35),
    );

    return _generateVectorStrokes(
      resultString,
      startOffset,
      fontSize,
      page,
      pageIndex,
    );
  }

  Future<List<Stroke>?> processStrokes(
    List<Stroke> strokes,
    EditorPage page,
    int pageIndex,
  ) async {
    if (strokes.isEmpty) return null;

    try {
      final isModelReady = await _modelManager.isModelDownloaded('en-US');
      if (!isModelReady) return null;
    } catch (e) {
      return null;
    }

    try {

      final monoInk = _buildInk(strokes);
      if (monoInk.strokes.isNotEmpty) {
        final candidates = await _recognizer.recognize(monoInk);
        if (candidates.isNotEmpty) {
          final out = _strokesForSolvedLine(
            strokes,
            candidates.first.text,
            page,
            pageIndex,
          );
          if (out != null && out.isNotEmpty) {
            return out;
          }
        }
      }

      final lineClusters = clusterStrokesIntoWritingLines(strokes);
      if (lineClusters.isEmpty) return null;

      final allOut = <Stroke>[];

      for (final lineStrokes in lineClusters) {
        if (lineStrokes.isEmpty) continue;

        final ink = _buildInk(lineStrokes);
        if (ink.strokes.isEmpty) continue;

        final candidates = await _recognizer.recognize(ink);
        if (candidates.isEmpty) continue;

        final mathString = candidates.first.text;
        final lineOut = _strokesForSolvedLine(
          lineStrokes,
          mathString,
          page,
          pageIndex,
        );
        if (lineOut != null && lineOut.isNotEmpty) {
          allOut.addAll(lineOut);
        }
      }

      return allOut.isEmpty ? null : allOut;
    } catch (e, st) {
      log.warning('processStrokes: $e', e, st);
      return null;
    }
  }

  Rect _getCombinedBounds(List<Stroke> strokes) {
    if (strokes.isEmpty) return Rect.zero;
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final s in strokes) {
      final points = s.points.isNotEmpty ? s.points : s.highQualityPolygon;
      for (final p in points) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  List<Stroke> _generateVectorStrokes(
    String text,
    Offset startPos,
    double fontSize,
    EditorPage page,
    int pageIndex,
  ) {
    final path = Path();

    final scale = fontSize / 24.0;

    double cursorX = startPos.dx;
    final cursorY = startPos.dy;

    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      final charInfo = _getVectorChar(char);

      final matrix = Matrix4.identity()
        ..translate(cursorX, cursorY)
        ..scale(
          scale,
          -scale,
        );

      path.addPath(charInfo.path.transform(matrix.storage), Offset.zero);

      cursorX += (charInfo.width + 4) * scale;
    }

    return _convertPathToStrokes(path, page, pageIndex);
  }

  List<Stroke> _convertPathToStrokes(
    Path path,
    EditorPage page,
    int pageIndex,
  ) {
    final strokes = <Stroke>[];
    final metrics = path.computeMetrics();

    for (final metric in metrics) {
      final points = <PointVector>[];
      final length = metric.length;

      const resolution = 2.0;

      for (double d = 0; d <= length; d += resolution) {
        final tangent = metric.getTangentForOffset(d);
        if (tangent != null) {
          points.add(
            PointVector(
              tangent.position.dx,
              tangent.position.dy,
              0.65,
            ),
          );
        }
      }

      if (points.isNotEmpty) {
        final stroke = Stroke(
          color: Colors.blue.shade800,
          pressureEnabled: false,
          options: StrokeOptions(
            size: 2.5,
            thinning: 0.0,
            smoothing: 0.7,
            streamline: 0.5,
            isComplete: true,
          ),
          toolId: ToolId.fountainPen,
          pageIndex: pageIndex,
          page: page,
        );

        for (final p in points) stroke.addPoint(Offset(p.x, p.y), p.pressure);

        strokes.add(stroke);
      }
    }
    return strokes;
  }

  // --- FONTE VETORIAL "ENGINEERING SANS" ---
  ({Path path, double width}) _getVectorChar(String char) {
    final p = Path();
    double w = 12.0;

    switch (char.toLowerCase()) {
      case '0':
        w = 14;
        p.addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(0, 0, 14, 20),
            const Radius.circular(7),
          ),
        );
        break;
      case '1':
        w = 8;
        p.moveTo(2, 16);
        p.lineTo(4, 20);
        p.lineTo(4, 0);
        p.moveTo(0, 0);
        p.lineTo(8, 0);
        break;
      case '2':
        w = 14;
        p.moveTo(0, 15);
        p.cubicTo(0, 22, 14, 22, 14, 15);
        p.cubicTo(14, 10, 0, 0, 0, 0);
        p.lineTo(14, 0);
        break;
      case '3':
        w = 14;
        p.moveTo(1, 19);
        p.lineTo(13, 19);
        p.lineTo(8, 11);
        p.cubicTo(16, 11, 16, 0, 8, 0);
        p.cubicTo(4, 0, 1, 2, 1, 4);
        break;
      case '4':
        w = 14;
        p.moveTo(10, 0);
        p.lineTo(10, 20);
        p.moveTo(10, 20);
        p.lineTo(0, 6);
        p.lineTo(14, 6);
        break;
      case '5':
        w = 13;
        p.moveTo(12, 20);
        p.lineTo(2, 20);
        p.lineTo(1, 11);
        p.cubicTo(1, 11, 13, 13, 13, 5);
        p.cubicTo(13, -2, 2, -2, 1, 1);
        break;
      case '6':
        w = 14;
        p.addOval(const Rect.fromLTWH(0, 0, 14, 10));
        p.moveTo(0, 5);
        p.cubicTo(0, 15, 10, 22, 12, 22);
        break;
      case '7':
        w = 14;
        p.moveTo(0, 20);
        p.lineTo(14, 20);
        p.lineTo(4, 0);
        break;
      case '8':
        w = 14;
        p.addOval(const Rect.fromLTWH(2, 11, 10, 9));
        p.addOval(const Rect.fromLTWH(0, 0, 14, 11));
        break;
      case '9':
        w = 14;
        p.addOval(const Rect.fromLTWH(0, 10, 14, 10));
        p.moveTo(14, 15);
        p.cubicTo(14, 5, 4, -2, 2, -2);
        break;

      case '.':
        w = 5;
        p.addOval(const Rect.fromLTWH(1, 0, 3, 3));
        break;
      case '-':
        w = 12;
        p.moveTo(0, 10);
        p.lineTo(12, 10);
        break;
      case '+':
        w = 14;
        p.moveTo(7, 4);
        p.lineTo(7, 16);
        p.moveTo(1, 10);
        p.lineTo(13, 10);
        break;
      case '=':
        w = 14;
        p.moveTo(1, 8);
        p.lineTo(13, 8);
        p.moveTo(1, 12);
        p.lineTo(13, 12);
        break;
      case '(':
        w = 8;
        p.moveTo(6, 22);
        p.quadraticBezierTo(0, 10, 6, -2);
        break;
      case ')':
        w = 8;
        p.moveTo(2, 22);
        p.quadraticBezierTo(8, 10, 2, -2);
        break;

      case 'e':
        w = 12;
        p.moveTo(12, 6);
        p.cubicTo(12, 14, 0, 14, 0, 6);
        p.cubicTo(0, 0, 8, -1, 11, 2);
        p.moveTo(0, 7);
        p.lineTo(12, 7);
        break;
      case 'i':
        w = 6;
        p.moveTo(3, 0);
        p.lineTo(3, 14);
        p.addOval(const Rect.fromLTWH(1.5, 17, 3, 3));
        break;
      case 'n':
        w = 12;
        p.moveTo(2, 0);
        p.lineTo(2, 14);
        p.moveTo(2, 10);
        p.quadraticBezierTo(6, 14, 10, 14);
        p.lineTo(10, 0);
        break;
      case 'f':
        w = 8;
        p.moveTo(4, 0);
        p.lineTo(4, 20);
        p.quadraticBezierTo(4, 22, 7, 22);
        p.moveTo(1, 12);
        p.lineTo(7, 12);
        break;
      case 'y':
        w = 12;
        p.moveTo(1, 14);
        p.lineTo(5, 5);
        p.moveTo(11, 14);
        p.lineTo(1, -6);
        break;
      case 'p':
        w = 14;
        p.moveTo(3, 0);
        p.lineTo(3, 14);
        p.moveTo(11, 0);
        p.lineTo(11, 14);
        p.moveTo(1, 12);
        p.lineTo(13, 12);
        break;

      default:
        w = 12;
        p.addRect(const Rect.fromLTWH(0, 0, 12, 20));
    }

    return (path: p, width: w);
  }
}
