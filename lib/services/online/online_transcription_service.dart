// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/services/online/online_model_catalog.dart';
import 'package:saber/services/vlm/page_latex_vlm_service.dart'
    show VlmException;
import 'package:saber/services/vlm/vlm_model_catalog.dart'
    show extractLatexDocument;

/// User-facing failure of online transcription (bad config, HTTP error,
/// empty output). Message is safe to show; API keys are never included.
class OnlineTranscriptionException extends VlmException {
  OnlineTranscriptionException(super.message);
}

/// Thrown when the active online provider still needs an API key.
class OnlineKeyMissingException extends OnlineTranscriptionException {
  OnlineKeyMissingException(super.message);
}

/// Secure-storage slots for provider API keys (keys never touch prefs/logs).
String onlineApiKeySlot(String providerId) => 'online_api_key_$providerId';

/// Minimal secure key access, injectable for tests.
class OnlineKeyStore {
  OnlineKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<String?> readKey(String providerId) {
    try {
      return _storage.read(key: onlineApiKeySlot(providerId));
    } catch (_) {
      return Future.value();
    }
  }

  Future<void> writeKey(String providerId, String key) {
    return _storage.write(key: onlineApiKeySlot(providerId), value: key);
  }

  Future<void> deleteKey(String providerId) {
    return _storage.delete(key: onlineApiKeySlot(providerId));
  }
}

/// Resolved, ready-to-call provider configuration.
class ResolvedOnlineProvider {
  const ResolvedOnlineProvider({
    required this.preset,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });

  final OnlineProviderPreset preset;
  final String baseUrl;
  final String model;

  /// Null for keyless presets.
  final String? apiKey;
}

/// HTTPS transcription against OpenAI-compatible and Anthropic endpoints.
/// The HTTP client is injectable so payloads and parsing are unit-testable
/// without network.
class OnlineTranscriptionService {
  OnlineTranscriptionService({
    http.Client? httpClient,
    OnlineKeyStore? keyStore,
  }) : _http = httpClient ?? http.Client(),
       _keys = keyStore ?? OnlineKeyStore();

  static final _log = Logger('OnlineTranscriptionService');

  /// Generous budget: remote VLMs answer dense pages in tens of seconds.
  static const Duration requestTimeout = Duration(minutes: 3);

  /// Max tokens requested per page transcription.
  static const int maxOutputTokens = 4096;

  final http.Client _http;
  final OnlineKeyStore _keys;

  /// Reads prefs + keychain and validates the active provider. Throws
  /// [OnlineKeyMissingException] or [OnlineTranscriptionException].
  Future<ResolvedOnlineProvider> resolveActiveProvider() async {
    final preset = onlinePresetForId(stows.onlineProviderId.value);
    final customModel = stows.onlineModel.value.trim();
    final customBase = stows.onlineBaseUrl.value.trim();
    final baseUrl = preset.id == 'custom'
        ? customBase
        : (customBase.isEmpty ? preset.baseUrl : customBase);
    if (baseUrl.isEmpty || !baseUrl.startsWith('http')) {
      throw OnlineTranscriptionException(
        'Configure an endpoint URL for ${preset.displayName} in Settings.',
      );
    }
    final model = customModel.isEmpty ? preset.defaultModel : customModel;
    if (model.isEmpty) {
      throw OnlineTranscriptionException(
        'Configure a model for ${preset.displayName} in Settings.',
      );
    }
    String? apiKey;
    if (preset.needsKey) {
      final stored = await _keys.readKey(preset.id);
      apiKey = stored?.trim();
      if (apiKey == null || apiKey.isEmpty) {
        throw OnlineKeyMissingException(
          'Add an API key for ${preset.displayName} in Settings.',
        );
      }
    }
    return ResolvedOnlineProvider(
      preset: preset,
      baseUrl: baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl,
      model: model,
      apiKey: apiKey,
    );
  }

  /// Transcribes one rendered page PNG with [prompt]. Returns extracted
  /// LaTeX; throws on HTTP, API or parse failures.
  Future<String> transcribePngBytes(
    Uint8List pngBytes, {
    required String prompt,
  }) async {
    final provider = await resolveActiveProvider();
    late final String raw;
    try {
      raw = switch (provider.preset.kind) {
        OnlineProviderKind.openAiCompatible => await _postOpenAiCompatible(
          provider,
          pngBytes: pngBytes,
          prompt: prompt,
        ),
        OnlineProviderKind.anthropic => await _postAnthropic(
          provider,
          pngBytes: pngBytes,
          prompt: prompt,
        ),
      };
    } on OnlineTranscriptionException {
      rethrow;
    } catch (e) {
      throw OnlineTranscriptionException('Transcription failed: $e');
    }
    final latex = extractLatexDocument(raw);
    if (latex == null || latex.isEmpty) {
      throw OnlineTranscriptionException(
        'The model returned no usable LaTeX.',
      );
    }
    return latex;
  }

  Future<String> _postOpenAiCompatible(
    ResolvedOnlineProvider provider, {
    required Uint8List pngBytes,
    required String prompt,
  }) async {
    final body = <String, Object?>{
      'model': provider.model,
      'temperature': 0.1,
      'max_tokens': maxOutputTokens,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {
                'url':
                    'data:image/png;base64,${base64Encode(pngBytes)}',
              },
            },
          ],
        },
      ],
    };
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (provider.apiKey != null) {
      headers['Authorization'] = 'Bearer ${provider.apiKey}';
    }
    http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse('${provider.baseUrl}/chat/completions'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      throw OnlineTranscriptionException(
        'Transcription timed out. Try a smaller page region.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OnlineTranscriptionException(
        _shortHttpError(response.statusCode, response.body),
      );
    }
    try {
      final decoded = jsonDecode(response.body);
      final choices = decoded['choices'] as List;
      if (choices.isEmpty) {
        throw OnlineTranscriptionException('The model returned no choices.');
      }
      final content = (choices.first as Map)['message']?['content'];
      return _joinContentParts(content);
    } catch (e) {
      if (e is OnlineTranscriptionException) rethrow;
      throw OnlineTranscriptionException(
        'Could not parse the model response: $e',
      );
    }
  }

  Future<String> _postAnthropic(
    ResolvedOnlineProvider provider, {
    required Uint8List pngBytes,
    required String prompt,
  }) async {
    final body = <String, Object?>{
      'model': provider.model,
      'max_tokens': maxOutputTokens,
      'temperature': 0.1,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': 'image/png',
                'data': base64Encode(pngBytes),
              },
            },
            {'type': 'text', 'text': prompt},
          ],
        },
      ],
    };
    http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse('${provider.baseUrl}/messages'),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': provider.apiKey ?? '',
              'anthropic-version': '2023-06-01',
            },
            body: jsonEncode(body),
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      throw OnlineTranscriptionException(
        'Transcription timed out. Try a smaller page region.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OnlineTranscriptionException(
        _shortHttpError(response.statusCode, response.body),
      );
    }
    try {
      final decoded = jsonDecode(response.body);
      final blocks = decoded['content'] as List;
      final texts = <String>[];
      for (final block in blocks) {
        final map = block as Map;
        if (map['type'] == 'text' && map['text'] is String) {
          texts.add(map['text'] as String);
        }
      }
      if (texts.isEmpty) {
        throw OnlineTranscriptionException('The model returned no text.');
      }
      return texts.join('\n');
    } catch (e) {
      if (e is OnlineTranscriptionException) rethrow;
      throw OnlineTranscriptionException(
        'Could not parse the model response: $e',
      );
    }
  }

  /// Joins OpenAI message content, which is either a plain string or a list
  /// of `{type, text}` parts.
  String _joinContentParts(Object? content) {
    if (content is String) return content;
    if (content is List) {
      final texts = <String>[];
      for (final part in content) {
        if (part is Map && part['text'] is String) {
          texts.add(part['text'] as String);
        }
      }
      if (texts.isNotEmpty) return texts.join('\n');
    }
    throw OnlineTranscriptionException('The model returned no text.');
  }

  /// Short, key-free error summary (truncates provider HTML dumps).
  String _shortHttpError(int status, String body) {
    var detail = body.trim();
    try {
      final decoded = jsonDecode(body);
      final map = decoded is Map ? decoded : null;
      final err = map?['error'];
      if (err is Map && err['message'] is String) {
        detail = err['message'] as String;
      } else if (err is String) {
        detail = err;
      } else if (map?['message'] is String) {
        detail = map!['message'] as String;
      }
    } catch (_) {
      // Fall through with the raw body below.
    }
    if (detail.length > 300) detail = '${detail.substring(0, 300)}…';
    _log.warning('Online transcription HTTP $status: $detail');
    return 'Request failed (HTTP $status): $detail';
  }

  void dispose() {
    try {
      _http.close();
    } catch (_) {}
  }
}

