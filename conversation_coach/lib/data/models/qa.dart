import 'dart:convert';

/// A timestamp citation attached to a Q&A answer (F-QA-02). The user can tap it
/// to replay the cited audio segment.
class Citation {
  final String segmentId;
  final int atMs;
  final String snippet;

  const Citation({
    required this.segmentId,
    required this.atMs,
    required this.snippet,
  });

  Map<String, dynamic> toJson() => {
        'segmentId': segmentId,
        'atMs': atMs,
        'snippet': snippet,
      };

  factory Citation.fromJson(Map<String, dynamic> j) => Citation(
        segmentId: (j['segmentId'] as String?) ?? '',
        atMs: (j['atMs'] as num?)?.toInt() ?? 0,
        snippet: (j['snippet'] as String?) ?? '',
      );

  String timestampLabel() {
    final s = atMs ~/ 1000;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}

/// QAThread(id, sessionId) — Tech Spec §7. One per-session Q&A conversation.
class QAThread {
  final String id;
  final String sessionId;

  const QAThread({required this.id, required this.sessionId});

  Map<String, dynamic> toMap() => {'id': id, 'sessionId': sessionId};

  factory QAThread.fromMap(Map<String, dynamic> m) =>
      QAThread(id: m['id'] as String, sessionId: m['sessionId'] as String);
}

enum QARole { user, assistant }

/// QAMessage(id, threadId, role, text, citationsJson) — Tech Spec §7.
class QAMessage {
  final String id;
  final String threadId;
  final QARole role;
  final String text;
  final List<Citation> citations;
  final DateTime createdAt;

  const QAMessage({
    required this.id,
    required this.threadId,
    required this.role,
    required this.text,
    this.citations = const [],
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'threadId': threadId,
        'role': role.name,
        'text': text,
        'citationsJson': jsonEncode(citations.map((c) => c.toJson()).toList()),
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory QAMessage.fromMap(Map<String, dynamic> m) => QAMessage(
        id: m['id'] as String,
        threadId: m['threadId'] as String,
        role: QARole.values
            .firstWhere((r) => r.name == m['role'], orElse: () => QARole.user),
        text: m['text'] as String,
        citations:
            ((jsonDecode((m['citationsJson'] as String?) ?? '[]')) as List)
                .map((e) => Citation.fromJson(e as Map<String, dynamic>))
                .toList(),
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
      );
}
