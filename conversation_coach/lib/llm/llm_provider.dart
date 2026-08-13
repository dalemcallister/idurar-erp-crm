import '../data/models/provider_config.dart';

/// Capabilities a provider advertises so the orchestrator can negotiate
/// behaviour (Tech Spec §5 — capability negotiation).
class LLMCapabilities {
  final bool streaming;
  final bool jsonMode;
  final int contextWindow;
  final bool vision;

  const LLMCapabilities({
    this.streaming = true,
    this.jsonMode = true,
    this.contextWindow = 200000,
    this.vision = false,
  });
}

/// A model offered by a provider.
class LLMModel {
  final String id;
  final String displayName;
  final int contextWindow;

  const LLMModel({
    required this.id,
    required this.displayName,
    this.contextWindow = 200000,
  });
}

/// Outcome of validating a provider config with a test call (F-MOD-07).
class ValidationResult {
  final bool ok;
  final String message;

  const ValidationResult(this.ok, this.message);
}

/// A structured-output request. The orchestrator asks for strict JSON so
/// results map cleanly to the data model (Tech Spec §5).
class PromptRequest {
  final String system;
  final String user;
  final int maxTokens;

  /// When set, the adapter instructs the model to return only JSON.
  final bool expectJson;

  /// Optional per-task model override (F-MOD-04). Falls back to the config's
  /// default model when null.
  final String? modelOverride;

  /// Name of the analysis task (e.g. "analysis", "qa"). Real adapters ignore
  /// this; the offline mock adapter uses it to choose which JSON shape to
  /// synthesise. Also used by the per-task override lookup.
  final String task;

  const PromptRequest({
    required this.system,
    required this.user,
    this.maxTokens = 4096,
    this.expectJson = true,
    this.modelOverride,
    this.task = 'analysis',
  });
}

/// Token accounting for the per-session cost meter (F-MOD-06).
class TokenUsage {
  final int inputTokens;
  final int outputTokens;

  const TokenUsage({this.inputTokens = 0, this.outputTokens = 0});

  TokenUsage operator +(TokenUsage other) => TokenUsage(
        inputTokens: inputTokens + other.inputTokens,
        outputTokens: outputTokens + other.outputTokens,
      );
}

class PromptResponse {
  final String text;
  final TokenUsage usage;
  final String modelUsed;

  const PromptResponse({
    required this.text,
    this.usage = const TokenUsage(),
    required this.modelUsed,
  });
}

/// The single internal interface every analysis and Q&A call passes through.
/// Swappable adapters implement it (Anthropic, OpenAI-compatible, Ollama,
/// mock) — Tech Spec §5.
abstract class LLMProvider {
  String get id;
  String get displayName;
  LLMCapabilities get capabilities;

  /// The config this adapter was built from.
  ProviderConfig get config;

  /// Models available within this provider (F-MOD-02).
  Future<List<LLMModel>> listModels();

  /// Validate the configuration with a real test call before saving (F-MOD-07).
  Future<ValidationResult> validate();

  /// Structured / JSON completion used by the analysis pipeline and Q&A.
  Future<PromptResponse> complete(PromptRequest request);
}

/// Thrown when an adapter cannot complete a request (surfaced to the user and
/// retried with backoff by the orchestrator — Tech Spec §5 resilience).
class LLMException implements Exception {
  final String message;
  final int? statusCode;
  const LLMException(this.message, {this.statusCode});

  @override
  String toString() => 'LLMException($statusCode): $message';
}
