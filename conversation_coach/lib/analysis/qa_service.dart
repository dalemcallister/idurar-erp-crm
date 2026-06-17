import 'dart:convert';
import 'dart:math';

import 'package:uuid/uuid.dart';

import '../data/models/provider_config.dart';
import '../data/models/qa.dart';
import '../data/models/segment.dart';
import '../data/models/speaker.dart';
import '../data/repository.dart';
import '../llm/llm_provider.dart';
import '../llm/prompt_registry.dart';
import '../llm/provider_registry.dart';

/// Per-session, retrieval-augmented Q&A (Tech Spec §6.4 / F-QA-01/02/04).
///
/// On finalisation the transcript is stored with a lightweight lexical
/// embedding per segment. A question retrieves the most relevant segments,
/// which are passed to the model with an instruction to answer only from that
/// context and to cite timestamps — and to say plainly when the answer is not
/// present.
class QAService {
  final Repository repo;
  final ProviderRegistry providers;
  final _uuid = const Uuid();

  QAService({required this.repo, required this.providers});

  static const _stop = {
    'the', 'and', 'you', 'that', 'this', 'with', 'for', 'are', 'was', 'have',
    'about', 'what', 'your', 'they', 'but', 'not', 'can', 'will', 'would',
    'just', 'did', 'does', 'how', 'why', 'who', 'where', 'when', 'a', 'an',
    'of', 'to', 'in', 'is', 'it', 'on', 'i', 'we', 'me', 'my',
  };

  /// A sparse term-frequency vector used as a cheap on-device embedding. A real
  /// build would use an SQLite vector extension (Tech Spec §6.4); this keeps the
  /// retrieval fully local with no external dependency.
  static Map<String, double> embed(String text) {
    final terms = _tokenize(text);
    if (terms.isEmpty) return {};
    final counts = <String, double>{};
    for (final t in terms) {
      counts[t] = (counts[t] ?? 0) + 1;
    }
    // L2-normalise.
    final norm = sqrt(counts.values.fold<double>(0, (s, v) => s + v * v));
    if (norm == 0) return counts;
    return counts.map((k, v) => MapEntry(k, v / norm));
  }

  static List<String> _tokenize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .split(RegExp(r'\s+'))
      .where((t) => t.length > 2 && !_stop.contains(t))
      .toList();

  static double _cosine(Map<String, double> a, Map<String, double> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final smaller = a.length <= b.length ? a : b;
    final larger = a.length <= b.length ? b : a;
    double dot = 0;
    smaller.forEach((k, v) {
      final o = larger[k];
      if (o != null) dot += v * o;
    });
    return dot;
  }

  /// Retrieves the top-k most relevant segments for [question]. Static because
  /// it depends only on its inputs (no repo/provider state), which also makes
  /// it directly unit-testable.
  static List<Segment> retrieve(String question, List<Segment> segments,
      {int k = 6}) {
    final q = embed(question);
    final scored = <MapEntry<Segment, double>>[];
    for (final s in segments) {
      final emb = s.embedding ?? embed(s.text);
      scored.add(MapEntry(s, _cosine(q, emb)));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    final top = scored.where((e) => e.value > 0).take(k).map((e) => e.key).toList();
    // Keep chronological order for the model.
    top.sort((a, b) => a.startMs.compareTo(b.startMs));
    return top;
  }

  /// Answers a question and persists both the user message and the grounded
  /// reply to the session's Q&A thread.
  Future<QAMessage> ask({
    required String sessionId,
    required String question,
    required ProviderConfig providerConfig,
  }) async {
    final thread = await repo.threadForSession(sessionId);
    await repo.addQAMessage(QAMessage(
      id: 'qm-${_uuid.v4()}',
      threadId: thread.id,
      role: QARole.user,
      text: question,
      createdAt: DateTime.now(),
    ));

    final segments = await repo.segments(sessionId);
    final speakers = await repo.speakerMap(sessionId);
    final retrieved = QAService.retrieve(question, segments);

    final provider = await providers.resolveForAnalysis(providerConfig);
    final request = PromptRegistry.qa(
      question: question,
      retrieved: retrieved,
      speakers: speakers,
      modelOverride: providerConfig.perTaskOverrides['qa'],
    );

    String answer;
    List<Citation> citations;
    try {
      final resp = await provider.complete(request);
      final parsed = _parse(resp.text);
      answer = (parsed['answer'] as String?) ??
          "I couldn't find an answer in this conversation.";
      citations = ((parsed['citations'] as List?) ?? const [])
          .map((c) => Citation.fromJson(c as Map<String, dynamic>))
          .toList();
    } on LLMException catch (e) {
      answer = 'Sorry — I could not reach the model: ${e.message}';
      citations = const [];
    }

    final reply = QAMessage(
      id: 'qm-${_uuid.v4()}',
      threadId: thread.id,
      role: QARole.assistant,
      text: answer,
      citations: citations,
      createdAt: DateTime.now(),
    );
    await repo.addQAMessage(reply);
    return reply;
  }

  Future<List<QAMessage>> history(String sessionId) async {
    final thread = await repo.threadForSession(sessionId);
    return repo.qaMessages(thread.id);
  }

  Map<String, dynamic> _parse(String text) {
    try {
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start >= 0 && end > start) {
        try {
          return jsonDecode(text.substring(start, end + 1))
              as Map<String, dynamic>;
        } catch (_) {}
      }
      return {'answer': text, 'citations': const <dynamic>[]};
    }
  }
}
