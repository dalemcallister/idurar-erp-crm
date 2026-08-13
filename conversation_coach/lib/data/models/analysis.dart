import 'dart:convert';

/// A single scored rubric dimension with its supporting evidence (F-ANA-05/06).
class DimensionScore {
  final String dimension;
  final double score; // 0..100
  final String rationale;

  /// Segment ids that back the score — every claim cites evidence (F-ANA-06).
  final List<String> evidenceSegmentIds;

  const DimensionScore({
    required this.dimension,
    required this.score,
    required this.rationale,
    this.evidenceSegmentIds = const [],
  });

  Map<String, dynamic> toJson() => {
        'dimension': dimension,
        'score': score,
        'rationale': rationale,
        'evidenceSegmentIds': evidenceSegmentIds,
      };

  factory DimensionScore.fromJson(Map<String, dynamic> j) => DimensionScore(
        dimension: j['dimension'] as String,
        score: (j['score'] as num).toDouble(),
        rationale: (j['rationale'] as String?) ?? '',
        evidenceSegmentIds: ((j['evidenceSegmentIds'] as List?) ?? [])
            .map((e) => e.toString())
            .toList(),
      );
}

/// One point on a speaker's emotional arc across the session (F-ANA-03).
class EmotionPoint {
  final String speakerId;
  final int atMs;
  final double valence; // -1 (negative) .. 1 (positive)
  final double energy; // 0 .. 1
  final String label;

  const EmotionPoint({
    required this.speakerId,
    required this.atMs,
    required this.valence,
    required this.energy,
    required this.label,
  });

  Map<String, dynamic> toJson() => {
        'speakerId': speakerId,
        'atMs': atMs,
        'valence': valence,
        'energy': energy,
        'label': label,
      };

  factory EmotionPoint.fromJson(Map<String, dynamic> j) => EmotionPoint(
        speakerId: j['speakerId'] as String,
        atMs: j['atMs'] as int,
        valence: (j['valence'] as num).toDouble(),
        energy: (j['energy'] as num).toDouble(),
        label: (j['label'] as String?) ?? '',
      );
}

/// Conversation dynamics — F-ANA-04. Computed from timestamps + signal stats
/// and surfaced on the emotion & dynamics timeline.
class Dynamics {
  /// speakerId -> share of talk time (0..1).
  final Map<String, double> talkTimeRatio;
  final int interruptions;
  final int longestMonologueMs;
  final int questionCount;
  final double fillerWordRate; // per 100 words
  final double avgResponseLatencyMs;

  const Dynamics({
    this.talkTimeRatio = const {},
    this.interruptions = 0,
    this.longestMonologueMs = 0,
    this.questionCount = 0,
    this.fillerWordRate = 0,
    this.avgResponseLatencyMs = 0,
  });

  Map<String, dynamic> toJson() => {
        'talkTimeRatio': talkTimeRatio,
        'interruptions': interruptions,
        'longestMonologueMs': longestMonologueMs,
        'questionCount': questionCount,
        'fillerWordRate': fillerWordRate,
        'avgResponseLatencyMs': avgResponseLatencyMs,
      };

  factory Dynamics.fromJson(Map<String, dynamic> j) => Dynamics(
        talkTimeRatio: ((j['talkTimeRatio'] as Map?) ?? {})
            .map((k, v) => MapEntry(k.toString(), (v as num).toDouble())),
        interruptions: (j['interruptions'] as num?)?.toInt() ?? 0,
        longestMonologueMs: (j['longestMonologueMs'] as num?)?.toInt() ?? 0,
        questionCount: (j['questionCount'] as num?)?.toInt() ?? 0,
        fillerWordRate: (j['fillerWordRate'] as num?)?.toDouble() ?? 0,
        avgResponseLatencyMs:
            (j['avgResponseLatencyMs'] as num?)?.toDouble() ?? 0,
      );
}

/// Analysis(id, sessionId, summary, topicsJson, actionItemsJson, dynamicsJson,
///          scoreOverall, scoreByDimensionJson, emotionArcJson,
///          modelUsed, promptVersion, createdAt) — Tech Spec §7.
class Analysis {
  final String id;
  final String sessionId;

  /// 2–3 sentence headline that opens the session detail (Design §6.3).
  final String headline;
  final String summary;
  final List<String> topics;
  final List<String> decisions;
  final List<String> actionItems;
  final List<String> openQuestions;
  final List<String> strengths;
  final List<String> improvements;

  /// Concrete, personal follow-up actions for the user after this conversation
  /// (owner = the user) — the basis of the "Your next steps" card and the
  /// follow-up email.
  final List<String> nextSteps;
  final Dynamics dynamics;
  final double scoreOverall; // 0..100
  final List<DimensionScore> scoreByDimension;
  final List<EmotionPoint> emotionArc;
  final String modelUsed;
  final String promptVersion;
  final DateTime createdAt;

  /// Token accounting for the per-session cost meter (F-MOD-06). Zero for the
  /// offline demo provider; real counts when a cloud model is used.
  final int inputTokens;
  final int outputTokens;

  const Analysis({
    required this.id,
    required this.sessionId,
    required this.headline,
    required this.summary,
    this.topics = const [],
    this.decisions = const [],
    this.actionItems = const [],
    this.openQuestions = const [],
    this.strengths = const [],
    this.improvements = const [],
    this.nextSteps = const [],
    this.dynamics = const Dynamics(),
    required this.scoreOverall,
    this.scoreByDimension = const [],
    this.emotionArc = const [],
    required this.modelUsed,
    required this.promptVersion,
    required this.createdAt,
    this.inputTokens = 0,
    this.outputTokens = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'sessionId': sessionId,
        'headline': headline,
        'summary': summary,
        'topicsJson': jsonEncode(topics),
        'decisionsJson': jsonEncode(decisions),
        'actionItemsJson': jsonEncode(actionItems),
        'openQuestionsJson': jsonEncode(openQuestions),
        'strengthsJson': jsonEncode(strengths),
        'improvementsJson': jsonEncode(improvements),
        'nextStepsJson': jsonEncode(nextSteps),
        'dynamicsJson': jsonEncode(dynamics.toJson()),
        'scoreOverall': scoreOverall,
        'scoreByDimensionJson':
            jsonEncode(scoreByDimension.map((d) => d.toJson()).toList()),
        'emotionArcJson':
            jsonEncode(emotionArc.map((e) => e.toJson()).toList()),
        'modelUsed': modelUsed,
        'promptVersion': promptVersion,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
      };

  factory Analysis.fromMap(Map<String, dynamic> m) {
    List<String> strs(String key) =>
        ((jsonDecode((m[key] as String?) ?? '[]')) as List)
            .map((e) => e.toString())
            .toList();
    return Analysis(
      id: m['id'] as String,
      sessionId: m['sessionId'] as String,
      headline: (m['headline'] as String?) ?? '',
      summary: (m['summary'] as String?) ?? '',
      topics: strs('topicsJson'),
      decisions: strs('decisionsJson'),
      actionItems: strs('actionItemsJson'),
      openQuestions: strs('openQuestionsJson'),
      strengths: strs('strengthsJson'),
      improvements: strs('improvementsJson'),
      nextSteps: strs('nextStepsJson'),
      dynamics: Dynamics.fromJson(
          jsonDecode((m['dynamicsJson'] as String?) ?? '{}')
              as Map<String, dynamic>),
      scoreOverall: (m['scoreOverall'] as num).toDouble(),
      scoreByDimension:
          ((jsonDecode((m['scoreByDimensionJson'] as String?) ?? '[]')) as List)
              .map((e) => DimensionScore.fromJson(e as Map<String, dynamic>))
              .toList(),
      emotionArc:
          ((jsonDecode((m['emotionArcJson'] as String?) ?? '[]')) as List)
              .map((e) => EmotionPoint.fromJson(e as Map<String, dynamic>))
              .toList(),
      modelUsed: (m['modelUsed'] as String?) ?? '',
      promptVersion: (m['promptVersion'] as String?) ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
      inputTokens: (m['inputTokens'] as int?) ?? 0,
      outputTokens: (m['outputTokens'] as int?) ?? 0,
    );
  }
}
