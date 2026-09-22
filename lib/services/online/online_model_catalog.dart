// SPDX-FileCopyrightText: 2026 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

/// Wire format of an online transcription provider.
enum OnlineProviderKind {
  /// OpenAI chat-completions schema (`/v1/chat/completions` with an
  /// `image_url` content part). Also spoken by OpenRouter, Pollinations,
  /// Together, Groq and other gateways.
  openAiCompatible,

  /// Anthropic Messages schema (`/v1/messages` with base64 image blocks).
  anthropic,
}

/// A transcription provider preset. Model ids, free-tier rosters and data
/// policies change over time, so [defaultModel] and [baseUrl] are starting
/// points the user can override in settings — never hard requirements.
/// Retention notes are honest summaries, not legal advice; Zero Data
/// Retention itself is a contract between the user and the provider.
class OnlineProviderPreset {
  const OnlineProviderPreset({
    required this.id,
    required this.displayName,
    required this.kind,
    required this.baseUrl,
    required this.defaultModel,
    required this.needsKey,
    required this.retentionNote,
    required this.keyHelp,
  });

  /// Stable id, also used for the secure-storage key slot.
  final String id;
  final String displayName;
  final OnlineProviderKind kind;

  /// Endpoint root without trailing slash.
  final String baseUrl;
  final String defaultModel;

  /// False for keyless public gateways (Pollinations).
  final bool needsKey;

  /// Short, honest data-retention summary shown in settings.
  final String retentionNote;

  /// Where to obtain a key (empty for keyless presets).
  final String keyHelp;
}

/// GPT-4o over the official API. Paid per use; OpenAI does not train on API
/// data by default, with Zero Data Retention on eligible tiers.
const OnlineProviderPreset openAiPreset = OnlineProviderPreset(
  id: 'openai',
  displayName: 'OpenAI (GPT-4o)',
  kind: OnlineProviderKind.openAiCompatible,
  baseUrl: 'https://api.openai.com/v1',
  defaultModel: 'gpt-4o',
  needsKey: true,
  retentionNote:
      'Paid API key. OpenAI does not train on API data by default; '
      'Zero Data Retention is available on eligible tiers.',
  keyHelp: 'Create a key at platform.openai.com/api-keys',
);

/// Claude Sonnet over the official API. Paid per use; Anthropic does not
/// train on API data, with Zero Data Retention programs available.
const OnlineProviderPreset anthropicPreset = OnlineProviderPreset(
  id: 'anthropic',
  displayName: 'Anthropic (Claude Sonnet)',
  kind: OnlineProviderKind.anthropic,
  baseUrl: 'https://api.anthropic.com/v1',
  defaultModel: 'claude-3-5-sonnet-latest',
  needsKey: true,
  retentionNote:
      'Paid API key. Anthropic does not train on API data; '
      'Zero Data Retention programs are available.',
  keyHelp: 'Create a key at console.anthropic.com',
);

/// OpenRouter gateway (OpenAI-compatible). Free `:free` models exist but the
/// roster rotates; the default below is editable. Free tiers may log
/// requests and allow training — check the provider terms for sensitive work.
const OnlineProviderPreset openRouterPreset = OnlineProviderPreset(
  id: 'openrouter',
  displayName: 'OpenRouter (free models available)',
  kind: OnlineProviderKind.openAiCompatible,
  baseUrl: 'https://openrouter.ai/api/v1',
  defaultModel: 'meta-llama/llama-3.2-11b-vision-instruct:free',
  needsKey: true,
  retentionNote:
      'Free :free models are rate-limited and may log requests for training. '
      'Paid models follow stricter retention terms.',
  keyHelp: 'Create a key at openrouter.ai/keys (free, no card required)',
);

/// Pollinations public gateway (OpenAI-compatible). Free without a key;
/// treat it as a public service and avoid sensitive notes.
const OnlineProviderPreset pollinationsPreset = OnlineProviderPreset(
  id: 'pollinations',
  displayName: 'Pollinations (free, no key)',
  kind: OnlineProviderKind.openAiCompatible,
  baseUrl: 'https://text.pollinations.ai/openai',
  defaultModel: 'openai',
  needsKey: false,
  retentionNote:
      'Free public service without a key. Assume requests may be logged; '
      'avoid sensitive notes.',
  keyHelp: '',
);

/// Fully user-defined endpoint speaking one of the two wire formats.
const OnlineProviderPreset customPreset = OnlineProviderPreset(
  id: 'custom',
  displayName: 'Custom endpoint',
  kind: OnlineProviderKind.openAiCompatible,
  baseUrl: '',
  defaultModel: '',
  needsKey: false,
  retentionNote:
      'Your server, your terms. Retention depends entirely on configuration.',
  keyHelp: '',
);

/// All provider presets, defaults first.
const List<OnlineProviderPreset> onlineProviderPresets = [
  openAiPreset,
  anthropicPreset,
  openRouterPreset,
  pollinationsPreset,
  customPreset,
];

/// Resolves [id] to its preset, falling back to OpenAI for unknown ids.
OnlineProviderPreset onlinePresetForId(String id) {
  for (final preset in onlineProviderPresets) {
    if (preset.id == id) return preset;
  }
  return openAiPreset;
}
