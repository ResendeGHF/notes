// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/pages/home/vlm_models_section.dart';
import 'package:saber/services/vlm/page_latex_vlm_service.dart';
import 'package:saber/services/vlm/vlm_model_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeHandle implements VlmDownloadHandle {
  _FakeHandle(this.done);

  @override
  final Future<void> done;

  var cancelled = false;

  @override
  void cancel() => cancelled = true;
}

class _FakeBackend implements VlmInferenceBackend {
  final Set<String> installedIds = {};

  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<bool> isModelInstalled(String modelId) async =>
      installedIds.contains(modelId);

  @override
  VlmDownloadHandle downloadModel({
    required VlmModelEntry entry,
    required void Function(int progress) onProgress,
  }) {
    onProgress(100);
    installedIds.add(entry.id);
    return _FakeHandle(Future<void>.value());
  }

  @override
  Future<String> generate({
    required VlmModelEntry entry,
    required Uint8List pngBytes,
    required String prompt,
    required Duration timeout,
  }) async =>
      'output';

  @override
  Future<void> uninstallModel(VlmModelEntry entry) async {
    installedIds.remove(entry.id);
  }

  @override
  Future<void> unload() async {}
}

Future<void> _pumpTiles(
  WidgetTester tester,
  _FakeBackend backend,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: VlmModelTiles(
            service: PageLatexVlmService(backend: backend),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('missing models offer download, then show uninstall', (
    tester,
  ) async {
    final backend = _FakeBackend();
    await _pumpTiles(tester, backend);

    expect(find.textContaining('Download'), findsNWidgets(2));

    await tester.tap(find.textContaining('Download').first);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.textContaining('Download'), findsOneWidget);
  });

  testWidgets('uninstall asks for confirmation before removing', (
    tester,
  ) async {
    final backend = _FakeBackend()
      ..installedIds.addAll([smolVlm2.id, qwen2Vl2b.id]);
    await _pumpTiles(tester, backend);

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();

    // Confirm dialog appears; cancelling keeps the model.
    expect(find.textContaining('Uninstall model?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));

    // Confirming removes it.
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });
}
