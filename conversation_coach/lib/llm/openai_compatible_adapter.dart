import 'dart:convert';
import 'package:http/http.dart' as http;

import '../data/models/provider_config.dart';
import 'llm_provider.dart';

/// A generic adapter for any provider exposing an OpenAI-style
/// `/chat/completions` endpoint (Tech Spec §5). Because Ollama also exposes an
/// OpenAI-compatible endpoint, the same adapter serves the phase-3 local path —
/// only the base URL and (optional) key differ.
class OpenAICompatibleAdapter implements LLMProvider {
  @override
  final ProviderConfig config;
  final String? apiKey;
  final http.Client _http;

  /// Ollama runs without an API key; Anthropic/OpenAI providers require one.
  final bool isLocal;

  OpenAICompatibleAdapter({
    required this.config,
    required this.apiKey,
    this.isLocal = false,
    http.Client? client,
  }) : _http = client ?? http.Client();

  @override
  String get id => config.id;

  @override
  String get displayName =>
      isLocal ? 'Ollama (local)' : 'OpenAI-compatible';

  @override
  LLMCapabilities get capabilities => LLMCapabilities(
        streaming: true,
        jsonMode: true,
        contextWindow: isLocal ? 8192 : 128000,
        vision: false,
      );

  String get _baseUrl => config.endpointUrl.replaceAll(RegExp(r'/+$'), '');

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        if ((apiKey ?? '').isNotEmpty) 'authorization': 'Bearer $apiKey',
      };

  @override
  Future<List<LLMModel>> listModels() async {
    try {
      final resp =
          await _http.get(Uri.parse('$_baseUrl/models'), headers: _headers);
      if (resp.statusCode == 200) {
        final j = jsonDecode(resp.body) as Map<String, dynamic>;
        final data = (j['data'] as List?) ?? const [];
        return data
            .map((m) => LLMModel(
                  id: (m as Map)['id'] as String,
                  displayName: m['id'] as String,
                ))
            .toList();
      }
    } catch (_) {}
    // Fall back to whatever model the user configured.
    return [LLMModel(id: config.model, displayName: config.model)];
  }

  @override
  Future<ValidationResult> validate() async {
    if (_baseUrl.isEmpty) {
      return const ValidationResult(false, 'Set an endpoint URL first.');
    }
    if (!isLocal && (apiKey ?? '').isEmpty) {
      return const ValidationResult(
          false, 'This provider needs an API key.');
    }
    try {
      final resp = await complete(const PromptRequest(
        system: 'Reply with the single word OK.',
        user: 'ping',
        maxTokens: 16,
        expectJson: false,
      ));
      return ValidationResult(
          true, 'Connected — ${resp.modelUsed} responded.');
    } on LLMException catch (e) {
      return ValidationResult(false, e.message);
    }
  }

  @override
  Future<PromptResponse> complete(PromptRequest request) async {
    final model = request.modelOverride ?? config.model;
    final body = <String, dynamic>{
      'model': model,
      'max_tokens': request.maxTokens,
      'messages': [
        {'role': 'system', 'content': request.system},
        {'role': 'user', 'content': request.user},
      ],
      if (request.expectJson)
        'response_format': {'type': 'json_object'},
    };

    http.Response resp;
    try {
      resp = await _http.post(
        Uri.parse('$_baseUrl/chat/completions'),
        headers: _headers,
        body: jsonEncode(body),
      );
    } catch (e) {
      throw LLMException('Network error: $e');
    }

    if (resp.statusCode != 200) {
      throw LLMException('Provider error (${resp.statusCode}): ${resp.body}',
          statusCode: resp.statusCode);
    }

    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final choices = (j['choices'] as List?) ?? const [];
    final text = choices.isEmpty
        ? ''
        : (((choices.first as Map)['message'] as Map)['content'] as String? ??
            '');
    final usage = (j['usage'] as Map?) ?? const {};
    return PromptResponse(
      text: text.trim(),
      modelUsed: (j['model'] as String?) ?? model,
      usage: TokenUsage(
        inputTokens: (usage['prompt_tokens'] as num?)?.toInt() ?? 0,
        outputTokens: (usage['completion_tokens'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}
