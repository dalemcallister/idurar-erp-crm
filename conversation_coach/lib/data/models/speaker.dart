/// Speaker(id, sessionId, label, isUser) — Tech Spec §7.
///
/// Speakers can be renamed by the user (F-TRA-05).
class Speaker {
  final String id;
  final String sessionId;
  String label;
  bool isUser;

  Speaker({
    required this.id,
    required this.sessionId,
    required this.label,
    required this.isUser,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'sessionId': sessionId,
        'label': label,
        'isUser': isUser ? 1 : 0,
      };

  factory Speaker.fromMap(Map<String, dynamic> m) => Speaker(
        id: m['id'] as String,
        sessionId: m['sessionId'] as String,
        label: m['label'] as String,
        isUser: (m['isUser'] as int) == 1,
      );
}
