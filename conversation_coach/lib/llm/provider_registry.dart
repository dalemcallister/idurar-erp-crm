import '../core/local_models.dart';
import '../data/models/provider_config.dart';
import '../data/secure_keystore.dart';
import 'anthropic_adapter.dart';
import 'llm_provider.dart';
import 'local_gemma_adapter.dart';
import 'mock_adapter.dart';
import 'openai_compatible_adapter.dart';

/// Builds a concrete [LLMProvider] adapter from a [ProviderConfig], resolving
/// the API key from the keystore at call time (never persisting it). This is
/// the seam that makes "the user selects the model" a configuration change
/// rather than a rewrite (Tech Spec §3 / §5).
class ProviderRegistry {
  final SecureKeystore keystore;

  ProviderRegistry(this.keystore);

  Future<LLMProvider> build(ProviderConfig config) async {
    switch (config.provider) {
      case ProviderKind.anthropic:
        final key =
            config.apiKeyRef == null ? null : await keystore.read(config.apiKeyRef!);
        return AnthropicAdapter(config: config, apiKey: key);
      case ProviderKind.openaiCompatible:
        final key =
            config.apiKeyRef == null ? null : await keystore.read(config.apiKeyRef!);
        return OpenAICompatibleAdapter(config: config, apiKey: key);
      case ProviderKind.ollama:
        return OpenAICompatibleAdapter(
            config: config, apiKey: null, isLocal: true);
      case ProviderKind.local:
        return LocalGemmaAdapter(config: config);
      case ProviderKind.mock:
        return MockAdapter(config: config);
    }
  }

  /// Resolves the provider to actually use for analysis, with a graceful
  /// fallback to the offline demo so the loop still completes:
  ///   - cloud providers fall back when no key is stored;
  ///   - the on-device provider falls back when its model isn't downloaded yet.
  Future<LLMProvider> resolveForAnalysis(ProviderConfig preferred) async {
    if (preferred.provider == ProviderKind.anthropic ||
        preferred.provider == ProviderKind.openaiCompatible) {
      final hasKey = preferred.apiKeyRef != null &&
          await keystore.has(preferred.apiKeyRef!);
      if (!hasKey) {
        return MockAdapter(config: ProviderConfig.mock());
      }
    }
    if (preferred.provider == ProviderKind.local) {
      final ready = await LocalModels.instance.isGemmaInstalled();
      if (!ready) {
        return MockAdapter(config: ProviderConfig.mock());
      }
    }
    return build(preferred);
  }
}
