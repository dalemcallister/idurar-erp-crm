import '../data/models/analysis.dart';
import '../data/models/segment.dart';
import '../data/models/speaker.dart';

/// Derives conversation dynamics (F-ANA-04) and lightweight prosody features
/// (Tech Spec §6.3) from segment timestamps and text. On device these prosodic
/// features would be computed from the full-quality USB-C waveform; here they
/// are derived from timing/text so the values are real and consistent, and fed
/// to the model as numeric context rather than asking it to "hear" emotion.
class FeatureExtractor {
  static const _fillers = {
    'um', 'uh', 'er', 'ah', 'like', 'you know', 'basically', 'actually',
    'sort of', 'kind of', 'i mean',
  };

  /// Computes session-level dynamics from ordered segments.
  Dynamics computeDynamics(
      List<Segment> segments, Map<String, Speaker> speakers) {
    if (segments.isEmpty) return const Dynamics();

    final talkMs = <String, int>{};
    var interruptions = 0;
    var longestMonologue = 0;
    var questionCount = 0;
    var totalWords = 0;
    var fillerCount = 0;
    final latencies = <int>[];

    String? runSpeaker;
    var runStart = 0;

    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      final dur = (s.endMs - s.startMs).clamp(0, 1 << 31);
      talkMs[s.speakerId] = (talkMs[s.speakerId] ?? 0) + dur;

      final words = s.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
      totalWords += words.length;
      final lower = s.text.toLowerCase();
      for (final f in _fillers) {
        fillerCount += _countOccurrences(lower, f);
      }
      if (s.text.contains('?')) questionCount++;

      // Monologue run tracking.
      if (runSpeaker == s.speakerId) {
        // continue run
      } else {
        if (runSpeaker != null) {
          final runLen = s.startMs - runStart;
          if (runLen > longestMonologue) longestMonologue = runLen;
        }
        runSpeaker = s.speakerId;
        runStart = s.startMs;
      }

      // Response latency & interruption against the previous turn.
      if (i > 0) {
        final prev = segments[i - 1];
        final gap = s.startMs - prev.endMs;
        if (prev.speakerId != s.speakerId) {
          if (gap < 0) {
            interruptions++;
          } else {
            latencies.add(gap);
          }
        }
      }
    }
    // Close the final monologue run.
    final lastRunLen = segments.last.endMs - runStart;
    if (lastRunLen > longestMonologue) longestMonologue = lastRunLen;

    final totalTalk = talkMs.values.fold<int>(0, (a, b) => a + b);
    final ratios = <String, double>{};
    if (totalTalk > 0) {
      talkMs.forEach((k, v) => ratios[k] = v / totalTalk);
    }

    final avgLatency = latencies.isEmpty
        ? 0.0
        : latencies.reduce((a, b) => a + b) / latencies.length;

    return Dynamics(
      talkTimeRatio: ratios,
      interruptions: interruptions,
      longestMonologueMs: longestMonologue,
      questionCount: questionCount,
      fillerWordRate:
          totalWords == 0 ? 0 : (fillerCount / totalWords) * 100,
      avgResponseLatencyMs: avgLatency,
    );
  }

  /// Per-segment prosody features (pace, energy proxy, pause-after) attached to
  /// each segment for the model and the timeline.
  Map<String, dynamic> prosodyFor(Segment s, Segment? next) {
    final words = s.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final durSec = ((s.endMs - s.startMs) / 1000).clamp(0.1, 600);
    final wpm = words / durSec * 60;
    final pauseAfterMs = next == null ? 0 : (next.startMs - s.endMs).clamp(0, 1 << 31);
    return {
      'wordsPerMinute': double.parse(wpm.toStringAsFixed(1)),
      'wordCount': words,
      'pauseAfterMs': pauseAfterMs,
      // Energy proxy from words-per-minute until real audio energy is wired in.
      'energy': (wpm / 180).clamp(0.0, 1.0),
    };
  }

  int _countOccurrences(String haystack, String needle) {
    if (needle.isEmpty) return 0;
    var count = 0;
    var idx = haystack.indexOf(needle);
    while (idx != -1) {
      count++;
      idx = haystack.indexOf(needle, idx + needle.length);
    }
    return count;
  }
}
