import 'dart:convert';

/// Segment(id, sessionId, speakerId, startMs, endMs, text,
///         textEmotion, intentTag, prosodyFeaturesJson, embeddingRef) — §7.
///
/// One turn / utterance. The transcript view renders these in order; the Q&A
/// retrieval grounds answers in them and cites their timestamps (F-QA-02).
class Segment {
  final String id;
  final String sessionId;
  String speakerId;
  final int startMs;
  final int endMs;
  String text;

  /// Per-turn text-derived emotion label (F-ANA-03), e.g. "neutral", "tense".
  String? textEmotion;

  /// Intent classification of the turn (F-ANA-02), e.g. "probing",
  /// "objecting", "buying_signal".
  String? intentTag;

  /// Prosodic features computed on-device from the full-quality waveform
  /// (Tech Spec §6.3): pace, energy, pauses. Numeric context for the model.
  Map<String, dynamic> prosodyFeatures;

  /// Lightweight lexical vector used by the local Q&A retriever
  /// (Tech Spec §6.4). Stored as a sparse term→weight map.
  Map<String, double>? embedding;

  Segment({
    required this.id,
    required this.sessionId,
    required this.speakerId,
    required this.startMs,
    required this.endMs,
    required this.text,
    this.textEmotion,
    this.intentTag,
    this.prosodyFeatures = const {},
    this.embedding,
  });

  String timestampLabel() {
    final s = startMs ~/ 1000;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'sessionId': sessionId,
        'speakerId': speakerId,
        'startMs': startMs,
        'endMs': endMs,
        'text': text,
        'textEmotion': textEmotion,
        'intentTag': intentTag,
        'prosodyFeaturesJson': jsonEncode(prosodyFeatures),
        'embeddingRef': embedding == null ? null : jsonEncode(embedding),
      };

  factory Segment.fromMap(Map<String, dynamic> m) => Segment(
        id: m['id'] as String,
        sessionId: m['sessionId'] as String,
        speakerId: m['speakerId'] as String,
        startMs: m['startMs'] as int,
        endMs: m['endMs'] as int,
        text: m['text'] as String,
        textEmotion: m['textEmotion'] as String?,
        intentTag: m['intentTag'] as String?,
        prosodyFeatures: m['prosodyFeaturesJson'] == null
            ? {}
            : jsonDecode(m['prosodyFeaturesJson'] as String)
                as Map<String, dynamic>,
        embedding: m['embeddingRef'] == null
            ? null
            : (jsonDecode(m['embeddingRef'] as String) as Map<String, dynamic>)
                .map((k, v) => MapEntry(k, (v as num).toDouble())),
      );
}
