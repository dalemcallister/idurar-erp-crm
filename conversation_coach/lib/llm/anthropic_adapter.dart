import 'dart:convert';
import 'package:http/http.dart' as http;

import '../data/models/provider_config.dart';
import 'llm_provider.dart';

/// AnthropicAdapter — the default provider (Claude). Tech Spec §5.
///
/// Dart has no official Anthropic SDK, so this calls the Messages API over
/// raw HTTP. The default model is `claude-opus-4-8`; the key is supplied at
/// runtime from the OS keystore (bring-your-own-key).
class AnthropicAdapter implements LLMProvider {
  static const String anthropicVersion = '2023-06-01';
  static const String defaultModel = 'claude-opus-4-8';

  @override
  final ProviderConfig config;

  /// Resolved at runtime from the keystore — never persisted in plaintext.
  final String? apiKey;

  final http.Client _http;

  AnthropicAdapter({
    required this.config,
    required this.apiKey,
    http.Client? client,
  }) : _http = client ?? http.Client();

  @override
  String get id => config.id;

  @override
  String get displayName => 'Anthropic (Claude)';

  @override
  LLMCapabilities get capabilities => const LLMCapabilities(
        streaming: true,
        jsonMode: true,
        contextWindow: 1000000,
        vision: true,
      );

  String get _baseUrl => config.endpointUrl.isEmpty
      ? 'https://api.anthropic.com'
      : config.endpointUrl;

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        'x-api-key': apiKey ?? '',
        'anthropic-version': anthropicVersion,
      };

  @override
  Future<List<LLMModel>> listModels() async {
    // A pinned, current shortlist (Models API discovery could replace this).
    return const [
      LLMModel(
          id: 'claude-opus-4-8',
          displayName: 'Claude Opus 4.8',
          contextWindow: 1000000),
      LLMModel(
          id: 'claude-sonnet-4-6',
          displayName: 'Claude Sonnet 4.6',
          contextWindow: 1000000),
      LLMModel(
          id: 'claude-haiku-4-5',
          displayName: 'Claude Haiku 4.5',
          contextWindow: 200000),
    ];
  }

  @override
  Future<ValidationResult> validate() async {
    if ((apiKey ?? '').isEmpty) {
      return const ValidationResult(
          false, 'No API key set. Add your Anthropic key in Settings.');
    }
    try {
      final resp = await complete(const PromptRequest(
        system: 'You are a connection tester. Reply with the single word OK.',
        user: 'ping',
        maxTokens: 16,
        expectJson: false,
      ));
      if (resp.text.toUpperCase().contains('OK')) {
        return ValidationResult(true, 'Connected — ${config.model} responded.');
      }
      return ValidationResult(true, 'Connected — model responded.');
    } on LLMException catch (e) {
      return ValidationResult(false, e.message);
    }
  }

  @override
  Future<PromptResponse> complete(PromptRequest request) async {
    final model =
        request.modelOverride ?? (config.model.isEmpty ? defaultModel : config.model);

    // Strict JSON is requested via a clear system instruction; the adapter
    // does not send sampling params (removed on Opus 4.8) — see prompt registry.
    final system = request.expectJson
        ? '${request.system}\n\nRespond with a single valid JSON object and nothing else. Do not wrap it in markdown fences.'
        : request.system;

    final body = <String, dynamic>{
      'model': model,
      'max_tokens': request.maxTokens,
      'system': system,
      'messages': [
        {'role': 'user', 'content': request.user},
      ],
    };

    http.Response resp;
    try {
      resp = await _http.post(
        Uri.parse('$_baseUrl/v1/messages'),
        headers: _headers,
        body: jsonEncode(body),
      );
    } catch (e) {
      throw LLMException('Network error calling Claude: $e');
    }

    if (resp.statusCode != 200) {
      throw LLMException(
        _errorMessage(resp),
        statusCode: resp.statusCode,
      );
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final content = (decoded['content'] as List?) ?? const [];
    final text = content
        .where((b) => (b as Map)['type'] == 'text')
        .map((b) => (b as Map)['text'] as String)
        .join('\n')
        .trim();

    final usage = (decoded['usage'] as Map?) ?? const {};
    return PromptResponse(
      text: text,
      modelUsed: (decoded['model'] as String?) ?? model,
      usage: TokenUsage(
        inputTokens: (usage['input_tokens'] as num?)?.toInt() ?? 0,
        outputTokens: (usage['output_tokens'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  String _errorMessage(http.Response resp) {
    try {
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      final err = j['error'];
      if (err is Map && err['message'] != null) {
        return 'Claude API ${resp.statusCode}: ${err['message']}';
      }
    } catch (_) {}
    if (resp.statusCode == 401) return 'Invalid API key (401).';
    if (resp.statusCode == 429) return 'Rate limited (429) — try again shortly.';
    return 'Claude API error (${resp.statusCode}).';
  }
}
