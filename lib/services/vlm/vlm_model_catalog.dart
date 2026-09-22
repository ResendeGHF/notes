// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

/// Registry of on-device vision-language models used for page-to-LaTeX
/// transcription, plus the prompt and output post-processing shared by all
/// of them. Downloading happens a posteriori (see [PageLatexVlmService]);
/// nothing here touches native code, so it is fully unit-testable.
class VlmModelEntry {
  const VlmModelEntry({
    required this.id,
    required this.displayName,
    required this.hfRepo,
    required this.hfFile,
    required this.bytes,
    required this.sizeLabel,
    required this.maxTokens,
    required this.maxOutputTokens,
    this.recommended = false,
  });

  /// Stable id, also the installed file name shown by the plugin manager.
  final String id;

  /// Human-readable name with size, shown in download prompts.
  final String displayName;

  /// Hugging Face repo, e.g. `litert-community/SmolVLM2-500M`.
  final String hfRepo;

  /// File inside the repo, e.g. `SmolVLM2-500M.litertlm`.
  final String hfFile;

  /// Expected file size in bytes (from the Hub `x-linked-size` header).
  final int bytes;

  /// Short size label for download prompts, e.g. `~344 MB`.
  final String sizeLabel;

  /// Total context window requested at model load. Must cover vision tokens
  /// plus the LaTeX output; larger windows cost RAM.
  final int maxTokens;

  /// Hard cap on generated tokens per page. Bounds worst-case time on CPU:
  /// a rambling model cannot burn 10+ minutes; truncation is detectable
  /// (missing closing fence) and reported.
  final int maxOutputTokens;
  final bool recommended;

  /// Direct download URL (also what the installer resolves).
  String get downloadUrl => 'https://huggingface.co/$hfRepo/resolve/main/$hfFile';
}

/// SmolVLM2 500M, the default: compact document-understanding VLM, public
/// repo (no auth), ~344 MB. Best speed/size trade-off for handwriting.
const VlmModelEntry smolVlm2 = VlmModelEntry(
  id: 'SmolVLM2-500M.litertlm',
  displayName: 'SmolVLM2 500M (~344 MB)',
  hfRepo: 'litert-community/SmolVLM2-500M',
  hfFile: 'SmolVLM2-500M.litertlm',
  bytes: 360822960,
  sizeLabel: '~344 MB',
  maxTokens: 8192,
  maxOutputTokens: 2048,
  recommended: true,
);

/// Qwen2-VL 2B, the quality alternative: stronger on dense math but ~1.7 GB
/// and much slower. Public repo (no auth).
const VlmModelEntry qwen2Vl2b = VlmModelEntry(
  id: 'Qwen2-VL-2B.litertlm',
  displayName: 'Qwen2-VL 2B (~1.7 GB)',
  hfRepo: 'litert-community/Qwen2-VL-2B',
  hfFile: 'Qwen2-VL-2B.litertlm',
  bytes: 1783424544,
  sizeLabel: '~1.7 GB',
  maxTokens: 16384,
  maxOutputTokens: 4096,
);

/// All transcription models, default first.
const List<VlmModelEntry> vlmTranscriptionModels = [smolVlm2, qwen2Vl2b];

/// Instruction sent with every page image. English on purpose:
/// vision-instruction models follow short English prompts most reliably;
/// long rule lists make small models ramble (which is also what burns
/// minutes on CPU). [ocrDraft] is an imperfect ML Kit transcript included
/// as a guide — the image stays the source of truth for symbols/layout.
String buildLatexPrompt({String? ocrDraft}) {
  final buffer = StringBuffer(
    'Transcribe this handwritten notebook page into LaTeX. '
    'Top to bottom, keep line breaks.\n'
    'Plain writing as text; displayed equations as \\[ ... \\]; inline '
    'math as \\( ... \\).\n'
    'Use \\int \\frac{}{} \\sqrt{} \\sum Greek letters (\\alpha-\\Omega) '
    'matrices.\n'
    'Illegible regions become [illegible]. Do not invent content.\n',
  );
  final draft = ocrDraft?.trim();
  if (draft != null && draft.isNotEmpty) {
    buffer
      ..writeln(
        'A rough OCR draft follows (it misreads symbols; trust the image):',
      )
      ..writeln(draft);
  }
  buffer.write('Output ONLY one ```latex block, then stop.');
  return buffer.toString();
}

/// Extracts the LaTeX payload from raw model output: prefers a fenced
/// ```latex (or bare ```) block, else falls back to the trimmed output when
/// it already looks like LaTeX. Returns null when there is nothing usable.
String? extractLatexDocument(String raw) {
  final fenced = RegExp(
    r'```(?:latex|tex)?\s*([\s\S]*?)\s*```',
    caseSensitive: false,
  ).firstMatch(raw);
  if (fenced != null) {
    final body = fenced.group(1)!.trim();
    if (body.isNotEmpty) return body;
  }
  // Truncated generation (hit the output cap before the closing fence):
  // salvage everything after an opening fence.
  final openFence = RegExp(
    r'```(?:latex|tex)?\s*',
    caseSensitive: false,
  ).firstMatch(raw);
  if (openFence != null) {
    final body = raw
        .substring(openFence.end)
        .replaceAll(RegExp(r'`+\s*$'), '')
        .trim();
    if (body.isNotEmpty) return body;
  }
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.contains('\\') || trimmed.contains('\$')) return trimmed;
  return null;
}

/// Light sanity check: non-empty with at least one LaTeX marker and
/// balanced braces. Imperfect output still passes; garbage does not.
bool looksLikeLatex(String text) {
  final t = text.trim();
  if (t.isEmpty) return false;
  if (!t.contains('\\') && !t.contains('\$')) return false;
  var depth = 0;
  for (var i = 0; i < t.length; i++) {
    final c = t[i];
    if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth < 0) return false;
    }
  }
  return depth == 0;
}
