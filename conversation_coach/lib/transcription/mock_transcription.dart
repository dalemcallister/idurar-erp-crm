import 'dart:io';

import 'transcription_engine.dart';

/// Offline demo transcription. On-device ASR (Whisper-class) is a phase-3
/// deliverable, and cloud ASR requires an opt-in and a configured provider.
/// Until then this engine yields a realistic, fully on-device sample transcript
/// so the analysis loop (transcribe → analyse → ask) runs end-to-end without
/// sending any audio anywhere.
///
/// It derives the turn timings from the actual recording length so the
/// timeline, talk-time and citations line up with the audio the user captured.
class MockTranscriptionEngine implements TranscriptionEngine {
  @override
  String get id => 'demo-asr';

  @override
  String get displayName => 'Built-in demo transcript (offline)';

  @override
  bool get sendsAudioToCloud => false;

  @override
  Future<TranscriptionResult> transcribe({
    required String audioPath,
    required List<String> languages,
    int channels = 1,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));

    // A discovery-call style sample with a clear buying signal and an
    // interruption, so every part of the report has something to show.
    final script = <_T>[
      _T('S1', "Thanks for making the time today — I'd love to understand what you're hoping to get out of a tool like this."),
      _T('S2', "Sure. Honestly our team is drowning in manual reporting and it's eating our week."),
      _T('S1', "That makes sense. When you say it eats the week, roughly how many hours are we talking?"),
      _T('S2', "Maybe two full days across the team. It's a real problem."),
      _T('S1', "Got it. And what does success look like six months from now?"),
      _T('S2', "We'd want that down to an afternoon, and I need to know the budget works — what does pricing look like?"),
      _T('S1', "Great question, let me come back to pricing in a moment. First, who else is involved in the decision?"),
      _T('S2', "It's me and our head of ops. She'll care about the timeline — when can you have us live?"),
      _T('S1', "We can usually onboard within two weeks. I'll put together a plan that covers pricing and the rollout timeline."),
      _T('S2', "Perfect, that sounds good. Send it over and I'll loop her in."),
    ];

    // Spread turns across the recorded duration (fallback to ~3s each).
    final durationMs = await _estimateDurationMs(audioPath, script.length);
    final perTurn = (durationMs / script.length).floor().clamp(1500, 8000);
    final turns = <TranscriptTurn>[];
    var t = 0;
    for (final line in script) {
      final len = (perTurn * (0.7 + line.text.length / 160)).round();
      turns.add(TranscriptTurn(
        startMs: t,
        endMs: t + len,
        speakerTag: line.speaker,
        text: line.text,
      ));
      t += len;
    }

    return TranscriptionResult(
      turns: turns,
      language: languages.isEmpty ? 'en' : languages.first,
    );
  }

  Future<int> _estimateDurationMs(String path, int turns) async {
    try {
      final f = File(path);
      if (await f.exists()) {
        final bytes = await f.length();
        // Rough: 48kHz * 2 bytes * 1ch ≈ 96 KB/s. Clamp to a sane window.
        final ms = (bytes / 96).round();
        if (ms > 5000) return ms.clamp(5000, 1800000);
      }
    } catch (_) {}
    return turns * 3000;
  }
}

class _T {
  final String speaker;
  final String text;
  _T(this.speaker, this.text);
}
