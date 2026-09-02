import 'package:flutter/foundation.dart';

import '../core/local_models.dart';
import '../data/models/provider_config.dart';
import 'llm_provider.dart';

/// On-device analysis provider (v2). Implements the same [LLMProvider] seam as
/// the cloud adapters, but runs a local Gemma model via [LocalModels] — no API
/// key, no network, nothing leaves the device.
///
/// Token usage is reported as zero: there is no metered cost on-device.
class LocalGemmaAdapter implements LLMProvider {
  @override
  final ProviderConfig config;

  LocalGemmaAdapter({required this.config});

  @override
  String get id => config.id;

  @override
  String get displayName => 'On-device (Gemma 4 E2B)';

  @override
  LLMCapabilities get capabilities =>
      const LLMCapabilities(streaming: true, jsonMode: true, contextWindow: 4096);

  @override
  Future<List<LLMModel>> listModels() async => const [
        LLMModel(
            id: LocalModels.gemmaModelId,
            displayName: 'Gemma 4 E2B (on-device)',
            contextWindow: 4096),
      ];

  @override
  Future<ValidationResult> validate() async {
    final ready = await LocalModels.instance.isGemmaInstalled();
    return ready
        ? const ValidationResult(true, 'On-device model is installed and ready.')
        : const ValidationResult(
            false, 'On-device model not downloaded yet — download it first.');
  }

  @override
  Future<PromptResponse> complete(PromptRequest request) async {
    // Nudge the small model toward clean JSON; the orchestrator still tolerates
    // fences/prose around the object.
    final system = request.expectJson
        ? '${request.system}\n\nReturn ONLY the JSON object, minified, with no '
            'markdown code fences and no text before or after it.'
        : request.system;
    try {
      final text = await LocalModels.instance.analyze(
        system: system,
        user: request.user,
        maxOutputTokens: request.maxTokens,
      );
      debugPrint('[GEMMA] raw output (${text.length} chars):\n$text');
      if (text.trim().isEmpty) {
        throw const LLMException('The on-device model returned an empty response.');
      }
      return PromptResponse(
        text: text,
        modelUsed: '${LocalModels.gemmaModelId} (on-device)',
        usage: const TokenUsage(),
      );
    } on LLMException {
      rethrow;
    } catch (e) {
      throw LLMException('On-device analysis failed: $e');
    }
  }
}
