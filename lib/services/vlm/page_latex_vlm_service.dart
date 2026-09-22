// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:logging/logging.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/services/vlm/vlm_model_catalog.dart';

/// Fatal, user-facing VLM failure (unsupported device, load error, timeout,
/// empty output). Carries a message safe to show in a snackbar/dialog.
class VlmException implements Exception {
  VlmException(this.message);

  final String message;

  @override
  String toString() => 'VlmException: $message';
}

/// Thrown when transcription needs a model download first. The editor turns
/// this into a download prompt instead of an error.
class VlmNeedsDownloadException extends VlmException {
  VlmNeedsDownloadException(this.entry)
    : super('Model ${entry.displayName} is not downloaded');

  final VlmModelEntry entry;
}

/// Readiness of one model entry.
enum VlmReadiness { ready, needsDownload, unsupported }

/// Narrow seam over flutter_gemma so orchestration is unit-testable without
/// native inference.
abstract class VlmInferenceBackend {
  Future<void> ensureInitialized();
  Future<bool> isModelInstalled(String modelId);
  VlmDownloadHandle downloadModel({
    required VlmModelEntry entry,
    required void Function(int progress) onProgress,
  });
  Future<String> generate({
    required VlmModelEntry entry,
    required Uint8List pngBytes,
    required String prompt,
    required Duration timeout,
  });
  Future<void> uninstallModel(VlmModelEntry entry);
  Future<void> unload();
}

/// Handle for an in-flight model download.
abstract class VlmDownloadHandle {
  Future<void> get done;
  void cancel();
}

/// True when [e] is a user-cancelled download (not a real failure).
bool isVlmDownloadCancelled(Object e) {
  try {
    return CancelToken.isCancel(e);
  } catch (_) {
    return false;
  }
}

class _FlutterGemmaDownloadHandle implements VlmDownloadHandle {
  _FlutterGemmaDownloadHandle(this._done, this._cancel);

  final Future<void> _done;
  final void Function() _cancel;

  @override
  Future<void> get done => _done;

  @override
  void cancel() => _cancel();
}

/// Production backend over flutter_gemma (.litertlm via LiteRT-LM).
class FlutterGemmaVlmBackend implements VlmInferenceBackend {
  static final _log = Logger('FlutterGemmaVlmBackend');

  static bool _engineReady = false;
  InferenceModel? _loadedModel;

  @override
  Future<void> ensureInitialized() async {
    if (_engineReady) return;
    await FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]);
    _engineReady = true;
  }

  @override
  Future<bool> isModelInstalled(String modelId) {
    return FlutterGemma.isModelInstalled(modelId);
  }

  @override
  VlmDownloadHandle downloadModel({
    required VlmModelEntry entry,
    required void Function(int progress) onProgress,
  }) {
    final cancelToken = CancelToken();
    final done = FlutterGemma.installModel(
      modelType: ModelType.general,
      fileType: ModelFileType.litertlm,
    )
        .fromHuggingFace(entry.hfRepo, file: entry.hfFile)
        .withProgress(onProgress)
        .withCancelToken(cancelToken)
        .install()
        .then<void>((_) {});
    return _FlutterGemmaDownloadHandle(done, () {
      try {
        cancelToken.cancel('User cancelled download');
      } catch (e) {
        _log.fine('Download cancel failed: $e');
      }
    });
  }

  @override
  Future<String> generate({
    required VlmModelEntry entry,
    required Uint8List pngBytes,
    required String prompt,
    required Duration timeout,
  }) async {
    await ensureInitialized();
    // CPU-only, deliberately: the OpenCL GPU delegate segfaults (null
    // function pointer inside libLiteRtOpenClAccelerator during graph
    // compilation) on Mali drivers such as the Galaxy Tab A9+ this was
    // diagnosed on — a native crash no Dart try/catch can survive. The
    // vision encoder is CPU-bound upstream anyway; text decoding is simply
    // slower. Revisit behind a settings toggle if GPU delegates mature.
    final model = await FlutterGemma.getActiveModel(
      maxTokens: entry.maxTokens,
      preferredBackend: PreferredBackend.cpu,
      preferredVisionBackend: PreferredBackend.cpu,
      supportImage: true,
    );
    _loadedModel = model;
    final chat = await model.createChat(
      supportImage: true,
      temperature: 0.1,
      maxOutputTokens: entry.maxOutputTokens,
    );
    try {
      await chat.addQueryChunk(
        Message.withImages(
          text: prompt,
          imageBytes: [pngBytes],
          isUser: true,
        ),
      );
      final response = await chat.generateChatResponse().timeout(timeout);
      if (response is TextResponse) return response.token;
      return response.toString();
    } finally {
      try {
        await chat.close();
      } catch (e) {
        _log.fine('Chat close failed: $e');
      }
    }
  }

  @override
  Future<void> uninstallModel(VlmModelEntry entry) async {
    await ensureInitialized();
    _loadedModel = null;
    await FlutterGemma.uninstallModel(entry.id);
  }

  @override
  Future<void> unload() async {
    final model = _loadedModel;
    _loadedModel = null;
    if (model == null) return;
    try {
      await model.close();
    } catch (e) {
      _log.fine('Model unload failed: $e');
    }
  }
}

/// Orchestrates page-to-LaTeX transcription: readiness gating, single-flight
/// downloads and generation, output extraction. No UI here; the editor maps
/// [VlmException]/[VlmNeedsDownloadException] to dialogs.
class PageLatexVlmService {
  PageLatexVlmService({VlmInferenceBackend? backend})
    : _backend = backend ?? FlutterGemmaVlmBackend();

  static final _log = Logger('PageLatexVlmService');

  /// .litertlm inference (arm64 FFI) requires Android 11+ at the OS level.
  static const int minAndroidSdk = 30;

  /// Generous per-page budget: a 500M model needs minutes for dense pages.
  static const Duration generationTimeout = Duration(minutes: 10);

  final VlmInferenceBackend _backend;

  int? _cachedSdkInt;
  bool _busy = false;

  /// False outside Android (this app only ships Android native code, and the
  /// vision path additionally needs [minAndroidSdk]).
  static bool get isPlatformSupported =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android;

  Future<int?> _androidSdkInt() async {
    if (_cachedSdkInt != null) return _cachedSdkInt;
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      // Bounded: on some devices/test harnesses the platform channel never
      // answers (neither value nor error). Unknown SDK is treated as
      // "not old" — the model load itself still fails loudly if needed.
      final info = await DeviceInfoPlugin()
          .androidInfo
          .timeout(const Duration(seconds: 5));
      _cachedSdkInt = info.version.sdkInt;
    } catch (e) {
      _log.fine('Android SDK check failed: $e');
    }
    return _cachedSdkInt;
  }

  /// Classifies one entry without side effects.
  Future<VlmReadiness> readiness(VlmModelEntry entry) async {
    if (!isPlatformSupported) return VlmReadiness.unsupported;
    final sdk = await _androidSdkInt();
    if (sdk != null && sdk < minAndroidSdk) return VlmReadiness.unsupported;
    try {
      await _backend.ensureInitialized();
      final installed = await _backend.isModelInstalled(entry.id);
      return installed ? VlmReadiness.ready : VlmReadiness.needsDownload;
    } catch (e) {
      _log.warning('VLM readiness check failed: $e');
      return VlmReadiness.unsupported;
    }
  }

  /// Human reason for [VlmReadiness.unsupported]; null otherwise.
  Future<String?> unsupportedReason(VlmModelEntry entry) async {
    if (await readiness(entry) != VlmReadiness.unsupported) return null;
    if (!isPlatformSupported) {
      return 'On-device vision transcription is only available on Android.';
    }
    final sdk = await _androidSdkInt();
    if (sdk != null && sdk < minAndroidSdk) {
      return 'On-device vision transcription needs Android 11 or newer.';
    }
    return 'On-device vision engine unavailable on this device.';
  }

  VlmDownloadHandle downloadModel(
    VlmModelEntry entry, {
    required void Function(int progress) onProgress,
  }) {
    return _backend.downloadModel(entry: entry, onProgress: onProgress);
  }

  /// Deletes an installed model file from this device. Throws
  /// [VlmException] on failure so callers can report it.
  Future<void> uninstallModel(VlmModelEntry entry) async {
    try {
      await _backend.ensureInitialized();
      await _backend.uninstallModel(entry);
      await unload();
    } catch (e) {
      throw VlmException('Could not uninstall ${entry.displayName}: $e');
    }
  }

  /// Catalog entry selected as default in settings, falling back to the
  /// recommended entry when unset or unknown.
  static VlmModelEntry preferredEntry() {
    final id = stows.vlmPreferredModelId.value;
    for (final entry in vlmTranscriptionModels) {
      if (entry.id == id) return entry;
    }
    return smolVlm2;
  }

  /// Transcribes one rendered page PNG. Throws [VlmNeedsDownloadException]
  /// when the model is missing, [VlmException] on any other failure.
  /// One generation at a time: a 500M+ vision model already saturates the
  /// device, so overlapping calls fail fast instead of OOMing.
  /// [prompt] defaults to [buildLatexPrompt]; callers pass a draft-enriched
  /// prompt when cheap OCR text is available.
  Future<String> transcribePngBytes(
    Uint8List pngBytes, {
    VlmModelEntry? model,
    String? prompt,
  }) async {
    if (_busy) throw VlmException('A transcription is already running.');
    _busy = true;
    try {
      return await _transcribeOnce(pngBytes, model: model, prompt: prompt);
    } finally {
      _busy = false;
    }
  }

  Future<String> _transcribeOnce(
    Uint8List pngBytes, {
    VlmModelEntry? model,
    String? prompt,
  }) async {
    final entry = model ?? smolVlm2;
    final state = await readiness(entry);
    if (state == VlmReadiness.unsupported) {
      throw VlmException(await unsupportedReason(entry) ?? 'Unsupported device.');
    }
    if (state == VlmReadiness.needsDownload) {
      throw VlmNeedsDownloadException(entry);
    }
    late final String raw;
    final stopwatch = Stopwatch()..start();
    try {
      raw = await _backend.generate(
        entry: entry,
        pngBytes: pngBytes,
        prompt: prompt ?? buildLatexPrompt(),
        timeout: generationTimeout,
      );
    } on TimeoutException {
      throw VlmException(
        'Transcription timed out. Try a smaller page region or close background apps.',
      );
    } catch (e) {
      throw VlmException('Transcription failed: $e');
    } finally {
      stopwatch.stop();
    }
    _log.info(
      'Transcribed ${(pngBytes.lengthInBytes / 1024).round()}KB image in '
      '${stopwatch.elapsed.inSeconds}s -> ${raw.length} chars.',
    );
    final latex = extractLatexDocument(raw);
    if (latex == null || latex.isEmpty) {
      throw VlmException('The model returned no usable LaTeX.');
    }
    return latex;
  }

  Future<void> unload() => _backend.unload();
}
