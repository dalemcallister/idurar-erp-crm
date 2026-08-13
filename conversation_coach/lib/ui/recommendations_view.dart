import 'package:flutter/material.dart';

import '../data/models/recommendation.dart';
import '../data/models/segment.dart';

/// Recommendations (Design §6.6) — 3–5 specific, prioritised, constructive
/// recommendations, each tied to evidence (timestamp + quoted snippet) and the
/// goal, with an optional "what to try instead" rephrasing (F-REC-01/02).
class RecommendationsView extends StatelessWidget {
  final List<Recommendation> recommendations;
  final List<Segment> segments;
  final void Function(int ms) onPlay;

  const RecommendationsView({
    super.key,
    required this.recommendations,
    required this.segments,
    required this.onPlay,
  });

  Segment? _segment(String id) {
    for (final s in segments) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (recommendations.isEmpty) {
      return const Center(child: Text('No recommendations for this session.'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final rec in recommendations) _RecCard(
          rec: rec,
          evidence: rec.evidenceRefs.map(_segment).whereType<Segment>().toList(),
          onPlay: onPlay,
        ),
      ],
    );
  }
}

class _RecCard extends StatelessWidget {
  final Recommendation rec;
  final List<Segment> evidence;
  final void Function(int ms) onPlay;

  const _RecCard({
    required this.rec,
    required this.evidence,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: scheme.primary,
                  child: Text('${rec.priority}',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(rec.text,
                      style: const TextStyle(
                          fontWeight: FontWeight.w500, height: 1.3)),
                ),
              ],
            ),
            if (rec.whatToTryInstead != null &&
                rec.whatToTryInstead!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3F1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.lightbulb_outline,
                          size: 16, color: scheme.primary),
                      const SizedBox(width: 6),
                      const Text('What to try instead',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                    ]),
                    const SizedBox(height: 6),
                    Text('“${rec.whatToTryInstead!}”',
                        style: const TextStyle(fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
            ],
            if (evidence.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Evidence',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 6),
              for (final seg in evidence)
                InkWell(
                  onTap: () => onPlay(seg.startMs),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.play_circle_outline,
                            size: 16, color: scheme.primary),
                        const SizedBox(width: 6),
                        Text(seg.timestampLabel(),
                            style: TextStyle(
                                color: scheme.primary, fontSize: 12)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('“${seg.text}”',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
