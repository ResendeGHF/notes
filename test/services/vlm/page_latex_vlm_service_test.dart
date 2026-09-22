// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/services/vlm/page_latex_vlm_service.dart';
import 'package:saber/services/vlm/vlm_model_catalog.dart';

class _FakeHandle implements VlmDownloadHandle {
  _FakeHandle(this.done);

  @override
  final Future<void> done;

  var cancelled = false;

  @override
  void cancel() => cancelled = true;
}

class FakeVlmBackend implements VlmInferenceBackend {
  var initialized = false;
  var installed = true;
  var downloads = 0;
  var generations = 0;
  String nextOutput = '```latex\n\\[x^2\\]\n```';
  Duration generateDelay = Duration.zero;

  @override
  Future<void> ensureInitialized() async => initialized = true;

  @override
  Future<bool> isModelInstalled(String modelId) async => installed;

  @override
  VlmDownloadHandle downloadModel({
    required VlmModelEntry entry,
    required void Function(int progress) onProgress,
  }) {
    downloads++;
    onProgress(100);
    return _FakeHandle(Future<void>.value());
  }

  @override
  Future<String> generate({
    required VlmModelEntry entry,
    required Uint8List pngBytes,
    required String prompt,
    required Duration timeout,
  }) async {
    generations++;
    if (generateDelay > Duration.zero) await Future.delayed(generateDelay);
    return nextOutput;
  }

  @override
  Future<void> uninstallModel(VlmModelEntry entry) async {
    installed = false;
  }

  @override
  Future<void> unload() async {}
}

void main() {
  group('PageLatexVlmService', () {
    test('transcribes fenced output to the latex body', () async {
      final backend = FakeVlmBackend();
      final svc = PageLatexVlmService(backend: backend);
      final latex = await svc.transcribePngBytes(
        Uint8List.fromList([1, 2, 3]),
      );
      expect(latex, r'\[x^2\]');
      expect(backend.generations, 1);
    });

    test('throws needs-download when the model is missing', () async {
      final backend = FakeVlmBackend()..installed = false;
      final svc = PageLatexVlmService(backend: backend);
      expect(
        () => svc.transcribePngBytes(Uint8List.fromList([1])),
        throwsA(isA<VlmNeedsDownloadException>()),
      );
      expect(backend.generations, 0);
    });

    test('throws on empty model output', () async {
      final backend = FakeVlmBackend()..nextOutput = 'nothing usable here';
      final svc = PageLatexVlmService(backend: backend);
      expect(
        () => svc.transcribePngBytes(Uint8List.fromList([1])),
        throwsA(isA<VlmException>()),
      );
    });

    test('rejects overlapping generations instead of OOMing', () async {
      final backend = FakeVlmBackend()
        ..generateDelay = const Duration(milliseconds: 50);
      final svc = PageLatexVlmService(backend: backend);
      final first = svc.transcribePngBytes(Uint8List.fromList([1]));
      await expectLater(
        svc.transcribePngBytes(Uint8List.fromList([2])),
        throwsA(isA<VlmException>()),
      );
      await first;
      expect(backend.generations, 1);
    });

    test('readiness reflects installation state', () async {
      final backend = FakeVlmBackend();
      final svc = PageLatexVlmService(backend: backend);
      expect(await svc.readiness(smolVlm2), VlmReadiness.ready);
      backend.installed = false;
      expect(await svc.readiness(smolVlm2), VlmReadiness.needsDownload);
    });

    test('download delegates progress', () async {
      final backend = FakeVlmBackend();
      final svc = PageLatexVlmService(backend: backend);
      final seen = <int>[];
      final handle = svc.downloadModel(smolVlm2, onProgress: seen.add);
      await handle.done;
      expect(seen, contains(100));
      expect(backend.downloads, 1);
    });
  });
}
