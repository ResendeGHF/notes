// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart'
    as ml;
import 'package:logging/logging.dart';
import 'package:saber/data/stroke_geometry/stroke_geometry.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/services/math_text_utils.dart';
import 'package:saber/services/stroke_ink_clusters.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

/// Result of attempting to solve writing lines: answer strokes to add plus
/// consumed previous-answer strokes to remove. Null means "not solvable";
/// a non-null outcome without changes means "already solved, nothing to do".
class MathSolveOutcome {
  const MathSolveOutcome({
    this.addedStrokes = const [],
    this.removedStrokes = const [],
  });

  final List<Stroke> addedStrokes;
  final List<Stroke> removedStrokes;

  bool get hasChanges => addedStrokes.isNotEmpty || removedStrokes.isNotEmpty;
}

class MathSolverService {
  final _recognizer = ml.DigitalInkRecognizer(languageCode: 'en-US');
  final _modelManager = ml.DigitalInkRecognizerModelManager();
  static final log = Logger('MathSolverService');

  /// ML Kit digital ink is implemented natively on Android/iOS only. On
  /// desktop/web the method channel has no handler, so skip silently instead
  /// of spamming MissingPluginException warnings.
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// In-flight background download, if any. Single-flight so repeated
  /// recognition attempts while offline never stack downloads.
  Future<void>? _pendingDownload;

  /// Latched when the method channel has no native handler (e.g. plugin
  /// registration failed at startup). Skips all further channel calls so one
  /// broken environment cannot spam the log on every recognition attempt.
  bool _channelDead = false;

  Future<void> init() async {
    if (!isSupported || _channelDead) return;
    try {
      final isDownloaded = await _modelManager.isModelDownloaded('en-US');
      if (!isDownloaded) {
        log.info('Downloading Math Solver model (en-US)...');
        // NB: isWifiRequired defaults to true upstream, which makes every
        // download fail on mobile data ("conditions not met"). These models
        // are small, so allow any connection here.
        await _modelManager
            .downloadModel('en-US', isWifiRequired: false)
            .timeout(const Duration(seconds: 60));
      }
    } on MissingPluginException catch (e) {
      _channelDead = true;
      log.info('Digital ink plugin unavailable, math solver disabled: $e');
    } catch (e) {
      log.warning(
        'Failed to download Math Solver model (${e.runtimeType}): $e. '
        'Check the network connection and Google Play Services.',
      );
    }
  }

  /// Kicks a single-flight background download when the model is missing, so
  /// a later recognition attempt recovers without reopening the editor.
  void _ensureDownloadInBackground() {
    if (_pendingDownload != null) return;
    log.info('Math Solver model missing, downloading in background...');
    final fut = _modelManager
        .downloadModel('en-US', isWifiRequired: false)
        .timeout(const Duration(seconds: 90))
        .then<void>((_) {})
        .catchError((Object e) {
      log.warning(
        'Background Math Solver model download failed (${e.runtimeType}): $e.',
      );
    });
    _pendingDownload = fut;
    fut.whenComplete(() => _pendingDownload = null);
  }

  Future<void> dispose() async {
    if (!isSupported || _channelDead) return;
    try {
      await _recognizer.close();
    } on MissingPluginException catch (e) {
      _channelDead = true;
      log.info('Digital ink plugin unavailable, math solver disabled: $e');
    } catch (e) {
      log.warning('Failed to dispose Math Solver recognizer: $e');
    }
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

  /// Last answer per solve signature, so re-solving an unchanged line is a
  /// silent no-op instead of history-churning remove/add cycles.
  final Map<String, String> _lastSolveAnswers = {};

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

  /// Solves one writing line. Previously generated answer strokes on the
  /// line contribute their known text (never re-recognized: mechanical glyph
  /// outlines poison the recognizer); only real handwriting runs go to ML
  /// Kit. Returns null when the line is not a solvable equation.
  Future<MathSolveOutcome?> _solveLine(
    List<Stroke> lineStrokes,
    EditorPage page,
    int pageIndex,
  ) async {
    if (lineStrokes.isEmpty) return null;
    final tokens = splitLineTokens(lineStrokes);
    if (tokens.isEmpty) return null;

    final buffer = StringBuffer();
    final consumed = <Stroke>[];
    var handwrittenSig = StringBuffer();
    for (final token in tokens) {
      if (token.isKnown) {
        buffer.write(token.knownText);
        consumed.addAll(token.known!);
      } else {
        final run = token.run!;
        final ink = _buildInk(run);
        if (ink.strokes.isEmpty) return null;
        final candidates = await _recognizer.recognize(ink);
        if (candidates.isEmpty) return null;
        final text = candidates.first.text.trim();
        if (text.isEmpty) return null;
        buffer.write(text);
        handwrittenSig.write(text);
        handwrittenSig.write('|');
      }
    }

    final assembled = buffer.toString();
    if (!assembled.trim().endsWith('=')) return null;

    final solved = solveMathChain(assembled);
    if (solved == null) {
      log.fine('No solution for "$assembled"');
      return null;
    }
    final answer = _formatResult(solved);

    // Dedup: same handwritten ink with the same answer already on the line
    // (e.g. decorative pen-up on a solved line) changes nothing.
    final sig =
        '$pageIndex|${lineStrokes.length}|$handwrittenSig=>${consumed.map((s) => knownResultOf(s)?.text ?? '').join()}';
    if (_lastSolveAnswers[sig] == answer) {
      return const MathSolveOutcome();
    }
    if (_lastSolveAnswers.length > 200) _lastSolveAnswers.clear();
    _lastSolveAnswers[sig] = answer;

    final bounds = _getCombinedBounds(lineStrokes);
    final fontSize = (bounds.height * 0.8).clamp(30.0, 80.0);
    final startOffset = Offset(
      bounds.right + 25,
      bounds.center.dy + (fontSize * 0.35),
    );
    final added = _generateVectorStrokes(
      answer,
      startOffset,
      fontSize,
      page,
      pageIndex,
    );
    if (added.isEmpty) return null;
    tagSolverResultStrokes(added, answer);
    return MathSolveOutcome(addedStrokes: added, removedStrokes: consumed);
  }

  Future<MathSolveOutcome?> processStrokes(
    List<Stroke> strokes,
    EditorPage page,
    int pageIndex,
  ) async {
    if (!isSupported || _channelDead || strokes.isEmpty) return null;

    try {
      final isModelReady = await _modelManager.isModelDownloaded('en-US');
      if (!isModelReady) {
        _ensureDownloadInBackground();
        return null;
      }
    } on MissingPluginException catch (e) {
      _channelDead = true;
      log.info('Digital ink plugin unavailable, math solver disabled: $e');
      return null;
    } catch (e) {
      return null;
    }

    try {
      final lineClusters = clusterStrokesIntoWritingLines(strokes);
      if (lineClusters.isEmpty) return null;

      final added = <Stroke>[];
      final removed = <Stroke>[];
      var solvedAny = false;
      for (final lineStrokes in lineClusters) {
        if (lineStrokes.isEmpty) continue;
        final outcome = await _solveLine(lineStrokes, page, pageIndex);
        if (outcome == null) continue;
        solvedAny = true;
        added.addAll(outcome.addedStrokes);
        removed.addAll(outcome.removedStrokes);
      }

      // Null (unsolvable) only when no line solved; an empty outcome means
      // "already solved", which callers treat as silent success.
      if (!solvedAny) return null;
      return MathSolveOutcome(addedStrokes: added, removedStrokes: removed);
    } on MissingPluginException catch (e) {
      _channelDead = true;
      log.info('Digital ink plugin unavailable, math solver disabled: $e');
      return null;
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
