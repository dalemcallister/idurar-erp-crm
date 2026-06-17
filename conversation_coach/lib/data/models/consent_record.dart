/// How consent was captured for a session.
enum ConsentMethod { self, inAudio }

/// ConsentRecord(id, sessionId, method[self|in-audio], jurisdictionNote,
///               timestamp) — Tech Spec §7.
///
/// F-CON-02 records a consent acknowledgement against the session; F-CON-04
/// surfaces a jurisdiction note (guidance, not legal advice).
class ConsentRecord {
  final String id;
  final String sessionId;
  final ConsentMethod method;
  final String jurisdictionNote;
  final DateTime timestamp;

  const ConsentRecord({
    required this.id,
    required this.sessionId,
    required this.method,
    required this.jurisdictionNote,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'sessionId': sessionId,
        'method': method.name,
        'jurisdictionNote': jurisdictionNote,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };

  factory ConsentRecord.fromMap(Map<String, dynamic> m) => ConsentRecord(
        id: m['id'] as String,
        sessionId: m['sessionId'] as String,
        method: ConsentMethod.values.firstWhere(
            (x) => x.name == m['method'],
            orElse: () => ConsentMethod.self),
        jurisdictionNote: (m['jurisdictionNote'] as String?) ?? '',
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(m['timestamp'] as int),
      );
}
