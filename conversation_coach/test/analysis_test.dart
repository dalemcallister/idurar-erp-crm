import 'package:conversation_coach/analysis/qa_service.dart';
import 'package:conversation_coach/audio/feature_extractor.dart';
import 'package:conversation_coach/data/models/segment.dart';
import 'package:conversation_coach/data/models/speaker.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the pure-Dart analysis logic that doesn't need a device:
/// dynamics extraction (F-ANA-04) and the local Q&A retriever (Tech Spec §6.4).
void main() {
  Segment seg(String id, String spk, int start, int end, String text) =>
      Segment(
        id: id,
        sessionId: 's',
        speakerId: spk,
        startMs: start,
        endMs: end,
        text: text,
      );

  group('FeatureExtractor.computeDynamics', () {
    test('computes talk-time ratio, questions and interruptions', () {
      final speakers = {
        'u': Speaker(id: 'u', sessionId: 's', label: 'You', isUser: true),
        'o': Speaker(id: 'o', sessionId: 's', label: 'Them', isUser: false),
      };
      final segments = [
        seg('1', 'u', 0, 4000, 'What are you hoping to achieve?'),
        seg('2', 'o', 4200, 6000, 'We want faster reporting.'),
        // Interruption: starts before the previous turn ends.
        seg('3', 'u', 5800, 9000, 'Right, and um what is the budget?'),
        seg('4', 'o', 9500, 11000, 'Around fifty thousand.'),
      ];

      final d = FeatureExtractor().computeDynamics(segments, speakers);

      expect(d.questionCount, 2);
      expect(d.interruptions, 1);
      expect(d.talkTimeRatio.length, 2);
      // User spoke 4000 + 3200 = 7200ms of 10000ms total.
      expect(d.talkTimeRatio['u']! > 0.6, isTrue);
      expect(d.fillerWordRate > 0, isTrue); // "um"
    });

    test('handles an empty transcript safely', () {
      final d = FeatureExtractor().computeDynamics([], {});
      expect(d.questionCount, 0);
      expect(d.talkTimeRatio, isEmpty);
    });
  });

  group('QAService retrieval', () {
    test('embed + cosine retrieves the most relevant segment', () {
      final segments = [
        seg('1', 'u', 0, 3000, 'Lovely weather we are having today.'),
        seg('2', 'o', 3000, 6000,
            'The budget is around fifty thousand dollars for this.'),
        seg('3', 'u', 6000, 9000, 'Great, thanks for your time.'),
      ];
      for (final s in segments) {
        s.embedding = QAService.embed(s.text);
      }
      final hits = QAService.retrieve('what was the budget?', segments, k: 1);
      expect(hits, isNotEmpty);
      expect(hits.first.id, '2');
    });

    test('returns nothing for an unrelated question', () {
      final segments = [
        seg('1', 'u', 0, 3000, 'Lovely weather today.'),
      ];
      for (final s in segments) {
        s.embedding = QAService.embed(s.text);
      }
      final hits = QAService.retrieve('quantum chromodynamics', segments);
      expect(hits, isEmpty);
    });
  });
}
