/// A timestamped, speaker-tagged utterance produced by transcription.
class TranscriptTurn {
  final int startMs;
  final int endMs;

  /// A stable per-recording speaker tag (e.g. "S1", or a channel label when
  /// hardware diarization is available). Mapped to a [Speaker] downstream.
  final String speakerTag;
  final String text;

  const TranscriptTurn({
    required this.startMs,
    required this.endMs,
    required this.speakerTag,
    required this.text,
  });
}

class TranscriptionResult {
  final List<TranscriptTurn> turns;
  final String language;

  const TranscriptionResult({required this.turns, required this.language});
}

/// Pluggable transcription engine (Tech Spec §6.2). Phase 1 ships a cloud
/// adapter (opt-in to send audio) and an offline demo engine; phase 3 adds an
/// on-device Whisper-class engine behind the same interface.
abstract class TranscriptionEngine {
  String get id;
  String get displayName;

  /// Whether audio leaves the device (drives the consent/opt-in copy).
  bool get sendsAudioToCloud;

  Future<TranscriptionResult> transcribe({
    required String audioPath,
    required List<String> languages,
    int channels = 1,
  });
}
