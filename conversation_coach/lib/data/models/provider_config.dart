import 'dart:convert';

/// The kind of provider adapter backing a [ProviderConfig].
enum ProviderKind { anthropic, openaiCompatible, ollama, mock }

extension ProviderKindX on ProviderKind {
  String get displayName {
    switch (this) {
      case ProviderKind.anthropic:
        return 'Anthropic (Claude)';
      case ProviderKind.openaiCompatible:
        return 'OpenAI-compatible';
      case ProviderKind.ollama:
        return 'Ollama (local)';
      case ProviderKind.mock:
        return 'Built-in demo (offline)';
    }
  }
}

/// ProviderConfig(id, provider, model, endpointUrl, apiKeyRef, paramsJson,
///                perTaskOverridesJson) — Tech Spec §7 / §5.
///
/// The API key is never stored here in plaintext — [apiKeyRef] is a handle into
/// the OS keystore (F-MOD-03). [perTaskOverrides] lets a cheaper model do
/// transcript cleanup while a stronger one does analysis (F-MOD-04).
class ProviderConfig {
  final String id;
  final ProviderKind provider;
  final String model;

  /// Base URL — required for OpenAI-compatible and Ollama; defaulted for
  /// Anthropic.
  final String endpointUrl;

  /// Keystore handle (not the key itself).
  final String? apiKeyRef;

  final Map<String, dynamic> params;

  /// task name -> model id, e.g. {"cleanup": "claude-haiku-4-5"}.
  final Map<String, String> perTaskOverrides;

  const ProviderConfig({
    required this.id,
    required this.provider,
    required this.model,
    required this.endpointUrl,
    this.apiKeyRef,
    this.params = const {},
    this.perTaskOverrides = const {},
  });

  /// F-MOD-01 — the default provider is Claude.
  factory ProviderConfig.defaultClaude() => const ProviderConfig(
        id: 'claude-default',
        provider: ProviderKind.anthropic,
        model: 'claude-opus-4-8',
        endpointUrl: 'https://api.anthropic.com',
        apiKeyRef: 'anthropic_api_key',
      );

  /// Offline demo provider — lets the app run end-to-end without a key
  /// (bring-your-own-key, with a usable fallback).
  factory ProviderConfig.mock() => const ProviderConfig(
        id: 'mock',
        provider: ProviderKind.mock,
        model: 'demo-analyst',
        endpointUrl: '',
      );

  String label() => '${provider.displayName} · $model';

  ProviderConfig copyWith({
    ProviderKind? provider,
    String? model,
    String? endpointUrl,
    String? apiKeyRef,
    Map<String, dynamic>? params,
    Map<String, String>? perTaskOverrides,
  }) =>
      ProviderConfig(
        id: id,
        provider: provider ?? this.provider,
        model: model ?? this.model,
        endpointUrl: endpointUrl ?? this.endpointUrl,
        apiKeyRef: apiKeyRef ?? this.apiKeyRef,
        params: params ?? this.params,
        perTaskOverrides: perTaskOverrides ?? this.perTaskOverrides,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'provider': provider.name,
        'model': model,
        'endpointUrl': endpointUrl,
        'apiKeyRef': apiKeyRef,
        'paramsJson': jsonEncode(params),
        'perTaskOverridesJson': jsonEncode(perTaskOverrides),
      };

  factory ProviderConfig.fromMap(Map<String, dynamic> m) => ProviderConfig(
        id: m['id'] as String,
        provider: ProviderKind.values.firstWhere(
            (p) => p.name == m['provider'],
            orElse: () => ProviderKind.anthropic),
        model: m['model'] as String,
        endpointUrl: (m['endpointUrl'] as String?) ?? '',
        apiKeyRef: m['apiKeyRef'] as String?,
        params: jsonDecode((m['paramsJson'] as String?) ?? '{}')
            as Map<String, dynamic>,
        perTaskOverrides:
            (jsonDecode((m['perTaskOverridesJson'] as String?) ?? '{}')
                    as Map<String, dynamic>)
                .map((k, v) => MapEntry(k, v.toString())),
      );
}
