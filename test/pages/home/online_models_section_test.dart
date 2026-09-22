// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/pages/home/online_models_section.dart';
import 'package:saber/services/online/online_transcription_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeKeys extends OnlineKeyStore {
  _FakeKeys([Map<String, String>? seed]) : _keys = seed ?? {};

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

Future<void> _pumpSection(WidgetTester tester, _FakeKeys keys) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: OnlineModelTiles(keyStore: keys),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('backend radios toggle, online reveals provider rows', (
    tester,
  ) async {
    await _pumpSection(tester, _FakeKeys());

    // On-device is the default; provider rows hidden.
    expect(find.textContaining('Provider'), findsNothing);

    await tester.tap(find.textContaining('Online provider'));
    await tester.pumpAndSettle();

    expect(stows.latexBackend.value, 'online');
    expect(find.textContaining('Provider'), findsWidgets);
  });

  testWidgets('provider dialog switches preset', (tester) async {
    stows.latexBackend.value = 'online';
    addTearDown(() => stows.latexBackend.value = 'ondevice');
    await _pumpSection(tester, _FakeKeys());

    await tester.tap(find.textContaining('Provider').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Anthropic'), findsWidgets);
    await tester.tap(find.textContaining('Anthropic').last);
    await tester.pumpAndSettle();

    expect(stows.onlineProviderId.value, 'anthropic');
  });

  testWidgets('api key row reflects the keychain and edits', (tester) async {
    stows.latexBackend.value = 'online';
    stows.onlineProviderId.value = 'openai';
    addTearDown(() {
      stows.latexBackend.value = 'ondevice';
      stows.onlineProviderId.value = 'openai';
    });
    final keys = _FakeKeys({'openai': 'sk-test'});
    await _pumpSection(tester, keys);

    expect(find.textContaining('Key saved'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('online-key-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'sk-new');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(keys._keys['openai'], 'sk-new');
  });
}
