// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/services/vlm/vlm_model_catalog.dart';

void main() {
  group('catalog', () {
    test('default model comes first and is marked recommended', () {
      expect(vlmTranscriptionModels, isNotEmpty);
      expect(vlmTranscriptionModels.first.recommended, isTrue);
      expect(vlmTranscriptionModels.first, same(smolVlm2));
    });

    test('entries carry plausible download metadata', () {
      for (final entry in vlmTranscriptionModels) {
        expect(entry.id.endsWith('.litertlm'), isTrue);
        expect(entry.hfFile, entry.id);
        expect(entry.hfRepo.contains('/'), isTrue);
        expect(entry.bytes, greaterThan(100 * 1024 * 1024));
        expect(entry.downloadUrl, contains('huggingface.co'));
        expect(entry.downloadUrl, contains(entry.hfFile));
        expect(entry.maxTokens, greaterThanOrEqualTo(4096));
      }
      expect(smolVlm2.bytes, lessThan(qwen2Vl2b.bytes));
    });
  });

  group('buildLatexPrompt', () {
    test('asks for fenced LaTeX with block/inline math and full symbols', () {
      final prompt = buildLatexPrompt();
      expect(prompt, contains('```latex'));
      expect(prompt, contains(r'\['));
      expect(prompt, contains(r'\('));
      expect(prompt, contains(r'\int'));
      expect(prompt, contains('Greek'));
      expect(prompt, contains('[illegible]'));
    });

    test('embeds an OCR draft when provided', () {
      expect(buildLatexPrompt(), isNot(contains('rough OCR draft')));
      final withDraft = buildLatexPrompt(ocrDraft: 'hello world');
      expect(withDraft, contains('rough OCR draft'));
      expect(withDraft, contains('hello world'));
      expect(buildLatexPrompt(ocrDraft: '   '), isNot(contains('draft')));
    });
  });

  group('extractLatexDocument', () {
    test('prefers fenced latex blocks', () {
      const raw = 'Here you go:\n```latex\n\\[x^2\\]\n```\nDone.';
      expect(extractLatexDocument(raw), r'\[x^2\]');
    });

    test('accepts bare fences and bare latex', () {
      expect(extractLatexDocument('```\na+b\n```'), 'a+b');
      expect(extractLatexDocument('\\[a+b\\]'), r'\[a+b\]');
    });

    test('returns null for empty or non-latex output', () {
      expect(extractLatexDocument(''), isNull);
      expect(extractLatexDocument('   '), isNull);
      expect(extractLatexDocument('just some words'), isNull);
    });

    test('salvages truncated output missing the closing fence', () {
      expect(
        extractLatexDocument('```latex\n\\[x^2+1\\]'),
        r'\[x^2+1\]',
      );
    });
  });

  group('looksLikeLatex', () {
    test('accepts balanced latex, rejects garbage', () {
      expect(looksLikeLatex(r'\[x^2\]'), isTrue);
      expect(looksLikeLatex(r'Hello \(y\) world'), isTrue);
      expect(looksLikeLatex('plain words'), isFalse);
      expect(looksLikeLatex(r'\frac{a}{b'), isFalse);
      expect(looksLikeLatex('}oops{\\'), isFalse);
      expect(looksLikeLatex(''), isFalse);
    });
  });
}
