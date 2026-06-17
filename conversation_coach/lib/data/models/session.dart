/// Lifecycle of a session as it moves through the analysis pipeline
/// (Technical Spec §6.1 stages).
enum SessionStatus {
  recording,
  recorded,
  transcribing,
  analyzing,
  ready,
  failed,
}

extension SessionStatusX on SessionStatus {
  String get label {
    switch (this) {
      case SessionStatus.recording:
        return 'Recording';
      case SessionStatus.recorded:
        return 'Recorded';
      case SessionStatus.transcribing:
        return 'Transcribing';
      case SessionStatus.analyzing:
        return 'Analyzing';
      case SessionStatus.ready:
        return 'Ready';
      case SessionStatus.failed:
        return 'Failed';
    }
  }

  bool get isBusy =>
      this == SessionStatus.transcribing || this == SessionStatus.analyzing;
}

/// Session(id, userId, title, createdAt, durationSec, language, goalId,
///         consentRecorded, providerConfigSnapshot, status) — Tech Spec §7.
class Session {
  final String id;
  final String userId;
  String title;
  final DateTime createdAt;
  int durationSec;
  String language;
  final String goalId;

  /// Free-text context the user adds in the goal picker ("who & why").
  final String context;
  bool consentRecorded;

  /// A human-readable snapshot of the provider+model used for analysis, so the
  /// report can show "Analyzed with Claude (claude-opus-4-8)" (F-MOD-01).
  String providerConfigSnapshot;
  SessionStatus status;

  Session({
    required this.id,
    required this.userId,
    required this.title,
    required this.createdAt,
    required this.durationSec,
    required this.language,
    required this.goalId,
    this.context = '',
    this.consentRecorded = false,
    this.providerConfigSnapshot = '',
    this.status = SessionStatus.recording,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'userId': userId,
        'title': title,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'durationSec': durationSec,
        'language': language,
        'goalId': goalId,
        'context': context,
        'consentRecorded': consentRecorded ? 1 : 0,
        'providerConfigSnapshot': providerConfigSnapshot,
        'status': status.name,
      };

  factory Session.fromMap(Map<String, dynamic> m) => Session(
        id: m['id'] as String,
        userId: m['userId'] as String,
        title: m['title'] as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
        durationSec: m['durationSec'] as int,
        language: m['language'] as String,
        goalId: m['goalId'] as String,
        context: (m['context'] as String?) ?? '',
        consentRecorded: (m['consentRecorded'] as int) == 1,
        providerConfigSnapshot:
            (m['providerConfigSnapshot'] as String?) ?? '',
        status: SessionStatus.values.firstWhere(
          (s) => s.name == m['status'],
          orElse: () => SessionStatus.recorded,
        ),
      );
}
