import '../data/models/goal.dart';
import '../data/models/segment.dart';
import '../data/models/speaker.dart';
import '../data/models/session.dart';
import 'llm_provider.dart';

/// Prompt registry — every analysis function is a versioned prompt template
/// with a strict expected output schema, so results stay consistent across
/// very different models (Tech Spec §5).
class PromptRegistry {
  static const String version = 'v1';

  /// Renders the transcript in a stable, parseable form. Each line carries its
  /// timestamp and segment id so the model can cite evidence by id, and the
  /// offline mock can parse it back out.
  static String renderTranscript(
      List<Segment> segments, Map<String, Speaker> speakers) {
    final b = StringBuffer();
    for (final s in segments) {
      final sp = speakers[s.speakerId]?.label ?? 'Speaker';
      final sec = (s.startMs / 1000).toStringAsFixed(1);
      b.writeln('[${sec}s] (${s.id}) $sp: ${s.text}');
    }
    return b.toString();
  }

  /// The core analysis prompt (summary, content, intent, emotion, dynamics,
  /// goal score, recommendations) — F-ANA-01..06, F-REC-01/02.
  static PromptRequest analysis({
    required Session session,
    required Goal goal,
    required Rubric rubric,
    required List<Segment> segments,
    required Map<String, Speaker> speakers,
    String? modelOverride,
  }) {
    final transcript = renderTranscript(segments, speakers);
    final dims = rubric.dimensions
        .map((d) => '- ${d.name} (weight ${d.weight}): ${d.description}')
        .join('\n');

    final system = '''
You are an expert communication coach. You analyse a single recorded
conversation strictly relative to the user's stated goal. You are constructive
and specific, never a cold grade. Every analytical claim must cite evidence by
referencing the segment id(s) it relies on — never invent content that is not in
the transcript.

The user is "${speakers.values.firstWhere((s) => s.isUser, orElse: () => speakers.values.first).label}".

Goal: ${goal.name} — ${goal.description}
Context the user added: ${session.context.isEmpty ? '(none)' : session.context}

Score the conversation against this rubric (0–100 per dimension):
$dims

Return JSON with exactly these keys:
{
  "headline": string (2-3 sentences, the story of the call),
  "summary": string,
  "topics": string[],
  "decisions": string[],
  "actionItems": string[],
  "openQuestions": string[],
  "strengths": string[] (top 3),
  "improvements": string[] (top 3),
  "scoreOverall": number (0-100),
  "scoreByDimension": [ { "dimension": string, "score": number, "rationale": string, "evidenceSegmentIds": string[] } ],
  "recommendations": [ { "priority": number, "text": string, "evidenceRefs": string[], "whatToTryInstead": string|null } ],
  "emotionArc": [ { "speakerId": string, "atMs": number, "valence": number (-1..1), "energy": number (0..1), "label": string } ]
}
Provide 3 to 5 recommendations, prioritised (1 = highest), each tied to evidence
and the goal. Use the speaker labels as written for speakerId.''';

    final user = 'Transcript:\n$transcript';

    return PromptRequest(
      system: system,
      user: user,
      maxTokens: 4096,
      expectJson: true,
      modelOverride: modelOverride,
      task: 'analysis',
    );
  }

  /// Per-session Q&A grounded in retrieved segments (F-QA-01/02/04).
  static PromptRequest qa({
    required String question,
    required List<Segment> retrieved,
    required Map<String, Speaker> speakers,
    String? modelOverride,
  }) {
    final context = renderTranscript(retrieved, speakers);
    final system = '''
You answer questions about ONE recorded conversation, using only the provided
excerpts. Cite the timestamps/segment ids you rely on. If the answer is not
present in the excerpts, say so plainly — never fabricate.

Return JSON:
{
  "answer": string,
  "citations": [ { "segmentId": string, "atMs": number, "snippet": string } ]
}''';
    final user = 'Relevant excerpts:\n$context\n\nQuestion: $question';
    return PromptRequest(
      system: system,
      user: user,
      maxTokens: 1024,
      expectJson: true,
      modelOverride: modelOverride,
      task: 'qa',
    );
  }
}
