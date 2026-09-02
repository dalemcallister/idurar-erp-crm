import '../core/local_models.dart';
import 'transcription_engine.dart';

/// On-device transcription engine (v2) — Whisper via whisper.cpp through
/// [LocalModels]. Audio never leaves the device, and there is no upload-size
/// limit (the whole recording is transcribed locally, however long it is).
class LocalWhisperEngine implements TranscriptionEngine {
  @override
  String get id => 'local-whisper';

  @override
  String get displayName => 'On-device Whisper (private)';

  @override
  bool get sendsAudioToCloud => false;

  @override
  Future<TranscriptionResult> transcribe({
    required String audioPath,
    required List<String> languages,
    int channels = 1,
  }) {
    return LocalModels.instance
        .transcribeFile(audioPath: audioPath, languages: languages);
  }
}
