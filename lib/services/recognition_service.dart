// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart'
    as ml;
import 'package:logging/logging.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/services/math_text_utils.dart';
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

  /// ML Kit digital ink is implemented natively on Android/iOS only. On
  /// desktop/web the method channel has no handler, so skip silently instead
  /// of spamming MissingPluginException warnings.
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Latched when the method channel has no native handler (e.g. plugin
  /// registration failed at startup). Skips all further channel calls so one
  /// broken environment cannot spam the log on every recognition attempt.
  bool _channelDead = false;

  void _noteChannelDead(Object e) {
    if (_channelDead) return;
    _channelDead = true;
    log.info('Digital ink plugin unavailable, recognition disabled: $e');
  }

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

  /// In-flight background downloads by language code. Single-flight so
  /// repeated recognition attempts while offline never stack downloads.
  final Map<String, Future<void>> _pendingEnsures = {};

  /// Ensures [languageCode] is downloaded, sharing one attempt between
  /// concurrent callers.
  Future<void> ensureModel(String languageCode) {
    final existing = _pendingEnsures[languageCode];
    if (existing != null) return existing;
    final fut = _ensureModelDownloaded(languageCode);
    _pendingEnsures[languageCode] = fut;
    fut.whenComplete(() => _pendingEnsures.remove(languageCode));
    return fut;
  }

  Future<void> _ensureModelDownloaded(String languageCode) async {
    final isDownloaded = await _modelManager.isModelDownloaded(languageCode);
    if (!isDownloaded) {
      log.info('Downloading OCR model: $languageCode...');
      // NB: isWifiRequired defaults to true upstream, which makes every
      // download fail on mobile data ("conditions not met"). These models
      // are small, so allow any connection here.
      await _modelManager
          .downloadModel(languageCode, isWifiRequired: false)
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
    if (!isSupported || _channelDead || saberStrokes.isEmpty) return null;

    try {
      if (!await _modelManager.isModelDownloaded(languageCode)) {
        log.info(
          'Model $languageCode missing, downloading in background for a later attempt.',
        );
        unawaited(
          ensureModel(languageCode).catchError((Object e) {
            if (e is MissingPluginException) _noteChannelDead(e);
            log.info('Background model download failed ($languageCode): $e.');
          }),
        );
        return null;
      }
    } on MissingPluginException catch (e) {
      _noteChannelDead(e);
      return null;
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
    } on MissingPluginException catch (e) {
      _noteChannelDead(e);
      return null;
    } catch (e) {
      log.warning('Error during recognition ($languageCode): $e');
      return null;
    }
  }

  /// Plain-text transcript of one writing line. Solver-generated answer
  /// strokes contribute their known text (never re-recognized); each
  /// handwriting run goes to ML Kit separately, spliced in x-order.
  Future<String?> _plainTextForLine(
    List<Stroke> line,
    String languageCode,
  ) async {
    final tokens = splitLineTokens(line);
    if (tokens.isEmpty) return null;
    final parts = <String>[];
    for (final token in tokens) {
      if (token.isKnown) {
        parts.add(token.knownText!);
        continue;
      }
      final c = await recognizeCandidate(token.run!, languageCode);
      final piece = c?.text.trim();
      if (piece != null && piece.isNotEmpty) parts.add(piece);
    }
    if (parts.isEmpty) return null;
    return parts.join(' ');
  }

  /// Layout-aware LaTeX fragment for whole-page export: lines stay in
  /// top-to-bottom order with coarse indent, equations become `\[...\]`
  /// blocks, inline math `\(...\)`, and running text is escaped.
  /// Recognition stays fully on-device (text ink model); no network model
  /// beyond the regular ML Kit download, no cloud, no LLM runtime.
  Future<String?> strokesToCombinedLatexText({
    required List<Stroke> strokes,
    required String textLanguageCode,
  }) async {
    if (strokes.isEmpty) return null;
    final lines = clusterStrokesIntoWritingLines(strokes);
    final out = <String>[];
    for (final line in lines) {
      if (line.isEmpty) continue;
      final text = await _plainTextForLine(line, textLanguageCode);
      if (text == null || text.trim().isEmpty) continue;
      final latex = latexLineForRecognizedText(
        text,
        indent: indentLevelForMinX(minXOfStrokes(line)),
      );
      if (latex.isNotEmpty) out.add(latex);
    }
    if (out.isEmpty) return null;
    return out.join('\n\n');
  }

  Future<void> init({String languageCode = 'en-US'}) async {
    if (!isSupported) return;
    try {
      await ensureModel(languageCode);
      await _recognizerFor(languageCode);
    } catch (e) {
      log.warning(
        'Failed to prepare OCR model ($languageCode, ${e.runtimeType}): $e. '
        'Check the network connection and Google Play Services.',
      );
    }
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
    return plainTextForStrokes(saberStrokes, languageCode: languageCode);
  }

  /// Plain-text transcript of arbitrary ink (selection or page), lines
  /// joined with newlines. Also used as the cheap OCR draft that guides the
  /// vision model in page-to-LaTeX transcription.
  Future<String?> plainTextForStrokes(
    List<Stroke> saberStrokes, {
    String languageCode = 'en-US',
  }) async {
    if (saberStrokes.isEmpty) return null;
    final lines = clusterStrokesIntoWritingLines(saberStrokes);
    final out = <String>[];
    for (final line in lines) {
      if (line.isEmpty) continue;
      final text = await _plainTextForLine(line, languageCode);
      if (text != null && text.trim().isNotEmpty) out.add(text.trim());
    }
    if (out.isEmpty) return null;
    return out.join('\n');
  }

  Future<void> dispose() async {
    if (!isSupported || _channelDead) {
      _recognizers.clear();
      return;
    }
    for (final r in _recognizers.values) {
      try {
        await r.close();
      } on MissingPluginException catch (e) {
        _noteChannelDead(e);
      } catch (e) {
        log.warning('Failed to close OCR recognizer: $e');
      }
    }
    _recognizers.clear();
  }
}
