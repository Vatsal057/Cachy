/// On-device AI (V2): optional local model that structures quota-degraded
/// cards on the user's phone — zero server AI spend.
///
/// Interface + pure helpers only; the real Gemma runtime lives in
/// `gemma_local_ai_service.dart`, tests use a fake.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Where the local model currently stands.
enum LocalAiPhase {
  /// Platform can't run it (web/desktop/iOS) — feature hidden entirely.
  unsupported,
  notInstalled,
  downloading,
  ready,
  error,
}

@immutable
class LocalAiStatus {
  const LocalAiStatus(this.phase, {this.progress = 0, this.message = ''});
  final LocalAiPhase phase;

  /// Download progress 0–1 (only meaningful while [LocalAiPhase.downloading]).
  final double progress;

  /// Human-readable detail for error states.
  final String message;
}

/// Contract for the on-device structuring model (mirrors the service-with-fake
/// test pattern used across the app).
abstract class LocalAiService extends ChangeNotifier {
  LocalAiStatus get status;

  /// User opt-in toggle (persisted). Downloaded-but-disabled stays on disk.
  bool get enabled;
  Future<void> setEnabled(bool value);

  /// True when the degrade path should attempt on-device structuring.
  bool get canStructure =>
      enabled && status.phase == LocalAiPhase.ready;

  /// Persist the HuggingFace token used for the license-gated model download.
  Future<void> saveHfToken(String token);

  /// Download + install the model (~550 MB — caller shows the Wi-Fi warning).
  Future<void> download();

  /// Remove the model from disk.
  Future<void> delete();

  /// Structure an extraction bundle into card JSON.
  /// Returns null when generation fails or the output isn't a valid card —
  /// callers keep the paragraph card (silent grace).
  Future<Map<String, dynamic>?> structureBundle(
    String bundle, {
    String transcript = '',
    String caption = '',
  });
}

/// Prompt tuned for 1B models: short instruction, one few-shot example,
/// strict JSON-only suffix.
String buildStructurePrompt(String bundle) => '''
You turn a video's raw text into one JSON knowledge card. Reply with JSON only, no prose, no markdown fences.

Schema:
{"base": {"one_liner": str, "tldr": str, "content_type": "recipe|tutorial|tip|product_list|travel|news_explainer|other", "tags": [str]}, "blocks": [{"type": "paragraph", "text": str} | {"type": "checklist", "items": [{"text": str, "checked": false}]} | {"type": "heading", "text": str}]}

Example input:
TRANSCRIPT: Boil pasta in salted water. Save a cup of pasta water. Finish the pasta in the sauce pan.

Example output:
{"base": {"one_liner": "Finish pasta in the sauce, not the pot", "tldr": "Salt the water, reserve starchy water, marry pasta and sauce in the pan.", "content_type": "recipe", "tags": ["cooking", "pasta"]}, "blocks": [{"type": "checklist", "items": [{"text": "Boil pasta in salted water", "checked": false}, {"text": "Reserve 1 cup pasta water", "checked": false}, {"text": "Finish pasta in the sauce pan", "checked": false}]}]}

Input:
$bundle

Output (JSON only):''';

/// Parse + minimally validate model output into card JSON.
///
/// Strips markdown fences and stray prefix/suffix text, requires a `base` map
/// and a non-empty `blocks` list. Returns null on anything else — the server
/// re-validates with full coercion, this guard just avoids pointless uploads.
Map<String, dynamic>? parseModelCardJson(String raw) {
  var text = raw.trim();
  // Strip ```json fences.
  text = text.replaceAll(RegExp(r'^```[a-zA-Z]*\s*', multiLine: false), '');
  text = text.replaceAll(RegExp(r'```\s*$'), '').trim();
  // Clamp to the outermost JSON object if the model added prose around it.
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  text = text.substring(start, end + 1);

  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  final base = decoded['base'];
  final blocks = decoded['blocks'];
  if (base is! Map || blocks is! List || blocks.isEmpty) return null;
  if ((base['one_liner'] ?? '').toString().trim().isEmpty) return null;
  return decoded;
}
