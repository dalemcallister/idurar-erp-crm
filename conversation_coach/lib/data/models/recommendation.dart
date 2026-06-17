import 'dart:convert';

/// Recommendation(id, sessionId, priority, text, evidenceRefs[segmentIds]) — §7.
///
/// F-REC-01: 3–5 specific, prioritised, constructive recommendations tied to
/// evidence and the goal. F-REC-02: an optional "what to try instead"
/// rephrasing for a specific moment.
class Recommendation {
  final String id;
  final String sessionId;

  /// 1 = highest priority.
  final int priority;
  final String text;

  /// Segment ids backing the recommendation (timestamp + quoted snippet).
  final List<String> evidenceRefs;

  /// F-REC-02 — concrete rephrasing the user could have said instead.
  final String? whatToTryInstead;

  const Recommendation({
    required this.id,
    required this.sessionId,
    required this.priority,
    required this.text,
    this.evidenceRefs = const [],
    this.whatToTryInstead,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'sessionId': sessionId,
        'priority': priority,
        'text': text,
        'evidenceRefs': jsonEncode(evidenceRefs),
        'whatToTryInstead': whatToTryInstead,
      };

  factory Recommendation.fromMap(Map<String, dynamic> m) => Recommendation(
        id: m['id'] as String,
        sessionId: m['sessionId'] as String,
        priority: m['priority'] as int,
        text: m['text'] as String,
        evidenceRefs: ((jsonDecode((m['evidenceRefs'] as String?) ?? '[]'))
                as List)
            .map((e) => e.toString())
            .toList(),
        whatToTryInstead: m['whatToTryInstead'] as String?,
      );
}
