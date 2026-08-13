import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../data/models/recording.dart';
import '../data/models/segment.dart';
import '../data/models/session.dart';
import '../data/models/speaker.dart';

/// Transcript (Design §6.4) — speaker-labelled and timestamped. Tap a line to
/// play that audio segment; sentiment shows subtly in the margin. The user can
/// correct text and rename speakers (F-TRA-05). Marked moments are flagged.
class TranscriptView extends StatefulWidget {
  final Session session;
  final List<Segment> segments;
  final Map<String, Speaker> speakers;
  final Recording? recording;
  final void Function(int ms) onPlay;
  final Future<void> Function() onChanged;

  const TranscriptView({
    super.key,
    required this.session,
    required this.segments,
    required this.speakers,
    required this.recording,
    required this.onPlay,
    required this.onChanged,
  });

  @override
  State<TranscriptView> createState() => _TranscriptViewState();
}

class _TranscriptViewState extends State<TranscriptView> {
  @override
  Widget build(BuildContext context) {
    final marks = widget.recording?.markedMomentsMs ?? const [];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            const Icon(Icons.people_alt_outlined, size: 18),
            const SizedBox(width: 8),
            const Text('Speakers',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('${widget.segments.length} turns',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final sp in widget.speakers.values)
              ActionChip(
                avatar: Icon(
                    sp.isUser ? Icons.person : Icons.person_outline,
                    size: 16),
                label: Text(sp.label),
                onPressed: () => _renameSpeaker(sp),
              ),
          ],
        ),
        const Divider(height: 24),
        for (final seg in widget.segments)
          _SegmentTile(
            segment: seg,
            speaker: widget.speakers[seg.speakerId],
            isMarked: marks.any((m) => (m - seg.startMs).abs() < 1500),
            onPlay: () => widget.onPlay(seg.startMs),
            onEdit: () => _editSegment(seg),
          ),
      ],
    );
  }

  Future<void> _renameSpeaker(Speaker sp) async {
    final controller = TextEditingController(text: sp.label);
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename speaker'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty) {
      sp.label = newName;
      await context.read<AppState>().repo.upsertSpeaker(sp);
      await widget.onChanged();
    }
  }

  Future<void> _editSegment(Segment seg) async {
    final controller = TextEditingController(text: seg.text);
    final newText = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Correct transcript'),
        content: TextField(
            controller: controller, autofocus: true, maxLines: null),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (newText != null && newText.isNotEmpty && newText != seg.text) {
      seg.text = newText;
      await context.read<AppState>().repo.upsertSegment(seg);
      await widget.onChanged();
    }
  }
}

class _SegmentTile extends StatelessWidget {
  final Segment segment;
  final Speaker? speaker;
  final bool isMarked;
  final VoidCallback onPlay;
  final VoidCallback onEdit;

  const _SegmentTile({
    required this.segment,
    required this.speaker,
    required this.isMarked,
    required this.onPlay,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = speaker?.isUser ?? false;
    final emotion = segment.textEmotion;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Margin: timestamp (tap to play) + subtle sentiment marker.
          GestureDetector(
            onTap: onPlay,
            child: Column(
              children: [
                Text(segment.timestampLabel(),
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.primary,
                        fontFeatures: const [])),
                const SizedBox(height: 2),
                Icon(Icons.play_circle_outline,
                    size: 16, color: Theme.of(context).colorScheme.primary),
                if (emotion != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _emotionColor(emotion),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFFEAF3F1) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(speaker?.label ?? 'Speaker',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      if (isMarked) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.flag, size: 14, color: Color(0xFFB8860B)),
                      ],
                      const Spacer(),
                      if (segment.intentTag != null)
                        Text(segment.intentTag!,
                            style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                      InkWell(
                        onTap: onEdit,
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(Icons.edit_outlined, size: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(segment.text),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _emotionColor(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'positive':
        return const Color(0xFF2E7D5B);
      case 'tense':
      case 'negative':
        return const Color(0xFFB44A3F);
      default:
        return Colors.grey;
    }
  }
}
