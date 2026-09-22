// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/services/online/online_model_catalog.dart';
import 'package:saber/services/online/online_transcription_service.dart';
import 'package:saber/services/vlm/page_latex_vlm_service.dart'
    show VlmException;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('catalog', () {
    test('presets have unique ids, https endpoints and retention notes', () {
      final ids = onlineProviderPresets.map((p) => p.id).toSet();
      expect(ids.length, onlineProviderPresets.length);
      for (final preset in onlineProviderPresets) {
        if (preset.id != 'custom') {
          expect(preset.baseUrl.startsWith('https://'), isTrue);
        }
        expect(preset.retentionNote, isNotEmpty);
        expect(preset.displayName, isNotEmpty);
      }
      expect(onlinePresetForId('nope'), same(openAiPreset));
      expect(onlinePresetForId('anthropic'), same(anthropicPreset));
    });
  });

  group('OpenAI-compatible wire format', () {
    test('posts model, prompt and data-url image with bearer key', () async {
      Map<String, dynamic>? seenBody;
      Map<String, String>? seenHeaders;
      Uri? seenUrl;
      final client = MockClient((request) async {
        seenUrl = request.url;
        seenHeaders = request.headers;
        seenBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '```latex\n\\[x\\]\n```'},
              },
            ],
          }),
          200,
        );
      });
      final store = _FakeKeys({'openai': 'sk-test'});
      final svc = OnlineTranscriptionService(
        httpClient: client,
        keyStore: store,
      );

      final latex = await svc.transcribePngBytes(
        Uint8List.fromList([1, 2, 3]),
        prompt: 'prompt',
      );

      expect(latex, r'\[x\]');
      expect(seenUrl.toString(), endsWith('/chat/completions'));
      expect(seenHeaders!['Authorization'], 'Bearer sk-test');
      expect(seenBody!['model'], 'gpt-4o');
      expect(seenBody!['temperature'], 0.1);
      final content = (seenBody!['messages'] as List).first['content'] as List;
      expect(content.any((p) => p['type'] == 'text'), isTrue);
      final imagePart = content.firstWhere((p) => p['type'] == 'image_url');
      expect(
        (imagePart['image_url'] as Map)['url'],
        startsWith('data:image/png;base64,'),
      );
    });

    test('joins array content parts and surfaces HTTP errors', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': [
                    {'type': 'text', 'text': '```latex'},
                    {'type': 'text', 'text': r'\[y\]'},
                    {'type': 'text', 'text': '```'},
                  ],
                },
              },
            ],
          }),
          200,
        );
      });
      final svc = OnlineTranscriptionService(
        httpClient: client,
        keyStore: _FakeKeys({'openai': 'sk-test'}),
      );
      expect(
        await svc.transcribePngBytes(Uint8List.fromList([1]), prompt: 'p'),
        r'\[y\]',
      );

      final failing = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {'message': 'bad key'},
          }),
          401,
        );
      });
      final failingSvc = OnlineTranscriptionService(
        httpClient: failing,
        keyStore: _FakeKeys({'openai': 'sk-test'}),
      );
      await expectLater(
        failingSvc.transcribePngBytes(Uint8List.fromList([1]), prompt: 'p'),
        throwsA(
          isA<VlmException>().having(
            (e) => e.message,
            'message',
            allOf(contains('401'), contains('bad key')),
          ),
        ),
      );
      // API keys never leak into error text.
      await expectLater(
        failingSvc.transcribePngBytes(Uint8List.fromList([1]), prompt: 'p'),
        throwsA(
          isA<VlmException>().having(
            (e) => e.message,
            'message',
            isNot(contains('sk-test')),
          ),
        ),
      );
    });

    test('missing key guides to Settings without network', () async {
      var called = false;
      final client = MockClient((request) async {
        called = true;
        return http.Response('{}', 200);
      });
      final svc = OnlineTranscriptionService(
        httpClient: client,
        keyStore: _FakeKeys({}),
      );
      await expectLater(
        svc.transcribePngBytes(Uint8List.fromList([1]), prompt: 'p'),
        throwsA(isA<OnlineKeyMissingException>()),
      );
      expect(called, isFalse);
    });
  });

  group('Anthropic wire format', () {
    test('posts base64 blocks with version header', () async {
      Map<String, dynamic>? seenBody;
      Map<String, String>? seenHeaders;
      Uri? seenUrl;
      final client = MockClient((request) async {
        seenUrl = request.url;
        seenHeaders = request.headers;
        seenBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'content': [
              {'type': 'text', 'text': '```latex\n\\[z\\]\n```'},
            ],
          }),
          200,
        );
      });
      final svc = OnlineTranscriptionService(
        httpClient: client,
        keyStore: _FakeKeys({'anthropic': 'sk-ant-test'}),
      );
      // Point prefs at Anthropic for this call.
      final previous = await _withProvider('anthropic', () async {
        return svc.transcribePngBytes(Uint8List.fromList([1]), prompt: 'p');
      });

      expect(previous, r'\[z\]');
      expect(seenUrl.toString(), endsWith('/messages'));
      expect(seenHeaders!['x-api-key'], 'sk-ant-test');
      expect(seenHeaders!['anthropic-version'], '2023-06-01');
      expect(seenBody!['model'], contains('claude'));
      expect(seenBody!['max_tokens'], greaterThan(0));
    });
  });
}

/// Runs [fn] with the online provider pref temporarily set to [id].
Future<T> _withProvider<T>(String id, Future<T> Function() fn) async {
  final previous = stows.onlineProviderId.value;
  stows.onlineProviderId.value = id;
  try {
    return await fn();
  } finally {
    stows.onlineProviderId.value = previous;
  }
}

class _FakeKeys extends OnlineKeyStore {
  _FakeKeys(this._keys);

  final Map<String, String> _keys;

  @override
  Future<String?> readKey(String providerId) async => _keys[providerId];

  @override
  Future<void> writeKey(String providerId, String key) async {
    _keys[providerId] = key;
  }

  @override
  Future<void> deleteKey(String providerId) async {
    _keys.remove(providerId);
  }
}
