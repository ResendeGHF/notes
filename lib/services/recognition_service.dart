// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

import 'dart:async';

import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart'
    as ml;
import 'package:logging/logging.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/services/stroke_ink_clusters.dart';

class RecognitionService {

  static final RecognitionService _instance = RecognitionService._internal();
  factory RecognitionService() => _instance;
  RecognitionService._internal();

  /// ML Kit base model for math / LaTeX-like digital ink (symbols & equations).
  static const String mathInkLanguageCode = 'zxx-Zsym-x-math';

  static const Duration recognizeTimeout = Duration(seconds: 15);
  static const Duration downloadTimeout = Duration(seconds: 60);

  final _modelManager = ml.DigitalInkRecognizerModelManager();

  /// One native recognizer per downloaded model; avoids re-init between lines.
  final Map<String, ml.DigitalInkRecognizer> _recognizers = {};

  static final log = Logger('RecognitionService');

  ml.Ink _buildMlInk(List<Stroke> saberStrokes) {
    final ink = ml.Ink();
    for (final stroke in saberStrokes) {
      final mlStroke = ml.Stroke();
      if (stroke.points.isNotEmpty) {
        for (int i = 0; i < stroke.points.length; i++) {
          final p = stroke.points[i];
          final t = i * 20;
          mlStroke.points.add(ml.StrokePoint(x: p.x, y: p.y, t: t));
        }
      }
      if (mlStroke.points.isNotEmpty) {
        ink.strokes.add(mlStroke);
      }
    }
    return ink;
  }

  Future<void> _ensureModelDownloaded(String languageCode) async {
    final isDownloaded = await _modelManager.isModelDownloaded(languageCode);
    if (!isDownloaded) {
      log.info('Downloading OCR model: $languageCode...');
      await _modelManager
          .downloadModel(languageCode)
          .timeout(downloadTimeout);
    }
  }

  Future<ml.DigitalInkRecognizer> _recognizerFor(String languageCode) async {
    final existing = _recognizers[languageCode];
    if (existing != null) return existing;

    await _ensureModelDownloaded(languageCode);
    final r = ml.DigitalInkRecognizer(languageCode: languageCode);
    _recognizers[languageCode] = r;
    return r;
  }

  /// Returns the top [ml.RecognitionCandidate] or null on failure / timeout.
  Future<ml.RecognitionCandidate?> recognizeCandidate(
    List<Stroke> saberStrokes,
    String languageCode,
  ) async {
    if (saberStrokes.isEmpty) return null;

    try {
      if (!await _modelManager.isModelDownloaded(languageCode)) {
        log.warning('Cannot recognize: Model $languageCode not downloaded.');
        return null;
      }
    } catch (_) {
      return null;
    }

    final ink = _buildMlInk(saberStrokes);
    if (ink.strokes.isEmpty) return null;

    try {
      final recognizer = await _recognizerFor(languageCode);
      final candidates = await recognizer
          .recognize(ink)
          .timeout(recognizeTimeout);
      if (candidates.isEmpty) return null;
      return candidates.first;
    } on TimeoutException catch (e) {
      log.warning('Recognition timed out ($languageCode): $e');
      return null;
    } catch (e) {
      log.warning('Error during recognition ($languageCode): $e');
      return null;
    }
  }

  /// Per-line transcript using the **text** ink model only.
  ///
  /// The ML Kit math symbol model (`zxx-Zsym-x-math`) is for specialized notation
  /// and often mis-reads simple arithmetic (e.g. "space shuttle"). Export uses the
  /// same text locale as Stroke to Text so results are usable; users can edit to
  /// LaTeX manually if needed.
  Future<String?> strokesToCombinedLatexText({
    required List<Stroke> strokes,
    required String textLanguageCode,
  }) async {
    if (strokes.isEmpty) return null;
    final lines = clusterStrokesIntoWritingLines(strokes);
    final out = <String>[];
    for (final line in lines) {
      final c = await recognizeCandidate(line, textLanguageCode);
      final piece = c?.text;
      if (piece != null) {
        final t = piece.trim();
        if (t.isNotEmpty) out.add(t);
      }
    }
    if (out.isEmpty) return null;
    return out.join('\n');
  }

  Future<void> init({String languageCode = 'en-US'}) async {
    try {
      await _ensureModelDownloaded(languageCode);
    } catch (e) {
      log.warning('Failed to prepare OCR model ($languageCode): $e');
    }
    await _recognizerFor(languageCode);
  }

  Future<String?> recognizeStrokes(List<Stroke> saberStrokes) async {
    await init(languageCode: 'en-US');
    final c = await recognizeCandidate(saberStrokes, 'en-US');
    return c?.text;
  }

  Future<String?> recognizeMathStrokes(List<Stroke> saberStrokes) async {
    final c = await recognizeCandidate(saberStrokes, mathInkLanguageCode);
    return c?.text;
  }

  Future<String?> recognizeTextStrokes(
    List<Stroke> saberStrokes, {
    String languageCode = 'en-US',
  }) async {
    final c = await recognizeCandidate(saberStrokes, languageCode);
    return c?.text;
  }

  Future<void> dispose() async {
    for (final r in _recognizers.values) {
      await r.close();
    }
    _recognizers.clear();
  }
}
