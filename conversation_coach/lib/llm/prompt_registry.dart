import '../data/models/goal.dart';
import '../data/models/segment.dart';
import '../data/models/speaker.dart';
import '../data/models/session.dart';
import 'llm_provider.dart';

/// Prompt registry — every analysis function is a versioned prompt template
/// with a strict expected output schema, so results stay consistent across
/// very different models (Tech Spec §5).
class PromptRegistry {
  static const String version = 'v2';

  /// Renders the transcript in a stable, parseable form. Each line carries its
  /// timestamp and (optionally) segment id so the model can cite evidence by id,
  /// and the offline mock can parse it back out.
  ///
  /// [withIds] controls whether the segment id is included. The cloud prompt
  /// cites evidence by id so it needs them, but the segment ids are UUIDs
  /// (~50 chars/line) — on a small on-device window that overhead alone can
  /// double the token count, and the compact on-device prompts don't cite ids,
  /// so they render with `withIds: false`.
  static String renderTranscript(
      List<Segment> segments, Map<String, Speaker> speakers,
      {bool withIds = true}) {
    final b = StringBuffer();
    for (final s in segments) {
      final sp = speakers[s.speakerId]?.label ?? 'Speaker';
      final sec = (s.startMs / 1000).toStringAsFixed(1);
      if (withIds) {
        b.writeln('[${sec}s] (${s.id}) $sp: ${s.text}');
      } else {
        b.writeln('[${sec}s] $sp: ${s.text}');
      }
    }
    return b.toString();
  }

  /// The user's speaker label (the person being coached), or a fallback.
  static String _userLabel(Map<String, Speaker> speakers) =>
      speakers.values.isEmpty
          ? 'the user'
          : speakers.values
              .firstWhere((s) => s.isUser, orElse: () => speakers.values.first)
              .label;

  /// The core analysis prompt (summary, content, intent, emotion, dynamics,
  /// goal score, recommendations) — F-ANA-01..06, F-REC-01/02.
  static PromptRequest analysis({
    required Session session,
    required Goal goal,
    required Rubric rubric,
    required List<Segment> segments,
    required Map<String, Speaker> speakers,
    String? modelOverride,
    bool simple = false,
    List<String>? digests,
  }) {
    // Local prompts render without the UUID segment ids (they don't cite them,
    // and the ids blow the small context window); the cloud prompt keeps them.
    final transcript = renderTranscript(segments, speakers, withIds: !simple);
    final dims = rubric.dimensions
        .map((d) => '- ${d.name} (weight ${d.weight}): ${d.description}')
        .join('\n');

    final userLabel = _userLabel(speakers);

    // A compact, strict prompt for small on-device models: fewer fields, no
    // evidence ids (which sent the 1B model into repetition loops), and
    // explicit rules to keep the JSON valid.
    if (simple) {
      final dimNames = rubric.dimensions.map((d) => d.name).join(', ');
      final simpleSystem = '''
You are an expert communication coach. Analyse ONE conversation for "$userLabel"
against the goal and rubric. Be specific, concrete and constructive — refer to
what was actually said, not generic advice.

Goal: ${goal.name} — ${goal.description}
${session.context.isEmpty ? '' : 'Context: ${session.context}'}
Rubric dimensions (score EACH 0-100), use these EXACT names: $dimNames

Content rules:
- Ground every point in THIS conversation. Do not give generic filler.
- strengths and improvements must be DIFFERENT from each other; never repeat a
  point across fields.
- Give 3-4 recommendations, most important first, each with a concrete
  "whatToTryInstead" (a specific phrase or move the user could use next time).
- Score every rubric dimension listed above, using its exact name.

Output rules — output ONLY one valid JSON object, nothing before or after it:
- Put a comma after every field and every array item except the last one.
- Use double quotes for all keys and string values.
- Do NOT repeat words or characters. No markdown, no code fences, no comments.

JSON shape:
{
  "headline": "one vivid sentence — the story of the conversation",
  "summary": "three or four sentences: what happened and how it went vs the goal",
  "topics": ["main topic", "main topic"],
  "openQuestions": ["a question left unresolved", "another"],
  "strengths": ["specific thing done well", "another", "another"],
  "improvements": ["specific thing to improve", "another", "another"],
  "nextSteps": ["a concrete action for the user afterwards", "another", "another"],
  "recommendations": [
    {"priority": 1, "text": "the recommendation", "whatToTryInstead": "a specific phrase or move to try"}
  ],
  "scoreOverall": 75,
  "scoreByDimension": [ {"dimension": "exact name", "score": 75, "rationale": "short reason"} ]
}''';
      // For a long meeting the orchestrator map-reduces: it digests the
      // transcript in windowed chunks, then calls this with those `digests`
      // instead of the raw transcript. Same JSON shape either way.
      final String userText;
      if (digests != null && digests.isNotEmpty) {
        final b = StringBuffer(
            'This is a long conversation, summarised in time order as section '
            'digests below. Treat them together as the full transcript and '
            'analyse the WHOLE conversation from them.\n');
        for (var i = 0; i < digests.length; i++) {
          b.writeln('\n--- Part ${i + 1} of ${digests.length} ---');
          b.writeln(digests[i].trim());
        }
        userText = b.toString();
      } else {
        userText = 'Transcript:\n$transcript';
      }
      return PromptRequest(
        system: simpleSystem,
        user: userText,
        // Output cap (not context): the structured JSON fits comfortably, and a
        // smaller cap leaves more of the 4096 window for the input.
        maxTokens: 1024,
        expectJson: true,
        modelOverride: modelOverride,
        task: 'analysis',
      );
    }

    final system = '''
You are an expert communication coach. You analyse a single recorded
conversation strictly relative to the user's stated goal. You are constructive
and specific, never a cold grade. Every analytical claim must cite evidence by
referencing the segment id(s) it relies on — never invent content that is not in
the transcript.

The user is "$userLabel".

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
  "nextSteps": string[] (3-6 concrete follow-up actions the user should take AFTER this conversation to move the goal forward — written to the user in the imperative, specific and self-contained, time-bound where the transcript supports it, e.g. "Email $userLabel a one-page recap of the agreed scope by Friday"),
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

  /// MAP step of on-device map-reduce: summarise ONE windowed chunk of a long
  /// transcript into a compact, plain-text digest. The [analysis] REDUCE step
  /// then works from these digests instead of the raw transcript, so a long
  /// meeting is analysed with full coverage without overflowing the small
  /// on-device context window. Digests are also the per-session raw material the
  /// communication-persona feature will reuse (PROJECT.md roadmap #5).
  static PromptRequest digestChunk({
    required Session session,
    required Goal goal,
    required Rubric rubric,
    required List<Segment> segments,
    required Map<String, Speaker> speakers,
    required int partIndex,
    required int partCount,
    String? modelOverride,
  }) {
    final transcript = renderTranscript(segments, speakers, withIds: false);
    final userLabel = _userLabel(speakers);
    final system = '''
You are a communication coach reading PART $partIndex of $partCount of ONE
recorded conversation. Summarise ONLY this part into a compact digest that a
later step will use to coach "$userLabel" on the whole conversation.

Goal of the conversation: ${goal.name} — ${goal.description}
${session.context.isEmpty ? '' : 'Context: ${session.context}'}

From THIS part only, grounded in what was actually said, capture:
- the main topics and points discussed
- specific things "$userLabel" said or did, and how (tone, clarity, questions asked)
- notable moments — briefly paraphrase a telling quote or two
- any decisions, agreements, objections, or questions left open
- anything relevant to the goal above

Rules: 6-12 short bullet lines, each starting with "-". Be concrete and specific
to this part. No headings, no preamble, no JSON — only the bullet lines. Never
invent anything that is not in this part.''';
    return PromptRequest(
      system: system,
      user: 'Transcript (part $partIndex of $partCount):\n$transcript',
      maxTokens: 512,
      expectJson: false,
      modelOverride: modelOverride,
      task: 'digest',
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
