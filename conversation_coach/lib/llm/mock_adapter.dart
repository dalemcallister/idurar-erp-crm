import 'dart:convert';
import 'dart:math';

import '../data/models/provider_config.dart';
import 'llm_provider.dart';

/// An offline provider that synthesises plausible, schema-correct analysis and
/// Q&A output from the transcript embedded in the prompt. It lets the whole
/// app run end-to-end — record → transcribe → analyse → ask — with no API key,
/// which is the demo fallback for the bring-your-own-key model.
///
/// It is deliberately heuristic, not intelligent: it derives summaries and
/// scores from simple text statistics so the UI has real, consistent data to
/// render. Pointing the app at Claude swaps this out with no other changes.
class MockAdapter implements LLMProvider {
  @override
  final ProviderConfig config;
  final _rng = Random(42);

  MockAdapter({required this.config});

  @override
  String get id => config.id;

  @override
  String get displayName => 'Built-in demo (offline)';

  @override
  LLMCapabilities get capabilities =>
      const LLMCapabilities(streaming: false, jsonMode: true);

  @override
  Future<List<LLMModel>> listModels() async =>
      const [LLMModel(id: 'demo-analyst', displayName: 'Demo analyst')];

  @override
  Future<ValidationResult> validate() async =>
      const ValidationResult(true, 'Built-in demo provider is always available.');

  @override
  Future<PromptResponse> complete(PromptRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final transcript = _extractTranscript(request.user);
    final Map<String, dynamic> json;
    switch (request.task) {
      case 'qa':
        json = _qa(request.user, transcript);
        break;
      case 'analysis':
      default:
        json = _analysis(transcript);
    }
    return PromptResponse(
      text: jsonEncode(json),
      modelUsed: 'demo-analyst',
      usage: const TokenUsage(inputTokens: 0, outputTokens: 0),
    );
  }

  // The prompt embeds lines like "[12.0s] (seg-id) Speaker: text".
  List<_Line> _extractTranscript(String prompt) {
    final re = RegExp(r'\[(\d+)\.\ds\]\s*\((seg-[\w-]+)\)\s*([^:]+):\s*(.*)');
    final lines = <_Line>[];
    for (final m in re.allMatches(prompt)) {
      lines.add(_Line(
        sec: int.parse(m.group(1)!),
        segId: m.group(2)!,
        speaker: m.group(3)!.trim(),
        text: m.group(4)!.trim(),
      ));
    }
    return lines;
  }

  Map<String, dynamic> _analysis(List<_Line> lines) {
    if (lines.isEmpty) {
      return {
        'headline':
            'Not enough conversation was captured to analyse this session.',
        'summary': 'The recording was too short or empty to read.',
        'topics': <String>[],
        'decisions': <String>[],
        'actionItems': <String>[],
        'openQuestions': <String>[],
        'strengths': <String>[],
        'improvements': <String>[],
        'scoreOverall': 0,
        'scoreByDimension': <dynamic>[],
        'recommendations': <dynamic>[],
        'emotionArc': <dynamic>[],
      };
    }

    final speakers = lines.map((l) => l.speaker).toSet().toList();
    final words = <String, int>{};
    for (final l in lines) {
      words[l.speaker] = (words[l.speaker] ?? 0) + l.text.split(' ').length;
    }
    final totalWords = words.values.fold<int>(0, (s, v) => s + v);
    final user = speakers.first;
    final userShare =
        totalWords == 0 ? 0.0 : (words[user] ?? 0) / totalWords;

    final questionSegs =
        lines.where((l) => l.text.contains('?')).toList();
    final buyingSegs = lines
        .where((l) => RegExp(r'budget|price|cost|timeline|when can',
                caseSensitive: false)
            .hasMatch(l.text))
        .toList();

    final overall = (55 +
            (questionSegs.length * 4) +
            ((1 - (userShare - 0.5).abs() * 2) * 20))
        .clamp(0, 100)
        .round();

    String ev(List<_Line> src) =>
        src.isEmpty ? '' : src[_rng.nextInt(src.length)].segId;

    return {
      'headline':
          'You ${userShare > 0.6 ? 'led most of the conversation' : 'kept talk-time balanced'} '
              'and asked ${questionSegs.length} question${questionSegs.length == 1 ? '' : 's'}'
              '${buyingSegs.isNotEmpty ? '; the signal around "${_short(buyingSegs.first.text)}" is worth following up' : ''}.',
      'summary':
          'Across ${lines.length} turns with ${speakers.join(' and ')}, the discussion covered '
              '${_topics(lines).take(3).join(', ')}. '
              'You spoke about ${(userShare * 100).round()}% of the time.',
      'topics': _topics(lines),
      'decisions': buyingSegs.isEmpty
          ? <String>[]
          : ['Follow up on ${_short(buyingSegs.first.text)}'],
      'actionItems': [
        if (buyingSegs.isNotEmpty)
          'Send pricing/next-step detail referenced at ${buyingSegs.first.sec}s',
        'Summarise agreed points back to ${speakers.length > 1 ? speakers[1] : 'the other party'}',
      ],
      'openQuestions': questionSegs
          .take(3)
          .map((l) => _short(l.text))
          .toList(),
      'strengths': [
        if (questionSegs.isNotEmpty)
          'Asked clarifying questions (${questionSegs.length} total)',
        if (userShare < 0.6) 'Left room for the other party to speak',
        'Maintained a clear, on-topic thread',
      ].take(3).toList(),
      'improvements': [
        if (userShare > 0.6) 'Reduce talk-time — you spoke most of the session',
        if (buyingSegs.isNotEmpty)
          'Address the buying/timeline signal sooner',
        'Confirm next steps explicitly before closing',
      ].take(3).toList(),
      'scoreOverall': overall,
      'scoreByDimension': _dimensions(userShare, questionSegs, lines, ev),
      'recommendations': _recommendations(
          userShare, questionSegs, buyingSegs, lines, ev),
      'emotionArc': _emotionArc(lines, speakers),
    };
  }

  List<Map<String, dynamic>> _dimensions(double userShare,
      List<_Line> questionSegs, List<_Line> lines, String Function(List<_Line>) ev) {
    final listening = ((1 - userShare) * 100).clamp(0, 100).round();
    final questions = (questionSegs.length * 18).clamp(0, 100);
    return [
      {
        'dimension': 'Listening ratio',
        'score': listening,
        'rationale':
            'You spoke ${(userShare * 100).round()}% of the time; the rest was the other party.',
        'evidenceSegmentIds': [if (lines.isNotEmpty) ev(lines)],
      },
      {
        'dimension': 'Question quality',
        'score': questions,
        'rationale':
            'Asked ${questionSegs.length} question${questionSegs.length == 1 ? '' : 's'} across the session.',
        'evidenceSegmentIds':
            questionSegs.take(2).map((l) => l.segId).toList(),
      },
      {
        'dimension': 'Clarity',
        'score': 72,
        'rationale': 'Turns stayed on-topic and were easy to follow.',
        'evidenceSegmentIds': [if (lines.isNotEmpty) ev(lines)],
      },
      {
        'dimension': 'Call to action',
        'score': 60,
        'rationale': 'Next steps were implied but not always confirmed.',
        'evidenceSegmentIds': [if (lines.isNotEmpty) ev(lines)],
      },
    ];
  }

  List<Map<String, dynamic>> _recommendations(
      double userShare,
      List<_Line> questionSegs,
      List<_Line> buyingSegs,
      List<_Line> lines,
      String Function(List<_Line>) ev) {
    final recs = <Map<String, dynamic>>[];
    if (userShare > 0.55) {
      recs.add({
        'priority': 1,
        'text':
            'You carried ${(userShare * 100).round()}% of the talk time. Pause more and invite the other party to expand.',
        'evidenceRefs': [if (lines.isNotEmpty) ev(lines)],
        'whatToTryInstead':
            'After making a point, ask "How does that land for you?" and wait.',
      });
    }
    if (buyingSegs.isNotEmpty) {
      recs.add({
        'priority': recs.length + 1,
        'text':
            'A buying/timeline signal appeared around ${buyingSegs.first.sec}s and went under-explored.',
        'evidenceRefs': [buyingSegs.first.segId],
        'whatToTryInstead':
            'Acknowledge it directly: "You mentioned ${_short(buyingSegs.first.text)} — shall we map out the next step now?"',
      });
    }
    recs.add({
      'priority': recs.length + 1,
      'text':
          'Close by confirming next steps so both parties leave with the same plan.',
      'evidenceRefs': [if (lines.isNotEmpty) lines.last.segId],
      'whatToTryInstead':
          'End with "So the next step is X by Friday — does that work?"',
    });
    return recs.take(5).toList();
  }

  List<Map<String, dynamic>> _emotionArc(
      List<_Line> lines, List<String> speakers) {
    final arc = <Map<String, dynamic>>[];
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      final positive = RegExp(r'great|thanks|agree|sounds good|perfect|yes',
              caseSensitive: false)
          .hasMatch(l.text);
      final negative = RegExp(r'concern|worried|but|problem|not sure|expensive',
              caseSensitive: false)
          .hasMatch(l.text);
      final valence = positive ? 0.6 : (negative ? -0.5 : 0.05);
      arc.add({
        'speakerId': l.speaker,
        'atMs': l.sec * 1000,
        'valence': valence,
        'energy': (l.text.split(' ').length / 25).clamp(0.1, 1.0),
        'label': positive ? 'positive' : (negative ? 'tense' : 'neutral'),
      });
    }
    return arc;
  }

  Map<String, dynamic> _qa(String prompt, List<_Line> lines) {
    // Pull the question out of the prompt's "Question: ..." marker.
    final qMatch = RegExp(r'Question:\s*(.+)').firstMatch(prompt);
    final question = qMatch?.group(1)?.trim() ?? '';
    final terms = question
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
        .split(' ')
        .where((t) => t.length > 2)
        .toSet();
    final hits = lines
        .where((l) =>
            terms.any((t) => l.text.toLowerCase().contains(t)))
        .take(3)
        .toList();

    if (hits.isEmpty) {
      return {
        'answer':
            "I can't find anything about that in this conversation. It may not have come up.",
        'citations': <dynamic>[],
      };
    }
    return {
      'answer':
          'Based on the conversation: ${hits.map((l) => '"${_short(l.text)}" (${l.speaker})').join('; ')}.',
      'citations': hits
          .map((l) => {
                'segmentId': l.segId,
                'atMs': l.sec * 1000,
                'snippet': _short(l.text),
              })
          .toList(),
    };
  }

  List<String> _topics(List<_Line> lines) {
    final freq = <String, int>{};
    const stop = {
      'the', 'and', 'you', 'that', 'this', 'with', 'for', 'are', 'was',
      'have', 'about', 'what', 'your', 'they', 'but', 'not', 'can', 'will',
      'would', 'just', 'like', 'how', 'our', 'their', 'them', 'has', 'were',
    };
    for (final l in lines) {
      for (final w in l.text.toLowerCase().split(RegExp(r'[^a-z]+'))) {
        if (w.length > 3 && !stop.contains(w)) {
          freq[w] = (freq[w] ?? 0) + 1;
        }
      }
    }
    final sorted = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(5).map((e) => e.key).toList();
  }

  String _short(String s) => s.length <= 60 ? s : '${s.substring(0, 57)}…';
}

class _Line {
  final int sec;
  final String segId;
  final String speaker;
  final String text;
  _Line({
    required this.sec,
    required this.segId,
    required this.speaker,
    required this.text,
  });
}
